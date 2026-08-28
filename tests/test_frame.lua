local stub = require("tests/wow_stub")
require("Frame")

local Addon = stub.Addon

describe("Frame controls", function()
  before_each(function()
    stub.reset_test_profile()
  end)

  it("reserves space by default", function()
    local width, height, gap = Addon:GetFrameControlsSize()

    assert.is_true(width > 0)
    assert.is_true(height > 0)
    assert.is_true(gap > 0)
  end)

  it("does not reserve space when frame buttons are hidden", function()
    Addon:SetProfileValue("showFrameControls", false)

    local width, height, gap = Addon:GetFrameControlsSize()

    assert.are.equal(0, width)
    assert.are.equal(0, height)
    assert.are.equal(0, gap)
  end)
end)
