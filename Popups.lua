local _, ns = ...

ns = ns or {}
ns.ZhuraStats = ns.ZhuraStats or {}
local Addon = ns.ZhuraStats

local pendingRenameProfileName

function Addon:RefreshStaticPopupTexts()
    if StaticPopupDialogs["NE_STATS_CREATE_PROFILE"] then
        StaticPopupDialogs["NE_STATS_CREATE_PROFILE"].text = self:S("NE_STATS_CREATE_A_NEW_PROFILE_FOR_THIS_ACCOUNT")
        StaticPopupDialogs["NE_STATS_CREATE_PROFILE"].button1 = self:S("NE_STATS_CREATE")
        StaticPopupDialogs["NE_STATS_CREATE_PROFILE"].button2 = self:S("NE_STATS_CANCEL")
    end
    if StaticPopupDialogs["NE_STATS_RENAME_PROFILE"] then
        StaticPopupDialogs["NE_STATS_RENAME_PROFILE"].text = self:S("NE_STATS_RENAME_PROFILE_FMT")
        StaticPopupDialogs["NE_STATS_RENAME_PROFILE"].button1 = self:S("NE_STATS_RENAME")
        StaticPopupDialogs["NE_STATS_RENAME_PROFILE"].button2 = self:S("NE_STATS_CANCEL")
    end
    if StaticPopupDialogs["NE_STATS_DELETE_PROFILE"] then
        StaticPopupDialogs["NE_STATS_DELETE_PROFILE"].text = self:S("NE_STATS_DELETE_PROFILE_FMT")
        StaticPopupDialogs["NE_STATS_DELETE_PROFILE"].button1 = self:S("NE_STATS_DELETE")
        StaticPopupDialogs["NE_STATS_DELETE_PROFILE"].button2 = self:S("NE_STATS_CANCEL")
    end
end

function Addon:InitializePopups()
    StaticPopupDialogs["NE_STATS_CREATE_PROFILE"] = {
        text = self:S("NE_STATS_CREATE_A_NEW_PROFILE_FOR_THIS_ACCOUNT"),
        button1 = self:S("NE_STATS_CREATE"),
        button2 = self:S("NE_STATS_CANCEL"),
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
                print(Addon:S("NE_STATS_PROFILE_CREATED", profileName))
            elseif status == "exists" then
                print(Addon:S("NE_STATS_PROFILE_ALREADY_EXISTS"))
            end
            Addon:RefreshStats()
            Addon:RefreshOptionRows()
        end,
    }

    StaticPopupDialogs["NE_STATS_RENAME_PROFILE"] = {
        text = self:S("NE_STATS_RENAME_PROFILE_FMT"),
        button1 = self:S("NE_STATS_RENAME"),
        button2 = self:S("NE_STATS_CANCEL"),
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
                print(Addon:S("NE_STATS_PROFILE_ALREADY_EXISTS"))
            elseif status == "invalid" then
                print(Addon:S("NE_STATS_PROFILE_RENAME_FAILED_DETAIL", tostring(profileName)))
            elseif status == "renamed" and profileName then
                print(Addon:S("NE_STATS_PROFILE_RENAMED", profileName))
            end
        end,
        OnCancel = function()
            pendingRenameProfileName = nil
        end,
    }

    StaticPopupDialogs["NE_STATS_DELETE_PROFILE"] = {
        text = self:S("NE_STATS_DELETE_PROFILE_FMT"),
        button1 = self:S("NE_STATS_DELETE"),
        button2 = self:S("NE_STATS_CANCEL"),
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = STATICPOPUP_NUMDIALOGS,
        OnAccept = function(dialog)
            local data = dialog.data
            if Addon:DeleteProfile(data) then
                print(Addon:S("NE_STATS_PROFILE_DELETED", data))
            else
                print(Addon:S("NE_STATS_PROFILE_DELETE_FAILED"))
            end
        end,
    }
end
