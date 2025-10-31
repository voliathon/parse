--[[
    Copyright (c) 2016-2023, Flippant
    Copyright (c) 2025, Voliathon
    All rights reserved.

    This source code is licensed under the BSD-style license found in the
    LICENSE.md file in the root directory of this source tree.
]]

-- This table defines the "divisor" for percentage calculations.
-- The key is the stat being calculated (e.g., 'crit'), and the Set of values
-- are the stats that make up the "total" (e.g., 'melee' + 'crit').
-- A '+' prefix in a value means it's part of the "dividend" as well (e.g., 'melee' % = (melee + crit) / (melee + crit + miss)).
percent_table = {
		intimidate = S{"hit","block","anticipate","parry","evade"},
		evade = S{"hit","block","anticipate","parry"},
		parry = S{"nonparry"},
		anticipate = S{"hit","block"},
		block = S{"nonblock"},
		absorb = S{"hit","block"},
		retrate = S{"nonret"},
	
		melee = S{"miss","+crit"},
		crit = S{"melee"},
		
		ranged = S{"r_miss","+r_crit"},
		r_crit = S{"ranged"},
		
		ws = S{"ws_miss"},
		ja = S{"ja_miss"},
		
        -- Multi-hit percentages are calculated against all other multi-hit tallies
		['1'] = S{'2','3','4','5','6','7','8'},
		['2'] = S{'1','3','4','5','6','7','8'},
		['3'] = S{'1','2','4','5','6','7','8'},
		['4'] = S{'1','2','3','5','6','7','8'},
		['5'] = S{'1','2','3','4','6','7','8'},
		['6'] = S{'1','2','3','4','5','7','8'},
		['7'] = S{'1','2','3','4','5','6','8'},
		['8'] = S{'1','2','3','4','5','6','7'},
	}

---
-- Iterates the entire database to compile a unique list of all players.
-- @return {List} A List object containing all unique player names.
--
function get_players()
	local player_table = L{}
	
	for mob,players in pairs(database) do
		for player,__ in pairs(players) do
			if not player_table:contains(player) then
				player_table:append(player)
			end
		end
	end
	
	return player_table
end

---
-- Iterates the entire database to compile a unique list of all mobs.
-- @return {List} A List object containing all unique mob names.
--
function get_mobs()
	local mob_table = L{}
	
	for mob,players in pairs(database) do
		if not mob_table:contains(mob) then
			mob_table:append(mob)
		end
	end
	
	return mob_table
end

---
-- Gets a list of players, sorted by a specific stat, up to a given limit.
-- This is used to determine who appears in the UI boxes and reports.
-- @param sort_value {string} The stat to sort by (e.g., 'damage', 'defense', 'ws', 'melee').
-- @param limit {number} The maximum number of players to return.
-- @return {List} A sorted List object of player names.
--
function get_sorted_players(sort_value,limit)
	local player_table = get_players()
	if not player_table or player_table:empty() then
		return nil
	end
	
	if not limit then
		limit = 20 -- Default to 20 if no limit is provided
	end
	
    -- Handle 'multi' sort requests by sorting by 'melee' instead
	if S{'multi','1','2','3','4','5','6','7','8'}:contains(sort_value) then
		sort_value = 'melee'
	end

	local sorted_player_table = L{}
	
    -- This performs a simple N-pass selection sort to find the top 'limit' players.
	for i=1,limit,+1 do
		player_name = nil
		top_result = 0
		for __,player in pairs(player_table) do
			if sort_value == 'damage' then -- Sort by total damage
				if get_player_damage(player) > top_result and not sorted_player_table:contains(player) then
					top_result = get_player_damage(player)
					player_name = player					
				end						
			elseif sort_value == 'defense' then -- Sort by total defensive actions taken
				player_hits_received = get_player_stat_tally('parry',player) + get_player_stat_tally('hit',player) + get_player_stat_tally('evade',player) + get_player_stat_tally('block',player)
				if player_hits_received > top_result and not sorted_player_table:contains(player) then
					top_result = player_hits_received
					player_name = player
				end
			elseif S{'ws','ja','spell','mb'}:contains(sort_value) and get_player_stat_avg(sort_value,player) then -- Sort by avg for categories
				if get_player_stat_avg(sort_value,player) > top_result and not sorted_player_table:contains(player) then
					top_result = get_player_stat_avg(sort_value,player)
					player_name = player
				end				
			elseif S{'hit','miss','nonblock','nonparry','r_miss','ws_miss','ja_miss','enfeeb','enfeeb_miss'}:contains(sort_value) then -- Sort by tally (count)
				if get_player_stat_tally(sort_value,player) > top_result and not sorted_player_table:contains(player) then
					top_result = get_player_stat_tally(sort_value,player)
					player_name = player
				end		
			elseif (S{'melee','ranged','crit','r_crit'}:contains(sort_value) or get_stat_type(sort_value)=="defense") and get_player_stat_percent(sort_value,player) then -- Sort by percent
				if get_player_stat_percent(sort_value,player) > top_result and not sorted_player_table:contains(player) then
					top_result = get_player_stat_percent(sort_value,player)
					player_name = player
				end	
			elseif S{'sc','add','spike'}:contains(sort_value) then --Sort by 'other' types
				if get_player_stat_damage(sort_value,player) > top_result and not sorted_player_table:contains(player) then
					top_result = get_player_stat_damage(sort_value,player)
					player_name = player
				end	
			end
		end	
        -- Add the top player found in this pass to the sorted list
		if player_name then sorted_player_table:append(player_name) end		
	end

	return sorted_player_table
