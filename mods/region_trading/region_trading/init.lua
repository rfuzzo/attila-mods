-- Region trading: entry point, required by campaigns/<campaign>/mods/region_trading/scripting.lua.

local rt = require("region_trading/core");
local maga = require("region_trading/compat/maga");
local explain = require("region_trading/explain");
local federates = require("region_trading/federates");
local governor = require("region_trading/governor");
local value = require("region_trading/value");

rt.log("version %s loading", rt.version);

maga.disable();

-- For the console: region_trading.explain(region_key[, faction_key[, other_key]]),
-- region_trading.value.of(region_key, faction_key, other_key), region_trading.federates.offer(ai_key, player_key, { region_keys })
region_trading = { explain = explain, federates = federates, rt = rt, value = value };

-- The engine's region deals (its "Gift Region", widened by TWASE): the AI values a region like this much gold, and
-- governors survive the transfer of their province capital.
local handlers = {
	-- other_key: the other side of the deal (nil from TWASE builds before 2026-10-07)
	value = function(region_key, faction_key, other_key)
		local ok, gold, parts = pcall(value.of, region_key, faction_key, other_key);
		if not ok then
			rt.log("value of %s for %s failed: %s", tostring(region_key), tostring(faction_key), tostring(gold));
			return 0;
		end;
		rt.log("value of %s for %s (with %s): %s", region_key, faction_key, tostring(other_key), parts.formula);
		return gold;
	end,
	transfer = function(phase, region_key, to)
		local ok, err = pcall(governor.on_transfer, phase, region_key, to);
		if not ok then rt.log("transfer handler (%s %s) failed: %s", phase, region_key, tostring(err)) end;
	end,
};
if twase and twase.enable_region_trading then
	twase.enable_region_trading(handlers);
elseif twase and twase.dev_native_region_trading then
	-- TEMPORARY (remove once nobody runs a TWASE build from before 2026-10-07): the earlier dev API
	twase.dev_native_region_trading(true);
	twase.set_region_value_handler(handlers.value);
	if twase.set_region_transfer_handler then twase.set_region_transfer_handler(handlers.transfer) end;
else
	rt.log("needs TWASE with twase.enable_region_trading, region trading stays off");
end;

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
