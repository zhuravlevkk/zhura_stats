local _, ns = ...

ns = ns or {}
ns.ZhuraStats = ns.ZhuraStats or {}
local Addon = ns.ZhuraStats

ZhuraStatsDB = ZhuraStatsDB or {}

local AceDB = LibStub and LibStub("AceDB-3.0", true)
local db

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

function Addon:MigrateProfile(profile)
    local defaults = self.Defaults.profile
    local statDefinitions = self.StatDefinitions
    local defaultStatsByKey = self.DefaultStatsByKey
    local statKeys = self.Constants.STAT_KEYS

    if not profile.stats then
        profile.stats = self.DeepCopy(defaults.stats)
    end

    local byKey = {}
    for _, entry in ipairs(profile.stats) do
        if type(entry) == "string" and statDefinitions[entry] then
            byKey[entry] = { key = entry, enabled = true, color = self.DeepCopy(statDefinitions[entry].color) }
        elseif type(entry) == "table" and entry.key and statDefinitions[entry.key] then
            byKey[entry.key] = entry
        end
    end

    local migrated, seen = {}, {}
    for _, entry in ipairs(profile.stats) do
        local key = type(entry) == "table" and entry.key or entry
        if key and byKey[key] and not seen[key] then
            local normalized = byKey[key]
            normalized.enabled = normalized.enabled ~= false
            normalized.color = normalized.color or self.DeepCopy(statDefinitions[key].color)
            table.insert(migrated, normalized)
            seen[key] = true
        end
    end

    for _, key in ipairs(statKeys) do
        if not seen[key] then
            local entry = byKey[key]
            if entry then
                entry.enabled = entry.enabled ~= false
                entry.color = entry.color or self.DeepCopy(statDefinitions[key].color)
                table.insert(migrated, entry)
            else
                local defaultEntry = defaultStatsByKey[key]
                table.insert(migrated, {
                    key = key,
                    enabled = defaultEntry and defaultEntry.enabled or false,
                    color = self.DeepCopy(statDefinitions[key].color),
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
    profile.percentPrecision = profile.percentPrecision or profile.decimalPrecision or defaults.percentPrecision
    if profile.drDisplayMode == nil then
        if profile.showDiminishingReturns == true then
            profile.drDisplayMode = "suffix"
        else
            profile.drDisplayMode = defaults.drDisplayMode
        end
    end
    if profile.drDisplayMode ~= "off" and profile.drDisplayMode ~= "suffix" then
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
end

function Addon:EnsureDatabase()
    if not AceDB then
        return
    end
    local aceDefaults = self.Defaults.ace
    if type(ZhuraStatsDB) ~= "table" or not ZhuraStatsDB.profileKeys or ZhuraStatsDB.characters or ZhuraStatsDB.accountProfilesMigrated then
        ZhuraStatsDB = nil
    end
    if not db then
        db = AceDB:New("ZhuraStatsDB", aceDefaults, "Default")
        self.db = db
    end
    db.global.addonLocale = db.global.addonLocale or self.Constants.CLIENT_LANGUAGE_VALUE
    self:ApplyLocale()
    self:MigrateProfile(db.profile)
end

function Addon:GetActiveRootProfile()
    if not db then
        return self.Defaults.profile, "Default"
    end
    local profileName = db:GetCurrentProfile() or "Default"
    self:MigrateProfile(db.profile)
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
    local ok = pcall(function()
        db:SetProfile(profileName)
        self:MigrateProfile(db.profile)
    end)
    if not ok then
        print(self:S("NE Stats: profile could not be applied."))
        return
    end
    self:ApplyCurrentProfileState()
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
    local sourceProfileName = db:GetCurrentProfile()
    local ok = pcall(function()
        db:SetProfile(profileName)
        if sourceProfileName and sourceProfileName ~= profileName then
            db:CopyProfile(sourceProfileName, true)
        end
        self:MigrateProfile(db.profile)
    end)
    if not ok then
        print(self:S("NE Stats: profile could not be created."))
        return "invalid", nil
    end
    self:ApplyCurrentProfileState()
    return "created", profileName
end

function Addon:RenameProfile(oldName, newName)
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
        self:MigrateProfile(db.profile)
    end, function(message) return tostring(message) end)
    if not ok then
        return "invalid", err
    end
    self:ApplyCurrentProfileState()
    return "renamed", newName
end

function Addon:DeleteProfile(profileName)
    profileName = self:NormalizeProfileName(profileName)
    if not db or not self:CanModifyProfile(profileName) then
        return false
    end
    local ok = pcall(function()
        db:SetProfile("Default")
        self:MigrateProfile(db.profile)
        db:DeleteProfile(profileName, true)
    end)
    if not ok then
        return false
    end
    self:ApplyCurrentProfileState()
    return true
end

function Addon:ResetActiveProfile()
    if not db then
        return
    end
    db:ResetProfile()
    self:MigrateProfile(db.profile)
end

function Addon:ApplyCurrentProfileState()
    if self.ApplyCurrentProfileStateImpl then
        self:ApplyCurrentProfileStateImpl()
    end
end
