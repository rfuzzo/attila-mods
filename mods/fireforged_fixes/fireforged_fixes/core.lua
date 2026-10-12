-- Shared module table and helpers.

local ff = {};

ff.version = "0.1.0";
ff.config = require("fireforged_fixes/config");
ff.patched = {};   -- name -> true, for the report
ff.errors = {};    -- "function: message" -> count

function ff.log(fmt, ...)
	print("[fireforged_fixes] " .. string.format(fmt, ...));
end;

-- The campaign manager instance. The global `cm` isn't visible in every Lua context, get_cm() is.
function ff.cm()
	return get_cm();
end;

-- Fireforged's campaign scripts (antonina_incident.lua, att_preservation_data.lua, ...) define their functions
-- and flags as globals of the campaign's script environment (scripting.lua stores it as _G.script_env).
-- Their listeners look those globals up by name when they fire, so assigning there replaces the code.
-- Returns the table that holds Great_Invasion, or nil when Fireforged's scripts aren't loaded.
function ff.find_env()
	local candidates = { rawget(_G, "script_env") };
	if getfenv then
		candidates[#candidates + 1] = getfenv(1);
	end;
	candidates[#candidates + 1] = _G;
	for _, env in ipairs(candidates) do
		if type(env) == "table" and type(env.Great_Invasion) == "function" then
			return env;
		end;
	end;
	return nil;
end;

-- Replace the global function `name` in env with make(original). false when env has no such function.
function ff.wrap(env, name, make)
	local original = env[name];
	if type(original) ~= "function" then
		ff.log("%s not found, not patched", name);
		return false;
	end;
	env[name] = make(original);
	ff.patched[name] = true;
	return true;
end;

-- An error caught in a wrapped function: log the first of each kind, then every 100th.
function ff.record_error(name, err)
	local key = name .. ": " .. tostring(err);
	local count = (ff.errors[key] or 0) + 1;
	ff.errors[key] = count;
	if count == 1 or count % 100 == 0 then
		ff.log("%s failed (%d times so far): %s", name, count, tostring(err));
	end;
end;

return ff;
