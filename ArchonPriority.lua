local _, ns = ...

ns = ns or {}
ns.ZhuraStats = ns.ZhuraStats or {}
local Addon = ns.ZhuraStats

local VALID_PRIORITY_MODES = {
    manual = true,
    archon_raid = true,
    archon_mplus = true,
}

local CLASS_SLUGS = {
    DEATHKNIGHT = "death-knight",
    DEMONHUNTER = "demon-hunter",
    DRUID = "druid",
    EVOKER = "evoker",
    HUNTER = "hunter",
    MAGE = "mage",
    MONK = "monk",
    PALADIN = "paladin",
    PRIEST = "priest",
    ROGUE = "rogue",
    SHAMAN = "shaman",
    WARLOCK = "warlock",
    WARRIOR = "warrior",
}

local SPEC_SLUGS_BY_ID = {
    [62] = "arcane",
    [63] = "fire",
    [64] = "frost",
    [65] = "holy",
    [66] = "protection",
    [70] = "retribution",
    [71] = "arms",
    [72] = "fury",
    [73] = "protection",
    [102] = "balance",
    [103] = "feral",
    [104] = "guardian",
    [105] = "restoration",
    [1467] = "devastation",
    [1468] = "preservation",
    [1473] = "augmentation",
    [250] = "blood",
    [251] = "frost",
    [252] = "unholy",
    [253] = "beast-mastery",
    [254] = "marksmanship",
    [255] = "survival",
    [256] = "discipline",
    [257] = "holy",
    [258] = "shadow",
    [259] = "assassination",
    [260] = "outlaw",
    [261] = "subtlety",
    [262] = "elemental",
    [263] = "enhancement",
    [264] = "restoration",
    [265] = "affliction",
    [266] = "demonology",
    [267] = "destruction",
    [268] = "brewmaster",
    [269] = "windwalker",
    [270] = "mistweaver",
    [577] = "havoc",
    [581] = "vengeance",
}

local STAT_NAME_TO_KEY = {
    crit = "CRIT",
    haste = "HASTE",
    mastery = "MASTERY",
    versatility = "VERS",
    vers = "VERS",
}

local ALLOWED_ARCHON_STATS = {
    CRIT = true,
    HASTE = true,
    MASTERY = true,
    VERS = true,
}

function Addon:NormalizeStatPriorityMode(mode)
    if VALID_PRIORITY_MODES[mode] then
        return mode
    end
    return "manual"
end

function Addon:SetStatPriorityMode(mode)
    local normalizedMode = self:NormalizeStatPriorityMode(mode)
    local currentMode = self:NormalizeStatPriorityMode(self:GetProfileValue("statPriorityMode") or "manual")
    if currentMode ~= normalizedMode then
        self:SetProfileValue("statPriorityMode", normalizedMode)
    end

    if self.RefreshPriorityModeButtons then
        self:RefreshPriorityModeButtons()
    end

    self:RefreshStats()
    if self.RefreshOptions then
        self:RefreshOptions()
    elseif self.RefreshOptionRows then
        self:RefreshOptionRows()
    end
end

function Addon:GetPlayerClassSpec()
    if type(UnitClass) ~= "function" then
        return nil
    end

    local _, classFile = UnitClass("player")
    if type(classFile) ~= "string" then
        return nil
    end

    local classSlug = CLASS_SLUGS[classFile]
    if not classSlug then
        return nil
    end

    if type(GetSpecialization) ~= "function" or type(GetSpecializationInfo) ~= "function" then
        return nil
    end

    local specIndex = GetSpecialization()
    if type(specIndex) ~= "number" then
        return nil
    end

    local specID = GetSpecializationInfo(specIndex)
    if type(specID) ~= "number" then
        return nil
    end

    local specSlug = SPEC_SLUGS_BY_ID[specID]
    if not specSlug then
        return nil
    end

    return classSlug, specSlug, specID, classFile
