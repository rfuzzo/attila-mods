# attila-mods

Personal mods and tools for Total War: ATTILA on macOS and Windows.

The built mods are in `packs/`: download a `.pack`, copy it into the game's `data` folder and switch it on in the launcher's mod manager (or Runcher). All need [TWASE](https://github.com/rfuzzo/TWASE) for their scripts. Sources are in `mods/<name>/`.

## Region Trading

**Download:** [region_trading.pack](https://github.com/rfuzzo/attila-mods/raw/main/packs/region_trading.pack)

Trade regions in diplomacy (unifies Fireforged Empire's and Region Trading Reloaded's). Needs a TWASE with native region deals (`twase.enable_region_trading`), otherwise it stays off.

## Fireforged Fixes

**Download:** [fireforged_fixes.pack](https://github.com/rfuzzo/attila-mods/raw/main/packs/fireforged_fixes.pack)

Fixes for Fireforged Empire's scripts; load it after Fireforged. Inert without it.

## Fireforged Encyclopedia

**Download:** [fireforged_encyclopedia.pack](https://github.com/rfuzzo/attila-mods/raw/main/packs/fireforged_encyclopedia.pack) · **Site:** [rfuzzo.github.io/attila-mods](https://rfuzzo.github.io/attila-mods/)

An encyclopedia of Fireforged Empire's units (stats, abilities, recruitment and areas of recruitment, the mod's own descriptions, links to the culture pages on [late-roman.ru](https://late-roman.ru/fireforged-empire/units/)) and buildings (each chain's tiers per culture, effects, recruits, garrisons, requirements), built from the mod's data. With the pack and a TWASE that has `twase.set_encyclopedia_url`, the game's unit and building links open it. Inert without Fireforged. Technologies and the rest are not covered yet; those links offer the vanilla encyclopedia.

## TDD TWASE Slots

**Download:** [tdd_twase_slots.pack](https://github.com/rfuzzo/attila-mods/raw/main/packs/tdd_twase_slots.pack)

The Dawnless Days' 12/9 settlement slots and encyclopedia link through TWASE (`twase.set_max_slots_*`, `twase.set_encyclopedia_url`) instead of TDD's external memory patcher. Inert without TDD; without TWASE's campaign UI hook TDD's own patcher runs.

## Tools

### twpack

`tools/twpack` – pack tool (list, extract, DB ↔ TSV, build), on [rpfm_lib](https://github.com/Frodo45127/rpfm).

### Deploy and launch scripts

- macOS: `tools/deploy.sh`, `tools/play.sh`
- Windows: `tools/deploy.ps1`, `tools/play.ps1` (`play.cmd` to double-click)

### encyclopedia

`tools/encyclopedia/build.py` regenerates `encyclopedia/` from `extracted/` (macOS). Commit the result; pushing to `main` publishes it.

### build-packs

`tools/build-packs.sh` rebuilds `packs/` (macOS, or Git Bash on Windows).

## Other folders

- `docs/` – plans, designs and reviews
- `encyclopedia/` – the generated encyclopedia site (published by `.github/workflows/encyclopedia.yml`)
- `extracted/` – unpacked game and mod files for reference, git-ignored
