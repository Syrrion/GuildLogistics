local ADDON, ns = ...
ns.CDZ = ns.CDZ or {}
local CDZ, UI = ns.CDZ, ns.UI

-- ➕ Garde-fou : attache les helpers UID exposés par Helper.lua (et fallback ultime)
CDZ.GetOrAssignUID = CDZ.GetOrAssignUID or (ns.Util and ns.Util.GetOrAssignUID)
CDZ.GetNameByUID   = CDZ.GetNameByUID   or (ns.Util and ns.Util.GetNameByUID)
CDZ.MapUID         = CDZ.MapUID         or (ns.Util and ns.Util.MapUID)
CDZ.UnmapUID       = CDZ.UnmapUID       or (ns.Util and ns.Util.UnmapUID)
CDZ.EnsureRosterLocal = CDZ.EnsureRosterLocal or (ns.Util and ns.Util.EnsureRosterLocal)

if not CDZ.GetOrAssignUID then
    -- Fallback minimal (au cas où Helper.lua n’est pas encore chargé — évite les nil)
    local function _ensureDB()
        ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}
        ChroniquesDuZephyrDB.meta    = ChroniquesDuZephyrDB.meta    or {}
        ChroniquesDuZephyrDB.players = ChroniquesDuZephyrDB.players or {}
        ChroniquesDuZephyrDB.uids    = ChroniquesDuZephyrDB.uids    or {}
        ChroniquesDuZephyrDB.meta.uidSeq = ChroniquesDuZephyrDB.meta.uidSeq or 1
        return ChroniquesDuZephyrDB
    end
    function CDZ.GetOrAssignUID(name)
        local db = _ensureDB()
        local full = tostring(name or "")
        for uid, stored in pairs(db.uids) do if stored == full then return uid end end
        local uid = string.format("P%06d", db.meta.uidSeq); db.meta.uidSeq = db.meta.uidSeq + 1
        db.uids[uid] = full
        db.players[full] = db.players[full] or { credit = 0, debit = 0 }
        return uid
    end
    function CDZ.GetNameByUID(uid)
        local db = _ensureDB()
        return db.uids[tostring(uid or "")]
    end
    function CDZ.MapUID(uid, name)
        local db = _ensureDB()
        db.uids[tostring(uid or "")] = tostring(name or "")
        db.players[tostring(name or "")] = db.players[tostring(name or "")] or { credit=0, debit=0 }
        return uid
    end
    function CDZ.UnmapUID(uid)
        local db = _ensureDB()
        db.uids[tostring(uid or "")] = nil
    end
    function CDZ.EnsureRosterLocal(name)
        local db = _ensureDB()
        local full = tostring(name or "")
        db.players[full] = db.players[full] or { credit = 0, debit = 0 }
        return db.players[full]
    end
end

-- ===== Constantes / État =====
local PREFIX   = "CDZ1"
local MAX_PAY  = 200   -- fragmentation des messages
local Seq      = 0     -- séquence réseau

-- Limitation d'émission (paquets / seconde)
local OUT_MAX_PER_SEC = 2

-- Compression (optionnelle via LibDeflate) : compresse avant fragmentation, décompresse après réassemblage
local LD do
    local lib = nil
    local f = CreateFrame("Frame")
    f:SetScript("OnEvent", function()
        if not lib then
            if LibStub then lib = LibStub:GetLibrary("LibDeflate", true) end
        end
    end)
    f:RegisterEvent("ADDON_LOADED")
    LD = setmetatable({}, {
        __index = function(_, k)
            if not lib then
                if LibStub then lib = LibStub:GetLibrary("LibDeflate", true) end
            end
            return lib and lib[k]
        end
    })
end

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
local getRev         = (U and U.getRev)         or (_G and _G.getRev)         or function() local db=ChroniquesDuZephyrDB; return (db and db.meta and db.meta.rev) or 0 end

