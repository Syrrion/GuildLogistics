-- Module de transport réseau bas niveau pour GuildLogistics
-- Gère la fragmentation, la file d'attente, l'envoi et le réassemblage des messages

local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
local GLOG = ns.GLOG

-- Références aux utilitaires centralisées
local U = ns.Util or {}
local safenum = U.safenum
local now = U.now
local playerFullName = U.playerFullName

-- ===== Constantes =====
local PREFIX   = "GLOG2"
local MAX_PAY  = 215   -- fragmentation des messages
local Seq      = 0     -- séquence réseau

-- Limitation d'émission (paquets / seconde)
local OUT_MAX_PER_SEC = 2

-- Seau de jetons global pour limiter tous les envois (toutes files confondues)
-- Cap de burst = 1 → pas de rafale, intervalle régulier
local _tb_tokens = 0
local _tb_lastRefill = 0
local OUT_BURST_CAP = 1

-- ===== État du transport =====
-- File d'envoi temporisée
local OutQ      = {}
local OutTicker = nil

-- Boîtes aux lettres (réassemblage fragments)
local Inbox     = {}

-- 🔁 Anti-doublon : clé = "seq@sender" (TTL court, purgé par ticker)
local Processed = {}   -- [ "123@nom-realm" ] = ts

-- ➕ Suivi d'une synchro FULL en cours par émetteur (pour piloter l'UI)
local ActiveFullSync = {}   -- [senderKey]=true

-- ===== Gestion de la file d'attente =====
local function _ensureTicker()
    if OutTicker then return end
    local last = 0
    local idle = 0   -- compte les ticks "sans travail"

    OutTicker = C_Timer.NewTicker(0.1, function()
        -- Utilise un temps relatif haute résolution pour le throttling (seau de jetons global)
        local t = (type(GetTimePreciseSec) == "function" and GetTimePreciseSec())
               or (type(GetTime) == "function" and GetTime())
               or 0

        if OUT_MAX_PER_SEC > 0 then
            if _tb_lastRefill == 0 then _tb_lastRefill = t end
            local dt = t - _tb_lastRefill
            if dt > 0 then
                _tb_tokens = math.min(OUT_BURST_CAP, _tb_tokens + dt * OUT_MAX_PER_SEC)
                _tb_lastRefill = t
            end
            if _tb_tokens < 1 then
                return -- pas assez de jetons, attendre le prochain tick
            end
        end

        local item = table.remove(OutQ, 1)
        if not item then
            idle = idle + 1
            -- Éteint le ticker après ~3s sans travail (30 ticks)
            if idle >= 30 then
                if OutTicker and OutTicker.Cancel then OutTicker:Cancel() end
                OutTicker = nil
            end
            return
        end
        idle = 0

        C_ChatInfo.SendAddonMessage(item.prefix, item.payload, item.channel, item.target)

        -- Consommer 1 jeton après envoi effectif
        if OUT_MAX_PER_SEC > 0 then
            _tb_tokens = math.max(0, _tb_tokens - 1)
        end

        -- Journalisation fragment envoyé (délégué au module de logging)
        if GLOG.PushLog then
            GLOG.PushLog("send", item.type, #item.payload, item.channel, item.target or "", 
                        item.seq, item.part, item.total, item.payload)
        end

        -- Nettoyer l'index d'envoi si c'est le dernier fragment
        if item.part == item.total and GLOG.SendLogIndexBySeq then
            GLOG.SendLogIndexBySeq[item.seq] = nil
        end
    end)
end

