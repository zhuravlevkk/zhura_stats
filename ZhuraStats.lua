local ADDON_NAME = ...
NE_STATS_LOCALES = NE_STATS_LOCALES or {}

local FALLBACK_LOCALE = "enUS"
local CLIENT_LOCALE = GetLocale() or FALLBACK_LOCALE
local CLIENT_LANGUAGE_VALUE = "client"
local LOCALE_DISPLAY_NAMES = {
    deDE = "Deutsch",
    enUS = "English (US)",
    esES = "Espanol (EU)",
    esMX = "Espanol (LATAM)",
    frFR = "Francais",
    itIT = "Italiano",
    koKR = "한국어",
    ptBR = "Portugues (BR)",
    ruRU = "Русский",
    ukUA = "Українська",
    zhCN = "简体中文",
    zhTW = "繁體中文",
}
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
    DEATHKNIGHT = {
        [1] = "STR", -- Blood
        [2] = "STR", -- Frost
        [3] = "STR", -- Unholy
    },
    DEMONHUNTER = {
        [1] = "AGI", -- Havoc
        [2] = "AGI", -- Vengeance
        [3] = "INT", -- Devourer
    },
    DRUID = {
        [1] = "INT", -- Balance
        [2] = "AGI", -- Feral
        [3] = "AGI", -- Guardian
        [4] = "INT", -- Restoration
    },
    EVOKER = {
        [1] = "INT", -- Devastation
        [2] = "INT", -- Preservation
        [3] = "INT", -- Augmentation
    },
    HUNTER = {
        [1] = "AGI", -- Beast Mastery
        [2] = "AGI", -- Marksmanship
        [3] = "AGI", -- Survival
    },
    MAGE = {
        [1] = "INT", -- Arcane
        [2] = "INT", -- Fire
        [3] = "INT", -- Frost
    },
    MONK = {
        [1] = "AGI", -- Brewmaster
        [2] = "INT", -- Mistweaver
        [3] = "AGI", -- Windwalker
    },
    PALADIN = {
        [1] = "INT", -- Holy
        [2] = "STR", -- Protection
        [3] = "STR", -- Retribution
    },
    SHAMAN = {
        [1] = "INT", -- Elemental
        [2] = "AGI", -- Enhancement
        [3] = "INT", -- Restoration
    },
    PRIEST = {
        [1] = "INT", -- Discipline
        [2] = "INT", -- Holy
        [3] = "INT", -- Shadow
    },
    ROGUE = {
        [1] = "AGI", -- Assassination
        [2] = "AGI", -- Outlaw
        [3] = "AGI", -- Subtlety
    },
    WARLOCK = {
        [1] = "INT", -- Affliction
        [2] = "INT", -- Demonology
        [3] = "INT", -- Destruction
    },
    WARRIOR = {
        [1] = "STR", -- Arms
        [2] = "STR", -- Fury
        [3] = "STR", -- Protection
    },
}
local L = {}

local db

local function CopyLocaleEntries(source, target)
    if type(source) ~= "table" then
        return
    end

    for key, value in pairs(source) do
        target[key] = value
    end
end

local function GetConfiguredLocale()
    if db and db.global and type(db.global.addonLocale) == "string" and db.global.addonLocale ~= "" then
        return db.global.addonLocale
    end

    return CLIENT_LANGUAGE_VALUE
end

local function GetEffectiveLocale()
    local configuredLocale = GetConfiguredLocale()
    local localeCode = configuredLocale == CLIENT_LANGUAGE_VALUE and CLIENT_LOCALE or configuredLocale

    if not NE_STATS_LOCALES[localeCode] then
        localeCode = FALLBACK_LOCALE
    end

    return localeCode
end

local function ApplyLocale()
    wipe(L)
    CopyLocaleEntries(NE_STATS_LOCALES[FALLBACK_LOCALE], L)

    local effectiveLocale = GetEffectiveLocale()
    if effectiveLocale ~= FALLBACK_LOCALE then
        CopyLocaleEntries(NE_STATS_LOCALES[effectiveLocale], L)
    end
end

local function S(key, ...)
    local text = L[key] or key
    if select("#", ...) > 0 then
        return string.format(text, ...)
    end
    return text
end

local function GetLocaleDisplayName(localeCode)
    if localeCode == CLIENT_LANGUAGE_VALUE then
        return string.format("%s (%s)", S("Client language"), LOCALE_DISPLAY_NAMES[CLIENT_LOCALE] or CLIENT_LOCALE)
    end

    return LOCALE_DISPLAY_NAMES[localeCode] or localeCode
end

ApplyLocale()

local function GetDisplayProfileName(profileName)
    if profileName == "Default" then
        return S("Default")
    end
    return profileName
end

local function SetProfileDropDownSelection(dropDown, profileName)
    if not dropDown or not profileName then
        return
    end

    local displayName = GetDisplayProfileName(profileName)
    UIDropDownMenu_SetText(dropDown, displayName)
    UIDropDownMenu_SetSelectedName(dropDown, displayName)
    UIDropDownMenu_SetSelectedValue(dropDown, profileName)
end

ZhuraStatsDB = ZhuraStatsDB or {}

local addon = CreateFrame("Frame")
addon:RegisterEvent("ADDON_LOADED")
addon:RegisterEvent("PLAYER_LOGIN")
addon:RegisterEvent("PLAYER_ENTERING_WORLD")
addon:RegisterEvent("COMBAT_RATING_UPDATE")
addon:RegisterEvent("UNIT_STATS")
addon:RegisterEvent("UNIT_INVENTORY_CHANGED")
addon:RegisterEvent("UNIT_AURA")
addon:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
addon:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
addon:RegisterEvent("TRAIT_CONFIG_UPDATED")
addon:RegisterEvent("PLAYER_REGEN_ENABLED")

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
local AceDB = LibStub and LibStub("AceDB-3.0", true)
local FALLBACK_FONTS = {
    "Friz Quadrata TT",
    "Arial Narrow",
    "Morpheus",
    "Skurri",
}

local STAT_KEYS = {
    "STR",
    "AGI",
    "INT",
    "HASTE",
    "CRIT",
    "VERS",
    "MASTERY",
    "AVOIDANCE",
    "PARRY",
    "DODGE",
    "BLOCK",
    "LEECH",
    "SPEED",
}

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
    showLabels = true,
    showValues = true,
    locked = false,
    showLockOnHover = false,
    preferCurrentSpecMainStat = false,
    point = "TOPLEFT",
    relativePoint = "TOPLEFT",
    x = 300,
    y = -240,
    width = 1,
    height = 1,
    stats = nil,
}

local statDefinitions = {
    STR = {
        label = "Strength",
        color = { 0.95, 0.12, 0.12 },
        suffix = "",
        value = function()
            return select(2, UnitStat("player", 1))
        end,
    },
    AGI = {
        label = "Agility",
        color = { 0.10, 1.00, 0.10 },
        suffix = "",
        value = function()
            return select(2, UnitStat("player", 2))
        end,
    },
    INT = {
        label = "Intellect",
        color = { 0.10, 0.45, 1.00 },
        suffix = "",
        value = function()
            return select(2, UnitStat("player", 4))
        end,
    },
    HASTE = {
        label = "Haste",
        color = { 0.45, 1.00, 0.82 },
        suffix = "%",
        rating = function()
            return GetCombatRating and (GetCombatRating(CR_HASTE_MELEE) or 0) or 0
        end,
        value = function()
            return GetHaste()
        end,
    },
    CRIT = {
        label = "Crit",
        color = { 1.00, 0.15, 0.15 },
        suffix = "%",
        rating = function()
            return GetCombatRating and (GetCombatRating(CR_CRIT_MELEE) or 0) or 0
        end,
        value = function()
            return GetCritChance()
        end,
    },
    VERS = {
        label = "Vers",
        color = { 0.42, 0.56, 0.74 },
        suffix = "%",
        rating = function()
            return GetCombatRating and (GetCombatRating(CR_VERSATILITY_DAMAGE_DONE) or 0) or 0
        end,
        value = function()
            local ratingBonus = (GetCombatRatingBonus and GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE)) or 0
            local baseBonus = (GetVersatilityBonus and GetVersatilityBonus(CR_VERSATILITY_DAMAGE_DONE)) or 0
            return ratingBonus + baseBonus
        end,
    },
    MASTERY = {
        label = "Mastery",
        color = { 0.68, 0.20, 1.00 },
        suffix = "%",
        rating = function()
            return GetCombatRating and (GetCombatRating(CR_MASTERY) or 0) or 0
        end,
        value = function()
            return GetMasteryEffect()
        end,
    },
    AVOIDANCE = {
        label = "Avoidance",
        color = { 1.00, 0.72, 0.20 },
        suffix = "%",
        rating = function()
            return GetCombatRating and (GetCombatRating(CR_AVOIDANCE) or 0) or 0
        end,
        value = function()
            return GetAvoidance and (GetAvoidance() or 0) or 0
        end,
    },
    PARRY = {
        label = "Parry",
        color = { 0.94, 0.64, 0.24 },
        suffix = "%",
        rating = function()
            return GetCombatRating and (GetCombatRating(CR_PARRY) or 0) or 0
        end,
        value = function()
            return GetParryChance and (GetParryChance() or 0) or 0
        end,
    },
    DODGE = {
        label = "Dodge",
        color = { 0.95, 0.80, 0.26 },
        suffix = "%",
        rating = function()
            return GetCombatRating and (GetCombatRating(CR_DODGE) or 0) or 0
        end,
        value = function()
            return GetDodgeChance and (GetDodgeChance() or 0) or 0
        end,
    },
    BLOCK = {
        label = "Block",
        color = { 0.87, 0.73, 0.42 },
        suffix = "%",
        rating = function()
            return GetCombatRating and (GetCombatRating(CR_BLOCK) or 0) or 0
        end,
        value = function()
            return GetBlockChance and (GetBlockChance() or 0) or 0
        end,
    },
    LEECH = {
        label = "Leech",
        color = { 0.10, 1.00, 0.55 },
        suffix = "%",
        rating = function()
            return GetCombatRating and (GetCombatRating(CR_LIFESTEAL) or 0) or 0
        end,
        value = function()
            return GetLifesteal and (GetLifesteal() or 0) or 0
        end,
    },
    SPEED = {
        label = "Speed",
        color = { 1.00, 0.85, 0.30 },
        suffix = "%",
        rating = function()
            return GetCombatRating and (GetCombatRating(CR_SPEED) or 0) or 0
        end,
        value = function()
            return GetSpeed and (GetSpeed() or 0) or 0
        end,
    },
}