end

---
-- Recursively iterates through a table and collapses 'category' stats (ws, ja, spell).
-- It sums up the tallies and damages of individual abilities into the main category entry.
-- This modifies the table in-place.
-- @param t {table} The table to process (e.g., a player_table from collapse_mobs).
-- @return {table} The modified table.
--
function collapse_categories(t)
	for key,value in pairs(t) do
		if get_stat_type(key)=='category' then -- ws, ja, spell
			if not t[key].tally then t[key].tally = 0 end
			if not t[key].damage then t[key].damage = 0 end
			
			for spell,data in pairs(value) do
				if type(data)=='table' then
                    -- Sum the individual spell data into the main category
					if data.tally then
						t[key].tally = t[key].tally + data.tally
					end
					if data.damage then
						t[key].damage = t[key].damage + data.damage
					end
					-- NOTE: Does not remove the individual spell entry, as it's a copy
				end
			end
		elseif type(value)=='table' then -- Not a category, but a table, so go deeper
			collapse_categories(value)
		end
	end
	
	return t
end

---
-- Creates a new table that merges all data from all mobs, honoring filters.
-- The resulting table is player-centric (t[player][stat]...).
-- (Optimized to remove the 'copy(database)' call)
-- @param s_type {any} (Unused parameter)
-- @param mob_filters {table} (Unused parameter, uses global 'filters')
-- @return {table} A new table with all mob data collapsed by player.
--
function collapse_mobs(s_type,mob_filters)
	-- Create a new empty table to build our results into
	local player_table = {}
	
    -- Iterate over the main 'database' directly (no copy)
	for mob,players in pairs(database) do
        -- Check if the mob passes the 'mob' filters
		if check_filters('mob',mob) then
			for player,player_data in pairs(players) do
                -- Check if the player passes the 'player' filters
				if check_filters('player',player) then
					if not player_table[player] then
                        -- First time seeing this player, just add their data
						-- We MUST use copy() here to avoid modifying the original database
						player_table[player] = copy(player_data)
					else
                        -- Player already exists, merge this mob's data into their total
						merge_tables(player_table[player],player_data)
					end
				end				
			end
		end
	end
	
	if player_table then
        -- Now that all mobs are merged, collapse the categories (ws, ja, etc.)
        -- This sums up individual spell data into the main 'ws', 'ja', 'spell' categories
		collapse_categories(player_table)
	end

	return player_table
end

-- ============================================================================
-- == The slow get_player_spell_table() function has been removed from here.
-- ============================================================================

