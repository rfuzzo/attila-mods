-- Rules (who and what can be traded) and the AI's evaluation of a deal.
-- A deal: { player = key, ai = key, region = player's region key, kind = "money" | "payments" | "troops" | "swap",
--           ai_region = AI's region key (swap only) }

local rt = require("region_trading/core");
local config = require("region_trading/config");
local value = require("region_trading/value");

local deal = {};

-- deal.can_trade_with(player, ai) -> ok, reason
function deal.can_trade_with(player_key, ai_key)
	local world = rt.world();
	local player, ai = world:faction_by_key(player_key), world:faction_by_key(ai_key);
	if player_key == ai_key then return false, "same faction" end;
	if player:is_horde() then return false, "hordes can't trade regions" end;
	if ai:is_horde() then return false, ai_key .. " is a horde" end;
	if player:at_war_with(ai) then return false, "at war" end;
	if ai:region_list():num_items() == 0 then return false, ai_key .. " has no regions" end;
	return true;
end;

-- deal.can_trade_region(region, from) -> ok, reason
function deal.can_trade_region(region_key, from_key)
	local region = rt.world():region_manager():region_by_key(region_key);
	local from = rt.world():faction_by_key(from_key);
	if region:owning_faction():name() ~= from_key then return false, "not owned by " .. from_key end;
	if from:has_home_region() and from:home_region():name() == region_key then return false, "capital" end;
	if region:garrison_residence():is_under_siege() then return false, "under siege" end;
	return true;
end;

-- The AI's relationship to the player in gold, and its parts.
local function relationship(ai_key, player_key, deal_value)
	local world = rt.world();
	local ai = world:faction_by_key(ai_key);
	local parts, total = {}, 0;

	local attitude = rt.attitude(ai_key, player_key);
	if attitude then
		local share = math.max(-config.attitude_cap, math.min(config.attitude_cap, attitude * config.attitude_share));
		parts.attitude = attitude;
		parts.attitude_value = deal_value * share;
		total = total + parts.attitude_value;
	end;
	if ai:allied_with(world:faction_by_key(player_key)) then
		parts.alliance = deal_value * config.alliance_bonus;
		total = total + parts.alliance;
	end;
	if ai:is_trading_with(world:faction_by_key(player_key)) then
		parts.trade_agreement = deal_value * config.trade_agreement_bonus;
		total = total + parts.trade_agreement;
	end;
	return total, parts;
end;

-- Units the AI can give as federates: copies of the land units in its armies, most expensive first,
-- as many as the budget and `slots` allow. -> { unit keys }, total cost
function deal.federates(ai_key, budget, slots)
	local seen, candidates = {}, {};
	local forces = rt.world():faction_by_key(ai_key):military_force_list();
	for i = 0, forces:num_items() - 1 do
		local force = forces:item_at(i);
		if force:is_army() then
			local units = force:unit_list();
			for j = 0, units:num_items() - 1 do
				local unit = units:item_at(j);
				local key = unit:unit_key();
				-- skip the general's bodyguard (the only unit with a unit commander)
				if unit:is_land_unit() and not unit:has_unit_commander() and not seen[key] then
					local record = rt.unit(key);
					if record and record.recruitment_cost > 0 then
						seen[key] = true;
						table.insert(candidates, { key = key, cost = record.recruitment_cost });
					end;
				end;
			end;
		end;
	end;
	table.sort(candidates, function(a, b) return a.cost > b.cost end);

	-- Fill the budget, cycling through the AI's unit types so the gift is a mixed force.
	local chosen, total = {}, 0;
	local added = true;
	while added and #chosen < slots do
		added = false;
		for _, unit in ipairs(candidates) do
			if #chosen < slots and total + unit.cost <= budget then
				table.insert(chosen, unit.key);
				total = total + unit.cost;
				added = true;
			end;
		end;
	end;
	return chosen, total;
end;

-- deal.evaluate(d) -> result
-- result = { score, band = "low" | "moderate" | "high", accept, price, value, ai_region_value, units, relationship, parts }
-- The AI accepts at score >= 0, like the game's own deals.
function deal.evaluate(d)
	local ai = rt.world():faction_by_key(d.ai);
	local region_value, parts = value.of(d.region, d.ai);
	local result = { value = region_value, parts = parts };

	local gain, cost = region_value, 0;
	if d.kind == "money" then
		cost = math.floor(math.min(region_value * config.money_lump_share, math.max(ai:treasury(), 0) * config.money_lump_treasury_cap));
		result.price = cost;
	elseif d.kind == "payments" then
		local per_turn = math.floor(region_value * config.money_payments_share / config.money_payments_turns);
		cost = per_turn * config.money_payments_turns;
		result.price, result.per_turn, result.turns = cost, per_turn, config.money_payments_turns;
	elseif d.kind == "troops" then
		local units, units_cost = deal.federates(d.ai, region_value * config.troops_share, d.slots or config.army_size);
		cost = units_cost;
		result.price, result.units = cost, units;
	elseif d.kind == "swap" then
		cost = value.of(d.ai_region, d.ai);
		result.ai_region_value = cost;
	end;

	local deal_value = math.max(gain, cost, 1);
	local rel, rel_parts = relationship(d.ai, d.player, deal_value);
	result.relationship, result.relationship_parts = rel, rel_parts;

	result.score = math.floor(gain - cost + rel + 0.5);
	result.accept = result.score >= 0;
	if result.score < -config.band * deal_value then
		result.band = "low";
	elseif result.score > config.band * deal_value then
		result.band = "high";
	else
		result.band = "moderate";
	end;
	return result;
end;

return deal;
