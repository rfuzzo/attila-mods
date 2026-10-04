-- DEV ONLY: drives the region trading UI with simulated clicks and logs what happens.
-- Deploy with tools/deploy.sh region_trading_dev for an unattended test run, remove it afterwards.
-- Loaded after region_trading (mods load sorted by name).

local rt = require("region_trading/core");
local kit = require("region_trading/ui/kit");

local AI = "att_fact_eastern_roman_empire";
local REGION = "att_reg_lusitania_olisipo";

local function log(fmt, ...) rt.log("TEST " .. fmt, ...) end;

-- depth-first search for a component id
local function find_id(uic, id, depth)
	if uic:Id() == id then return uic end;
	if depth <= 0 then return nil end;
	for i = 0, uic:ChildCount() - 1 do
		local found = find_id(UIComponent(uic:Find(i)), id, depth - 1);
		if found then return found end;
	end;
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

-- probe the component and its descendants for the DiplomacyDropdown controller
local function probe(uic, depth)
	local result = twase.dev_diplomacy_actions(uic:Address());
	if string.find(result, "no DiplomacyDropdown", 1, true) ~= 1 then return uic:Id() .. ": " .. result end;
	if depth <= 0 then return nil end;
	for i = 0, uic:ChildCount() - 1 do
		local r = probe(UIComponent(uic:Find(i)), depth - 1);
		if r then return r end;
	end;
end;

local function actions(tag)
	local d = kit.find(nil, { "diplomacy_dropdown" });
	log("%s actions (type:side:available:blocked): %s", tag, tostring(d and (probe(d, 3) or "no controller found")));
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

local steps = {};
for _, f in ipairs(open_with_ai()) do table.insert(steps, f) end;
table.insert(steps, function() actions("before"); click("add_offer_button") end);
table.insert(steps, function() log("SHOT before") end);
table.insert(steps, function()
	local player = rt.cm():get_local_faction();
	rt.cm():force_diplomacy(player, AI, "regions", true, true);
	rt.cm():force_diplomacy(AI, player, "regions", true, true);
	log("force_diplomacy regions enabled both ways");
	click("button_cancel");
end);
table.insert(steps, function() click("button_cancel") end);
for _, f in ipairs(open_with_ai()) do table.insert(steps, f) end;
table.insert(steps, function() actions("after"); click("add_offer_button") end);
table.insert(steps, function() log("SHOT after") end);
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
