-- Module de découverte et synchronisation réseau pour GuildLogistics
-- Gère le handshake HELLO/OFFER/GRANT/FULL/ACK et la découverte de pairs

local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
local GLOG = ns.GLOG

-- Références aux utilitaires centralisées
local U = ns.Util or {}
local safenum = U.safenum
local now = U.now
local normalizeStr = U.normalizeStr
local playerFullName = U.playerFullName
local getRev = (U and U.getRev) or function() local db=GuildLogisticsDB; return (db and db.meta and db.meta.rev) or 0 end

-- ===== Constantes de découverte =====
local HELLO_WAIT_SEC          = 4.0        -- fenêtre collecte OFFERS (+1s)
local OFFER_BACKOFF_MS_MAX    = 50         -- étalement OFFERS (0..50ms)
local FULL_INHIBIT_SEC        = 1          -- n'offre pas si FULL récent vu
local OFFER_RATE_LIMIT_SEC    = 1          -- anti-spam OFFERS par initiateur
local GM_EXTRA_WAIT_SEC       = 0.5        -- prolongation si GM en ligne mais pas encore d'OFFERS du GM

-- ===== État de la découverte =====
local LastFullSeenAt  = 0
local LastFullSeenRv  = -1
local LastGMFullAt    = 0
local LastGMFullRv    = -1

-- Suivi Debug de la découverte
local HelloElect = {}   -- [hid] = { startedAt, endsAt, decided, winner, token, offers, applied }

-- Sessions initiées localement
-- [hid] = { initiator=me, rv_me, decided=false, endsAt, offers={[normName]={player,rv,est,h}}, grantedTo, token, reason }
local Discovery = {}

-- Cooldown d'OFFERS par initiateur
-- [normInitiator] = lastTs
local OfferCooldown = {}
-- Cooldown de réponse HELLO->HELLO (par cible) pour éviter le ping-pong
local HelloReplyCooldown = {}

-- Petits utilitaires
local function _norm(s) return normalizeStr(s or "") end

-- ===== Fonctions de découverte =====
local function _registerOffer(hid, player, rv, est, h)
    Discovery[hid] = Discovery[hid] or {}
    local sess = Discovery[hid]
    sess.offers = sess.offers or {}
    sess.offers[_norm(player)] = { player = player, rv = safenum(rv, -1), est = safenum(est, 0), h = safenum(h, 0) }
    HelloElect[hid] = HelloElect[hid] or { startedAt = now(), endsAt = now() + HELLO_WAIT_SEC, decided = false, offers = 0 }
    HelloElect[hid].offers = (HelloElect[hid].offers or 0) + 1
    if ns.Emit then ns.Emit("debug:changed") end
end

