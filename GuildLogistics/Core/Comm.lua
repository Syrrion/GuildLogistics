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
    -- Fallback minimal basé uniquement sur players[*].uid (aucune table uids)
    local function _ensureDB()
        GuildLogisticsDB = GuildLogisticsDB or {}
        GuildLogisticsDB.meta    = GuildLogisticsDB.meta    or {}
        GuildLogisticsDB.players = GuildLogisticsDB.players or {}
        GuildLogisticsDB.meta.uidSeq = GuildLogisticsDB.meta.uidSeq or 1
        return GuildLogisticsDB
    end

    function GLOG.GetOrAssignUID(name)
        local db   = _ensureDB()
        local full = tostring(name or "")
        db.players[full] = db.players[full] or { solde = 0, reserved = true }
        if db.players[full].uid then return db.players[full].uid end
        local nextId = tonumber(db.meta.uidSeq or 1) or 1
        db.players[full].uid = nextId
        db.meta.uidSeq = nextId + 1
        return db.players[full].uid
    end

    function GLOG.GetNameByUID(uid)
        local db = _ensureDB()
        local n  = tonumber(uid)
        if not n then return nil end
        for full, rec in pairs(db.players or {}) do
            if tonumber(rec and rec.uid) == n then return full end
        end
        return nil
    end

    function GLOG.MapUID(uid, name)
        local db   = _ensureDB()
        local full =
            (GLOG.ResolveFullName and GLOG.ResolveFullName(name, { strict = true }))
            or (type(name)=="string" and name:find("%-") and name)
            or tostring(name or "")
        local nuid = tonumber(uid)
        if not nuid then return nil end
        db.players[full] = db.players[full] or { solde=0, reserved=true }
        db.players[full].uid = nuid
        return nuid
    end

    function GLOG.UnmapUID(uid)
        local db = _ensureDB()
        local n  = tonumber(uid)
        if not n then return end
        for _, rec in pairs(db.players or {}) do
            if tonumber(rec and rec.uid) == n then rec.uid = nil; return end
        end
    end

    function GLOG.EnsureRosterLocal(name)
        local db   = _ensureDB()
        local full = tostring(name or "")
        db.players[full] = db.players[full] or { solde=0, reserved=true }
        if db.players[full].reserved == nil then db.players[full].reserved = true end
        return db.players[full]
    end
end

-- ===== Constantes / État =====
local PREFIX   = "GLOG2"
local MAX_PAY  = 200   -- fragmentation des messages
local Seq      = 0     -- séquence réseau

-- Limitation d'émission (paquets / seconde)
local OUT_MAX_PER_SEC = -1

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
local playerFullName = (U and U.playerFullName) or function()
    local n = (UnitName and UnitName("player")) or "?"
    local rn = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
    rn = tostring(rn):gsub("%s+",""):gsub("'","")
    return (rn ~= "" and (n.."-"..rn)) or n
