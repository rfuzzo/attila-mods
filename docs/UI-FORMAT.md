# Attila UI layout files

Status: **decoder, encoder and a YAML text form done for versions 92 to 99** (`tools/twpack/src/uic.rs`), lossless on all 1969 such layouts in the game, Fireforged and RTR. First slice of a viewer: `ui render`.

## What they are

- Files under `ui/` without extension (`ui/campaign ui/regions_dropdown`, `ui/bin/button/trade_region`, ...). **Not XML**: a binary tree starting with `Version0NN`. (The XML form is Three Kingdoms and later; RPFM's `uic` module only reads that, version 138.)
- RPFM extracts them fine as plain bytes, it just can't decode them. `.cml` files in `ui/` are a different format (`Version002`).
- Versions in `extracted/`: 095 (1867 files), 096 (80), 097 (12), 092 to 094 (10), and about 34 older (077 to 091) that are not supported. Attila's engine reads old versions too, so a layout can be saved in any of them.

## Format

Little-endian. `str` = u16 length + bytes, `wstr` = u16 character count + UTF-16LE, lists = i32 count + elements. A component (`Uic`) is, in order: uid (4 bytes), name, b0 (a context object id such as `CampaignRoot`), offset (2 x i32, relative to the parent), 12 flag bytes, tooltip text and id (wstr), docking (3 x i32), images, mask image, states, dynamic properties (string pairs), funcs (animations), children (recursively, inline: **no templates before v100**), then a tail with the layout engine (`List`, `HorizontalList`, `RadialList`, `Table`) and optional 3D model attachments.

- **Image**: path (`ui/skins/...png`), size. Referenced from a state's `images` (placements: offset, size, colour, tile, flips, dock point 1 to 9, nine-patch margin) by uid.
- **State**: `NewState`, `active`, `hover`, ... each with its own size, text (`text`, `text_label`, `localised`), font (name, size, colour, category), shaders, image placements and mouse events (state to switch to, sounds).
- **Func / Anim**: animations (`show` / `hide`, easing curve, target offset / size / colour, `Visibility false` triggers).

Many bytes are still opaque (`flags`, `b0`..`b7`, the list tail): they are kept as hex and written back unchanged, which is what makes the round trip exact. Meanings of some are known from the reference parser (flags: visible, moveable, resizable, clip ...), see its comments.

## Text form

`twpack ui export` writes YAML, `<name>.uic.yml`. Meant to be read, diffed and edited:

- Fields equal to their default are left out, and missing ones read as the default. So a typical state is ten lines.
- Number groups are one line: `bounds: 1280 960`, `margin: 0 0 0 0`.
- References are names, not ids: `default_state: unselected` and mouse `state_uid: selected_down` name a state of the same component, `image_uid: ui/skins/default/sort_arrow.png` an image of it (`#2` = third image, when the path is empty or repeated), an animation trigger's `uid` a component (when its name is unique in the file). Anything that can't be a name stays an 8 digit hex id.
- Ids of components, states and images (`uid`) are written by default so that import gives back the exact original bytes. `--no-uids` leaves them out; a missing id is made up on import from where the thing sits in the tree, so the same text always gives the same file. Write new components without ids.
- Named where there is evidence: `class` (what the game treats the component as: `Button`, `VSlider`, `List` ...), `properties` (`stepSize`, `minValue` ...), `priority`, `flags` (`allow_h_resize`, `allow_v_resize`, `moveable` set on slider handles, `visible`, `clip_children` set on every `*_clip`, `clip_image`), a state's `focus.interactive` (set on buttons, i.e. everything with `mouse` events) and `focus.mouse_on`, `editor_pos`. `flagN` / `unkN` / `bN` are bytes with no known meaning yet, shown as hex or numbers as found. Names for flags follow the reference parser's notes, checked against which components set them (`visible` is the least certain).

## Tool

```
twpack ui check <files/folders>      # binary round trip, text round trip (with and without ids); extracted/ is all green
twpack ui tree <file> [-v]           # outline: name, size @ offset, text, engine; -v adds states / images / anims
twpack ui export <file|folder> [-o out] [--no-uids]   # YAML; a folder is mirrored to <out>/<path>.uic.yml
twpack ui import <x.uic.yml|folder> -o <out>          # back to binary layouts
twpack ui render <layout> -o <dir> [--only name] [--state hover] [--show-hidden] [--pack p.pack ...] [--scale 1.5]
twpack build <mod folder> -o x.pack                   # also turns every *.uic.yml into its binary layout (path without .uic.yml)
```

Edit loop: `twpack ui export extracted/game/data/ui/"campaign ui"/regions_dropdown --no-uids -o mods/<mod>/ui/"campaign ui"/regions_dropdown.uic.yml`, edit, `twpack build`. (`tools/deploy.sh` copies loose files, so a `.uic.yml` needs `twpack ui import` first; not wired up yet.) Verified end to end: edited text and a new component without ids, built into a pack, extracted, checked.

## Viewer (`twpack ui render`)

Writes `<dir>/index.html` plus the skin images the page uses, taken from the game's `data.pack` and the DLC packs (`--pack` to use others, e.g. `region_trading_ui.pack`). Open it in a browser (a local `python3 -m http.server` if the viewer won't open `file://`). About 0.4 s for a layout. `--only trade_regions` renders just that component (the first with the name), `--show-hidden` also draws components whose `visible` flag is off (dashed outline), `--state hover` shows that state wherever a component has it.

