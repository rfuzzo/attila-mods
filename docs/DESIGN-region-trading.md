# Region trading – design (Phase 4)

Draft 2026-10-04, decisions from the Phase 4 discussion. Background: [`ANALYSIS-region-trading.md`](ANALYSIS-region-trading.md).

## Decisions

| Topic | Decision |
|---|---|
| Partners | any faction at peace with the player (neither side a horde); the AI decides by score, alliance and attitude only change the score |
| Trade types (v1) | region → money, region → troops, region ↔ region |
| Not in v1 | buying regions for money; AI-initiated offers (later, e.g. via dilemmas) |
| Region selection | clicks on settlements on the tactical map (RTR's idea, rewritten), no per-region overlay images |
| Hardcoded data | none hand-written: everything from the game model, the game DB (through TWASE) or the loc |
| Base | our own code as a TWASE mod (`campaigns/<campaign>/mods/region_trading/scripting.lua`, all 3 campaigns); Fireforged's `maga` copy is switched off |

## Rules

- **Who:** player and AI faction at peace; neither is a horde; the AI faction isn't the player's vassal / puppet (to check: should puppets be allowed to receive gifts?).
- **Which regions:** not either side's capital (`home_region`), not under siege, not with an enemy army in it (to check: `garrison_residence():army()` / adjacent armies).
- **How often:** one region trade per AI faction per turn (instead of one per turn overall); a rejected offer can't be repeated with the same faction until the next turn.
- **When:** player's turn only.

## Score

The AI accepts when `score >= 0`, like the game's deals (likelihood display: < -4 low, -4..4 moderate, > 4 high; we show the same three bands plus the number).

```
score = value_for_ai(region_given) - value_for_ai(region_taken)   -- swap; region_taken = 0 for money / troops
        - price                                                   -- money or troops the AI pays, in the same unit
        + relationship(ai, player)
```

**Region value** (`value_for_ai`, for the receiving AI; all scaled to "gold"):

| Part | Source |
|---|---|
| buildings: sum of the building levels' `create_cost` (or a share of it) | model `slot_list` → building key, DB `building_levels` |
| province: bonus if it completes a province for the AI, malus if it breaks one up for the player (only for the player's own valuation display) | DB `region_to_province_junctions` + model `owning_faction` of the other regions |
| contiguity: bonus if it borders the AI's regions, big malus if it's an enclave | model `adjacent_region_list` |
| religion: bonus if `majority_religion` is the AI's `state_religion`, scaled by the percentage | model |
| public order / squalor: malus for unrest | model `public_order`, `squalor` |
| port / resources: bonus | model `resource_exists`, settlement type (to check) |

**Relationship** (in gold too): attitude (from `twase.faction_attitude`; without TWASE: strategic stance + alliance), alliance bonus, trade agreement bonus, recent treachery malus (later).

**Price → what the player gets** (Fireforged's rewards, scaled):

- **money:** the AI pays up to `value * factor`, capped by its `treasury()`. The panel shows the maximum the AI accepts; the player can't ask for more.
- **troops ("federates"):** real units copied from the AI's own armies (`military_force_list` → `unit_list` → `unit_key`), as many as the value buys (unit cost from DB `main_units.recruitment_cost`), spawned as a new army at or next to the traded region (`create_force`) or added to a chosen army. No hardcoded unit lists, the units fit the AI's culture automatically. The AI only gives units it has.
  Fallback if spawning is unreliable: recruitment-slot bundles in a few sizes (Fireforged's `rex_bundle_treaty_federates_region` idea), but stacking by trade.
- **swap:** the other region; the difference has to be ≥ 0 for the AI.

All factors in one config table (`config.lua`), tuned by playing.

## UI

- **Entry:** a "Trade regions" button in the diplomacy offers panel (like RTR), active when the rules allow trading with the selected faction.
- **Panel:** replaces the offers list while open. Shows the player's region, the AI's region or the reward type (money / troops / swap), the price, and the score as low / moderate / high plus the number. Accept / cancel.
- **Map:** the tactical map opens; only the two factions' settlements stay visible, untradable ones greyed out (shader, as in RTR). Click a settlement to select it. No overlay images.
- **Names:** region names from the loc (`twase.localise("regions_onscreen_" .. key)`), not from tooltip text.
- **Robustness:** event-driven where possible; one place with all UI paths; if a path is missing (UI mod, other campaign), the button simply doesn't appear and the log says why.
- **Result:** the AI's answer like vanilla (accept / reject message), then the transfer.

## Execution

- `transfer_region_to_faction`, with RTR's governor immortality trick (keep, but check if it's needed in Attila at all).
- money: `treasury_mod` on both factions (player +, AI −).
- troops: `cm:create_force(faction, "unit_a,unit_b,…", home_region, x, y, army_id, true, callback(cqi))` (used in `bel_attila/lib_spawn_army.lua`, which also has a free-coordinate search to reuse); unit cost from DB `main_units.recruitment_cost`. `add_unit_to_force` as the alternative.
- the faction stats correction from RTR's `clanPanel` (traded regions don't count as "lost"): keep.
- saved state: trades per faction this turn, totals for the stats.

## TWASE work this needs

1. `twase.faction_attitude(a, b)`: `CAI_INTERFACE::get_faction_attitude`.
2. `twase.localise(key)`: the game's loc lookup.
3. DB access: `twase.db_rows(table)` or targeted getters for `building_levels` (cost), `region_to_province_junctions`, `main_units` (cost). Fallback until then: a Lua data file generated by `twpack` from the merged game + Fireforged DB (generated, but blind to other mods).

Without 1–3 the mod still works with reduced inputs (stance instead of attitude, tooltip names, building count instead of cost), so Lua and TWASE work can go in parallel.

## Switching off Fireforged's `maga`

Preferred: at runtime, our mod (loaded after `scripting.lua`) removes every `MAGA_EventHandler_*` listener and deletes `maga`'s UI hooks, so no override pack is needed and Fireforged's files stay untouched. Fallback: a small override pack with a stub `maga/init.lua`.

## Open points

- puppets / tributaries: may they trade?
- troops: new army vs. into an existing army; what if the region has no free space (create_force near a settlement)?
- money factor and building share: start values, then tune.
- should the panel show the AI's reasons (like vanilla's "they think …" lines)? Nice, later.
