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

-- Persisted snapshot bridge. Core wires these to db.char (per-character,
-- keyed by spec) so the last trustworthy reading survives /reload and can be
-- shown — clearly marked — while live values are Secret (combat / M+ /
-- encounter / PvP). See Stats.SetSnapshotStore.
local snapshotStore = nil      -- table we read/write snapshot entries into
local snapshotGetSpecKey = nil -- function() -> string|number spec key

local function GetSnapshotTable(create)
    if type(snapshotStore) ~= "table" then
        return nil
    end
    local specKey = "default"
    if type(snapshotGetSpecKey) == "function" then
        local ok, key = pcall(snapshotGetSpecKey)
        if ok and key ~= nil then
            specKey = key
        end
    end
    local bucket = snapshotStore[specKey]
    if not bucket and create then
        bucket = {}
        snapshotStore[specKey] = bucket
    end
    return bucket
end

function Stats.SetSnapshotStore(store, getSpecKey)
    snapshotStore = store
    snapshotGetSpecKey = getSpecKey
end

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

local SNAPSHOT_FIELDS = { "value", "rating", "ratingBonus", "dr", "coefficient", "mitigation", "passiveBonus" }

local function StoreSnapshot(key, result)
    local bucket = GetSnapshotTable(true)
    if not bucket then
        return
    end
    local entry = {}
    for _, field in ipairs(SNAPSHOT_FIELDS) do
        entry[field] = result[field]
    end
    entry.capturedAt = (GetTime and GetTime()) or 0
    bucket[key] = entry
end

local function ReadSnapshot(key)
    local bucket = GetSnapshotTable(false)
    if not bucket then
        return nil
    end
    return bucket[key]
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
        -- Live, non-secret value. This is the only place we know the reading is
        -- trustworthy, so persist it as the snapshot (approach (a): a value
        -- that survived AsNumber cannot be a Secret).
        cache[key] = result
        StoreSnapshot(key, result)
        return result
    end

    -- No live value (Secret, or API unavailable). Prefer the in-memory cache
    -- from earlier this session; it carries the full extra fields.
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

    -- Nothing in memory (e.g. fresh /reload inside a Mythic+). Fall back to the
    -- persisted snapshot so we show the last trustworthy reading instead of 0.
    local snap = ReadSnapshot(key)
    if snap and snap.value ~= nil then
        local copy = {}
        for snapKey, snapValue in pairs(snap) do
            copy[snapKey] = snapValue
        end
        copy.key = key
        copy.stale = true
        copy.source = "snapshot"
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

    local rawCurrent, rawRun, rawFlight, rawSwim = GetUnitSpeed("player")
    -- GetUnitSpeed is SecretWhenUnitStatsRestricted: in combat/M+/encounter/PvP
    -- these come back as Secret values. Coerce through AsNumber so any Secret
    -- (or non-number) collapses to nil instead of erroring on comparison.
    local currentSpeed = AsNumber(rawCurrent)
    local runSpeed = AsNumber(rawRun)
    local flightSpeed = AsNumber(rawFlight)
    local swimSpeed = AsNumber(rawSwim)

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

-- Single-call live getters for the stripped-down in-combat display. Each returns
-- exactly ONE raw API value (no arithmetic, no sums) so the result can be a
-- Secret we pass straight to FontString:SetFormattedText without ever inspecting
-- it. Stats that need Lua math are handled specially or omitted:
--   MOVEMENT_SPEED -> needs (speed / 7) * 100, no clean passthrough (omitted).
--   VERS           -> rating bonus only; the passive/aura component (a second
--                     Secret we cannot add) is dropped while restricted.
--   DURA/ILVL/GOLD -> never Secret, so they are absent here and keep the full
--                     formatted path even in combat.
local SECRET_LIVE_GETTERS = {
    STR = function() return (select(2, UnitStat("player", STAT_IDS.STR))) end,
    AGI = function() return (select(2, UnitStat("player", STAT_IDS.AGI))) end,
    INT = function() return (select(2, UnitStat("player", STAT_IDS.INT))) end,
    HASTE = function() return GetHaste and GetHaste() end,
    CRIT = function() return GetCritChance and GetCritChance() end,
    MASTERY = function() return GetMasteryEffect and (GetMasteryEffect()) end,
    VERS = function()
        local id = CR_VERSATILITY_DAMAGE_DONE or CR_VERSATILITY_DAMAGE_TAKEN or CR_VERSATILITY
        return GetCombatRatingBonus and id and GetCombatRatingBonus(id)
    end,
    AVOIDANCE = function() return GetAvoidance and GetAvoidance() end,
    PARRY = function() return GetParryChance and GetParryChance() end,
    DODGE = function() return GetDodgeChance and GetDodgeChance() end,
    BLOCK = function() return GetBlockChance and GetBlockChance() end,
    LEECH = function() return GetLifesteal and GetLifesteal() end,
    SPEED = function() return GetCombatRatingBonus and CR_SPEED and GetCombatRatingBonus(CR_SPEED) end,
}

-- Live passthrough probe. Returns (true, rawSecret) when the stat's live value
-- is a Secret (combat / M+ / encounter / PvP) so the renderer can display it
-- without reading it. Returns false when the value is readable (caller should
-- use the normal formatted path) or the stat has no clean single-call value.
-- Never inspects the raw value beyond issecretvalue.
function Stats.ReadSecretPassthrough(key)
    local getter = SECRET_LIVE_GETTERS[key]
    if not getter then
        return false
    end

    local ok, raw = pcall(getter)
    if not ok then
        return false
    end

    if IsSecret(raw) then
        return true, raw
    end

    return false
end

function Stats.GetMovementSpeedPercent()
    return GetMovementSpeedPercent()
end
