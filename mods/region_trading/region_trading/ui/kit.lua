-- Small UI toolkit: components cut out of vanilla layouts, click handlers, timers.
-- UI component methods: see docs/research/uicomponent_methods.txt.

local rt = require("region_trading/core");

local kit = {};

local garbage = nil;
local next_id = 0;

function kit.root()
	return rt.cm():ui_root();
end;

-- find(parent, {"a", "b"}) -> UIComponent or nil
function kit.find(parent, path)
	local found = find_uicomponent_by_table(parent or kit.root(), path);
	return found or nil;
end;

local function unique(prefix)
	next_id = next_id + 1;
	return prefix .. "_rt" .. next_id;
end;

-- Delete a component (components can only be destroyed as children, so it's adopted by a dummy first).
function kit.delete(uic)
	if not uic then return end;
	if not garbage then
		kit.root():CreateComponent("RegionTradingGarbage", "UI/campaign ui/script_dummy");
		garbage = UIComponent(kit.root():Find("RegionTradingGarbage"));
	end;
	garbage:Adopt(uic:Address());
	garbage:DestroyChildren();
end;

-- Instantiate `layout`, take the component at `path` out of it, give it to `parent`, delete the rest.
-- -> UIComponent or nil (logged) if the layout or the path doesn't exist.
function kit.from_layout(layout, path, parent)
	local name = unique("temp");
	local ok, err = pcall(function() kit.root():CreateComponent(name, layout) end);
	local temp = ok and kit.root():Find(name);
	if not temp then
		rt.log("ui: can't create layout %s (%s)", layout, tostring(err));
		return nil;
	end;
	temp = UIComponent(temp);
	local part = #path > 0 and kit.find(temp, path) or temp;
	if not part then
		rt.log("ui: layout %s has no %s", layout, table.concat(path, "/"));
		kit.delete(temp);
		return nil;
	end;
	parent:Adopt(part:Address());
	if #path > 0 then kit.delete(temp) end;
	return part;
end;

-- Coloured text markup, as the game's own strings use it.
function kit.colour(text, rgb)
	return "[[rgba:" .. rgb .. "]]" .. text .. "[[/rgba:" .. rgb .. "]]";
end;

kit.BROWN, kit.GREEN, kit.RED, kit.GREY, kit.YELLOW = "87:47:37", "50:110:40", "150:30:20", "120:110:100", "180:140:30";

-- CLICKS: handlers by component address (our components) or by id (vanilla ones)

local by_address, by_id = {}, {};

function kit.on_click(uic, handler)
	by_address[tostring(uic:Address())] = handler;
end;

function kit.forget(uic)
	by_address[tostring(uic:Address())] = nil;
end;

-- handler(uic, id) for every vanilla component with this id (or id prefix ending in "*")
function kit.on_click_id(id, handler)
	by_id[id] = handler;
end;

rt.cm():add_listener("RegionTrading_Click", "ComponentLClickUp", true, function(context)
	local handler = by_address[tostring(context.component)];
	local uic = UIComponent(context.component);
	local id = context.string;
	if not handler then
		handler = by_id[id];
		if not handler then
			for pattern, h in pairs(by_id) do
				if string.sub(pattern, -1) == "*" and string.sub(id, 1, #pattern - 1) == string.sub(pattern, 1, -2) then
					handler = h;
					break;
				end;
			end;
		end;
	end;
	if handler then
		local ok, err = pcall(handler, uic, id);
		if not ok then rt.log("ui: click handler for %s failed: %s", id, tostring(err)) end;
	end;
end, true);

-- TIMERS: kit.after(seconds, fn), kit.next_tick(fn)

local timers = {};

function kit.after(seconds, fn)
	local id = unique("RegionTradingTimer");
	timers[id] = fn;
	rt.cm():add_time_trigger(id, seconds);
end;

function kit.next_tick(fn)
	kit.after(0, fn);
end;

rt.cm():add_listener("RegionTrading_Timer", "TimeTrigger", true, function(context)
	local fn = timers[context.string];
	if fn then
		timers[context.string] = nil;
		local ok, err = pcall(fn);
		if not ok then rt.log("ui: timer failed: %s", tostring(err)) end;
	end;
end, true);

return kit;