end

function Addon:GetArchonKey(activity)
    if type(activity) ~= "string" or activity == "" then
        return nil
    end

    local classSlug, specSlug = self:GetPlayerClassSpec()
    if not classSlug or not specSlug then
        return nil
    end

    return classSlug .. "/" .. specSlug .. "/" .. activity
end

function Addon:GetArchonDataForMode(mode)
    mode = self:NormalizeStatPriorityMode(mode)
    local activity
    if mode == "archon_mplus" then
        activity = "m+"
    elseif mode == "archon_raid" then
        activity = "raid"
    else
        return nil
    end

    local key = self:GetArchonKey(activity)
    if not key then
        return nil
    end

    local data = WoWLogsStatsPrio and WoWLogsStatsPrio[key]
    if not data then
        return nil, key, activity
    end

    return data, key, activity
end

function Addon:GetArchonTopHeroForMode(mode)
    local data = self:GetArchonDataForMode(mode)
    if type(data) ~= "table" or type(data.heroes) ~= "table" then
        return nil
    end

    -- Current Archon data contains hero popularity but not hero-specific stat priorities. Heroes are informational only for now.
    local heroes = {}
    for _, hero in ipairs(data.heroes) do
        if type(hero) == "table" and type(hero.hero) == "string" then
            table.insert(heroes, {
                hero = hero.hero,
                rank = tonumber(hero.rank) or math.huge,
                usage_pct = tonumber(hero.usage_pct) or 0,
            })
        end
    end

    if #heroes == 0 then
        return nil
    end

    table.sort(heroes, function(a, b)
        if a.rank ~= b.rank then
            return a.rank < b.rank
        end
        return a.usage_pct > b.usage_pct
    end)

    return heroes[1]
end

function Addon:GetArchonPriorityForMode(mode)
    local data = self:GetArchonDataForMode(mode)
    if type(data) ~= "table" or type(data.secondary) ~= "table" then
        return nil
    end

    local secondary = {}
    for _, entry in ipairs(data.secondary) do
        if type(entry) == "table" then
            table.insert(secondary, {
                stat = string.lower(tostring(entry.stat or "")),
                order = tonumber(entry.order) or math.huge,
                rating = tonumber(entry.rating) or 0,
            })
        end
    end

    if #secondary == 0 then
        return nil
    end

    table.sort(secondary, function(a, b)
        if a.order ~= b.order then
            return a.order < b.order
        end
        return a.rating > b.rating
    end)

    local result = {}
    local seen = {}
    for _, entry in ipairs(secondary) do
        local statKey = STAT_NAME_TO_KEY[entry.stat]
        if statKey and ALLOWED_ARCHON_STATS[statKey] and not seen[statKey] then
            seen[statKey] = true
            table.insert(result, statKey)
        end
    end

    if #result == 0 then
        return nil
    end

    return result
end

function Addon:GetDisplayStats()
    local profile = self:GetProfile()
    if type(profile) ~= "table" or type(profile.stats) ~= "table" then
        return {}
    end

    local mode = self:NormalizeStatPriorityMode(profile.statPriorityMode or "manual")
    if mode == "manual" then
        return profile.stats
    end

    local priority = self:GetArchonPriorityForMode(mode)
    if type(priority) ~= "table" or #priority == 0 then
        return profile.stats
    end

    local byKey = {}
    for _, entry in ipairs(profile.stats) do
        if type(entry) == "table" and type(entry.key) == "string" and not byKey[entry.key] then
            byKey[entry.key] = entry
        end
    end

    local result = {}
    local added = {}
    for _, statKey in ipairs(priority) do
        local entry = byKey[statKey]
        if entry and not added[entry] then
            table.insert(result, entry)
            added[entry] = true
        end
    end

    for _, entry in ipairs(profile.stats) do
        if not added[entry] then
            table.insert(result, entry)
        end
    end

    return result
end
