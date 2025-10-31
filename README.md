# parse v2.0.1
An FFXI Parser Addon for Windower. This addon parses both offensive and defensive data, stores WS/JAs/spells data by individual spell, tracks additional information like multihit rates, and provides the ability to export/import data in XML format and log individually recorded data.

### Commands

`//parse pause` or `//p p`
Pauses/unpauses the parser. When paused, new data is not recorded.

`//parse reset`
Resets all currently stored parse data.

`//parse report [stat] [ability name] [chatmode] [target]`
Reports stat to the specified chatmode.
* If `[stat]` is not provided, it defaults to 'damage'.
* If `[ability name]` is provided (for ws, ja, spell, etc.), it will report only that ability. Must be an exact match (case-sensitive, use `_` for spaces, omit special characters).
* If `[chatmode]` is not provided, it prints to your personal chatlog.
* Valid chatmodes: `p` (party), `s` (say), `l` (linkshell), `l2` (linkshell2), `t [target]` (tell), `echo` (echo to chat).
* **To send a report to party chat, use `p` as the chatmode.**
    * Example (report total damage to party): `//parse report damage p`
    * Example (report WS stats to party): `//parse report ws p`
    * Shortcut (report default damage to party): `//parse report p`

`//parse show [box_name]` or `//p s [box_name]`
Toggles the visibility of a display box.
* Also accepts `//parse d` or `//parse display`.
* Valid box names: `melee`, `ranged`, `magic`, `defense`.
* If no `[box_name]` is provided, it defaults to `melee`.

`//parse filter [action] [string] [type]` or `//p f [action] [string] [type]`
Adds, removes, or clears filters for mobs or players.
* `[action]`: `add` (or `+`), `remove` (or `-`), `clear` (or `reset`).
* `[string]`: The text to filter for (e.g., `Schah`). Not case-sensitive. Use `_` for spaces.
* `[type]`: `mob` (default) or `player`. This allows you to filter out specific players.
* **Filter String Handling:**
    * `!schah`: Excludes any matches containing "schah".
    * `^schah`: Includes only exact matches for "schah".
    * `!^schah`: Excludes only exact matches for "schah".

`//parse list [type]` or `//p l [type]`
Lists all mobs or players currently registered in the database.
* `[type]`: `mobs` (default) or `players`.

`//parse rename [original_name] [new_name]`
Assigns a player or monster a new name for all *future* incoming data.
* Always use the original name when renaming (e.g., `//p rename Kirin Kirin2`, then `//p rename Kirin Kirin3`).
* Replace spaces with `_` and omit special characters.

`//parse export [file_name]`
Exports the current parse database to an XML file in the `parse/data/export/` folder.
* If filters are active, only data matching the filters will be exported.

`//parse import [file_name]`
Imports parse data from an XML file. The imported data will be merged with any data currently in the addon.

`//parse autoexport [file_name | off]`
Toggles auto-exporting the database every 500 actions (by default).
* Use `//p autoexport [file_name]` to turn on.
* Use `//p autoexport` or `//p autoexport off` to turn off.

`//parse log`
Toggles the individual action logging feature on or off.

`//parse interval [number]`
Changes the update interval (in seconds) for the display boxes.

`//parse help`
Displays a list of available commands in the chatlog.

### Display

Up to four draggable, customizable UIs can appear on screen: "melee", "ranged", "magic", and "defense." The visibility of each can be toggled, and the default appearance can be changed in the settings file.

Despite their titles, the stats shown on each display are completely customizable in the settings. Any recorded stat can be added, along with the data type (total damage, average, percentage, tally).

### Filtering

Mob and player filters can be added/removed to filter data. Filters are not case-sensitive. Multiple filters may be added. Special characters in names are handled: spaces are replaced with underscores, and apostrophes are removed.

If a substring begins with `!` it will exclude any monsters with that substring. If it begins with `^` it will only include exact matches.

### Report

The report feature can be used to output data to any chat mode (including tells) or your personal chatlog. All stats can be reported. When reporting weaponskills, job abilities, and spells, results are shown for both the entire category and each individual ability/spell.

### Renaming

Both players and monsters can be "renamed" for new, incoming data. This can help distinguish between multiple enemies of the same name or assist in testing. Always rename using the original name.

### Special Indexing

Special features are available to assist with parsing defensive stats. These can be enabled/disabled in the settings and only work for the player's own character.

* **index_shield:** Indexing by subweapon/shield, represented by the first three letters.
* **index_reprisal:** Indexing by Reprisal, represented with "R" when on.
* **index_palisade:** Indexing by Palisade, represented with "P" when on.
* **index_battuta:** Indexing by Battuta, represented with "B" when on.

### Export/Import

Parses can be exported to and imported from XML format. When importing, the imported data is merged with any current data.

Data is saved according to active mob filters. Keep this in mind when exporting, as any non-included monsters will not be saved.

You can also toggle auto-export, which automatically saves the database after a set of actions (default 500).

### Logging

As opposed to `export` (which saves the aggregated database), `logging` records each individual action's parameters to a file (e.g., how much *each* Rudra's Storm did).

Logging is automatic for any player listed in the `logger` option of your settings. This is case-sensitive, and a wildcard (`*`) is permitted (e.g., `Voliat*`) to log all data for a character, including their special-indexed defensive data.

Data is saved to `/parse/data/log/`, in folders named after the *recording* player.

---

## Code Optimizations (v2.0.1)

This version includes a major backend refactor to fix critical bugs and significantly improve performance.

* **Critical Data Fix:** Fixed a bug where defensive buffs (Reprisal, Palisade, etc.) would never turn off, ensuring special-indexed defensive data is now logged accurately.
* **Performance Overhaul (UI & Reports):** Eliminated a severe lag bottleneck where the UI and `//parse report` command would re-calculate the entire parse database on every update. Both features now use a pre-compiled data table and will remain fast and responsive even during long, data-heavy fights.
* **"Hot Path" Optimization (Actor Caching):** Optimized the core packet-parsing loop by implementing a cache for actor and mob names. This converts thousands of slow, repetitive name lookups into instant cache hits, significantly reducing CPU load during combat.
* **"Hot Path" Optimization (Ability Caching):** Added a cache for spell, ability, and weapon skill names. This removes redundant resource lookups and string sanitization from the most high-frequency part of the code.
* **"Hot Path" Optimization (Stat Lookup):** Replaced the `get_stat_type()` function's loop with a pre-built map, converting it into an instant O(1) lookup.
* **Efficiency & Bugfix (Report Command):** Refactored the `report` command to build its output strings more efficiently using `table.concat`. This also fixed a formatting bug where the `damage` report failed to show players on separate lines.
* **Efficiency (File Logging):** Optimized the `log_data` function to cache file handles, significantly reducing slow disk I/O operations during combat.
