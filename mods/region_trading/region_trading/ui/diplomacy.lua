-- Diplomacy screen integration: tracks the selected faction and adds a "Trade regions" button to the offers panel.

local rt = require("region_trading/core");
local deal = require("region_trading/deal");
local kit = require("region_trading/ui/kit");
local panel = require("region_trading/ui/panel");

local diplomacy = {};

local PATH = {
	faction_list = { "diplomacy_dropdown", "faction_panel", "sortable_list_factions", "list_clip", "list_box" },
	offers = { "diplomacy_dropdown", "offers_panel" },
	button_set = { "diplomacy_dropdown", "offers_panel", "offers_list_panel", "button_set1" },
};

local POLL = 0.2; -- seconds

local open = false;
local selected = nil; -- faction key
local button = nil;

-- The faction selected in the list (the list is also changed by clicks on the map and on faction icons).
local function read_selected()
	local list = kit.find(nil, PATH.faction_list);
	if not list then return end;
	for i = 0, list:ChildCount() - 1 do
		local row = UIComponent(list:Find(i));
		local state = row:CurrentState();
		if state == "selected" or state == "selected_hover" then
			selected = string.gsub(row:Id(), "faction_row_entry_", "");
			return;
		end;
	end;
end;

-- Our button, cut from MAGA's layout if Fireforged / RTR ship it (it has the region icon), else a vanilla one.
local function create_button(button_set)
	local b = kit.from_layout("ui/bin/button/trade_region", { "lower_panel", "button_view_tree" }, button_set);
	if not b then
		b = kit.from_layout("ui/campaign ui/diplomacy_hud", { "offers_panel", "offers_list_panel", "button_set1", "button_counteroffer" }, button_set);
	end;
	if not b then return nil end;
	local counter = button_set:Find("button_counteroffer");
	local send = button_set:Find("button_send");
	if counter and send then
		local cx, cy = UIComponent(counter):Position();
		local sx = UIComponent(send):Position();
		b:MoveTo(cx - (sx - cx), cy);
	end;
	kit.on_click(b, function()
		if b:CurrentState() == "inactive" or not selected then return end;
		panel.open(rt.cm():get_local_faction(), selected);
	end);
	return b;
end;

local function update_button()
	local offers = kit.find(nil, PATH.offers);
	if not (offers and offers:Visible()) or panel.is_open() then return end;
	if not button then
		local button_set = kit.find(nil, PATH.button_set);
		if not button_set then return end;
		button = create_button(button_set);
		if not button then return end;
	end;
	local ok, reason = false, "no faction selected";
	if selected then ok, reason = deal.can_trade_with(rt.cm():get_local_faction(), selected) end;
	button:SetState(ok and "active" or "inactive");
	button:SetTooltipText(ok and "Trade regions||Offer regions for gold, federate troops or another region."
		or ("Trade regions||Not possible: " .. tostring(reason)), true);
end;

local function poll()
	if not open then return end;
	read_selected();
	update_button();
	kit.after(POLL, poll);
end;

rt.cm():add_listener("RegionTrading_DiplomacyOpened", "PanelOpenedCampaign", function(context)
	return context.string == "diplomacy_dropdown";
end, function()
	-- the AI's own offers during its turn are left alone
	if not rt.cm():model():is_player_turn() or open then return end;
	open, selected, button = true, nil, nil;
	poll();
end, true);

rt.cm():add_listener("RegionTrading_DiplomacyClosed", "PanelClosedCampaign", function(context)
	return context.string == "diplomacy_dropdown";
end, function()
	open = false;
	panel.close();
	if button then kit.forget(button); kit.delete(button); button = nil end;
end, true);

-- For testing from the console / a harness
function diplomacy.state()
	return { open = open, selected = selected, button = button ~= nil, panel = panel.is_open() };
end;

return diplomacy;
