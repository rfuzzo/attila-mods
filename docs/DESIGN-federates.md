# Federates: regions for troops – design (2026-10-07)

Fireforged's idea, the part of its region trading the native deals don't cover: you cede a region to a people, and
they serve you as *foederati*. Nothing here is implemented yet; the questions at the end are what I need decided.

## Historical basis

Rome granted land to a people in exchange for military service under their own leaders: Franks in Toxandria (358),
Goths in Thrace (382), Visigoths in Aquitania (418), Burgundians in Sapaudia (443). The treaty (*foedus*) was
concluded by the general in the field, and the federates fought beside him (Visigoths with Aetius at the Catalaunian
Plains, 451). Rome paid them (*annona*). Their loyalty depended on that general, on pay and on success: Alaric rose
after Theodosius died (395).

## What the native deal can't do

The engine's deal has no "troops" component, and the AI can't give units. So federates are our own addition on top
of a native region deal:

1. You **give** the AI one or more regions in the native deal, and ask for federates in return.
2. The AI scores the deal natively; the federates count like the AI **paying their value in gold** (the same way
   regions count), so a friendly AI gives more and a poor one values its warriors highly.
3. When the deal goes through, the units join your general's army (`add_unit_to_force`), right after the transfer
   (TWASE already calls the mod then).

## Options for the UI

| Option | How | For | Against |
|---|---|---|---|
| **A. A line in the region panel** (recommended) | Under the two lists: "Federates: ask for troops in return", a checkbox with the number of units and their total value; the tooltip lists the units. Ticking it adds the units to the deal. | One place for everything about land; the AI's score includes the troops at once | TWASE has to add a component to the panel and to the deal score |
| B. A separate entry in "Add Offer/Demand" | "Demand federates", like Payments | Looks fully native | The engine's list has no such action type: a lot of new reverse engineering |
| C. Fireforged's way | No units: ceding a region grants recruitment slots (an effect bundle) for some turns | Simple, no army needed | Not federates of that people, no loyalty, no link to the general |

## The troops

- **Who concludes it:** a general of yours with an army **in or next to** one of the ceded regions (decided
  2026-10-04). Without one, the federates line is greyed out with the reason. The army with the most free slots is
  chosen.
- **Which units:** copies of the AI's own land units (no generals), so the federates keep their culture: Gothic
  troops from the Goths. Alternative: the game's Roman foederati units (`att_rom_foederati_spears`,
  `att_rom_noble_foederati_javelinmen`, `bel_rom_foederati*`), which exist but are a Roman roster.
- **How many:** units worth up to 80 % of the ceded regions' value in recruitment cost, limited by the army's free
  slots, most expensive first, mixed types.
- **Upkeep:** you pay it (the *annona*).
- **The AI's side:** the units are copies; the AI keeps its armies (removing units from an AI army would need more
  TWASE work).

## Loyalty (v1, decided 2026-10-04: track it, grumbling and uprising)

One loyalty value per foedus, saved with it (army, general, units, home faction, region).

| Raises loyalty | Lowers loyalty |
|---|---|
| the concluding general alive and in command | that general dies or loses command (big drop) |
| victories, loot | heavy losses among the federate units |
| time: the foedus becomes normal | your treasury negative, upkeep unpaid |
| good relations with their home faction | war with their home faction (they won't fight their kin) |
| same religion as yours | another religion (small) |

Consequences, escalating: (1) grumbling, a morale malus on the army; (3) uprising, a rebellion in the region they
were settled in, and the federate units leave (leaving needs TWASE unit removal; until then the rebels spawn and the
army keeps the units). Step 2, a dilemma "pay X gold or refuse", is for v2.

## Decisions (2026-10-07)

1. UI: option A, a federates line in the region panel.
2. When: when you give regions (land for service); treaties can be in the same deal.
3. Units: a mix of the AI's own units, no elite ones (the most expensive quarter of its unit types; changed
   2026-10-07 after the ERE offered its Scholae).
