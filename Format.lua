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

-- Reference proximity gradient: red (far from Archon) -> green (on target).
local REF_COLOR_OK = { 0x78 / 255, 0xff / 255, 0x8f / 255 }
local REF_COLOR_FAR = { 0.9, 0.15, 0.15 }
-- At this fraction of archonRating away, ref color reaches full "far" red.
local REF_PROXIMITY_BAND_RATIO = 0.5

function Addon:GetReferenceProximityColor(playerR, archonR)
    archonR = math.max(1, math.floor((archonR or 0) + 0.5))
    playerR = math.floor((playerR or 0) + 0.5)
    local delta = math.abs(playerR - archonR)
    local band = math.max(1, archonR * REF_PROXIMITY_BAND_RATIO)
    local t = math.min(1, delta / band)
    local farR, farG, farB = REF_COLOR_FAR[1], REF_COLOR_FAR[2], REF_COLOR_FAR[3]
    local okR, okG, okB = REF_COLOR_OK[1], REF_COLOR_OK[2], REF_COLOR_OK[3]
    local blend = 1 - t
    return farR + (okR - farR) * blend,
        farG + (okG - farG) * blend,
        farB + (okB - farB) * blend
end

function Addon:FormatReferenceColorMarkup(r, g, b, text)
    return string.format(
        "|cff%02x%02x%02x%s|r",
        math.floor(r * 255 + 0.5),
        math.floor(g * 255 + 0.5),
        math.floor(b * 255 + 0.5),
        text or ""
    )
end

-- Addon TGAs: triangles centered in the canvas (see scripts/gen_ref_arrows.py).
local REF_ARROW_TEX_UP = "Interface\\AddOns\\ZhuraStats\\Media\\RefArrowUp"
local REF_ARROW_TEX_DOWN = "Interface\\AddOns\\ZhuraStats\\Media\\RefArrowDown"

function Addon:GetRefArrowTexturePath(isUp)
    return isUp and REF_ARROW_TEX_UP or REF_ARROW_TEX_DOWN
end

function Addon:GetRefArrowSize(profile, defaults)
    local fontSize = profile.fontSize or (defaults and defaults.fontSize) or 12
    return math.max(10, math.floor(fontSize * 0.75 + 0.5))
end

local function RefArrowTexture(isUp, profile, defaults)
    local size = Addon:GetRefArrowSize(profile, defaults)
    local path = isUp and REF_ARROW_TEX_UP or REF_ARROW_TEX_DOWN
    return string.format("|T%s:%d:%d:0:0|t", path, size, size)
end

local function RefDeltaSegments(isUp, magnitude, profile, defaults, color)
    local size = Addon:GetRefArrowSize(profile, defaults)
    return {
        {
            col = "ref_arrow",
            texture = Addon:GetRefArrowTexturePath(isUp),
            textureSize = size,
            color = color,
        },
        { col = "ref", text = tostring(magnitude), color = color, justify = "LEFT" },
    }
end

