-- Spawn points. antonina_incident.lua has 40 FindXxx() functions with the same body: pick a random point from a
-- global array, check it with IsValidSpawn, remove it from the array and return it. Nothing refills the arrays, and
-- some have fewer points than callers (army_east: 2 points, 3 Iranian Hun armies; army_germania: 4 points, 8
-- Germanic spawns and respawns). Once an array is empty cm:random_number(0) raises a script error, the spawn is
-- lost and the rest of the turn's listener work is skipped. The fallback line after the loops also reads
-- `randomSpawn`, which is out of scope there.
--
-- Replacement: among the points that pass IsValidSpawn (far from armies first, then only not on top of one) pick
-- a random one and take it out of the pool, so successive spawns still use different places; an empty pool is
-- refilled from a copy made when the mod loaded; if no point is valid, take any.

local ff = require("fireforged_fixes/core");

-- Find function -> the global array of {x =, y =} points it draws from.
local POOLS = {
	FindAlaniSpawn = "army_leopolis",
	FindAntSpawn = "army_ant",
	FindAntiohiaSpawn = "army_Antiohia",
	FindArabiaSpawn = "army_Arabia",
	FindCaledoniaSpawn = "army_caledonia",
	FindERESpawn = "army_ERE",
	FindFrisiaSpawn = "army_frisia",
	FindGepidiSpawn = "army_apulum",
	FindGermaniaSpawn = "army_germania",
	FindGreithungiSpawn = "army_chersonessus",
	FindIsavriSpawn = "army_Isavri",
	FindMacedoniaSpawn = "army_Makedonia",
	FindOstgotiSpawn = "army_petrodava",
	FindRomaMavritaniaSpawn = "army_mavritania",
	FindRomanSpawn = "army_brittania",
	FindSarmatov_KvadovSpawn = "army_Sarmatov_Kvadov",
	FindSpawn = "army_sarmatiya",
	FindSpawn0 = "army_zero",
	FindSpawn010 = "army_zero10",
	FindSpawn011 = "army_zero11",
	FindSpawn012 = "army_zero12",
	FindSpawn013 = "army_zero13",
	FindSpawn014 = "army_zero14",
	FindSpawn015 = "army_zero15",
	FindSpawn016 = "army_zero16",
	FindSpawn02 = "army_zero2",
	FindSpawn03 = "army_zero3",
	FindSpawn04 = "army_zero4",
	FindSpawn05 = "army_zero5",
	FindSpawn06 = "army_zero6",
	FindSpawn07 = "army_zero7",
	FindSpawn08 = "army_zero8",
	FindSpawn09 = "army_zero9",
	FindSpawn2 = "army_east",
	FindSpawnBagaud = "army_galliya",
	FindSpawnEuro = "army_euro",
	FindVandaliSpawn = "army_budorgis",
	FindVandaliSpawn2 = "army_budorgis2",
	FindVestgotiSpawn = "army_markianorol",
	FindWRESpawn = "army_WRE",
};

local function make_picker(env, pool_name, pristine)
	return function()
		local pool = env[pool_name];
		if type(pool) ~= "table" then
			return nil;
		end;

		if #pool == 0 then
			for i = 1, #pristine do
				pool[i] = pristine[i];
			end;
			ff.log("spawn points %s used up, refilled with %d", pool_name, #pristine);
		end;
		if #pool == 0 then
			return nil;
		end;

		local cm = ff.cm();
		local is_valid = env.IsValidSpawn;

		-- pass 1: far from other armies (the original's safe check), pass 2: just not on top of one
		for pass = 1, 2 do
			local candidates = {};
			for i = 1, #pool do
				if not is_valid or is_valid(pool[i].x, pool[i].y, pass == 1) then
					candidates[#candidates + 1] = i;
				end;
			end;
			if #candidates > 0 then
				return table.remove(pool, candidates[cm:random_number(#candidates)]);
			end;
		end;

		return table.remove(pool, cm:random_number(#pool));
	end;
end;

local function apply(env)
	local count = 0;
	for func_name, pool_name in pairs(POOLS) do
		local pool = env[pool_name];
		if type(env[func_name]) == "function" and type(pool) == "table" then
			local pristine = {};
			for i = 1, #pool do
				pristine[i] = pool[i];
			end;
			env[func_name] = make_picker(env, pool_name, pristine);
			ff.patched[func_name] = true;
			count = count + 1;
		else
			ff.log("%s or %s not found, not patched", func_name, pool_name);
		end;
	end;
	ff.log("spawn points: %d of %d pickers replaced", count, 40);
	return count;
end;

return { apply = apply, POOLS = POOLS };
