local _, ns = ...

ns = ns or {}
ns.ZhuraStats = ns.ZhuraStats or {}
local Addon = ns.ZhuraStats

ZhuraStatsDB = ZhuraStatsDB or {}

local AceDB = LibStub and LibStub("AceDB-3.0", true)
local db
local profileStateChangeCounter = 0
local newProfileInitCounter = 0
local STATS_MIGRATION_VERSION = 5
local PRIMARY_STATS = {
    STR = true,
    AGI = true,
    INT = true,
}

local function PrintProfileList(title, profiles)
    print(title)
    if type(profiles) ~= "table" then
        print("-", "<none>")
        return
    end

    local names = {}
    for name in pairs(profiles) do
        table.insert(names, name)
    end
    table.sort(names)

    if #names == 0 then
        print("-", "<empty>")
        return
    end

    for _, name in ipairs(names) do
        print("-", name)
    end
end

function Addon:NormalizeProfileName(profileName)
    if not profileName then
        return ""
    end
    local normalized = strtrim(profileName)
    normalized = normalized:gsub("%s+", " ")
    return normalized
end

function Addon:CanModifyProfile(profileName)
    return profileName and profileName ~= "" and profileName ~= "Default"
end

function Addon:GetCurrentPrimaryStatKey()
    local constants = self.Constants
    local primaryStatKeyById = constants and constants.PRIMARY_STAT_KEY_BY_ID
    if type(primaryStatKeyById) ~= "table" then
        return nil
    end

    if type(GetSpecialization) ~= "function" or type(GetSpecializationInfo) ~= "function" then
        return nil
    end

    local okSpec, specIndex = pcall(GetSpecialization)
    if not okSpec or type(specIndex) ~= "number" then
        return nil
    end

    -- pcall returns ok first, then GetSpecializationInfo values:
    -- id, name, description, icon, role, primaryStat.
    -- Therefore primaryStat is the variable after five ignored return values.
    local okInfo, _, _, _, _, _, primaryStat = pcall(GetSpecializationInfo, specIndex)
    if not okInfo then
        return nil
    end

    return primaryStatKeyById[primaryStat]
end

function Addon:InitializePrimaryStatForProfile(profile)
    if type(profile) ~= "table" then
        return
    end

    if profile.primaryStatInitialized == true then
        return
    end

    if type(profile.stats) ~= "table" then
        profile.primaryStatInitialized = true
        return
    end

    for _, entry in ipairs(profile.stats) do
        if type(entry) == "table" and PRIMARY_STATS[entry.key] then
            entry.enabled = false
        end
    end

    local primaryStatKey = self:GetCurrentPrimaryStatKey()
    if primaryStatKey then
        for _, entry in ipairs(profile.stats) do
            if type(entry) == "table" and entry.key == primaryStatKey then
                entry.enabled = true
                break
            end
        end
    end

    profile.primaryStatInitialized = true
end

function Addon:InitializeNewProfile(profile)
    if type(profile) ~= "table" then
        return
    end

    self:MigrateProfile(profile)
    profile.primaryStatInitialized = false
    self:InitializePrimaryStatForProfile(profile)
end