-- Returns zero or more { col="ref"|"ref_arrow", ... } segments for the tail zone.
function Addon:BuildReferenceSegments(statKey, statResult, profile)
    local defaults = self.Defaults.profile
    local display = profile.referenceDisplay or defaults.referenceDisplay or "off"
    if display == "off" or display == "tooltip" then
        return nil
    end
    local mode = self:NormalizeStatPriorityMode(profile.statPriorityMode or defaults.statPriorityMode or "manual")
    if mode == "manual" then
        return nil
    end
    local payload = self:GetArchonStatReferencePayload(statKey, profile)
    if not payload then
        return nil
    end

    local playerR = math.floor(((statResult and statResult.rating) or 0) + 0.5)
    local archonR = payload.archonRating
    local d = playerR - archonR
    -- d > 0 => above Archon (up arrow); d < 0 => below (down arrow).
    -- Color uses proximity gradient (red far, green on target), same for both directions.

    local tagOk = self:S("NE_STATS_REFERENCE_TAG_OK")
    local tagLow = self:S("NE_STATS_REFERENCE_TAG_LOW")
    local proxR, proxG, proxB = self:GetReferenceProximityColor(playerR, archonR)
    local proxColor = { proxR, proxG, proxB }

    if display == "delta" then
        if d == 0 then
            return { { col = "ref", text = tagOk, color = REF_COLOR_OK, justify = "LEFT" } }
        elseif d > 0 then
            return RefDeltaSegments(true, d, profile, defaults, proxColor)
        end
        return RefDeltaSegments(false, -d, profile, defaults, proxColor)
    end

    -- inline
    if playerR >= archonR then
        return { { col = "ref", text = tagOk, color = REF_COLOR_OK, justify = "LEFT" } }
    end
    if profile.showReferenceRanges ~= false then
        return { { col = "ref", text = string.format("%s %d", tagLow, archonR), color = proxColor, justify = "LEFT" } }
    end
    return { { col = "ref", text = tagLow, color = proxColor, justify = "LEFT" } }
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
        end
        local proxR, proxG, proxB = self:GetReferenceProximityColor(playerR, archonR)
        local arrow = RefArrowTexture(d > 0, profile, defaults)
        local magnitude = d > 0 and d or -d
        return "  " .. self:FormatReferenceColorMarkup(proxR, proxG, proxB, arrow .. magnitude) .. drExtra
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
    if not self:WantsReferenceTooltip(statKey, statResult, profile) then
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
    GameTooltip:AddLine(self:S("NE_STATS_REFERENCE_TOOLTIP_TITLE", self:S(def.label), self:S("NE_STATS_ARCHON_REFERENCE_RATING")), 1, 0.82, 0)
    GameTooltip:AddLine(self:S("NE_STATS_YOUR_RATING_FMT", playerR), 1, 1, 1)
    if profile.showPercent ~= false then
        GameTooltip:AddLine(self:S("NE_STATS_YOUR_PERCENT") .. ": " .. string.format("%." .. precision .. "f%%", pct), 1, 1, 1)
    end
    GameTooltip:AddLine(self:S("NE_STATS_ARCHON_TYPICAL_RATING_FMT", archonR), 1, 1, 1)
    if self:HasActiveDiminishingReturns(profile, statResult) then
        if d > 0 then
            GameTooltip:AddLine(self:S("NE_STATS_REFERENCE_DR_OVER_HINT_FMT", d), 1, 0.9, 0.5, true)
        else
            GameTooltip:AddLine(self:S("NE_STATS_REFERENCE_DR_HIDDEN_HINT"), 1, 0.82, 0.6, true)
        end
    else
        local proxR, proxG, proxB = self:GetReferenceProximityColor(playerR, archonR)
        if d == 0 then
            GameTooltip:AddLine(self:S("NE_STATS_RATING_DELTA_OK"), proxR, proxG, proxB)
        elseif d < 0 then
            GameTooltip:AddLine(self:S("NE_STATS_RATING_DELTA_NEED_FMT", -d), proxR, proxG, proxB)
        else
            GameTooltip:AddLine(self:S("NE_STATS_RATING_DELTA_OVER_FMT", d), proxR, proxG, proxB)
        end
    end
    if profile.showReferenceSource ~= false then
        GameTooltip:AddLine(self:S("NE_STATS_REFERENCE_SOURCE"), 0.7, 0.7, 0.7)
    end
    if payload.updated ~= "" then
        GameTooltip:AddLine(self:S("NE_STATS_UPDATED_FMT", payload.updated), 0.7, 0.7, 0.7)
    end
    if payload.activity ~= "" then
        local actKey = payload.activity
        local actLabel = actKey
        if actKey == "m+" then
            actLabel = self:S("NE_STATS_ACTIVITY_MPLUS")
        elseif actKey == "raid" then
            actLabel = self:S("NE_STATS_ACTIVITY_RAID")
        end
        GameTooltip:AddLine(self:S("NE_STATS_ACTIVITY_FMT", actLabel), 0.7, 0.7, 0.7)
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

