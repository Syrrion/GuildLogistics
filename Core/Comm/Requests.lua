-- Module de gestion des demandes TX_REQ pour GuildLogistics
-- Gère l'envoi de demandes d'ajustement et leur mise en file d'attente

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

-- ===== Gestion des demandes entrantes (côté GM) =====
function GLOG.AddIncomingRequest(kv)
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.requests = GuildLogisticsDB.requests or {}
    local list = GuildLogisticsDB.requests
    local id = tostring(kv.uid or "") .. ":" .. tostring(kv.ts or now())
    list[#list+1] = {
        id = id, uid = kv.uid, delta = safenum(kv.delta,0),
        who = kv.who or kv.requester or "?", ts = safenum(kv.ts, now()),
    }
    if ns.Emit then ns.Emit("requests:changed") end
end

function GLOG.ResolveRequest(id, accepted, by)
    GuildLogisticsDB = GuildLogisticsDB or {}
    local list = GuildLogisticsDB.requests or {}
    local kept = {}
    for _, req in ipairs(list) do
        if req.id ~= id then kept[#kept+1] = req end
    end
    GuildLogisticsDB.requests = kept
    if ns.Emit then ns.Emit("requests:changed") end
end

-- ===== Envoi de demandes d'ajustement (côté client) =====
function GLOG.RequestAdjust(a, b, ctx)
    -- Compat : UI appelle (name, delta) ; ancienne forme : (delta)
    local delta = (b ~= nil) and safenum(b, 0) or safenum(a, 0)
    if delta == 0 then return end

    local me  = playerFullName()
    local uid = GLOG.GetOrAssignUID and GLOG.GetOrAssignUID(me)
    if not uid then return end

    local payload = { uid = uid, delta = delta, who = me, ts = now(), reason = (ctx and ctx.reason) or "CLIENT_REQ" }

    -- Heuristique temps-réel : considérer "en ligne" si vu récemment via HELLO
    local function _masterSeenRecently(name)
        local nf = (ns and ns.Util and ns.Util.NormalizeFull) and ns.Util.NormalizeFull or tostring
        local target = nf(name or "")

        -- 1) On a reçu un HELLO tout juste du GM et on attend le flush
        if GLOG._awaitHelloFrom and nf(GLOG._awaitHelloFrom) == target then
            return true
        end

        -- 2) Élection HELLO récente où le gagnant est le GM (fenêtre ~60s)
        local nowt = now()
        local HelloElect = GLOG.HelloElect or {}
        for _, sess in pairs(HelloElect) do
            if sess and sess.decided and sess.winner then
                if nf(sess.winner) == target then
                    local stamp = safenum(sess.endsAt or sess.startedAt or 0, 0)
                    if (nowt - stamp) <= 60 then
                        return true
                    end
                end
            end
        end
        return false
    end

    -- Étape commune (décision après lecture du roster à jour)
    local function decideAndSend()
        -- Cible = GM effectif (rang 0 du roster) — relu depuis le cache fraîchement scanné
        local gmName, gmRow = GLOG.GetGuildMasterCached and GLOG.GetGuildMasterCached() or nil, nil
        if type(gmName) == "table" and not gmRow then gmName, gmRow = gmName[1], gmName[2] end
        if not gmRow and GLOG.GetGuildMasterCached then gmName, gmRow = GLOG.GetGuildMasterCached() end

        local onlineNow = false
        if gmName then
            onlineNow = (gmRow and gmRow.online) or _masterSeenRecently(gmName)
        end

        if gmName and onlineNow then
            -- GM réellement disponible : envoi direct
            if GLOG.Comm_Whisper then
                GLOG.Comm_Whisper(gmName, "TX_REQ", payload)
            end
        else
            -- GM hors-ligne ou inconnu : persiste → flush auto sur HELLO
            if GLOG.Pending_AddTXREQ then GLOG.Pending_AddTXREQ(payload) end
            if UIErrorsFrame and UIErrorsFrame.AddMessage then
                UIErrorsFrame:AddMessage("|cffffff80[GLOG]|r GM hors-ligne : demande mise en file d'attente.", 1, 0.9, 0.4)
            end
            if ns.Emit then ns.Emit("debug:changed") end
        end
    end

    -- Nouveau : rafraîchir le roster AVANT la décision d'envoi
    if GLOG.RefreshGuildCache then
        GLOG.RefreshGuildCache(function() decideAndSend() end)
    else
        -- Fallback si jamais la fonction n'existe pas
        decideAndSend()
    end
end