function Addon:MigrateProfile(profile)
    local defaults = self.Defaults.profile
    local statDefinitions = self.StatDefinitions
    local defaultStatsByKey = self.DefaultStatsByKey
    local statKeys = self.Constants.STAT_KEYS

    local function IsStatsValid(stats)
        if type(stats) ~= "table" then
            return false
        end
        for i = 1, #statKeys do
            local entry = stats[i]
            if type(entry) ~= "table" then
                return false
            end
            if entry.key ~= statKeys[i] then
                return false
            end
            if entry.enabled == nil then
                return false
            end
            if type(entry.color) ~= "table" then
                return false
            end
        end
        return true
    end

    if profile.statsMigrationVersion ~= STATS_MIGRATION_VERSION or not IsStatsValid(profile.stats) then
        local oldStats = type(profile.stats) == "table" and profile.stats or nil
        local oldByKey = {}
        local oldPriorityByKey = {}

        for index = 1, #statKeys do
            local entry = oldStats and oldStats[index] or nil
            local key
            local priority = 0

            if type(entry) == "table" then
                if type(entry.key) == "string" then
                    key = entry.key
                    priority = 2
                else
                    key = statKeys[index]
                    priority = 1
                end
            elseif type(entry) == "string" then
                key = entry
                priority = 2
            end

            if key and statDefinitions[key] then
                local existingPriority = oldPriorityByKey[key] or -1
                if priority >= existingPriority then
                    oldByKey[key] = entry
                    oldPriorityByKey[key] = priority
                end
            end
        end

        if oldStats then
            for _, entry in pairs(oldStats) do
                local key
                local priority = 0
                if type(entry) == "table" and type(entry.key) == "string" then
                    key = entry.key
                    priority = 2
                elseif type(entry) == "string" then
                    key = entry
                    priority = 2
                end
                if key and statDefinitions[key] then
                    local existingPriority = oldPriorityByKey[key] or -1
                    if priority >= existingPriority then
                        oldByKey[key] = entry
                        oldPriorityByKey[key] = priority
                    end
                end
            end
        end

        local migrated = {}
        for i = 1, #statKeys do
            local key = statKeys[i]
            local oldEntry = oldByKey[key]

            local enabled
            local color

            if type(oldEntry) == "table" then
                enabled = oldEntry.enabled
                color = oldEntry.color
            end

            if enabled == nil then
                enabled = defaultStatsByKey[key] and defaultStatsByKey[key].enabled or false
            end

            if type(color) ~= "table" then
                color = self.DeepCopy(statDefinitions[key].color)
            end

            migrated[i] = {
                key = key,
                enabled = enabled ~= false,
                color = color,
            }
        end

        profile.stats = migrated
        profile.statsMigrationVersion = STATS_MIGRATION_VERSION
    end
    profile.alpha = profile.alpha or defaults.alpha
    profile.scale = profile.scale or defaults.scale
    profile.fontSize = profile.fontSize or defaults.fontSize
    profile.fontKey = profile.fontKey or defaults.fontKey
    profile.columnCount = math.max(1, math.floor(profile.columnCount or defaults.columnCount))
    profile.rowsPerColumn = math.max(0, math.floor(profile.rowsPerColumn or defaults.rowsPerColumn))
    profile.showPercent = profile.showPercent ~= false
    profile.percentPrecision = profile.percentPrecision or profile.decimalPrecision or defaults.percentPrecision
    if profile.drDisplayMode == nil then
        if profile.showDiminishingReturns == true then
            profile.drDisplayMode = "penalty"
        else
            profile.drDisplayMode = defaults.drDisplayMode
        end
    end
    if profile.drDisplayMode == "suffix" then
        profile.drDisplayMode = "penalty"
    end
    if profile.drDisplayMode ~= "off" and profile.drDisplayMode ~= "penalty"
        and profile.drDisplayMode ~= "loss" and profile.drDisplayMode ~= "full" then
        profile.drDisplayMode = defaults.drDisplayMode
    end
    profile.showDiminishingReturns = nil
    profile.showPotionState = nil
    profile.showLabels = profile.showLabels ~= false
    profile.showValues = profile.showValues ~= false
    profile.textAlign = profile.textAlign or defaults.textAlign
    if profile.textAlign ~= "LEFT" and profile.textAlign ~= "CENTER" and profile.textAlign ~= "RIGHT" then
        profile.textAlign = defaults.textAlign
    end
    profile.goldUseSeparator = profile.goldUseSeparator ~= false
    profile.goldSeparator = profile.goldSeparator or defaults.goldSeparator
    if profile.goldSeparator ~= " " and profile.goldSeparator ~= "," and profile.goldSeparator ~= "." and profile.goldSeparator ~= "'" and profile.goldSeparator ~= "_" then
        profile.goldSeparator = defaults.goldSeparator
    end
    profile.locked = profile.locked or false
    profile.showLockOnHover = profile.showLockOnHover == true
    profile.preferCurrentSpecMainStat = profile.preferCurrentSpecMainStat == true
    profile.specProfiles = profile.specProfiles or {}
    profile.point = profile.point or defaults.point
    profile.relativeTo = profile.relativeTo or defaults.relativeTo
    profile.relativePoint = profile.relativePoint or defaults.relativePoint
    profile.x = profile.x or defaults.x
    profile.y = profile.y or defaults.y
    profile.width = profile.width or defaults.width
    profile.height = profile.height or defaults.height
    profile.useSpecProfiles = false
    profile.useLoadoutProfiles = nil
    if profile.primaryStatInitialized == nil then
        profile.primaryStatInitialized = true
    end