- **Drawn:** a box per component at its design-size `offset`, sized by the shown state's `bounds`, clipped if `clip_children`; each state's image metrics (tiled, stretched, or nine-patch from `margin`, opacity from the colour's alpha, flips); the state's text with size, colour, alignment and `text_offset`; the page covers everything drawn (title plaques stick out above their panel).
- **Findings that came out of it:**
  - `offset` is the position at the design size. `docking` (1 to 9: top left .. bottom right, 3x3) plus `dock_offset` gives the same position in about 94% of components (`anchor(docking, parent size, own size) + dock_offset`; centre rounding varies by one pixel), the dock only matters when the parent is resized.
  - A lower `priority` is in front: the parchment has 12, the lists 0, a title 45 in front of its plaque 50.
  - `colour` is RGBA, alpha last (`ffffff00` is transparent).
- **Validated** against in-game screenshots of the `trade_regions` panel: plaque, parchment, lists with their backgrounds and scrollbars, buttons and titles come out where the game has them.
- **Not shown:** anything the game or a script does at run time (the side by side lists of the region trade panel are placed by TWASE, the layout has them on top of each other), fonts (a serif stands in), font colours from the font categories (`fontcategories.fc`: titles come out in the state's own colour), colour tints, localised text (the layout's literal text is shown), animations, other screen sizes, text that is set from script, images the game fills in (dotted outline), `3D_window`s.
- **Ideas:** a state switcher in the page, `--screen WxH` to place components by their docking, tooltips, loc lookup for text, an index page for a whole folder.

## Sources

Format knowledge from <https://github.com/Cpecific/twwh2_ctm> (`class.php`, PHP, GPL-3.0, versions 70 to 133, also a web viewer: `ui.php`). The Rust port is pruned to Attila's versions and merges read and write into one description (`trait Io`).

## Ideas

- Wire `.uic.yml` into `tools/deploy.sh` (loose files for the TWASE test loop).
- Name more bytes (`flag9`, `flag10`, `unk2`, `unk3`, `b3`, the list tail); find out what the game reads (Binary Ninja, the loader in the Mach-O).
- Text form is long (a 51 KB layout is ~3800 lines, mostly per-state font and shader boilerplate): inherit from the first state, or a `defaults:` block.
- Support 77 to 91 (a few vanilla panels) and 100+ (not needed for Attila).
- Offline viewer: render component boxes and the skin PNGs (`ui/skins/default/*.png` are in data.pack) from the tree; see `ui.php` and `js/ui.js` of the reference for a start.
