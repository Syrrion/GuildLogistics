-- Module de communication principal pour GuildLogistics
-- Orchestrateur qui importe et coordonne tous les sous-modules

local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
local GLOG = ns.GLOG

-- ===== Import des modules spécialisés =====

-- Vérification que tous les modules requis sont chargés
local function ensureModulesLoaded()
    -- Dans WoW, les fichiers .lua sont chargés séquentiellement selon l'ordre du .toc
    -- Si nous arrivons ici, c'est que Comm.lua a été chargé, donc tous les modules précédents aussi
    -- On fait une vérification minimale pour s'assurer que les fonctions critiques existent
    
    local criticalFunctions = {
        "encodeKV",           -- Serialization
        "pushLog",            -- DebugLogging  
        "HandleMessage",      -- MessageHandlers
    }
    
    local missing = {}
    for _, funcName in ipairs(criticalFunctions) do
        if not GLOG[funcName] or type(GLOG[funcName]) ~= "function" then
            missing[#missing + 1] = funcName
        end
    end
    
    if #missing > 0 then
        local msg = "GuildLogistics: Fonctions critiques manquantes: " .. table.concat(missing, ", ")
        if geterrorhandler then 
            geterrorhandler()(msg)
        else
            print(msg)
        end
        return false
    end
    
    return true
end

-- ===== État global et constantes =====

-- Drapeau de première synchronisation
local _FirstSyncRebroadcastDone = false

-- Garde-fou : attache les helpers UID exposés par Helper.lua (et fallback ultime)
GLOG.GetOrAssignUID = GLOG.GetOrAssignUID or (ns.Util and ns.Util.GetOrAssignUID)
GLOG.GetNameByUID   = GLOG.GetNameByUID   or (ns.Util and ns.Util.GetNameByUID)
GLOG.MapUID         = GLOG.MapUID         or (ns.Util and ns.Util.MapUID)
GLOG.UnmapUID       = GLOG.UnmapUID       or (ns.Util and ns.Util.UnmapUID)
GLOG.EnsureRosterLocal = GLOG.EnsureRosterLocal or (ns.Util and ns.Util.EnsureRosterLocal)

-- Fallback minimal si les utilitaires UID ne sont pas disponibles
if not GLOG.GetOrAssignUID then
    function GLOG.GetOrAssignUID(name)
        local db   = GLOG.EnsureDB()
        local full = tostring(name or "")
    db.players[full] = db.players[full] or {}
        if db.players[full].uid then return db.players[full].uid end
        local nextId = tonumber(db.meta.uidSeq or 1) or 1
        db.players[full].uid = nextId
        db.meta.uidSeq = nextId + 1
        return db.players[full].uid
    end

    function GLOG.GetNameByUID(uid)
        local db = GLOG.EnsureDB()
        local n  = tonumber(uid)
        if not n then return nil end
        for full, rec in pairs(db.players or {}) do
            if tonumber(rec and rec.uid) == n then return full end
        end
        return nil
    end

    function GLOG.MapUID(uid, name)
        local db   = GLOG.EnsureDB()
        local full =
            (GLOG.ResolveFullName and GLOG.ResolveFullName(name, { strict = true }))
            or (type(name)=="string" and name:find("%-") and name)
            or tostring(name or "")
        local nuid = tonumber(uid)
        if not nuid then return nil end
    db.players[full] = db.players[full] or {}
        db.players[full].uid = nuid
        return nuid
    end

    function GLOG.UnmapUID(uid)
        local db = GLOG.EnsureDB()
        local n  = tonumber(uid)
        if not n then return end
        for _, rec in pairs(db.players or {}) do
            if tonumber(rec and rec.uid) == n then rec.uid = nil; return end
        end
    end

    function GLOG.EnsureRosterLocal(name)
        local db   = GLOG.EnsureDB()
        local full = tostring(name or "")
    db.players[full] = db.players[full] or {}
        return db.players[full]
    end
end

-- ===== Utilitaires de base =====
local U = ns.Util or {}
local safenum = U.safenum
local truthy = U.truthy
local now = U.now
local normalizeStr = U.normalizeStr
local playerFullName = (U and U.playerFullName) or function()
    local n = (UnitName and UnitName("player")) or "?"
    local rn = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
    rn = tostring(rn):gsub("%s+",""):gsub("'","")
    return (rn ~= "" and (n.."-"..rn)) or n
end
local getRev = (U and U.getRev) or function() 
    local db = GuildLogisticsDB
    return (db and db.meta and db.meta.rev) or 0 
end

-- ===== Fonctions d'orchestration principales =====

-- Initialisation du système de communication
function GLOG.InitComm()
    -- Dans WoW, si on arrive ici, les modules sont déjà chargés par le .toc
    -- On initialise les sous-systèmes disponibles
    if GLOG.InitTransport then GLOG.InitTransport() end
    if GLOG.InitNetworkDiscovery then GLOG.InitNetworkDiscovery() end
    
    return true
end

-- Démarrage de la synchronisation réseau
function GLOG.StartNetworkSync()
    -- Démarrer la découverte réseau si disponible
    if GLOG.StartDiscovery then GLOG.StartDiscovery() end
    
    return true
end

-- Arrêt propre du système de communication
function GLOG.StopComm()
    if GLOG.StopTransport then GLOG.StopTransport() end
    if GLOG.StopDiscovery then GLOG.StopDiscovery() end
end

-- ===== Compatibility Layer =====
-- Maintient la compatibilité avec l'ancien code qui appelait directement les fonctions

-- Fonction principale de gestion des messages (délégation vers MessageHandlers)
function GLOG._HandleFull(sender, t, kv)
    if GLOG.HandleMessage then
        return GLOG.HandleMessage(sender, t, kv)
    end
end

-- Aliases pour les fonctions d'état
GLOG.SetFirstSyncRebroadcastDone = function(value)
    _FirstSyncRebroadcastDone = not not value
end

GLOG.GetFirstSyncRebroadcastDone = function()
    return _FirstSyncRebroadcastDone
end

-- ===== Auto-initialisation =====
-- S'assurer que le système est initialisé dès que possible

-- Déclencher l'initialisation après un court délai pour laisser le temps aux événements de s'initialiser
local function delayedInit()
    local success = ensureModulesLoaded()
    
    if success then
        -- ✅ Initialiser le transport IMMÉDIATEMENT pour pouvoir recevoir tous les messages
        if GLOG.InitTransport then GLOG.InitTransport() end
        if GLOG.InitNetworkDiscovery then GLOG.InitNetworkDiscovery() end
        
        -- ✅ Retarder seulement l'ÉMISSION du HELLO, pas l'initialisation
        if GLOG.StartDiscovery then 
            C_Timer.After(0.5, function() -- Délai réduit pour l'émission
                GLOG.StartDiscovery()
                -- ➕ Émettre un STATUS_UPDATE juste après le HELLO initial
                if GLOG.BroadcastStatusUpdate then
                    C_Timer.After(0.1, function()
                        GLOG.BroadcastStatusUpdate()
                    end)
                end
            end)
        end
        
        if ns.Debug then ns.Debug("Comm", "Communication system initialized successfully") end
    else
        local msg = "GuildLogistics: Critical initialization failure - check module loading order"
        if geterrorhandler then 
            geterrorhandler()(msg)
        else
            print(msg)
        end
    end
end

-- Initialiser selon le statut de connexion
if IsLoggedIn and IsLoggedIn() then
    C_Timer.After(0.1, delayedInit) -- Délai très court si déjà connecté
else
    -- Attendre la connexion
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_LOGIN" then
            C_Timer.After(0.2, delayedInit) -- Délai très court après connexion
            self:UnregisterEvent("PLAYER_LOGIN")
        end
    end)
