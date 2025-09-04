local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
ns.Util = ns.Util or {}
local GLOG, U = ns.GLOG, ns.Util

-- Retourne le classTag (ex: "WARRIOR") pour 'name' en inspectant player/party/raid.
-- Utilise UnitClass / GUID pour résoudre si besoin.
function U.LookupClassForName(name)
    local targetKey = (GLOG.NormName and GLOG.NormName(name)) or tostring(name or ""):lower()
    if not targetKey or targetKey == "" then return nil end

    local function classOf(unit)
        if not UnitExists or not UnitExists(unit) then return nil end
        local n, r = UnitName(unit)
        if not n or n == "" then return nil end
        local full = (r and r ~= "" and (n .. "-" .. r)) or n
        local key  = (GLOG.NormName and GLOG.NormName(full)) or tostring(full or ""):lower()
        if key ~= targetKey then return nil end

        local _, classTag = UnitClass(unit)
        if classTag and classTag ~= "" then return classTag end

        local guid = UnitGUID and UnitGUID(unit)
        if guid and GetPlayerInfoByGUID then
            local _, _, _, _, _, classByGUID = GetPlayerInfoByGUID(guid)
            if classByGUID and classByGUID ~= "" then return classByGUID end
        end
        return nil
    end

    local c = classOf("player"); if c then return c end
    if IsInRaid and IsInRaid() then
        for i = 1, (GetNumGroupMembers() or 0) do
            c = classOf("raid" .. i); if c then return c end
        end
    else
        for i = 1, 4 do
            c = classOf("party" .. i); if c then return c end
        end
    end
    return nil
end

-- Détermine (classID, classTag, specID) pour le joueur avec fallbacks via DB passée.
function U.ResolvePlayerClassSpec(dataByClassTag)
    local useTag, useID, useSpec

    if UnitClass then
        local _, token, classID = UnitClass("player")
        useTag = token and token:upper() or nil
        if type(classID) == "number" then
            useID = classID
        elseif C_CreatureInfo and C_CreatureInfo.GetClassInfo and useTag then
            for cid = 1, 30 do
                local ok, info = pcall(C_CreatureInfo.GetClassInfo, cid)
                if ok and info and info.classFile and info.classFile:upper() == useTag then
                    useID = cid
                    break
                end
            end
        end
    end

    if GetSpecialization and GetSpecializationInfo then
        local specIndex = GetSpecialization()
        local id = specIndex and select(1, GetSpecializationInfo(specIndex)) or nil
        if id and id ~= 0 then useSpec = id end
    end

    if (not useID) and type(dataByClassTag) == "table" then
        for tag in pairs(dataByClassTag) do
            useTag = useTag or tag
            if C_CreatureInfo and C_CreatureInfo.GetClassInfo then
                for cid = 1, 30 do
                    local ok, info = pcall(C_CreatureInfo.GetClassInfo, cid)
                    if ok and info and info.classFile and info.classFile:upper() == tag then
                        useID = cid
                        break
                    end
                end
            end
            if useID then break end
        end
    end

    return useID, useTag, useSpec
end