-- ===== File d'attente persistante des TX_REQ (client) =====
function GLOG.Pending_AddTXREQ(kv)
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.pending = GuildLogisticsDB.pending or {}
    local P = GuildLogisticsDB.pending
    P.txreq = P.txreq or {}
    kv = kv or {}
    kv.id = kv.id or (tostring(now()) .. "-" .. tostring(math.random(1000,9999)))
    kv.ts = kv.ts or now() -- horodatage pour l'affichage Pending
    table.insert(P.txreq, kv)
    if ns.Emit then ns.Emit("pending:changed") end
end

function GLOG.Pending_ListTXREQ()
    local P = GuildLogisticsDB and GuildLogisticsDB.pending
    return (P and P.txreq) or {}
end

function GLOG.Pending_ClearTXREQ()
    local P = GuildLogisticsDB and GuildLogisticsDB.pending
    if P then P.txreq = {} end
    if ns.Emit then ns.Emit("pending:changed") end
end

-- ===== File d'attente persistante des ERR_REPORT (client) =====
function GLOG.Pending_AddERRRPT(rep)
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.pending = GuildLogisticsDB.pending or {}
    local P = GuildLogisticsDB.pending
    P.err = P.err or {}
    
    rep = rep or {}
    local currentTime = (time and time()) or 0
    rep.id = rep.id or (tostring(currentTime) .. "-" .. tostring(math.random(1000,9999)))
    rep.ts = rep.ts or currentTime -- horodatage pour l'affichage Pending
    
    table.insert(P.err, rep)
    
    if ns.Emit then 
        ns.Emit("pending:changed") 
    end
end

-- ===== Flush des demandes en attente =====
function GLOG.Pending_FlushTXREQ(targetGM)
    local P = GuildLogisticsDB and GuildLogisticsDB.pending
    local list = (P and P.txreq) or {}
    
    if #list == 0 then return end
    
    local flushed = 0
    for _, req in ipairs(list) do
        if GLOG.Comm_Whisper then
            GLOG.Comm_Whisper(targetGM, "TX_REQ", req)
            flushed = flushed + 1
        end
    end
    
    if flushed > 0 then
        GLOG.Pending_ClearTXREQ()
        if UIErrorsFrame and UIErrorsFrame.AddMessage then
            UIErrorsFrame:AddMessage(string.format("|cffffff80[GLOG]|r %d demande(s) envoyée(s) au GM.", flushed), 0.4, 1, 0.4)
        end
    end
end

-- ===== Flush global des demandes en attente =====
function GLOG.Pending_FlushToMaster(master)
    local P = GuildLogisticsDB and GuildLogisticsDB.pending or {}
    if not P then 
        return 0 
    end

    -- Destinataire par défaut : GM effectif (rang 0)
    if not master or master == "" then
        if GLOG.GetGuildMasterCached then master = select(1, GLOG.GetGuildMasterCached()) end
    end
    if not master or master == "" then 
        return 0 
    end

    -- Vérifier si le GM est vraiment en ligne avant de flush
    local gmOnline = (GLOG.IsMasterOnline and GLOG.IsMasterOnline()) or false
    if not gmOnline then
        -- GM pas en ligne, ne pas flush - garder en attente
        return 0
    end

    local sent = 0

    -- 1) Flush des TX_REQ
    if P.txreq and #P.txreq > 0 then
        local sentTxReq = {}
        for i = 1, #P.txreq do
            local kv = P.txreq[i]
            if kv and GLOG.Comm_Whisper then
                GLOG.Comm_Whisper(master, "TX_REQ", kv)
                sent = sent + 1
                sentTxReq[#sentTxReq + 1] = i
            end
        end
        -- Supprimer seulement les éléments envoyés avec succès
        for j = #sentTxReq, 1, -1 do
            table.remove(P.txreq, sentTxReq[j])
        end
    end

    -- 2) Flush des rapports d'erreurs
    if P.err and #P.err > 0 then
        local sentErr = {}
        for i = 1, #P.err do
            local kv = P.err[i]
            if kv and GLOG.Comm_Whisper then
                GLOG.Comm_Whisper(master, "ERR_REPORT", kv)
                sent = sent + 1
                sentErr[#sentErr + 1] = i
            end
        end
        -- Supprimer seulement les éléments envoyés avec succès
        for j = #sentErr, 1, -1 do
            table.remove(P.err, sentErr[j])
        end
    end

    if ns.Emit then ns.Emit("debug:changed") end
    return sent
end

-- ===== Helpers pour compatibilité =====
-- Fonctions globales pour compatibilité
RequestAdjust = GLOG.RequestAdjust
AddIncomingRequest = GLOG.AddIncomingRequest
ResolveRequest = GLOG.ResolveRequest
