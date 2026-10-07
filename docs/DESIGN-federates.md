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

1. UI: its own entry in "Add Offer/Demand", **"Region for Troops"** (changed 2026-10-07 after trying the federates row
   in the region panel, which was reverted). It opens the region panel in troops mode: your regions on the left, their
   warriors on the right.
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
relationship (including its tendency to break away). **Decided 2026-10-07: a foedus is native, land +
tributary in one deal**; our free contingent comes on top.

## Willingness: who becomes your federates (draft for review, 2026-10-07)

Decided 2026-10-07: the units cost the AI nothing in the deal score (their number already follows from the land's
value). What decides is whether a people is willing to become federates at all. The precedents: Goths 332 (after
their defeat by Constantine), Goths 382 (after Adrianople, at war, unbeaten but worn out), Visigoths 418 (starved by
Constantius' blockade), Vandals 435 (after their conquests in Africa), Burgundians 443 (after their defeat in 436).
What they share: peoples, not states; under pressure (landless, hungry, defeated or exhausted); facing a stronger
partner. War is often the occasion, not the barrier. No great power became anyone's federates.

Proposal: the troops term adds a **willingness** W to the deal score (in the game's score points, where ±4 is the
likelihood band), instead of a cost for the units. The land itself is valued as before.

| Factor | W | Source |
|---|---|---|
| a state, not a people (Roman or Eastern culture) | −30, effectively never | `faction:culture()` |
| landless: a horde | +8 | `is_horde()` |
| little land: 1–2 regions / 3–5 / more | +4 / 0 / −4 | `region_list()` |
| hungry (food shortage) | +4 | `has_food_shortage()` |
| broke (losing money) | +2 | `losing_money()` |
| your strength over theirs (units in armies): ≥ 3× / ≥ 1.5× / below 1× | +4 / +2 / −6 | `military_force_list()` |
| at war with you: you're far stronger (≥ 3×) / otherwise | +2 (a peace settlement) / −6 (unbeaten enemies refuse) | `at_war_with()` |
| attitude towards you | ± attitude / 25, at most ± 4 | `twase.faction_attitude` |
| allied with you | +2 | `allied_with()` |

Examples: the Visigoths as a horde at war with a far stronger Rome, hungry: 8 + 4 + 4 + 2 + attitude ≈ +18, they
accept even a poor strip of land. The Franks with 4 regions, at peace, Rome 2× stronger: 0 + 2 + attitude ≈ +2,
they want good land. The ERE: −30, never.

Questions:

1. Should Roman and Eastern factions be excluded entirely (no troops entry), or just very unwilling?
2. At war: is "far stronger" the right condition for a foedus as a peace settlement, or should a war always make it
   harder?
3. The tributary status (the native levy) was meant to come with the foedus in the same deal. With W, should the
   troops term imply it (the deal makes them your tributary), or stay a separate native term you add (and the AI
   scores natively)?
4. The numbers as a start?
Answers (2026-10-07): (1) Roman and Eastern factions are just unwilling (−30), no exclusion. (4) Hordes: yes, the
troops entry replaces vanilla's "Gift Region" for hordes (settling a people as federates). (5) The numbers as a
start, to tune in play. (2, 3) open: ceding land is a big step for the player too; it's realistically tied to a
peace or a tributary relationship.

**Decided (2026-10-07), (2, 3):** a foedus is land + a contingent + a bond. Confirming a Region for Troops adds the
native terms "Make Tributary State" (action type 25) and, at war, "Peace" (type 2, to confirm) to the deal, the way a
click in "Add Offer/Demand" does (dispatcher `0x1035f5044`); the game executes them on acceptance, no script calls. In
a troops deal TWASE leaves the game's scores of those two terms out and adds the willingness W instead.

5. Hordes: the "Region for Troops" entry only appears for settled factions today (hordes keep vanilla's "Gift
   Region", which settles them, but only on regions where their army stands). Settling a horde as federates is the
   classic case (382, 418): should the troops entry also be offered to hordes, with vanilla's rule for which regions?

## Implementation plan

Decided 2026-10-07: a foedus is a native deal: you cede land and demand that the people becomes your **tributary**.
The game then provides the ongoing levy ("Levy from tributary") and the relationship. On top, a free **contingent**
of their warriors when the deal is made.

1. **Lua, the offer:** for the regions you give, the negotiating army (your general in or next to one of them, most
   free slots), the units and their cost (budget 80 % of the regions' value for the AI, limited by the free slots).
   Units: that people's own levy pool units (`faction_to_mercenary_set_junctions`, through a TWASE DB getter) where it
   has one, else copies of its land units; no elite ones. Done for the copies.
2. **TWASE, the panel:** done (2026-10-07). A second button for the region action, "Region for Troops", in the
   "Add Offer/Demand" list (a copy of the region action's entry, so the engine makes and lays out the button); its
   click opens the region panel in troops mode: "Cede Region" (your regions) on the left, "Their Warriors" on the
   right (the units, or why none), updated as you tick. OK puts the ticked regions in the deal and remembers the
   deal's region term as for troops.
3. **TWASE, score and deal list:** the units' recruitment cost counts like the AI paying that much gold (the same
   mirror as regions); the deal list shows the term as "Region for Troops" with the units.
4. **On acceptance:** after the transfer the mod adds the units to the army (`add_unit_to_force`) and saves the foedus
   (one per faction at a time).
5. **Loyalty:** only if the native tributary relationship isn't enough (it already breaks away on its own).

To check in play: the AI's answer to land + tributary, and where "Levy from tributary" becomes available (in the
tributary's regions with your army there?).

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
