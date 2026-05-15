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
  end)
end)
