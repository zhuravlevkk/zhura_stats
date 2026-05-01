local _, ns = ...

ns = ns or {}
ns.ZhuraStats = ns.ZhuraStats or {}
local Addon = ns.ZhuraStats

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
local FALLBACK_FONTS = {
    "Friz Quadrata TT",
    "Arial Narrow",
    "Morpheus",
    "Skurri",
}

function Addon:GetAvailableFonts()
    local available = {}
    local seen = {}

    if LSM and LSM.HashTable then
        local fonts = LSM:HashTable("font")
        for name in pairs(fonts) do
            table.insert(available, { key = name, label = name })
            seen[name] = true
        end
    end

    for _, name in ipairs(FALLBACK_FONTS) do
        if not seen[name] then
            table.insert(available, { key = name, label = name })
        end
    end

    table.sort(available, function(a, b)
        return a.label < b.label
    end)

    return available
end

function Addon:GetFontInfo(fontKey)
    if LSM and LSM.Fetch and fontKey then
        local fetched = LSM:Fetch("font", fontKey, true)
        if fetched then
            return fetched, "OUTLINE"
        end
    end

    return STANDARD_TEXT_FONT, "OUTLINE"
end

Addon.Constants = Addon.Constants or {}
Addon.Constants.FALLBACK_FONTS = FALLBACK_FONTS
