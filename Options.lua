local _, ns = ...

ns = ns or {}
ns.ZhuraStats = ns.ZhuraStats or {}
local Addon = ns.ZhuraStats

local ADDON_NAME_FALLBACK = "ZhuraStats"

local optionsPanel
local optionsCategory
local optionsCategoryID
local optionsPanelBuilt = false
local lastOptionsPanelError
local rowControls = {}
local controlRefs = {}
local activeTab = "profiles"
local statDragState = { active = false }
local localizedWidgets = {}

local function BindLocalizedText(widget, localeKey)
    if not widget or not localeKey then
        return widget
    end
    localizedWidgets[#localizedWidgets + 1] = { widget = widget, key = localeKey }
    widget:SetText(Addon:S(localeKey))
    return widget
end

local TAB_ORDER = { "profiles", "display", "stats" }
local TAB_LABELS = {
    profiles = "NE_STATS_PROFILES",
    display = "NE_STATS_DISPLAY",
    stats = "NE_STATS_STATS",
}

local PRIORITY_MODE_OPTIONS = {
    { value = "manual", label = "NE_STATS_PRIORITY_MODE_MANUAL" },
    { value = "archon_raid", label = "NE_STATS_PRIORITY_MODE_RAID" },
    { value = "archon_mplus", label = "NE_STATS_PRIORITY_MODE_MPLUS" },
}

local REFERENCE_DISPLAY_OPTIONS = {
    { value = "off", label = "NE_STATS_REFERENCE_DISPLAY_OFF" },
    { value = "inline", label = "NE_STATS_REFERENCE_DISPLAY_INLINE" },
    { value = "delta", label = "NE_STATS_REFERENCE_DISPLAY_DELTA" },
    { value = "tooltip", label = "NE_STATS_REFERENCE_DISPLAY_TOOLTIP" },
}

local FRAME_CONTROLS_POSITION_LABELS = {
    BOTTOM = "NE_STATS_ALIGN_BOTTOM",
    TOP = "NE_STATS_ALIGN_TOP",
    LEFT = "NE_STATS_ALIGN_LEFT",
    RIGHT = "NE_STATS_ALIGN_RIGHT",
}

local FRAME_CONTROLS_DIRECTION_LABELS = {
    HORIZONTAL = "NE_STATS_DIRECTION_HORIZONTAL",
    VERTICAL = "NE_STATS_DIRECTION_VERTICAL",
}

-- Layout grid. The settings canvas is roughly 620px wide; a left navigation
-- rail plus a stretching content column fit comfortably within that budget.
local SIDEBAR_W = 128
local HEADER_H = 64
local PAGE_X = 0
local PAGE_Y = -6
local PAGE_WIDTH = 470
local ROW_H = 30
local FORM_X = 14
local FORM_Y = -4
local LABEL_X = 16
local CONTROL_X = 168
local CONTROL_W = 220
local FORM_ROW_H = 34
local SLIDER_ROW_H = 56
local GROUP_GAP = 16

-- Stat row column layout (stats options page).
local STAT_ROW_LABEL_W = 72
local STAT_ROW_COLOR_BTN_W = 46
local STAT_ROW_SWATCH_SIZE = 16
local STAT_ROW_COLOR_GAP = 8
local STAT_ROW_FIELD_GAP = 8

-- Shared visual palette for the redesigned panel.
local COLOR_CARD_BG = { 0.09, 0.10, 0.13, 0.55 }
local COLOR_CARD_BORDER = { 0.32, 0.35, 0.42, 0.85 }
local COLOR_ACCENT = { 0.36, 0.62, 1.00 }
local COLOR_NAV_ACTIVE = { 0.36, 0.62, 1.00, 0.22 }
local COLOR_NAV_HOVER = { 1.00, 1.00, 1.00, 0.08 }
local COLOR_ROW_STRIPE = { 1.00, 1.00, 1.00, 0.03 }
local COLOR_DROP_LINE = { 0.36, 0.62, 1.00, 0.95 }

function Addon:GetControlRefs()
    return controlRefs
end

local function Profile()
    return Addon:GetProfile()
end

local function GetValue(key, fallback)
    local value = Addon:GetProfileValue(key)
    if value == nil then
        return fallback
    end
    return value
end

local function SetValue(key, value)
    Addon:SetProfileValue(key, value)
end

local function GetActiveProfileNameFromDB()
    local db = Addon.db
    if db and db.GetCurrentProfile then
        return db:GetCurrentProfile() or "Default"
    end
    return "Default"
end

local function CreateLabel(parent, text, fontTemplate)
    local label = parent:CreateFontString(nil, "ARTWORK", fontTemplate or "GameFontNormalSmall")
    label:SetJustifyH("LEFT")
    label:SetText(text or "")
    return label
end

local function CreateButton(parent, width, localeKey, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 120, 22)
    if onClick then
        button:SetScript("OnClick", onClick)
    end
    BindLocalizedText(button, localeKey)
    return button
end

local function CreateCheckbox(parent, labelKey, tooltipKey, onClick)
    local checkbox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    checkbox.label = checkbox:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    checkbox.label:SetPoint("LEFT", checkbox, "RIGHT", 6, 0)
    checkbox.label:SetJustifyH("LEFT")
    BindLocalizedText(checkbox.label, labelKey)
    checkbox.tooltipKey = tooltipKey
    checkbox:SetScript("OnClick", onClick)
    checkbox:SetScript("OnEnter", function(self)
        if not self.tooltipKey then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(Addon:S(self.tooltipKey), 1, 0.82, 0)
        GameTooltip:Show()
    end)
    checkbox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    return checkbox
end

-- Modern slider built on MinimalSliderWithSteppersTemplate. The wrapper keeps the
-- legacy call contract (a :SetValue method and a function(self, value) callback)
-- so the rest of Options.lua stays untouched.
local function CreateSlider(name, parent, label, minValue, maxValue, step, onValueChanged)
    local slider = CreateFrame("Frame", name, parent, "MinimalSliderWithSteppersTemplate")
    local steps = math.max(1, math.floor(((maxValue - minValue) / step) + 0.5))
    slider.useDecimals = step < 1
    slider.minLabel = tostring(minValue)
    slider.maxLabel = tostring(maxValue)

    local function FormatTop(value)
        if slider.useDecimals then
            return string.format("%.2f", value)
        end
        return tostring(math.floor(value + 0.5))
    end

    local formatters = {
        [MinimalSliderWithSteppersMixin.Label.Top] = FormatTop,
        [MinimalSliderWithSteppersMixin.Label.Min] = function() return slider.minLabel end,
        [MinimalSliderWithSteppersMixin.Label.Max] = function() return slider.maxLabel end,
    }

    slider:Init(minValue, minValue, maxValue, steps, formatters)
    slider.onValueChanged = onValueChanged
    -- CallbackRegistry invokes function callbacks as func(owner, ...), so the
    -- registered owner arrives first and the slider value second.
    slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(owner, value)
        if owner.onValueChanged then
            owner.onValueChanged(owner, value)
        end
    end, slider)

    function slider:RefreshLabels()
        local current = self.Slider and self.Slider:GetValue() or minValue
        self:FormatValue(current)
    end

    function slider:SetMinLabel(text)
        self.minLabel = text
        self:RefreshLabels()
    end

    return slider
end

local function CreateEditBox(parent, width, onCommit)
    local editBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    editBox:SetSize(width or 120, 22)
    editBox:SetAutoFocus(false)
    editBox:SetScript("OnEnterPressed", function(self)
        if onCommit then
            onCommit(self)
        end
        self:ClearFocus()
    end)
    editBox:SetScript("OnEscapePressed", function(self)
        self.skipNextCommit = true
        self:ClearFocus()
        Addon:RefreshOptionRows()
    end)
    editBox:SetScript("OnEditFocusLost", function(self)
        if self.skipNextCommit then
            self.skipNextCommit = nil
            return
        end
        if onCommit then
            onCommit(self)
        end
    end)
    return editBox
end

local function OpenColorPicker(entry)
    local color = entry.color
    local previous = { color[1], color[2], color[3] }

    local function apply(r, g, b)
        entry.color[1], entry.color[2], entry.color[3] = r, g, b
        Addon:RefreshStats()
        Addon:RefreshOptionRows()
    end

    if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = color[1],
            g = color[2],
            b = color[3],
            hasOpacity = false,
            swatchFunc = function()
                local r, g, b = ColorPickerFrame:GetColorRGB()
                apply(r, g, b)
            end,
            cancelFunc = function()
                apply(previous[1], previous[2], previous[3])
            end,
        })
        return
    end

    if ColorPickerFrame then
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.func = function()
            local r, g, b = ColorPickerFrame:GetColorRGB()
            apply(r, g, b)
        end
        ColorPickerFrame.cancelFunc = function()
            apply(previous[1], previous[2], previous[3])
        end
        ColorPickerFrame:SetColorRGB(color[1], color[2], color[3])
        ColorPickerFrame:Hide()
        ColorPickerFrame:Show()
    end
end

local function RefreshStatsDeferred()
    Addon:RefreshStats()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, function()
            if Addon.initialized then
                Addon:RefreshStats()
            end
        end)
    end
end

local ARCHON_LOCKED_ORDER_STATS = {
    CRIT = true,
    HASTE = true,
    MASTERY = true,
    VERS = true,
}