local function _compressStr(s)
    if not (LD and s and #s >= COMPRESS_MIN_SIZE) then return nil end
    if not (LD and LD.CompressDeflate) then return nil end
    local comp = LD:CompressDeflate(s, { level = 6 })
    return comp and LD:EncodeForWoWAddonChannel(comp) or nil
end

local function _decompressStr(s)
    if not (LD and s and s ~= "") then return nil end
    if not (LD and LD.DecompressDeflate) then return nil end
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
local HELLO_WAIT_SEC          = 3.0        -- fenêtre collecte OFFERS
local OFFER_BACKOFF_MS_MAX    = 600        -- étalement OFFERS (0..600ms)
local FULL_INHIBIT_SEC        = 15         -- n'offre pas si FULL récent vu
local OFFER_RATE_LIMIT_SEC    = 10         -- anti-spam OFFERS par initiateur

-- Suivi "FULL vu" pour UI/anti-bruit
local LastFullSentAt  = LastFullSentAt or 0
local LastFullSeenAt  = LastFullSeenAt or 0
local LastFullSeenRv  = LastFullSeenRv or -1

-- Suivi Debug de la découverte
local HelloElect      = HelloElect or {}   -- [hid] = { startedAt, endsAt, decided, winner, token, offers, applied }

-- Sessions initiées localement
-- [hid] = { initiator=me, rv_me, decided=false, endsAt, offers={[normName]={player,rv,est,h}}, grantedTo, token, reason }
local Discovery = Discovery or {}

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
    local ok, snap = pcall(function() return (CDZ._SnapshotExport and CDZ._SnapshotExport()) or {} end)
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
    if not sess or sess.decided then return end
    sess.decided = true

    -- Si FULL pertinent vu pendant fenêtre → annuler
    if (LastFullSeenRv or -1) >= safenum(sess.rv_me, 0) and (now() - (LastFullSeenAt or 0)) < HELLO_WAIT_SEC then
        HelloElect[hid] = HelloElect[hid] or {}
        HelloElect[hid].decided = true
        HelloElect[hid].winner  = nil
        if ns.Emit then ns.Emit("debug:changed") end
        Discovery[hid] = nil
        return
    end

    local offers = sess.offers or {}
    local chosen = nil
    for _, o in pairs(offers) do
        if not chosen then chosen = o
        else
            if (o.rv > chosen.rv)
            or (o.rv == chosen.rv and o.est < chosen.est)
            or (o.rv == chosen.rv and o.est == chosen.est and o.h > chosen.h)
            then chosen = o end
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

    -- Token sans overflow : timestamp + 8 hex “safe”
    local token = string.format("%d-%s", now(), _randHex8())
    sess.token     = token
    sess.grantedTo = chosen.player

    HelloElect[hid] = HelloElect[hid] or {}
    HelloElect[hid].winner  = chosen.player
    HelloElect[hid].token   = token
    HelloElect[hid].decided = true
    if ns.Emit then ns.Emit("debug:changed") end

    CDZ.Comm_Whisper(chosen.player, "SYNC_GRANT", {
        hid   = hid,
        token = token,
        init  = sess.initiator,
        m     = sess.reason or "rv_gap",
    })
end

local function _scheduleOfferReply(hid, initiator, rv_init)
    -- Inhibition si FULL récent ≥ mon rv
    if (now() - (LastFullSeenAt or 0)) < FULL_INHIBIT_SEC and (LastFullSeenRv or -1) >= safenum(getRev(), 0) then
        return
    end
    -- Anti-spam par initiateur
    local k = _norm(initiator)
    local last = OfferCooldown[k] or 0
    if (now() - last) < OFFER_RATE_LIMIT_SEC then return end
    OfferCooldown[k] = now()

    local est = _estimateSnapshotSize()
    local h   = _hashHint(string.format("%s|%d|%s", playerFullName(), safenum(getRev(),0), hid))
    local delay = math.random(0, OFFER_BACKOFF_MS_MAX) / 1000.0

    ns.Util.After(delay, function()
        local rv_peer = safenum(getRev(), 0)
        if rv_peer <= safenum(rv_init, 0) then return end
        CDZ.Comm_Whisper(initiator, "SYNC_OFFER", {
            hid = hid, rv = rv_peer, est = est, h = h, from = playerFullName()
        })
    end)
end

-- File d'envoi temporisée
local OutQ      = {}
local OutTicker = nil

-- Boîtes aux lettres (réassemblage fragments)
local Inbox     = {}

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
    if CDZ and CDZ.IsDebugEnabled and not CDZ.IsDebugEnabled() then return end

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


function CDZ.GetDebugLogs() return DebugLog end
function CDZ.PurgeDebug()
    wipe(DebugLog)
    if ns.Emit then ns.Emit("debug:changed") end
end
-- ➕ Alias attendu par Tabs/Debug.lua
function CDZ.ClearDebugLogs()
    wipe(DebugLog)
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

function CDZ.Comm_Broadcast(typeName, kv)
    _send(typeName, "GUILD", nil, kv)
end

function CDZ.Comm_Whisper(target, typeName, kv)
    _send(typeName, "WHISPER", target, kv)
end

-- ===== Application snapshot (import/export compact) =====
function CDZ._SnapshotExport()
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}
    ChroniquesDuZephyrDB.meta = ChroniquesDuZephyrDB.meta or {}
    ChroniquesDuZephyrDB.players = ChroniquesDuZephyrDB.players or {}
    ChroniquesDuZephyrDB.uids = ChroniquesDuZephyrDB.uids or {}
    ChroniquesDuZephyrDB.expenses = ChroniquesDuZephyrDB.expenses or { list = {}, nextId = 1 }
    ChroniquesDuZephyrDB.lots = ChroniquesDuZephyrDB.lots or { list = {}, nextId = 1 }

    local meta = ChroniquesDuZephyrDB.meta
    local t = {
        P = {}, I = {}, E = {}, L = {}, H = {},
        rv = safenum(meta.rev, 0),
        lm = safenum(meta.lastModified, now()),
        fs = safenum(meta.fullStamp, now()),
    }

    for name, rec in pairs(ChroniquesDuZephyrDB.players) do
        local res = (rec and rec.reserved) and 1 or 0
        t.P[#t.P+1] = table.concat({ name, safenum(rec.credit, 0), safenum(rec.debit, 0), res }, ":")
    end

    local _players = ChroniquesDuZephyrDB.players or {}
    for uid, name in pairs(ChroniquesDuZephyrDB.uids) do
        if name and _players[name] ~= nil then
            t.I[#t.I+1] = tostring(uid) .. ":" .. tostring(name)
        end
    end
    for _, e in ipairs(ChroniquesDuZephyrDB.expenses.list) do
        t.E[#t.E+1] = table.concat({
            safenum(e.id,0), safenum(e.qty,0), safenum(e.copper,0),
            tostring(e.source or ""), safenum(e.lotId,0), safenum(e.itemID,0)
        }, ",")
    end
    for _, l in ipairs(ChroniquesDuZephyrDB.lots.list) do
        local ids = {}
        for _, id in ipairs(l.itemIds or {}) do ids[#ids+1] = tostring(id) end
        t.L[#t.L+1] = table.concat({
            safenum(l.id,0), tostring(l.name or ("Lot "..tostring(l.id))), safenum(l.sessions,1),
            safenum(l.used,0), safenum(l.totalCopper,0), table.concat(ids, ";")
        }, ",")
    end
    -- ➕ Historique compact (CSV: ts,total,perHead,count,ref,participants(;))
    for _, h in ipairs(ChroniquesDuZephyrDB.history or {}) do
        local parts = table.concat(h.participants or {}, ";")
        t.H[#t.H+1] = table.concat({
            safenum(h.ts,0), safenum(h.total,0), safenum(h.perHead,0),
            safenum(h.count,0), (h.refunded and 1 or 0), parts
        }, ",")
    end
    return t
end

