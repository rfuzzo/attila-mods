# Region trading – design

Updated 2026-10-07 for the native approach. Background: [`ANALYSIS-region-trading.md`](ANALYSIS-region-trading.md).
Parts with their own docs: [the region value](DESIGN-region-value.md) and [federates](DESIGN-federates.md) (both
drafts for review).

## Approach: the engine's own region deals

Attila still has Rome II's region trading in its engine (diplomatic action type 6, `DIPLOMATIC_ACTION_TRADE_REGIONS`,
permission "regions"), used only for "Gift Region" to settle hordes. TWASE widens it for a human and a settled AI
faction, so regions become a normal part of the game's diplomacy:

- the AI answers with its own deal evaluation, and regions weigh against gold, treaties and peace in the same deal
- the game's panel, deal list and transfer do the rest; gold and instalments are the native Payments
- what we add: the region's value in the AI's score, the wider rules, a better panel, and later federates

Regions are bundled with other terms, which is historically accurate: Jovian ceded Nisibis for peace (363); the
Visigoths got Aquitania for military service (418); Valentinian III recognised the Vandal conquests together with a
betrothal (442); Attila demanded a strip south of the Danube on top of the tribute (449).

**Superseded (2026-10-04 / 05):** our own "Trade regions" button and Lua panel with map clicks (RTR's idea), and our
own score and execution in Lua. They froze the game and duplicated what the engine already does; the code is in git
history (until commit `4d9163d`).

## Decisions

| Topic | Decision |
|---|---|
| Partners | any settled faction (neither side a horde); the AI decides by its own deal score |
| When | at peace and in peace negotiations during a war ("region for peace", decided 2026-10-04); at war the region entries appear once peace is in the deal (2026-10-07) |
| What | give regions, demand regions, both in one deal (swaps), together with any other terms |
| Value | a region is worth gold to the AI (income, buildings, province, religion, unrest); it may be negative, a burden. See [the region value](DESIGN-region-value.md) |
| Troops | federates, our own addition to native deals. See [federates](DESIGN-federates.md) |
| Hardcoded data | none: everything from the game model, the game DB (through TWASE) or the loc |
| Historical basis | Fireforged's spirit: the trades model late-antique practice, not a land market |
| Base | a TWASE mod (`campaigns/<campaign>/mods/region_trading/scripting.lua`, all 3 campaigns) plus TWASE's native hooks; Fireforged's `maga` copy is switched off |
| Not in v1 | AI-initiated region offers (maybe via dilemmas), the AI's reasons in the likelihood tooltip |

## Rules (TWASE, `Hooks/NativeRegionTrading.cpp`)

- **Available** between a human and a settled AI faction if the human has a region to give (vanilla: only with a
  horde).
- **Regions** either side can give: all but its capital and settlements with an army garrisoned in them (vanilla's
  rule; vanilla also only listed regions where the receiver's army stands).
- Hordes keep the vanilla rules.

## Historical basis

- **Region ↔ region = partition between powers**, e.g. Armenia divided between Rome and Persia (around 387).
  Embassies suffice.
- **Region → gold:** the weakest historically; gold mostly flowed the other way, as subsidies and tribute (Rome to
  the Huns: Margus 435, Anatolius 443). Natively as Payments, which also covers regular payments over several turns.
- **Region → troops = the *foedus*,** see [federates](DESIGN-federates.md).
- **Region → peace:** the most common cession of the period (Nisibis 363, the Danube strip 449).

## The AI's score

The game's evaluator scores each part of the deal by the AI's personality and relationship and accepts at ≥ 0. TWASE
adds the regions: a region worth V gold to the AI counts like the AI not having to pay V gold, so it's on the game's
own gold scale (relative to the AI's treasury, scaled by the relationship). Values below the first step of that
scale are interpolated. Details and open proposals: [the region value](DESIGN-region-value.md).

## UI (the native panel, extended by TWASE)

- **Entry:** "Gift Region" in the diplomacy's "Add Offer/Demand" list (rename to "Trade Regions" at packaging).
- **Panel:** two lists side by side, your regions to give and theirs to demand; tick any number in both. Ticking a
  region pans the map to it. Regions already in the deal are ticked when the panel opens again.
- **Deal list:** each column shows its own regions. The X removes the whole region term (one action in the engine);
  to drop one side, reopen the panel and untick it.
- **Likelihood:** the game's, with the deal score in the tooltip (TWASE's existing tweak).
- **Layout:** the demand list lacked the offers list's background (vanilla's `list_clip` has no image, and its `list_box` background is transparent, `ffffff00`). Fixed in `mods/region_trading_ui/ui/campaign ui/diplomacy_hud.uic.yml` (the vanilla layout as text, see [UI-FORMAT](UI-FORMAT.md); the diff against `twpack ui export` of the vanilla file is the 12 lines that add the parchment row image to `list_demands/list_clip`). Loose layout files are ignored by the game (tested), so it ships as a pack: `region_trading_ui.pack`, built by `tools/deploy.sh region_trading_ui` (marker file `.build-pack`) and listed in `tools/mod_list.txt`.
- **Names:** `mods/region_trading_ui/text/db/________region_trading.loc.tsv` (in the same pack) renames the entry and the panel to "Trade Regions", the lists to "Give Regions" / "Demand Regions", the deal list label to "Regions:", rewrites the entry's tooltip (vanilla's is about migrating tribes only) and gives the two list titles their own tooltips (the layout's `region_trade_give_Tooltip` / `region_trade_demand_Tooltip`; vanilla's `offers_title_Tooltip_2b0037p` is shared with three other panels). The file name has more leading underscores than Fireforged's `_diplomacy_strings` / `_uied_component_texts` copies so that it is read first (the same convention; to be confirmed in game). Not yet seen in game.

## Execution

- The engine's transfer (list 1 to one side, list 2 to the other); armies in the settlements stay.
- Transferring a province capital kills its governor: TWASE calls the mod before and after each region, and the mod
  makes him immortal for the transfer and mortal again when the game recreates him (RTR's trick).
- Open: the faction stats correction from RTR's `clanPanel` (traded regions don't count as "lost").

## TWASE pieces

| Piece | Status |
|---|---|
| `twase.faction_attitude`, `twase.region_wealth`, `twase.region_province`, `twase.building_level`, `twase.unit`, `twase.localise` | done |
| `twase.enable_region_trading{ value = fn, transfer = fn }`: switches the native deals on with the mod's value and transfer handlers | done |
| wider rules, two-list panel with multiple ticks, deal list text, region value in the deal score, transfer handler | done (branch `region-trading`) |
| federates in the panel and the score | to design |
| removing single units from an army (federate desertion) | later |

## Switching off Fireforged's `maga`

At runtime, our mod (loaded after `scripting.lua`) removes every `MAGA_EventHandler_*` listener, so Fireforged's and
RTR's region trading is off and their files stay untouched (8 listeners, tested).

## Open points

- the value proposals and federates: see their docs
- the AI's own proposals with regions, and whether its evaluation during its turn is safe (long play test)
- packaging: the names, the demand list's background, a pack for the mod manager, the DLC campaigns
- later: the AI's reasons in the panel; AI-initiated offers
