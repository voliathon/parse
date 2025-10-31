--[[
    Copyright (c) 2016-2023, Flippant
    Copyright (c) 2025, Voliathon
    All rights reserved.

    This source code is licensed under the BSD-style license found in the
    LICENSE.md file in the root directory of this source tree.
]]


-- This table seems to define which action categories are valid for spike damage (e.g., counters, spikes)
-- true = valid, false = invalid
spike_effect_valid = {true,false,false,false,false,false,false,false,false,false,false,false,false,false,false}

-- This table defines which action categories are valid for "add effects" (e.g., Skillchains, additional elemental damage)
add_effect_valid = {true,true,true,true,false,false,false,false,false,false,true,false,true,false,false}

-- A set of all action message IDs that correspond to a Skillchain.
skillchain_messages = T{288,289,290,291,292,293,294,295,296,297,298,299,300,301,302,385,386,387,388,389,390,391,392,393,394,395,396,397,398,732,767,768,769,770}

-- A set of action message IDs that correspond to "add effects" (e.g., "Additional effect: Fire damage.")
add_effect_messages = T{161,163,229}

-- A mapping of Skillchain message IDs to their names, used for debug messages.
skillchain_names = {
    [288] = "Skillchain: Light",
    [289] = "Skillchain: Darkness",
    [290] = "Skillchain: Gravitation",
    [291] = "Skillchain: Fragmentation",
    [292] = "Skillchain: Distortion",
    [293] = "Skillchain: Fusion",
    [294] = "Skillchain: Compression",
    [295] = "Skillchain: Liquefaction",
    [296] = "Skillchain: Induration",
    [297] = "Skillchain: Reverberation",
    [298] = "Skillchain: Transfixion",
    [299] = "Skillchain: Scission",
    [300] = "Skillchain: Detonation",
    [301] = "Skillchain: Impaction",
    [302] = "Skillchain: Cosmic Elucidation",
    [385] = "Skillchain: Light",
    [386] = "Skillchain: Darkness",
    [387] = "Skillchain: Gravitation",
    [388] = "Skillchain: Fragmentation",
    [389] = "Skillchain: Distortion",
    [390] = "Skillchain: Fusion",
    [391] = "Skillchain: Compression",
    [392] = "Skillchain: Liquefaction",
    [393] = "Skillchain: Induration",
    [394] = "Skillchain: Reverberation",
    [395] = "Skillchain: Transfixion",
    [396] = "Skillchain: Scission",
    [397] = "Skillchain: Detonation",
    [398] = "Skillchain: Impaction",
    [732] = "Skillchain: Universal Enlightenment",
    [767] = "Skillchain: Radiance",
    [768] = "Skillchain: Umbra",
    [769] = "Skillchain: Radiance",
    [770] = "Skillchain: Umbra",
}

-- Maps action message IDs from a mob's perspective to our internal defensive stat names.
local defense_action_messages = {
	[1] = 'hit', -- Mob hits player
	[67] = 'hit', -- Mob critically hits player (still a 'hit' for defensive purposes)
	[106] = 'intimidate', -- Mob intimidates player
	[15] = 'evade', [282] = 'evade', -- Player evades mob
	[373] = 'absorb', -- Player absorbs damage
	[536] = 'retaliate', [535] = 'retaliate' -- Player retaliates (e.g., Counter)
}

-- Maps action message IDs from a player's perspective to our internal offensive stat names.
local offense_action_messages = {
	[1] = 'melee', -- Player hits mob
	[67] = 'crit', -- Player critically hits mob
	[15] = 'miss', [63] = 'miss', -- Player misses mob
	[352] = 'ranged', [576] = 'ranged', [577] = 'ranged', -- Player hits with ranged attack
	[353] = 'r_crit', -- Player critically hits with ranged attack
	[354] = 'r_miss', -- Player misses with ranged attack
	[185] = 'ws', [197] = 'ws', [187] = 'ws', -- Player uses weapon skill
	[188] = 'ws_miss', -- Player's weapon skill misses
	[2] = 'spell', [227] = 'spell', -- Player casts spell
	[252] = 'mb', [265] = 'mb', [274] = 'mb', [379] = 'mb', [747] = 'mb', [748] = 'mb', -- Magic Burst
	[82] = 'enfeeb', [236] = 'enfeeb', [754] = 'enfeeb', [755] = 'enfeeb', -- Enfeebling magic
	[85] = 'enfeeb_miss', [284] = 'enfeeb_miss', [653] = 'enfeeb_miss', [654] = 'enfeeb_miss', [655] = 'enfeeb_miss', [656] = 'enfeeb_miss', -- Enfeebling magic resisted/missed
	[110] = 'ja', [317] = 'ja', [522] = 'ja', [802] = 'ja', -- Player uses job ability
	[158] = 'ja_miss', [324] = 'ja_miss', -- Player's job ability misses
	[157] = 'Barrage', -- Special case for Barrage (handled as a 'ja')
	[77] = 'Sange', -- Special case for Sange (handled as a 'ja')
	[264] = 'aoe' -- Area of Effect (likely a secondary hit from a WS/spell)
}

