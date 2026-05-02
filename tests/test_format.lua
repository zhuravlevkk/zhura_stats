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
    it("returns base color when no penalty", function()
      local r, g, b = Addon:GetDRColor({ 0.5, 0.6, 0.7 }, 0)
      assert.is_true(math.abs(r - 0.5) < 0.0001)
      assert.is_true(math.abs(g - 0.6) < 0.0001)
      assert.is_true(math.abs(b - 0.7) < 0.0001)
    end)

    it("returns base color when penalty nil", function()
      local r, g, b = Addon:GetDRColor({ 0.5, 0.6, 0.7 }, nil)
      assert.is_true(math.abs(r - 0.5) < 0.0001)
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
  end)
end)
