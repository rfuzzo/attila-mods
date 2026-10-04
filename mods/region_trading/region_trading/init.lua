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

	if not twase then
		rt.log("TWASE Lua API not available");
		return;
	end;

	-- Attitudes in both directions for a few factions, to compare with the diplomacy screen.
	rt.log("TWASE %s: attitudes (them -> player / player -> them)", twase.version);
	local factions = world:faction_list();
	local shown = 0;
	for i = 0, factions:num_items() - 1 do
		local key = factions:item_at(i):name();
		local them = rt.attitude(key, player);
		if key ~= player and them and them ~= 0 and shown < 10 then
			rt.log("  %s: %s / %s", key, tostring(them), tostring(rt.attitude(player, key)));
			shown = shown + 1;
		end;
	end;

	rt.log("localise: %s / %s / missing key -> %s", tostring(rt.localise("factions_screen_name_" .. player)),
		tostring(rt.localise("campaign_localised_strings_string_gdp_farming")), tostring(rt.localise("no_such_loc_key")));

	-- Wealth of the player's regions, to compare with the province panel.
	local regions = world:faction_by_key(player):region_list();
	for i = 0, regions:num_items() - 1 do
		local key = regions:item_at(i):name();
		local total, breakdown = rt.region_wealth(key);
		local parts = {};
		for category, values in pairs(breakdown or {}) do
			table.insert(parts, string.format("%s %d", category, values.total));
		end;
		table.sort(parts);
		rt.log("  %s (%s): wealth %s (%s)", rt.region_name(key), tostring(rt.province_name(rt.province(key))), tostring(total), table.concat(parts, ", "));
	end;
end);
