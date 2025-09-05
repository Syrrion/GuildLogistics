local ADDON, ns = ...

-- Module: LootTrackerInstance
-- Responsabilités: Contexte d'instance, résolution des noms, cache des instances
ns.LootTrackerInstance = ns.LootTrackerInstance or {}

-- Cache des noms d'instances
local _mapNameCache = {}

-- Fonctions utilitaires
local function _Now() return (time and time()) or 0 end

local function _GetEquippedIlvl()
    if GetAverageItemLevel then
        local overall, equipped = GetAverageItemLevel()
        return math.floor((equipped or overall or 0) + 0.5)
    end
    return 0
end

-- Résolution nom d'instance depuis instID (UIMapID / instanceMapID)
local function _ResolveInstanceName(instID)
    local id = tonumber(instID or 0) or 0
    if id <= 0 then return "" end
    if _mapNameCache[instID] ~= nil then return _mapNameCache[instID] end

    local name = ""
    name = (GetRealZoneText and GetRealZoneText(instID))
    _mapNameCache[instID] = name or ""

    return _mapNameCache[instID]
end

-- Retourne: ok, instID, diffID, mplusLevel
-- instID = instanceMapID (fallback: UIMapID via C_Map.GetBestMapForUnit("player"))
local function _InstanceContext()
    -- Donjon / Raid / Scénario
    local inInst, instType = false, nil
    if IsInInstance then
        local a, b = IsInInstance()
        inInst, instType = (a and true) or false, b
    end
    if inInst and (instType == "party" or instType == "raid" or instType == "scenario") then
        local diffID, mplus, instID = 0, 0, 0
        if GetInstanceInfo then
            -- 8e retour = mapID de l'instance
            local _, _, did, _, _, _, _, mapID = GetInstanceInfo()
            diffID = tonumber(did) or 0

            -- On tente de convertir le mapID en ID Encounter Journal
            local ejID = nil
            if C_EncounterJournal and C_EncounterJournal.GetInstanceForMap then
                ejID = C_EncounterJournal.GetInstanceForMap(tonumber(mapID or 0) or 0)
            end

            instID = tonumber(ejID or 0) or 0  -- ✅ priorité à l'ID EJ
            if instID == 0 then
                instID = tonumber(mapID or 0) or 0  -- fallback: on garde le mapID
            end
        end

        -- Récupération du niveau M+
        if ns.LootTrackerState and ns.LootTrackerState.GetActiveKeystoneLevel then
            local lv = ns.LootTrackerState.GetActiveKeystoneLevel()
            mplus = tonumber(lv) or 0
        end

        if (mplus == 0) and diffID == 8 and ns.LootTrackerState then
            mplus = tonumber(ns.LootTrackerState.GetCurrentMPlusLevel()) or 0
        end
        if mplus <= 0 then mplus = nil end

        return true, instID, diffID, mplus
    end

    -- Gouffres (Delves)
    if C_Scenario and C_Scenario.IsInScenario and C_Scenario.IsInScenario() then
        local instID = 0
        local mapID = 0
        if GetInstanceInfo and IsInInstance and select(1, IsInInstance()) then
            local _, _, _, _, _, _, _, mid = GetInstanceInfo()
            mapID = tonumber(mid or 0) or 0
        end
        if mapID == 0 and C_Map and C_Map.GetBestMapForUnit then
            mapID = tonumber(C_Map.GetBestMapForUnit("player") or 0) or 0
        end
        -- Tentative d'ID EJ d'abord
        if C_EncounterJournal and C_EncounterJournal.GetInstanceForMap and mapID > 0 then
            local ejID = C_EncounterJournal.GetInstanceForMap(mapID)
            instID = tonumber(ejID or 0) or 0
        end
        if instID == 0 then
            instID = mapID -- fallback: on garde le UiMapID
        end

        local diffID = 0
        return true, instID, diffID, nil
    end

    return false
end

-- Snapshot du groupe/raid au moment de l'enregistrement
local function _SnapshotGroup()
    local roster = {}

    local function addUnit(unit)
        if UnitExists and UnitExists(unit) then
            local full = (GetUnitName and GetUnitName(unit, true)) or UnitName(unit)
            if full and full ~= "" then table.insert(roster, full) end
        end
    end

    if IsInRaid and IsInRaid() then
        local n = tonumber(GetNumGroupMembers and GetNumGroupMembers()) or 0
        for i = 1, n do addUnit("raid"..i) end
    elseif IsInGroup and IsInGroup() then
        -- party1..party4 n'inclut pas le joueur
        for i = 1, 4 do addUnit("party"..i) end
        addUnit("player")
    else
        addUnit("player")
    end

    -- Optionnel: tri pour une stabilité d'affichage/stockage
    table.sort(roster, function(a, b) return tostring(a) < tostring(b) end)
    return roster
