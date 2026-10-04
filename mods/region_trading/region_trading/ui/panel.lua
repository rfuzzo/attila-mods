-- The region trading panel: replaces the diplomacy offers list while open. Regions are picked by clicking
-- settlements on the tactical map. Built from vanilla layouts (frame: finance_screen, texts: tech_tooltip /
-- character_information, buttons: diplomacy_hud), so it needs no image files.

local rt = require("region_trading/core");
local deal = require("region_trading/deal");
local execute = require("region_trading/execute");
local kit = require("region_trading/ui/kit");

local panel = {};

local KINDS = {
	{ kind = "money", label = "Gold" },
	{ kind = "payments", label = "Instalments" },
	{ kind = "troops", label = "Federates" },
	{ kind = "swap", label = "Region" },
};

local PATH = {
	diplomacy = { "diplomacy_dropdown" },
	offers = { "diplomacy_dropdown", "offers_panel" },
	offers_cancel = { "diplomacy_dropdown", "offers_panel", "offers_list_panel", "button_set1", "button_cancel" },
	diplomacy_cancel = { "diplomacy_dropdown", "faction_panel", "both_buttongroup", "button_cancel" },
	tactical_map_button = { "diplomacy_dropdown", "offers_panel", "button_tactical_map" },
	radar = { "campaign_tactical_map", "radar" },
};

local s = nil; -- state while open: { player, ai, region, ai_region, kind, ui = {...}, icons = {...} }

local function number(n)
	local text = tostring(math.floor(n + 0.5));
	return (text:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""):gsub("^%-,", "-"));
end;

local function faction_name(key)
	return rt.localise("factions_screen_name_" .. key) or key;
end;

-- TEXTS

local function text(parent, style)
	local uic;
	if style == "title" then
		uic = kit.from_layout("ui/campaign ui/tech_tooltip", { "title_frame", "dy_building_title" }, parent);
		if uic then
			local bar = uic:Find("tooltip_bar");
			if bar then kit.delete(UIComponent(bar)) end;
		end;
	else
		uic = kit.from_layout("ui/campaign ui/character_information", { "subpanel_character", "dy_type" }, parent);
	end;
	if uic then uic:SetInteractive(true) end;
	return uic;
end;

local function set(uic, value, colour)
	if uic then uic:SetStateText(kit.colour(value, colour or kit.BROWN)) end;
end;

-- MAP: show only the two factions' settlements, grey out what can't be traded

local function region_of_icon(id)
	local key = string.gsub(id, "radar_icon_settlement:", "");
	local colon = string.find(key, ":"); -- some bel_attila icons are "<province>:<name>"
	if colon then key = string.sub(key, 1, colon - 1) end;
	return key;
end;

local function prepare_map()
	local radar = kit.find(nil, PATH.radar);
	if not radar or not radar:Visible() then
		local button = kit.find(nil, PATH.tactical_map_button);
		if button then button:SimulateClick() end;
		radar = kit.find(nil, PATH.radar);
	end;
	local map = radar and radar:Find("map");
	if not map then
		rt.log("ui: tactical map not found");
		return;
	end;
	map = UIComponent(map);
	s.icons = {};
	for i = 0, map:ChildCount() - 1 do
		local icon = UIComponent(map:Find(i));
		local id = icon:Id();
		if string.find(id, "radar_icon_settlement", 1, true) then
			local key = region_of_icon(id);
			local ok, owner = pcall(function() return rt.world():region_manager():region_by_key(key):owning_faction():name() end);
			if ok and (owner == s.player or owner == s.ai) then
				local tradable = deal.can_trade_region(key, owner);
				if not tradable then
					local main = icon:Find("main_icon");
					if main then
						main = UIComponent(main);
						main:ShaderTechniqueSet("set_greyscale_t0", false);
						main:ShaderVarsSet(0.75, 0.75, 0, 0, false);
					end;
				end;
				table.insert(s.icons, { uic = icon, greyed = not tradable });
			else
				icon:SetVisible(false);
				table.insert(s.icons, { uic = icon, hidden = true });
			end;
		end;
	end;
end;

local function restore_map()
	for _, icon in ipairs(s.icons or {}) do
		if icon.hidden then icon.uic:SetVisible(true) end;
		if icon.greyed then
			local main = icon.uic:Find("main_icon");
			if main then
				main = UIComponent(main);
				main:ShaderTechniqueSet(7, false);
				main:ShaderVarsSet(0, 0, 0, 0, false);
			end;
		end;
	end;
	s.icons = {};
end;

-- UPDATE