-- Build the per-stat row as an ordered list of segments instead of one glued
-- string. Each segment is its own grid cell so the renderer can align ratings,
-- percents and reference deltas into independent sub-columns.
--
-- Segment shape:
--   { col = "<column key>", text = "<plain text>", color = {r,g,b} | nil,
--     justify = "LEFT" | "RIGHT" | "CENTER" }
-- color = nil means "inherit the row's stat color" (resolved by the renderer).
--
-- Column keys (fixed order, renderer maps each to a sub-column):
--   "label"   stat name
--   "value"   non-rating value (AGI / DURA / ILVL / GOLD); spans rating+sep+pct
--   "rating"  rating number   (rating stats only)
--   "sep"     "/" separator   (only when both rating and percent shown)
--   "percent" percent value   (rating stats only)
--   "dr"      diminishing-returns suffix (inherits stat / DR color downstream)
--   "ref"     Archon reference tag/delta (carries its own color)
function Addon:BuildStatSegments(statKey, statResult, profile, def)
    local defaults = self.Defaults.profile
    local resolvedDef = def or (self.StatDefinitions and self.StatDefinitions[statKey])
    if not resolvedDef then
        return {}
    end

    local segments = {}
    local statLabel = GetStatLabelOverride(profile, statKey) or self:S(resolvedDef.label)
    if profile.showLabels then
        table.insert(segments, { col = "label", text = statLabel, justify = "LEFT" })
    end

    local precision = math.max(0, math.min(3, profile.percentPrecision or defaults.percentPrecision))
    local value = statResult and statResult.value or 0
    local ratingOverride = statResult and statResult.rating or nil

    -- Diminishing returns: shown as a "DR(-N)" tag where N is the rating lost
    -- to DR (statResult.dr.loss, rounded), colored by penalty severity. This is
    -- the real DR loss from the game's ratingBonus, NOT the Archon reference
    -- delta (that lives in the separate "ref" segment). The displayed percent
    -- is already the post-DR effective value.
    -- drMode "off" hides the DR signal entirely.
    local hasDR = self:HasActiveDiminishingReturns(profile, statResult)
    local drTagText
    if hasDR then
        local loss = math.floor((statResult.dr.loss or 0) + 0.5)
        if loss > 0 then
            drTagText = string.format("%s(-%d)", self:S("NE_STATS_REFERENCE_DR_TAG"), loss)
        else
            drTagText = self:S("NE_STATS_REFERENCE_DR_TAG")
        end
    end

    if resolvedDef.rating then
        local rating = ratingOverride or 0
        local ratingText = string.format("%d", math.floor(rating + 0.5))
        local percentText = string.format("%." .. precision .. "f%%", value)

        if profile.showValues and profile.showPercent then
            table.insert(segments, { col = "rating", text = ratingText, justify = "RIGHT" })
            table.insert(segments, { col = "sep", text = "/", justify = "CENTER" })
            table.insert(segments, { col = "percent", text = percentText, justify = "RIGHT", drFlag = hasDR })
        elseif profile.showValues and not profile.showPercent then
            table.insert(segments, { col = "rating", text = ratingText, justify = "RIGHT", drFlag = hasDR })
        elseif (not profile.showValues) and profile.showPercent then
            table.insert(segments, { col = "percent", text = percentText, justify = "RIGHT", drFlag = hasDR })
        else
            -- label-only row: nothing besides the label already pushed above.
            if not profile.showLabels then
                table.insert(segments, { col = "label", text = statLabel, justify = "LEFT" })
            end
        end

        if hasDR then
            -- "DR(-N)" tag, N = rating lost to DR, colored by severity downstream.
            table.insert(segments, { col = "dr", text = drTagText, justify = "LEFT", drFlag = true })
        end

        if self:ShouldShowReferenceOnRow(statKey, statResult, profile) then
            local refSegs = self:BuildReferenceSegments(statKey, statResult, profile)
            if refSegs then
                for _, refSeg in ipairs(refSegs) do
                    table.insert(segments, refSeg)
                end
            end
        end
        return segments
    end

    -- Non-rating stats: single value cell spanning the rating/sep/percent band.
    if not profile.showValues then
        if not profile.showLabels then
            table.insert(segments, { col = "label", text = statLabel, justify = "LEFT" })
        end
        return segments
    end

    local valueText
    if statKey == "GOLD" then
        valueText = self:FormatGoldValue(value, profile)
    elseif resolvedDef.formatValue then
        valueText = resolvedDef.formatValue(value, profile)
    else
        valueText = self:FormatValue(resolvedDef, value)
    end
    table.insert(segments, { col = "value", text = valueText, justify = "RIGHT", drFlag = hasDR })
    if hasDR then
        table.insert(segments, { col = "dr", text = drTagText, justify = "LEFT", drFlag = true })
    end
    return segments
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
        if out and self:ShouldShowReferenceOnRow(statKey, statResult, profile) then
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
