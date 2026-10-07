-- Turn-gated code in Great_Invasion. The function runs from a FactionTurnStart listener, once per faction
-- (about 50 times per turn), and some blocks in it have no "already done" flag.

local ff = require("fireforged_fixes/core");

local SAVE_KEY = "fireforged_fixes_hunn_turn48";
local turn48_done = false;

-- `if turn_number == 48 then Hunn_Spawn() end`: meant as one extra Hun army ("added on turn 48"), but it runs for
-- every faction's turn start. Let the first call through. (Hunn_Spawn() is also the flagged call on turn 10.)
local function hunn_turn48(env)
	if not ff.config.hunn_turn48_once then
		return;
	end;

	ff.wrap(env, "Hunn_Spawn", function(original)
		return function(...)
			if ff.cm():model():turn_number() == ff.config.hunn_turn48 then
				if turn48_done then
					return;
				end;
				turn48_done = true;
				ff.log("turn %d: the extra Hun army spawns once", ff.config.hunn_turn48);
			end;
			return original(...);
		end;
	end);

	ff.cm():register_saving_game_callback(function(context)
		ff.cm():save_value(SAVE_KEY, turn48_done, context);
	end);
	ff.cm():register_loading_game_callback(function(context)
		turn48_done = ff.cm():load_value(SAVE_KEY, false, context);
	end);
end;

-- Optional: the turn-1 block of Great_Invasion (declarations, Zero armies, WRE_TRIGGERED = WRE_TRIGGERED + 1) once.
-- WRE_TRIGGERED >= 1 means a first pass has run (it starts at 0, nothing else raises it before turn 2).
local function dedupe_turn1(env)
	ff.wrap(env, "Great_Invasion", function(original)
		return function(...)
			if ff.config.dedupe_turn1 and ff.cm():model():turn_number() == 1 and (env.WRE_TRIGGERED or 0) >= 1 then
				return;
			end;
			return original(...);
		end;
	end);
end;

-- Log what the turn-1 block left behind, once, at the first faction turn start of turn 2.
local function diagnose(env)
	local cm = ff.cm();
	cm:add_listener("FireforgedFixes_Diagnose", "FactionTurnStart", true, function(context)
		if cm:model():turn_number() < 2 then
			return;
		end;
		ff.log("turn 2: WRE_TRIGGERED=%s ZERO_TRIGGERED=%s (Great_Exodus expects WRE_TRIGGERED == 1)",
			tostring(env.WRE_TRIGGERED), tostring(env.ZERO_TRIGGERED));
		cm:remove_listener("FireforgedFixes_Diagnose");
	end, true);
end;

local function apply(env)
	hunn_turn48(env);
	dedupe_turn1(env);
	diagnose(env);
end;

return { apply = apply };
