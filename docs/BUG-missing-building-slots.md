# Missing building slots (Argentoratum and three others)

Status 2026-10-17: cause found (vanilla bug, inherited by Fireforged), not fixed. Investigated with `twpack esf dump` (new, see below).

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

## Fix options

1. **Ask Fireforged to add the slots** when they next rebuild their startpos. CA won't patch Attila any more, but
   Fireforged regenerates its own startpos with the Assembly Kit, so they could fix the slot data there. That's the clean fix,
   but it only helps new campaigns.
2. **Patch the startpos ourselves**: copy a secondary `REGION_SLOT` record of the same region, set the next index in its
   key (`…argentoratum:3`), clear its building, give it unused slot / garrison / building ids, and ship the startpos in a
   small pack loaded after Fireforged. New campaigns only, and the copy has to be redone whenever Fireforged updates its
   startpos (it would otherwise silently undo their changes). Open questions: how the game allocates these ids (a counter
   somewhere in the file that new ids must stay below or above), and whether slots are also referenced elsewhere (in the
   save, each slot key appears twice, in the startpos only once).
3. **Patch the save** the same way, for the running campaign. Same tooling and open questions; saves are CAAB ESF too.
4. **At runtime (Lua / TWASE)**: Attila's Lua has no way to add slots, and a native hook that adds one to a region would
   be much more reverse engineering than options 2 and 3.

Options 2 and 3 are blocked on writing ESF: rpfm_lib (v5.1.1) decodes these files, but what it encodes doesn't decode
again (`String not found: 262144`), for Fireforged's startpos and for vanilla's `pro_attila` one alike, so it's an
rpfm_lib bug in the CAAB writer, not something in the file. Its encoder also writes the whole tree uncompressed next to
a new compressed copy (`COMPRESSED_DATA`, which is what the decoder reads), 15.6 MB instead of 6.7 MB; whether the game
accepts that layout is untested. So a patch needs a working CAAB writer first (fix rpfm's, or write one in twpack),
checked with `twpack esf check` until it reports the same tree, and then a test in game.

## Tools

- `twpack esf dump <file.esf> [-o out.txt]`, or `twpack esf dump <pack> --path campaigns/main_attila/startpos.esf`:
  the ESF as an indented text tree (`NAME[i]` for each block of a list). Fireforged's startpos is 170 MB of text,
  the 390 AD save 490 MB; grep it.
- `twpack esf check <file|pack --path …>`: decodes, re-encodes and decodes again, and says whether the tree survives.
