local _, ns = ...

ns = ns or {}
ns.ZhuraStats = ns.ZhuraStats or {}
local Addon = ns.ZhuraStats

local statsFrame
local statsAnchor
local lockButton
local priorityModeButtons = {}
local priorityModeControls
local isStatsFrameHovered = false
local isLockButtonHovered = false
local isPriorityModeHovered = false
local renderRows = {}
local lines = {}
local lineOverlays = {}
local measureLine
local PRIORITY_BUTTON_SIZE = 18
local PRIORITY_BUTTON_GAP = 3
local LOCK_BUTTON_SIZE = 20
local LOCK_BUTTON_GAP = 2
local FRAME_CONTROLS_GAP = 4

local glyphDebugFrame
local lockButtonMiddleClickCount = 0
local lockButtonMiddleClickTime = 0
local LOCK_BUTTON_TRIPLE_CLICK_WINDOW = 0.5

-- Arrow glyph candidates for in-game font/texture comparison (3x middle-click lock).
local GLYPH_DEBUG_CANDIDATES = {
    { label = "U+2191", text = "\226\134\145" },
    { label = "U+2193", text = "\226\134\147" },
    { label = "U+25B2", text = "\226\150\178" },
    { label = "U+25BC", text = "\226\150\188" },
    { label = "U+2B06", text = "\226\172\134" },
    { label = "U+2B07", text = "\226\172\135" },
    { label = "ASCII ^", text = "^" },
    { label = "ASCII v", text = "v" },
    { label = "U+203A", text = "\226\128\186" },
    { label = "U+2039", text = "\226\128\185" },
}

local GLYPH_DEBUG_TEXTURES = {
    { label = "Zhura RefArrowUp", text = "|TInterface\\AddOns\\ZhuraStats\\Media\\RefArrowUp:16:16:0:0|t" },
    { label = "Zhura RefArrowDown", text = "|TInterface\\AddOns\\ZhuraStats\\Media\\RefArrowDown:16:16:0:0|t" },
    { label = "Arrow-Up-Up", text = "|TInterface\\Buttons\\Arrow-Up-Up:16:16:0:0|t" },
    { label = "Arrow-Down-Up", text = "|TInterface\\Buttons\\Arrow-Down-Up:16:16:0:0|t" },
    { label = "ScrollUpButton", text = "|TInterface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up:16:16:0:0|t" },
    { label = "ScrollDownButton", text = "|TInterface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up:16:16:0:0|t" },
}

local function ApplyGlyphDebugFont()
    if not glyphDebugFrame then
        return
    end
    local profile = Addon:GetProfile()
    local defaults = Addon.Defaults and Addon.Defaults.profile
    local fontKey = (profile and profile.fontKey) or (defaults and defaults.fontKey)
    local fontPath, fontFlags = Addon:GetFontInfo(fontKey)
    local fontSize = (profile and profile.fontSize) or (defaults and defaults.fontSize) or 12

    if glyphDebugFrame.title then
        glyphDebugFrame.title:SetFont(fontPath, fontSize, fontFlags)
    end
    for _, row in ipairs(glyphDebugFrame.rows or {}) do
        if row.sample then
            row.sample:SetFont(fontPath, fontSize, fontFlags)
        end
    end
end

local function EnsureGlyphDebugFrame()
    if glyphDebugFrame then
        return glyphDebugFrame
    end

    local rowCount = #GLYPH_DEBUG_CANDIDATES + #GLYPH_DEBUG_TEXTURES + 2
    local frame = CreateFrame("Frame", "ZhuraStatsGlyphDebugFrame", UIParent, "BackdropTemplate")
    frame:SetSize(340, 48 + (rowCount * 20))
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    frame:SetFrameStrata("DIALOG")
    frame:EnableMouse(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", frame, "TOP", 0, -10)
    title:SetText("Arrow glyph debug — 3x middle-click lock to close")
    frame.title = title

    frame.rows = {}
    local y = -34

    local function addRow(labelText, sampleText)
        local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        label:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, y)
        label:SetWidth(130)
        label:SetJustifyH("LEFT")
        label:SetText(labelText)

        local sample = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        sample:SetPoint("LEFT", label, "RIGHT", 8, 0)
        sample:SetJustifyH("LEFT")
        sample:SetText(sampleText)

        table.insert(frame.rows, { sample = sample })
        y = y - 20
    end

    addRow("— font glyphs —", "")
    for _, entry in ipairs(GLYPH_DEBUG_CANDIDATES) do
        addRow(entry.label, entry.text .. " 123")
    end

    addRow("— textures —", "")
    for _, entry in ipairs(GLYPH_DEBUG_TEXTURES) do
        addRow(entry.label, entry.text .. " 123")
    end

    local closeBtn = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
    closeBtn:SetScript("OnClick", function()
        frame:Hide()
    end)

    glyphDebugFrame = frame
    return frame
