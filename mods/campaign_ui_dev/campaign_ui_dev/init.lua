-- Opt-in TWASE campaign UI checks. No campaign data, saves, or UI layouts are changed.
-- Install/remove with tools/deploy.ps1 or tools/deploy.sh campaign_ui_dev.
local dev = {};
campaign_ui_dev = dev;
local baseline;
local required = {
	"get_encyclopedia_url", "set_encyclopedia_url", "get_max_slots_major", "set_max_slots_major",
	"get_max_slots_minor", "set_max_slots_minor", "clear_max_slots",
};
local function log(fmt, ...) print("[CampaignUIDev] " .. string.format(fmt, ...)) end;
local function available()
	for _, name in ipairs(required) do
		if type(twase) ~= "table" or type(twase[name]) ~= "function" then
			log("UNAVAILABLE: twase.%s; install the URL/slot feature build, not only TWASE main", name);
			return false;
		end;
	end;
	return true;
end;
local function capture()
	local url = twase.get_encyclopedia_url();
	assert(type(url) == "string" and url ~= "", "encyclopedia hook did not resolve a native URL");
	return { url = url, major = twase.get_max_slots_major(), minor = twase.get_max_slots_minor() };
end;
local function restore_slots(state)
	twase.set_max_slots_major(state.major);
	twase.set_max_slots_minor(state.minor);
end;
local function restore(state)
	local url = state.url;
	if state.native_url == url then url = nil end;
	twase.set_encyclopedia_url(url);
	restore_slots(state);
	assert(twase.get_encyclopedia_url() == state.url and twase.get_max_slots_major() == state.major and
		twase.get_max_slots_minor() == state.minor, "restored settings differ from the snapshot");
end;
local function run(label, fn)
	if not available() then return false end;
	local ok, value = pcall(fn);
	if not ok then log("FAIL %s: %s", label, tostring(value)); return false end;
	return true, value;
end;
local function remember()
	if not baseline then baseline = capture() end;
end;

function dev.report()
	return run("report", function()
		log("TWASE %s; URL=%s; major=%s; minor=%s", tostring(twase.version),
			tostring(twase.get_encyclopedia_url()), tostring(twase.get_max_slots_major()),
			tostring(twase.get_max_slots_minor()));
		log("nil slot override means native limits; report/getters alone do not prove rendered UI behavior");
	end);
end;

-- API checks are synchronous on the game/Lua thread. Always attempt to restore the starting values, even on failure.
function dev.api()
	if not available() then return false end;
	local captured, state = pcall(capture);
	if not captured then log("FAIL capture: %s", tostring(state)); return false end;
	if not baseline then baseline = state end;
	local checks = 0;
	local function check(condition, label)
		assert(condition, label);
		checks = checks + 1;
		log("API PASS %s", label);
	end;
	local ok, err = pcall(function()
		state.native_url = twase.set_encyclopedia_url(nil);
		if baseline.url == state.native_url then baseline.native_url = state.native_url end;
		check(type(state.native_url) == "string" and state.native_url ~= "", "native URL reset");
		local custom = "http://127.0.0.1:18765/#";
		check(twase.set_encyclopedia_url(custom) == custom, "set URL");
		collectgarbage("collect");
		check(twase.get_encyclopedia_url() == custom, "URL ownership after Lua GC");
		for _, invalid in ipairs({true, 12, {}, "bad\000suffix"}) do
			check(not pcall(twase.set_encyclopedia_url, invalid) and twase.get_encyclopedia_url() == custom,
				"invalid URL leaves value unchanged");
		end;
		check(twase.set_encyclopedia_url("") == state.native_url, "empty URL reset");
		twase.set_encyclopedia_url(custom .. string.rep("a", 300));
		check(twase.set_encyclopedia_url() == state.native_url, "omitted URL reset after replacement");
		twase.clear_max_slots();
		check(twase.get_max_slots_major() == nil and twase.get_max_slots_minor() == nil, "native slot defaults");
		check(twase.set_max_slots_major(8) == 8 and twase.set_max_slots_minor(6) == 6, "independent slot overrides");
		for _, invalid in ipairs({0, -1, 21, 1.5, "8", true, {}, math.huge, -math.huge, 0/0}) do
			for _, setter in ipairs({twase.set_max_slots_major, twase.set_max_slots_minor}) do
				check(not pcall(setter, invalid) and twase.get_max_slots_major() == 8 and
					twase.get_max_slots_minor() == 6, "invalid slot input leaves both values unchanged");
			end;
		end;
		check(twase.set_max_slots_major(nil) == nil and twase.get_max_slots_minor() == 6, "reset major only");
		check(twase.set_max_slots_minor() == nil, "omitted minor reset");
		check(twase.set_max_slots_major(20) == 20 and twase.set_max_slots_minor(1) == 1, "slot boundaries");
		twase.clear_max_slots();
		check(twase.get_max_slots_major() == nil and twase.get_max_slots_minor() == nil, "clear both overrides");
	end);
	local restored, restore_error = pcall(restore, state);
	if not restored then log("FAIL RESTORE: %s; quit the game before continuing", tostring(restore_error)) end;
	if not ok then log("API FAIL after %d checks: %s", checks, tostring(err)) end;
	if ok and restored then log("API PASS %d checks; prior settings restored; native navigation/rendering still need manual checks", checks) end;
	return ok and restored;
