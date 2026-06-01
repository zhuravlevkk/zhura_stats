local stub = require("tests/wow_stub")
require("Format")

local Addon = stub.Addon

local function expectedRefArrowSize()
  return Addon:GetRefArrowSize(Addon.Defaults.profile, Addon.Defaults.profile)
end

local REF_ARROW_TEX_UP = "Interface\\AddOns\\ZhuraStats\\Media\\RefArrowUp"
local REF_ARROW_TEX_DOWN = "Interface\\AddOns\\ZhuraStats\\Media\\RefArrowDown"

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

  describe("GetReferenceProximityColor", function()
    it("returns green on archon rating match", function()
      local r, g, b = Addon:GetReferenceProximityColor(300, 300)
      assert.is_true(r < 0.5 and g > 0.8)
    end)

    it("returns red when far below or above archon reference", function()
      local underR, underG, underB = Addon:GetReferenceProximityColor(100, 300)
      local overR, overG, overB = Addon:GetReferenceProximityColor(500, 300)
      assert.is_true(underR > 0.85 and underG < 0.25)
      assert.is_true(overR > 0.85 and overG < 0.25)
    end)

    it("returns near-green for small delta", function()
      local r, g, b = Addon:GetReferenceProximityColor(304, 300)
      assert.is_true(g > 0.85 and r < 0.55)
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
    local FIXTURE_CRIT = 300
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

  describe("BuildStatSegments", function()
    local FIXTURE_CRIT = 300
    before_each(function()
      WoWLogsStatsPrio = WoWLogsStatsPrio or {}
      WoWLogsStatsPrio["mage/fire/m+"] = {
        updated  = "2025-01-01T00:00:00Z",
        activity = "m+", class = "mage", spec = "fire",
        primary  = "intellect",
        secondary = {
          { stat = "crit", rating = FIXTURE_CRIT, order = 4 },
        },
      }
    end)

    local function byCol(segments, col)
      for _, seg in ipairs(segments) do
        if seg.col == col then
          return seg
        end
      end
      return nil
    end

    it("rating stat with values+percent yields rating/sep/percent segments", function()
      local p = Addon._test_profile
      p.showLabels = true
      p.showValues = true
      p.showPercent = true
      p.percentPrecision = 0
      p.drDisplayMode = "off"
      p.statPriorityMode = "manual"
      local segs = Addon:BuildStatSegments("CRIT", { value = 35, rating = 981 }, p, Addon.StatDefinitions.CRIT)
      assert.is_not_nil(byCol(segs, "label"))
      assert.are.equal("981", byCol(segs, "rating").text)
      assert.are.equal("/", byCol(segs, "sep").text)
      assert.are.equal("35%", byCol(segs, "percent").text)
      assert.is_nil(byCol(segs, "value"))
    end)

    it("rating segments carry RIGHT justify for numeric columns", function()
      local p = Addon._test_profile
      p.showLabels = false
      p.showValues = true
      p.showPercent = true
      p.percentPrecision = 0
      p.drDisplayMode = "off"
      p.statPriorityMode = "manual"
      local segs = Addon:BuildStatSegments("CRIT", { value = 35, rating = 981 }, p, Addon.StatDefinitions.CRIT)
      assert.are.equal("RIGHT", byCol(segs, "rating").justify)
      assert.are.equal("RIGHT", byCol(segs, "percent").justify)
    end)

    it("non-rating stat yields a single value segment, no rating/sep/percent", function()
      local p = Addon._test_profile
      p.showLabels = true
      p.showValues = true
      p.showPercent = true
      p.drDisplayMode = "off"
      p.statPriorityMode = "manual"
      local segs = Addon:BuildStatSegments("ILVL", { value = 287.44 }, p, Addon.StatDefinitions.ILVL)
      assert.is_not_nil(byCol(segs, "value"))
      assert.is_nil(byCol(segs, "rating"))
      assert.is_nil(byCol(segs, "sep"))
      assert.is_nil(byCol(segs, "percent"))
    end)

    it("GOLD value segment uses gold formatting", function()
      local p = Addon._test_profile
      p.showLabels = false
      p.showValues = true
      p.goldUseSeparator = true
      p.goldSeparator = "."
      p.drDisplayMode = "off"
      p.statPriorityMode = "manual"
      local segs = Addon:BuildStatSegments("GOLD", { value = 63399 }, p, Addon.StatDefinitions.GOLD)
      assert.are.equal("63.399", byCol(segs, "value").text)
    end)

    it("delta mode emits a colored ref segment with +N when under", function()
      local p = Addon._test_profile
      p.showLabels = false
      p.showValues = true
      p.showPercent = true
      p.percentPrecision = 0
      p.drDisplayMode = "off"
      p.statPriorityMode = "archon_mplus"
      p.referenceDisplay = "delta"
      -- rating 100 < FIXTURE_CRIT 300 → undercapped by 200 → down arrow
      local segs = Addon:BuildStatSegments("CRIT", { value = 10, rating = 100 }, p, Addon.StatDefinitions.CRIT)
      local refArrow = byCol(segs, "ref_arrow")
      local ref = byCol(segs, "ref")
      assert.is_not_nil(refArrow)
      assert.is_not_nil(ref)
      assert.are.equal(REF_ARROW_TEX_DOWN, refArrow.texture)
      assert.are.equal(expectedRefArrowSize(), refArrow.textureSize)
      local r, g, b = Addon:GetReferenceProximityColor(100, 300)
      assert.are.same({ r, g, b }, refArrow.color)
      assert.are.equal("200", ref.text)
      assert.is_not_nil(ref.color)
    end)

    it("delta mode emits up arrow when overcapped (rating above reference)", function()
      local p = Addon._test_profile
      p.showLabels = false
      p.showValues = true
      p.showPercent = true
      p.percentPrecision = 0
      p.drDisplayMode = "off"
      p.statPriorityMode = "archon_mplus"
      p.referenceDisplay = "delta"
      -- rating 500 > FIXTURE_CRIT 300 → overcapped by 200 → up arrow, NOT minus
      local segs = Addon:BuildStatSegments("CRIT", { value = 10, rating = 500 }, p, Addon.StatDefinitions.CRIT)
      local refArrow = byCol(segs, "ref_arrow")
      local ref = byCol(segs, "ref")
      assert.is_not_nil(refArrow)
      assert.is_not_nil(ref)
      assert.are.equal(REF_ARROW_TEX_UP, refArrow.texture)
      assert.are.equal(expectedRefArrowSize(), refArrow.textureSize)
      local r, g, b = Addon:GetReferenceProximityColor(500, 300)
      assert.are.same({ r, g, b }, refArrow.color)
      assert.are.equal("200", ref.text)
      -- guard against the old sign-inversion bug (negative delta magnitude)
      assert.is_nil(ref.text:match("%-%d+$"))
    end)

    it("manual mode emits no ref segment", function()
      local p = Addon._test_profile
      p.showLabels = false
      p.showValues = true
      p.showPercent = true
      p.drDisplayMode = "off"
      p.statPriorityMode = "manual"
      p.referenceDisplay = "delta"
      local segs = Addon:BuildStatSegments("CRIT", { value = 10, rating = 100 }, p, Addon.StatDefinitions.CRIT)
      assert.is_nil(byCol(segs, "ref"))
    end)

    it("hides ref segments while DR is active but wants hover tooltip", function()
      local p = Addon._test_profile
      p.showLabels = false
      p.showValues = true
      p.showPercent = true
      p.percentPrecision = 0
      p.drDisplayMode = "penalty"
      p.statPriorityMode = "archon_mplus"
      p.referenceDisplay = "delta"
      local statResult = { value = 60, rating = 500, dr = { penalty = 25, loss = 120 } }
      local segs = Addon:BuildStatSegments("CRIT", statResult, p, Addon.StatDefinitions.CRIT)
      assert.is_not_nil(byCol(segs, "dr"))
      assert.is_nil(byCol(segs, "ref"))
      assert.is_nil(byCol(segs, "ref_arrow"))
      assert.is_false(Addon:ShouldShowReferenceOnRow("CRIT", statResult, p))
      assert.is_true(Addon:WantsReferenceTooltip("CRIT", statResult, p))
    end)

    it("shows ref in delta mode when DR is inactive and no hover tooltip", function()
      local p = Addon._test_profile
      p.showLabels = false
      p.showValues = true
      p.showPercent = true
      p.percentPrecision = 0
      p.drDisplayMode = "off"
      p.statPriorityMode = "archon_mplus"
      p.referenceDisplay = "delta"
      local statResult = { value = 10, rating = 500 }
      local segs = Addon:BuildStatSegments("CRIT", statResult, p, Addon.StatDefinitions.CRIT)
      assert.is_not_nil(byCol(segs, "ref"))
      assert.is_true(Addon:ShouldShowReferenceOnRow("CRIT", statResult, p))
      assert.is_false(Addon:WantsReferenceTooltip("CRIT", statResult, p))
    end)

    it("dr penalty mode emits a dr segment", function()
      local p = Addon._test_profile
      p.showLabels = false
      p.showValues = true
      p.showPercent = true
      p.percentPrecision = 0
      p.drDisplayMode = "penalty"
      p.statPriorityMode = "manual"
      local segs = Addon:BuildStatSegments("CRIT", { value = 10, rating = 100, dr = { penalty = 25, loss = 3 } }, p, Addon.StatDefinitions.CRIT)
      local dr = byCol(segs, "dr")
      assert.is_not_nil(dr)
      assert.is_true(dr.text:find("DR", 1, true) ~= nil)
    end)

    it("dr tag shows DR(-loss) using rating lost to DR", function()
      local p = Addon._test_profile
      p.showLabels = false
      p.showValues = true
      p.showPercent = true
      p.percentPrecision = 0
      p.drDisplayMode = "full"
      p.statPriorityMode = "manual"
      local segs = Addon:BuildStatSegments("CRIT", { value = 10, rating = 100, dr = { penalty = 25, loss = 123 } }, p, Addon.StatDefinitions.CRIT)
      local dr = byCol(segs, "dr")
      assert.is_not_nil(dr)
      -- Tag carries the real DR loss, formatted as DR(-N).
      assert.are.equal("DR(-123)", dr.text)
      assert.is_true(dr.drFlag == true)
    end)

    it("dr tag rounds loss and falls back to bare DR when loss is zero", function()
      local p = Addon._test_profile
      p.showLabels = false
      p.showValues = true
      p.showPercent = true
      p.percentPrecision = 0
      p.drDisplayMode = "penalty"
      p.statPriorityMode = "manual"
      -- penalty > 0 (so DR shows) but loss rounds to 0 → bare "DR".
      local segs = Addon:BuildStatSegments("CRIT", { value = 10, rating = 100, dr = { penalty = 10, loss = 0.2 } }, p, Addon.StatDefinitions.CRIT)
      assert.are.equal("DR", byCol(segs, "dr").text)
    end)

    it("percent segment is dr-flagged when diminished", function()
      local p = Addon._test_profile
      p.showLabels = false
      p.showValues = true
      p.showPercent = true
      p.percentPrecision = 0
      p.drDisplayMode = "penalty"
      p.statPriorityMode = "manual"
      local segs = Addon:BuildStatSegments("CRIT", { value = 10, rating = 100, dr = { penalty = 25 } }, p, Addon.StatDefinitions.CRIT)
      assert.is_true(byCol(segs, "percent").drFlag == true)
    end)

    it("no dr segment and no dr flag when penalty is zero", function()
      local p = Addon._test_profile
      p.showLabels = false
      p.showValues = true
      p.showPercent = true
      p.percentPrecision = 0
      p.drDisplayMode = "penalty"
      p.statPriorityMode = "manual"
      local segs = Addon:BuildStatSegments("CRIT", { value = 10, rating = 100, dr = { penalty = 0, loss = 0 } }, p, Addon.StatDefinitions.CRIT)
      assert.is_nil(byCol(segs, "dr"))
      assert.is_not_true(byCol(segs, "percent").drFlag)
    end)

    it("no dr segment when drDisplayMode is off even with penalty", function()
      local p = Addon._test_profile
      p.showLabels = false
      p.showValues = true
      p.showPercent = true
      p.percentPrecision = 0
      p.drDisplayMode = "off"
      p.statPriorityMode = "manual"
      local segs = Addon:BuildStatSegments("CRIT", { value = 10, rating = 100, dr = { penalty = 25, loss = 3 } }, p, Addon.StatDefinitions.CRIT)
      assert.is_nil(byCol(segs, "dr"))
      assert.is_not_true(byCol(segs, "percent").drFlag)
    end)
  end)
end)
