local _, ns = ...

ns = ns or {}
ns.ZhuraStats = ns.ZhuraStats or {}
local Addon = ns.ZhuraStats

-- Maps addon stat keys to WoWLogsStatsPrio secondary[].stat names (lowercase in data file).
local STAT_KEY_TO_ARCHON_STAT = {
    HASTE = "haste",
    CRIT = "crit",
    MASTERY = "mastery",
    VERS = "versatility",
}

local REFERENCE_SECONDARY_KEYS = {
    HASTE = true,
    CRIT = true,
    MASTERY = true,
    VERS = true,
}

function Addon:IsArchonReferenceStatKey(statKey)
    return REFERENCE_SECONDARY_KEYS[statKey] == true
end

-- True when DR display is on and the stat has an active DR penalty.
function Addon:HasActiveDiminishingReturns(profile, statResult)
    local defaults = self.Defaults and self.Defaults.profile
    profile = profile or {}
    local drMode = profile.drDisplayMode or (defaults and defaults.drDisplayMode) or "off"
    return drMode ~= "off"
        and statResult and statResult.dr
        and (statResult.dr.penalty or 0) > 0
end

function Addon:IsReferenceDisplayEnabled(profile)
    local defaults = self.Defaults and self.Defaults.profile
    profile = profile or {}
    local display = profile.referenceDisplay or (defaults and defaults.referenceDisplay) or "off"
    return display ~= "off"
end

-- On-screen ref segments (inline / delta) are hidden while DR is active.
function Addon:ShouldShowReferenceOnRow(statKey, statResult, profile)
    if not self:IsArchonReferenceStatKey(statKey) then
        return false
    end
    if not self:IsReferenceDisplayEnabled(profile) then
        return false
    end
    local defaults = self.Defaults and self.Defaults.profile
    profile = profile or {}
    local display = profile.referenceDisplay or (defaults and defaults.referenceDisplay) or "off"
    if display == "tooltip" then
        return false
    end
    if self:NormalizeStatPriorityMode(profile.statPriorityMode or (defaults and defaults.statPriorityMode) or "manual") == "manual" then
        return false
    end
    if self:HasActiveDiminishingReturns(profile, statResult) then
        return false
    end
    return self:GetArchonStatReferencePayload(statKey, profile) ~= nil
end

-- Tooltip on row hover: tooltip-only mode, or DR hiding on-screen reference.
function Addon:WantsReferenceTooltip(statKey, statResult, profile)
    if not self:IsArchonReferenceStatKey(statKey) then
        return false
    end
    if not self:IsReferenceDisplayEnabled(profile) then
        return false
    end
    local defaults = self.Defaults and self.Defaults.profile
    profile = profile or {}
    if self:NormalizeStatPriorityMode(profile.statPriorityMode or (defaults and defaults.statPriorityMode) or "manual") == "manual" then
        return false
    end
    if not self:GetArchonStatReferencePayload(statKey, profile) then
        return false
    end
    local display = profile.referenceDisplay or (defaults and defaults.referenceDisplay) or "off"
    if display == "tooltip" then
        return true
    end
    return self:HasActiveDiminishingReturns(profile, statResult)
end

-- Returns Archon-generated reference for one secondary stat, or nil if unavailable.
-- Uses only WoWLogsStatsPrio fields: secondary[].stat, secondary[].rating, plus root updated/activity.
function Addon:GetArchonStatReferencePayload(statKey, profile)
    if not self:IsArchonReferenceStatKey(statKey) then
        return nil
    end
    local defaults = self.Defaults and self.Defaults.profile
    profile = profile or (self.GetProfile and self:GetProfile()) or {}
    local mode = self:NormalizeStatPriorityMode(profile.statPriorityMode or (defaults and defaults.statPriorityMode) or "manual")
    if mode == "manual" then
        return nil
    end
    local want = STAT_KEY_TO_ARCHON_STAT[statKey]
    if not want then
        return nil
    end
    local data = select(1, self:GetArchonDataForMode(mode))
    if type(data) ~= "table" or type(data.secondary) ~= "table" then
        return nil
    end
    for _, row in ipairs(data.secondary) do
        if type(row) == "table" and type(row.stat) == "string" then
            local s = string.lower(row.stat)
            if s == "vers" then
                s = "versatility"
            end
            if s == want then
                local r = tonumber(row.rating)
                if r and r >= 0 then
                    return {
                        archonRating = math.floor(r + 0.5),
                        updated = type(data.updated) == "string" and data.updated or "",
                        activity = type(data.activity) == "string" and data.activity or "",
                    }
                end
            end
        end
    end
    return nil
end

-- Optional short DR marker for reference suffix; uses only statResult.dr (no invented thresholds).
function Addon:GetDRHint(statKey, percent, statResult)
    if not statResult or not statResult.dr then
        return nil
    end
    local penalty = statResult.dr.penalty or 0
    local loss = statResult.dr.loss or 0
    if penalty <= 0 and loss <= 0 then
        return nil
    end
    return " " .. self:S("NE_STATS_REFERENCE_DR_TAG")
end
