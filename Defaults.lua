local _, ns = ...

ns = ns or {}
ns.ZhuraStats = ns.ZhuraStats or {}
local Addon = ns.ZhuraStats

local function DeepCopy(source)
    if type(source) ~= "table" then
        return source
    end

    local copy = {}
    for key, value in pairs(source) do
        copy[key] = DeepCopy(value)
    end
    return copy
end

local PRIMARY_STAT_KEY_BY_ID = {
    [1] = "STR",
    [2] = "AGI",
    [4] = "INT",
}

local STAT_KEYS = {
    "STR", "AGI", "INT", "HASTE", "CRIT", "VERS", "MASTERY",
    "BLOCK", "LEECH", "SPEED", "DURA", "ILVL", "GOLD",
}

local TEXT_ALIGN_OPTIONS = { "LEFT", "CENTER", "RIGHT" }
local GOLD_SEPARATOR_OPTIONS = { " ", ",", ".", "'", "_" }

local defaults = {
    useSpecProfiles = false,
    scale = 1,
    alpha = 1,
    fontSize = 18,
    fontKey = "Friz Quadrata TT",
    columnCount = 1,
    rowsPerColumn = 0,
    showPercent = true,
    percentPrecision = 2,
    drDisplayMode = "off",
    showLabels = true,
    showValues = true,
    textAlign = "LEFT",
    goldUseSeparator = true,
    goldSeparator = " ",
    locked = false,
    showLockOnHover = false,
    preferCurrentSpecMainStat = false,
    statPriorityMode = "manual",
    primaryStatInitialized = false,
    point = "TOPLEFT",
    relativeTo = "UIParent",
    relativePoint = "TOPLEFT",
    x = 300,
    y = -240,
    width = 1,
    height = 1,
    stats = nil,
}

local aceDefaults = {
    profile = defaults,
    global = {
        addonLocale = "client",
    },
}

Addon.Constants = Addon.Constants or {}
Addon.Constants.PRIMARY_STAT_KEY_BY_ID = PRIMARY_STAT_KEY_BY_ID
Addon.Constants.STAT_KEYS = STAT_KEYS
Addon.Constants.TEXT_ALIGN_OPTIONS = TEXT_ALIGN_OPTIONS
Addon.Constants.GOLD_SEPARATOR_OPTIONS = GOLD_SEPARATOR_OPTIONS

Addon.Defaults = Addon.Defaults or {}
Addon.Defaults.profile = defaults
Addon.Defaults.ace = aceDefaults
Addon.DeepCopy = Addon.DeepCopy or DeepCopy
