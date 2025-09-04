local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
ns.Util = ns.Util or {}
local GLOG, U = ns.GLOG, ns.Util

-- Renvoie le sous-groupe (1..8) de 'name' dans le raid, ou nil si introuvable/hors-raid.
function GLOG.GetRaidSubgroupOf(name)
    if not name or name == "" then return nil end
    if not (IsInRaid and IsInRaid()) then return nil end

    local nf = U.NormalizeFull
    local target = nf(name)
    if target == "" then return nil end

    for i = 1, 40 do
        local unit = "raid" .. i
        if UnitExists and UnitExists(unit) then
            local rn, rr = UnitFullName and UnitFullName(unit)
            local full = nf(rn, rr)
            if full ~= "" and full:lower() == target:lower() then
                local _, _, subgroup = GetRaidRosterInfo(i)
                return tonumber(subgroup or 0) or 0
            end
        end
    end
    return nil
end

-- Renvoie le sous-groupe (1..8) du joueur local s'il est en raid, sinon nil.
function GLOG.GetMyRaidSubgroup()
    if not (IsInRaid and IsInRaid()) then return nil end
    local me = U.playerFullName and U.playerFullName() or (playerFullName and playerFullName())
    if not me or me == "" then return nil end
    return GLOG.GetRaidSubgroupOf(me)
end

-- True si un perso du même MAIN que 'name' est dans MON sous-groupe de raid (ou ma party).
function GLOG.IsInMySubgroup(name)
    if not name or name == "" then return false end

    local function normKey(n)
        return (GLOG.NormName and GLOG.NormName(n)) or (tostring(n or "")):lower()
    end
    local function mainKeyOfName(n)
        if not n or n == "" then return nil end
        local mk = (GLOG.GetMainOf and GLOG.GetMainOf(n)) or nil
        if mk and mk ~= "" then return mk end
        return normKey(n)
    end
    local function mainKeyOfUnit(unitId)
        if not (UnitExists and UnitExists(unitId)) then return nil end
        local uName = UnitName and UnitName(unitId)
        return mainKeyOfName(uName)
    end

    local targetMainKey = mainKeyOfName(name)
    if not targetMainKey or targetMainKey == "" then return false end

    if IsInRaid and IsInRaid() then
        local mySub = GLOG.GetMyRaidSubgroup and GLOG.GetMyRaidSubgroup()
        if not (tonumber(mySub or 0) > 0) then return false end

        for i = 1, 40 do
            local unit = "raid" .. i
            if UnitExists and UnitExists(unit) then
                local _, _, subgroup = GetRaidRosterInfo(i)
                if tonumber(subgroup or -1) == tonumber(mySub) then
                    if mainKeyOfUnit(unit) == targetMainKey then
                        return true
                    end
                end
            end
        end
        return false
    end

    if IsInGroup and IsInGroup() then
        if mainKeyOfUnit("player") == targetMainKey then return true end
        for i = 1, 4 do
            if mainKeyOfUnit("party" .. i) == targetMainKey then
                return true
            end
        end
        return false
    end

    return false
end
