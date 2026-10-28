# Handoff: campaign UI controls on macOS

Windows (Steam) and macOS (Steam arm64) acceptance completed on 2026-10-28, except the explicitly deferred
Charlemagne and The Last Roman panels. Mac evidence includes 35 in-game API checks and user-reported manual
navigation, slot, TDD integration, and edge-case results. See the closure section below and TWASE's
`docs/windows-port.md` and `docs/macos/addresses.md`. The procedures below remain available for reproduction.

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
| --- | --- | --- | --- |
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
| 11 | The Dawnless Days with `tdd_twase_slots` (below), no console input | Capital cards 12 slots, others 9; `reset_slots()` gives 6/4; unit and building encyclopedia links open TDD's entries on `rai4u.de/tde` | Whether TDD runs on Feral's port at all; its Windows patcher can't run there, so without the hook it stays 6/4 |

### The Dawnless Days (check 11)

Passed on Windows 2026-10-28 ([REVIEW-tdd-slot-patcher.md](REVIEW-tdd-slot-patcher.md)). Copy TDD's six
`tdd_pack*_v1.1.0.pack` files into `TotalWarAttilaData/data`, run `tools/deploy.sh tdd_twase_slots` (builds
`data/tdd_twase_slots.pack`) next to `campaign_ui_dev`, and start with `twase-launch.command --skip-launcher --mods
<list>` where the list has a `mod "…";` line for each TDD pack and `tdd_twase_slots.pack` (it overrides no TDD file,
so the order doesn't matter). TDD sends Lua `print` to its own `tdd.log.txt` (in the game's working directory), not
the TWASE log: expect `[tdd_twase_slots] Slot limits 12/9 set through TWASE` and `Encyclopedia URL
https://www.rai4u.de/tde`. A `TWASE slot limits unavailable` line means the hook isn't installed; the fallback then
starts TDD's `.exe` through `os.execute`, which fails on macOS (TDD writes `TDD_12_9_slots_A.exe` into that directory
first). TDD's campaign is `main_attila_map`; `campaign_ui_dev` has a stub for it.

## Report

TWASE commit, Mac game build, the `API PASS`/`FAIL` lines, one `/seen` line per link type (it also gives the exact
suffix format for `lua-api.md`), which browser opened, `inspect()` output per transition, and any crash. Add the
results to TWASE's `docs/macos/addresses.md` (Campaign UI controls section). Remove the harness afterwards with
`tools/deploy.sh --remove campaign_ui_dev`.

## Mac restart checkpoint (2026-10-28)

- Updated standalone Lua regressions passed after `b115c07`.
- The campaign loaded; hook installation and all 35 native API checks passed, restoring the original settings.
- Screen-capture permission was unavailable to the running session. Restart the session after granting permission,
  then continue the acceptance table above; do not infer its UI/navigation passes from the API result.
- The disposable game exited with status 0 after a quit request. The probe server was stopped and the deployed
  debug mod removed; redeploy/restart them for the next run. No production code was changed during this initial smoke.
- Evidence: TWASE log `twase-2026-10-28-11-43-50.log`; detailed checkpoint in TWASE `docs/macos/addresses.md`.

## Manual acceptance and closure (2026-10-28)

- After restarting, the user reported URL override/reset and the exercised slot-limit cases passed.
- The user also confirmed expanded slots work in The Dawnless Days with the requested `slots(12, 9)` override.
  This closes the Mac expansion-layout prerequisite for the exercised TDD case, not every slot or layout.
- The updated harness includes TDD's `main_attila_map` entrypoint; manual `require` is no longer needed.
- After deploying `tdd_twase_slots.pack`, the user confirmed automatic 12/9 slot expansion and working TDD
  encyclopedia navigation, without console setup or TDD's Windows-only executable patcher.
- The user also reported verifying the remaining edge cases. These are manual user-reported results, not an
  additional automated trace or exhaustive per-slot record.
- The user considers acceptance complete and requested PRs. No blocking production defect remains known.

## Remaining coverage

- Charlemagne and The Last Roman settlement panels remain untested on both platforms and are explicitly
  deferred by the user, not marked passed.
- TDD expansion-layout integration passed on Windows and, by user report, macOS.
- The debug harness was redeployed for manual testing; remove it afterward with
  `tools/deploy.sh --remove campaign_ui_dev`.
