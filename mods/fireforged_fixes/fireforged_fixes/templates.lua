-- Random army templates (ram.NewForce / AddUnit / AddMandatoryUnit, filled by the Setup*ArmyTemplates functions
-- when the campaign starts). create_force takes main unit keys, the Antioch revolt template (voiska_Antiohia) names
-- two land unit keys instead, so the forces built from it fail or lose those units.

local ff = require("fireforged_fixes/core");

-- land unit key -> main unit key with that land unit
local UNIT_KEYS = {
	rex_rom_legionis_defensores = "att_rom_comitatensis_spears",
	rex_rom_equites_clibanarii_parthi = "att_rom_clibanarii",
};

local function replace_keys(list)
	local count = 0;
	for i = 1, #list do
		local fixed = UNIT_KEYS[list[i]];
		if fixed then
			list[i] = fixed;
			count = count + 1;
		end;
	end;
	return count;
end;

-- Log template units that aren't in the DB's main_units table (twase.unit), once each.
local function validate(forces)
	if not (twase and twase.unit) then
		return 0;
	end;
	local seen, unknown = {}, 0;
	for _, force in ipairs(forces) do
		for _, list in ipairs({ force.units or {}, force.mandatory_units or {} }) do
			for _, key in ipairs(list) do
				if not seen[key] then
					seen[key] = true;
					local ok, record = pcall(twase.unit, key);
					if ok and record == nil then
						unknown = unknown + 1;
						ff.log("template %s: unit %s is not a main unit", tostring(force.key), key);
					end;
				end;
			end;
		end;
	end;
	return unknown;
end;

local function fix(env)
	local ram = env.ram;
	local forces = ram and ram.force_list;
	if type(forces) ~= "table" or #forces == 0 then
		return false;
	end;

	local replaced = 0;
	for _, force in ipairs(forces) do
		replaced = replaced + replace_keys(force.units or {}) + replace_keys(force.mandatory_units or {});
	end;
	ff.log("templates: %d unit keys replaced in %d forces, %d unknown", replaced, #forces, validate(forces));
	return true;
end;

-- The templates are built when the campaign starts, after the mod loaded: fix them right after.
-- (If they exist already, e.g. the mod was loaded late, fix them now.)
local function apply(env)
	if not ff.config.template_unit_keys then
		return;
	end;
	ff.wrap(env, "Add_Barbarian_Invasion_Listeners", function(original)
		return function(...)
			local results = { original(...) };
			local ok, err = pcall(fix, env);
			if not ok then
				ff.record_error("template fix", err);
			end;
			return unpack(results);
		end;
	end);
	pcall(fix, env);
end;

return { apply = apply, fix = fix, UNIT_KEYS = UNIT_KEYS };
