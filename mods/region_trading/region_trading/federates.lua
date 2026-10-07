-- Federates (a foedus): troops a people gives you for land you cede to it. See docs/DESIGN-federates.md.

local rt = require("region_trading/core");
local config = require("region_trading/config");
local value = require("region_trading/value");

local federates = {};

-- running foedera by the AI faction's key (saved with the game, see step 4 of the plan)
federates.active = {};

-- A field army: led by a general. A settlement's garrison is an army too, led by a "colonel" (has_garrison_residence
-- doesn't tell them apart: it's true for any army inside a settlement).
local function is_field_army(force)
	return force:is_army() and force:has_general() and force:general_character():character_type("general");
end;

-- Your army that concludes the foedus: a general in one of the ceded regions or next to one, the most free slots.
-- -> force, free slots (nil if there's none)
local function negotiating_army(player_key, region_keys)
	local near = {};
	local regions = rt.world():region_manager();
	for _, key in ipairs(region_keys) do
		near[key] = true;
		local adjacent = regions:region_by_key(key):adjacent_region_list();
		for i = 0, adjacent:num_items() - 1 do near[adjacent:item_at(i):name()] = true end;
	end;

	local best, best_free = nil, 0;
	local forces = rt.world():faction_by_key(player_key):military_force_list();
	for i = 0, forces:num_items() - 1 do
		local force = forces:item_at(i);
		-- field armies only: a garrison stays with the settlement
		if is_field_army(force) then
			local general = force:general_character();
			if general:has_region() and near[general:region():name()] then
				local free = config.army_size - force:unit_list():num_items();
				if not best or free > best_free then best, best_free = force, free end;
			end;
		end;
	end;
	return best, best_free;
end;

-- The AI's own levy pool (that people's warriors, the units others levy from it), each type at most its pool count
local function pool_types(ai_key)
	local seen, types = {}, {};
	for _, group in pairs(rt.levy_pool(ai_key) or {}) do
		local record = group.unit and rt.unit(group.unit);
		if record and record.recruitment_cost > 0 and not seen[group.unit] then
			seen[group.unit] = true;
			table.insert(types, { key = group.unit, cost = record.recruitment_cost, max = group.max_count });
		end;
	end;
	return types;
end;

-- The AI's land unit types, from its field armies (no garrisons, no generals' bodyguards)
local function army_types(ai_key)
	local seen, types = {}, {};
	local forces = rt.world():faction_by_key(ai_key):military_force_list();
	for i = 0, forces:num_items() - 1 do
		local force = forces:item_at(i);
		if is_field_army(force) then
			local units = force:unit_list();
			for j = 0, units:num_items() - 1 do
				local unit = units:item_at(j);
				local key = unit:unit_key();
				-- the general's bodyguard is the only unit with a unit commander
				if unit:is_land_unit() and not unit:has_unit_commander() and not seen[key] then
					local record = rt.unit(key);
					if record and record.recruitment_cost > 0 then
						seen[key] = true;
						table.insert(types, { key = key, cost = record.recruitment_cost });
					end;
				end;
			end;
		end;
	end;
	return types;
end;

-- The unit types the AI gives: its levy pool where it has one, else its army's types. Most expensive first; the most
-- expensive quarter of them are its elite.
local function unit_types(ai_key)
	local types = pool_types(ai_key);
	if #types == 0 then types = army_types(ai_key) end;
	table.sort(types, function(a, b) return a.cost > b.cost end);
	local elite = math.floor(#types * config.federates_elite_share);
	for i, t in ipairs(types) do t.elite = i <= elite end;
	return types;
end;

-- Fill the budget, cycling through the AI's unit types so the federates are a mixed force, with at most
-- config.federates_max_elite elite units and each type at most its `max` (pool types). -> { unit keys }, total cost
local function pick_units(types, budget, slots)
	local chosen, total, elite, count = {}, 0, 0, {};
	local added = true;
	while added and #chosen < slots do
		added = false;
		for _, t in ipairs(types) do
			if #chosen < slots and total + t.cost <= budget and (not t.elite or elite < config.federates_max_elite)
					and (not t.max or (count[t.key] or 0) < t.max) then
				table.insert(chosen, t.key);
				total = total + t.cost;
				count[t.key] = (count[t.key] or 0) + 1;
				if t.elite then elite = elite + 1 end;
				added = true;
			end;
		end;
	end;
	return chosen, total;
end;

-- federates.offer(ai_key, player_key, region_keys) -> offer or nil, short reason, reason
-- What `ai_key` gives as federates for the regions `region_keys` you cede to it:
-- offer = { units = { unit keys }, cost = recruitment cost in gold, force_cqi, general_cqi, value, budget }
function federates.offer(ai_key, player_key, region_keys)
	if #region_keys == 0 then return nil, "give land", "Tick land of yours to cede to them." end;
	if federates.active[ai_key] then return nil, "foedus runs", "A foedus with them is still in force." end;

	local force, free = negotiating_army(player_key, region_keys);
	if not force then return nil, "no general", "Needs one of your generals with an army in or next to the land you cede." end;
	if free <= 0 then return nil, "army full", "Your general's army is full." end;

	local land = 0;
	for _, key in ipairs(region_keys) do land = land + value.of(key, ai_key, player_key) end;
	local budget = math.max(land, 0) * config.federates_share;

	local units, cost = pick_units(unit_types(ai_key), budget, free);
	if #units == 0 then return nil, "too little", "The land isn't worth any of their units." end;

	return {
		units = units,
		cost = cost,
		force_cqi = force:command_queue_index(),
		general_cqi = force:general_character():cqi(),
		value = land,
		budget = budget,
	};
end;

-- units in a faction's field armies (its land strength; garrisons don't march)
local function strength(faction)
	local units = 0;
	local forces = faction:military_force_list();
	for i = 0, forces:num_items() - 1 do
		local force = forces:item_at(i);
		if is_field_army(force) then units = units + force:unit_list():num_items() end;
	end;
	return units;
