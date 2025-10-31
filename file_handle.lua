--[[
    Copyright (c) 2016-2023, Flippant
    Copyright (c) 2025, Voliathon
    All rights reserved.

    This source code is licensed under the BSD-style license found in the
    LICENSE.md file in the root directory of this source tree.
]]

-- Import required Windower libraries for file and XML handling
files = require('files')
xml = require('xml')

---
-- Imports a parse database from an XML file.
-- @param file_name {string} The name of the file in the /data/export/ folder.
--
function import_parse(file_name)   
	local path = '/data/export/'..file_name
	
    -- Create a new file object for the XML
	import = files.new(path..'.xml', true)
    -- Read and parse the XML file
	parsed, err = xml.read(import)
	
	if not parsed then
		message(err or 'XML error: Unknown error.')
		return
	end
	
    -- Reconstruct the database table structure from the parsed XML
	imported_database = construct_database(parsed)	
    -- Merge the imported data into the current in-memory database
	merge_tables(database,imported_database)
	
	-- Backwards compatibility: Add 'nonblock' data for older parse versions
	for mob,players in pairs(database) do
		for player,player_table in pairs(players) do
			if player_table['defense'] and player_table['defense']['block'] and not player_table['defense']['nonblock'] then
				player_table['defense']['nonblock'] = player_table['defense']['hit']
			end
		end
	end
	
	-- Backwards compatibility: Add 'total_damage' for older parse versions
	for mob,players in pairs(database) do
		for player,player_table in pairs(players) do
			if not player_table.total_damage then
                -- Manually calculate total damage if it's missing
				player_table.total_damage = find_total_damage(player,mob)
			end
		end
	end

	message('Parse ['..file_name..'] was imported to database!')
end

---
-- Exports the current parse database to an XML file.
-- @param file_name {string} (Optional) The name to save the file as.
--
function export_parse(file_name)   	
    -- Ensure the /data/ and /data/export/ directories exist
    if not windower.dir_exists(windower.addon_path..'data') then
        windower.create_dir(windower.addon_path..'data')
    end
	if not windower.dir_exists(windower.addon_path..'data/export') then
        windower.create_dir(windower.addon_path..'data/export')
    end
	
	local path = windower.addon_path..'data/export/'
	if file_name then
        -- Use user-provided name
		path = path..file_name
	else
        -- Use a timestamped default name
		path = path..os.date(' %H %M %S%p  %y-%d-%m')
	end
	
    -- If file already exists, append a timestamp to prevent overwriting
	if windower.file_exists(path..'.xml') then
		path = path..'_'..os.clock()
	end
	
    -- Open the file for writing
	local f = io.open(path..'.xml','w+')
	f:write('<database>\n') -- Write the root XML tag

	-- Iterate over all mobs in the database
	for mob,data in pairs(database) do		
		if check_filters('mob',mob) then -- Only export mobs that pass the filters
			f:write('    <'..mob..'>\n') -- Write the <MobName> tag
			f:write(to_xml(data,'        ')) -- Recursively convert this mob's data to XML
			f:write('    </'..mob..'>\n') -- Close the <MobName> tag
		end		
	end
	
	f:write('</database>') -- Close the root tag
	f:close()
	
	message('Database was exported to '..path..'.xml!')
	if get_filters()~="" then
		message('Note that the database was filtered by [ '..get_filters()..' ]')
	end
end

---
-- Recursively converts a Lua table into an XML string.
-- @param t {table} The table to convert.
-- @param indent_string {string} The string to use for indentation.
-- @return {string} The resulting XML string.
--
function to_xml(t,indent_string)
	local indent = indent_string or '    '
	local xml_string = ""
	for key,value in pairs(t) do
		key = tostring(key)
        -- Sanitize key (replace spaces with underscores) and write the opening tag
		xml_string = xml_string .. indent .. '<'..key:gsub(" ","_")..'>'		
		if type(value)=='number' then
            -- If it's a number, write it as the tag's value
			xml_string = xml_string .. value
			xml_string = xml_string .. '</'..key:gsub(" ","_")..'>\n'
		elseif type(value)=='table' then
            -- If it's a table, recurse
			xml_string = xml_string .. '\n' .. to_xml(value,indent..'    ')
			xml_string = xml_string .. indent .. '</'..key:gsub(" ","_")..'>\n'
		end
		
	end
	
	return xml_string
end

---------------------------------------------------------
-- Function credit to the Windower Luacore config library
-- This function reconstructs a Lua table from a parsed XML node.
---------------------------------------------------------
function construct_database(node, settings, key, meta)
    settings = settings or T{}
    key = key or 'settings'
    meta = meta

    local t = T{}
    if node.type ~= 'tag' then
        return t
    end

    if not node.children:all(function(n)
        return n.type == 'tag' or n.type == 'comment'
    end) and not (#node.children == 1 and node.children[1].type == 'text') then
        error('Malformatted settings file.')
        return t
    end

    if #node.children == 1 and node.children[1].type == 'text' then
        -- This is a leaf node (e.g., <tally>10</tally>)
        local val = node.children[1].value
        if node.children[1].cdata then
            --meta.cdata:add(key)
            return val
        end

        if val:lower() == 'false' then
            return false
        elseif val:lower() == 'true' then
            return true
        end
        
        -- Try to convert the value to a number
        local num = tonumber(val)
        if num ~= nil then
            return num
        end

        return val -- Return as string if all else fails
    end

    -- This is a branch node (e.g., <player><melee>...</melee></player>)
    for child in node.children:it() do
        if child.type == 'comment' then
            -- meta.comments[key] = child.value:trim() -- Comment handling (disabled)
        elseif child.type == 'tag' then
            key = child.name
            local childdict
            if table.containskey(settings, key) then
                childdict = table.copy(settings)
            else
                childdict = settings
            end
            -- Recurse to build the child table
            t[child.name] = construct_database(child, childdict, key, meta)
        end
    end

    return t -- Return the constructed sub-table
end

---
-- Logs a single action to a player-specific log file.
-- (Optimized to cache file handles)
-- @param player {string} The name of the player who performed the action.
-- @param mob {string} The name of the mob involved.
-- @param action_type {string} The stat name (e.g., 'ws', 'crit').
-- @param value {number} The damage/healing value.
-- @param spellName {string} (Optional) The name of the ability, if applicable.
--
function log_data(player,mob,action_type,value,spellName)
    if not logging then return end -- Do nothing if logging is globally disabled
    
	local log_name = player..'_'..mob..'_'..action_type
	local file = logs[log_name] -- Check if the file object is already cached
	
	if not file then
		-- File is not cached, so we do the slow I/O checks ONCE
		local log_path = windower.addon_path..'data/log/'..windower.ffxi.get_player().name..'/'
		local file_path = log_path..log_name..'.log'
		
		-- Ensure all directories exist, creating them if necessary
		if not windower.dir_exists(windower.addon_path..'data') then
			windower.create_dir(windower.addon_path..'data')
		end
		if not windower.dir_exists(windower.addon_path..'data/log') then
			windower.create_dir(windower.addon_path..'data/log')
		end
		if not windower.dir_exists(log_path) then
			windower.create_dir(log_path)
		end

		-- Create a file object
		file = files.new(file_path) 
		if not file:exists() then
			file:create()
		end
		
		-- Write the header and cache the file object
		file:append(os.date('======= %H:%M:%S %p  %m-%d-%y =======')..'\n')
		logs[log_name] = file -- Store the file object in our cache
	end
        
    -- Append the action data (fast)
    file:append('%s %s\n':format(spellName or '',value or ''))
end
