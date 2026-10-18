# Missing building slots (Argentoratum and three others)

Status 2026-10-18: won't fix. The towns have no room for another building plot, and the slot count follows the plots
(vanilla, inherited by Fireforged). A patched startpos that added the slots was tried and removed: the game had the slots,
but the settlement panel didn't show them. Investigated with `twpack esf dump` (see below).

## Symptom

Argentoratum (`att_reg_maxima_sequanorum_argentoratum`) has 3 building slots in game, while the other minor settlements have 4.

## Cause

The slots of each settlement are not taken from the DB at campaign start; they are records in the campaign's `startpos.esf`
(`REGIONS_ARRAY / REGION / REGION_SLOT_MANAGER / REGION_SLOT_ARRAY`, one `REGION_SLOT` per slot, with key `<region>:<index>`,
slot template and type, and the building in it). `campaign_map_settlements.slot_count` is 4 for every settlement, capitals
included, so it doesn't decide anything.

Fireforged Empire ships its own `campaigns/main_attila/startpos.esf`, built from vanilla's (in `@Fireforged-Empire_1.pack`; it's the only map-related
file it ships, no `campaign_maps/`). In it, of 186 regions, 123 have 4 slots (minor settlements), 59 have 6 (province
capitals), and four have one secondary slot too few:

| Region | Slots | Should be | Slot templates |
|---|---|---|---|
| `att_reg_maxima_sequanorum_argentoratum` | 3 | 4 | `rom_minor_primary`, 2 × `rom_minor_secondary` |
| `att_reg_bithynia_ancyra` | 5 | 6 | `rom_major_primary`, 4 × `att_major_silk` |
| `att_reg_cappadocia_caesarea_eusebia` | 5 | 6 | `rom_major_primary`, 4 × `rom_major_secondary` |
| `att_reg_palaestinea_nova_trajana_bostra` | 5 | 6 | `rom_major_primary`, 4 × `rom_major_secondary` |

The slot, garrison and building ids of these regions are consecutive (Argentoratum: slots 284–286, garrisons 344–347,
so the settlement's garrison follows right after the third slot's), so no slot was deleted afterwards: the startpos was
generated with these slot counts, which come from the town layout (next section).

The save `Picts 390 AD Spring.save` has the same counts (Argentoratum `:0`–`:2`, Ancyra `:0`–`:4`), so a running campaign
keeps what its startpos had.

