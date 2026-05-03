-- WoW / client API stubs for running addon modules under Lua 5.1 (busted).
-- Comments in English per project rules.

local ns = { ZhuraStats = {} }

function GetLocale()
  return "enUS"
end

function UnitStat(unit, index)
  return 0, 0
end

function GetCombatRating(ratingIndex)
  return 0
end

function GetCombatRatingBonus(ratingIndex)
  return 0
end

function UnitLevel(unit)
  return 0
end

function strtrim(s)
  if s == nil then
    return ""
  end
  s = tostring(s)
  return (s:gsub("^%s*(.-)%s*$", "%1"))
end

function wipe(t)
  if type(t) == "table" then
    for k in pairs(t) do
      t[k] = nil
    end
  end
  return t
end

-- Defaults for ArchonPriority:GetPlayerClassSpec (fire mage).
function UnitClass(unit)
  return "Mage", "MAGE"
end

function GetSpecialization()
  return 1
end

function GetSpecializationInfo(index)
  return 63, "Fire", "", "", "DAMAGER", 5, 2
end

local testRoot = "."

local function resolve(relPath)
  relPath = relPath:gsub("\\", "/")
  if testRoot == "." then
    return relPath
  end
  return testRoot .. "/" .. relPath
end

local function run_addon_chunk(relPath)
  local path = resolve(relPath)
  local chunk, err = loadfile(path)
  assert(chunk, err or path)
  chunk("ZhuraStats", ns)
end

local loaded = {}
local function ensure_loaded(relPath)
  if loaded[relPath] then
    return
  end
  loaded[relPath] = true
  run_addon_chunk(relPath)
end

local function install_profile_stubs()
  local A = ns.ZhuraStats
  A._test_profile = A._test_profile or {}
  function A:GetProfile()
    return A._test_profile
  end
  function A:GetProfileValue(key)
    local p = A._test_profile
    if p and p[key] ~= nil then
      return p[key]
    end
    local defaults = self.Defaults and self.Defaults.profile
    if defaults and defaults[key] ~= nil then
      return defaults[key]
    end
    return nil
  end
  function A:SetProfileValue(key, value)
    A._test_profile[key] = value
  end
  function A:RefreshStats() end
  function A:RefreshOptions() end
  function A:RefreshOptionRows() end
  function A:RefreshPriorityModeButtons() end
end

local function register_preload(name, relPath, deps)
  package.preload[name] = function()
    if deps then
      for _, dep in ipairs(deps) do
        require(dep)
      end
    end
    ensure_loaded(relPath)
    return true
  end
end

register_preload("Defaults", "Defaults.lua", nil)
register_preload("StatDefinitions", "StatDefinitions.lua", { "Defaults" })

package.preload["LocaleData_enUS"] = function()
  ensure_loaded("Locales/enUS.lua")
  return true
end

register_preload("Locale", "Locale.lua", { "Defaults", "LocaleData_enUS" })

package.preload["Format"] = function()
  require("Defaults")
  require("StatDefinitions")
  require("LocaleData_enUS")
  require("Locale")
  require("WoWLogsStatsPrioData")
  require("ArchonPriority")
  ensure_loaded("Reference.lua")
  install_profile_stubs()
  ensure_loaded("Format.lua")
  return true
end

package.preload["WoWLogsStatsPrioData"] = function()
  ensure_loaded("WoWLogsStatsPrio.lua")
  return true
end

package.preload["ArchonPriority"] = function()
  require("WoWLogsStatsPrioData")
  install_profile_stubs()
  ensure_loaded("ArchonPriority.lua")
  return true
end

register_preload("Database", "Database.lua", { "Defaults", "StatDefinitions" })

local Addon = ns.ZhuraStats

local M = {
  ns = ns,
  Addon = Addon,
  resolve = resolve,
  ensure_loaded = ensure_loaded,
  reset_test_profile = function()
    wipe(Addon._test_profile or {})
    Addon._test_profile = {}
  end,
}

return M
