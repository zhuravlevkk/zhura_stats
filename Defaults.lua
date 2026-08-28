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
    "BLOCK", "LEECH", "SPEED", "DURA", "ILVL", "GOLD", "MOVEMENT_SPEED",
}

local TEXT_ALIGN_OPTIONS = { "LEFT", "CENTER", "RIGHT" }
local GOLD_SEPARATOR_OPTIONS = { " ", ",", ".", "'", "_" }
local FRAME_CONTROLS_POSITION_OPTIONS = { "BOTTOM", "TOP", "LEFT", "RIGHT" }
local FRAME_CONTROLS_DIRECTION_OPTIONS = { "HORIZONTAL", "VERTICAL" }

local defaults = {
    useSpecProfiles = false,
    scale = 1,
    alpha = 1,
    fontSize = 18,
    fontKey = "Friz Quadrata TT",
    columnCount = 1,
    rowsPerColumn = 0,
    rowGap = 2,
    columnGap = 20,
    valueColumnWidth = 0,
    compactValueColumns = false,
    showPercent = true,
    percentPrecision = 2,
    drDisplayMode = "off",
    showLabels = true,
    showValues = true,
    useClassColor = false,
    showStatIcons = false,
    textAlign = "LEFT",
    goldUseSeparator = true,
    goldSeparator = " ",
    locked = false,
    showFrameControls = true,
    showLockOnHover = false,
    frameControlsPosition = "BOTTOM",
    frameControlsDirection = "HORIZONTAL",
    preferCurrentSpecMainStat = false,
    statPriorityMode = "manual",
    referenceDisplay = "inline",
    showReferenceRanges = true,
    showReferenceSource = true,
    showDiminishingReturnHint = true,
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
    char = {
        -- Per-character stat snapshots, keyed by spec. Lets the addon show the
        -- last trustworthy reading (clearly marked stale) while live values are
        -- Secret in combat / Mythic+ / encounters / PvP, and survives /reload.
        statSnapshot = {},
    },
}

Addon.Constants = Addon.Constants or {}
Addon.Constants.PRIMARY_STAT_KEY_BY_ID = PRIMARY_STAT_KEY_BY_ID
Addon.Constants.STAT_KEYS = STAT_KEYS
Addon.Constants.TEXT_ALIGN_OPTIONS = TEXT_ALIGN_OPTIONS
Addon.Constants.GOLD_SEPARATOR_OPTIONS = GOLD_SEPARATOR_OPTIONS
Addon.Constants.FRAME_CONTROLS_POSITION_OPTIONS = FRAME_CONTROLS_POSITION_OPTIONS
Addon.Constants.FRAME_CONTROLS_DIRECTION_OPTIONS = FRAME_CONTROLS_DIRECTION_OPTIONS

Addon.Defaults = Addon.Defaults or {}
Addon.Defaults.profile = defaults
Addon.Defaults.ace = aceDefaults
Addon.DeepCopy = Addon.DeepCopy or DeepCopy
