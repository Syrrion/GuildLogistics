local ADDON, ns = ...
ns.Util = ns.Util or {}
local U = ns.Util
ns.GLOG = ns.GLOG or {}
local GLOG = ns.GLOG

-- Guild Logistics - Mythic Plus Affixes Rotation Manager for Season 3 (started August 12, 2025)

-- Affix data with their starting week and rotation pattern
local AFFIXES_DATA = {
    [158] = { -- Lié par le vide
        startWeek = 1, 
        pattern = {3, 5, 3, 5} 
    },
    [148] = { -- Sublimation
        startWeek = 2, 
        pattern = {5, 3, 5, 3} 
    },
    [162] = { -- Pulsar
        startWeek = 3, 
        pattern = {3, 5, 3, 5} 
    },
    [160] = { -- Dévorer
        startWeek = 5, 
        pattern = {3, 5, 3, 5} 
    }
}

-- Weekly alternating affixes (10 starts week 1, then alternates with 9)
local WEEKLY_AFFIXES = {
    [10] = { startWeek = 1 }, -- Fortifié
    [9] = { startWeek = 2 }   -- Tyrannique
}

-- Check if an affix is active for a given week (affixId, weekNumber -> boolean)
function U.IsAffixActiveForWeek(affixId, weekNumber)
    -- Check weekly alternating affixes first
    local weeklyAffix = WEEKLY_AFFIXES[affixId]
    if weeklyAffix then
        local isActive = false
        if affixId == 10 then
            isActive = (weekNumber % 2) == 1 -- Odd weeks
        elseif affixId == 9 then
            isActive = (weekNumber % 2) == 0 -- Even weeks
        end
        return isActive
    end
    
    -- Check pattern-based affixes
    local affixData = AFFIXES_DATA[affixId]
    if not affixData then
        return false
    end
    
    local startWeek = affixData.startWeek
    local pattern = affixData.pattern
    
    -- Affix hasn't started yet
    if weekNumber < startWeek then
        return false
    end
    
    -- Calculate if current week matches the affix schedule
    local currentWeek = startWeek
    local patternIndex = 1
    
    -- Debug pour affixe 148
    if affixId == 148 then
    end
    
    -- Find the exact week in the rotation cycle
    while currentWeek < weekNumber do
        if affixId == 148 then
        end
        currentWeek = currentWeek + pattern[patternIndex]
        patternIndex = patternIndex + 1
        if patternIndex > #pattern then
            patternIndex = 1 -- Reset to beginning of pattern
        end
    end
    
    local isActive = currentWeek == weekNumber
    return isActive
end

-- Get the active affix for a given timestamp (optional timestamp -> affixId or nil)
function U.GetActiveAffixForTimestamp(timestamp)
    timestamp = timestamp or time()
    
    local weekNumber = GLOG.Time.GetWeekNumberFromTimestamp(timestamp)
    
    -- Check pattern-based affixes first
    for affixId, _ in pairs(AFFIXES_DATA) do
        if U.IsAffixActiveForWeek(affixId, weekNumber) then
            return affixId
        end
    end
    
    return nil
end

-- Get all active affixes for a given timestamp (optional timestamp -> table of affixIds)
function U.GetAllActiveAffixesForTimestamp(timestamp)
    timestamp = timestamp or time()
    
    local weekNumber = GLOG.Time.GetWeekNumberFromTimestamp(timestamp)
    local activeAffixes = {}
    
    -- Check pattern-based affixes
    for affixId, _ in pairs(AFFIXES_DATA) do
        if U.IsAffixActiveForWeek(affixId, weekNumber) then
            table.insert(activeAffixes, affixId)
        end
    end
    
    -- Check weekly alternating affixes
    for affixId, _ in pairs(WEEKLY_AFFIXES) do
        if U.IsAffixActiveForWeek(affixId, weekNumber) then
            table.insert(activeAffixes, affixId)
        end
    end
    
    return activeAffixes
end

-- Get the current weekly affix (10 or 9)
function U.GetCurrentWeeklyAffix()
    local weekNumber = GLOG.Time.GetWeekNumberFromTimestamp(time())
    return (weekNumber % 2) == 1 and 10 or 9
end

-- Get the current active affix (-> affixId or nil)
function U.GetCurrentActiveAffix()
    return U.GetActiveAffixForTimestamp(time())
end

-- Get all future affixes up to a given timestamp (optional endTimestamp -> table of {week, affixId, timestamp})
function U.GetFutureAffixes(endTimestamp)
    endTimestamp = endTimestamp or (time() + (90 * 24 * 60 * 60)) -- 3 months from now
    
    local result = {}
    local currentTimestamp = GLOG.Time.SEASON_START_TIMESTAMP
    local weekNumber = 1
    
    while currentTimestamp <= endTimestamp do
        local weekAffixes = {}
        
        -- Check pattern-based affixes
        for affixId, _ in pairs(AFFIXES_DATA) do
            if U.IsAffixActiveForWeek(affixId, weekNumber) then
                table.insert(weekAffixes, affixId)
            end
        end
        
        -- Check weekly alternating affixes
        for affixId, _ in pairs(WEEKLY_AFFIXES) do
            if U.IsAffixActiveForWeek(affixId, weekNumber) then
                table.insert(weekAffixes, affixId)
            end
        end
        
        -- Add entry for this week
        table.insert(result, {
            week = weekNumber,
            affixes = weekAffixes,
            timestamp = currentTimestamp
        })
        
        weekNumber = weekNumber + 1
        currentTimestamp = currentTimestamp + GLOG.Time.SECONDS_PER_WEEK
    end
    
    return result