---
-- Gets the total tally (count) for a specific stat for one player,
-- summed across all filtered mobs.
-- @param stat {string} The stat to retrieve (e.g., 'melee', 'crit', 'ws').
-- @param plyr {string} The player's name.
-- @param mob_filters {table} (Unused parameter, uses global 'filters')
-- @return {number} The total tally for that stat.
--
function get_player_stat_tally(stat,plyr,mob_filters)
	if type(stat)=='number' then stat=tostring(stat) end
	local tally = 0
	for mob,mob_table in pairs(database) do
        -- Check if mob passes filters
		if check_filters('mob',mob) then
            -- Check if data exists for this mob/player/stat
			if database[mob][plyr] and database[mob][plyr][get_stat_type(stat)] and database[mob][plyr][get_stat_type(stat)][stat] then
				if database[mob][plyr][get_stat_type(stat)][stat].tally then
                    -- Simple stat, just add the tally
					tally = tally + database[mob][plyr][get_stat_type(stat)][stat].tally
				elseif get_stat_type(stat)=="category" then
                    -- Category stat, must sum all individual spells/abilities
					for spell,spell_table in pairs (database[mob][plyr][get_stat_type(stat)][stat]) do
						if spell_table.tally then
							tally = tally + spell_table.tally
						end
					end
				end
			end
		end
	end
	return tally
end

---
-- Gets the total damage for a specific stat for one player,
-- summed across all filtered mobs.
-- @param stat {string} The stat to retrieve (e.g., 'melee', 'crit', 'ws').
-- @param plyr {string} The player's name.
-- @param mob_filters {string} (Optional) A specific mob name to filter by. If nil, uses global filters.
-- @return {number} The total damage for that stat.
--
function get_player_stat_damage(stat,plyr,mob_filters)
	if type(stat)=='number' then stat=tostring(stat) end
	local damage = 0
	for mob,mob_table in pairs(database) do
        -- Check if mob passes filters (either the specific mob_filter or global filters)
		if (mob_filters and mob==mob_filters) or (not mob_filters and check_filters('mob',mob)) then
            -- Check if data exists
			if database[mob][plyr] and database[mob][plyr][get_stat_type(stat)] and database[mob][plyr][get_stat_type(stat)][stat] then
				if database[mob][plyr][get_stat_type(stat)][stat].damage then
                    -- Simple stat, add the damage
					damage = damage + database[mob][plyr][get_stat_type(stat)][stat].damage
				elseif get_stat_type(stat)=="category" then
                    -- Category stat, sum damage from all individual spells/abilities
					for spell,spell_table in pairs (database[mob][plyr][get_stat_type(stat)][stat]) do
						if spell_table.damage then
							damage = damage + spell_table.damage
						end
					end
				end
			end
		end
	end
	return damage
end

---
-- Calculates the average damage for a given stat for one player.
-- @param stat {string} The stat to calculate (e.g., 'ws', 'spell', 'multi').
-- @param plyr {string} The player's name.
-- @param mob_filters {table} (Unused parameter, uses global 'filters')
-- @return {number|nil} The calculated average, or nil if no data.
--
function get_player_stat_avg(stat,plyr,mob_filters)
    -- These stats don't have damage, so they can't have an average.
    if S{'ws_miss','ja_miss','enfeeb','enfeeb_miss'}:contains(stat) then return nil end
	if type(stat)=='number' then stat=tostring(stat) end
	local total,tally,result,digits = 0,0,0,0
	
	if stat=='multi' then
        -- 'multi' avg is special: it's the weighted average number of hits.
		digits = 2 -- Round to 2 decimal places
		for i=1,8,1 do -- Iterate 1 through 8
            local hits_str = tostring(i)
			total = total + (get_player_stat_tally(hits_str,plyr,mob_filters) * i)
			tally = tally + get_player_stat_tally(hits_str,plyr,mob_filters)
		end
	else	
        -- Standard avg: total damage / total tally
		digits = 0 -- No decimal places
		total = get_player_stat_damage(stat,plyr,mob_filters)
		tally = get_player_stat_tally(stat,plyr,mob_filters)		
	end

	if tally == 0 then return nil end -- Avoid division by zero

    -- Rounding logic
	local shift = 10 ^ digits
	result = math.floor( (total / tally)*shift + 0.5 ) / shift
	
	return result
