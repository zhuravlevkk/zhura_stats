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
local FRAME_CONTROLS_WIDTH = 84
local FRAME_CONTROLS_HEIGHT = 20
local FRAME_CONTROLS_GAP = 4

local FRAME_ANCHOR_BY_TEXT_ALIGN = {
    LEFT = "BOTTOMLEFT",
    CENTER = "BOTTOM",
    RIGHT = "BOTTOMRIGHT",
}

local function GetFrameAnchorPoint(profile, defaults)
    local align = (profile and profile.textAlign) or (defaults and defaults.textAlign) or "LEFT"
    return FRAME_ANCHOR_BY_TEXT_ALIGN[align] or "BOTTOMLEFT"
end

local function GetCurrentAnchorOffsets(frame, anchorPoint, relativeTo)
    if not frame or not frame:GetLeft() then
        return nil, nil
    end

    relativeTo = relativeTo or UIParent
    local relLeft = relativeTo:GetLeft() or 0
    local relRight = relativeTo:GetRight() or (relLeft + (relativeTo:GetWidth() or 0))
    local relBottom = relativeTo:GetBottom() or 0
    local frameLeft = frame:GetLeft() or 0
    local frameRight = frame:GetRight() or frameLeft
    local frameBottom = frame:GetBottom() or 0

    if anchorPoint == "BOTTOMRIGHT" then
        return frameRight - relRight, frameBottom - relBottom
    end

    if anchorPoint == "BOTTOM" then
        local relCenter = relLeft + ((relativeTo:GetWidth() or 0) / 2)
        local frameCenter = frameLeft + ((frameRight - frameLeft) / 2)
        return frameCenter - relCenter, frameBottom - relBottom
    end

    return frameLeft - relLeft, frameBottom - relBottom
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

function Addon:GetFrameControlsSize()
    return FRAME_CONTROLS_WIDTH, FRAME_CONTROLS_HEIGHT, FRAME_CONTROLS_GAP
end

function Addon:LayoutFrameControls(xOffset, yOffset)
    if not lockButton or not priorityModeControls then
        return
    end

    priorityModeControls:ClearAllPoints()
    priorityModeControls:SetPoint("TOPLEFT", statsFrame, "TOPLEFT", xOffset, -yOffset)

    lockButton:ClearAllPoints()
    lockButton:SetPoint("TOPLEFT", priorityModeControls, "TOPRIGHT", 2, 0)
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

    local controlsVisible = (not self:GetProfileValue("showLockOnHover")) or isStatsFrameHovered or isLockButtonHovered or isPriorityModeHovered

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
        print(self:S("NE Stats: frame locked. Use settings to unlock and adjust it."))
    else
        print(self:S("NE Stats: frame unlocked. Drag it, then lock when ready."))
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
    local defaults = self.Defaults.profile
    local tooltipMode = (profile.referenceDisplay or defaults.referenceDisplay or "off") == "tooltip"
    local archonMode = self:NormalizeStatPriorityMode(profile.statPriorityMode or defaults.statPriorityMode or "manual") ~= "manual"
    local active = tooltipMode and archonMode
    for _, overlay in ipairs(lineOverlays) do
        overlay:EnableMouse(active and overlay:IsShown())
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
    lockButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    lockButton:SetScript("OnEnter", function(btn)
        isLockButtonHovered = true
        Addon:UpdateFrameLockState()
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        GameTooltip:SetText(Addon:S("Lock button"), 1, 0.82, 0)
        GameTooltip:AddLine(Addon:S("Left-click: lock or unlock the frame."), 1, 1, 1, true)
        GameTooltip:AddLine(Addon:S("Right-click: open addon settings."), 1, 1, 1, true)
        GameTooltip:Show()
    end)
    lockButton:SetScript("OnLeave", function()
        isLockButtonHovered = false
        GameTooltip:Hide()
        Addon:UpdateFrameLockState()
    end)
    lockButton:SetScript("OnClick", function(_, button)
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
            title = "User priority",
            body = "Manual stat order from settings.",
        },
        {
            id = "archon_raid",
            text = "R",
            title = "Archon Raid",
            body = "Use Archon Raid stat priority for display order.",
        },
        {
            id = "archon_mplus",
            text = "M",
            title = "Archon Mythic+",
            body = "Use Archon Mythic+ stat priority for display order.",
        },
    }

    for index, config in ipairs(modeButtons) do
        local button = CreateFrame("Button", nil, priorityModeControls, "UIPanelButtonTemplate")
        button:SetSize(18, 18)
        button:SetPoint("LEFT", priorityModeControls, "LEFT", (index - 1) * 21, 0)
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
        row.text = line
        lines[index] = line

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
            if not Addon:IsArchonReferenceStatKey(key) then
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
