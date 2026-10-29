-- Points the game's encyclopedia links (unit cards, buildings, ...) at the Fireforged Empire encyclopedia, a static
-- site built from Fireforged's data by tools/encyclopedia/build.py and published from the attila-mods repo.
-- The game appends its entry path (/unit/<main unit key>, /building/..., ...) to the prefix; with "#" the site
-- routes on the URL fragment. Needs TWASE's campaign UI hook (twase.set_encyclopedia_url).
--
-- The URL is one setting for the whole game process: it stays when another campaign or save is loaded. So it is set
-- only when Fireforged's campaign scripts are loaded, and put back to the game's own encyclopedia when a campaign
-- without them loads after one with them.

local URL = "https://rfuzzo.github.io/attila-mods/#";

local function log(fmt, ...)
	print("[fireforged_encyclopedia] " .. string.format(fmt, ...));
end;

if type(twase) ~= "table" or type(twase.set_encyclopedia_url) ~= "function" then
	log("this TWASE has no twase.set_encyclopedia_url, the game's encyclopedia stays");
	return;
end;

-- Great_Invasion is Fireforged's (antonina_incident.lua); campaign globals are visible to TWASE's mods
local fireforged = type(Great_Invasion) == "function";

if not fireforged then
	local ok, current = pcall(twase.get_encyclopedia_url);
	if ok and current == URL then
		pcall(twase.set_encyclopedia_url, nil);
		log("no Fireforged in this campaign, encyclopedia links back to the game's own");
	end;
	return;
end;

local ok, result = pcall(twase.set_encyclopedia_url, URL);
if ok then
	log("encyclopedia links open %s", tostring(result));
else
	log("encyclopedia URL not changed: %s", tostring(result));
end;
