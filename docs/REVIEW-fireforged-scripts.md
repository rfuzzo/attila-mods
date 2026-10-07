# Fireforged Empire scripts: review and fixes

Review of the Lua in `@Fireforged-Empire_1.pack` (2026-10-06): `campaigns/main_attila/*.lua`, `sands/`, `factions/`, `maga/`. Method: all files parsed with `luac -p`; every unit, effect bundle, incident, faction and region key checked against the DB tables; each file diffed against vanilla; trigger flags and spawn-point pools traced with scripts. **Nothing was run in the game**, so the effects below are read from the code. Line numbers are those of the extracted files (`extracted/fireforged/1/campaigns/main_attila/`).

The fixes are the mod `mods/fireforged_fixes/`: it patches Fireforged's globals after its scripts loaded (TWASE loads mods after the campaign's `scripting.lua`), no Fireforged file is edited. Tests: `lua tests/fireforged_fixes.lua` (runs the real scripts with a stubbed `cm`). Console: `fireforged_fixes.report()`. Switches: `fireforged_fixes/config.lua`.

## Fixed by the mod

| # | Where | Problem | Fix |
|---|---|---|---|
| 1 | `antonina_incident.lua` `FindXxx` (40 copies, e.g. `:5104-5126`) | Each pops the point it returns from a global array, nothing refills it, and some arrays are smaller than their caller count: `army_east` 2 points for 3 Iranian Hun armies (`:2202,2232,2262`), `army_germania` 4 points for 8 Germanic spawns and respawns (`:3698-4192`). Empty array: `cm:random_number(0)` script error, the spawn is lost. The fallback line after the loops reads `randomSpawn`, out of scope there. | `spawn.lua`: all 40 replaced by one picker (valid points first, pool refilled when used up). |
| 2 | `:825` `if turn_number == 48 then Hunn_Spawn() end` | No flag, runs once per faction turn start. With the pool empty (1) it errors about 50 times; an error aborts the listener callback, so `Great_Exodus`, the respawns and `Inflation` are skipped for that faction. | `events.lua`: runs once (saved in the save game). `safety.lua`: the per-turn functions run in `pcall`, errors are logged once and counted. |
| 3 | `:5846,5850` | `voiska_Antiohia` (Antioch revolt, turn 81) uses the land unit keys `rex_rom_legionis_defensores` and `rex_rom_equites_clibanarii_parthi`; `create_force` needs main unit keys. 7 of the 16 weighted slots are bad, so nearly every force has one. | `templates.lua` swaps them for `att_rom_comitatensis_spears` (`att_rom_western_auxilia_palatina` has the same land unit) and `att_rom_clibanarii`, and logs template units unknown to `main_units` (`twase.unit`). |
| 4 | `att_preservation_data.lua:11-14` | The constants are squared distances (`distance_squared() < constant`). Player 20 (comment: 20 hexes, vanilla 400) and Hunnic 24 (vanilla 14, bigger than the AI value 19) look unsquared. | `preservation.lua`: 400 and 14. Battle (26) and AI (19) stay, they read as tuning. |
| 6 | `:1258-1619` `Inflation`, `Inflation1`, `Inflation2` | Three 27-branch `elseif` chains; Antes, Sclaveni, Dani and Venedi never get inflation. | `inflation.lua`: same tiers (50k / 100k / 200k), bundles and duration, any human faction (`inflation_all_factions = false` restores the 27). |

## Not fixed on purpose

- **5. `WRE_TRIGGERED`** (`:554`, `:1063`): the turn-1 block of `Great_Invasion` runs once per faction, so `WRE_TRIGGERED` counts to about 50, and `Great_Exodus` waits for `== 1`. That branch kills the Eastern Roman leader (`VALENT_DEAD`) when the West drops below 6 regions, and has probably never run. Fixing it turns that on, so it is off (`dedupe_turn1`). The mod logs `WRE_TRIGGERED` at turn 2; if it is 1 the premise is wrong.
- **Climate phases** (`att_climate_change.lua:37-52`): shifted by one, phase 1 (turn 19) does nothing, Attila is born at turn 99, there is no sixth seal, so no scripted death. Probably intended.
- **Turn-1 Zero armies** (`:550-626`): `ZERO_TRIGGERED < 16` counts spawns, so if the player is one of the 15 conditional factions a second batch starts on the next faction's turn and one army repeats.
- `factions/att_fact_suebi_intro.lua` has a UTF-8 BOM (Lua 5.1 rejects it; the `pcall` around the intro `require` turns it into a warning). Fixing it needs a replacement file.
- `1att_preservation_data.lua` is never loaded (leftover test values: 57 Hun armies per turn). `maga/doc.lua` is documentation, not Lua. `random_army.lua` is an identical copy of the sands module whose `ram` binding is overwritten at `scripting.lua:123`; the module itself has `RemoveForce` calling `table.remove(i)` and a `NewForce` duplicate check that compares a key to a table (both from vanilla).
- `civil_war_string.lua`: the Tanukhids civil war bundle is `""`; `civil_war_fix.lua` `FactionIsAlive` returns `nil` for a missing key. Harmless in practice.
- `att_attila_story.lua:130` uses an undefined `attila` (vanilla bug; only when the Huns are player-controlled).
- `if not faction == faction:is_human()` (`:631-675`) works only through operator precedence.
- `Great_Exodus` (`:947-970`) calls `faction_by_key(...):region_list()` for 18 factions without a null check; fine as long as they all exist in the campaign.
- Everything in `antonina_incident.lua` runs once per faction turn start. The repeated `force_declare_war` and `Obbyavit_*` calls are idempotent; spawn counts that use `< 2` / `< 4` ranges depend on how many AI factions play before the flag trips.

## Checked and fine

All unit keys in scripts except the two above (main_units), all effect bundles, incidents, faction keys and region keys exist. Save and load are complete for all 69 state variables in `antonina_incident.lua`. The civil war tables cover every playable faction. The sands changes (unit keys, Tanukhids building and turn) are consistent. The faction intro scripts are emptied on purpose (no intro cutscenes) and the callers guard for it.
