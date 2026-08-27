local stub = require("tests/wow_stub")
require("Database")

local Addon = stub.Addon

local function copy_profile(overrides)
  local profile = Addon.DeepCopy(Addon.Defaults.profile)
  if overrides then
    for k, v in pairs(overrides) do
      profile[k] = v
    end
  end
  return profile
end

describe("Database", function()
  describe("NormalizeProfileName", function()
    it("trims and collapses spaces", function()
      assert.are.equal("a b", Addon:NormalizeProfileName("  a   b  "))
    end)

    it("returns empty for nil", function()
      assert.are.equal("", Addon:NormalizeProfileName(nil))
    end)
  end)

  describe("CanModifyProfile", function()
    it("disallows Default, empty, and nil", function()
      assert.is_false(Addon:CanModifyProfile("Default"))
      assert.is_false(Addon:CanModifyProfile(""))
      assert.is_false(Addon:CanModifyProfile(nil))
    end)

    it("allows other names", function()
      assert.is_true(Addon:CanModifyProfile("Raids"))
    end)
  end)

  describe("GetCurrentPrimaryStatKey", function()
    it("keeps the last valid primary stat when specialization info is temporarily unavailable", function()
      local oldGetSpecialization = _G.GetSpecialization
      local oldGetSpecializationInfo = _G.GetSpecializationInfo

      _G.GetSpecialization = function()
        return 1
      end
      _G.GetSpecializationInfo = function(index)
        return 63, "Fire", "", "", "DAMAGER", 2
      end
      assert.are.equal("AGI", Addon:GetCurrentPrimaryStatKey())

      _G.GetSpecializationInfo = function(index)
        return 63, "Fire", "", "", "DAMAGER", nil
      end
      assert.are.equal("AGI", Addon:GetCurrentPrimaryStatKey())

      _G.GetSpecializationInfo = function(index)
        error("specialization info unavailable")
      end
      assert.are.equal("AGI", Addon:GetCurrentPrimaryStatKey())

      _G.GetSpecialization = oldGetSpecialization
      _G.GetSpecializationInfo = oldGetSpecializationInfo
    end)
  end)

  describe("MigrateProfile", function()
    it("sets statsMigrationVersion and preserves stat keys order", function()
      local profile = copy_profile({ statsMigrationVersion = 0 })
      Addon:MigrateProfile(profile)
      assert.are.equal(6, profile.statsMigrationVersion)
      local keys = Addon.Constants.STAT_KEYS
      assert.are.equal(#keys, #profile.stats)
      for i = 1, #keys do
        assert.are.equal(keys[i], profile.stats[i].key)
      end
    end)

    it("preserves custom stat order during migration", function()
      local profile = copy_profile({ statsMigrationVersion = 0 })
      profile.stats = {
        { key = "GOLD", enabled = true, color = { 1, 0.82, 0 } },
        { key = "ILVL", enabled = true, color = { 1, 1, 1 } },
        { key = "CRIT", enabled = true, color = { 1, 0, 0 } },
        { key = "HASTE", enabled = true, color = { 0, 1, 0 } },
      }

      Addon:MigrateProfile(profile)

      assert.are.equal(6, profile.statsMigrationVersion)
      assert.are.equal("GOLD", profile.stats[1].key)
      assert.are.equal("ILVL", profile.stats[2].key)
      assert.are.equal("CRIT", profile.stats[3].key)
      assert.are.equal("HASTE", profile.stats[4].key)
      assert.are.equal(#Addon.Constants.STAT_KEYS, #profile.stats)
    end)

    it("keeps a complete saved custom stat order valid", function()
      local profile = copy_profile({ statsMigrationVersion = 6 })
      local original = Addon.DeepCopy(profile.stats)
      profile.stats[1], profile.stats[13] = profile.stats[13], profile.stats[1]
      profile.stats[2], profile.stats[12] = profile.stats[12], profile.stats[2]

      Addon:MigrateProfile(profile)

      assert.are.equal(6, profile.statsMigrationVersion)
      assert.are.equal(original[13].key, profile.stats[1].key)
      assert.are.equal(original[12].key, profile.stats[2].key)
      assert.are.equal(original[1].key, profile.stats[13].key)
      assert.are.equal(original[2].key, profile.stats[12].key)
    end)

    it("maps legacy showDiminishingReturns true to drDisplayMode penalty", function()
      local profile = copy_profile({
        statsMigrationVersion = 0,
        showDiminishingReturns = true,
      })
      -- DeepCopy keeps defaults.drDisplayMode ("off"); migration only maps legacy DR when drDisplayMode is nil.
      profile.drDisplayMode = nil
      Addon:MigrateProfile(profile)
      assert.is_nil(profile.showDiminishingReturns)
      assert.are.equal("penalty", profile.drDisplayMode)
    end)

    it("maps legacy drDisplayMode suffix to penalty", function()
      local profile = copy_profile({
        statsMigrationVersion = 0,
        drDisplayMode = "suffix",
      })
      Addon:MigrateProfile(profile)
      assert.are.equal("penalty", profile.drDisplayMode)
    end)

    it("resets invalid drDisplayMode to default", function()
      local profile = copy_profile({
        statsMigrationVersion = 0,
        drDisplayMode = "invalid_mode",
      })
      Addon:MigrateProfile(profile)
      assert.are.equal(Addon.Defaults.profile.drDisplayMode, profile.drDisplayMode)
    end)

    it("copies decimalPrecision into percentPrecision when missing", function()
      local profile = copy_profile({
        statsMigrationVersion = 0,
        decimalPrecision = 3,
      })
      -- Defaults copy still has percentPrecision = 2; clear so MigrateProfile uses decimalPrecision.
      profile.percentPrecision = nil
      Addon:MigrateProfile(profile)
      assert.are.equal(3, profile.percentPrecision)
    end)

    it("normalizes invalid goldSeparator to default", function()
      local profile = copy_profile({
        statsMigrationVersion = 0,
        goldSeparator = "|",
      })
      Addon:MigrateProfile(profile)
      assert.are.equal(Addon.Defaults.profile.goldSeparator, profile.goldSeparator)
    end)

    it("normalizes invalid textAlign to default", function()
      local profile = copy_profile({
        statsMigrationVersion = 0,
        textAlign = "DIAGONAL",
      })
      Addon:MigrateProfile(profile)
      assert.are.equal(Addon.Defaults.profile.textAlign, profile.textAlign)
    end)

    it("normalizes useClassColor to a strict boolean", function()
      local enabled = copy_profile({ useClassColor = true })
      Addon:MigrateProfile(enabled)
      assert.is_true(enabled.useClassColor)

      local invalid = copy_profile({ useClassColor = "true" })
      Addon:MigrateProfile(invalid)
      assert.is_false(invalid.useClassColor)
    end)

    it("normalizes invalid frameControlsPosition to default", function()
      local profile = copy_profile({
        statsMigrationVersion = 0,
        frameControlsPosition = "CENTER",
      })
      Addon:MigrateProfile(profile)
      assert.are.equal(Addon.Defaults.profile.frameControlsPosition, profile.frameControlsPosition)
    end)

    it("preserves valid frameControlsPosition", function()
      local profile = copy_profile({
        statsMigrationVersion = 0,
        frameControlsPosition = "LEFT",
      })
      Addon:MigrateProfile(profile)
      assert.are.equal("LEFT", profile.frameControlsPosition)
    end)

    it("normalizes invalid frameControlsDirection to default", function()
      local profile = copy_profile({
        statsMigrationVersion = 0,
        frameControlsDirection = "DIAGONAL",
      })
      Addon:MigrateProfile(profile)
      assert.are.equal(Addon.Defaults.profile.frameControlsDirection, profile.frameControlsDirection)
    end)

    it("preserves valid frameControlsDirection", function()
      local profile = copy_profile({
        statsMigrationVersion = 0,
        frameControlsDirection = "VERTICAL",
      })
      Addon:MigrateProfile(profile)
      assert.are.equal("VERTICAL", profile.frameControlsDirection)
    end)

    it("clears legacy nil fields", function()
      local profile = copy_profile({
        statsMigrationVersion = 0,
        useLoadoutProfiles = true,
        showPotionState = true,
      })
      Addon:MigrateProfile(profile)
      assert.is_nil(profile.useLoadoutProfiles)
      assert.is_nil(profile.showPotionState)
    end)

    it("is idempotent when stats already at current migration version", function()
      local profile = copy_profile({ statsMigrationVersion = 0 })
      Addon:MigrateProfile(profile)
      assert.are.equal(6, profile.statsMigrationVersion)
      local keys = Addon.Constants.STAT_KEYS
      local snap = {}
      for i = 1, #profile.stats do
        snap[i] = {
          key = profile.stats[i].key,
          enabled = profile.stats[i].enabled,
        }
      end
      Addon:MigrateProfile(profile)
      assert.are.equal(6, profile.statsMigrationVersion)
      assert.are.equal(#keys, #profile.stats)
      for i = 1, #keys do
        assert.are.equal(snap[i].key, profile.stats[i].key)
        assert.are.equal(snap[i].enabled, profile.stats[i].enabled)
      end
    end)

    it("preserves stat name overrides during migration", function()
      local profile = copy_profile({
        statsMigrationVersion = 5,
        stats = {
          { key = "STR", enabled = true, color = { 1, 0, 0 }, nameOverride = "Power" },
        },
      })
      Addon:MigrateProfile(profile)
      assert.are.equal(6, profile.statsMigrationVersion)
      assert.are.equal("Power", profile.stats[1].nameOverride)
    end)

    it("clears blank stat name overrides", function()
      local profile = copy_profile({ statsMigrationVersion = 0 })
      Addon:MigrateProfile(profile)
      profile.stats[1].nameOverride = "   "
      Addon:MigrateProfile(profile)
      assert.is_nil(profile.stats[1].nameOverride)
    end)

    it("coerces string numeric profile fields during migration", function()
      local profile = copy_profile({
        statsMigrationVersion = 6,
        alpha = "0.75",
        scale = "1.5",
        fontSize = "14",
        columnCount = "2",
        rowGap = "4",
        valueColumnWidth = "96",
        compactValueColumns = 1,
        percentPrecision = "3",
      })
      Addon:MigrateProfile(profile)
      assert.are.equal(0.75, profile.alpha)
      assert.are.equal(1.5, profile.scale)
      assert.are.equal(14, profile.fontSize)
      assert.are.equal(2, profile.columnCount)
      assert.are.equal(4, profile.rowGap)
      assert.are.equal(96, profile.valueColumnWidth)
      assert.is_false(profile.compactValueColumns)
      assert.are.equal(3, profile.percentPrecision)
    end)
  end)
end)
