-- Inflation: three tiers by treasury, a 2-turn effect bundle re-applied every turn while the human faction's
-- treasury is in the tier, removed below it. Fireforged wrote each as a 27-way if/elseif chain on the faction key,
-- which leaves out Antes, Sclaveni, Dani and Venedi. Same thresholds, same bundles, same duration, any human faction.

local ff = require("fireforged_fixes/core");

local TIERS = {
	{ func = "Inflation", bundle = "rex_bundle_inflation", from = 50000, to = 100000 },
	{ func = "Inflation1", bundle = "rex_bundle_inflation1", from = 100000, to = 200000 },
	{ func = "Inflation2", bundle = "rex_bundle_inflation2", from = 200000, to = nil },
};
local DURATION = 2;

-- The factions Fireforged's chains name (for inflation_all_factions = false).
local ORIGINAL_FACTIONS = {};
for _, key in ipairs({
	"att_fact_ostrogothi", "att_fact_visigothi", "att_fact_western_roman_empire", "att_fact_eastern_roman_empire",
	"roman", "att_fact_alani", "att_fact_alamanni", "att_fact_armenia", "att_fact_axum", "att_fact_burgundii",
	"att_fact_ebdani", "att_fact_franci", "att_fact_garamantes", "att_fact_gauti", "att_fact_himyar", "att_fact_iuti",
	"att_fact_langobardi", "att_fact_lakhmids", "att_fact_picti", "att_fact_tanukhids", "att_fact_sassanid_empire",
	"att_fact_saxones", "att_fact_suebi", "att_fact_vandali", "att_fact_votadini", "att_fact_white_huns", "roxolani",
}) do
	ORIGINAL_FACTIONS[key] = true;
end;

local function make_tier(tier)
	return function(context)
		local faction = context:faction();
		if not faction:is_human() then
			return;
		end;

		local name = faction:name();
		if not ff.config.inflation_all_factions and not ORIGINAL_FACTIONS[name] then
			return;
		end;

		local cm = ff.cm();
		local treasury = faction:treasury();
		if treasury < tier.from then
			cm:remove_effect_bundle(tier.bundle, name);
		elseif not tier.to or treasury < tier.to then
			cm:apply_effect_bundle(tier.bundle, name, DURATION);
		end;
	end;
end;

local function apply(env)
	for _, tier in ipairs(TIERS) do
		if type(env[tier.func]) == "function" then
			env[tier.func] = make_tier(tier);
			ff.patched[tier.func] = true;
		else
			ff.log("%s not found, not patched", tier.func);
		end;
	end;
end;

return { apply = apply, TIERS = TIERS };
