-- Debug-mod behavior tests, not proof of TWASE's native hooks. Run from the repository root:
--   lua tests/campaign_ui_dev.lua
local root = arg[0]:match("^(.*)[/\\]tests[/\\][^/\\]*$") or ".";
local source = root .. "/mods/campaign_ui_dev/campaign_ui_dev/init.lua";
local function check(condition, message) assert(condition, message) end;
local function equal(a, b, message) check(a == b, message .. ": " .. tostring(a) .. " ~= " .. tostring(b)) end;
local function node(id, visible, children)
	local n = { id = id, visible = visible, children = children or {} };
	function n:Id() return self.id end;
	function n:Visible() return self.visible end;
	function n:ChildCount() return #self.children end;
	function n:Find(key, recursive)
		if type(key) == "number" then return self.children[key + 1] end;
		for _, child in ipairs(self.children) do
			if child.id == key then return child end;
			if recursive then local found = child:Find(key, true); if found then return found end end;
		end;
	end;
	return n;
end;
local function boot(options)
	options = options or {};
	local state = { url = "https://previous.invalid/#", major = 3, minor = 5, writes = 0 };
	local native = "https://native.invalid/#";
	local api = { version = "test" };
	local function before(name, value)
		if options.fault then options.fault(name, value) end;
		state.writes = state.writes + 1;
	end;
	function api.get_encyclopedia_url() return state.url end;
	function api.set_encyclopedia_url(value)
		assert(value == nil or (type(value) == "string" and not value:find("\000", 1, true)), "invalid URL");
		before("url", value);
		state.url = (value == nil or value == "") and native or value;
		return state.url;
	end;
	local function set_slots(field, value)
		assert(value == nil or (type(value) == "number" and value >= 1 and value <= 20 and value == math.floor(value)), "invalid slots");
		before(field, value); state[field] = value; return value;
	end;
	function api.get_max_slots_major() return state.major end;
	function api.get_max_slots_minor() return state.minor end;
	function api.set_max_slots_major(value) return set_slots("major", value) end;
	function api.set_max_slots_minor(value) return set_slots("minor", value) end;
	function api.clear_max_slots() before("clear"); state.major = nil; state.minor = nil end;
	if options.missing then api[options.missing] = nil end;
	local callbacks = {};
	local cm = {};
	function cm:register_first_tick_callback(fn) callbacks[#callbacks + 1] = fn end;
	function cm:ui_root() return options.ui or node("root", true) end;
	local env = setmetatable({
		twase = api, get_cm = function() return cm end, print = function() end,
		-- The real UIComponent wrapper is a callable table, not a plain function.
		UIComponent = setmetatable({}, { __call = function(_, raw) return assert(raw, "missing component") end }),
	}, { __index = _G });
	local chunk, err;
	if setfenv then chunk, err = loadfile(source); if chunk then setfenv(chunk, env) end
	else chunk, err = loadfile(source, "t", env) end;
	assert(chunk, err);
	local dev = chunk();
	return dev, state, callbacks;
end;

local dev, state, callbacks = boot();
equal(state.writes, 0, "loading does not change settings before first tick");
callbacks[1]();
equal(state.url, "https://previous.invalid/#", "automatic checks restore custom URL");
equal(state.major, 3, "automatic checks restore major override");
equal(state.minor, 5, "automatic checks restore minor override");
check(dev.api(), "passing API run should report success");
check(dev.url(), "enable manual URL probe");
check(dev.slots(8, 6), "set manual slot pair");
check(dev.restore(), "restore initial manual-test state");
equal(state.url, "https://previous.invalid/#", "manual restore restores URL");
equal(state.major, 3, "manual restore restores major");
equal(state.minor, 5, "manual restore restores minor");
check(not dev.slots(8, -1), "bad minor input rejects pair");
equal(state.major, 3, "bad minor input rolls major back");
equal(state.minor, 5, "bad minor input preserves minor");
equal(state.url, "https://previous.invalid/#", "slot-pair failure does not reset URL");

local fail_once = true;
dev, state = boot({ fault = function(name, value)
	if fail_once and name == "minor" and value == 6 then fail_once = false; error("injected write failure") end;
end });
check(not dev.api(), "an interrupted check must not report success");
equal(state.url, "https://previous.invalid/#", "interrupted check restores URL");
equal(state.major, 3, "interrupted check restores already-mutated major");
equal(state.minor, 5, "interrupted check restores minor");

dev, state = boot({ fault = function(name, value)
	if name == "major" and value == 3 then error("injected restore failure") end;
end });
check(not dev.api(), "a restoration failure must not report success");
check(state.major ~= 3, "test really exercised an incomplete restoration");

dev, state, callbacks = boot({ missing = "set_max_slots_minor" });
check(not dev.api(), "older TWASE must report unavailable");
equal(state.writes, 0, "missing API causes no partial changes");
callbacks[1]();
equal(state.writes, 0, "automatic check is inert with missing API");

local function card(id, count, shown, visible)
	local slots = {};
	for i = 1, count do slots[i] = node("building_slot_" .. i, i <= shown) end;
	return node(id, visible, slots);
end;
local panel = node("settlement_panel", true, {
	node("main_settlement_panel", true, {
		card("settlement_capital", 6, 2, true), card("settlement_1", 4, 4, true),
		node("hidden_template", false, { card("template_card", 6, 6, true) }),
	}),
});
dev = boot({ ui = node("root", true, { panel }) });
local ok, records = dev.inspect();
check(ok, "inspect real-shaped UI with callable wrapper");
equal(#records, 2, "hidden ancestor suppresses template observations");
equal(records[1].visible, 2, "observe major's actual two visible children");
equal(records[1].widgets, 6, "report template capacity separately from visibility");
equal(records[1].indices, "1,2", "visible indices reported in numerical order");
equal(records[2].visible, 4, "inspect minor independently");
panel.visible = false;
check(not dev.inspect(), "hidden panel cannot be reported as an observed pass");
dev = boot();
check(not dev.inspect(), "missing panel cannot be reported as an observed pass");
print("PASS campaign_ui_dev: restoration, interrupted checks, missing API, atomic slot pairs, and actual UI-tree observations");
