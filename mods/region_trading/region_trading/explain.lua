-- Console helper: region_trading.explain(region_key[, faction_key[, other_key]]) -> what the region is worth to a
-- faction (default: its owner) in a deal with `other_key` (default: you), and the parts of that value, as the AI sees
-- it. Also logged.

local rt = require("region_trading/core");
local value = require("region_trading/value");

local function number(v)
	if type(v) ~= "number" then return tostring(v) end;
	return math.abs(v) < 5 and string.format("%.2f", v) or string.format("%d", math.floor(v + 0.5));
end;

return function(region_key, faction_key, other_key)
	faction_key = faction_key or rt.world():region_manager():region_by_key(region_key):owning_faction():name();
	other_key = other_key or rt.cm():get_local_faction();
	local total, parts = value.of(region_key, faction_key, other_key);
	local out = {};
	for k, v in pairs(parts) do
		if k ~= "formula" then table.insert(out, k .. " " .. number(v)) end;
	end;
	table.sort(out);
	local text = string.format("%s for %s: %d gold = %s\n    parts: %s", rt.region_name(region_key), faction_key, total,
		parts.formula, table.concat(out, ", "));
	rt.log("%s", text);
	return text;
end;
