local _, ns = ...

ns = ns or {}
ns.ZhuraStats = ns.ZhuraStats or {}
local Addon = ns.ZhuraStats

local MIN_DYNAMIC_FONT_SIZE = 8
local combatStatRefreshHandle
local COMBAT_STAT_REFRESH_SEC = 0.35
-- Row brightness multiplier for stale / snapshot values (not live).
local STALE_DIM_FACTOR = 0.70

-- Only dim numeric/value segments when stats are stale; labels stay full brightness.
local STALE_DIM_COLUMNS = {
    rating = true,
    percent = true,
    value = true,
    sep = true,
    dr = true,
    ref = true,
    ref_arrow = true,
}
local lastRefreshErrorAt = 0
local lastRefreshErrorMessage = ""

-- Sub-columns that the rating band is composed of (left-to-right). The
-- non-rating "value" cell is right-aligned to this same band zone, and the
-- dr/ref "tail" forms a separate right-aligned zone after it.
local VALUE_SPAN = { "rating", "sep", "percent" }

local SUBCOL_GAP = 3 -- horizontal gap between adjacent sub-columns
local REF_ARROW_NUM_GAP = 1 -- tight gap between ref arrow texture and delta digits

local TAIL_COLUMNS = {
    dr = true,
    ref = true,
    ref_arrow = true,
}

local function RefArrowSegmentWidth(seg)
    return seg.textureSize or 0
end

local function TailSegmentGap(prevCol, col)
    if not prevCol then
        return 0
    end
    if prevCol == "ref_arrow" and col == "ref" then
        return REF_ARROW_NUM_GAP
    end
    return SUBCOL_GAP
end

local function MeasureTailWidth(segments)
    local width = 0
    local prevCol
    for _, seg in ipairs(segments) do
        if TAIL_COLUMNS[seg.col] then
            width = width + TailSegmentGap(prevCol, seg.col)
            width = width + seg.width
            prevCol = seg.col
        end
    end
    return width
end

local function SegmentGap(prevCol, col)
    if not prevCol then
        return 0
    end
    return TailSegmentGap(prevCol, col)
end

local function MeasureCompactRowWidth(segments)
    local width = 0
    local prevCol
    for _, seg in ipairs(segments) do
        width = width + SegmentGap(prevCol, seg.col)
        width = width + seg.width
        prevCol = seg.col
    end
    return width
end

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
        tostring(profile.valueColumnWidth or defaults.valueColumnWidth),
        tostring(profile.compactValueColumns == true),
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

local function ResetRenderWidgets(addon, lines, lineOverlays, renderRows)
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
            addon:HideRowSegmentsFrom(row, 1)
            addon:HideRowRefArrowsFrom(row, 1)
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

