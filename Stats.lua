local _, ns = ...

ns = ns or {}
ns.Stats = ns.Stats or {}

local Stats = ns.Stats

local DR_THRESHOLDS = { 30, 39, 47, 54, 66 }
-- DR verified against Midnight thresholds.

local STAT_IDS = {
    STR = 1,
    AGI = 2,
    INT = 4,
}

local cache = {}
local potionState = {
    active = false,
    name = nil,
    expirationTime = 0,
    lastUsedAt = 0,
    lastUsedName = nil,
}

-- A tiny seed list. The scanner also accepts registered IDs so new potion IDs
-- can be added without changing the display layer.
local potionSpellIDs = {
    -- Combat Potions (30 sec, 5 min CD)
    [1236994] = true, -- Potion of Recklessness
    [1238443] = true, -- Potion of Zealotry
    [1236998] = true, -- Draught of Rampant Abandon
    [1236616] = true, -- Light's Potential

    -- Flasks (1 hour, persist through death)
    [1235057] = true, -- Flask of Thalassian Resistance (+Versatility)
    [1235110] = true, -- Flask of the Blood Knights (+Haste)
    [1235108] = true, -- Flask of the Magisters (+Mastery)
    [1235111] = true, -- Flask of the Shattered Sun (+Crit)
}

local function IsSecret(value)
    return issecretvalue and issecretvalue(value)
end

local function AsNumber(value)
    if IsSecret(value) then
        return nil
    end
    if type(value) ~= "number" then
        return nil
    end
    return value
end

local function CallNumber(fn)
    if type(fn) ~= "function" then
        return nil
    end

    local ok, value = pcall(fn)
    if not ok then
        return nil
    end

    return AsNumber(value)
end

local function MakeResult(key, value, rating, ratingBonus, extra)
    local result = extra or {}
    result.key = key
    result.value = value
    result.rating = rating
    result.ratingBonus = ratingBonus
    result.stale = false
    result.source = "fresh"

    if value ~= nil then
        cache[key] = result
        return result
    end

    local cached = cache[key]
    if cached then
        local copy = {}
        for cachedKey, cachedValue in pairs(cached) do
            copy[cachedKey] = cachedValue
        end
        copy.stale = true
        copy.source = "cache"
        return copy
    end

    result.value = 0
    result.rating = rating or 0
    result.ratingBonus = ratingBonus or 0
    result.stale = true
    result.source = "empty"
    return result
end

local function SumKnownNumbers(...)
    local total = 0
    local hasValue = false
    for index = 1, select("#", ...) do
        local value = select(index, ...)
        if value ~= nil then
            total = total + value
            hasValue = true
        end
    end
    return hasValue and total or nil
end

function Stats.ReverseDR(ratingBonus)
    ratingBonus = AsNumber(ratingBonus) or 0
    if ratingBonus <= 0 then return 0 end
    if ratingBonus <= 30 then return ratingBonus end
    if ratingBonus <= 39 then return 30 + (ratingBonus - 30) / 0.9 end
    if ratingBonus <= 47 then return 30 + 9 / 0.9 + (ratingBonus - 39) / 0.8 end
    if ratingBonus <= 54 then return 30 + 9 / 0.9 + 8 / 0.8 + (ratingBonus - 47) / 0.7 end
    if ratingBonus <= 66 then return 30 + 9 / 0.9 + 8 / 0.8 + 7 / 0.7 + (ratingBonus - 54) / 0.6 end
    return 30 + 9 / 0.9 + 8 / 0.8 + 7 / 0.7 + 12 / 0.6 + (ratingBonus - 66) / 0.5
end

function Stats.GetDRInfo(ratingBonus, coefficient)
    ratingBonus = AsNumber(ratingBonus)
    if not ratingBonus then
        return nil
    end

    local previous = 0
    local nextThreshold
    local penalty = 0

    for index, threshold in ipairs(DR_THRESHOLDS) do
        if ratingBonus < threshold then
            nextThreshold = threshold
            if index == 1 then
                penalty = 0
            elseif index == 2 then
                penalty = 10
            elseif index == 3 then
                penalty = 20
            elseif index == 4 then
                penalty = 30
            else
                penalty = 40
            end
            break
        end
        previous = threshold
    end

    if not nextThreshold then
        nextThreshold = nil
        penalty = 50
    end

    local rawLoss = Stats.ReverseDR(ratingBonus) - ratingBonus
    local loss = rawLoss
    if coefficient and not IsSecret(coefficient) then
        loss = rawLoss * coefficient
    end

    return {
        value = ratingBonus,
        previous = previous,
        next = nextThreshold,
        remaining = nextThreshold and math.max(0, nextThreshold - ratingBonus) or 0,
        penalty = penalty,
        loss = loss,
    }