local initialized = false
local optionsPanel
local optionsCategory
local optionsCategoryID
local optionsPanelBuilt = false
local lastOptionsPanelError
local statsFrame
local statsAnchor
local lockButton
local isStatsFrameHovered = false
local isLockButtonHovered = false
local rowControls = {}
local controlRefs = {}
local lines = {}
local defaultStatsByKey = {}
local MIN_DYNAMIC_FONT_SIZE = 8
local measureLine
local pendingOptionRowsAfterCombat = false
local lastRefreshErrorAt = 0
local lastRefreshErrorMessage = ""
local BuildOptionsPanel
local SelectRootProfile
local InitializeProfileDropDown
local InitializeLanguageDropDown
local ApplyCurrentProfileState
local RefreshStats
local RefreshOptionRows
local RefreshLocalizedUI
local RefreshStaticPopupTexts
local pendingRenameProfileName

local function GetAvailableFonts()
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

defaults.stats = {
    { key = "STR", enabled = true, color = DeepCopy(statDefinitions.STR.color) },
    { key = "AGI", enabled = true, color = DeepCopy(statDefinitions.AGI.color) },
    { key = "INT", enabled = true, color = DeepCopy(statDefinitions.INT.color) },
    { key = "HASTE", enabled = true, color = DeepCopy(statDefinitions.HASTE.color) },
    { key = "CRIT", enabled = true, color = DeepCopy(statDefinitions.CRIT.color) },
    { key = "VERS", enabled = true, color = DeepCopy(statDefinitions.VERS.color) },
    { key = "MASTERY", enabled = true, color = DeepCopy(statDefinitions.MASTERY.color) },
    { key = "AVOIDANCE", enabled = false, color = DeepCopy(statDefinitions.AVOIDANCE.color) },
    { key = "PARRY", enabled = false, color = DeepCopy(statDefinitions.PARRY.color) },
    { key = "DODGE", enabled = false, color = DeepCopy(statDefinitions.DODGE.color) },
    { key = "BLOCK", enabled = false, color = DeepCopy(statDefinitions.BLOCK.color) },
    { key = "LEECH", enabled = false, color = DeepCopy(statDefinitions.LEECH.color) },
    { key = "SPEED", enabled = false, color = DeepCopy(statDefinitions.SPEED.color) },
}

for _, entry in ipairs(defaults.stats) do
    defaultStatsByKey[entry.key] = entry
end

local aceDefaults = {
    profile = defaults,
    global = {
        addonLocale = CLIENT_LANGUAGE_VALUE,
    },
}

local function GetFontInfo(fontKey)
    if LSM and LSM.Fetch and fontKey then
        local fetched = LSM:Fetch("font", fontKey, true)
        if fetched then
            return fetched, "OUTLINE"
        end
    end

    return STANDARD_TEXT_FONT, "OUTLINE"
end

local MigrateProfile

local function EnsureDatabase()
    if not AceDB then
        return
    end

    if type(ZhuraStatsDB) ~= "table" or not ZhuraStatsDB.profileKeys or ZhuraStatsDB.characters or ZhuraStatsDB.accountProfilesMigrated then
        ZhuraStatsDB = nil
    end

    if not db then
        db = AceDB:New("ZhuraStatsDB", aceDefaults, "Default")
    end

    db.global.addonLocale = db.global.addonLocale or CLIENT_LANGUAGE_VALUE

    ApplyLocale()
    MigrateProfile(db.profile)
end

MigrateProfile = function(profile)
    if not profile.stats then
        profile.stats = DeepCopy(defaults.stats)
    end

    local byKey = {}
    for _, entry in ipairs(profile.stats) do
        if type(entry) == "string" and statDefinitions[entry] then
            byKey[entry] = {
                key = entry,
                enabled = true,
                color = DeepCopy(statDefinitions[entry].color),
            }
        elseif type(entry) == "table" and entry.key and statDefinitions[entry.key] then
            byKey[entry.key] = entry
        end
    end

    local migrated = {}
    local seen = {}

    for _, entry in ipairs(profile.stats) do
        local key = type(entry) == "table" and entry.key or entry
        if key and byKey[key] and not seen[key] then
            local normalized = byKey[key]
            normalized.enabled = normalized.enabled ~= false
            normalized.color = normalized.color or DeepCopy(statDefinitions[key].color)
            table.insert(migrated, normalized)
            seen[key] = true
        end
    end

    for _, key in ipairs(STAT_KEYS) do
        if not seen[key] then
            local entry = byKey[key]
            if entry then
                entry.enabled = entry.enabled ~= false
                entry.color = entry.color or DeepCopy(statDefinitions[key].color)
                table.insert(migrated, entry)
            else
                local defaultEntry = defaultStatsByKey[key]
                table.insert(migrated, {
                    key = key,
                    enabled = defaultEntry and defaultEntry.enabled or false,
                    color = DeepCopy(statDefinitions[key].color),
                })
            end
        end
    end

    profile.stats = migrated
    profile.alpha = profile.alpha or defaults.alpha
    profile.scale = profile.scale or defaults.scale
    profile.fontSize = profile.fontSize or defaults.fontSize
    profile.fontKey = profile.fontKey or defaults.fontKey
    profile.columnCount = math.max(1, math.floor(profile.columnCount or defaults.columnCount))
    profile.rowsPerColumn = math.max(0, math.floor(profile.rowsPerColumn or defaults.rowsPerColumn))
    profile.showPercent = profile.showPercent ~= false
    profile.percentPrecision = profile.percentPrecision
        or profile.decimalPrecision
        or defaults.percentPrecision
    profile.showLabels = profile.showLabels ~= false
    profile.showValues = profile.showValues ~= false
    profile.locked = profile.locked or false
    profile.showLockOnHover = profile.showLockOnHover == true
    profile.preferCurrentSpecMainStat = profile.preferCurrentSpecMainStat == true
    profile.specProfiles = profile.specProfiles or {}
    profile.point = profile.point or defaults.point
    profile.relativePoint = profile.relativePoint or defaults.relativePoint
    profile.x = profile.x or defaults.x
    profile.y = profile.y or defaults.y
    profile.width = profile.width or defaults.width
    profile.height = profile.height or defaults.height
    profile.useSpecProfiles = false
    profile.useLoadoutProfiles = nil
end

local function GetActiveRootProfile()
    if not db then
        return defaults, "Default"
    end

    local profileName = db:GetCurrentProfile() or "Default"
    MigrateProfile(db.profile)
    return db.profile, profileName
end

local function GetProfileNames()
    local names = {}
    if not db then
        return { "Default" }
    end

    db:GetProfiles(names)
    table.sort(names)
    return names
end

local function NormalizeProfileName(profileName)
    if not profileName then
        return ""
    end

    local normalized = strtrim(profileName)
    normalized = normalized:gsub("%s+", " ")
    return normalized
end

local function CanModifyProfile(profileName)
    return profileName and profileName ~= "" and profileName ~= "Default"
end

local function CreateProfile(profileName)
    profileName = NormalizeProfileName(profileName)
    if not db or profileName == "" then
        return "invalid", nil
    end

    for _, existingName in ipairs(GetProfileNames()) do
        if existingName == profileName then
            SelectRootProfile(profileName)
            return "exists", profileName
        end
    end

    local sourceProfileName = db:GetCurrentProfile()
    local ok = pcall(function()
        db:SetProfile(profileName)
        if sourceProfileName and sourceProfileName ~= profileName then
            db:CopyProfile(sourceProfileName, true)
        end
        MigrateProfile(db.profile)
    end)

    if not ok then
        print(S("NE Stats: profile could not be created."))
        return "invalid", nil
    end

    ApplyCurrentProfileState()
    return "created", profileName
end

