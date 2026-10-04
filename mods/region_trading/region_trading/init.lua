-- Region trading: entry point, required by campaigns/<campaign>/mods/region_trading/scripting.lua.

local rt = require("region_trading/core");
local maga = require("region_trading/compat/maga");
local explain = require("region_trading/explain");
local diplomacy = require("region_trading/ui/diplomacy");
local panel = require("region_trading/ui/panel");

rt.log("version %s loading", rt.version);

maga.disable();

-- For the console: region_trading.explain(region_key, ai_key[, kind[, ai_region_key]])
region_trading = { explain = explain, rt = rt, diplomacy = diplomacy, panel = panel };

-- Smoke test: what the mod will build on, once the game model exists.
rt.cm():register_first_tick_callback(function()
	local world = rt.world();
	local player = rt.cm():get_local_faction();
	rt.log("first tick: player %s, %d regions in the world, %d own, %d factions",
		player,
		world:region_manager():region_list():num_items(),
		world:faction_by_key(player):region_list():num_items(),
		world:faction_list():num_items());

	if not twase then
		rt.log("TWASE Lua API not available, region trading needs TWASE with the twase table");
		return;
	end;
	rt.log("TWASE %s Lua API found", twase.version);
end);
