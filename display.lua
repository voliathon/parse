--[[
    Copyright (c) 2016-2023, Flippant
    Copyright (c) 2025, Voliathon
    All rights reserved.

    This source code is licensed under the BSD-style license found in the
    LICENSE.md file in the root directory of this source tree.
]]

---
-- Initializes all text boxes defined in the settings file.
--
function init_boxes()
	for box,__ in pairs(settings.display) do
		create_text(box)
	end
end

---
-- Creates a single new text box object based on its name.
-- @param stat_type {string} The name of the display box (e.g., 'melee', 'defense').
--
function create_text(stat_type)
	local t_settings = settings.display[stat_type]

    -- Create a new text object using the settings
    text_box[stat_type] = texts.new(t_settings)
	text_box[stat_type]:hide() -- Hide it by default
	update_text(stat_type) -- Populate it with initial data (or "No data")
end

---
-- The main update function for a single display box.
-- Gathers all data, sorts players, and formats the text.
-- (This function is now optimized to loop the database only once).
-- @param stat_type {string} The name of the display box to update.
--
function update_text(stat_type)    
	-- Don't update if box doesn't exist, has no settings, is hidden, or player is not logged in.
	if not text_box[stat_type] or not settings.display[stat_type] or not settings.display[stat_type].visible or not windower.ffxi.get_info().logged_in then
		return
	end

	-- info: Holds the final formatted string for each player
    -- head: Holds the header lines (title, filters, stats)
    -- to_be_sorted: A temporary table {player_name = sort_value} used for sorting
    -- sorted_players: The final list of player names in the correct order
	local info = {}
	local head = L{}
	local to_be_sorted = {}
	local sorted_players = L{}
	
	-- === 1. Prepare Data (THE OPTIMIZATION) ===
	-- Call collapse_mobs() ONCE. This loops the main database and returns a
	-- simple, player-centric table. This is fast.
	local collapsed_db = collapse_mobs()
	
	-- Get the total parse damage ONCE from the new collapsed table.
	local total_parse_damage = get_total_parse_damage(collapsed_db)
	
	-- Determine what to sort by, based on the box's 'type' in settings
	local sort_type
	if settings.display[stat_type]["type"] == "offense" then 
		sort_type = "damage" 
	else 
		sort_type = "defense" 
	end

	-- === 2. Gather and Pre-Sort Data ===
	-- Loop the *collapsed database* (which is small), NOT the main database.
	if collapsed_db then
		for player_name, player_data in pairs(collapsed_db) do		
			-- Get the sort value for this player
			if sort_type == "damage" then
				to_be_sorted[player_name] = player_data.total_damage or 0
			else -- defense
				to_be_sorted[player_name] = fast_get_tally(player_data, 'parry') + fast_get_tally(player_data, 'hit') + fast_get_tally(player_data, 'evade')
			end
			
			-- Start the player's line with their formatted name
			info[player_name] = '\\cs('..label_colors('player')..')'..string.format('%-13s',player_name..' ')..'\\cr' 
			
			-- Iterate over each stat this box is configured to show
			for stat in settings.display[stat_type].order:it() do 
				if settings.display[stat_type].data_types[stat] then					
					local d = {} -- Holds the data for this single stat
					
					-- Iterate over the data types for that stat (e.g., 'total', 'avg', 'percent')
					for report_type,__ in pairs(settings.display[stat_type].data_types[stat]) do
						-- === Call the NEW FAST functions ===
						-- These functions just read from player_data, they DO NOT loop the database.
						if report_type=="total" then
							local total = player_data.total_damage or 0
							d[report_type] = total
						elseif report_type=="total-percent" then
							d[report_type] = fast_get_percent(player_data, stat, total_parse_damage) or "--"
						elseif report_type=="avg" then
							d[report_type] = fast_get_avg(player_data, stat) or "--" 
						elseif report_type=="percent" then
							d[report_type] = fast_get_percent(player_data, stat, total_parse_damage) or "--"
						elseif report_type=="tally" then
							d[report_type] = fast_get_tally(player_data, stat) or "--"
						elseif report_type=="damage" then
							d[report_type] = fast_get_damage(player_data, stat) or "--"
						else
							d[report_type] = "--"
						end											
					end
					-- Format and append the data for this stat
					info[player_name] = info[player_name] .. (format_display_data(d))	
				end
			end
		end
	end
	
	-- === 3. Sort Players ===
    -- This is a simple N-pass selection sort to get the top 'max' players
	for i=1,settings.display[stat_type].max,+1 do
		p_name = nil
		top_result = 0
		for player_name,sort_num in pairs(to_be_sorted) do
            -- Find the player with the highest sort_num who isn't already in the sorted list
			if sort_num > top_result and not sorted_players:contains('${'..player_name..'}') then
				top_result = sort_num
				p_name = player_name					
			end						
		end	
        -- Add the top player found in this pass to the list
		if p_name then sorted_players:append('${'..p_name..'}') end		
	end

	-- === 4. Assemble Header ===
    -- Add the title, filters, and pause status
	head:append('[ ${title} ] ${filters} ${pause}')
	info['title'] = stat_type -- The text object will replace ${title} with this

	info['filters'] = update_filters() -- Add filter string
	
	if pause then
		info['pause'] = "- PARSE PAUSED -" -- Add pause status
	end

    -- Add the stat column headers (e.g., "  damage   melee    ws  ")
	head:append('${header}')
	info['header'] = format_display_head(stat_type)

	if sorted_players:length() == 0 then
		head:append('No data found')
	end
	
	-- === 5. Update the Text Box Object ===
	if text_box[stat_type] then
		text_box[stat_type]:clear() -- Clear all existing text
		text_box[stat_type]:append(head:concat('\n')) -- Add the header lines
		text_box[stat_type]:append('\n') -- Add a blank line
		text_box[stat_type]:append(sorted_players:concat('\n')) -- Add the list of sorted player names
		text_box[stat_type]:update(info) -- Pass the 'info' table to resolve all variables (e.t., ${title}, ${player_name})
		
		if settings.display[stat_type].visible then
			text_box[stat_type]:show() -- Ensure it's visible
		end
	end
