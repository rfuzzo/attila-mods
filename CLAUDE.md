# attila-mods

Personal Total War: ATTILA mods and tools for macOS (Apple Silicon, Feral port 1.6.1 from Steam). Personal use only; mods may require TWASE. Current project: unifying the region trading of Fireforged Empire and Region Trading Reloaded, see `docs/PLAN-region-trading.md` (status at the top).

## Layout

- `tools/twpack`: pack tool in Rust on `rpfm_lib` (pinned to RPFM tag `v5.1.1`, keep default features or it doesn't compile). Build with `cargo build --release`, binary `tools/twpack/target/release/twpack`. Commands (`--help` on each): `ls <pack> [pattern]`, `extract <pack> -o <dir> [pattern] [--raw]`, `db export <pack> [table] -o <dir>`, `db import <pack> <tsv>...`, `loc export <pack> -o <dir>`, `build <folder> -o <out.pack>`. Patterns are case-insensitive prefixes or `*` globs. `--schema` defaults to `extracted/schemas/schema_att.ron`. rpfm_lib's `Container::extract` / `insert_file` silently fall back to binary on TSV errors, so twpack does TSV export / import itself.
- `mods/<name>/`: mods, each folder mirrors the game's `data/` root (so it deploys as loose files or builds into a pack with `twpack build`).
  - `mods/region_trading/`: the region trading mod (design: `docs/DESIGN-region-trading.md`). `campaigns/<campaign>/mods/region_trading/scripting.lua` are stubs for TWASE's loader, the code is in `region_trading/` (`init.lua` entry, `core.lua` shared table `rt` with `rt.log` / `rt.cm()`, `compat/maga.lua` removes Fireforged's / RTR's `MAGA_EventHandler_*` listeners). Logs go through `print` with the prefix `[region_trading]`.
- `tools/deploy.sh [--remove] [mod]`: copy a mod as loose files into the game's `data/` folder (or remove them). `tools/extract-all.sh`: see `extracted/`.
- `extracted/`: unpacked game / mod content (`game/`, `fireforged/`, `rtr/`, made by `tools/extract-all.sh`) and `schemas/schema_att.ron` (from rpfm-schemas), **git-ignored, never commit it**. It is its own local git repo for diffing versions.

## Paths

- Game: `~/Library/Application Support/Steam/steamapps/common/Total War Attila/`, packs in `TotalWarAttilaData/data/` (plain PFH4: `data.pack`, DLC `belisarius`, `charlemagne`, `slavs`, ...)
- Workshop packs: `~/Library/Application Support/Steam/steamapps/workshop/content/325610/<id>/`
  - Fireforged Empire: `2649271551/@Fireforged-Empire_1.pack`, `2649270391/@Fireforged-Empire_2.pack`, `2882854931/@Fireforged-Empire_ballast.pack`
  - Region Trading Reloaded: `2875210346/maga_reloaded.pack`
- Feral preferences: `~/Library/Application Support/Feral Interactive/Total War ATTILA/Preferences Data` (XML; `DisableAllMods`, `Launcher/mods` list). Only edit while the game is closed.

## TWASE (script extender, ~/GitHub/twase_macos, released v1.0.0)

- Region trading work in TWASE goes on the branch `region-trading`, checked out as the worktree `~/GitHub/twase_macos-region-trading` (other sessions use `~/GitHub/twase_macos`, don't switch its branch). `xmake -y` there builds and installs into the game.

- Start the game with `<game folder>/twase-launch.command [--skip-launcher] [--mods <Runcher-style mod_list.txt>] [--load "<save>.save"]`. The game ignores process arguments on macOS; the launcher sets Feral's preferences for one launch and links packs from the Workshop into `TotalWarAttilaData/data`. Steam must be running.
- In-game Lua console: key below Esc. Commands run on the game's Lua thread. Game Lua output goes to the console and `TWASE/logs/` (Lua lines need `logging.level = "debug"` or lower in `TWASE/config.ini`). The global `cm` is nil there: use `get_cm()` (the instance; `campaign_manager` is only the class).
- Mod loader: every `campaigns/<campaign>/mods/<name>/scripting.lua` is `require`d after the campaign's `scripting.lua`, from loose files in `TotalWarAttilaData/data/` or from a loaded pack. Feral's user `maps` folder is wiped on every launch, don't use it.
- The user tests interactively and quits the game themselves; unattended test launches should close the game when done.

## Reverse engineering

- Binary Ninja 6.0 (Free) on the Mach-O `Total War ATTILA.app/Contents/MacOS/Total War ATTILA`, bndb at `<game folder>/Total War ATTILA/Total War ATTILA.bndb`. The GUI MCP server (http://127.0.0.1:24642/mcp, when started in BN) can decompile and rename, but renaming functions with many callers is slow.
- Known addresses (unslid, base `0x100000000`), incl. the diplomacy deal evaluator `0x101d7b25c`: `~/GitHub/twase_macos/docs/addresses.md`.
- The binary has two Lua 5.1 copies; the game's is at `0x103f…`.

## Mod facts so far

- Both mods ship the same `maga\*` script paths (Fireforged has its own modified copy plus `maga\script\ui\regionTrading.lua` and `ui\bin\button\trade_region`) and both replace `campaigns\<campaign>\scripting.lua`, so whichever pack has priority silently replaces the other.
