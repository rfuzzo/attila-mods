-- Tests for mods/fireforged_fixes against Fireforged's real scripts (extracted/fireforged, git-ignored, from
-- tools/extract-all.sh) with a stubbed campaign manager. Plain Lua (5.1 or 5.4), run from the repo root:
--   lua tests/fireforged_fixes.lua
-- The scripts are cp1251 with CRLF, they are converted with iconv.

local root = arg[0]:match("^(.*)/tests/[^/]*$") or ".";
local extracted = root .. "/extracted";
local ff_scripts = extracted .. "/fireforged/1/campaigns/main_attila";

local function read(path)
	local pipe = io.popen("iconv -f cp1251 -t utf8 -c '" .. path .. "' 2>/dev/null | tr -d '\\r'");
	local text = pipe:read("*a");
	pipe:close();
	if text == "" then
		say("SKIP: " .. path .. " not found, run tools/extract-all.sh");
		os.exit(0);
	end;
	return text;
end;

unpack = unpack or table.unpack;

-- the mod logs through print: collect it, tests print through say()
local say = print;
local log_lines = {};
print = function(...) log_lines[#log_lines + 1] = table.concat({ ... }, " ") end;

local failures, checks = 0, 0;
local function check(condition, message)
	checks = checks + 1;
	if not condition then
		failures = failures + 1;
		say("FAIL: " .. message);
	end;
end;

local function load_into(env, path, chunk_name)
	local fn, err;
	if setfenv then
		fn, err = loadstring(read(path), chunk_name);
		if fn then setfenv(fn, env) end;
	else
		fn, err = load(read(path), chunk_name, "t", env);
	end;
	assert(fn, err);
	return fn();
end;

-- A campaign manager that records calls it doesn't know.
local function new_cm(state)
	local cm = { calls = {}, saved = {}, listeners = {} };
	local known = {
		random_number = function(_, n) return math.random(n) end,
		model = function() return { turn_number = function() return state.turn end } end,
		add_listener = function(self, name, event, cond, fn) self.listeners[name] = fn end,
		remove_listener = function(self, name) self.listeners[name] = nil end,
		register_saving_game_callback = function(self, fn) self.save_cb = fn end,
		register_loading_game_callback = function(self, fn) self.load_cb = fn end,
		save_value = function(self, key, value) self.saved[key] = value end,
		load_value = function(self, key, default) if self.saved[key] ~= nil then return self.saved[key] end return default end,
	};
	return setmetatable(cm, { __index = function(_, name)
		if known[name] then return known[name] end;
		return function(self, ...)
			self.calls[#self.calls + 1] = { name = name, ... };
		end;
	end });
end;

local function count_calls(cm, name)
	local n = 0;
	for _, call in ipairs(cm.calls) do if call.name == name then n = n + 1 end end;
	return n;
end;

-- Fireforged's scripts in a fresh script environment, then the mod on top. overrides(env) runs between the two.
local function boot(overrides, config)
	math.randomseed(1);
	local state = { turn = 1 };
	local env = setmetatable({}, { __index = _G });
	local cm = new_cm(state);
	env.cm = cm;
	_G.get_cm = function() return cm end;
	_G.script_env = env;
	env.output = function() end;
	env.script_error = function(message) error("script_error: " .. tostring(message), 0) end;
	env.IsValidSpawn = function() return true end;

	-- the random army module, loaded as `module(..., package.seeall)` would
	local ram = setmetatable({ module = function() end, cm = cm }, { __index = _G });
	load_into(ram, root .. "/extracted/game/data/campaigns/main_attila/sands/random_army.lua", "random_army");
	env.ram = ram;

	load_into(env, ff_scripts .. "/att_preservation_data.lua", "att_preservation_data");
	load_into(env, ff_scripts .. "/antonina_incident.lua", "antonina_incident");

	if overrides then overrides(env, cm, state) end;

	for name in pairs(package.loaded) do
		if name:match("^fireforged_fixes/") then package.loaded[name] = nil end;
	end;
	package.path = root .. "/mods/fireforged_fixes/?.lua;" .. package.path;
	require("fireforged_fixes/core").patched = {};
	if config then
		for key, value in pairs(config) do require("fireforged_fixes/core").config[key] = value end;
	end;
	local ok, err = pcall(require, "fireforged_fixes/init");
	assert(ok, err);
	return env, cm, state;
end;

local function fake_context(name, human, treasury)
	local faction = {
		is_human = function() return human end,
		name = function() return name end,
		treasury = function() return treasury end,
	};
	return { faction = function() return faction end };
end;

-- 1. the bug: the original pools run dry and raise an error; the replacement doesn't
do
	local original = boot(nil, { spawn_points = false });
	local ok = true;
	for _ = 1, 3 do ok = pcall(original.FindSpawn2) and ok end;
	check(not ok, "original FindSpawn2: the third call (2 points) should fail");

	local env = boot();
	local positions = {};
	for i = 1, 10 do
		local pos = env.FindSpawn2();
		check(pos and pos.x and pos.y, "FindSpawn2 call " .. i .. " returns a point");
		positions[#positions + 1] = pos;
	end;
	for i = 1, 8 do check(env.FindGermaniaSpawn(), "FindGermaniaSpawn call " .. i) end;
	check(#env.army_east <= 2, "pool is never larger than its original size");
end;

-- 2. valid points are preferred, a pool with no valid point still returns one
do
	local env = boot(function(env) env.IsValidSpawn = function(x, y, safe) return x == 935 end end);
	check(env.FindSpawn2().x == 935, "the valid point is picked first");
	check(env.FindSpawn2() ~= nil, "then the other one, although invalid");

	local env2 = boot(function(env) env.IsValidSpawn = function() return false end end);
	check(env2.FindSpawn2() ~= nil, "no valid point: any point");

	-- far-from-armies points win over merely free ones
	local env3 = boot(function(env) env.IsValidSpawn = function(x, y, safe) return not safe or x == 940 end end);
	check(env3.FindSpawn2().x == 940, "the safe point is picked first");
end;

-- 3. the turn-48 call runs once, the flagged call on turn 10 still runs
do
	local env, cm, state = boot();
	env.Add_Barbarian_Invasion_Listeners();
	state.turn = 10;
	env.Hunn_Spawn();
	check(count_calls(cm, "create_force") == 1, "turn 10: one force");
	state.turn = 48;
	for _ = 1, 40 do env.Hunn_Spawn() end;
	check(count_calls(cm, "create_force") == 2, "turn 48: one more force, not 40 (got " .. count_calls(cm, "create_force") .. ")");
	check(cm.saved.fireforged_fixes_hunn_turn48 == nil, "nothing saved before a save");
	cm.save_cb(nil);
	check(cm.saved.fireforged_fixes_hunn_turn48 == true, "the turn-48 flag is saved");
end;

-- 4. the Antioch template
do
	local env, cm = boot();
	env.Add_Barbarian_Invasion_Listeners();
	local found, bad = 0, 0;
	for _, force in ipairs(env.ram.force_list) do
		if force.key == "voiska_Antiohia" then
			for _, list in ipairs({ force.units, force.mandatory_units }) do
				for _, key in ipairs(list) do
					if key == "rex_rom_legionis_defensores" or key == "rex_rom_equites_clibanarii_parthi" then bad = bad + 1 end;
					if key == "att_rom_comitatensis_spears" or key == "att_rom_clibanarii" then found = found + 1 end;
				end;
			end;
		end;
	end;
	check(bad == 0, "voiska_Antiohia has no land unit keys left");
	check(found == 7, "voiska_Antiohia has the main unit keys, weights 5 + 2 (got " .. found .. ")");
end;

-- 5. inflation: same tiers as Fireforged's, any human faction
do
	local env, cm = boot();
	local function run(func, name, human, treasury)
		cm.calls = {};
		env[func](fake_context(name, human, treasury));
		local call = cm.calls[1];
		return call and (call.name .. ":" .. call[1] .. ":" .. tostring(call[2]) .. ":" .. tostring(call[3])) or "none";
	end;
	check(run("Inflation", "att_fact_antes", true, 60000) == "apply_effect_bundle:rex_bundle_inflation:att_fact_antes:2", "tier 0 applies to Antes");
	check(run("Inflation", "att_fact_antes", true, 49999) == "remove_effect_bundle:rex_bundle_inflation:att_fact_antes:nil", "tier 0 removed below 50000");
	check(run("Inflation", "att_fact_antes", true, 100000) == "none", "tier 0 does nothing from 100000");
	check(run("Inflation1", "att_fact_dani", true, 150000):find("rex_bundle_inflation1") ~= nil, "tier 1 applies at 150000");
	check(run("Inflation2", "att_fact_sclaveni", true, 250000):find("rex_bundle_inflation2:att_fact_sclaveni:2") ~= nil, "tier 2 applies at 250000");
	check(run("Inflation2", "att_fact_sclaveni", true, 199999):find("remove") ~= nil, "tier 2 removed below 200000");
	check(run("Inflation", "att_fact_franci", false, 60000) == "none", "AI factions get nothing");
end;
do
	local env, cm = boot(nil, { inflation_all_factions = false });
	cm.calls = {};
	env.Inflation(fake_context("att_fact_antes", true, 60000));
	check(#cm.calls == 0, "inflation_all_factions = false: Antes is skipped as in Fireforged");
	env.Inflation(fake_context("att_fact_franci", true, 60000));
	check(#cm.calls == 1, "inflation_all_factions = false: Franci still gets it");
end;

-- 6. Hun preservation distances
do
	local env = boot();
	check(env.HUN_PRESERVATION_SYSTEM_SAFE_PLAYER_DISTANCE_TO_SPAWNPOINT_SQUARED == 400, "player distance 400");
	check(env.HUN_PRESERVATION_SYSTEM_SAFE_HUNNIC_AI_DISTANCE_TO_SPAWNPOINT_SQUARED == 14, "Hunnic distance 14");
	check(env.HUN_PRESERVATION_SYSTEM_SAFE_AI_DISTANCE_TO_SPAWNPOINT_SQUARED == 19, "AI distance stays Fireforged's 19");
	check(env.HUN_PRESERVATION_SYSTEM_SAFE_DISTANCE_TO_BATTLE_SQUARED == 26, "battle distance stays Fireforged's 26");
end;

-- 7. one failing function doesn't stop the others
do
	local ran = {};
	local env = boot(function(env)
		env.Great_Exodus = function() error("boom") end;
		env.TRIGGERED_Exodus = function() ran[#ran + 1] = "TRIGGERED_Exodus" end;
	end);
	local ok = pcall(function() env.Great_Exodus(); env.TRIGGERED_Exodus() end);
	check(ok, "an error in Great_Exodus doesn't escape");
	check(ran[1] == "TRIGGERED_Exodus", "the next function runs");
	local ff = require("fireforged_fixes/core");
	local total = 0;
	for _, count in pairs(ff.errors) do total = total + count end;
	check(total == 1, "the error is counted");
end;

-- 8. optional turn-1 dedupe
do
	local calls = 0;
	local env, cm, state = boot(function(env)
		env.Great_Invasion = function() calls = calls + 1; env.WRE_TRIGGERED = (env.WRE_TRIGGERED or 0) + 1 end;
	end, { dedupe_turn1 = true });
	for _ = 1, 50 do env.Great_Invasion() end;
	check(calls == 1 and env.WRE_TRIGGERED == 1, "dedupe_turn1: turn 1 runs once (" .. calls .. " calls)");
	state.turn = 2;
	env.Great_Invasion();
	check(calls == 2, "other turns are untouched");
end;
do
	local calls = 0;
	local env = boot(function(env)
		env.Great_Invasion = function() calls = calls + 1 end;
	end);
	for _ = 1, 5 do env.Great_Invasion() end;
	check(calls == 5, "dedupe_turn1 is off by default");
end;

-- 9. slot report: counts the settlements the startpos fix should have given an extra slot
do
	local _, cm = boot();
	local counts = {
		att_reg_maxima_sequanorum_argentoratum = 3,
		att_reg_bithynia_ancyra = 6,
		att_reg_cappadocia_caesarea_eusebia = 6,
		att_reg_palaestinea_nova_trajana_bostra = 6,
	};
	local manager = { region_by_key = function(_, key)
		return { slot_list = function() return { num_items = function() return counts[key] end } end };
	end };
	cm.model = function() return { world = function() return { region_manager = function() return manager end } end } end;
	local slots = require("fireforged_fixes/slots");
	check(slots.report() == 1, "slot report: Argentoratum with 3 slots is short");
	counts.att_reg_maxima_sequanorum_argentoratum = 4;
	check(slots.report() == 0, "slot report: none short with the fix");
	local ok, err = pcall(fireforged_fixes.report);
	check(ok, "report runs (" .. tostring(err) .. ")");
end;

-- 10. nothing to do without Fireforged
do
	_G.script_env = nil;
	for name in pairs(package.loaded) do
		if name:match("^fireforged_fixes/") then package.loaded[name] = nil end;
	end;
	local env_before = rawget(_G, "Great_Invasion");
	local ok, err = pcall(require, "fireforged_fixes/init");
	check(ok and env_before == nil, "without Fireforged the mod loads and does nothing (" .. tostring(err) .. ")");
end;

say(string.format("%d checks, %d failed", checks, failures));
os.exit(failures == 0 and 0 or 1);
