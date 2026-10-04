# Region trading – plan

Status: 2026-10-04, Phase 1 spike done. Personal use for now (the mod would contain modified code from Fireforged Empire and Region Trading Reloaded, publishing needs their authors' permission). The mod may require [TWASE](https://github.com/rfuzzo/twase_macos).

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
2. Commands: `ls`, `extract` (all or filtered), `db export` / `db import` (TSV), `loc export`, `build` (folder of Lua / TSV / UI files → `.pack`).
3. Fallback if the spike fails: a Python extractor for raw files (Lua, text, UI layouts; no DB decoding).

## Phase 2: unpack into `extracted/` (git-ignored)

- base game: `data.pack`, DLC packs `belisarius`, `charlemagne`, `slavs`, English loc
- `extracted/fireforged/` (3 packs), `extracted/rtr/`
- Lua as is, DB tables as TSV, so everything can be grepped and diffed (a local git repo inside `extracted/` makes version diffs easy)

## Phase 3: analysis

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

## Phase 6: packaging and testing

- build the pack with `twpack build`
- test: save / load persistence, DLC campaigns, playing with Fireforged
- Workshop later, if wanted