local function RenameProfile(oldName, newName)
    oldName = NormalizeProfileName(oldName)
    newName = NormalizeProfileName(newName)

    if not db or not CanModifyProfile(oldName) or newName == "" then
        return "invalid", nil
    end

    if oldName == newName then
        SelectRootProfile(oldName)
        return "exists", oldName
    end

    for _, existingName in ipairs(GetProfileNames()) do
        if existingName == newName then
            return "exists", existingName
        end
    end

    local ok, err = xpcall(function()
        local profiles = (db.sv and db.sv.profiles) or db.profiles
        local source = profiles and profiles[oldName]
        if type(source) ~= "table" then
            error("missing source profile")
        end

        profiles[newName] = DeepCopy(source)

        if db.sv and db.sv.profileKeys then
            for key, profileName in pairs(db.sv.profileKeys) do
                if profileName == oldName then
                    db.sv.profileKeys[key] = newName
                end
            end
        end

        profiles[oldName] = nil
        db.profiles = profiles
        db.keys.profile = newName
        db.profile = profiles[newName]
        MigrateProfile(db.profile)
    end, function(message)
        return tostring(message)
    end)

    if not ok then
        return "invalid", err
    end

    ApplyCurrentProfileState()
    return "renamed", newName
end

local function DeleteProfile(profileName)
    profileName = NormalizeProfileName(profileName)
    if not db or not CanModifyProfile(profileName) then
        return false
    end

    local ok = pcall(function()
        db:SetProfile("Default")
        MigrateProfile(db.profile)
        db:DeleteProfile(profileName, true)
    end)

    if not ok then
        return false
    end

    ApplyCurrentProfileState()
    return true
end

SelectRootProfile = function(profileName)
    if not db or not profileName or profileName == "" then
        return
    end

    local ok = pcall(function()
        db:SetProfile(profileName)
        MigrateProfile(db.profile)
    end)

    if not ok then
        print(S("NE Stats: profile could not be applied."))
        return
    end

    ApplyCurrentProfileState()
end

StaticPopupDialogs["NE_STATS_CREATE_PROFILE"] = {
    text = S("Create a new profile for this account"),
    button1 = S("Create"),
    button2 = S("Cancel"),
    hasEditBox = true,
    maxLetters = 24,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = STATICPOPUP_NUMDIALOGS,
    OnAccept = function(self)
        local text = self.editBox and self.editBox:GetText() or ""
        local status, profileName = CreateProfile(text)
        if status == "invalid" then
            return
        end

        if status == "exists" then
            print(S("NE Stats: profile already exists."))
            if controlRefs.profileDropDown and profileName then
                SetProfileDropDownSelection(controlRefs.profileDropDown, profileName)
            end
            return
        end

        print(S("NE Stats: created profile %s.", profileName))
        if controlRefs.profileDropDown and profileName then
            SetProfileDropDownSelection(controlRefs.profileDropDown, profileName)
            UIDropDownMenu_Refresh(controlRefs.profileDropDown)
        end
        CloseDropDownMenus()
        RefreshStats()
        RefreshOptionRows()
        if optionsPanel and optionsPanel:IsShown() and optionsPanel:GetScript("OnShow") then
            optionsPanel:GetScript("OnShow")(optionsPanel)
        end
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        if parent and parent.button1 then
            parent.button1:Click()
        end
    end,
    EditBoxOnTextChanged = function(self)
        local parent = self:GetParent()
        if parent and parent.button1 then
            parent.button1:SetEnabled(NormalizeProfileName(self:GetText()) ~= "")
        end
    end,
    OnShow = function(self)
        if self.editBox then
            self.editBox:SetText("")
            self.editBox:SetFocus()
        end
        if self.button1 then
            self.button1:SetEnabled(false)
        end
    end,
}

StaticPopupDialogs["NE_STATS_RENAME_PROFILE"] = {
    text = S("Rename profile %s"),
    button1 = S("Rename"),
    button2 = S("Cancel"),
    hasEditBox = true,
    maxLetters = 24,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = STATICPOPUP_NUMDIALOGS,
    OnAccept = function(self)
        local _, activeProfileName = GetActiveRootProfile()
        local data = self.data or pendingRenameProfileName or activeProfileName
        local newName = NormalizeProfileName(self.editBox and self.editBox:GetText() or "")
        local status, profileName = RenameProfile(data, newName)
        pendingRenameProfileName = nil
        if status == "exists" then
            print(S("NE Stats: profile already exists."))
            return
        end
        if status == "invalid" then
            print(S("NE Stats: profile could not be renamed: %s", tostring(profileName)))
            return
        end
        if status == "renamed" and profileName then
            if controlRefs.profileDropDown then
                UIDropDownMenu_Refresh(controlRefs.profileDropDown)
                SetProfileDropDownSelection(controlRefs.profileDropDown, profileName)
            end
            print(S("NE Stats: renamed profile to %s.", profileName))
        end
    end,
    OnCancel = function()
        pendingRenameProfileName = nil
    end,
    EditBoxOnEnterPressed = function(self)
        local parent = self:GetParent()
        if parent and parent.button1 then
            parent.button1:Click()
        end
    end,
    EditBoxOnTextChanged = function(self)
        local parent = self:GetParent()
        if parent and parent.button1 then
            parent.button1:SetEnabled(NormalizeProfileName(self:GetText()) ~= "")
        end
    end,
    OnShow = function(self)
        local _, activeProfileName = GetActiveRootProfile()
        local data = self.data or pendingRenameProfileName or activeProfileName
        self.data = data
        if self.editBox then
            self.editBox:SetText(data or "")
            self.editBox:HighlightText()
            self.editBox:SetFocus()
        end
        if self.button1 then
            self.button1:SetEnabled(true)
        end
    end,
}

StaticPopupDialogs["NE_STATS_DELETE_PROFILE"] = {
    text = S("Delete profile %s?"),
    button1 = S("Delete"),
    button2 = S("Cancel"),
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = STATICPOPUP_NUMDIALOGS,
    OnAccept = function(self)
        local data = self.data
        if DeleteProfile(data) then
            print(S("NE Stats: deleted profile %s.", data))
        else
            print(S("NE Stats: profile could not be deleted."))
        end
    end,
}

local function CreateProfileFromInput(editBox)
    if not editBox then
        return
    end

    local status, profileName = CreateProfile(editBox:GetText())
    if status == "invalid" then
        return
    end

    if status == "exists" then
        print(S("NE Stats: profile already exists."))
    else
        print(S("NE Stats: created profile %s.", profileName))
    end

    editBox:SetText("")
    ApplyCurrentProfileState()
end

local function GetActiveProfile()
    return GetActiveRootProfile()
end

ApplyCurrentProfileState = function()
    local profile, activeProfileName = GetActiveRootProfile()

    if controlRefs.profileDropDown then
        if InitializeProfileDropDown then
            UIDropDownMenu_Initialize(controlRefs.profileDropDown, InitializeProfileDropDown)
        end
        controlRefs.profileDropDown:SetValue(activeProfileName)
    end

    if controlRefs.profileInfo then
        controlRefs.profileInfo:SetText(S("Active profile: %s", GetDisplayProfileName(activeProfileName)))
    end
    if controlRefs.profileRenameButton then
        controlRefs.profileRenameButton:SetEnabled(CanModifyProfile(activeProfileName))
    end
    if controlRefs.profileDeleteButton then
        controlRefs.profileDeleteButton:SetEnabled(CanModifyProfile(activeProfileName))
    end
    if controlRefs.languageDropDown then
        UIDropDownMenu_SetSelectedValue(controlRefs.languageDropDown, GetConfiguredLocale())
        UIDropDownMenu_SetText(controlRefs.languageDropDown, GetLocaleDisplayName(GetConfiguredLocale()))
    end

    if controlRefs.showPercentCheckbox then
        controlRefs.showPercentCheckbox:SetChecked(profile.showPercent)
    end
    if controlRefs.precisionSlider then
        controlRefs.precisionSlider:SetValue(profile.percentPrecision or defaults.percentPrecision)
    end
    if controlRefs.showLabelsCheckbox then
        controlRefs.showLabelsCheckbox:SetChecked(profile.showLabels)
    end
    if controlRefs.showValuesCheckbox then
        controlRefs.showValuesCheckbox:SetChecked(profile.showValues)
    end
    if controlRefs.lockCheckbox then
        controlRefs.lockCheckbox:SetChecked(profile.locked)
    end
    if controlRefs.showLockOnHoverCheckbox then
        controlRefs.showLockOnHoverCheckbox:SetChecked(profile.showLockOnHover)
    end
    if controlRefs.preferCurrentSpecMainStatCheckbox then
        controlRefs.preferCurrentSpecMainStatCheckbox:SetChecked(profile.preferCurrentSpecMainStat)
    end
    if controlRefs.alphaSlider then
        controlRefs.alphaSlider:SetValue(profile.alpha or defaults.alpha)
    end
    if controlRefs.scaleSlider then
        controlRefs.scaleSlider:SetValue(profile.scale or defaults.scale)
    end
    if controlRefs.fontSizeSlider then
        controlRefs.fontSizeSlider:SetValue(profile.fontSize or defaults.fontSize)
    end
    if controlRefs.columnCountSlider then
        controlRefs.columnCountSlider:SetValue(profile.columnCount or defaults.columnCount)
    end
    if controlRefs.rowsPerColumnSlider then
        controlRefs.rowsPerColumnSlider:SetValue(profile.rowsPerColumn or defaults.rowsPerColumn)
    end

    if controlRefs.fontDropDown or controlRefs.fontPreview then
        for _, font in ipairs(GetAvailableFonts()) do
            if font.key == profile.fontKey then
                if controlRefs.fontDropDown then
                    UIDropDownMenu_SetSelectedName(controlRefs.fontDropDown, font.label)
                end
                if controlRefs.fontPreview then
                    local path, flags = GetFontInfo(font.key)
                    controlRefs.fontPreview:SetFont(path or STANDARD_TEXT_FONT, 18, flags or "OUTLINE")
                    controlRefs.fontPreview:SetText(font.label .. " - " .. S("The quick brown fox 123"))
                end
                break
            end
        end
    end

    RefreshStats()
    RefreshOptionRows()
