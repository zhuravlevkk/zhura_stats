local _, ns = ...

ns = ns or {}
ns.ZhuraStats = ns.ZhuraStats or {}
local Addon = ns.ZhuraStats

local statsFrame
local statsAnchor
local lockButton
local isStatsFrameHovered = false
local isLockButtonHovered = false
local lines = {}
local measureLine

function Addon:GetFrameRefs()
    return statsFrame, statsAnchor, lockButton
end

function Addon:GetRenderWidgets()
    return lines, measureLine
end

function Addon:SaveFramePosition()
    if not statsAnchor then
        return
    end

    local profile = self:GetProfile()
    local defaults = self.Defaults.profile
    local point, relativeTo, relativePoint, x, y = statsAnchor:GetPoint(1)
    profile.point = point or defaults.point
    profile.relativeTo = relativeTo and relativeTo:GetName() or defaults.relativeTo
    profile.relativePoint = relativePoint or defaults.relativePoint
    profile.x = x or 0
    profile.y = y or 0
end

function Addon:UpdateFrameLockState()
    if not statsFrame or not statsAnchor then
        return
    end

    local profile = self:GetProfile()
    local locked = self:GetProfileValue("locked")
    statsAnchor:EnableMouse(true)
    statsFrame:SetBackdropColor(0, 0, 0, 0)
    statsFrame:SetBackdropBorderColor(0, 0, 0, 0)

    if lockButton then
        if locked then
            lockButton:SetNormalTexture("Interface\\BUTTONS\\LockButton-Locked-Up")
            lockButton:SetPushedTexture("Interface\\BUTTONS\\LockButton-Locked-Down")
        else
            lockButton:SetNormalTexture("Interface\\BUTTONS\\LockButton-Unlocked-Up")
            lockButton:SetPushedTexture("Interface\\BUTTONS\\LockButton-Unlocked-Down")
        end
        lockButton:SetHighlightTexture("Interface\\BUTTONS\\UI-Panel-MinimizeButton-Highlight")
        lockButton:SetShown((not self:GetProfileValue("showLockOnHover")) or isStatsFrameHovered or isLockButtonHovered)
    end
end

function Addon:ApplyFrameStyle()
    if not statsFrame or not statsAnchor then
        return
    end

    local profile = self:GetProfile()
    local defaults = self.Defaults.profile
    statsFrame:SetScale(profile.scale or defaults.scale)
    statsFrame:SetAlpha(profile.alpha)
    statsAnchor:ClearAllPoints()
    statsAnchor:SetPoint(
        profile.point or defaults.point,
        _G[profile.relativeTo or defaults.relativeTo] or UIParent,
        profile.relativePoint or defaults.relativePoint,
        profile.x or defaults.x,
        profile.y or defaults.y
    )
    statsFrame:ClearAllPoints()
    statsFrame:SetPoint("TOPLEFT", statsAnchor, "TOPLEFT", 0, 0)
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
    statsAnchor:SetScript("OnDragStart", function(self)
        if not Addon:GetProfileValue("locked") then
            self:StartMoving()
        end
    end)
    statsAnchor:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        Addon:SaveFramePosition()
    end)

    lockButton = CreateFrame("Button", nil, statsFrame, "UIPanelButtonTemplate")
    lockButton:SetSize(20, 20)
    lockButton:SetPoint("TOPRIGHT", -6, -6)
    lockButton:SetFrameLevel(statsAnchor:GetFrameLevel() + 10)
    lockButton:SetText("")
    lockButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    lockButton:SetScript("OnEnter", function(self)
        isLockButtonHovered = true
        Addon:UpdateFrameLockState()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
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

    local statKeys = Addon.Constants.STAT_KEYS
    for index = 1, #statKeys + 1 do
        local line = statsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        line:SetJustifyH("LEFT")
        line:SetShadowOffset(1, -1)
        lines[index] = line
    end

    measureLine = statsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    measureLine:Hide()
end
