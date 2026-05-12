local _, ns = ...

ns = ns or {}
ns.ZhuraStats = ns.ZhuraStats or {}
local Addon = ns.ZhuraStats

local function FormatGoldValue(value, profile, defaults)
    local rounded = math.floor((value or 0) + 0.5)
    if not profile.goldUseSeparator then
        return tostring(rounded)
    end

    local separator = profile.goldSeparator or defaults.goldSeparator or " "
    local digits = tostring(rounded)
    local sign = ""
    if string.sub(digits, 1, 1) == "-" then
        sign = "-"
        digits = string.sub(digits, 2)
    end

    local chunks = {}
    while string.len(digits) > 3 do
        table.insert(chunks, 1, string.sub(digits, -3))
        digits = string.sub(digits, 1, -4)
    end
    table.insert(chunks, 1, digits)
    return sign .. table.concat(chunks, separator)
end

function Addon:FormatValue(entry, value)
    local defaults = self.Defaults.profile
    local precision = math.max(0, math.min(3, self:GetProfileValue("percentPrecision") or defaults.percentPrecision))
    if entry.suffix == "%" then
        if self:GetProfileValue("showPercent") then
            return string.format("%." .. precision .. "f%%", value)
        end
        return string.format("%." .. precision .. "f", value)
    end

    if value == math.floor(value) then
        return tostring(math.floor(value))
    end

    return string.format("%.2f", value)
end

function Addon:FormatDiminishingReturns(statResult, mode)
    if not statResult or not statResult.dr then
        return ""
    end

    local dr = statResult.dr
    local penalty = dr.penalty or 0
    local loss = math.floor((dr.loss or 0) + 0.5)

    if penalty <= 0 and loss <= 0 then
        return ""
    end

    if mode == "penalty" then
        return string.format(" (DR -%d%%)", penalty)
    elseif mode == "loss" then
        return string.format(" (-%d)", loss)
    elseif mode == "full" then
        return string.format(" (DR -%d%%, -%d)", penalty, loss)
    end

    return ""
end

function Addon:GetDRColor(baseColor, drPenalty)
    local r, g, b = baseColor[1], baseColor[2], baseColor[3]
    if not drPenalty or drPenalty <= 0 then
        return r, g, b
    end

    local warnR, warnG, warnB
    if drPenalty >= 50 then
        warnR, warnG, warnB = 0.9, 0.2, 0.2
    elseif drPenalty >= 40 then
        warnR, warnG, warnB = 0.9, 0.5, 0.1
    elseif drPenalty >= 20 then
        warnR, warnG, warnB = 0.9, 0.8, 0.1
    else
        warnR, warnG, warnB = 0.7, 0.9, 0.3
    end

    local blend = 0.3
    return r + (warnR - r) * blend,
        g + (warnG - g) * blend,
        b + (warnB - b) * blend
end

function Addon:FormatGoldValue(value, profile)
    return FormatGoldValue(value, profile, self.Defaults.profile)
end

-- WoWLogsStatsPrio secondary[].rating only (no Lua-derived percent bands).
function Addon:FormatReferenceRatingSuffix(statKey, statResult, profile)
    local defaults = self.Defaults.profile
    local display = profile.referenceDisplay or defaults.referenceDisplay or "off"
    if display == "off" or display == "tooltip" then
        return ""
    end
    local mode = self:NormalizeStatPriorityMode(profile.statPriorityMode or defaults.statPriorityMode or "manual")
    if mode == "manual" then
        return ""
    end
    local payload = self:GetArchonStatReferencePayload(statKey, profile)
    if not payload then
        return ""
    end
    local playerR = math.floor(((statResult and statResult.rating) or 0) + 0.5)
    local archonR = payload.archonRating
    local d = playerR - archonR
    local drExtra = ""
    if profile.showDiminishingReturnHint == true then
        local hint = self:GetDRHint(statKey, statResult and statResult.value, statResult)
        if hint then
            drExtra = hint
        end
    end
    local tagOk = "|cff78ff8f" .. self:S("NE_STATS_REFERENCE_TAG_OK") .. "|r"
    local tagLowOpen = "|cffffd25d" .. self:S("NE_STATS_REFERENCE_TAG_LOW")
    if display == "delta" then
        if d == 0 then
            return "  " .. tagOk .. drExtra
        elseif d < 0 then
            return string.format("  |cffffd25d+%d|r%s", -d, drExtra)
        end
        return string.format("  |cffff9455-%d|r%s", d, drExtra)
    end
    -- inline
    if playerR >= archonR then
        return "  " .. tagOk .. drExtra
    end
    if profile.showReferenceRanges ~= false then
        return string.format("  %s %d|r%s", tagLowOpen, archonR, drExtra)
    end
    return "  " .. tagLowOpen .. "|r" .. drExtra
end