---
-- The primary packet listener function.
-- (Optimized to use actor_name_cache)
-- @param act {table} The raw action packet table.
--
function parse_action_packet(act)
	if pause then return end -- Do nothing if the parser is paused
	
	local player = windower.ffxi.get_player()
	local NPC_name, PC_name -- Placeholders for actor/target names
   
    -- Get extended info for the actor (who is performing the action)
	act.actor = player_info(act.actor_id)
	if not act.actor then
		return -- If actor info can't be found, stop
	end
	
	local multihit_count,multihit_count2 = nil
	local aoe_type = 'ws'
	
    -- Loop through every target of the action
	for i,targ in pairs(act.targets) do
		multihit_count,multihit_count2 = 0,0
        
        -- Loop through every "action" on this specific target
        for n,m in pairs(targ.actions) do
            -- Ensure the message ID is valid and exists in Windower's resources
            if m.message ~= 0 and res.action_messages[m.message] ~= nil then	
				
				-- === This is the bottleneck we are fixing ===
				-- We still need player_info to check type, but we will cache the name
				local target = player_info(targ.id) 
				
                -- === CASE 1: MOB IS ACTOR (Defensive Parsing) ===
				if act.actor.type == 'mob' and settings.record[target.type] then
					
					-- === CACHING LOGIC (MOB ACTOR) ===
					NPC_name = actor_name_cache[act.actor.id]
					if not NPC_name then
						NPC_name = nickname(act.actor.name:gsub(" ","_"):gsub("'",""))
						actor_name_cache[act.actor.id] = NPC_name
						debug('CACHE MISS: Caching mob name '..NPC_name..' for ID '..act.actor.id)
					end
					
					PC_name = actor_name_cache[target.id]
					if not PC_name then
						PC_name = construct_PC_name(target)
						actor_name_cache[target.id] = PC_name
						debug('CACHE MISS: Caching player name '..PC_name..' for ID '..target.id)
					end
					-- ===================================
					
                    -- Apply special indexing if the target is the local player
                    if target.name == player.name then
						local shield_name = get_shield()
						if settings.index_shield and shield_name then
							-- Re-cache the special indexed name
							local indexed_name = PC_name:sub(1, 6)..'-'..shield_name..''
							if settings.index_reprisal and buffs.Reprisal then indexed_name = indexed_name .. 'R' end
							if settings.index_palisade and buffs.Palisade then indexed_name = indexed_name .. 'P' end
							if settings.index_battuta and buffs.Battuta then indexed_name = indexed_name .. 'B' end
							PC_name = indexed_name -- Use the full name for this action
						else
							if settings.index_reprisal and buffs.Reprisal then PC_name = PC_name .. 'R' end
							if settings.index_palisade and buffs.Palisade then PC_name = PC_name .. 'P' end
							if settings.index_battuta and buffs.Battuta then PC_name = PC_name .. 'B' end
						end
					end

					local action = defense_action_messages[m.message]
					local engaged = (target.status==1) and true or false

					if m.reaction == 12 and act.category == 1 then  -- Block
						register_data(NPC_name,PC_name,'block',m.param)
						if engaged then
							register_data(NPC_name,PC_name,'nonparry')
						end
					elseif m.reaction == 11 and act.category == 1 then  -- Parry
						register_data(NPC_name,PC_name,'parry')
					elseif action == 'hit' then -- Hit or Crit
						register_data(NPC_name,PC_name,action,m.param)
						if engaged then
							register_data(NPC_name,PC_name,'nonparry')
							if buffs.Retaliation and not m.has_spike_effect then
								register_data(NPC_name,PC_name,'nonret')
							end
						end
						if act.category == 1 then
							register_data(NPC_name,PC_name,'nonblock',m.param)
						end
					elseif T{'intimidate','evade'}:contains(action) then
						register_data(NPC_name,PC_name,action)
					end

					if action == 'absorb' then
						register_data(NPC_name,PC_name,'absorb',m.param)
					end					
					
					if m.has_spike_effect then
						local spike_action = defense_action_messages[m.spike_effect_message]
						if m.spike_effect_param then
							register_data(NPC_name,PC_name,'spike',m.spike_effect_param)
						end
						if spike_action == 'retaliate' then
							register_data(NPC_name,PC_name,'retrate')
						end
					end
					
				-- === CASE 2: PLAYER IS ACTOR (Offensive Parsing) ===
				elseif target.type == 'mob' and settings.record[act.actor.type] then
					
					-- === CACHING LOGIC (PLAYER ACTOR) ===
					NPC_name = actor_name_cache[target.id]
					if not NPC_name then
						NPC_name = nickname(target.name:gsub(" ","_"):gsub("'",""))
						actor_name_cache[target.id] = NPC_name
						debug('CACHE MISS: Caching mob name '..NPC_name..' for ID '..target.id)
					end
					
					PC_name = actor_name_cache[act.actor.id]
					if not PC_name then
						PC_name = construct_PC_name(act.actor)
						actor_name_cache[act.actor.id] = PC_name
						debug('CACHE MISS: Caching player name '..PC_name..' for ID '..act.actor.id)
					end
					-- ===================================

					local action = offense_action_messages[m.message]

					if T{'melee','crit','miss'}:contains(action) then
						register_data(NPC_name,PC_name,action,m.param)
						if m.animation==0 then -- main hand
							multihit_count = multihit_count + 1
						elseif m.animation==1 then -- off hand
							multihit_count2 = multihit_count2 + 1
						end	
					elseif T{'ranged','r_crit','r_miss'}:contains(action) then
						register_data(NPC_name,PC_name,action,m.param)
					elseif T{'ws','ws_miss'}:contains(action) then
						register_data(NPC_name,PC_name,action,m.param,'ws',act.param)
						aoe_type = 'ws'
					elseif T{'spell','mb'}:contains(action) then
						register_datalogging(NPC_name,PC_name,action,m.param,'spell',act.param)
						aoe_type = 'spell'
					elseif T{'enfeeb','enfeeb_miss'}:contains(action) then
						register_data(NPC_name,PC_name,action,nil,'spell',act.param)
					elseif T{'ja','ja_miss'}:contains(action) then
						register_data(NPC_name,PC_name,action,m.param,'ja',act.param)
						aoe_type = 'ja'
					elseif T{'Barrage','Sange'}:contains(action) then
						register_data(NPC_name,PC_name,'ja',m.param,'ja',action)
					elseif action == 'aoe' then
						register_data(NPC_name,PC_name,aoe_type,m.param,aoe_type,act.param)
					end

					if m.has_add_effect and m.add_effect_message ~= 0 and add_effect_valid[act.category] then
						if skillchain_messages:contains(m.add_effect_message) then
							-- Create a special "player" name for the SC damage
							-- Note: We don't cache this "SC-Vol" name as it's not tied to an ID
							local SC_PC_name = "SC-"..PC_name:sub(1, 3)							
							register_data(NPC_name,SC_PC_name,'sc',m.add_effect_param)
							if skillchain_names and skillchain_names[m.add_effect_message] then debug('sc ('..SC_PC_name..') '..skillchain_names[m.add_effect_message]..' '..m.add_effect_param) end
						elseif add_effect_messages:contains(m.add_effect_message) and m.add_effect_param > 0 then
							register_data(NPC_name,PC_name,'add',m.add_effect_param)
						end
					end
					
					if m.has_spike_effect and m.spike_effect_message ~= 0 and spike_effect_valid[act.category] then 
						--debug('Monster spikes: Effect: '..m.spike_effect_effect)
					end
				end				
			end
		end
	end
	
	if multihit_count and multihit_count > 0 then
		register_data(NPC_name,PC_name,tostring(multihit_count))
	end
	if multihit_count2 and multihit_count2 > 0 then
		register_data(NPC_name,PC_name,tostring(multihit_count2))
	end
	
	--Handle auto-export
	if PC_name and autoexport and autoexport_tracker == autoexport_interval then
		export_parse(autoexport)
	end
	autoexport_tracker = (autoexport_tracker % autoexport_interval) + 1