end;

function dev.url(url)
	return run("set test URL", function()
		remember();
		local active = twase.set_encyclopedia_url(url or "http://127.0.0.1:18765/#");
		log("URL=%s; now open a NEW encyclopedia link from a unit/building/technology card", active);
		log("The local page must show the game's appended suffix; a getter or manually opened browser tab is not a pass");
		return active;
	end);
end;
function dev.restore_url()
	return run("native URL reset", function()
		local url = twase.set_encyclopedia_url(nil);
		log("Native URL=%s; open a NEW link to check restoration (the old browser page will not change)", url);
		return url;
	end);
end;
function dev.slots(major, minor)
	return run("set slots", function()
		remember();
		local previous = { major = twase.get_max_slots_major(), minor = twase.get_max_slots_minor() };
		local ok, err = pcall(function()
			twase.set_max_slots_major(major);
			twase.set_max_slots_minor(minor);
		end);
		if not ok then
			local restored, restore_error = pcall(restore_slots, previous);
			if not restored then error("RESTORE failed: " .. tostring(restore_error) .. "; quit the game", 0) end;
			error(err, 0);
		end;
		log("major=%s minor=%s; reselect a settlement or close/reopen its panel, then inspect()",
			tostring(major), tostring(minor));
	end);
end;
function dev.reset_slots()
	return run("native slot reset", function()
		twase.clear_max_slots();
		log("Both slot limits reset; reselect a settlement or close/reopen its panel, then inspect()");
	end);
end;
function dev.restore()
	return run("restore original settings", function()
		if not baseline then log("No settings were changed by this harness"); return end;
		restore(baseline);
		log("Load-time settings restored; refresh the settlement panel and reopen encyclopedia links");
	end);
end;

-- Inspect the actual visible UI tree, not configuration getters. No hardcoded addresses or capital guesses.
function dev.inspect()
	return run("inspect settlement panel", function()
		assert(type(get_cm) == "function" and UIComponent ~= nil, "campaign UI is unavailable");
		local raw = get_cm():ui_root():Find("settlement_panel", true);
		assert(raw, "open a settlement panel first");
		local panel = UIComponent(raw);
		assert(panel:Visible(), "settlement panel is hidden; select a settlement first");
		raw = panel:Find("main_settlement_panel", true);
		assert(raw, "main_settlement_panel was not found in this UI layout");
		local records = {};
		local function visit(component, path, ancestors_visible)
			local visible = ancestors_visible and component:Visible();
			if not visible then return end;
			local slots = {};
			for i = 0, component:ChildCount() - 1 do
				local child = UIComponent(component:Find(i));
				local index = tonumber(child:Id():match("^building_slot_(%d+)$"));
				if index then slots[#slots + 1] = { index = index, visible = child:Visible() } end;
			end;
			if #slots > 0 then
				table.sort(slots, function(a, b) return a.index < b.index end);
				local shown = {};
				for _, slot in ipairs(slots) do if slot.visible then shown[#shown + 1] = tostring(slot.index) end end;
				records[#records + 1] = { path = path, visible = #shown, widgets = #slots, indices = table.concat(shown, ",") };
			end;
			for i = 0, component:ChildCount() - 1 do
				local child = UIComponent(component:Find(i));
				visit(child, path .. "/" .. child:Id() .. "[" .. i .. "]", visible);
			end;
		end;
		visit(UIComponent(raw), "main_settlement_panel", true);
		assert(#records > 0, "no visible settlement cards with building_slot_N children; inspect this UI layout manually");
		for _, record in ipairs(records) do
			log("UI %s: %d/%d slot widgets visible [%s]", record.path, record.visible, record.widgets, record.indices);
		end;
		log("UI observation only: compare these counts with the real cards, not just setter return values");
		return records;
	end);
end;

log("Opt-in debug mod loaded; commands: api(), url(), restore_url(), slots(major, minor), reset_slots(), inspect(), restore(), report()");
if type(get_cm) == "function" then
	get_cm():register_first_tick_callback(function() dev.api(); dev.report() end);
else
	log("No campaign manager; run campaign_ui_dev.api() manually in the campaign context");
end;
return dev;
