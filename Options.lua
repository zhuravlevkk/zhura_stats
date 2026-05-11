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

local TAB_ORDER = { "profiles", "display", "stats" }
local TAB_LABELS = {
    profiles = "Profiles",
    display = "Display",
    stats = "Stats",
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

local PAGE_X = 16
local PAGE_Y = -112
local PAGE_WIDTH = 620
local ROW_H = 30
local FORM_X = 24
local FORM_Y = -70
local LABEL_X = 24
local CONTROL_X = 210
local CONTROL_W = 240
local FORM_ROW_H = 32
local SLIDER_ROW_H = 52
local GROUP_GAP = 14

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

local function SetGenericDropDownSelection(dropDown, text, value)
    if not dropDown then
        return
    end
    UIDropDownMenu_SetText(dropDown, text or "")
    UIDropDownMenu_SetSelectedName(dropDown, text or "")
    UIDropDownMenu_SetSelectedValue(dropDown, value)
end

local function CreateLabel(parent, text, fontTemplate)
    local label = parent:CreateFontString(nil, "ARTWORK", fontTemplate or "GameFontNormalSmall")
    label:SetJustifyH("LEFT")
    label:SetText(text or "")
    return label
end

local function CreateButton(parent, width, text, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width or 120, 22)
    button:SetText(text or "")
    if onClick then
        button:SetScript("OnClick", onClick)
    end
    return button
end

local function CreateCheckbox(parent, label, tooltip, onClick)
    local checkbox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    checkbox.label = checkbox:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    checkbox.label:SetPoint("LEFT", checkbox, "RIGHT", 6, 0)
    checkbox.label:SetJustifyH("LEFT")
    checkbox.label:SetText(label or "")
    checkbox.tooltipText = tooltip
    checkbox:SetScript("OnClick", onClick)
    checkbox:SetScript("OnEnter", function(self)
        if not self.tooltipText then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tooltipText, 1, 0.82, 0, true)
        GameTooltip:Show()
    end)
    checkbox:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    return checkbox
end

local function CreateSlider(name, parent, label, minValue, maxValue, step, onValueChanged)
    local slider = CreateFrame("Slider", name, parent, "OptionsSliderTemplate")
    slider:SetWidth(220)
    slider:SetMinMaxValues(minValue, maxValue)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    _G[name .. "Low"]:SetText(tostring(minValue))
    _G[name .. "High"]:SetText(tostring(maxValue))
    _G[name .. "Text"]:SetText(label)
    slider:SetScript("OnValueChanged", onValueChanged)
    return slider
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

local function MoveStat(index, direction)
    local profile = Profile()
    if not profile or not profile.stats then
        return
    end
    if not CanMoveStat(index, direction) then
        return
    end

    local stats = profile.stats
    local target = index + direction
    stats[index], stats[target] = stats[target], stats[index]

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
    page:SetSize(PAGE_WIDTH, 480)
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

local function CreateDropDown(parent, name, width, getItems, onSelect)
    local dropDown = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(dropDown, width or 220)
    dropDown.selectedValue = nil
    dropDown.getItems = getItems
    dropDown.onSelect = onSelect
    dropDown.initializeFunc = function(_, level)
        local items = dropDown.getItems and dropDown.getItems() or {}
        for _, item in ipairs(items) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = item.text
            info.value = item.value
            info.disabled = item.disabled
            info.checked = dropDown.selectedValue == item.value
            info.func = function()
                dropDown.selectedValue = item.value
                SetGenericDropDownSelection(dropDown, item.text, item.value)
                CloseDropDownMenus()
                if dropDown.onSelect then
                    dropDown.onSelect(item.value, item)
                end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end
    UIDropDownMenu_Initialize(dropDown, dropDown.initializeFunc)
    dropDown.Refresh = function(self, preferredValue)
        UIDropDownMenu_Initialize(self, self.initializeFunc)
        local items = self.getItems and self.getItems() or {}
        local selectedValue = preferredValue or self.selectedValue
        local selectedText
        for _, item in ipairs(items) do
            if item.value == selectedValue and not item.disabled then
                selectedText = item.text
                break
            end
        end
        if not selectedText then
            selectedValue = nil
            for _, item in ipairs(items) do
                if not item.disabled then
                    selectedValue = item.value
                    selectedText = item.text
                    break
                end
            end
        end
        self.selectedValue = selectedValue
        if selectedValue then
            SetGenericDropDownSelection(self, selectedText, selectedValue)
        else
            UIDropDownMenu_SetSelectedValue(self, nil)
            UIDropDownMenu_SetText(self, Addon:S("No available profiles"))
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
        print(Addon:S("NE Stats: profile already exists."))
    else
        print(Addon:S("NE Stats: created profile %s.", profileName))
    end
    editBox:SetText("")
    Addon:OnProfileStateChanged()
