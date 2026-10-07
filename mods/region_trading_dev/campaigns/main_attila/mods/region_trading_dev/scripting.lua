-- DEV ONLY: drives the region trading UI with simulated clicks and logs what happens.
-- Deploy with tools/deploy.sh region_trading_dev for an unattended test run, remove it afterwards.
-- Loaded after region_trading (mods load sorted by name).

local rt = require("region_trading/core");

local kit = {};

function kit.root()
	return rt.cm():ui_root();
end;

-- kit.after(seconds, fn): run fn after a delay, through the campaign's time triggers
local timers, next_timer = {}, 0;
function kit.after(seconds, fn)
	next_timer = next_timer + 1;
	local id = "RegionTradingDevTimer" .. next_timer;
	timers[id] = fn;
	rt.cm():add_time_trigger(id, seconds);
end;

rt.cm():add_listener("RegionTradingDev_Timer", "TimeTrigger", true, function(context)
	local fn = timers[context.string];
	if fn then
		timers[context.string] = nil;
		fn();
	end;
end, true);

local AI = "att_fact_quadi"; -- the partner (the ERE for most tests)
local REGION = "att_reg_lusitania_olisipo";

local function log(fmt, ...) rt.log("TEST " .. fmt, ...) end;

-- the engine's own recursive search (Find(name, true)); the depth argument is ignored
local function find_id(uic, id, depth)
	local found = uic:Find(id, true);
	return found and UIComponent(found) or nil;
end;

local function texts(uic, out, depth)
	out = out or {};
	local t = uic:GetStateText();
	if t and t ~= "" then table.insert(out, uic:Id() .. "=" .. t) end;
	if depth > 0 then
		for i = 0, uic:ChildCount() - 1 do texts(UIComponent(uic:Find(i)), out, depth - 1) end;
	end;
	return out;
end;

local function click(id, depth)
	local c = find_id(kit.root(), id, depth or 12);
	log("click %s: %s", id, tostring(c ~= nil));
	if c then c:SimulateClick() end;
end;

local function open_with_ai()
	return {
		function() click("button_diplomacy", 8) end,
		function() click("faction_row_entry_" .. AI) end,
		function() click("button_ok") end,
	};
end;

local function list_rows(list_id)
	local list = find_id(kit.root(), list_id, 14);
	local box = list and find_id(list, "list_box", 4);
	local rows = {};
	if box then
		box = UIComponent(box);
		for i = 0, box:ChildCount() - 1 do
			local child = box:Find(i);
			if child then table.insert(rows, UIComponent(child)) end;
		end;
	end;
	return rows;
end;

-- "panel": open the native region panel with the AI; "transfer": the deal's transfer, for the minimap (needs
-- [dev] lua_dev_functions = true in TWASE/config.ini)
local MODE = "federates";

local steps = {};
if MODE == "federates" then
	-- federates for Salona from a faction without a levy pool (the ERE) and from peoples with one
	for _, ai in ipairs({ "att_fact_quadi", "att_fact_visigothi" }) do
		table.insert(steps, function()
			local pool = {};
			for g, p in pairs(twase.levy_pool(ai) or {}) do table.insert(pool, string.format("%s x%d", p.unit, p.max_count)) end;
			local offer, _, reason = region_trading.federates.offer(ai, "att_fact_western_roman_empire", { "att_reg_pannonia_savaria" });
			log("FEDERATES from %s (pool: %s): %s", ai, table.concat(pool, ", "),
				offer and string.format("army %d, %d units, cost %d of budget %d: %s", offer.force_cqi, #offer.units, offer.cost, offer.budget,
					table.concat(offer.units, ", ")) or ("none, " .. tostring(reason)));
		end);
	end;
elseif MODE == "db" then
	-- record layouts of the levy pool tables (needs [dev] lua_dev_functions = true)
	for _, t in ipairs({ "faction_to_mercenary_set_junctions", "mercenary_pool_to_groups_junctions", "mercenary_unit_groups" }) do
		table.insert(steps, function()
			for i = 0, 2 do
				local fields, count = twase.dev_db_fields(t, i, 0x50);
				log("DB %s[%d] of %d: %s", t, i, count, tostring(fields));
			end;
		end);
	end;