end

---
-- Creates a standardized player name, especially for pets/trusts.
-- Function credit to Suji.
-- @param PC {table} The player info table from `player_info()`.
-- @return {string} The constructed name (e.g., "Player-Petn").
--
function construct_PC_name(PC)
	local name = PC.name
    local result = ''
    if PC.owner then -- If it's a pet/trust
        if string.len(name) > 7 then
            result = string.sub(name, 1, 6)
        else
            result = name
        end
        -- Append the first 4 chars of the owner's name
        result = result..'-'..string.sub(nickname(PC.owner.name), 1, 4)..''
    else -- If it's a regular player
        result = nickname(name)
    end
    return string.sub(result,1,10) -- Truncate to 10 chars
end

---
-- Checks if a player name has a rename mapping and returns the new name.
-- @param player_name {string} The original name.
-- @return {string} The renamed name, or the original name if no mapping exists.
--
function nickname(player_name)
	if renames[player_name] then
		return renames[player_name]
	else
		return player_name
	end
end

---
-- Initializes the table structure in the database for a new mob/player pair.
-- @param mob_name {string} The name of the mob.
-- @param player_name {string} The name of the player.
--
function init_mob_player_table(mob_name,player_name)
	if not database[mob_name] then
		database[mob_name] = {}
	end
	database[mob_name][player_name] = {}	