end

-- ===== Debug et diagnostics =====
function GLOG.GetCommStatus()
    return {
        criticalFunctions = ensureModulesLoaded(),
        firstSyncDone = _FirstSyncRebroadcastDone,
        functions = {
            transport = GLOG._send and "loaded" or "missing",
            discovery = GLOG.HandleHello and "loaded" or "missing", 
            broadcasting = GLOG.BroadcastRosterUpsert and "loaded" or "missing",
            messageHandlers = GLOG.HandleMessage and "loaded" or "missing",
            serialization = GLOG.encodeKV and "loaded" or "missing",
            debugging = GLOG.pushLog and "loaded" or "missing",
            dataSync = GLOG.SnapshotExport and "loaded" or "missing",
        }
    }
end

-- Fonction de diagnostic pour l'utilisateur
function GLOG.DiagnoseComm()
    local status = GLOG.GetCommStatus()
    print("=== GuildLogistics Communication Status ===")
    for module, state in pairs(status) do
        local icon = (state == "loaded" or state == true) and "✅" or "❌"
        print(icon .. " " .. module .. ": " .. tostring(state))
    end
    print("==========================================")
end

-- ===== Exposition globale pour compatibilité =====
-- Certains anciens scripts peuvent s'attendre à ces fonctions globales
_G.GLOG_InitComm = GLOG.InitComm
_G.GLOG_StartNetworkSync = GLOG.StartNetworkSync
_G.GLOG_StopComm = GLOG.StopComm
