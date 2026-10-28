# TWASE encyclopedia and settlement-slot checks

Opt-in debug mod: `campaign_ui_dev`. Requires TWASE's URL/slot feature build on Windows or macOS, not only the
integrity fix on `main`. It works with the main, Charlemagne, and Last Roman campaign entrypoints, and with The
Dawnless Days' `main_attila_map`. It has no region-trading or Fireforged dependency and does not modify startpos,
saves, buildings, or UI layouts.

The native hooks still need Windows gameplay verification. Passing the API checks below is **not** proof that the
browser consumes the changed URL or that the game renders the requested slots. The local probe page and the UI
inspector are for those separate observations.

## 1. Deploy on Windows

From this repository's root, with the game closed:

```powershell
git fetch origin
git switch test/campaign-ui-controls
git pull --ff-only
powershell -ExecutionPolicy Bypass -File .\tools\deploy.ps1 campaign_ui_dev
```

Install the freshly built TWASE DLL in the game first. Launch normally with your usual mod list and load a test
campaign/save. This debug mod deploys **loose Lua**, so it needs no `.pack`, Rust build, or mod-list change. Existing
`region_trading` and `fireforged_fixes` packs can remain enabled. Do not also run `region_trading_dev`: that older
harness simulates clicks and can spawn armies. If it is deployed, remove it before this test:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\deploy.ps1 -Remove region_trading_dev
```

For Lua output in `TWASE/logs/twase-*.log`, use these settings in the game's `TWASE/config.ini`:

```toml
[logging]
level = "debug"

[scripting]
enable_logging = true
```

At the first campaign tick, the mod runs synchronous API checks, attempts to restore all prior settings even if a
check fails, and logs `[CampaignUIDev] API PASS ...` or `API FAIL ...`. Check the log or TWASE console. An unavailable
function means the feature DLL is missing; a setter error saying the campaign UI hook is unavailable means target
resolution/hook installation failed. Inspect the preceding TWASE startup error; do not interpret a successful DLL
build as successful hook installation.

The first tick must occur in the campaign. A mod-loader `Loaded: campaign_ui_dev` line alone does not prove the
checks ran. The harness is also available in the campaign console as `campaign_ui_dev`; rerun with:

```lua
campaign_ui_dev.api()
campaign_ui_dev.report()
```

A `FAIL RESTORE` message means settings could not be restored: quit/restart the game before continuing. These
settings are process-local; reloading a save alone does not necessarily clear them.

## 2. Test actual encyclopedia navigation

In a separate terminal at the repository root, start the loopback-only test page:

```powershell
py -3 -m http.server 18765 --bind 127.0.0.1 --directory tools/campaign_ui_dev
```

Use `python` instead of `py -3` if that is how Python 3 is installed. On macOS use `python3`. No Python dependency
is needed for the mod itself; any static HTTP server serving that folder at the same loopback address also works.
Nothing should listen on an external network interface.

In the in-game TWASE console, in the campaign context:

```lua
campaign_ui_dev.url()
```

This sets `http://127.0.0.1:18765/#`. Close the console and open an **encyclopedia link from the game**, for example
from a unit or building card. The Steam build loads it in the game's own browser panel (Steam's embedded HTML
surface); other platforms hand it to the default system browser. The page titled **TWASE encyclopedia hook test**
(cream text on black, like the real encyclopedia) must show the complete URL plus a nonempty game-appended suffix,
and the HTTP server must log the same URL as `GET /seen?url=http%3A%2F%2F127.0.0.1%3A18765%2F%23<suffix>` (a 404 by
design). Try a second entry and a technology/help link; confirm the suffix changes appropriately. Capture the
displayed URL or the `/seen` log lines. Browsing to the page directly, reading the setter return, or seeing only
`GET /` in the HTTP log is not a navigation pass: URL fragments are not sent to the HTTP server. `GET /` without a
following `/seen` line means the page was fetched but its script did not run.

Then reset:

```lua
campaign_ui_dev.restore_url()
```

Open a **new** encyclopedia link. It must use the native prefix printed by the harness and no longer navigate to
the test page. The existing browser page does not change on reset. If the game's original online encyclopedia is
unavailable, a network error at that original address is distinct from a failure to restore the prefix.

## 3. Test actual settlement-card rendering

Use a normal settled province, not a horde/ruins panel. Select one of its settlements, open the console, and record:

```lua
campaign_ui_dev.reset_slots()
-- Reselect a different settlement, then return, or close/reopen the panel.
campaign_ui_dev.inspect()
```

`inspect()` traverses the real visible settlement-panel tree and logs each card's path, visible slot indices/count,
and total named slot widgets. Hidden parent/template nodes are excluded. Compare this with the actual display.
An absent/hidden panel or an unknown UI layout produces a failure, not an automatic pass. It reports observations,
not a guessed mapping of arbitrary modded UI names to province-capital identity.

Exercise the following **manual transitions**, refreshing/reselecting after each command. Both changing settlements
within the same province and closing/reopening the panel matter. Merely changing the setting leaves the existing
panel unchanged until the engine initializes it again.