elseif MODE == "values" then
	-- region values as the ERE sees them: WRE regions it would receive, its own it would give (to the WRE)
	local player = "att_fact_western_roman_empire";
	for _, region in ipairs({ "att_reg_narbonensis_aquae_sextiae", "att_reg_mediterraneus_occidentalis_ajax", "att_reg_lusitania_olisipo",
			"att_reg_dardania_serdica", "att_reg_dardania_viminacium", "att_reg_palaestinea_aila" }) do
		table.insert(steps, function() log("VALUE %s", region_trading.explain(region, AI, player)) end);
	end;
	-- federates the ERE would give for land the WRE cedes
	for _, regions in ipairs({ { "att_reg_dalmatia_salona" }, { "att_reg_lusitania_olisipo" }, { "att_reg_dalmatia_salona", "att_reg_narbonensis_aquae_sextiae" } }) do
		table.insert(steps, function()
			local offer, reason = region_trading.federates.offer(AI, player, regions);
			if not offer then
				log("FEDERATES for %s: none, %s", table.concat(regions, " + "), reason);
			else
				log("FEDERATES for %s: %d units, cost %d of budget %d (land %d), army %d: %s", table.concat(regions, " + "),
					#offer.units, offer.cost, offer.budget, offer.value, offer.force_cqi, table.concat(offer.units, ", "));
			end;
		end);
	end;
	-- every WRE region the WRE has an army in, valued by the WRE as owner against the ERE (leverage: none expected)
	table.insert(steps, function()
		local forces = rt.world():faction_by_key(player):military_force_list();
		for i = 0, forces:num_items() - 1 do
			local f = forces:item_at(i);
			if f:is_army() and f:has_general() and f:general_character():has_region() then
				local r = f:general_character():region();
				log("ARMY in %s (owner %s)", r:name(), r:owning_faction():name());
			end;
		end;
	end);
elseif MODE == "garrison" then
	-- what tells a settlement's garrison from a field army inside the settlement
	table.insert(steps, function()
		local forces = rt.world():faction_by_key("att_fact_western_roman_empire"):military_force_list();
		for i = 0, forces:num_items() - 1 do
			local f = forces:item_at(i);
			if f:has_general() and f:general_character():has_region() and f:general_character():region():name():find("savaria") then
				local g = f:general_character();
				local function try(fn) local ok, v = pcall(fn); return ok and tostring(v) or ("err:" .. tostring(v)) end;
				log("FORCE %d: army %s, garrison_residence %s, units %d, type general %s colonel %s, ap %s, rank %s, politician %s, family %s, faction_leader %s, embedded %s, in_settlement %s, upkeep %s",
					f:command_queue_index(), tostring(f:is_army()), tostring(f:has_garrison_residence()), f:unit_list():num_items(),
					try(function() return g:character_type("general") end), try(function() return g:character_type("colonel") end),
					try(function() return g:action_points_per_turn() end), try(function() return g:rank() end),
					try(function() return g:is_politician() end), try(function() return g:family_member() end),
					try(function() return g:is_faction_leader() end), try(function() return g:is_embedded_in_military_force() end),
					try(function() return g:in_settlement() end), try(function() return f:upkeep() end));
			end;
		end;
	end);
elseif MODE == "addunit" then
	-- add_unit_to_force on the WRE armies in or next to Savaria: their units before and after
	local function armies()
		local out = {};
		local forces = rt.world():faction_by_key("att_fact_western_roman_empire"):military_force_list();
		for i = 0, forces:num_items() - 1 do
			local f = forces:item_at(i);
			if f:is_army() and f:has_general() and f:general_character():has_region() then
				local r = f:general_character():region():name();
				if r:find("pannonia") or r:find("savaria") then table.insert(out, f) end;
			end;
		end;
		return out;
	end;
	table.insert(steps, function()
		for _, f in ipairs(armies()) do
			log("ARMY %d in %s: %d units", f:command_queue_index(), f:general_character():region():name(), f:unit_list():num_items());
			rt.cm():add_unit_to_force("rex_germ_band_defenders_sueb", f:command_queue_index());
			rt.cm():add_unit_to_force("att_rom_comitatensis_spears", f:command_queue_index());
		end;
	end);
	table.insert(steps, function()
		for _, f in ipairs(armies()) do
			log("ARMY %d after: %d units", f:command_queue_index(), f:unit_list():num_items());
		end;
	end);
elseif MODE == "willingness" then
	for _, ai in ipairs({ "att_fact_eastern_roman_empire", "att_fact_quadi", "att_fact_visigothi", "att_fact_alani", "att_fact_franci" }) do
		table.insert(steps, function()
			local points, parts = region_trading.federates.willingness(ai, "att_fact_western_roman_empire");
			local out = {};
			for k, v in pairs(parts) do table.insert(out, string.format("%s %.1f", k, v)) end;
			table.sort(out);
			log("WILLINGNESS %s: %+.1f (%s)", ai, points, table.concat(out, ", "));
		end);
	end;
elseif MODE == "actions" then
	-- the Add Offer/Demand buttons: their ids (type numbers) and labels; at war, again after adding peace
	local function list_actions(tag)
		local any = find_id(kit.root(), "diplomac_action_possible_12") or find_id(kit.root(), "diplomac_action_possible_6");
		local parent = any and UIComponent(any:Parent());
		for i = 0, (parent and parent:ChildCount() or 0) - 1 do
			local child = UIComponent(parent:Find(i));
			local label = child:Find("row_tx");
			log("ACTION %s %s = %s", tag, child:Id(), label and UIComponent(label):GetStateText() or "?");
		end;
	end;
	for _, f in ipairs(open_with_ai()) do table.insert(steps, f) end;
	table.insert(steps, function() click("add_offer_button") end);
	table.insert(steps, function() list_actions("before") end);
	table.insert(steps, function() click("diplomac_action_possible_12") end);
	table.insert(steps, function() click("add_offer_button") end);
	table.insert(steps, function() list_actions("after peace") end);
	table.insert(steps, function() log("ACTIONS type:side:available:blocked %s", tostring(twase.dev_diplomacy_actions())) end);
	table.insert(steps, function() log("SHOT deal") end);
elseif MODE == "troops" then
	for _, f in ipairs(open_with_ai()) do table.insert(steps, f) end;
	table.insert(steps, function() click("add_offer_button") end);
	table.insert(steps, function() log("SHOT list") end);
	-- "Region for Troops" is the second button of the region action (same id as "Gift Region")
	table.insert(steps, function()
		local gift = find_id(kit.root(), "diplomac_action_possible_6");
		local parent = gift and UIComponent(gift:Parent());
		local seen = 0;
		for i = 0, (parent and parent:ChildCount() or 0) - 1 do
			local child = UIComponent(parent:Find(i));
			if child:Id() == "diplomac_action_possible_6" then
				seen = seen + 1;
				if seen == 2 then
					log("click Region for Troops");
					child:SimulateClick();
					return;
				end;
			end;
		end;
		log("Region for Troops button not found (%d region buttons)", seen);
	end);
	table.insert(steps, function() log("SHOT troops") end);
elseif MODE == "panel" then
	for _, f in ipairs(open_with_ai()) do table.insert(steps, f) end;
	table.insert(steps, function() click("add_offer_button") end);
	table.insert(steps, function() click("diplomac_action_possible_6") end);
	table.insert(steps, function() log("SHOT panel") end);
	-- tick the first row of each list, untick the first again
	local function click_first(list)
		local l = find_id(kit.root(), list);
		local c = l and find_id(l, "checkbox");
		log("click first checkbox of %s: %s", list, tostring(c ~= nil));
		if c then c:SimulateClick() end;
	end;
	table.insert(steps, function() click_first("list_offers") end);
	table.insert(steps, function() log("SHOT tick1") end);
	table.insert(steps, function() click_first("list_demands") end);
	table.insert(steps, function() log("SHOT tick2") end);
	table.insert(steps, function() click_first("list_offers") end);
	table.insert(steps, function() log("SHOT untick1") end);
else
	-- the region deal's transfer with flag 0 (as the deal calls it), then with flag 1 (as transfer_region_to_faction)
	local function transfer(region, flag)
		local world = rt.world();
		twase.dev_transfer_region(world:region_manager():region_by_key(region), world:faction_by_key(AI), flag);
		log("transferred %s to %s with flag %d", region, AI, flag);
	end;
	table.insert(steps, function() log("SHOT before") end);
	table.insert(steps, function() transfer(REGION, 0) end);
	table.insert(steps, function() log("SHOT flag0") end);
	table.insert(steps, function() transfer("att_reg_narbonensis_aquae_sextiae", 1) end);
	table.insert(steps, function() log("SHOT flag1") end);
end;
table.insert(steps, function() log("done") end);

rt.cm():register_first_tick_callback(function()
	local i = 0;
	local function next_step()
		i = i + 1;
		if not steps[i] then return end;
		local ok, err = pcall(steps[i]);
		if not ok then log("step %d failed: %s", i, tostring(err)) end;
		kit.after(3, next_step);
	end;
	kit.after(3, next_step);
end);
