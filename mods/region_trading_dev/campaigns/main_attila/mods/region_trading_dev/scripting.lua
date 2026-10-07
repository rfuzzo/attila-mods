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

local AI = "att_fact_eastern_roman_empire";
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
local MODE = "values";

local steps = {};
if MODE == "values" then
	-- region values as the ERE sees them: WRE regions it would receive, its own it would give (to the WRE)
	local player = "att_fact_western_roman_empire";
	for _, region in ipairs({ "att_reg_narbonensis_aquae_sextiae", "att_reg_mediterraneus_occidentalis_ajax", "att_reg_lusitania_olisipo",
			"att_reg_dardania_serdica", "att_reg_dardania_viminacium", "att_reg_palaestinea_aila" }) do
		table.insert(steps, function() log("VALUE %s", region_trading.explain(region, AI, player)) end);
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