local function IsStatOrderLockedByPriorityMode(statKey)
    local profile = Profile()
    local mode = Addon:NormalizeStatPriorityMode(profile and profile.statPriorityMode or "manual")
    return mode ~= "manual" and ARCHON_LOCKED_ORDER_STATS[statKey] == true
end

local function CanMoveStat(index, direction)
    local profile = Profile()
    if not profile or not profile.stats then
        return false
    end

    local entry = profile.stats[index]
    local target = profile.stats[index + direction]
    if not entry or not target then
        return false
    end

    local mode = Addon:NormalizeStatPriorityMode(profile.statPriorityMode or "manual")
    if mode == "manual" then
        return true
    end

    if IsStatOrderLockedByPriorityMode(entry.key) then
        return false
    end

    if IsStatOrderLockedByPriorityMode(target.key) then
        return false
    end

    return true
end

local function ApplyStatOrderChange()
    -- Force a full UI/display sync so the main stat frame rebuilds immediately.
    if Addon.ApplyCurrentProfileStateImpl then
        Addon:ApplyCurrentProfileStateImpl()
    elseif Addon.ApplyCurrentProfileState then
        Addon:ApplyCurrentProfileState()
    else
        Addon:RefreshStats()
        Addon:RefreshOptionRows()
    end
end

-- Moves a stat from one index to another by walking it one slot at a time. Each
-- step reuses CanMoveStat, so priority-mode locks (Archon) are honored exactly
-- like the up/down arrows: locked stats never move and are never displaced.
local function ReorderStat(fromIndex, toIndex)
    local profile = Profile()
    if not profile or not profile.stats then
        return
    end
    if not fromIndex or not toIndex or fromIndex == toIndex then
        return
    end

    local stats = profile.stats
    local direction = toIndex > fromIndex and 1 or -1
    local index = fromIndex
    local moved = false
    while index ~= toIndex do
        if not CanMoveStat(index, direction) then
            break
        end
        local target = index + direction
        stats[index], stats[target] = stats[target], stats[index]
        index = target
        moved = true
    end

    if moved then
        ApplyStatOrderChange()
    end
end

local function LocalizeArchonActivityLabel(activity)
    if activity == "m+" then
        return Addon:S("NE_STATS_ACTIVITY_MPLUS")
    end
    if activity == "raid" then
        return Addon:S("NE_STATS_ACTIVITY_RAID")
    end
    if not activity or activity == "" then
        return Addon:S("NE_STATS_VALUE_UNKNOWN")
    end
    return activity
end

local function RefreshArchonHint(profile)
    if not controlRefs.archonHint then
        return
    end

    local mode = Addon:NormalizeStatPriorityMode(profile and profile.statPriorityMode or "manual")
    if mode == "manual" then
        controlRefs.archonHint:SetText("")
        return
    end

    local data, _, activity = Addon:GetArchonDataForMode(mode)
    if not data then
        controlRefs.archonHint:SetText(Addon:S("NE_STATS_ARCHON_NO_DATA"))
        return
    end

    local actLabel = LocalizeArchonActivityLabel(activity)
    local hero = Addon:GetArchonTopHeroForMode(mode)
    if hero and hero.hero then
        local usage = tonumber(hero.usage_pct)
        if usage and usage > 0 then
            controlRefs.archonHint:SetText(Addon:S("NE_STATS_ARCHON_TOP_HERO_PCT", hero.hero, usage))
        else
            controlRefs.archonHint:SetText(Addon:S("NE_STATS_ARCHON_ACTIVITY_TOP_HERO", actLabel, hero.hero))
        end
        return
    end

    controlRefs.archonHint:SetText(Addon:S("NE_STATS_ARCHON_ACTIVITY_ONLY", actLabel))
end

local function CreatePage(parent, key)
    local page = CreateFrame("Frame", nil, parent)
    page:SetPoint("TOPLEFT", PAGE_X, PAGE_Y)
    page:SetPoint("TOPRIGHT", -PAGE_X, PAGE_Y)
    page:SetHeight(480)
    page.cursorY = 0
    page.maxBottom = 0
    page.key = key

    function page:AddTitle(text)
        local label = CreateLabel(self, text, "GameFontNormalLarge")
        label:SetPoint("TOPLEFT", 0, self.cursorY)
        self.cursorY = self.cursorY - 36
        self.maxBottom = math.min(self.maxBottom, self.cursorY)
        return label
    end

    function page:AddSection(text)
        local label = CreateLabel(self, text, "GameFontNormal")
        label:SetPoint("TOPLEFT", 0, self.cursorY)
        self.cursorY = self.cursorY - 28
        self.maxBottom = math.min(self.maxBottom, self.cursorY)
        return label
    end

    function page:AddLabel(text, fontTemplate)
        local label = CreateLabel(self, text, fontTemplate or "GameFontHighlight")
        label:SetPoint("TOPLEFT", 0, self.cursorY)
        self.cursorY = self.cursorY - ROW_H
        self.maxBottom = math.min(self.maxBottom, self.cursorY)
        return label
    end

    function page:AddGap(gap)
        self.cursorY = self.cursorY - (gap or 12)
        self.maxBottom = math.min(self.maxBottom, self.cursorY)
    end

    function page:AddRowLabel(text)
        local label = CreateLabel(self, text, "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", 0, self.cursorY - 4)
        return label
    end

    function page:Advance(rows, extra)
        self.cursorY = self.cursorY - ((rows or 1) * ROW_H) - (extra or 0)
        self.maxBottom = math.min(self.maxBottom, self.cursorY)
    end

    function page:ContentHeight()
        return math.abs(self.maxBottom) + 140
    end

    return page
end

-- Modern dropdown built on WowStyle1DropdownTemplate + the Menu system. The
-- wrapper preserves the legacy surface (getItems, onSelect, selectedValue and a
-- :Refresh(preferredValue) method) so callers and state sync code are unchanged.
local function CreateDropDown(parent, name, width, getItems, onSelect)
    local dropDown = CreateFrame("DropdownButton", name, parent, "WowStyle1DropdownTemplate")
    dropDown:SetWidth(width or 220)
    dropDown.selectedValue = nil
    dropDown.getItems = getItems
    dropDown.onSelect = onSelect

    dropDown:SetupMenu(function(dd, rootDescription)
        local items = dd.getItems and dd.getItems() or {}
        for _, item in ipairs(items) do
            local radio = rootDescription:CreateRadio(item.text, function(value)
                return dd.selectedValue == value
            end, function(value)
                dd.selectedValue = value
                if dd.onSelect then
                    dd.onSelect(value, item)
                end
            end, item.value)
            if item.disabled then
                radio:SetEnabled(false)
            end
        end
    end)

    function dropDown:Refresh(preferredValue)
        local items = self.getItems and self.getItems() or {}
        local selectedValue = preferredValue or self.selectedValue
        local valid = false
        for _, item in ipairs(items) do
            if item.value == selectedValue and not item.disabled then
                valid = true
                break
            end
        end
        if not valid then
            selectedValue = nil
            for _, item in ipairs(items) do
                if not item.disabled then
                    selectedValue = item.value
                    break
                end
            end
        end
        self.selectedValue = selectedValue
        if selectedValue == nil then
            self:OverrideText(Addon:S("NE_STATS_NO_AVAILABLE_PROFILES"))
        else
            -- Re-enable selection-driven text after a possible OverrideText call.
            self.disableSelectionText = false
            self:GenerateMenu()
        end
    end

    return dropDown
end

local function CreateProfileItems(rule)
    local items = {}
    local activeName = GetActiveProfileNameFromDB()
    for _, name in ipairs(Addon:GetProfileNames()) do
        local include = true
        if rule == "copySource" then
            include = name ~= activeName
        elseif rule == "renameTarget" then
            include = name ~= "Default"
        elseif rule == "deleteTarget" then
            include = name ~= "Default" and name ~= activeName
        end
        if include then
            table.insert(items, { value = name, text = Addon:GetDisplayProfileName(name) })
        end
    end
    return items
end

local function CreateProfileFromInput(editBox)
    if not editBox then
        return
    end
    local status, profileName = Addon:CreateProfile(editBox:GetText())
    if status == "invalid" then
        return
    end
    if status == "exists" then
        print(Addon:S("NE_STATS_PROFILE_ALREADY_EXISTS"))
    else
        print(Addon:S("NE_STATS_PROFILE_CREATED", profileName))
    end
    editBox:SetText("")
    Addon:OnProfileStateChanged()
end

local function EnsureResetProfilePopup()
    if StaticPopupDialogs["NE_STATS_RESET_PROFILE"] then
        return
    end
    StaticPopupDialogs["NE_STATS_RESET_PROFILE"] = {
        text = Addon:S("NE_STATS_RESET_PROFILE_FMT"),
        button1 = Addon:S("NE_STATS_RESET"),
        button2 = Addon:S("NE_STATS_CANCEL"),
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = STATICPOPUP_NUMDIALOGS,
        OnAccept = function()
            Addon:ResetActiveProfile()
            Addon:OnProfileStateChanged()
            print(Addon:S("NE_STATS_PROFILE_RESET"))
        end,
    }
end