function CDZ._SnapshotApply(kv)
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}
    ChroniquesDuZephyrDB.meta = ChroniquesDuZephyrDB.meta or {}
    ChroniquesDuZephyrDB.players = {}
    ChroniquesDuZephyrDB.uids = {}
    ChroniquesDuZephyrDB.expenses = { list = {}, nextId = 1 }
    ChroniquesDuZephyrDB.lots = { list = {}, nextId = 1 }

    local meta = ChroniquesDuZephyrDB.meta
    meta.rev = safenum(kv.rv, 0)
    meta.lastModified = safenum(kv.lm, now())
    meta.fullStamp = safenum(kv.fs, now())

    -- (dans function CDZ._SnapshotApply(kv))
    for _, s in ipairs(kv.P or {}) do
        -- Nouveau format (4 champs) : name:credit:debit:reserved
        local name, credit, debit, res = s:match("^(.-):(%-?%d+):(%-?%d+):(%-?%d+)$")
        if name then
            ChroniquesDuZephyrDB.players[name] = {
                credit   = safenum(credit,0),
                debit    = safenum(debit,0),
                reserved = safenum(res,0) ~= 0
            }
        else
            -- Compat anciens snapshots (3 champs) : name:credit:debit
            local n2, c2, d2 = s:match("^(.-):(%-?%d+):(%-?%d+)$")
            if n2 then
                ChroniquesDuZephyrDB.players[n2] = {
                    credit   = safenum(c2,0),
                    debit    = safenum(d2,0),
                    reserved = false
                }
            end
        end
    end

    for _, s in ipairs(kv.I or {}) do
        local uid, name = s:match("^(.-):(.-)$")
        if uid and name then ChroniquesDuZephyrDB.uids[uid] = name end
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
            ChroniquesDuZephyrDB.expenses.list[#ChroniquesDuZephyrDB.expenses.list+1] = {
                id = id,
                qty = safenum(qty,0),
                copper = safenum(copper,0),
                source = src,
                lotId = _lot,
                itemID = safenum(itemId,0), -- ✅ normalisation clé attendue par l’UI
            }
            ChroniquesDuZephyrDB.expenses.nextId = math.max(ChroniquesDuZephyrDB.expenses.nextId or 1, id + 1)
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
        ChroniquesDuZephyrDB.history = {}
        for _, line in ipairs(kv.H or {}) do
            local ts, total, per, cnt, ref, parts = line:match("^(%-?%d+),(%-?%d+),(%-?%d+),(%-?%d+),(%-?%d+),?(.*)$")
            if ts then
                local s = {
                    ts = safenum(ts,0),
                    total = safenum(total,0),
                    perHead = safenum(per,0),
                    count = safenum(cnt,0),
                    refunded = (safenum(ref,0) ~= 0),
                    participants = {},
                }
                if parts and parts ~= "" then
                    for p in tostring(parts):gmatch("[^;]+") do s.participants[#s.participants+1] = p end
                end
                table.insert(ChroniquesDuZephyrDB.history, s)
            end
        end
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
            ChroniquesDuZephyrDB.lots.list[#ChroniquesDuZephyrDB.lots.list+1] = l
            ChroniquesDuZephyrDB.lots.nextId = math.max(ChroniquesDuZephyrDB.lots.nextId or 1, id + 1)
        end
    end

    -- ➕ Import Historique depuis le snapshot (robuste 6/7 champs + filtres)
    ChroniquesDuZephyrDB.history = {}
    for _, s in ipairs(kv.H or {}) do
        if type(s) == "string" then
            local hid, ts, total, per, count, refunded, rest

            -- Format export actuel (6 champs) : ts,total,perHead,count,ref,participants
            ts, total, per, count, refunded, rest =
                s:match("^(%-?%d+),(%-?%d+),(%-?%d+),(%-?%d+),(%-?%d+),?(.*)$")

            -- Ancien format toléré (7 champs) : hid,ts,total,per,count,ref,rest
            if not ts then
                hid, ts, total, per, count, refunded, rest =
                    s:match("^(.-),(%-?%d+),(%-?%d+),(%-?%d+),(%-?%d+),(%-?%d+),?(.*)$")
            end

            local names = {}
            if rest and rest ~= "" then
                for name in tostring(rest):gmatch("[^;]+") do names[#names+1] = name end
            end

            -- Filtre anti-lignes fantômes : ts valide ET au moins un champ non nul
            local _ts      = safenum(ts, 0)
            local _total   = safenum(total, 0)
            local _per     = safenum(per, 0)
            local _count   = safenum(count, #names)
            local _ref     = (safenum(refunded, 0) == 1)

            if _ts > 0 and (_total ~= 0 or _per ~= 0 or _count > 0) then
                ChroniquesDuZephyrDB.history[#ChroniquesDuZephyrDB.history+1] = {
                    hid = (hid ~= "" and hid or nil),
                    ts  = _ts,
                    total = _total,
                    perHead = _per,
                    count = _count,
                    participants = names,
                    refunded = _ref,
                }
            end

        elseif type(s) == "table" then
            -- tolérance (au cas où)
            local _ts    = safenum(s.ts, 0)
            local _total = safenum(s.total or s.t, 0)
            local _per   = safenum(s.perHead or s.per or s.p, 0)
            local _parts = s.names or s.participants or {}
            local _count = safenum(s.count or s.c or #_parts, 0)
            if _ts > 0 and (_total ~= 0 or _per ~= 0 or _count > 0) then
                ChroniquesDuZephyrDB.history[#ChroniquesDuZephyrDB.history+1] = {
                    hid = s.hid, ts = _ts, total = _total, perHead = _per,
                    count = _count, participants = _parts,
                    refunded = (s.refunded or s.r == 1) and true or false,
                }
            end
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
        CDZ._HandleFull(item._sender, item._t, item)
    end
end

local function refreshActive()
    if ns and ns.UI and ns.UI.RefreshActive then ns.UI.RefreshActive() end
end

-- ===== Handler principal =====
function CDZ._HandleFull(sender, msgType, kv)
    msgType = tostring(msgType or ""):upper()
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}; ChroniquesDuZephyrDB.meta = ChroniquesDuZephyrDB.meta or {}
    local meta = ChroniquesDuZephyrDB.meta

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
            if CDZ.MapUID then CDZ.MapUID(uid, full) end
            if CDZ.EnsureRosterLocal then CDZ.EnsureRosterLocal(full) end
            meta.rev = (rv >= 0) and rv or myrv
            meta.lastModified = safenum(kv.lm, now())
            refreshActive()
        end

    elseif msgType == "ROSTER_REMOVE" then
        -- Tolère les anciens messages (sans rv/lm) : on applique quand même.
        local hasVersioning = (kv.rv ~= nil) or (kv.lm ~= nil)
        if hasVersioning and not shouldApply() then return end

        local uid  = kv.uid
        -- Récupérer le nom AVANT de défaire le mapping UID -> name.
        local name = (uid and CDZ.GetNameByUID and CDZ.GetNameByUID(uid)) or kv.name

        if uid and CDZ.UnmapUID then CDZ.UnmapUID(uid) end

        -- Purge du roster local (nom complet si possible)
        if name and name ~= "" then
            if CDZ.RemovePlayerLocal then
                CDZ.RemovePlayerLocal(name, true)
            else
                ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}
                ChroniquesDuZephyrDB.players = ChroniquesDuZephyrDB.players or {}
                ChroniquesDuZephyrDB.players[name] = nil
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
        ChroniquesDuZephyrDB.players = ChroniquesDuZephyrDB.players or {}
        local uid, name = kv.uid, kv.name
        -- récupérer le nom complet via l’UID si besoin
        if (not name or name == "") and uid and CDZ.GetNameByUID then
            name = CDZ.GetNameByUID(uid)
        end
        if name and name ~= "" then
            local p = ChroniquesDuZephyrDB.players[name] or { credit=0, debit=0, reserved=false }
            p.reserved = (tonumber(kv.res) or 0) ~= 0
            ChroniquesDuZephyrDB.players[name] = p
            meta.rev = (rv >= 0) and rv or myrv
            meta.lastModified = safenum(kv.lm, now())
            if ns.Emit then ns.Emit("roster:reserve", name, p.reserved) end
            refreshActive()
        end
        
    elseif msgType == "TX_REQ" then
        -- Seul le GM traite les demandes : les clients non-GM ignorent.
        if not (CDZ.IsMaster and CDZ.IsMaster()) then
            return
        end

        if CDZ.AddIncomingRequest then CDZ.AddIncomingRequest(kv) end
        refreshActive()

        -- Popup côté GM
        local ui = ns.UI
        if ui and ui.PopupRequest then
            local _id = tostring(kv.uid or "") .. ":" .. tostring(kv.ts or now())
            ui.PopupRequest(kv.who or sender, safenum(kv.delta,0),
                function()
                    if CDZ.GM_ApplyAndBroadcastByUID then
                        CDZ.GM_ApplyAndBroadcastByUID(kv.uid, safenum(kv.delta,0), {
                            reason = "PLAYER_REQUEST", requester = kv.who or sender
                        })
                    end
                    if CDZ.ResolveRequest then CDZ.ResolveRequest(_id, true, playerFullName()) end
                end,
                function()
                    if CDZ.ResolveRequest then CDZ.ResolveRequest(_id, false, playerFullName()) end
                end
            )
        end

    elseif msgType == "TX_APPLIED" then
        if not shouldApply() then return end
        local applied = false
        if CDZ.ApplyDeltaByName and kv.name and kv.delta then
            CDZ.ApplyDeltaByName(kv.name, safenum(kv.delta,0), kv.by or sender)
            applied = true
        else
            -- ➕ Fallback : appliquer localement si l’API n’est pas disponible
            ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}; ChroniquesDuZephyrDB.players = ChroniquesDuZephyrDB.players or {}
            local nf = (ns and ns.Util and ns.Util.NormalizeFull) and ns.Util.NormalizeFull or tostring
            local full = nf(kv.name or "")
            local rec = ChroniquesDuZephyrDB.players[full] or { credit = 0, debit = 0 }
            local d = safenum(kv.delta, 0)
            if d >= 0 then
                rec.credit = safenum(rec.credit,0) + d
            else
                rec.debit  = safenum(rec.debit,0)  + (-d)
            end
            ChroniquesDuZephyrDB.players[full] = rec
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
        if CDZ.ApplyBatch then
            CDZ.ApplyBatch(kv)
            done = true
        else
            -- ➕ Fallback : boucle sur les éléments du batch
            ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}; ChroniquesDuZephyrDB.players = ChroniquesDuZephyrDB.players or {}
            local U, D, N = kv.U or {}, kv.D or {}, kv.N or {}
            local nf = (ns and ns.Util and ns.Util.NormalizeFull) and ns.Util.NormalizeFull or tostring
            for i = 1, math.max(#U, #D, #N) do
                local name = N[i] or (CDZ.GetNameByUID and CDZ.GetNameByUID(U[i])) or "?"
                local full = nf(name)
                local d = safenum(D[i], 0)
                local rec = ChroniquesDuZephyrDB.players[full] or { credit = 0, debit = 0 }
                if d >= 0 then
                    rec.credit = safenum(rec.credit,0) + d
                else
                    rec.debit  = safenum(rec.debit,0)  + (-d)
                end
                ChroniquesDuZephyrDB.players[full] = rec
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
                    local name = N[i] or (CDZ.GetNameByUID and CDZ.GetNameByUID(U[i])) or "?"
                    if nf(name) == meK then
                        local d = safenum(D[i], 0)
                        if d < 0 then
                            local per   = -d
                            local after = (CDZ.GetSolde and CDZ.GetSolde(meFull)) or 0

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

                            ns.UI.PopupRaidDebit(meFull, per, after, { L = Lctx })
                            if ns.Emit then ns.Emit("raid:popup-shown", meFull) end
                        end
                        break
                    end
                end
            end
        end

    elseif msgType == "EXP_ADD" then
        if not shouldApply() then return end
        ChroniquesDuZephyrDB.expenses = ChroniquesDuZephyrDB.expenses or { list = {}, nextId = 1 }
        local id = safenum(kv.id, 0); if id <= 0 then return end
        for _, e in ipairs(ChroniquesDuZephyrDB.expenses.list) do if safenum(e.id,0) == id then return end end

        -- Normalisations : clé 'src' pour la source, et lotId 0 -> nil
        local _src = kv.src or kv.s
        local _lot = safenum(kv.l, 0); if _lot == 0 then _lot = nil end

        local e = {
            id = id,
            qty = safenum(kv.q,0),
            copper = safenum(kv.c,0),
            source = _src,
            lotId  = _lot,
            itemID = safenum(kv.i,0),
        }
        table.insert(ChroniquesDuZephyrDB.expenses.list, e)
        ChroniquesDuZephyrDB.expenses.nextId = math.max(ChroniquesDuZephyrDB.expenses.nextId or 1, id + 1)
        meta.rev = (rv >= 0) and rv or myrv
        meta.lastModified = (lm >= 0) and lm or now()
        refreshActive()

    -- ➕ Suppression d'une dépense (diffusée par le GM)
    elseif msgType == "EXP_REMOVE" then
        if not shouldApply() then return end
        ChroniquesDuZephyrDB.expenses = ChroniquesDuZephyrDB.expenses or { list = {}, nextId = 1 }
        local id = safenum(kv.id, 0); if id <= 0 then return end
        local list = ChroniquesDuZephyrDB.expenses.list
        for i = #list, 1, -1 do
            if safenum(list[i].id, 0) == id then
                table.remove(list, i)
                break
            end
        end
        meta.rev = (rv >= 0) and rv or myrv
        meta.lastModified = (lm >= 0) and lm or now()
        refreshActive()

    -- ➕ Historique : ajout / remboursement / annulation / suppression
    elseif msgType == "HIST_ADD" then
        if not shouldApply() then return end
        ChroniquesDuZephyrDB.history = ChroniquesDuZephyrDB.history or {}
        local ts = safenum(kv.ts,0)
        local exists = false
        for _, h in ipairs(ChroniquesDuZephyrDB.history) do if safenum(h.ts,0) == ts then exists = true break end end
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
            table.insert(ChroniquesDuZephyrDB.history, 1, rec)
            meta.rev = (rv >= 0) and rv or myrv
            meta.lastModified = (lm >= 0) and lm or now()
            if ns.Emit then ns.Emit("history:changed") end
            refreshActive()
        end

    elseif msgType == "HIST_REFUND" then
        if not shouldApply() then return end
        local ts = safenum(kv.ts,0)
        for _, h in ipairs(ChroniquesDuZephyrDB.history or {}) do
            if safenum(h.ts,0) == ts then h.refunded = true break end
        end
        meta.rev = (rv >= 0) and rv or myrv
        meta.lastModified = (lm >= 0) and lm or now()
        if ns.Emit then ns.Emit("history:changed") end
        refreshActive()

    elseif msgType == "HIST_UNREFUND" then
        if not shouldApply() then return end
        local ts = safenum(kv.ts,0)
        for _, h in ipairs(ChroniquesDuZephyrDB.history or {}) do
            if safenum(h.ts,0) == ts then h.refunded = false break end
        end
        meta.rev = (rv >= 0) and rv or myrv
        meta.lastModified = (lm >= 0) and lm or now()
        if ns.Emit then ns.Emit("history:changed") end
        refreshActive()

    elseif msgType == "HIST_DEL" then
        if not shouldApply() then return end
        local ts = safenum(kv.ts,0)
        local t = ChroniquesDuZephyrDB.history or {}
        for i = #t, 1, -1 do
            if safenum(t[i].ts,0) == ts then table.remove(t, i) break end
        end
        meta.rev = (rv >= 0) and rv or myrv
        meta.lastModified = (lm >= 0) and lm or now()
        if ns.Emit then ns.Emit("history:changed") end
        refreshActive()

    elseif msgType == "LOT_CREATE" then
        if not shouldApply() then return end
        ChroniquesDuZephyrDB.lots = ChroniquesDuZephyrDB.lots or { list = {}, nextId = 1 }
        ChroniquesDuZephyrDB.expenses = ChroniquesDuZephyrDB.expenses or { list = {}, nextId = 1 }

        local id = safenum(kv.id, 0); if id <= 0 then return end
        for _, l0 in ipairs(ChroniquesDuZephyrDB.lots.list) do if safenum(l0.id,0) == id then return end end

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
                for _, e in ipairs(ChroniquesDuZephyrDB.expenses.list or {}) do
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
            for _, e in ipairs(ChroniquesDuZephyrDB.expenses.list or {}) do
                if set[safenum(e.id, -2)] then e.lotId = id end
            end
        end

        table.insert(ChroniquesDuZephyrDB.lots.list, l)
        ChroniquesDuZephyrDB.lots.nextId = math.max(ChroniquesDuZephyrDB.lots.nextId or 1, id + 1)

        meta.rev = (rv >= 0) and rv or myrv
        meta.lastModified = (lm >= 0) and lm or now()
        if ns.Emit then ns.Emit("lots:changed") end
        refreshActive()

    elseif msgType == "LOT_DELETE" then
        if not shouldApply() then return end
        ChroniquesDuZephyrDB.lots = ChroniquesDuZephyrDB.lots or { list = {}, nextId = 1 }
        local id = safenum(kv.id, 0)
        local kept = {}
        for _, l in ipairs(ChroniquesDuZephyrDB.lots.list) do
            if safenum(l.id, -1) ~= id then kept[#kept+1] = l end
        end
        ChroniquesDuZephyrDB.lots.list = kept
        for _, e in ipairs(ChroniquesDuZephyrDB.expenses.list or {}) do if safenum(e.lotId,0) == id then e.lotId = nil end end
        meta.rev = (rv >= 0) and rv or myrv
        meta.lastModified = (lm >= 0) and lm or now()
        if ns.Emit then ns.Emit("lots:changed") end
        refreshActive()

    elseif msgType == "LOT_CONSUME" then
        if not shouldApply() then return end
        ChroniquesDuZephyrDB.lots = ChroniquesDuZephyrDB.lots or { list = {}, nextId = 1 }
        local set = {}; for _, v in ipairs(kv.ids or {}) do set[safenum(v, -2)] = true end
        for _, l in ipairs(ChroniquesDuZephyrDB.lots.list) do
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
        -- Côté pair : répondre par une OFFER uniquement si rv_peer > rv_initiateur
        local hid   = kv.hid or kv.helloId or ""
        local from  = kv.player or kv.from or sender
        local rvi   = safenum(kv.rv, -1)
        if hid ~= "" and from and from ~= "" then
            _scheduleOfferReply(hid, from, rvi)
        end

        -- ✏️ Flush TX_REQ si le HELLO vient du GM effectif (tolérant au roster pas encore prêt)
        local nf = (ns and ns.Util and ns.Util.NormalizeFull) and ns.Util.NormalizeFull or tostring
        local gmName = CDZ.GetGuildMasterCached and select(1, CDZ.GetGuildMasterCached())
        local fromNF = nf(from)

        if gmName and fromNF == nf(gmName) then
            if CDZ.Pending_FlushToMaster then CDZ.Pending_FlushToMaster(gmName) end
        else
            -- Roster possiblement pas prêt : on retente quelques fois (délais 1s)
            CDZ._awaitHelloFrom = fromNF
            CDZ._awaitHelloRetry = 0
            local function _tryFlushLater()
                if not CDZ._awaitHelloFrom then return end
                local gm = CDZ.GetGuildMasterCached and select(1, CDZ.GetGuildMasterCached())
                if gm and CDZ._awaitHelloFrom == nf(gm) then
                    if CDZ.Pending_FlushToMaster then CDZ.Pending_FlushToMaster(gm) end
                    CDZ._awaitHelloFrom = nil
                    return
                end
                CDZ._awaitHelloRetry = (CDZ._awaitHelloRetry or 0) + 1
                if CDZ._awaitHelloRetry < 5 then
                    if C_Timer and C_Timer.After then C_Timer.After(1, _tryFlushLater) end
                else
                    CDZ._awaitHelloFrom = nil
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
        end

    elseif msgType == "SYNC_GRANT" then
        -- Reçu par le gagnant : envoyer un FULL ciblé avec token
        local hid   = kv.hid or ""
        local token = kv.token or ""
        local init  = kv.init or sender
        if hid ~= "" and token ~= "" and init and init ~= "" then
            local snap = (CDZ._SnapshotExport and CDZ._SnapshotExport()) or {}
            snap.hid   = hid
            snap.token = token
            CDZ.Comm_Whisper(init, "SYNC_FULL", snap)
        end

    elseif msgType == "SYNC_FULL" then
        -- Mémoriser la vue du FULL (anti-doublon & inhibitions)
        LastFullSeenAt = now()
        LastFullSeenRv = safenum(kv.rv, -1)

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
        CDZ._SnapshotApply(kv)
        refreshActive()

        -- ACK vers l'émetteur si token présent
        if hid ~= "" and token ~= "" then
            CDZ.Comm_Whisper(sender, "SYNC_ACK", { hid = hid, rv = safenum(meta.rev,0) })
            HelloElect[hid] = HelloElect[hid] or {}
            HelloElect[hid].applied = true
            if ns.Emit then ns.Emit("debug:changed") end
            Discovery[hid] = nil
        end

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
    if not (CDZ and CDZ._helloSent) and peekType ~= "HELLO" then return end

    local t, s, p, n = message:match("v=1|t=([^|]+)|s=(%d+)|p=(%d+)|n=(%d+)|")
    local seq  = safenum(s, 0)
    local part = safenum(p, 1)
    local total= safenum(n, 1)

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

    if not t then return end

    local payload = message:match("|n=%d+|(.*)$") or ""
    local key = sender .. "#" .. tostring(seq)
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

    if box.got == box.total then
        local chunks = {}
        for i = 1, box.total do
            if not box.parts[i] then chunks = nil; break else chunks[#chunks+1] = box.parts[i] end
        end
        if chunks then
            -- ✅ Fin de réception : marquer l'état "Reçu" et libérer l'index
            local i = RecvLogIndexBySeq[seq]
            if i and DebugLog[i] then
                DebugLog[i].ts        = _nowPrecise()
                DebugLog[i].state     = "received"
                DebugLog[i].status    = "received"
                DebugLog[i].stateText = "Reçu"
                DebugLog[i].part      = total
                DebugLog[i].total     = total
                if ns.Emit then ns.Emit("debug:changed") end
            end
            RecvLogIndexBySeq[seq] = nil

            Inbox[key] = nil
            local full = table.concat(chunks, "")
            -- Décompression éventuelle (balise 'c=z|...')
            full = unpackPayloadStr(full)
            local kv = decodeKV(full)
            enqueueComplete(sender, t, kv)
        end
    end
end

-- ===== Envoi mutations (roster & crédits) =====
function CDZ.BroadcastRosterUpsert(name)
    if not (CDZ.IsMaster and CDZ.IsMaster()) then return end
    if not name or name=="" then return end
    local uid = CDZ.GetOrAssignUID(name)
    if not uid then return end
    local rv = safenum((ChroniquesDuZephyrDB and ChroniquesDuZephyrDB.meta and ChroniquesDuZephyrDB.meta.rev), 0) + 1
    ChroniquesDuZephyrDB.meta.rev = rv
    ChroniquesDuZephyrDB.meta.lastModified = now()
    CDZ.Comm_Broadcast("ROSTER_UPSERT", { uid = uid, name = name, rv = rv, lm = ChroniquesDuZephyrDB.meta.lastModified })
end

function CDZ.BroadcastRosterRemove(idOrName)
    if not (CDZ.IsMaster and CDZ.IsMaster()) then return end
    if not idOrName or idOrName=="" then return end

    local uid, name = nil, nil
    local s = tostring(idOrName or "")

    -- Si on reçoit un UID (ex: P000123), on garde tel quel ; sinon on considère que c’est un nom
    if s:match("^P%d+$") then
        uid  = s
        name = (CDZ.GetNameByUID and CDZ.GetNameByUID(uid)) or nil
    else
        name = s
        uid  = (CDZ.FindUIDByName and CDZ.FindUIDByName(name)) or (CDZ.GetUID and CDZ.GetUID(name)) or nil
        -- Surtout ne pas créer un nouvel UID lors d’une suppression : on accepte uid=nil, mais on envoie le nom
    end

    local rv = safenum((ChroniquesDuZephyrDB and ChroniquesDuZephyrDB.meta and ChroniquesDuZephyrDB.meta.rev), 0) + 1
    ChroniquesDuZephyrDB.meta.rev = rv
    ChroniquesDuZephyrDB.meta.lastModified = now()

    -- On diffuse toujours les deux champs (uid + name) si disponibles pour une réception robuste
    CDZ.Comm_Broadcast("ROSTER_REMOVE", {
        uid = uid, name = name, rv = rv, lm = ChroniquesDuZephyrDB.meta.lastModified
    })
end

function CDZ.GM_ApplyAndBroadcast(name, delta)
    if not (CDZ.IsMaster and CDZ.IsMaster()) then return end
    local uid = CDZ.GetOrAssignUID(name); if not uid then return end
    local rv = safenum((ChroniquesDuZephyrDB and ChroniquesDuZephyrDB.meta and ChroniquesDuZephyrDB.meta.rev), 0) + 1
    ChroniquesDuZephyrDB.meta.rev = rv
    ChroniquesDuZephyrDB.meta.lastModified = now()
    local nm = CDZ.GetNameByUID(uid) or name
    CDZ.Comm_Broadcast("TX_APPLIED", { uid=uid, name=nm, delta=delta, rv=rv, lm=ChroniquesDuZephyrDB.meta.lastModified, by=playerFullName() })
end
function CDZ.GM_ApplyAndBroadcastEx(name, delta, extra)
    if not (CDZ.IsMaster and CDZ.IsMaster()) then return end
    local uid = CDZ.GetOrAssignUID(name); if not uid then return end
    local rv = safenum((ChroniquesDuZephyrDB and ChroniquesDuZephyrDB.meta and ChroniquesDuZephyrDB.meta.rev), 0) + 1
    ChroniquesDuZephyrDB.meta.rev = rv
    ChroniquesDuZephyrDB.meta.lastModified = now()
    local nm = CDZ.GetNameByUID(uid) or name
    local p = { uid=uid, name=nm, delta=delta, rv=rv, lm=ChroniquesDuZephyrDB.meta.lastModified, by=playerFullName() }
    if type(extra)=="table" then for k,v in pairs(extra) do if p[k]==nil then p[k]=v end end end
    CDZ.Comm_Broadcast("TX_APPLIED", p)
end

function CDZ.GM_ApplyAndBroadcastByUID(uid, delta, extra)
    if not (CDZ.IsMaster and CDZ.IsMaster()) then return end
    local rv = safenum((ChroniquesDuZephyrDB and ChroniquesDuZephyrDB.meta and ChroniquesDuZephyrDB.meta.rev), 0) + 1
    ChroniquesDuZephyrDB.meta.rev = rv
    ChroniquesDuZephyrDB.meta.lastModified = now()
    local p = {
        uid   = uid,
        name  = (CDZ.GetNameByUID and CDZ.GetNameByUID(uid)) or tostring(uid),
        delta = delta,
        rv    = rv,
        lm    = ChroniquesDuZephyrDB.meta.lastModified,
        by    = playerFullName(),
    }
    if type(extra) == "table" then
        for k, v in pairs(extra) do if p[k] == nil then p[k] = v end end
    end
    CDZ.Comm_Broadcast("TX_APPLIED", p)
end

-- ➕ Envoi batch compact (1 seul TX_BATCH au lieu d'une rafale de TX_APPLIED)
function CDZ.GM_BroadcastBatch(adjusts, opts)
    if not (CDZ.IsMaster and CDZ.IsMaster()) then return end
    adjusts = adjusts or {}
    opts    = opts or {}

    local uids, deltas, names = {}, {}, {}
    for _, a in ipairs(adjusts) do
        local nm = a and a.name
        if nm and nm ~= "" then
            local uid = (CDZ.GetOrAssignUID and CDZ.GetOrAssignUID(nm)) or nil
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

    CDZ.GM_ApplyBatchAndBroadcast(uids, deltas, names, reason, silent, extra)
end

function CDZ.GM_ApplyBatchAndBroadcast(uids, deltas, names, reason, silent, extra)
    if not (CDZ.IsMaster and CDZ.IsMaster()) then return end

    -- Versionnage unique partagé avec le broadcast
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}
    ChroniquesDuZephyrDB.meta = ChroniquesDuZephyrDB.meta or {}
    local rv = safenum(ChroniquesDuZephyrDB.meta.rev, 0) + 1
    ChroniquesDuZephyrDB.meta.rev = rv
    ChroniquesDuZephyrDB.meta.lastModified = now()

    -- ✅ Application LOCALE côté GM (on n'attend pas notre propre message réseau)
    do
        local U, D, N = uids or {}, deltas or {}, names or {}
        local nf = (ns and ns.Util and ns.Util.NormalizeFull) and ns.Util.NormalizeFull or tostring
        for i = 1, math.max(#U, #D, #N) do
            local name = N[i] or (CDZ.GetNameByUID and CDZ.GetNameByUID(U[i])) or nil
            local delta = safenum(D[i], 0)
            if name and delta ~= 0 then
                if CDZ.ApplyDeltaByName then
                    CDZ.ApplyDeltaByName(name, delta, playerFullName())
                else
                    ChroniquesDuZephyrDB.players = ChroniquesDuZephyrDB.players or {}
                    local full = nf(name)
                    local rec = ChroniquesDuZephyrDB.players[full] or { credit = 0, debit = 0 }
                    if delta >= 0 then rec.credit = safenum(rec.credit,0) + delta
                    else               rec.debit  = safenum(rec.debit,0)  + (-delta) end
                    ChroniquesDuZephyrDB.players[full] = rec
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
        lm = ChroniquesDuZephyrDB.meta.lastModified,
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

    CDZ.Comm_Broadcast("TX_BATCH", p)
end

function CDZ.AddIncomingRequest(kv)
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}
    ChroniquesDuZephyrDB.requests = ChroniquesDuZephyrDB.requests or {}
    local list = ChroniquesDuZephyrDB.requests
    local id = tostring(kv.uid or "") .. ":" .. tostring(kv.ts or now())
    list[#list+1] = {
        id = id, uid = kv.uid, delta = safenum(kv.delta,0),
        who = kv.who or kv.requester or "?", ts = safenum(kv.ts, now()),
    }
    if ns.Emit then ns.Emit("requests:changed") end
end
function CDZ.ResolveRequest(id, accepted, by)
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}
    local list = ChroniquesDuZephyrDB.requests or {}
    local kept = {}
    for _, r in ipairs(list) do if r.id ~= id then kept[#kept+1] = r end end
    ChroniquesDuZephyrDB.requests = kept
    if accepted and CDZ and CDZ.GM_ApplyAndBroadcastByUID then
        -- L’appelant a déjà appliqué la mutation
    end
    if ns.Emit then ns.Emit("requests:changed") end
end

function CDZ.RequestAdjust(a, b)
    -- Compat : UI appelle (name, delta) ; ancienne forme : (delta)
    local delta = (b ~= nil) and safenum(b, 0) or safenum(a, 0)
    if delta == 0 then return end

    local me  = playerFullName()
    local uid = CDZ.GetOrAssignUID and CDZ.GetOrAssignUID(me)
    if not uid then return end

    local payload = { uid = uid, delta = delta, who = me, ts = now(), reason = "CLIENT_REQ" }

    -- ➕ Heuristique temps-réel : considérer “en ligne” si vu récemment via HELLO
    local function _masterSeenRecently(name)
        local nf = (ns and ns.Util and ns.Util.NormalizeFull) and ns.Util.NormalizeFull or tostring
        local target = nf(name or "")

        -- 1) On a reçu un HELLO tout juste du GM et on attend le flush
        if CDZ._awaitHelloFrom and nf(CDZ._awaitHelloFrom) == target then
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
        local gmName, gmRow = CDZ.GetGuildMasterCached and CDZ.GetGuildMasterCached() or nil, nil
        if type(gmName) == "table" and not gmRow then gmName, gmRow = gmName[1], gmName[2] end
        if not gmRow and CDZ.GetGuildMasterCached then gmName, gmRow = CDZ.GetGuildMasterCached() end

        local onlineNow = false
        if gmName then
            onlineNow = (gmRow and gmRow.online) or _masterSeenRecently(gmName)
        end

        if gmName and onlineNow then
            -- GM réellement disponible : envoi direct
            CDZ.Comm_Whisper(gmName, "TX_REQ", payload)
        else
            -- GM hors-ligne ou inconnu : persiste → flush auto sur HELLO
            if CDZ.Pending_AddTXREQ then CDZ.Pending_AddTXREQ(payload) end
            if UIErrorsFrame and UIErrorsFrame.AddMessage then
                UIErrorsFrame:AddMessage("|cffffff80[CDZ]|r GM hors-ligne : demande mise en file d’attente.", 1, 0.9, 0.4)
            end
            if ns.Emit then ns.Emit("debug:changed") end
        end
    end

    -- ✏️ Nouveau : rafraîchir le roster AVANT la décision d’envoi
    if CDZ.RefreshGuildCache then
        CDZ.RefreshGuildCache(function() decideAndSend() end)
    else
        -- Fallback si jamais la fonction n’existe pas
        decideAndSend()
    end
end


-- ===== File d'attente persistante des TX_REQ (client) =====
function CDZ.Pending_AddTXREQ(kv)
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}
    ChroniquesDuZephyrDB.pending = ChroniquesDuZephyrDB.pending or {}
    local P = ChroniquesDuZephyrDB.pending
    P.txreq = P.txreq or {}
    kv = kv or {}
    kv.id = kv.id or (tostring(now()) .. "-" .. tostring(math.random(1000,9999)))
    table.insert(P.txreq, kv)
    if ns.Emit then ns.Emit("debug:changed") end
    return kv.id
end

function CDZ.Pending_ListTXREQ()
    local P = ChroniquesDuZephyrDB and ChroniquesDuZephyrDB.pending or {}
    return (P and P.txreq) or {}
end

function CDZ.Pending_FlushToMaster(master)
    local P = ChroniquesDuZephyrDB and ChroniquesDuZephyrDB.pending or {}
    if not P or not P.txreq or #P.txreq == 0 then return 0 end

    -- Destinataire par défaut : GM effectif (rang 0)
    if not master or master == "" then
        if CDZ.GetGuildMasterCached then master = select(1, CDZ.GetGuildMasterCached()) end
    end
    if not master or master == "" then return 0 end

    local sent = 0
    for i = 1, #P.txreq do
        local kv = P.txreq[i]
        if kv then
            CDZ.Comm_Whisper(master, "TX_REQ", kv)
            sent = sent + 1
        end
    end
    P.txreq = {}
    if ns.Emit then ns.Emit("debug:changed") end
    return sent
end

-- (Optionnel pour l’UI Debug — si tu veux alimenter une 3e liste)
function CDZ.GetPendingOutbox()
    local t = {}
    for _, kv in ipairs(CDZ.Pending_ListTXREQ() or {}) do
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
function CDZ.BroadcastLotCreate(l)
    if not (CDZ.IsMaster and CDZ.IsMaster()) then return end
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}
    ChroniquesDuZephyrDB.meta = ChroniquesDuZephyrDB.meta or {}
    local rv = safenum(ChroniquesDuZephyrDB.meta.rev, 0) + 1
    ChroniquesDuZephyrDB.meta.rev = rv
    ChroniquesDuZephyrDB.meta.lastModified = now()

    local payload = {
        id = safenum(l.id, 0),
        n  = l.name or ("Lot " .. tostring(l.id or "")),
        N  = safenum(l.sessions, 1),
        u  = safenum(l.used, 0),
        t  = safenum(l.totalCopper, 0),
        I  = {},
        rv = rv,
        lm = ChroniquesDuZephyrDB.meta.lastModified,
    }
    for _, eid in ipairs(l.itemIds or {}) do payload.I[#payload.I+1] = safenum(eid, 0) end
    CDZ.Comm_Broadcast("LOT_CREATE", payload)
end

-- Diffusion : suppression d’un lot (utilisé par Core.Lot_Delete)
function CDZ.BroadcastLotDelete(id)
    if not (CDZ.IsMaster and CDZ.IsMaster()) then return end
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}
    ChroniquesDuZephyrDB.meta = ChroniquesDuZephyrDB.meta or {}
    local rv = safenum(ChroniquesDuZephyrDB.meta.rev, 0) + 1
    ChroniquesDuZephyrDB.meta.rev = rv
    ChroniquesDuZephyrDB.meta.lastModified = now()
    CDZ.Comm_Broadcast("LOT_DELETE", { id = safenum(id,0), rv = rv, lm = ChroniquesDuZephyrDB.meta.lastModified })
end

-- Diffusion : consommation de plusieurs lots (utilisé par Core.Lots_ConsumeMany)
function CDZ.BroadcastLotsConsume(ids)
    if not (CDZ.IsMaster and CDZ.IsMaster()) then return end
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}
    ChroniquesDuZephyrDB.meta = ChroniquesDuZephyrDB.meta or {}
    local rv = safenum(ChroniquesDuZephyrDB.meta.rev, 0) + 1
    ChroniquesDuZephyrDB.meta.rev = rv
    ChroniquesDuZephyrDB.meta.lastModified = now()
    CDZ.Comm_Broadcast("LOT_CONSUME", { ids = ids or {}, rv = rv, lm = ChroniquesDuZephyrDB.meta.lastModified })
end

-- Conserve l'id alloué par le logger et versionne correctement.
function CDZ.BroadcastExpenseAdd(p)
    if not (CDZ.IsMaster and CDZ.IsMaster()) then return end
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}
    ChroniquesDuZephyrDB.meta     = ChroniquesDuZephyrDB.meta     or {}
    ChroniquesDuZephyrDB.expenses = ChroniquesDuZephyrDB.expenses or { list = {}, nextId = 1 }

    local id = safenum(p.id, 0)
    if id <= 0 then
        id = safenum(ChroniquesDuZephyrDB.expenses.nextId, 1)
        ChroniquesDuZephyrDB.expenses.nextId = id + 1
    else
        -- S’assure que la séquence locale reste > id
        local nextId = safenum(ChroniquesDuZephyrDB.expenses.nextId, 1)
        if (id + 1) > nextId then ChroniquesDuZephyrDB.expenses.nextId = id + 1 end
    end

    local rv = safenum((ChroniquesDuZephyrDB.meta and ChroniquesDuZephyrDB.meta.rev), 0) + 1
    ChroniquesDuZephyrDB.meta.rev = rv
    ChroniquesDuZephyrDB.meta.lastModified = now()

    CDZ.Comm_Broadcast("EXP_ADD", {
        id = id,
        i   = safenum(p.i, 0),
        q   = safenum(p.q, 1),
        c   = safenum(p.c, 0),
        src = p.src or p.s, -- la source voyage désormais sous 'src'
        l   = safenum(p.l, 0),
        rv  = rv,
        lm  = ChroniquesDuZephyrDB.meta.lastModified,
    })
