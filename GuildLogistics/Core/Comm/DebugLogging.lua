-- Module de journalisation pour le système de communication GuildLogistics
-- Gère l'enregistrement des messages réseau pour le debug et le monitoring

local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
local GLOG = ns.GLOG

-- Références aux utilitaires centralisées
local U = ns.Util or {}
local safenum = U.safenum
local now = U.now
local playerFullName = (U and U.playerFullName) or function()
    local n = (UnitName and UnitName("player")) or "?"
    local rn = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
    rn = tostring(rn):gsub("%s+",""):gsub("'","")
    return (rn ~= "" and (n.."-"..rn)) or n
end

-- Journalisation (onglet Debug)
local DebugLog = {} -- { {dir,type,size,chan,channel,dist,target,from,sender,emitter,seq,part,total,raw,state,status,stateText} ... }
local SendLogIndexBySeq = {}  -- index "pending" ENVOI par seq
local RecvLogIndexBySeq = {}  -- index RECU par seq

-- ===== Gestion du debug activé/désactivé =====
-- Évier : neutralise toute écriture dans les index quand le debug est OFF
local function _sinkIndexTable()
    return setmetatable({}, {
        __newindex = function() end,
        __index    = function() return nil end
    })
end

local function _updateIndexes()
    if GLOG and GLOG.IsDebugEnabled and not GLOG.IsDebugEnabled() then
        SendLogIndexBySeq = _sinkIndexTable()
        RecvLogIndexBySeq = _sinkIndexTable()
    else
        -- Restaurer les tables normales si le debug est réactivé
        if type(SendLogIndexBySeq.__newindex) == "function" then
            SendLogIndexBySeq = {}
        end
        if type(RecvLogIndexBySeq.__newindex) == "function" then
            RecvLogIndexBySeq = {}
        end
    end
end

-- Timestamp précis pour garantir l'ordre visuel dans l'onglet Debug
local function _nowPrecise()
    if type(GetTimePreciseSec) == "function" then return GetTimePreciseSec() end
    if type(GetTime) == "function" then return GetTime() end
    return (time and time()) or 0
end