end

local function EnsureResetProfilePopup()
    if StaticPopupDialogs["NE_STATS_RESET_PROFILE"] then
        return
    end
    StaticPopupDialogs["NE_STATS_RESET_PROFILE"] = {
        text = Addon:S("Reset active profile %s?"),
        button1 = Addon:S("Reset"),
        button2 = Addon:S("Cancel"),
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = STATICPOPUP_NUMDIALOGS,
        OnAccept = function()
            Addon:ResetActiveProfile()
            Addon:OnProfileStateChanged()
            print(Addon:S("NE Stats: active profile reset."))
        end,
    }
end

local function RefreshProfileControls()
    local activeName = GetActiveProfileNameFromDB()

    if controlRefs.profileDropDown then
        controlRefs.profileDropDown:Refresh(activeName)
    end
    if controlRefs.profileInfo then
        controlRefs.profileInfo:SetText(Addon:S("Active profile: %s", Addon:GetDisplayProfileName(activeName)))
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
    local page = controlRefs.pages[activeTab]
    local height = 600
    if page and page.ContentHeight then
        height = math.max(600, page:ContentHeight())
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
        if key == activeTab then
            button:Disable()
        else
            button:Enable()
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
            row.swatch.texture:SetColorTexture(entry.color[1], entry.color[2], entry.color[3], 1)
            row.up:SetEnabled(CanMoveStat(index, -1))
            row.down:SetEnabled(CanMoveStat(index, 1))
            row.entry = entry
        end
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
    if controlRefs.showStatIconsCheckbox then controlRefs.showStatIconsCheckbox:SetChecked(profile.showStatIcons) end
    if controlRefs.textAlignDropDown then controlRefs.textAlignDropDown:Refresh(profile.textAlign or defaults.textAlign) end
    if controlRefs.goldUseSeparatorCheckbox then controlRefs.goldUseSeparatorCheckbox:SetChecked(profile.goldUseSeparator) end
    if controlRefs.goldSeparatorDropDown then controlRefs.goldSeparatorDropDown:Refresh(profile.goldSeparator or defaults.goldSeparator) end
    if controlRefs.lockCheckbox then controlRefs.lockCheckbox:SetChecked(profile.locked) end
    if controlRefs.showLockOnHoverCheckbox then controlRefs.showLockOnHoverCheckbox:SetChecked(profile.showLockOnHover) end
    if controlRefs.preferCurrentSpecMainStatCheckbox then controlRefs.preferCurrentSpecMainStatCheckbox:SetChecked(profile.preferCurrentSpecMainStat) end
    if controlRefs.alphaSlider then controlRefs.alphaSlider:SetValue(profile.alpha or defaults.alpha) end
    if controlRefs.scaleSlider then controlRefs.scaleSlider:SetValue(profile.scale or defaults.scale) end
    if controlRefs.fontSizeSlider then controlRefs.fontSizeSlider:SetValue(profile.fontSize or defaults.fontSize) end
    if controlRefs.columnCountSlider then controlRefs.columnCountSlider:SetValue(profile.columnCount or defaults.columnCount) end
    if controlRefs.rowsPerColumnSlider then controlRefs.rowsPerColumnSlider:SetValue(profile.rowsPerColumn or defaults.rowsPerColumn) end
    if controlRefs.rowGapSlider then controlRefs.rowGapSlider:SetValue(profile.rowGap or defaults.rowGap) end
    if controlRefs.columnGapSlider then controlRefs.columnGapSlider:SetValue(profile.columnGap or defaults.columnGap) end
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
                    controlRefs.fontPreview:SetText(font.label .. " - " .. self:S("The quick brown fox 123"))
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
    if optionsPanel then optionsPanel.name = self:S("NE Stats") end
    if controlRefs.title then controlRefs.title:SetText(self:S("NE Stats")) end
    if controlRefs.subtitle then controlRefs.subtitle:SetText(self:S("Profiles are shared across your account.\nYou can create multiple profiles to save different layouts, positions, and display settings.")) end

    for key, button in pairs(controlRefs.tabButtons or {}) do
        button:SetText(self:S(TAB_LABELS[key] or key))
    end

    if controlRefs.profileInfo then
        local activeName = GetActiveProfileNameFromDB()
        controlRefs.profileInfo:SetText(self:S("Active profile: %s", self:GetDisplayProfileName(activeName)))
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
    if controlRefs.referenceDisplayHint then
        controlRefs.referenceDisplayHint:SetText(self:S("NE_STATS_REFERENCE_MODE_HINT"))
    end
    RefreshArchonHint(self:GetProfile())

    if controlRefs.showPercentCheckbox then controlRefs.showPercentCheckbox.label:SetText(self:S("Show percentages")) end
    if controlRefs.showLabelsCheckbox then controlRefs.showLabelsCheckbox.label:SetText(self:S("Show stat names")) end
    if controlRefs.showValuesCheckbox then controlRefs.showValuesCheckbox.label:SetText(self:S("Show values")) end
    if controlRefs.showStatIconsCheckbox then controlRefs.showStatIconsCheckbox.label:SetText(self:S("Show stat icons")) end
    if controlRefs.goldUseSeparatorCheckbox then controlRefs.goldUseSeparatorCheckbox.label:SetText(self:S("Use separator for gold")) end
    if controlRefs.lockCheckbox then controlRefs.lockCheckbox.label:SetText(self:S("Lock frame")) end
    if controlRefs.showLockOnHoverCheckbox then controlRefs.showLockOnHoverCheckbox.label:SetText(self:S("Show lock icon only on hover")) end
    if controlRefs.preferCurrentSpecMainStatCheckbox then controlRefs.preferCurrentSpecMainStatCheckbox.label:SetText(self:S("Always show current specialization main stat first")) end

    if controlRefs.precisionSlider then _G[controlRefs.precisionSlider:GetName() .. "Text"]:SetText("") end
    if controlRefs.alphaSlider then _G[controlRefs.alphaSlider:GetName() .. "Text"]:SetText("") end
    if controlRefs.scaleSlider then _G[controlRefs.scaleSlider:GetName() .. "Text"]:SetText("") end
    if controlRefs.fontSizeSlider then _G[controlRefs.fontSizeSlider:GetName() .. "Text"]:SetText("") end
    if controlRefs.columnCountSlider then _G[controlRefs.columnCountSlider:GetName() .. "Text"]:SetText("") end
    if controlRefs.rowsPerColumnSlider then
        _G[controlRefs.rowsPerColumnSlider:GetName() .. "Text"]:SetText("")
        _G[controlRefs.rowsPerColumnSlider:GetName() .. "Low"]:SetText(self:S("Auto"))
    end
    if controlRefs.rowGapSlider then _G[controlRefs.rowGapSlider:GetName() .. "Text"]:SetText("") end
    if controlRefs.columnGapSlider then _G[controlRefs.columnGapSlider:GetName() .. "Text"]:SetText("") end

    if StaticPopupDialogs["NE_STATS_RESET_PROFILE"] then
        StaticPopupDialogs["NE_STATS_RESET_PROFILE"].text = self:S("Reset active profile %s?")
        StaticPopupDialogs["NE_STATS_RESET_PROFILE"].button1 = self:S("Reset")
        StaticPopupDialogs["NE_STATS_RESET_PROFILE"].button2 = self:S("Cancel")
    end

    for _, row in ipairs(rowControls) do
        if row.color then row.color:SetText(self:S("Color")) end
    end

    self:RefreshOptions()