local function RefreshProfileControls()
    local activeName = GetActiveProfileNameFromDB()

    if controlRefs.profileDropDown then
        controlRefs.profileDropDown:Refresh(activeName)
    end
    if controlRefs.profileInfo then
        controlRefs.profileInfo:SetText(Addon:S("NE_STATS_ACTIVE_PROFILE_FMT", Addon:GetDisplayProfileName(activeName)))
    end
    if controlRefs.profileCopySourceDropDown then
        controlRefs.profileCopySourceDropDown:Refresh(controlRefs.profileCopySourceDropDown.selectedValue)
    end
    if controlRefs.profileRenameTargetDropDown then
        controlRefs.profileRenameTargetDropDown:Refresh(controlRefs.profileRenameTargetDropDown.selectedValue)
    end
    if controlRefs.profileDeleteTargetDropDown then
        controlRefs.profileDeleteTargetDropDown:Refresh(controlRefs.profileDeleteTargetDropDown.selectedValue)
    end
end

local function UpdateContentHeight()
    if not controlRefs.scrollContent or not controlRefs.pages then
        return
    end
    if controlRefs.scrollFrame then
        local width = controlRefs.scrollFrame:GetWidth()
        if width and width > 1 then
            controlRefs.scrollContent:SetWidth(width)
        end
    end
    local page = controlRefs.pages[activeTab]
    local height = 480
    if page and page.ContentHeight then
        height = math.max(480, page:ContentHeight())
    end
    controlRefs.scrollContent:SetHeight(height)
end

local function ShowOptionsTab(tabName)
    activeTab = tabName or "profiles"
    if not controlRefs.pages then
        return
    end
    for key, page in pairs(controlRefs.pages) do
        if key == activeTab then
            page:Show()
        else
            page:Hide()
        end
    end
    for key, button in pairs(controlRefs.tabButtons or {}) do
        if button.SetActive then
            button:SetActive(key == activeTab)
        end
    end
    UpdateContentHeight()
    Addon:ApplyCurrentProfileStateImpl()
end

function Addon:RefreshOptions()
    RefreshProfileControls()
    self:RefreshOptionRows()
    UpdateContentHeight()
end

function Addon:RefreshOptionRows()
    if InCombatLockdown and InCombatLockdown() then
        self.pendingOptionRowsAfterCombat = true
        return
    end
    self.pendingOptionRowsAfterCombat = false
    if not optionsPanel then
        return
    end

    RefreshProfileControls()

    local profile = self:GetProfile()
    local statDefinitions = self.StatDefinitions
    for index, row in ipairs(rowControls) do
        local entry = profile.stats[index]
        if entry then
            local def = statDefinitions[entry.key]
            row.index = index
            row.checkbox:SetChecked(entry.enabled)
            row.label:SetText(self:S(def.label))
            if row.nameOverride then
                row.nameOverride:SetText(entry.nameOverride or "")
            end
            row.swatch.texture:SetColorTexture(entry.color[1], entry.color[2], entry.color[3], 1)
            if row.handle then
                local locked = IsStatOrderLockedByPriorityMode(entry.key)
                row.handle:SetEnabled(not locked)
                row.handle:SetAlpha(locked and 0.25 or 1)
                if row.dragHighlight then
                    row.dragHighlight:Hide()
                end
            end
            row.entry = entry
        end
    end
    if controlRefs.statDropIndicator then
        controlRefs.statDropIndicator:Hide()
    end
    RefreshArchonHint(profile)
end

function Addon:ApplyCurrentProfileStateImpl()
    local defaults = self.Defaults.profile
    local profile = self:GetProfile()

    RefreshProfileControls()

    if controlRefs.languageDropDown then
        controlRefs.languageDropDown:Refresh(self:GetConfiguredLocale())
    end
    if controlRefs.showPercentCheckbox then controlRefs.showPercentCheckbox:SetChecked(profile.showPercent) end
    if controlRefs.precisionSlider then controlRefs.precisionSlider:SetValue(profile.percentPrecision or defaults.percentPrecision) end
    if controlRefs.drModeDropDown then
        controlRefs.drModeDropDown:Refresh(profile.drDisplayMode or defaults.drDisplayMode or "off")
    end
    if controlRefs.showLabelsCheckbox then controlRefs.showLabelsCheckbox:SetChecked(profile.showLabels) end
    if controlRefs.showValuesCheckbox then controlRefs.showValuesCheckbox:SetChecked(profile.showValues) end
    if controlRefs.useClassColorCheckbox then controlRefs.useClassColorCheckbox:SetChecked(profile.useClassColor) end
    if controlRefs.showStatIconsCheckbox then controlRefs.showStatIconsCheckbox:SetChecked(profile.showStatIcons) end
    if controlRefs.compactValueColumnsCheckbox then controlRefs.compactValueColumnsCheckbox:SetChecked(profile.compactValueColumns) end
    if controlRefs.textAlignDropDown then controlRefs.textAlignDropDown:Refresh(profile.textAlign or defaults.textAlign) end
    if controlRefs.goldUseSeparatorCheckbox then controlRefs.goldUseSeparatorCheckbox:SetChecked(profile.goldUseSeparator) end
    if controlRefs.goldSeparatorDropDown then controlRefs.goldSeparatorDropDown:Refresh(profile.goldSeparator or defaults.goldSeparator) end
    if controlRefs.lockCheckbox then controlRefs.lockCheckbox:SetChecked(profile.locked) end
    if controlRefs.showLockOnHoverCheckbox then controlRefs.showLockOnHoverCheckbox:SetChecked(profile.showLockOnHover) end
    if controlRefs.frameControlsPositionDropDown then
        controlRefs.frameControlsPositionDropDown:Refresh(profile.frameControlsPosition or defaults.frameControlsPosition)
    end
    if controlRefs.frameControlsDirectionDropDown then
        controlRefs.frameControlsDirectionDropDown:Refresh(profile.frameControlsDirection or defaults.frameControlsDirection)
    end
    if controlRefs.preferCurrentSpecMainStatCheckbox then controlRefs.preferCurrentSpecMainStatCheckbox:SetChecked(profile.preferCurrentSpecMainStat) end
    if controlRefs.alphaSlider then controlRefs.alphaSlider:SetValue(profile.alpha or defaults.alpha) end
    if controlRefs.scaleSlider then controlRefs.scaleSlider:SetValue(profile.scale or defaults.scale) end
    if controlRefs.fontSizeSlider then controlRefs.fontSizeSlider:SetValue(profile.fontSize or defaults.fontSize) end
    if controlRefs.columnCountSlider then controlRefs.columnCountSlider:SetValue(profile.columnCount or defaults.columnCount) end
    if controlRefs.rowsPerColumnSlider then controlRefs.rowsPerColumnSlider:SetValue(profile.rowsPerColumn or defaults.rowsPerColumn) end
    if controlRefs.rowGapSlider then controlRefs.rowGapSlider:SetValue(profile.rowGap or defaults.rowGap) end
    if controlRefs.columnGapSlider then controlRefs.columnGapSlider:SetValue(profile.columnGap or defaults.columnGap) end
    if controlRefs.valueColumnWidthSlider then controlRefs.valueColumnWidthSlider:SetValue(profile.valueColumnWidth or defaults.valueColumnWidth) end
    if controlRefs.priorityModeDropDown then
        controlRefs.priorityModeDropDown:Refresh(self:NormalizeStatPriorityMode(profile.statPriorityMode or defaults.statPriorityMode or "manual"))
    end
    if controlRefs.referenceDisplayDropDown then
        controlRefs.referenceDisplayDropDown:Refresh(profile.referenceDisplay or defaults.referenceDisplay or "inline")
    end
    if self.RefreshPriorityModeButtons then
        self:RefreshPriorityModeButtons()
    end

    if controlRefs.fontDropDown or controlRefs.fontPreview then
        for _, font in ipairs(self:GetAvailableFonts()) do
            if font.key == profile.fontKey then
                if controlRefs.fontDropDown then
                    controlRefs.fontDropDown:Refresh(font.key)
                end
                if controlRefs.fontPreview then
                    local path, flags = self:GetFontInfo(font.key)
                    controlRefs.fontPreview:SetFont(path or STANDARD_TEXT_FONT, 18, flags or "OUTLINE")
                    controlRefs.fontPreview:SetText(font.label .. " - " .. self:S("NE_STATS_FONT_PREVIEW"))
                end
                break
            end
        end
    end

    self:RefreshStats()
    self:RefreshOptionRows()
end