end

RefreshLocalizedUI = function()
    RefreshStaticPopupTexts()

    if optionsPanel then
        optionsPanel.name = S("NE Stats")
    end

    if controlRefs.title then
        controlRefs.title:SetText(S("NE Stats"))
    end
    if controlRefs.subtitle then
        controlRefs.subtitle:SetText(S("Profiles are shared across your account.\nYou can create multiple profiles to save different layouts, positions, and display settings."))
    end
    if controlRefs.profileLabel then
        controlRefs.profileLabel:SetText(S("Profile"))
    end
    if controlRefs.profileCreateLabel then
        controlRefs.profileCreateLabel:SetText(S("Create New..."))
    end
    if controlRefs.languageLabel then
        controlRefs.languageLabel:SetText(S("Addon language"))
    end
    if controlRefs.profileCreateButton then
        controlRefs.profileCreateButton:SetText(S("Create"))
    end
    if controlRefs.profileRenameButton then
        controlRefs.profileRenameButton.tooltipText = S("Rename profile")
    end
    if controlRefs.profileDeleteButton then
        controlRefs.profileDeleteButton.tooltipText = S("Delete profile")
    end
    if controlRefs.showPercentCheckbox then
        controlRefs.showPercentCheckbox.label:SetText(S("Show percentages"))
    end
    if controlRefs.showLabelsCheckbox then
        controlRefs.showLabelsCheckbox.label:SetText(S("Show stat names"))
    end
    if controlRefs.showValuesCheckbox then
        controlRefs.showValuesCheckbox.label:SetText(S("Show values"))
    end
    if controlRefs.lockCheckbox then
        controlRefs.lockCheckbox.label:SetText(S("Lock frame"))
    end
    if controlRefs.showLockOnHoverCheckbox then
        controlRefs.showLockOnHoverCheckbox.label:SetText(S("Show lock icon only on hover"))
        controlRefs.showLockOnHoverCheckbox.tooltipText = S("Shows the lock button only while the mouse is over the frame.")
    end
    if controlRefs.preferCurrentSpecMainStatCheckbox then
        controlRefs.preferCurrentSpecMainStatCheckbox.label:SetText(S("Always show current specialization main stat first"))
        controlRefs.preferCurrentSpecMainStatCheckbox.tooltipText = S("Keeps the primary stat for your current specialization at the top of the display.")
    end
    if controlRefs.fontLabel then
        controlRefs.fontLabel:SetText(S("Font"))
    end
    if controlRefs.resetButton then
        controlRefs.resetButton:SetText(S("Reset Position"))
    end
    if controlRefs.statHeader then
        controlRefs.statHeader:SetText(S("Stats"))
    end
    if controlRefs.statHint then
        controlRefs.statHint:SetText(S("Check to show, set color, move with arrows"))
    end
    if controlRefs.precisionSlider then
        _G[controlRefs.precisionSlider:GetName() .. "Text"]:SetText(S("Percent Decimals"))
    end
    if controlRefs.alphaSlider then
        _G[controlRefs.alphaSlider:GetName() .. "Text"]:SetText(S("Background Opacity"))
    end
    if controlRefs.scaleSlider then
        _G[controlRefs.scaleSlider:GetName() .. "Text"]:SetText(S("UI Scale"))
    end
    if controlRefs.fontSizeSlider then
        _G[controlRefs.fontSizeSlider:GetName() .. "Text"]:SetText(S("Font Size"))
    end
    if controlRefs.columnCountSlider then
        _G[controlRefs.columnCountSlider:GetName() .. "Text"]:SetText(S("Columns"))
    end
    if controlRefs.rowsPerColumnSlider then
        _G[controlRefs.rowsPerColumnSlider:GetName() .. "Text"]:SetText(S("Max Rows per Column"))
        _G[controlRefs.rowsPerColumnSlider:GetName() .. "Low"]:SetText(S("Auto"))
    end
    if controlRefs.languageDropDown then
        UIDropDownMenu_Initialize(controlRefs.languageDropDown, InitializeLanguageDropDown)
        UIDropDownMenu_SetSelectedValue(controlRefs.languageDropDown, GetConfiguredLocale())
        UIDropDownMenu_SetText(controlRefs.languageDropDown, GetLocaleDisplayName(GetConfiguredLocale()))
    end

    for _, row in ipairs(rowControls) do
        if row.color then
            row.color:SetText(S("Color"))
        end
    end

    RefreshOptionRows()
end

local function StoreTopLeftPosition(profile, left, top)
    if not profile or not left or not top then
        return
    end

    local parentLeft = UIParent:GetLeft() or 0
    local parentTop = UIParent:GetTop() or 0

    profile.point = "TOPLEFT"
    profile.relativePoint = "TOPLEFT"
    profile.x = left - parentLeft
    profile.y = top - parentTop
end

local function SaveFramePosition()
    if not statsAnchor then
        return
    end

    local profile = GetActiveProfile()
    StoreTopLeftPosition(profile, statsAnchor:GetLeft(), statsAnchor:GetTop())
end

local function GetVisibleStats()
    local profile = GetActiveProfile()
    local visible = {}
    local mainStatKey
    local mainStatEntry

    if profile.preferCurrentSpecMainStat then
        local activeSpecIndex = GetSpecialization and GetSpecialization()
        if activeSpecIndex and GetSpecializationInfo then
            local _, _, _, _, _, _, primaryStat = GetSpecializationInfo(activeSpecIndex)
            mainStatKey = PRIMARY_STAT_KEY_BY_ID[primaryStat]
        end

        if not mainStatKey then
            local _, classFile = UnitClass("player")
            if classFile and activeSpecIndex then
                local classSpecMap = PRIMARY_STAT_KEY_BY_CLASS_AND_SPEC[classFile]
                if classSpecMap then
                    mainStatKey = classSpecMap[activeSpecIndex]
                end
            end

            if not mainStatKey and classFile then
                mainStatKey = PRIMARY_STAT_KEY_BY_CLASS_FILE[classFile]
            end
        end
    end

    for _, entry in ipairs(profile.stats) do
        if entry.key == mainStatKey then
            mainStatEntry = entry
        end

        if entry.enabled then
            table.insert(visible, entry)
        end
    end

    if mainStatEntry then
        for index, entry in ipairs(visible) do
            if entry.key == mainStatKey then
                table.remove(visible, index)
                break
            end
        end

        table.insert(visible, 1, mainStatEntry)
    end

    return visible
end

local function GetDisplayLayout(profile, visibleCount)
    if visibleCount <= 0 then
        return 1, { 0 }
    end

    local preferredColumns = math.max(1, math.floor(profile.columnCount or defaults.columnCount or 1))
    preferredColumns = math.min(preferredColumns, visibleCount)

    local rowsPerColumn = math.max(0, math.floor(profile.rowsPerColumn or defaults.rowsPerColumn or 0))
    local actualColumns = preferredColumns
    if rowsPerColumn > 0 then
        actualColumns = math.max(actualColumns, math.ceil(visibleCount / rowsPerColumn))
    end

    actualColumns = math.min(actualColumns, visibleCount)

    local columnItemCounts = {}
    local baseCount = math.floor(visibleCount / actualColumns)
    local extraCount = visibleCount % actualColumns
    for index = 1, actualColumns do
        columnItemCounts[index] = baseCount + (index <= extraCount and 1 or 0)
    end

    return actualColumns, columnItemCounts
end

RefreshStaticPopupTexts = function()
    if StaticPopupDialogs["NE_STATS_CREATE_PROFILE"] then
        StaticPopupDialogs["NE_STATS_CREATE_PROFILE"].text = S("Create a new profile for this account")
        StaticPopupDialogs["NE_STATS_CREATE_PROFILE"].button1 = S("Create")
        StaticPopupDialogs["NE_STATS_CREATE_PROFILE"].button2 = S("Cancel")
    end

    if StaticPopupDialogs["NE_STATS_RENAME_PROFILE"] then
        StaticPopupDialogs["NE_STATS_RENAME_PROFILE"].text = S("Rename profile %s")
        StaticPopupDialogs["NE_STATS_RENAME_PROFILE"].button1 = S("Rename")
        StaticPopupDialogs["NE_STATS_RENAME_PROFILE"].button2 = S("Cancel")
    end

    if StaticPopupDialogs["NE_STATS_DELETE_PROFILE"] then
        StaticPopupDialogs["NE_STATS_DELETE_PROFILE"].text = S("Delete profile %s?")
        StaticPopupDialogs["NE_STATS_DELETE_PROFILE"].button1 = S("Delete")
        StaticPopupDialogs["NE_STATS_DELETE_PROFILE"].button2 = S("Cancel")
    end