local function _decideAndGrant(hid)
    local sess = Discovery[hid]
    if not sess or sess.grantedTo then return end
    sess.decided = true

    local rv_me = safenum(sess.rv_me, 0)

    -- Si FULL "récent" vu → on n'annule QUE s'il n'existe aucune offre strictement meilleure
    local fullSeen = (LastFullSeenRv or -1) >= rv_me and (now() - (LastFullSeenAt or 0)) < HELLO_WAIT_SEC
    local hasBetter = false
    do
        local offers = sess.offers or {}
        for _, o in pairs(offers) do
            if safenum(o.rv, -1) > rv_me then hasBetter = true; break end
        end
    end
    if fullSeen and not hasBetter then
        HelloElect[hid] = HelloElect[hid] or {}
        HelloElect[hid].decided = true
        HelloElect[hid].winner  = nil
        if ns.Emit then ns.Emit("debug:changed") end
        Discovery[hid] = nil
        return
    end

    local offers = sess.offers or {}

    -- ➕ Si le GM est EN LIGNE mais qu'aucune offre du GM n'est présente, prolonge l'attente une fois
    local function _isGM(name)
        if not name or name == "" then return false end
        if GLOG.IsNameGuildMaster then return GLOG.IsNameGuildMaster(name) end
        if GLOG.GetGuildMasterCached and GLOG.NormName then
            local gm = select(1, GLOG.GetGuildMasterCached())
            if gm and gm ~= "" then return GLOG.NormName(name) == GLOG.NormName(gm) end
        end
        return false
    end
    local gmOfferPresent = false
    for _, o in pairs(offers) do
        if _isGM(o.player) then gmOfferPresent = true; break end
    end
    if not gmOfferPresent and (GLOG.IsMasterOnline and GLOG.IsMasterOnline()) and not sess.gmWaitExtended then
        sess.gmWaitExtended = true
        HelloElect[hid] = HelloElect[hid] or {}
        HelloElect[hid].endsAt = (HelloElect[hid].endsAt or now()) + GM_EXTRA_WAIT_SEC
        if ns.Emit then ns.Emit("debug:changed") end
        -- ⏳ attend encore un peu pour laisser le GM répondre
        C_Timer.After(GM_EXTRA_WAIT_SEC, function() _decideAndGrant(hid) end)
        return
    end

    -- ✅ Priorité GM si présent dans les offres
    local chosen = nil
    for _, o in pairs(offers) do
        if not chosen then
            chosen = o
        else
            local ogm = _isGM(o.player)
            local cgm = _isGM(chosen.player)
            if ogm and not cgm then
                chosen = o                                -- GM prioritaire
            elseif (ogm == cgm) then
                -- tri existant : meilleure révision, puis plus "léger", puis tiebreaker
                if (o.rv > chosen.rv)
                or (o.rv == chosen.rv and o.est < chosen.est)
                or (o.rv == chosen.rv and o.est == chosen.est and o.h > chosen.h)
                then chosen = o end
            end
        end
    end

    if not chosen then
        HelloElect[hid] = HelloElect[hid] or {}
        HelloElect[hid].decided = true
        HelloElect[hid].winner  = nil
        if ns.Emit then ns.Emit("debug:changed") end
        Discovery[hid] = nil
        return
    end

    -- Jeton pseudo-aléatoire : timestamp + 8 hex "safe"
    local token = string.format("%d-%s", now(), (GLOG.RandHex8 and GLOG.RandHex8()) or "deadbeef")
    sess.token     = token
    sess.grantedTo = chosen.player

    HelloElect[hid] = HelloElect[hid] or {}
    HelloElect[hid].winner  = chosen.player
    HelloElect[hid].token   = token
    HelloElect[hid].decided = true
    if ns.Emit then ns.Emit("debug:changed") end

    -- Envoi du GRANT via le module de transport
    if GLOG.Comm_Whisper then
        GLOG.Comm_Whisper(chosen.player, "SYNC_GRANT", {
            hid   = hid,
            token = token,
            init  = sess.initiator,
            m     = sess.reason or "rv_gap",
        })
    end
    
    -- On garde 5s pour l'affichage éventuel, puis on libère l'élection de la mémoire
    C_Timer.After(5, function()
        if HelloElect then HelloElect[hid] = nil end
        if ns and ns.Emit then ns.Emit("debug:changed") end
    end)
end

