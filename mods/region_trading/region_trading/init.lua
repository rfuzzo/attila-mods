-- Region trading: entry point, required by campaigns/<campaign>/mods/region_trading/scripting.lua.

local rt = require("region_trading/core");
local maga = require("region_trading/compat/maga");

rt.log("version %s loading", rt.version);

maga.disable();

-- Smoke test: what the mod will build on, once the game model exists.
rt.cm():register_first_tick_callback(function()
	local world = rt.world();
	local player = rt.cm():get_local_faction();
	rt.log("first tick: player %s, %d regions in the world, %d own, %d factions",
		player,
		world:region_manager():region_list():num_items(),
		world:faction_by_key(player):region_list():num_items(),
		world:faction_list():num_items());
end);