end

local function ToggleGlyphDebugPanel()
    local frame = EnsureGlyphDebugFrame()
    ApplyGlyphDebugFont()
    if frame:IsShown() then
        frame:Hide()
    else
        frame:Show()
    end
end

local function HandleLockButtonMiddleClick()
    local now = GetTime()
    if now - lockButtonMiddleClickTime > LOCK_BUTTON_TRIPLE_CLICK_WINDOW then
        lockButtonMiddleClickCount = 0
    end
    lockButtonMiddleClickCount = lockButtonMiddleClickCount + 1
    lockButtonMiddleClickTime = now
    if lockButtonMiddleClickCount >= 3 then
        lockButtonMiddleClickCount = 0
        ToggleGlyphDebugPanel()
    end
end

-- The stat block is anchored by its TOP edge so that adding rows or widening a
-- row (e.g. a DR suffix appearing) grows the frame downward / sideways away
-- from the anchor, never shifting the anchor point itself.
--   LEFT   -> top-left  pinned, grows right & down
--   CENTER -> top-center pinned, grows symmetrically & down
--   RIGHT  -> top-right pinned, grows left & down
local FRAME_ANCHOR_BY_TEXT_ALIGN = {
    LEFT = "TOPLEFT",
    CENTER = "TOP",
    RIGHT = "TOPRIGHT",
}

local function GetFrameAnchorPoint(profile, defaults)
    local align = (profile and profile.textAlign) or (defaults and defaults.textAlign) or "LEFT"
    return FRAME_ANCHOR_BY_TEXT_ALIGN[align] or "TOPLEFT"
end

local function GetCurrentAnchorOffsets(frame, anchorPoint, relativeTo)
    if not frame or not frame:GetLeft() then
        return nil, nil
    end

    relativeTo = relativeTo or UIParent
    local relLeft = relativeTo:GetLeft() or 0
    local relRight = relativeTo:GetRight() or (relLeft + (relativeTo:GetWidth() or 0))
    local relTop = relativeTo:GetTop() or 0
    local frameLeft = frame:GetLeft() or 0
    local frameRight = frame:GetRight() or frameLeft
    local frameTop = frame:GetTop() or 0

    -- All anchor points pin the TOP edge; only the horizontal reference differs.
    if anchorPoint == "TOPRIGHT" then
        return frameRight - relRight, frameTop - relTop
    end

    if anchorPoint == "TOP" then
        local relCenter = relLeft + ((relativeTo:GetWidth() or 0) / 2)
        local frameCenter = frameLeft + ((frameRight - frameLeft) / 2)
        return frameCenter - relCenter, frameTop - relTop
    end

    return frameLeft - relLeft, frameTop - relTop
end

function Addon:GetFrameRefs()
    return statsFrame, statsAnchor, lockButton
end

function Addon:GetRenderWidgets()
    return lines, measureLine
end

function Addon:GetRenderRows()
    return renderRows
end

function Addon:GetLineOverlays()
    return lineOverlays
end

-- Lazily grow a row's segment FontString pool and return the Nth one,
-- reset to a clean state ready for SetText/SetPoint by the renderer.
function Addon:AcquireRowSegment(row, segIndex)
    if not row then
        return nil
    end
    row.segments = row.segments or {}
    local fs = row.segments[segIndex]
    if not fs then
        fs = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        fs:SetShadowOffset(1, -1)
        row.segments[segIndex] = fs
    end
    fs:ClearAllPoints()
    fs:SetText("")
    fs:SetWordWrap(false)
    fs:SetMaxLines(1)
    fs:Show()
    return fs
