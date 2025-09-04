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
