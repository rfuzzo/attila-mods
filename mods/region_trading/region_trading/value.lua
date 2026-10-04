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

-- value.of(region_key, faction_key) -> total, parts
-- The region's value for `faction` as its (new or current) owner: (net income x turns + building share) x the factors
-- (province, enclave, religion, unrest), which multiply. `parts` lists every part for display.
function value.of(region_key, faction_key)
	local region = rt.world():region_manager():region_by_key(region_key);
	local faction = rt.world():faction_by_key(faction_key);
	local parts = {};

	local wealth, upkeep, buildings = economy(region);
	local income = math.max(wealth - upkeep, 0) * config.income_turns;
	local base = income + buildings * config.building_share;
	parts.wealth, parts.upkeep, parts.income_value = wealth, upkeep, income;
	parts.building_value = buildings * config.building_share;

	local factor = 1;

	if owns_rest_of_province(faction_key, region) then
		factor = factor * (1 + config.province_complete_bonus);
		parts.province_complete = config.province_complete_bonus;
	end;

	-- An enclave only matters for a new owner; the current owner borders itself trivially.
	if region:owning_faction():name() ~= faction_key and not borders(faction_key, region) then
		factor = factor * (1 - config.enclave_malus);
		parts.enclave = -config.enclave_malus;
	end;

	local share = region:majority_religion_percentage() / 100;
	local religion = config.religion_factor * share;
	if region:majority_religion() ~= faction:state_religion() then religion = -religion end;
	factor = factor * (1 + religion);
	parts.religion = religion;

	local order = region:public_order();
	if order < 0 then
		local unrest = math.max(order * config.unrest_per_point, config.unrest_floor - 1);
		factor = factor * (1 + unrest);
		parts.unrest = unrest;
	end;

	local total = math.max(base * factor, config.min_value);
	parts.factor = factor;
	return math.floor(total + 0.5), parts;
end;

return value;
