-- Building slots: vanilla's startpos, and so Fireforged's, gives these settlements one secondary slot too few
-- (docs/BUG-missing-building-slots.md). The fix is not Lua: tools/deploy.sh puts a copy of Fireforged's startpos
-- with the slots added into this mod's pack, which only new campaigns use, and only if the pack has priority over
-- @Fireforged-Empire_1.pack. This module just reports whether the running campaign has them.

local ff = require("fireforged_fixes/core");

-- region key -> slots it should have
local REGIONS = {
	att_reg_maxima_sequanorum_argentoratum = 4,
	att_reg_bithynia_ancyra = 6,
	att_reg_cappadocia_caesarea_eusebia = 6,
	att_reg_palaestinea_nova_trajana_bostra = 6,
};

-- Log the slot count of each region; returns how many are short.
local function report()
	local keys = {};
	for key in pairs(REGIONS) do keys[#keys + 1] = key end;
	table.sort(keys);
	local short = 0;
	local manager = ff.cm():model():world():region_manager();
	for _, key in ipairs(keys) do
		local region = manager:region_by_key(key);
		local count = region and region:slot_list():num_items();
		if count ~= REGIONS[key] then short = short + 1 end;
		ff.log("  %s: %s of %d slots", key, tostring(count), REGIONS[key]);
	end;
	if short > 0 then
		ff.log("%d settlements short of slots: this campaign started without the startpos fix, or fireforged_fixes.pack doesn't have priority over Fireforged's", short);
	end;
	return short;
end;

return { REGIONS = REGIONS, report = report };