end

function Addon:EnsureDatabase()
    if not AceDB then
        return
    end
    local aceDefaults = self.Defaults.ace
    ZhuraStatsDB = ZhuraStatsDB or {}
    local hasExistingProfiles = type(ZhuraStatsDB.profiles) == "table" and next(ZhuraStatsDB.profiles) ~= nil

    db = LibStub("AceDB-3.0"):New("ZhuraStatsDB", aceDefaults, true)
    self.db = db

    if db.RegisterCallback then
        db.RegisterCallback(Addon, "OnProfileChanged", "HandleAceDBProfileStateChanged")
        db.RegisterCallback(Addon, "OnProfileCopied", "HandleAceDBProfileStateChanged")
        db.RegisterCallback(Addon, "OnProfileReset", "HandleAceDBProfileStateChanged")
        db.RegisterCallback(Addon, "OnNewProfile", "HandleAceDBNewProfile")
    end

    for _, profile in pairs(db.sv.profiles or {}) do
        Addon:MigrateProfile(profile)
    end

    if not hasExistingProfiles and db.profile then
        self:InitializeNewProfile(db.profile)
    end

    db.global.addonLocale = db.global.addonLocale or self.Constants.CLIENT_LANGUAGE_VALUE
    self:ApplyLocale()
end

function Addon:RestoreMissingProfilesFromBackup()
    if type(ZhuraStatsDBBackup) ~= "table" then return end
    if type(ZhuraStatsDBBackup.profiles) ~= "table" then return end
    if type(ZhuraStatsDB) ~= "table" then return end
    if type(ZhuraStatsDB.profiles) ~= "table" then return end

    for profileName, profileData in pairs(ZhuraStatsDBBackup.profiles) do
        if type(profileData) == "table" and ZhuraStatsDB.profiles[profileName] == nil then
            ZhuraStatsDB.profiles[profileName] = Addon.DeepCopy(profileData)
            print("NE Stats: restored profile from backup:", profileName)
        end
    end

    if type(ZhuraStatsDBBackup.profileKeys) == "table" then
        if type(ZhuraStatsDB.profileKeys) ~= "table" then return end
        for charKey, profileName in pairs(ZhuraStatsDBBackup.profileKeys) do
            if ZhuraStatsDB.profileKeys[charKey] == nil then
                ZhuraStatsDB.profileKeys[charKey] = profileName
            end
        end
    end
end

function Addon:ReinitializeDatabase()
    db = nil
    self.db = nil
    self:EnsureDatabase()
end

function Addon:RestoreProfilesFromBackup()
    self:RestoreMissingProfilesFromBackup()
    self:ReinitializeDatabase()
    self:OnProfileStateChanged()
    print("NE Stats: profile restore complete.")
end

function Addon:PrintDatabaseDebug()
    PrintProfileList("ZhuraStatsDB.profiles:", ZhuraStatsDB and ZhuraStatsDB.profiles)
    PrintProfileList("ZhuraStatsDBBackup.profiles:", ZhuraStatsDBBackup and ZhuraStatsDBBackup.profiles)

    print("AceDB profiles:")
    if not db then
        print("-", "<db not initialized>")
        return
    end
    local profileNames = db:GetProfiles()
    if #profileNames == 0 then
        print("-", "<empty>")
    else
        table.sort(profileNames)
        for _, name in ipairs(profileNames) do
            print("-", name)
        end
    end
end

function Addon:GetActiveRootProfile()
    if not db then
        return self.Defaults.profile, "Default"
    end
    local profileName = db:GetCurrentProfile() or "Default"
    return db.profile, profileName
end

function Addon:GetActiveProfile()
    return self:GetActiveRootProfile()
end

function Addon:GetProfile()
    return self:GetActiveRootProfile()
end

function Addon:GetProfileValue(key)
    local profile = self:GetProfile()
    if not profile or not key then
        return nil
    end
    return profile[key]
end

function Addon:SetProfileValue(key, value)
    local profile = self:GetProfile()
    if not profile or not key then
        return
    end
    profile[key] = value
end

function Addon:GetProfileNames()
    local names = {}
    if not db then
        return { "Default" }
    end
    db:GetProfiles(names)
    table.sort(names)
    return names
end

