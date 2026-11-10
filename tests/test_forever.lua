local stub = require("tests/wow_stub")

local function loadForever()
  local env = setmetatable({
    GetBuildInfo = function() return "1.60.1", "70862", "", 16001 end,
    GetLocale = function() return "ruRU" end,
    NE_STATS_LOCALES = {},
    CR_HIT_MELEE = 6,
    CR_HIT_RANGED = 7,
    CR_HIT_SPELL = 8,
    CR_HASTE_MELEE = 18,
    GetCombatRating = function() return 20 end,
    GetCombatRatingBonus = function() return 2 end,
  }, { __index = _G })
  local ns = {}
  for _, module in ipairs({
    "Locales/enUS", "Locales/ruRU", "Defaults", "Stats", "Locale", "StatDefinitions",
    "Database", "ArchonPriority", "Reference", "Format",
  }) do
    local chunk = assert(loadfile(stub.resolve(module .. ".lua")))
    setfenv(chunk, env)("ZhuraStats", ns)
  end
  return ns, env
end

describe("WoW Forever", function()
  it("displays all three coin denominations, including zeros", function()
    local ns, env = loadForever()
    local addon = ns.ZhuraStats
    addon:ApplyLocale()
    local profile = addon.DeepCopy(addon.Defaults.profile)
    local balance = 12345678
    env.GetMoney = function() return balance end

    local result = ns.Stats.ReadStat("GOLD")
    local segments = addon:BuildStatSegments("GOLD", result, profile)
    assert.are.equal("Деньги", segments[1].text)
    assert.are.equal("1 234 з. 56 с. 78 м.", segments[2].text)
    assert.are.equal("Деньги 1 234 з. 56 с. 78 м.", addon:FormatStatValue("GOLD", result, profile))

    balance = 9
    assert.are.equal("Деньги 0 з. 0 с. 9 м.", addon:FormatStatValue("GOLD", ns.Stats.ReadStat("GOLD"), profile))
  end)

  it("migrates a profile to the Forever stat list and keeps manual settings", function()
    local ns = loadForever()
    local addon = ns.ZhuraStats
    local profile = { stats = {
      { key = "MASTERY", enabled = true },
      { key = "CRIT", enabled = false, color = { 0, 1, 0 } },
      { key = "VERS", enabled = true },
    } }

    addon:MigrateProfile(profile)
    assert.are.equal(#addon.Constants.STAT_KEYS, #profile.stats)
    assert.are.same({ key = "CRIT", enabled = false, color = { 0, 1, 0 } }, profile.stats[1])
    assert.is_true(addon.DefaultStatsByKey.HIT.enabled)
    assert.is_not_nil(addon.DefaultStatsByKey.STA)
    assert.is_not_nil(addon.DefaultStatsByKey.SPI)
    assert.is_nil(addon.StatDefinitions.MASTERY)
    assert.is_nil(addon.StatDefinitions.VERS)
    assert.are.equal("manual", addon:NormalizeStatPriorityMode("archon_raid"))
  end)

  it("uses the highest hit chance and keeps the last result when a component is secret", function()
    local ns, env = loadForever()
    env.GetHitModifier = function() return 1 end
    env.GetOffhandHitModifier = function() return 0 end
    env.GetRangedHitModifier = function() return 0 end
    env.GetSpellHitModifier = function() return 3 end

    local hit = ns.Stats.ReadStat("HIT")
    assert.are.equal(5, hit.value)
    assert.are.equal(20, hit.rating)

    env.GetSpellHitModifier = function() return { __secret = true } end
    local cached = ns.Stats.ReadStat("HIT")
    assert.are.equal(5, cached.value)
    assert.are.equal("cache", cached.source)
  end)

  it("uses the highest crit and haste values without applying Midnight DR", function()
    local ns, env = loadForever()
    env.GetCritChance = function() return 4 end
    env.GetRangedCritChance = function() return 5 end
    env.GetSpellCritChance = function() return 7 end
    env.GetMeleeHaste = function() return 8 end
    env.GetRangedHaste = function() return 6, 7 end
    env.UnitSpellHaste = function() return 9 end
    env.GetCombatRatingBonus = function() return 40 end

    local crit = ns.Stats.ReadStat("CRIT")
    local haste = ns.Stats.ReadStat("HASTE")
    assert.are.equal(7, crit.value)
    assert.are.equal(13, haste.value)
    assert.is_nil(crit.dr)
    assert.is_nil(haste.dr)

    env.GetRangedHaste = function() return 6, { __secret = true } end
    assert.are.equal("cache", ns.Stats.ReadStat("HASTE").source)
  end)
end)