end

-- ➕ Diffusion GM : suppression d'une dépense
function CDZ.GM_RemoveExpense(id)
    if not (CDZ.IsMaster and CDZ.IsMaster()) then return end
    local rv = safenum((ChroniquesDuZephyrDB.meta and ChroniquesDuZephyrDB.meta.rev),0) + 1
    ChroniquesDuZephyrDB.meta.rev = rv
    ChroniquesDuZephyrDB.meta.lastModified = now()
    CDZ.Comm_Broadcast("EXP_REMOVE", { id = safenum(id,0), rv = rv, lm = ChroniquesDuZephyrDB.meta.lastModified })
end

function CDZ.GM_CreateLot(name, sessions, totalCopper, itemIds)
    if not (CDZ.IsMaster and CDZ.IsMaster()) then return end
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}
    ChroniquesDuZephyrDB.lots = ChroniquesDuZephyrDB.lots or { list = {}, nextId = 1 }

    local id = safenum(ChroniquesDuZephyrDB.lots.nextId, 1)
    ChroniquesDuZephyrDB.lots.nextId = id + 1

    -- Versionnage
    ChroniquesDuZephyrDB.meta = ChroniquesDuZephyrDB.meta or {}
    local rv = safenum(ChroniquesDuZephyrDB.meta.rev, 0) + 1
    ChroniquesDuZephyrDB.meta.rev = rv
    ChroniquesDuZephyrDB.meta.lastModified = now()

    -- Calcul du total fiable côté GM si non fourni (ou incohérent)
    local total = 0
    if itemIds and #itemIds > 0 then
        for _, eid in ipairs(itemIds) do
            if CDZ.GetExpenseById then
                local _, it = CDZ.GetExpenseById(eid)
                if it then total = total + safenum(it.copper, 0) end
            end
        end
    end
    if safenum(totalCopper, 0) > 0 then total = safenum(totalCopper, 0) end

    -- Diffusion stricte : id, n, N, u, t, I (et méta)
    CDZ.Comm_Broadcast("LOT_CREATE", {
        id = id,
        n  = name,
        N  = safenum(sessions, 1),
        u  = 0,
        t  = safenum(total, 0),
        I  = itemIds or {},
        rv = rv,
        lm = ChroniquesDuZephyrDB.meta.lastModified,
    })