-- Build a measured row for a stat whose live value is a Secret (combat / M+ /
-- encounter / PvP). The number cannot be read or formatted in Lua, so we render
-- it stripped down: [icon] [label] [value], pushing the raw Secret into the
-- FontString via SetFormattedText at draw time. No rating split, DR, reference
-- arrows or value-based coloring — all of those require reading the value.
local function BuildSecretMeasuredStat(addon, entry, def, profile, defaults, measureLine, secretValue)
    local resolvedDef = def or (addon.StatDefinitions and addon.StatDefinitions[entry.key])
    if not resolvedDef then
        return nil
    end

    local precision = math.max(0, math.min(3, profile.percentPrecision or defaults.percentPrecision or 0))
    local isPercent = resolvedDef.suffix == "%"
    local valueFormat = isPercent and ("%." .. precision .. "f%%") or "%.0f"
    -- Non-secret placeholder sized to the widest realistic value. ALL width and
    -- height measuring uses this string — never the Secret (see the value block).
    local placeholder = string.format(valueFormat, isPercent and 188.8 or 1888888)

    local segments = {}
    local textHeight = 0

    local statLabel = addon:GetStatLabel(entry.key, profile, resolvedDef)
    if profile.showLabels and statLabel and statLabel ~= "" then
        measureLine:SetText(statLabel)
        textHeight = math.max(textHeight, measureLine:GetStringHeight())
        table.insert(segments, {
            col = "label",
            text = statLabel,
            justify = "LEFT",
            width = GetStringWidth(measureLine),
        })
    end

    if profile.showValues ~= false then
        -- Measure width/height from the non-secret placeholder ONLY. We must
        -- never put the Secret on measureLine: a FontString that has held secret
        -- text returns a Secret width/height afterwards, and SetText does NOT
        -- clear that aspect, so it would poison every later measurement (this
        -- line shares measureLine with all other rows). The real Secret is
        -- written straight to the row FontString via SetFormattedText at draw
        -- time and is never measured.
        measureLine:SetText(placeholder)
        textHeight = math.max(textHeight, measureLine:GetStringHeight())

        table.insert(segments, {
            col = "value",
            secret = true,
            secretFormat = valueFormat,
            secretValue = secretValue,
            justify = "RIGHT",
            width = GetStringWidth(measureLine),
        })
    end

    if #segments == 0 then
        return nil
    end

    if textHeight <= 0 then
        measureLine:SetText("0")
        textHeight = measureLine:GetStringHeight()
    end

    local iconSize = 0
    if profile.showStatIcons == true and resolvedDef.icon then
        iconSize = math.max(MIN_DYNAMIC_FONT_SIZE, math.ceil(textHeight))
    end

    return {
        entry = entry,
        def = resolvedDef,
        -- Benign statResult: live (not stale, so ResolveSegmentColor won't dim)
        -- and carries no rating/value/dr for the hover/reference paths to read.
        statResult = { key = entry.key, source = "live_secret", stale = false, secret = true },
        drPenalty = nil,
        textHeight = textHeight,
        iconSize = iconSize,
        segments = segments,
    }
end

-- Measure every visible stat into a segment list with per-segment widths.
-- measured = {
--   entry, def, statResult, drPenalty, textHeight,
--   iconSize,                 -- icon px (0 if none)
--   segments = { {col,text,color,justify,width}, ... },
-- }
local function BuildMeasuredStats(addon, statsReader, statDefinitions, visibleStats, profile, defaults, measureLine)
    local measuredStats = {}
    local maxLineHeight = 0

    for _, entry in ipairs(visibleStats) do
        local def = statDefinitions[entry.key]

        -- In combat / M+ / encounter / PvP the live stat value is a Secret we
        -- cannot read or format in Lua. Render it live but stripped down (label
        -- + raw number via SetFormattedText) instead of the stale snapshot.
        -- Stats that never go Secret (durability / ilvl / gold) report no secret
        -- here and fall through to the full formatted path.
        local hasSecret, secretValue = false, nil
        if statsReader and statsReader.ReadSecretPassthrough then
            local okSecret, isSecretLive, rawSecret = pcall(statsReader.ReadSecretPassthrough, entry.key)
            if okSecret and isSecretLive then
                hasSecret, secretValue = true, rawSecret
            end
        end

        if hasSecret then
            local measured = BuildSecretMeasuredStat(addon, entry, def, profile, defaults, measureLine, secretValue)
            if measured then
                table.insert(measuredStats, measured)
                maxLineHeight = math.max(maxLineHeight, math.ceil(measured.textHeight))
            end
        else
            local readOk, statResult = pcall(function()
                return statsReader and statsReader.ReadStat and statsReader.ReadStat(entry.key)
            end)
            if readOk and statResult and statResult.value ~= nil then
                local segOk, segments = pcall(function()
                    return addon:BuildStatSegments(entry.key, statResult, profile, def)
                end)
                if segOk and segments and #segments > 0 then
                    local measuredSegments = {}
                    local textHeight = 0
                    for _, seg in ipairs(segments) do
                        local width
                        if seg.col == "ref_arrow" then
                            width = RefArrowSegmentWidth(seg)
                            textHeight = math.max(textHeight, width)
                        else
                            measureLine:SetText(seg.text or "")
                            textHeight = math.max(textHeight, measureLine:GetStringHeight())
                            width = GetStringWidth(measureLine)
                        end
                        table.insert(measuredSegments, {
                            col = seg.col,
                            text = seg.text or "",
                            texture = seg.texture,
                            textureSize = seg.textureSize,
                            color = seg.color,
                            justify = seg.justify or "LEFT",
                            drFlag = seg.drFlag,
                            width = width,
                        })
                    end
                    if textHeight <= 0 then
                        measureLine:SetText("0")
                        textHeight = measureLine:GetStringHeight()
                    end

                    local iconSize = 0
                    if profile.showStatIcons == true and def and def.icon then
                        iconSize = math.max(MIN_DYNAMIC_FONT_SIZE, math.ceil(textHeight))
                    end

                    table.insert(measuredStats, {
                        entry = entry,
                        def = def,
                        statResult = statResult,
                        drPenalty = statResult and statResult.dr and statResult.dr.penalty or nil,
                        textHeight = textHeight,
                        iconSize = iconSize,
                        segments = measuredSegments,
                    })
                    maxLineHeight = math.max(maxLineHeight, math.ceil(textHeight))
                end
            end
        end
    end

    return measuredStats, maxLineHeight
end

-- Layout model: three zones laid left-to-right inside a display column.
--   [icon] [label] [ BAND ] [ TAIL ]
-- BAND  = rating / sep / percent, internally grid-aligned and right-aligned
--         within a zone of width max(bandWidth, valueWidth). The non-rating
--         "value" cell is right-aligned to the same zone.
-- TAIL  = dr + ref, drawn tight together per row and right-aligned within a
--         zone of width = max over rows of (dr + gap? + ref). Because TAIL is a
--         single right-aligned zone, a DR suffix on one row never pushes the
--         ref column of other rows — it just makes that row's tail longer.
--
-- ComputeColumnMetrics returns everything the offset/draw passes need:
--   sub        -- [col] = max width of that sub-column (rating/sep/percent/label/value)
--   iconWidth  -- max icon px (0 if none)
--   bandWidth  -- rating+sep+percent grid width
--   valueWidth -- max non-rating value width
--   bandZone   -- max(bandWidth, valueWidth)
--   tailZone   -- max per-row (dr + ref) width
local function ComputeColumnMetrics(measuredStats, startIndex, count, profile, defaults)
    local sub = {}
    local iconWidth = 0
    local tailZone = 0
    local compact = profile and profile.compactValueColumns == true
    local compactWidth = 0

    for offset = 0, count - 1 do
        local measured = measuredStats[startIndex + offset]
        if measured then
            iconWidth = math.max(iconWidth, measured.iconSize or 0)
            if compact then
                compactWidth = math.max(compactWidth, MeasureCompactRowWidth(measured.segments))
            else
                for _, seg in ipairs(measured.segments) do
                    if not TAIL_COLUMNS[seg.col] then
                        sub[seg.col] = math.max(sub[seg.col] or 0, seg.width)
                    end
                end
                local rowTail = MeasureTailWidth(measured.segments)
                tailZone = math.max(tailZone, rowTail)
            end
        end
    end

    if compact then
        return {
            sub = sub,
            iconWidth = iconWidth,
            bandWidth = 0,
            valueWidth = 0,
            bandZone = 0,
            tailZone = 0,
            compact = true,
            compactWidth = compactWidth,
        }
    end

    local bandWidth = 0
    local bandCols = 0
    for _, key in ipairs(VALUE_SPAN) do
        if sub[key] then
            bandWidth = bandWidth + sub[key]
            bandCols = bandCols + 1
        end
    end
    if bandCols > 0 then
        bandWidth = bandWidth + (bandCols - 1) * SUBCOL_GAP
    end

    local valueWidth = sub.value or 0
    local minValueColumnWidth = math.max(0, math.floor((profile and profile.valueColumnWidth)
        or (defaults and defaults.valueColumnWidth) or 0))
    local bandZone = math.max(bandWidth, valueWidth, minValueColumnWidth)

    return {
        sub = sub,
        iconWidth = iconWidth,
        bandWidth = bandWidth,
        valueWidth = valueWidth,
        bandZone = bandZone,
        tailZone = tailZone,
    }
end

-- Compute X offsets (relative to the content box, after the icon) for the band
-- sub-columns and the value/tail zone starts. Returns offsets table + total
-- content width (excluding icon advance).
--   offsets.rating/sep/percent  -- band sub-column left edges
--   offsets.value               -- value cell left edge (right-aligned in band zone)
--   offsets.tail                -- tail zone left edge
--   offsets.tailZone            -- tail zone width (for right-alignment in draw)
local function ComputeColumnOffsets(metrics)
    if metrics.compact then
        return {}, metrics.compactWidth or 0
    end

    local offsets = {}
    local sub = metrics.sub
    local x = 0
    local placed = false

    -- label
    if sub.label and sub.label > 0 then
        offsets.label = x
        x = x + sub.label
        placed = true
    end

    -- band zone (rating/sep/percent right-aligned within bandZone; value too)
    if metrics.bandZone > 0 then
        if placed then
            x = x + SUBCOL_GAP
        end
        local zoneStart = x
        local bandStart = zoneStart + (metrics.bandZone - metrics.bandWidth)
        local bx = bandStart
        for _, bkey in ipairs(VALUE_SPAN) do
            local bw = sub[bkey]
            if bw then
                offsets[bkey] = bx
                bx = bx + bw + SUBCOL_GAP
            end
        end
        offsets.value = zoneStart + (metrics.bandZone - metrics.valueWidth)
        x = zoneStart + metrics.bandZone
        placed = true
    end

    -- tail zone (dr+ref right-aligned within tailZone)
    if metrics.tailZone > 0 then
        if placed then
            x = x + SUBCOL_GAP
        end
        offsets.tail = x
        offsets.tailZone = metrics.tailZone
        x = x + metrics.tailZone
    end

    return offsets, x
end

local function BuildRenderLayout(addon, profile, defaults, measuredStats, maxLineHeight, fontSize, controlsWidth, controlsHeight, controlsGap)
    local actualColumns, columnItemCounts = addon:GetDisplayLayout(profile, #measuredStats)
    local rowHeight = math.max(maxLineHeight, fontSize)
    local rowGap = math.max(0, math.floor(profile.rowGap or defaults.rowGap or 0))
    local columnGap = math.max(0, math.floor(profile.columnGap or defaults.columnGap or 0))
    local controlsPosition = profile.frameControlsPosition or defaults.frameControlsPosition or "BOTTOM"
    local controlsOnLeft = controlsPosition == "LEFT"
    local controlsOnRight = controlsPosition == "RIGHT"
    local controlsOnTop = controlsPosition == "TOP"
    local controlsOnBottom = not controlsOnLeft and not controlsOnRight and not controlsOnTop

    local contentX = LAYOUT.leftPadding + (controlsOnLeft and (controlsWidth + controlsGap) or 0)
    local contentY = LAYOUT.topPadding + (controlsOnTop and (controlsHeight + controlsGap) or 0)

    local rows = {}
    local itemIndex = 1
    local currentXOffset = contentX
    local maxRows = 0
    local columnContentWidths = {}

    for columnIndex = 1, actualColumns do
        local rowCount = columnItemCounts[columnIndex] or 0
        maxRows = math.max(maxRows, rowCount)

        local metrics = ComputeColumnMetrics(measuredStats, itemIndex, rowCount, profile, defaults)
        local subOffsets, subContentWidth = ComputeColumnOffsets(metrics)
        local iconWidth = metrics.iconWidth
        local iconAdvance = iconWidth > 0 and (iconWidth + LAYOUT.iconGap) or 0
        local columnContentWidth = iconAdvance + subContentWidth
        columnContentWidths[columnIndex] = math.max(columnContentWidth, LAYOUT.minColumnWidth)

        for rowIndex = 1, rowCount do
            local measured = measuredStats[itemIndex]
            if measured then
                table.insert(rows, {
                    index = itemIndex,
                    measured = measured,
                    x = currentXOffset,
                    y = contentY + (rowIndex - 1) * (rowHeight + rowGap),
                    height = rowHeight,
                    iconWidth = iconWidth,
                    iconAdvance = iconAdvance,
                    metrics = metrics,
                    subOffsets = subOffsets,
                    columnWidth = columnContentWidths[columnIndex],
                })
            end
            itemIndex = itemIndex + 1
        end

        currentXOffset = currentXOffset + columnContentWidths[columnIndex] + columnGap
    end

    local contentWidth = 0
    for columnIndex = 1, actualColumns do
        contentWidth = contentWidth + (columnContentWidths[columnIndex] or 0)
    end
    if actualColumns > 1 then
        contentWidth = contentWidth + (actualColumns - 1) * columnGap
    end

    local contentHeight = 0
    if maxRows > 0 then
        contentHeight = maxRows * rowHeight + math.max(0, maxRows - 1) * rowGap
    end

    local controlsX = LAYOUT.leftPadding
    local controlsY = LAYOUT.topPadding
    local frameContentWidth
    local frameContentHeight

    if controlsOnLeft then
        frameContentWidth = controlsWidth + controlsGap + contentWidth
    elseif controlsOnRight then
        controlsX = LAYOUT.leftPadding + contentWidth + controlsGap
        frameContentWidth = contentWidth + controlsGap + controlsWidth
    else
        frameContentWidth = math.max(contentWidth, controlsWidth)
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

local function ResolveSegmentColor(addon, measured, seg, profile, classColor)
    -- ref segments carry their own color verbatim.
    if seg.color then
        return seg.color[1], seg.color[2], seg.color[3]
    end

    local color = classColor or measured.entry.color
    local r, g, b = color[1], color[2], color[3]

    -- DR coloring: only segments explicitly flagged (percent/value + the DR tag)
    -- are tinted by penalty severity. The percent shown is the real post-DR
    -- value; the color simply signals it is being diminished.
    if seg.drFlag and measured.drPenalty then
        r, g, b = addon:GetDRColor(color, measured.drPenalty)
    end

    -- Dim value segments when the stat isn't live (stale snapshot / cache).
    local sr = measured.statResult
    if sr and STALE_DIM_COLUMNS[seg.col]
        and (sr.source == "snapshot" or sr.source == "cache" or sr.stale == true) then
        r, g, b = r * STALE_DIM_FACTOR, g * STALE_DIM_FACTOR, b * STALE_DIM_FACTOR
    end

    return r, g, b
end

local function ApplyRenderRows(addon, statsFrame, lines, renderRows, lineOverlays, layout, fontPath, fontSize, fontFlags, profile, classColor)
    for _, rowLayout in ipairs(layout.rows) do
        local measured = rowLayout.measured
        local row = renderRows and renderRows[rowLayout.index]
        if measured and row then
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", statsFrame, "TOPLEFT", rowLayout.x, -rowLayout.y)
            row:SetSize(rowLayout.columnWidth, rowLayout.height)
            row.statKey = measured.entry.key
            row:Show()

            -- Icon.
            if rowLayout.iconWidth > 0 and measured.iconSize > 0 and measured.def and measured.def.icon and row.icon then
                row.icon:SetTexture(measured.def.icon)
                row.icon:SetSize(measured.iconSize, measured.iconSize)
                row.icon:ClearAllPoints()
                row.icon:SetPoint("LEFT", row, "LEFT", 0, 0)
                row.icon:Show()
            elseif row.icon then
                row.icon:Hide()
            end

            local baseX = rowLayout.iconAdvance
            local metrics = rowLayout.metrics
            local sub = metrics.sub
            local subOffsets = rowLayout.subOffsets

            -- Pre-measure this row's tail width so we can right-align it in the zone.
            local rowTailWidth = MeasureTailWidth(measured.segments)
            local tailStart = (subOffsets.tail or 0) + (metrics.tailZone - rowTailWidth)
            local tailCursor = tailStart
            local prevTailCol

            local segIndex = 0
            local refArrowIndex = 0
            local pendingRefArrow = nil
            local compactCursor = 0
            local compactPrevCol
            for _, seg in ipairs(measured.segments) do
                local cellWidth, cellX
                if metrics.compact then
                    if compactPrevCol then
                        compactCursor = compactCursor + SegmentGap(compactPrevCol, seg.col)
                    end
                    cellWidth = seg.width
                    cellX = compactCursor
                    compactCursor = compactCursor + seg.width
                    compactPrevCol = seg.col
                elseif TAIL_COLUMNS[seg.col] then
                    cellWidth = seg.width
                    if prevTailCol then
                        tailCursor = tailCursor + TailSegmentGap(prevTailCol, seg.col)
                    end
                    cellX = tailCursor
                    tailCursor = tailCursor + seg.width
                    prevTailCol = seg.col
                elseif seg.col == "value" then
                    cellWidth = metrics.valueWidth
                    cellX = subOffsets.value or 0
                else
                    cellWidth = sub[seg.col] or seg.width
                    cellX = subOffsets[seg.col] or 0
                end

                local r, g, b = ResolveSegmentColor(addon, measured, seg, profile, classColor)

                if seg.col == "ref_arrow" and seg.texture then
                    pendingRefArrow = {
                        texture = seg.texture,
                        textureSize = seg.textureSize,
                        color = { r, g, b },
                    }
                else
                    segIndex = segIndex + 1
                    local fs = addon:AcquireRowSegment(row, segIndex)
                    if fs then
                        fs:SetFont(fontPath, fontSize, fontFlags)
                        fs:SetJustifyH(seg.justify)
                        fs:ClearAllPoints()
                        fs:SetPoint("LEFT", row, "LEFT", baseX + cellX, 0)
                        fs:SetWidth(math.max(1, cellWidth))
                        fs:SetHeight(math.max(1, rowLayout.height))
                        if fs.SetJustifyV then
                            fs:SetJustifyV("MIDDLE")
                        end
                        fs:SetTextColor(r, g, b, 1)
                        if seg.secret then
                            -- Live Secret value: the engine formats it; Lua never reads it.
                            if not pcall(fs.SetFormattedText, fs, seg.secretFormat, seg.secretValue) then
                                fs:SetText("")
                            end
                        else
                            fs:SetText(seg.text)
                        end
                        fs:Show()

                        if seg.col == "ref" and pendingRefArrow then
                            refArrowIndex = refArrowIndex + 1
                            local tex = addon:AcquireRowRefArrow(row, refArrowIndex)
                            if tex then
                                local size = pendingRefArrow.textureSize or 0
                                tex:SetTexture(pendingRefArrow.texture)
                                tex:SetSize(size, size)
                                tex:ClearAllPoints()
                                tex:SetPoint("CENTER", fs, "LEFT", -(REF_ARROW_NUM_GAP + (size * 0.5)), 0)
                                local cr, cg, cb = pendingRefArrow.color[1], pendingRefArrow.color[2], pendingRefArrow.color[3]
                                tex:SetVertexColor(cr, cg, cb, 1)
                                tex:Show()
                            end
                            pendingRefArrow = nil
                        end
                    end
                end
            end
            addon:HideRowSegmentsFrom(row, segIndex + 1)
            addon:HideRowRefArrowsFrom(row, refArrowIndex + 1)

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

-- Text alignment is now expressed per sub-column inside the grid, so a change
-- to the profile textAlign just re-runs a full layout pass.
function Addon:ApplyTextAlignmentToVisibleLines()
    if self.initialized then
        self:RefreshStats()
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
    local classColor = profile.useClassColor and self:GetPlayerClassColor() or nil
    local controlsWidth, controlsHeight, controlsGap = self:GetFrameControlsSize()
    -- Signature kept for potential future caching; layout itself is now fully
    -- deterministic from measured widths, so no reserved-width memo is needed.
    BuildLayoutSignature(self, profile, defaults, fontSize, textAlign, visibleStats)

    ResetRenderWidgets(self, lines, lineOverlays, renderRows)

    measureLine:SetFont(fontPath, fontSize, fontFlags)
    local measuredStats, maxLineHeight = BuildMeasuredStats(self, ns.Stats, self.StatDefinitions, visibleStats, profile, defaults, measureLine)
    local layout = BuildRenderLayout(self, profile, defaults, measuredStats, maxLineHeight, fontSize, controlsWidth, controlsHeight, controlsGap)
    ApplyRenderRows(self, statsFrame, lines, renderRows, lineOverlays, layout, fontPath, fontSize, fontFlags, profile, classColor)
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
                print(self:S("NE_STATS_REFRESH_FAILED", displayError))
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