Vanilla has the same four: its `TotalWarAttilaData/data/campaigns/main_attila/startpos.esf` (loose, like every
campaign's startpos, not in a pack) has the same 186 regions with the same counts (123 × 4, 59 × 6, 3 × 5, 1 × 3) and
the same four short regions. So it's a base game bug that Fireforged inherited when it rebuilt its startpos, not a
Fireforged bug. (That file was missing on this machine until a Steam "verify integrity" on 2026-10-17 restored it;
why it was gone is unknown.)

## Why: no room in the town layout

Each settlement's record in the startpos also has its town layout, `SETTLEMENT / SETTLEMENT_EXPANSION_MANAGER /
SETTLEMENT_EXPANSION_MAP_DATA`: numbered plots (`SLOT_MAP_DATA`: plot number, centre hex, a 7-hex `SLOT_FOOTPRINT_ARRAY` of
the centre and its 6 neighbours, a `SLOT_ZOE_ARRAY` zone around it, `SLOT_WALL_ARRAY`, a u32), first the settlement
(plot 0), then the port (plot 1; inland towns have an entry without ground, centre 65535, 65535, no hexes), then
`SECONDARY_SLOT_ARRAY` with plots 2, 3, ..., and `SPRAWL_BLOCK`, the town's hexes, each tagged with the bit of the plot
whose zone it's in (`1` the settlement, `4` plot 2, `8` plot 3, `16` plot 4, `0` free). Footprints sit in their zone,
zones in the sprawl, zones don't overlap. Hex neighbours: even x (x±1, y−1), (x±1, y), (x, y±1); odd x (x±1, y),
(x±1, y+1), (x, y±1).

Every settlement has as many slots as plots, and when the world is created the game maps slots to plots in order (a save
has it in `SETTLEMENT_EXPANSION_MANAGER / SLOTS_ARRAY`: Octodurus `:0` → plot 0, `:1` → 2, `:2` → 3, `:3` → 4). The four
short towns have one secondary plot fewer (Argentoratum plots 2 and 3, Octodurus 2 to 4), and in three of them the sprawl
has no free centre whose 6 neighbours are free too, i.e. no room for another footprint (Ancyra has two such spots). So the
tools that built the startpos placed as many plots as the ground allowed, and the slots followed: an unintended side
effect of the town generation, but consistent within the engine, and CA never changed it.

## What was tried (removed again)

A startpos patch in `fireforged_fixes`, generated at build time from the installed Fireforged pack (so not in git): per
region a copy of its last secondary `REGION_SLOT` with the next key index (`…argentoratum:3`), an empty building manager
and the next free slot / garrison ids (865–868, 1051–1054; the ids were 1–864 and 1–1050 in region order), later also a
secondary plot without ground (like an inland port entry) for it. In a new campaign Lua counted 4 / 6 slots, but the
settlement panel showed the old number, with and without the extra plot. A slot the player can't see but the AI might
build in is worse than none, so it went; a real fix would need room in the town (new sprawl hexes on the terrain and a
proper footprint, and whatever else the panel needs), which is guesswork. Patching saves was ruled out before (more state
refers to slots there).

Learned on the way:
- The startpos is only read when a campaign starts; the save then has its own copy of the regions. Attila's Lua can't add
  slots, and the engine only creates them when it loads a startpos.
- Pack priority on Feral's port: the pack listed first wins (a test pack listed first replaced `data.pack`'s
  `lua_scripts/frontend_scripted.lua`, and `fireforged_fixes.pack` listed first replaced Fireforged's startpos).
- An unattended new campaign: a throwaway pack listed first with `lua_scripts/frontend_scripted.lua` plus a navigator
  that clicks `button_campaign`, `button_new_campaign`, `att_fact_western_roman_empire`, `button_start_campaign` (the
  frontend's ids; the faction screen `sp_grand_campaign` is the campaign list too), and a campaign stub in
  `campaigns/main_attila/mods/<name>/scripting.lua`. Clicking into the window while a script moves the camera
  (`scroll_camera_with_direction`) crashed the game: a UI listener calls `context:IsComponentType` (`0x10214f304`) on a
  click that hit no component, with a null pointer.

## Writing ESF

rpfm_lib (v5.1.1) decodes these files, but its CAAB writer writes a `utf16[]` array's length as a u32 where the format
(and its own reader) has a CAULEB128, so what it writes doesn't decode again (`String not found: 262144`), for any
startpos. Its LZMA compressor (lzma-rs) also only writes literals, which made a startpos 15.6 MB instead of 6.7 MB.
twpack has its own writer (`tools/twpack/src/esf.rs`): rpfm's node encoder with that fixed, the original string tables'
order kept, and liblzma (`xz2`) with CA's LZMA settings (properties `5d 00 00 40 00`: lc 3, lp 0, pb 2, 4 MB dictionary).

A startpos is two ESFs: the outer one (`SAVE_GAME_HEADER`, `CAMPAIGN_PREOPEN_MAP_INFO`, `COMPRESSED_DATA`) and, in
`COMPRESSED_DATA`, the LZMA-compressed full campaign (`BUILD`, the same header and map info, `CAMPAIGN_ENV`, where the
regions are). rpfm_lib's decoder returns the inner one in place of the file; twpack reads both and writes both.

What twpack writes isn't byte-identical to CA's files: CA pads some CAULEB128 sizes (`BUILD`'s size takes 5 bytes
where 3 do) and rpfm_lib's tree doesn't keep that, so the record sizes come out a few hundred bytes shorter. Readers
decode both the same, and the game loaded a startpos twpack wrote; `esf check` checks that the rewritten file reads back as
the same campaign (Fireforged's and vanilla's startpos and the 390 AD save do), and twpack's own output comes back
byte-identical.

## Tools

- `twpack esf dump <file.esf> [-o out.txt]`, or `twpack esf dump <pack> --path campaigns/main_attila/startpos.esf`:
  the ESF as an indented text tree (`NAME[i]` for each block of a list). Fireforged's startpos is 170 MB of text,
  the 390 AD save 490 MB; grep it.
- `twpack esf check <file|pack --path …>`: re-encodes with twpack's writer, compares the bytes (the file, and a
  startpos's compressed ESF), recompresses and reads it back.