end

local function CreateCard(page, title, topY)
    local card = CreateFrame("Frame", nil, page, "BackdropTemplate")
    card:SetPoint("TOPLEFT", page, "TOPLEFT", FORM_X, topY)
    card:SetWidth(PAGE_WIDTH - (FORM_X * 2))
    card:SetBackdrop({
        bgFile = "Interface/Buttons/WHITE8x8",
        edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
        tile = true,
        tileSize = 8,
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    card:SetBackdropColor(0.06, 0.06, 0.06, 0.22)
    card:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.6)

    local padding = 14
    local currentY = -(padding + 22)

    local titleLabel = CreateLabel(card, title, "GameFontNormal")
    titleLabel:SetPoint("TOPLEFT", card, "TOPLEFT", padding, -padding)

    function card:AddDropdownRow(labelText, dropdown, width)
        local label = CreateLabel(self, labelText, "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", self, "TOPLEFT", LABEL_X, currentY - 4)
        dropdown:ClearAllPoints()
        dropdown:SetPoint("TOPLEFT", self, "TOPLEFT", CONTROL_X, currentY + 8)
        UIDropDownMenu_SetWidth(dropdown, width or CONTROL_W)
        currentY = currentY - FORM_ROW_H
        return label
    end

    function card:AddCheckboxRow(checkbox)
        checkbox:ClearAllPoints()
        checkbox:SetPoint("TOPLEFT", self, "TOPLEFT", CONTROL_X, currentY + 8)
        currentY = currentY - FORM_ROW_H
    end

    function card:AddSliderRow(labelText, slider)
        local label = CreateLabel(self, labelText, "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", self, "TOPLEFT", LABEL_X, currentY - 4)
        slider:ClearAllPoints()
        slider:SetPoint("TOPLEFT", self, "TOPLEFT", CONTROL_X, currentY + 2)
        slider:SetWidth(CONTROL_W)
        local titleText = _G[slider:GetName() .. "Text"]
        if titleText then
            titleText:SetText("")
        end
        currentY = currentY - SLIDER_ROW_H
        return label
    end

    function card:AddControlRow(labelText, control)
        local label = CreateLabel(self, labelText, "GameFontNormalSmall")
        label:SetPoint("TOPLEFT", self, "TOPLEFT", LABEL_X, currentY - 4)
        control:ClearAllPoints()
        control:SetPoint("TOPLEFT", self, "TOPLEFT", CONTROL_X, currentY + 8)
        currentY = currentY - FORM_ROW_H
        return label
    end

    function card:AddTextLine(text, fontTemplate, width)
        local textLine = CreateLabel(self, text, fontTemplate or "GameFontHighlightSmall")
        textLine:SetPoint("TOPLEFT", self, "TOPLEFT", CONTROL_X, currentY + 2)
        textLine:SetWidth(width or (CONTROL_W + 180))
        textLine:SetJustifyH("LEFT")
        currentY = currentY - FORM_ROW_H
        return textLine
    end

    function card:AddButtonRow(button)
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", self, "TOPLEFT", CONTROL_X, currentY + 6)
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
    page:AddTitle(Addon:S("Profiles"))

    local card = CreateCard(page, Addon:S("Profiles"), FORM_Y)

    local activeDropDown = CreateDropDown(card, addonName .. "ProfileDropDown", 190, function()
        return CreateProfileItems("active")
    end, function(profileName)
        Addon:SelectRootProfile(profileName)
        Addon:OnProfileStateChanged()
    end)
    card:AddDropdownRow(Addon:S("Current profile"), activeDropDown, 190)
    controlRefs.profileDropDown = activeDropDown

    local profileInfo = card:AddTextLine("", "GameFontHighlightSmall", 320)
    controlRefs.profileInfo = profileInfo

    local createEditBox = CreateFrame("EditBox", nil, card, "InputBoxTemplate")
    createEditBox:SetSize(220, 24)
    createEditBox:SetAutoFocus(false)
    createEditBox:SetScript("OnEnterPressed", function(self)
        CreateProfileFromInput(self)
        self:ClearFocus()
    end)
    local createLabel = card:AddControlRow(Addon:S("Create profile"), createEditBox)
    controlRefs.profileCreateLabel = createLabel
    controlRefs.profileCreateEditBox = createEditBox
    local createButton = CreateButton(card, 90, Addon:S("Create"), function()
        CreateProfileFromInput(createEditBox)
    end)
    createButton:SetPoint("LEFT", createEditBox, "RIGHT", 6, 0)
    controlRefs.profileCreateButton = createButton

    local copyDropDown = CreateDropDown(card, addonName .. "ProfileCopySourceDropDown", 190, function()
        return CreateProfileItems("copySource")
    end)
    card:AddDropdownRow(Addon:S("Copy into current"), copyDropDown, 190)
    controlRefs.profileCopySourceDropDown = copyDropDown
    local copyButton = CreateButton(card, 90, Addon:S("Copy"), function()
        local sourceProfileName = copyDropDown.selectedValue
        if not sourceProfileName then
            print(Addon:S("NE Stats: source profile is not selected."))
            return
        end
        local activeName = GetActiveProfileNameFromDB()
        if Addon:CopyProfile(sourceProfileName) then
            print(Addon:S("NE Stats: copied profile %s into active profile %s.", Addon:GetDisplayProfileName(sourceProfileName), Addon:GetDisplayProfileName(activeName)))
            Addon:OnProfileStateChanged()
        else
            print(Addon:S("NE Stats: profile could not be copied."))
        end
    end)
    copyButton:SetPoint("LEFT", copyDropDown, "RIGHT", 6, 0)
    controlRefs.profileCopyButton = copyButton

    local renameDropDown = CreateDropDown(card, addonName .. "ProfileRenameTargetDropDown", 190, function()
        return CreateProfileItems("renameTarget")
    end)
    card:AddDropdownRow(Addon:S("Rename profile"), renameDropDown, 190)
    controlRefs.profileRenameTargetDropDown = renameDropDown
    local renameButton = CreateButton(card, 90, Addon:S("Rename"), function()
        local profileName = renameDropDown.selectedValue
        if not profileName or not Addon:CanModifyProfile(profileName) then
            print(Addon:S("NE Stats: profile could not be renamed."))
            return
        end
        local dialog = StaticPopup_Show("NE_STATS_RENAME_PROFILE", Addon:GetDisplayProfileName(profileName), nil, profileName)
        if dialog then
            dialog.data = profileName
        end
    end)
    renameButton:SetPoint("LEFT", renameDropDown, "RIGHT", 6, 0)
    controlRefs.profileRenameButton = renameButton

    local deleteDropDown = CreateDropDown(card, addonName .. "ProfileDeleteTargetDropDown", 190, function()
        return CreateProfileItems("deleteTarget")
    end)
    card:AddDropdownRow(Addon:S("Delete profile"), deleteDropDown, 190)
    controlRefs.profileDeleteTargetDropDown = deleteDropDown
    local deleteButton = CreateButton(card, 90, Addon:S("Delete"), function()
        local profileName = deleteDropDown.selectedValue
        if not profileName or not Addon:CanModifyProfile(profileName) or profileName == GetActiveProfileNameFromDB() then
            print(Addon:S("NE Stats: profile could not be deleted."))
            return
        end
        StaticPopup_Show("NE_STATS_DELETE_PROFILE", Addon:GetDisplayProfileName(profileName), nil, profileName)
    end)
    deleteButton:SetPoint("LEFT", deleteDropDown, "RIGHT", 6, 0)
    controlRefs.profileDeleteButton = deleteButton

    card:Advance(8)
    local resetButton = CreateButton(card, 200, Addon:S("Reset Current"), function()
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
    page:AddTitle(Addon:S("Display"))

    local currentTopY = FORM_Y

    local generalCard = CreateCard(page, Addon:S("General"), currentTopY)

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
    end)
    generalCard:AddDropdownRow(Addon:S("Addon language"), languageDropDown, 220)
    controlRefs.languageDropDown = languageDropDown

    local drModeDropDown = CreateDropDown(generalCard, addonName .. "DRModeDropDown", 220, function()
        return {
            { value = "off", text = Addon:S("Off") },
            { value = "penalty", text = Addon:S("DR penalty (%)") },
            { value = "loss", text = Addon:S("Rating lost to DR") },
            { value = "full", text = Addon:S("Full DR info") },
        }
    end, function(mode)
        SetValue("drDisplayMode", mode)
        Addon:RefreshStats()
    end)
    generalCard:AddDropdownRow(Addon:S("Diminishing returns"), drModeDropDown, 220)
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
    generalCard:AddDropdownRow(Addon:S("Text alignment"), textAlignDropDown, 160)
    controlRefs.textAlignDropDown = textAlignDropDown

    currentTopY = generalCard:Finish() - GROUP_GAP

    local numbersCard = CreateCard(page, Addon:S("Numbers"), currentTopY)

    local showPercentCheckbox = CreateCheckbox(numbersCard, Addon:S("Show percentages"), nil, function(self)
        SetValue("showPercent", self:GetChecked())
        Addon:RefreshStats()
    end)
    numbersCard:AddCheckboxRow(showPercentCheckbox)
    controlRefs.showPercentCheckbox = showPercentCheckbox

    local precisionSlider = CreateSlider(addonName .. "PercentPrecisionSlider", numbersCard, Addon:S("Percent Decimals"), 0, 3, 1, function(_, value)
        SetValue("percentPrecision", value)
        Addon:RefreshStats()
    end)
    numbersCard:AddSliderRow(Addon:S("Percent decimals"), precisionSlider)
    controlRefs.precisionSlider = precisionSlider

    local showLabelsCheckbox = CreateCheckbox(numbersCard, Addon:S("Show stat names"), nil, function(self)
        SetValue("showLabels", self:GetChecked())
        Addon:RefreshStats()
    end)
    numbersCard:AddCheckboxRow(showLabelsCheckbox)
    controlRefs.showLabelsCheckbox = showLabelsCheckbox

    local showValuesCheckbox = CreateCheckbox(numbersCard, Addon:S("Show values"), nil, function(self)
        SetValue("showValues", self:GetChecked())
        Addon:RefreshStats()
    end)
    numbersCard:AddCheckboxRow(showValuesCheckbox)
    controlRefs.showValuesCheckbox = showValuesCheckbox

    local goldUseSeparatorCheckbox = CreateCheckbox(numbersCard, Addon:S("Use separator for gold"), nil, function(self)
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
    numbersCard:AddDropdownRow(Addon:S("Gold separator"), goldSeparatorDropDown, 160)
    controlRefs.goldSeparatorDropDown = goldSeparatorDropDown

    currentTopY = numbersCard:Finish() - GROUP_GAP

    local frameCard = CreateCard(page, Addon:S("Frame"), currentTopY)

    local lockCheckbox = CreateCheckbox(frameCard, Addon:S("Lock frame"), nil, function(self)
        SetValue("locked", self:GetChecked())
        Addon:UpdateFrameLockState()
        if self:GetChecked() then
            print(Addon:S("NE Stats: frame locked. Use settings to unlock and adjust it."))
        else
            print(Addon:S("NE Stats: frame unlocked. Drag it, then lock when ready."))
        end
    end)
    frameCard:AddCheckboxRow(lockCheckbox)
    controlRefs.lockCheckbox = lockCheckbox

    local showLockOnHoverCheckbox = CreateCheckbox(frameCard, Addon:S("Show lock icon only on hover"), Addon:S("Shows the lock button only while the mouse is over the frame."), function(self)
        SetValue("showLockOnHover", self:GetChecked())
        Addon:UpdateFrameLockState()
    end)
    frameCard:AddCheckboxRow(showLockOnHoverCheckbox)
    controlRefs.showLockOnHoverCheckbox = showLockOnHoverCheckbox

    local alphaSlider = CreateSlider(addonName .. "AlphaSlider", frameCard, Addon:S("Background Opacity"), 0.1, 1, 0.05, function(_, value)
        SetValue("alpha", value)
        Addon:ApplyFrameStyle()
    end)
    frameCard:AddSliderRow(Addon:S("Background opacity"), alphaSlider)
    controlRefs.alphaSlider = alphaSlider

    local scaleSlider = CreateSlider(addonName .. "ScaleSlider", frameCard, Addon:S("UI Scale"), 0.5, 3, 0.05, function(_, value)
        SetValue("scale", value)
        Addon:ApplyFrameStyle()
        Addon:RefreshStats()
    end)
    frameCard:AddSliderRow(Addon:S("UI scale"), scaleSlider)
    controlRefs.scaleSlider = scaleSlider

    local resetButton = CreateButton(frameCard, 180, Addon:S("Reset Position"), function()
        local profile = Profile()
        profile.point = defaults.point
        profile.relativeTo = defaults.relativeTo
        profile.relativePoint = defaults.relativePoint
        profile.x = defaults.x
        profile.y = defaults.y
        Addon:ApplyFrameStyle()
        Addon:RefreshStats()
        print(Addon:S("NE Stats: frame position reset."))
    end)
    frameCard:AddButtonRow(resetButton)
    controlRefs.resetButton = resetButton

    currentTopY = frameCard:Finish() - GROUP_GAP

    local textLayoutCard = CreateCard(page, Addon:S("Text & Layout"), currentTopY)

    local fontSizeSlider = CreateSlider(addonName .. "FontSizeSlider", textLayoutCard, Addon:S("Font Size"), 10, 32, 1, function(_, value)
        SetValue("fontSize", value)
        Addon:RefreshStats()
    end)
    textLayoutCard:AddSliderRow(Addon:S("Font size"), fontSizeSlider)
    controlRefs.fontSizeSlider = fontSizeSlider

    local columnCountSlider = CreateSlider(addonName .. "ColumnCountSlider", textLayoutCard, Addon:S("Columns"), 1, #statKeys, 1, function(_, value)
        SetValue("columnCount", math.max(1, math.floor(value + 0.5)))
        Addon:RefreshStats()
    end)
    textLayoutCard:AddSliderRow(Addon:S("Columns"), columnCountSlider)
    controlRefs.columnCountSlider = columnCountSlider

    local rowsPerColumnSlider = CreateSlider(addonName .. "RowsPerColumnSlider", textLayoutCard, Addon:S("Max Rows per Column"), 0, #statKeys, 1, function(_, value)
        SetValue("rowsPerColumn", math.max(0, math.floor(value + 0.5)))
        Addon:RefreshStats()
    end)
    _G[rowsPerColumnSlider:GetName() .. "Low"]:SetText(Addon:S("Auto"))
    textLayoutCard:AddSliderRow(Addon:S("Max rows per column"), rowsPerColumnSlider)
    controlRefs.rowsPerColumnSlider = rowsPerColumnSlider

    local showStatIconsCheckbox = CreateCheckbox(textLayoutCard, Addon:S("Show stat icons"), nil, function(self)
        SetValue("showStatIcons", self:GetChecked())
        Addon:RefreshStats()
    end)
    textLayoutCard:AddCheckboxRow(showStatIconsCheckbox)
    controlRefs.showStatIconsCheckbox = showStatIconsCheckbox

    local rowGapSlider = CreateSlider(addonName .. "RowGapSlider", textLayoutCard, Addon:S("Row spacing"), 0, 20, 1, function(_, value)
        SetValue("rowGap", math.max(0, math.floor(value + 0.5)))
        Addon:RefreshStats()
    end)
    textLayoutCard:AddSliderRow(Addon:S("Row spacing"), rowGapSlider)
    controlRefs.rowGapSlider = rowGapSlider

    local columnGapSlider = CreateSlider(addonName .. "ColumnGapSlider", textLayoutCard, Addon:S("Column spacing"), 0, 120, 1, function(_, value)
        SetValue("columnGap", math.max(0, math.floor(value + 0.5)))
        Addon:RefreshStats()
    end)
    textLayoutCard:AddSliderRow(Addon:S("Column spacing"), columnGapSlider)
    controlRefs.columnGapSlider = columnGapSlider

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
            controlRefs.fontPreview:SetText((item and item.text or fontKey) .. " - " .. Addon:S("The quick brown fox 123"))
        end
        RefreshStatsDeferred()
    end)
    textLayoutCard:AddDropdownRow(Addon:S("Font"), fontDropDown, 220)
    controlRefs.fontDropDown = fontDropDown

    local fontPreview = textLayoutCard:AddTextLine(Addon:S("The quick brown fox 123"), "GameFontHighlight", 320)
    controlRefs.fontPreview = fontPreview
    local bottomY = textLayoutCard:Finish()
    page.cursorY = bottomY - GROUP_GAP

    return page
end

local function BuildStatsPage(content, addonName, statKeys)
    local page = CreatePage(content, "stats")
    page:AddTitle(Addon:S("Stats"))

    local card = CreateCard(page, Addon:S("Stats"), FORM_Y)

    local priorityDropDown = CreateDropDown(card, addonName .. "PriorityModeDropDown", 220, function()
        local items = {}
        for _, option in ipairs(PRIORITY_MODE_OPTIONS) do
            table.insert(items, { value = option.value, text = Addon:S(option.label) })
        end
        return items
    end, function(mode)
        Addon:SetStatPriorityMode(mode)
    end)
    card:AddDropdownRow(Addon:S("NE_STATS_DISPLAY_ORDER"), priorityDropDown, 220)
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
    card:AddDropdownRow(Addon:S("Reference display"), referenceDropDown, 220)
    controlRefs.referenceDisplayDropDown = referenceDropDown

    local preferCurrentSpecMainStatCheckbox = CreateCheckbox(card, Addon:S("Always show current specialization main stat first"), Addon:S("Keeps the primary stat for your current specialization at the top of the display."), function(self)
        SetValue("preferCurrentSpecMainStat", self:GetChecked())
        Addon:RefreshStats()
    end)
    preferCurrentSpecMainStatCheckbox.label:SetWidth(420)
    card:AddCheckboxRow(preferCurrentSpecMainStatCheckbox)
    controlRefs.preferCurrentSpecMainStatCheckbox = preferCurrentSpecMainStatCheckbox

    local hint = CreateLabel(card, Addon:S("NE_STATS_ARCHON_LOCK_ORDER_HINT"), "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", card, "TOPLEFT", LABEL_X, card:GetCurrentY() + 4)
    hint:SetWidth(500)
    hint:SetJustifyH("LEFT")
    controlRefs.priorityHint = hint
    card:Advance(FORM_ROW_H)

    local archonHint = CreateLabel(card, "", "GameFontHighlightSmall")
    archonHint:SetPoint("TOPLEFT", card, "TOPLEFT", LABEL_X, card:GetCurrentY() + 4)
    archonHint:SetWidth(500)
    archonHint:SetJustifyH("LEFT")
    controlRefs.archonHint = archonHint
    card:Advance(FORM_ROW_H)

    local referenceModeHint = CreateLabel(card, Addon:S("NE_STATS_REFERENCE_MODE_HINT"), "GameFontHighlightSmall")
    referenceModeHint:SetPoint("TOPLEFT", card, "TOPLEFT", LABEL_X, card:GetCurrentY() + 4)
    referenceModeHint:SetWidth(500)
    referenceModeHint:SetJustifyH("LEFT")
    controlRefs.referenceDisplayHint = referenceModeHint
    card:Advance(FORM_ROW_H)

    local header = CreateLabel(card, Addon:S("Check to show, set color, move with arrows"), "GameFontNormalSmall")
    header:SetPoint("TOPLEFT", card, "TOPLEFT", LABEL_X, card:GetCurrentY() + 4)
    controlRefs.statHint = header
    card:Advance(FORM_ROW_H)

    for index = 1, #statKeys do
        local row = CreateFrame("Frame", nil, card)
        row:SetSize(PAGE_WIDTH - (FORM_X * 2) - (LABEL_X * 2), 26)
        row:SetPoint("TOPLEFT", card, "TOPLEFT", LABEL_X, card:GetCurrentY() + 6)

        local checkbox = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        checkbox:SetPoint("LEFT", 0, 0)
        row.checkbox = checkbox

        local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        label:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
        label:SetWidth(170)
        label:SetJustifyH("LEFT")
        row.label = label

        local swatch = CreateFrame("Button", nil, row, "BackdropTemplate")
        swatch:SetSize(16, 16)
        swatch:SetPoint("LEFT", label, "RIGHT", 8, 0)
        swatch:SetBackdrop({
            bgFile = "Interface/Buttons/WHITE8x8",
            edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
            tile = true,
            tileSize = 8,
            edgeSize = 8,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        swatch:SetBackdropColor(0, 0, 0, 0.9)
        swatch.texture = swatch:CreateTexture(nil, "ARTWORK")
        swatch.texture:SetPoint("TOPLEFT", 2, -2)
        swatch.texture:SetPoint("BOTTOMRIGHT", -2, 2)
        row.swatch = swatch

        local color = CreateButton(row, 60, Addon:S("Color"), function()
            OpenColorPicker(row.entry)
        end)
        color:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
        row.color = color

        local up = CreateFrame("Button", nil, row)
        up:SetSize(24, 20)
        up:SetPoint("LEFT", color, "RIGHT", 16, 0)
        up:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up")
        up:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Down")
        up:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
        up:SetDisabledTexture("Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Disabled")
        row.up = up

        local down = CreateFrame("Button", nil, row)
        down:SetSize(24, 20)
        down:SetPoint("LEFT", up, "RIGHT", 6, 0)
        down:SetNormalTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
        down:SetPushedTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Down")
        down:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
        down:SetDisabledTexture("Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Disabled")
        row.down = down

        checkbox:SetScript("OnClick", function(self)
            row.entry.enabled = self:GetChecked()
            Addon:RefreshStats()
        end)
        swatch:SetScript("OnClick", function()
            OpenColorPicker(row.entry)
        end)
        up:SetScript("OnClick", function()
            MoveStat(row.index, -1)
        end)
        down:SetScript("OnClick", function()
            MoveStat(row.index, 1)
        end)

        rowControls[index] = row
        card:Advance(FORM_ROW_H)
    end

    local bottomY = card:Finish()
    page.cursorY = bottomY - GROUP_GAP

    return page
end

function Addon:BuildOptionsPanel()
    if optionsPanel and optionsPanelBuilt then return end

    local addonName = self.name or ADDON_NAME_FALLBACK
    local defaults = self.Defaults.profile
    local statKeys = self.Constants.STAT_KEYS

    optionsPanel = CreateFrame("Frame", addonName .. "OptionsPanel", UIParent)
    optionsPanel.name = self:S("NE Stats")
    optionsPanel:SetSize(780, 620)

    local scrollFrame = CreateFrame("ScrollFrame", addonName .. "OptionsScrollFrame", optionsPanel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 12, -12)
    scrollFrame:SetPoint("BOTTOMRIGHT", -32, 12)
    controlRefs.scrollFrame = scrollFrame

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(720, 620)
    scrollFrame:SetScrollChild(content)
    controlRefs.scrollContent = content

    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(self:S("NE Stats"))
    controlRefs.title = title

    local subtitle = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    subtitle:SetWidth(660)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetText(self:S("Profiles are shared across your account.\nYou can create multiple profiles to save different layouts, positions, and display settings."))
    controlRefs.subtitle = subtitle

    controlRefs.tabButtons = {}
    local previousTab
    for _, key in ipairs(TAB_ORDER) do
        local button = CreateButton(content, 110, self:S(TAB_LABELS[key]), function()
            ShowOptionsTab(key)
        end)
        if previousTab then
            button:SetPoint("LEFT", previousTab, "RIGHT", 8, 0)
        else
            button:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -18)
        end
        controlRefs.tabButtons[key] = button
        previousTab = button
    end

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
        optionsCategory = Settings.RegisterCanvasLayoutCategory(optionsPanel, self:S("NE Stats"))
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
    activeTab = "profiles"
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
            print(self:S("NE Stats: settings panel failed: %s", tostring(lastOptionsPanelError)))
        else
            print(self:S("NE Stats: settings panel is not available yet."))
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
    print(self:S("NE Stats: settings panel is not available yet."))
end
