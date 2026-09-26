local ADDON_NAME, ns = ...

ns = ns or {}
ns.ZhuraStats = ns.ZhuraStats or {}

local Addon = ns.ZhuraStats
Addon.name = Addon.name or ADDON_NAME
local debugProfileStop = _G.debugprofilestop

local addonFrame = CreateFrame("Frame")

local restrictedRefreshTicker = nil
local pendingRefresh = {
    values = false,
    layout = false,
    full = false,
    options = false,
    statKeys = {},
    reasons = {},
}
local refreshScheduleGeneration = 0
local refreshScheduled = false
local refreshProfile = {
    enabled = false,
    requests = 0,
    actual = 0,
    coalesced = 0,
    operations = {},
    lastReasons = {},
}

local function ResetRefreshProfile()
    refreshProfile.requests = 0
    refreshProfile.actual = 0
    refreshProfile.coalesced = 0
    wipe(refreshProfile.operations)
    wipe(refreshProfile.lastReasons)
end

function Addon:IsRefreshProfilingEnabled()
    return refreshProfile.enabled
end

function Addon:ProfileRefreshOperation(name, callback)
    if not refreshProfile.enabled or not debugProfileStop then
        return callback()
    end
    local startedAt = debugProfileStop()
    local results = { callback() }
    local elapsed = debugProfileStop() - startedAt
    local metric = refreshProfile.operations[name]
    if not metric then
        metric = { calls = 0, total = 0, max = 0 }
        refreshProfile.operations[name] = metric
    end
    metric.calls = metric.calls + 1
    metric.total = metric.total + elapsed
    metric.max = math.max(metric.max, elapsed)
    return unpack(results)
end

local function PrintRefreshProfileReport()
    print("NE Stats refresh profile")
    print(string.format("Refresh requests: %d", refreshProfile.requests))
    print(string.format("Actual refreshes: %d", refreshProfile.actual))
    print(string.format("Coalesced: %d", refreshProfile.coalesced))
    local names = {}
    for name in pairs(refreshProfile.operations) do
        table.insert(names, name)
    end
    table.sort(names)
    for _, name in ipairs(names) do
        local metric = refreshProfile.operations[name]
        print(string.format("%s: calls=%d avg=%.3f ms max=%.3f ms",
            name, metric.calls, metric.calls > 0 and metric.total / metric.calls or 0, metric.max))
    end
    if next(refreshProfile.lastReasons) then
        local reasons = {}
        for reason, count in pairs(refreshProfile.lastReasons) do
            table.insert(reasons, string.format("%s x%d", reason, count))
        end
        table.sort(reasons)
        print("Last refresh: " .. table.concat(reasons, ", "))
    end
end

local function FlushPendingRefresh()
    refreshScheduled = false
    if not Addon.initialized then
        return
    end

    local doFull = pendingRefresh.full
    local doLayout = pendingRefresh.layout
    local doValues = pendingRefresh.values
    local doOptions = pendingRefresh.options
    local statKeys = pendingRefresh.statKeys
    local reasons = pendingRefresh.reasons
    pendingRefresh.values = false
    pendingRefresh.layout = false
    pendingRefresh.full = false
    pendingRefresh.options = false
    pendingRefresh.statKeys = {}
    pendingRefresh.reasons = {}

    refreshProfile.actual = refreshProfile.actual + 1
    refreshProfile.lastReasons = reasons
    if doFull then
        Addon:FullRebuild()
    elseif doLayout then
        Addon:RebuildLayout()
    elseif doValues then
        if next(statKeys) and not statKeys.__all then
            Addon:RefreshStatsValues(statKeys)
        else
            Addon:RefreshStatsValues()
        end
    end

    if doOptions then
        local refs = Addon:GetControlRefs()
        if refs and refs.scrollFrame and refs.scrollFrame:IsShown() then
            Addon:RefreshOptionRows()
        end
    end
end

