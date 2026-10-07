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
2. When: only in a region swap (see the open point below).
3. Units: a mix, mostly copies of the AI's own units, at most a few elite ones.
4. Size: units worth up to 80 % of the ceded regions' value, limited by the army's free slots.
5. The AI's armies: copies, the AI loses nothing.
6. Repeated deals: none for now, one foedus per faction at a time.
7. Loyalty v1: grumbling (morale malus) and uprising.

Open: question 2's answer, "only in a region swap", to confirm (a swap is regions both ways; a foedus was land for
service, i.e. you give regions and get troops).

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