function Addon:RefreshLocalizedUI()
    local defaults = self.Defaults.profile
    self:RefreshStaticPopupTexts()

    for _, entry in ipairs(localizedWidgets) do
        if entry.widget and entry.widget.SetText then
            entry.widget:SetText(self:S(entry.key))
        end
    end

    if optionsPanel then optionsPanel.name = self:S("NE_STATS_ADDON_NAME") end

    if controlRefs.profileInfo then
        local activeName = GetActiveProfileNameFromDB()
        controlRefs.profileInfo:SetText(self:S("NE_STATS_ACTIVE_PROFILE_FMT", self:GetDisplayProfileName(activeName)))
    end

    if controlRefs.languageDropDown then controlRefs.languageDropDown:Refresh(self:GetConfiguredLocale()) end
    if controlRefs.drModeDropDown then controlRefs.drModeDropDown:Refresh(GetValue("drDisplayMode", defaults.drDisplayMode)) end
    if controlRefs.textAlignDropDown then controlRefs.textAlignDropDown:Refresh(GetValue("textAlign", defaults.textAlign)) end
    if controlRefs.goldSeparatorDropDown then controlRefs.goldSeparatorDropDown:Refresh(GetValue("goldSeparator", defaults.goldSeparator)) end
    if controlRefs.priorityModeDropDown then
        controlRefs.priorityModeDropDown:Refresh(self:NormalizeStatPriorityMode(GetValue("statPriorityMode", defaults.statPriorityMode or "manual")))
    end
    if controlRefs.referenceDisplayDropDown then
        controlRefs.referenceDisplayDropDown:Refresh(GetValue("referenceDisplay", defaults.referenceDisplay or "inline"))
    end
    if controlRefs.frameControlsPositionDropDown then
        controlRefs.frameControlsPositionDropDown:Refresh(GetValue("frameControlsPosition", defaults.frameControlsPosition))
    end
    if controlRefs.frameControlsDirectionDropDown then
        controlRefs.frameControlsDirectionDropDown:Refresh(GetValue("frameControlsDirection", defaults.frameControlsDirection))
    end
    if controlRefs.profileDropDown then
        controlRefs.profileDropDown:Refresh(GetActiveProfileNameFromDB())
    end
    if controlRefs.profileCopySourceDropDown then
        controlRefs.profileCopySourceDropDown:Refresh(controlRefs.profileCopySourceDropDown.selectedValue)
    end
    if controlRefs.profileRenameTargetDropDown then
        controlRefs.profileRenameTargetDropDown:Refresh(controlRefs.profileRenameTargetDropDown.selectedValue)
    end
    if controlRefs.profileDeleteTargetDropDown then
        controlRefs.profileDeleteTargetDropDown:Refresh(controlRefs.profileDeleteTargetDropDown.selectedValue)
    end
    if controlRefs.fontDropDown then
        controlRefs.fontDropDown:Refresh(GetValue("fontKey", defaults.fontKey))
    end

    if controlRefs.referenceDisplayHint then
        controlRefs.referenceDisplayHint:SetText(self:S("NE_STATS_REFERENCE_MODE_HINT"))
    end
    if controlRefs.combatRestrictionHint then
        controlRefs.combatRestrictionHint:SetText(self:S("NE_STATS_COMBAT_RESTRICTION_HINT"))
    end
    if controlRefs.priorityHint then
        controlRefs.priorityHint:SetText(self:S("NE_STATS_ARCHON_LOCK_ORDER_HINT"))
    end
    if controlRefs.statHint then
        controlRefs.statHint:SetText(self:S("NE_STATS_REORDER_HINT"))
    end
    RefreshArchonHint(self:GetProfile())

    if controlRefs.rowsPerColumnSlider and controlRefs.rowsPerColumnSlider.SetMinLabel then
        controlRefs.rowsPerColumnSlider:SetMinLabel(self:S("NE_STATS_AUTO"))
    end

    if StaticPopupDialogs["NE_STATS_RESET_PROFILE"] then
        StaticPopupDialogs["NE_STATS_RESET_PROFILE"].text = self:S("NE_STATS_RESET_PROFILE_FMT")
        StaticPopupDialogs["NE_STATS_RESET_PROFILE"].button1 = self:S("NE_STATS_RESET")
        StaticPopupDialogs["NE_STATS_RESET_PROFILE"].button2 = self:S("NE_STATS_CANCEL")
    end

    self:RefreshOptions()
end

local function CreateCard(page, titleKey, topY)
    local card = CreateFrame("Frame", nil, page, "BackdropTemplate")
    card:SetPoint("TOPLEFT", page, "TOPLEFT", FORM_X, topY)
    card:SetPoint("TOPRIGHT", page, "TOPRIGHT", -FORM_X, topY)
    card:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8x8",
        edgeFile = "Interface/Buttons/WHITE8x8",
        edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    card:SetBackdropColor(unpack(COLOR_CARD_BG))
    card:SetBackdropBorderColor(unpack(COLOR_CARD_BORDER))

    local padding = 16
    local currentY = -(padding + 24)

    local accent = card:CreateTexture(nil, "ARTWORK")
    accent:SetColorTexture(COLOR_ACCENT[1], COLOR_ACCENT[2], COLOR_ACCENT[3], 1)
    accent:SetPoint("TOPLEFT", card, "TOPLEFT", padding, -padding - 1)
    accent:SetSize(3, 14)

    local titleLabel = CreateLabel(card, Addon:S(titleKey), "GameFontNormal")
    titleLabel:SetPoint("LEFT", accent, "RIGHT", 8, 0)
    BindLocalizedText(titleLabel, titleKey)

    function card:AddDropdownRow(labelKey, dropdown, width)
        local label = CreateLabel(self, Addon:S(labelKey), "GameFontHighlightSmall")
        BindLocalizedText(label, labelKey)
        label:SetPoint("LEFT", self, "TOPLEFT", LABEL_X, currentY - 12)
        dropdown:ClearAllPoints()
        dropdown:SetPoint("TOPLEFT", self, "TOPLEFT", CONTROL_X, currentY)
        dropdown:SetWidth(width or CONTROL_W)
        currentY = currentY - FORM_ROW_H
        return label
    end

    function card:AddCheckboxRow(checkbox)
        checkbox:ClearAllPoints()
        checkbox:SetPoint("TOPLEFT", self, "TOPLEFT", LABEL_X, currentY)
        currentY = currentY - FORM_ROW_H
    end

    function card:AddSliderRow(labelKey, slider)
        local label = CreateLabel(self, Addon:S(labelKey), "GameFontHighlightSmall")
        BindLocalizedText(label, labelKey)
        label:SetPoint("LEFT", self, "TOPLEFT", LABEL_X, currentY - 16)
        slider:ClearAllPoints()
        slider:SetPoint("TOPLEFT", self, "TOPLEFT", CONTROL_X, currentY - 4)
        slider:SetWidth(CONTROL_W)
        currentY = currentY - SLIDER_ROW_H
        return label
    end

    function card:AddControlRow(labelKey, control)
        local label = CreateLabel(self, Addon:S(labelKey), "GameFontHighlightSmall")
        BindLocalizedText(label, labelKey)
        label:SetPoint("LEFT", self, "TOPLEFT", LABEL_X, currentY - 12)
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", self, "TOPLEFT", CONTROL_X, currentY)
        currentY = currentY - FORM_ROW_H
        return label
    end

    function card:AddTextLine(text, fontTemplate, width)
        local textLine = CreateLabel(self, text, fontTemplate or "GameFontHighlightSmall")
        textLine:SetPoint("TOPLEFT", self, "TOPLEFT", LABEL_X, currentY - 2)
        textLine:SetWidth(width or (CONTROL_W + 120))
        textLine:SetJustifyH("LEFT")
        currentY = currentY - FORM_ROW_H
        return textLine
    end

    function card:AddButtonRow(button)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", self, "TOPLEFT", LABEL_X, currentY)
        currentY = currentY - FORM_ROW_H
    end

    function card.Advance(_, amount)
        currentY = currentY - (amount or FORM_ROW_H)
    end

    function card.GetCurrentY()
        return currentY
    end

    function card:Finish()
        local height = math.abs(currentY) + padding
        self:SetHeight(height)
        local bottomY = topY - height
        page.maxBottom = math.min(page.maxBottom, bottomY)
        return bottomY
    end

    return card
end