end
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
    local len = #s
    local i   = 1
    local buf = {}

    local function flush(part)
        if part == "" then return end
        local eq = part:find("=", 1, true)
        if not eq then return end
        local k = part:sub(1, eq - 1)
        local v = part:sub(eq + 1)

        if v:match("^%[.*%]$") then
            -- Array: on réutilise le parseur existant (échappements \n, \\, \,, \], ||)
            local body = v:sub(2, -2)
            local list, abuf, esc = {}, {}, false
            for p = 1, #body do
                local ch = body:sub(p, p)
                if esc then
                    abuf[#abuf+1] = ch; esc = false
                else
                    if ch == "\\" then
                        esc = true
                    elseif ch == "," then
                        list[#list+1] = table.concat(abuf); abuf = {}
                    else
                        abuf[#abuf+1] = ch
                    end
                end
            end
            list[#list+1] = table.concat(abuf)

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
            -- String simple (|| = pipe littéral)
            v = v:gsub("\\n", "\n"):gsub("||", "|")
            t[k] = v
        end
    end

    -- Scanner top-level: '||' = pipe échappé, '|' seul = séparateur
    while i <= len do
        local ch = s:sub(i, i)
        if ch == "|" then
            if s:sub(i + 1, i + 1) == "|" then
                buf[#buf+1] = "|"  -- pipe littéral
                i = i + 2
            else
                flush(table.concat(buf)); buf = {}
                i = i + 1
            end
        else
            buf[#buf+1] = ch
            i = i + 1
        end
    end
    flush(table.concat(buf))
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
    -- On garde 5s pour l'affichage éventuel, puis on libère l'élection de la mémoire
    C_Timer.After(5, function()
        if HelloElect then HelloElect[hid] = nil end
        if ns and ns.Emit then ns.Emit("debug:changed") end
    end)

end

local function _scheduleOfferReply(hid, initiator, rv_init)
    -- Inhibition si FULL récent ≥ mon rv (⚠️ sauf GM pour priorité absolue)
    local iAmGM = (GLOG.IsNameGuildMaster and GLOG.IsNameGuildMaster(playerFullName())) or false
    if not iAmGM then
        if (now() - (LastFullSeenAt or 0)) < FULL_INHIBIT_SEC and (LastFullSeenRv or -1) >= safenum(getRev(), 0) then
            return
        end
    end

    -- ✅ Nouvelle règle : on ne dépend plus du rv du GM.
    -- On proposera une synchro si (et seulement si) mon rv > rv_init.

    -- Anti-spam par initiateur (conservé même pour GM)
    local k = _norm(initiator)
    local last = OfferCooldown[k] or 0
    if (now() - last) < OFFER_RATE_LIMIT_SEC then return end
    OfferCooldown[k] = now()

    local myRv  = safenum(getRev(), 0)
    local est   = _estimateSnapshotSize()
    local h     = _hashHint(string.format("%s|%d|%s", playerFullName(), myRv, hid))
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
            hid  = hid,
            rv   = rv_peer,
            est  = est,
            h    = h,
            from = playerFullName(),
            m    = "rv_gap",
        })
    end)
end

-- File d'envoi temporisée
local OutQ      = {}
local OutTicker = nil

-- Boîtes aux lettres (réassemblage fragments)
local Inbox     = {}

-- 🔁 Anti-doublon : clé = "seq@sender" (TTL court, purgé par ticker)
local Processed = {}   -- [ "123@nom-realm" ] = ts

-- ➕ Suivi d’une synchro FULL en cours par émetteur (pour piloter l’UI)
local ActiveFullSync = ActiveFullSync or {}   -- [senderKey]=true

-- Journalisation (onglet Debug)
local DebugLog  = DebugLog or {} -- { {dir,type,size,chan,channel,dist,target,from,sender,emitter,seq,part,total,raw,state,status,stateText} ... }
local SendLogIndexBySeq = SendLogIndexBySeq or {}  -- index "pending" ENVOI par seq
local RecvLogIndexBySeq = RecvLogIndexBySeq or {}  -- index RECU par seq

function GLOG.Debug_GetMemStats()
    local function len(t) local n=0; for _ in pairs(t or {}) do n=n+1 end; return n end
    local mem = (collectgarbage and collectgarbage("count")) or 0
    return {
        mem = mem,           -- en KiB
        outq = #OutQ,
        inbox = len(Inbox),
        recvIdx = len(RecvLogIndexBySeq),
        sendIdx = len(SendLogIndexBySeq),
        debugLog = #DebugLog,
    }
end

function GLOG.Debug_PrintMemStats()
    local s = GLOG.Debug_GetMemStats()
    print(("GuildLogistics mem: %.1f KiB | OutQ=%d Inbox=%d RecvIdx=%d SendIdx=%d DebugLog=%d")
        :format(s.mem, s.outq, s.inbox, s.recvIdx, s.sendIdx, s.debugLog))
end

-- Évier : neutralise toute écriture dans les index quand le debug est OFF
local function _sinkIndexTable()
    return setmetatable({}, {
        __newindex = function() end,
        __index    = function() return nil end
    })
end
if GLOG and GLOG.IsDebugEnabled and not GLOG.IsDebugEnabled() then
    SendLogIndexBySeq = _sinkIndexTable()
    RecvLogIndexBySeq = _sinkIndexTable()
end

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

function GLOG.Debug_GetMemStats()
    local function len(t) local n=0; for _ in pairs(t or {}) do n=n+1 end; return n end
    local mem = (collectgarbage and collectgarbage("count")) or 0
    return { mem=mem, outq=#OutQ, inbox=len(Inbox), recvIdx=len(RecvLogIndexBySeq),
             sendIdx=len(SendLogIndexBySeq), debugLog=#DebugLog, he=len(HelloElect or {}) }
end

function GLOG.Debug_PrintMemStats()
    local s = GLOG.Debug_GetMemStats()
    print(("GuildLogistics mem: %.1f KiB | OutQ=%d Inbox=%d RecvIdx=%d SendIdx=%d DebugLog=%d Hello=%d")
        :format(s.mem, s.outq, s.inbox, s.recvIdx, s.sendIdx, s.debugLog, s.he))
end

-- Nettoyage agressif des caches temporaires (utile en raid si la RAM grimpe)
function GLOG.Debug_BulkCleanup(opts)
    opts = opts or {}
    -- ⚠️ ceci peut interrompre une reconstitution en cours
    Inbox = {}
    if not opts.keepDiscovery then Discovery = {} end
    HelloElect = {}
    OfferCooldown = {}
    _HelloStatusSentTo = {}
    _NonCritSuppress = {}
    wipe(DebugLog); wipe(RecvLogIndexBySeq); wipe(SendLogIndexBySeq)
    if collectgarbage then collectgarbage("collect") end
    if ns and ns.Emit then ns.Emit("debug:changed") end
    print("GLOG: caches volatils purgés")
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
    local idle = 0   -- compte les ticks "sans travail"

    OutTicker = C_Timer.NewTicker(0.1, function()
        local t = now()
        if OUT_MAX_PER_SEC > 0 and (t - last) < (1.0 / OUT_MAX_PER_SEC) then return end
        last = t

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
    -- ⚠️ Attention : 'kv.t' est réservé au TYPE de message par l'enveloppe réseau.
    -- Ne pas réutiliser 't' pour des champs applicatifs dans les payloads (utiliser 'tc', 'amt', etc.).

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
    kv = kv or {}
    -- Injecter la version sur TOUTES les transactions sortantes (guilde)
    if kv.ver == nil then
        local ver = (GLOG.GetAddonVersion and GLOG.GetAddonVersion()) or ""
        if ver ~= "" then kv.ver = ver end
    end
    _send(typeName, "GUILD", nil, kv)
end

function GLOG.Comm_Whisper(target, msgType, data)
    if _NONCRIT_TYPES and _isSuppressedTo and _NONCRIT_TYPES[msgType] and _isSuppressedTo(target) then
        return
    end

    data = data or {}
    -- Injecter la version sur TOUT whisper sortant
    if data.ver == nil then
        local ver = (GLOG.GetAddonVersion and GLOG.GetAddonVersion()) or ""
        if ver ~= "" then data.ver = ver end
    end

    _send(msgType, "WHISPER", target, data)

    if msgType == "SYNC_OFFER" and _suppressTo then
        _suppressTo(target, (HELLO_WAIT_SEC or 5) + 2)
    elseif msgType == "SYNC_GRANT" and _suppressTo then
        _suppressTo(target, 2)
    end
    return true
end

-- ===== Application snapshot (import/export compact) =====
function GLOG._SnapshotExport()
    -- ==== DB minimale ====
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.meta     = GuildLogisticsDB.meta     or {}
    GuildLogisticsDB.players  = GuildLogisticsDB.players  or {}
    GuildLogisticsDB.expenses = GuildLogisticsDB.expenses or { list = {}, nextId = 1 }
    GuildLogisticsDB.lots     = GuildLogisticsDB.lots     or { list = {}, nextId = 1 }

    local meta = GuildLogisticsDB.meta

    -- ==== helpers ====
    local function escText(s)
        s = tostring(s or "")
        return (s:gsub("[:,%|%[%]]", function(ch) return string.format("%%%02X", string.byte(ch)) end))
    end
    local function normRealm(realm)
        realm = tostring(realm or "")
        if realm == "" then return realm end
        local first, allsame
        for seg in realm:gmatch("[^%-]+") do
            if not first then first=seg; allsame=true
            elseif seg ~= first then allsame=false end
        end
        if allsame and first then return first end
        return realm
    end
    local function splitName(full)
        local base, realm = tostring(full):match("^([^%-]+)%-(.+)$")
        return base or tostring(full), realm or ""
    end
    local function uidNumFor(full)
        local uid = (GLOG.GetOrAssignUID and GLOG.GetOrAssignUID(full)) or nil
        local n = tonumber(uid) or 0
        return n
    end
    local function aliasFor(full, baseName)
        local a = (GLOG.GetAliasFor and GLOG.GetAliasFor(full)) or baseName
        return a or baseName
    end

    -- ===== joueurs et royaumes SANS fusion =====
    -- On exporte chaque personnage tel quel (Nom-Complet), sans regroupement par baseName.

    -- 1) Construire l'ensemble des royaumes utilisés
    local realmSet = {}
    for full, rec in pairs(GuildLogisticsDB.players) do
        local base, realm = splitName(full)
        local nrealm = normRealm(realm)
        if nrealm ~= "" then realmSet[nrealm] = true end
    end

    -- 2) Construire R (réalms) trié alpha
    local realms = {}
    for r,_ in pairs(realmSet) do realms[#realms+1]=r end
    table.sort(realms, function(a,b) return a:lower() < b:lower() end)
    local ridByRealm = {}
    local R = {}
    for i,r in ipairs(realms) do
        ridByRealm[r]=i
        R[#R+1]=tostring(i)..":"..escText(r)
    end

    -- 3) Construire P sans fusion (une entrée par personnage complet)
    local P = {}
    for full, rec in pairs(GuildLogisticsDB.players) do
        local base, realm = splitName(full)
        local nrealm = normRealm(realm)
        local rid = (nrealm ~= "" and ridByRealm[nrealm]) or 0
        local aliasText = (aliasFor(full, base) or base)
        if aliasText == base then aliasText = "@" end
        local uidN = uidNumFor(full)
        local balance = safenum(rec.solde, 0)
        local res = rec.reserved and 1 or 0

        P[#P+1] = table.concat({
            tostring(uidN), tostring(rid), escText(base), escText(aliasText),
            tostring(balance), tostring(res)
        }, ":")
    end
    table.sort(P, function(a,b) return a:lower() < b:lower() end)


    -- ===== Lots & labels =====
    local T, L = {}, {}
    for _,l in ipairs(GuildLogisticsDB.lots.list or {}) do
        local lid = safenum(l.id,0)
        T[#T+1] = tostring(lid) .. ":" .. escText(tostring(l.name or ("Lot "..lid)))
        L[#L+1] = table.concat({
            tostring(lid),
            tostring(safenum(l.sessions,1)),
            tostring(safenum(l.used,0)),
            tostring(safenum(l.totalCopper,0))
        }, ":")
    end

    -- ===== Dépenses & LE =====
    local E, LE = {}, {}
    for _, e in ipairs(GuildLogisticsDB.expenses.list or {}) do
        local srcId = safenum(e.sourceId or 0, 0)
        E[#E+1] = table.concat({
            tostring(safenum(e.id,0)),
            tostring(safenum(e.qty,0)),
            tostring(safenum(e.copper,0)),
            tostring(srcId),
            tostring(safenum(e.itemID,0))
        }, ":")
        local lid = safenum(e.lotId, 0)
        if lid > 0 then
            LE[#LE+1] = tostring(lid) .. ":" .. tostring(safenum(e.id,0))
        end
    end

    -- ===== Historique =====
    local H = {}
    for _, h in ipairs(GuildLogisticsDB.history or {}) do
        local ts      = safenum(h.ts, 0)
        local total   = safenum(h.total, 0)
        local count   = safenum(h.count, (h.participants and #h.participants) or 0)
        local refund  = (h.refunded and 1 or 0)

        local pidsSet, pids = {}, {}
        for _, name in ipairs(h.participants or {}) do
            -- Utilise l'UID du personnage complet, sans passage par un « canon »
            local uidNum = uidNumFor(tostring(name))
            if uidNum and uidNum > 0 and not pidsSet[uidNum] then
                pidsSet[uidNum] = true
                pids[#pids+1] = tostring(uidNum)
            end
        end

        local lots = {}
        for _, li in ipairs(h.lots or {}) do
            if type(li) == "table" then
                local lid = safenum(li.id, 0)
                if lid > 0 then lots[#lots+1] = tostring(lid) end
            end
        end

        local head = table.concat({ tostring(ts), tostring(total), tostring(count), tostring(refund) }, ":")
        local rec  = head .. "|" .. table.concat(pids, ",") .. "|" .. table.concat(lots, ",")
        H[#H+1] = rec
    end

    -- ===== KV final =====
    return {
        sv = 3,
        rv = safenum(meta.rev, 0),
        lm = safenum(meta.lastModified, now()),
        fs = safenum(meta.fullStamp, now()),
        R  = R,
        P  = P,
        T  = T,
        L  = L,
        E  = E,
        LE = LE,
        H  = H,
    }
end


function GLOG._SnapshotApply(kv)
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.meta     = GuildLogisticsDB.meta     or {}
    GuildLogisticsDB.players  = {}
    GuildLogisticsDB.expenses = { list = {}, nextId = 1 }
    GuildLogisticsDB.lots     = { list = {}, nextId = 1 }

    local meta = GuildLogisticsDB.meta
    meta.rev         = safenum(kv.rv, 0)
    meta.lastModified= safenum(kv.lm, now())
    meta.fullStamp   = safenum(kv.fs, now())
    -- helpers
    local function unescText(s)
        s = tostring(s or "")
        return (s:gsub("%%(%x%x)", function(h)
            local n = tonumber(h, 16); return n and string.char(n) or ("%")..h
        end))
    end
    local function normRealm(realm)
        realm = tostring(realm or "")
        if realm == "" then return realm end
        local first, allsame
        for seg in realm:gmatch("[^%-]+") do
            if not first then first=seg; allsame=true
            elseif seg ~= first then allsame=false end
        end
        if allsame and first then return first end
        return realm
    end

    local sv = tostring(kv.sv or "")
    if sv ~= "3" and sv ~= "3.0" then return end

    -- 1) R (réalms) avec normalisation anti-duplication
    local realmById = {}
    for _, s in ipairs(kv.R or {}) do
        local rid, label = s:match("^(%-?%d+):(.*)$")
        if rid then
            local realm = unescText(label)
            realmById[tonumber(rid) or 0] = normRealm(realm)
        end
    end

    -- 2) P (brut par PERSONNAGE COMPLET, pas de fusion)
    -- uid:rid:name:alias:balance:res
    for _, s in ipairs(kv.P or {}) do
        local uid, rid, name, alias, bal, res = s:match("^([%-%d]+):([%-%d]+):(.-):(.-):([%-%d]+):([%-%d]+)$")
        if uid then
            local uidNum = tonumber(uid) or 0
            local ridNum = tonumber(rid) or 0
            local base   = unescText(name)
            local aliasS = unescText(alias)
            if aliasS == "@" then aliasS = base end
            local realm  = realmById[ridNum] or ""
            local full   = (U and U.NormalizeFull and U.NormalizeFull(base, realm))
                        or (realm ~= "" and (base.."-"..realm) or base)
            local balance= safenum(bal,0)
            local credit, debit = 0, 0
            if balance >= 0 then credit = balance else debit = -balance end

            GuildLogisticsDB.players[full] = {
                uid      = safenum(uidNum,0),
                solde    = safenum(balance,0),
                reserved = (safenum(res,0) == 1),
                alias    = aliasS,
            }


            local kMain = (GLOG.NormName and GLOG.NormName(full)) or string.lower(full)
        end
    end


    -- 3) T (id→nom)
    local LotNameById = {}
    for _, s in ipairs(kv.T or {}) do
        local lid, label = s:match("^(%-?%d+):(.*)$")
        if lid then
            LotNameById[safenum(lid,0)] = unescText(label)
        end
    end

    -- 4) L (lots)
    local LotsById = {}
    for _, s in ipairs(kv.L or {}) do
        local lid, sessions, used, tot = s:match("^([%-%d]+):([%-%d]+):([%-%d]+):([%-%d]+)$")
        if lid then
            local id = safenum(lid,0)
            local rec = {
                id = id,
                name = LotNameById[id] or ("Lot "..tostring(id)),
                sessions = safenum(sessions,1),
                used = safenum(used,0),
                totalCopper = safenum(tot,0),
                itemIds = {},
            }
            table.insert(GuildLogisticsDB.lots.list, rec)
            LotsById[id] = rec
            GuildLogisticsDB.lots.nextId = math.max(GuildLogisticsDB.lots.nextId or 1, id + 1)
        end
    end

    -- 5) E (dépenses)
    local ExpensesById = {}
    for _, s in ipairs(kv.E or {}) do
        local id, qty, copper, srcId, itemId = s:match("^([%-%d]+):([%-%d]+):([%-%d]+):([%-%d]+):([%-%d]+)$")
        if id then
            local e = {
                id     = safenum(id,0),
                qty    = safenum(qty,0),
                copper = safenum(copper,0),
                itemID = safenum(itemId,0),
            }
            local sid = safenum(srcId,0)
            if sid > 0 then e.sourceId = sid end
            table.insert(GuildLogisticsDB.expenses.list, e)
            GuildLogisticsDB.expenses.nextId = math.max(GuildLogisticsDB.expenses.nextId or 1, e.id + 1)
            ExpensesById[e.id] = e
        end
    end

    -- 6) LE (liaison et itemIds)
    for _, s in ipairs(kv.LE or {}) do
        local lid, eid = s:match("^([%-%d]+):([%-%d]+)$")
        if lid and eid then
            local Lrec = LotsById[safenum(lid,0)]
            local Erec = ExpensesById[safenum(eid,0)]
            if Lrec and Erec then
                Erec.lotId = Lrec.id
                -- IMPORTANT : Resources.lua attend des EXPENSE IDs dans lot.itemIds
                Lrec.itemIds = Lrec.itemIds or {}
                table.insert(Lrec.itemIds, Erec.id)
            end
            -- Backfill : si un lot n’a pas d’itemIds via LE, le reconstituer depuis les dépenses
            do
                -- Prépare un set par lot pour éviter les doublons
                local seenPerLot = {}
                for lid, Lrec in pairs(LotsById or {}) do
                    seenPerLot[lid] = {}
                    for _, eid in ipairs(Lrec.itemIds or {}) do
                        seenPerLot[lid][eid] = true
                    end
                end
                -- Balayer toutes les dépenses et rattacher par lotId
                for _, Erec in pairs(ExpensesById or {}) do
                    local lid = tonumber(Erec.lotId or 0) or 0
                    local Lrec = LotsById and LotsById[lid]
                    if Lrec then
                        Lrec.itemIds = Lrec.itemIds or {}
                        local seen = seenPerLot[lid]
                        if not seen[Erec.id] then
                            table.insert(Lrec.itemIds, Erec.id)
                            seen[Erec.id] = true
                        end
                    end
                end
            end
        end
    end

    -- 7) H (historique) : ts:total:count:refund|pids|lotIds
    GuildLogisticsDB.history = {}
    -- Build reverse map UID->full déjà en place via DB.uids
    for _, s in ipairs(kv.H or {}) do
        local line = tostring(s):gsub("%|%|", "|")
        local header, plist, llist = line:match("^(.-)%|(.-)%|(.*)$")
        if not header then
            header, plist = line:match("^(.-)%|(.*)$")
            llist = ""
        end
        local ts, total, count, refund = (header or ""):match("^([%-%d]+):([%-%d]+):([%-%d]+):([%-%d]+)$")
        local _ts     = safenum(ts,0)
        local _total  = safenum(total,0)
        local _count  = safenum(count,0)
        local _ref    = safenum(refund,0) == 1

        local participants = {}
        local seenP = {}
        for pid in tostring(plist or ""):gmatch("([^,]+)") do
            local n = tonumber(pid)
            if n and n > 0 then
                local full = (GLOG.GetNameByUID and GLOG.GetNameByUID(n))
                if full and not seenP[full] then
                    seenP[full] = true
                    participants[#participants+1] = full
                end
            end
        end

        local lots = {}
        for tok in tostring(llist or ""):gmatch("([^,]+)") do
            local lid = tonumber(tok)
            if lid and lid > 0 then
                local name = LotNameById[lid] or ("Lot "..tostring(lid))
                table.insert(lots, { id = lid, name = name })
            end
        end

        local per = (_count > 0) and math.floor(_total / _count) or 0
        if _ts > 0 then
            table.insert(GuildLogisticsDB.history, {
                ts = _ts, total = _total, perHead = per,
                count = _count, participants = participants, refunded = _ref,
                lots = lots,
            })
        end
    end

    if ns and ns.Emit then
        ns.Emit("players:changed")
        ns.Emit("expenses:changed")
        ns.Emit("lots:changed")
        ns.Emit("history:changed")
    end
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
            local full = (GLOG.ResolveFullName and GLOG.ResolveFullName(name, { strict = true }))
                    or (name:find("%-") and name)
                    or (uid and GLOG.GetNameByUID and GLOG.GetNameByUID(uid))
            if full and full ~= "" then
                local p = GuildLogisticsDB.players[full] or { solde=0, reserved=false }
                p.reserved = (tonumber(kv.res) or 0) ~= 0
                GuildLogisticsDB.players[full] = p
                meta.rev = (rv >= 0) and rv or myrv
                meta.lastModified = safenum(kv.lm, now())
                if ns.Emit then ns.Emit("roster:reserve", full, p.reserved) end
                refreshActive()
            else
                -- On ignore si on ne parvient pas à résoudre (mieux vaut ignorer que créer une mauvaise clé)
            end
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
            local rec = GuildLogisticsDB.players[full] or { solde = 0, reserved = true }
            rec.solde = safenum(rec.solde, 0) + safenum(kv.delta, 0)
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
                local rec = GuildLogisticsDB.players[full] or { solde = 0 }
                rec.solde = safenum(rec.solde, 0) + safenum(d, 0)
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
            if sender then
                local me = playerFullName and playerFullName()
                local same = (U and U.SamePlayer and U.SamePlayer(sender, me)) or (sender == me)
                if same then isSelf = true end
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
        -- Unifié : iLvl (+max) / Clé M+ (mid,lvl) / ✨ Score M+ (score)
        -- ➕ Extension : accepte un batch kv.S avec entrées "uid;ts;ilvl;ilvlMax;mid;lvl;score" (séparateur ';' → aucun anti-slash).
        --    Autorité = statusTimestamp (ts le plus récent l’emporte).
        --    ⚠️ N'initialise pas de nouveaux joueurs (on met à jour uniquement ceux existants).

        -- Compat: conserve le traçage de version d'addon si présent
        do
            local v_status = tostring(kv.ver or "")
            if v_status ~= "" and GLOG.SetPlayerAddonVersion then
                local who = tostring(kv.name or sender or "")
                GLOG.SetPlayerAddonVersion(who, v_status, tonumber(kv.ts) or time(), sender)
            end
        end

        local function _applyOne(pname, info)
            if not pname or pname == "" then return end
            GuildLogisticsDB = GuildLogisticsDB or {}; GuildLogisticsDB.players = GuildLogisticsDB.players or {}
            local p = GuildLogisticsDB.players[pname]      -- ⚠️ ne jamais créer ici
            if not p then return end

            local n_ts   = safenum(info.ts, now())
            local prev   = safenum(p.statusTimestamp, 0)
            local changed= false

            -- ===== iLvl =====
            local n_ilvl    = safenum(info.ilvl, -1)
            local n_ilvlMax = safenum(info.ilvlMax, -1)
            if n_ilvl >= 0 and n_ts >= prev then
                p.ilvl = math.floor(n_ilvl)
                if n_ilvlMax >= 0 then p.ilvlMax = math.floor(n_ilvlMax) end
                changed = true; if ns.Emit then ns.Emit("ilvl:changed", pname) end
            end

            -- ===== Clé M+ (mid/lvl) =====
            local n_mid = safenum(info.mid, -1)
            local n_lvl = safenum(info.lvl, -1)
            if (n_mid >= 0 or n_lvl >= 0) and n_ts >= prev then
                if n_mid >= 0 then p.mkeyMapId = n_mid end
                if n_lvl >= 0 then p.mkeyLevel = n_lvl end
                changed = true; if ns.Emit then ns.Emit("mkey:changed", pname) end
            end

            -- ✨ ===== Score M+ =====
            local n_score = safenum(info.score, -1)
            if n_score >= 0 and n_ts >= prev then
                p.mplusScore = n_score
                changed = true; if ns.Emit then ns.Emit("mplus:changed", pname) end
            end

            if changed and n_ts > prev then p.statusTimestamp = n_ts end
            if changed and ns.RefreshAll then ns.RefreshAll() end
        end

        local function _applyByUID(uid, info)
            uid = safenum(uid, -1)
            if uid < 0 then return end
            local name = (GLOG.GetNameByUID and GLOG.GetNameByUID(uid)) or nil
            if not name or name == "" then return end -- ⚠️ on n'invente pas d'entrée
            _applyOne(name, info)
        end

        -- 1) Batch (nouveau) : kv.S peut être une liste de chaînes "uid;ts;ilvl;ilvlMax;mid;lvl;score"
        if type(kv.S) == "table" then
            for _, rec in ipairs(kv.S) do
                if type(rec) == "string" then
                    -- Format UID + ';'
                    local uid, ts, ilvl, ilvlMax, mid, lvl, score =
                        rec:match("^([%d]+);([%-%d]+);([%-%d]+);([%-%d]+);([%-%d]+);([%-%d]+);([%-%d]+)$")
                    if uid and ts then
                        _applyByUID(uid, {
                            ts = safenum(ts, now()),
                            ilvl = safenum(ilvl, -1),
                            ilvlMax = safenum(ilvlMax, -1),
                            mid = safenum(mid, -1),
                            lvl = safenum(lvl, -1),
                            score = safenum(score, -1),
                        })
                    else
                        -- 🔁 Compat lecture ancien CSV à la virgule, soit "name,..." soit "uid,..."
                        local a,b,c,d,e,f,g = rec:match("^(.-),([%-%d]+),([%-%d]+),([%-%d]+),([%-%d]+),([%-%d]+),([%-%d]+)$")
                        if a and b then
                            local maybeUID = tonumber(a)
                            if maybeUID then
                                _applyByUID(maybeUID, {
                                    ts = safenum(b, now()),
                                    ilvl = safenum(c, -1), ilvlMax = safenum(d, -1),
                                    mid = safenum(e, -1),   lvl = safenum(f, -1),
                                    score = safenum(g, -1),
                                })
                            else
                                _applyOne(tostring(a or ""), {
                                    ts = safenum(b, now()),
                                    ilvl = safenum(c, -1), ilvlMax = safenum(d, -1),
                                    mid = safenum(e, -1),   lvl = safenum(f, -1),
                                    score = safenum(g, -1),
                                })
                            end
                        end
                    end
                elseif type(rec) == "table" then
                    local uid = rec.uid or rec.u
                    local name = rec.name or rec.n
                    local info = {
                        ts = safenum(rec.ts, now()),
                        ilvl = rec.ilvl, ilvlMax = rec.ilvlMax,
                        mid = rec.mid,   lvl = rec.lvl,
                        score = rec.score,
                    }
                    if uid then _applyByUID(uid, info)
                    elseif name then _applyOne(name, info) end
                end
            end
        end

        -- 2) Compat (ancien) : enregistrement unitaire (accepte aussi kv.uid)
        do
            local uid  = safenum(kv.uid, -1)
            local name = tostring(kv.name or "")
            local info = {
                ts = safenum(kv.ts, now()),
                ilvl = kv.ilvl, ilvlMax = kv.ilvlMax,
                mid  = kv.mid,  lvl     = kv.lvl,
                score= kv.score,
            }
            if uid >= 0 then
                _applyByUID(uid, info)
            elseif name ~= "" then
                _applyOne(name, info)
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
            rec.hid = safenum(kv.h or kv.hid, 0)
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
            local match = (hid > 0 and safenum(rec.hid,0) == hid) or (ts > 0 and safenum(rec.ts,0) == ts)
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

        -- Remplacer le lot existant (au lieu d’ignorer le LOT_CREATE)
        local existingIndex, existing = nil, nil
        for i, l0 in ipairs(GuildLogisticsDB.lots.list) do
            if safenum(l0.id,0) == id then existingIndex, existing = i, l0; break end
        end

        -- Copie défensive des IDs (ne jamais aliaser kv.I)
        local items = {}
        if type(kv.I) == "table" then
            for i2 = 1, #kv.I do
                items[#items+1] = safenum(kv.I[i2], 0)
            end
        end

        local l = {
            id = id,
            name = kv.n or ("Lot " .. tostring(id)),
            sessions = safenum(kv.N, 1),
            used = safenum(math.max(tonumber(kv.u or 0) or 0, tonumber(existing and existing.used or 0) or 0), 0),
            totalCopper = safenum(tonumber(kv.tc) or tonumber(kv.t), 0),
            itemIds = items,
        }

        if existingIndex then
            table.remove(GuildLogisticsDB.lots.list, existingIndex)
        end

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

        local v_hello = tostring(kv.ver or "")
        if v_hello ~= "" and GLOG.SetPlayerAddonVersion then GLOG.SetPlayerAddonVersion(sender, v_hello, tonumber(kv.ts) or time(), sender) end

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
                end

                -- ✅ Appliquer aussi localement à moi (sans créer d'entrée)
                do
                    GuildLogisticsDB = GuildLogisticsDB or {}; GuildLogisticsDB.players = GuildLogisticsDB.players or {}
                    local p  = GuildLogisticsDB.players[me]   -- ⚠️ ne crée jamais ici
                    local ts = now()
                    if p then
                        local prev    = safenum(p.statusTimestamp, 0)
                        local changed = false

                        -- iLvl (équipé + max)
                        if ilvl > 0 and ts >= prev then
                            p.ilvl = math.floor(tonumber(ilvl) or 0)
                            if ilvMx > 0 then p.ilvlMax = math.floor(tonumber(ilvMx) or 0) end
                            changed = true; if ns.Emit then ns.Emit("ilvl:changed", me) end
                        end

                        -- Clé M+
                        if lvl > 0 and ts >= prev then
                            p.mkeyMapId = mid; p.mkeyLevel = lvl
                            changed = true; if ns.Emit then ns.Emit("mkey:changed", me) end
                        end

                        -- Côte M+
                        if safenum(score, -1) >= 0 and ts >= prev then
                            p.mplusScore = math.floor(tonumber(score) or 0)
                            changed = true; if ns.Emit then ns.Emit("mplus:changed", me) end
                        end

                        if changed and ts > prev then
                            p.statusTimestamp = ts
                            if ns.RefreshAll then ns.RefreshAll() end
                        end
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
                        hid = hid2, rv = rv_me, player = me, caps = {"OFFER","GRANT","TOKEN1"},
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

    elseif msgType == "SYNC_ACK" then
        -- Reçu par l'émetteur du FULL : fin de transfert (place à des métriques éventuelles)
        local hid = kv.hid or ""
        if hid ~= "" then
            -- no-op
        end
    end
end

do
    -- Patch "version-aware": propose une OFFER même avec rv égal si ma version est plus récente
    local _PrevHandleFull_VSYNC = GLOG._HandleFull
    function GLOG._HandleFull(sender, msgType, kv)
        msgType = tostring(msgType or ""):upper()

        if msgType == "HELLO" and kv then
            local hid      = tostring(kv.hid or "")
            local rv_them  = safenum(kv.rv, -1)
            local ver_them = tostring(kv.ver or "")

            -- Enregistre la version de l’émetteur au plus tôt (utile à l’UI et aux comparaisons)
            if ver_them ~= "" and GLOG.SetPlayerAddonVersion then
                local ts = tonumber(kv.ts) or (time and time()) or 0
                GLOG.SetPlayerAddonVersion(sender, ver_them, ts, sender)
            end

            -- Déclenche une OFFER sensible à la version (4e param) ; le rate-limit évite les doublons
            if hid ~= "" and sender and sender ~= "" then
                if _scheduleOfferReply then
                    _scheduleOfferReply(hid, sender, rv_them, ver_them)
                end
            end
        end

        -- Laisse l’implémentation existante faire le reste (HELLO inclut l’appel historique)
        return _PrevHandleFull_VSYNC(sender, msgType, kv)
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
        -- Alimente la progression avec le compteur réel du réassemblage
        r.got     = (box and box.got) or r.got

        if ns.Emit then ns.Emit("debug:changed") end
    else
        -- première trace pour cette séquence
        pushLog("recv", t or "?", #message, channel, sender, seq, part, total, message, (part >= total) and "received" or "receiving")
        -- ⚠️ Ne crée pas d'index si le debug est OFF (sinon la table croit quand même)
        if not (GLOG and GLOG.IsDebugEnabled and not GLOG.IsDebugEnabled()) then
            RecvLogIndexBySeq[seq] = #DebugLog
        end
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

        -- Libère l'entrée d'index liée à cette séquence (même si le debug est OFF ça ne coûte rien)
        if RecvLogIndexBySeq then RecvLogIndexBySeq[seq] = nil end

        -- ➕ Termine proprement l’indicateur en toute circonstance pour SYNC_FULL
        local function _finishSync(ok)
            if t == "SYNC_FULL" and ActiveFullSync[senderKey] then
                ActiveFullSync[senderKey] = nil
                if ns and ns.Emit then ns.Emit("sync:end", "full", ok) end
            end
        end

        if t then
            -- 🛡️ Déduplication par séquence@expéditeur (notamment pour n=1 fragment)
            do
                local pkey = tostring(seq) .. "@" .. tostring(senderKey or ""):lower()
                if Processed[pkey] then
                    _finishSync(true) -- termine proprement un éventuel indicateur
                    return
                end
                Processed[pkey] = now()
            end

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
    -- 🔒 Toujours travailler sur un nom complet strict (jamais suffixer avec le royaume local ici)
    local full = (GLOG.ResolveFullNameStrict and GLOG.ResolveFullNameStrict(name))
              or (type(name)=="string" and name:find("%-") and ((ns.Util and ns.Util.CleanFullName and ns.Util.CleanFullName(name)) or name))
    if not full or full == "" then return end

    local uid = GLOG.GetOrAssignUID(full)
    if not uid then return end
    local rv = safenum((GuildLogisticsDB and GuildLogisticsDB.meta and GuildLogisticsDB.meta.rev), 0) + 1
    GuildLogisticsDB.meta.rev = rv
    GuildLogisticsDB.meta.lastModified = now()
    local alias = (GLOG.GetAliasFor and GLOG.GetAliasFor(full)) or nil
    GLOG.Comm_Broadcast("ROSTER_UPSERT", {
        uid = uid, name = full, alias = alias,   -- ➕ alias (optionnel)
        rv = rv, lm = GuildLogisticsDB.meta.lastModified
    })
end

function GLOG.BroadcastRosterRemove(idOrName)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
    if not idOrName or idOrName=="" then return end

    local uid, name = nil, nil
    local s = tostring(idOrName or "")

    -- Si on reçoit un UID numérique ...
    if s:match("^%d+$") then
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
    -- 🔒 Résolution stricte du nom pour éviter les UID/entrées sur le mauvais royaume
    local full = (GLOG.ResolveFullNameStrict and GLOG.ResolveFullNameStrict(name))
              or (type(name)=="string" and name:find("%-") and ((ns.Util and ns.Util.CleanFullName and ns.Util.CleanFullName(name)) or name))
    if not full or full == "" then return end

    local uid = GLOG.GetOrAssignUID(full); if not uid then return end
    local rv = safenum((GuildLogisticsDB and GuildLogisticsDB.meta and GuildLogisticsDB.meta.rev), 0) + 1
    GuildLogisticsDB.meta.rev = rv
    GuildLogisticsDB.meta.lastModified = now()
    local nm = GLOG.GetNameByUID(uid) or full
    GLOG.Comm_Broadcast("TX_APPLIED", { uid=uid, name=nm, delta=delta, rv=rv, lm=GuildLogisticsDB.meta.lastModified, by=playerFullName() })
end


function GLOG.GM_ApplyAndBroadcastEx(name, delta, extra)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
    -- 🔒 Résolution stricte du nom
    local full = (GLOG.ResolveFullNameStrict and GLOG.ResolveFullNameStrict(name))
              or (type(name)=="string" and name:find("%-") and ((ns.Util and ns.Util.CleanFullName and ns.Util.CleanFullName(name)) or name))
    if not full or full == "" then return end

    local uid = GLOG.GetOrAssignUID(full); if not uid then return end
    local rv = safenum((GuildLogisticsDB and GuildLogisticsDB.meta and GuildLogisticsDB.meta.rev), 0) + 1
    GuildLogisticsDB.meta.rev = rv
    GuildLogisticsDB.meta.lastModified = now()
    local nm = GLOG.GetNameByUID(uid) or full
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
        for i = 1, math.max(#U, #D, #N) do
            local name  = N[i] or (GLOG.GetNameByUID and GLOG.GetNameByUID(U[i])) or nil
            local delta = safenum(D[i], 0)
            if name and delta ~= 0 then
                -- Écrit dans 'solde' (source de vérité) via l’API générique
                GLOG.ApplyDeltaByName(name, delta, playerFullName())
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
        tc = safenum(l.totalCopper, 0), 
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
            local prev = safenum(p.statusTimestamp, 0)
            local changed = false

            -- iLvl
            if ilvl ~= nil and ts >= prev then
                p.ilvl = math.floor(tonumber(ilvl) or 0)
                if ilvlMax ~= nil then p.ilvlMax = math.floor(tonumber(ilvlMax) or 0) end
                changed = true; if ns.Emit then ns.Emit("ilvl:changed", me) end
            end

            -- Clé M+
            if safenum(lvl,0) > 0 and ts >= prev then
                if mid ~= nil then p.mkeyMapId = safenum(mid, 0) end
                p.mkeyLevel = safenum(lvl, 0)
                changed = true; if ns.Emit then ns.Emit("mkey:changed", me) end
            end

            -- Côte M+
            if safenum(score, -1) >= 0 and ts >= prev then
                p.mplusScore = safenum(score, 0)
                changed = true; if ns.Emit then ns.Emit("mplus:changed", me) end
            end

            if changed and ts > prev then
                p.statusTimestamp = ts
                if ns.RefreshAll then ns.RefreshAll() end
            end
        end
    end

    -- ✉️ Diffusion réseau
    local myUID = (GLOG.GetOrAssignUID and GLOG.GetOrAssignUID(me)) or (ns.Util and ns.Util.GetOrAssignUID and ns.Util.GetOrAssignUID(me)) or nil
    local payload = {
        name = me, ts = ts, by = by, uid = myUID,  -- ➕ uid de l’émetteur
    }
    if ilvl    ~= nil then payload.ilvl    = math.floor(tonumber(ilvl)    or 0) end
    if ilvlMax ~= nil then payload.ilvlMax = math.floor(tonumber(ilvlMax) or 0) end
    if score > 0 then payload.score = score end
    if safenum(lvl,0) > 0 then
        if mid ~= nil then payload.mid = safenum(mid, 0) end
        payload.lvl = safenum(lvl, 0)
    end

    -- ➕ NOUVEAU : batch 'S' de statuts connus localement
    -- Format compact par entrée : "uid;ts;ilvl;ilvlMax;mid;lvl;score"  (séparateur ';' → aucun antislash à l'encodage)
    do
        GuildLogisticsDB = GuildLogisticsDB or {}; GuildLogisticsDB.players = GuildLogisticsDB.players or {}
        local S = {}
        for full, rec in pairs(GuildLogisticsDB.players) do
            local ts2 = safenum(rec.statusTimestamp, 0)
            if ts2 > 0 then
                -- Assigne un UID si absent (sur ENTRÉE existante uniquement)
                local uid = tonumber(rec.uid) or (GLOG.GetOrAssignUID and GLOG.GetOrAssignUID(full)) or nil
                if uid then
                    local il   = (rec.ilvl       ~= nil) and math.floor(tonumber(rec.ilvl)    or 0) or -1
                    local ilMx = (rec.ilvlMax    ~= nil) and math.floor(tonumber(rec.ilvlMax) or 0) or -1
                    local mid2 = (rec.mkeyMapId  ~= nil) and safenum(rec.mkeyMapId,  -1)          or -1
                    local lvl2 = (rec.mkeyLevel  ~= nil) and safenum(rec.mkeyLevel,  -1)          or -1
                    local sc   = (rec.mplusScore ~= nil) and safenum(rec.mplusScore, -1)          or -1
                    if (il >= 0) or (ilMx >= 0) or (mid2 >= 0) or (lvl2 >= 0) or (sc >= 0) then
                        S[#S+1] = string.format("%d;%d;%d;%d;%d;%d;%d", uid, ts2, il, ilMx, mid2, lvl2, sc)
                    end
                end
            end
        end
        if #S > 0 then payload.S = S end
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
    GLOG.BroadcastStatusUpdate({ mid = mid, lvl = lvl, ts = safenum(ts, now()), by = tostring(by or "") })
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
        tc = safenum(total, 0), -- ⚠️ 'tc' au lieu de 't'
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
        hid = hid, rv = rv_me, player = me, caps = {"OFFER","GRANT","TOKEN1"},
        ver = (GLOG.GetAddonVersion and GLOG.GetAddonVersion()) or ""
    })

end


function GLOG.Comm_Init()
    -- 🔒 Idempotence : ne s'initialise qu'une seule fois
    if GLOG._commReady then return end
    GLOG._commReady = true

    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

    -- Centralisé via Core/Events.lua
    ns.Events.Register("CHAT_MSG_ADDON", function(_, _, prefix, msg, channel, sender)
        onAddonMsg(prefix, msg, channel, sender)
    end)

    -- Nettoyage des fragments périmés
    if not GLOG._inboxCleaner then
        GLOG._inboxCleaner = C_Timer.NewTicker(10, function()
            local cutoff = now() - 30
            for k, box in pairs(Inbox) do if (box.ts or 0) < cutoff then Inbox[k] = nil end end
            -- 🔁 Purge des messages déjà vus (anti-doublon)
            for k, ts in pairs(Processed) do if (ts or 0) < cutoff then Processed[k] = nil end end

        end)

            -- Maintenance mémoire

            -- 1) Élections HELLO terminées (garde 60s max pour l'UI, puis on libère)
            local heCutoff = now() - 60
            for hid, info in pairs(HelloElect or {}) do
                local ends = (info and info.endsAt) or 0
                if ends < heCutoff then HelloElect[hid] = nil end
            end

            -- 2) Index de debug orphelins (au cas où le ring a tourné)
            for s, idx in pairs(RecvLogIndexBySeq or {}) do
                local r = DebugLog and DebugLog[idx]
                if not r or r.seq ~= s then RecvLogIndexBySeq[s] = nil end
            end
            for s, idx in pairs(SendLogIndexBySeq or {}) do
                local r = DebugLog and DebugLog[idx]
                if not r or r.seq ~= s then SendLogIndexBySeq[s] = nil end
            end

            -- 3) Anti-spam expiré & cooldowns anciens
            for k, untilTs in pairs(_NonCritSuppress or {}) do
                if (untilTs or 0) <= now() then _NonCritSuppress[k] = nil end
            end
            do
                local coolCutoff = now() - 300 -- 5 min
                for who, ts in pairs(OfferCooldown or {}) do
                    if (ts or 0) < coolCutoff then OfferCooldown[who] = nil end
                end
                local helloCutoff = now() - (HELLO_STATUS_CD_SEC or 3)
                for who, ts in pairs(_HelloStatusSentTo or {}) do
                    if (ts or 0) < helloCutoff then _HelloStatusSentTo[who] = nil end
                end
            end

            -- 4) Allègement des vieux logs : on retire le payload 'raw' > 15s
            do
                local stripBefore = now() - 15
                for _, r in ipairs(DebugLog or {}) do
                    if (r.ts or 0) < stripBefore and r.raw ~= nil then r.raw = nil end
                end
            end

    end

    -- Purge les index de réception orphelins (ligne supprimée du ring-buffer ou mismatch)
    for s, idx in pairs(RecvLogIndexBySeq) do
        local r = DebugLog[idx]
        if not r or r.seq ~= s then
            RecvLogIndexBySeq[s] = nil
        end
    end

    -- Purge les entrées anti-spam arrivées à échéance
    for k, untilTs in pairs(_NonCritSuppress) do
        if (untilTs or 0) <= now() then
            _NonCritSuppress[k] = nil
        end
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
    local function _maybeInit(_, ev, name)
        if ev == "ADDON_LOADED" and name and name ~= ADDON then return end
        if GLOG._commReady then return end
        if type(GLOG.Comm_Init) == "function" then GLOG.Comm_Init() end
    end
    ns.Events.Register("ADDON_LOADED",  _maybeInit)
    ns.Events.Register("PLAYER_LOGIN",  _maybeInit)
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

-- ✅ Bloc d’intégration « vérification version » 
do
    -- 🔒 Mémoire session : une seule notification MAX par session
    local _OutdatedNotified = false

    -- Helper : affichage différé (anti burst) si et seulement si hors instance
    local function _maybeNotifyOutdated(fromPlayer, remoteVer)
        if _OutdatedNotified then return end
        remoteVer = tostring(remoteVer or "")
        if remoteVer == "" then return end

        local mine = (GLOG.GetAddonVersion and GLOG.GetAddonVersion()) or ""
        if mine == "" then return end

        local cmp = (ns and ns.Util and ns.Util.CompareVersions and ns.Util.CompareVersions(mine, remoteVer)) or 0
        if cmp >= 0 then return end -- 👈 je suis déjà à jour (0) ou en avance (>0) → rien à faire

        -- Ne pas déranger en instance (donjon/raid)… on retentera au prochain message
        local inInstance = false
        if type(IsInInstance) == "function" then
            inInstance = IsInInstance() and true or false
        end
        if inInstance then return end

        -- Petit jitter et anti-double popup court (réutilise _ObsoletePopupUntil/OBSOLETE_DEBOUNCE_SEC si présents)
        if (now() < (_ObsoletePopupUntil or 0)) then return end
        _ObsoletePopupUntil = now() + (OBSOLETE_DEBOUNCE_SEC or 10)

        local jitter = (math.random(0, 200) / 1000.0)
        if ns and ns.Util and ns.Util.After then
            ns.Util.After(jitter, function()
                if ns.UI and ns.UI.ShowOutdatedAddonPopup then
                    ns.UI.ShowOutdatedAddonPopup(mine, remoteVer, tostring(fromPlayer or ""))
                    _OutdatedNotified = true  -- ✅ une seule fois par session
                end
            end)
        else
            -- Fallback immédiat si pas de scheduler util
            if ns and ns.UI and ns.UI.ShowOutdatedAddonPopup then
                ns.UI.ShowOutdatedAddonPopup(mine, remoteVer, tostring(fromPlayer or ""))
                _OutdatedNotified = true
            end
        end
    end

    -- 🛑 Neutralise l’envoi de VERSION_WARN (mécanique supprimée)
    local _PrevCommWhisper = GLOG.Comm_Whisper
    function GLOG.Comm_Whisper(target, msgType, data)
        if tostring(msgType) == "VERSION_WARN" then
            -- On ne l’envoie plus. On retourne true pour ne pas perturber l’appelant.
            return true
        end
        return _PrevCommWhisper(target, msgType, data)
    end

    -- 🌐 Hook central : chaque message reçu avec kv.ver déclenche le contrôle « obsolète »
    local _PrevEnqueueComplete = enqueueComplete
    function enqueueComplete(sender, msgType, kv)
        -- Ignore tout traitement « VERSION_WARN » côté réception (mécanique retirée)
        if tostring(msgType) == "VERSION_WARN" then
            return -- no-op
        end

        -- Utiliser la version portée par la trame pour notifier si besoin
        if kv and kv.ver and kv.ver ~= "" then
            _maybeNotifyOutdated(sender, tostring(kv.ver))
        end

        return _PrevEnqueueComplete(sender, msgType, kv)
    end
end