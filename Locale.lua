local _, ns = ...

ns = ns or {}
ns.ZhuraStats = ns.ZhuraStats or {}
local Addon = ns.ZhuraStats

NE_STATS_LOCALES = NE_STATS_LOCALES or {}

local FALLBACK_LOCALE = "enUS"
local CLIENT_LOCALE = GetLocale() or FALLBACK_LOCALE
local CLIENT_LANGUAGE_VALUE = "client"
local LOCALE_DISPLAY_NAMES = {
    deDE = "Deutsch",
    enUS = "English (US)",
    esES = "Espanol (EU)",
    esMX = "Espanol (LATAM)",
    frFR = "Francais",
    itIT = "Italiano",
    koKR = "한국어",
    ptBR = "Portugues (BR)",
    ruRU = "Русский",
    ukUA = "Українська",
    zhCN = "简体中文",
    zhTW = "繁體中文",
}

local L = {}

local function CopyLocaleEntries(source, target)
    if type(source) ~= "table" then
        return
    end
    for key, value in pairs(source) do
        target[key] = value
    end
end

function Addon:GetConfiguredLocale()
    local db = self.db
    if db and db.global and type(db.global.addonLocale) == "string" and db.global.addonLocale ~= "" then
        return db.global.addonLocale
    end
    return CLIENT_LANGUAGE_VALUE
end

function Addon:SetConfiguredLocale(localeCode)
    local db = self.db
    if not db or not db.global then
        return
    end
    if type(localeCode) ~= "string" or localeCode == "" then
        return
    end
    db.global.addonLocale = localeCode
end

local function GetEffectiveLocale()
    local configuredLocale = Addon:GetConfiguredLocale()
    local localeCode = configuredLocale == CLIENT_LANGUAGE_VALUE and CLIENT_LOCALE or configuredLocale
    if not NE_STATS_LOCALES[localeCode] then
        localeCode = FALLBACK_LOCALE
    end
    return localeCode
end

function Addon:ApplyLocale()
    wipe(L)
    CopyLocaleEntries(NE_STATS_LOCALES[FALLBACK_LOCALE], L)
    local effectiveLocale = GetEffectiveLocale()
    if effectiveLocale ~= FALLBACK_LOCALE then
        CopyLocaleEntries(NE_STATS_LOCALES[effectiveLocale], L)
    end
end

function Addon:S(key, ...)
    local text = L[key] or key
    if select("#", ...) > 0 then
        return string.format(text, ...)
    end
    return text
end

function Addon:GetLocaleDisplayName(localeCode)
    if localeCode == CLIENT_LANGUAGE_VALUE then
        return string.format("%s (%s)", self:S("Client language"), LOCALE_DISPLAY_NAMES[CLIENT_LOCALE] or CLIENT_LOCALE)
    end
    return LOCALE_DISPLAY_NAMES[localeCode] or localeCode
end

function Addon:GetTextAlignDisplayName(value)
    if value == "CENTER" then return self:S("Center") end
    if value == "RIGHT" then return self:S("Right") end
    return self:S("Left")
end

function Addon:GetGoldSeparatorDisplayName(value)
    if value == " " then return self:S("Space") end
    if value == "," then return self:S("Comma") end
    if value == "." then return self:S("Dot") end
    if value == "'" then return self:S("Apostrophe") end
    if value == "_" then return self:S("Underscore") end
    return tostring(value or " ")
end

function Addon:GetDisplayProfileName(profileName)
    if profileName == "Default" then
        return self:S("Default")
    end
    return profileName
end

Addon.Constants = Addon.Constants or {}
Addon.Constants.FALLBACK_LOCALE = FALLBACK_LOCALE
Addon.Constants.CLIENT_LOCALE = CLIENT_LOCALE
Addon.Constants.CLIENT_LANGUAGE_VALUE = CLIENT_LANGUAGE_VALUE
Addon.Constants.LOCALE_DISPLAY_NAMES = LOCALE_DISPLAY_NAMES
