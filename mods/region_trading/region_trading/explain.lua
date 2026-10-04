-- Console helper: region_trading.explain(region_key, ai_key[, kind[, ai_region_key]]) logs and returns
-- how the AI would value a deal. Without `kind` it shows all of them.

local rt = require("region_trading/core");
local deal = require("region_trading/deal");

local function fmt(n) return n and string.format("%d", math.floor(n + 0.5)) or "-" end;

local function parts_text(parts)
	local out = {};
	for k, v in pairs(parts or {}) do
		table.insert(out, string.format("%s %s", k, type(v) == "number" and (math.abs(v) < 5 and string.format("%.2f", v) or fmt(v)) or tostring(v)));
	end;
	table.sort(out);
	return table.concat(out, ", ");
end;

return function(region_key, ai_key, kind, ai_region_key)
	local player = rt.cm():get_local_faction();
	local lines = {};
	local function line(...) local s = string.format(...); table.insert(lines, s); rt.log("%s", s) end;

	local ok, reason = deal.can_trade_with(player, ai_key);
	if not ok then line("can't trade with %s: %s", ai_key, reason) end;
	ok, reason = deal.can_trade_region(region_key, player);
	if not ok then line("can't trade %s: %s", region_key, reason) end;

	local kinds = kind and { kind } or { "money", "payments", "troops", "swap" };
	for _, k in ipairs(kinds) do
		local swap_region = ai_region_key;
		if k == "swap" and not swap_region then
			-- the AI's first tradable region, as an example
			local regions = rt.world():faction_by_key(ai_key):region_list();
			for i = 0, regions:num_items() - 1 do
				if deal.can_trade_region(regions:item_at(i):name(), ai_key) then swap_region = regions:item_at(i):name(); break end;
			end;
		end;
		if k ~= "swap" or swap_region then
			local r = deal.evaluate({ player = player, ai = ai_key, region = region_key, kind = k, ai_region = swap_region });
			line("%s %s for %s -> %s: score %s (%s, %s) | value %s | price %s%s | relationship %s",
				k, rt.region_name(region_key), swap_region and rt.region_name(swap_region) or "", ai_key,
				fmt(r.score), r.band, r.accept and "accepts" or "refuses", fmt(r.value),
				fmt(r.price or r.ai_region_value), r.per_turn and (" (" .. r.per_turn .. "/turn)") or (r.units and (" (" .. #r.units .. " units)") or ""),
				fmt(r.relationship));
			line("    value: %s | relationship: %s%s", parts_text(r.parts), parts_text(r.relationship_parts),
				r.units and (" | units: " .. table.concat(r.units, ", ")) or "");
		end;
	end;
	return table.concat(lines, "\n");
end;