-- ===== Fonctions principales de journalisation =====
local function pushLog(dir, t, size, channel, peerOrSender, seq, part, total, raw, state)
    -- ➕ Inhibition complète de la journalisation si le débug est désactivé
    if GLOG and GLOG.IsDebugEnabled and not GLOG.IsDebugEnabled() then return end

    local isSend   = (dir == "send")
    local emitter  = isSend and ((playerFullName and playerFullName()) or "") or (peerOrSender or "")
    local st       = state or ((part == 0 and "pending") or (isSend and "sent") or "receiving")
    local stText   = (st == "pending"   and "En attente")
                  or (st == "sent"      and ((part and total and part >= total) and "Transmis" or "En cours"))
                  or (st == "receiving" and "En cours")
                  or (st == "received"  and "Reçu")
                  or nil

    local r = {
        ts        = _nowPrecise(),
        dir       = dir,
        type      = t,
        size      = size,

        -- Canal
        chan      = channel or "",
        channel   = channel or "",
        dist      = channel or "",

        -- Émetteur
        target    = emitter,
        from      = emitter,
        sender    = emitter,
        emitter   = emitter,

        -- Divers
        seq       = seq,
        part      = part,
        total     = total,
        raw       = raw,

        -- État + alias
        state     = st,
        status    = st,      -- alias possible
        stateText = stText,  -- texte prêt à afficher
    }

    DebugLog[#DebugLog+1] = r

    -- Limite douce du journal (ring ~400). On coupe par paquet pour amortir.
    local MAX = 400
    if #DebugLog > (MAX + 40) then
        local drop = #DebugLog - MAX
        -- compactage manuel (plus rapide que remove(1) en boucle)
        local new = {}
        for i = drop+1, #DebugLog do new[#new+1] = DebugLog[i] end
        DebugLog = new
        -- Répare les index après compactage
        for s, idx in pairs(RecvLogIndexBySeq or {}) do
            local ni = idx - drop; RecvLogIndexBySeq[s] = (ni > 0) and ni or nil
        end
        for s, idx in pairs(SendLogIndexBySeq or {}) do
            local ni = idx - drop; SendLogIndexBySeq[s] = (ni > 0) and ni or nil
        end
        if ns.Emit then ns.Emit("debug:changed") end
    end

    if #DebugLog > 400 then table.remove(DebugLog, 1) end
    if ns.Emit then ns.Emit("debug:changed") end
end

-- Met à jour la ligne d'envoi "pending" via l'index (plus robuste que la recherche)
local function _updateSendLog(item)
    _updateIndexes() -- S'assurer que les index sont dans le bon état
    
    local idx = SendLogIndexBySeq[item.seq]
    if not idx or not DebugLog[idx] or DebugLog[idx].seq ~= item.seq then
        -- garde-fou (fallback) : recherche en sens inverse
        for i = #DebugLog, 1, -1 do
            local r = DebugLog[i]
            if r.dir == "send" and r.seq == item.seq and r.part == 0 then
                idx = i; break
            end
        end
    end
    local ts = _nowPrecise()
    if idx and DebugLog[idx] then
        local r = DebugLog[idx]
        r.ts      = ts
        r.type    = item.type
        r.size    = #item.payload
        r.channel = item.channel
        r.peer    = item.target or ""
        r.part    = item.part
        r.total   = item.total
        r.raw     = item.payload
        if ns.Emit then ns.Emit("debug:changed") end
    else
        -- Pas trouvé : on trace normalement pour ne pas perdre l'info
        pushLog("send", item.type, #item.payload, item.channel, item.target or "", item.seq, item.part, item.total, item.payload)
    end
end

-- ===== API publiques =====
function GLOG.PushLog(dir, msgType, size, channel, peer, seq, part, total, raw, state)
    pushLog(dir, msgType, size, channel, peer, seq, part, total, raw, state)
    
    -- Gérer les index pour les envois
    if dir == "send" and part == 0 then
        _updateIndexes()
        SendLogIndexBySeq[seq] = #DebugLog
    elseif dir == "recv" and part == 1 then
        _updateIndexes()
        RecvLogIndexBySeq[seq] = #DebugLog
    end
end

function GLOG.UpdateSendLog(item)
    return _updateSendLog(item)
end

function GLOG.GetDebugLogs() 
    return DebugLog 
end

function GLOG.PurgeDebug()
    wipe(DebugLog)
    wipe(SendLogIndexBySeq)
    wipe(RecvLogIndexBySeq)
    if ns.Emit then ns.Emit("debug:changed") end
end

-- ➕ Alias attendu par Tabs/Debug.lua
function GLOG.ClearDebugLogs()
    GLOG.PurgeDebug()
end

-- ===== Statistiques mémoire =====
function GLOG.Debug_GetMemStats()
    local function len(t) local n=0; for _ in pairs(t or {}) do n=n+1 end; return n end
    local mem = (collectgarbage and collectgarbage("count")) or 0
    return {
        mem = mem,           -- en KiB
        debugLog = #DebugLog,
        sendIdx = len(SendLogIndexBySeq),
        recvIdx = len(RecvLogIndexBySeq),
    }
end

function GLOG.Debug_PrintMemStats()
    local s = GLOG.Debug_GetMemStats()
    print(("GuildLogistics Debug mem: %.1f KiB | DebugLog=%d SendIdx=%d RecvIdx=%d")
        :format(s.mem, s.debugLog, s.sendIdx, s.recvIdx))
end

-- ✏️ Trace locale vers l'onglet Debug avec entête conforme (raw = "v=1|t=...|s=...|p=...|n=...|payload")
function GLOG.DebugLocal(event, fields)
    if GLOG and GLOG.IsDebugEnabled and not GLOG.IsDebugEnabled() then return end

    local tname = tostring(event or "DEBUG")
    local kv    = type(fields) == "table" and fields or {}
    kv.t = tname
    kv.s = 0  -- séquence "locale"

    -- Utilise l'encodeur existant (compression éventuelle gérée)
    local payload = ""
    if GLOG.PackPayloadStr then
        payload = GLOG.PackPayloadStr(kv)
    end
    
    -- Entête attendu par l'onglet Debug (il extrait après "|n=...|")
    local header  = string.format("v=1|t=%s|s=%d|p=%d|n=%d|", tname, 0, 1, 1)
    local raw     = header .. payload

    local me = (playerFullName and playerFullName()) or ""

    DebugLog[#DebugLog+1] = {
        ts        = _nowPrecise() or time(),
        dir       = "send",            -- s'affiche dans la liste « Envoyés »
        type      = tname,
        size      = #payload,

        chan      = "LOCAL", channel = "LOCAL", dist = "LOCAL",
        target    = me, from = me, sender = me, emitter = me,

        seq       = 0, part = 1, total = 1,
        raw       = raw,               -- ✅ exploité par groupLogs() → fullPayload
        state     = "sent", status = "sent", stateText = "|cffffd200Debug|r",
    }
    if ns.Emit then ns.Emit("debug:changed") end
end

-- ===== Nettoyage périodique =====
function GLOG.CleanupDebugLogs()
    -- Purge les index de réception orphelins (ligne supprimée du ring-buffer ou mismatch)
    for s, idx in pairs(RecvLogIndexBySeq) do
        local r = DebugLog[idx]
        if not r or r.seq ~= s then
            RecvLogIndexBySeq[s] = nil
        end
    end
    
    -- Purge les index d'envoi orphelins
    for s, idx in pairs(SendLogIndexBySeq) do
        local r = DebugLog[idx]
        if not r or r.seq ~= s then
            SendLogIndexBySeq[s] = nil
        end
    end

    -- Allègement des vieux logs : on retire le payload 'raw' > 15s
    local stripBefore = now() - 15
    for _, r in ipairs(DebugLog or {}) do
        if (r.ts or 0) < stripBefore and r.raw ~= nil then 
            r.raw = nil 
        end
    end
end

-- ===== Helpers pour la compatibilité =====
GLOG.pushLog = pushLog
GLOG._updateSendLog = _updateSendLog
GLOG.SendLogIndexBySeq = SendLogIndexBySeq
GLOG.RecvLogIndexBySeq = RecvLogIndexBySeq

-- ✅ Export de DebugLog comme alias vers pushLog (attendu par le validator)
GLOG.DebugLog = pushLog

-- Fonctions globales pour compatibilité
pushLog = pushLog
_updateSendLog = _updateSendLog
SendLogIndexBySeq = SendLogIndexBySeq
RecvLogIndexBySeq = RecvLogIndexBySeq

-- Export global de la fonction DebugLog (éviter conflit avec variable locale)
if not _G.DebugLog then
    _G.DebugLog = pushLog
end
