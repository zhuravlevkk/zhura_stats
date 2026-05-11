local _, ns = ...

ns = ns or {}
ns.ZhuraStats = ns.ZhuraStats or {}
local Addon = ns.ZhuraStats

local MIN_DYNAMIC_FONT_SIZE = 8
local combatStatRefreshHandle
local COMBAT_STAT_REFRESH_SEC = 0.35
local lastRefreshErrorAt = 0
local lastRefreshErrorMessage = ""
local stableLayoutSignature = nil
local stableColumnWidths = {}

local function GetReservedReferenceSuffixWidth(addon, measureLine, statKey, profile, defaults)
    if not addon:IsArchonReferenceStatKey(statKey) then
        return 0
    end

    local display = profile.referenceDisplay or defaults.referenceDisplay or "off"
    if display == "off" or display == "tooltip" then
        return 0
    end

    local mode = addon:NormalizeStatPriorityMode(profile.statPriorityMode or defaults.statPriorityMode or "manual")
    if mode == "manual" then
        return 0
    end

    local payload = addon:GetArchonStatReferencePayload(statKey, profile)
    local referenceRating = payload and payload.archonRating or 9999
    local samples
    if display == "delta" then
        samples = {
            "  |cff78ff8f" .. addon:S("NE_STATS_REFERENCE_TAG_OK") .. "|r",
            "  |cffffd25d+" .. referenceRating .. "|r",
            "  |cffff9455-" .. referenceRating .. "|r",
        }
    elseif profile.showReferenceRanges ~= false then
        samples = {
            "  |cff78ff8f" .. addon:S("NE_STATS_REFERENCE_TAG_OK") .. "|r",
            "  |cffffd25d" .. addon:S("NE_STATS_REFERENCE_TAG_LOW") .. " " .. referenceRating .. "|r",
        }
    else
        samples = {
            "  |cff78ff8f" .. addon:S("NE_STATS_REFERENCE_TAG_OK") .. "|r",
            "  |cffffd25d" .. addon:S("NE_STATS_REFERENCE_TAG_LOW") .. "|r",
        }
    end

    if profile.showDiminishingReturnHint == true then
        table.insert(samples, samples[#samples] .. " " .. addon:S("NE_STATS_REFERENCE_DR_TAG"))
    end

    local width = 0
    for _, sample in ipairs(samples) do
        measureLine:SetText(sample)
        width = math.max(width, measureLine.GetUnboundedStringWidth and measureLine:GetUnboundedStringWidth() or measureLine:GetStringWidth())
    end
    return width
end

local function ResetRenderWidgets(lines, lineOverlays, renderRows)
    for index, line in ipairs(lines) do
        local row = renderRows and renderRows[index]
        if row then
            row.statKey = nil
            row:Hide()
            row:ClearAllPoints()
            row:SetSize(1, 1)
        end

        if line then
            line.statKey = nil
            line:Hide()
            line:SetText("")
            line:SetWidth(1)
        end

        local overlay = lineOverlays[index]
        if overlay then
            overlay.statKey = nil
            overlay.statResult = nil
            overlay:Hide()
            overlay:ClearAllPoints()
            if row then
                overlay:SetAllPoints(row)
            else
                overlay:SetSize(1, 1)
            end
            overlay:EnableMouse(false)
        end
    end
end

function Addon:GetVisibleStats()
    local profile = self:GetProfile()
    local displayStats = self:GetDisplayStats()
    local visible = {}
    local mainStatKey
    local mainStatEntry

    if profile.preferCurrentSpecMainStat then
        mainStatKey = self.GetCurrentPrimaryStatKey and self:GetCurrentPrimaryStatKey()
    end

    for _, entry in ipairs(displayStats) do
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

function Addon:GetDisplayLayout(profile, visibleCount)
    local defaults = self.Defaults.profile
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

function Addon:ApplyTextAlignmentToVisibleLines()
    local lines = select(1, self:GetRenderWidgets())
    local align = self:GetProfileValue("textAlign") or self.Defaults.profile.textAlign
    for _, line in ipairs(lines) do
        if line and line:IsShown() then
            line:SetJustifyH(align)
            line:SetText(line:GetText() or "")
        end
    end
end

function Addon:RefreshStatsImpl()
    self:EnsureStatsFrame()

    local profile = self:GetProfile()
    local defaults = self.Defaults.profile
    local statDefinitions = self.StatDefinitions
    local statsFrame, statsAnchor = self:GetFrameRefs()
    local lines, measureLine = self:GetRenderWidgets()
    local renderRows = self.GetRenderRows and self:GetRenderRows() or nil
    local lineOverlays = self:GetLineOverlays()
    local textAlign = profile.textAlign or defaults.textAlign
    local visibleStats = self:GetVisibleStats()
    local fontPath, fontFlags = self:GetFontInfo(profile.fontKey)
    local fontSize = math.max(MIN_DYNAMIC_FONT_SIZE, profile.fontSize or defaults.fontSize)
    local leftPadding, rightPadding, topPadding, bottomPadding = 8, 8, 8, 4
    local columnGap, rowGap = 20, 2
    local controlsWidth, controlsHeight, controlsGap = self:GetFrameControlsSize()
    local measuredStats = {}
    local maxLineHeight = 0
    local Stats = ns.Stats
    local layoutSignature = table.concat({
        tostring(profile.fontKey or ""),
        tostring(fontSize),
        tostring(profile.showLabels),
        tostring(profile.showValues),
        tostring(profile.showPercent),
        tostring(profile.percentPrecision),
        tostring(textAlign),
        tostring(profile.columnCount or defaults.columnCount),
        tostring(profile.rowsPerColumn or defaults.rowsPerColumn),
        tostring(#visibleStats),
        tostring(profile.referenceDisplay or defaults.referenceDisplay or "inline"),
        tostring(self:NormalizeStatPriorityMode(profile.statPriorityMode or defaults.statPriorityMode or "manual")),
        tostring(profile.showReferenceRanges ~= false),
        tostring(profile.showReferenceSource ~= false),
        tostring(profile.showDiminishingReturnHint ~= false),
    }, "|")

    if stableLayoutSignature ~= layoutSignature then
        stableLayoutSignature = layoutSignature
        stableColumnWidths = {}
    end

    ResetRenderWidgets(lines, lineOverlays, renderRows)

    measureLine:SetFont(fontPath, fontSize, fontFlags)
    for _, entry in ipairs(visibleStats) do
        local def = statDefinitions[entry.key]
        local readOk, statResult = pcall(function()
            return Stats and Stats.ReadStat and Stats.ReadStat(entry.key)
        end)
        if readOk and statResult and statResult.value ~= nil then
            local formatOk, text = pcall(function()
                return self:FormatStatValue(entry.key, statResult, profile, def)
            end)
            if formatOk and text then
                measureLine:SetText(text)
                local textWidth = measureLine.GetUnboundedStringWidth and measureLine:GetUnboundedStringWidth() or measureLine:GetStringWidth()
                local textHeight = measureLine:GetStringHeight()
                local reservedReferenceWidth = GetReservedReferenceSuffixWidth(self, measureLine, entry.key, profile, defaults)
                table.insert(measuredStats, {
                    entry = entry,
                    text = text,
                    textWidth = textWidth + reservedReferenceWidth,
                    textHeight = textHeight,
                    drPenalty = statResult and statResult.dr and statResult.dr.penalty or nil,
                    statResult = statResult,
                })
                maxLineHeight = math.max(maxLineHeight, math.ceil(textHeight))
            end
        end
    end

    local actualColumns, columnItemCounts = self:GetDisplayLayout(profile, #measuredStats)
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

    for columnIndex = 1, actualColumns do
        local currentWidth = columnWidths[columnIndex] or 0
        local rememberedWidth = stableColumnWidths[columnIndex] or 0
        local effectiveWidth = math.max(currentWidth, rememberedWidth)
        stableColumnWidths[columnIndex] = effectiveWidth
        columnWidths[columnIndex] = effectiveWidth
    end

    maxLineHeight = math.max(maxLineHeight, fontSize)
    itemIndex = 1
    local currentXOffset = leftPadding
    for columnIndex = 1, actualColumns do
        local rowCount = columnItemCounts[columnIndex] or 0
        for rowIndex = 1, rowCount do
            local measured = measuredStats[itemIndex]
            local line = lines[itemIndex]
            local row = renderRows and renderRows[itemIndex]
            if measured and line and row then
                local currentYOffset = topPadding + (rowIndex - 1) * (maxLineHeight + rowGap)
                local columnWidth = math.max(columnWidths[columnIndex] + 4, 40)
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT", statsFrame, "TOPLEFT", currentXOffset, -currentYOffset)
                row:SetSize(columnWidth, maxLineHeight)
                row.statKey = measured.entry.key
                row:Show()

                line:SetFont(fontPath, fontSize, fontFlags)
                line:SetJustifyH(textAlign)
                line:SetWidth(columnWidth)
                line:SetJustifyH(textAlign)
                line:SetWordWrap(false)
                line:SetMaxLines(1)
                local lineR, lineG, lineB = measured.entry.color[1], measured.entry.color[2], measured.entry.color[3]
                if (profile.drDisplayMode or "off") ~= "off" and measured.drPenalty then
                    lineR, lineG, lineB = self:GetDRColor(measured.entry.color, measured.drPenalty)
                end
                line:SetTextColor(lineR, lineG, lineB, 1)
                line:SetText(measured.text)
                line.statKey = measured.entry.key
                line:Show()

                local overlay = lineOverlays[itemIndex]
                if overlay then
                    overlay.statKey = measured.entry.key
                    overlay.statResult = measured.statResult
                    overlay:ClearAllPoints()
                    overlay:SetAllPoints(row)
                    overlay:Show()
                end
            end
            itemIndex = itemIndex + 1
        end
        currentXOffset = currentXOffset + columnWidths[columnIndex] + columnGap
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

    local controlsYOffset = topPadding + contentHeight + controlsGap
    local frameContentWidth = math.max(contentWidth, controlsWidth)
    local frameContentHeight = contentHeight + controlsGap + controlsHeight
    local frameWidth = math.max(24, math.ceil(frameContentWidth) + leftPadding + rightPadding)
    local frameHeight = math.max(24, math.ceil(topPadding + frameContentHeight + bottomPadding))
    statsFrame:SetSize(frameWidth, frameHeight)
    self:LayoutFrameControls(leftPadding, controlsYOffset)
    if statsAnchor then
        local scale = profile.scale or defaults.scale
        local newAnchorWidth = frameWidth * scale
        local newAnchorHeight = frameHeight * scale
        local currentAnchorWidth, currentAnchorHeight = statsAnchor:GetSize()
        if math.abs(currentAnchorWidth - newAnchorWidth) > 0.5 or math.abs(currentAnchorHeight - newAnchorHeight) > 0.5 then
            statsAnchor:SetSize(newAnchorWidth, newAnchorHeight)
        end
    end

    self:UpdateTooltipOverlayVisibility()
end

function Addon:RefreshStats()
    local handledError
    local ok, err = xpcall(function()
        self:RefreshStatsImpl()
    end, function(message)
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
            if displayError ~= lastRefreshErrorMessage or (now - lastRefreshErrorAt) > 30 then
                print(self:S("NE Stats: refresh failed: %s", displayError))
                lastRefreshErrorMessage = displayError
                lastRefreshErrorAt = now
            end
        end
    end

    if self.RefreshPriorityModeButtons then
        self:RefreshPriorityModeButtons()
    end
end

function Addon:StopCombatStatRefresh()
    if combatStatRefreshHandle then
        combatStatRefreshHandle:Cancel()
        combatStatRefreshHandle = nil
    end
end

function Addon:StartCombatStatRefresh()
    if combatStatRefreshHandle or not (C_Timer and C_Timer.NewTicker) then
        return
    end

    combatStatRefreshHandle = C_Timer.NewTicker(COMBAT_STAT_REFRESH_SEC, function()
        if not InCombatLockdown or not InCombatLockdown() then
            Addon:StopCombatStatRefresh()
            return
        end
        if Addon.initialized then
            Addon:RefreshStats()
        end
    end)
end