end

-- Hide all segment FontStrings on a row from index `fromIndex` onward (cleanup
-- for rows that now use fewer segments than a previous render).
function Addon:HideRowSegmentsFrom(row, fromIndex)
    if not row or not row.segments then
        return
    end
    for i = fromIndex, #row.segments do
        local fs = row.segments[i]
        if fs then
            fs:Hide()
            fs:ClearAllPoints()
            fs:SetText("")
        end
    end
end

-- Reference delta arrows use Texture (not FontString |T) for vertical centering and tinting.
function Addon:AcquireRowRefArrow(row, index)
    if not row then
        return nil
    end
    row.refArrows = row.refArrows or {}
    local tex = row.refArrows[index]
    if not tex then
        tex = row:CreateTexture(nil, "OVERLAY")
        if tex.SetBlendMode then
            tex:SetBlendMode("BLEND")
        end
        row.refArrows[index] = tex
    end
    tex:ClearAllPoints()
    tex:Show()
    return tex
end

function Addon:HideRowRefArrowsFrom(row, fromIndex)
    if not row or not row.refArrows then
        return
    end
    for i = fromIndex, #row.refArrows do
        local tex = row.refArrows[i]
        if tex then
            tex:Hide()
            tex:ClearAllPoints()
            tex:SetTexture(nil)
        end
    end
end

function Addon:GetFrameControlsSize()
    if self:GetProfileValue("showFrameControls") == false then
        return 0, 0, 0
    end

    local direction = self:GetProfileValue("frameControlsDirection") or self.Defaults.profile.frameControlsDirection
    local priorityCount = 3
    if direction == "VERTICAL" then
        local priorityHeight = (priorityCount * PRIORITY_BUTTON_SIZE) + ((priorityCount - 1) * PRIORITY_BUTTON_GAP)
        return LOCK_BUTTON_SIZE, priorityHeight + LOCK_BUTTON_GAP + LOCK_BUTTON_SIZE, FRAME_CONTROLS_GAP
    end

    local priorityWidth = (priorityCount * PRIORITY_BUTTON_SIZE) + ((priorityCount - 1) * PRIORITY_BUTTON_GAP)
    return priorityWidth + LOCK_BUTTON_GAP + LOCK_BUTTON_SIZE, LOCK_BUTTON_SIZE, FRAME_CONTROLS_GAP
end

function Addon:LayoutFrameControls(xOffset, yOffset)
    if not lockButton or not priorityModeControls then
        return
    end

    local direction = self:GetProfileValue("frameControlsDirection") or self.Defaults.profile.frameControlsDirection
    local priorityCount = 3
    local priorityWidth = (priorityCount * PRIORITY_BUTTON_SIZE) + ((priorityCount - 1) * PRIORITY_BUTTON_GAP)
    local priorityHeight = PRIORITY_BUTTON_SIZE
    if direction == "VERTICAL" then
        priorityWidth = PRIORITY_BUTTON_SIZE
        priorityHeight = (priorityCount * PRIORITY_BUTTON_SIZE) + ((priorityCount - 1) * PRIORITY_BUTTON_GAP)
    end

    priorityModeControls:ClearAllPoints()
    priorityModeControls:SetSize(priorityWidth, priorityHeight)
    priorityModeControls:SetPoint("TOPLEFT", statsFrame, "TOPLEFT", xOffset, -yOffset)

    local orderedModes = { "manual", "archon_raid", "archon_mplus" }
    for index, mode in ipairs(orderedModes) do
        local button = priorityModeButtons[mode]
        if button then
            button:ClearAllPoints()
            if direction == "VERTICAL" then
                button:SetPoint("TOPLEFT", priorityModeControls, "TOPLEFT", 0, -((index - 1) * (PRIORITY_BUTTON_SIZE + PRIORITY_BUTTON_GAP)))
            else
                button:SetPoint("LEFT", priorityModeControls, "LEFT", (index - 1) * (PRIORITY_BUTTON_SIZE + PRIORITY_BUTTON_GAP), 0)
            end
        end
    end

    lockButton:ClearAllPoints()
    if direction == "VERTICAL" then
        lockButton:SetPoint("TOPLEFT", priorityModeControls, "BOTTOMLEFT", 0, -LOCK_BUTTON_GAP)
    else
        lockButton:SetPoint("TOPLEFT", priorityModeControls, "TOPRIGHT", LOCK_BUTTON_GAP, 0)
    end