end

local function UpdateFrameLockState()
    if not statsFrame or not statsAnchor then
        return
    end

    local profile = GetActiveProfile()
    local locked = profile.locked

    statsAnchor:EnableMouse(true)
    statsFrame:SetBackdropColor(0, 0, 0, 0)
    statsFrame:SetBackdropBorderColor(0, 0, 0, 0)

    if lockButton then
        if locked then
            lockButton:SetNormalTexture("Interface\\BUTTONS\\LockButton-Locked-Up")
            lockButton:SetPushedTexture("Interface\\BUTTONS\\LockButton-Locked-Down")
        else
            lockButton:SetNormalTexture("Interface\\BUTTONS\\LockButton-Unlocked-Up")
            lockButton:SetPushedTexture("Interface\\BUTTONS\\LockButton-Unlocked-Down")
        end
        lockButton:SetHighlightTexture("Interface\\BUTTONS\\UI-Panel-MinimizeButton-Highlight")
        lockButton:SetShown((not profile.showLockOnHover) or isStatsFrameHovered or isLockButtonHovered)
    end
end

local function ApplyFrameStyle()
    if not statsFrame or not statsAnchor then
        return
    end

    local profile = GetActiveProfile()
    statsFrame:SetScale(profile.scale or defaults.scale)
    statsFrame:SetAlpha(profile.alpha)
    statsAnchor:ClearAllPoints()
    statsAnchor:SetPoint("TOPLEFT", UIParent, "TOPLEFT", profile.x or defaults.x, profile.y or defaults.y)
    statsFrame:ClearAllPoints()
    statsFrame:SetPoint("TOPLEFT", statsAnchor, "TOPLEFT", 0, 0)

    UpdateFrameLockState()
end

local function ToggleLockState()
    local profile = GetActiveProfile()
    profile.locked = not profile.locked
    UpdateFrameLockState()

    if profile.locked then
        print(S("NE Stats: frame locked. Use settings to unlock and adjust it."))
    else
        print(S("NE Stats: frame unlocked. Drag it, then lock when ready."))
    end

    if controlRefs.lockCheckbox then
        controlRefs.lockCheckbox:SetChecked(profile.locked)
    end
end

local function ResetOptionsPanelState()
    if optionsPanel then
        optionsPanel:Hide()
        optionsPanel:SetParent(nil)
    end
    optionsPanel = nil
    optionsCategory = nil
    optionsCategoryID = nil
    optionsPanelBuilt = false
    rowControls = {}
    controlRefs = {}
end

local function SafeBuildOptionsPanel()
    if optionsPanel and optionsPanelBuilt then
        return true
    end

    if optionsPanel and not optionsPanelBuilt then
        ResetOptionsPanelState()
    end

    local ok, err = xpcall(BuildOptionsPanel, function(message)
        return tostring(message)
    end)
    if not ok then
        lastOptionsPanelError = err
        ResetOptionsPanelState()
        return false
    end

    lastOptionsPanelError = nil
    return optionsPanelBuilt
end

local function OpenAddonSettings()
    if not SafeBuildOptionsPanel() then
        if lastOptionsPanelError and lastOptionsPanelError ~= "" then
            print(S("NE Stats: settings panel failed: %s", tostring(lastOptionsPanelError)))
        else
            print(S("NE Stats: settings panel is not available yet."))
        end
        return
    end

    if Settings and Settings.OpenToCategory and optionsCategoryID then
        Settings.OpenToCategory(optionsCategoryID)
        return
    end

    if Settings and Settings.OpenToCategory and optionsCategory then
        Settings.OpenToCategory(optionsCategory)
        return
    end

    if InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(optionsPanel)
        InterfaceOptionsFrame_OpenToCategory(optionsPanel)
        return
    end

    print(S("NE Stats: settings panel is not available yet."))
end