local function BuildProfilesPage(content, addonName)
    local page = CreatePage(content, "profiles")

    local card = CreateCard(page, "NE_STATS_PROFILES", FORM_Y)

    local activeDropDown = CreateDropDown(card, addonName .. "ProfileDropDown", 150, function()
        return CreateProfileItems("active")
    end, function(profileName)
        Addon:SelectRootProfile(profileName)
        Addon:OnProfileStateChanged()
    end)
    card:AddDropdownRow("NE_STATS_CURRENT_PROFILE", activeDropDown, 150)
    controlRefs.profileDropDown = activeDropDown

    local profileInfo = card:AddTextLine("", "GameFontHighlightSmall", 320)
    controlRefs.profileInfo = profileInfo

    local createEditBox = CreateFrame("EditBox", nil, card, "InputBoxTemplate")
    createEditBox:SetSize(150, 24)
    createEditBox:SetAutoFocus(false)
    createEditBox:SetScript("OnEnterPressed", function(self)
        CreateProfileFromInput(self)
        self:ClearFocus()
    end)
    local createLabel = card:AddControlRow("NE_STATS_CREATE_PROFILE", createEditBox)
    controlRefs.profileCreateLabel = createLabel
    controlRefs.profileCreateEditBox = createEditBox
    local createButton = CreateButton(card, 78, "NE_STATS_CREATE", function()
        CreateProfileFromInput(createEditBox)
    end)
    createButton:SetPoint("LEFT", createEditBox, "RIGHT", 6, 0)
    controlRefs.profileCreateButton = createButton

    local copyDropDown = CreateDropDown(card, addonName .. "ProfileCopySourceDropDown", 150, function()
        return CreateProfileItems("copySource")
    end)
    card:AddDropdownRow("NE_STATS_COPY_INTO_CURRENT", copyDropDown, 150)
    controlRefs.profileCopySourceDropDown = copyDropDown
    local copyButton = CreateButton(card, 78, "NE_STATS_COPY", function()
        local sourceProfileName = copyDropDown.selectedValue
        if not sourceProfileName then
            print(Addon:S("NE_STATS_SOURCE_PROFILE_NOT_SELECTED"))
            return
        end
        local activeName = GetActiveProfileNameFromDB()
        if Addon:CopyProfile(sourceProfileName) then
            print(Addon:S("NE_STATS_PROFILE_COPIED", Addon:GetDisplayProfileName(sourceProfileName), Addon:GetDisplayProfileName(activeName)))
            Addon:OnProfileStateChanged()
        else
            print(Addon:S("NE_STATS_PROFILE_COPY_FAILED"))
        end
    end)
    copyButton:SetPoint("LEFT", copyDropDown, "RIGHT", 6, 0)
    controlRefs.profileCopyButton = copyButton

    local renameDropDown = CreateDropDown(card, addonName .. "ProfileRenameTargetDropDown", 150, function()
        return CreateProfileItems("renameTarget")
    end)
    card:AddDropdownRow("NE_STATS_RENAME_PROFILE", renameDropDown, 150)
    controlRefs.profileRenameTargetDropDown = renameDropDown
    local renameButton = CreateButton(card, 78, "NE_STATS_RENAME", function()
        local profileName = renameDropDown.selectedValue
        if not profileName or not Addon:CanModifyProfile(profileName) then
            print(Addon:S("NE_STATS_PROFILE_RENAME_FAILED"))
            return
        end
        local dialog = StaticPopup_Show("NE_STATS_RENAME_PROFILE", Addon:GetDisplayProfileName(profileName), nil, profileName)
        if dialog then
            dialog.data = profileName
        end
    end)
    renameButton:SetPoint("LEFT", renameDropDown, "RIGHT", 6, 0)
    controlRefs.profileRenameButton = renameButton

    local deleteDropDown = CreateDropDown(card, addonName .. "ProfileDeleteTargetDropDown", 150, function()
        return CreateProfileItems("deleteTarget")
    end)
    card:AddDropdownRow("NE_STATS_DELETE_PROFILE", deleteDropDown, 150)
    controlRefs.profileDeleteTargetDropDown = deleteDropDown
    local deleteButton = CreateButton(card, 78, "NE_STATS_DELETE", function()
        local profileName = deleteDropDown.selectedValue
        if not profileName or not Addon:CanModifyProfile(profileName) or profileName == GetActiveProfileNameFromDB() then
            print(Addon:S("NE_STATS_PROFILE_DELETE_FAILED"))
            return
        end
        StaticPopup_Show("NE_STATS_DELETE_PROFILE", Addon:GetDisplayProfileName(profileName), nil, profileName)
    end)
    deleteButton:SetPoint("LEFT", deleteDropDown, "RIGHT", 6, 0)
    controlRefs.profileDeleteButton = deleteButton

    card:Advance(8)
    local resetButton = CreateButton(card, 200, "NE_STATS_RESET_CURRENT", function()
        EnsureResetProfilePopup()
        StaticPopup_Show("NE_STATS_RESET_PROFILE", Addon:GetDisplayProfileName(GetActiveProfileNameFromDB()))
    end)
    card:AddButtonRow(resetButton)
    controlRefs.profileResetButton = resetButton
    local bottomY = card:Finish()
    page.cursorY = bottomY - GROUP_GAP

    return page
end