local function update()
	local ui = s.ui;
	set(ui.give, "You give: " .. (s.region and rt.region_name(s.region) or "select one of your settlements on the map"));

	for _, k in ipairs(KINDS) do
		set(ui.kinds[k.kind], k.label, k.kind == s.kind and kit.YELLOW or kit.GREY);
	end;

	s.result = nil;
	local want = "";
	if s.kind == "swap" then
		want = "You get: " .. (s.ai_region and rt.region_name(s.ai_region) or "select one of their settlements on the map");
	end;

	local ready = s.region and (s.kind ~= "swap" or s.ai_region);
	if ready then
		local d = { player = s.player, ai = s.ai, region = s.region, kind = s.kind, ai_region = s.ai_region };
		local ok, result = pcall(deal.evaluate, d);
		if not ok then
			rt.log("ui: evaluation failed: %s", tostring(result));
		else
			s.deal, s.result = d, result;
			if s.kind == "money" then
				want = "You get: " .. number(result.price) .. " gold";
			elseif s.kind == "payments" then
				want = string.format("You get: %s gold for %d turns", number(result.per_turn), result.turns);
			elseif s.kind == "troops" then
				want = result.unavailable and ("No federates: " .. result.unavailable)
					or string.format("You get: %d units of federates", #result.units);
			end;
		end;
	end;
	set(ui.get, want);

	local r = s.result;
	if r and not r.unavailable then
		local colour = r.band == "high" and kit.GREEN or (r.band == "low" and kit.RED or kit.YELLOW);
		local band = r.band == "high" and "High" or (r.band == "low" and "Low" or "Moderate");
		set(ui.likelihood, string.format("Likelihood of success: %s (%s%s)", band, r.score >= 0 and "+" or "", number(r.score)), colour);
		ui.likelihood:SetTooltipText(string.format("Value of %s for them: %s\nWhat they give: %s\nRelationship: %s%s",
			rt.region_name(s.region), number(r.value), number(r.price or r.ai_region_value or 0),
			r.relationship >= 0 and "+" or "", number(r.relationship)), true);
		ui.ok:SetState("active");
	else
		set(ui.likelihood, "");
		ui.ok:SetState("inactive");
	end;
end;

-- OPEN / CLOSE

function panel.close()
	if not s then return end;
	for _, uic in ipairs(s.clickable or {}) do kit.forget(uic) end;
	kit.on_click_id("main_icon", nil);
	kit.on_click_id("name_bar", nil);
	restore_map();
	kit.delete(s.ui.frame);
	local offers = kit.find(nil, PATH.offers);
	if offers then offers:SetVisible(true) end;
	s = nil;
	rt.log("panel closed");
end;

function panel.is_open()
	return s ~= nil;
end;

local function close_diplomacy()
	panel.close();
	local cancel = kit.find(nil, PATH.offers_cancel);
	if cancel then cancel:SimulateClick() end;
	kit.next_tick(function()
		local close = kit.find(nil, PATH.diplomacy_cancel);
		if close then close:SimulateClick() end;
	end);
end;

local function on_ok()
	if not (s and s.result and s.deal) or s.ui.ok:CurrentState() == "inactive" then return end;
	if s.result.accept then
		execute.run(s.deal, s.result);
		close_diplomacy();
	else
		set(s.ui.likelihood, faction_name(s.ai) .. " refuse this offer.", kit.RED);
		s.ui.ok:SetState("inactive");
	end;
end;

local function on_settlement(uic)
	if not s then return end;
	-- main_icon's parent, or name_bar's grandparent, is the settlement icon
	local icon = UIComponent(uic:Parent());
	if not string.find(icon:Id(), "radar_icon_settlement", 1, true) then icon = UIComponent(icon:Parent()) end;
	if not string.find(icon:Id(), "radar_icon_settlement", 1, true) then return end;
	local key = region_of_icon(icon:Id());
	local owner = rt.world():region_manager():region_by_key(key):owning_faction():name();
	if not deal.can_trade_region(key, owner) then return end;
	if owner == s.player then
		s.region = key;
	elseif owner == s.ai then
		s.ai_region = key;
		s.kind = "swap";
	end;
	update();
end;

function panel.open(player, ai)
	if s then panel.close() end;
	local diplomacy = kit.find(nil, PATH.diplomacy);
	local offers = kit.find(nil, PATH.offers);
	if not (diplomacy and offers) then return end;

	s = { player = player, ai = ai, kind = "money", ui = {}, clickable = {} };
	local ui = s.ui;

	ui.frame = kit.from_layout("ui/campaign ui/finance_screen", {}, diplomacy);
	if not ui.frame then s = nil; return end;
	for _, child in ipairs({ "TabGroup", "button_info_holder" }) do
		local c = ui.frame:Find(child);
		if c then kit.delete(UIComponent(c)) end;
	end;
	local x, y = offers:Position();
	local w, h = offers:Dimensions();
	ui.frame:MoveTo(x, y);
	ui.frame:Resize(w, h);
	local title = kit.find(ui.frame, { "title_plaque", "tx_finance" });
	if title then title:SetStateText("Regions: " .. faction_name(ai)) end;
	offers:SetVisible(false);

	local left, top, line = x + 40, y + 70, 34;
	ui.give = text(ui.frame);
	ui.give:MoveTo(left, top);

	ui.kinds = {};
	for i, k in ipairs(KINDS) do
		local t = text(ui.frame);
		t:MoveTo(left + (i - 1) * (w - 80) / #KINDS, top + line);
		kit.on_click(t, function() s.kind = k.kind; if k.kind ~= "swap" then s.ai_region = nil end; update() end);
		table.insert(s.clickable, t);
		ui.kinds[k.kind] = t;
	end;

	ui.get = text(ui.frame);
	ui.get:MoveTo(left, top + 2 * line);
	ui.likelihood = text(ui.frame);
	ui.likelihood:MoveTo(left, top + 3 * line);

	ui.ok = kit.from_layout("ui/campaign ui/diplomacy_hud", { "faction_panel", "both_buttongroup", "button_ok" }, ui.frame);
	ui.cancel = kit.from_layout("ui/campaign ui/diplomacy_hud", { "faction_panel", "both_buttongroup", "button_cancel" }, ui.frame);
	if ui.ok then ui.ok:MoveTo(x + w / 2 - 70, y + h - 70); kit.on_click(ui.ok, on_ok); table.insert(s.clickable, ui.ok) end;
	if ui.cancel then ui.cancel:MoveTo(x + w / 2 + 20, y + h - 70); kit.on_click(ui.cancel, panel.close); table.insert(s.clickable, ui.cancel) end;

	kit.on_click_id("main_icon", on_settlement);
	kit.on_click_id("name_bar", on_settlement);
	prepare_map();
	update();
	rt.log("panel open: %s with %s", player, ai);
end;

return panel;
