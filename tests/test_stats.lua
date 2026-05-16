local stub = require("tests/wow_stub")
require("Stats")

local Stats = stub.ns.Stats

describe("Stats", function()
  describe("ReadStat", function()
    it("falls back to the cached primary stat when UnitStat returns a secret value", function()
      local oldUnitStat = _G.UnitStat

      _G.UnitStat = function(unit, index)
        return 0, 1234
      end
      local fresh = Stats.ReadStat("AGI")
      assert.are.equal(1234, fresh.value)
      assert.are.equal("fresh", fresh.source)
      assert.is_false(fresh.stale)

      _G.UnitStat = function(unit, index)
        return 0, { __secret = true }
      end
      local cached = Stats.ReadStat("AGI")
      assert.are.equal(1234, cached.value)
      assert.are.equal("cache", cached.source)
      assert.is_true(cached.stale)

      _G.UnitStat = oldUnitStat
    end)

    it("falls back to cached rating stats when combat rating APIs are unavailable", function()
      local oldGetHaste = _G.GetHaste
      local oldGetCombatRating = _G.GetCombatRating
      local oldGetCombatRatingBonus = _G.GetCombatRatingBonus
      local oldCrHaste = _G.CR_HASTE

      _G.CR_HASTE = 36
      _G.GetHaste = function()
        return 12.5
      end
      _G.GetCombatRating = function(ratingIndex)
        return 450
      end
      _G.GetCombatRatingBonus = function(ratingIndex)
        return 10.5
      end
      local fresh = Stats.ReadStat("HASTE")
      assert.are.equal(12.5, fresh.value)
      assert.are.equal("fresh", fresh.source)

      _G.GetHaste = function()
        return nil
      end
      _G.GetCombatRating = function(ratingIndex)
        return nil
      end
      _G.GetCombatRatingBonus = function(ratingIndex)
        return nil
      end
      local cached = Stats.ReadStat("HASTE")
      assert.are.equal(12.5, cached.value)
      assert.are.equal(450, cached.rating)
      assert.are.equal(10.5, cached.ratingBonus)
      assert.are.equal("cache", cached.source)
      assert.is_true(cached.stale)

      _G.GetHaste = oldGetHaste
      _G.GetCombatRating = oldGetCombatRating
      _G.GetCombatRatingBonus = oldGetCombatRatingBonus
      _G.CR_HASTE = oldCrHaste
    end)

    it("does not turn unavailable item level into a fresh zero", function()
      local oldGetAverageItemLevel = _G.GetAverageItemLevel

      _G.GetAverageItemLevel = function()
        return 480, 476
      end
      local fresh = Stats.ReadStat("ILVL")
      assert.are.equal(476, fresh.value)
      assert.are.equal("fresh", fresh.source)

      _G.GetAverageItemLevel = function()
        return nil, nil
      end
      local cached = Stats.ReadStat("ILVL")
      assert.are.equal(476, cached.value)
      assert.are.equal("cache", cached.source)
      assert.is_true(cached.stale)

      _G.GetAverageItemLevel = oldGetAverageItemLevel
    end)
  end)
end)