local function EnsureStatsFrame()
    if statsFrame then
        return
    end

    statsAnchor = CreateFrame("Frame", "ZhuraStatsAnchor", UIParent)
    statsAnchor:SetClampedToScreen(true)
    statsAnchor:SetMovable(true)
    statsAnchor:RegisterForDrag("LeftButton")
    statsAnchor:EnableMouse(true)
    statsAnchor:SetScript("OnEnter", function()
        isStatsFrameHovered = true
        UpdateFrameLockState()
    end)
    statsAnchor:SetScript("OnLeave", function()
        isStatsFrameHovered = false
        UpdateFrameLockState()
    end)

    statsFrame = CreateFrame("Frame", "ZhuraStatsFrame", statsAnchor, "BackdropTemplate")
    statsFrame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })

    statsAnchor:SetScript("OnDragStart", function(self)
        if not GetActiveProfile().locked then
            self:StartMoving()
        end
    end)

    statsAnchor:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveFramePosition()
    end)

    lockButton = CreateFrame("Button", nil, statsFrame, "UIPanelButtonTemplate")
    lockButton:SetSize(20, 20)
    lockButton:SetPoint("TOPRIGHT", -6, -6)
    lockButton:SetText("")
    lockButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    lockButton:SetScript("OnEnter", function(self)
        isLockButtonHovered = true
        UpdateFrameLockState()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(S("Lock button"), 1, 0.82, 0)
        GameTooltip:AddLine(S("Left-click: lock or unlock the frame."), 1, 1, 1, true)
        GameTooltip:AddLine(S("Right-click: open addon settings."), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    lockButton:SetScript("OnLeave", function()
        isLockButtonHovered = false
        GameTooltip:Hide()
        UpdateFrameLockState()
    end)
    lockButton:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            OpenAddonSettings()
            return
        end

        ToggleLockState()
    end)

    for index = 1, #STAT_KEYS do
        local line = statsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        line:SetJustifyH("LEFT")
        line:SetShadowOffset(1, -1)
        lines[index] = line
    end

    measureLine = statsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    measureLine:Hide()
end

local function FormatValue(entry, value)
    local precision = math.max(0, math.min(3, GetActiveProfile().percentPrecision or defaults.percentPrecision))
    if entry.suffix == "%" then
        if GetActiveProfile().showPercent then
            return string.format("%." .. precision .. "f%%", value)
        end
        return string.format("%." .. precision .. "f", value)
    end

    if value == math.floor(value) then
        return tostring(math.floor(value))
    end

    return string.format("%.2f", value)
end

local function SafeNumberCall(fn, fallback)
    if type(fn) ~= "function" then
        return fallback
    end

    local ok, value = pcall(fn)
    if not ok or type(value) ~= "number" then
        return fallback
    end

    if issecretvalue and issecretvalue(value) then
        return fallback
    end

    return value
end

local function FormatStatLine(def, profile, value)
    local statLabel = S(def.label)
    local labelPart = profile.showLabels and (statLabel .. " ") or ""
    local precision = math.max(0, math.min(3, profile.percentPrecision or defaults.percentPrecision))

    if def.rating then
        local rating = SafeNumberCall(def.rating, 0)
        if profile.showValues and profile.showPercent then
            return string.format("%s%d / %." .. precision .. "f%%", labelPart, math.floor(rating + 0.5), value)
        end

        if profile.showValues and not profile.showPercent then
            return string.format("%s%d", labelPart, math.floor(rating + 0.5))
        end

        if (not profile.showValues) and profile.showPercent then
            return string.format("%s%." .. precision .. "f%%", labelPart, value)
        end

        return labelPart ~= "" and labelPart or statLabel
    end

    if not profile.showValues then
        return labelPart ~= "" and labelPart or statLabel
    end

    return string.format("%s%s", labelPart, FormatValue(def, value))
end

local function RefreshStatsImpl()
    EnsureStatsFrame()
    ApplyFrameStyle()

    local profile = GetActiveProfile()
    local visibleStats = GetVisibleStats()
    local fontPath, fontFlags = GetFontInfo(profile.fontKey)
    local fontSize = math.max(MIN_DYNAMIC_FONT_SIZE, profile.fontSize or defaults.fontSize)
    local leftPadding = 8
    local rightPadding = 28
    local topPadding = 8
    local bottomPadding = 4
    local columnGap = 20
    local rowGap = 2
    local measuredStats = {}
    local maxLineHeight = 0

    measureLine:SetFont(fontPath, fontSize, fontFlags)
    for index, entry in ipairs(visibleStats) do
        local def = statDefinitions[entry.key]
        local value = SafeNumberCall(def.value, nil)
        if value ~= nil then
            local text = FormatStatLine(def, profile, value)

            measureLine:SetText(text)
            local textWidth = measureLine.GetUnboundedStringWidth and measureLine:GetUnboundedStringWidth() or measureLine:GetStringWidth()
            local textHeight = measureLine:GetStringHeight()
            measuredStats[index] = {
                entry = entry,
                text = text,
                textWidth = textWidth,
                textHeight = textHeight,
            }
            maxLineHeight = math.max(maxLineHeight, math.ceil(textHeight))
        end
    end

    local actualColumns, columnItemCounts = GetDisplayLayout(profile, #measuredStats)
    local columnWidths = {}
    local maxRows = 0
    local itemIndex = 1
    for columnIndex = 1, actualColumns do
        local columnWidth = 0
        local rowCount = columnItemCounts[columnIndex] or 0
        maxRows = math.max(maxRows, rowCount)
        for _ = 1, rowCount do
            local measured = measuredStats[itemIndex]
            if measured then
                columnWidth = math.max(columnWidth, measured.textWidth)
            end
            itemIndex = itemIndex + 1
        end
        columnWidths[columnIndex] = columnWidth
    end

    maxLineHeight = math.max(maxLineHeight, fontSize)
    itemIndex = 1
    local currentXOffset = leftPadding
    for columnIndex = 1, actualColumns do
        local rowCount = columnItemCounts[columnIndex] or 0
        for rowIndex = 1, rowCount do
            local measured = measuredStats[itemIndex]
            local line = lines[itemIndex]
            if measured and line then
                local currentYOffset = topPadding + (rowIndex - 1) * (maxLineHeight + rowGap)
                line:ClearAllPoints()
                line:SetFont(fontPath, fontSize, fontFlags)
                line:SetPoint("TOPLEFT", statsFrame, "TOPLEFT", currentXOffset, -currentYOffset)
                line:SetWidth(math.max(columnWidths[columnIndex] + 4, 40))
                line:SetWordWrap(false)
                line:SetMaxLines(1)
                line:SetTextColor(measured.entry.color[1], measured.entry.color[2], measured.entry.color[3], 1)
                line:SetText(measured.text)
                line:Show()
            end
            itemIndex = itemIndex + 1
        end
        currentXOffset = currentXOffset + columnWidths[columnIndex] + columnGap
    end

    for index = #measuredStats + 1, #lines do
        lines[index]:Hide()
    end

    local contentWidth = 0
    for columnIndex = 1, actualColumns do
        contentWidth = contentWidth + (columnWidths[columnIndex] or 0)
    end
    if actualColumns > 1 then
        contentWidth = contentWidth + (actualColumns - 1) * columnGap
    end

    local contentHeight = 0
    if maxRows > 0 then
        contentHeight = maxRows * maxLineHeight + math.max(0, maxRows - 1) * rowGap
    end

    local frameWidth = math.max(24, math.ceil(contentWidth) + leftPadding + rightPadding)
    local frameHeight = math.max(24, math.ceil(topPadding + contentHeight + bottomPadding))
    statsFrame:SetSize(frameWidth, frameHeight)
    if statsAnchor then
        local scale = profile.scale or defaults.scale
        statsAnchor:SetSize(frameWidth * scale, frameHeight * scale)
    end
end

RefreshStats = function()
    local handledError
    local ok, err = xpcall(RefreshStatsImpl, function(message)
        handledError = tostring(message or "unknown error")
        local errorHandler = geterrorhandler and geterrorhandler()
        if type(errorHandler) == "function" then
            errorHandler(handledError)
        end
        return handledError
    end)
    if not ok then
        local displayError = tostring(err or handledError or "")
        if displayError ~= "" and displayError ~= "nil" then
            local now = (GetTime and GetTime()) or 0
            if displayError ~= lastRefreshErrorMessage or (now - lastRefreshErrorAt) > 2 then
                print(S("NE Stats: refresh failed: %s", displayError))
                lastRefreshErrorMessage = displayError
                lastRefreshErrorAt = now
            end
        end
    end
end

local function MoveStat(index, direction)
    local stats = GetActiveProfile().stats
    local target = index + direction
    if not stats[index] or not stats[target] then
        return
    end

    stats[index], stats[target] = stats[target], stats[index]
    RefreshStats()
end

local function CreateCheckbox(parent, label, tooltip, onClick)
    local checkbox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    checkbox.label = checkbox:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    checkbox.label:SetPoint("LEFT", checkbox, "RIGHT", 6, 0)
    checkbox.label:SetJustifyH("LEFT")
    checkbox.label:SetText(label)
    checkbox.tooltipText = tooltip
    checkbox:SetScript("OnClick", onClick)
    checkbox:SetScript("OnEnter", function(self)
        if not self.tooltipText then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tooltipText, 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    checkbox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    return checkbox
end

local function CreateIconButton(parent, width, height, normalTexture, pushedTexture, disabledTexture, tooltipText)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, height)
    button:SetNormalTexture(normalTexture)
    button:SetPushedTexture(pushedTexture or normalTexture)
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    if disabledTexture then
        button:SetDisabledTexture(disabledTexture)
    end

    button.tooltipText = tooltipText
    button:SetScript("OnEnter", function(self)
        if not self.tooltipText then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tooltipText, 1, 0.82, 0)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    button:SetMotionScriptsWhileDisabled(true)
    return button
end

local function CreateSlider(name, parent, label, minValue, maxValue, step, onValueChanged)
    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    slider:SetWidth(220)
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    _G[name .. "Low"]:SetText(tostring(minValue))
    _G[name .. "High"]:SetText(tostring(maxValue))
    _G[name .. "Text"]:SetText(label)
    slider:SetScript("OnValueChanged", onValueChanged)
    return slider
end

local function OpenColorPicker(entry)
    local color = entry.color
    local previous = { color[1], color[2], color[3] }

    local function apply(r, g, b)
        entry.color[1], entry.color[2], entry.color[3] = r, g, b
        RefreshStats()
        if optionsPanel and optionsPanel:GetScript("OnShow") then
            optionsPanel:GetScript("OnShow")(optionsPanel)
        end
    end

    if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = color[1],
            g = color[2],
            b = color[3],
            hasOpacity = false,
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                apply(r, g, b)
            end,
            cancelFunc = function()
                apply(previous[1], previous[2], previous[3])
            end,
        })
        return
    end

    if ColorPickerFrame then
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.func = function()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            apply(r, g, b)
        end
        ColorPickerFrame.cancelFunc = function()
            apply(previous[1], previous[2], previous[3])
        end
        ColorPickerFrame:SetColorRGB(color[1], color[2], color[3])
        ColorPickerFrame:Hide()
        ColorPickerFrame:Show()
    end
end

local function RefreshStatsDeferred()
    RefreshStats()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if initialized then
                RefreshStats()
            end
        end)
    end
end