4. Size: units worth up to 80 % of the ceded regions' value, limited by the army's free slots.
5. The AI's armies: copies, the AI loses nothing.
6. Repeated deals: none for now, one foedus per faction at a time.
7. Loyalty v1: grumbling (morale malus) and uprising.

## The game's own federates: "Recruit from Horde"

CA modelled foederati as a faction trait (`att_effect_faction_trait_roman_foederati_horde_levy`, effect
`mercenary_levy_can_recruit_from_local_hordes`: "Can levy units from friendly hordes passing through Roman
territory"; vanilla Romans only, Fireforged gives it to almost every culture). An army in your territory next to a
friendly **horde** can hire units from that people's own mercenary pool (`faction_to_mercenary_set_junctions`: 15
peoples, e.g. the Alans' Agathyrsi warriors and Sarmatian cataphracts), for gold, limited and slowly replenishing.
The recruitment panel offers it when one of its sources is a horde faction (`0x1034676c8`, horde check
`0x101b521ec`). Once a people is settled, it stops.

Vanilla's "Gift Region" to a horde is the settlement of a people on your land (the 382 / 418 foedera); after it, the
levy ends. That's where our federates can continue CA's idea.

### The levy system

The horde levy is one source of a wider native **levy** (`LEVY_MERCENARY_MANAGER`, `LEVY_MERCENARY_POOL`, command
`CCQ_RECRUIT_LEVY_MERCENARY_UNIT`). The recruitment panel offers "Levy from tributary" (client state), "Levy from
puppet state" and "Recruit from Horde"; effects like `mercenary_levy_units_per_region_mod` (the Sassanid "levies
from vassals" trait) and `att_effect_force_all_campaign_recruitment_cost_vassal_levy` tune it, and the Western Roman
Empire has an edict `att_edict_western_rome_levy_foederati`. Tributary and puppet status are native deal terms, so a
foedus can be: cede land + "become our tributary" in one native deal; the game then provides the ongoing levy and the
relationship (including its tendency to break away). To decide (2026-10-07).

## Implementation plan

Decided 2026-10-07: a free **contingent** when the deal is made, then an ongoing **levy** while the foedus lasts.

1. **Lua, the offer:** for the regions you give, the negotiating army (your general in or next to one of them, most
   free slots), the units and their cost (budget 80 % of the regions' value for the AI, limited by the free slots).
   Units: that people's own pool units (`faction_to_mercenary_set_junctions`, through a TWASE DB getter) where it has
   a pool, else copies of its land units; no elite ones. Done for the copies.
2. **TWASE, the panel:** a "Federates: N units" row at the top of the demand list (made with the engine's row
   template, so it ticks like a region), active only when you give regions and a general is there; otherwise it
   shows why not.
3. **TWASE, score and deal list:** the units' recruitment cost counts like the AI paying that much gold (the same
   mirror as regions); the deal list shows "+ federates (N units)" under your demands.
4. **On acceptance:** after the transfer the mod adds the units to the army (`add_unit_to_force`) and saves the foedus
   (one per faction at a time).
5. **The levy:** while the foedus lasts, your armies in or next to the ceded land can levy from that people's pool
   like from a friendly horde (TWASE: the recruitment sources count a foedus partner like a horde).
6. **Loyalty v1:** grumbling (morale malus bundle) and uprising (`force_rebellion_in_region`); an uprising ends the
   foedus and the levy.

## The original questions

1. **UI:** option A (a federates line in the region panel)?
2. **When:** only when you give regions (land for service), or also in a swap or when you add gold?
3. **Units:** copies of the AI's own units, the Roman foederati units, or a mix (their units, but at most a few
   elite ones)?
4. **Size:** 80 % of the region's value, limited by free slots: a region worth 6,000 would give about 9 units of median cost (500).
   Too many, too few?
5. **The AI's armies:** copies (the AI loses nothing), or should the AI lose those men (later, needs TWASE work)?
6. **Repeated deals:** can you get federates from the same faction again while an earlier foedus is running?
7. **Loyalty v1:** is grumbling + uprising enough for a start, as decided?