end

local function ReadPrimary(key)
    local statId = STAT_IDS[key]
    local _, effective = UnitStat("player", statId)
    local value = AsNumber(effective)

    return MakeResult(key, value)
end

local function ReadHaste()
    local ratingId = CR_HASTE_MELEE or CR_HASTE_SPELL or CR_HASTE
    local value = CallNumber(GetHaste)
    local rating = ratingId and CallNumber(function() return GetCombatRating(ratingId) end)
    local ratingBonus = ratingId and CallNumber(function() return GetCombatRatingBonus(ratingId) end)
    return MakeResult("HASTE", value, rating, ratingBonus, {
        dr = Stats.GetDRInfo(ratingBonus),
    })
end

local function ReadCrit()
    local value = CallNumber(GetCritChance)
    local ratingId = CR_CRIT_MELEE or CR_CRIT_SPELL or CR_CRIT_RANGED or CR_CRIT
    local rating = ratingId and CallNumber(function() return GetCombatRating(ratingId) end)
    local ratingBonus = ratingId and CallNumber(function() return GetCombatRatingBonus(ratingId) end)

    return MakeResult("CRIT", value, rating, ratingBonus, {
        dr = Stats.GetDRInfo(ratingBonus),
    })
end

local function ReadMastery()
    local value, coefficient = nil, nil
    if GetMasteryEffect then
        local ok, valueResult, coefficientValue = pcall(GetMasteryEffect)
        if ok then
            value = AsNumber(valueResult)
            coefficient = AsNumber(coefficientValue)
        end
    end
    local ratingId = CR_MASTERY
    local rating = ratingId and CallNumber(function() return GetCombatRating(ratingId) end)
    local ratingBonus = ratingId and CallNumber(function() return GetCombatRatingBonus(ratingId) end)

    return MakeResult("MASTERY", value, rating, ratingBonus, {
        coefficient = coefficient,
        dr = Stats.GetDRInfo(ratingBonus, coefficient),
    })
end

local function ReadVersatility()
    local ratingId = CR_VERSATILITY_DAMAGE_DONE or CR_VERSATILITY_DAMAGE_TAKEN or CR_VERSATILITY
    local mitigationRatingId = CR_VERSATILITY_DAMAGE_TAKEN
    local ratingBonus = ratingId and CallNumber(function() return GetCombatRatingBonus(ratingId) end)
    local rating = ratingId and CallNumber(function() return GetCombatRating(ratingId) end)

    -- GetVersatilityBonus returns bonus % from passives/talents/auras (on top of rating)
    local passiveBonus = CallNumber(function()
        return GetVersatilityBonus and GetVersatilityBonus(ratingId) or 0
    end)
    local value = SumKnownNumbers(ratingBonus, passiveBonus)

    local mitigationRatingBonus = mitigationRatingId and CallNumber(function()
        return GetCombatRatingBonus(mitigationRatingId)
    end)
    local mitigationPassiveBonus = CallNumber(function()
        return GetVersatilityBonus and GetVersatilityBonus(mitigationRatingId) or 0
    end)
    local mitigationValue = SumKnownNumbers(mitigationRatingBonus, mitigationPassiveBonus)

    return MakeResult("VERS", value, rating, ratingBonus, {
        mitigation = mitigationValue,
        passiveBonus = passiveBonus,
        dr = Stats.GetDRInfo(ratingBonus),
    })
end

local function ReadRatingStat(key, valueFn, ratingId)
    local value = CallNumber(valueFn)
    local rating = ratingId and CallNumber(function() return GetCombatRating(ratingId) end)
    local ratingBonus = ratingId and CallNumber(function() return GetCombatRatingBonus(ratingId) end)
    return MakeResult(key, value, rating, ratingBonus)
end

local function ReadSpeed()
    local value = CR_SPEED and CallNumber(function()
        return GetCombatRatingBonus(CR_SPEED)
    end)
    local rating = CR_SPEED and CallNumber(function()
        return GetCombatRating(CR_SPEED)
    end)
    local ratingBonus = CR_SPEED and CallNumber(function()
        return GetCombatRatingBonus(CR_SPEED)
    end)

    return MakeResult("SPEED", value, rating, ratingBonus)
end