| Command | Observe after refresh |
|---|---|
| `campaign_ui_dev.slots(2, 2)` | Both province-capital and other cards show at most two slot widgets; no stale higher-numbered slots remain visible |
| `campaign_ui_dev.slots(3, 1)` | Province-capital card uses the major limit, other settlements use minor; changing the selected settlement does not swap that classification |
| `campaign_ui_dev.slots(2, 2)` | Reused cards shrink again without stale visible slots |
| `campaign_ui_dev.reset_slots()` | The original card visibility/count returns, not the last override |

Run `campaign_ui_dev.inspect()` after each transition and compare against the baseline **for the same province**.
Do not build/demolish during this check. Verify existing building icons/tooltips are still correct after resetting.
The capital card normally has six widgets and other cards four, but use the observed baseline: modded/ruined layouts
and settlements with fewer actual slots can differ.

To test an increase beyond vanilla limits:

```lua
campaign_ui_dev.slots(8, 6)
-- Refresh/reselect, then inspect.
campaign_ui_dev.inspect()
```

This needs **both** a UI layout with `building_slot_7`/`building_slot_8` (and fifth/sixth minor widgets) and campaign
data with the intended slots. The hooks do not create either. A vanilla six/four template cannot demonstrate an
eight/six expansion; missing widgets are not a hook failure. Inspect reports existing widget capacity to expose this
prerequisite. Do not assume this fixes every missing-plot issue described in [BUG-missing-building-slots.md](BUG-missing-building-slots.md).

The Dawnless Days (TDD, analysis in [REVIEW-tdd-slot-patcher.md](REVIEW-tdd-slot-patcher.md)) ships all three for
12/9: a `settlement_panel` with `building_slot_1`–`12`, a startpos with
12 slots per province capital and 9 elsewhere, and a Windows patcher (`TDD_12_9_slots_A.exe`, started from
`lua_scripts/extend_slots.lua` on `UICreated`) that rewrites the same bound at `+0x48` in the game's memory: 6 → 12
in SetAsCapital, 4 → 9 in the callback's constructor. `tdd_twase_slots` replaces it with TWASE's API: build it with
`deploy.ps1 tdd_twase_slots` (`data\tdd_twase_slots.pack`), switch it on in Runcher or the launcher next to TDD, and
start a fresh game process (TDD's patch lasts until exit). TDD sends Lua `print` to its own `tdd.log.txt`, which
then shows `[tdd_twase_slots] Slot limits 12/9 set through TWASE`, the encyclopedia URL, and no new `Extending slot
limits to 12/9`. If the TWASE hook is unavailable, it logs that and runs TDD's patcher. With `campaign_ui_dev` also
deployed, `inspect()` should report 12 widgets on capital cards and 9 elsewhere; `reset_slots()` shows the native
6/4 for comparison.

TDD's encyclopedia: without `tdd.cfg` (or with `encyclopedia = online`) the prefix is `https://www.rai4u.de/tde`.
The game appends `/unit/%S`, `/building/%S`, `/tech/%S`, … as a path, and that site routes such paths itself
(`…/tde/unit/arn_spear_militia` and `…/tde/building/rom_ere_city_major_1rom_cult_dwarves`, the form of the site's own
building links, open the cards). TDD's `offline` default points at
`C:/Program Files (x86)/Steam/...`, so it only works for a game installed there.

## 4. Clean up and report

Before quitting, restore the values captured when the harness started:

```lua
campaign_ui_dev.restore()
```

Refresh the panel and verify the original display. Quit the game, stop the HTTP server with Ctrl+C, then remove the
loose debug files so normal play does not rerun the checks:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\deploy.ps1 -Remove campaign_ui_dev
```

Report: TWASE feature commit/build and Windows game version, `API PASS`/failure output, the actual game-opened URL,
per-province slot counts before/after/reset, UI mod name if testing expansion, and any crash or stale-slot behavior.
Do not include personal filesystem paths or whole unredacted logs unnecessarily.

## macOS and harness checks

Mac status, differences, and the check list: [HANDOFF-campaign-ui-mac.md](HANDOFF-campaign-ui-mac.md).

```sh
tools/deploy.sh campaign_ui_dev
# Play interactively, then quit before removal.
tools/deploy.sh --remove campaign_ui_dev
lua tests/campaign_ui_dev.lua
```

The standalone Lua tests exercise the **debug harness's** restoration/error handling and UI-tree inspection using
a simulated game API. They do not verify native game addresses, Windows hook installation, browser navigation, or
real settlement rendering. The probe page uses no remote assets; its script displays the current browser URL and
fragment and reports the URL only to the loopback server that served the page (`/seen?url=...`).

Local test-kit verification: `lua tests/campaign_ui_dev.lua` passed under Lua 5.4.8; the macOS deployment/removal
commands were exercised with an isolated temporary home directory, without touching an installed game. The static
probe page was served on loopback and checked in a real browser for full-URL display and fragment-change updates.
These checks do not claim a Lua 5.1 engine run, Windows deployment run, or a native-hook gameplay pass.