end

---
-- The main data registration function.
-- (Optimized to use spell_name_cache)
-- @param NPC_name {string} The name of the mob.
-- @param PC_name {string} The name of the player.
-- @param stat {string} The internal stat name (e.g., 'melee', 'ws', 'block').
-- @param val {number} (Optional) The damage/healing value of the action.
-- @param spell_type {string} (Optional) The category ('ws', 'ja', 'spell') if applicable.
-- @param spell_id {number|string} (Optional) The resource ID or name of the ability.
--
function register_data(NPC_name,PC_name,stat,val,spell_type,spell_id)    
    -- Initialize database structure if this is the first time seeing this pair
    if not database[NPC_name] or not database[NPC_name][PC_name] then						
        init_mob_player_table(NPC_name,PC_name)
    end
    
	local spell_name = nil
	local stat_type = get_stat_type(stat) or 'unknown'

    local mob_player_table = database[NPC_name][PC_name]
    -- Create the stat_type table (e.g., 'defense', 'melee', 'category') if it doesn't exist
	if not mob_player_table[stat_type] then
		mob_player_table[stat_type] = {}
	end

    -- Create the stat table (e.g., 'hit', 'crit', 'ws') if it doesn't exist
	if not mob_player_table[stat_type][stat] then
		mob_player_table[stat_type][stat] = {}
	end
	
	if stat_type == "category" then -- Handle WS, spells, and JA
        
		-- === OPTIMIZATION #2 START ===
		if type(spell_id) == 'number' then
			-- Check the cache first!
			spell_name = spell_name_cache[spell_id]
			
			if not spell_name then
				-- Not in cache. Do the slow lookup and sanitization ONCE.
				local name_from_res
				if spell_type == "ws" and res.weapon_skills[spell_id] then 
					name_from_res = res.weapon_skills[spell_id].english
				elseif spell_type == "ja" and res.job_abilities[spell_id] then 
					name_from_res = res.job_abilities[spell_id].english
				elseif spell_type == "spell" and res.spells[spell_id] then 
					name_from_res = res.spells[spell_id].english 
				end
				
				if name_from_res then
					-- Sanitize the name
					spell_name = name_from_res:gsub(" ","_"):gsub("'",""):gsub(":","")
					-- Store the clean name in the cache for next time
					spell_name_cache[spell_id] = spell_name
					debug('CACHE MISS: Caching spell name '..spell_name..' for ID '..spell_id)
				else
					spell_name = "unknown"
				end
			end
		elseif type(spell_id) == 'string' then 
			-- This is for manually-named abilities like 'Barrage'
			-- We can cache these too, using the string as the key
			spell_name = spell_name_cache[spell_id]
			if not spell_name then
				spell_name = spell_id:gsub(" ","_"):gsub("'",""):gsub(":","")
				spell_name_cache[spell_id] = spell_name
			end
		end
		-- === OPTIMIZATION #2 END ===
		
		if not spell_name then
			message('There was an error recording that action...')
			return
		end
		
        -- Create the table for this specific ability if it doesn't exist
		if not mob_player_table[stat_type][stat][spell_name] then
			mob_player_table[stat_type][stat][spell_name] = {['tally'] = 0}
		end
		
        -- Increment the tally
		mob_player_table[stat_type][stat][spell_name].tally = mob_player_table[stat_type][stat][spell_name].tally + 1
		
		if val then -- If there was damage
            -- Initialize damage if it doesn't exist
			if not mob_player_table[stat_type][stat][spell_name].damage then
				mob_player_table[stat_type][stat][spell_name].damage = val
			else
				mob_player_table[stat_type][stat][spell_name].damage = mob_player_table[stat_type][stat][spell_name].damage + val
			end
			
            -- Add to the player's total_damage for this mob
			if damage_types:contains(stat) then
				if not mob_player_table.total_damage then
					mob_player_table.total_damage = val
				else
					mob_player_table.total_damage = mob_player_table.total_damage + val
				end
			end
		end
	else -- Handle all other stats (melee, defense, multi-hit, etc.)
        -- Initialize tally if it doesn't exist
		if not mob_player_table[stat_type][stat].tally then
			mob_player_table[stat_type][stat].tally = 0 
		end
		
        -- Increment tally
		mob_player_table[stat_type][stat].tally = mob_player_table[stat_type][stat].tally + 1
		
		if val then -- If there was damage
            -- Initialize damage if it doesn't exist
			if not mob_player_table[stat_type][stat].damage then
				mob_player_table[stat_type][stat].damage = val
			else
				mob_player_table[stat_type][stat].damage = mob_player_table[stat_type][stat].damage + val
			end
			
            -- Add to the player's total_damage for this mob
			if damage_types:contains(stat) then
				if not mob_player_table.total_damage then
					mob_player_table.total_damage = val
				else
					mob_player_table.total_damage = mob_player_table.total_damage + val
				end
			end
		end	
	end

    -- Check if this player is in the 'logger' list and write to the log file
    if val and settings.logger:find(function(el) if PC_name==el or (el:endswith('*') and PC_name:startswith(tostring(el:gsub('*','')))) then return true end return false end) then
        log_data(PC_name,NPC_name,stat,val,spellName)
    end
