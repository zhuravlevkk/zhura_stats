local ADDON_NAME, ns = ...

ns = ns or {}
ns.ZhuraStats = ns.ZhuraStats or {}

local Addon = ns.ZhuraStats
Addon.name = Addon.name or ADDON_NAME

local addonFrame = CreateFrame("Frame")

local combatLogTicker = nil

local function StartCombatLogPolling()
    if combatLogTicker then return end
    combatLogTicker = C_Timer.NewTicker(0.1, function()
        local Stats = ns.Stats
        if Stats and Stats.HandleCombatLogEvent then
            Stats.HandleCombatLogEvent()
        end
        if Addon.initialized then
            Addon:RefreshStats()
        end
    end)
end

local function StopCombatLogPolling()
    if combatLogTicker then
        combatLogTicker:Cancel()
        combatLogTicker = nil
    end
end

local function EnsureDatabaseBackup()
    ZhuraStatsDBBackup = ZhuraStatsDBBackup or Addon.DeepCopy(ZhuraStatsDB)
end

local function SlashHandler(message)
    local command = string.lower(strtrim(message or ""))
    if command == "reset" then
        Addon:ResetActiveProfile()
        print(Addon:S("NE Stats: active profile reset."))
        return
    end

    if command == "restoreprofiles" then
        Addon:RestoreProfilesFromBackup()
        return
    end

    if command == "db" then
        Addon:PrintDatabaseDebug()
        return
    end

    if command == "lock" then
        if not Addon:GetProfileValue("locked") then
            Addon:ToggleLockState()
        end
        return
    end

    if command == "unlock" then
        if Addon:GetProfileValue("locked") then
            Addon:ToggleLockState()
        end
        return
    end

    Addon:OpenAddonSettings()
end

SLASH_ZHURASTATS1 = "/zhs"
SLASH_ZHURASTATS2 = "/zhurastats"
SlashCmdList.ZHURASTATS = SlashHandler

function Addon:Initialize()
    if self.initialized then
        return
    end

    self.initialized = true
    EnsureDatabaseBackup()
    self:EnsureDatabase()
    self:ApplyLocale()
    self:EnsureFormatBindings()
    self:InitializePopups()
    self:EnsureStatsFrame()
    self:ApplyFrameStyle()
    self:RefreshStats()
end

local function OnEvent(_, event, arg1, ...)
    local Stats = ns.Stats

    if event == "ADDON_RESTRICTION_STATE_CHANGED" then
        local restrictionType = arg1
        local restrictionState = select(2, ...)

        if restrictionType == 2 then
            if restrictionState == 0 then
                C_Timer.After(0.05, function()
                    if Addon.initialized then
                        Addon:RefreshStats()
                    end
                end)
            end
        end
        return
    end

    if event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if Stats and Stats.HandleCombatLogEvent then
            Stats.HandleCombatLogEvent()
        end
        if Addon.initialized then
            Addon:RefreshStats()
        end
        return
    end

    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        EnsureDatabaseBackup()
        Addon:EnsureDatabase()
        Addon:ApplyLocale()
        Addon:EnsureFormatBindings()
        return
    end

    if event == "PLAYER_LOGIN" then
        Addon:Initialize()
        Addon:SafeBuildOptionsPanel()
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        if InCombatLockdown and InCombatLockdown() then
            Addon:StartCombatStatRefresh()
        end
        Addon:RefreshStats()
        return
    end

    if event == "PLAYER_REGEN_DISABLED" then
        StartCombatLogPolling()
        Addon:StartCombatStatRefresh()
        Addon:RefreshStats()
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        StopCombatLogPolling()
        Addon:StopCombatStatRefresh()
        local refs = Addon:GetControlRefs()
        if Addon.pendingOptionRowsAfterCombat and refs and refs.scrollFrame and refs.scrollFrame:IsShown() then
            Addon:RefreshOptionRows()
        end
        Addon:RefreshStats()
        return
    end

    if event == "COMBAT_RATING_UPDATE"
        or (event == "UNIT_AURA" and arg1 == "player")
        or (event == "UNIT_STATS" and arg1 == "player") then
        Addon:RefreshStats()
        return
    end

    if (event == "UNIT_AURA" or event == "UNIT_STATS" or event == "UNIT_INVENTORY_CHANGED" or event == "UNIT_SPELLCAST_SUCCEEDED"
        or event == "UNIT_ENTERED_VEHICLE" or event == "UNIT_EXITED_VEHICLE")
        and arg1 ~= "player" then
        return
    end

    if event == "UNIT_AURA" and Stats and Stats.RefreshPotionState then
        Stats.RefreshPotionState()
    end

    if event == "TRAIT_CONFIG_UPDATED"
        and arg1
        and tostring(arg1) ~= tostring(C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_ClassTalents.GetActiveConfigID() or "") then
        return
    end


    Addon:RefreshStats()
    local refs = Addon:GetControlRefs()
    if refs and refs.scrollFrame and refs.scrollFrame:IsShown() then
        Addon:RefreshOptionRows()
    end
end

local function RegisterAllEvents()
    addonFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
    addonFrame:RegisterEvent("COMBAT_RATING_UPDATE")
    if addonFrame.RegisterUnitEvent then
        addonFrame:RegisterUnitEvent("UNIT_STATS", "player")
        addonFrame:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
        addonFrame:RegisterUnitEvent("UNIT_AURA", "player")
        addonFrame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    else
        addonFrame:RegisterEvent("UNIT_STATS")
        addonFrame:RegisterEvent("UNIT_INVENTORY_CHANGED")
        addonFrame:RegisterEvent("UNIT_AURA")
        addonFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    end
    addonFrame:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
    addonFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
    addonFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
    addonFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    addonFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    addonFrame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
    addonFrame:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    addonFrame:RegisterEvent("PLAYER_MONEY")
    addonFrame:RegisterEvent("UPDATE_INVENTORY_DURABILITY")
    addonFrame:RegisterEvent("MASTERY_UPDATE")
    addonFrame:RegisterEvent("PLAYER_LEVEL_UP")
    addonFrame:RegisterEvent("PLAYER_STARTED_MOVING")
    addonFrame:RegisterEvent("PLAYER_STOPPED_MOVING")
    addonFrame:RegisterEvent("PLAYER_MOUNT_DISPLAY_CHANGED")
    addonFrame:RegisterEvent("UPDATE_SHAPESHIFT_FORM")
    if addonFrame.RegisterUnitEvent then
        addonFrame:RegisterUnitEvent("UNIT_ENTERED_VEHICLE", "player")
        addonFrame:RegisterUnitEvent("UNIT_EXITED_VEHICLE", "player")
    else
        addonFrame:RegisterEvent("UNIT_ENTERED_VEHICLE")
        addonFrame:RegisterEvent("UNIT_EXITED_VEHICLE")
    end
end

local eventsRegistered = false

local function BootstrapOnEvent(self, event, arg1, ...)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME and not eventsRegistered then
        eventsRegistered = true
        RegisterAllEvents()
    end
    OnEvent(self, event, arg1, ...)
end

addonFrame:RegisterEvent("ADDON_LOADED")
addonFrame:RegisterEvent("PLAYER_LOGIN")
addonFrame:SetScript("OnEvent", BootstrapOnEvent)
