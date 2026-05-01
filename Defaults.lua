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

local PRIMARY_STAT_KEY_BY_CLASS_FILE = {
    DEATHKNIGHT = "STR",
    DEMONHUNTER = "AGI",
    DRUID = "AGI",
    EVOKER = "INT",
    HUNTER = "AGI",
    MAGE = "INT",
    MONK = "AGI",
    PALADIN = "STR",
    PRIEST = "INT",
    ROGUE = "AGI",
    SHAMAN = "INT",
    WARLOCK = "INT",
    WARRIOR = "STR",
}

local PRIMARY_STAT_KEY_BY_CLASS_AND_SPEC = {
    DEATHKNIGHT = { [1] = "STR", [2] = "STR", [3] = "STR" },
    DEMONHUNTER = { [1] = "AGI", [2] = "AGI", [3] = "INT" },
    DRUID = { [1] = "INT", [2] = "AGI", [3] = "AGI", [4] = "INT" },
    EVOKER = { [1] = "INT", [2] = "INT", [3] = "INT" },
    HUNTER = { [1] = "AGI", [2] = "AGI", [3] = "AGI" },
    MAGE = { [1] = "INT", [2] = "INT", [3] = "INT" },
    MONK = { [1] = "AGI", [2] = "INT", [3] = "AGI" },
    PALADIN = { [1] = "INT", [2] = "STR", [3] = "STR" },
    SHAMAN = { [1] = "INT", [2] = "AGI", [3] = "INT" },
    PRIEST = { [1] = "INT", [2] = "INT", [3] = "INT" },
    ROGUE = { [1] = "AGI", [2] = "AGI", [3] = "AGI" },
    WARLOCK = { [1] = "INT", [2] = "INT", [3] = "INT" },
    WARRIOR = { [1] = "STR", [2] = "STR", [3] = "STR" },
}

local STAT_KEYS = {
    "STR", "AGI", "INT", "HASTE", "CRIT", "VERS", "MASTERY", "AVOIDANCE",
    "PARRY", "DODGE", "BLOCK", "LEECH", "SPEED", "DURA", "ILVL", "GOLD",
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
Addon.Constants.PRIMARY_STAT_KEY_BY_CLASS_FILE = PRIMARY_STAT_KEY_BY_CLASS_FILE
Addon.Constants.PRIMARY_STAT_KEY_BY_CLASS_AND_SPEC = PRIMARY_STAT_KEY_BY_CLASS_AND_SPEC
Addon.Constants.STAT_KEYS = STAT_KEYS
Addon.Constants.TEXT_ALIGN_OPTIONS = TEXT_ALIGN_OPTIONS
Addon.Constants.GOLD_SEPARATOR_OPTIONS = GOLD_SEPARATOR_OPTIONS

Addon.Defaults = Addon.Defaults or {}
Addon.Defaults.profile = defaults
Addon.Defaults.ace = aceDefaults
Addon.DeepCopy = Addon.DeepCopy or DeepCopy
