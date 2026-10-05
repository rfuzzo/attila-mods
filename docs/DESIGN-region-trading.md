# Region trading – design (Phase 4)

Draft 2026-10-04, decisions from the Phase 4 discussion. Background: [`ANALYSIS-region-trading.md`](ANALYSIS-region-trading.md).

## Direction change (2026-10-04): native deals with a map UI

Attila still has Rome II's region trading in its engine, used only for "Gift Region" to settle hordes. TWASE widens its rules (dev switch `twase.dev_native_region_trading(true)`), and it works end to end: the region is a real deal component, the AI answers, the game transfers the region. Decision (updated): **the native deal and the native region list**, no map UI. Ticking a region in the list pans the map to it, which is enough; one region per deal like vanilla. That gives the native AI answer and transfer, and gold / instalments for free as native Payments.

Regions are weighed against the other diplomacy options in the same deal. Historically accurate: cessions were bundled with other terms (Jovian ceded Nisibis for peace, 363; the Visigoths got Aquitania for military service, 418, i.e. land for an alliance; Valentinian III recognised the Vandal conquests together with a betrothal, 442; Attila's strip south of the Danube on top of the tribute, 449). Consequences: the region value must be on the AI's deal score scale (calibration), and may be negative for the receiver (a distant enclave in revolt is a burden), so a worthless region can't buy an alliance.

Decided 2026-10-04: regions can also be traded **during a war**, in peace negotiations ("region for peace", the most common cession of the period). A region's value **can be negative** for the receiver (no 200 floor); the AI then refuses it as a burden.

| Fireforged / design | Native deal | What we add |
|---|---|---|
| region → gold / instalments | Gift Region + demand Payments | the region's value in the evaluation (TWASE hook; today the deal score gives regions +0.0) |
| region ↔ region | Gift Region + Demand Region (the AI's regions where your army stands, the engine's horde rule reused) | same |
| region → federates | not native | an option (UI to decide), units after acceptance, their cost in the evaluation |

The Lua panel / execution below stay as the fallback; the MAGA-style map UI is dropped.

**AI valuation (done 2026-10-05):** TWASE adds a region's value to the native deal score as the mirror image of the AI paying that much gold (the evaluator only values gold the AI pays), with the value from `value.lua` via `twase.set_region_value_handler`. Tested: demand 2,000 gold −3.1; Ajax (2,103 to the ERE) alone +3.4; 2,000 + Ajax −1.5; 2,000 + Aquae Sextiae (6,069) +13.1.

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

### Implementation (2026-10-04, `mods/region_trading/region_trading/{config,value,deal,explain}.lua`)

- `value = max((wealth − building upkeep) × 10 + 25 % × Σ building create_cost × health, 200) × factors`. The factors (province complete ×1.3, enclave ×0.5, religion ×(1 ± 0.2 × majority share), unrest ×(1 − 1 % per negative public order point, min 0.5)) **multiply**. Deviation from the table below: all buildings count with 25 % of their cost (Lua can't tell economic from non-economic buildings; their yield is in the income anyway).
- relationship, all as shares of the deal value: attitude 1 % per point (capped at ±100 %, decided 2026-10-04: proportional, so the deal itself still matters), alliance 15 %, trade agreement 5 %. Client state bonus: needs a TWASE getter (no vassal check in Lua).
- prices: money 50 % of the value (max 50 % of the AI's treasury), payments 70 % over 10 turns, troops up to 80 % in recruitment cost (copies of the land units in the AI's armies, no bodyguards, mixed, most expensive first), swap: the AI's value of its own region.
- console: `region_trading.explain(region_key, ai_key[, kind[, ai_region_key]])` logs the evaluation with all parts.
- First numbers (WRE 367, Olisipo): value ~1,700 for distant factions (enclave, unrest −20); the Visigoths (attitude −157) and Vandals (−40) refuse everything, the allied ERE (+76) accepts money / payments / troops; swaps fail because the AI values its own regions higher (they're not enclaves for it).

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

**Land value = income (decided 2026-10-04):** `value = (region wealth − building upkeep) × 10 turns + 40 % of the cost of non-economic buildings (military, religious) × health`. Net, not gross: e.g. Corduba has wealth 336 but −200 building upkeep, replacing the "land base" and "buildings" rows above. Historically apt (the late Roman *iugatio / capitatio* assessed land by its yield), self-calibrating with Fireforged's economy, and it covers trade, resources and economic buildings in one number. Use the untaxed GDP, not the current tax take (tax rate, sieges and unrest swing it).
Source: `twase.region_wealth(region)` (verified in game 2026-10-04, matches the province panel); building upkeep from DB `building_levels.upkeep_cost`. The engine keeps per-region GDP by category (`gdp_subsistence`, `gdp_animal_husbandry`, `gdp_farming`, `gdp_local_trade`, `gdp_land_trade`, `gdp_sea_trade`, `gdp_entertainment`, `gdp_learning` in the binary), read through TWASE. Fallback until then: an estimate from the buildings' GDP effects in DB `building_effects_junction` (`att_effect_economy_gdp_*`).

## Federate loyalty

One loyalty value per foedus (per troops deal), saved with the deal (army cqi, the general, the unit keys, the home faction, the region).

| Raises loyalty | Lowers loyalty |
|---|---|
| the concluding general alive and in command | that general dies or loses command (big drop; Alaric rose after Theodosius died, 395) |
| victories, loot | heavy losses among the federate units (Goths at the Frigidus, 394) |
| time: the foedus becomes normal | player's treasury negative / upkeep unpaid (Alaric's demands for gold and grain) |
| good relations with the home faction | war with the home faction (they won't fight their kin) |
| same religion as the player | different religion (small) |

Consequences, escalating:

1. grumbling: morale malus on the army (`apply_effect_bundle_to_force`)
2. demands: a dilemma "pay X gold or refuse" (`trigger_dilemma`, needs DB rows in our pack)
3. uprising: `force_rebellion_in_region(region, n, unit_list, x, y, false)` in the region they were settled in, and the federate units leave the army (needs TWASE item 5; without it the rebels spawn and the army keeps the units)

v1: track loyalty, consequences 1 and 3. v2: the dilemma and real desertion. A strong federate people expanding on its own (Visigoths against Arles 425, Narbonne 436) is out of scope; that's the AI's job.

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

4. **Region GDP** (no Lua getter): needed for the land value, fallback above.
5. Later: remove single units from an army (federate desertion); Lua can only kill whole characters / armies.

Without 1–3 the mod still works with reduced inputs (stance instead of attitude, tooltip names, building count instead of cost), so Lua and TWASE work can go in parallel.

## Switching off Fireforged's `maga`

Preferred: at runtime, our mod (loaded after `scripting.lua`) removes every `MAGA_EventHandler_*` listener and deletes `maga`'s UI hooks, so no override pack is needed and Fireforged's files stay untouched. Fallback: a small override pack with a stub `maga/init.lua`.

## Open points

- the general requirement for troops: adjacent regions too (decided; revisit after playing).
- later: the AI's reasons in the panel (like vanilla's "they think …" lines); region for peace; AI-initiated offers.