end;

-- federates.willingness(ai_key, player_key) -> points, parts
-- How willing `ai_key` is to become `player_key`'s federates, in the game's deal score points (±4 is the likelihood
-- band). Peoples under pressure facing a stronger partner accept; states don't. See docs/DESIGN-federates.md.
function federates.willingness(ai_key, player_key)
	local world = rt.world();
	local ai, player = world:faction_by_key(ai_key), world:faction_by_key(player_key);
	local w = config.willingness;
	local parts, total = {}, 0;
	local function add(name, points) if points ~= 0 then parts[name] = points; total = total + points end end;

	local culture = ai:culture();
	if culture == "att_cult_roman" or culture == "att_cult_eastern" then add("a state", w.state) end;
	if ai:is_horde() then
		add("landless", w.horde);
	else
		local regions = ai:region_list():num_items();
		add("land", regions <= 2 and w.little_land or (regions <= 5 and 0 or w.much_land));
	end;
	if ai:has_food_shortage() then add("hungry", w.hungry) end;
	if ai:losing_money() then add("broke", w.broke) end;

	local theirs = math.max(strength(ai), 1);
	local ratio = strength(player) / theirs;
	add("strength", ratio >= 3 and w.far_stronger or (ratio >= 1.5 and w.stronger or (ratio < 1 and w.weaker or 0)));
	if ai:at_war_with(player) then add("war", ratio >= 3 and w.war_far_stronger or w.war) end;

	local attitude = rt.attitude(ai_key, player_key);
	if attitude then add("attitude", math.max(-w.attitude_cap, math.min(w.attitude_cap, attitude / w.attitude_per_point))) end;
	if ai:allied_with(player) then add("allied", w.allied) end;
	parts.strength_ratio = ratio;
	return total, parts;
end;

-- A deal for troops around its transfer: "before" works out the warriors (the land is still yours), "after" adds them
-- to your general's army and records the foedus.
local pending = nil;

function federates.on_deal(phase, ai_key, player_key, ...)
	if phase == "before" then
		local offer, _, reason = federates.offer(ai_key, player_key, { ... });
		pending = offer;
		if not pending then rt.log("foedus with %s: no warriors (%s)", ai_key, tostring(reason)) end;
		return;
	end;
	if not pending then return end;
	for _, unit in ipairs(pending.units) do
		rt.cm():add_unit_to_force(unit, pending.force_cqi);
	end;
	federates.active[ai_key] = rt.cm():model():turn_number();
	rt.log("foedus with %s for %s: %d units to army %d: %s", ai_key, table.concat({ ... }, ", "), #pending.units,
		pending.force_cqi, table.concat(pending.units, ", "));
	pending = nil;
end;

-- running foedera, saved as "faction:turn;..."
rt.cm():register_saving_game_callback(function(context)
	local entries = {};
	for faction, turn in pairs(federates.active) do table.insert(entries, faction .. ":" .. turn) end;
	rt.cm():save_value("RegionTrading_foedera", table.concat(entries, ";"), context);
end);

rt.cm():register_loading_game_callback(function(context)
	federates.active = {};
	for faction, turn in string.gmatch(rt.cm():load_value("RegionTrading_foedera", "", context), "([^:;]+):(%d+)") do
		federates.active[faction] = tonumber(turn);
	end;
end);

return federates;
