local ADDON_NAME, ns = ...
ns = ns or {}
ns.ZhuraStats = ns.ZhuraStats or {}

local Addon = ns.ZhuraStats
Addon.name = ADDON_NAME

if Addon.Initialize then
    Addon:Initialize()
end
