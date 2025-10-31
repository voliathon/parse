--[[
    Copyright (c) 2016-2023, Flippant
    Copyright (c) 2025, Voliathon
    All rights reserved.

    This source code is licensed under the BSD-style license found in the
    LICENSE.md file in the root directory of this source tree.
]]

-- Addon metadata
_addon.version = '2.0.1'
_addon.name = 'Parse'
_addon.author = 'Flippant(Original) & Voliathon(New)'
_addon.commands = {'parse','p'}

-- Import required Windower libraries
require 'tables'
require 'sets'
require 'strings'
require 'actions'
config = require('config')
texts = require('texts')
res = require 'resources'

-- Set the chat color for addon messages (200 is a light blue)
messageColor = 200

-- Define the default settings table.
-- This is used to create the initial settings.xml if one doesn't exist.
default_settings = {}
default_settings.update_interval = 1 -- How often (in seconds) to refresh the display boxes
default_settings.autoexport_interval = 500 -- How many actions before triggering an auto-export
default_settings.debug = false -- Enable/disable debug messages
-- Special indexing settings for player defense
default_settings.index_shield = false -- Append shield name to player name for defense stats
default_settings.index_reprisal = true -- Append 'R' if Reprisal is active
default_settings.index_palisade = true -- Append 'P' if Palisade is active
default_settings.index_battuta = true -- Append 'B' if Battuta is active
-- Define which entity types to record data for
default_settings.record = {
		["me"] = true,
		["party"] = true,
		["trust"] = true,
		["alliance"] = true,
		["pet"] = true,
		["fellow"] = true
	}
default_settings.logger = S{"Voliat*"} -- Players to log individual actions for (supports wildcard '*')
-- Default color settings for UI labels
default_settings.label = {
		["player"] = {red=100,green=200,blue=200},
		["stat"] = {red=225,green=150,blue=0},
	}
-- Define the default settings for all display boxes
default_settings.display = {}
-- Melee Box Settings
default_settings.display.melee = {
		["visible"] = true,
		["type"] = "offense", -- Determines sorting (damage vs. defensive tallies)
		["pos"] = {x=570,y=50}, -- Default position
		["order"] = L{"damage","melee","ws"}, -- Stats to display, in order
		["max"] = 6, -- Max number of players to show
		["data_types"] = { -- Data to show for each stat
			["damage"] = S{'total','total-percent'},
			["melee"] = S{'percent'},
			["miss"] = S{'tally'},
			["crit"] = S{'percent'},
			["ws"] = S{'avg'},
			["ja"] = S{'avg'},
			["multi"] = S{'avg'},
			["ws_miss"] = S{'tally'}
		},
		["bg"] = {visible=true,alpha=50,red=0,green=0,blue=0}, -- Background settings
		["text"] = {size=10,font="consolas",alpha=255,red=255,green=255,blue=255,stroke={width=1,alpha=200,red=0,green=0,blue=0}}, -- Font settings
		["padding"] = 4,
		["flags"] = {draggable=true,right=false,bottom=false,bold=true} -- Text box flags
	}
-- Defense Box Settings
default_settings.display.defense = {
		["visible"] = false,
		["type"] = "defense",
		["pos"] = {x=150,y=440},
		["order"] = L{"block","hit","parry",},
		["max"] = 2,
		["data_types"] = {
			["block"] = S{'avg','percent'},
			["evade"] = S{'percent'},
			["hit"] = S{'avg'},
			["parry"] = S{'percent'},
			["absorb"] = S{'percent'},
			["intimidate"] = S{'percent'},
		},
		["bg"] = {visible=true,alpha=50,red=0,green=0,blue=0},
		["text"] = {size=10,font="consolas",alpha=255,red=255,green=255,blue=255,stroke={width=1,alpha=200,red=0,green=0,blue=0}},
		["padding"] = 4,
		["flags"] = {draggable=true,right=false,bottom=false,bold=true}
	}
-- Ranged Box Settings
default_settings.display.ranged = {
		["visible"] = false,
		["type"] = "offense",
		["pos"] = {x=570,y=200},
		["order"] = L{"damage","ranged","ws"},
		["max"] = 6,
		["data_types"] = {
			["damage"] = S{'total','total-percent'},
			["ranged"] = S{'percent'},
			["r_crit"] = S{'percent'},
			["ws"] = S{'avg'},
		},
		["bg"] = {visible=true,alpha=50,red=0,green=0,blue=0},
		["text"] = {size=10,font="consolas",alpha=255,red=255,green=255,blue=255,stroke={width=1,alpha=200,red=0,green=0,blue=0}},
		["padding"] = 4,
		["flags"] = {draggable=true,right=false,bottom=false,bold=true}
	}