end

---
-- Calculates the percentage for a given stat for one player.
-- Uses `percent_table` to determine the correct dividend and divisor.
-- @param stat {string} The stat to calculate (e.g., 'crit', 'block', 'damage').
-- @param plyr {string} The player's name.
-- @param mob_filters {table} (Unused parameter, uses global 'filters')
-- @return {number|nil} The calculated percentage (e.g., 25.5), or nil if no data.
--
function get_player_stat_percent(stat,plyr,mob_filters)
	if type(stat)=='number' then stat=tostring(stat) end
	
    local dividend, divisor
    
	if stat=="damage" then
        -- Special case: 'damage' % is player's damage / total parse damage
		dividend = get_player_damage(plyr,mob_filters)
		divisor = get_player_damage(nil,mob_filters) -- Get damage for *all* players
	else
        -- Standard stat percentage
		if not percent_table[stat] then
			return nil -- Stat is not configured for percentage calculation
		end
		dividend = get_player_stat_tally(stat,plyr,mob_filters)
		divisor = get_player_stat_tally(stat,plyr,mob_filters)
		
		if percent_table[stat] then
            -- Build the divisor based on the values in percent_table
			for v,__ in pairs(percent_table[stat]) do
				-- if string begins with +
				if type(v)=='string' and v:startswith('+') then
                    -- This stat (e.g. 'crit') counts towards both dividend and divisor
                    local stat_name = string.sub(v,2)
					dividend = dividend + get_player_stat_tally(stat_name,plyr,mob_filters)
					divisor = divisor + get_player_stat_tally(stat_name,plyr,mob_filters)
				else
                    -- This stat (e.g. 'melee') only counts towards the divisor
					divisor = divisor + get_player_stat_tally(v,plyr,mob_filters)
				end
			end
		end
	end
	
	if dividend==0 or divisor==0 then
		return nil -- Avoid division by zero
	end

	digits = 4 -- Round to 4 decimal places for precision

	shift = 10 ^ digits
	result = math.floor( (dividend / divisor) *shift + 0.5 ) / shift

	return result * 100 -- Return as a percentage (e.g., 25.5)
end

---
-- Gets the total damage (from all sources) for a specific player,
-- or for all players if plyr is nil.
-- @param plyr {string|nil} The player's name, or nil for all players.
-- @param mob_filters {string} (Optional) A specific mob name to filter by. If nil, uses global filters.
-- @return {number} The total damage.
--
function get_player_damage(plyr,mob_filters)
	local damage = 0
	
	for mob,players in pairs(database) do
        -- Check filters
		if (mob_filters and mob==mob_filters) or (not mob_filters and check_filters('mob',mob)) then
			for player,mob_player_table in pairs(players) do
                -- If plyr is nil, or if player matches plyr
				if not plyr or (plyr and player==plyr) then
					if mob_player_table.total_damage then
                        -- Add the pre-calculated total_damage for this player/mob
						damage = damage + mob_player_table.total_damage
					end
				end
			end
		end
	end
	
	return damage
end

---
-- Legacy function for old export versions that did not have the 'total_damage' field.
-- This manually calculates total damage by summing all individual damage_types.
-- @param plyr {string} The player's name.
-- @param mnst {string} The *specific* mob name (no filters).
-- @return {number} The total damage.
--
function find_total_damage(plyr,mnst)
	local damage = 0
	if database[mnst] and database[mnst][plyr] then
		for stat in damage_types:it() do
			damage = damage + get_player_stat_damage(stat,plyr,mnst)
		end
	end
	return damage
end

-- ============================================================================
-- == NEW FAST FUNCTIONS FOR DISPLAY
-- == These functions read from a pre-collapsed player table, not the
-- == main database. They are not expensive to call.
-- ============================================================================

---
-- Calculates the total damage of the entire parse from a collapsed player table.
-- @param player_table {table} The table returned by `collapse_mobs()`.
-- @return {number} The total damage from all players.
--
function get_total_parse_damage(player_table)
	local total_damage = 0
	if not player_table then return 0 end
	
	for player, data in pairs(player_table) do
		if data.total_damage then
			total_damage = total_damage + data.total_damage
		end
	end
	return total_damage