local function _scheduleOfferReply(hid, initiator, rv_init, ver_them)
    -- Inhibition si FULL récent ≥ mon rv
    local iAmGM = (GLOG.IsNameGuildMaster and GLOG.IsNameGuildMaster(playerFullName())) or false
    if not iAmGM then
        if (now() - (LastFullSeenAt or 0)) < FULL_INHIBIT_SEC and (LastFullSeenRv or -1) >= safenum(getRev(), 0) then
            return
        end
    end

    -- Anti-spam par initiateur (conservé même pour GM)
    local k = _norm(initiator)
    local last = OfferCooldown[k] or 0
    if (now() - last) < OFFER_RATE_LIMIT_SEC then return end
    OfferCooldown[k] = now()

    local myRv  = safenum(getRev(), 0)
    local est   = GLOG.EstimateSnapshotSize and GLOG.EstimateSnapshotSize() or 0
    local h     = (GLOG.HashHint and GLOG.HashHint(string.format("%s|%d|%s", playerFullName(), myRv, hid))) or 0
    
    -- Le GM répond sans jitter pour passer devant tout le monde
    local delay = iAmGM and 0 or (math.random(0, OFFER_BACKOFF_MS_MAX) / 1000.0)

    if ns.Util and ns.Util.After then
        ns.Util.After(delay, function()
            local rv_peer = safenum(getRev(), 0)

            -- Ne proposer que si l'on est réellement plus à jour que l'initiateur
            if rv_peer <= safenum(rv_init, 0) then return end

            -- Double-vérif d'inhibition tout près de l'envoi (sauf GM)
            if not iAmGM then
                if (now() - (LastFullSeenAt or 0)) < FULL_INHIBIT_SEC and (LastFullSeenRv or -1) >= rv_peer then
                    return
                end
            end

            if GLOG.Comm_Whisper then
                GLOG.Comm_Whisper(initiator, "SYNC_OFFER", {
                    hid  = hid,
                    rv   = rv_peer,
                    est  = est,
                    h    = h,
                    from = playerFullName(),
                    m    = "rv_gap",
                })
            end
        end)
    end
end

