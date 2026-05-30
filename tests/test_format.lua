local stub = require("tests/wow_stub")
require("Format")

local Addon = stub.Addon

describe("Format", function()
  before_each(function()
    stub.reset_test_profile()
  end)

  describe("FormatValue", function()
    it("formats integer without decimals", function()
      local p = Addon._test_profile
      p.showPercent = true
      p.percentPrecision = 2
      local entry = { suffix = "" }
      assert.are.equal("42", Addon:FormatValue(entry, 42))
    end)

    it("formats non-integer with two decimals", function()
      local p = Addon._test_profile
      p.showPercent = true
      p.percentPrecision = 2
      local entry = { suffix = "" }
      assert.are.equal("12.35", Addon:FormatValue(entry, 12.345))
    end)

    it("shows percent sign when suffix is percent and showPercent true", function()
      local p = Addon._test_profile
      p.showPercent = true
      p.percentPrecision = 2
      local entry = { suffix = "%" }
      assert.are.equal("15.00%", Addon:FormatValue(entry, 15))
    end)

    it("hides percent sign when showPercent false", function()
      local p = Addon._test_profile
      p.showPercent = false
      p.percentPrecision = 1
      local entry = { suffix = "%" }
      assert.are.equal("15.0", Addon:FormatValue(entry, 15))
    end)

    it("handles zero", function()
      local p = Addon._test_profile
      p.showPercent = true
      local entry = { suffix = "" }
      assert.are.equal("0", Addon:FormatValue(entry, 0))
    end)

    it("handles negative values", function()
      local p = Addon._test_profile
      p.showPercent = true
      p.percentPrecision = 2
      local entry = { suffix = "%" }
      assert.are.equal("-3.50%", Addon:FormatValue(entry, -3.5))
    end)

    it("handles large numbers", function()
      local p = Addon._test_profile
      p.showPercent = true
      p.percentPrecision = 2
      local entry = { suffix = "" }
      assert.are.equal("999999999", Addon:FormatValue(entry, 999999999))
    end)
  end)

  describe("FormatDiminishingReturns", function()
    it("returns empty when no dr", function()
      assert.are.equal("", Addon:FormatDiminishingReturns(nil, "penalty"))
      assert.are.equal("", Addon:FormatDiminishingReturns({}, "penalty"))
    end)

    it("returns empty when no penalty or loss", function()
      assert.are.equal("", Addon:FormatDiminishingReturns({ dr = { penalty = 0, loss = 0 } }, "penalty"))
    end)

    it("formats penalty mode", function()
      local r = { dr = { penalty = 30, loss = 12 } }
      assert.are.equal(" (DR -30%)", Addon:FormatDiminishingReturns(r, "penalty"))
    end)

    it("formats loss mode", function()
      local r = { dr = { penalty = 30, loss = 12 } }
      assert.are.equal(" (-12)", Addon:FormatDiminishingReturns(r, "loss"))
    end)

    it("formats full mode", function()
      local r = { dr = { penalty = 30, loss = 12 } }
      assert.are.equal(" (DR -30%, -12)", Addon:FormatDiminishingReturns(r, "full"))
    end)
  end)

  describe("GetDRColor", function()
    it("returns base color when penalty is 0", function()
      local r, g, b = Addon:GetDRColor({ 0.5, 0.6, 0.7 }, 0)
      assert.is_true(math.abs(r - 0.5) < 0.0001)
      assert.is_true(math.abs(g - 0.6) < 0.0001)
      assert.is_true(math.abs(b - 0.7) < 0.0001)
    end)

    it("returns base color when penalty nil", function()
      local r, g, b = Addon:GetDRColor({ 0.5, 0.6, 0.7 }, nil)
      assert.is_true(math.abs(r - 0.5) < 0.0001)
    end)

    it("interpolates at penalty 50 with fixed tolerance (>=50 warn tier)", function()
      local baseR, baseG, baseB = 0.5, 0.5, 0.5
      local warnR, warnG, warnB = 0.9, 0.2, 0.2
      local blend = 0.3
      local er = baseR + (warnR - baseR) * blend
      local eg = baseG + (warnG - baseG) * blend
      local eb = baseB + (warnB - baseB) * blend
      local r, g, b = Addon:GetDRColor({ baseR, baseG, baseB }, 50)
      assert.is_true(math.abs(r - er) < 0.05)
      assert.is_true(math.abs(g - eg) < 0.05)
      assert.is_true(math.abs(b - eb) < 0.05)
    end)

    it("uses same warn tier for penalty 100 as for 50 (max tier blend)", function()
      local r50, g50, b50 = Addon:GetDRColor({ 0.2, 0.3, 0.4 }, 50)
      local r100, g100, b100 = Addon:GetDRColor({ 0.2, 0.3, 0.4 }, 100)
      assert.is_true(math.abs(r50 - r100) < 0.0001)
      assert.is_true(math.abs(g50 - g100) < 0.0001)
      assert.is_true(math.abs(b50 - b100) < 0.0001)
    end)

    it("shifts toward warning when penalty high", function()
      local r, g, b = Addon:GetDRColor({ 0.2, 0.2, 0.2 }, 55)
      assert.is_true(r > 0.2)
    end)
  end)

  describe("FormatGoldValue", function()
    it("returns plain string when separator disabled", function()
      local profile = { goldUseSeparator = false }
      assert.are.equal("12345", Addon:FormatGoldValue(12345.4, profile))
    end)

    it("rounds gold", function()
      local profile = { goldUseSeparator = false }
      assert.are.equal("124", Addon:FormatGoldValue(123.6, profile))
    end)

    it("separates thousands with space", function()
      local profile = { goldUseSeparator = true, goldSeparator = " " }
      assert.are.equal("1 234 567", Addon:FormatGoldValue(1234567, profile))
    end)

    it("handles negative gold with separator", function()
      local profile = { goldUseSeparator = true, goldSeparator = "," }
      assert.are.equal("-9,876", Addon:FormatGoldValue(-9876, profile))
    end)

    it("handles zero", function()
      local profile = { goldUseSeparator = true, goldSeparator = " " }
      assert.are.equal("0", Addon:FormatGoldValue(0, profile))
    end)

    it("handles very large values", function()
      local profile = { goldUseSeparator = true, goldSeparator = " " }
      assert.are.equal("1 000 000 000 000", Addon:FormatGoldValue(1e12, profile))
    end)
  end)

  describe("FormatStatValue", function()
    -- These tests verify formatting *logic* (ok/low tags, suffix presence).
    -- They must not depend on WoWLogsStatsPrio.lua content, which changes every
    -- week. A fixed fixture is injected here so tests stay deterministic.
    -- FIXTURE_CRIT = 300: "ok" test sends rating=400 (>300), "low" sends rating=100 (<300).
    local FIXTURE_CRIT = 50 -- temporary: force failure to test CI notifications
    before_each(function()
      WoWLogsStatsPrio = WoWLogsStatsPrio or {}
      WoWLogsStatsPrio["mage/fire/m+"] = {
        updated  = "2025-01-01T00:00:00Z",
        activity = "m+", class = "mage", spec = "fire",
        primary  = "intellect",
        secondary = {
          { stat = "haste",       rating = 1000,         order = 2 },
          { stat = "mastery",     rating = 700,          order = 3 },
          { stat = "crit",        rating = FIXTURE_CRIT, order = 4 },
          { stat = "versatility", rating = 200,          order = 5 },
        },
      }
    end)

    it("formats GOLD with gold rules", function()
      local p = Addon._test_profile
      p.showLabels = false
      p.showValues = true
      p.showPercent = true
      p.percentPrecision = 2
      p.goldUseSeparator = false
      p.drDisplayMode = "off"
      local statResult = { value = 5000 }
      local def = Addon.StatDefinitions.GOLD
      local out = Addon:FormatStatValue("GOLD", statResult, p, def)
      assert.are.equal("5000", out)
    end)

    it("returns empty when stat definition missing", function()
      local p = Addon._test_profile
      assert.are.equal("", Addon:FormatStatValue("UNKNOWN", { value = 1 }, p, nil))
    end)

    it("with showLabels true output contains stat label", function()
      local p = Addon._test_profile
      p.showLabels = true
      p.showValues = true
      p.showPercent = true
      p.percentPrecision = 2
      p.drDisplayMode = "off"
      local def = Addon.StatDefinitions.CRIT
      local label = Addon:S(def.label)
      local out = Addon:FormatStatValue("CRIT", { value = 12.34, rating = 400 }, p, def)
      assert.is_true(out:find(label, 1, true) ~= nil)
    end)

    it("uses stat name override when labels are shown", function()
      local p = Addon._test_profile
      p.showLabels = true
      p.showValues = true
      p.showPercent = true
      p.percentPrecision = 2
      p.drDisplayMode = "off"
      p.stats = {
        { key = "CRIT", nameOverride = "Boom" },
      }
      local out = Addon:FormatStatValue("CRIT", { value = 12.34, rating = 400 }, p, Addon.StatDefinitions.CRIT)
      assert.is_true(out:find("Boom", 1, true) == 1)
      assert.is_nil(out:find("Crit", 1, true))
    end)

    it("with showValues false and showPercent false output has no digits", function()
      local p = Addon._test_profile
      p.showLabels = true
      p.showValues = false
      p.showPercent = false
      p.drDisplayMode = "off"
      local def = Addon.StatDefinitions.CRIT
      local out = Addon:FormatStatValue("CRIT", { value = 12.34, rating = 400 }, p, def)
      assert.is_nil(out:match("%d"))
    end)

    it("with drDisplayMode penalty appends DR suffix for rating stat when dr present", function()
      local p = Addon._test_profile
      p.showLabels = false
      p.showValues = true
      p.showPercent = true
      p.percentPrecision = 2
      p.drDisplayMode = "penalty"
      local def = Addon.StatDefinitions.CRIT
      local out = Addon:FormatStatValue(
        "CRIT",
        { value = 10, rating = 100, dr = { penalty = 25, loss = 3 } },
        p,
        def
      )
      assert.is_true(out:find("DR", 1, true) ~= nil)
    end)

    it("with drDisplayMode off does not append DR suffix", function()
      local p = Addon._test_profile
      p.showLabels = false
      p.showValues = true
      p.showPercent = true
      p.percentPrecision = 2
      p.drDisplayMode = "off"
      local def = Addon.StatDefinitions.CRIT
      local out = Addon:FormatStatValue(
        "CRIT",
        { value = 10, rating = 100, dr = { penalty = 25, loss = 3 } },
        p,
        def
      )
      assert.is_nil(out:find("DR", 1, true))
    end)

    it("with manual stat priority does not append Archon reference suffix", function()
      local p = Addon._test_profile
      p.showLabels = false
      p.showValues = true
      p.showPercent = true
      p.percentPrecision = 2
      p.drDisplayMode = "off"
      p.statPriorityMode = "manual"
      p.referenceDisplay = "inline"
      local def = Addon.StatDefinitions.CRIT
      local out = Addon:FormatStatValue("CRIT", { value = 10, rating = 400 }, p, def)
      assert.is_nil(out:find("ok", 1, true))
      assert.is_nil(out:find("low", 1, true))
    end)

    it("with archon_mplus appends inline ok when rating meets Archon typical", function()
      local p = Addon._test_profile
      p.showLabels = false
      p.showValues = true
      p.showPercent = true
      p.percentPrecision = 2
      p.drDisplayMode = "off"
      p.statPriorityMode = "archon_mplus"
      p.referenceDisplay = "inline"
      local def = Addon.StatDefinitions.CRIT
      -- rating=400 > FIXTURE_CRIT=300 → expects "ok"
      local out = Addon:FormatStatValue("CRIT", { value = 10, rating = 400 }, p, def)
      assert.is_true(out:find("ok", 1, true) ~= nil)
    end)

    it("with archon_mplus appends low when rating below Archon typical", function()
      local p = Addon._test_profile
      p.showLabels = false
      p.showValues = true
      p.showPercent = true
      p.percentPrecision = 2
      p.drDisplayMode = "off"
      p.statPriorityMode = "archon_mplus"
      p.referenceDisplay = "inline"
      p.showReferenceRanges = true
      local def = Addon.StatDefinitions.CRIT
      -- rating=100 < FIXTURE_CRIT=300 → expects "low" and the archon rating number
      local out = Addon:FormatStatValue("CRIT", { value = 10, rating = 100 }, p, def)
      assert.is_true(out:find("low", 1, true) ~= nil)
      assert.is_true(out:find(tostring(FIXTURE_CRIT), 1, true) ~= nil)
    end)

    it("with referenceDisplay off skips Archon suffix in archon mode", function()
      local p = Addon._test_profile
      p.showLabels = false
      p.showValues = true
      p.showPercent = true
      p.percentPrecision = 2
      p.drDisplayMode = "off"
      p.statPriorityMode = "archon_mplus"
      p.referenceDisplay = "off"
      local def = Addon.StatDefinitions.CRIT
      local out = Addon:FormatStatValue("CRIT", { value = 10, rating = 400 }, p, def)
      assert.is_nil(out:find("ok", 1, true))
    end)
  end)
end)
