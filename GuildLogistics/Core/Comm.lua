local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
local GLOG, UI = ns.GLOG, ns.UI

-- ➕ première synchro: flag session
local _FirstSyncRebroadcastDone = false

-- ➕ Garde-fou : attache les helpers UID exposés par Helper.lua (et fallback ultime)
GLOG.GetOrAssignUID = GLOG.GetOrAssignUID or (ns.Util and ns.Util.GetOrAssignUID)
GLOG.GetNameByUID   = GLOG.GetNameByUID   or (ns.Util and ns.Util.GetNameByUID)
GLOG.MapUID         = GLOG.MapUID         or (ns.Util and ns.Util.MapUID)
GLOG.UnmapUID       = GLOG.UnmapUID       or (ns.Util and ns.Util.UnmapUID)
GLOG.EnsureRosterLocal = GLOG.EnsureRosterLocal or (ns.Util and ns.Util.EnsureRosterLocal)

if not GLOG.GetOrAssignUID then
    -- Fallback minimal (au cas où Helper.lua n’est pas encore chargé — évite les nil)
    local function _ensureDB()
        GuildLogisticsDB = GuildLogisticsDB or {}
        GuildLogisticsDB.meta    = GuildLogisticsDB.meta    or {}
        GuildLogisticsDB.players = GuildLogisticsDB.players or {}
        GuildLogisticsDB.uids    = GuildLogisticsDB.uids    or {}
        GuildLogisticsDB.meta.uidSeq = GuildLogisticsDB.meta.uidSeq or 1
        return GuildLogisticsDB
    end
    function GLOG.GetOrAssignUID(name)
        local db = _ensureDB()
        local full = tostring(name or "")
        for uid, stored in pairs(db.uids) do if stored == full then return uid end end
        local uid = string.format("P%06d", db.meta.uidSeq); db.meta.uidSeq = db.meta.uidSeq + 1
        db.uids[uid] = full
        -- ⛑️ Création implicite = Réserve
        db.players[full] = db.players[full] or { credit = 0, debit = 0, reserved = true }
        return uid
    end
    function GLOG.GetNameByUID(uid)
        local db = _ensureDB()
        return db.uids[tostring(uid or "")]
    end
    function GLOG.MapUID(uid, name)
        local db = _ensureDB()
        db.uids[tostring(uid or "")] = tostring(name or "")
        -- ⛑️ Création implicite = Réserve
        local key = tostring(name or "")
        db.players[key] = db.players[key] or { credit=0, debit=0, reserved = true }
        return uid
    end
    function GLOG.UnmapUID(uid)
        local db = _ensureDB()
        db.uids[tostring(uid or "")] = nil
    end
    function GLOG.EnsureRosterLocal(name)
        local db = _ensureDB()
        local full = tostring(name or "")
        -- ⛑️ Création implicite = Réserve
        db.players[full] = db.players[full] or { credit = 0, debit = 0, reserved = true }
        if db.players[full].reserved == nil then db.players[full].reserved = true end
        return db.players[full]
    end
end

-- ===== Constantes / État =====
local PREFIX   = "GLOG1"
local MAX_PAY  = 200   -- fragmentation des messages
local Seq      = 0     -- séquence réseau

-- Limitation d'émission (paquets / seconde)
local OUT_MAX_PER_SEC = 1

-- Compression via LibDeflate (obligatoire)
local LD = assert(LibStub and LibStub:GetLibrary("LibDeflate"),  "LibDeflate requis")

-- Seuil de compression : ne pas compresser les tout petits messages
local COMPRESS_MIN_SIZE = 200

-- ⚙️ Utilitaires (rétablis) + fallbacks sûrs si Helper n'est pas encore chargé
local U = (ns and ns.Util) or {}
local safenum        = (U and U.safenum)        or (_G and _G.safenum)        or function(v,d) v=tonumber(v); if v==nil then return d or 0 end; return v end
local truthy         = (U and U.truthy)         or (_G and _G.truthy)         or function(v) v=tostring(v or ""); return (v=="1" or v:lower()=="true") end
local now            = (U and U.now)            or (_G and _G.now)            or function() return (time and time()) or 0 end
local normalizeStr   = (U and U.normalizeStr)   or (_G and _G.normalizeStr)   or function(s) s=tostring(s or ""):gsub("%s+",""):gsub("'",""); return s:lower() end
local playerFullName = (U and U.playerFullName) or (_G and _G.playerFullName) or function() local n,r=UnitFullName("player"); return r and (n.."-"..r) or n end
local masterName     = (U and U.masterName)     or (_G and _G.masterName)     or function() return nil end
local getRev         = (U and U.getRev)         or (_G and _G.getRev)         or function() local db=GuildLogisticsDB; return (db and db.meta and db.meta.rev) or 0 end

local function _compressStr(s)
    if not s or #s < COMPRESS_MIN_SIZE then return nil end
    local comp = LD:CompressDeflate(s, { level = 6 })
    return comp and LD:EncodeForWoWAddonChannel(comp) or nil
end

local function _decompressStr(s)
    if not s or s == "" then return nil end
    local decoded = LD:DecodeForWoWAddonChannel(s)
    if not decoded then return nil end
    local ok, raw = pcall(function() return LD:DecompressDeflate(decoded) end)
    return ok and raw or nil
end