-- ===== Handlers de découverte =====
function GLOG.HandleHello(sender, kv)
    local hid     = kv.hid or ""
    local rv_me   = safenum(getRev(), 0)
    local rv_them = safenum(kv.rv, -1)

    -- ➕ Comparaison de versions d'addon (si fournie)
    local ver_me   = (GLOG.GetAddonVersion and GLOG.GetAddonVersion()) or ""
    local ver_them = tostring(kv.ver or "")

    -- (revert) Pas de HELLO de guilde auto ici

    if rv_me > rv_them and GLOG._suppressTo then
        GLOG._suppressTo(sender, (HELLO_WAIT_SEC or 5) + 2)
    end

    if hid ~= "" and sender and sender ~= "" then
        _scheduleOfferReply(hid, sender, rv_them, ver_them)
    end

    local v_hello = tostring(kv.ver or "")
    if v_hello ~= "" and GLOG.SetPlayerAddonVersion then 
        GLOG.SetPlayerAddonVersion(sender, v_hello, tonumber(kv.ts) or time(), sender) 
    end

    -- Gestion du flush TX_REQ vers le GM (code existant conservé)
    local nf = (ns and ns.Util and ns.Util.NormalizeFull) and ns.Util.NormalizeFull or tostring
    local gmName = GLOG.GetGuildMasterCached and select(1, GLOG.GetGuildMasterCached())
    local senderNF = nf(sender)

    if gmName and senderNF == nf(gmName) then
        if GLOG.Pending_FlushToMaster then GLOG.Pending_FlushToMaster(gmName) end
    else
        -- Roster possiblement pas prêt : on retente quelques fois (délais 1s)
        GLOG._awaitHelloFrom = senderNF
        GLOG._awaitHelloRetry = 0
        local function _tryFlushLater()
            if not GLOG._awaitHelloFrom then return end
            local gm = GLOG.GetGuildMasterCached and select(1, GLOG.GetGuildMasterCached())
            if gm and GLOG._awaitHelloFrom == nf(gm) then
                if GLOG.Pending_FlushToMaster then GLOG.Pending_FlushToMaster(gm) end
                GLOG._awaitHelloFrom = nil
                return
            end
            GLOG._awaitHelloRetry = (GLOG._awaitHelloRetry or 0) + 1
            if GLOG._awaitHelloRetry < 5 then
                if C_Timer and C_Timer.After then C_Timer.After(1, _tryFlushLater) end
            else
                GLOG._awaitHelloFrom = nil
            end
        end
        if C_Timer and C_Timer.After then C_Timer.After(1, _tryFlushLater) end
    end
    
    -- ===== Réponse HELLO (WHISPER) =====
    do
        -- Éviter le ping-pong: ne pas répondre à notre propre HELLO et appliquer un petit cooldown par cible
        local nf = (ns and ns.Util and ns.Util.NormalizeFull) and ns.Util.NormalizeFull or tostring
        local me = playerFullName()
        -- IMPORTANT: ne jamais répondre à un HELLO reçu en privé (WHISPER)
        local incomingChannel = tostring(kv._ch or "")
        local isGuild = (incomingChannel == "GUILD")
        if isGuild and nf(sender) ~= nf(me) then
            local key = nf(sender)
            local last = HelloReplyCooldown[key] or 0
            local COOLDOWN = 1.0
            if (now() - last) > COOLDOWN then
                if GLOG.Comm_Whisper then
                    local meFull = me
                    local myRv = safenum(getRev(), 0)
                    GLOG.Comm_Whisper(sender, "HELLO", {
                        hid = hid,
                        rv = myRv,
                        player = meFull,
                        caps = {"OFFER","GRANT","TOKEN1"},
                        ver = (GLOG.GetAddonVersion and GLOG.GetAddonVersion()) or "",
                        reply = true,
                    })
                    HelloReplyCooldown[key] = now()
                end
            end
        end
    end

    -- ===== Réponse STATUS_UPDATE au HELLO =====
    -- Envoyer notre statut mis à jour (iLvl, clé M+, etc.) en réponse au HELLO
    -- IMPORTANT: ne PAS répondre si le HELLO a été reçu en WHISPER (uniquement si reçu via GUILD)
    do
        local incomingChannel = tostring(kv._ch or "")
        if incomingChannel ~= "GUILD" then
            -- Ne pas envoyer de STATUS_UPDATE en réponse à un HELLO en WHISPER
            return
        end

        local me = playerFullName()
        local meta = GuildLogisticsDB and GuildLogisticsDB.meta
        local myRv = safenum(meta and meta.rev, 0)
        
        -- 🚫 Ne pas s'envoyer de STATUS_UPDATE à soi-même
        local nf = (ns and ns.Util and ns.Util.NormalizeFull) and ns.Util.NormalizeFull or tostring
        if nf(sender) == nf(me) then
            return -- Éviter l'auto-envoi
        end
        
        -- Ne pas répondre si le sender a une DB obsolète
        local senderRv = safenum(kv.rv, 0)
        --if myRv > 0 and senderRv >= myRv then
            -- Anti-doublon : 1 seul STATUS_UPDATE par cible dans la foulée du HELLO
            local HelloStatusSentTo = GLOG.HelloStatusSentTo or {}
            GLOG.HelloStatusSentTo = HelloStatusSentTo
            local nf = (ns and ns.Util and ns.Util.NormalizeFull) and ns.Util.NormalizeFull or tostring
            local key = nf(sender)
            local last = HelloStatusSentTo[key] or 0
            local HELLO_STATUS_CD_SEC = 1.0
            
            if (now() - last) > HELLO_STATUS_CD_SEC then
                -- Créer un payload unifié avec tableau S
                if GLOG.CreateStatusUpdatePayload and GLOG.Comm_Whisper then
                    local payload = GLOG.CreateStatusUpdatePayload({ ts = now(), by = me })
                    if payload then
                        GLOG.Comm_Whisper(sender, "STATUS_UPDATE", payload)
                        HelloStatusSentTo[key] = now()
                    end
                end
            end
        --end
    end
end

function GLOG.HandleSyncOffer(sender, kv)
    -- Côté initiateur : collecter les OFFERS pendant HELLO_WAIT
    local hid = kv.hid or ""
    local sess = Discovery[hid]

    -- (revert) Ne pas créer de session à la volée ici
    if hid ~= "" and sess and _norm(sess.initiator) == _norm(playerFullName()) then
        _registerOffer(hid, kv.from or sender, kv.rv, kv.est, kv.h)

        -- Si une offre STRICTEMENT meilleure que ma version arrive, décider tout de suite
        local offerRv = safenum(kv.rv, 0)
        if not sess.grantedTo and (offerRv > safenum(sess.rv_me, 0) or sess.decided) then
            C_Timer.After(0, function() _decideAndGrant(hid) end)
        end
    end