-- ===== Fonction d'envoi bas niveau =====
local function _send(typeName, channel, target, kv)
    kv = kv or {}
    Seq = Seq + 1
    kv.t = typeName
    kv.s = Seq

    -- Sérialisation via le module de sérialisation
    local payload = ""
    if GLOG.PackPayloadStr then
        payload = GLOG.PackPayloadStr(kv)
    end

    -- Fragmentation
    local parts = {}
    local i = 1
    while i <= #payload do
        parts[#parts+1] = payload:sub(i, i + MAX_PAY - 1)
        i = i + MAX_PAY
    end

    -- Trace "pending" (part=0), puis mémorise l'index pour mises à jour suivantes
    if GLOG.PushLog then
        GLOG.PushLog("send", typeName, #payload, channel, target or "", Seq, 0, #parts, "<queued>")
        -- Mémoriser l'index pour les mises à jour (délégué au module de logging)
        if GLOG.SendLogIndexBySeq then
            GLOG.SendLogIndexBySeq[Seq] = GLOG.GetDebugLogs and #GLOG.GetDebugLogs() or 0
        end
    end

    -- Ajout à la file d'attente
    for idx, chunk in ipairs(parts) do
        local header = string.format("v=1|t=%s|s=%d|p=%d|n=%d|", typeName, Seq, idx, #parts)
        local msg = header .. chunk
        OutQ[#OutQ+1] = {
            prefix = PREFIX, payload = msg, channel = channel, target = target,
            type = typeName, seq = Seq, part = idx, total = #parts
        }
    end
    _ensureTicker()
end

-- ===== API publiques d'envoi =====
function GLOG.Comm_Broadcast(typeName, kv)
    kv = kv or {}
    -- Injecter la version sur TOUTES les transactions sortantes (guilde)
    if kv.ver == nil then
        local ver = (GLOG.GetAddonVersion and GLOG.GetAddonVersion()) or ""
        if ver ~= "" then kv.ver = ver end
    end
    _send(typeName, "GUILD", nil, kv)
end

function GLOG.Comm_Whisper(target, msgType, data)
    data = data or {}
    -- Injecter la version sur TOUT whisper sortant
    if data.ver == nil then
        local ver = (GLOG.GetAddonVersion and GLOG.GetAddonVersion()) or ""
        if ver ~= "" then data.ver = ver end
    end

    _send(msgType, "WHISPER", target, data)
    return true
end

-- ===== Réception et réassemblage =====
function GLOG.OnAddonMessage(prefix, message, channel, sender)
    if prefix ~= PREFIX then return end
    
    -- Extraire le type de message pour la logique de filtrage
    local peekType = message:match("v=1|t=([^|]+)|")
    
    -- ✅ Vérification simple : le transport doit être initialisé
    if not GLOG._transportReady then 
        return -- Transport pas prêt du tout
    end

    -- ➕ Mode bootstrap : si la DB locale est en version 0, ne traiter QUE les messages "SYNC_*" et quelques autres critiques
    do
        local rev0 = safenum((GuildLogisticsDB and GuildLogisticsDB.meta and GuildLogisticsDB.meta.rev), 0)
        if rev0 == 0 then
            local pt = tostring(peekType or "")
            local bootstrapAcceptedTypes = {
                ["HELLO"] = true,
                ["SYNC_OFFER"] = true,
                ["SYNC_GRANT"] = true,
                ["SYNC_FULL"] = true,
                ["SYNC_ACK"] = true,
                ["STATUS_UPDATE"] = true -- Accepté même en bootstrap pour les réponses HELLO
            }
            if not bootstrapAcceptedTypes[pt] then return end
        end
    end

    local t, s, p, n = message:match("v=1|t=([^|]+)|s=(%d+)|p=(%d+)|n=(%d+)|")

    local seq  = safenum(s, 0)
    local part = safenum(p, 1)
    local total= safenum(n, 1)

    -- ➕ Affiche l'indicateur dès le 1er fragment d'un SYNC_FULL
    if t == "SYNC_FULL" and part == 1 then
        local senderKey = (ns.Util and ns.Util.NormalizeFull and ns.Util.NormalizeFull(sender)) or tostring(sender or "")
        if not ActiveFullSync[senderKey] then
            ActiveFullSync[senderKey] = true
            if ns and ns.Emit then ns.Emit("sync:begin", "full") end
        end
    end

    -- Journalisation de réception (délégué au module de logging)
    if GLOG.PushLog then
        -- ➜ Registre/MAJ d'une ligne unique par séquence pour l'UI
        local idx = GLOG.RecvLogIndexBySeq and GLOG.RecvLogIndexBySeq[seq]
        local logs = GLOG.GetDebugLogs and GLOG.GetDebugLogs() or {}
        
        if idx and logs[idx] then
            local r = logs[idx]
            -- Mise à jour de l'entrée existante
            r.ts      = (GetTimePreciseSec and GetTimePreciseSec()) or now()
            r.type    = t or r.type
            r.size    = #message
            r.chan    = channel or r.chan
            r.channel = channel or r.channel
            r.dist    = channel or r.dist
            r.target  = sender or r.target
            r.from    = sender or r.from
            r.sender  = sender or r.sender
            r.emitter = sender or r.emitter
            r.seq     = seq
            r.part    = part
            r.total   = total
            r.raw     = message
            r.state   = (part >= total) and "received" or "receiving"
            r.status  = r.state
            r.stateText = (r.state == "received") and "Reçu" or "En cours"

            if ns.Emit then ns.Emit("debug:changed") end
        else
            -- première trace pour cette séquence
            GLOG.PushLog("recv", t or "?", #message, channel, sender, seq, part, total, message, 
                        (part >= total) and "received" or "receiving")
            -- ⚠️ Ne crée pas d'index si le debug est OFF
            if GLOG.RecvLogIndexBySeq and not (GLOG and GLOG.IsDebugEnabled and not GLOG.IsDebugEnabled()) then
                GLOG.RecvLogIndexBySeq[seq] = #logs + 1
            end
        end

        -- ✅ Ajout : pour chaque fragment reçu après le premier, on journalise AUSSI ce fragment
        if part > 1 then
            GLOG.PushLog("recv", t or "?", #message, channel, sender, seq, part, total, message, 
                        (part >= total) and "received" or "receiving")
        end
    end

    if not t then return end

    local payload = message:match("|n=%d+|(.*)$") or ""

    -- ✅ Clé de réassemblage robuste : séquence + émetteur NORMALISÉ
    local senderKey = (ns.Util and ns.Util.NormalizeFull and ns.Util.NormalizeFull(sender)) or tostring(sender or "")
    local key = tostring(seq) .. "@" .. senderKey:lower()

    local box = Inbox[key]
    if not box then
        box = { total = total, got = 0, parts = {}, ts = now() }
        Inbox[key] = box
    else
        box.total = math.max(box.total or total, total)
    end
    box.ts = now()

    if not box.parts[part] then
        box.parts[part] = payload
        box.got = box.got + 1
    end

    if box.got >= box.total then
        -- Reconstitution
        local full = table.concat(box.parts, "")
        Inbox[key] = nil

        -- Libère l'entrée d'index liée à cette séquence
        if GLOG.RecvLogIndexBySeq then 
            GLOG.RecvLogIndexBySeq[seq] = nil 
        end

        -- ➕ Termine proprement l'indicateur en toute circonstance pour SYNC_FULL
        local function _finishSync(ok)
            if t == "SYNC_FULL" and ActiveFullSync[senderKey] then
                ActiveFullSync[senderKey] = nil
                if ns and ns.Emit then ns.Emit("sync:end", "full", ok) end
            end
        end

        if t then
            -- 🛡️ Déduplication par séquence@expéditeur
            local pkey = tostring(seq) .. "@" .. tostring(senderKey or ""):lower()
            if Processed[pkey] then
                _finishSync(true) -- termine proprement un éventuel indicateur
                return
            end
            Processed[pkey] = now()

            -- Décodage KV + transmission au handler principal
            local _ok, _err = pcall(function()
                local plain = ""
                if GLOG.UnpackPayloadStr then
                    plain = GLOG.UnpackPayloadStr(full)
                end
                
                local kv = {}
                if GLOG.DecodeKV then
                    kv = GLOG.DecodeKV(plain)
                end
                
                -- Déléguer au handler principal (qui sera défini dans un autre module)
                if GLOG.HandleMessage then
                    GLOG.HandleMessage(sender, t, kv)
                end
            end)
            _finishSync(_ok)
            if not _ok then
                local eh = geterrorhandler() or print
                eh(_err)
            end
        else
            _finishSync(true)
        end
    end
end

-- ===== Nettoyage périodique =====
function GLOG.CleanupTransport()
    local cutoff = now() - 30
    
    -- Nettoyage des fragments périmés
    for k, box in pairs(Inbox) do 
        if (box.ts or 0) < cutoff then 
            Inbox[k] = nil 
        end 
    end
    
    -- 🔁 Purge des messages déjà vus (anti-doublon)
    for k, ts in pairs(Processed) do 
        if (ts or 0) < cutoff then 
            Processed[k] = nil 
        end 
    end
end

-- ===== Initialisation =====
function GLOG.InitTransport()
    if GLOG._transportReady then return end
    GLOG._transportReady = true
    
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    
    -- Créer le frame d'écoute des messages addon
    if not GLOG._transportFrame then
        GLOG._transportFrame = CreateFrame("Frame")
        GLOG._transportFrame:RegisterEvent("CHAT_MSG_ADDON")
        GLOG._transportFrame:SetScript("OnEvent", function(self, event, prefix, message, channel, sender)
            if event == "CHAT_MSG_ADDON" and prefix == PREFIX then
                if GLOG.OnAddonMessage and type(GLOG.OnAddonMessage) == "function" then
                    GLOG.OnAddonMessage(prefix, message, channel, sender)
                else
                    print("Erreur: GLOG.OnAddonMessage non trouvé lors de la réception de message")
                end
            end
        end)
    end
    
    -- Nettoyage périodique
    if not GLOG._transportCleaner then
        GLOG._transportCleaner = C_Timer.NewTicker(10, function()
            GLOG.CleanupTransport()
        end)
    end
end

function GLOG.StopTransport()
    if GLOG._transportFrame then
        GLOG._transportFrame:UnregisterAllEvents()
        GLOG._transportFrame = nil
    end
    
    if GLOG._transportCleaner then
        GLOG._transportCleaner:Cancel()
        GLOG._transportCleaner = nil
    end
    
    if OutTicker then
        OutTicker:Cancel()
        OutTicker = nil
    end
    
    GLOG._transportReady = false
end

-- ===== API publiques pour statistiques =====
function GLOG.GetTransportStats()
    local function len(t) local n=0; for _ in pairs(t or {}) do n=n+1 end; return n end
    return {
        outq = #OutQ,
        inbox = len(Inbox),
        processed = len(Processed),
        activeFullSync = len(ActiveFullSync),
    }
end

-- ===== Helpers pour compatibilité =====
GLOG.Inbox = Inbox
GLOG.OutQ = OutQ
GLOG.ActiveFullSync = ActiveFullSync
GLOG.Processed = Processed

-- Export des fonctions principales
GLOG._send = _send
-- OnAddonMessage est déjà définie comme GLOG.OnAddonMessage
-- InitTransport, StopTransport et CleanupTransport sont déjà définies comme GLOG.fonctions

-- Fonctions globales pour compatibilité
Inbox = Inbox
OutQ = OutQ
ActiveFullSync = ActiveFullSync
Processed = Processed
_send = _send
-- OnAddonMessage globale pour compatibilité avec l'ancien code
OnAddonMessage = function(prefix, message, channel, sender)
    if GLOG.OnAddonMessage then
        return GLOG.OnAddonMessage(prefix, message, channel, sender)
    end
end
