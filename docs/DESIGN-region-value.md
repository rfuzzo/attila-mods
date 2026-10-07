# Region value – design (2026-10-07)

What a region is worth to the AI in a deal, and how that becomes a yes or no. The current state is implemented and
tested. The proposals at the end aren't implemented yet; the questions are what I need decided first.

## 1. How a region enters the AI's decision (now)

The AI decides every deal with the **game's own evaluator** (`0x101d7b25c`). Each part of the deal is one
*component* (peace, alliance, trade agreement, Payments, …), scored by the AI's personality and its relationship to
you (DB `cai_personality_deal_evaluation_*`: a value per relationship band from "bitter enemies" to "best friends",
and balance factors for war and peace). The sum is the deal score; the AI accepts at ≥ 0, and the likelihood shows
low / moderate / high.

Regions have no component of their own (vanilla only gifts them to hordes, for free). TWASE adds one: a region worth
**V gold** to the AI counts exactly like **the AI not having to pay V gold** in Payments. So regions, gold and
treaties are on one scale, and everything the game applies to gold applies to regions too:

- **Relative to the AI's treasury.** The same region weighs much more for a poor faction. Measured (Aquae Sextiae,
  V = 6,069): Alamanni +154.5, Eastern Roman Empire +13.1.
- **The relationship.** A friendly AI values your gold, and so your regions, more than a hostile one.
- **Small amounts.** The game's table ignores amounts that are small for the treasury. TWASE interpolates below the
  first step, so a swap 439 short now scores −0.8 for the ERE instead of 0.

A region you give counts +V for the AI, a region it gives counts −V; V is always computed for the faction that
evaluates, as the (new or current) owner.

## 2. The value V (now, `value.lua`)

```
V = (max(wealth − building upkeep, 0) × 10 turns  +  25 % × Σ building create_cost × health)  ×  factors
```

| Part | Now | Source |
|---|---|---|
| income | net income (untaxed GDP minus building upkeep), never below 0, × 10 turns | `twase.region_wealth`, DB `building_levels.upkeep_cost` |
| buildings | 25 % of every building's cost, × its health | model `slot_list`, DB `building_levels.create_cost` |
| province complete | × 1.3 if the faction then owns the whole province | `twase.region_province`, model owners |
| enclave | × 0.5 for a new owner without an adjacent region | model `adjacent_region_list` |
| religion | × (1 ± 0.2 × majority share), + same as the faction's state religion, − other | model |
| unrest | × (1 − 1 % per point of negative public order), at least × 0.5 | model `public_order` |

Examples (WRE 367 AD, valued by the ERE): Aquae Sextiae 6,069, Serdica 2,841, Viminacium 2,542, Ajax 2,103, Eboracum
924 (for the Votadini). Console: `region_trading.explain(region_key[, faction_key])` shows every part.

Today V can't be negative: income is clamped at 0 and the factors only shrink it. We decided on 2026-10-04 that a
region can be a burden.

## 3. Proposals

### 3.1 Burden: regions that cost more than they bring

A region is worth less than nothing when holding it costs more than it yields. Sources, in gold over the same 10 turns:

| Burden | Proposal | Historical sense |
|---|---|---|
| negative net income | drop the clamp: `(wealth − upkeep) × 10` can go below 0 | a province that costs more than it yields (Britain, given up around 410) |
| unrest | instead of the × 0.5 floor: below −X public order a rebellion is likely; count the upkeep of a garrison army for some turns | Isaurian and Bacaudae revolts tied down armies |
| frontier | the region borders a faction the receiver is at war with: count garrison upkeep | the Danube limes, the Rhine after 406 |
| enclave | keep × 0.5 on the positive part, plus a fixed defence cost | isolated holdings like Soissons were lost |

`V = positive part × factors − burden`, so a rich region stays worth something even with a burden, and a poor,
rebellious enclave goes negative.

### 3.2 Army leverage (your question from 2026-10-05)

No hard rule (any region can be asked for), but the owner gives up a region more easily when your army has it in
hand. It changes only the **owner's** value of a region it would give:

| Situation | Owner's V | Historical sense |
|---|---|---|
| your army besieges the settlement | × 0.25 | cities surrendered to a besieger on terms |
| your army stands in the region (at war) | × 0.5 | *uti possidetis*: Jovian ceded Nisibis with his army trapped in Persia (363) |
| your army stands in the region (at peace, with military access) | × 0.85? | a show of force, weaker |
| your army next to the region | no change? | |

The receiving side (you) values nothing here: the AI's view of what it gets doesn't depend on armies.

### 3.3 Reluctance to cede

Rulers lost face by giving up land: Jovian's treaty was called a disgrace, and Rome rarely ceded provinces it still
held. Proposal: the owner values what it gives × 1.5 (more for a province capital, less for a region of another
culture or religion than its own). This makes swaps of equal value fail unless you add something, which fits how
rarely powers exchanged land outright (Armenia's partition around 387 was part of a wider peace).

### 3.4 Calibration

Log, for each evaluation, the AI's treasury, the relationship band, V and the score part, and play a few turns with
different factions (rich / poor, friendly / hostile). Then tune `income_turns`, the building share and the burden
amounts so typical deals land where they feel right: e.g. a friendly neighbour pays roughly a region's value in
gold, a hostile one refuses unless you overpay.

## 4. Decisions (2026-10-07) and implementation

1. **Burden:** negative income, unrest and enclave count; frontier is left out for now. Implemented: income below 0
   counts in full (no clamp), unrest costs 30 gold per point of negative public order (instead of the × 0.5 floor), an
   enclave halves the positive part and costs 1,000 for its defence.
2. **Army leverage:** siege × 0.25, an army in the region at war × 0.5, at peace × 0.85, next to the region nothing.
   Implemented (the other side's armies with a general in the region; the deal's other faction comes from TWASE).
3. **Reluctance:** yes, giving land away is a huge deal: × 2.0 on the owner's positive value, − 0.5 for a region of
   another religion than the owner's. Province capitals can't get more yet: the game's Lua has no province capital
   check (TWASE task).
4. **Poor vs rich:** kept, but by GDP only. TWASE rescales the region's amount so the game's economic power is
   computed without the treasury (which a deal earlier in the turn can move): `clamp(GDP / 8,000, 0.2, 4)`.
5. **Your side:** yes, show what a region is worth to you in the panel (next step).

First numbers (WRE 367, valued by the ERE): Aquae Sextiae 5,069 (was 6,069, enclave burden), Olisipo 494 (enclave,
unrest 600), Serdica 4,261 (its own, × 1.5), Viminacium 3,240 (its own, a WRE army in it at peace, × 0.85).
To tune: all ERE regions have another majority religion than its (Arian) state religion, so the reluctance is
always 1.5 for the ERE.

## 5. The original questions

1. **Burden:** which sources should count (negative income, unrest, frontier, enclave)? Any you'd leave out?
2. **Army leverage:** are the factors in 3.2 right? Should an army at peace (military access) count at all, and
   should an army next to the region count?
3. **Reluctance:** do you want the × 1.5 for regions the AI gives up? It makes the AI harder to deal with, also
   for swaps.
4. **Poor vs rich factions:** keep the game's treasury scaling (a poor tribe values land far more than an empire),
   or flatten it?
5. **Your side:** the AI only values what it gets and gives. Should the panel also show you what a region is worth
   to *you* (e.g. in the region's tooltip), so you can judge a swap?