end

function CDZ.GM_DeleteLot(id)
    if not (CDZ.IsMaster and CDZ.IsMaster()) then return end
    local rv = safenum((ChroniquesDuZephyrDB.meta and ChroniquesDuZephyrDB.meta.rev),0) + 1
    ChroniquesDuZephyrDB.meta.rev = rv
    ChroniquesDuZephyrDB.meta.lastModified = now()
    CDZ.Comm_Broadcast("LOT_DELETE", { id=safenum(id,0), rv=rv, lm=ChroniquesDuZephyrDB.meta.lastModified })
end

function CDZ.GM_ConsumeLots(ids)
    if not (CDZ.IsMaster and CDZ.IsMaster()) then return end
    local rv = safenum((ChroniquesDuZephyrDB.meta and ChroniquesDuZephyrDB.meta.rev),0) + 1
    ChroniquesDuZephyrDB.meta.rev = rv
    ChroniquesDuZephyrDB.meta.lastModified = now()
    CDZ.Comm_Broadcast("LOT_CONSUME", { ids = ids or {}, rv=rv, lm=ChroniquesDuZephyrDB.meta.lastModified })
end

-- ➕ Diffusion Historique (GM uniquement)
function CDZ.BroadcastHistoryAdd(p)
    if not (CDZ.IsMaster and CDZ.IsMaster()) then return end
    ChroniquesDuZephyrDB.meta = ChroniquesDuZephyrDB.meta or {}
    local rv = safenum(ChroniquesDuZephyrDB.meta.rev, 0) + 1
    ChroniquesDuZephyrDB.meta.rev = rv
    ChroniquesDuZephyrDB.meta.lastModified = now()
    CDZ.Comm_Broadcast("HIST_ADD", {
        h  = tostring(p.hid or ""),
        ts = safenum(p.ts, now()),
        t  = safenum(p.total or p.t, 0),
        p  = safenum(p.per or p.p, 0),
        c  = safenum(p.count or p.c or #(p.names or p.participants or {}), 0),
        N  = p.names or p.participants or {},
        r  = safenum(p.r or (p.refunded and 1 or 0), 0),
        rv = rv, lm = ChroniquesDuZephyrDB.meta.lastModified,
    })
end

function CDZ.BroadcastHistoryRefund(hid, flag)
    if not (CDZ.IsMaster and CDZ.IsMaster()) then return end
    ChroniquesDuZephyrDB.meta = ChroniquesDuZephyrDB.meta or {}
    local rv = safenum(ChroniquesDuZephyrDB.meta.rev, 0) + 1
    ChroniquesDuZephyrDB.meta.rev = rv
    ChroniquesDuZephyrDB.meta.lastModified = now()
    CDZ.Comm_Broadcast("HIST_REFUND", {
        h = tostring(hid or ""), v = (flag and 1 or 0),
        rv = rv, lm = ChroniquesDuZephyrDB.meta.lastModified,
    })
end

function CDZ.BroadcastHistoryDelete(hid)
    if not (CDZ.IsMaster and CDZ.IsMaster()) then return end
    ChroniquesDuZephyrDB.meta = ChroniquesDuZephyrDB.meta or {}
    local rv = safenum(ChroniquesDuZephyrDB.meta.rev, 0) + 1
    ChroniquesDuZephyrDB.meta.rev = rv
    ChroniquesDuZephyrDB.meta.lastModified = now()
    CDZ.Comm_Broadcast("HIST_DELETE", {
        h = tostring(hid or ""),
        rv = rv, lm = ChroniquesDuZephyrDB.meta.lastModified,
    })
end

-- ===== Meta helpers =====
local function incRev()
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}; ChroniquesDuZephyrDB.meta = ChroniquesDuZephyrDB.meta or {}
    ChroniquesDuZephyrDB.meta.rev = safenum(ChroniquesDuZephyrDB.meta.rev, 0) + 1
    ChroniquesDuZephyrDB.meta.lastModified = now()
    return ChroniquesDuZephyrDB.meta.rev
