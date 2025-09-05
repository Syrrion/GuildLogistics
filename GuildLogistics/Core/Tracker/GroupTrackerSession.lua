local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
ns.UI   = ns.UI   or {}
ns.Util = ns.Util or {}
ns.Data = ns.Data or {}

local GLOG, UI, U, Data = ns.GLOG, ns.UI, ns.Util, ns.Data
local Tr = ns.Tr or function(s) return s end

local _G = _G
if setfenv then
    setfenv(1, setmetatable({}, { __index = _G, __newindex = _G }))
end

-- =========================
-- ===  SESSION COMBAT   ===
-- =========================

-- Session de combat en cours
local session = {
    inCombat = false,
    label    = nil,     -- nom de la rencontre (boss prioritaire)
    isBoss   = false,
    start    = 0,
    roster   = {},      -- snapshot des joueurs à l'entrée en combat
    hist     = {},      -- [full] = { {t,cat,spellID,spellName}, ... }
}

-- Anti-doublon CLEU : même joueur + même spellID dans une fenêtre courte
local _lastEventTS = {} -- key = guid:spellID (fallback name:spellID) -> epoch
local _DUP_WINDOW = 2.0

-- =========================
-- ===   OUTILS ROSTER   ===
-- =========================

local function _normalize(full)
    if GLOG and GLOG.NormalizeFull then return GLOG.NormalizeFull(full) end
    if U and U.NormalizeFull then return U.NormalizeFull(full) end
    return tostring(full or "")
end

local function _BuildRosterSet()
    local set = {}
    if IsInRaid and IsInRaid() then
        for i=1,(GetNumGroupMembers() or 0) do
            local u = "raid"..i
            if UnitExists(u) then
                local n, r = UnitName(u)
                set[_normalize((r and r~="" and (n.."-"..r)) or n)] = true
            end
        end
    else
        if UnitExists("player") then
            local n, r = UnitName("player")
            set[_normalize((r and r~="" and (n.."-"..r)) or n)] = true
        end
        for i=1,4 do
            local u = "party"..i
            if UnitExists(u) then
                local n, r = UnitName("u")
                set[_normalize((r and r~="" and (n.."-"..r)) or n)] = true
            end
        end
    end
    return set
end

