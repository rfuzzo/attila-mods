-- Fireforged Empire fixes: entry point, required by campaigns/main_attila/mods/fireforged_fixes/scripting.lua.
-- Patches Fireforged's globals after its scripts loaded. Findings and reasons: docs/REVIEW-fireforged-scripts.md.

local ff = require("fireforged_fixes/core");

ff.log("version %s loading", ff.version);

local env = ff.find_env();
if not env then
	ff.log("Fireforged's scripts (Great_Invasion) not found, nothing to fix");
	return;
end;

-- For the console: fireforged_fixes.report()
fireforged_fixes = ff;
ff.env = env;

if ff.config.spawn_points then require("fireforged_fixes/spawn").apply(env) end;
require("fireforged_fixes/inflation").apply(env);
require("fireforged_fixes/preservation").apply(env);
require("fireforged_fixes/templates").apply(env);
require("fireforged_fixes/events").apply(env);
-- last, so it wraps the functions the modules above replaced or wrapped
if ff.config.safe_calls then require("fireforged_fixes/safety").apply(env) end;

-- What got patched, how often a wrapped function failed, the spawn pools left, the slots of the settlements
-- the startpos fix adds one to.
function ff.report()
	local names = {};
	for name in pairs(ff.patched) do names[#names + 1] = name end;
	table.sort(names);
	ff.log("version %s, %d patched: %s", ff.version, #names, table.concat(names, ", "));

	local failed = 0;
	for message, count in pairs(ff.errors) do
		failed = failed + count;
		ff.log("  %dx %s", count, message);
	end;
	ff.log("%d errors caught", failed);

	for func, pool in pairs(require("fireforged_fixes/spawn").POOLS) do
		local points = env[pool];
		if type(points) == "table" and #points < 2 then
			ff.log("  spawn pool %s (%s) has %d left", pool, func, #points);
		end;
	end;

	require("fireforged_fixes/slots").report();
end;

local patched = 0;
for _ in pairs(ff.patched) do patched = patched + 1 end;
ff.log("loaded, %d functions and constants patched", patched);
