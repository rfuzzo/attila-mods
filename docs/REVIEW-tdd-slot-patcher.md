# The Dawnless Days' slot patcher

Reviewed 2026-10-28 on Windows (Steam build, The Dawnless Days 1.1.0, `tdd_pack1_main_v1.1.0.pack`). TDD raises the
settlement panel's building slots to 12 for province capitals and 9 elsewhere, and points the encyclopedia at its own
site, by patching the running game from an external program. `mods/tdd_twase_slots` does the same through TWASE.

## What TDD ships

- `campaigns/main_attila_map/scripting.lua` (its campaign; the folder is `main_attila_map`, not `main_attila`):
  `require "lua_scripts.extend_slots"`, and on `UICreated` first `ConfigureEncyclopedia(tddSettings["encyclopedia"])`
  (`util/encyclopedia.lua`: sets the global `baseEncyclopediaUrl`; no `tdd.cfg` or `online` gives
  `https://www.rai4u.de/tde`, `offline` a `file:///C:/Program%20Files%20(x86)/Steam/...` path), then
  `ExtendSlotLimits()`. It also sets `print = tdd_log`, so every Lua `print` in that campaign, TWASE mods included,
  goes to `tdd.log.txt` in the game folder instead of the TWASE log.
- `lua_scripts/extend_slots.lua`: `ExtendSlotLimits` deletes an old `TDD_12_9_slots.exe`, writes
  `TDD_12_9_slots_A.exe` into the game folder from `lua_scripts/slots_binaries.lua` (a table of 12,800 hex strings)
  if it isn't there, and runs `os.execute("TDD_12_9_slots_A.exe " .. baseEncyclopediaUrl)`. The registry flag
  `SBOOL_Slots_Extended` stops it running twice in one game process.
- `ui/campaign ui/settlement_panel`: `building_slot_1`–`12` on the capital card, `1`–`9` on the others.
- `campaigns/main_attila_map/startpos.esf`: 156 regions, 52 with 12 slots and 104 with 9.

## The patcher

`TDD_12_9_slots_A.exe`: 32-bit console program, SHA-256 `4feb5bc35cef0c159799457cd44faada9644bd7a7f87fee57751422a0c81a867`,
built 2026-09-18 (PDB `…\attila10slots\Release\TDD_12_9_slots.pdb`). Imports only window lookup, toolhelp module
listing and `OpenProcess` / `ReadProcessMemory` / `WriteProcessMemory` / `VirtualProtectEx`; no network or file I/O.
It finds the window `Total War: ATTILA`, opens the process with full access, scans `Empire.Retail.dll` in 4 KB
chunks for three exact 12-byte patterns and writes:

| Pattern | Function in `Empire.Retail.dll` (image base `0x10000000`) | Write |
|---|---|---|
| `01 c7 41 48 06 00 00 00 c3 cc cc cc` | `0x11410340`, capital presentation: `+0x44 = 1`, `+0x48 = 6` | `+0x48` value 6 → 12 |
| `00 c7 41 48 04 00 00 00 c7 41 40 00` | `0x113E1760`, `CampaignSettlementCallback` setup: `+0x44 = 0`, `+0x48 = 4` | 4 → 9 |
| `http://Atenc` | the string `http://Atenc.totalwar.com/#` | the URL argument, at most 27 characters, NUL-terminated |

`+0x48` is the bound of the loop in the card's Initialize (`0x11407530`) over `FindChild("building_slot_%d")`; a
missing widget is skipped, slots up to the region's slot count (`+0x4C`) are filled, the rest only made visible.
TWASE's hook overrides the same field for the duration of Initialize, keyed on the same `+0x44` flag.

Weak points: Windows only; the patch lasts for the whole process (other campaigns included) and can't be undone; it
needs an unsigned exe written into the game folder and process-memory writes (antivirus heuristics); one unreadable
chunk ends the whole scan and is reported as "already changed?"; if `Empire.Retail.dll` isn't found it scans the
last module listed; TDD's `offline` URL is longer than 27 characters and never gets patched; the URL is passed to
`os.execute` unquoted.

## `tdd_twase_slots`

`mods/tdd_twase_slots/campaigns/main_attila_map/mods/tdd_twase_slots/scripting.lua`, built into
`data/tdd_twase_slots.pack` (`.build-pack`; enable it in Runcher or the launcher next to TDD). TWASE's mod loader
runs it after TDD's `scripting.lua` and before `UICreated`. It keeps TDD's `ExtendSlotLimits` and replaces the
global with a function that calls `twase.set_max_slots_major(12)`, `twase.set_max_slots_minor(9)` and
`twase.set_encyclopedia_url(baseEncyclopediaUrl)`. If the slot calls fail (TWASE's campaign UI hook not installed),
it runs TDD's original function, i.e. the patcher. Without TDD (no `ExtendSlotLimits`) or without the slot API it
changes nothing. `tdd.log.txt` shows `[tdd_twase_slots] Slot limits 12/9 set through TWASE` and the URL.

Windows result (2026-10-28): 12/9 cards with no console input, `clear_max_slots()` back to 6/4, and unit and
building links open TDD's encyclopedia entries; details in TWASE's `docs/windows-port.md`. The game appends
`/unit/%S`, `/building/%S`, `/tech/%S`, `/skill/%S` to the prefix, so with TDD's prefix (no `#`) they are paths,
which `rai4u.de/tde` routes itself. macOS: see [HANDOFF-campaign-ui-mac.md](HANDOFF-campaign-ui-mac.md).

## Reproducing

`twpack extract <tdd pack> -o extracted/tdd "lua_scripts/*"`; the exe is the bytes of `slots_binaries`. With no
`extracted/schemas/` on Windows, pass `--schema "$APPDATA/FrodoWazEre/rpfm/config/schemas/schema_att.ron"`.
