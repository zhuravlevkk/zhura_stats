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

function Addon:FormatDiminishingReturns(statResult)
    if not statResult or not statResult.dr then
        return ""
    end
    local dr = statResult.dr
    if dr.next then
        return string.format(" ->%d%%", dr.next)
    end
    return " ->cap"
end

function Addon:GetDRColor(baseColor, drPenalty)
    local r, g, b = baseColor[1], baseColor[2], baseColor[3]
    if not drPenalty then
        return r, g, b
    end

    if drPenalty >= 50 then
        return 0.9, 0.2, 0.2
    end
    if drPenalty >= 40 then
        return 0.9, 0.5, 0.1
    end
    if drPenalty >= 20 then
        return 0.9, 0.8, 0.1
    end
    if drPenalty >= 10 then
        return 0.7, 0.9, 0.3
    end

    return r, g, b
end

function Addon:FormatGoldValue(value, profile)
    return FormatGoldValue(value, profile, self.Defaults.profile)
end

function Addon:FormatStatValue(statKey, statResult, profile, def)
    local defaults = self.Defaults.profile
    local resolvedDef = def or (self.StatDefinitions and self.StatDefinitions[statKey])
    if not resolvedDef then
        return ""
    end

    local statLabel = self:S(resolvedDef.label)
    local labelPart = profile.showLabels and (statLabel .. " ") or ""
    local precision = math.max(0, math.min(3, profile.percentPrecision or defaults.percentPrecision))
    local value = statResult and statResult.value or 0
    local ratingOverride = statResult and statResult.rating or nil
    local drSuffix = ""
    if (profile.drDisplayMode or "off") == "suffix" then
        drSuffix = self:FormatDiminishingReturns(statResult)
    end

    if resolvedDef.rating then
        local rating = ratingOverride or 0
        if profile.showValues and profile.showPercent then
            return string.format("%s%d / %." .. precision .. "f%%%s", labelPart, math.floor(rating + 0.5), value, drSuffix)
        end
        if profile.showValues and not profile.showPercent then
            return string.format("%s%d%s", labelPart, math.floor(rating + 0.5), drSuffix)
        end
        if (not profile.showValues) and profile.showPercent then
            return string.format("%s%." .. precision .. "f%%%s", labelPart, value, drSuffix)
        end
        return labelPart ~= "" and labelPart or statLabel
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
