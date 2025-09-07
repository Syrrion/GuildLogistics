local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
local GLOG = ns.GLOG

-- Convertit un timestamp relatif client (GetTime / GetTimePreciseSec) en epoch local.
-- Si 'ts' est déjà un epoch plausible (>= 1e9), fait un passage direct (floor).
function GLOG.PreciseToEpoch(ts)
    ts = tonumber(ts or 0) or 0
    if ts >= 1000000000 then
        return math.floor(ts)
    end
    local epochNow = (time and time()) or 0
    local relNow = (type(GetTimePreciseSec) == "function" and GetTimePreciseSec())
                or (type(GetTime) == "function" and GetTime())
                or 0
    local offset = epochNow - relNow
    return math.floor(offset + ts + 0.5)
end

-- Epoch basé sur le temps calendrier (C_DateAndTime)
function GLOG.GetCurrentCalendarEpoch()
    local ct = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime and C_DateAndTime.GetCurrentCalendarTime()
    if ct then
        return time({ year = ct.year, month = ct.month, day = ct.monthDay, hour = ct.hour, min = ct.minute, sec = 0 })
    end
    return time()
end

-- Initialize GLOG.Time namespace for date/time utilities
GLOG.Time = GLOG.Time or {}

-- Constants for M+ season calculations
GLOG.Time.SECONDS_PER_WEEK = 604800
GLOG.Time.SEASON_START_TIMESTAMP = 1754956800 - GLOG.Time.SECONDS_PER_WEEK -- August 12, 2025 00:00:00 GMT (corrigé)

-- Calculate the week number for a given timestamp (timestamp -> week number since season start)
function GLOG.Time.GetWeekNumberFromTimestamp(timestamp)
    if not timestamp or timestamp < GLOG.Time.SEASON_START_TIMESTAMP then
        return 0
    end
    
    local weeksSinceStart = math.floor((timestamp - GLOG.Time.SEASON_START_TIMESTAMP) / GLOG.Time.SECONDS_PER_WEEK)
    return weeksSinceStart + 1 -- Week 1 starts at timestamp 0
end

-- Get the start and end timestamps for a given week number
function GLOG.Time.GetWeekStartEndTimestamps(weekNumber)
    local weekStartTimestamp = GLOG.Time.SEASON_START_TIMESTAMP + ((weekNumber - 1) * GLOG.Time.SECONDS_PER_WEEK)
    -- Correction : end timestamp doit être le début de la semaine suivante - 1 seconde
    -- Mais pour l'affichage des dates, on veut la fin du dernier jour de la semaine
    local weekEndTimestamp = weekStartTimestamp + GLOG.Time.SECONDS_PER_WEEK - 1
    return weekStartTimestamp, weekEndTimestamp
end

-- Debug function to test week calculations
function GLOG.Time.DebugWeekCalculations()
    for week = 1, 12 do
        local startTS, endTS = GLOG.Time.GetWeekStartEndTimestamps(week)
        local startDate = GLOG.Time.FormatDateLocalized(startTS)
        local endDate = GLOG.Time.FormatDateLocalized(endTS)
        
        -- Test avec le jour suivant
        local nextDayTS = endTS + 1
        local nextDayDate = GLOG.Time.FormatDateLocalized(nextDayTS)
    end
end

-- Format a timestamp to a localized date string
function GLOG.Time.FormatDateLocalized(timestamp)
    local dateTable = date("*t", timestamp)
    local locale = GetLocale()
    
    -- Format selon la locale
    if locale == "frFR" then
        return string.format("%02d/%02d/%04d", dateTable.day, dateTable.month, dateTable.year)
    elseif locale == "enUS" or locale == "enGB" then
        return string.format("%02d/%02d/%04d", dateTable.month, dateTable.day, dateTable.year)
    elseif locale == "deDE" then
        return string.format("%02d.%02d.%04d", dateTable.day, dateTable.month, dateTable.year)
    else
        -- Fallback : format ISO
        return string.format("%04d-%02d-%02d", dateTable.year, dateTable.month, dateTable.day)
    end
end

-- Get formatted date range for a week
function GLOG.Time.GetWeekDateRange(weekNumber)
    local startTimestamp = GLOG.Time.SEASON_START_TIMESTAMP + ((weekNumber - 1) * GLOG.Time.SECONDS_PER_WEEK)
    
    -- Pour éviter tout chevauchement : fin = début + exactement 6 jours (6*24*60*60 secondes)
    -- Cela donne une semaine du lundi au dimanche inclus
    local endTimestamp = startTimestamp + (6 * 24 * 60 * 60)
    
    local startFormatted = GLOG.Time.FormatDateLocalized(startTimestamp)
    local endFormatted = GLOG.Time.FormatDateLocalized(endTimestamp)
    
    return string.format("%s - %s", startFormatted, endFormatted)
end