end

-- Get the next occurrence of a specific affix (affixId, optional fromTimestamp -> table or nil)
function U.GetNextAffixOccurrence(affixId, fromTimestamp)
    fromTimestamp = fromTimestamp or time()
    local endTimestamp = fromTimestamp + (180 * 24 * 60 * 60) -- 6 months from start
    
    local startWeek = GLOG.Time.GetWeekNumberFromTimestamp(fromTimestamp)
    local currentTimestamp = GLOG.Time.SEASON_START_TIMESTAMP + ((startWeek - 1) * GLOG.Time.SECONDS_PER_WEEK)
    local weekNumber = startWeek
    
    while currentTimestamp <= endTimestamp do
        if U.IsAffixActiveForWeek(affixId, weekNumber) and currentTimestamp >= fromTimestamp then
            return {
                week = weekNumber,
                affixId = affixId,
                timestamp = currentTimestamp
            }
        end
        
        weekNumber = weekNumber + 1
        currentTimestamp = currentTimestamp + GLOG.Time.SECONDS_PER_WEEK
    end
    
    return nil
end

-- Get debugging information about the affix rotation (optional timestamp -> debug table)
function U.GetAffixDebugInfo(timestamp)
    timestamp = timestamp or time()
    
    local weekNumber = GLOG.Time.GetWeekNumberFromTimestamp(timestamp)
    local activeAffix = U.GetActiveAffixForTimestamp(timestamp)
    local allActiveAffixes = U.GetAllActiveAffixesForTimestamp(timestamp)
    
    local debug = {
        timestamp = timestamp,
        weekNumber = weekNumber,
        activeAffix = activeAffix,
        allActiveAffixes = allActiveAffixes,
        affixesStatus = {}
    }
    
    -- Check status of pattern-based affixes
    for affixId, data in pairs(AFFIXES_DATA) do
        debug.affixesStatus[affixId] = {
            isActive = U.IsAffixActiveForWeek(affixId, weekNumber),
            startWeek = data.startWeek,
            pattern = data.pattern,
            type = "pattern"
        }
    end
    
    -- Check status of weekly affixes
    for affixId, data in pairs(WEEKLY_AFFIXES) do
        debug.affixesStatus[affixId] = {
            isActive = U.IsAffixActiveForWeek(affixId, weekNumber),
            startWeek = data.startWeek,
            pattern = "weekly",
            type = "weekly"
        }
    end
    
    return debug
end

-- Get affixes for a specific week with offset from current week (weekOffset -> affixes table, weekNumber)
function U.GetWeekAffixes(weekOffset)
    weekOffset = weekOffset or 0
    local currentWeek = GLOG.Time.GetWeekNumberFromTimestamp(time())
    local targetWeek = currentWeek + weekOffset
    local affixes = {}
    
    -- Get pattern-based affix (test all affixes in AFFIXES_DATA)
    for affixId, _ in pairs(AFFIXES_DATA) do
        if U.IsAffixActiveForWeek(affixId, targetWeek) then
            table.insert(affixes, affixId)
            break -- Seulement un affix pattern par semaine
        end
    end
    
    -- Get weekly affix (9 or 10) - ALWAYS present
    local weeklyAffix = (targetWeek % 2) == 1 and 10 or 9
    table.insert(affixes, weeklyAffix)
    return affixes, targetWeek
end

-- Get affix information using WoW API (affixId -> name, iconId, description)
function U.GetAffixInfo(affixId)
    if not C_ChallengeMode or not C_ChallengeMode.GetAffixInfo then
        return "Affixe " .. tostring(affixId), nil, ""
    end
    
    local name, description, filedataid = C_ChallengeMode.GetAffixInfo(affixId)
    if name then
        return name, filedataid, description
    end
    
    return "Affixe " .. tostring(affixId), nil, ""
end

-- Test function specifically for date calculations
function U.TestDateCalculations()
    -- Test des 15 premières semaines
    for week = 1, 15 do
        local dateRange = GLOG.Time.GetWeekDateRange(week)
        local startTS, endTS = GLOG.Time.GetWeekStartEndTimestamps(week)
        
        -- Vérifier la semaine suivante
        local nextWeekStartTS = GLOG.Time.GetWeekStartEndTimestamps(week + 1)
        local daysBetween = (nextWeekStartTS - startTS) / (24 * 60 * 60)
        
    end
end
