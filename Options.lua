local _, ns = ...

ns = ns or {}
ns.ZhuraStats = ns.ZhuraStats or {}
local Addon = ns.ZhuraStats

local optionsPanel
local optionsCategory
local optionsCategoryID
local optionsPanelBuilt = false
local lastOptionsPanelError
local rowControls = {}
local controlRefs = {}
local InitializeProfileDropDown
local InitializeLanguageDropDown

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

local function SetProfileDropDownSelection(dropDown, profileName)
    if not dropDown or not profileName then
        return
    end
    local displayName = Addon:GetDisplayProfileName(profileName)
    UIDropDownMenu_SetText(dropDown, displayName)
    UIDropDownMenu_SetSelectedName(dropDown, displayName)
    UIDropDownMenu_SetSelectedValue(dropDown, profileName)
end

local function MoveStat(index, direction)
    local stats = Profile().stats
    local target = index + direction
    if not stats[index] or not stats[target] then
        return
    end
    stats[index], stats[target] = stats[target], stats[index]
    Addon:RefreshStats()
end

local function CreateCheckbox(parent, label, tooltip, onClick)
    local checkbox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    checkbox.label = checkbox:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    checkbox.label:SetPoint("LEFT", checkbox, "RIGHT", 6, 0)
    checkbox.label:SetJustifyH("LEFT")
    checkbox.label:SetText(label)
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