end

---
-- Formats the header row (the stat names) with correct spacing.
-- @param box_name {string} The name of the display box.
-- @return {string} A formatted string of stat names.
--
function format_display_head(box_name)
	local text = string.format('%-13s',' ') -- Initial padding to align with player names
	for stat in settings.display[box_name].order:it() do
		if settings.display[box_name].data_types[stat] then
			local characters = 0
            -- Calculate the width of the column based on the data types it will show
			for i,v in pairs(settings.display[box_name].data_types[stat]) do
				characters = characters + 7
				if i=='total' then characters = characters + 1 end -- 'total' is a bit wider
			end
            -- Create the formatted, fixed-width stat name
			text = text .. '\\cs('..label_colors('stat')..')' .. string.format('%-'..characters..'s',stat) .. '\\cr'
		end
	end
	return text
end

---
-- Helper function to get the RGB color string for labels from settings.
-- @param label {string} The label type ('player' or 'stat').
-- @return {string} A string formatted as "r,g,b".
--
function label_colors(label)
	local r, b, g = 255, 255, 255
	
	if settings.label[label] then
		r = settings.label[label].red or 255
		b = settings.label[label].blue or 255
		g = settings.label[label].green or 255
	end
	
	return tostring(r)..','..tostring(g)..','..tostring(b)
end

---
-- Formats the data for a single stat into a fixed-width string.
-- The order of 'if' statements determines the column order.
-- @param data {table} A table of data, e.g., {total=1000, "total-percent"=10.5}.
-- @return {string} The formatted string for that stat.
--
function format_display_data(data)
	line = ""
	
	if data["total-percent"] then
		line = line .. string.format('%-7s',data["total-percent"] .. '% ')
	end
	
	if data["percent"] then
		line = line .. string.format('%-7s',data["percent"] .. '% ')
	end
	
	if data["total"] then
		line = line .. string.format('%-8s',data["total"] .. ' ')
	end

	if data["avg"] then
		line = line .. string.format('%-7s','~' .. data["avg"] .. ' ')
	end

	if data["tally"] then
		if data["damage"] then
			line = line .. string.format('%-7s',data["damage"] ..' ')
		end
		line = line .. string.format('%-7s','#' .. data["tally"])
	elseif data["damage"] then
		line = line .. string.format('%-7s',data["damage"])
	end
	
	return line
end

---
-- A global refresh function that calls update_text() on all active boxes.
-- This is looped by the main parse.lua 'config.register' callback.
--
function update_texts()
	for v,__ in pairs(text_box) do
		update_text(v)
	end
end

---
-- Gets a string representation of the currently active filters.
-- This is used by update_text() to display filter status in the box header.
-- @return {string} The filter status string.
--
function update_filters()
	local text = ""
	if filters['mob'] and filters['mob']:tostring()~="{}" then
		text = text .. ('Monsters: ' .. filters['mob']:tostring())
	end
	if filters['player'] and filters['player']:tostring()~="{}" then
		text = text .. ('\nPlayers: ' .. filters['player']:tostring())
	end
	return text
end