RefreshOptionRows = function()
    if InCombatLockdown and InCombatLockdown() then
        pendingOptionRowsAfterCombat = true
        return
    end

    pendingOptionRowsAfterCombat = false
    if not optionsPanel then
        return
    end

    local profile = GetActiveProfile()
    for index, row in ipairs(rowControls) do
        local entry = profile.stats[index]
        local def = statDefinitions[entry.key]
        row.index = index
        row.checkbox:SetChecked(entry.enabled)
        row.label:SetText(S(def.label))
        row.swatch.texture:SetColorTexture(entry.color[1], entry.color[2], entry.color[3], 1)
        row.up:SetEnabled(index > 1)
        row.down:SetEnabled(index < #profile.stats)
        row.entry = entry
    end
end

BuildOptionsPanel = function()
    if optionsPanel and optionsPanelBuilt then
        return
    end

    optionsPanel = CreateFrame("Frame", ADDON_NAME .. "OptionsPanel", UIParent)
    optionsPanel.name = S("NE Stats")
    optionsPanel:SetSize(780, 620)
    local scrollFrame = CreateFrame("ScrollFrame", ADDON_NAME .. "OptionsScrollFrame", optionsPanel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 12, -12)
    scrollFrame:SetPoint("BOTTOMRIGHT", -32, 12)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(720, 980)
    scrollFrame:SetScrollChild(content)
    controlRefs.scrollFrame = scrollFrame
    controlRefs.scrollContent = content

    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(S("NE Stats"))
    controlRefs.title = title

    local subtitle = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetWidth(660)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText(S("Profiles are shared across your account.\nYou can create multiple profiles to save different layouts, positions, and display settings."))
    controlRefs.subtitle = subtitle

    local profileLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    profileLabel:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -18)
    profileLabel:SetText(S("Profile"))
    controlRefs.profileLabel = profileLabel

    local profileDropDown = CreateFrame("Frame", ADDON_NAME .. "ProfileDropDown", content, "UIDropDownMenuTemplate")
    profileDropDown:SetPoint("TOPLEFT", profileLabel, "BOTTOMLEFT", -16, -2)
    UIDropDownMenu_SetWidth(profileDropDown, 240)
    InitializeProfileDropDown = function(_, level)
        for _, name in ipairs(GetProfileNames()) do
            local profileName = name
            local info = UIDropDownMenu_CreateInfo()
            info.text = GetDisplayProfileName(profileName)
            local _, activeName = GetActiveRootProfile()
            info.checked = activeName == profileName
            info.func = function()
                profileDropDown:SetValue(profileName)
                CloseDropDownMenus()
                SelectRootProfile(profileName)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end
    UIDropDownMenu_Initialize(profileDropDown, InitializeProfileDropDown)
    profileDropDown.SetValue = function(_, newValue)
        SetProfileDropDownSelection(profileDropDown, newValue)
    end
    local _, activeProfileName = GetActiveRootProfile()
    profileDropDown:SetValue(activeProfileName)
    controlRefs.profileDropDown = profileDropDown

    local profileDropDownText = _G[profileDropDown:GetName() .. "Text"]
    local profileDropDownButton = _G[profileDropDown:GetName() .. "Button"]
    if profileDropDownText then
        profileDropDownText:SetWidth(126)
        profileDropDownText:SetJustifyH("LEFT")
    end

    local profileActions = CreateFrame("Frame", nil, profileDropDown)
    profileActions:SetSize(34, 18)
    if profileDropDownButton then
        profileActions:SetPoint("RIGHT", profileDropDownButton, "LEFT", -12, 0)
    else
        profileActions:SetPoint("RIGHT", profileDropDown, "RIGHT", -30, 0)
    end
    profileActions:SetFrameStrata(profileDropDown:GetFrameStrata())
    profileActions:SetFrameLevel(profileDropDown:GetFrameLevel() + 8)
    controlRefs.profileActions = profileActions

    local profileRenameButton = CreateIconButton(
        profileActions,
        16,
        16,
        "Interface\\Buttons\\UI-GuildButton-PublicNote-Up",
        "Interface\\Buttons\\UI-GuildButton-PublicNote-Down",
        "Interface\\Buttons\\UI-GuildButton-PublicNote-Disabled",
        S("Rename profile")
    )
    profileRenameButton:SetPoint("RIGHT", profileActions, "RIGHT", 0, 0)
    profileRenameButton:SetFrameStrata(profileActions:GetFrameStrata())
    profileRenameButton:SetFrameLevel(profileActions:GetFrameLevel() + 1)
    profileRenameButton:SetScript("OnClick", function()
        local _, profileName = GetActiveRootProfile()
        if not CanModifyProfile(profileName) then
            return
        end
        pendingRenameProfileName = profileName
        local dialog = StaticPopup_Show("NE_STATS_RENAME_PROFILE", GetDisplayProfileName(profileName), nil, profileName)
        if dialog then
            dialog.data = profileName
        end
    end)
    controlRefs.profileRenameButton = profileRenameButton

    local profileDeleteButton = CreateIconButton(
        profileActions,
        16,
        16,
        "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
        "Interface\\Buttons\\UI-GroupLoot-Pass-Down",
        "Interface\\Buttons\\UI-GroupLoot-Pass-Disabled",
        S("Delete profile")
    )
    profileDeleteButton:SetPoint("RIGHT", profileRenameButton, "LEFT", -2, 0)
    profileDeleteButton:SetFrameStrata(profileActions:GetFrameStrata())
    profileDeleteButton:SetFrameLevel(profileActions:GetFrameLevel() + 1)
    profileDeleteButton:SetScript("OnClick", function()
        local _, profileName = GetActiveRootProfile()
        if not CanModifyProfile(profileName) then
            return
        end
        StaticPopup_Show("NE_STATS_DELETE_PROFILE", GetDisplayProfileName(profileName), nil, profileName)
    end)
    controlRefs.profileDeleteButton = profileDeleteButton

    local profileInfo = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    profileInfo:SetPoint("TOPLEFT", profileDropDown, "BOTTOMLEFT", 20, -8)
    profileInfo:SetJustifyH("LEFT")
    profileInfo:SetText("")
    controlRefs.profileInfo = profileInfo

    local profileCreateLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    profileCreateLabel:SetPoint("TOPLEFT", profileInfo, "BOTTOMLEFT", 0, -10)
    profileCreateLabel:SetText(S("Create New..."))
    controlRefs.profileCreateLabel = profileCreateLabel

    local profileCreateEditBox = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    profileCreateEditBox:SetSize(150, 24)
    profileCreateEditBox:SetAutoFocus(false)
    profileCreateEditBox:SetPoint("TOPLEFT", profileCreateLabel, "BOTTOMLEFT", 0, -6)
    profileCreateEditBox:SetScript("OnEnterPressed", function(self)
        CreateProfileFromInput(self)
        self:ClearFocus()
    end)
    controlRefs.profileCreateEditBox = profileCreateEditBox

    local profileCreateButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    profileCreateButton:SetSize(70, 22)
    profileCreateButton:SetPoint("LEFT", profileCreateEditBox, "RIGHT", 8, 0)
    profileCreateButton:SetText(S("Create"))
    profileCreateButton:SetScript("OnClick", function()
        CreateProfileFromInput(profileCreateEditBox)
    end)
    controlRefs.profileCreateButton = profileCreateButton

    local languageLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    languageLabel:SetPoint("TOPLEFT", profileCreateEditBox, "BOTTOMLEFT", 0, -18)
    languageLabel:SetText(S("Addon language"))
    controlRefs.languageLabel = languageLabel

    local languageDropDown = CreateFrame("Frame", ADDON_NAME .. "LanguageDropDown", content, "UIDropDownMenuTemplate")
    languageDropDown:SetPoint("TOPLEFT", languageLabel, "BOTTOMLEFT", -16, -2)
    UIDropDownMenu_SetWidth(languageDropDown, 220)
    InitializeLanguageDropDown = function(_, level)
        local localeOptions = {
            CLIENT_LANGUAGE_VALUE,
            "enUS",
            "deDE",
            "esES",
            "esMX",
            "frFR",
            "itIT",
            "koKR",
            "ptBR",
            "ruRU",
            "ukUA",
            "zhCN",
            "zhTW",
        }

        for _, localeCode in ipairs(localeOptions) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = GetLocaleDisplayName(localeCode)
            info.value = localeCode
            info.checked = GetConfiguredLocale() == localeCode
            info.func = function()
                db.global.addonLocale = localeCode
                ApplyLocale()
                RefreshLocalizedUI()
                ApplyCurrentProfileState()
                UpdateFrameLockState()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end
    UIDropDownMenu_Initialize(languageDropDown, InitializeLanguageDropDown)
    controlRefs.languageDropDown = languageDropDown

    local showPercentCheckbox = CreateCheckbox(content, S("Show percentages"), nil, function(self)
        GetActiveProfile().showPercent = self:GetChecked()
        RefreshStats()
    end)
    showPercentCheckbox:SetPoint("TOPLEFT", languageDropDown, "BOTTOMLEFT", 16, -16)
    controlRefs.showPercentCheckbox = showPercentCheckbox

    local precisionSlider = CreateSlider(ADDON_NAME .. "PercentPrecisionSlider", content, S("Percent Decimals"), 0, 3, 1, function(_, value)
        GetActiveProfile().percentPrecision = value
        RefreshStats()
    end)
    precisionSlider:SetPoint("TOPLEFT", showPercentCheckbox, "BOTTOMLEFT", 6, -24)
    controlRefs.precisionSlider = precisionSlider

    local showLabelsCheckbox = CreateCheckbox(content, S("Show stat names"), nil, function(self)
        GetActiveProfile().showLabels = self:GetChecked()
        RefreshStats()
    end)
    showLabelsCheckbox:SetPoint("TOPLEFT", precisionSlider, "BOTTOMLEFT", -6, -18)
    controlRefs.showLabelsCheckbox = showLabelsCheckbox

    local showValuesCheckbox = CreateCheckbox(content, S("Show values"), nil, function(self)
        GetActiveProfile().showValues = self:GetChecked()
        RefreshStats()
    end)
    showValuesCheckbox:SetPoint("TOPLEFT", showLabelsCheckbox, "BOTTOMLEFT", 0, -8)
    controlRefs.showValuesCheckbox = showValuesCheckbox

    local lockCheckbox = CreateCheckbox(content, S("Lock frame"), nil, function(self)
        GetActiveProfile().locked = self:GetChecked()
        UpdateFrameLockState()
        if self:GetChecked() then
            print(S("NE Stats: frame locked. Use settings to unlock and adjust it."))
        else
            print(S("NE Stats: frame unlocked. Drag it, then lock when ready."))
        end
    end)
    lockCheckbox:SetPoint("TOPLEFT", showValuesCheckbox, "BOTTOMLEFT", 0, -8)
    controlRefs.lockCheckbox = lockCheckbox

    local showLockOnHoverCheckbox = CreateCheckbox(
        content,
        S("Show lock icon only on hover"),
        S("Shows the lock button only while the mouse is over the frame."),
        function(self)
            GetActiveProfile().showLockOnHover = self:GetChecked()
            UpdateFrameLockState()
        end
    )
    showLockOnHoverCheckbox:SetPoint("TOPLEFT", lockCheckbox, "BOTTOMLEFT", 0, -8)
    controlRefs.showLockOnHoverCheckbox = showLockOnHoverCheckbox

    local preferCurrentSpecMainStatCheckbox = CreateCheckbox(
        content,
        S("Always show current specialization main stat first"),
        S("Keeps the primary stat for your current specialization at the top of the display."),
        function(self)
            GetActiveProfile().preferCurrentSpecMainStat = self:GetChecked()
            RefreshStats()
        end
    )
    preferCurrentSpecMainStatCheckbox:SetPoint("TOPLEFT", showLockOnHoverCheckbox, "BOTTOMLEFT", 0, -8)
    controlRefs.preferCurrentSpecMainStatCheckbox = preferCurrentSpecMainStatCheckbox

    local alphaSlider = CreateSlider(ADDON_NAME .. "AlphaSlider", content, S("Background Opacity"), 0.1, 1, 0.05, function(_, value)
        GetActiveProfile().alpha = value
        ApplyFrameStyle()
    end)
    alphaSlider:SetPoint("TOPLEFT", preferCurrentSpecMainStatCheckbox, "BOTTOMLEFT", 6, -24)
    controlRefs.alphaSlider = alphaSlider

    local scaleSlider = CreateSlider(ADDON_NAME .. "ScaleSlider", content, S("UI Scale"), 0.5, 3, 0.05, function(_, value)
        GetActiveProfile().scale = value
        ApplyFrameStyle()
        RefreshStats()
    end)
    scaleSlider:SetPoint("TOPLEFT", alphaSlider, "BOTTOMLEFT", 0, -36)
    controlRefs.scaleSlider = scaleSlider

    local fontSizeSlider = CreateSlider(ADDON_NAME .. "FontSizeSlider", content, S("Font Size"), 10, 32, 1, function(_, value)
        GetActiveProfile().fontSize = value
        RefreshStats()
    end)
    fontSizeSlider:SetPoint("TOPLEFT", scaleSlider, "BOTTOMLEFT", 0, -36)
    controlRefs.fontSizeSlider = fontSizeSlider

    local columnCountSlider = CreateSlider(ADDON_NAME .. "ColumnCountSlider", content, S("Columns"), 1, #STAT_KEYS, 1, function(_, value)
        GetActiveProfile().columnCount = math.max(1, math.floor(value + 0.5))
        RefreshStats()
    end)
    columnCountSlider:SetPoint("TOPLEFT", fontSizeSlider, "BOTTOMLEFT", 0, -36)
    controlRefs.columnCountSlider = columnCountSlider

    local rowsPerColumnSlider = CreateSlider(ADDON_NAME .. "RowsPerColumnSlider", content, S("Max Rows per Column"), 0, #STAT_KEYS, 1, function(_, value)
        GetActiveProfile().rowsPerColumn = math.max(0, math.floor(value + 0.5))
        RefreshStats()
    end)
    rowsPerColumnSlider:SetPoint("TOPLEFT", columnCountSlider, "BOTTOMLEFT", 0, -36)
    _G[rowsPerColumnSlider:GetName() .. "Low"]:SetText(S("Auto"))
    controlRefs.rowsPerColumnSlider = rowsPerColumnSlider

    local fontLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fontLabel:SetPoint("TOPLEFT", rowsPerColumnSlider, "BOTTOMLEFT", -6, -26)
    fontLabel:SetText(S("Font"))
    controlRefs.fontLabel = fontLabel

    local fontDropDown = CreateFrame("Frame", ADDON_NAME .. "FontDropDown", content, "UIDropDownMenuTemplate")
    fontDropDown:SetPoint("TOPLEFT", fontLabel, "BOTTOMLEFT", -16, -2)
    UIDropDownMenu_SetWidth(fontDropDown, 220)
    UIDropDownMenu_Initialize(fontDropDown, function(_, level)
        for _, font in ipairs(GetAvailableFonts()) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = font.label
            info.func = function()
                GetActiveProfile().fontKey = font.key
                UIDropDownMenu_SetSelectedName(fontDropDown, font.label)
                if controlRefs.fontPreview then
                    local path, flags = GetFontInfo(font.key)
                    controlRefs.fontPreview:SetFont(path or STANDARD_TEXT_FONT, 18, flags or "OUTLINE")
                    controlRefs.fontPreview:SetText(font.label .. " - " .. S("The quick brown fox 123"))
                end
                RefreshStatsDeferred()
            end
            info.checked = GetActiveProfile().fontKey == font.key
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    controlRefs.fontDropDown = fontDropDown

    local fontPreview = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fontPreview:SetPoint("TOPLEFT", fontDropDown, "BOTTOMLEFT", 20, -6)
    fontPreview:SetText(S("The quick brown fox 123"))
    controlRefs.fontPreview = fontPreview

    local resetButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    resetButton:SetSize(140, 24)
    resetButton:SetPoint("TOPLEFT", fontPreview, "BOTTOMLEFT", -4, -18)
    resetButton:SetText(S("Reset Position"))
    resetButton:SetScript("OnClick", function()
        local profile = GetActiveProfile()
        profile.point = defaults.point
        profile.relativePoint = defaults.relativePoint
        profile.x = defaults.x
        profile.y = defaults.y
        ApplyFrameStyle()
        RefreshStats()
        print(S("NE Stats: frame position reset."))
    end)
    controlRefs.resetButton = resetButton

    local statHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    statHeader:SetPoint("TOPLEFT", 360, -150)
    statHeader:SetText(S("Stats"))
    controlRefs.statHeader = statHeader

    local statHint = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    statHint:SetPoint("TOPLEFT", statHeader, "BOTTOMLEFT", 0, -4)
    statHint:SetText(S("Check to show, set color, move with arrows"))
    controlRefs.statHint = statHint

    for index = 1, #STAT_KEYS do
        local row = CreateFrame("Frame", nil, content)
        row:SetSize(320, 26)
        row:SetPoint("TOPLEFT", 360, -180 - (index - 1) * 30)

        local checkbox = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        checkbox:SetPoint("LEFT", 0, 0)
        row.checkbox = checkbox

        local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        label:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
        label:SetWidth(112)
        label:SetJustifyH("LEFT")
        row.label = label

        local swatch = CreateFrame("Button", nil, row, "BackdropTemplate")
        swatch:SetSize(16, 16)
        swatch:SetPoint("LEFT", label, "RIGHT", 8, 0)
        swatch:SetBackdrop({
            bgFile = "Interface/Buttons/WHITE8x8",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true,
            tileSize = 8,
            edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        swatch:SetBackdropColor(0, 0, 0, 0.9)
        swatch.texture = swatch:CreateTexture(nil, "ARTWORK")
        swatch.texture:SetPoint("TOPLEFT", 2, -2)
        swatch.texture:SetPoint("BOTTOMRIGHT", -2, 2)
        row.swatch = swatch

        local color = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        color:SetSize(48, 20)
        color:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
        color:SetText(S("Color"))
        row.color = color

        local up = CreateFrame("Button", nil, row)
        up:SetSize(24, 20)
        up:SetPoint("LEFT", color, "RIGHT", 10, 0)
        up:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up")
        up:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Down")
        up:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
        up:SetDisabledTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Disabled")
        row.up = up

        local down = CreateFrame("Button", nil, row)
        down:SetSize(24, 20)
        down:SetPoint("LEFT", up, "RIGHT", 6, 0)
        down:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
        down:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Down")
        down:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
        down:SetDisabledTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Disabled")
        row.down = down

        checkbox:SetScript("OnClick", function(self)
            row.entry.enabled = self:GetChecked()
            RefreshStats()
        end)
        swatch:SetScript("OnClick", function()
            OpenColorPicker(row.entry)
        end)
        color:SetScript("OnClick", function()
            OpenColorPicker(row.entry)
        end)
        up:SetScript("OnClick", function()
            MoveStat(row.index, -1)
            RefreshOptionRows()
        end)
        down:SetScript("OnClick", function()
            MoveStat(row.index, 1)
            RefreshOptionRows()
        end)

        rowControls[index] = row
    end

    optionsPanel:SetScript("OnShow", function()
        RefreshLocalizedUI()
        ApplyCurrentProfileState()
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        optionsCategory = Settings.RegisterCanvasLayoutCategory(optionsPanel, S("NE Stats"))
        optionsCategoryID = optionsCategory.GetID and optionsCategory:GetID() or nil
        Settings.RegisterAddOnCategory(optionsCategory)
    end

    if InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(optionsPanel)
    end

    optionsPanelBuilt = true
end

local function SlashHandler(message)
    local command = string.lower(strtrim(message or ""))
    if command == "reset" then
        if db then
            db:ResetProfile()
            MigrateProfile(db.profile)
        end
        ApplyCurrentProfileState()
        print(S("NE Stats: active profile reset."))
        return
    end

    if command == "lock" then
        if not GetActiveProfile().locked then
            ToggleLockState()
        end
        return
    end

    if command == "unlock" then
        if GetActiveProfile().locked then
            ToggleLockState()
        end
        return
    end

    OpenAddonSettings()
end

SLASH_ZHURASTATS1 = "/zhs"
SLASH_ZHURASTATS2 = "/zhurastats"
SlashCmdList.ZHURASTATS = SlashHandler

local function Initialize()
    if initialized then
        return
    end

    initialized = true
    EnsureDatabase()
    EnsureStatsFrame()
    ApplyFrameStyle()
    RefreshStats()
end

addon:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        EnsureDatabase()
        return
    end

    if event == "PLAYER_LOGIN" then
        Initialize()
        SafeBuildOptionsPanel()
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        RefreshStats()
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        if pendingOptionRowsAfterCombat and optionsPanel and optionsPanel:IsShown() then
            RefreshOptionRows()
        end
        return
    end

    if (event == "UNIT_AURA" or event == "UNIT_STATS" or event == "UNIT_INVENTORY_CHANGED") and arg1 ~= "player" then
        return
    end

    if event == "TRAIT_CONFIG_UPDATED" and arg1 and tostring(arg1) ~= tostring(C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID() or "") then
        return
    end

    RefreshStats()
    if optionsPanel and optionsPanel:IsShown() then
        RefreshOptionRows()
    end
end)
