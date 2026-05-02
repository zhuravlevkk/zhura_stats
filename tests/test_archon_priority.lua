local stub = require("tests/wow_stub")
require("ArchonPriority")

local Addon = stub.Addon

describe("ArchonPriority", function()
  before_each(function()
    stub.reset_test_profile()
  end)

  describe("NormalizeStatPriorityMode", function()
    it("accepts manual and archon modes", function()
      assert.are.equal("manual", Addon:NormalizeStatPriorityMode("manual"))
      assert.are.equal("archon_raid", Addon:NormalizeStatPriorityMode("archon_raid"))
      assert.are.equal("archon_mplus", Addon:NormalizeStatPriorityMode("archon_mplus"))
    end)

    it("maps invalid modes to manual", function()
      assert.are.equal("manual", Addon:NormalizeStatPriorityMode(nil))
      assert.are.equal("manual", Addon:NormalizeStatPriorityMode(""))
      assert.are.equal("manual", Addon:NormalizeStatPriorityMode("unknown"))
    end)
  end)

  describe("class and spec slugs", function()
    it("builds Archon key from mocked mage fire character", function()
      local key = Addon:GetArchonKey("m+")
      assert.are.equal("mage/fire/m+", key)
    end)

    it("returns priority list for m+ fire mage from data", function()
      local list = Addon:GetArchonPriorityForMode("archon_mplus")
      assert.is_true(type(list) == "table")
      assert.are.equal(4, #list)
      assert.are.equal("HASTE", list[1])
    end)

    it("returns raid priority list for same character", function()
      local raid = Addon:GetArchonPriorityForMode("archon_raid")
      assert.is_true(type(raid) == "table")
      assert.are.equal(4, #raid)
      assert.are.equal("HASTE", raid[1])
    end)
  end)

  describe("GetArchonDataForMode", function()
    it("returns nil for manual mode", function()
      local data, key, activity = Addon:GetArchonDataForMode("manual")
      assert.is_nil(data)
    end)

    it("returns data table for archon_mplus", function()
      local data, key, activity = Addon:GetArchonDataForMode("archon_mplus")
      assert.is_true(type(data) == "table")
      assert.are.equal("mage/fire/m+", key)
      assert.are.equal("m+", activity)
    end)
  end)

  describe("GetArchonTopHeroForMode", function()
    it("returns top hero entry when heroes exist", function()
      local top = Addon:GetArchonTopHeroForMode("archon_mplus")
      assert.is_true(type(top) == "table")
      assert.are.equal("sunfury", top.hero)
    end)
  end)

  describe("SetStatPriorityMode", function()
    it("persists normalized mode on profile", function()
      Addon:SetStatPriorityMode("archon_mplus")
      assert.are.equal("archon_mplus", Addon._test_profile.statPriorityMode)
      Addon:SetStatPriorityMode("bogus")
      assert.are.equal("manual", Addon._test_profile.statPriorityMode)
    end)
  end)

  describe("GetDisplayStats", function()
    it("returns profile stats in manual mode", function()
      local stats = {
        { key = "CRIT", enabled = true },
        { key = "HASTE", enabled = true },
      }
      Addon._test_profile.statPriorityMode = "manual"
      Addon._test_profile.stats = stats
      local out = Addon:GetDisplayStats()
      assert.are.same(stats, out)
    end)

    it("reorders by Archon priority when mode is archon_mplus", function()
      Addon._test_profile.statPriorityMode = "archon_mplus"
      Addon._test_profile.stats = {
        { key = "CRIT", enabled = true },
        { key = "HASTE", enabled = true },
        { key = "VERS", enabled = true },
        { key = "MASTERY", enabled = true },
      }
      local out = Addon:GetDisplayStats()
      assert.is_true(#out == 4)
      assert.are.equal("HASTE", out[1].key)
    end)
  end)
end)
