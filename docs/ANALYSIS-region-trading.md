# Region trading – analysis (Phase 3)

2026-10-04. Sources: `extracted/rtr`, `extracted/fireforged/1`, `extracted/game` (see `tools/extract-all.sh`), the Lua binding names in the game binary (`strings`), and `~/GitHub/twase_macos/docs/addresses.md`.

## The `maga` framework (Region Trading Reloaded, author "Hardballer")

About 1,900 lines of Lua, loaded by one line at the end of `campaigns/<campaign>/scripting.lua`: `require("maga/init")`.

| File | Role |
|---|---|
| `maga/init.lua`, `namespace.lua`, `config.lua` | module table `maga`, config (`enableLog = false`) |
| `maga/events.lua` | listeners: `CharacterCreated`, `FactionTurnStart`, `PanelOpenedCampaign` / `PanelClosedCampaign`, `UICreated`; helpers for `ComponentLClickUp` / `ComponentMouseOn` |
| `maga/core/common/*` | log file writer (`data/campaigns/<campaign>/maga_log.txt`), `maga.nextTick` (via `add_time_trigger(id, 0)`), string split |
| `maga/core/model*` | thin `Faction` wrapper (region count) |
| `maga/core/uic/*` | UI component classes: create from layouts in `ui/bin/<type>/<name>` via `root:CreateComponent`, re-parent with `Adopt`, delete via a garbage component, click / hover callbacks by component address |
| `maga/script/regionTrading.lua` | **the mechanics** (127 lines, see below) |
| `maga/script/ui.lua` | routes panel events to the three UI modules |
| `maga/script/ui/diplomacyDropdown.lua` | tracks the selected faction in the diplomacy list (polls every tick, only on the player's turn) |
| `maga/script/ui/offersPanel.lua` | adds the "trade region" button next to "counter offer" in the offers panel, enables it when `canTradeWith` |
| `maga/script/ui/regionTrading.lua` | **the trading panel** (505 lines): hides the offers panel, shows a frame with OK / cancel, opens the tactical map, hides everything but the two factions' settlements, greys out untradable ones, colours regions with one overlay image per region and colour (`ui/bin/img/map/<region>_{green,yellow}` + PNGs, about 1,800 files for all 3 campaigns), click a settlement to select it |
| `maga/script/ui/clanPanel.lua` | patches the faction stats ("regions lost") so traded / gifted regions don't count as lost |
| `maga/data/<campaign>/regions.lua` | province → regions lists, **never required** (dead code) |

### Mechanics (`maga/script/regionTrading.lua`)

- `canTradeWith(faction)`: not if the player already traded this turn (one trade per turn), the player or the other faction is a horde, or they're at war. **No check of attitude, alliance or AI consent.**
- `canTrade(region, faction)`: not the player's or the faction's capital (`home_region`), not under siege.
- `gift(region, faction)`: `transferRegion(region, faction)`.
- `trade(playerRegion, aiRegion)`: two `transferRegion` calls, a straight swap.
- `transferRegion`: `cm:transfer_region_to_faction(region, faction)`. Transferring a province capital kills its governor, so the governor is made immortal first (`set_character_immortality`), and the `CharacterCreated` event the "death" fires is used to make the new character mortal again.
- Saved values: `MAGA_RegionTrading_PlayerHasTraded`, `…_RegionsGifted`, `…_RegionsTraded`.

The AI never decides anything: every trade the player clicks is executed.

## Fireforged Empire's changes

Fireforged ships a copy of the whole `maga` tree (and identical UI assets). Only two files differ from RTR:

- `maga/script/ui/regionTrading.lua`: the title "Region trading" → "Region for money or troops". Nothing else.
- `maga/script/regionTrading.lua`:
  - `gift`: the player additionally gets **3,000 gold** (`cm:treasury_mod(player, 3000)`).
  - `trade`: the player's region goes to the AI and the player gets the effect bundle **`rex_bundle_treaty_federates_region` for 16 turns**; the AI region is **not** transferred (that line is commented out). The bundle (Fireforged DB `_rex_effect_bundles`, "Treaty of federates") is `att_effect_unit_recruitment_points` +2, `faction_to_province_own`: +2 recruitment slots in every own province.

`campaigns/main_attila/scripting.lua` in Fireforged has its own additions (`random_army`, `bel_common`, `antonina_incident`, `civil_war_fix`, …) and ends with `require("maga/init")`. Fireforged only covers `main_attila`.

### Where the jank comes from

1. **The UI says something else than what happens.** The panel is RTR's unchanged: selecting only your region shows the "gift" icon and means "money", selecting an AI region too shows the "trade" icon and means "troops", and the AI region you picked stays with the AI.
2. **Fixed rewards:** 3,000 gold or the same troop bundle for any region, from a village to a rich province capital.
3. **The troop bundle probably doesn't stack:** it is always the same bundle key, and re-applying a bundle the faction already has most likely only resets its duration (not verified in game yet), so a second trade within 16 turns would give nothing new.
4. **No AI consent:** any non-war, non-horde faction "accepts", including ones that hate the player.
5. **Fragile UI:** state is tracked by polling every tick (`nextTick` loops), clicks are simulated (`SimulateClick`, `clickWithState`), the selected faction is read from list row states one tick after a click, the panel only works on the player's turn. Region names come from parsing tooltip text.
6. Small: the governor immortality trick relies on `CharacterCreated` firing synchronously inside `transfer_region_to_faction`.

### Why the mods conflict

Both ship `maga/*` at the same paths and both replace `campaigns/main_attila/scripting.lua`. RTR's `scripting.lua` (all 3 campaigns) is the vanilla file plus `require("maga/init")`, nothing else. Fireforged's must win (it loads Fireforged's own scripts), and its `maga` copy then decides the behaviour.

**Consequence for our mod:** with TWASE's loader (`campaigns/<campaign>/mods/<name>/scripting.lua`), the trading code needs no `scripting.lua` of its own. But Fireforged's `scripting.lua` will keep loading its `maga` copy, so we have to neutralise it (Phase 5): either an override pack with higher priority that replaces `maga/init.lua` (or `maga/script/regionTrading.lua`) with a stub, or patching at runtime (our mod is required after `scripting.lua`, so it can remove maga's listeners: they are all named `MAGA_EventHandler_*`, and `cm:remove_listener` takes the name).

## Game side

### Campaign Lua API (native bindings, names from the binary)

Useful **getters** (model interfaces):

- faction: `name`, `region_list`, `home_region` / `has_home_region`, `is_horde`, `is_human`, `allied_with(f)`, `at_war_with(f)`, `num_allies`, `treasury`, `culture`, `state_religion`, `imperium_level`, `military_force_list`, `is_trading_with(f)`
- region: `name`, `owning_faction`, `adjacent_region_list`, `slot_list` → `building` → `name` / `chain` / `superchain`, `num_buildings`, `building_exists`, `public_order`, `majority_religion` / `_percentage`, `region_wealth_change_percent`, `resource_exists`, `squalor`, `sanitation`, `garrison_residence` → `is_under_siege` / `army` / `unit_count`, `has_governor` / `governor`
- campaign AI: `strategic_stance_between_factions(a, b)` and promotion / blocking state of stances
- **Missing:** the AI's attitude towards a faction (the number shown in the diplomacy screen), region income, province of a region, whether a region is a province capital

Useful **actions** (`game_interface`, called as `cm:<name>`):

- `transfer_region_to_faction(region, faction)`, `treasury_mod(faction, amount)`, `apply_effect_bundle(bundle, faction, turns)` / `_to_region` / `_to_force`, `create_force(…)`, `add_unit_to_force(…)`, `grant_unit(…)`, `set_character_immortality`
- diplomacy: `force_diplomacy(faction, target, type, offer, accept)`, `force_make_peace`, `force_declare_war`, `force_make_vassal`, `force_make_trade_agreement`, `force_break_alliance`, …, `faction_offers_peace_to_other_faction`, `cai_strategic_stance_manager_*` (promote / block stances between factions)
- `show_message_event`, `trigger_dilemma` / `trigger_incident` (for AI-initiated offers), `save_named_value` / `load_named_value`

### Native region trading?

`force_diplomacy` still lists **`"regions"`** as a diplomacy type (with "state gift", "payments", "technology", …), and the DB keeps `offer_regions` / `demand_regions` / `reject_*_regions` in `diplomacy_keys`. Nothing in the vanilla scripts disables it. But the AI's deal evaluation (`cai_personality_deal_evaluation_deal_component_names`) has **no region component**, and Attila's diplomacy UI has no region list. It's most likely a leftover from Empire / Rome II.
**To test in game** (TWASE console, cheap): `cm:force_diplomacy(cm:get_local_faction(), "<ai faction>", "regions", true, true)`, then open diplomacy with that faction. If a region option appears and the AI evaluates it, that's a much better base than a Lua UI.

### Deal evaluation (from TWASE)

- Evaluator `0x101d7b25c`, wrapped by `Diplo_GetDisplayedDealScore` `0x101d7e890` `float (deal, cai + 0x788, factionA, factionB)`. The UI buckets the score with thresholds -4 / 4 (low / moderate / high). TWASE already shows the score in the "Likelihood of success" tooltip.
- `EMPIRECAMPAIGNAI::CAI_INTERFACE::get_faction_attitude(FACTION const&, FACTION const&)` exists (RTTI / lambda names). Exposing it as `twase.faction_attitude(a, b)` would give Lua the real attitude.
- DB: `cai_personality_deal_evaluation_deal_component_values` has per-personality values per component and attitude (bitter enemies … best friends) and balance factors (war, tension, peace, …), `diplomatic_relations_attitudes` (7 rows) and `diplomacy_negotiation_attitudes` (4 rows) map attitude values to bands.

### Data for a region value score

- model: buildings via `slot_list` (+ DB `building_levels`: `create_cost`, `upkeep_cost`, prestige columns, `only_in_capital`), adjacency, religion, public order, wealth change
- DB: `region_to_province_junctions` (province of a region, so: "completes a province for the AI"), `provinces`, `region_economics_factors`, `region_religions`, `region_unit_resources`, `regions` (`is_sea`, owner bundle)
- Fireforged changes many of these tables; read them from `extracted/fireforged/1/db` first, then the base game.

## Gaps Lua can't fill → TWASE candidates

1. **AI attitude** between two factions: `CAI_INTERFACE::get_faction_attitude` (address still to find in BN; the lambda name gives a starting point).
2. Optional: the **game's own deal score** for a hypothetical deal, so our score is on the same scale as the "Likelihood" display. Building a native deal object is harder; a Lua-side score with the attitude as input is probably enough.
3. Optional: the region's **income** (the game shows it in the province panel; no Lua getter).

TWASE has no `twase.*` Lua API yet; adding one is a TWASE-side task (register C functions into the `EpisodicScriptingEnv` state after `RunStartupPath`).

## Open questions for Phase 4

- Is native `"regions"` diplomacy usable (test above)? That decides between "enable and tune the native option" and "keep a Lua panel".
- Do we keep RTR's tactical-map panel (works, but heavy and fragile) or a simpler list in the offers panel?
- Fireforged's rewards: keep money / troops, but scaled by region value; troops as a stacking bundle per trade (several bundle keys) or as actual units (`create_force` / `add_unit_to_force`)?
