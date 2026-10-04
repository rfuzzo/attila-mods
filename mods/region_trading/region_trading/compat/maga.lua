-- Switch off the `maga` region trading that Fireforged Empire and Region Trading Reloaded load from
-- their scripting.lua. Our mod is loaded after it, so all of maga's listeners already exist; they are
-- all named "MAGA_EventHandler_*". Without its listeners maga never builds its UI or trades anything.
-- Its save / load callbacks stay, they only store maga's own counters.

local rt = require("region_trading/core");

local PREFIX = "MAGA_EventHandler_";

local function disable()
	local eh = rt.cm().eh;
	if not eh or type(eh.listeners) ~= "table" then
		rt.log("maga: no event handler found, nothing to switch off");
		return 0;
	end;

	local names = {};
	for _, listener in ipairs(eh.listeners) do
		local name = listener.name;
		if type(name) == "string" and string.sub(name, 1, #PREFIX) == PREFIX then
			names[name] = true;
		end;
	end;

	local count = 0;
	for name in pairs(names) do
		rt.cm():remove_listener(name);
		count = count + 1;
	end;

	if count > 0 then
		rt.log("maga: removed %d listeners, its region trading is switched off", count);
	else
		rt.log("maga: not loaded");
	end;
	return count;
end;

return { disable = disable };