end

function GLOG.HandleSyncGrant(sender, kv)
    -- Reçu par le gagnant : envoyer un FULL ciblé avec token
    local hid   = kv.hid or ""
    local token = kv.token or ""
    local init  = kv.init or sender
    if hid ~= "" and token ~= "" and init and init ~= "" then
        local snap = (GLOG.SnapshotExport and GLOG.SnapshotExport()) or {}
        snap.hid   = hid
        snap.token = token
        if GLOG.Comm_Whisper then
            GLOG.Comm_Whisper(init, "SYNC_FULL", snap)
        end
    end
end

function GLOG.HandleSyncFull(sender, kv)
    -- Mémoriser la vue du FULL (anti-doublon & inhibitions)
    LastFullSeenAt = now()
    LastFullSeenRv = safenum(kv.rv, -1)

    -- ➕ Si l'émetteur est le GM, mémoriser aussi sa révision
    if GLOG.IsNameGuildMaster and GLOG.IsNameGuildMaster(sender) then
        LastGMFullAt = now()
        LastGMFullRv = safenum(kv.rv, -1)
    end

    -- ⛔ Ignore notre propre FULL (évite de ré-appliquer/vider localement chez le GM)
    do
        local senderKey = (ns.Util and ns.Util.NormalizeFull and ns.Util.NormalizeFull(sender)) or tostring(sender or "")
        local meKey     = (ns.Util and ns.Util.NormalizeFull and ns.Util.NormalizeFull(playerFullName())) or playerFullName()
        if senderKey == meKey then
            if GLOG.Debug then GLOG.Debug("RECV","SYNC_FULL","ignored self") end
            return false -- Indique qu'on a ignoré le message
        end
    end

    -- Le FULL finalise le handshake : lever la suppression pour l'émetteur
    if GLOG._suppressTo then
        GLOG._suppressTo(sender, -999999)
    end

    -- Vérifier jeton si une découverte locale est active
    local hid   = kv.hid or ""
    local token = kv.token or ""
    local okByToken = true
    local sess = Discovery[hid]
    if hid ~= "" and sess then
        okByToken = (token ~= "" and token == sess.token)
    end

    if not okByToken then return false end

    -- Vérifier si on doit appliquer (révision)
    local function shouldApply()
        local meta = GuildLogisticsDB and GuildLogisticsDB.meta
        local rv = safenum(kv.rv, -1)
        local myrv = safenum(meta and meta.rev, 0)
        local lm = safenum(kv.lm, -1)
        local mylm = safenum(meta and meta.lastModified, 0)
        
        if rv >= 0 then return rv >= myrv end
        if lm >= 0 then return lm >= mylm end
        return false
    end
    
    if not shouldApply() then return false end

    -- ➕ Indiquer à l'UI que la synchro débute, puis céder la main au frame suivant
    if ns and ns.Emit then ns.Emit("sync:begin", "full") end
    C_Timer.After(0, function()
        local _ok, _err = pcall(function()
            if GLOG.SnapshotApply then
                GLOG.SnapshotApply(kv)
            end
            
            -- Refresh UI
            if ns.UI and ns.UI.RefreshActive then 
                ns.UI.RefreshActive() 
            end

            -- ACK vers l'émetteur si token présent
            if hid ~= "" and token ~= "" and GLOG.Comm_Whisper then
                local meta = GuildLogisticsDB and GuildLogisticsDB.meta
                GLOG.Comm_Whisper(sender, "SYNC_ACK", { hid = hid, rv = safenum(meta and meta.rev, 0) })
                HelloElect[hid] = HelloElect[hid] or {}
                HelloElect[hid].applied = true
                if ns.Emit then ns.Emit("debug:changed") end
                Discovery[hid] = nil
            end
        end)

        -- ➕ Fin de synchro (ok/erreur)
        if ns and ns.Emit then ns.Emit("sync:end", "full", _ok) end

        -- ➕ Après application réussie du FULL : recalcul statut local du joueur
        if _ok then
            C_Timer.After(0.15, function()
                if GLOG.UpdateOwnStatusIfMain then GLOG.UpdateOwnStatusIfMain() end
            end)

            -- ➕ Puis rebroadcast d'un HELLO (GUILD)
            local hid2   = string.format("%d.%03d", time(), math.random(0, 999))
            local me     = playerFullName()
            local rv_me  = safenum(getRev(), 0)
            C_Timer.After(0.2, function()
                if GLOG.Comm_Broadcast then
                    GLOG.Comm_Broadcast("HELLO", {
                        hid = hid2, rv = rv_me, player = me, caps = {"OFFER","GRANT","TOKEN1"},
                        ver = (GLOG.GetAddonVersion and GLOG.GetAddonVersion()) or ""
                    })
                end
            end)

            C_Timer.After(0.5, function()
                -- ✅ Assure une entrée roster/réserve locale pour ne pas bloquer la diffusion
                local meNow = playerFullName()
                if GLOG.EnsureRosterLocal then GLOG.EnsureRosterLocal(meNow) end

                -- Statut unifié (iLvl + M+)
                if GLOG.BroadcastStatusUpdate then
                    local il  = GLOG.ReadOwnEquippedIlvl and GLOG.ReadOwnEquippedIlvl() or nil
                    local ilM = GLOG.ReadOwnMaxIlvl     and GLOG.ReadOwnMaxIlvl()     or nil
                    local mid, lvl, map = 0, 0, ""
                    if GLOG.ReadOwnedKeystone then mid, lvl, map = GLOG.ReadOwnedKeystone() end
                    if (not map or map == "" or map == "Clé") and safenum(mid,0) > 0 and GLOG.ResolveMKeyMapName then
                        local nm = GLOG.ResolveMKeyMapName(mid); if nm and nm ~= "" then map = nm end
                    end
                    GLOG.BroadcastStatusUpdate({
                        ilvl = il, ilvlMax = ilM,
                        mid = safenum(mid,0), lvl = safenum(lvl,0),
                        ts = time(), by = meNow,
                    })
                end
            end)
        end

        if not _ok then
            local eh = geterrorhandler() or print
            eh(_err)
        end
    end)
    
    return true -- Indique qu'on a traité le message