function Addon:RequestRefresh(reason, flags)
    flags = flags or { values = true }
    refreshProfile.requests = refreshProfile.requests + 1
    if refreshScheduled then
        refreshProfile.coalesced = refreshProfile.coalesced + 1
    end
    pendingRefresh.values = pendingRefresh.values or flags.values == true or flags.layout == true or flags.full == true
    pendingRefresh.layout = pendingRefresh.layout or flags.layout == true or flags.full == true
    pendingRefresh.full = pendingRefresh.full or flags.full == true
    pendingRefresh.options = pendingRefresh.options or flags.options == true
    if flags.statKey then
        pendingRefresh.statKeys[flags.statKey] = true
    else
        pendingRefresh.statKeys.__all = true
    end
    reason = tostring(reason or "unknown")
    pendingRefresh.reasons[reason] = (pendingRefresh.reasons[reason] or 0) + 1

    local delay = math.max(0, tonumber(flags.delay) or 0)
    refreshScheduleGeneration = refreshScheduleGeneration + 1
    local generation = refreshScheduleGeneration
    refreshScheduled = true
    if C_Timer and C_Timer.After then
        C_Timer.After(delay, function()
            if generation == refreshScheduleGeneration then
                FlushPendingRefresh()
            end
        end)
    else
        FlushPendingRefresh()
    end
end

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

function Addon:IsRestrictedRefreshContext()
    return InRestrictedZone()
end

local function StartRestrictedRefresh()
    if not InRestrictedZone() or restrictedRefreshTicker or not (C_Timer and C_Timer.NewTicker) then
        return
    end
    Addon:StopCombatStatRefresh()
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
                Addon:RequestRefresh("RESTRICTED_CONTEXT_ENDED", { values = true })
            end
            return
        end
        if Addon.initialized then
            Addon:RequestRefresh("RESTRICTED_TICKER", { values = true })
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
    if firstToken == "profile" then
        local sub = string.lower(strtrim(rest or ""))
        if sub == "on" then
            refreshProfile.enabled = true
            print("NE Stats refresh profiling: ON")
        elseif sub == "off" then
            refreshProfile.enabled = false
            print("NE Stats refresh profiling: OFF")
        elseif sub == "reset" then
            ResetRefreshProfile()
            print("NE Stats refresh profile reset")
        elseif sub == "report" then
            PrintRefreshProfileReport()
        else
            print("/zhs profile on|off|reset|report")
        end
        return
    end
    if firstToken == "ref" then
        local sub = string.lower(strtrim(rest or ""))
        if sub == "manual" then
            Addon:SetStatPriorityMode("manual")
            print(Addon:S("NE_STATS_SLASH_REF_PRIORITY", Addon:S("NE_STATS_MODE_MANUAL")))
            Addon:RequestRefresh("SLASH_REF_MANUAL", { layout = true })
            return
        end
        if sub == "raid" then
            Addon:SetStatPriorityMode("archon_raid")
            print(Addon:S("NE_STATS_SLASH_REF_PRIORITY", Addon:S("NE_STATS_MODE_RAID")))
            Addon:RequestRefresh("SLASH_REF_RAID", { layout = true })
            return
        end
        if sub == "mythic" or sub == "mplus" or sub == "m+" then
            Addon:SetStatPriorityMode("archon_mplus")
            print(Addon:S("NE_STATS_SLASH_REF_PRIORITY", Addon:S("NE_STATS_MODE_MPLUS")))
            Addon:RequestRefresh("SLASH_REF_MPLUS", { layout = true })
            return
        end
        if sub == "off" then
            Addon:SetProfileValue("referenceDisplay", "off")
            print(Addon:S("NE_STATS_SLASH_REF_DISPLAY", sub))
            Addon:RequestRefresh("SLASH_REF_OFF", { layout = true })
            return
        end
        if sub == "inline" or sub == "delta" or sub == "tooltip" then
            Addon:SetProfileValue("referenceDisplay", sub)
            print(Addon:S("NE_STATS_SLASH_REF_DISPLAY", sub))
            Addon:RequestRefresh("SLASH_REF_DISPLAY", { layout = true })
            return
        end
        print(Addon:S("NE_STATS_SLASH_REF_USAGE"))
        return
    end
    if command == "reset" then
        Addon:ResetActiveProfile()
        print(Addon:S("NE_STATS_PROFILE_RESET"))
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
    self:FullRebuild()
