# Handoff: campaign UI controls on macOS

Windows (Steam) passed on 2026-10-28; see "Windows integration run" in TWASE's `docs/windows-port.md`. The macOS
backend (`src/platform/macos/dylib/Hooks/CampaignUI.cpp`, TWASE `f14d33b`) has not been run in the game. Follow
[TEST-campaign-ui.md](TEST-campaign-ui.md); this note lists what differs on the Mac and what is still open.

## Setup

1. Build and install the TWASE dylib from a TWASE checkout that includes `f14d33b` (the docs commits after it don't
   change code).
2. In this repository: `git switch test/campaign-ui-controls && git pull --ff-only`, then `tools/deploy.sh
   campaign_ui_dev`. It copies loose files into `TotalWarAttilaData/data`; the game empties Feral's user `maps/`
   folder on every launch, so nothing may go there.
3. In `TWASE/config.ini`: `[logging] level = "debug"` and `[scripting] enable_logging = true`.
4. Probe server: `python3 -m http.server 18765 --bind 127.0.0.1 --directory tools/campaign_ui_dev`.

## Expected on startup

- TWASE log: `The campaign UI hooks were attached`. Failure logs `[CampaignUI] Unexpected game instructions or
  encyclopedia URL; hooks not installed` or a Dobby error code, and the setters then raise `campaign UI hook is
  unavailable`.
- First campaign tick: `[CampaignUIDev] API PASS 35 checks; prior settings restored`. Before `b115c07` this stopped
  after 11 checks on `math.huge`; any other failure is new.

## Checks

| # | Check | Pass | Mac-specific risk |
|---|---|---|---|
| 1 | `campaign_ui_dev.url()`, open building, unit, and tech links | Probe page (cream on black) shows the URL with a suffix; server logs `GET /seen?url=...%23<suffix>` | Unknown whether Feral opens links in the game or in Safari; either is fine, note which |
| 2 | `campaign_ui_dev.restore_url()`, open a new link | The native site opens; the URL matches the `Native URL=` log line | Feral's `EncyclopaediaBaseURL` preference can replace the native prefix; the hook should keep and restore that value |
| 3 | `slots(2, 2)`, reselect, `inspect()` | Every card 2 visible | Cleanup uses the per-slot clear function (`0x10345b30c`), unlike Windows |
| 4 | `slots(3, 1)` then `slots(2, 2)`, inspect after each | 3/1/1, then 2/2/2, no stale slots | Same as 3; reused cards are the risky case |
| 5 | `reset_slots()`, inspect | Native 6/4 (or that province's baseline) | |
| 6 | With 2/2: build or demolish in a visible slot, end turn, reset | Buildings in hidden slots survive and reappear with correct icons/tooltips | Clear-function side effects on slot controllers |
| 7 | 2/2 on a desolate/ruined settlement and a horde | Desolate cards unchanged, no crash | |
| 8 | `slots(8, 6)` on the vanilla layout | Stays 6/4, no crash (missing widgets are expected) | |
| 9 | Load another save with an override set, quit to menu, exit the game | Override persists (by design), no crash on exit | Hooks stay installed during Mac teardown |
| 10 | One settlement panel in Charlemagne and The Last Roman with an override | Same as 3 | Also still open on Windows |

## Report

TWASE commit, Mac game build, the `API PASS`/`FAIL` lines, one `/seen` line per link type (it also gives the exact
suffix format for `lua-api.md`), which browser opened, `inspect()` output per transition, and any crash. Add the
results to TWASE's `docs/macos/addresses.md` (Campaign UI controls section). Remove the harness afterwards with
`tools/deploy.sh --remove campaign_ui_dev`.

## Still open on both platforms

- Expansion above vanilla needs a UI layout with `building_slot_7`/`8` and campaign data with those slots.
- `lua tests/campaign_ui_dev.lua` has not been rerun since `b115c07` (no Lua on the Windows machine); run it on the
  Mac.
