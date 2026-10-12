-- Hun preservation (att_preservation_data.lua): the distances are squared (distance_squared() < constant).
-- Fireforged changed them to 26 / 19 / 24 / 20, which reads like unsquared distances for the last two:
--   player:  20 (comment: "don't spawn within 20 hexes of a player army", vanilla 400) -> 4.5 tiles
--   Hunnic:  24 (vanilla 14, "2 hexes") -> 4.9 tiles, more than the AI value of 19, the reverse of the intent
-- The battle (26) and AI (19) values are Fireforged's tuning and stay.

local ff = require("fireforged_fixes/core");

local function set(env, name, value)
	local old = env[name];
	if type(old) ~= "number" then
		ff.log("%s not found, not patched", name);
		return;
	end;
	env[name] = value;
	ff.log("%s: %s -> %s", name, tostring(old), tostring(value));
	ff.patched[name] = true;
end;

local function apply(env)
	if not ff.config.preservation_distances then
		return;
	end;
	set(env, "HUN_PRESERVATION_SYSTEM_SAFE_PLAYER_DISTANCE_TO_SPAWNPOINT_SQUARED", ff.config.player_distance_squared);
	set(env, "HUN_PRESERVATION_SYSTEM_SAFE_HUNNIC_AI_DISTANCE_TO_SPAWNPOINT_SQUARED", ff.config.hunnic_distance_squared);
end;

return { apply = apply };
