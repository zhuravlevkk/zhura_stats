local stub = require("tests/wow_stub")
require("ArchonPriority")

local Addon = stub.Addon

local function is_upper_stat_token(s)
  return type(s) == "string" and s == string.upper(s) and s:match("^[%u_]+$") ~= nil
end

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

  describe("GetArchonKey", function()
    it("builds slug/slug/activity key from mocked player", function()
      local key = Addon:GetArchonKey("m+")
      assert.is_true(type(key) == "string")
      local classSlug, specSlug, activity = key:match("^([^/]+)/([^/]+)/(.+)$")
      assert.is_true(classSlug ~= nil and specSlug ~= nil)
      assert.are.equal("m+", activity)
    end)
  end)

  describe("GetArchonPriorityForMode", function()
    it("with archon mode and data returns a list of uppercase stat tokens", function()
      local list = Addon:GetArchonPriorityForMode("archon_mplus")
      assert.is_not_nil(list)
      assert.is_true(type(list) == "table")
      assert.is_true(#list > 0)
      for i = 1, #list do
        assert.is_true(is_upper_stat_token(list[i]), "expected uppercase stat key, got " .. tostring(list[i]))
      end
    end)

    it("with invalid mode string returns nil (no Archon table)", function()
      assert.is_nil(Addon:GetArchonPriorityForMode("not_a_real_mode_xyz"))
    end)

    it("with archon mode but unknown class returns nil", function()
      local saved = _G.UnitClass
      _G.UnitClass = function()
        return "X", "NOTINADDON"
      end
      local list = Addon:GetArchonPriorityForMode("archon_mplus")
      _G.UnitClass = saved
      assert.is_nil(list)
    end)
  end)

  describe("GetArchonTopHeroForMode", function()
    it("when non-nil, result has non-empty string hero field", function()
      local top = Addon:GetArchonTopHeroForMode("archon_mplus")
      assert.is_not_nil(top)
      assert.is_true(type(top) == "table")
      assert.is_true(type(top.hero) == "string")
      assert.is_true(top.hero ~= "")
    end)
  end)

  describe("GetArchonDataForMode", function()
    it("returns nil for manual mode", function()
      local data = Addon:GetArchonDataForMode("manual")
      assert.is_nil(data)
    end)

    it("returns nil without error when class is unknown (no Archon key)", function()
      local saved = _G.UnitClass
      _G.UnitClass = function()
        return "X", "NOTINADDON"
      end
      local data, key, activity = Addon:GetArchonDataForMode("archon_mplus")
      _G.UnitClass = saved
      assert.is_nil(data)
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
    it("in manual mode returns profile stats table unchanged", function()
      local stats = {
        { key = "CRIT", enabled = true },
        { key = "HASTE", enabled = false },
      }
      Addon._test_profile.statPriorityMode = "manual"
      Addon._test_profile.stats = stats
      local out = Addon:GetDisplayStats()
      assert.are.same(stats, out)
    end)

    it("in manual mode still lists disabled stats (no enabled filter)", function()
      local stats = {
        { key = "CRIT", enabled = false },
      }
      Addon._test_profile.statPriorityMode = "manual"
      Addon._test_profile.stats = stats
      local out = Addon:GetDisplayStats()
      assert.are.equal(1, #out)
      assert.is_false(out[1].enabled)
    end)

    it("in archon mode when priority exists, first entry follows Archon order", function()
      local priority = Addon:GetArchonPriorityForMode("archon_mplus")
      assert.is_not_nil(priority)
      assert.is_true(#priority > 0)
      Addon._test_profile.statPriorityMode = "archon_mplus"
      Addon._test_profile.stats = {
        { key = "CRIT", enabled = true },
        { key = "HASTE", enabled = true },
        { key = "VERS", enabled = true },
        { key = "MASTERY", enabled = true },
      }
      local out = Addon:GetDisplayStats()
      assert.is_true(#out >= 1)
      assert.are.equal(priority[1], out[1].key)
    end)
  end)
end)
