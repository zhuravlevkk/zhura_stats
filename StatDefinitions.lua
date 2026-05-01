local _, ns = ...

ns = ns or {}
ns.ZhuraStats = ns.ZhuraStats or {}
local Addon = ns.ZhuraStats

local defaults = Addon.Defaults.profile
local DeepCopy = Addon.DeepCopy

local statDefinitions = {
    STR = {
        label = "Strength",
        color = { 0.95, 0.12, 0.12 },
        suffix = "",
        value = function() return select(2, UnitStat("player", 1)) end,
    },
    AGI = {
        label = "Agility",
        color = { 0.10, 1.00, 0.10 },
        suffix = "",
        value = function() return select(2, UnitStat("player", 2)) end,
    },
    INT = {
        label = "Intellect",
        color = { 0.10, 0.45, 1.00 },
        suffix = "",
        value = function() return select(2, UnitStat("player", 4)) end,
    },
    HASTE = { label = "Haste", color = { 0.45, 1.00, 0.82 }, suffix = "%", rating = function() return GetCombatRating and (GetCombatRating(CR_HASTE_MELEE) or 0) or 0 end, value = function() return GetHaste() end },
    CRIT = { label = "Crit", color = { 1.00, 0.15, 0.15 }, suffix = "%", rating = function() return GetCombatRating and (GetCombatRating(CR_CRIT_MELEE) or 0) or 0 end, value = function() return GetCritChance() end },
    VERS = { label = "Vers", color = { 0.42, 0.56, 0.74 }, suffix = "%", rating = function() return GetCombatRating and (GetCombatRating(CR_VERSATILITY_DAMAGE_DONE) or 0) or 0 end, value = function() local ratingBonus = (GetCombatRatingBonus and GetCombatRatingBonus(CR_VERSATILITY_DAMAGE_DONE)) or 0 local baseBonus = (GetVersatilityBonus and GetVersatilityBonus(CR_VERSATILITY_DAMAGE_DONE)) or 0 return ratingBonus + baseBonus end },
    MASTERY = { label = "Mastery", color = { 0.68, 0.20, 1.00 }, suffix = "%", rating = function() return GetCombatRating and (GetCombatRating(CR_MASTERY) or 0) or 0 end, value = function() return GetMasteryEffect() end },
    AVOIDANCE = { label = "Avoidance", color = { 1.00, 0.72, 0.20 }, suffix = "%", rating = function() return GetCombatRating and (GetCombatRating(CR_AVOIDANCE) or 0) or 0 end, value = function() return GetAvoidance and (GetAvoidance() or 0) or 0 end },
    PARRY = { label = "Parry", color = { 0.94, 0.64, 0.24 }, suffix = "%", rating = function() return GetCombatRating and (GetCombatRating(CR_PARRY) or 0) or 0 end, value = function() return GetParryChance and (GetParryChance() or 0) or 0 end },
    DODGE = { label = "Dodge", color = { 0.95, 0.80, 0.26 }, suffix = "%", rating = function() return GetCombatRating and (GetCombatRating(CR_DODGE) or 0) or 0 end, value = function() return GetDodgeChance and (GetDodgeChance() or 0) or 0 end },
    BLOCK = { label = "Block", color = { 0.87, 0.73, 0.42 }, suffix = "%", rating = function() return GetCombatRating and (GetCombatRating(CR_BLOCK) or 0) or 0 end, value = function() return GetBlockChance and (GetBlockChance() or 0) or 0 end },
    LEECH = { label = "Leech", color = { 0.10, 1.00, 0.55 }, suffix = "%", rating = function() return GetCombatRating and (GetCombatRating(CR_LIFESTEAL) or 0) or 0 end, value = function() return GetLifesteal and (GetLifesteal() or 0) or 0 end },
    SPEED = { label = "Speed Rating", color = { 1.00, 0.85, 0.30 }, suffix = "%", rating = function() return GetCombatRating and (GetCombatRating(CR_SPEED) or 0) or 0 end, value = function() return GetCombatRatingBonus and (GetCombatRatingBonus(CR_SPEED) or 0) or 0 end },
    MOVEMENT_SPEED = {
        label = "Movement Speed",
        color = { 1.00, 0.92, 0.38 },
        suffix = "%",
        value = function()
            local Stats = ns.Stats
            if Stats and Stats.GetMovementSpeedPercent then
                return Stats.GetMovementSpeedPercent()
            end
            return 0
        end,
    },
    DURA = { label = "Durability", color = { 0.42, 1.00, 0.42 }, suffix = "%", value = function() local totalCurrent = 0 local totalMaximum = 0 for slot = 1, 17 do local current, maximum = GetInventoryItemDurability(slot) if current and maximum and maximum > 0 then totalCurrent = totalCurrent + current totalMaximum = totalMaximum + maximum end end if totalMaximum <= 0 then return 0 end return (totalCurrent / totalMaximum) * 100 end },
    ILVL = { label = "Item Level", color = { 0.60, 0.82, 1.00 }, suffix = "", value = function() local _, equippedLevel = GetAverageItemLevel() return equippedLevel or 0 end },
    GOLD = { label = "Gold", color = { 1.00, 0.84, 0.00 }, suffix = "", value = function() return math.floor((GetMoney() or 0) / 10000) end },
}

defaults.stats = {
    { key = "STR", enabled = false, color = DeepCopy(statDefinitions.STR.color) },
    { key = "AGI", enabled = false, color = DeepCopy(statDefinitions.AGI.color) },
    { key = "INT", enabled = false, color = DeepCopy(statDefinitions.INT.color) },
    { key = "HASTE", enabled = true, color = DeepCopy(statDefinitions.HASTE.color) },
    { key = "CRIT", enabled = true, color = DeepCopy(statDefinitions.CRIT.color) },
    { key = "VERS", enabled = true, color = DeepCopy(statDefinitions.VERS.color) },
    { key = "MASTERY", enabled = true, color = DeepCopy(statDefinitions.MASTERY.color) },
    { key = "BLOCK", enabled = false, color = DeepCopy(statDefinitions.BLOCK.color) },
    { key = "LEECH", enabled = false, color = DeepCopy(statDefinitions.LEECH.color) },
    { key = "SPEED", enabled = false, color = DeepCopy(statDefinitions.SPEED.color) },
    { key = "DURA", enabled = true, color = DeepCopy(statDefinitions.DURA.color) },
    { key = "ILVL", enabled = true, color = DeepCopy(statDefinitions.ILVL.color) },
    { key = "GOLD", enabled = true, color = DeepCopy(statDefinitions.GOLD.color) },
    { key = "MOVEMENT_SPEED", enabled = false, color = DeepCopy(statDefinitions.MOVEMENT_SPEED.color) },
}

local defaultStatsByKey = {}
for _, entry in ipairs(defaults.stats) do
    defaultStatsByKey[entry.key] = entry
end

Addon.StatDefinitions = statDefinitions
Addon.DefaultStatsByKey = defaultStatsByKey