end

local function OnEvent(_, event, arg1, ...)
    if event == "ADDON_RESTRICTION_STATE_CHANGED" then
        local restrictionType = arg1
        local restrictionState = select(2, ...)

        if restrictionType == 2 then
            if restrictionState == 0 then
                Addon:RequestRefresh("ADDON_RESTRICTION_STATE_CHANGED", { values = true, delay = 0.05 })
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
        elseif InCombatLockdown and InCombatLockdown() then
            Addon:StartCombatStatRefresh()
        end
        Addon:EnsureStatsFrame()
        Addon:RequestRefresh(event, { layout = true, delay = 0.15 })
        return
    end

    if event == "CHALLENGE_MODE_START" then
        -- Entering a M+ key: stats are Secret for the whole run. Keep the
        -- snapshot display refreshing even between pulls.
        StartRestrictedRefresh()
        Addon:RequestRefresh(event, { values = true })
        return
    end

    if event == "CHALLENGE_MODE_COMPLETED" then
        StopRestrictedRefresh()
        Addon:RequestRefresh(event, { values = true, delay = 0.05 })
        return
    end

    if event == "PLAYER_REGEN_DISABLED" then
        if InRestrictedZone() then
            StartRestrictedRefresh()
        else
            Addon:StartCombatStatRefresh()
        end
        Addon:RequestRefresh(event, { values = true })
        return
    end

    if event == "PLAYER_REGEN_ENABLED" then
        StopRestrictedRefresh()
        Addon:StopCombatStatRefresh()
        local refs = Addon:GetControlRefs()
        if Addon.pendingOptionRowsAfterCombat and refs and refs.scrollFrame and refs.scrollFrame:IsShown() then
            Addon:RefreshOptionRows()
        end
        Addon:RequestRefresh(event, { values = true })
        return
    end

    if event == "UNIT_AURA" and arg1 == "player" then
        Addon:RequestRefresh(event, { values = true, delay = 0.05 })
        return
    end

    if event == "UNIT_SPELLCAST_SUCCEEDED" and arg1 == "player" then
        Addon:RequestRefresh(event, { values = true, delay = 0.075 })
        return
    end

    if event == "COMBAT_RATING_UPDATE" or (event == "UNIT_STATS" and arg1 == "player") or event == "MASTERY_UPDATE" then
        Addon:RequestRefresh(event, { values = true })
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


    if event == "PLAYER_MONEY" then
        if Addon:IsStatRendered("GOLD") then
            Addon:RequestRefresh(event, { values = true, statKey = "GOLD" })
        end
        return
    end
    if event == "UPDATE_INVENTORY_DURABILITY" then
        if Addon:IsStatRendered("DURABILITY") then
            Addon:RequestRefresh(event, { values = true, statKey = "DURABILITY" })
        end
        return
    end
    if event == "PLAYER_STARTED_MOVING" or event == "PLAYER_STOPPED_MOVING" then
        if Addon:IsStatRendered("SPEED") then
            Addon:RequestRefresh(event, { values = true, statKey = "SPEED" })
        end
        return
    end

    if event == "PLAYER_EQUIPMENT_CHANGED"
        or event == "UNIT_INVENTORY_CHANGED" then
        Addon:RequestRefresh(event, { values = true, options = true, delay = 0.075 })
        return
    end

    if event == "TRAIT_CONFIG_UPDATED"
        or event == "ACTIVE_TALENT_GROUP_CHANGED"
        or event == "PLAYER_SPECIALIZATION_CHANGED" then
        Addon:RequestRefresh(event, { layout = true, options = true, delay = 0.075 })
        return
    end

    Addon:RequestRefresh(event, { values = true, options = true })
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
