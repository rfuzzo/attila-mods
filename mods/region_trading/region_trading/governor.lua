-- Transferring a province capital kills its governor: make him immortal for the transfer and mortal again when the
-- "death" recreates him (CharacterCreated fires during the transfer). From Region Trading Reloaded.
-- Called by TWASE around a native region deal's transfer (twase.set_region_transfer_handler).

local rt = require("region_trading/core");

local governor = {};

local protecting = false;

function governor.on_transfer(phase, region_key, to)
	if phase == "before" then
		local region = rt.world():region_manager():region_by_key(region_key);
		if region:has_governor() and region:governor():region():name() == region_key then
			rt.cm():set_character_immortality("character_cqi:" .. region:governor():cqi(), true);
			rt.log("protecting the governor of %s", region_key);
		end;
		protecting = true;
	else
		protecting = false;
		rt.log("transferred %s to %s", region_key, to);
	end;
end;

rt.cm():add_listener("RegionTrading_GovernorCreated", "CharacterCreated", true, function(context)
	if protecting then
		rt.cm():set_character_immortality("character_cqi:" .. context:character():cqi(), false);
		rt.log("governor recreated as cqi %d", context:character():cqi());
	end;
end, true);

return governor;
