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

return rt;
