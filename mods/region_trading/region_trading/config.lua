-- Tuning values of the region value (value.lua), in gold. See docs/DESIGN-region-trading.md.

return {
	income_turns = 10,               -- value = net income (wealth - building upkeep) x this many turns
	building_share = 0.25,           -- + this share of the buildings' create_cost, x their health
	province_complete_bonus = 0.30,  -- the receiver then owns the whole province
	enclave_malus = 0.50,            -- no adjacent region of the receiver
	religion_factor = 0.20,          -- +/- this, x majority religion share, same / other religion than the receiver's
	unrest_per_point = 0.01,         -- - this per point of negative public order
	unrest_floor = 0.5,              -- unrest can't take the value below this factor
};
