-- Tuning values of the region value (value.lua), in gold. See docs/DESIGN-region-value.md.

return {
	income_turns = 10,               -- value = net income (wealth - building upkeep) x this many turns, negative at a loss
	building_share = 0.25,           -- + this share of the buildings' create_cost, x their health
	province_complete_bonus = 0.30,  -- the receiver then owns the whole province
	enclave_malus = 0.50,            -- no adjacent region of the receiver: the positive part x (1 - this)
	enclave_burden = 1000,           -- and its defence costs this much
	religion_factor = 0.20,          -- +/- this, x majority religion share, same / other religion than the receiver's
	unrest_burden_per_point = 30,    -- per point of negative public order (garrisons, the risk of a revolt)

	-- The owner giving a region away
	cession_reluctance = 2.0,        -- giving land away is a huge deal: the owner's (positive) value x this
	reluctance_other_religion = 0.5, -- less for a region of another religion than the owner's
	leverage_siege = 0.25,           -- the other side's army besieges the settlement
	leverage_war = 0.5,              -- the other side's army stands in the region, at war
	leverage_peace = 0.85,           -- the other side's army stands in the region, at peace (military access)
};
