-- Tuning values, see docs/DESIGN-region-trading.md ("Start values"). All values are in gold.

return {
	-- Region value
	income_turns = 10,               -- value = net income (wealth - building upkeep) x this many turns
	building_share = 0.25,           -- + this share of the buildings' create_cost, x their health
	province_complete_bonus = 0.30,  -- the receiver then owns the whole province
	enclave_malus = 0.50,            -- no adjacent region of the receiver
	religion_factor = 0.20,          -- +/- this, x majority religion share, same / other religion than the receiver's
	unrest_per_point = 0.01,         -- - this per point of negative public order
	unrest_floor = 0.5,              -- unrest can't take the value below this factor
	min_value = 200,                 -- every region is worth at least this

	-- Relationship
	attitude_share = 0.01,           -- share of the deal value per point of the AI's attitude towards the player
	attitude_cap = 1.0,              -- at most +/- this share of the deal value
	alliance_bonus = 0.15,           -- share of the deal value
	trade_agreement_bonus = 0.05,

	-- Prices the AI pays
	money_lump_share = 0.5,          -- of the region's value
	money_lump_treasury_cap = 0.5,   -- at most this share of the AI's treasury
	money_payments_share = 0.7,      -- total over money_payments_turns
	money_payments_turns = 10,
	troops_share = 0.8,              -- recruitment cost of the units, of the region's value
	army_size = 20,                  -- units per army

	-- Likelihood display, as a share of the deal value
	band = 0.10,
};