function Addon:SelectRootProfile(profileName)
    if not db or not profileName or profileName == "" then
        return
    end
    local callbackStateBefore = profileStateChangeCounter
    local ok = pcall(function()
        db:SetProfile(profileName)
    end)
    if not ok then
        print(self:S("NE Stats: profile could not be applied."))
        return
    end
    if profileStateChangeCounter == callbackStateBefore then
        self:OnProfileStateChanged()
    end
end

function Addon:CreateProfile(profileName)
    profileName = self:NormalizeProfileName(profileName)
    if not db or profileName == "" then
        return "invalid", nil
    end
    for _, existingName in ipairs(self:GetProfileNames()) do
        if existingName == profileName then
            self:SelectRootProfile(profileName)
            return "exists", profileName
        end
    end
    local callbackStateBefore = profileStateChangeCounter
    local newProfileInitStateBefore = newProfileInitCounter
    local ok = pcall(function()
        db:SetProfile(profileName)
    end)
    if not ok then
        print(self:S("NE Stats: profile could not be created."))
        return "invalid", nil
    end
    if db and db.profile and newProfileInitCounter == newProfileInitStateBefore then
        self:InitializeNewProfile(db.profile)
    end
    if profileStateChangeCounter == callbackStateBefore then
        self:OnProfileStateChanged()
    end
    return "created", profileName
end

function Addon:CopyProfile(sourceProfileName)
    sourceProfileName = self:NormalizeProfileName(sourceProfileName)
    if not db or sourceProfileName == "" then
        return false
    end

    local callbackStateBefore = profileStateChangeCounter
    local ok = pcall(function()
        db:CopyProfile(sourceProfileName)
    end)
    if not ok then
        return false
    end

    if profileStateChangeCounter == callbackStateBefore then
        self:OnProfileStateChanged()
    end
    return true
end

-- AceDB-3.0 does not expose a safe public profile rename API.
-- Keep this custom flow isolated from normal Set/Copy/Reset/Delete methods.
function Addon:LegacyRenameProfile(oldName, newName)
    oldName = self:NormalizeProfileName(oldName)
    newName = self:NormalizeProfileName(newName)
    if not db or not self:CanModifyProfile(oldName) or newName == "" then
        return "invalid", nil
    end
    if oldName == newName then
        self:SelectRootProfile(oldName)
        return "exists", oldName
    end
    for _, existingName in ipairs(self:GetProfileNames()) do
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
        profiles[newName] = self.DeepCopy(source)
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
    end, function(message) return tostring(message) end)
    if not ok then
        return "invalid", err
    end
    self:OnProfileStateChanged()
    return "renamed", newName
end

function Addon:RenameProfile(oldName, newName)
    return self:LegacyRenameProfile(oldName, newName)
end

function Addon:DeleteProfile(profileName)
    profileName = self:NormalizeProfileName(profileName)
    if not db or not self:CanModifyProfile(profileName) then
        return false
    end
    local activeProfileName = db:GetCurrentProfile()
    if activeProfileName == profileName then
        return false
    end
    local callbackStateBefore = profileStateChangeCounter
    local ok = pcall(function()
        db:DeleteProfile(profileName)
    end)
    if not ok then
        return false
    end
    if profileStateChangeCounter == callbackStateBefore then
        self:OnProfileStateChanged()
    end
    return true
end

function Addon:ResetActiveProfile()
    if not db then
        return
    end
    local callbackStateBefore = profileStateChangeCounter
    db:ResetProfile()
    if profileStateChangeCounter == callbackStateBefore then
        self:OnProfileStateChanged()
    end
end

function Addon:ApplyCurrentProfileState()
    if self.ApplyCurrentProfileStateImpl then
        self:ApplyCurrentProfileStateImpl()
    end
end

function Addon:OnProfileStateChanged()
    self:ApplyCurrentProfileState()
    if self.RefreshOptions then
        self:RefreshOptions()
    elseif self.RefreshOptionRows then
        self:RefreshOptionRows()
    end
end

function Addon:HandleAceDBProfileStateChanged()
    profileStateChangeCounter = profileStateChangeCounter + 1
    self:OnProfileStateChanged()
end

function Addon:HandleAceDBNewProfile()
    newProfileInitCounter = newProfileInitCounter + 1
    if db and db.profile then
        self:InitializeNewProfile(db.profile)
    end
    self:HandleAceDBProfileStateChanged()
end