end

---
-- (Fast) Gets the tally for a stat from a collapsed player table.
-- @param player_data {table} A single player's table (e.g., `collapsed_db[player_name]`).
-- @param stat {string} The stat name.
-- @return {number} The tally, or 0 if not found.
--
function fast_get_tally(player_data, stat)
	if type(stat)=='number' then stat=tostring(stat) end
	local stat_type = get_stat_type(stat)
	
	if player_data[stat_type] and player_data[stat_type][stat] and player_data[stat_type][stat].tally then
		return player_data[stat_type][stat].tally
	end
	
	return 0
end

---
-- (Fast) Gets the damage for a stat from a collapsed player table.
-- @param player_data {table} A single player's table.
-- @param stat {string} The stat name.
-- @return {number} The damage, or 0 if not found.
--
function fast_get_damage(player_data, stat)
	if type(stat)=='number' then stat=tostring(stat) end
	local stat_type = get_stat_type(stat)
	
	if player_data[stat_type] and player_data[stat_type][stat] and player_data[stat_type][stat].damage then
		return player_data[stat_type][stat].damage
	end
	
	return 0
end

---
-- (Fast) Calculates the average for a stat from a collapsed player table.
-- @param player_data {table} A single player's table.
-- @param stat {string} The stat name.
-- @return {number|nil} The average, or nil if no data.
--
function fast_get_avg(player_data, stat)
	if S{'ws_miss','ja_miss','enfeeb','enfeeb_miss'}:contains(stat) then return nil end
	if type(stat)=='number' then stat=tostring(stat) end
	
	local total,tally,result,digits = 0,0,0,0
	
	if stat=='multi' then
		digits = 2 -- Round to 2 decimal places
		for i=1,8,1 do
            local hits_str = tostring(i)
			local hits_tally = fast_get_tally(player_data, hits_str)
			total = total + (hits_tally * i)
			tally = tally + hits_tally
		end
	else
		digits = 0 -- No decimal places
		total = fast_get_damage(player_data, stat)
		tally = fast_get_tally(player_data, stat)
	end
	
	if tally == 0 then return nil end -- Avoid division by zero
	
	local shift = 10 ^ digits
	result = math.floor( (total / tally)*shift + 0.5 ) / shift
	
	return result
end

---
-- (Fast) Calculates the percentage for a stat from a collapsed player table.
-- @param player_data {table} A single player's table.
-- @param stat {string} The stat name.
-- @param total_parse_damage {number} The total damage for the entire parse.
-- @return {number|nil} The percentage, or nil if no data.
--
function fast_get_percent(player_data, stat, total_parse_damage)
	if type(stat)=='number' then stat=tostring(stat) end
	
    local dividend, divisor
    
	if stat=="damage" then
        -- Special case: 'damage' % is player's damage / total parse damage
		dividend = player_data.total_damage or 0
		divisor = total_parse_damage
	else
        -- Standard stat percentage
		if not percent_table[stat] then
			return nil -- Stat is not configured for percentage calculation
		end
		
		dividend = fast_get_tally(player_data, stat)
		divisor = dividend -- Start with divisor = dividend
		
		if percent_table[stat] then
            -- Build the divisor based on the values in percent_table
			for v,__ in pairs(percent_table[stat]) do
				if type(v)=='string' and v:startswith('+') then
                    -- This stat (e.g. 'crit') counts towards both dividend and divisor
                    local stat_name = string.sub(v,2)
					local tally = fast_get_tally(player_data, stat_name)
					dividend = dividend + tally
					divisor = divisor + tally
				else
                    -- This stat (e.g. 'melee') only counts towards the divisor
					divisor = divisor + fast_get_tally(player_data, v)
				end
			end
		end
	end
	
	if not dividend or not divisor or dividend == 0 or divisor == 0 then
		return nil
	end

	local digits = 1 -- Round to 1 decimal place for display

	local shift = 10 ^ digits
	local result = math.floor( ((dividend / divisor) * 100) * shift + 0.5 ) / shift

	return result
end
