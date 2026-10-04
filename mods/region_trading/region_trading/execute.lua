-- Carrying out an accepted deal: region transfer, money, instalments, federate troops. Running instalments are saved.

local rt = require("region_trading/core");
local config = require("region_trading/config");
local deal = require("region_trading/deal");

local execute = {};

-- running instalments: { ai, player, per_turn, turns_left }
local payments = {};
-- governor whose immortality we switched on for a transfer
local protect_governor = false;

-- Transferring a province capital kills its governor: make him immortal for the transfer and mortal again
-- when the "death" recreates him (CharacterCreated fires during the transfer). From Region Trading Reloaded.
local function transfer(region_key, to)
	local region = rt.world():region_manager():region_by_key(region_key);
	if region:has_governor() and region:governor():region():name() == region_key then
		rt.cm():set_character_immortality("character_cqi:" .. region:governor():cqi(), true);
	end;
	protect_governor = true;
	rt.cm():transfer_region_to_faction(region_key, to);
	protect_governor = false;
	rt.log("transferred %s to %s", region_key, to);
end;

rt.cm():add_listener("RegionTrading_GovernorCreated", "CharacterCreated", true, function(context)
	if protect_governor then
		rt.cm():set_character_immortality("character_cqi:" .. context:character():cqi(), false);
	end;
end, true);

-- execute.run(d, result) with an evaluated, accepted deal
function execute.run(d, result)
	transfer(d.region, d.ai);

	if d.kind == "money" then
		rt.cm():treasury_mod(d.ai, -result.price);
		rt.cm():treasury_mod(d.player, result.price);
	elseif d.kind == "payments" then
		table.insert(payments, { ai = d.ai, player = d.player, per_turn = result.per_turn, turns_left = result.turns });
	elseif d.kind == "troops" then
		local force = deal.negotiating_army(d.player, d.region);
		for _, unit in ipairs(result.units or {}) do
			rt.cm():add_unit_to_force(unit, force:command_queue_index());
		end;
		-- TODO federate loyalty (design: "Federate loyalty")
	elseif d.kind == "swap" then
		transfer(d.ai_region, d.player);
	end;
	rt.log("deal done: %s %s with %s, score %d", d.kind, d.region, d.ai, result.score);
end;

-- Instalments at the start of the player's turn. If the AI can't pay, the deal ends.
rt.cm():add_listener("RegionTrading_Payments", "FactionTurnStart", true, function(context)
	local faction = context:faction();
	if faction:name() ~= rt.cm():get_local_faction() then return end;
	local still = {};
	for _, p in ipairs(payments) do
		local ai = rt.world():faction_by_key(p.ai);
		if ai:treasury() >= p.per_turn and not ai:at_war_with(faction) then
			rt.cm():treasury_mod(p.ai, -p.per_turn);
			rt.cm():treasury_mod(p.player, p.per_turn);
			p.turns_left = p.turns_left - 1;
			if p.turns_left > 0 then table.insert(still, p) end;
		else
			rt.log("payments from %s ended: can't pay or at war", p.ai);
		end;
	end;
	payments = still;
end, true);

-- Save / load the running instalments as "ai,player,per_turn,turns_left;..."
rt.cm():register_saving_game_callback(function(context)
	local parts = {};
	for _, p in ipairs(payments) do
		table.insert(parts, table.concat({ p.ai, p.player, p.per_turn, p.turns_left }, ","));
	end;
	rt.cm():save_value("RegionTrading_Payments", table.concat(parts, ";"), context);
end);

rt.cm():register_loading_game_callback(function(context)
	payments = {};
	local saved = rt.cm():load_value("RegionTrading_Payments", "", context);
	for entry in string.gmatch(saved, "[^;]+") do
		local ai, player, per_turn, turns_left = string.match(entry, "([^,]+),([^,]+),([^,]+),([^,]+)");
		if ai then
			table.insert(payments, { ai = ai, player = player, per_turn = tonumber(per_turn), turns_left = tonumber(turns_left) });
		end;
	end;
end);

return execute;
