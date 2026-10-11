# Federates: regions for troops – design

Updated 2026-10-07. Built and tested in game (WRE 367 AD: Savaria to the Quadi at war, Ajax to the Franks). Part of
[region trading](DESIGN-region-trading.md).

## Historical basis

Rome granted land to a people in exchange for military service under their own leaders: Goths 332 (after their
defeat by Constantine), Goths 382 (after Adrianople, at war, unbeaten but worn out), Visigoths 418 (starved by
Constantius' blockade), Vandals 435 (after their conquests in Africa), Burgundians 443 (after their defeat in 436).
The treaty (*foedus*) ended a conflict and bound the people to Rome; the federates fought as their own contingent
under their own leaders, next to the Roman army (Visigoths with Aetius at the Catalaunian Plains, 451), and Rome paid
them (*annona*). What the cases share: peoples, not states; under pressure (landless, hungry, defeated or exhausted);
facing a stronger partner. War is often the occasion, not the barrier. No great power became anyone's federates.

## The deal: "Region for Troops"

A foedus is **land + a contingent + a bond**, built from native parts:

- **The entry:** "Region for Troops" in "Add Offer/Demand" (TWASE adds a second button for the region action). It
  opens the region panel in troops mode: your regions on the left ("Cede Region"), their warriors on the right ("Their
  Warriors": the units and their cost, or why none), updated as you tick. Several regions can be ceded at once.
- **The bond:** confirming adds the native terms **"Peace Treaty"** (at war) and **"Make Tributary State"** (the AI
  becomes your tributary; at war the engine offers it once peace is in the deal). The game executes them on
  acceptance, no script calls. The tributary status gives the game's ongoing levy ("Levy from tributary", in the
  tributary's regions with their buildings, not in the ceded land).
- **Landless peoples** (e.g. the Blemmyes, no regions, not a horde): the engine offers "Make Tributary State" only to a
  faction with land, so their deal lacks it. TWASE tells the mod whether the deal has the term; if not, the mod makes
  them your tributary once the land is theirs (`cm:force_make_vassal(player, ai)`, after the transfer).
- **At war** the region entries (Trade Regions and Region for Troops) only appear once peace is in the deal.
- **The deal list** labels the term "Region for Troops".

## The AI's decision: willingness

The units cost the AI nothing in the score (their number follows from the land's value). In a deal for troops the
game's own scores of the peace and tributary terms are left out; instead the **willingness** W counts, in the game's
score points (±4 is the likelihood band), plus the land as in any region deal. Other terms (e.g. money) count
normally.

| Factor | W |
|---|---|
| a state, not a people (Roman or Eastern culture) | −30, effectively never |
| landless: a horde | +8 |
| little land: 1–2 regions / 3–5 / more | +4 / 0 / −4 |
| hungry (food shortage) / broke (losing money) | +4 / +2 |
| your field armies over theirs: ≥ 3× / ≥ 1.5× / weaker | +4 / +2 / −6 |
| at war with you: you're far stronger (≥ 3×) / otherwise | +2 (a peace settlement) / −6 |
| attitude towards you | ± attitude / 25, at most ± 4 |
| allied with you | +2 |

WRE 367 AD: ERE −27, Quadi (at war) +6, Visigoths +4, Alani +4.6, Franks +4.3. Tuned in `config.lua`
(`willingness`); to tune in play.

## The warriors: a new army of yours

On acceptance the warriors **form a new army of yours** at the settlement of the ceded region (the most valuable one
if several), with `cm:create_force` (the game generates the general and finds a free spot):

- **Units:** that people's own levy pool (`twase.levy_pool`, the units the game's levy offers from them; 15 peoples,
  e.g. Gothic pikemen and falxmen) where it has one, else copies of the land units in its field armies. No elite ones
  (the most expensive quarter of its unit types), each pool type at most its pool count, cycling through the types.
- **Size:** units worth up to 80 % of the ceded land's value for the AI, at most 19 (plus the general).
- **Why a new army:** federates fought as their own contingent; no general of yours is needed nearby; loyalty can act
  on that army as a whole. Going over the army limit is fine (the game allows it).
- **Garrisons** are never field armies: they're led by a colonel or the province's governor and cost no upkeep.
- One foedus per people at a time (saved with the game).

## Decisions (2026-10-07)

- Roman and Eastern factions are only very unwilling, not excluded.
- The willingness alone decides for now; no part of the native peace / tributary score is kept.
- Hordes: the troops entry should replace vanilla's "Gift Region" for hordes (settling a people as federates).
- Dropped on the way: a federates row in the Gift Region panel (tried, reverted), units joining a general's army
  (federates fought as their own contingent, and it needed a general nearby), the units' cost in the score.

## Open

- **Hordes:** the troops entry for hordes (they keep vanilla's rules today). Plan (2026-10-11): with a horde, only
  "Region for Troops" (no Trade Regions), for regions where the horde's army stands (vanilla's rule), the land not
  counted as an enclave for a landless receiver. Found 2026-10-11 (WRE 367 AD, dev harness mode `teleport`, a copy of
  the horde's army spawned in Salona with `create_force`; the campaign has no teleport): neither the Attacotti (at war,
  also after peace in the deal) nor the Huns (at peace) get vanilla's "Gift Region" (action 6 not available) or "Make
  Tributary State" (25 not available). Open: why vanilla's region rule doesn't list Salona (an army spawned the same
  turn not counted yet? a garrisoned settlement?); try at the next turn, and a region without an army of yours.
- **Check in play:** the Blemmyes' foedus: does `force_make_vassal(player, ai)` make them your *tributary* (not a
  puppet), and in that argument order?
- **Loyalty v1** (decided 2026-10-04: grumbling and uprising, on the federate army). The game already has an army
  **integrity** with mutinies (the new army showed "Obedient 50, −6 per turn, mutiny in 9 turns": faction −5, politics
  −1, foreign soil −1, friendly territory +1); check whether that's enough, or how our loyalty fits with it.
- **The army's name:** the game names it like a Roman legion ("Legio XIV Diocletiana"); e.g. "Foederati of the Quadi".
- **The panel** could say where the army will appear.
- **Ending a foedus:** when it ends (the tributary breaks away, the army is destroyed or disbanded), so that a new one
  can be made with that people.
- Calibration in play: the 80 % share, the willingness numbers, small contingents for poor land (Ajax gave 2 units).