end

function Addon:SaveFramePosition()
    if not statsAnchor then
        return
    end

    local profile = self:GetProfile()
    local defaults = self.Defaults.profile
    local anchorPoint = GetFrameAnchorPoint(profile, defaults)
    local _, relativeTo, _, x, y = statsAnchor:GetPoint(1)
    local relativeFrame = relativeTo or (_G[defaults.relativeTo] or UIParent)
    local anchorX, anchorY = GetCurrentAnchorOffsets(statsAnchor, anchorPoint, relativeFrame)
    profile.point = anchorPoint
    profile.relativeTo = relativeFrame and relativeFrame:GetName() or defaults.relativeTo
    profile.relativePoint = anchorPoint
    profile.x = anchorX or x or 0
    profile.y = anchorY or y or 0
end

function Addon:UpdateFrameLockState()
    if not statsFrame or not statsAnchor then
        return
    end

    local locked = self:GetProfileValue("locked")
    statsAnchor:EnableMouse(true)
    statsFrame:SetBackdropColor(0, 0, 0, 0)
    statsFrame:SetBackdropBorderColor(0, 0, 0, 0)

    local controlsEnabled = self:GetProfileValue("showFrameControls") ~= false
    local controlsVisible = controlsEnabled and (
        (not self:GetProfileValue("showLockOnHover"))
        or isStatsFrameHovered
        or isLockButtonHovered
        or isPriorityModeHovered
    )

    if lockButton then
        if locked then
            lockButton:SetNormalTexture("Interface\\BUTTONS\\LockButton-Locked-Up")
            lockButton:SetPushedTexture("Interface\\BUTTONS\\LockButton-Locked-Down")
        else
            lockButton:SetNormalTexture("Interface\\BUTTONS\\LockButton-Unlocked-Up")
            lockButton:SetPushedTexture("Interface\\BUTTONS\\LockButton-Unlocked-Down")
        end
        lockButton:SetHighlightTexture("Interface\\BUTTONS\\UI-Panel-MinimizeButton-Highlight")
        lockButton:SetShown(controlsVisible)
    end

    if priorityModeControls then
        priorityModeControls:SetShown(controlsVisible)
    end
end

function Addon:RefreshPriorityModeButtons()
    if not priorityModeButtons then
        return
    end

    local activeMode = self:NormalizeStatPriorityMode(self:GetProfileValue("statPriorityMode") or "manual")
    for mode, button in pairs(priorityModeButtons) do
        if button then
            local isActive = mode == activeMode
            button.isActiveMode = isActive
            button:SetEnabled(true)
            button:SetAlpha(isActive and 1 or 0.45)
        end
    end
end

function Addon:ApplyFrameStyle()
    if not statsFrame or not statsAnchor then
        return
    end

    local profile = self:GetProfile()
    local defaults = self.Defaults.profile
    local anchorPoint = GetFrameAnchorPoint(profile, defaults)
    local relativeFrame = _G[profile.relativeTo or defaults.relativeTo] or UIParent
    if (profile.point or defaults.point) ~= anchorPoint then
        local x, y = GetCurrentAnchorOffsets(statsAnchor, anchorPoint, relativeFrame)
        if x and y then
            profile.x = x
            profile.y = y
        end
        profile.point = anchorPoint
        profile.relativePoint = anchorPoint
    end

    statsFrame:SetScale(profile.scale or defaults.scale)
    statsFrame:SetAlpha(profile.alpha)
    statsAnchor:ClearAllPoints()
    statsAnchor:SetPoint(
        anchorPoint,
        relativeFrame,
        anchorPoint,
        profile.x or defaults.x,
        profile.y or defaults.y
    )
    statsFrame:ClearAllPoints()
    statsFrame:SetPoint(anchorPoint, statsAnchor, anchorPoint, 0, 0)
    self:UpdateFrameLockState()
