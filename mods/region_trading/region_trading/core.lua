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

return rt;
