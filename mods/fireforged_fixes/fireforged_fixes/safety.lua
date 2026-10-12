-- Fireforged's FactionTurnStart listeners call these functions one after the other from one callback. An error in
-- one aborts the callback, so the functions after it don't run for that faction and turn (an exhausted spawn pool
-- on turn 48 took Great_Exodus, the respawns and the inflation down with it). pcall each of them, log the error
-- once, carry on.

local ff = require("fireforged_fixes/core");

local FUNCTIONS = {
	"Great_Invasion",
	"Immortality_Character_Check",
	"TRIGGERED_Exodus",
	"Great_Exodus",
	"Inflation",
	"Inflation1",
	"Inflation2",
	"Dogovor_Federati",
};

local function apply(env)
	for _, name in ipairs(FUNCTIONS) do
		ff.wrap(env, name, function(original)
			return function(...)
				local ok, err = pcall(original, ...);
				if not ok then
					ff.record_error(name, err);
				end;
			end;
		end);
	end;
end;

return { apply = apply };
