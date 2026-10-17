# Missing building slots (Argentoratum and three others)

Status 2026-10-17: cause found (vanilla bug, inherited by Fireforged); patched startpos in `fireforged_fixes`, not tested in game yet. Investigated with `twpack esf dump` (new, see below).

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
generated with these slot counts. That happens in CA's Assembly Kit (BOB), from its own slot data, which isn't in the game.

The save `Picts 390 AD Spring.save` has the same counts (Argentoratum `:0`–`:2`, Ancyra `:0`–`:4`), so a running campaign
keeps what its startpos had.

Vanilla has the same four: its `TotalWarAttilaData/data/campaigns/main_attila/startpos.esf` (loose, like every
campaign's startpos, not in a pack) has the same 186 regions with the same counts (123 × 4, 59 × 6, 3 × 5, 1 × 3) and
the same four short regions. So it's a base game bug that Fireforged inherited when it rebuilt its startpos, not a
Fireforged bug. (That file was missing on this machine until a Steam "verify integrity" on 2026-10-17 restored it;
why it was gone is unknown.)

## Fix (in `fireforged_fixes`)

`mods/fireforged_fixes/.generate` (run by `tools/deploy.sh` on every build) takes the startpos out of the installed
`@Fireforged-Empire_1.pack`, adds the slots with `twpack esf add-slots`, and puts it into `fireforged_fixes.pack` as
`campaigns/main_attila/startpos.esf`. It isn't in git (it's Fireforged's and CA's data), and since it's made from the
installed pack it follows Fireforged's updates.

Each new slot is a copy of the region's last secondary slot (same template: `rom_minor_secondary`, `att_major_silk`,
`rom_major_secondary`) with the next index in its key (`…argentoratum:3`, `…ancyra:5`), the building manager of an empty
slot (no `BUILDING_BASE`), and the next free ids: slots 865–868, garrisons 1051–1054. The ids were 1–864 and 1–1050
without gaps, numbered in region order, so the new ones are out of order; whether the game minds is what the in-game
test shows. Nothing else in the file refers to slots by key (each key occurs once), and the dump of the patched file
differs from Fireforged's only in the four added slots.

Limits:
- **New campaigns only.** A save has its own copy of the regions; the running campaign keeps its 3 / 5 slots.
  (`add-slots` also takes a save, which has the same outer / compressed layout, but that's untested.)
- **Load order:** the pack has to have priority over `@Fireforged-Empire_1.pack`, or Fireforged's startpos wins.
  In Total War the pack listed first wins, so `tools/mod_list.txt` lists `fireforged_fixes.pack` before Fireforged's;
  in Feral's mod manager put it above them. Not verified on Feral's port yet.
- **Check in game:** `fireforged_fixes.report()` in the console logs the four settlements' slot counts (`4 of 4`,
  `6 of 6`) and says when some are short.

Other options considered: asking Fireforged to fix it when they next rebuild their startpos with the Assembly Kit
(cleaner, but out of our hands), and a runtime fix (Attila's Lua can't add slots; a TWASE hook would be much more
reverse engineering).

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
decode both the same; `esf check` checks that the rewritten file reads back as the same campaign (Fireforged's and
vanilla's startpos and the 390 AD save do), and twpack's own output comes back byte-identical.

## Tools

- `twpack esf dump <file.esf> [-o out.txt]`, or `twpack esf dump <pack> --path campaigns/main_attila/startpos.esf`:
  the ESF as an indented text tree (`NAME[i]` for each block of a list). Fireforged's startpos is 170 MB of text,
  the 390 AD save 490 MB; grep it.
- `twpack esf check <file|pack --path …>`: re-encodes with twpack's writer, compares the bytes (the file, and a
  startpos's compressed ESF), recompresses and reads it back.
- `twpack esf add-slots <file|pack --path …> -o <out.esf> <region>...`: adds one empty secondary slot per region key.
