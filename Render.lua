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

local LAYOUT = {
    leftPadding = 8,
    rightPadding = 8,
    topPadding = 8,
    bottomPadding = 4,
    minColumnWidth = 40,
    minFrameSize = 24,
    iconGap = 4,
}

local function GetStringWidth(fontString)
    return fontString.GetUnboundedStringWidth and fontString:GetUnboundedStringWidth() or fontString:GetStringWidth()
end

local function BuildLayoutSignature(addon, profile, defaults, fontSize, textAlign, visibleStats)
    return table.concat({
        tostring(profile.fontKey or ""),
        tostring(fontSize),
        tostring(profile.showLabels),
        tostring(profile.showValues),
        tostring(profile.showStatIcons),
        tostring(profile.showPercent),
        tostring(profile.percentPrecision),
        tostring(textAlign),
        tostring(profile.columnCount or defaults.columnCount),
        tostring(profile.rowsPerColumn or defaults.rowsPerColumn),
        tostring(profile.rowGap or defaults.rowGap),
        tostring(profile.columnGap or defaults.columnGap),
        tostring(profile.frameControlsPosition or defaults.frameControlsPosition),
        tostring(profile.frameControlsDirection or defaults.frameControlsDirection),
        tostring(#visibleStats),
        tostring(profile.referenceDisplay or defaults.referenceDisplay or "inline"),
        tostring(addon:NormalizeStatPriorityMode(profile.statPriorityMode or defaults.statPriorityMode or "manual")),
        tostring(profile.showReferenceRanges ~= false),
        tostring(profile.showReferenceSource ~= false),
        tostring(profile.showDiminishingReturnHint ~= false),
    }, "|")
end

local function ResetStableLayoutIfNeeded(layoutSignature)
    if stableLayoutSignature ~= layoutSignature then
        stableLayoutSignature = layoutSignature
        stableColumnWidths = {}
    end
end

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
        width = math.max(width, GetStringWidth(measureLine))
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
            if row.icon then
                row.icon:Hide()
                row.icon:SetTexture(nil)
                row.icon:SetSize(1, 1)
            end
        end

        if line then
            line.statKey = nil
            line:Hide()
            line:ClearAllPoints()
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

local function BuildMeasuredStats(addon, statsReader, statDefinitions, visibleStats, profile, defaults, measureLine)
    local measuredStats = {}
    local maxLineHeight = 0

    for _, entry in ipairs(visibleStats) do
        local def = statDefinitions[entry.key]
        local readOk, statResult = pcall(function()
            return statsReader and statsReader.ReadStat and statsReader.ReadStat(entry.key)
        end)
        if readOk and statResult and statResult.value ~= nil then
            local formatOk, text = pcall(function()
                return addon:FormatStatValue(entry.key, statResult, profile, def)
            end)
            if formatOk and text then
                measureLine:SetText(text)
                local textWidth = GetStringWidth(measureLine)
                local textHeight = measureLine:GetStringHeight()
                local reservedReferenceWidth = GetReservedReferenceSuffixWidth(addon, measureLine, entry.key, profile, defaults)
                local iconWidth = 0
                if profile.showStatIcons == true and def and def.icon then
                    iconWidth = math.max(MIN_DYNAMIC_FONT_SIZE, math.ceil(measureLine:GetStringHeight())) + LAYOUT.iconGap
                end
                table.insert(measuredStats, {
                    entry = entry,
                    def = def,
                    text = text,
                    textWidth = textWidth + iconWidth,
                    reservedTextWidth = textWidth + iconWidth + reservedReferenceWidth,
                    iconSize = iconWidth > 0 and (iconWidth - LAYOUT.iconGap) or 0,
                    textHeight = textHeight,
                    drPenalty = statResult and statResult.dr and statResult.dr.penalty or nil,
                    statResult = statResult,
                })
                maxLineHeight = math.max(maxLineHeight, math.ceil(textHeight))
            end
        end
    end

    return measuredStats, maxLineHeight
end

local function ComputeColumnWidths(measuredStats, columnItemCounts, actualColumns)
    local columnWidths = {}
    local reservedColumnWidths = {}
    local maxRows = 0
    local itemIndex = 1

    for columnIndex = 1, actualColumns do
        local columnWidth = 0
        local reservedColumnWidth = 0
        local rowCount = columnItemCounts[columnIndex] or 0
        maxRows = math.max(maxRows, rowCount)
        for _ = 1, rowCount do
            local measured = measuredStats[itemIndex]
            if measured then
                columnWidth = math.max(columnWidth, measured.textWidth)
                reservedColumnWidth = math.max(reservedColumnWidth, measured.reservedTextWidth or measured.textWidth)
            end
            itemIndex = itemIndex + 1
        end
        columnWidths[columnIndex] = columnWidth
        reservedColumnWidths[columnIndex] = reservedColumnWidth
    end

    for columnIndex = 1, actualColumns do
        local currentWidth = reservedColumnWidths[columnIndex] or columnWidths[columnIndex] or 0
        local rememberedWidth = stableColumnWidths[columnIndex] or 0
        local effectiveWidth = math.max(currentWidth, rememberedWidth)
        stableColumnWidths[columnIndex] = effectiveWidth
        reservedColumnWidths[columnIndex] = effectiveWidth
    end

    return columnWidths, reservedColumnWidths, maxRows
end

local function BuildRenderLayout(addon, profile, defaults, measuredStats, maxLineHeight, fontSize, controlsWidth, controlsHeight, controlsGap)
    local actualColumns, columnItemCounts = addon:GetDisplayLayout(profile, #measuredStats)
    local columnWidths, reservedColumnWidths, maxRows = ComputeColumnWidths(measuredStats, columnItemCounts, actualColumns)
    local rowHeight = math.max(maxLineHeight, fontSize)
    local rowGap = math.max(0, math.floor(profile.rowGap or defaults.rowGap or 0))
    local columnGap = math.max(0, math.floor(profile.columnGap or defaults.columnGap or 0))
    local controlsPosition = profile.frameControlsPosition or defaults.frameControlsPosition or "BOTTOM"
    local controlsOnLeft = controlsPosition == "LEFT"
    local controlsOnRight = controlsPosition == "RIGHT"
    local controlsOnTop = controlsPosition == "TOP"
    local controlsOnBottom = not controlsOnLeft and not controlsOnRight and not controlsOnTop
    local rows = {}
    local itemIndex = 1
    local contentX = LAYOUT.leftPadding + (controlsOnLeft and (controlsWidth + controlsGap) or 0)
    local contentY = LAYOUT.topPadding + (controlsOnTop and (controlsHeight + controlsGap) or 0)
    local currentXOffset = contentX

    for columnIndex = 1, actualColumns do
        local rowCount = columnItemCounts[columnIndex] or 0
        local columnWidth = math.max((columnWidths[columnIndex] or 0) + 4, LAYOUT.minColumnWidth)
        for rowIndex = 1, rowCount do
            local measured = measuredStats[itemIndex]
            if measured then
                table.insert(rows, {
                    index = itemIndex,
                    measured = measured,
                    x = currentXOffset,
                    y = contentY + (rowIndex - 1) * (rowHeight + rowGap),
                    width = columnWidth,
                    height = rowHeight,
                })
            end
            itemIndex = itemIndex + 1
        end
        currentXOffset = currentXOffset + (columnWidths[columnIndex] or 0) + columnGap
    end

    local contentWidth = 0
    local reservedContentWidth = 0
    for columnIndex = 1, actualColumns do
        contentWidth = contentWidth + (columnWidths[columnIndex] or 0)
        reservedContentWidth = reservedContentWidth + (reservedColumnWidths[columnIndex] or columnWidths[columnIndex] or 0)
    end
    if actualColumns > 1 then
        contentWidth = contentWidth + (actualColumns - 1) * columnGap
        reservedContentWidth = reservedContentWidth + (actualColumns - 1) * columnGap
    end

    local contentHeight = 0
    if maxRows > 0 then
        contentHeight = maxRows * rowHeight + math.max(0, maxRows - 1) * rowGap
    end

    local contentAreaWidth = math.max(contentWidth, reservedContentWidth)
    local controlsX = LAYOUT.leftPadding
    local controlsY = LAYOUT.topPadding
    local frameContentWidth
    local frameContentHeight

    if controlsOnLeft then
        frameContentWidth = controlsWidth + controlsGap + contentAreaWidth
    elseif controlsOnRight then
        controlsX = LAYOUT.leftPadding + contentAreaWidth + controlsGap
        frameContentWidth = contentAreaWidth + controlsGap + controlsWidth
    else
        frameContentWidth = math.max(contentAreaWidth, controlsWidth)
    end

    if controlsOnTop then
        frameContentHeight = controlsHeight + controlsGap + contentHeight
    elseif controlsOnBottom then
        controlsY = LAYOUT.topPadding + contentHeight + controlsGap
        frameContentHeight = contentHeight + controlsGap + controlsHeight
    else
        frameContentHeight = math.max(contentHeight, controlsHeight)
    end

    return {
        rows = rows,
        controlsX = controlsX,
        controlsY = controlsY,
        frameWidth = math.max(LAYOUT.minFrameSize, math.ceil(frameContentWidth) + LAYOUT.leftPadding + LAYOUT.rightPadding),
        frameHeight = math.max(LAYOUT.minFrameSize, math.ceil(LAYOUT.topPadding + frameContentHeight + LAYOUT.bottomPadding)),
    }
end

local function ApplyRenderRows(addon, statsFrame, lines, renderRows, lineOverlays, layout, fontPath, fontSize, fontFlags, textAlign, profile)
    for _, rowLayout in ipairs(layout.rows) do
        local measured = rowLayout.measured
        local line = lines[rowLayout.index]
        local row = renderRows and renderRows[rowLayout.index]
        if measured and line and row then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", statsFrame, "TOPLEFT", rowLayout.x, -rowLayout.y)
            row:SetSize(rowLayout.width, rowLayout.height)
            row.statKey = measured.entry.key
            row:Show()

            local textX = 0
            if measured.iconSize and measured.iconSize > 0 and measured.def and measured.def.icon and row.icon then
                row.icon:SetTexture(measured.def.icon)
                row.icon:SetSize(measured.iconSize, measured.iconSize)
                row.icon:ClearAllPoints()
                row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
                row.icon:Show()
                textX = measured.iconSize + LAYOUT.iconGap
            elseif row.icon then
                row.icon:Hide()
            end

            line:ClearAllPoints()
            line:SetPoint("TOPLEFT", row, "TOPLEFT", textX, 0)
            line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
            line:SetFont(fontPath, fontSize, fontFlags)
            line:SetJustifyH(textAlign)
            line:SetWidth(math.max(1, rowLayout.width - textX))
            line:SetWordWrap(false)
            line:SetMaxLines(1)
            local lineR, lineG, lineB = measured.entry.color[1], measured.entry.color[2], measured.entry.color[3]
            if (profile.drDisplayMode or "off") ~= "off" and measured.drPenalty then
                lineR, lineG, lineB = addon:GetDRColor(measured.entry.color, measured.drPenalty)
            end
            line:SetTextColor(lineR, lineG, lineB, 1)
            line:SetText(measured.text)
            line.statKey = measured.entry.key
            line:Show()

            local overlay = lineOverlays[rowLayout.index]
            if overlay then
                overlay.statKey = measured.entry.key
                overlay.statResult = measured.statResult
                overlay:ClearAllPoints()
                overlay:SetAllPoints(row)
                overlay:Show()
            end
        end
    end
end

local function ResizeStatsFrame(addon, statsFrame, statsAnchor, profile, defaults, layout)
    statsFrame:SetSize(layout.frameWidth, layout.frameHeight)
    addon:LayoutFrameControls(layout.controlsX, layout.controlsY)

    if statsAnchor then
        local scale = profile.scale or defaults.scale
        local newAnchorWidth = layout.frameWidth * scale
        local newAnchorHeight = layout.frameHeight * scale
        local currentAnchorWidth, currentAnchorHeight = statsAnchor:GetSize()
        if math.abs(currentAnchorWidth - newAnchorWidth) > 0.5 or math.abs(currentAnchorHeight - newAnchorHeight) > 0.5 then
            statsAnchor:SetSize(newAnchorWidth, newAnchorHeight)
        end
    end
end

local function IsPrimaryStatKey(statKey)
    return statKey == "STR" or statKey == "AGI" or statKey == "INT"
end

function Addon:GetVisibleStats()
    local profile = self:GetProfile()
    local displayStats = self:GetDisplayStats()
    local visible = {}
    local mainStatKey
    local mainStatEntry
    local primaryStats = {}
    local otherStats = {}

    if profile.preferCurrentSpecMainStat then
        mainStatKey = self.GetCurrentPrimaryStatKey and self:GetCurrentPrimaryStatKey()
    end

    for _, entry in ipairs(displayStats) do
        if entry.key == mainStatKey then
            mainStatEntry = entry
        end
        if entry.enabled then
            if profile.preferCurrentSpecMainStat and IsPrimaryStatKey(entry.key) then
                table.insert(primaryStats, entry)
            else
                table.insert(otherStats, entry)
            end
        end
    end

    if profile.preferCurrentSpecMainStat then
        if mainStatEntry then
            table.insert(visible, mainStatEntry)
        end
        for _, entry in ipairs(primaryStats) do
            if entry.key ~= mainStatKey then
                table.insert(visible, entry)
            end
        end
    end
    for _, entry in ipairs(otherStats) do
        table.insert(visible, entry)
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
    local statsFrame, statsAnchor = self:GetFrameRefs()
    local lines, measureLine = self:GetRenderWidgets()
    local renderRows = self.GetRenderRows and self:GetRenderRows() or nil
    local lineOverlays = self:GetLineOverlays()
    local textAlign = profile.textAlign or defaults.textAlign
    local visibleStats = self:GetVisibleStats()
    local fontPath, fontFlags = self:GetFontInfo(profile.fontKey)
    local fontSize = math.max(MIN_DYNAMIC_FONT_SIZE, profile.fontSize or defaults.fontSize)
    local controlsWidth, controlsHeight, controlsGap = self:GetFrameControlsSize()
    local layoutSignature = BuildLayoutSignature(self, profile, defaults, fontSize, textAlign, visibleStats)

    ResetStableLayoutIfNeeded(layoutSignature)
    ResetRenderWidgets(lines, lineOverlays, renderRows)

    measureLine:SetFont(fontPath, fontSize, fontFlags)
    local measuredStats, maxLineHeight = BuildMeasuredStats(self, ns.Stats, self.StatDefinitions, visibleStats, profile, defaults, measureLine)
    local layout = BuildRenderLayout(self, profile, defaults, measuredStats, maxLineHeight, fontSize, controlsWidth, controlsHeight, controlsGap)
    ApplyRenderRows(self, statsFrame, lines, renderRows, lineOverlays, layout, fontPath, fontSize, fontFlags, textAlign, profile)
    ResizeStatsFrame(self, statsFrame, statsAnchor, profile, defaults, layout)

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
