-- DEV ONLY: drives the region trading UI with simulated clicks and logs what happens.
-- Deploy with tools/deploy.sh region_trading_dev for an unattended test run, remove it afterwards.
-- Loaded after region_trading (mods load sorted by name).

local rt = require("region_trading/core");
local kit = require("region_trading/ui/kit");

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

local function actions(tag)
	log("%s actions (type:side:available:blocked): %s", tag, tostring(twase.dev_diplomacy_actions()));
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

local steps = {};
table.insert(steps, function() log("native region trading: %s", tostring(twase.dev_native_region_trading(true))) end);
for _, f in ipairs(open_with_ai()) do table.insert(steps, f) end;
table.insert(steps, function() actions("native"); click("add_offer_button") end);
table.insert(steps, function() click("diplomac_action_possible_6") end);
table.insert(steps, function()
	local offers, demands = list_rows("list_offers"), list_rows("list_demands");
	log("gift region panel: %d offers, %d demands", #offers, #demands);
	for i, row in ipairs(offers) do if i <= 5 then log("  offer row %s: %s", row:Id(), tostring(row:GetStateText())) end end;
	log("SHOT panel");
end);
table.insert(steps, function()
	local offers = list_rows("list_offers");
	if offers[1] then
		-- tick a region from the middle of the list, not the first (alphabetical) one
		local row = offers[math.min(5, #offers)];
		local box = find_id(row, "checkbox", 3);
		if box then box:SimulateClick() end;
		log("ticking %s: %s", row:Id(), tostring(row:GetStateText()));
	end;
end);
table.insert(steps, function() click("ok_trade_regions") end);
table.insert(steps, function() log("SHOT offer") end);
table.insert(steps, function() click("button_send") end);
table.insert(steps, function() log("SHOT answer") end);
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