local function BuildDisplayPage(content, addonName, defaults, statKeys)
    local page = CreatePage(content, "display")

    local currentTopY = FORM_Y

    local generalCard = CreateCard(page, "NE_STATS_GENERAL", currentTopY)

    local languageDropDown = CreateDropDown(generalCard, addonName .. "LanguageDropDown", 220, function()
        local localeOptions = { "client", "enUS", "deDE", "esES", "esMX", "frFR", "itIT", "koKR", "ptBR", "ruRU", "ukUA", "zhCN", "zhTW" }
        local items = {}
        for _, localeCode in ipairs(localeOptions) do
            table.insert(items, { value = localeCode, text = Addon:GetLocaleDisplayName(localeCode) })
        end
        return items
    end, function(localeCode)
        Addon:SetConfiguredLocale(localeCode)
        Addon:ApplyLocale()
        Addon:RefreshLocalizedUI()
        Addon:ApplyCurrentProfileState()
        Addon:UpdateFrameLockState()
        Addon:RefreshStats()
    end)
    generalCard:AddDropdownRow("NE_STATS_ADDON_LANGUAGE", languageDropDown, 220)
    controlRefs.languageDropDown = languageDropDown

    local drModeDropDown = CreateDropDown(generalCard, addonName .. "DRModeDropDown", 220, function()
        return {
            { value = "off", text = Addon:S("NE_STATS_OFF") },
            { value = "penalty", text = Addon:S("NE_STATS_DR_PENALTY") },
            { value = "loss", text = Addon:S("NE_STATS_RATING_LOST_TO_DR") },
            { value = "full", text = Addon:S("NE_STATS_FULL_DR_INFO") },
        }
    end, function(mode)
        SetValue("drDisplayMode", mode)
        Addon:RefreshStats()
    end)
    generalCard:AddDropdownRow("NE_STATS_DIMINISHING_RETURNS", drModeDropDown, 220)
    controlRefs.drModeDropDown = drModeDropDown

    local textAlignDropDown = CreateDropDown(generalCard, addonName .. "TextAlignDropDown", 160, function()
        local items = {}
        for _, align in ipairs(Addon.Constants.TEXT_ALIGN_OPTIONS) do
            table.insert(items, { value = align, text = Addon:GetTextAlignDisplayName(align) })
        end
        return items
    end, function(align)
        SetValue("textAlign", align)
        Addon:ApplyFrameStyle()
        Addon:ApplyTextAlignmentToVisibleLines()
        Addon:RefreshStats()
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                if Addon.initialized then
                    Addon:ApplyFrameStyle()
                    Addon:ApplyTextAlignmentToVisibleLines()
                    Addon:RefreshStats()
                end
            end)
        end
    end)
    generalCard:AddDropdownRow("NE_STATS_TEXT_ALIGNMENT", textAlignDropDown, 160)
    controlRefs.textAlignDropDown = textAlignDropDown

    currentTopY = generalCard:Finish() - GROUP_GAP

    local numbersCard = CreateCard(page, "NE_STATS_NUMBERS", currentTopY)

    local showPercentCheckbox = CreateCheckbox(numbersCard, "NE_STATS_SHOW_PERCENTAGES", nil, function(self)
        SetValue("showPercent", self:GetChecked())
        Addon:RefreshStats()
    end)
    numbersCard:AddCheckboxRow(showPercentCheckbox)
    controlRefs.showPercentCheckbox = showPercentCheckbox

    local precisionSlider = CreateSlider(addonName .. "PercentPrecisionSlider", numbersCard, Addon:S("NE_STATS_PERCENT_DECIMALS"), 0, 3, 1, function(_, value)
        SetValue("percentPrecision", value)
        Addon:RefreshStats()
    end)
    numbersCard:AddSliderRow("NE_STATS_PERCENT_DECIMALS", precisionSlider)
    controlRefs.precisionSlider = precisionSlider

    local showLabelsCheckbox = CreateCheckbox(numbersCard, "NE_STATS_SHOW_STAT_NAMES", nil, function(self)
        SetValue("showLabels", self:GetChecked())
        Addon:RefreshStats()
    end)
    numbersCard:AddCheckboxRow(showLabelsCheckbox)
    controlRefs.showLabelsCheckbox = showLabelsCheckbox

    local showValuesCheckbox = CreateCheckbox(numbersCard, "NE_STATS_SHOW_VALUES", nil, function(self)
        SetValue("showValues", self:GetChecked())
        Addon:RefreshStats()
    end)
    numbersCard:AddCheckboxRow(showValuesCheckbox)
    controlRefs.showValuesCheckbox = showValuesCheckbox

    local goldUseSeparatorCheckbox = CreateCheckbox(numbersCard, "NE_STATS_USE_SEPARATOR_FOR_GOLD", nil, function(self)
        SetValue("goldUseSeparator", self:GetChecked())
        Addon:RefreshStats()
    end)
    numbersCard:AddCheckboxRow(goldUseSeparatorCheckbox)
    controlRefs.goldUseSeparatorCheckbox = goldUseSeparatorCheckbox

    local goldSeparatorDropDown = CreateDropDown(numbersCard, addonName .. "GoldSeparatorDropDown", 160, function()
        local items = {}
        for _, separator in ipairs(Addon.Constants.GOLD_SEPARATOR_OPTIONS) do
            table.insert(items, { value = separator, text = Addon:GetGoldSeparatorDisplayName(separator) })
        end
        return items
    end, function(separator)
        SetValue("goldSeparator", separator)
        Addon:RefreshStats()
    end)
    numbersCard:AddDropdownRow("NE_STATS_GOLD_SEPARATOR", goldSeparatorDropDown, 160)
    controlRefs.goldSeparatorDropDown = goldSeparatorDropDown

    currentTopY = numbersCard:Finish() - GROUP_GAP

    local frameCard = CreateCard(page, "NE_STATS_FRAME", currentTopY)

    local lockCheckbox = CreateCheckbox(frameCard, "NE_STATS_LOCK_FRAME", nil, function(self)
        SetValue("locked", self:GetChecked())
        Addon:UpdateFrameLockState()
        if self:GetChecked() then
            print(Addon:S("NE_STATS_FRAME_LOCKED"))
        else
            print(Addon:S("NE_STATS_FRAME_UNLOCKED"))
        end
    end)
    frameCard:AddCheckboxRow(lockCheckbox)
    controlRefs.lockCheckbox = lockCheckbox

    local showLockOnHoverCheckbox = CreateCheckbox(frameCard, "NE_STATS_SHOW_LOCK_ICON_ONLY_ON_HOVER", "NE_STATS_LOCK_ON_HOVER_HINT", function(self)
        SetValue("showLockOnHover", self:GetChecked())
        Addon:UpdateFrameLockState()
    end)
    frameCard:AddCheckboxRow(showLockOnHoverCheckbox)
    controlRefs.showLockOnHoverCheckbox = showLockOnHoverCheckbox

    local frameControlsPositionDropDown = CreateDropDown(frameCard, addonName .. "FrameControlsPositionDropDown", 160, function()
        local items = {}
        for _, position in ipairs(Addon.Constants.FRAME_CONTROLS_POSITION_OPTIONS) do
            table.insert(items, { value = position, text = Addon:S(FRAME_CONTROLS_POSITION_LABELS[position] or position) })
        end
        return items
    end, function(value)
        SetValue("frameControlsPosition", value)
        Addon:RefreshStats()
    end)
    local frameControlsPositionLabel = frameCard:AddDropdownRow("NE_STATS_BUTTON_POSITION", frameControlsPositionDropDown, 160)
    controlRefs.frameControlsPositionDropDown = frameControlsPositionDropDown
    controlRefs.frameControlsPositionLabel = frameControlsPositionLabel

    local frameControlsDirectionDropDown = CreateDropDown(frameCard, addonName .. "FrameControlsDirectionDropDown", 160, function()
        local items = {}
        for _, direction in ipairs(Addon.Constants.FRAME_CONTROLS_DIRECTION_OPTIONS) do
            table.insert(items, { value = direction, text = Addon:S(FRAME_CONTROLS_DIRECTION_LABELS[direction] or direction) })
        end
        return items
    end, function(value)
        SetValue("frameControlsDirection", value)
        Addon:RefreshStats()
    end)
    local frameControlsDirectionLabel = frameCard:AddDropdownRow("NE_STATS_BUTTON_DIRECTION", frameControlsDirectionDropDown, 160)
    controlRefs.frameControlsDirectionDropDown = frameControlsDirectionDropDown
    controlRefs.frameControlsDirectionLabel = frameControlsDirectionLabel

    local alphaSlider = CreateSlider(addonName .. "AlphaSlider", frameCard, Addon:S("NE_STATS_BACKGROUND_OPACITY"), 0.1, 1, 0.05, function(_, value)
        SetValue("alpha", value)
        Addon:ApplyFrameStyle()
    end)
    frameCard:AddSliderRow("NE_STATS_BACKGROUND_OPACITY", alphaSlider)
    controlRefs.alphaSlider = alphaSlider

    local scaleSlider = CreateSlider(addonName .. "ScaleSlider", frameCard, Addon:S("NE_STATS_UI_SCALE"), 0.5, 3, 0.05, function(_, value)
        SetValue("scale", value)
        Addon:ApplyFrameStyle()
        Addon:RefreshStats()
    end)
    frameCard:AddSliderRow("NE_STATS_UI_SCALE", scaleSlider)
    controlRefs.scaleSlider = scaleSlider

    local resetButton = CreateButton(frameCard, 180, "NE_STATS_RESET_POSITION", function()
        local profile = Profile()
        profile.point = defaults.point
        profile.relativeTo = defaults.relativeTo
        profile.relativePoint = defaults.relativePoint
        profile.x = defaults.x
        profile.y = defaults.y
        Addon:ApplyFrameStyle()
        Addon:RefreshStats()
        print(Addon:S("NE_STATS_FRAME_POSITION_RESET"))
    end)
    frameCard:AddButtonRow(resetButton)
    controlRefs.resetButton = resetButton

    currentTopY = frameCard:Finish() - GROUP_GAP

    local textLayoutCard = CreateCard(page, "NE_STATS_TEXT_AND_LAYOUT", currentTopY)

    local fontSizeSlider = CreateSlider(addonName .. "FontSizeSlider", textLayoutCard, Addon:S("NE_STATS_FONT_SIZE"), 10, 32, 1, function(_, value)
        SetValue("fontSize", value)
        Addon:RefreshStats()
    end)
    textLayoutCard:AddSliderRow("NE_STATS_FONT_SIZE", fontSizeSlider)
    controlRefs.fontSizeSlider = fontSizeSlider

    local columnCountSlider = CreateSlider(addonName .. "ColumnCountSlider", textLayoutCard, Addon:S("NE_STATS_COLUMNS"), 1, #statKeys, 1, function(_, value)
        SetValue("columnCount", math.max(1, math.floor(value + 0.5)))
        Addon:RefreshStats()
    end)
    textLayoutCard:AddSliderRow("NE_STATS_COLUMNS", columnCountSlider)
    controlRefs.columnCountSlider = columnCountSlider

    local rowsPerColumnSlider = CreateSlider(addonName .. "RowsPerColumnSlider", textLayoutCard, Addon:S("NE_STATS_MAX_ROWS_PER_COLUMN"), 0, #statKeys, 1, function(_, value)
        SetValue("rowsPerColumn", math.max(0, math.floor(value + 0.5)))
        Addon:RefreshStats()
    end)
    rowsPerColumnSlider:SetMinLabel(Addon:S("NE_STATS_AUTO"))
    textLayoutCard:AddSliderRow("NE_STATS_MAX_ROWS_PER_COLUMN", rowsPerColumnSlider)
    controlRefs.rowsPerColumnSlider = rowsPerColumnSlider

    local showStatIconsCheckbox = CreateCheckbox(textLayoutCard, "NE_STATS_SHOW_STAT_ICONS", nil, function(self)
        SetValue("showStatIcons", self:GetChecked())
        Addon:RefreshStats()
    end)
    textLayoutCard:AddCheckboxRow(showStatIconsCheckbox)
    controlRefs.showStatIconsCheckbox = showStatIconsCheckbox

    local compactValueColumnsCheckbox = CreateCheckbox(textLayoutCard, "NE_STATS_COMPACT_VALUE_COLUMNS", nil, function(self)
        SetValue("compactValueColumns", self:GetChecked())
        Addon:RefreshStats()
    end)
    textLayoutCard:AddCheckboxRow(compactValueColumnsCheckbox)
    controlRefs.compactValueColumnsCheckbox = compactValueColumnsCheckbox

    local rowGapSlider = CreateSlider(addonName .. "RowGapSlider", textLayoutCard, Addon:S("NE_STATS_ROW_SPACING"), 0, 20, 1, function(_, value)
        SetValue("rowGap", math.max(0, math.floor(value + 0.5)))
        Addon:RefreshStats()
    end)
    textLayoutCard:AddSliderRow("NE_STATS_ROW_SPACING", rowGapSlider)
    controlRefs.rowGapSlider = rowGapSlider

    local columnGapSlider = CreateSlider(addonName .. "ColumnGapSlider", textLayoutCard, Addon:S("NE_STATS_COLUMN_SPACING"), 0, 120, 1, function(_, value)
        SetValue("columnGap", math.max(0, math.floor(value + 0.5)))
        Addon:RefreshStats()
    end)
    textLayoutCard:AddSliderRow("NE_STATS_COLUMN_SPACING", columnGapSlider)
    controlRefs.columnGapSlider = columnGapSlider

    local valueColumnWidthSlider = CreateSlider(addonName .. "ValueColumnWidthSlider", textLayoutCard, Addon:S("NE_STATS_VALUE_COLUMN_WIDTH"), 0, 240, 1, function(_, value)
        SetValue("valueColumnWidth", math.max(0, math.floor(value + 0.5)))
        Addon:RefreshStats()
    end)
    valueColumnWidthSlider:SetMinLabel(Addon:S("NE_STATS_AUTO"))
    textLayoutCard:AddSliderRow("NE_STATS_VALUE_COLUMN_WIDTH", valueColumnWidthSlider)
    controlRefs.valueColumnWidthSlider = valueColumnWidthSlider

    local fontDropDown = CreateDropDown(textLayoutCard, addonName .. "FontDropDown", 220, function()
        local items = {}
        for _, font in ipairs(Addon:GetAvailableFonts()) do
            table.insert(items, { value = font.key, text = font.label })
        end
        return items
    end, function(fontKey, item)
        SetValue("fontKey", fontKey)
        if controlRefs.fontPreview then
            local path, flags = Addon:GetFontInfo(fontKey)
            controlRefs.fontPreview:SetFont(path or STANDARD_TEXT_FONT, 18, flags or "OUTLINE")
            controlRefs.fontPreview:SetText((item and item.text or fontKey) .. " - " .. Addon:S("NE_STATS_FONT_PREVIEW"))
        end
        RefreshStatsDeferred()
    end)
    textLayoutCard:AddDropdownRow("NE_STATS_FONT", fontDropDown, 220)
    controlRefs.fontDropDown = fontDropDown

    local fontPreview = textLayoutCard:AddTextLine(Addon:S("NE_STATS_FONT_PREVIEW"), "GameFontHighlight", 320)
    controlRefs.fontPreview = fontPreview
    local bottomY = textLayoutCard:Finish()
    page.cursorY = bottomY - GROUP_GAP

    return page
end