end

function GLOG.HandleSyncAck(sender, kv)
    -- Reçu par l'émetteur du FULL : fin de transfert (place à des métriques éventuelles)
    local hid = kv.hid or ""
    if hid ~= "" then
        -- no-op pour l'instant
    end
end

-- ===== API publique =====
function GLOG.Sync_RequestHello()
    -- Émet un HELLO léger (avec caps) et collecte les OFFERS pendant HELLO_WAIT,
    -- puis choisit un gagnant et envoie un GRANT (token) en WHISPER.
    local hid   = string.format("%d.%03d", time(), math.random(0, 999))
    local me    = playerFullName()
    local rv_me = safenum(getRev(), 0)

    Discovery[hid] = {
        initiator = me,
        rv_me     = rv_me,
        decided   = false,
        endsAt    = now() + HELLO_WAIT_SEC,
        offers    = {},
        reason    = "rv_gap",
    }

    HelloElect[hid] = { startedAt = now(), endsAt = now() + HELLO_WAIT_SEC, decided = false, offers = 0 }
    if ns.Emit then ns.Emit("debug:changed") end

    C_Timer.After(HELLO_WAIT_SEC, function() _decideAndGrant(hid) end)

    -- ✅ Marqueur d'amorçage : on autorise la réception de réponses dès AVANT l'émission
    GLOG._helloSent  = true
    GLOG._lastHelloHid = hid

    if GLOG.Comm_Broadcast then
        GLOG.Comm_Broadcast("HELLO", {
            hid = hid, rv = rv_me, player = me, caps = {"OFFER","GRANT","TOKEN1"},
            ver = (GLOG.GetAddonVersion and GLOG.GetAddonVersion()) or ""
        })
    end