local function encodeKV(t, out)
    -- ✅ Tolérance : si on nous passe déjà une chaîne encodée, renvoyer tel quel
    if type(t) ~= "table" then
        return tostring(t or "")
    end
    out = out or {}

    -- échappement sûr pour les éléments de tableau (gère virgules, crochets, pipes, retours ligne)
    local function escArrElem(s)
        s = tostring(s or "")
        s = s:gsub("\\", "\\\\")     -- antislash
             :gsub("|", "||")        -- pipe
             :gsub("\n", "\\n")      -- newline
             :gsub(",", "\\,")       -- virgule (séparateur d'array)
             :gsub("%]", "\\]")      -- crochet fermant d'array
        return s
    end

    for k, v in pairs(t) do
        local vt = type(v)
        if vt == "table" then
            local arr = {}
            for i = 1, #v do
                arr[#arr+1] = escArrElem(v[i])
            end
            out[#out+1] = k .. "=[" .. table.concat(arr, ",") .. "]"
        else
            v = tostring(v)
            v = v:gsub("|", "||"):gsub("\n", "\\n")
            out[#out+1] = k .. "=" .. v
        end
    end
    return table.concat(out, "|")
end

local function decodeKV(s)
    local t = {}
    s = tostring(s or "")
    local i = 1
    while i <= #s do
        local j = s:find("|", i, true) or (#s + 1)
        local part = s:sub(i, j - 1)
        local eq = part:find("=", 1, true)
        if eq then
            local k = part:sub(1, eq - 1)
            local v = part:sub(eq + 1)

            if v:match("^%[.*%]$") then
                -- Parse d'array avec échappements (\, \], \\, ||, \n)
                local body = v:sub(2, -2)
                local list, buf, esc = {}, {}, false
                for p = 1, #body do
                    local ch = body:sub(p, p)
                    if esc then
                        buf[#buf+1] = ch
                        esc = false
                    else
                        if ch == "\\" then
                            esc = true
                        elseif ch == "," then
                            list[#list+1] = table.concat(buf); buf = {}
                        else
                            buf[#buf+1] = ch
                        end
                    end
                end
                list[#list+1] = table.concat(buf)

                -- déséchappement final par élément
                for idx = 1, #list do
                    local x = list[idx]
                    x = x:gsub("\\n", "\n")
                         :gsub("||", "|")
                         :gsub("\\,", ",")
                         :gsub("\\%]", "]")
                         :gsub("\\\\", "\\")
                    list[idx] = x
                end
                t[k] = list
            else
                -- valeur scalaire : déséchappement simple
                v = v:gsub("\\n", "\n"):gsub("||", "|")
                t[k] = v
            end
        end
        i = j + 1
    end
    return t
end

local function packPayloadStr(kv_or_str)
    -- ✅ Si on reçoit déjà une chaîne encodée, ne pas ré-encoder (on compresse éventuellement)
    local plain
    if type(kv_or_str) == "table" then
        plain = encodeKV(kv_or_str)
    else
        plain = tostring(kv_or_str or "")
    end
    local comp = _compressStr(plain)
    if comp and #comp < #plain then
        return "c=z|" .. comp
    end
    return plain
end

local function unpackPayloadStr(s)
    s = tostring(s or "")
    if s:find("^c=z|") then
        local plain = _decompressStr(s:sub(5))
        if plain and plain ~= "" then return plain end
    end
    return s
end

-- ===== Découverte & Sync (HELLO → OFFER → GRANT → FULL → ACK) =====
-- Paramètres (sans broadcast, sans test de bande passante)
local HELLO_WAIT_SEC          = 4.0        -- ⬆️ fenêtre collecte OFFERS (+1s)
local OFFER_BACKOFF_MS_MAX    = 600        -- étalement OFFERS (0..600ms)
local FULL_INHIBIT_SEC        = 15         -- n'offre pas si FULL récent vu
local OFFER_RATE_LIMIT_SEC    = 10         -- anti-spam OFFERS par initiateur
local GM_EXTRA_WAIT_SEC       = 1.5        -- ➕ prolongation si GM en ligne mais pas encore d’OFFERS du GM

local LastFullSeenAt  = LastFullSeenAt or 0
local LastFullSeenRv  = LastFullSeenRv or -1
local LastGMFullAt    = LastGMFullAt   or 0
local LastGMFullRv    = LastGMFullRv   or -1

-- Suivi Debug de la découverte
local HelloElect      = HelloElect or {}   -- [hid] = { startedAt, endsAt, decided, winner, token, offers, applied }

-- Sessions initiées localement
-- [hid] = { initiator=me, rv_me, decided=false, endsAt, offers={[normName]={player,rv,est,h}}, grantedTo, token, reason }
local Discovery = Discovery or {}

-- Registre de suppression des envois non-critiques (STATUS_UPDATE) par cible
local _NonCritSuppress = _NonCritSuppress or {}
local _NONCRIT_TYPES = { STATUS_UPDATE=true }


-- Anti-spam version : envoi (1 fois par session) et réception (popup debounce)
-- [normName] = true  → un avertissement déjà envoyé à cette cible pendant cette session
local _VersionWarnSentTo   = _VersionWarnSentTo   or {}
-- (cooldown supprimé : envoi unique par session)
local _ObsoletePopupUntil  = _ObsoletePopupUntil  or 0   -- anti-popups multiples
local OBSOLETE_DEBOUNCE_SEC= 10                   -- 10s d’immunité côté client

-- Anti-doublon : n’émettre qu’un seul STATUS_UPDATE immédiatement après un HELLO (par cible)
local _HelloStatusSentTo   = _HelloStatusSentTo   or {}  -- [normTarget] = lastTs
local HELLO_STATUS_CD_SEC  = 3.0

local function _suppressTo(target, seconds)
    if not target or not seconds then return end
    local key = (_norm and _norm(target)) or string.lower(target or "")
    local untilTs = (now() + seconds)
    _NonCritSuppress[key] = math.max(_NonCritSuppress[key] or 0, untilTs)
end

local function _isSuppressedTo(target)
    if not target then return false end
    local key = (_norm and _norm(target)) or string.lower(target or "")
    return (now() < (_NonCritSuppress[key] or 0))
end


-- Cooldown d’OFFERS par initiateur
-- [normInitiator] = lastTs
local OfferCooldown = OfferCooldown or {}

-- Petits utilitaires
local function _norm(s) return normalizeStr(s or "") end

-- XOR compatible WoW (Lua 5.1) : utilise bit.bxor si présent, sinon fallback pur Lua
local bxor = (bit and bit.bxor) or function(a, b)
    a = tonumber(a) or 0; b = tonumber(b) or 0
    local res, bitv = 0, 1
    while a > 0 or b > 0 do
        local abit, bbit = a % 2, b % 2
        if (abit + bbit) == 1 then res = res + bitv end
        a = math.floor(a / 2); b = math.floor(b / 2); bitv = bitv * 2
    end
    return res
end

local function _hashHint(s)
    s = tostring(s or "")
    local h = 2166136261
    for i = 1, #s do
        h = (bxor(h, s:byte(i)) * 16777619) % 2^32
    end
    return h
end

-- Générateur hex “safe WoW” (évite les overflows de %x sur 32 bits)
local function _randHex8()
    -- Concatène deux mots 16 bits pour obtenir 8 hex digits sans jamais dépasser INT_MAX
    return string.format("%04x%04x", math.random(0, 0xFFFF), math.random(0, 0xFFFF))
end

local function _estimateSnapshotSize()
    local ok, snap = pcall(function() return (GLOG._SnapshotExport and GLOG._SnapshotExport()) or {} end)
    if not ok then return 0 end
    local enc = encodeKV(snap) or ""
    local comp = _compressStr and _compressStr(enc) or nil
    return comp and #comp or #enc
end

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

    -- Jeton pseudo-aléatoire : timestamp + 8 hex “safe”
    local token = string.format("%d-%s", now(), _randHex8())
    sess.token     = token
    sess.grantedTo = chosen.player

    HelloElect[hid] = HelloElect[hid] or {}
    HelloElect[hid].winner  = chosen.player
    HelloElect[hid].token   = token
    HelloElect[hid].decided = true
    if ns.Emit then ns.Emit("debug:changed") end

    GLOG.Comm_Whisper(chosen.player, "SYNC_GRANT", {
        hid   = hid,
        token = token,
        init  = sess.initiator,
        m     = sess.reason or "rv_gap",
    })
end

local function _scheduleOfferReply(hid, initiator, rv_init)
    -- Inhibition si FULL récent ≥ mon rv (⚠️ sauf GM pour priorité absolue)
    local iAmGM = (GLOG.IsNameGuildMaster and GLOG.IsNameGuildMaster(playerFullName())) or false
    if not iAmGM then
        if (now() - (LastFullSeenAt or 0)) < FULL_INHIBIT_SEC and (LastFullSeenRv or -1) >= safenum(getRev(), 0) then
            return
        end
    end

    -- ➕ Règle demandée : n'envoyer un SYNC_OFFER que si la "version" (révision DB) du joueur (HELLO)
    -- est STRICTEMENT inférieure à celle du GM. Si identique ou supérieure → pas d'OFFER.
    local gmRv
    if iAmGM then
        gmRv = safenum(getRev(), 0)
    else
        gmRv = (LastGMFullRv ~= nil) and safenum(LastGMFullRv, -1) or -1
    end
    -- Si on n'a aucune info sur le GM et qu'on n'est pas GM nous-même → ne pas répondre.
    if not iAmGM and (not gmRv or gmRv < 0) then return end
    -- Si la révision de l'initiateur (rv_init) n'est pas inférieure à celle du GM → ne pas répondre.
    if safenum(rv_init, 0) >= safenum(gmRv, -1) then return end

    -- Anti-spam par initiateur (conservé même pour GM)
    local k = _norm(initiator)
    local last = OfferCooldown[k] or 0
    if (now() - last) < OFFER_RATE_LIMIT_SEC then return end
    OfferCooldown[k] = now()

    local est   = _estimateSnapshotSize()
    local h     = _hashHint(string.format("%s|%d|%s", playerFullName(), safenum(getRev(),0), hid))
    -- Le GM répond sans jitter pour passer devant tout le monde
    local delay = iAmGM and 0 or (math.random(0, OFFER_BACKOFF_MS_MAX) / 1000.0)

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

        GLOG.Comm_Whisper(initiator, "SYNC_OFFER", {
            hid = hid, rv = rv_peer, est = est, h = h, from = playerFullName()
        })
    end)
end

-- File d'envoi temporisée
local OutQ      = {}
local OutTicker = nil

-- Boîtes aux lettres (réassemblage fragments)
local Inbox     = {}

-- ➕ Suivi d’une synchro FULL en cours par émetteur (pour piloter l’UI)
local ActiveFullSync = ActiveFullSync or {}   -- [senderKey]=true

-- Journalisation (onglet Debug)
local DebugLog  = DebugLog or {} -- { {dir,type,size,chan,channel,dist,target,from,sender,emitter,seq,part,total,raw,state,status,stateText} ... }
local SendLogIndexBySeq = SendLogIndexBySeq or {}  -- index "pending" ENVOI par seq
local RecvLogIndexBySeq = RecvLogIndexBySeq or {}  -- index RECU par seq

-- Timestamp précis pour garantir l'ordre visuel dans l'onglet Debug
local function _nowPrecise()
    if type(GetTimePreciseSec) == "function" then return GetTimePreciseSec() end
    if type(GetTime) == "function" then return GetTime() end
    return (time and time()) or 0
end

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
    if #DebugLog > 400 then table.remove(DebugLog, 1) end
    if ns.Emit then ns.Emit("debug:changed") end
end

-- Met à jour la ligne d'envoi "pending" via l'index (plus robuste que la recherche)
local function _updateSendLog(item)
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


function GLOG.GetDebugLogs() return DebugLog end
function GLOG.PurgeDebug()
    wipe(DebugLog)
    if ns.Emit then ns.Emit("debug:changed") end
end
-- ➕ Alias attendu par Tabs/Debug.lua
function GLOG.ClearDebugLogs()
    wipe(DebugLog)
    if ns.Emit then ns.Emit("debug:changed") end
end

-- ✏️ Trace locale vers l’onglet Debug avec entête conforme (raw = "v=1|t=...|s=...|p=...|n=...|payload")
function GLOG.DebugLocal(event, fields)
    if GLOG and GLOG.IsDebugEnabled and not GLOG.IsDebugEnabled() then return end

    local tname = tostring(event or "DEBUG")
    local kv    = type(fields) == "table" and fields or {}
    kv.t = tname
    kv.s = 0  -- séquence "locale"

    -- Utilise l’encodeur existant (compression éventuelle gérée)
    local payload = packPayloadStr and packPayloadStr(kv) or ""
    -- Entête attendu par l’onglet Debug (il extrait après "|n=...|")
    local header  = string.format("v=1|t=%s|s=%d|p=%d|n=%d|", tname, 0, 1, 1)
    local raw     = header .. payload

    local me = (playerFullName and playerFullName()) or ""

    DebugLog[#DebugLog+1] = {
        ts        = _nowPrecise and _nowPrecise() or time(),
        dir       = "send",            -- s’affiche dans la liste « Envoyés »
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

local function _ensureTicker()
    if OutTicker then return end
    local last = 0
    OutTicker = C_Timer.NewTicker(0.1, function()
        local t = now()
        if (t - last) < (1.0 / OUT_MAX_PER_SEC) then return end
        last = t
        local item = table.remove(OutQ, 1)
        if not item then return end

        C_ChatInfo.SendAddonMessage(item.prefix, item.payload, item.channel, item.target)

        -- Journalisation fragment envoyé (state, canal & émetteur sont gérés par pushLog)
        pushLog("send", item.type, #item.payload, item.channel, item.target or "", item.seq, item.part, item.total, item.payload)

        if item.part == item.total then
            SendLogIndexBySeq[item.seq] = nil
        end
    end)
end

local function _send(typeName, channel, target, kv)
    kv = kv or {}
    Seq = Seq + 1
    kv.t = typeName
    kv.s = Seq

    local payload = packPayloadStr(kv)
    local parts = {}
    local i = 1
    while i <= #payload do
        parts[#parts+1] = payload:sub(i, i + MAX_PAY - 1)
        i = i + MAX_PAY
    end

    -- Trace "pending" (part=0), puis mémorise l'index pour mises à jour suivantes
    pushLog("send", typeName, #payload, channel, target or "", Seq, 0, #parts, "<queued>")
    -- garde-fou : s'assurer que l'index existe
    SendLogIndexBySeq = SendLogIndexBySeq or {}
    SendLogIndexBySeq[Seq] = #DebugLog

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

function GLOG.Comm_Broadcast(typeName, kv)
    _send(typeName, "GUILD", nil, kv)
end

function GLOG.Comm_Whisper(target, msgType, data)
    -- Bloque l'émission des updates non-critiques vers une cible en cours de handshake
    if _NONCRIT_TYPES[msgType] and _isSuppressedTo(target) then
        return -- ne rien envoyer
    end

    _send(msgType, "WHISPER", target, data)

    -- Dès qu'on propose un SYNC_OFFER, on "gèle" les non-critiques vers cette cible
    if msgType == "SYNC_OFFER" then
        _suppressTo(target, (HELLO_WAIT_SEC or 5) + 2)
    elseif msgType == "SYNC_GRANT" then
        -- Petit gel après un GRANT pour laisser passer le FULL proprement
        _suppressTo(target, 2)
    end

    return true
end



-- ===== Application snapshot (import/export compact) =====
function GLOG._SnapshotExport()
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.meta = GuildLogisticsDB.meta or {}
    GuildLogisticsDB.players = GuildLogisticsDB.players or {}
    GuildLogisticsDB.uids = GuildLogisticsDB.uids or {}
    GuildLogisticsDB.expenses = GuildLogisticsDB.expenses or { list = {}, nextId = 1 }
    GuildLogisticsDB.lots = GuildLogisticsDB.lots or { list = {}, nextId = 1 }
    GuildLogisticsDB.aliases = GuildLogisticsDB.aliases or {}

    local meta = GuildLogisticsDB.meta
    local t = {
        P = {}, I = {}, E = {}, L = {}, H = {}, HL = {},
        A = {},  -- ➕ aliases (mainNormalisé:alias)
        rv = safenum(meta.rev, 0),
        lm = safenum(meta.lastModified, now()),
        fs = safenum(meta.fullStamp, now()),
    }

    for name, rec in pairs(GuildLogisticsDB.players) do
        local res = (rec and rec.reserved) and 1 or 0
        t.P[#t.P+1] = table.concat({ name, safenum(rec.credit, 0), safenum(rec.debit, 0), res }, ":")
    end

    local _players = GuildLogisticsDB.players or {}
    for uid, name in pairs(GuildLogisticsDB.uids) do
        if name and _players[name] ~= nil then
            t.I[#t.I+1] = tostring(uid) .. ":" .. tostring(name)
        end
    end

    -- ➕ Export des aliases (clé déjà normalisée côté Core)
    for key, alias in pairs(GuildLogisticsDB.aliases) do
        if alias and alias ~= "" then
            t.A[#t.A+1] = tostring(key) .. ":" .. tostring(alias)
        end
    end

    for _, e in ipairs(GuildLogisticsDB.expenses.list) do
        -- Préfère l'ID de source stable si présent, sinon retombe sur l’ancien libellé texte
        local srcField = tonumber(e.sourceId or 0) or 0
        if srcField == 0 then srcField = tostring(e.source or "") end

        t.E[#t.E+1] = table.concat({
            safenum(e.id,0), safenum(e.qty,0), safenum(e.copper,0),
            srcField, safenum(e.lotId,0), safenum(e.itemID,0)
        }, ",")
    end

    for _, l in ipairs(GuildLogisticsDB.lots.list) do
        local ids = {}
        for _, id in ipairs(l.itemIds or {}) do ids[#ids+1] = tostring(id) end
        t.L[#t.L+1] = table.concat({
            safenum(l.id,0), tostring(l.name or ("Lot "..tostring(l.id))), safenum(l.sessions,1),
            safenum(l.used,0), safenum(l.totalCopper,0), table.concat(ids, ";")
        }, ",")
    end
    -- Historique compact (CSV: ts,total,perHead,count,ref,participants(;))
    -- + ➕ tableau de correspondance HL : "ts|id,name,k,N,n,g;id,name,k,N,n,g"
    for _, h in ipairs(GuildLogisticsDB.history or {}) do
        local parts = table.concat(h.participants or {}, ";")
        t.H[#t.H+1] = table.concat({
            safenum(h.ts,0), safenum(h.total,0), safenum(h.perHead,0),
            safenum(h.count,0), (h.refunded and 1 or 0), parts
        }, ",")

        local Lctx = {}
        for _, li in ipairs(h.lots or {}) do
            if type(li) == "table" then
                local id   = tonumber(li.id or 0) or 0
                local name = tostring(li.name or ("Lot " .. tostring(id)))
                local k    = tonumber(li.k or 0) or 0
                local N    = tonumber(li.N or 1) or 1
                local n    = tonumber(li.n or 1) or 1
                local g    = tonumber(li.gold or li.c or 0) or 0
                Lctx[#Lctx+1] = table.concat({ id, name, k, N, n, g }, ",")
            end
        end
        if #Lctx > 0 then
            t.HL[#t.HL+1] = tostring(safenum(h.ts,0)) .. "|" .. table.concat(Lctx, ";")
        end
    end
    return t
end



function GLOG._SnapshotApply(kv)
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.meta = GuildLogisticsDB.meta or {}
    GuildLogisticsDB.players = {}
    GuildLogisticsDB.uids = {}
    GuildLogisticsDB.expenses = { list = {}, nextId = 1 }
    GuildLogisticsDB.lots = { list = {}, nextId = 1 }
    GuildLogisticsDB.aliases = {}  -- ➕ reset aliases (le FULL est autoritatif)

    local meta = GuildLogisticsDB.meta
    meta.rev = safenum(kv.rv, 0)
    meta.lastModified = safenum(kv.lm, now())
    meta.fullStamp = safenum(kv.fs, now())

    -- ➕ Import des aliases (A = { "main:alias", ... })
    for _, s in ipairs(kv.A or {}) do
        local mainKey, alias = tostring(s):match("^(.-):(.*)$")
        if mainKey and mainKey ~= "" then
            if alias == "" then
                GuildLogisticsDB.aliases[mainKey] = nil
            else
                GuildLogisticsDB.aliases[mainKey] = alias
            end
        end
    end

    -- (dans function GLOG._SnapshotApply(kv))
    for _, s in ipairs(kv.P or {}) do
    -- Nouveau format (4 champs) : name:credit:debit:reserved
        local name, credit, debit, res = s:match("^(.-):(%-?%d+):(%-?%d+):(%-?%d+)$")
        if name then
            GuildLogisticsDB.players[name] = {
                credit   = safenum(credit,0),
                debit    = safenum(debit,0),
                reserved = safenum(res,0) ~= 0
            }
        else
            -- Compat anciens snapshots (3 champs) : name:credit:debit
            local n2, c2, d2 = s:match("^(.-):(%-?%d+):(%-?%d+)$")
            if n2 then
                GuildLogisticsDB.players[n2] = {
                    credit   = safenum(c2,0),
                    debit    = safenum(d2,0),
                    reserved = false
                }
            end
        end
    end

    for _, s in ipairs(kv.I or {}) do
        local uid, name = s:match("^(.-):(.-)$")
        if uid and name then GuildLogisticsDB.uids[uid] = name end
    end
    do
        local listE = kv.E or {}

        -- Détecte si E est "agrégé" (1 élément = 1 ligne CSV) ou "aplati" (chaque champ séparé)
        local aggregated = false
        for _, s in ipairs(listE) do
            if type(s) == "string" and s:find(",", 1, true) then aggregated = true; break end
        end

        local function addRecord(id, qty, copper, src, lotId, itemId)
            id = safenum(id,0); if id <= 0 then return end
            -- Normalise lotId: 0 => nil (sinon les “libres” disparaissent de l’UI)
            local _lot = safenum(lotId,0); if _lot == 0 then _lot = nil end

            -- src peut être un label (ancien format) OU un ID numérique (nouveau format)
            local _sid = safenum(src, 0)
            local entry = {
                id      = id,
                qty     = safenum(qty,0),
                copper  = safenum(copper,0),
                lotId   = _lot,
                itemID  = safenum(itemId,0), -- ✅ normalisation clé attendue par l’UI
            }
            if _sid > 0 then
                entry.sourceId = _sid    -- nouveau format
            else
                entry.source   = tostring(src or "") -- rétro-compat
            end

            GuildLogisticsDB.expenses.list[#GuildLogisticsDB.expenses.list+1] = entry
            GuildLogisticsDB.expenses.nextId = math.max(GuildLogisticsDB.expenses.nextId or 1, id + 1)
        end

        if aggregated then
            -- Format historique : chaque élément est "id,qty,copper,src,lotId,itemId"
            for _, s in ipairs(listE) do
                local id, qty, copper, src, lotId, itemId =
                    s:match("^(%-?%d+),(%-?%d+),(%-?%d+),(.+),(%-?%d+),(%-?%d+)$")
                if id then addRecord(id, qty, copper, src, lotId, itemId) end
            end
        else
            -- Format aplati : reconstitue par paquets de 6 champs
            local buf = {}
            for _, tok in ipairs(listE) do
                buf[#buf+1] = tok
                if #buf == 6 then
                    addRecord(buf[1], buf[2], buf[3], buf[4], buf[5], buf[6])
                    buf = {}
                end
            end
        end
    end
    do
        GuildLogisticsDB.history = {}
    end

    for _, s in ipairs(kv.L or {}) do
        local id, name, sessions, used, totalCopper, idsCsv = s:match("^(%-?%d+),(.-),(%-?%d+),(%-?%d+),(%-?%d+),?(.*)$")
        id = safenum(id,0); if id > 0 then
            local l = {
                id = id, name = name,
                sessions = safenum(sessions,1), used = safenum(used,0), totalCopper = safenum(totalCopper,0),
                itemIds = {},
            }
            if idsCsv and idsCsv ~= "" then
                for v in tostring(idsCsv):gmatch("[^;]+") do l.itemIds[#l.itemIds+1] = safenum(v,0) end
            end
            GuildLogisticsDB.lots.list[#GuildLogisticsDB.lots.list+1] = l
            GuildLogisticsDB.lots.nextId = math.max(GuildLogisticsDB.lots.nextId or 1, id + 1)
        end
    end


    -- ➕ Import Historique (compat CSV) + rattachement lots via HL et/ou s.L
    GuildLogisticsDB.history = {}

    -- 1) Prépare un dictionnaire ts -> lots à partir de HL
    local HLmap = {}
    local HLsrc = kv.HL

    -- normalise : si HL est une string, mets-la dans une table
    if type(HLsrc) == "string" then
        HLsrc = { HLsrc }
    elseif type(HLsrc) ~= "table" then
        HLsrc = {}
    end

    for _, m in ipairs(HLsrc) do
        if type(m) == "string" then
            local tsStr, rest = m:match("^(%-?%d+)|(.+)$")
            local ts = safenum(tsStr, 0)
            if ts > 0 and rest and rest ~= "" then
                local Lctx = {}
                for chunk in tostring(rest):gmatch("[^;]+") do
                    local id,name,kUse,Ns,n,g = chunk:match("^(%-?%d+),(.-),(%-?%d+),(%-?%d+),(%-?%d+),(%-?%d+)$")
                    if id then
                        Lctx[#Lctx+1] = {
                            id = tonumber(id), name = name,
                            k = tonumber(kUse), N = tonumber(Ns),
                            n = tonumber(n),   gold = tonumber(g),
                        }
                    end
                end
                if #Lctx > 0 then HLmap[ts] = Lctx end
            end
        end
    end

    -- 2) Construit l'historique (CSV ou “table riche”) et attache les lots
    for _, s in ipairs(kv.H or {}) do
        local rec
        if type(s) == "string" then
            local hid, ts, total, per, count, refunded, rest
            ts, total, per, count, refunded, rest =
                s:match("^(%-?%d+),(%-?%d+),(%-?%d+),(%-?%d+),(%-?%d+),?(.*)$")
            if not ts then
                hid, ts, total, per, count, refunded, rest =
                    s:match("^(.-),(%-?%d+),(%-?%d+),(%-?%d+),(%-?%d+),(%-?%d+),?(.*)$")
            end

            local names = {}
            if rest and rest ~= "" then
                for name in tostring(rest):gmatch("[^;]+") do names[#names+1] = name end
            end

            local _ts    = safenum(ts, 0)
            local _total = safenum(total, 0)
            local _per   = safenum(per, 0)
            local _count = safenum(count, #names)
            local _ref   = (safenum(refunded, 0) == 1)

            if _ts > 0 and (_total ~= 0 or _per ~= 0 or _count > 0) then
                rec = {
                    hid = (hid ~= "" and hid or nil),
                    ts  = _ts, total = _total, perHead = _per,
                    count = _count, participants = names, refunded = _ref,
                }
            end
        elseif type(s) == "table" then
            local _ts    = safenum(s.ts or s.t, 0)
            local _total = safenum(s.total or s.tot, 0)
            local _per   = safenum(s.perHead or s.per or s.p, 0)
            local _parts = s.names or s.participants or s.P or {}
            local _count = safenum(s.count or s.cnt or s.c or #(_parts or {}), 0)
            if _ts > 0 and (_total ~= 0 or _per ~= 0 or _count > 0) then
                rec = {
                    hid = s.hid, ts = _ts, total = _total, perHead = _per,
                    count = _count, participants = _parts,
                    refunded = (s.refunded or s.r == 1) and true or false,
                }
                -- Si la ligne “riche” porte déjà L, on la parse
                local Lctx = {}
                for j = 1, #(s.L or {}) do
                    local v = s.L[j]
                    if type(v) == "string" then
                        local id,name,kUse,Ns,n,g = v:match("^(%-?%d+),(.-),(%-?%d+),(%-?%d+),(%-?%d+),(%-?%d+)$")
                        if id then
                            Lctx[#Lctx+1] = {
                                id = tonumber(id), name = name,
                                k = tonumber(kUse), N = tonumber(Ns),
                                n = tonumber(n),   gold = tonumber(g),
                            }
                        end
                    elseif type(v) == "table" then
                        Lctx[#Lctx+1] = v
                    end
                end
                if #Lctx > 0 then rec.lots = Lctx end
            end
        end

        if rec then
            -- Attache les lots depuis HL si pas déjà fournis sur la ligne
            if not rec.lots and HLmap[rec.ts] and #HLmap[rec.ts] > 0 then
                rec.lots = HLmap[rec.ts]
            end
            GuildLogisticsDB.history[#GuildLogisticsDB.history+1] = rec
        end
    end

    if ns and ns.Emit then ns.Emit("history:changed") end
end

-- ===== File complète → traitement ordonné =====
local CompleteQ = {}
local function enqueueComplete(sender, t, kv)
    -- Tri d’application : lm ↑, puis rv ↑, puis ordre d’arrivée
    kv._sender = sender
    kv._t = t
    kv._lm = safenum(kv.lm, now())
    kv._rv = safenum(kv.rv, -1)
    CompleteQ[#CompleteQ+1] = kv
    table.sort(CompleteQ, function(a,b)
        if a._lm ~= b._lm then return a._lm < b._lm end
        if a._rv ~= b._rv then return a._rv < b._rv end
        return false
    end)
    while true do
        local item = table.remove(CompleteQ, 1)
        if not item then break end
        GLOG._HandleFull(item._sender, item._t, item)
    end
end

local function refreshActive()
    if ns and ns.UI and ns.UI.RefreshActive then ns.UI.RefreshActive() end
end

-- ===== Handler principal =====
function GLOG._HandleFull(sender, msgType, kv)
    msgType = tostring(msgType or ""):upper()
    GuildLogisticsDB = GuildLogisticsDB or {}; GuildLogisticsDB.meta = GuildLogisticsDB.meta or {}
    local meta = GuildLogisticsDB.meta

    -- ➕ Double sécurité : en mode bootstrap (rev=0), ignorer tout sauf "SYNC_*"
    if safenum(meta.rev, 0) == 0 and not tostring(msgType or ""):match("^SYNC_") then
        return
    end

    local rv   = safenum(kv.rv, -1)
    local myrv = safenum(meta.rev, 0)
    local lm   = safenum(kv.lm, -1)
    local mylm = safenum(meta.lastModified, 0)

    local function shouldApply()
        if rv >= 0 then return rv >= myrv end
        if lm >= 0 then return lm >= mylm end
        return false
    end

    -- ======= Mutations cœur =======
    if msgType == "ROSTER_UPSERT" then
        if not shouldApply() then return end
        local uid, name = kv.uid, kv.name
        if uid and name then
            local nf = (ns and ns.Util and ns.Util.NormalizeFull) and ns.Util.NormalizeFull or tostring
            local full = nf(name)
            if GLOG.MapUID then GLOG.MapUID(uid, full) end
            if GLOG.EnsureRosterLocal then GLOG.EnsureRosterLocal(full) end
            meta.rev = (rv >= 0) and rv or myrv
            meta.lastModified = safenum(kv.lm, now())
            refreshActive()

            -- ✏️ Si l'UPSERT me concerne et que je suis connecté, envoyer un message unifié
            local me = nf(playerFullName())
            if me == full then
                local ilvl    = (GLOG.ReadOwnEquippedIlvl and GLOG.ReadOwnEquippedIlvl()) or nil
                local ilvlMax = (GLOG.ReadOwnMaxIlvl     and GLOG.ReadOwnMaxIlvl())       or nil
                local mid, lvl, map = 0, 0, ""
                if GLOG.ReadOwnedKeystone then mid, lvl, map = GLOG.ReadOwnedKeystone() end
                if (not map or map == "" or map == "Clé") and safenum(mid, 0) > 0 and GLOG.ResolveMKeyMapName then
                    local nm = GLOG.ResolveMKeyMapName(mid); if nm and nm ~= "" then map = nm end
                end
                if GLOG.BroadcastStatusUpdate then
                    GLOG.BroadcastStatusUpdate({
                        ilvl = ilvl, ilvlMax = ilvlMax,
                        mid = safenum(mid, 0), lvl = safenum(lvl, 0), map = tostring(map or ""),
                        ts = now(), by = me,
                    })
                end
            end
        end

    elseif msgType == "ROSTER_REMOVE" then
        -- Tolère les anciens messages (sans rv/lm) : on applique quand même.
        local hasVersioning = (kv.rv ~= nil) or (kv.lm ~= nil)
        if hasVersioning and not shouldApply() then return end

        local uid  = kv.uid
        -- Récupérer le nom AVANT de défaire le mapping UID -> name.
        local name = (uid and GLOG.GetNameByUID and GLOG.GetNameByUID(uid)) or kv.name

        if uid and GLOG.UnmapUID then GLOG.UnmapUID(uid) end

        -- Purge du roster local (nom complet si possible)
        if name and name ~= "" then
            if GLOG.RemovePlayerLocal then
                GLOG.RemovePlayerLocal(name, true)
            else
                GuildLogisticsDB = GuildLogisticsDB or {}
                GuildLogisticsDB.players = GuildLogisticsDB.players or {}
                GuildLogisticsDB.players[name] = nil
            end
        end

        if hasVersioning then
            meta.rev = (rv >= 0) and rv or myrv
            meta.lastModified = safenum(kv.lm, now())
        else
            -- Pas de versioning transmis : on marque juste une modif locale.
            meta.lastModified = now()
        end
        refreshActive()

    elseif msgType == "ROSTER_RESERVE" then
        if not shouldApply() then return end
        GuildLogisticsDB.players = GuildLogisticsDB.players or {}
        local uid, name = kv.uid, kv.name
        -- récupérer le nom complet via l’UID si besoin
        if (not name or name == "") and uid and GLOG.GetNameByUID then
            name = GLOG.GetNameByUID(uid)
        end
        if name and name ~= "" then
            local p = GuildLogisticsDB.players[name] or { credit=0, debit=0, reserved=false }
            p.reserved = (tonumber(kv.res) or 0) ~= 0
            GuildLogisticsDB.players[name] = p
            meta.rev = (rv >= 0) and rv or myrv
            meta.lastModified = safenum(kv.lm, now())
            if ns.Emit then ns.Emit("roster:reserve", name, p.reserved) end
            refreshActive()
        end
        
    elseif msgType == "TX_REQ" then
        -- Seul le GM traite les demandes : les clients non-GM ignorent.
        if not (GLOG.IsMaster and GLOG.IsMaster()) then
            return
        end

        if GLOG.AddIncomingRequest then GLOG.AddIncomingRequest(kv) end
        refreshActive()

        -- Popup côté GM
        local ui = ns.UI
        if ui and ui.PopupRequest then
            local _id = tostring(kv.uid or "") .. ":" .. tostring(kv.ts or now())
            ui.PopupRequest(kv.who or sender, safenum(kv.delta,0),
                function()
                    -- ⚠️ IMPORTANT : appliquer par NOM (kv.who) et non par UID local (non global)
                    local who = kv.who or sender
                    if GLOG.GM_ApplyAndBroadcastEx then
                        GLOG.GM_ApplyAndBroadcastEx(who, safenum(kv.delta,0), {
                            reason = "PLAYER_REQUEST",
                            requester = who,
                            uid = kv.uid, -- conservé pour audit/debug
                        })
                    elseif GLOG.GM_ApplyAndBroadcast then
                        GLOG.GM_ApplyAndBroadcast(who, safenum(kv.delta,0))
                    elseif GLOG.GM_ApplyAndBroadcastByUID then
                        -- Fallback ultime si l’API ci-dessus n’existe pas
                        GLOG.GM_ApplyAndBroadcastByUID(kv.uid, safenum(kv.delta,0), {
                            reason = "PLAYER_REQUEST", requester = who
                        })
                    end
                    if GLOG.ResolveRequest then GLOG.ResolveRequest(_id, true, playerFullName()) end
                end,
                function()
                    if GLOG.ResolveRequest then GLOG.ResolveRequest(_id, false, playerFullName()) end
                end
            )
        end

    elseif msgType == "TX_APPLIED" then
        if not shouldApply() then return end
        local applied = false
        if GLOG.ApplyDeltaByName and kv.name and kv.delta then
            GLOG.ApplyDeltaByName(kv.name, safenum(kv.delta,0), kv.by or sender)
            applied = true
        else
            -- ➕ Fallback : appliquer localement si l’API n’est pas disponible
            GuildLogisticsDB = GuildLogisticsDB or {}; GuildLogisticsDB.players = GuildLogisticsDB.players or {}
            local nf = (ns and ns.Util and ns.Util.NormalizeFull) and ns.Util.NormalizeFull or tostring
            local full = nf(kv.name or "")
            local existed = not not GuildLogisticsDB.players[full]
            local rec = GuildLogisticsDB.players[full] or { credit = 0, debit = 0, reserved = true }
            local d = safenum(kv.delta, 0)
            if d >= 0 then
                rec.credit = safenum(rec.credit,0) + d
            else
                rec.debit  = safenum(rec.debit,0)  + (-d)
            end
            -- 1er mouvement reçu par le réseau => flag réserve par défaut
            if not existed and rec.reserved == nil then rec.reserved = true end
            GuildLogisticsDB.players[full] = rec
            applied = true
        end
        if applied then
            meta.rev = (rv >= 0) and rv or myrv
            meta.lastModified = safenum(kv.lm, now())
            refreshActive()
        end

    elseif msgType == "TX_BATCH" then
        if not shouldApply() then return end
        local done = false
        if GLOG.ApplyBatch then
            GLOG.ApplyBatch(kv)
            done = true
        else
            -- ➕ Fallback : boucle sur les éléments du batch
            GuildLogisticsDB = GuildLogisticsDB or {}; GuildLogisticsDB.players = GuildLogisticsDB.players or {}
            local U, D, N = kv.U or {}, kv.D or {}, kv.N or {}
            local nf = (ns and ns.Util and ns.Util.NormalizeFull) and ns.Util.NormalizeFull or tostring
            for i = 1, math.max(#U, #D, #N) do
                local name = N[i] or (GLOG.GetNameByUID and GLOG.GetNameByUID(U[i])) or "?"
                local full = nf(name)
                local d = safenum(D[i], 0)
                local existed = not not GuildLogisticsDB.players[full]
                local rec = GuildLogisticsDB.players[full] or { credit = 0, debit = 0, reserved = true }
                if d >= 0 then
                    rec.credit = safenum(rec.credit,0) + d
                else
                    rec.debit  = safenum(rec.debit,0)  + (-d)
                end
                -- 1er mouvement reçu par le réseau => flag réserve par défaut
                if not existed and rec.reserved == nil then rec.reserved = true end
                GuildLogisticsDB.players[full] = rec
            end
            done = true
        end
        if done then
            meta.rev = (rv >= 0) and rv or myrv
            meta.lastModified = safenum(kv.lm, now())
            refreshActive()

            -- ➕ Popup réseau pour les joueurs impactés (si non silencieux)
            if not truthy(kv.S) and ns and ns.UI and ns.UI.PopupRaidDebit then
                local nf = (ns and ns.Util and ns.Util.NormalizeFull) and ns.Util.NormalizeFull or tostring
                local meFull = (playerFullName and playerFullName()) or UnitName("player")
                local meK = nf(meFull)
                local U, D, N = kv.U or {}, kv.D or {}, kv.N or {}
                for i = 1, math.max(#U, #D, #N) do
                    local name = N[i] or (GLOG.GetNameByUID and GLOG.GetNameByUID(U[i])) or "?"
                    if nf(name) == meK then
                        local d = safenum(D[i], 0)
                        local per   = -d
                        local after = (GLOG.GetSolde and GLOG.GetSolde(meFull)) or 0

                        -- Parse kv.L (CSV "id,name,k,N,n,gold") → tableau d'objets
                        local Lctx, Lraw = {}, kv and kv.L
                        if type(Lraw) == "table" then
                            for j = 1, #Lraw do
                                local s = Lraw[j]
                                if type(s) == "string" then
                                    local id,name,kUse,Ns,n,g = s:match("^(%-?%d+),(.-),(%-?%d+),(%-?%d+),(%-?%d+),(%-?%d+)$")
                                    if id then
                                        Lctx[#Lctx+1] = {
                                            id   = tonumber(id),
                                            name = name,
                                            k    = tonumber(kUse),
                                            N    = tonumber(Ns),
                                            n    = tonumber(n),
                                            gold = tonumber(g),
                                        }
                                    end
                                elseif type(s) == "table" then
                                    -- tolérance (anciens GM locaux)
                                    Lctx[#Lctx+1] = s
                                end
                            end
                        end

                        -- Respecte l’option "Notification de participation à un raid"
                        local _sv = (GLOG.GetSavedWindow and GLOG.GetSavedWindow()) or GuildLogisticsUI or {}
                        _sv.popups = _sv.popups or {}
                        if _sv.popups.raidParticipation ~= false then
                            ns.UI.PopupRaidDebit(meFull, per, after, { L = Lctx })
                        end
                        if ns.Emit then ns.Emit("raid:popup-shown", meFull) end
                        break
                    end
                end
            end
        end

    elseif msgType == "EXP_ADD" then
        if not shouldApply() then return end
        GuildLogisticsDB.expenses = GuildLogisticsDB.expenses or { list = {}, nextId = 1 }
        local id = safenum(kv.id, 0); if id <= 0 then return end
        for _, e in ipairs(GuildLogisticsDB.expenses.list) do if safenum(e.id,0) == id then return end end

        -- Normalisations : 'sid' = ID source stable, 'src' = libellé (compat), lotId 0 -> nil
        local _src = kv.src or kv.s
        local _sid = safenum(kv.sid, 0)
        local _lot = safenum(kv.l, 0); if _lot == 0 then _lot = nil end

        local e = {
            id = id,
            qty = safenum(kv.q,0),
            copper = safenum(kv.c,0),
            source  = _src,               -- compat anciens enregistrements
            sourceId = (_sid > 0) and _sid or nil,
            lotId  = _lot,
            itemID = safenum(kv.i,0),
        }
        table.insert(GuildLogisticsDB.expenses.list, e)
        GuildLogisticsDB.expenses.nextId = math.max(GuildLogisticsDB.expenses.nextId or 1, id + 1)
        meta.rev = (rv >= 0) and rv or myrv
        meta.lastModified = (lm >= 0) and lm or now()
        refreshActive()

    elseif msgType == "EXP_SPLIT" then
        if GLOG.Debug then GLOG.Debug("RECV","EXP_SPLIT") end

        -- 🔒 Évite le double-traitement chez l'émetteur (GM) : on ignore notre propre message
        do
            local isSelf = false
            if sender and UnitName then
                local me, realm = UnitName("player")
                local norm = GetNormalizedRealmName and GetNormalizedRealmName() or realm
                local fullRealm = (realm and realm ~= "") and (me.."-"..realm) or me
                local fullNorm  = (norm  and norm  ~= "") and (me.."-"..norm)  or nil
                if sender == me or sender == fullRealm or (fullNorm and sender == fullNorm) then
                    isSelf = true
                end
            end
            if isSelf then
                if GLOG.Debug then GLOG.Debug("RECV","EXP_SPLIT","ignored self") end
                return
            end
        end

        if not shouldApply() then return end
        GuildLogisticsDB.expenses = GuildLogisticsDB.expenses or { list = {}, nextId = 1 }

        local id  = safenum(kv.id, 0)
        local nq  = safenum(kv.nq, 0)
        local nc  = safenum(kv.nc, 0)

        -- ✅ Supporte message "aplati" et ancien format objet
        local addId  = safenum(kv.addId, 0);  if addId == 0 and kv.add then addId = safenum(kv.add.id, 0) end
        local addI   = safenum(kv.addI,  0);  if addI  == 0 and kv.add then addI  = safenum(kv.add.i,  0) end
        local addQ   = safenum(kv.addQ,  0);  if addQ  == 0 and kv.add then addQ  = safenum(kv.add.q,  0) end
        local addC   = safenum(kv.addC,  0);  if addC  == 0 and kv.add then addC  = safenum(kv.add.c,  0) end
        local addSid = safenum(kv.addSid,0);  if addSid== 0 and kv.add then addSid= safenum(kv.add.sid,0) end
        local addLot = safenum(kv.addLot,0);  if addLot== 0 and kv.add then addLot= safenum(kv.add.l,  0) end

        -- ✏️ Mise à jour + capture méta
        local baseMeta
        for _, it in ipairs(GuildLogisticsDB.expenses.list) do
            if safenum(it.id, 0) == id then
                it.qty    = nq
                it.copper = nc
                baseMeta  = it
                break
            end
        end

        -- ➕ Insertion robuste SANS dépendre d'helpers externes
        if addId > 0 or addQ > 0 or addC > 0 then
            -- anti-collision ID
            local used, maxId = {}, 0
            for _, x in ipairs(GuildLogisticsDB.expenses.list) do
                local xid = safenum(x.id, 0)
                used[xid] = true
                if xid > maxId then maxId = xid end
            end
            local insId = (addId > 0) and addId or (maxId + 1)
            while used[insId] do insId = insId + 1 end

            -- normalisation
            local _lot = (addLot ~= 0) and addLot or nil
            local newLine = {
                id       = insId,
                ts       = time(),
                qty      = (addQ > 0) and addQ or 1,
                copper   = addC,
                sourceId = (addSid > 0) and addSid or (baseMeta and baseMeta.sourceId) or nil,
                itemID   = (addI   > 0) and addI  or (baseMeta and baseMeta.itemID)   or 0,
                itemLink = baseMeta and baseMeta.itemLink or nil,
                itemName = baseMeta and baseMeta.itemName or nil,
                lotId    = _lot,
            }
            table.insert(GuildLogisticsDB.expenses.list, newLine)

            local nextId = safenum(GuildLogisticsDB.expenses.nextId, 1)
            if (insId + 1) > nextId then GuildLogisticsDB.expenses.nextId = insId + 1 end
        else
            if GLOG.Debug then GLOG.Debug("EXP_SPLIT","add-part manquante (id/q/c)") end
        end

        meta.rev = (rv >= 0) and rv or myrv
        meta.lastModified = (lm >= 0) and lm or now()
        refreshActive()
        if ns.Emit then ns.Emit("expenses:changed") end

        -- ➕ Suppression d'une dépense (diffusée par le GM)
    elseif msgType == "EXP_REMOVE" then
        if not shouldApply() then return end
        local id = safenum(kv.id, 0)
        local e = GuildLogisticsDB.expenses
        if e and e.list then
            local keep = {}
            for _, it in ipairs(e.list) do if safenum(it.id, -1) ~= id then keep[#keep+1] = it end end
            e.list = keep
        end
        meta.rev = (rv >= 0) and rv or myrv
        meta.lastModified = (lm >= 0) and lm or now()

        -- ✏️ Alignement avec EXP_ADD : rafraîchit l’onglet/écran actif (Ressources inclus)
        refreshActive()

        if ns.Emit then ns.Emit("expenses:changed") end

    elseif msgType == "STATUS_UPDATE" then
        -- Unifié : iLvl (+max) / Clé Mythique (mid,lvl,map) / ✨ Côte M+ (score)
        local pname = tostring(kv.name or "")
        local by    = tostring(kv.by   or sender or "")
        if pname ~= "" and GLOG.NormName and (GLOG.NormName(pname) == GLOG.NormName(by)) then
            GuildLogisticsDB = GuildLogisticsDB or {}; GuildLogisticsDB.players = GuildLogisticsDB.players or {}
            local p = GuildLogisticsDB.players[pname]      -- ⚠️ ne jamais créer ici
            if p then
                local n_ts = safenum(kv.ts, now())
                local changedIlvl, changedM, changedScore = false, false, false

                -- ===== iLvl =====
                local n_ilvl    = safenum(kv.ilvl, -1)
                local n_ilvlMax = safenum(kv.ilvlMax, -1)
                if n_ilvl >= 0 and n_ts >= safenum(p.ilvlTs, 0) then
                    p.ilvl     = math.floor(n_ilvl)
                    p.ilvlTs   = n_ts
                    p.ilvlAuth = by
                    if n_ilvlMax >= 0 then
                        p.ilvlMax   = math.floor(n_ilvlMax)
                        p.ilvlMaxTs = n_ts
                    end
                    changedIlvl = true
                end

                -- ===== M+ =====
                local n_mid = safenum(kv.mid, 0)
                local n_lvl = safenum(kv.lvl, 0)
                local n_map = tostring(kv.map or "")
                if (n_map == "" or n_map == "Clé") and n_mid > 0 and GLOG.ResolveMKeyMapName then
                    local nm = GLOG.ResolveMKeyMapName(n_mid); if nm and nm ~= "" then n_map = nm end
                end
                if n_lvl > 0 and n_ts >= safenum(p.mkeyTs, 0) then
                    p.mkeyMapId = n_mid
                    p.mkeyLevel = n_lvl
                    p.mkeyName  = n_map
                    p.mkeyTs    = n_ts
                    p.mkeyAuth  = by
                    changedM = true
                end

                -- ✨ ===== Côte M+ =====
                local n_score = safenum(kv.score, -1)
                if n_score >= 0 and n_ts >= safenum(p.mplusTs, 0) then
                    p.mplusScore = n_score
                    p.mplusTs    = n_ts
                    p.mplusAuth  = by
                    changedScore = true
                end

                if changedIlvl and ns.Emit then ns.Emit("ilvl:changed", pname) end
                if changedM    and ns.Emit then ns.Emit("mkey:changed", pname) end
                if changedScore and ns.Emit then ns.Emit("mplus:changed", pname) end
                if (changedIlvl or changedM or changedScore) and ns.RefreshAll then ns.RefreshAll() end
            end
        end

    elseif msgType == "HIST_ADD" then
        if not shouldApply() then return end
        GuildLogisticsDB.history = GuildLogisticsDB.history or {}
        local ts  = safenum(kv.ts,0)
        local exists = false
        for _, h in ipairs(GuildLogisticsDB.history) do if safenum(h.ts,0) == ts then exists = true break end end
        if not exists and ts > 0 then
            local rec = {
                ts = ts,
                total = safenum(kv.total or kv.t, 0),
                perHead = safenum(kv.per or kv.p, 0),
                count = safenum(kv.cnt or kv.c, 0),
                refunded = safenum(kv.r,0) ~= 0,
                participants = {},
            }
            for i = 1, #(kv.P or {}) do rec.participants[i] = kv.P[i] end

            -- ➕ parse L (lots) envoyé dans l'add (compat: L peut être liste de CSV)
            local Lctx = {}
            for j = 1, #(kv.L or {}) do
                local s = kv.L[j]
                if type(s) == "string" then
                    local id,name,kUse,Ns,n,g = s:match("^(%-?%d+),(.-),(%-?%d+),(%-?%d+),(%-?%d+),(%-?%d+)$")
                    if id then
                        Lctx[#Lctx+1] = {
                            id = tonumber(id), name = name,
                            k = tonumber(kUse), N = tonumber(Ns),
                            n = tonumber(n),   gold = tonumber(g),
                        }
                    end
                elseif type(s) == "table" then
                    Lctx[#Lctx+1] = s
                end
            end
            if #Lctx > 0 then rec.lots = Lctx end

            table.insert(GuildLogisticsDB.history, 1, rec)
            meta.rev = (rv >= 0) and rv or myrv
            meta.lastModified = (lm >= 0) and lm or now()
            if ns.Emit then ns.Emit("history:changed") end
            refreshActive()
        end

    elseif msgType == "HIST_REFUND" then
        if not shouldApply() then return end
        local ts   = safenum(kv.ts,0)
        local flag = safenum(kv.r,1) ~= 0  -- ✅ applique r=1 ou r=0
        for _, h in ipairs(GuildLogisticsDB.history or {}) do
            if safenum(h.ts,0) == ts then
                h.refunded = flag
                break
            end
        end
        meta.rev = (rv >= 0) and rv or myrv
        meta.lastModified = (lm >= 0) and lm or now()
        if ns.Emit then ns.Emit("history:changed") end
        refreshActive()

    elseif msgType == "HIST_DEL" then
        if not shouldApply() then return end
        local ts  = safenum(kv.ts,0)
        local hid = safenum(kv.h,0)
        local t = GuildLogisticsDB.history or {}
        for i = #t, 1, -1 do
            local rec = t[i]
            local match = (hid > 0 and safenum(rec.hid,0) == hid) or (hid == 0 and safenum(rec.ts,0) == ts)
            if match then
                table.remove(t, i)
                break
            end
        end

        meta.rev = (rv >= 0) and rv or myrv
        meta.lastModified = (lm >= 0) and lm or now()
        if ns.Emit then ns.Emit("history:changed") end
        refreshActive()

    elseif msgType == "LOT_CREATE" then
        if not shouldApply() then return end
        GuildLogisticsDB.lots = GuildLogisticsDB.lots or { list = {}, nextId = 1 }
        GuildLogisticsDB.expenses = GuildLogisticsDB.expenses or { list = {}, nextId = 1 }

        local id = safenum(kv.id, 0); if id <= 0 then return end
        for _, l0 in ipairs(GuildLogisticsDB.lots.list) do if safenum(l0.id,0) == id then return end end

        local l = {
            id = id,
            name = kv.n or ("Lot " .. tostring(id)),
            sessions = safenum(kv.N, 1),
            used = safenum(kv.u, 0),
            totalCopper = safenum(kv.t, 0),
            itemIds = {},
        }
        for _, v in ipairs(kv.I or {}) do l.itemIds[#l.itemIds+1] = safenum(v, 0) end

        -- ➕ Sécurités de cohérence côté client
        -- 1) Recalcule le total si absent/invalide
        if not l.totalCopper or l.totalCopper <= 0 then
            local sum = 0
            for _, eid in ipairs(l.itemIds or {}) do
                for _, e in ipairs(GuildLogisticsDB.expenses.list or {}) do
                    if safenum(e.id, -1) == safenum(eid, -2) then
                        sum = sum + safenum(e.copper, 0)
                        break
                    end
                end
            end
            l.totalCopper = sum
        end

        -- 2) Marque les dépenses rattachées au lot (sans toucher à `source`)
        if #l.itemIds > 0 then
            local set = {}
            for _, eid in ipairs(l.itemIds) do set[safenum(eid, -1)] = true end
            for _, e in ipairs(GuildLogisticsDB.expenses.list or {}) do
                if set[safenum(e.id, -2)] then e.lotId = id end
            end
        end

        table.insert(GuildLogisticsDB.lots.list, l)
        GuildLogisticsDB.lots.nextId = math.max(GuildLogisticsDB.lots.nextId or 1, id + 1)

        meta.rev = (rv >= 0) and rv or myrv
        meta.lastModified = (lm >= 0) and lm or now()
        if ns.Emit then ns.Emit("lots:changed") end
        refreshActive()

    elseif msgType == "LOT_DELETE" then
        if not shouldApply() then return end
        GuildLogisticsDB.lots = GuildLogisticsDB.lots or { list = {}, nextId = 1 }
        local id = safenum(kv.id, 0)
        local kept = {}
        for _, l in ipairs(GuildLogisticsDB.lots.list) do
            if safenum(l.id, -1) ~= id then kept[#kept+1] = l end
        end
        GuildLogisticsDB.lots.list = kept
        for _, e in ipairs(GuildLogisticsDB.expenses.list or {}) do if safenum(e.lotId,0) == id then e.lotId = nil end end
        meta.rev = (rv >= 0) and rv or myrv
        meta.lastModified = (lm >= 0) and lm or now()
        if ns.Emit then ns.Emit("lots:changed") end
        refreshActive()

    elseif msgType == "LOT_CONSUME" then
        if not shouldApply() then return end
        GuildLogisticsDB.lots = GuildLogisticsDB.lots or { list = {}, nextId = 1 }

        -- ✅ de-dup rv/lot : n’applique qu’UNE fois par lot et par révision
        GLOG._lastConsumeRv = GLOG._lastConsumeRv or {}

        local set = {}; for _, v in ipairs(kv.ids or {}) do set[safenum(v, -2)] = true end
        for _, l in ipairs(GuildLogisticsDB.lots.list) do
            if set[safenum(l.id, -2)] then
                l.__pendingConsume = nil -- ✅ fin d’attente locale (optimistic UI)
                l.used = safenum(l.used, 0) + 1
            end
        end
        meta.rev = (rv >= 0) and rv or myrv
        meta.lastModified = (lm >= 0) and lm or now()
        if ns.Emit then ns.Emit("lots:changed") end
        refreshActive()

        -- ======= Handshake & Snapshots =======
    elseif msgType == "HELLO" then
        local hid     = kv.hid or ""
        local rv_me   = safenum(getRev(), 0)
        local rv_them = safenum(kv.rv, -1)

        -- ➕ Comparaison de versions d'addon (si fournie)
        local ver_me   = (GLOG.GetAddonVersion and GLOG.GetAddonVersion()) or ""
        local ver_them = tostring(kv.ver or "")
        local cmp = (ns and ns.Util and ns.Util.CompareVersions and ns.Util.CompareVersions(ver_me, ver_them)) or 0

        if rv_me > rv_them then
            _suppressTo(sender, (HELLO_WAIT_SEC or 5) + 2)
        end

        if hid ~= "" and sender and sender ~= "" then
            _scheduleOfferReply(hid, sender, rv_them)
        end

        -- Si ma version est plus récente → prévenir le joueur obsolète en WHISPER (⚠️ 1 fois par session)
        if sender and sender ~= "" and cmp > 0 then
            local k = (_norm and _norm(sender)) or string.lower(sender or "")
            if not _VersionWarnSentTo[k] then
                _VersionWarnSentTo[k] = true
                GLOG.Comm_Whisper(sender, "VERSION_WARN", {
                    by     = playerFullName(),
                    latest = ver_me,
                    yours  = ver_them,
                    ts     = now(),
                })
            end
        end

                -- Statut unifié → un seul STATUS_UPDATE si sa DB n'est pas obsolète
        if sender and sender ~= "" and sender ~= playerFullName() and rv_them >= rv_me then
            local me = playerFullName()
            if GLOG.IsPlayerInRosterOrReserve and GLOG.IsPlayerInRosterOrReserve(me) then
                local p     = (GuildLogisticsDB and GuildLogisticsDB.players and GuildLogisticsDB.players[me]) or {}
                local ilvl  = safenum(p.ilvl, 0)
                local ilvMx = safenum(p.ilvlMax or 0, 0)
                if (ilvMx <= 0) and GLOG.ReadOwnMaxIlvl then ilvMx = safenum(GLOG.ReadOwnMaxIlvl(), 0) end

                -- Clé mythique (fallback API si non stockée)
                local mid = safenum(p.mkeyMapId, 0)
                local lvl = safenum(p.mkeyLevel, 0)
                local map = tostring(p.mkeyName or "")
                if (lvl <= 0 or mid <= 0) and GLOG.ReadOwnedKeystone then
                    local _mid, _lvl, _map = GLOG.ReadOwnedKeystone()
                    if safenum(_mid,0) > 0 then mid = safenum(_mid,0) end
                    if safenum(_lvl,0) > 0 then lvl = safenum(_lvl,0) end
                    if (not map or map == "" or map == "Clé") and _map and _map ~= "" then map = tostring(_map) end
                end
                if (map == "" or map == "Clé") and mid > 0 and GLOG.ResolveMKeyMapName then
                    local nm = GLOG.ResolveMKeyMapName(mid); if nm and nm ~= "" then map = nm end
                end

                local payload = {
                    name = me, ts = now(), by = me,
                    ilvl = ilvl,
                }
                if ilvMx > 0 then payload.ilvlMax = ilvMx end

                -- ✨ Côte M+ depuis DB ou API si manquante
                local score = safenum((p and p.mplusScore) or 0, 0)
                if score <= 0 and GLOG.ReadOwnMythicPlusScore then
                    score = safenum(GLOG.ReadOwnMythicPlusScore(), 0)
                end
                if score > 0 then payload.score = score end

                if lvl > 0 then
                    payload.mid = mid; payload.lvl = lvl
                    if map ~= "" then payload.map = map end
                end

                -- ✅ Appliquer aussi localement à moi (sans créer d'entrée)
                do
                    GuildLogisticsDB = GuildLogisticsDB or {}; GuildLogisticsDB.players = GuildLogisticsDB.players or {}
                    local p  = GuildLogisticsDB.players[me]
                    local ts = now()
                    local changed = false
                    if p then
                        if ilvl > 0 and ts >= safenum(p.ilvlTs, 0) then
                            p.ilvl   = ilvl
                            if ilvMx > 0 then p.ilvlMax = ilvMx; p.ilvlMaxTs = ts end
                            p.ilvlTs = ts; p.ilvlAuth = me
                            changed = true
                            if ns.Emit then ns.Emit("ilvl:changed", me) end
                        end
                        if lvl > 0 and ts >= safenum(p.mkeyTs, 0) then
                            p.mkeyMapId = mid; p.mkeyLevel = lvl; p.mkeyName = map
                            p.mkeyTs = ts; p.mkeyAuth = me
                            changed = true
                            if ns.Emit then ns.Emit("mkey:changed", me) end
                        end
                        if safenum(score, -1) >= 0 and ts >= safenum(p.mplusTs, 0) then
                            p.mplusScore = score; p.mplusTs = ts; p.mplusAuth = me
                            changed = true
                            if ns.Emit then ns.Emit("mplus:changed", me) end
                        end
                        if changed and ns.RefreshAll then ns.RefreshAll() end
                    end
                end

                -- Anti-doublon : 1 seul STATUS_UPDATE par cible dans la foulée du HELLO
                local key  = (_norm and _norm(sender)) or tostring(sender)
                local last = _HelloStatusSentTo[key] or 0
                if (now() - last) > (HELLO_STATUS_CD_SEC or 1.0) then
                    GLOG.Comm_Whisper(sender, "STATUS_UPDATE", payload)
                    _HelloStatusSentTo[key] = now()
                end
            end
        end

        -- ✏️ Flush TX_REQ si le HELLO vient du GM effectif (tolérant au roster pas encore prêt)
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

    elseif msgType == "VERSION_WARN" then
        -- Reçu par un client obsolète (potentiellement plusieurs fois) → popup unique (debounce)
        local latest = tostring(kv.latest or "")
        local mine   = (GLOG.GetAddonVersion and GLOG.GetAddonVersion()) or ""

        -- Anti-popups multiples pendant un court laps de temps
        if (now() < (_ObsoletePopupUntil or 0)) then return end
        _ObsoletePopupUntil = now() + (OBSOLETE_DEBOUNCE_SEC or 10)

        local jitter = (math.random(0, 200) / 1000.0)
        ns.Util.After(jitter, function()
            if ns.UI and ns.UI.ShowOutdatedAddonPopup then
                ns.UI.ShowOutdatedAddonPopup(mine, latest, kv.by or "")
            end
        end)

        
    elseif msgType == "SYNC_OFFER" then
        -- Côté initiateur : collecter les OFFERS pendant HELLO_WAIT
        local hid = kv.hid or ""
        local sess = Discovery[hid]
        if hid ~= "" and sess and _norm(sess.initiator) == _norm(playerFullName()) then
            _registerOffer(hid, kv.from or sender, kv.rv, kv.est, kv.h)

            -- Si une offre STRICTEMENT meilleure que ma version arrive, décider tout de suite
            local offerRv = safenum(kv.rv, 0)
            if not sess.grantedTo and (offerRv > safenum(sess.rv_me, 0) or sess.decided) then
                C_Timer.After(0, function() _decideAndGrant(hid) end)
            end
        end

    elseif msgType == "SYNC_GRANT" then
        -- Reçu par le gagnant : envoyer un FULL ciblé avec token
        local hid   = kv.hid or ""
        local token = kv.token or ""
        local init  = kv.init or sender
        if hid ~= "" and token ~= "" and init and init ~= "" then
            local snap = (GLOG._SnapshotExport and GLOG._SnapshotExport()) or {}
            snap.hid   = hid
            snap.token = token
            GLOG.Comm_Whisper(init, "SYNC_FULL", snap)
        end

    elseif msgType == "SYNC_FULL" then
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
                return
            end
        end

        -- Le FULL finalise le handshake : lever la suppression pour l'émetteur
        _suppressTo(sender, -999999)

        -- Vérifier jeton si une découverte locale est active
        local hid   = kv.hid or ""
        local token = kv.token or ""
        local okByToken = true
        local sess = Discovery[hid]
        if hid ~= "" and sess then
            okByToken = (token ~= "" and token == sess.token)
        end

        if not okByToken then return end

        if not shouldApply() then return end

        -- ➕ Indiquer à l'UI que la synchro débute, puis céder la main au frame suivant
        if ns and ns.Emit then ns.Emit("sync:begin", "full") end
        C_Timer.After(0, function()
            local _ok, _err = pcall(function()
        GLOG._SnapshotApply(kv)
        refreshActive()

        -- ACK vers l'émetteur si token présent
        if hid ~= "" and token ~= "" then
            GLOG.Comm_Whisper(sender, "SYNC_ACK", { hid = hid, rv = safenum(meta.rev,0) })
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
                    GLOG.Comm_Broadcast("HELLO", {
                        hid = hid2, rv = rv_me, player = me, caps = "OFFER|GRANT|TOKEN1",
                        ver = (GLOG.GetAddonVersion and GLOG.GetAddonVersion()) or ""
                    })
                end)

                C_Timer.After(0.5, function()
                    -- ✅ Assure une entrée roster/réserve locale pour ne pas bloquer la diffusion
                    local meNow = (playerFullName and playerFullName()) or me
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
                            mid = safenum(mid,0), lvl = safenum(lvl,0), map = tostring(map or ""),
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

    elseif msgType == "SYNC_ACK" then
        -- Reçu par l'émetteur du FULL : fin de transfert (place à des métriques éventuelles)
        local hid = kv.hid or ""
        if hid ~= "" then
            -- no-op
        end
    end
end

-- ===== Réception bas niveau =====
local function onAddonMsg(prefix, message, channel, sender)
    if prefix ~= PREFIX then return end
    -- Ignorer toute réception tant que notre HELLO n'a pas été émis (sauf HELLO lui-même)
    local peekType = message:match("v=1|t=([^|]+)|")
    if not (GLOG and GLOG._helloSent) and peekType ~= "HELLO" then return end

    -- ➕ Mode bootstrap : si la DB locale est en version 0, ne traiter QUE les messages "SYNC_*"
    do
        local rev0 = safenum((GuildLogisticsDB and GuildLogisticsDB.meta and GuildLogisticsDB.meta.rev), 0)
        if rev0 == 0 then
            local pt = tostring(peekType or "")
            if not pt:match("^SYNC_") then return end
        end
    end

    local t, s, p, n = message:match("v=1|t=([^|]+)|s=(%d+)|p=(%d+)|n=(%d+)|")

    local seq  = safenum(s, 0)
    local part = safenum(p, 1)
    local total= safenum(n, 1)

    -- ➕ Affiche l’indicateur dès le 1er fragment d’un SYNC_FULL
    if t == "SYNC_FULL" and part == 1 then
        local senderKey = (ns.Util and ns.Util.NormalizeFull and ns.Util.NormalizeFull(sender)) or tostring(sender or "")
        if not ActiveFullSync[senderKey] then
            ActiveFullSync[senderKey] = true
            if ns and ns.Emit then ns.Emit("sync:begin", "full") end
        end
    end

    -- ➜ Registre/MAJ d'une ligne unique par séquence pour l'UI
    local idx = RecvLogIndexBySeq[seq]
    if idx and DebugLog[idx] then
        local r = DebugLog[idx]
        r.ts      = _nowPrecise()
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
        pushLog("recv", t or "?", #message, channel, sender, seq, part, total, message, (part >= total) and "received" or "receiving")
        RecvLogIndexBySeq[seq] = #DebugLog
    end

    -- ✅ Ajout : pour chaque fragment reçu après le premier, on journalise AUSSI ce fragment
    do
        local idx = RecvLogIndexBySeq[seq]
        if idx and DebugLog[idx] then
            -- on duplique en « recv » afin que Debug.lua reconstitue got/total correctement
            pushLog("recv", t or "?", #message, channel, sender, seq, part, total, message, (part >= total) and "received" or "receiving")
        end
    end

    if not t then return end

    local payload = message:match("|n=%d+|(.*)$") or ""

    -- ✅ Clé de réassemblage robuste : séquence + émetteur NORMALISÉ (évite 'Name' vs 'Name-Royaume')
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

        -- ➕ Termine proprement l’indicateur en toute circonstance pour SYNC_FULL
        local function _finishSync(ok)
            if t == "SYNC_FULL" and ActiveFullSync[senderKey] then
                ActiveFullSync[senderKey] = nil
                if ns and ns.Emit then ns.Emit("sync:end", "full", ok) end
            end
        end

        if t then
            -- Décodage KV + enfilement ordonné (sécurisé)
            local _ok, _err = pcall(function()
            local plain = unpackPayloadStr(full)
            local kv = decodeKV(plain)
            enqueueComplete(sender, t, kv)
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

-- ===== Envoi mutations (roster & crédits) =====
function GLOG.BroadcastRosterUpsert(name)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
    if not name or name=="" then return end
    local uid = GLOG.GetOrAssignUID(name)
    if not uid then return end
    local rv = safenum((GuildLogisticsDB and GuildLogisticsDB.meta and GuildLogisticsDB.meta.rev), 0) + 1
    GuildLogisticsDB.meta.rev = rv
    GuildLogisticsDB.meta.lastModified = now()
    local alias = (GLOG.GetAliasFor and GLOG.GetAliasFor(name)) or nil
    GLOG.Comm_Broadcast("ROSTER_UPSERT", {
        uid = uid, name = name, alias = alias,   -- ➕ alias (optionnel)
        rv = rv, lm = GuildLogisticsDB.meta.lastModified
    })
end

function GLOG.BroadcastRosterRemove(idOrName)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
    if not idOrName or idOrName=="" then return end

    local uid, name = nil, nil
    local s = tostring(idOrName or "")

    -- Si on reçoit un UID (ex: P000123), on garde tel quel ; sinon on considère que c’est un nom
    if s:match("^P%d+$") then
        uid  = s
        name = (GLOG.GetNameByUID and GLOG.GetNameByUID(uid)) or nil
    else
        name = s
        uid  = (GLOG.FindUIDByName and GLOG.FindUIDByName(name)) or (GLOG.GetUID and GLOG.GetUID(name)) or nil
        -- Surtout ne pas créer un nouvel UID lors d’une suppression : on accepte uid=nil, mais on envoie le nom
    end

    local rv = safenum((GuildLogisticsDB and GuildLogisticsDB.meta and GuildLogisticsDB.meta.rev), 0) + 1
    GuildLogisticsDB.meta.rev = rv
    GuildLogisticsDB.meta.lastModified = now()

    -- On diffuse toujours les deux champs (uid + name) si disponibles pour une réception robuste
    GLOG.Comm_Broadcast("ROSTER_REMOVE", {
        uid = uid, name = name, rv = rv, lm = GuildLogisticsDB.meta.lastModified
    })
end

function GLOG.GM_ApplyAndBroadcast(name, delta)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
    local uid = GLOG.GetOrAssignUID(name); if not uid then return end
    local rv = safenum((GuildLogisticsDB and GuildLogisticsDB.meta and GuildLogisticsDB.meta.rev), 0) + 1
    GuildLogisticsDB.meta.rev = rv
    GuildLogisticsDB.meta.lastModified = now()
    local nm = GLOG.GetNameByUID(uid) or name
    GLOG.Comm_Broadcast("TX_APPLIED", { uid=uid, name=nm, delta=delta, rv=rv, lm=GuildLogisticsDB.meta.lastModified, by=playerFullName() })
end
function GLOG.GM_ApplyAndBroadcastEx(name, delta, extra)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
    local uid = GLOG.GetOrAssignUID(name); if not uid then return end
    local rv = safenum((GuildLogisticsDB and GuildLogisticsDB.meta and GuildLogisticsDB.meta.rev), 0) + 1
    GuildLogisticsDB.meta.rev = rv
    GuildLogisticsDB.meta.lastModified = now()
    local nm = GLOG.GetNameByUID(uid) or name
    local p = { uid=uid, name=nm, delta=delta, rv=rv, lm=GuildLogisticsDB.meta.lastModified, by=playerFullName() }
    if type(extra)=="table" then for k,v in pairs(extra) do if p[k]==nil then p[k]=v end end end
    GLOG.Comm_Broadcast("TX_APPLIED", p)
end

function GLOG.GM_ApplyAndBroadcastByUID(uid, delta, extra)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
    local rv = safenum((GuildLogisticsDB and GuildLogisticsDB.meta and GuildLogisticsDB.meta.rev), 0) + 1
    GuildLogisticsDB.meta.rev = rv
    GuildLogisticsDB.meta.lastModified = now()
    local p = {
        uid   = uid,
        name  = (GLOG.GetNameByUID and GLOG.GetNameByUID(uid)) or tostring(uid),
        delta = delta,
        rv    = rv,
        lm    = GuildLogisticsDB.meta.lastModified,
        by    = playerFullName(),
    }
    if type(extra) == "table" then
        for k, v in pairs(extra) do if p[k] == nil then p[k] = v end end
    end
    GLOG.Comm_Broadcast("TX_APPLIED", p)
end

-- ➕ Envoi batch compact (1 seul TX_BATCH au lieu d'une rafale de TX_APPLIED)
function GLOG.GM_BroadcastBatch(adjusts, opts)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
    adjusts = adjusts or {}
    opts    = opts or {}

    local uids, deltas, names = {}, {}, {}
    for _, a in ipairs(adjusts) do
        local nm = a and a.name
        if nm and nm ~= "" then
            local uid = (GLOG.GetOrAssignUID and GLOG.GetOrAssignUID(nm)) or nil
            names[#names+1]   = nm
            uids[#uids+1]    = uid or ""
            deltas[#deltas+1] = math.floor(tonumber(a.delta) or 0)
        end
    end

    local reason = opts.reason or opts.R
    local silent = not not (opts.silent or opts.S)

    -- On passe les autres champs (ex: L = contexte lots) dans 'extra'
    local extra = {}
    for k, v in pairs(opts) do
        if k ~= "reason" and k ~= "R" and k ~= "silent" and k ~= "S" then
            extra[k] = v
        end
    end

    GLOG.GM_ApplyBatchAndBroadcast(uids, deltas, names, reason, silent, extra)
end

function GLOG.GM_ApplyBatchAndBroadcast(uids, deltas, names, reason, silent, extra)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end

    -- Versionnage unique partagé avec le broadcast
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.meta = GuildLogisticsDB.meta or {}
    local rv = safenum(GuildLogisticsDB.meta.rev, 0) + 1
    GuildLogisticsDB.meta.rev = rv
    GuildLogisticsDB.meta.lastModified = now()

    -- ✅ Application LOCALE côté GM (on n'attend pas notre propre message réseau)
    do
        local U, D, N = uids or {}, deltas or {}, names or {}
        local nf = (ns and ns.Util and ns.Util.NormalizeFull) and ns.Util.NormalizeFull or tostring
        for i = 1, math.max(#U, #D, #N) do
            local name = N[i] or (GLOG.GetNameByUID and GLOG.GetNameByUID(U[i])) or nil
            local delta = safenum(D[i], 0)
            if name and delta ~= 0 then
                if GLOG.ApplyDeltaByName then
                    GLOG.ApplyDeltaByName(name, delta, playerFullName())
                else
                    GuildLogisticsDB.players = GuildLogisticsDB.players or {}
                    local full = nf(name)
                    local rec = GuildLogisticsDB.players[full] or { credit = 0, debit = 0 }
                    if delta >= 0 then rec.credit = safenum(rec.credit,0) + delta
                    else               rec.debit  = safenum(rec.debit,0)  + (-delta) end
                    GuildLogisticsDB.players[full] = rec
                end
            end
        end
        if ns.RefreshAll then ns.RefreshAll() end
    end

    -- Diffusion réseau du même batch (rv/lm identiques)
    local p = {
        U  = uids or {},
        D  = deltas or {},
        N  = names or {},
        R  = reason or "",               -- libellé (optionnel)
        S  = silent and 1 or 0,          -- silencieux ? (bool → int)
        rv = rv,
        lm = GuildLogisticsDB.meta.lastModified,
    }

    -- Sérialise extra.L (liste des lots utilisés) en CSV "id,name,k,N,n,gold"
    if type(extra) == "table" then
        for k, v in pairs(extra) do
            if k == "L" and type(v) == "table" then
                local Ls = {}
                for i = 1, #v do
                    local li = v[i]
                    if type(li) == "table" then
                        local id   = tonumber(li.id or li.lotId) or 0
                        local name = tostring(li.name or "")
                        local kUse = tonumber(li.k or li.n or 1) or 1
                        local Ns   = tonumber(li.N or 1) or 1
                        local n    = tonumber(li.n or 1) or 1
                        local g    = tonumber(li.gold or li.g or 0) or 0
                        Ls[#Ls+1]  = table.concat({ id, name, kUse, Ns, n, g }, ",")
                    else
                        Ls[#Ls+1]  = tostring(li or "")
                    end
                end
                p.L = Ls
            elseif p[k] == nil then
                p[k] = v
            end
        end
    end

    GLOG.Comm_Broadcast("TX_BATCH", p)
end

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
    for _, r in ipairs(list) do if r.id ~= id then kept[#kept+1] = r end end
    GuildLogisticsDB.requests = kept
    if accepted and GLOG and GLOG.GM_ApplyAndBroadcastByUID then
        -- L’appelant a déjà appliqué la mutation
    end
    if ns.Emit then ns.Emit("requests:changed") end
end

function GLOG.RequestAdjust(a, b)
    -- Compat : UI appelle (name, delta) ; ancienne forme : (delta)
    local delta = (b ~= nil) and safenum(b, 0) or safenum(a, 0)
    if delta == 0 then return end

    local me  = playerFullName()
    local uid = GLOG.GetOrAssignUID and GLOG.GetOrAssignUID(me)
    if not uid then return end

    local payload = { uid = uid, delta = delta, who = me, ts = now(), reason = "CLIENT_REQ" }

    -- ➕ Heuristique temps-réel : considérer “en ligne” si vu récemment via HELLO
    local function _masterSeenRecently(name)
        local nf = (ns and ns.Util and ns.Util.NormalizeFull) and ns.Util.NormalizeFull or tostring
        local target = nf(name or "")

        -- 1) On a reçu un HELLO tout juste du GM et on attend le flush
        if GLOG._awaitHelloFrom and nf(GLOG._awaitHelloFrom) == target then
            return true
        end

        -- 2) Élection HELLO récente où le gagnant est le GM (fenêtre ~60s)
        local nowt = now()
        for _, sess in pairs(HelloElect or {}) do
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

    -- ➕ Étape commune (décision après lecture du roster à jour)
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
            GLOG.Comm_Whisper(gmName, "TX_REQ", payload)
        else
            -- GM hors-ligne ou inconnu : persiste → flush auto sur HELLO
            if GLOG.Pending_AddTXREQ then GLOG.Pending_AddTXREQ(payload) end
            if UIErrorsFrame and UIErrorsFrame.AddMessage then
                UIErrorsFrame:AddMessage("|cffffff80[GLOG]|r GM hors-ligne : demande mise en file d’attente.", 1, 0.9, 0.4)
            end
            if ns.Emit then ns.Emit("debug:changed") end
        end
    end

    -- ✏️ Nouveau : rafraîchir le roster AVANT la décision d’envoi
    if GLOG.RefreshGuildCache then
        GLOG.RefreshGuildCache(function() decideAndSend() end)
    else
        -- Fallback si jamais la fonction n’existe pas
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
    table.insert(P.txreq, kv)
    if ns.Emit then ns.Emit("debug:changed") end
    return kv.id
end

function GLOG.Pending_ListTXREQ()
    local P = GuildLogisticsDB and GuildLogisticsDB.pending or {}
    return (P and P.txreq) or {}
end

function GLOG.Pending_FlushToMaster(master)
    local P = GuildLogisticsDB and GuildLogisticsDB.pending or {}
    if not P or not P.txreq or #P.txreq == 0 then return 0 end

    -- Destinataire par défaut : GM effectif (rang 0)
    if not master or master == "" then
        if GLOG.GetGuildMasterCached then master = select(1, GLOG.GetGuildMasterCached()) end
    end
    if not master or master == "" then return 0 end

    local sent = 0
    for i = 1, #P.txreq do
        local kv = P.txreq[i]
        if kv then
            GLOG.Comm_Whisper(master, "TX_REQ", kv)
            sent = sent + 1
        end
    end
    P.txreq = {}
    if ns.Emit then ns.Emit("debug:changed") end
    return sent
end

-- (Optionnel pour l’UI Debug — si tu veux alimenter une 3e liste)
function GLOG.GetPendingOutbox()
    local t = {}
    for _, kv in ipairs(GLOG.Pending_ListTXREQ() or {}) do
        t[#t+1] = {
            ts   = safenum(kv.ts, 0),
            type = "TX_REQ",
            info = string.format("%s : %+dg", tostring(kv.who or "?"), safenum(kv.delta,0)),
            id   = tostring(kv.id or ""),
        }
    end
    table.sort(t, function(a,b) return safenum(a.ts,0) > safenum(b.ts,0) end)
    return t
end

-- ===== Dépenses/Lots (émission GM) =====
-- Diffusion : création d’un lot (utilisé par Core.Lot_Create)
function GLOG.BroadcastLotCreate(l)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.meta = GuildLogisticsDB.meta or {}
    local rv = safenum(GuildLogisticsDB.meta.rev, 0) + 1
    GuildLogisticsDB.meta.rev = rv
    GuildLogisticsDB.meta.lastModified = now()

    local payload = {
        id = safenum(l.id, 0),
        n  = l.name or ("Lot " .. tostring(l.id or "")),
        N  = safenum(l.sessions, 1),
        u  = safenum(l.used, 0),
        t  = safenum(l.totalCopper, 0),
        I  = {},
        rv = rv,
        lm = GuildLogisticsDB.meta.lastModified,
    }
    for _, eid in ipairs(l.itemIds or {}) do payload.I[#payload.I+1] = safenum(eid, 0) end
    GLOG.Comm_Broadcast("LOT_CREATE", payload)
end

-- Diffusion : suppression d’un lot (utilisé par Core.Lot_Delete)
function GLOG.BroadcastLotDelete(id)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.meta = GuildLogisticsDB.meta or {}
    local rv = safenum(GuildLogisticsDB.meta.rev, 0) + 1
    GuildLogisticsDB.meta.rev = rv
    GuildLogisticsDB.meta.lastModified = now()
    GLOG.Comm_Broadcast("LOT_DELETE", { id = safenum(id,0), rv = rv, lm = GuildLogisticsDB.meta.lastModified })
end

-- Diffusion : consommation de plusieurs lots (utilisé par Core.Lots_ConsumeMany)
function GLOG.BroadcastLotsConsume(ids)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.meta = GuildLogisticsDB.meta or {}
    local rv = safenum(GuildLogisticsDB.meta.rev, 0) + 1
    GuildLogisticsDB.meta.rev = rv
    GuildLogisticsDB.meta.lastModified = now()
    GLOG.Comm_Broadcast("LOT_CONSUME", { ids = ids or {}, rv = rv, lm = GuildLogisticsDB.meta.lastModified })
end

-- Conserve l'id alloué par le logger et versionne correctement.
function GLOG.BroadcastExpenseAdd(p)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.meta     = GuildLogisticsDB.meta     or {}
    GuildLogisticsDB.expenses = GuildLogisticsDB.expenses or { list = {}, nextId = 1 }

    local id = safenum(p.id, 0)
    if id <= 0 then
        id = safenum(GuildLogisticsDB.expenses.nextId, 1)
        GuildLogisticsDB.expenses.nextId = id + 1
    else
        -- S’assure que la séquence locale reste > id
        local nextId = safenum(GuildLogisticsDB.expenses.nextId, 1)
        if (id + 1) > nextId then GuildLogisticsDB.expenses.nextId = id + 1 end
    end

    local rv = safenum((GuildLogisticsDB.meta and GuildLogisticsDB.meta.rev), 0) + 1
    GuildLogisticsDB.meta.rev = rv
    GuildLogisticsDB.meta.lastModified = now()

    GLOG.Comm_Broadcast("EXP_ADD", {
        id  = id,
        i   = safenum(p.i, 0),
        q   = safenum(p.q, 1),
        c   = safenum(p.c, 0),
        src = p.src or p.s,
        sid = safenum(p.sid, 0),
        l   = safenum(p.l, 0),
        rv  = rv,
        lm  = GuildLogisticsDB.meta.lastModified,
    })

end

function GLOG.BroadcastExpenseSplit(p)
    -- Ne bloque plus sur IsMaster : l'appelant côté UI est déjà restreint
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.meta     = GuildLogisticsDB.meta     or {}
    GuildLogisticsDB.expenses = GuildLogisticsDB.expenses or { list = {}, nextId = 1 }

    local nowF = now or time
    local rv = safenum((GuildLogisticsDB.meta and GuildLogisticsDB.meta.rev), 0) + 1
    GuildLogisticsDB.meta.rev = rv
    GuildLogisticsDB.meta.lastModified = nowF()

    -- ✅ Supporte p.add (objet) ET champs "aplatis" pour compat réseau
    local add      = p.add or {}
    local addId    = safenum(p.addId, 0);   if addId == 0 then addId = safenum(add.id, 0) end
    local addI     = safenum(p.addI,  0);   if addI  == 0 then addI  = safenum(add.i,  0) end
    local addQ     = safenum(p.addQ,  0);   if addQ  == 0 then addQ  = safenum(add.q,  0) end
    local addC     = safenum(p.addC,  0);   if addC  == 0 then addC  = safenum(add.c,  0) end
    local addSid   = safenum(p.addSid,0);   if addSid== 0 then addSid= safenum(add.sid,0) end
    local addLot   = safenum(p.addLot,0);   if addLot== 0 then addLot= safenum(add.l,  0) end

    if GLOG and GLOG.Debug then
        GLOG.Debug("SEND","EXP_SPLIT","id=", p and p.id, "addId=", addId, "q=", addQ, "c=", addC)
    end

    -- 📦 Message "aplati" (pas d'objet imbriqué) pour éviter add=[]
    GLOG.Comm_Broadcast("EXP_SPLIT", {
        id     = safenum(p.id, 0),
        nq     = safenum(p.nq, 0),
        nc     = safenum(p.nc, 0),
        addId  = addId,
        addI   = addI,
        addQ   = addQ,
        addC   = addC,
        addSid = addSid,
        addLot = addLot,
        rv     = rv,
        lm     = GuildLogisticsDB.meta.lastModified,
    })
end

-- ➕ Utils split/sync (copie et normalisation sûres)
local function _ensureUniqueExpenseId(list, id)
    local used, maxId = {}, 0
    for _, x in ipairs(list or {}) do
        local xid = tonumber(x.id or 0) or 0
        used[xid] = true
        if xid > maxId then maxId = xid end
    end
    local nid = tonumber(id or 0) or 0
    if nid <= 0 then nid = maxId + 1 end
    while used[nid] do nid = nid + 1 end
    return nid
end

local function _cloneExpenseWithMeta(src, override)
    local t = {}
    t.id       = override and override.id       or src.id
    t.ts       = override and override.ts       or (src.ts or time())
    t.qty      = override and override.qty      or src.qty
    t.copper   = override and override.copper   or src.copper
    t.sourceId = override and override.sourceId or src.sourceId
    t.itemID   = override and override.itemID   or src.itemID
    t.itemLink = override and override.itemLink or src.itemLink
    t.itemName = override and override.itemName or src.itemName
    t.lotId    = override and override.lotId    or src.lotId
    return t
end

local function _deepcopyExpenses(e)
    local out = { list = {}, nextId = tonumber((e and e.nextId) or 1) or 1 }
    for i, it in ipairs((e and e.list) or {}) do
        out.list[i] = _cloneExpenseWithMeta(it)
    end
    return out
end

-- ➕ Diffusion GM : suppression d'une dépense
function GLOG.GM_RemoveExpense(id)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
    local rv = safenum((GuildLogisticsDB.meta and GuildLogisticsDB.meta.rev),0) + 1
    GuildLogisticsDB.meta.rev = rv
    GuildLogisticsDB.meta.lastModified = now()
    GLOG.Comm_Broadcast("EXP_REMOVE", { id = safenum(id,0), rv = rv, lm = GuildLogisticsDB.meta.lastModified })
end

-- ✨ Diffusion unifiée (iLvl + M+) dans un seul message
-- overrides = { ilvl, ilvlMax, mid, lvl, map, ts, by }
function GLOG.BroadcastStatusUpdate(overrides)
    overrides = overrides or {}
    local me = playerFullName()
    local nf = (ns and ns.Util and ns.Util.NormalizeFull) and ns.Util.NormalizeFull or tostring
    me = nf(me)

    if not (GLOG.IsPlayerInRosterOrReserve and GLOG.IsPlayerInRosterOrReserve(me)) then return end

    -- iLvl
    local ilvl    = overrides.ilvl
    local ilvlMax = overrides.ilvlMax
    if ilvl == nil and GLOG.ReadOwnEquippedIlvl then ilvl = GLOG.ReadOwnEquippedIlvl() end
    if ilvlMax == nil and GLOG.ReadOwnMaxIlvl     then ilvlMax = GLOG.ReadOwnMaxIlvl()     end

    -- Clé M+
    local mid, lvl, map = overrides.mid, overrides.lvl, tostring(overrides.map or "")
    if (mid == nil or lvl == nil or map == "") and GLOG.ReadOwnedKeystone then
        local _mid, _lvl, _map = GLOG.ReadOwnedKeystone()
        if mid == nil then mid = _mid end
        if lvl == nil then lvl = _lvl end
        if map == ""  then map = tostring(_map or "") end
    end
    if (map == "" or map == "Clé") and safenum(mid, 0) > 0 and GLOG.ResolveMKeyMapName then
        local nm = GLOG.ResolveMKeyMapName(mid); if nm and nm ~= "" then map = nm end
    end

    -- ✨ Côte M+
    local score = overrides.score
    if score == nil and GLOG.ReadOwnMythicPlusScore then score = GLOG.ReadOwnMythicPlusScore() end
    score = safenum(score, 0)

    local ts = safenum(overrides.ts, now())
    local by = tostring(overrides.by or me)

    -- ✅ Application locale systématique (si pas déjà appliquée en amont)
    if not overrides.localApplied then
        GuildLogisticsDB = GuildLogisticsDB or {}; GuildLogisticsDB.players = GuildLogisticsDB.players or {}
        local p = GuildLogisticsDB.players[me]   -- ⚠️ ne crée pas d'entrée
        local changed = false
        if p then
            -- iLvl (+ Max)
            if ilvl ~= nil and ts >= safenum(p.ilvlTs, 0) then
                p.ilvl   = math.floor(tonumber(ilvl) or 0)
                if ilvlMax ~= nil then
                    p.ilvlMax   = math.floor(tonumber(ilvlMax) or 0)
                    p.ilvlMaxTs = ts
                end
                p.ilvlTs   = ts
                p.ilvlAuth = by
                changed = true
                if ns.Emit then ns.Emit("ilvl:changed", me) end
            end
            -- Clé M+
            if safenum(lvl, 0) > 0 and ts >= safenum(p.mkeyTs, 0) then
                p.mkeyMapId = safenum(mid, 0)
                p.mkeyLevel = safenum(lvl, 0)
                p.mkeyName  = tostring(map or "")
                p.mkeyTs    = ts
                p.mkeyAuth  = by
                changed = true
                if ns.Emit then ns.Emit("mkey:changed", me) end
            end
            -- Côte M+
            if safenum(score, -1) >= 0 and ts >= safenum(p.mplusTs, 0) then
                p.mplusScore = safenum(score, 0)
                p.mplusTs    = ts
                p.mplusAuth  = by
                changed = true
                if ns.Emit then ns.Emit("mplus:changed", me) end
            end
            if changed and ns.RefreshAll then ns.RefreshAll() end
        end
    end

    -- ✉️ Diffusion réseau
    local payload = {
        name = me, ts = ts, by = by,
    }
    if ilvl    ~= nil then payload.ilvl    = math.floor(tonumber(ilvl)    or 0) end
    if ilvlMax ~= nil then payload.ilvlMax = math.floor(tonumber(ilvlMax) or 0) end
    if score > 0 then payload.score = score end
    if safenum(lvl,0) > 0 then
        if mid ~= nil then payload.mid = safenum(mid, 0) end
        payload.lvl = safenum(lvl, 0)
        if map ~= "" then payload.map = map end
    end

    GLOG.Comm_Broadcast("STATUS_UPDATE", payload)
end

-- 🧭 Compat : redirige les anciens appels vers le nouveau message unifié
function GLOG.BroadcastIlvlUpdate(name, a2, a3, a4, a5)
    local hasNew  = (a5 ~= nil) -- 5 params → nouvelle signature
    local ilvl    = math.floor(tonumber(a2) or 0)
    local ilvlMax = hasNew and math.floor(tonumber(a3) or 0) or nil
    local ts      = safenum(hasNew and a4 or a3, now())
    local by      = tostring((hasNew and a5) or a4 or name or "")
    GLOG.BroadcastStatusUpdate({ ilvl = ilvl, ilvlMax = ilvlMax, ts = ts, by = by })
end

function GLOG.BroadcastMKeyUpdate(name, mapId, level, mapName, ts, by)
    local mid = safenum(mapId, 0)
    local lvl = safenum(level, 0)
    local map = tostring(mapName or "")
    if (map == "" or map == "Clé") and mid > 0 and GLOG.ResolveMKeyMapName then
        local nm = GLOG.ResolveMKeyMapName(mid)
        if nm and nm ~= "" then map = nm end
    end
    GLOG.BroadcastStatusUpdate({ mid = mid, lvl = lvl, map = map, ts = safenum(ts, now()), by = tostring(by or "") })
end


function GLOG.GM_CreateLot(name, sessions, totalCopper, itemIds)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.lots = GuildLogisticsDB.lots or { list = {}, nextId = 1 }

    local id = safenum(GuildLogisticsDB.lots.nextId, 1)
    GuildLogisticsDB.lots.nextId = id + 1

    -- Versionnage
    GuildLogisticsDB.meta = GuildLogisticsDB.meta or {}
    local rv = safenum(GuildLogisticsDB.meta.rev, 0) + 1
    GuildLogisticsDB.meta.rev = rv
    GuildLogisticsDB.meta.lastModified = now()

    -- Calcul du total fiable côté GM si non fourni (ou incohérent)
    local total = 0
    if itemIds and #itemIds > 0 then
        for _, eid in ipairs(itemIds) do
            if GLOG.GetExpenseById then
                local _, it = GLOG.GetExpenseById(eid)
                if it then total = total + safenum(it.copper, 0) end
            end
        end
    end
    if safenum(totalCopper, 0) > 0 then total = safenum(totalCopper, 0) end

    -- Diffusion stricte : id, n, N, u, t, I (et méta)
    GLOG.Comm_Broadcast("LOT_CREATE", {
        id = id,
        n  = name,
        N  = safenum(sessions, 1),
        u  = 0,
        t  = safenum(total, 0),
        I  = itemIds or {},
        rv = rv,
        lm = GuildLogisticsDB.meta.lastModified,
    })
end

function GLOG.GM_DeleteLot(id)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
    local rv = safenum((GuildLogisticsDB.meta and GuildLogisticsDB.meta.rev),0) + 1
    GuildLogisticsDB.meta.rev = rv
    GuildLogisticsDB.meta.lastModified = now()
    GLOG.Comm_Broadcast("LOT_DELETE", { id=safenum(id,0), rv=rv, lm=GuildLogisticsDB.meta.lastModified })
end

function GLOG.GM_ConsumeLots(ids)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
    local rv = safenum((GuildLogisticsDB.meta and GuildLogisticsDB.meta.rev),0) + 1
    GuildLogisticsDB.meta.rev = rv
    GuildLogisticsDB.meta.lastModified = now()
    GLOG.Comm_Broadcast("LOT_CONSUME", { ids = ids or {}, rv=rv, lm=GuildLogisticsDB.meta.lastModified })
end

-- ➕ Diffusion Historique (GM uniquement)
function GLOG.BroadcastHistoryAdd(p)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
    GuildLogisticsDB.meta = GuildLogisticsDB.meta or {}
    local rv = safenum(GuildLogisticsDB.meta.rev, 0) + 1
    GuildLogisticsDB.meta.rev = rv
    GuildLogisticsDB.meta.lastModified = now()
    GLOG.Comm_Broadcast("HIST_ADD", {
        h  = safenum(p.hid,0),
        ts = safenum(p.ts, now()),
        t  = safenum(p.total or p.t, 0),
        p  = safenum(p.per or p.p, 0),
        c  = safenum(p.count or p.c or #(p.names or p.participants or {}), 0),
        N  = p.names or p.participants or {},
        r  = safenum(p.r or (p.refunded and 1 or 0), 0),
        rv = rv, lm = GuildLogisticsDB.meta.lastModified,
    })
end

function GLOG.BroadcastHistoryRefund(hid, ts, flag)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
    GuildLogisticsDB.meta = GuildLogisticsDB.meta or {}
    local rv = safenum(GuildLogisticsDB.meta.rev, 0) + 1
    GuildLogisticsDB.meta.rev = rv
    GuildLogisticsDB.meta.lastModified = now()
    GLOG.Comm_Broadcast("HIST_REFUND", {
        h  = safenum(hid, 0),
        ts = safenum(ts, 0),
        r  = flag and 1 or 0,
        rv = rv,
        lm = GuildLogisticsDB.meta.lastModified,
    })
end

function GLOG.BroadcastHistoryDelete(hid)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
    GuildLogisticsDB.meta = GuildLogisticsDB.meta or {}
    local rv = safenum(GuildLogisticsDB.meta.rev, 0) + 1
    GuildLogisticsDB.meta.rev = rv
    GuildLogisticsDB.meta.lastModified = now()
    GLOG.Comm_Broadcast("HIST_DEL", {
        h = tostring(hid or ""),
        rv = rv, lm = GuildLogisticsDB.meta.lastModified,
    })
end

-- ===== Meta helpers =====
local function incRev()
    GuildLogisticsDB = GuildLogisticsDB or {}; GuildLogisticsDB.meta = GuildLogisticsDB.meta or {}
    GuildLogisticsDB.meta.rev = safenum(GuildLogisticsDB.meta.rev, 0) + 1
    GuildLogisticsDB.meta.lastModified = now()
    return GuildLogisticsDB.meta.rev
end

-- ===== Handshake / Init =====
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

    -- ✅ Marqueur d’amorçage : on autorise la réception de réponses dès maintenant
    GLOG._helloSent  = true
    GLOG._lastHelloHid = hid

    GLOG.Comm_Broadcast("HELLO", {
        hid = hid, rv = rv_me, player = me, caps = "OFFER|GRANT|TOKEN1",
        ver = (GLOG.GetAddonVersion and GLOG.GetAddonVersion()) or ""
    })

end


function GLOG.Comm_Init()
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

    -- Normalisation éventuelle du master stocké (realm)
    if GuildLogisticsDB and GuildLogisticsDB.meta and GuildLogisticsDB.meta.master then
        local m = GuildLogisticsDB.meta.master
        local n, r = m:match("^(.-)%-(.+)$")
        if not r then
            local _, realm = UnitFullName("player")
            GuildLogisticsDB.meta.master = m .. "-" .. (realm or "")
        end
    end

    if not GLOG._commFrame then
        local f = CreateFrame("Frame")
        f:RegisterEvent("CHAT_MSG_ADDON")
        f:SetScript("OnEvent", function(_, _, prefix, msg, channel, sender) onAddonMsg(prefix, msg, channel, sender) end)
        GLOG._commFrame = f
    end

    -- Nettoyage des fragments périmés
    if not GLOG._inboxCleaner then
        GLOG._inboxCleaner = C_Timer.NewTicker(10, function()
            local cutoff = now() - 30
            for k, box in pairs(Inbox) do if (box.ts or 0) < cutoff then Inbox[k] = nil end end
        end)
    end

    -- ✅ Démarrage automatique : envoie un HELLO pour ouvrir la découverte
    if not GLOG._helloAutoStarted then
        GLOG._helloAutoStarted = true
        C_Timer.After(1.0, function()
            if IsInGuild and IsInGuild() then
                GLOG.Sync_RequestHello()
            end
        end)
    end

    -- ✏️ Ne JAMAIS s’auto-désigner GM : on prend le roster (rang 0) si dispo
    C_Timer.After(5, function()
        if not IsInGuild or not IsInGuild() then return end
        if not GuildLogisticsDB then GuildLogisticsDB = {} end
        GuildLogisticsDB.meta = GuildLogisticsDB.meta or {}

        if not GuildLogisticsDB.meta.master or GuildLogisticsDB.meta.master == "" then
            local gmName = GLOG.GetGuildMasterCached and select(1, GLOG.GetGuildMasterCached()) or ""
            GuildLogisticsDB.meta.master = gmName or ""
            if ns.Emit then ns.Emit("meta:changed") end
        end
    end)


end

-- ===== API publique Debug =====
function GLOG.GetHelloElect() return HelloElect end
-- ➕ Accès ciblé par hid (utilisé par certains onglets Debug)
function GLOG._GetHelloElect(hid)
    return HelloElect and HelloElect[hid]
end

function GLOG.ForceMyVersion()
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
    local rv = incRev()
    local snap = GLOG._SnapshotExport()
    snap.rv = rv
    GLOG.Comm_Broadcast("SYNC_FULL", snap)
    LastFullSentAt = now()
end

-- ===== Décodage =====
function decode(s) return decodeKV(s) end
function encode(s) return encodeKV(s) end

-- ✅ Bootstrap de secours : s’assure que Comm_Init est bien appelé
if not GLOG._autoBootstrap then
    local boot = CreateFrame("Frame")
    boot:RegisterEvent("ADDON_LOADED")
    boot:RegisterEvent("PLAYER_LOGIN")
    boot:SetScript("OnEvent", function(_, ev, name)
        if ev == "ADDON_LOADED" and name and name ~= ADDON then return end
        if GLOG._commReady then return end
        GLOG._commReady = true
        if type(GLOG.Comm_Init) == "function" then
            GLOG.Comm_Init()
        end
    end)
    GLOG._autoBootstrap = true
end

-- =========================
-- Patch de réception Alias
-- =========================
-- On enveloppe le handler principal pour capter l'alias sans toucher au gros corps de fonction.
do
    local _OldHandleFull = GLOG._HandleFull
    function GLOG._HandleFull(sender, msgType, kv)
        local ret = _OldHandleFull(sender, msgType, kv)
        local t = tostring(msgType or ""):upper()
        if (t == "ROSTER_UPSERT" or t == "ROSTER_RESERVE") and kv then
            local name = kv.name
            if (not name or name == "") and kv.uid and GLOG.GetNameByUID then
                name = GLOG.GetNameByUID(kv.uid)
            end
            if name and kv.alias and GLOG.SetAliasLocal then
                local nf = (ns and ns.Util and ns.Util.NormalizeFull) and ns.Util.NormalizeFull or tostring
                GLOG.SetAliasLocal(nf(name), kv.alias)
            end
        end
        return ret
    end
end