end

function Addon:ToggleLockState()
    local locked = not self:GetProfileValue("locked")
    self:SetProfileValue("locked", locked)
    self:UpdateFrameLockState()

    if locked then
        print(self:S("NE_STATS_FRAME_LOCKED"))
    else
        print(self:S("NE_STATS_FRAME_UNLOCKED"))
    end

    local refs = self:GetControlRefs()
    if refs.lockCheckbox then
        refs.lockCheckbox:SetChecked(locked)
    end
end

function Addon:UpdateTooltipOverlayVisibility()
    local profile = self:GetProfile()
    if not profile then
        return
    end
    for _, overlay in ipairs(lineOverlays) do
        local active = overlay:IsShown()
            and overlay.statKey
            and overlay.statResult
            and self:WantsReferenceTooltip(overlay.statKey, overlay.statResult, profile)
        overlay:EnableMouse(active == true)
    end
end

function Addon:EnsureStatsFrame()
    if statsFrame then
        return
    end

    statsAnchor = CreateFrame("Frame", "ZhuraStatsAnchor", UIParent)
    statsAnchor:SetClampedToScreen(true)
    statsAnchor:SetMovable(true)
    statsAnchor:RegisterForDrag("LeftButton")
    statsAnchor:EnableMouse(true)
    statsAnchor:SetScript("OnEnter", function()
        isStatsFrameHovered = true
        Addon:UpdateFrameLockState()
    end)
    statsAnchor:SetScript("OnLeave", function()
        isStatsFrameHovered = false
        Addon:UpdateFrameLockState()
    end)

    statsFrame = CreateFrame("Frame", "ZhuraStatsFrame", statsAnchor, "BackdropTemplate")
    statsFrame:SetBackdrop({
        bgFile = "Interface/Tooltips/UI-Tooltip-Background",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 10,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    statsFrame:EnableMouse(false)
    statsAnchor:SetScript("OnDragStart", function(anchor)
        if not Addon:GetProfileValue("locked") then
            anchor:StartMoving()
        end
    end)
    statsAnchor:SetScript("OnDragStop", function(anchor)
        anchor:StopMovingOrSizing()
        Addon:SaveFramePosition()
    end)

    lockButton = CreateFrame("Button", nil, statsFrame, "UIPanelButtonTemplate")
    lockButton:SetSize(20, 20)
    lockButton:SetFrameLevel(statsAnchor:GetFrameLevel() + 10)
    lockButton:SetText("")
    lockButton:RegisterForClicks("LeftButtonUp", "RightButtonUp", "MiddleButtonUp")
    lockButton:SetScript("OnEnter", function(btn)
        isLockButtonHovered = true
        Addon:UpdateFrameLockState()
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        GameTooltip:SetText(Addon:S("NE_STATS_LOCK_BUTTON"), 1, 0.82, 0)
        GameTooltip:AddLine(Addon:S("NE_STATS_LEFT_CLICK_LOCK_OR_UNLOCK_THE_FRAME"), 1, 1, 1, true)
        GameTooltip:AddLine(Addon:S("NE_STATS_RIGHT_CLICK_OPEN_ADDON_SETTINGS"), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    lockButton:SetScript("OnLeave", function()
        isLockButtonHovered = false
        GameTooltip:Hide()
        Addon:UpdateFrameLockState()
    end)
    lockButton:SetScript("OnClick", function(_, button)
        if button == "MiddleButton" then
            HandleLockButtonMiddleClick()
            return
        end
        if button == "RightButton" then
            Addon:OpenAddonSettings()
            return
        end
        Addon:ToggleLockState()
    end)

    priorityModeControls = CreateFrame("Frame", nil, statsFrame)
    priorityModeControls:SetSize(62, 20)
    priorityModeControls:SetFrameLevel(statsAnchor:GetFrameLevel() + 10)
    priorityModeControls:SetScript("OnEnter", function()
        isPriorityModeHovered = true
        Addon:UpdateFrameLockState()
    end)
    priorityModeControls:SetScript("OnLeave", function()
        isPriorityModeHovered = false
        GameTooltip:Hide()
        Addon:UpdateFrameLockState()
    end)

    local modeButtons = {
        {
            id = "manual",
            text = "U",
            title = "NE_STATS_USER_PRIORITY",
            body = "NE_STATS_MANUAL_PRIORITY_HINT",
        },
        {
            id = "archon_raid",
            text = "R",
            title = "NE_STATS_ARCHON_RAID",
            body = "NE_STATS_ARCHON_RAID_PRIORITY_HINT",
        },
        {
            id = "archon_mplus",
            text = "M",
            title = "NE_STATS_ARCHON_MYTHIC",
            body = "NE_STATS_ARCHON_MPLUS_PRIORITY_HINT",
        },
    }

    for index, config in ipairs(modeButtons) do
        local button = CreateFrame("Button", nil, priorityModeControls, "UIPanelButtonTemplate")
        button:SetSize(PRIORITY_BUTTON_SIZE, PRIORITY_BUTTON_SIZE)
        button:SetPoint("LEFT", priorityModeControls, "LEFT", (index - 1) * (PRIORITY_BUTTON_SIZE + PRIORITY_BUTTON_GAP), 0)
        button:SetText(config.text)
        button.mode = config.id
        button.tooltipTitle = config.title
        button.tooltipBody = config.body
        button:SetScript("OnEnter", function(btn)
            isPriorityModeHovered = true
            Addon:UpdateFrameLockState()
            GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
            GameTooltip:SetText(Addon:S(btn.tooltipTitle), 1, 0.82, 0)
            GameTooltip:AddLine(Addon:S(btn.tooltipBody), 1, 1, 1, true)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function()
            isPriorityModeHovered = false
            GameTooltip:Hide()
            Addon:UpdateFrameLockState()
        end)
        button:SetScript("OnClick", function(btn)
            if btn.isActiveMode then
                return
            end
            Addon:SetStatPriorityMode(btn.mode)
        end)
        priorityModeButtons[config.id] = button
    end
    self:RefreshPriorityModeButtons()
    self:UpdateFrameLockState()

    local statKeys = Addon.Constants.STAT_KEYS
    for index = 1, #statKeys + 1 do
        local row = CreateFrame("Frame", nil, statsFrame)
        row:Hide()
        renderRows[index] = row

        local icon = row:CreateTexture(nil, "OVERLAY")
        icon:SetPoint("LEFT", row, "LEFT", 0, 0)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        icon:Hide()
        row.icon = icon

        local line = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        line:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        line:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        line:SetJustifyH("LEFT")
        line:SetShadowOffset(1, -1)
        line:Hide() -- legacy single-string widget; segment FS below do the drawing
        row.text = line
        lines[index] = line

        -- Per-segment FontStrings. The renderer positions each one into its own
        -- aligned sub-column (rating / sep / percent / ref / ...). Pool is grown
        -- lazily via Addon:AcquireRowSegment so we never create more than used.
        row.segments = {}

        -- Invisible overlay frame for tooltip hit-testing.
        -- EnableMouse is toggled by UpdateTooltipOverlayVisibility — off by default
        -- so it never blocks drag or lock button interaction.
        local overlay = CreateFrame("Frame", nil, row)
        overlay:SetAllPoints(row)
        overlay:SetFrameLevel(statsFrame:GetFrameLevel() + 1)
        overlay:EnableMouse(false)
        row.overlay = overlay
        overlay:SetScript("OnEnter", function(frame)
            local key = frame.statKey
            if not key then
                return
            end
            local profile = Addon:GetProfile()
            if not profile then
                return
            end
            Addon:PopulateReferenceStatTooltip(frame, key, frame.statResult, profile)
        end)
        overlay:SetScript("OnLeave", function(frame)
            if GameTooltip and GameTooltip:GetOwner() == frame then
                GameTooltip:Hide()
            end
        end)
        lineOverlays[index] = overlay
    end

    measureLine = statsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    measureLine:Hide()
end
