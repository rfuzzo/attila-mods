-- Console helper: region_trading.explain(region_key[, faction_key]) -> what the region is worth to a faction (default:
-- its owner) and the parts of that value, as the AI sees it in a deal. Also logged.

local rt = require("region_trading/core");
local value = require("region_trading/value");

local function number(v)
	if type(v) ~= "number" then return tostring(v) end;
	return math.abs(v) < 5 and string.format("%.2f", v) or string.format("%d", math.floor(v + 0.5));
end;

return function(region_key, faction_key)
	faction_key = faction_key or rt.world():region_manager():region_by_key(region_key):owning_faction():name();
	local total, parts = value.of(region_key, faction_key);
	local out = {};
	for k, v in pairs(parts) do table.insert(out, k .. " " .. number(v)) end;
	table.sort(out);
	local text = string.format("%s for %s: %d gold (%s)", rt.region_name(region_key), faction_key, total, table.concat(out, ", "));
	rt.log("%s", text);
	return text;
end;