-- Magic Box Settings
default_settings.display.magic = {
		["visible"] = false,
		["type"] = "offense",
		["pos"] = {x=570,y=50},		
		["order"] = L{"damage","spell"},
		["max"] = 6,
		["data_types"] = {
			["damage"] = S{'total','total-percent'},
			["spell"] = S{'avg'},
		},
		["bg"] = {visible=true,alpha=50,red=0,green=0,blue=0},
		["text"] = {size=10,font="consolas",alpha=255,red=255,green=255,blue=255,stroke={width=1,alpha=200,red=0,green=0,blue=0}},
		["padding"] = 4,
		["flags"] = {draggable=true,right=false,bottom=false,bold=true}
	}

-- Load the settings from file (settings.xml), using defaults if no file exists
settings = config.load(default_settings)
-- Save the settings (this creates the file if it doesn't exist, or updates it)
config.save(settings)

-- Initialize global state variables
update_tracker,update_interval = 0,settings.update_interval -- Timers for UI updates
autoexport = nil -- Holds the autoexport filename if enabled
autoexport_tracker,autoexport_interval = 0,settings.autoexport_interval -- Timers for auto-export
pause = false -- Global pause state
logging = true -- Global logging state
-- Table to hold the state of tracked buffs for special indexing
buffs = {
	["Palisade"] = false, 
	["Reprisal"] = false, 
	["Battuta"] = false, 
	["Retaliation"] = false,
	["current_shield"] = nil 
} 

-- The main database table. Structure: database[mob_name][player_name][stat_type][stat_name]
database = {}
actor_name_cache = {} -- Caches entity IDs to their constructed names
spell_name_cache = {} -- Caches spell/ability IDs to their sanitized names
stat_to_type_map = {} -- A reverse map for fast stat type lookups
-- Tables to hold active filters
filters = {
		['mob'] = S{},
		['player'] = S{}
	}
-- Table to hold renames (e.g., renames['OriginalName'] = 'NewName')
renames = {}
-- Table to hold the text box UI objects
text_box = {}
-- Table to track which log files have been created during this session
logs = {}

-- Define categories for all tracked stats
-- This helps organize the database and logic
stat_types = {}
stat_types.defense = S{"hit","block","evade","parry","intimidate","absorb","shadow","anticipate","nonparry","nonblock","retrate","nonret"}
stat_types.melee = S{"melee","miss","crit"}
stat_types.ranged = S{"ranged","r_miss","r_crit"}
stat_types.category = S{"ws","ja","spell","mb","enfeeb","ws_miss","ja_miss","enfeeb_miss"}
stat_types.other = S{"spike","sc","add"}
stat_types.multi = S{'1','2','3','4','5','6','7','8'} -- Multi-attack hits per round

-- Build the fast lookup map for get_stat_type()
-- This runs ONCE when the addon is loaded.
for stat_type, stats_set in pairs(stat_types) do
	for stat_name in stats_set:it() do
		stat_to_type_map[stat_name] = stat_type
	end
end

-- Define which stats contribute to total damage
damage_types = S{"melee","crit","ranged","r_crit","ws","ja","spell","mb","spike","sc","add"}

-- Load other addon modules (lua files)
require 'utility'
require 'retrieval'
require 'display'
require 'action_parse'
require 'report'
require 'file_handle'

-- Register the packet listener function from action_parse.lua
ActionPacket.open_listener(parse_action_packet)
-- Initialize the UI display boxes
init_boxes()

-- Register the 'addon command' event to handle user commands (e.g., //parse ...)
windower.register_event('addon command', function(...)
    local args = {...} -- Collect all command arguments into a table
    
    -- Command: //parse report [stat] [ability] [chatmode] [target]
    if args[1] == 'report' then
		report_data(args[2],args[3],args[4],args[5])
	
    -- Command: //parse filter [action] [string] [type]
	elseif (args[1] == 'filter' or args[1] == 'f') and args[2] then
		edit_filters(args[2],args[3],args[4])
		update_texts() -- Refresh UI to show new filter status
	
    -- Command: //parse list [type]
	elseif (args[1] == 'list' or args[1] == 'l') then
		print_list(args[2])
	
    -- Command: //parse show [box_name]
	elseif (args[1] == 'show' or args[1] == 's' or args[1] == 'display' or args[1] == 'd') then
		toggle_box(args[2])
		update_texts()
	
    -- Command: //parse reset
	elseif args[1] == 'reset' then
		reset_parse()
		update_texts()
	
    -- Command: //parse pause
	elseif args[1] == 'pause' or args[1] == 'p' then
		if pause then pause=false else pause=true end
		update_texts() -- Refresh UI to show "PAUSED" status
	
    -- Command: //parse rename [original_name] [new_name]
	elseif args[1] == 'rename' and args[2] and args[3] then
        -- Basic validation for new name (alphanumeric and underscores)
		if args[3]:gsub('[%w_]','')=="" then
			renames[args[2]:gsub("^%l", string.upper)] = args[3] -- Capitalize first letter of original name
			message('Data for player/mob '..args[2]:gsub("^%l", string.upper)..' will now be indexed as '..args[3])	
			return
		end
		message('Invalid character found. You may only use alphanumeric characters or underscores.')
	
    -- Command: //parse interval [number]
	elseif args[1] == 'interval' then
		if type(tonumber(args[2]))=='number' then 
            update_tracker,update_interval = 0, tonumber(args[2]) -- Reset tracker and set new interval
        end
		message('Your current update interval is every '..update_interval..' actions.')
	
    -- Command: //parse export [file_name]
	elseif args[1] == 'export' then
		export_parse(args[2])
	
    -- Command: //parse autoexport [file_name | off]
	elseif args[1] == 'autoexport' then
		if (autoexport and not args[2]) or args[2] == 'off' then
			autoexport = nil -- Turn off autoexport
            message('Autoexport turned off.')
		else
			autoexport = args[2] or 'autoexport' -- Set filename or use 'autoexport' default
			message('Autoexport now on. Saving under file name "'..autoexport..'" every '..autoexport_interval..' recorded actions.')
		end
	
    -- Command: //parse import [file_name]
	elseif args[1] == 'import' and args[2] then
		import_parse(args[2])
		update_texts() -- Refresh UI with new merged data
    
    -- Command: //parse log
    elseif args[1] == 'log' then
        if logging then 
            logging=false 
            message('Logging has been turned off.') 
        else 
            logging=true 
            message('Logging has been turned on.') 
        end
	
    -- Command: //parse help
	elseif args[1] == 'help' then
		-- Print help messages to chat
		message('report [stat] [chatmode] : Reports stat to designated chatmode. Defaults to damage.')
		message('filter/f [add/+ | remove/- | clear/reset] [string] : Adds/removes/clears mob filter.')
		message('show/s [melee/ranged/magic/defense] : Shows/hides display box. "melee" is the default.')
		message('pause/p : Pauses/unpauses parse. When paused, data is not recorded.')
		message('reset :  Resets parse.')
		message('rename [player name] [new name] : Renames a player or monster for NEW incoming data.')
		message('import/export [file name] : Imports/exports an XML file to/from database. Only filtered monsters are exported.')
		message('autoexport [file name] : Automatically exports an XML file every '..autoexport_interval..' recorded actions.')
        message('log : Toggles logging feature.')
		message('list/l [mobs/players] : Lists the mobs and players currently in the database. "mobs" is the default.')
        message('interval [number] :  Defines how many actions it takes before displays are updated.')
	
    -- Default case for unknown commands
	else
		message('That command was not found. Use //parse help for a list of commands.')
	end
end )

-- Table of buff IDs to track for special indexing
tracked_buffs = {
	[403] = "Reprisal",
	[478] = "Palisade",
	[570] = "Battuta",
	[405] = "Retaliation"
}

-- Event listener for when the player gains a buff
windower.register_event('gain buff', function(id)
	if tracked_buffs[id] then
		buffs[tracked_buffs[id]] = true -- Set buff state to true
	end
end )

-- Event listener for when the player loses a buff
windower.register_event('lose buff', function(id)
	if tracked_buffs[id] then
		buffs[tracked_buffs[id]] = false 
	end
end )

-- Event listener for when the player changes equipment
windower.register_event('equip change', function(new_id, new_slot, old_id, old_slot)
	-- Check if the 'sub' slot (slot 1) was changed
    if new_slot == 1 then
		if new_id == 0 then
			-- Sub slot is now empty
			buffs.current_shield = nil
		else
			-- Get item info from resources
			local item_info = res.items[new_id]
			if item_info then
				buffs.current_shield = item_info.english:sub(1, 3) -- Cache first 3 letters
			else
				buffs.current_shield = nil -- Item not found in resources
			end
		end
	end
end)

-- Helper function to get the 'type' (e.g., 'defense', 'melee', 'category') of a given stat name
-- (Optimized to use the fast lookup map)
function get_stat_type(stat)
	return stat_to_type_map[stat] or 'unknown' -- Use the map, fallback to 'unknown'
end

-- Resets the main database table to be empty
function reset_parse()
	database = {}
	actor_name_cache = {}
	spell_name_cache = {}
    message('Parse data has been reset.')
end

-- Toggles the visibility of a specified display box
function toggle_box(box_name)
	if not box_name then
		box_name = 'melee' -- Default to 'melee' box if none specified
	end
	
	if text_box[box_name] then -- Check if the box object exists
		if settings.display[box_name].visible then
			text_box[box_name]:hide()
			settings.display[box_name].visible = false
		else
			text_box[box_name]:show()
			settings.display[box_name].visible = true
		end
	else
		message('That display was not found. Display names are: melee, defense, ranged, magic.')
	end
end

-- Adds, removes, or clears filters for mobs or players
function edit_filters(filter_action,str,filter_type)
	-- Default to 'mob' filter if type invalid or not specified
	if not filter_type or not filters[filter_type] then
		filter_type = 'mob'
	end
	
    -- Add a filter
	if filter_action=='add' or filter_action=="+" then
		if not str then message("Please provide string to add to filters.") return end
		filters[filter_type]:add(str)
		message('"'..str..'" has been added to '..filter_type..' filters.')
    -- Remove a filter
	elseif filter_action=='remove' or filter_action=="-" then
		if not str then message("Please provide string to remove from filters.") return end
		filters[filter_type]:remove(str)
		message('"'..str..'" has been removed from '..filter_type..' filters.')
    -- Clear all filters of that type
	elseif filter_action=='clear' or filter_action=="reset" then
		filters[filter_type] = S{} -- Reset the filter set to be empty
		message(filter_type..' filters have been cleared.')
	end	
end

-- Gets a string representation of the currently active filters (for UI display)
function get_filters()
	local text = ""
	if filters['mob'] and filters['mob']:tostring()~="{}" then
		text = text .. ('Monsters: ' .. filters['mob']:tostring())
	end
	if filters['player'] and filters['player']:tostring()~="{}" then
		text = text .. ('\nPlayers: ' .. filters['player']:tostring())
	end
	return text
end

-- Prints a list of all tracked mobs or players to the chat log
function print_list(list_type) 
	-- Handle default and abbreviated list types
	if not list_type or list_type=="monsters" or list_type=="m" then 
		list_type="mobs" 
	elseif list_type=="p" then
		list_type="players"
	end
	
	local lst = S{}
	if list_type=='mobs' then
		lst = get_mobs() -- From retrieval.lua
	elseif list_type=='players' then
		lst = get_players() -- From retrieval.lua
	else
		message('List type not found. Valid list types: mobs, players')
		return
	end
	
	if lst:length()==0 then message('No data found. Nothing to list!') return end
	
	lst['n'] = nil -- Remove the 'n' (count) field from the Set
	local msg = ""
	-- Concatenate all names into a single string
	for __,i in pairs(lst) do
		msg = msg .. i .. ', '
	end
	
	msg = msg:slice(1,#msg-2) -- Remove the trailing comma and space
	
	-- Prepare the string to be split into multiple lines if it's too long (from report.lua)
	msg = prepare_string(msg,100)
	msg['n'] = nil
	
	-- Print each line
	for i,line in pairs(msg) do
		message(line)
	end
end

-- Checks if a given name passes the current filters for that type
-- Returns true if the name should be included, false if it should be filtered out
function check_filters(filter_type,mob_name)
	-- If no filters of this type exist, all names pass
	if not filters[filter_type] or filters[filter_type]:tostring()=="{}" then
		return true
	end

	local response = false -- Default to not matching
	local only_excludes = true -- Flag to track if *only* exclusion filters exist
	
	for v,__ in pairs(filters[filter_type]) do
		if v:lower():startswith('!^') then -- Handle exact exclusion (e.g., !^Schah)
			if v:lower():gsub('%!',''):gsub('%^','')==mob_name:lower() then 
				return false -- Exact exclusion match, immediately filter out
			end
        elseif v:lower():startswith('!') then -- Handle wildcard exclusion (e.g., !Schah)
			if string.find(mob_name:lower(),v:lower():gsub('%!','')) then 
				return false -- Wildcard exclusion match, immediately filter out
			end
		elseif v:lower():startswith('^') then -- Handle exact inclusion (e.g., ^Schah)
			if v:lower():gsub('%^','')==mob_name:lower() then
				response = true -- It's a match
			end
			only_excludes = false -- An inclusion filter was found
		elseif string.find(mob_name:lower(),v:lower()) then -- Handle wildcard inclusion (e.g., Schah)
			response = true -- It's a match
			only_excludes = false -- An inclusion filter was found
		else
			only_excludes = false -- This filter was an inclusion filter, but it didn't match
		end
	end
	
    -- If no inclusion filters were found (only exclusions), and the mob wasn't excluded,
    -- then it should be included.
	if not response and only_excludes then
		response = true
	end
	
	return response
end

-- Register a callback function with the config system
-- This will loop the update_texts function based on the settings.update_interval
config.register(settings, function(settings)
    update_texts:loop(settings.update_interval)
end)
