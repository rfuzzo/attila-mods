# Region trading – plan

Status: 2026-10-04, Phase 5. Direction change: native region deals (TWASE widens the engine's Gift Region, tested end to end) with a MAGA-style map UI on top, see the design. Next: region value in the native deal evaluation (TWASE), demand region, map UI, federates.

## Goal

Unify the region trading of **Fireforged Empire** and **Region Trading Reloaded** into one mod that works with Fireforged:

- keep Fireforged's mechanic (trade regions to the AI for troops / money)
- allow trading with allies (and others above an attitude threshold)
- a proper score the AI decides on, instead of forcing trades
- a usable UI in the diplomacy panel

## What we know

- **Region Trading Reloaded = `maga_reloaded.pack`** (Workshop 2875210346): `maga\script\regionTrading.lua`, `maga\script\ui\diplomacyDropdown.lua`, `offersPanel.lua`, region data per campaign (`maga\data\<campaign>\regions.lua`), a small UI framework (`maga\core\*`).
- **Fireforged ships its own modified copy of the same `maga` framework** (`@Fireforged-Empire_1.pack`): `maga\script\regionTrading.lua` (4405 bytes vs 4146 in RTR), its own UI `maga\script\ui\regionTrading.lua` (15 KB) and a `ui\bin\button\trade_region` layout.
- **Why they conflict:** both mods ship the same `maga\*` paths and both replace `campaigns\<campaign>\scripting.lua`. Whichever pack has priority silently replaces the other's files.
- **All packs are plain PFH4** without compression or encryption (incl. the base game's `data.pack`, 50,763 files). Raw files are easy to extract; DB tables need a schema.
- **Tooling:** Runcher doesn't unpack itself, it uses `rpfm_lib` from [RPFM](https://github.com/Frodo45127/rpfm) (Rust, MIT). RPFM has no macOS build and no CLI anymore, but `rpfm_lib` has pack (PFH0–6), DB, loc and schema support. Attila schema: `schema_att.ron` in [rpfm-schemas](https://github.com/Frodo45127/rpfm-schemas).
- **From TWASE:** the game's deal evaluator (`0x101d7b25c`) and likelihood thresholds are known, the mod loader loads `mods/*/scripting.lua` without replacing `scripting.lua`, and the console + Lua log + `twase-launch.command --mods … --load <save>` give a fast iteration loop.

## Phase 1: pack tool for macOS (`tools/twpack`, Rust on `rpfm_lib`)

1. ✅ Spike (2026-10-04): `rpfm_lib` v5.1.1 builds on arm64 macOS (Rust 1.94). It opens the base game's `data.pack` (50,763 files, 0.5 s with lazy loading) and decodes `db/regions_tables/regions` (v3, 519 rows) to TSV with `schema_att.ron`. Note: it doesn't compile with `default-features = false` (its UI layout XML code uses `serde_xml_rs` unconditionally), so `twpack` keeps the default features. The schema goes to `extracted/schemas/` (from rpfm-schemas, MIT).
2. ✅ Commands (2026-10-04): `ls`, `extract` (all or filtered by prefix / `*` glob), `db export` / `db import` (TSV), `loc export`, `build` (folder → PFH4 mod pack, `.tsv` files become tables, hidden files skipped). The schema defaults to `extracted/schemas/schema_att.ron`.
   - Tested: `data.pack` exports 754 tables in 0.3 s. 647 decode, 103 are empty tables in versions the schema doesn't know (harmless), 4 have data or a version the schema lacks: `models_artillery` (v0), `models_naval` (v11), plus `regions_to_region_groups_junctions` and `land_unit_articulated_vehicles` (both v0 with 0 rows). None of them matter for region trading. `local_en.pack` (in `data/localisation/en/`) exports 171 loc files.
   - Round trip: extract `maga_reloaded.pack` → `build` (plus a TSV table) → extract gives identical files. `db import` → `db export` gives the same TSV. The header matches Workshop packs (PFH4, type Mod). rpfm_lib also writes its `*.rpfm_reserved` files into mod packs, like RPFM does.
   - Not tested yet: the game loading a `twpack build` pack (first real test in Phase 5).
3. ~~Fallback: Python extractor~~ (not needed).

## Phase 2: unpack into `extracted/` (git-ignored) ✅

Done 2026-10-04 with `tools/extract-all.sh` (1.3 s, 96 MB, re-run after updates). Only text-like content: DB tables and loc as TSV, Lua, UI layouts, XML; images, models, animations, shaders, pathfinding and wind data are skipped.

- `extracted/game/{data,belisarius,charlemagne,local_en}`: the DLC packs hold no DB tables, only campaign Lua, UI and terrain; `slavs.pack` only has movies
- `extracted/fireforged/{1,ballast}`: `@Fireforged-Empire_2.pack` is only models and textures, skipped. All 195 Fireforged DB tables decode.
- `extracted/rtr/`
- `extracted/PACKS.txt`: pack timestamps and sizes. `extracted/` is its own git repo (baseline commit), so `git -C extracted diff` shows what an update changed.

First findings:

- The two `maga` trees are identical except `maga/script/regionTrading.lua` and `maga/script/ui/regionTrading.lua` (RTR has the UI file too, not only Fireforged).
- Fireforged replaces only `campaigns/main_attila/scripting.lua` (plus many own campaign scripts there), RTR replaces the `scripting.lua` of `main_attila`, `bel_attila` and `cha_attila`.

## Phase 3: analysis ✅

Done 2026-10-04, results in [`ANALYSIS-region-trading.md`](ANALYSIS-region-trading.md). Short version: Fireforged's change is a few lines (gift → +3,000 gold, "trade" → +2 recruitment slots for 16 turns, the AI region isn't transferred) on top of RTR's unchanged UI; neither mod asks the AI. RTR's `scripting.lua` only adds `require("maga/init")`. The engine still knows a `"regions"` diplomacy type (to test), and `CAI_INTERFACE::get_faction_attitude` is the TWASE candidate for the AI's attitude.

Original tasks:


- diff the two `maga` copies (Fireforged vs RTR), separate the shared core from each mod's changes
- map the mechanics: how trades are offered, how they're executed (which `cm` / interface calls transfer regions, money, troops), which UI they inject, where Fireforged's jank comes from
- game side: diplomacy DB (`cai_personality_deal_evaluation_*` tables), region / settlement / building value data, the Lua API Attila's campaign environment offers for regions, factions, treaties
- gaps Lua can't fill (e.g. the AI's real attitude or deal evaluation) → native `twase.*` Lua functions in TWASE

