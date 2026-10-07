-- Switches for the fixes. Change them here, or from the console before the first turn:
-- fireforged_fixes.config.dedupe_turn1 = true
return {
	-- Wrap Fireforged's per-turn listener functions in pcall, so one error doesn't skip the rest of the turn's work.
	safe_calls = true,

	-- Spawn points: pick one among the valid ones and refill the pool when it is used up (Fireforged's own
	-- pools run dry: 2 points for 3 Iranian Hun armies, 4 for 8 Germanic spawns).
	spawn_points = true,

	-- The unguarded Hunn_Spawn() on turn 48 runs once per faction turn start. Let it run once.
	hunn_turn48_once = true,
	hunn_turn48 = 48,

	-- Antioch revolt force: land unit keys where main unit keys belong, swapped for the right ones.
	template_unit_keys = true,

	-- Hun reinforcement distances (squared, in map units). Fireforged's values for these two are not squared
	-- (20 hexes became 20, 2 hexes became 24); the originals are 400 and 14. The other two are Fireforged's tuning.
	preservation_distances = true,
	player_distance_squared = 400,
	hunnic_distance_squared = 14,

	-- Inflation: Fireforged's three tiers only name 27 factions, so Antes, Sclaveni, Dani and Venedi never
	-- get it. true = every human faction, false = Fireforged's list.
	inflation_all_factions = true,

	-- The turn-1 block of Great_Invasion runs once per faction (about 50 times), which also counts
	-- WRE_TRIGGERED up to about 50; Great_Exodus expects it to be 1 and, if it were, would kill the
	-- Eastern Roman leader when the West falls below 6 regions. Off: that branch stays dead as it is today.
	-- On: turn 1 runs once, the branch can fire. Check the log line "turn 2: WRE_TRIGGERED=..." first.
	dedupe_turn1 = false,
};
