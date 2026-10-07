-- Shared module table and helpers.

local rt = {};

rt.version = "0.1.0";

function rt.log(fmt, ...)
	print("[region_trading] " .. string.format(fmt, ...));
end;

-- The campaign manager instance. The global `cm` isn't visible in every Lua context, get_cm() is.
function rt.cm()
	return get_cm();
end;

function rt.world()
	return get_cm():model():world();
end;

-- a's attitude towards b (faction keys), as the diplomacy screen shows it. nil without TWASE's Lua API.
function rt.attitude(a, b)
	if not (twase and twase.faction_attitude) then return nil end;
	local world = rt.world();
	return twase.faction_attitude(world:faction_by_key(a), world:faction_by_key(b));
end;

-- The region's wealth (GDP before tax) and its breakdown { <category> = { base, total, bonus_percent } }.
-- nil without TWASE's Lua API.
function rt.region_wealth(key)
	if not (twase and twase.region_wealth) then return nil end;
	return twase.region_wealth(rt.world():region_manager():region_by_key(key));
end;

-- The province key of a region. nil without TWASE's Lua API.
function rt.province(key)
	if not (twase and twase.region_province) then return nil end;
	return twase.region_province(rt.world():region_manager():region_by_key(key));
end;

-- Building level and unit records from the loaded DB (game and mods merged). nil without TWASE.
function rt.building_level(key)
	return twase and twase.building_level and twase.building_level(key) or nil;
end;

function rt.unit(key)
	return twase and twase.unit and twase.unit(key) or nil;
end;

-- A faction's own levy pool { [group] = { unit, max_count, ... } } (the units of that people others can levy), nil if it
-- has none or without TWASE.
function rt.levy_pool(faction_key)
	return twase and twase.levy_pool and twase.levy_pool(faction_key) or nil;
end;

-- Localised text of a loc key, nil if missing or without TWASE.
function rt.localise(key)
	return twase and twase.localise and twase.localise(key) or nil;
end;

-- Display names, falling back to the key.
function rt.region_name(key)
	return rt.localise("regions_onscreen_" .. key) or key;
end;

function rt.province_name(key)
	return key and (rt.localise("provinces_onscreen_" .. key) or key);
end;

return rt;
