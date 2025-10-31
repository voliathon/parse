--[[
    Copyright (c) 2016-2023, Flippant
    Copyright (c) 2025, Voliathon
    All rights reserved.

    This source code is licensed under the BSD-style license found in the
    LICENSE.md file in the root directory of this source tree.
]]

---
-- Prints a formatted message to the user's chat log with the addon's prefix.
-- @param message The string message to print.
--
function message(message)
	windower.add_to_chat(messageColor,'PARSE: '..message)
end

---
-- Prints a debug message to the chat log, only if debug mode is enabled in settings.
-- @param message The string message to print.
--
function debug(message)
	if settings.debug then
		windower.add_to_chat(messageColor,'PARSE DEBUG: '..message)
	end
end

---
-- Recursively merges the contents of table `t2` into table `t1`.
-- If keys conflict:
--   - Numbers are added together.
--   - Tables are merged recursively.
--   - Other values in `t2` will not overwrite `t1` (based on current logic).
-- This modifies `t1` in place.
-- @param t1 The target table to merge into.
-- @param t2 The source table to merge from.
--
function merge_tables(t1,t2)
	for key,value in pairs(t2) do
		if not t1[key] then -- Key doesn't exist in target, so just add it.
			t1[key] = value
		else -- Key exists, need to merge.
			if type(value)=='number' and type(t1[key])=='number' then -- If both are numbers, add them.
				t1[key] = t1[key] + value
			elseif type(value)=='table' and type(t1[key])=='table' then -- If both are tables, recurse.
				merge_tables(t1[key],value)
			-- Note: If types mismatch (e.g., table and number), no action is taken.
			end
		end
	end
end

---
-- Performs a deep copy of a table, handling nested tables and table references.
-- @param obj The table to copy.
-- @param seen An optional table to track objects already copied (for handling cycles).
-- @return A new table that is a deep copy of `obj`.
--
function copy(obj, seen)
    -- If it's not a table, just return the value directly.
	if type(obj) ~= 'table' then return obj end
    -- If this table has already been seen (part of a cycle), return the existing copy.
	if seen and seen[obj] then return seen[obj] end
	
    -- Initialize the 'seen' table on the first call.
	local s = seen or {}
    -- Create the new table, preserving the original's metatable.
	local res = setmetatable({}, getmetatable(obj))
	
    -- Store the new table in 'seen' to handle cycles.
	s[obj] = res
	
    -- Iterate over all key-value pairs and recursively copy them.
	for k, v in pairs(obj) do 
        res[copy(k, s)] = copy(v, s) 
    end
	
	return res
end