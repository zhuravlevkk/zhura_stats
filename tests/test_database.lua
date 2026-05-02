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
    it("disallows Default and empty", function()
      assert.is_false(Addon:CanModifyProfile("Default"))
      assert.is_false(Addon:CanModifyProfile(""))
      assert.is_false(Addon:CanModifyProfile(nil))
    end)

    it("allows other names", function()
      assert.is_true(Addon:CanModifyProfile("Raids"))
    end)
  end)

  describe("MigrateProfile", function()
    it("sets statsMigrationVersion and preserves stat keys order", function()
      local profile = copy_profile({ statsMigrationVersion = 0 })
      Addon:MigrateProfile(profile)
      assert.are.equal(5, profile.statsMigrationVersion)
      local keys = Addon.Constants.STAT_KEYS
      assert.are.equal(#keys, #profile.stats)
      for i = 1, #keys do
        assert.are.equal(keys[i], profile.stats[i].key)
      end
    end)

    it("maps legacy showDiminishingReturns true to drDisplayMode penalty", function()
      local profile = copy_profile({
        statsMigrationVersion = 0,
        showDiminishingReturns = true,
        drDisplayMode = nil,
      })
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
        percentPrecision = nil,
        decimalPrecision = 3,
      })
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
  end)
end)