end

-- ===== Handshake / Init =====
function CDZ.Sync_RequestHello()
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
    CDZ._helloSent  = true
    CDZ._lastHelloHid = hid

    CDZ.Comm_Broadcast("HELLO", { hid = hid, rv = rv_me, player = me, caps = "OFFER|GRANT|TOKEN1" })
end


function CDZ.Comm_Init()
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

    -- Normalisation éventuelle du master stocké (realm)
    if ChroniquesDuZephyrDB and ChroniquesDuZephyrDB.meta and ChroniquesDuZephyrDB.meta.master then
        local m = ChroniquesDuZephyrDB.meta.master
        local n, r = m:match("^(.-)%-(.+)$")
        if not r then
            local _, realm = UnitFullName("player")
            ChroniquesDuZephyrDB.meta.master = m .. "-" .. (realm or "")
        end
    end

    if not CDZ._commFrame then
        local f = CreateFrame("Frame")
        f:RegisterEvent("CHAT_MSG_ADDON")
        f:SetScript("OnEvent", function(_, _, prefix, msg, channel, sender) onAddonMsg(prefix, msg, channel, sender) end)
        CDZ._commFrame = f
    end

    -- Nettoyage des fragments périmés
    if not CDZ._inboxCleaner then
        CDZ._inboxCleaner = C_Timer.NewTicker(10, function()
            local cutoff = now() - 30
            for k, box in pairs(Inbox) do if (box.ts or 0) < cutoff then Inbox[k] = nil end end
        end)
    end

    -- ✅ Démarrage automatique : envoie un HELLO pour ouvrir la découverte
    if not CDZ._helloAutoStarted then
        CDZ._helloAutoStarted = true
        C_Timer.After(1.0, function()
            if IsInGuild and IsInGuild() then
                CDZ.Sync_RequestHello()
            end
        end)
    end

    -- ✏️ Ne JAMAIS s’auto-désigner GM : on prend le roster (rang 0) si dispo
    C_Timer.After(5, function()
        if not IsInGuild or not IsInGuild() then return end
        if not ChroniquesDuZephyrDB then ChroniquesDuZephyrDB = {} end
        ChroniquesDuZephyrDB.meta = ChroniquesDuZephyrDB.meta or {}

        if not ChroniquesDuZephyrDB.meta.master or ChroniquesDuZephyrDB.meta.master == "" then
            local gmName = CDZ.GetGuildMasterCached and select(1, CDZ.GetGuildMasterCached()) or ""
            ChroniquesDuZephyrDB.meta.master = gmName or ""
            if ns.Emit then ns.Emit("meta:changed") end
        end
    end)


