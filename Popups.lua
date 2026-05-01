local _, ns = ...

ns = ns or {}
ns.ZhuraStats = ns.ZhuraStats or {}
local Addon = ns.ZhuraStats

local pendingRenameProfileName

function Addon:RefreshStaticPopupTexts()
    if StaticPopupDialogs["NE_STATS_CREATE_PROFILE"] then
        StaticPopupDialogs["NE_STATS_CREATE_PROFILE"].text = self:S("Create a new profile for this account")
        StaticPopupDialogs["NE_STATS_CREATE_PROFILE"].button1 = self:S("Create")
        StaticPopupDialogs["NE_STATS_CREATE_PROFILE"].button2 = self:S("Cancel")
    end
    if StaticPopupDialogs["NE_STATS_RENAME_PROFILE"] then
        StaticPopupDialogs["NE_STATS_RENAME_PROFILE"].text = self:S("Rename profile %s")
        StaticPopupDialogs["NE_STATS_RENAME_PROFILE"].button1 = self:S("Rename")
        StaticPopupDialogs["NE_STATS_RENAME_PROFILE"].button2 = self:S("Cancel")
    end
    if StaticPopupDialogs["NE_STATS_DELETE_PROFILE"] then
        StaticPopupDialogs["NE_STATS_DELETE_PROFILE"].text = self:S("Delete profile %s?")
        StaticPopupDialogs["NE_STATS_DELETE_PROFILE"].button1 = self:S("Delete")
        StaticPopupDialogs["NE_STATS_DELETE_PROFILE"].button2 = self:S("Cancel")
    end
end

function Addon:InitializePopups()
    StaticPopupDialogs["NE_STATS_CREATE_PROFILE"] = {
        text = self:S("Create a new profile for this account"),
        button1 = self:S("Create"),
        button2 = self:S("Cancel"),
        hasEditBox = true,
        maxLetters = 24,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = STATICPOPUP_NUMDIALOGS,
        OnAccept = function(dialog)
            local text = dialog.editBox and dialog.editBox:GetText() or ""
            local status, profileName = Addon:CreateProfile(text)
            if status == "created" and profileName then
                print(Addon:S("NE Stats: created profile %s.", profileName))
            elseif status == "exists" then
                print(Addon:S("NE Stats: profile already exists."))
            end
            Addon:RefreshStats()
            Addon:RefreshOptionRows()
        end,
    }

    StaticPopupDialogs["NE_STATS_RENAME_PROFILE"] = {
        text = self:S("Rename profile %s"),
        button1 = self:S("Rename"),
        button2 = self:S("Cancel"),
        hasEditBox = true,
        maxLetters = 24,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = STATICPOPUP_NUMDIALOGS,
        OnAccept = function(dialog)
            local _, activeProfileName = Addon:GetActiveRootProfile()
            local data = dialog.data or pendingRenameProfileName or activeProfileName
            local newName = Addon:NormalizeProfileName(dialog.editBox and dialog.editBox:GetText() or "")
            local status, profileName = Addon:RenameProfile(data, newName)
            pendingRenameProfileName = nil
            if status == "exists" then
                print(Addon:S("NE Stats: profile already exists."))
            elseif status == "invalid" then
                print(Addon:S("NE Stats: profile could not be renamed: %s", tostring(profileName)))
            elseif status == "renamed" and profileName then
                print(Addon:S("NE Stats: renamed profile to %s.", profileName))
            end
        end,
        OnCancel = function()
            pendingRenameProfileName = nil
        end,
    }

    StaticPopupDialogs["NE_STATS_DELETE_PROFILE"] = {
        text = self:S("Delete profile %s?"),
        button1 = self:S("Delete"),
        button2 = self:S("Cancel"),
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = STATICPOPUP_NUMDIALOGS,
        OnAccept = function(dialog)
            local data = dialog.data
            if Addon:DeleteProfile(data) then
                print(Addon:S("NE Stats: deleted profile %s.", data))
            else
                print(Addon:S("NE Stats: profile could not be deleted."))
            end
        end,
    }
end