end

---
-- Gets the name of the player's currently equipped shield/sub-weapon.
-- (Optimized to return the cached name from the 'buffs' table)
-- @return {string|nil} The 3-letter cached name of the item, or nil.
--
function get_shield()
	return buffs.current_shield
end


---
-- Gets extended information about an entity (player, mob, pet) by its ID.
-- Function credit to Byrth.
-- @param id {number} The entity's game ID.
-- @return {table} A table with info: {name, status, id, type, owner}.
--
function player_info(id)
    local player_table = windower.ffxi.get_mob_by_id(id)
    local typ,owner
    
    if player_table == nil then
        return {name=nil,id=nil,type='debug',owner=nil}
    end
    
    -- Check if the ID is in the player's party/alliance list
    for i,v in pairs(windower.ffxi.get_party()) do
        if type(v) == 'table' and v.mob and v.mob.id == player_table.id then           
            if i == 'p0' then
                typ = 'me'
            elseif i:sub(1,1) == 'p' then
                typ = 'party'
				if player_table.is_npc then typ = 'trust' end -- It's a party member, but also an NPC = Trust
            else
				typ = 'alliance'
            end
        end
    end
    
    -- If not in party, check if it's a pet, fellow, or mob
    if not typ then
        if player_table.is_npc then
            if player_table.id%4096>2047 then
                -- Check if it's a pet or fellow by matching its index to a party member's pet/fellow index
                for i,v in pairs(windower.ffxi.get_party()) do
                    if type(v) == 'table' and v.mob and v.mob.pet_index and v.mob.pet_index == player_table.index then
                        typ = 'pet'
						owner = v
                    elseif type(v) == 'table' and v.mob and v.mob.fellow_index and v.mob.fellow_index == player_table.index then
                        typ = 'fellow'
                        owner = v
                        break
                    end
                end
            else
                typ = 'mob'
            end
        else
            typ = 'other' -- A player not in your party/alliance
        end
    end
    if not typ then typ = 'debug' end -- Fallback
    return {name=player_table.name,status=player_table.status,id=id,type=typ,owner=(owner or nil)}
end