end

function GLOG.ForceMyVersion()
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
    
    local meta = GuildLogisticsDB and GuildLogisticsDB.meta or {}
    local rv = safenum(meta.rev, 0) + 1
    meta.rev = rv
    meta.lastModified = now()
    
    local snap = GLOG.SnapshotExport and GLOG.SnapshotExport() or {}
    snap.rv = rv
    
    if GLOG.Comm_Broadcast then
        GLOG.Comm_Broadcast("SYNC_FULL", snap)
    end
    
    -- Marquer qu'on a envoyé un FULL récemment
    LastFullSeenAt = now() 
    LastFullSeenRv = rv
end

-- ===== Nettoyage périodique =====
function GLOG.CleanupDiscovery()
    -- 1) Élections HELLO terminées (garde 60s max pour l'UI, puis on libère)
    local heCutoff = now() - 60
    for hid, info in pairs(HelloElect or {}) do
        local ends = (info and info.endsAt) or 0
        if ends < heCutoff then HelloElect[hid] = nil end
    end

    -- 2) Cooldowns anciens
    local coolCutoff = now() - 300 -- 5 min
    for who, ts in pairs(OfferCooldown or {}) do
        if (ts or 0) < coolCutoff then OfferCooldown[who] = nil end
    end
    for who, ts in pairs(HelloReplyCooldown or {}) do
        if (ts or 0) < coolCutoff then HelloReplyCooldown[who] = nil end
    end
end

-- ===== API publiques pour le debug =====
function GLOG.GetHelloElect() 
    return HelloElect 
end

function GLOG._GetHelloElect(hid)
    return HelloElect and HelloElect[hid]
end

function GLOG.GetDiscoveryStats()
    local function len(t) local n=0; for _ in pairs(t or {}) do n=n+1 end; return n end
    return {
        helloElect = len(HelloElect),
        discovery = len(Discovery),
        offerCooldown = len(OfferCooldown),
    }
end

-- ===== API d'initialisation et de contrôle =====
function GLOG.InitNetworkDiscovery()
    -- Initialisation du système de découverte
    -- Pas d'initialisation spécifique nécessaire pour l'instant
    return true
end

function GLOG.StartDiscovery()
    -- Démarrer la découverte réseau avec un HELLO
    if GLOG.Sync_RequestHello then
        GLOG.Sync_RequestHello()
    end
    return true
end

function GLOG.StopDiscovery()
    -- Arrêter la découverte réseau
    -- Nettoyer les timers actifs si nécessaire
    HelloElect = {}
    Discovery = {}
    OfferCooldown = {}
    return true
end

-- ===== Helpers pour compatibilité =====
GLOG.HelloElect = HelloElect
GLOG.Discovery = Discovery
GLOG.LastFullSeenAt = function() return LastFullSeenAt end
GLOG.LastFullSeenRv = function() return LastFullSeenRv end
GLOG._registerOffer = _registerOffer
GLOG._decideAndGrant = _decideAndGrant
GLOG._scheduleOfferReply = _scheduleOfferReply
GLOG.HelloReplyCooldown = HelloReplyCooldown

-- Fonctions globales pour compatibilité
HelloElect = HelloElect
Discovery = Discovery
LastFullSeenAt = LastFullSeenAt
LastFullSeenRv = LastFullSeenRv
_registerOffer = _registerOffer
_decideAndGrant = _decideAndGrant
_scheduleOfferReply = _scheduleOfferReply
HelloReplyCooldown = HelloReplyCooldown