local function GetMovementSpeedPercent()
    if not GetUnitSpeed then
        return nil
    end

    local currentSpeed, runSpeed, flightSpeed, swimSpeed = GetUnitSpeed("player")
    local speed = runSpeed

    if type(speed) ~= "number" or speed <= 0 then
        speed = currentSpeed
    end

    if type(flightSpeed) == "number" and flightSpeed > (speed or 0) then
        speed = flightSpeed
    end

    if type(swimSpeed) == "number" and swimSpeed > (speed or 0) then
        speed = swimSpeed
    end

    if type(speed) ~= "number" or speed <= 0 then
        return nil
    end

    return (speed / 7) * 100
end

local function ReadMovementSpeed()
    return MakeResult("MOVEMENT_SPEED", GetMovementSpeedPercent())
end

local function ReadDurability()
    local totalCurrent = 0
    local totalMaximum = 0
    for slot = 1, 17 do
        local current, maximum = GetInventoryItemDurability(slot)
        if current and maximum and maximum > 0 then
            totalCurrent = totalCurrent + current
            totalMaximum = totalMaximum + maximum
        end
    end
    if totalMaximum <= 0 then
        return MakeResult("DURA", 0)
    end
    return MakeResult("DURA", (totalCurrent / totalMaximum) * 100)
end

local function ReadItemLevel()
    local _, equippedLevel = GetAverageItemLevel()
    return MakeResult("ILVL", AsNumber(equippedLevel))
end

local function ReadGold()
    return MakeResult("GOLD", math.floor((GetMoney() or 0) / 10000))
end

local readers = {
    STR = ReadPrimary,
    AGI = ReadPrimary,
    INT = ReadPrimary,
    HASTE = ReadHaste,
    CRIT = ReadCrit,
    VERS = ReadVersatility,
    MASTERY = ReadMastery,
    AVOIDANCE = function()
        return ReadRatingStat("AVOIDANCE", GetAvoidance, CR_AVOIDANCE)
    end,
    PARRY = function()
        return ReadRatingStat("PARRY", GetParryChance, CR_PARRY)
    end,
    DODGE = function()
        return ReadRatingStat("DODGE", GetDodgeChance, CR_DODGE)
    end,
    BLOCK = function()
        return ReadRatingStat("BLOCK", GetBlockChance, CR_BLOCK)
    end,
    LEECH = function()
        return ReadRatingStat("LEECH", GetLifesteal, CR_LIFESTEAL)
    end,
    SPEED = ReadSpeed,
    MOVEMENT_SPEED = ReadMovementSpeed,
    DURA = ReadDurability,
    ILVL = ReadItemLevel,
    GOLD = ReadGold,
}

function Stats.ReadStat(key)
    local reader = readers[key]
    if not reader then
        return MakeResult(key, 0)
    end

    local ok, result = pcall(reader, key)
    if ok and type(result) == "table" then
        return result
    end

    return MakeResult(key, nil)
end

function Stats.RegisterPotionSpell(spellId)
    if spellId then
        potionSpellIDs[spellId] = true
    end
end

local function AuraLooksLikePotion(aura)
    if not aura then return false end
    local spellId = aura.spellId
    if spellId and not IsSecret(spellId) then
        return potionSpellIDs[spellId] == true
    end
    return false
end

function Stats.RefreshPotionState()
    potionState.active = false
    potionState.name = nil
    potionState.expirationTime = 0

    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for index = 1, 60 do
            local aura = C_UnitAuras.GetAuraDataByIndex("player", index, "HELPFUL")
            if not aura then
                break
            end
            if AuraLooksLikePotion(aura) then
                potionState.active = true
                potionState.name = aura.name
                potionState.expirationTime = aura.expirationTime or 0
                return potionState
            end
        end
    end

    return potionState
end

function Stats.HandleCombatLogEvent()
    if not CombatLogGetCurrentEventInfo or not UnitGUID then
        return
    end

    local _, subevent, _, sourceGUID, _, _, _, _, _, _, _, spellId, spellName = CombatLogGetCurrentEventInfo()
    if sourceGUID ~= UnitGUID("player") then
        return
    end
    if subevent ~= "SPELL_CAST_SUCCESS" and subevent ~= "SPELL_AURA_APPLIED" and subevent ~= "SPELL_AURA_REFRESH" then
        return
    end

    if spellId and not IsSecret(spellId) and potionSpellIDs[spellId] then
        potionState.lastUsedAt = GetTime and GetTime() or 0
        potionState.lastUsedName = spellName
    end
end

function Stats.GetPotionState()
    Stats.RefreshPotionState()
    return potionState
end

function Stats.GetMovementSpeedPercent()
    return GetMovementSpeedPercent()
end
