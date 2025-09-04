local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
ns.Util = ns.Util or {}
local GLOG, U = ns.GLOG, ns.Util

-- True si 'name' (ou un de ses alts du même MAIN) est dans MA party (non-raid).
-- Comparaison sur nom complet "Nom-Royaume".
function GLOG.IsInMyParty(name)
    if not name or name == "" then return false end
    if IsInRaid and IsInRaid() then return false end
    if not (IsInGroup and IsInGroup()) then return false end

    local nf = U.NormalizeFull
    local target = nf(name)
    if target == "" then return false end

    local pn, pr = UnitFullName and UnitFullName("player")
    local pfull = nf(pn, pr)
    if pfull:lower() == target:lower() then return true end

    for i = 1, 4 do
        local unit = "party" .. i
        if UnitExists and UnitExists(unit) then
            local n, r = UnitFullName(unit)
            local full = nf(n, r)
            if full ~= "" and full:lower() == target:lower() then
                return true
            end
        end
    end
    return false
end

-- True si un perso du même MAIN que 'name' est dans mon groupe (party) ou mon raid
-- (peu importe le sous-groupe en raid).
function GLOG.IsInMyGroup(name)
    if not name or name == "" then return false end

    local function mainKeyOf(n)
        if not n or n == "" then return nil end
        local mk = (GLOG.GetMainOf and GLOG.GetMainOf(n)) or nil
        if mk and mk ~= "" then
            return (GLOG.NormName and GLOG.NormName(mk)) or tostring(mk):lower()
        end
        return (GLOG.NormName and GLOG.NormName(n)) or tostring(n):lower()
    end

    local target = mainKeyOf(name)
    if not target then return false end

    if IsInRaid and IsInRaid() then
        for i = 1, 40 do
            local unit = "raid" .. i
            if UnitExists and UnitExists(unit) then
                local uName = UnitName and UnitName(unit)
                if mainKeyOf(uName) == target then return true end
            end
        end
        return false
    end

    if IsInGroup and IsInGroup() then
        local pName = UnitName and UnitName("player")
        if mainKeyOf(pName) == target then return true end
        for i = 1, 4 do
            local unit = "party" .. i
            if UnitExists and UnitExists(unit) then
                local uName = UnitName and UnitName(unit)
                if mainKeyOf(uName) == target then return true end
            end
        end
        return false
    end

    return false
end
