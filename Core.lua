local ADDON_NAME, ns = ...

ns = ns or {}
ns.ZhuraStats = ns.ZhuraStats or {}

local Addon = ns.ZhuraStats
Addon.name = Addon.name or ADDON_NAME

local addonFrame = CreateFrame("Frame")

local restrictedRefreshTicker = nil

-- True when the player is in a context where stat APIs return Secret values
-- the whole time (Mythic+ / challenge mode), not just while in combat. In
-- those zones live values never become readable, so we keep a low-frequency
-- ticker running to refresh the snapshot display even out of combat.
local function InRestrictedZone()
    if C_ChallengeMode and C_ChallengeMode.IsChallengeModeActive then
        local ok, active = pcall(C_ChallengeMode.IsChallengeModeActive)
        if ok and active then
            return true
        end
    end
    return false
end

local function StartRestrictedRefresh()
    if restrictedRefreshTicker or not (C_Timer and C_Timer.NewTicker) then
        return
    end
    -- 0.5s is plenty: in a restricted zone we're only re-rendering the
    -- persisted snapshot, which changes rarely. No CLEU, no per-frame polling.
    restrictedRefreshTicker = C_Timer.NewTicker(0.5, function()
        if not InRestrictedZone() and not (InCombatLockdown and InCombatLockdown()) then
            -- Left the restricted context and out of combat: stop and do a
            -- final refresh to pick up now-readable live values.
            if restrictedRefreshTicker then
                restrictedRefreshTicker:Cancel()
                restrictedRefreshTicker = nil
            end
            if Addon.initialized then
                Addon:RefreshStats()
            end
            return
        end
        if Addon.initialized then
            Addon:RefreshStats()
        end
    end)
end

local function StopRestrictedRefresh()
    -- Only stop if we're genuinely out of any restricted context. Inside M+
    -- the ticker must survive leaving combat between pulls.
    if InRestrictedZone() then
        return
    end
    if restrictedRefreshTicker then
        restrictedRefreshTicker:Cancel()
        restrictedRefreshTicker = nil
    end
end

local function EnsureDatabaseBackup()
    ZhuraStatsDBBackup = ZhuraStatsDBBackup or Addon.DeepCopy(ZhuraStatsDB)
end

local function SlashHandler(message)
    local raw = strtrim(message or "")
    local command = string.lower(raw)
    local firstToken, rest = command:match("^(%S+)%s*(.*)$")
    if firstToken == "ref" then
        local sub = string.lower(strtrim(rest or ""))
        if sub == "manual" then
            Addon:SetStatPriorityMode("manual")
            print(Addon:S("NE_STATS_SLASH_REF_PRIORITY", Addon:S("NE_STATS_MODE_MANUAL")))
            Addon:RefreshStats()
            return
        end
        if sub == "raid" then
            Addon:SetStatPriorityMode("archon_raid")
            print(Addon:S("NE_STATS_SLASH_REF_PRIORITY", Addon:S("NE_STATS_MODE_RAID")))
            Addon:RefreshStats()
            return
        end
        if sub == "mythic" or sub == "mplus" or sub == "m+" then
            Addon:SetStatPriorityMode("archon_mplus")
            print(Addon:S("NE_STATS_SLASH_REF_PRIORITY", Addon:S("NE_STATS_MODE_MPLUS")))
            Addon:RefreshStats()
            return
        end
        if sub == "off" then
            Addon:SetProfileValue("referenceDisplay", "off")
            print(Addon:S("NE_STATS_SLASH_REF_DISPLAY", sub))
            Addon:RefreshStats()
            return
        end
        if sub == "inline" or sub == "delta" or sub == "tooltip" then
            Addon:SetProfileValue("referenceDisplay", sub)
            print(Addon:S("NE_STATS_SLASH_REF_DISPLAY", sub))
            Addon:RefreshStats()
            return
        end
        print(Addon:S("NE_STATS_SLASH_REF_USAGE"))
        return
    end
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
        if InRestrictedZone() then
            StartRestrictedRefresh()
        end
        if InCombatLockdown and InCombatLockdown() then
            Addon:StartCombatStatRefresh()
        end
        Addon:RefreshStats()
        return
    end

    if event == "CHALLENGE_MODE_START" then
        -- Entering a M+ key: stats are Secret for the whole run. Keep the
        -- snapshot display refreshing even between pulls.
        StartRestrictedRefresh()
        Addon:RefreshStats()
        return
    end

    if event == "CHALLENGE_MODE_COMPLETED" then
        StopRestrictedRefresh()
        Addon:RefreshStats()
        return
    end

    if event == "PLAYER_REGEN_DISABLED" then
        StartRestrictedRefresh()
        Addon:StartCombatStatRefresh()
        Addon:RefreshStats()
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        StopRestrictedRefresh()
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

    -- Some events fire before the engine finishes recomputing derived stats
    -- (gear swaps, gems/enchants, talent/spec changes). A same-frame read sees
    -- the old values, which looked like "lag". Schedule one follow-up read on
    -- the next frame so the snapshot reflects the new values immediately.
    if event == "PLAYER_EQUIPMENT_CHANGED"
        or event == "UNIT_INVENTORY_CHANGED"
        or event == "TRAIT_CONFIG_UPDATED"
        or event == "ACTIVE_TALENT_GROUP_CHANGED"
        or event == "PLAYER_SPECIALIZATION_CHANGED" then
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if Addon.initialized then
                    Addon:RefreshStats()
                end
            end)
        end
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
    addonFrame:RegisterEvent("CHALLENGE_MODE_START")
    addonFrame:RegisterEvent("CHALLENGE_MODE_COMPLETED")
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