end

-- ===== API publique Debug =====
function CDZ.GetHelloElect() return HelloElect end
-- ➕ Accès ciblé par hid (utilisé par certains onglets Debug)
function CDZ._GetHelloElect(hid)
    return HelloElect and HelloElect[hid]
end

function CDZ.ForceMyVersion()
    if not (CDZ.IsMaster and CDZ.IsMaster()) then return end
    local rv = incRev()
    local snap = CDZ._SnapshotExport()
    snap.rv = rv
    CDZ.Comm_Broadcast("SYNC_FULL", snap)
    LastFullSentAt = now()
end

-- ===== Décodage =====
function decode(s) return decodeKV(s) end
function encode(s) return encodeKV(s) end

-- ✅ Bootstrap de secours : s’assure que Comm_Init est bien appelé
if not CDZ._autoBootstrap then
    local boot = CreateFrame("Frame")
    boot:RegisterEvent("ADDON_LOADED")
    boot:RegisterEvent("PLAYER_LOGIN")
    boot:SetScript("OnEvent", function(_, ev, name)
        if ev == "ADDON_LOADED" and name and name ~= ADDON then return end
        if CDZ._commReady then return end
        CDZ._commReady = true
        if type(CDZ.Comm_Init) == "function" then
            CDZ.Comm_Init()
        end
    end)
    CDZ._autoBootstrap = true
end