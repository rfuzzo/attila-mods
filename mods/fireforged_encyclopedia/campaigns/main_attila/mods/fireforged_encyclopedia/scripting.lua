-- Fireforged encyclopedia: loaded by TWASE's mod loader after the campaign's scripting.lua.
-- Run init again on every campaign load, also when the Lua state kept the module from an earlier one.
package.loaded["fireforged_encyclopedia/init"] = nil;
require("fireforged_encyclopedia/init");
