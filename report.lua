--[[
    Copyright (c) 2016-2023, Flippant
    Copyright (c) 2025, Voliathon
    All rights reserved.

    This source code is licensed under the BSD-style license found in the
    LICENSE.md file in the root directory of this source tree.
]]

---
-- Main function to generate and output a report to the chat.
-- (This function is now optimized to use "table.concat" for string building)
-- @param stat {string} (Optional) The stat to report. Can also be a chatmode.
-- @param ability {string} (Optional) The specific ability name. Can also be a chatmode or target.
-- @param chatmode {string} (Optional) The chat mode (p, s, l, t, etc.).
-- @param chattarget {string} (Optional) The target for a tell ('t') chatmode.
--
function report_data(stat,ability,chatmode,chattarget)
	local valid_chatmodes = S{'s','p','t','l','l2','echo'}
    
    -- This block intelligently rearranges arguments to handle optional inputs.
	if not stat then
		stat = 'damage' -- Default stat
	elseif valid_chatmodes:contains(stat) then
		chattarget = ability
		chatmode = stat
        ability = nil
		stat = 'damage'
    elseif valid_chatmodes:contains(ability) then
        chattarget = chatmode
        chatmode = ability
        ability = nil
	end

	-- If chatmode is still not valid, default to nil (echo)
	if not valid_chatmodes[chatmode] then
		chatmode = nil
	end
    
    -- Build the chat command prefix
    local chat_prefix
	if chatmode == 't' then
        if chattarget then
        	chat_prefix = chatmode..' '..chattarget
        else 
            message("Chat target not found.") 
            return
        end
	else
		chat_prefix = chatmode
	end

	-- Handle stat aliases
	if S{'acc','accuracy','hitrate'}:contains(stat) then
		stat = 'melee'
	elseif S{'racc'}:contains(stat) then
		stat = 'ranged'
	elseif S{'evasion','eva'}:contains(stat) then
		stat = 'evade'
	end
	
	-- === 1. Prepare Data (THE OPTIMIZATION) ===
	-- Call collapse_mobs() ONCE. This is fast.
	local collapsed_db = collapse_mobs()
	if not collapsed_db then
		message('No data found to report.')
		return
	end
	
	-- Get the total parse damage ONCE. This is fast.
	local total_parse_damage = get_total_parse_damage(collapsed_db)
	
	-- === 2. Sort Players (The FAST way) ===
	local sorted_players = L{}
	local sort_stat = stat
	
	-- Determine the actual stat to sort by
	if S{'multi','1','2','3','4','5','6','7','8'}:contains(sort_stat) then
		sort_stat = 'melee' -- Sort by melee % if multi is requested
	elseif get_stat_type(sort_stat) == 'category' then
		sort_stat = 'avg' -- Sort categories by avg
	elseif S{'melee','ranged','crit','r_crit'}:contains(sort_stat) or get_stat_type(sort_stat)=="defense" then
		sort_stat = 'percent' -- Sort most others by percent
	elseif S{'hit','miss','nonblock','nonparry','r_miss','ws_miss','ja_miss','enfeeb','enfeeb_miss'}:contains(sort_stat) then
		sort_stat = 'tally' -- Sort misses/hits by tally
	end

	-- Create a list of players to be sorted
	local player_list = {}
	for player_name, data in pairs(collapsed_db) do
		-- Get the value to sort by for this player
		local sort_value = 0
		if stat == 'damage' then
			sort_value = data.total_damage or 0
		elseif stat == 'defense' then
			sort_value = fast_get_tally(data, 'parry') + fast_get_tally(data, 'hit') + fast_get_tally(data, 'evade') + fast_get_tally(data, 'block')
		elseif sort_stat == 'avg' then
			sort_value = fast_get_avg(data, stat) or 0
		elseif sort_stat == 'percent' then
			sort_value = fast_get_percent(data, stat, total_parse_damage) or 0
		elseif sort_stat == 'tally' then
			sort_value = fast_get_tally(data, stat) or 0
		end
		
		player_list[#player_list + 1] = { name = player_name, sort_val = sort_value }
	end

	-- Sort the list using table.sort (very fast)
	table.sort(player_list, function(a, b) return a.sort_val > b.sort_val end)

	-- Populate the final sorted list, respecting the 20 player limit
	for i = 1, math.min(#player_list, 20) do
		sorted_players:append(player_list[i].name)
	end
	
	-- === 3. Build the Report String (OPTIMIZATION #3) ===
	-- Instead of one giant string, we build a table of lines.
	local report_lines = {}
	local player_parts = {} -- This table will be our string buffer

	if stat == 'damage' then
        -- Special report for 'damage'
		report_lines[#report_lines + 1] = '[Total damage] '..update_filters()
		for player in sorted_players:it() do
			player_parts = {} -- Reset the buffer for each player
			local player_data = collapsed_db[player]
			local player_damage = player_data.total_damage or 0
			
			player_parts[#player_parts + 1] = player..': '
			player_parts[#player_parts + 1] = fast_get_percent(player_data, stat, total_parse_damage)..'% ('
			player_parts[#player_parts + 1] = player_damage..')'
			
			report_lines[#report_lines + 1] = table.concat(player_parts, '')
		end
        
	elseif get_stat_type(stat)=='category' then		
        -- Report for 'category' stats (ws, ja, spell)
        local header = '[Reporting '..stat..' '
        if ability then header = header .. '('..ability..') ' end
        header = header .. 'stats] '..update_filters()
		report_lines[#report_lines + 1] = header
        
        for player in sorted_players:it() do
			player_parts = {} -- Reset buffer
			local player_data = collapsed_db[player]
			
			-- Get the spell list directly from the player's collapsed data
			local player_spell_list = nil
			if player_data.category and player_data.category[stat] then
				player_spell_list = player_data.category[stat]
			end
			
            if not ability or (ability and player_spell_list and player_spell_list[ability]) then
                player_parts[#player_parts + 1] = player..': '
                if not ability then
                    -- If reporting all abilities, show totals first (using FAST functions)
                    player_parts[#player_parts + 1] = '{Total} '
                    if (stat=='ws' or stat=='ja' or stat=='enfeeb') and fast_get_percent(player_data, stat) then 
                        player_parts[#player_parts + 1] = fast_get_percent(player_data, stat) ..'% '
                    end
                    if fast_get_avg(player_data, stat) then 
						player_parts[#player_parts + 1] = '~'..fast_get_avg(player_data, stat)..'avg ' 
					end	
                    player_parts[#player_parts + 1] = '('..fast_get_tally(player_data, stat)..'s) '
                end
                
                -- Loop through the fast list we just retrieved
                if player_spell_list then
					for spell,spell_table in pairs(player_spell_list) do
						-- Don't show the 'tally' or 'damage' keys for the main category
						if type(spell_table) == 'table' then 
							if not ability then 
								player_parts[#player_parts + 1] = '['..spell..'] ' 
							end
							if not ability or (ability and spell==ability) then
								if spell_table.damage and spell_table.tally > 0 then 
									player_parts[#player_parts + 1] = '~'..math.floor(spell_table.damage / spell_table.tally)..'avg ' 
								end			
								player_parts[#player_parts + 1] = '('..spell_table.tally..'s) '
							end
						end
					end
				end
                report_lines[#report_lines + 1] = table.concat(player_parts, '')
            end  			
        end
        
	elseif get_stat_type(stat)=='multi' or stat=='multi' then
        -- Report for 'multi' stats (1-hit, 2-hit, etc.)
		report_lines[#report_lines + 1] = '[Reporting multihit stats] '..update_filters()
		for player in sorted_players:it() do
			player_parts = {} -- Reset buffer
			local player_data = collapsed_db[player]
			player_parts[#player_parts + 1] = player..': '
			player_parts[#player_parts + 1] = '{Total} '
			player_parts[#player_parts + 1] = '~'..fast_get_avg(player_data, 'multi')..'avg '
			
            -- Loop 1 through 8 to show individual hit counts and percentages
			for i=1,8,1 do
				local hits_str = tostring(i)
				if fast_get_tally(player_data, hits_str) > 0 then
					player_parts[#player_parts + 1] = '['..i..'-hit] '
					if fast_get_percent(player_data, hits_str) then 
						player_parts[#player_parts + 1] = ''..fast_get_percent(player_data, hits_str)..'% ' 
					end		
					player_parts[#player_parts + 1] = '('..fast_get_tally(player_data, hits_str)..'s), '
				end
			end
			report_lines[#report_lines + 1] = table.concat(player_parts, '')
		end
        
	elseif get_stat_type(stat) then
        -- Report for all other standard stats (melee, crit, block, evade, etc.)
		report_lines[#report_lines + 1] = '[Reporting '..stat..' stats] '..update_filters()
		for player in sorted_players:it() do
			player_parts = {} -- Reset buffer
			local player_data = collapsed_db[player]
			player_parts[#player_parts + 1] = player..': '
			if fast_get_percent(player_data, stat) then 
				player_parts[#player_parts + 1] = ''..fast_get_percent(player_data, stat)..'% ' 
			end
			if fast_get_avg(player_data, stat) then 
				player_parts[#player_parts + 1] = '~'..fast_get_avg(player_data, stat)..'avg ' 
			end		
			player_parts[#player_parts + 1] = '('..fast_get_tally(player_data, stat)..'s)'
			report_lines[#report_lines + 1] = table.concat(player_parts, '')
		end
        
	else
        -- Stat not found
		message('That stat was not found. Reportable stats include:')
		message('damage, melee, multi, crit, miss, ranged, r_crit, r_miss, spike, sc, add, hit, block, evade, parry, intimidate, absorb, ws, ja, spell')
		return
	end
	
	-- === 4. Send the report to chat ===
	-- The old logic (slice, split) is gone. We just loop our new table of lines.
	
	line_cap = 90 -- Max characters per chat line
	
	for i,line in pairs(report_lines) do
		if #line <= line_cap then
            -- Line is short enough, send it
			if chat_prefix then windower.send_command('input /'..chat_prefix..' '..line) coroutine.sleep(1.5)
			else message(line) end		
		else
            -- Line is too long, use prepare_string to wrap it
			line_table = prepare_string(line,line_cap)
			line_table['n'] = nil
			for i,subline in pairs(line_table) do
				if chat_prefix then windower.send_command('input /'..chat_prefix..' '..subline) coroutine.sleep(1.5)
				else message(subline) end		
			end
		end
	end
end

---
-- Takes a long string and splits it into a table of smaller strings,
-- each under a specified character limit, without breaking words.
-- @param str {string} The long string to wrap.
-- @param cap {number} The maximum number of characters per line.
-- @return {List} A List object containing the new, shorter strings.
--
function prepare_string(str,cap) 
	str_table = str:split(' ') -- Split the string by spaces
	str_table['n'] = nil
	new_string = ""
	new_table = L{}
	
	for i,word in pairs(str_table) do		
		new_string = new_string .. word .. ' '
		if #new_string > cap then
            -- String is over the cap, so append it to the table
			new_table:append(new_string)
			new_string = "" -- Start a new line
		end		
	end
	
    -- Add any remaining text that didn't hit the cap
	if new_string ~= "" then new_table:append(new_string) end
	
	return new_table
end