local function BuildStatsPage(content, addonName, statKeys)
    local page = CreatePage(content, "stats")

    local card = CreateCard(page, "NE_STATS_STATS", FORM_Y)

    local hintWidth = PAGE_WIDTH - (FORM_X * 2) - (LABEL_X * 2)

    local combatRestrictionHint = CreateLabel(card, Addon:S("NE_STATS_COMBAT_RESTRICTION_HINT"), "GameFontDisableSmall")
    BindLocalizedText(combatRestrictionHint, "NE_STATS_COMBAT_RESTRICTION_HINT")
    combatRestrictionHint:SetPoint("TOPLEFT", card, "TOPLEFT", LABEL_X, card:GetCurrentY() + 4)
    combatRestrictionHint:SetWidth(hintWidth)
    combatRestrictionHint:SetJustifyH("LEFT")
    controlRefs.combatRestrictionHint = combatRestrictionHint
    card:Advance(FORM_ROW_H)

    local priorityDropDown = CreateDropDown(card, addonName .. "PriorityModeDropDown", 220, function()
        local items = {}
        for _, option in ipairs(PRIORITY_MODE_OPTIONS) do
            table.insert(items, { value = option.value, text = Addon:S(option.label) })
        end
        return items
    end, function(mode)
        Addon:SetStatPriorityMode(mode)
    end)
    card:AddDropdownRow("NE_STATS_DISPLAY_ORDER", priorityDropDown, 220)
    controlRefs.priorityModeDropDown = priorityDropDown

    local referenceDropDown = CreateDropDown(card, addonName .. "ReferenceDisplayDropDown", 220, function()
        local items = {}
        for _, option in ipairs(REFERENCE_DISPLAY_OPTIONS) do
            table.insert(items, { value = option.value, text = Addon:S(option.label) })
        end
        return items
    end, function(value)
        SetValue("referenceDisplay", value)
        Addon:RefreshStats()
    end)
    card:AddDropdownRow("NE_STATS_REFERENCE_DISPLAY", referenceDropDown, 220)
    controlRefs.referenceDisplayDropDown = referenceDropDown

    local preferCurrentSpecMainStatCheckbox = CreateCheckbox(card, "NE_STATS_ALWAYS_SHOW_CURRENT_SPECIALIZATION_MAIN_STAT_FIRST", "NE_STATS_PREFER_MAIN_STAT_HINT", function(self)
        SetValue("preferCurrentSpecMainStat", self:GetChecked())
        Addon:RefreshStats()
    end)
    card:AddCheckboxRow(preferCurrentSpecMainStatCheckbox)
    controlRefs.preferCurrentSpecMainStatCheckbox = preferCurrentSpecMainStatCheckbox

    preferCurrentSpecMainStatCheckbox.label:SetWidth(hintWidth - 30)

    local useClassColorCheckbox = CreateCheckbox(card, "NE_STATS_USE_CLASS_COLOR", nil, function(self)
        SetValue("useClassColor", self:GetChecked())
        Addon:RefreshStats()
    end)
    card:AddCheckboxRow(useClassColorCheckbox)
    controlRefs.useClassColorCheckbox = useClassColorCheckbox

    local hint = CreateLabel(card, Addon:S("NE_STATS_ARCHON_LOCK_ORDER_HINT"), "GameFontDisableSmall")
    BindLocalizedText(hint, "NE_STATS_ARCHON_LOCK_ORDER_HINT")
    hint:SetPoint("TOPLEFT", card, "TOPLEFT", LABEL_X, card:GetCurrentY() + 4)
    hint:SetWidth(hintWidth)
    hint:SetJustifyH("LEFT")
    controlRefs.priorityHint = hint
    card:Advance(FORM_ROW_H)

    local archonHint = CreateLabel(card, "", "GameFontDisableSmall")
    archonHint:SetPoint("TOPLEFT", card, "TOPLEFT", LABEL_X, card:GetCurrentY() + 4)
    archonHint:SetWidth(hintWidth)
    archonHint:SetJustifyH("LEFT")
    controlRefs.archonHint = archonHint
    card:Advance(FORM_ROW_H)

    local referenceModeHint = CreateLabel(card, Addon:S("NE_STATS_REFERENCE_MODE_HINT"), "GameFontDisableSmall")
    BindLocalizedText(referenceModeHint, "NE_STATS_REFERENCE_MODE_HINT")
    referenceModeHint:SetPoint("TOPLEFT", card, "TOPLEFT", LABEL_X, card:GetCurrentY() + 4)
    referenceModeHint:SetWidth(hintWidth)
    referenceModeHint:SetJustifyH("LEFT")
    controlRefs.referenceDisplayHint = referenceModeHint
    card:Advance(FORM_ROW_H)

    local header = CreateLabel(card, Addon:S("NE_STATS_REORDER_HINT"), "GameFontNormalSmall")
    BindLocalizedText(header, "NE_STATS_REORDER_HINT")
    header:SetPoint("TOPLEFT", card, "TOPLEFT", LABEL_X, card:GetCurrentY() + 4)
    header:SetWidth(hintWidth)
    header:SetJustifyH("LEFT")
    controlRefs.statHint = header
    card:Advance(FORM_ROW_H)

    -- Drop indicator drawn between rows while dragging.
    local dropIndicator = card:CreateTexture(nil, "OVERLAY")
    dropIndicator:SetColorTexture(unpack(COLOR_DROP_LINE))
    dropIndicator:SetHeight(2)
    dropIndicator:Hide()
    controlRefs.statDropIndicator = dropIndicator

    local function ComputeDropTarget()
        local scale = card:GetEffectiveScale()
        if not scale or scale == 0 then
            return statDragState.fromIndex or 1
        end
        local _, cursorY = GetCursorPosition()
        cursorY = cursorY / scale
        local target = 1
        for rowIndex, row in ipairs(rowControls) do
            if row:IsShown() then
                local mid = (row:GetTop() + row:GetBottom()) / 2
                if cursorY < mid then
                    target = rowIndex + 1
                end
            end
        end
        return target
    end

    local function UpdateDropIndicator(target)
        local count = #rowControls
        local anchorRow, edge
        if target > count then
            anchorRow = rowControls[count]
            edge = "BOTTOM"
        else
            anchorRow = rowControls[target]
            edge = "TOP"
        end
        if not anchorRow then
            dropIndicator:Hide()
            return
        end
        dropIndicator:ClearAllPoints()
        dropIndicator:SetPoint("TOPLEFT", anchorRow, edge .. "LEFT", 0, 1)
        dropIndicator:SetPoint("TOPRIGHT", anchorRow, edge .. "RIGHT", 0, 1)
        dropIndicator:Show()
    end

    local function OnDragUpdate()
        if not statDragState.active then
            return
        end
        local target = ComputeDropTarget()
        statDragState.targetIndex = target
        UpdateDropIndicator(target)
    end

    local function BeginStatDrag(row)
        if InCombatLockdown and InCombatLockdown() then
            return
        end
        statDragState.active = true
        statDragState.fromIndex = row.index
        statDragState.targetIndex = row.index
        if row.dragHighlight then
            row.dragHighlight:Show()
        end
        card:SetScript("OnUpdate", OnDragUpdate)
    end

    local function EndStatDrag(row)
        if not statDragState.active then
            return
        end
        card:SetScript("OnUpdate", nil)
        dropIndicator:Hide()
        if row.dragHighlight then
            row.dragHighlight:Hide()
        end

        local from = statDragState.fromIndex
        local target = statDragState.targetIndex
        statDragState.active = false
        statDragState.fromIndex = nil
        statDragState.targetIndex = nil

        if not from or not target then
            return
        end

        local dest = target
        if dest > from then
            dest = dest - 1
        end
        if dest < 1 then
            dest = 1
        end
        if dest > #rowControls then
            dest = #rowControls
        end
        ReorderStat(from, dest)
    end

    for index = 1, #statKeys do
        local row = CreateFrame("Frame", nil, card)
        row:SetHeight(28)
        row:SetPoint("TOPLEFT", card, "TOPLEFT", LABEL_X, card:GetCurrentY() + 4)
        row:SetPoint("TOPRIGHT", card, "TOPRIGHT", -LABEL_X, card:GetCurrentY() + 4)

        if index % 2 == 0 then
            local stripe = row:CreateTexture(nil, "BACKGROUND")
            stripe:SetAllPoints()
            stripe:SetColorTexture(unpack(COLOR_ROW_STRIPE))
        end

        local dragHighlight = row:CreateTexture(nil, "BACKGROUND", nil, 1)
        dragHighlight:SetAllPoints()
        dragHighlight:SetColorTexture(COLOR_ACCENT[1], COLOR_ACCENT[2], COLOR_ACCENT[3], 0.16)
        dragHighlight:Hide()
        row.dragHighlight = dragHighlight

        -- Drag handle (grip) on the far left.
        local handle = CreateFrame("Button", nil, row)
        handle:SetSize(14, 24)
        handle:SetPoint("LEFT", row, "LEFT", 0, 0)
        for line = 1, 3 do
            local grip = handle:CreateTexture(nil, "ARTWORK")
            grip:SetColorTexture(0.65, 0.68, 0.74, 0.9)
            grip:SetSize(10, 2)
            grip:SetPoint("CENTER", handle, "CENTER", 0, (line - 2) * 5)
        end
        local handleHighlight = handle:CreateTexture(nil, "HIGHLIGHT")
        handleHighlight:SetAllPoints()
        handleHighlight:SetColorTexture(1, 1, 1, 0.12)
        handle:RegisterForDrag("LeftButton")
        handle:SetScript("OnDragStart", function()
            BeginStatDrag(row)
        end)
        handle:SetScript("OnDragStop", function()
            EndStatDrag(row)
        end)
        handle:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(Addon:S("NE_STATS_DRAG_TO_REORDER"), 1, 0.82, 0)
            GameTooltip:Show()
        end)
        handle:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        row.handle = handle

        local checkbox = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        checkbox:SetSize(22, 22)
        checkbox:SetPoint("LEFT", handle, "RIGHT", 4, 0)
        row.checkbox = checkbox

        local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        label:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
        label:SetWidth(STAT_ROW_LABEL_W)
        label:SetJustifyH("LEFT")
        row.label = label

        local color = CreateButton(row, STAT_ROW_COLOR_BTN_W, "NE_STATS_COLOR", function()
            OpenColorPicker(row.entry)
        end)
        color:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.color = color

        local swatch = CreateFrame("Button", nil, row, "BackdropTemplate")
        swatch:SetSize(STAT_ROW_SWATCH_SIZE, STAT_ROW_SWATCH_SIZE)
        swatch:SetPoint("RIGHT", color, "LEFT", -STAT_ROW_COLOR_GAP, 0)
        swatch:SetBackdrop({
            bgFile = "Interface/Buttons/WHITE8x8",
            edgeFile = "Interface/Buttons/WHITE8x8",
            edgeSize = 1,
            insets = { left = 1, right = 1, top = 1, bottom = 1 },
        })
        swatch:SetBackdropColor(0, 0, 0, 0.9)
        swatch:SetBackdropBorderColor(0.4, 0.4, 0.45, 0.9)
        swatch.texture = swatch:CreateTexture(nil, "ARTWORK")
        swatch.texture:SetPoint("TOPLEFT", 2, -2)
        swatch.texture:SetPoint("BOTTOMRIGHT", -2, 2)
        row.swatch = swatch

        local nameOverride = CreateEditBox(row, nil, function(self)
            local text = strtrim(self:GetText() or "")
            row.entry.nameOverride = text ~= "" and text or nil
            self:SetText(row.entry.nameOverride or "")
            Addon:RefreshStats()
        end)
        nameOverride:SetPoint("LEFT", label, "RIGHT", STAT_ROW_FIELD_GAP, 0)
        nameOverride:SetPoint("RIGHT", swatch, "LEFT", -STAT_ROW_FIELD_GAP, 0)
        nameOverride:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(Addon:S("NE_STATS_NAME_OVERRIDE"), 1, 0.82, 0)
            GameTooltip:Show()
        end)
        nameOverride:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        row.nameOverride = nameOverride

        checkbox:SetScript("OnClick", function(self)
            row.entry.enabled = self:GetChecked()
            Addon:RefreshStats()
        end)
        swatch:SetScript("OnClick", function()
            OpenColorPicker(row.entry)
        end)

        rowControls[index] = row
        card:Advance(30)
    end

    local bottomY = card:Finish()
    page.cursorY = bottomY - GROUP_GAP

    return page