local function CreateIconButton(parent, width, height, normalTexture, pushedTexture, disabledTexture, tooltipText)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(width, height)
    button:SetNormalTexture(normalTexture)
    button:SetPushedTexture(pushedTexture or normalTexture)
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    if disabledTexture then
        button:SetDisabledTexture(disabledTexture)
    end
    button.tooltipText = tooltipText
    button:SetScript("OnEnter", function(self)
        if not self.tooltipText then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tooltipText, 1, 0.82, 0)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    button:SetMotionScriptsWhileDisabled(true)
    return button
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
        if optionsPanel and optionsPanel:GetScript("OnShow") then
            optionsPanel:GetScript("OnShow")(optionsPanel)
        end
    end

    if ColorPickerFrame and ColorPickerFrame.SetupColorPickerAndShow then
        ColorPickerFrame:SetupColorPickerAndShow({
            r = color[1], g = color[2], b = color[3], hasOpacity = false,
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
    Addon:ApplyCurrentProfileState()
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

    local profile = self:GetProfile()
    local statDefinitions = self.StatDefinitions
    for index, row in ipairs(rowControls) do
        local entry = profile.stats[index]
        local def = statDefinitions[entry.key]
        row.index = index
        row.checkbox:SetChecked(entry.enabled)
        row.label:SetText(self:S(def.label))
        row.swatch.texture:SetColorTexture(entry.color[1], entry.color[2], entry.color[3], 1)
        row.up:SetEnabled(index > 1)
        row.down:SetEnabled(index < #profile.stats)
        row.entry = entry
    end
end

function Addon:ApplyCurrentProfileStateImpl()
    local defaults = self.Defaults.profile
    local profile, activeProfileName = self:GetActiveRootProfile()

    if controlRefs.profileDropDown then
        if InitializeProfileDropDown then
            UIDropDownMenu_Initialize(controlRefs.profileDropDown, InitializeProfileDropDown)
        end
        controlRefs.profileDropDown:SetValue(activeProfileName)
    end
    if controlRefs.profileInfo then
        controlRefs.profileInfo:SetText(self:S("Active profile: %s", self:GetDisplayProfileName(activeProfileName)))
    end
    if controlRefs.profileRenameButton then
        controlRefs.profileRenameButton:SetEnabled(self:CanModifyProfile(activeProfileName))
    end
    if controlRefs.profileDeleteButton then
        controlRefs.profileDeleteButton:SetEnabled(self:CanModifyProfile(activeProfileName))
    end
    if controlRefs.languageDropDown then
        UIDropDownMenu_SetSelectedValue(controlRefs.languageDropDown, self:GetConfiguredLocale())
        UIDropDownMenu_SetText(controlRefs.languageDropDown, self:GetLocaleDisplayName(self:GetConfiguredLocale()))
    end
    if controlRefs.showPercentCheckbox then controlRefs.showPercentCheckbox:SetChecked(profile.showPercent) end
    if controlRefs.precisionSlider then controlRefs.precisionSlider:SetValue(profile.percentPrecision or defaults.percentPrecision) end
    if controlRefs.drModeDropDown then
        local mode = profile.drDisplayMode or "off"
        local labels = { off = self:S("Off"), suffix = self:S("Show next threshold (->39%)") }
        UIDropDownMenu_SetSelectedValue(controlRefs.drModeDropDown, mode)
        UIDropDownMenu_SetText(controlRefs.drModeDropDown, labels[mode] or mode)
    end
    if controlRefs.showLabelsCheckbox then controlRefs.showLabelsCheckbox:SetChecked(profile.showLabels) end
    if controlRefs.showValuesCheckbox then controlRefs.showValuesCheckbox:SetChecked(profile.showValues) end
    if controlRefs.textAlignDropDown then
        local align = profile.textAlign or defaults.textAlign
        UIDropDownMenu_SetSelectedValue(controlRefs.textAlignDropDown, align)
        UIDropDownMenu_SetText(controlRefs.textAlignDropDown, self:GetTextAlignDisplayName(align))
    end
    if controlRefs.goldUseSeparatorCheckbox then controlRefs.goldUseSeparatorCheckbox:SetChecked(profile.goldUseSeparator) end
    if controlRefs.goldSeparatorDropDown then
        UIDropDownMenu_Initialize(controlRefs.goldSeparatorDropDown, controlRefs.goldSeparatorDropDown.initializeFunc)
        UIDropDownMenu_SetSelectedValue(controlRefs.goldSeparatorDropDown, profile.goldSeparator or defaults.goldSeparator)
        UIDropDownMenu_SetText(controlRefs.goldSeparatorDropDown, self:GetGoldSeparatorDisplayName(profile.goldSeparator or defaults.goldSeparator))
    end
    if controlRefs.lockCheckbox then controlRefs.lockCheckbox:SetChecked(profile.locked) end
    if controlRefs.showLockOnHoverCheckbox then controlRefs.showLockOnHoverCheckbox:SetChecked(profile.showLockOnHover) end
    if controlRefs.preferCurrentSpecMainStatCheckbox then controlRefs.preferCurrentSpecMainStatCheckbox:SetChecked(profile.preferCurrentSpecMainStat) end
    if controlRefs.alphaSlider then controlRefs.alphaSlider:SetValue(profile.alpha or defaults.alpha) end
    if controlRefs.scaleSlider then controlRefs.scaleSlider:SetValue(profile.scale or defaults.scale) end
    if controlRefs.fontSizeSlider then controlRefs.fontSizeSlider:SetValue(profile.fontSize or defaults.fontSize) end
    if controlRefs.columnCountSlider then controlRefs.columnCountSlider:SetValue(profile.columnCount or defaults.columnCount) end
    if controlRefs.rowsPerColumnSlider then controlRefs.rowsPerColumnSlider:SetValue(profile.rowsPerColumn or defaults.rowsPerColumn) end

    if controlRefs.fontDropDown or controlRefs.fontPreview then
        for _, font in ipairs(self:GetAvailableFonts()) do
            if font.key == profile.fontKey then
                if controlRefs.fontDropDown then
                    UIDropDownMenu_SetSelectedName(controlRefs.fontDropDown, font.label)
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
    if controlRefs.profileLabel then controlRefs.profileLabel:SetText(self:S("Profile")) end
    if controlRefs.profileCreateLabel then controlRefs.profileCreateLabel:SetText(self:S("Create New...")) end
    if controlRefs.languageLabel then controlRefs.languageLabel:SetText(self:S("Addon language")) end
    if controlRefs.profileCreateButton then controlRefs.profileCreateButton:SetText(self:S("Create")) end
    if controlRefs.profileRenameButton then controlRefs.profileRenameButton.tooltipText = self:S("Rename profile") end
    if controlRefs.profileDeleteButton then controlRefs.profileDeleteButton.tooltipText = self:S("Delete profile") end
    if controlRefs.showPercentCheckbox then controlRefs.showPercentCheckbox.label:SetText(self:S("Show percentages")) end
    if controlRefs.drModeLabel then controlRefs.drModeLabel:SetText(self:S("Diminishing returns")) end
    if controlRefs.drModeDropDown then
        UIDropDownMenu_Initialize(controlRefs.drModeDropDown, controlRefs.drModeDropDown.initializeFunc)
        local mode = (GetValue("drDisplayMode", defaults.drDisplayMode))
        local labels = { off = self:S("Off"), suffix = self:S("Show next threshold (->39%)") }
        UIDropDownMenu_SetSelectedValue(controlRefs.drModeDropDown, mode)
        UIDropDownMenu_SetText(controlRefs.drModeDropDown, labels[mode] or mode)
    end
    if controlRefs.showLabelsCheckbox then controlRefs.showLabelsCheckbox.label:SetText(self:S("Show stat names")) end
    if controlRefs.showValuesCheckbox then controlRefs.showValuesCheckbox.label:SetText(self:S("Show values")) end
    if controlRefs.textAlignLabel then controlRefs.textAlignLabel:SetText(self:S("Text alignment")) end
    if controlRefs.textAlignDropDown then
        UIDropDownMenu_Initialize(controlRefs.textAlignDropDown, controlRefs.textAlignDropDown.initializeFunc)
        local align = (GetValue("textAlign", defaults.textAlign))
        UIDropDownMenu_SetSelectedValue(controlRefs.textAlignDropDown, align)
        UIDropDownMenu_SetText(controlRefs.textAlignDropDown, self:GetTextAlignDisplayName(align))
    end
    if controlRefs.goldUseSeparatorCheckbox then controlRefs.goldUseSeparatorCheckbox.label:SetText(self:S("Use separator for gold")) end
    if controlRefs.goldSeparatorLabel then controlRefs.goldSeparatorLabel:SetText(self:S("Gold separator")) end
    if controlRefs.goldSeparatorDropDown then
        UIDropDownMenu_Initialize(controlRefs.goldSeparatorDropDown, controlRefs.goldSeparatorDropDown.initializeFunc)
        local separator = (GetValue("goldSeparator", defaults.goldSeparator))
        UIDropDownMenu_SetSelectedValue(controlRefs.goldSeparatorDropDown, separator)
        UIDropDownMenu_SetText(controlRefs.goldSeparatorDropDown, self:GetGoldSeparatorDisplayName(separator))
    end
    if controlRefs.lockCheckbox then controlRefs.lockCheckbox.label:SetText(self:S("Lock frame")) end
    if controlRefs.showLockOnHoverCheckbox then
        controlRefs.showLockOnHoverCheckbox.label:SetText(self:S("Show lock icon only on hover"))
        controlRefs.showLockOnHoverCheckbox.tooltipText = self:S("Shows the lock button only while the mouse is over the frame.")
    end
    if controlRefs.preferCurrentSpecMainStatCheckbox then
        controlRefs.preferCurrentSpecMainStatCheckbox.label:SetText(self:S("Always show current specialization main stat first"))
        controlRefs.preferCurrentSpecMainStatCheckbox.tooltipText = self:S("Keeps the primary stat for your current specialization at the top of the display.")
    end
    if controlRefs.fontLabel then controlRefs.fontLabel:SetText(self:S("Font")) end
    if controlRefs.resetButton then controlRefs.resetButton:SetText(self:S("Reset Position")) end
    if controlRefs.statHeader then controlRefs.statHeader:SetText(self:S("Stats")) end
    if controlRefs.statHint then controlRefs.statHint:SetText(self:S("Check to show, set color, move with arrows")) end
    if controlRefs.precisionSlider then _G[controlRefs.precisionSlider:GetName() .. "Text"]:SetText(self:S("Percent Decimals")) end
    if controlRefs.alphaSlider then _G[controlRefs.alphaSlider:GetName() .. "Text"]:SetText(self:S("Background Opacity")) end
    if controlRefs.scaleSlider then _G[controlRefs.scaleSlider:GetName() .. "Text"]:SetText(self:S("UI Scale")) end
    if controlRefs.fontSizeSlider then _G[controlRefs.fontSizeSlider:GetName() .. "Text"]:SetText(self:S("Font Size")) end
    if controlRefs.columnCountSlider then _G[controlRefs.columnCountSlider:GetName() .. "Text"]:SetText(self:S("Columns")) end
    if controlRefs.rowsPerColumnSlider then
        _G[controlRefs.rowsPerColumnSlider:GetName() .. "Text"]:SetText(self:S("Max Rows per Column"))
        _G[controlRefs.rowsPerColumnSlider:GetName() .. "Low"]:SetText(self:S("Auto"))
    end
    if controlRefs.languageDropDown then
        UIDropDownMenu_Initialize(controlRefs.languageDropDown, InitializeLanguageDropDown)
        UIDropDownMenu_SetSelectedValue(controlRefs.languageDropDown, self:GetConfiguredLocale())
        UIDropDownMenu_SetText(controlRefs.languageDropDown, self:GetLocaleDisplayName(self:GetConfiguredLocale()))
    end
    for _, row in ipairs(rowControls) do
        if row.color then row.color:SetText(self:S("Color")) end
    end
    self:RefreshOptionRows()
end

function Addon:BuildOptionsPanel()
    if optionsPanel and optionsPanelBuilt then return end
    local ADDON_NAME = self.name
    local defaults = self.Defaults.profile
    local statKeys = self.Constants.STAT_KEYS

    optionsPanel = CreateFrame("Frame", ADDON_NAME .. "OptionsPanel", UIParent)
    optionsPanel.name = self:S("NE Stats")
    optionsPanel:SetSize(780, 620)
    local scrollFrame = CreateFrame("ScrollFrame", ADDON_NAME .. "OptionsScrollFrame", optionsPanel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 12, -12)
    scrollFrame:SetPoint("BOTTOMRIGHT", -32, 12)
    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetSize(720, 980)
    scrollFrame:SetScrollChild(content)
    controlRefs.scrollFrame = scrollFrame
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

    local profileLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    profileLabel:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -18)
    profileLabel:SetText(self:S("Profile"))
    controlRefs.profileLabel = profileLabel

    local profileDropDown = CreateFrame("Frame", ADDON_NAME .. "ProfileDropDown", content, "UIDropDownMenuTemplate")
    profileDropDown:SetPoint("TOPLEFT", profileLabel, "BOTTOMLEFT", -16, -2)
    UIDropDownMenu_SetWidth(profileDropDown, 240)
    InitializeProfileDropDown = function(_, level)
        for _, name in ipairs(Addon:GetProfileNames()) do
            local profileName = name
            local info = UIDropDownMenu_CreateInfo()
            info.text = Addon:GetDisplayProfileName(profileName)
            local _, activeName = Addon:GetActiveRootProfile()
            info.checked = activeName == profileName
            info.func = function()
                profileDropDown:SetValue(profileName)
                CloseDropDownMenus()
                Addon:SelectRootProfile(profileName)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end
    UIDropDownMenu_Initialize(profileDropDown, InitializeProfileDropDown)
    profileDropDown.SetValue = function(_, newValue) SetProfileDropDownSelection(profileDropDown, newValue) end
    local _, activeProfileName = self:GetActiveRootProfile()
    profileDropDown:SetValue(activeProfileName)
    controlRefs.profileDropDown = profileDropDown

    local profileDropDownText = _G[profileDropDown:GetName() .. "Text"]
    local profileDropDownButton = _G[profileDropDown:GetName() .. "Button"]
    if profileDropDownText then
        profileDropDownText:SetWidth(126)
        profileDropDownText:SetJustifyH("LEFT")
    end

    local profileActions = CreateFrame("Frame", nil, profileDropDown)
    profileActions:SetSize(34, 18)
    if profileDropDownButton then
        profileActions:SetPoint("RIGHT", profileDropDownButton, "LEFT", -12, 0)
    else
        profileActions:SetPoint("RIGHT", profileDropDown, "RIGHT", -30, 0)
    end
    profileActions:SetFrameStrata(profileDropDown:GetFrameStrata())
    profileActions:SetFrameLevel(profileDropDown:GetFrameLevel() + 8)
    controlRefs.profileActions = profileActions

    local profileRenameButton = CreateIconButton(profileActions,16,16,"Interface\\Buttons\\UI-GuildButton-PublicNote-Up","Interface\\Buttons\\UI-GuildButton-PublicNote-Down","Interface\\Buttons\\UI-GuildButton-PublicNote-Disabled",self:S("Rename profile"))
    profileRenameButton:SetPoint("RIGHT", profileActions, "RIGHT", 0, 0)
    profileRenameButton:SetFrameStrata(profileActions:GetFrameStrata())
    profileRenameButton:SetFrameLevel(profileActions:GetFrameLevel() + 1)
    profileRenameButton:SetScript("OnClick", function()
        local _, profileName = Addon:GetActiveRootProfile()
        if not Addon:CanModifyProfile(profileName) then return end
        local dialog = StaticPopup_Show("NE_STATS_RENAME_PROFILE", Addon:GetDisplayProfileName(profileName), nil, profileName)
        if dialog then dialog.data = profileName end
    end)
    controlRefs.profileRenameButton = profileRenameButton

    local profileDeleteButton = CreateIconButton(profileActions,16,16,"Interface\\Buttons\\UI-GroupLoot-Pass-Up","Interface\\Buttons\\UI-GroupLoot-Pass-Down","Interface\\Buttons\\UI-GroupLoot-Pass-Disabled",self:S("Delete profile"))
    profileDeleteButton:SetPoint("RIGHT", profileRenameButton, "LEFT", -2, 0)
    profileDeleteButton:SetFrameStrata(profileActions:GetFrameStrata())
    profileDeleteButton:SetFrameLevel(profileActions:GetFrameLevel() + 1)
    profileDeleteButton:SetScript("OnClick", function()
        local _, profileName = Addon:GetActiveRootProfile()
        if not Addon:CanModifyProfile(profileName) then return end
        StaticPopup_Show("NE_STATS_DELETE_PROFILE", Addon:GetDisplayProfileName(profileName), nil, profileName)
    end)
    controlRefs.profileDeleteButton = profileDeleteButton

    local profileInfo = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    profileInfo:SetPoint("TOPLEFT", profileDropDown, "BOTTOMLEFT", 20, -8)
    profileInfo:SetJustifyH("LEFT")
    profileInfo:SetText("")
    controlRefs.profileInfo = profileInfo

    local profileCreateLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    profileCreateLabel:SetPoint("TOPLEFT", profileInfo, "BOTTOMLEFT", 0, -10)
    profileCreateLabel:SetText(self:S("Create New..."))
    controlRefs.profileCreateLabel = profileCreateLabel

    local profileCreateEditBox = CreateFrame("EditBox", nil, content, "InputBoxTemplate")
    profileCreateEditBox:SetSize(150, 24)
    profileCreateEditBox:SetAutoFocus(false)
    profileCreateEditBox:SetPoint("TOPLEFT", profileCreateLabel, "BOTTOMLEFT", 0, -6)
    profileCreateEditBox:SetScript("OnEnterPressed", function(self)
        CreateProfileFromInput(self)
        self:ClearFocus()
    end)
    controlRefs.profileCreateEditBox = profileCreateEditBox

    local profileCreateButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    profileCreateButton:SetSize(70, 22)
    profileCreateButton:SetPoint("LEFT", profileCreateEditBox, "RIGHT", 8, 0)
    profileCreateButton:SetText(self:S("Create"))
    profileCreateButton:SetScript("OnClick", function()
        CreateProfileFromInput(profileCreateEditBox)
    end)
    controlRefs.profileCreateButton = profileCreateButton

    local languageLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    languageLabel:SetPoint("TOPLEFT", profileCreateEditBox, "BOTTOMLEFT", 0, -18)
    languageLabel:SetText(self:S("Addon language"))
    controlRefs.languageLabel = languageLabel

    local languageDropDown = CreateFrame("Frame", ADDON_NAME .. "LanguageDropDown", content, "UIDropDownMenuTemplate")
    languageDropDown:SetPoint("TOPLEFT", languageLabel, "BOTTOMLEFT", -16, -2)
    UIDropDownMenu_SetWidth(languageDropDown, 220)
    InitializeLanguageDropDown = function(_, level)
        local localeOptions = { "client","enUS","deDE","esES","esMX","frFR","itIT","koKR","ptBR","ruRU","ukUA","zhCN","zhTW" }
        for _, localeCode in ipairs(localeOptions) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = Addon:GetLocaleDisplayName(localeCode)
            info.value = localeCode
            info.checked = Addon:GetConfiguredLocale() == localeCode
            info.func = function()
                Addon:SetConfiguredLocale(localeCode)
                Addon:ApplyLocale()
                Addon:RefreshLocalizedUI()
                Addon:ApplyCurrentProfileState()
                Addon:UpdateFrameLockState()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end
    UIDropDownMenu_Initialize(languageDropDown, InitializeLanguageDropDown)
    controlRefs.languageDropDown = languageDropDown

    local showPercentCheckbox = CreateCheckbox(content, self:S("Show percentages"), nil, function(self) SetValue("showPercent", self:GetChecked()) Addon:RefreshStats() end)
    showPercentCheckbox:SetPoint("TOPLEFT", languageDropDown, "BOTTOMLEFT", 16, -16)
    controlRefs.showPercentCheckbox = showPercentCheckbox

    local precisionSlider = CreateSlider(ADDON_NAME .. "PercentPrecisionSlider", content, self:S("Percent Decimals"), 0, 3, 1, function(_, value) SetValue("percentPrecision", value) Addon:RefreshStats() end)
    precisionSlider:SetPoint("TOPLEFT", showPercentCheckbox, "BOTTOMLEFT", 6, -24)
    controlRefs.precisionSlider = precisionSlider

    local drModeLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    drModeLabel:SetPoint("TOPLEFT", precisionSlider, "BOTTOMLEFT", -6, -18)
    drModeLabel:SetText(self:S("Diminishing returns"))
    controlRefs.drModeLabel = drModeLabel

    local drModeDropDown = CreateFrame("Frame", ADDON_NAME .. "DRModeDropDown", content, "UIDropDownMenuTemplate")
    drModeDropDown:SetPoint("TOPLEFT", drModeLabel, "BOTTOMLEFT", -16, -2)
    UIDropDownMenu_SetWidth(drModeDropDown, 220)
    drModeDropDown.initializeFunc = function(_, level)
        local options = { { value = "off", label = Addon:S("Off") }, { value = "suffix", label = Addon:S("Show next threshold (->39%)") } }
        for _, opt in ipairs(options) do
            local info = UIDropDownMenu_CreateInfo()
            info.text, info.value = opt.label, opt.value
            info.checked = (GetValue("drDisplayMode", "off")) == opt.value
            info.func = function() SetValue("drDisplayMode", opt.value) UIDropDownMenu_SetSelectedValue(drModeDropDown, opt.value) UIDropDownMenu_SetText(drModeDropDown, opt.label) Addon:RefreshStats() end
            UIDropDownMenu_AddButton(info, level)
        end
    end
    UIDropDownMenu_Initialize(drModeDropDown, drModeDropDown.initializeFunc)
    controlRefs.drModeDropDown = drModeDropDown

    local showLabelsCheckbox = CreateCheckbox(content, self:S("Show stat names"), nil, function(self) SetValue("showLabels", self:GetChecked()) Addon:RefreshStats() end)
    showLabelsCheckbox:SetPoint("TOPLEFT", drModeDropDown, "BOTTOMLEFT", 16, -8)
    controlRefs.showLabelsCheckbox = showLabelsCheckbox
    local showValuesCheckbox = CreateCheckbox(content, self:S("Show values"), nil, function(self) SetValue("showValues", self:GetChecked()) Addon:RefreshStats() end)
    showValuesCheckbox:SetPoint("TOPLEFT", showLabelsCheckbox, "BOTTOMLEFT", 0, -8)
    controlRefs.showValuesCheckbox = showValuesCheckbox

    local textAlignLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    textAlignLabel:SetPoint("TOPLEFT", showValuesCheckbox, "BOTTOMLEFT", 0, -16)
    textAlignLabel:SetText(self:S("Text alignment"))
    controlRefs.textAlignLabel = textAlignLabel

    local textAlignDropDown = CreateFrame("Frame", ADDON_NAME .. "TextAlignDropDown", content, "UIDropDownMenuTemplate")
    textAlignDropDown:SetPoint("TOPLEFT", textAlignLabel, "BOTTOMLEFT", -16, -2)
    UIDropDownMenu_SetWidth(textAlignDropDown, 140)
    textAlignDropDown.initializeFunc = function(_, level)
        for _, align in ipairs(Addon.Constants.TEXT_ALIGN_OPTIONS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = Addon:GetTextAlignDisplayName(align)
            info.value = align
            info.checked = (GetValue("textAlign", defaults.textAlign)) == align
            info.func = function()
                SetValue("textAlign", align)
                UIDropDownMenu_SetSelectedValue(textAlignDropDown, align)
                UIDropDownMenu_SetText(textAlignDropDown, Addon:GetTextAlignDisplayName(align))
                Addon:ApplyTextAlignmentToVisibleLines()
                Addon:RefreshStats()
                if C_Timer and C_Timer.After then
                    C_Timer.After(0, function()
                        if Addon.initialized then
                            Addon:ApplyTextAlignmentToVisibleLines()
                            Addon:RefreshStats()
                        end
                    end)
                end
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end
    UIDropDownMenu_Initialize(textAlignDropDown, textAlignDropDown.initializeFunc)
    controlRefs.textAlignDropDown = textAlignDropDown

    local goldUseSeparatorCheckbox = CreateCheckbox(content, self:S("Use separator for gold"), nil, function(self) SetValue("goldUseSeparator", self:GetChecked()) Addon:RefreshStats() end)
    goldUseSeparatorCheckbox:SetPoint("TOPLEFT", textAlignDropDown, "BOTTOMLEFT", 16, -8)
    controlRefs.goldUseSeparatorCheckbox = goldUseSeparatorCheckbox
    local goldSeparatorLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    goldSeparatorLabel:SetPoint("TOPLEFT", goldUseSeparatorCheckbox, "BOTTOMLEFT", 0, -16)
    goldSeparatorLabel:SetText(self:S("Gold separator"))
    controlRefs.goldSeparatorLabel = goldSeparatorLabel

    local goldSeparatorDropDown = CreateFrame("Frame", ADDON_NAME .. "GoldSeparatorDropDown", content, "UIDropDownMenuTemplate")
    goldSeparatorDropDown:SetPoint("TOPLEFT", goldSeparatorLabel, "BOTTOMLEFT", -16, -2)
    UIDropDownMenu_SetWidth(goldSeparatorDropDown, 140)
    goldSeparatorDropDown.initializeFunc = function(_, level)
        for _, separator in ipairs(Addon.Constants.GOLD_SEPARATOR_OPTIONS) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = Addon:GetGoldSeparatorDisplayName(separator)
            info.value = separator
            info.checked = (GetValue("goldSeparator", defaults.goldSeparator)) == separator
            info.func = function() SetValue("goldSeparator", separator) UIDropDownMenu_SetSelectedValue(goldSeparatorDropDown, separator) UIDropDownMenu_SetText(goldSeparatorDropDown, Addon:GetGoldSeparatorDisplayName(separator)) Addon:RefreshStats() end
            UIDropDownMenu_AddButton(info, level)
        end
    end
    UIDropDownMenu_Initialize(goldSeparatorDropDown, goldSeparatorDropDown.initializeFunc)
    controlRefs.goldSeparatorDropDown = goldSeparatorDropDown

    local lockCheckbox = CreateCheckbox(content, self:S("Lock frame"), nil, function(self) SetValue("locked", self:GetChecked()) Addon:UpdateFrameLockState() if self:GetChecked() then print(Addon:S("NE Stats: frame locked. Use settings to unlock and adjust it.")) else print(Addon:S("NE Stats: frame unlocked. Drag it, then lock when ready.")) end end)
    lockCheckbox:SetPoint("TOPLEFT", goldSeparatorDropDown, "BOTTOMLEFT", 16, -12)
    controlRefs.lockCheckbox = lockCheckbox

    local showLockOnHoverCheckbox = CreateCheckbox(content, self:S("Show lock icon only on hover"), self:S("Shows the lock button only while the mouse is over the frame."), function(self) SetValue("showLockOnHover", self:GetChecked()) Addon:UpdateFrameLockState() end)
    showLockOnHoverCheckbox:SetPoint("TOPLEFT", lockCheckbox, "BOTTOMLEFT", 0, -8)
    controlRefs.showLockOnHoverCheckbox = showLockOnHoverCheckbox
    local preferCurrentSpecMainStatCheckbox = CreateCheckbox(content, self:S("Always show current specialization main stat first"), self:S("Keeps the primary stat for your current specialization at the top of the display."), function(self) SetValue("preferCurrentSpecMainStat", self:GetChecked()) Addon:RefreshStats() end)
    preferCurrentSpecMainStatCheckbox:SetPoint("TOPLEFT", showLockOnHoverCheckbox, "BOTTOMLEFT", 0, -8)
    controlRefs.preferCurrentSpecMainStatCheckbox = preferCurrentSpecMainStatCheckbox

    local alphaSlider = CreateSlider(ADDON_NAME .. "AlphaSlider", content, self:S("Background Opacity"), 0.1, 1, 0.05, function(_, value) SetValue("alpha", value) Addon:ApplyFrameStyle() end)
    alphaSlider:SetPoint("TOPLEFT", preferCurrentSpecMainStatCheckbox, "BOTTOMLEFT", 6, -24)
    controlRefs.alphaSlider = alphaSlider
    local scaleSlider = CreateSlider(ADDON_NAME .. "ScaleSlider", content, self:S("UI Scale"), 0.5, 3, 0.05, function(_, value) SetValue("scale", value) Addon:ApplyFrameStyle() Addon:RefreshStats() end)
    scaleSlider:SetPoint("TOPLEFT", alphaSlider, "BOTTOMLEFT", 0, -36)
    controlRefs.scaleSlider = scaleSlider
    local fontSizeSlider = CreateSlider(ADDON_NAME .. "FontSizeSlider", content, self:S("Font Size"), 10, 32, 1, function(_, value) SetValue("fontSize", value) Addon:RefreshStats() end)
    fontSizeSlider:SetPoint("TOPLEFT", scaleSlider, "BOTTOMLEFT", 0, -36)
    controlRefs.fontSizeSlider = fontSizeSlider
    local columnCountSlider = CreateSlider(ADDON_NAME .. "ColumnCountSlider", content, self:S("Columns"), 1, #statKeys, 1, function(_, value) SetValue("columnCount", math.max(1, math.floor(value + 0.5))) Addon:RefreshStats() end)
    columnCountSlider:SetPoint("TOPLEFT", fontSizeSlider, "BOTTOMLEFT", 0, -36)
    controlRefs.columnCountSlider = columnCountSlider
    local rowsPerColumnSlider = CreateSlider(ADDON_NAME .. "RowsPerColumnSlider", content, self:S("Max Rows per Column"), 0, #statKeys, 1, function(_, value) SetValue("rowsPerColumn", math.max(0, math.floor(value + 0.5))) Addon:RefreshStats() end)
    rowsPerColumnSlider:SetPoint("TOPLEFT", columnCountSlider, "BOTTOMLEFT", 0, -36)
    _G[rowsPerColumnSlider:GetName() .. "Low"]:SetText(self:S("Auto"))
    controlRefs.rowsPerColumnSlider = rowsPerColumnSlider

    local fontLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    fontLabel:SetPoint("TOPLEFT", rowsPerColumnSlider, "BOTTOMLEFT", -6, -26)
    fontLabel:SetText(self:S("Font"))
    controlRefs.fontLabel = fontLabel
    local fontDropDown = CreateFrame("Frame", ADDON_NAME .. "FontDropDown", content, "UIDropDownMenuTemplate")
    fontDropDown:SetPoint("TOPLEFT", fontLabel, "BOTTOMLEFT", -16, -2)
    UIDropDownMenu_SetWidth(fontDropDown, 220)
    UIDropDownMenu_Initialize(fontDropDown, function(_, level)
        for _, font in ipairs(Addon:GetAvailableFonts()) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = font.label
            info.func = function()
                SetValue("fontKey", font.key)
                UIDropDownMenu_SetSelectedName(fontDropDown, font.label)
                if controlRefs.fontPreview then
                    local path, flags = Addon:GetFontInfo(font.key)
                    controlRefs.fontPreview:SetFont(path or STANDARD_TEXT_FONT, 18, flags or "OUTLINE")
                    controlRefs.fontPreview:SetText(font.label .. " - " .. Addon:S("The quick brown fox 123"))
                end
                RefreshStatsDeferred()
            end
            info.checked = GetValue("fontKey") == font.key
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    controlRefs.fontDropDown = fontDropDown

    local fontPreview = content:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    fontPreview:SetPoint("TOPLEFT", fontDropDown, "BOTTOMLEFT", 20, -6)
    fontPreview:SetText(self:S("The quick brown fox 123"))
    controlRefs.fontPreview = fontPreview

    local resetButton = CreateFrame("Button", nil, content, "UIPanelButtonTemplate")
    resetButton:SetSize(140, 24)
    resetButton:SetPoint("TOPLEFT", fontPreview, "BOTTOMLEFT", -4, -18)
    resetButton:SetText(self:S("Reset Position"))
    resetButton:SetScript("OnClick", function()
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
    controlRefs.resetButton = resetButton

    local statHeader = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    statHeader:SetPoint("TOPLEFT", 360, -150)
    statHeader:SetText(self:S("Stats"))
    controlRefs.statHeader = statHeader
    local statHint = content:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    statHint:SetPoint("TOPLEFT", statHeader, "BOTTOMLEFT", 0, -4)
    statHint:SetText(self:S("Check to show, set color, move with arrows"))
    controlRefs.statHint = statHint

    for index = 1, #statKeys do
        local row = CreateFrame("Frame", nil, content)
        row:SetSize(320, 26)
        row:SetPoint("TOPLEFT", 360, -180 - (index - 1) * 30)
        local checkbox = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
        checkbox:SetPoint("LEFT", 0, 0)
        row.checkbox = checkbox
        local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
        label:SetPoint("LEFT", checkbox, "RIGHT", 4, 0)
        label:SetWidth(112)
        label:SetJustifyH("LEFT")
        row.label = label
        local swatch = CreateFrame("Button", nil, row, "BackdropTemplate")
        swatch:SetSize(16, 16)
        swatch:SetPoint("LEFT", label, "RIGHT", 8, 0)
        swatch:SetBackdrop({ bgFile = "Interface/Buttons/WHITE8x8", edgeFile = "Interface/Tooltips/UI-Tooltip-Border", tile = true, tileSize = 8, edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
        swatch:SetBackdropColor(0, 0, 0, 0.9)
        swatch.texture = swatch:CreateTexture(nil, "ARTWORK")
        swatch.texture:SetPoint("TOPLEFT", 2, -2)
        swatch.texture:SetPoint("BOTTOMRIGHT", -2, 2)
        row.swatch = swatch
        local color = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
        color:SetSize(48, 20)
        color:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
        color:SetText(self:S("Color"))
        row.color = color
        local up = CreateFrame("Button", nil, row)
        up:SetSize(24, 20)
        up:SetPoint("LEFT", color, "RIGHT", 10, 0)
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
        checkbox:SetScript("OnClick", function(self) row.entry.enabled = self:GetChecked() Addon:RefreshStats() end)
        swatch:SetScript("OnClick", function() OpenColorPicker(row.entry) end)
        color:SetScript("OnClick", function() OpenColorPicker(row.entry) end)
        up:SetScript("OnClick", function() MoveStat(row.index, -1) Addon:RefreshOptionRows() end)
        down:SetScript("OnClick", function() MoveStat(row.index, 1) Addon:RefreshOptionRows() end)
        rowControls[index] = row
    end

    optionsPanel:SetScript("OnShow", function()
        Addon:RefreshLocalizedUI()
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
    rowControls = {}
    controlRefs = {}
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