function Addon:PopulateReferenceStatTooltip(owner, statKey, statResult, profile)
    if not GameTooltip or not owner then
        return
    end
    local defaults = self.Defaults.profile
    profile = profile or self:GetProfile()
    if (profile.referenceDisplay or defaults.referenceDisplay or "off") ~= "tooltip" then
        return
    end
    if self:NormalizeStatPriorityMode(profile.statPriorityMode or defaults.statPriorityMode or "manual") == "manual" then
        return
    end
    if not self:IsArchonReferenceStatKey(statKey) then
        return
    end
    local payload = self:GetArchonStatReferencePayload(statKey, profile)
    if not payload then
        return
    end
    local def = self.StatDefinitions and self.StatDefinitions[statKey]
    if not def then
        return
    end
    local precision = math.max(0, math.min(3, profile.percentPrecision or defaults.percentPrecision))
    local playerR = math.floor(((statResult and statResult.rating) or 0) + 0.5)
    local pct = statResult and statResult.value or 0
    local archonR = payload.archonRating
    local d = playerR - archonR
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:ClearLines()
    GameTooltip:AddLine(self:S("NE_STATS_REFERENCE_TOOLTIP_TITLE", self:S(def.label), self:S("Archon reference (rating)")), 1, 0.82, 0)
    GameTooltip:AddLine(self:S("Your rating: %d", playerR), 1, 1, 1)
    if profile.showPercent ~= false then
        GameTooltip:AddLine(self:S("Your percent") .. ": " .. string.format("%." .. precision .. "f%%", pct), 1, 1, 1)
    end
    GameTooltip:AddLine(self:S("Archon typical rating: %d", archonR), 1, 1, 1)
    if d == 0 then
        GameTooltip:AddLine(self:S("Rating delta: ok"), 1, 1, 1)
    elseif d < 0 then
        GameTooltip:AddLine(self:S("Rating delta: need +%d vs Archon", -d), 1, 0.82, 0.4)
    else
        GameTooltip:AddLine(self:S("Rating delta: %d over Archon", d), 1, 0.9, 0.5)
    end
    if profile.showReferenceSource ~= false then
        GameTooltip:AddLine(self:S("NE_STATS_REFERENCE_SOURCE"), 0.7, 0.7, 0.7)
    end
    if payload.updated ~= "" then
        GameTooltip:AddLine(self:S("Updated: %s", payload.updated), 0.7, 0.7, 0.7)
    end
    if payload.activity ~= "" then
        local actKey = payload.activity
        local actLabel = actKey
        if actKey == "m+" then
            actLabel = self:S("NE_STATS_ACTIVITY_MPLUS")
        elseif actKey == "raid" then
            actLabel = self:S("NE_STATS_ACTIVITY_RAID")
        end
        GameTooltip:AddLine(self:S("Activity: %s", actLabel), 0.7, 0.7, 0.7)
    end
    if profile.showDiminishingReturnHint == true and statResult and statResult.dr then
        local penalty = statResult.dr.penalty or 0
        local loss = math.floor((statResult.dr.loss or 0) + 0.5)
        if penalty > 0 or loss > 0 then
            GameTooltip:AddLine(self:S("NE_STATS_REFERENCE_DR_LINE", penalty, loss), 0.8, 0.75, 0.5)
        end
    end
    GameTooltip:Show()
end

local function GetStatLabelOverride(profile, statKey)
    if type(profile) ~= "table" or type(profile.stats) ~= "table" then
        return nil
    end
    for _, entry in ipairs(profile.stats) do
        if type(entry) == "table" and entry.key == statKey and type(entry.nameOverride) == "string" and entry.nameOverride ~= "" then
            return entry.nameOverride
        end
    end
    return nil
end

function Addon:FormatStatValue(statKey, statResult, profile, def)
    local defaults = self.Defaults.profile
    local resolvedDef = def or (self.StatDefinitions and self.StatDefinitions[statKey])
    if not resolvedDef then
        return ""
    end

    local statLabel = GetStatLabelOverride(profile, statKey) or self:S(resolvedDef.label)
    local labelPart = profile.showLabels and (statLabel .. " ") or ""
    local precision = math.max(0, math.min(3, profile.percentPrecision or defaults.percentPrecision))
    local value = statResult and statResult.value or 0
    local ratingOverride = statResult and statResult.rating or nil
    local drSuffix = ""
    local drMode = profile.drDisplayMode or "off"
    if drMode ~= "off" then
        drSuffix = self:FormatDiminishingReturns(statResult, drMode)
    end

    if resolvedDef.rating then
        local rating = ratingOverride or 0
        local out
        if profile.showValues and profile.showPercent then
            out = string.format("%s%d / %." .. precision .. "f%%%s", labelPart, math.floor(rating + 0.5), value, drSuffix)
        elseif profile.showValues and not profile.showPercent then
            out = string.format("%s%d%s", labelPart, math.floor(rating + 0.5), drSuffix)
        elseif (not profile.showValues) and profile.showPercent then
            out = string.format("%s%." .. precision .. "f%%%s", labelPart, value, drSuffix)
        else
            out = labelPart ~= "" and labelPart or statLabel
        end
        if out and self:IsArchonReferenceStatKey(statKey) then
            local refSuffix = self:FormatReferenceRatingSuffix(statKey, statResult, profile)
            if refSuffix and refSuffix ~= "" then
                out = out .. refSuffix
            end
        end
        return out
    end

    if not profile.showValues then
        return labelPart ~= "" and labelPart or statLabel
    end
    if statKey == "GOLD" then
        return string.format("%s%s", labelPart, self:FormatGoldValue(value, profile))
    end
    if resolvedDef.formatValue then
        return string.format("%s%s", labelPart, resolvedDef.formatValue(value, profile))
    end
    return string.format("%s%s", labelPart, self:FormatValue(resolvedDef, value))
end

function Addon:EnsureFormatBindings()
    local statDefinitions = self.StatDefinitions
    if statDefinitions and statDefinitions.GOLD then
        statDefinitions.GOLD.formatValue = function(value, profile)
            return Addon:FormatGoldValue(value, profile)
        end
    end
end
