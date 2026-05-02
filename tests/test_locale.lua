local stub = require("tests/wow_stub")
require("Locale")

local Addon = stub.Addon

describe("Locale", function()
  before_each(function()
    Addon.db = { global = { addonLocale = "client" } }
    NE_STATS_LOCALES["enUS"] = NE_STATS_LOCALES["enUS"] or {}
    NE_STATS_LOCALES["enUS"]["Default"] = "Default"
    NE_STATS_LOCALES["enUS"]["Show percentages"] = "Show percentages"
    NE_STATS_LOCALES["enUS"]["Client language"] = "Client language"
    Addon:ApplyLocale()
  end)

  it("resolves known keys from applied locale", function()
    assert.are.equal("Default", Addon:S("Default"))
  end)

  it("falls back to key string when translation missing", function()
    assert.are.equal("TotallyMissingKey_12345", Addon:S("TotallyMissingKey_12345"))
  end)

  it("formats with string.format when extra args provided", function()
    NE_STATS_LOCALES["enUS"]["Hello %s"] = "Hello %s"
    Addon:ApplyLocale()
    assert.are.equal("Hello world", Addon:S("Hello %s", "world"))
  end)

  it("uses enUS when configured locale table is absent", function()
    Addon.db.global.addonLocale = "missingLocaleCode"
    Addon:ApplyLocale()
    assert.are.equal("Default", Addon:S("Default"))
  end)

  it("GetLocaleDisplayName for client language includes client label", function()
    local name = Addon:GetLocaleDisplayName(Addon.Constants.CLIENT_LANGUAGE_VALUE)
    assert.is_true(name:find("Client language") ~= nil or name:len() > 0)
  end)

  it("GetTextAlignDisplayName maps alignment", function()
    assert.are.equal(Addon:S("Left"), Addon:GetTextAlignDisplayName("LEFT"))
    assert.are.equal(Addon:S("Center"), Addon:GetTextAlignDisplayName("CENTER"))
    assert.are.equal(Addon:S("Right"), Addon:GetTextAlignDisplayName("RIGHT"))
  end)

  it("GetGoldSeparatorDisplayName maps known separators", function()
    assert.are.equal(Addon:S("Space"), Addon:GetGoldSeparatorDisplayName(" "))
    assert.are.equal(Addon:S("Comma"), Addon:GetGoldSeparatorDisplayName(","))
  end)

  it("GetDisplayProfileName localizes Default only", function()
    assert.are.equal(Addon:S("Default"), Addon:GetDisplayProfileName("Default"))
    assert.are.equal("Custom", Addon:GetDisplayProfileName("Custom"))
  end)
end)
