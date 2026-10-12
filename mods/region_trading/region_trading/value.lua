-- What a region is worth to a faction, with the parts it's made of (for the UI and debugging).

local rt = require("region_trading/core");
local config = require("region_trading/config");

local value = {};

-- province key -> { region keys }, built once per session from the loaded DB
local provinces = nil;

local function province_regions(province)
	if not provinces then
		provinces = {};
		local regions = rt.world():region_manager():region_list();
		for i = 0, regions:num_items() - 1 do
			local key = regions:item_at(i):name();
			local p = rt.province(key);
			if p then
				provinces[p] = provinces[p] or {};
				table.insert(provinces[p], key);
			end;
		end;
	end;
	return provinces[province] or {};
end;

-- Net income and building value of a region, independent of who gets it.
local function economy(region)
	local wealth = rt.region_wealth(region:name()) or 0;
	local upkeep, buildings = 0, 0;
	local slots = region:slot_list();
	for i = 0, slots:num_items() - 1 do
		local slot = slots:item_at(i);
		if slot:has_building() then
			local building = slot:building();
			local record = rt.building_level(building:name());
			if record then
				upkeep = upkeep + record.upkeep_cost;
				buildings = buildings + record.create_cost * building:percent_health() / 100;
			end;
		end;
	end;
	return wealth, upkeep, buildings;
end;

-- Does `faction` own every region of the province except `except`?
local function owns_rest_of_province(faction, region)
	local province = rt.province(region:name());
	if not province then return false end;
	local manager = rt.world():region_manager();
	for _, key in ipairs(province_regions(province)) do
		if key ~= region:name() and manager:region_by_key(key):owning_faction():name() ~= faction then
			return false;
		end;
	end;
	return true;
end;

local function borders(faction, region)
	local adjacent = region:adjacent_region_list();
	for i = 0, adjacent:num_items() - 1 do
		-- abandoned regions have no owner, so name() can fail
		local ok, owner = pcall(function() return adjacent:item_at(i):owning_faction():name() end);
		if ok and owner == faction then
			return true;
		end;
	end;
	return false;
end;

-- How much `other`'s armies have the region in hand, as a factor on the owner's value: its army besieges the
-- settlement, or stands in the region at war or at peace (military access). An army next to the region doesn't count.
-- -> factor, reason (nil if no army of `other` is there)
local function leverage(region, owner, other)
	local forces = other:military_force_list();
	for i = 0, forces:num_items() - 1 do
		local force = forces:item_at(i);
		if force:is_army() and force:has_general() then
			local general = force:general_character();
			if general:has_region() and general:region():name() == region:name() then
				if region:garrison_residence():is_under_siege() then return config.leverage_siege, "siege" end;
				if owner:at_war_with(other) then return config.leverage_war, "war" end;
				return config.leverage_peace, "peace";
			end;
		end;
	end;
	return 1, nil;
end;

-- value.of(region_key, faction_key[, other_key]) -> total, parts
-- The region's value for `faction` as its new or current owner, in a deal with `other`:
--   (positive income + building share) x factors (province, enclave, religion)  + a loss  - burdens (enclave, unrest)
-- For the current owner giving it away, a positive value is raised by the reluctance to cede land and lowered by
-- `other`'s armies holding the region (leverage). It can be negative: a burden the faction is glad to be rid of.
-- `parts` lists every part for display.
function value.of(region_key, faction_key, other_key)
	local world = rt.world();
	local region = world:region_manager():region_by_key(region_key);
	local faction = world:faction_by_key(faction_key);
	local giving = region:owning_faction():name() == faction_key;
	local parts = {};

	local wealth, upkeep, buildings = economy(region);
	local income = (wealth - upkeep) * config.income_turns;
	local positive = math.max(income, 0) + buildings * config.building_share;
	local loss = math.min(income, 0); -- a region run at a loss
	parts.wealth, parts.upkeep, parts.income_value = wealth, upkeep, income;
	parts.building_value = buildings * config.building_share;

	local factor, burden = 1, 0;

	if owns_rest_of_province(faction_key, region) then
		factor = factor * (1 + config.province_complete_bonus);
		parts.province_complete = config.province_complete_bonus;
	end;

	-- An enclave only matters for a new owner; the current owner borders itself trivially. For a landless people (a
	-- horde settling, the Blemmyes) the land is all it has, not an outpost to defend.
	local landless = rt.world():faction_by_key(faction_key):region_list():num_items() == 0;
	if not giving and not landless and not borders(faction_key, region) then
		factor = factor * (1 - config.enclave_malus);
		burden = burden + config.enclave_burden;
		parts.enclave = -config.enclave_malus;
		parts.enclave_burden = config.enclave_burden;
	end;

	local share = region:majority_religion_percentage() / 100;
	local religion = config.religion_factor * share;
	local same_religion = region:majority_religion() == faction:state_religion();
	if not same_religion then religion = -religion end;
	factor = factor * (1 + religion);
	parts.religion = religion;

	local order = region:public_order();
	if order < 0 then
		parts.unrest_burden = -order * config.unrest_burden_per_point;
		burden = burden + parts.unrest_burden;
	end;

	local total = positive * factor + loss - burden;
	parts.factor = factor;

	-- the formula with its numbers, for the log
	local function n(v) return string.format("%d", math.floor(v + 0.5)) end;
	local function pct(v) return string.format("%+d %%", math.floor(v * 100 + 0.5)) end;
	local factors = {};
	if parts.province_complete then table.insert(factors, "province " .. pct(parts.province_complete)) end;
	if parts.enclave then table.insert(factors, "enclave " .. pct(parts.enclave)) end;
	table.insert(factors, "religion " .. pct(religion));
	local formula = string.format("(income %s + buildings %s) x %.2f (%s)", n(math.max(income, 0)),
		n(parts.building_value), factor, table.concat(factors, ", "));
	if loss < 0 then formula = formula .. " - loss " .. n(-loss) end;
	if burden > 0 then
		local burdens = {};
		if parts.enclave_burden then table.insert(burdens, "enclave " .. n(parts.enclave_burden)) end;
		if parts.unrest_burden then table.insert(burdens, "unrest " .. n(parts.unrest_burden)) end;
		formula = formula .. string.format(" - burdens %s (%s)", n(burden), table.concat(burdens, ", "));
	end;
	formula = formula .. " = " .. n(total);

	if giving and total > 0 then
		local reluctance = config.cession_reluctance;
		if not same_religion then reluctance = reluctance - config.reluctance_other_religion end;
		total = total * reluctance;
		parts.reluctance = reluctance;
		formula = formula .. string.format(" x reluctance %.2f", reluctance);
		if other_key then
			local lever, reason = leverage(region, faction, world:faction_by_key(other_key));
			if reason then
				total = total * lever;
				parts.leverage = lever;
				parts.leverage_by = reason;
				formula = formula .. string.format(" x leverage %.2f (%s's army, %s)", lever, other_key, reason);
			end;
		end;
		formula = formula .. " = " .. n(total);
	end;
	parts.formula = formula;

	return math.floor(total + 0.5), parts;
end;

return value;
