-- The Dawnless Days (campaign main_attila_map) without its external patcher. TDD's ExtendSlotLimits
-- (lua_scripts/extend_slots.lua) starts TDD_12_9_slots_A.exe, which rewrites the settlement cards' slot limits
-- (6/4 -> 12/9) and the encyclopedia URL in the game's memory. This sets the same through TWASE's Lua API instead.
-- TDD's scripting.lua calls the global ExtendSlotLimits on UICreated, after ConfigureEncyclopedia has set
-- baseEncyclopediaUrl; TWASE loads this file before that. Deploy loose, remove to get TDD's patcher back.
local MAJOR, MINOR = 12, 9; -- TDD's settlement_panel: building_slot_1..12 on the capital card, 1..9 on the others
local function log(fmt, ...) print("[tdd_twase_slots] " .. string.format(fmt, ...)) end;

local tdd_extend = ExtendSlotLimits;
if type(tdd_extend) ~= "function" then
	log("ExtendSlotLimits is not defined (TDD not loaded, or changed); nothing replaced");
	return;
end;
if type(twase) ~= "table" or type(twase.set_max_slots_major) ~= "function" then
	log("This TWASE has no slot API; TDD's patcher stays");
	return;
end;

function ExtendSlotLimits()
	local ok, err = pcall(function()
		twase.set_max_slots_major(MAJOR);
		twase.set_max_slots_minor(MINOR);
	end);
	if not ok then
		-- The hook isn't installed (unknown game build); TDD's patcher still finds its byte patterns.
		log("TWASE slot limits unavailable (%s); running TDD's patcher", tostring(err));
		return tdd_extend();
	end;
	log("Slot limits %d/%d set through TWASE", MAJOR, MINOR);
	if type(baseEncyclopediaUrl) == "string" and baseEncyclopediaUrl ~= "" then
		local url_ok, url = pcall(twase.set_encyclopedia_url, baseEncyclopediaUrl);
		log(url_ok and "Encyclopedia URL %s" or "Encyclopedia URL not changed: %s", tostring(url));
	end;
end;
log("Replaced TDD's ExtendSlotLimits");