local function _BuildRosterArrayFromSet(set)
    local arr = {}
    for full in pairs(set) do arr[#arr+1] = full end
    table.sort(arr)
    return arr
end

-- =========================
-- === ANTI-DOUBLON CLEU ===
-- =========================

local function _antiDupKey(sourceGUID, sourceName, spellID)
    if sourceGUID and sourceGUID ~= "" then
        return tostring(sourceGUID) .. ":" .. tostring(spellID or 0)
    end
    return tostring(sourceName or "") .. ":" .. tostring(spellID or 0)
end

local function _shouldAcceptEvent(sourceGUID, sourceName, spellID, now)
    local k = _antiDupKey(sourceGUID, sourceName, spellID)
    local last = _lastEventTS[k]
    if last and (now - last) < _DUP_WINDOW then
        return false
    end
    _lastEventTS[k] = now
    return true
end

-- =========================
-- === GESTION SESSION  ===
-- =========================

local function _clearLive()
    wipe(session.hist)
    if ns.GroupTrackerState and ns.GroupTrackerState.ClearUses then
        ns.GroupTrackerState.ClearUses()
    end
    wipe(session.roster)
end

local function _pushEvent(full, cat, spellID, spellName, when)
    session.hist[full] = session.hist[full] or {}
    table.insert(session.hist[full], {
        t = when, cat = cat,
        spellID = tonumber(spellID) or 0,
        spellName = tostring(spellName or "")
    })
end

-- Purge les données périmées pour les joueurs qui ne sont plus dans le groupe
local function _PurgeStale()
    local state = ns.GroupTrackerState and ns.GroupTrackerState.GetState() or {}
    local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
    local roster = _BuildRosterSet()
    
    -- Purge les expirations
    if store.expiry then
        for full in pairs(store.expiry) do
            if not roster[full] then store.expiry[full] = nil end
        end
    end
    
    -- Purge les compteurs de session
    if state.uses then
        for full in pairs(state.uses) do
            if not roster[full] then state.uses[full] = nil end
        end
    end
end

-- =========================
-- === NOM DE RENCONTRE ===
-- =========================

local function _findBossName()
    for i=1,5 do
        local u = "boss"..i
        if UnitExists(u) then
            local n = UnitName(u)
            if n and n ~= "" then return n, true end
        end
    end
    return nil, false
end

local function _bestEnemyFromTargets()
    local bestName, bestHP = nil, -1
    if UnitExists("target") and UnitCanAttack("player","target") then
        local hp = UnitHealthMax("target") or 0
        if hp > bestHP then bestHP = hp; bestName = UnitName("target") end
    end
    if UnitExists("focus") and UnitCanAttack("player","focus") then
        local hp = UnitHealthMax("focus") or 0
        if hp > bestHP then bestHP = hp; bestName = UnitName("focus") end
    end
    if IsInRaid and IsInRaid() then
        for i=1,(GetNumGroupMembers() or 0) do
            local u = "raid"..i.."target"
            if UnitExists(u) and UnitCanAttack("player", u) then
                local hp = UnitHealthMax(u) or 0
                if hp > bestHP then bestHP = hp; bestName = UnitName(u) end
            end
        end
    else
        for i=1,4 do
            local u = "party"..i.."target"
            if UnitExists(u) and UnitCanAttack("player", u) then
                local hp = UnitHealthMax(u) or 0
                if hp > bestHP then bestHP = hp; bestName = UnitName(u) end
            end
        end
    end
    return bestName
end

local function _computeEncounterLabel()
    local n, isBoss = _findBossName()
    if n and n ~= "" then return n, true end
    local best = _bestEnemyFromTargets()
    if best and best ~= "" then return best, false end
    return Tr("history_combat") or "Combat", false
end

-- =========================
-- ===   API PUBLIQUE    ===
-- =========================

ns.GroupTrackerSession = {
    -- Accès à la session
    GetSession = function() return session end,
    
    -- Gestion de l'état combat
    IsInCombat = function() return session.inCombat end,
    SetInCombat = function(inCombat) session.inCombat = (inCombat == true) end,
    
    GetLabel = function() return session.label end,
    SetLabel = function(label) session.label = label end,
    
    IsBoss = function() return session.isBoss end,
    SetIsBoss = function(isBoss) session.isBoss = (isBoss == true) end,
    
    GetStart = function() return session.start end,
    SetStart = function(start) session.start = tonumber(start) or 0 end,
    
    GetRoster = function() return session.roster end,
    SetRoster = function(roster) session.roster = roster or {} end,
    
    GetHist = function() return session.hist end,
    
    -- Utilitaires
    NormalizeName = function(full) return _normalize(full) end,
    BuildRosterSet = function() return _BuildRosterSet() end,
    BuildRosterArrayFromSet = function(set) return _BuildRosterArrayFromSet(set) end,
    PurgeStale = function() return _PurgeStale() end,
    ComputeEncounterLabel = function() return _computeEncounterLabel() end,
    
    -- Gestion des événements
    ShouldAcceptEvent = function(sourceGUID, sourceName, spellID, now)
        return _shouldAcceptEvent(sourceGUID, sourceName, spellID, now)
    end,
    
    -- Gestion de l'historique
    ClearLive = function() return _clearLive() end,
    PushEvent = function(full, cat, spellID, spellName, when)
        return _pushEvent(full, cat, spellID, spellName, when)
    end,
    
    -- Gestion des segments d'historique
    CreateSegment = function()
        local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
        local seg = {
            label  = session.label or (Tr("history_combat") or "Combat"),
            start  = session.start or (time and time() or 0),
            stop   = time and time() or 0,
            isBoss = (session.isBoss == true),
            roster = {},
            data   = {},
        }
        
        -- Copie du roster
        for i=1,#session.roster do 
            seg.roster[i] = session.roster[i] 
        end
        
        -- Initialisation des données
        for i=1,#seg.roster do
            local full = seg.roster[i]
            seg.data[full] = seg.data[full] or { events = {} }
        end
        
        -- Copie de l'historique
        for full, arr in pairs(session.hist) do
            seg.data[full] = seg.data[full] or { events = {} }
            for i=1,#arr do 
                seg.data[full].events[i] = arr[i] 
            end
        end
        
        -- Ajout au début de la liste des segments
        store.segments = store.segments or {}
        table.insert(store.segments, 1, seg)
        
        -- Limite à 30 segments
        while #store.segments > 30 do 
            table.remove(store.segments, #store.segments) 
        end
        
        return seg
    end,
}

-- Export vers le namespace global pour compatibilité
ns.GLOG.GroupTrackerSession = ns.GroupTrackerSession
