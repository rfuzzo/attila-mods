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

return rt;