## Phase 4: design (together)

- who can trade: allies, others above an attitude threshold
- what: region ↔ money, region ↔ troops (Fireforged), region ↔ region
- score: region value (income, buildings, population, connection to the AI's territory, culture / religion) + relationship (attitude, alliance, war); the AI accepts at score ≥ 0 like the game
- does the AI make region offers itself?
- UI in the diplomacy panel, showing the score

## Phase 5: implementation as a TWASE mod

- `campaigns/main_attila/mods/region_trading/scripting.lua`: never replaces `scripting.lua`, stays compatible with Fireforged
- Fireforged's built-in version has to be switched off: a small override pack with higher priority for its `maga\script\*` files, or patching it at runtime in Lua (decide after the analysis)
- loop: loose files in `TotalWarAttilaData/data`, reload from the TWASE console, Lua log, `twase-launch.command --mods … --load <save>`

## Wiki (task for later)

A wiki in this repo with what we've found: the vanilla campaign Lua API (script interfaces and their methods from the Lunar method tables, `game_interface` functions, events), engine internals relevant to modding, and the `twase.*` functions TWASE exposes.

## Phase 6: packaging and testing

- build the pack with `twpack build`
- test: save / load persistence, DLC campaigns, playing with Fireforged
- Workshop later, if wanted
