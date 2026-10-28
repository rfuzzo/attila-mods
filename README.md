# attila-mods

Personal mods and tools for Total War: ATTILA on macOS and Windows.

- `packs/` – the built mods, ready to download: copy a `.pack` into the game's `data` folder and switch it on in the launcher's mod manager (or Runcher). All need [TWASE](https://github.com/rfuzzo/TWASE) for their scripts.
  - `region_trading.pack` – trade regions in diplomacy (unifies Fireforged Empire's and Region Trading Reloaded's). Needs a TWASE with native region deals (`twase.enable_region_trading`), otherwise it stays off.
  - `fireforged_fixes.pack` – fixes for Fireforged Empire's scripts; load it after Fireforged. Inert without it.
  - `tdd_twase_slots.pack` – The Dawnless Days' 12/9 settlement slots and encyclopedia link through TWASE (`twase.set_max_slots_*`, `twase.set_encyclopedia_url`) instead of TDD's external memory patcher. Inert without TDD; without TWASE's campaign UI hook TDD's own patcher runs.
- `tools/twpack` – pack tool (list, extract, DB ↔ TSV, build), on [rpfm_lib](https://github.com/Frodo45127/rpfm)
- `tools/` – deploy and launch scripts: `deploy.sh` / `play.sh` on macOS, `deploy.ps1` / `play.ps1` (`play.cmd` to double-click) on Windows, `build-packs.sh` rebuilds `packs/` (both)
- `mods/` – mod sources (see `docs/` for plans)
- Opt-in URL/slot feature tests: [campaign UI test guide](docs/TEST-campaign-ui.md). Deploy `campaign_ui_dev` only for testing; it is not enabled by the normal play/deploy commands.
- `extracted/` – unpacked game and mod files for reference, git-ignored
