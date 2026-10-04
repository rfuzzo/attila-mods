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
| Historical basis | Fireforged's spirit: the trades model late-antique practice (see below), not a land market |
| Base | our own code as a TWASE mod (`campaigns/<campaign>/mods/region_trading/scripting.lua`, all 3 campaigns); Fireforged's `maga` copy is switched off |

## Rules

- **Who:** player and AI faction at peace; neither is a horde. Puppets / tributaries / clients may trade (historically the typical case: Rome and Persia granting land to client kings, e.g. Lazica, Armenia).
- **Which regions:** not either side's capital (`home_region`), not under siege, not with an enemy army in it (to check: `garrison_residence():army()` / adjacent armies).
- **How often:** one region trade per AI faction per turn (instead of one per turn overall); a rejected offer can't be repeated with the same faction until the next turn.
- **When:** player's turn only.

## Historical basis

- **Region → troops = the *foedus*.** Rome granted land to a people in exchange for military service under their own leaders: Franks in Toxandria (Julian, 358), Goths in Thrace (382), Visigoths in Aquitania (Constantius, 418), Burgundians in Sapaudia (Aetius, 443). The federates then fought beside the Roman general (Visigoths with Aetius at the Catalaunian Plains, 451). These settlements were concluded by the general in the field, so this deal **needs a player general** at the region and the troops **join his army**.
- **Region ↔ region = partition between powers.** E.g. Armenia divided between Rome and Persia (387). Embassies suffice.
- **Region → money:** the weakest historically. Gold mostly flowed the other way, as subsidies / tribute for peace (Rome to the Huns: Margus 435, Anatolius 443 with 6,000 lb plus 2,100 lb a year). Kept for gameplay, but modest, and preferably paid as **regular payments** over several turns (like vanilla's "Payments"), which is closer to how subsidies worked.
- **Envoy vs. general:** embassies concluded many treaties (Anatolius 443, Maximinus and Priscus to Attila 449), so money and swap deals don't need a general, but a general present (in the region or next to it) improves the score, scaled by his rank / gravitas.
- Idea for later, the most common case in the period: **region for peace** (Jovian ceding Nisibis to Persia, 363; Attila demanding a strip south of the Danube, 449). It would need trading while at war, so not v1.

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

- **money:** as regular payments over N turns (default) or a lump sum (smaller). The AI pays up to `value * factor`, capped by what its `treasury()` allows. The panel shows the maximum the AI accepts. If the AI can't pay an instalment, the deal ends and its attitude drops (needs TWASE or an effect bundle to model).
- **troops ("federates"):** real units copied from the AI's own armies (`military_force_list` → `unit_list` → `unit_key`), as many as the value buys (unit cost from DB `main_units.recruitment_cost`). No hardcoded unit lists, the units keep the AI's culture, as federates did. The AI only gives units it has.
  - Requires a **player army with a general in the traded region or an adjacent one** (the general concludes the foedus). The units join that army (`add_unit_to_force`), limited by its free slots; the panel shows how many fit. No new army: federates served under the Roman commander, and `create_force` would also bypass the army cap.
  - The player pays the units' upkeep (historically the *annona* Rome paid its federates).
  Fallback if spawning is unreliable: recruitment-slot bundles in a few sizes (Fireforged's `rex_bundle_treaty_federates_region` idea), but stacking by trade.
- **swap:** the other region; the difference has to be ≥ 0 for the AI.

All factors in one config table (`config.lua`), tuned by playing.

### Start values

Reference numbers (2026-10-04): building `create_cost` median 2,000 / p90 7,500 in Fireforged (vanilla 4,000 / 9,000, so Fireforged rebalances buildings and we must read the loaded DB, not vanilla); unit `recruitment_cost` median 500, p10 200, p90 1,700 in Fireforged. Negotiation attitude bands: friendly ≥ 25, hostile ≤ −20.

| Factor | Start value | Idea |
|---|---|---|
| land base | 1,500 per region, ×2 for a province capital | land is worth something even without buildings |
| buildings | 40 % of `create_cost`, × the building's `percent_health` | the AI gets the infrastructure, but used, and has to pay its upkeep |
| completes a province for the AI | +30 % of the region's value | |
| enclave (no adjacent AI region) | −50 % | historically, separated federate land was a liability |
| religion | ±20 %, scaled by `majority_religion_percentage` (+ same as the AI's state religion, − different) | Arian / Nicene / pagan mattered a lot |
| unrest | −1 % per point of negative public order | |
| money, lump sum | AI pays 50 % of the value, at most 50 % of its treasury | |
| money, payments | AI pays 70 % of the value spread over 10 turns | more in total because it's deferred and risky |
| troops | units worth up to 80 % of the value in `recruitment_cost` | e.g. a 4,000 region ≈ 6 median units; plus upkeep for the player |
| attitude | 20 gold per attitude point | friendly (25) ≈ +500, hostile (−20) ≈ −400 |
| alliance / client state | +15 % / +25 % of the deal value | |
| general present | +5 % per rank level (or gravitas), only for money / swap | |
| bands | low < −10 % of the deal value, high > +10 % | the same three bands as vanilla's likelihood |

Alternative for the land base: the region's income × 10 turns ("a decade of revenue", how land was valued for taxes). Self-calibrating with any economy mod, but there's no Lua getter for region income (TWASE item 4).

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
- troops: `cm:add_unit_to_force(unit_key, force_cqi)` per unit, into the negotiating general's army (general: `character:region()` is the traded region or adjacent, `military_force():unit_list():num_items()` for free slots). `create_force` (see `bel_attila/lib_spawn_army.lua`) only if we ever want a separate federate army.
- money as payments: a saved list of running deals, `treasury_mod` on both sides at each of the AI's turn starts.
- the faction stats correction from RTR's `clanPanel` (traded regions don't count as "lost"): keep.
- saved state: trades per faction this turn, totals for the stats.

## TWASE work this needs

1. `twase.faction_attitude(a, b)`: `CAI_INTERFACE::get_faction_attitude`.
2. `twase.localise(key)`: the game's loc lookup.
3. DB access: `twase.db_rows(table)` or targeted getters for `building_levels` (cost), `region_to_province_junctions`, `main_units` (cost). Fallback until then: a Lua data file generated by `twpack` from the merged game + Fireforged DB (generated, but blind to other mods).

4. Optional: region income (no Lua getter), for the alternative land value.

Without 1–3 the mod still works with reduced inputs (stance instead of attitude, tooltip names, building count instead of cost), so Lua and TWASE work can go in parallel.

## Switching off Fireforged's `maga`

Preferred: at runtime, our mod (loaded after `scripting.lua`) removes every `MAGA_EventHandler_*` listener and deletes `maga`'s UI hooks, so no override pack is needed and Fireforged's files stay untouched. Fallback: a small override pack with a stub `maga/init.lua`.

## Open points

- the general requirement for troops: same region only, or adjacent too (current draft: adjacent too)?
- federate loyalty (they rebelled more than once: Alaric 395): units with a loyalty risk, or a later "foedus broken" event? Later.
- later: the AI's reasons in the panel (like vanilla's "they think …" lines); region for peace; AI-initiated offers.