end

-- ===========
--  Cache "loot de boss" (clé: player|link) alimenté par ENCOUNTER_LOOT_RECEIVED
-- ===========
local _bossCtx = {}  -- [key] = { ts, boss, diffID, diffName, mplus, instName, player, link }

local function _normName(name) 
    name = tostring(name or ""):gsub("%-.*$", ""):lower()
    return name 
end

local function _mkKey(player, link) 
    return _normName(player or UnitName("player") or "") .. "|" .. tostring(link or "") 
end

local function _putCtx(player, link, ctx)
    ctx = ctx or {}
    ctx.ts    = _Now()
    ctx.player= player
    ctx.link  = link
    _bossCtx[_mkKey(player, link)] = ctx
end

local function _getCtx(player, link)
    local ctx = _bossCtx[_mkKey(player, link)]
    if not ctx then return nil end
    if (_Now() - (ctx.ts or 0)) > 150 then
        _bossCtx[_mkKey(player, link)] = nil
        return nil
    end
    return ctx
end

local function _getCtxByLink(link)
    local best, bestTs = nil, -1
    for _, ctx in pairs(_bossCtx) do
        if ctx.link == link and (ctx.ts or 0) > bestTs then
            best, bestTs = ctx, (ctx.ts or 0)
        end
    end
    -- Expire si trop vieux
    if best and (_Now() - (best.ts or 0)) > 150 then return nil end
    return best
end

-- =========================
-- ===   API du module   ===
-- =========================
ns.LootTrackerInstance = {
    -- Contexte d'instance
    GetInstanceContext = _InstanceContext,
    
    -- Résolution des noms
    ResolveInstanceName = _ResolveInstanceName,
    
    -- Snapshot du groupe
    SnapshotGroup = _SnapshotGroup,
    
    -- Utilitaires
    GetEquippedIlvl = _GetEquippedIlvl,
    Now = _Now,
    
    -- Cache des contextes de boss
    PutBossContext = _putCtx,
    GetBossContext = _getCtx,
    GetBossContextByLink = _getCtxByLink,
    
    -- Handler pour ENCOUNTER_LOOT_RECEIVED
    HandleEncounterLoot = function(encounterID, itemID, itemLink, quantity, player, difficultyID)
        if not itemLink or not player then return end

        -- Filtre instance/delve paramétrable
        if ns.LootTrackerState then
            local cfg = ns.LootTrackerState.GetConfig()
            if (cfg.lootInstanceOnly ~= false) then
                local okInst = _InstanceContext()
                if not okInst then return end
            end
        end

        local boss = nil
        if EJ_GetEncounterInfo and tonumber(encounterID) then
            boss = EJ_GetEncounterInfo(encounterID)
        elseif C_EncounterJournal and C_EncounterJournal.GetEncounterInfo and tonumber(encounterID) then
            local info = C_EncounterJournal.GetEncounterInfo(encounterID)
            boss = (type(info) == "table" and info.name) or info
        end

        local diffID   = tonumber(difficultyID) or 0
        local diffName = GetDifficultyInfo and GetDifficultyInfo(diffID) or nil
        diffName = (diffName ~= "" and diffName) or nil

        local instName = (GetInstanceInfo and select(1, GetInstanceInfo())) or nil
        local keystoneLevel = nil
        
        if ns.LootTrackerState and ns.LootTrackerState.GetActiveKeystoneLevel then
            keystoneLevel = tonumber(ns.LootTrackerState.GetActiveKeystoneLevel()) or nil
        end

        -- Fallback M+ si la valeur live est absente
        if (not keystoneLevel or keystoneLevel == 0) and diffID == 8 and ns.LootTrackerState then
            local lv = tonumber(ns.LootTrackerState.GetActiveKeystoneLevel()) or 0
            if lv > 0 then keystoneLevel = lv end
        end

        _putCtx(player, itemLink, {
            boss      = boss,
            diffID    = diffID,
            diffName  = diffName,
            mplus     = keystoneLevel,
            instName  = instName,
            player    = player,
            link      = itemLink,
        })

        if diffID == 8 and ns.LootTrackerState then
            ns.LootTrackerState.BackfillMPlus(itemLink)
        end
    end,
}