end

local function CreateNavButton(parent, localeKey, onClick)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetHeight(32)
    btn:SetScript("OnClick", onClick)

    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(unpack(COLOR_NAV_ACTIVE))
    bg:Hide()
    btn.bg = bg

    local hover = btn:CreateTexture(nil, "HIGHLIGHT")
    hover:SetAllPoints()
    hover:SetColorTexture(unpack(COLOR_NAV_HOVER))

    local accent = btn:CreateTexture(nil, "ARTWORK")
    accent:SetColorTexture(COLOR_ACCENT[1], COLOR_ACCENT[2], COLOR_ACCENT[3], 1)
    accent:SetPoint("TOPLEFT", 0, 0)
    accent:SetPoint("BOTTOMLEFT", 0, 0)
    accent:SetWidth(3)
    accent:Hide()
    btn.accent = accent

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", 14, 0)
    label:SetJustifyH("LEFT")
    BindLocalizedText(label, localeKey)
    btn.label = label

    function btn:SetText(value)
        self.label:SetText(value)
    end

    function btn:SetActive(active)
        self.bg:SetShown(active)
        self.accent:SetShown(active)
        self.label:SetFontObject(active and "GameFontHighlight" or "GameFontNormal")
    end

    return btn
end

function Addon:BuildOptionsPanel()
    if optionsPanel and optionsPanelBuilt then return end

    local addonName = self.name or ADDON_NAME_FALLBACK
    local defaults = self.Defaults.profile
    local statKeys = self.Constants.STAT_KEYS

    optionsPanel = CreateFrame("Frame", addonName .. "OptionsPanel", UIParent)
    optionsPanel.name = self:S("NE_STATS_ADDON_NAME")
    optionsPanel:SetSize(780, 620)

    -- Fixed header that stays in place while the content area scrolls.
    local title = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 20, -18)
    BindLocalizedText(title, "NE_STATS_ADDON_NAME")
    controlRefs.title = title

    local subtitle = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
    subtitle:SetWidth(720)
    subtitle:SetJustifyH("LEFT")
    BindLocalizedText(subtitle, "NE_STATS_PROFILES_SHARED_HINT")
    controlRefs.subtitle = subtitle

    local divider = optionsPanel:CreateTexture(nil, "ARTWORK")
    divider:SetColorTexture(unpack(COLOR_CARD_BORDER))
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", optionsPanel, "TOPLEFT", 16, -HEADER_H)
    divider:SetPoint("TOPRIGHT", optionsPanel, "TOPRIGHT", -16, -HEADER_H)

    -- Vertical navigation rail on the left.
    local nav = CreateFrame("Frame", nil, optionsPanel)
    nav:SetPoint("TOPLEFT", optionsPanel, "TOPLEFT", 16, -HEADER_H - 10)
    nav:SetPoint("BOTTOMLEFT", optionsPanel, "BOTTOMLEFT", 16, 14)
    nav:SetWidth(SIDEBAR_W)
    controlRefs.nav = nav

    controlRefs.tabButtons = {}
    local previousTab
    for _, key in ipairs(TAB_ORDER) do
        local button = CreateNavButton(nav, TAB_LABELS[key], function()
            ShowOptionsTab(key)
        end)
        button:SetPoint("LEFT", nav, "LEFT", 0, 0)
        button:SetPoint("RIGHT", nav, "RIGHT", 0, 0)
        if previousTab then
            button:SetPoint("TOP", previousTab, "BOTTOM", 0, -4)
        else
            button:SetPoint("TOP", nav, "TOP", 0, 0)
        end
        controlRefs.tabButtons[key] = button
        previousTab = button
    end

    -- Scrollable content area to the right of the navigation rail.
    local scrollFrame = CreateFrame("ScrollFrame", addonName .. "OptionsScrollFrame", optionsPanel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", nav, "TOPRIGHT", 18, 0)
    scrollFrame:SetPoint("BOTTOMRIGHT", optionsPanel, "BOTTOMRIGHT", -28, 14)
    controlRefs.scrollFrame = scrollFrame

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(PAGE_WIDTH, 480)
    scrollFrame:SetScrollChild(content)
    controlRefs.scrollContent = content

    scrollFrame:SetScript("OnSizeChanged", function()
        UpdateContentHeight()
    end)

    controlRefs.pages = {}
    controlRefs.pages.profiles = BuildProfilesPage(content, addonName)
    controlRefs.pages.display = BuildDisplayPage(content, addonName, defaults, statKeys)
    controlRefs.pages.stats = BuildStatsPage(content, addonName, statKeys)

    optionsPanel:SetScript("OnShow", function()
        Addon:RefreshLocalizedUI()
        ShowOptionsTab(activeTab)
        Addon:ApplyCurrentProfileState()
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        optionsCategory = Settings.RegisterCanvasLayoutCategory(optionsPanel, self:S("NE_STATS_ADDON_NAME"))
        optionsCategoryID = optionsCategory.GetID and optionsCategory:GetID() or nil
        Settings.RegisterAddOnCategory(optionsCategory)
    end
    if InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(optionsPanel)
    end

    optionsPanelBuilt = true
    ShowOptionsTab(activeTab)
end

function Addon:ResetOptionsPanelState()
    if optionsPanel then
        optionsPanel:Hide()
        optionsPanel:SetParent(nil)
    end
    optionsPanel = nil
    optionsCategory = nil
    optionsCategoryID = nil
    optionsPanelBuilt = false
    lastOptionsPanelError = nil
    rowControls = {}
    controlRefs = {}
    wipe(localizedWidgets)
    activeTab = "profiles"
    statDragState = { active = false }
end

function Addon:SafeBuildOptionsPanel()
    if optionsPanel and optionsPanelBuilt then
        return true
    end
    if optionsPanel and not optionsPanelBuilt then
        self:ResetOptionsPanelState()
    end

    local ok, err = xpcall(function()
        self:BuildOptionsPanel()
    end, function(message)
        return tostring(message)
    end)
    if not ok then
        lastOptionsPanelError = err
        self:ResetOptionsPanelState()
        return false
    end
    lastOptionsPanelError = nil
    return optionsPanelBuilt
end

function Addon:OpenAddonSettings()
    if not self:SafeBuildOptionsPanel() then
        if lastOptionsPanelError and lastOptionsPanelError ~= "" then
            print(self:S("NE_STATS_SETTINGS_PANEL_FAILED", tostring(lastOptionsPanelError)))
        else
            print(self:S("NE_STATS_SETTINGS_NOT_AVAILABLE"))
        end
        return
    end
    if Settings and Settings.OpenToCategory and optionsCategoryID then
        Settings.OpenToCategory(optionsCategoryID)
        return
    end
    if Settings and Settings.OpenToCategory and optionsCategory then
        Settings.OpenToCategory(optionsCategory)
        return
    end
    if InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(optionsPanel)
        InterfaceOptionsFrame_OpenToCategory(optionsPanel)
        return
    end
    print(self:S("NE_STATS_SETTINGS_NOT_AVAILABLE"))
end
