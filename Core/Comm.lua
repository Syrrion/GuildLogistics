-- ChroniquesDuZephyr/Comm.lua
local ADDON, ns = ...
ns.CDZ = ns.CDZ or {}
local CDZ, UI = ns.CDZ, ns.UI

-- ===== Constantes / État =====
local PREFIX   = "CDZ1"
local MAX_PAY  = 200   -- fragmentation des messages
local Seq      = 0     -- séquence réseau

-- Boîtes aux lettres (réassemblage) + file d'application ordonnée
local Inbox    = {}
local Q, QBusy = {}, false
local QCounter = 0

-- ===== Utils =====
local function now() return (time and time()) or 0 end
local function safenum(v, d) v = tonumber(v); if v == nil then return d or 0 end; return v end
local function truthy(v) v = tostring(v or ""); return (v == "1" or v == "true" or v == "TRUE") end

local function refreshActive()
    if ns.RefreshActive then ns.RefreshActive()
    elseif ns.RefreshAll   then ns.RefreshAll() end
end

-- ===== Debug log =====
local function pushLog(dir, msgType, sz, channel, target, seq, part, total, raw)
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}
    ChroniquesDuZephyrDB.debug = ChroniquesDuZephyrDB.debug or {}
    local t = ChroniquesDuZephyrDB.debug
    t[#t+1] = {
        ts = now(), dir = dir, type = msgType, size = sz, chan = channel or "", target = target or "",
        seq = seq or 0, part = part or 1, total = total or 1, raw = raw or ""
    }
    if #t > 800 then table.remove(t, 1) end
end
function CDZ.GetDebugLogs()  ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}; return ChroniquesDuZephyrDB.debug or {} end
function CDZ.ClearDebugLogs() ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}; ChroniquesDuZephyrDB.debug = {} end

-- ===== kv encode/decode =====
local function esc(s)  s = tostring(s or ""); s = s:gsub("\\", "\\\\"):gsub("|", "\\p"):gsub("\n", "\\n"); return s end
local function unesc(s) s = tostring(s or ""); s = s:gsub("\\n", "\n"):gsub("\\p", "|"):gsub("\\\\", "\\"); return s end

local function encode(tbl)
    local parts = {}
    for k, v in pairs(tbl or {}) do
        if type(v) == "table" then
            local arr = {}; for i = 1, #v do arr[#arr+1] = esc(v[i]) end
            parts[#parts+1] = esc(k) .. "=[" .. table.concat(arr, ",") .. "]"
        else
            parts[#parts+1] = esc(k) .. "=" .. esc(v)
        end
    end
    return table.concat(parts, "|")
end

local function decode(s)
    local out = {}
    for pair in string.gmatch(s or "", "([^|]+)") do
        local k, v = pair:match("^(.-)=(.*)$")
        if k then
            if v:find("^%[") and v:sub(-1) == "]" then
                local body = v:sub(2, -2); local arr = {}
                if body ~= "" then
                    for item in string.gmatch(body, "([^,]+)") do arr[#arr+1] = unesc(item) end
                end
                out[unesc(k)] = arr
            else
                out[unesc(k)] = unesc(v)
            end
        end
    end
    return out
end

-- Exposés pour l’écran Debug
function CDZ._decodeForDebug(s) local ok, kv = pcall(decode, s); if ok then return kv end end
function CDZ._unsafeDecode(s)  return decode(s or "") end

-- ===== Identité / GM =====
local function NormalizeFull(name, realm)
    realm = realm or ""
    realm = (realm == "" and (GetNormalizedRealmName and GetNormalizedRealmName()) or realm) or realm
    realm = realm:gsub("%s+", ""):gsub("'", "")
    return name .. "-" .. realm
end
local function playerFullName()
    local n = UnitName("player")
    local rn = (GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName()
    return NormalizeFull(n, rn)
end
local function normalizeStr(s) return (s or ""):gsub("%s+", ""):gsub("'", "") end
local function masterName()
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}; ChroniquesDuZephyrDB.meta = ChroniquesDuZephyrDB.meta or {}
    return ChroniquesDuZephyrDB.meta.master
end
function CDZ.IsMaster()
    local m = masterName()
    if m and m ~= "" then
        return normalizeStr(m) == normalizeStr(playerFullName())
    end
    if IsInGuild and IsInGuild() then
        local _, _, rankIndex = GetGuildInfo("player")
        if rankIndex == 0 then return true end
    end
    return false
end

-- ===== Version helpers =====
local function getRev()
    if CDZ.GetRev then return CDZ.GetRev() end
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}; ChroniquesDuZephyrDB.meta = ChroniquesDuZephyrDB.meta or {}
    return ChroniquesDuZephyrDB.meta.rev or 0
end
local function incRev()
    if CDZ.IncRev then return CDZ.IncRev() end
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}; ChroniquesDuZephyrDB.meta = ChroniquesDuZephyrDB.meta or {}
    ChroniquesDuZephyrDB.meta.rev = (ChroniquesDuZephyrDB.meta.rev or 0) + 1
    return ChroniquesDuZephyrDB.meta.rev
end

-- ===== Envoi (fragmenté) =====
local function send(channel, target, msgType, payloadStr)
    Seq = (Seq + 1) % 1000000
    local total = math.max(1, math.ceil(#payloadStr / MAX_PAY))
    for i = 1, total do
        local off   = (i - 1) * MAX_PAY
        local chunk = payloadStr:sub(off + 1, off + MAX_PAY)
        local head  = ("v=1|t=%s|s=%d|p=%d|n=%d|"):format(msgType, Seq, i, total)
        local packet = head .. chunk
        C_ChatInfo.SendAddonMessage(PREFIX, packet, channel, target)
        pushLog("send", msgType, #packet, channel, target, Seq, i, total, packet)
    end
end
function CDZ.Comm_Broadcast(msgType, tbl)     send("GUILD",  nil, msgType, encode(tbl or {})) end
function CDZ.Comm_Whisper(target, msgType, t) send("WHISPER",target, msgType, encode(t or {})) end

-- Forcer la version du GM : incrémente la révision puis diffuse un snapshot complet
function CDZ.GM_ForceVersionBroadcast()
    if not (CDZ.IsMaster and CDZ.IsMaster()) then return end
    local newrv = (CDZ.IncRev and CDZ.IncRev()) or incRev()
    local snap  = (CDZ._SnapshotExport and CDZ._SnapshotExport()) or {}
    CDZ.Comm_Broadcast("SYNC_FULL", snap)
    return newrv
end

-- ===== File de traitement (ordre : lm ↑ puis rv ↑ puis arrivée) =====
local function sortQueue()
    table.sort(Q, function(a, b)
        local alm = tonumber(a.orderLm) or math.huge
        local blm = tonumber(b.orderLm) or math.huge
        if alm ~= blm then return alm < blm end
        local arv = tonumber(a.orderRv) or math.huge
        local brv = tonumber(b.orderRv) or math.huge
        if arv ~= brv then return arv < brv end
        return (a.arrival or 0) < (b.arrival or 0)
    end)
end
local function processNext()
    if QBusy or #Q == 0 then return end
    sortQueue()
    local item = table.remove(Q, 1)
    QBusy = true
    local ok, err = pcall(item.handler, item.sender, item.msgType, item.kv)
    if not ok then geterrorhandler()(err) end
    C_Timer.After(0, function() QBusy = false; processNext() end)
end
local function enqueueComplete(sender, msgType, kv)
    QCounter = QCounter + 1
    local lm = tonumber(kv and kv.lm) or nil
    local rv = tonumber(kv and kv.rv) or nil
    table.insert(Q, {
        sender   = sender,
        msgType  = msgType,
        kv       = kv,
        handler  = ns.CDZ._HandleFull,
        orderLm  = lm,
        orderRv  = rv,
        arrival  = QCounter,
    })
    processNext()
end

-- ===== UID =====
function CDZ.GetUID(name)                    local m = ChroniquesDuZephyrDB and ChroniquesDuZephyrDB.ids; return m and m.byName and m.byName[name] end
function CDZ.MapUID(uid, name)
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}
    ChroniquesDuZephyrDB.ids = ChroniquesDuZephyrDB.ids or { counter = 0, byName = {}, byId = {} }
    ChroniquesDuZephyrDB.ids.byId[uid] = name
    if name and name ~= "" then ChroniquesDuZephyrDB.ids.byName[name] = uid end
end
function CDZ.GetNameByUID(uid)               local m = ChroniquesDuZephyrDB and ChroniquesDuZephyrDB.ids; return m and m.byId and m.byId[uid] end
function CDZ.GetOrAssignUID(name)
    if not name or name == "" then return nil end
    local uid = CDZ.GetUID(name); if uid then return uid end
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}
    ChroniquesDuZephyrDB.ids = ChroniquesDuZephyrDB.ids or { counter = 0, byName = {}, byId = {} }
    local ids = ChroniquesDuZephyrDB.ids
    ids.counter = (ids.counter or 0) + 1
    uid = string.format("%08x", (time() % 0x7FFFFFFF)) .. "-" .. string.format("%04x", ids.counter % 0xFFFF)
    ids.byName[name] = uid; ids.byId[uid] = name
    return uid
end

-- ===== Diffusions (mutations temps réel) =====
-- Dépenses (achats) : ajout
function CDZ.BroadcastExpenseAdd(recOrPayload, itemId)
    if not (CDZ.IsMaster and CDZ.IsMaster()) then return end
    local p
    if type(recOrPayload) == "table" and recOrPayload.id and (recOrPayload.q or recOrPayload.qty) then
        -- format compact déjà fourni
        p = {
            id = recOrPayload.id,
            s  = recOrPayload.s or recOrPayload.source or "Autre",
            i  = tonumber(recOrPayload.i or recOrPayload.itemID or itemId or 0) or 0,
            q  = tonumber(recOrPayload.q or recOrPayload.qty) or 1,
            c  = tonumber(recOrPayload.c or recOrPayload.copper) or 0,
        }
    else
        return
    end
    local rv = incRev(); local lm = now()
    p.rv = rv; p.lm = lm
    CDZ.Comm_Broadcast("EXP_ADD", p)
end

-- Lots (création / suppression / consommation) — réservé GM
function CDZ.BroadcastLotCreate(l)
    if not (CDZ.IsMaster and CDZ.IsMaster()) then return end
    if not l or not l.id then return end
    local rv = incRev(); local lm = now()
    local p = {
        id = l.id, n = l.name or "", N = tonumber(l.sessions or 1) or 1,
        u = tonumber(l.used or 0) or 0,
        t = tonumber(l.totalCopper or l.copper or 0) or 0,
        I = l.itemIds or {},
        rv = rv, lm = lm
    }
    CDZ.Comm_Broadcast("LOT_CREATE", p)
end
function CDZ.BroadcastLotDelete(id)
    if not (CDZ.IsMaster and CDZ.IsMaster()) then return end
    if not id then return end
    local rv = incRev(); local lm = now()
    CDZ.Comm_Broadcast("LOT_DELETE", { id = id, rv = rv, lm = lm })
end
function CDZ.BroadcastLotsConsume(ids)
    if not (CDZ.IsMaster and CDZ.IsMaster()) then return end
    ids = ids or {}; if #ids == 0 then return end
    local rv = incRev(); local lm = now()
    CDZ.Comm_Broadcast("LOT_CONSUME", { ids = ids, rv = rv, lm = lm })
end

-- ===== Handler principal =====
function CDZ._HandleFull(sender, msgType, kv)
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

    if msgType == "ROSTER_UPSERT" then
        if not shouldApply() then return end
        local uid, name = kv.uid, kv.name
        if uid and name then
            if CDZ.MapUID then CDZ.MapUID(uid, name) end
            if CDZ.EnsureRosterLocal then CDZ.EnsureRosterLocal(name) end
            meta.rev = (rv >= 0) and rv or myrv
            meta.lastModified = safenum(kv.lm, now())
            refreshActive()
        end

    elseif msgType == "ROSTER_REMOVE" then
        if not shouldApply() then return end
        local uid, name = kv.uid, kv.name
        if uid and name and CDZ.RemoveRosterLocal then
            CDZ.RemoveRosterLocal(name, uid)
            meta.rev = (rv >= 0) and rv or myrv
            meta.lastModified = safenum(kv.lm, now())
            refreshActive()
        end

    elseif msgType == "TX_REQ" then
        -- Demande côté GM
        if CDZ.IsMaster and CDZ.IsMaster() then
            local uid = kv.uid
            local delta = safenum(kv.delta, 0)
            local requester = kv.requester or sender
            local ts = safenum(kv.ts, now())
            if CDZ.AddIncomingRequest then CDZ.AddIncomingRequest(uid, delta, requester, ts) end
            if ns.UI and ns.UI.UpdateRequestsBadge then ns.UI.UpdateRequestsBadge() end
        end

    elseif msgType == "TX_APPLIED" then
        if not shouldApply() then return end
        local uid = kv.uid
        local delta = safenum(kv.delta, 0)
        local ts = safenum(kv.lm, now())
        local by = kv.by or sender
        local isSilent = truthy(kv.S or kv.silent)

        if uid then
            local nm = CDZ.GetNameByUID and CDZ.GetNameByUID(uid) or kv.name or "?"
            if nm and CDZ.EnsureRosterLocal then CDZ.EnsureRosterLocal(nm) end
            if CDZ.ApplyApprovedAdjust then CDZ.ApplyApprovedAdjust(uid, delta, ts, by) end

            -- Popup de clôture côté participant (si on est la cible)
            if (kv.reason == "RAID_CLOSE" or kv.R == "RAID_CLOSE") and not isSilent and delta < 0 then
                local myShort = UnitName("player")
                local who = (CDZ.ShortName and CDZ.ShortName(nm)) or nm
                if myShort and who and ((CDZ.SamePlayer and CDZ.SamePlayer(myShort, who)) or myShort == who) then
                    local after = (CDZ.GetSolde and CDZ.GetSolde(who)) or 0
                    if ns.UI and ns.UI.PopupRaidDebit then
                        ns.UI.PopupRaidDebit(who, -delta, after, { L = kv.L })
                        if ns.Emit then ns.Emit("raid:popup-shown", who) end
                    end
                end
            end
        end

        meta.rev = (rv >= 0) and rv or myrv
        meta.lastModified = ts
        refreshActive()

    elseif msgType == "TX_BATCH" then
        if not shouldApply() then return end
        local U = kv.U or {}
        local D = kv.D or {}
        local N = kv.N or {}
        local ts = safenum(kv.lm, now())
        local by = kv.by or sender
        local reason = kv.R or kv.reason
        local isSilent = truthy(kv.S or kv.silent)

        for i = 1, math.min(#U, #D) do
            local uid   = U[i]
            local delta = safenum(D[i], 0)
            local nm    = N[i]
            if uid then
                if nm and nm ~= "" and CDZ.MapUID then CDZ.MapUID(uid, nm) end
                local mappedName = (CDZ.GetNameByUID and CDZ.GetNameByUID(uid)) or nm
                if mappedName and CDZ.EnsureRosterLocal then CDZ.EnsureRosterLocal(mappedName) end
                if CDZ.ApplyApprovedAdjust then CDZ.ApplyApprovedAdjust(uid, delta, ts, by) end

                if reason == "RAID_CLOSE" and not isSilent and delta < 0 then
                    local myShort = UnitName("player")
                    local who = (CDZ.ShortName and CDZ.ShortName(mappedName)) or mappedName
                    if myShort and who and ((CDZ.SamePlayer and CDZ.SamePlayer(myShort, who)) or myShort == who) then
                        local after = (CDZ.GetSolde and CDZ.GetSolde(who)) or 0
                        if ns.UI and ns.UI.PopupRaidDebit then
                            ns.UI.PopupRaidDebit(who, -delta, after, { L = kv.L })
                            if ns.Emit then ns.Emit("raid:popup-shown", who) end
                        end
                    end
                end
            end
        end

        meta.rev = (rv >= 0) and rv or myrv
        meta.lastModified = ts
        refreshActive()

    -- ======= Synchronisation objets / lots =======

    -- Ajout d'une dépense (EXP_ADD) : { id, s=source, i=itemID, q=qty, c=copper, rv, lm }
    elseif msgType == "EXP_ADD" then
        if not shouldApply() then return end
        ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}
        ChroniquesDuZephyrDB.expenses = ChroniquesDuZephyrDB.expenses or { recording=false, list={}, nextId=1 }
        local e = ChroniquesDuZephyrDB.expenses

        local id  = tonumber(kv.id)
        if not id or id <= 0 then return end
        -- dédoublonnage
        for _, it in ipairs(e.list or {}) do if tonumber(it.id) == id then return end end

        local src = kv.s or kv.source or "Autre"
        if src == "A" then src = "HdV" elseif src == "B" then src = "Boutique" end
        local iid = tonumber(kv.i or 0) or 0
        local qty = safenum(kv.q, 1)
        local cop = safenum(kv.c, 0)
        local link = (iid > 0) and ("item:" .. tostring(iid)) or nil

        table.insert(e.list, {
            id = id,
            source = src,
            itemID = (iid > 0) and iid or nil,
            itemLink = link,
            qty = qty,
            copper = cop,
        })
        e.nextId = math.max(e.nextId or 1, id + 1)

        -- prime de cache item pour accélérer l'affichage
        if iid > 0 then
            if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(iid) end
            if GetItemInfo then GetItemInfo(iid) end
        end

        meta.rev = (rv >= 0) and rv or myrv
        meta.lastModified = (lm >= 0) and lm or now()
        refreshActive()

    -- Création lot (avec rattachements d'IDs d'objets)
    elseif msgType == "LOT_CREATE" then
        if not shouldApply() then return end
        ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}
        ChroniquesDuZephyrDB.lots = ChroniquesDuZephyrDB.lots or { nextId = 1, list = {} }
        ChroniquesDuZephyrDB.expenses = ChroniquesDuZephyrDB.expenses or { recording=false, list = {}, nextId = 1 }

        local id = safenum(kv.id, 0); if id <= 0 then return end
        -- déjà présent ?
        for _, l in ipairs(ChroniquesDuZephyrDB.lots.list) do if safenum(l.id,0) == id then return end end

        local l = {
            id = id,
            name = kv.n or ("Lot " .. tostring(id)),
            sessions = safenum(kv.N, 1),
            used = safenum(kv.u, 0),
            totalCopper = safenum(kv.t, 0),
            itemIds = {},
        }
        for _, v in ipairs(kv.I or {}) do l.itemIds[#l.itemIds+1] = safenum(v, 0) end
        table.insert(ChroniquesDuZephyrDB.lots.list, l)
        ChroniquesDuZephyrDB.lots.nextId = math.max(ChroniquesDuZephyrDB.lots.nextId or 1, id + 1)

        -- lier les dépenses
        for _, eid in ipairs(l.itemIds) do
            for _, it in ipairs(ChroniquesDuZephyrDB.expenses.list) do
                if safenum(it.id, 0) == safenum(eid, 0) then it.lotId = id; break end
            end
        end

        meta.rev = (rv >= 0) and rv or myrv
        meta.lastModified = (lm >= 0) and lm or now()
        if ns.Emit then ns.Emit("lots:changed") end
        refreshActive()

    elseif msgType == "LOT_DELETE" then
        if not shouldApply() then return end
        ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}
        ChroniquesDuZephyrDB.lots = ChroniquesDuZephyrDB.lots or { nextId = 1, list = {} }
        local id = safenum(kv.id, 0); if id <= 0 then return end

        local list = ChroniquesDuZephyrDB.lots.list
        local idx  = nil
        for i, l in ipairs(list) do if safenum(l.id, 0) == id then idx = i; break end end
        if idx then table.remove(list, idx) end

        if ChroniquesDuZephyrDB.expenses and ChroniquesDuZephyrDB.expenses.list then
            for _, it in ipairs(ChroniquesDuZephyrDB.expenses.list) do
                if safenum(it.lotId, 0) == id then it.lotId = nil end
            end
        end

        meta.rev = (rv >= 0) and rv or myrv
        meta.lastModified = (lm >= 0) and lm or now()
        if ns.Emit then ns.Emit("lots:changed") end
        refreshActive()

    elseif msgType == "LOT_CONSUME" then
        if not shouldApply() then return end
        ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}
        ChroniquesDuZephyrDB.lots = ChroniquesDuZephyrDB.lots or { nextId = 1, list = {} }

        local set = {}
        for _, v in ipairs(kv.ids or {}) do set[safenum(v, -1)] = true end
        for _, l in ipairs(ChroniquesDuZephyrDB.lots.list) do
            if set[safenum(l.id, -2)] then l.used = safenum(l.used, 0) + 1 end
        end

        meta.rev = (rv >= 0) and rv or myrv
        meta.lastModified = (lm >= 0) and lm or now()
        if ns.Emit then ns.Emit("lots:changed") end
        refreshActive()

    -- ======= Handshake & Snapshots =======

    elseif msgType == "SYNC_HELLO" then
        -- Application immédiate si plus récent (roster/ids + E/L si fournis)
        if shouldApply() and (kv.P and kv.I) then
            CDZ._SnapshotApply(kv)
            refreshActive()
        end
        -- Répondre par FULL si on est plus à jour
        local cli_rv, cli_lm = safenum(kv.rv, -1), safenum(kv.lm, -1)
        local myrv2 = safenum(meta.rev, 0)
        local mylm2 = safenum(meta.lastModified, 0)
        if (cli_rv >= 0 and myrv2 > cli_rv) or (cli_rv < 0 and mylm2 > cli_lm) then
            local snap = CDZ._SnapshotExport()
            CDZ.Comm_Whisper(sender, "SYNC_FULL", snap)
        end

    elseif msgType == "SYNC_FULL" then
        if not shouldApply() then return end
        CDZ._SnapshotApply(kv)
        refreshActive()
    end
end

-- ===== Réception bas niveau =====
local function onAddonMsg(prefix, message, channel, sender)
    if prefix ~= PREFIX then return end
    local t, s, p, n = message:match("v=1|t=([^|]+)|s=(%d+)|p=(%d+)|n=(%d+)|")
    local seq  = safenum(s, 0)
    local part = safenum(p, 1)
    local total= safenum(n, 1)
    pushLog("recv", t or "?", #message, channel, sender, seq, part, total, message)
    if not t then return end

    local payload = message:match("|n=%d+|(.*)$") or ""
    local key = sender .. "#" .. tostring(seq)
    local box = Inbox[key]
    if not box then
        box = { total = total, got = 0, parts = {}, ts = now() }
        Inbox[key] = box
    else
        box.total = math.max(box.total or total, total)
        box.ts = now()
    end

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
            Inbox[key] = nil
            local full = table.concat(chunks, "")
            local kv = decode(full)
            enqueueComplete(sender, t, kv)
        end
    end
end

-- ===== Envoi mutations (roster & crédits) =====
function CDZ.BroadcastRosterUpsert(name)
    if not (CDZ.IsMaster and CDZ.IsMaster()) then return end
    if not name or name=="" then return end
    local uid = CDZ.GetOrAssignUID(name)
    local rv = incRev(); local lm = now()
    CDZ.Comm_Broadcast("ROSTER_UPSERT", { uid=uid, name=name, rv=rv, lm=lm })
end
function CDZ.BroadcastRosterRemove(name)
    if not (CDZ.IsMaster and CDZ.IsMaster()) then return end
    if not name or name=="" then return end
    local uid = CDZ.GetUID and CDZ.GetUID(name) or nil
    local rv = incRev(); local lm = now()
    CDZ.Comm_Broadcast("ROSTER_REMOVE", { uid=uid, name=name, rv=rv, lm=lm })
end
function CDZ.GM_ApplyAndBroadcast(name, delta)
    if not (CDZ.IsMaster and CDZ.IsMaster()) then return end
    local uid = CDZ.GetOrAssignUID(name); if not uid then return end
    local rv = incRev(); local lm = now()
    local nm = CDZ.GetNameByUID(uid) or name
    CDZ.Comm_Broadcast("TX_APPLIED", { uid=uid, name=nm, delta=delta, rv=rv, lm=lm, by=playerFullName() })
end
function CDZ.GM_ApplyAndBroadcastEx(name, delta, extra)
    if not (CDZ.IsMaster and CDZ.IsMaster()) then return end
    local uid = CDZ.GetOrAssignUID(name); if not uid then return end
    local rv = incRev(); local lm = now()
    local nm = CDZ.GetNameByUID(uid) or name
    local p = { uid=uid, name=nm, delta=delta, rv=rv, lm=lm, by=playerFullName() }
    if type(extra)=="table" then for k,v in pairs(extra) do if p[k]==nil then p[k]=v end end end
    CDZ.Comm_Broadcast("TX_APPLIED", p)
end
function CDZ.GM_ApplyAndBroadcastByUID(uid, delta)
    if not (CDZ.IsMaster and CDZ.IsMaster()) then return end
    if not uid or uid=="" then return end
    local rv = incRev(); local lm = now()
    CDZ.Comm_Broadcast("TX_APPLIED", { uid=uid, delta=delta, rv=rv, lm=lm, by=playerFullName() })
end
function CDZ.GM_BroadcastBatch(adjusts, extra)
    if not (CDZ.IsMaster and CDZ.IsMaster()) then return end
    adjusts = adjusts or {}
    local U, D, N = {}, {}, {}
    for _, a in ipairs(adjusts) do
        local nm  = a.name
        local uid = a.uid or (nm and CDZ.GetOrAssignUID and CDZ.GetOrAssignUID(nm))
        if uid then
            U[#U+1] = uid
            D[#D+1] = tostring(math.floor(tonumber(a.delta) or 0))
            local mapped = (CDZ.GetNameByUID and CDZ.GetNameByUID(uid)) or nm
            N[#N+1] = mapped or ""
        end
    end
    if #U == 0 then return end
    local rv = incRev(); local lm = now()
    local p = { U=U, D=D, N=N, rv=rv, lm=lm, by=playerFullName() }
    if extra and type(extra)=="table" then
        if extra.reason ~= nil then p.R = extra.reason end
        if extra.silent ~= nil then p.S = extra.silent and "1" or "0" end
        if extra.L      ~= nil then p.L = extra.L end
    end
    CDZ.Comm_Broadcast("TX_BATCH", p)
end

-- ===== Application locale approuvée & Demandes =====
function CDZ.ApplyApprovedAdjust(uid, delta, ts, by)
    local name = CDZ.GetNameByUID(uid); if not name or name=="" then return end
    if CDZ.AdjustSolde then CDZ.AdjustSolde(name, safenum(delta, 0)) end
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}; ChroniquesDuZephyrDB.meta = ChroniquesDuZephyrDB.meta or {}
    ChroniquesDuZephyrDB.meta.lastModified = safenum(ts, now())
end
function CDZ.RequestAdjust(name, delta)
    if not (CDZ.IsMaster and CDZ.IsMaster()) then
        local selfName = UnitName("player")
        if name ~= selfName then
            UIErrorsFrame:AddMessage("|cffff6060[CDZ]|r Action réservée à votre personnage.", 1, 0.4, 0.4)
            return
        end
    end
    local uid = CDZ.GetOrAssignUID(name) or CDZ.GetUID(name); if not uid then return end
    local payload = { uid=uid, delta=safenum(delta, 0), requester=playerFullName(), ts=now() }
    local m = masterName()
    if m and m ~= "" then CDZ.Comm_Whisper(m, "TX_REQ", payload) else CDZ.Comm_Broadcast("TX_REQ", payload) end
end
function CDZ.AddIncomingRequest(uid, delta, requester, ts)
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}; ChroniquesDuZephyrDB.requests = ChroniquesDuZephyrDB.requests or {}
    local reqId = string.format("%d.%03d", time(), math.random(0, 999))
    table.insert(ChroniquesDuZephyrDB.requests, { id=reqId, uid=uid, delta=safenum(delta, 0), requester=requester, ts=ts or now() })
    if ns.UI and ns.UI.PopupRequest then
        local displayName = CDZ.GetNameByUID(uid) or requester or "?"
        ns.UI.PopupRequest(displayName, delta,
            function() CDZ.GM_ApplyAndBroadcastByUID(uid, safenum(delta, 0)); CDZ.ResolveRequest(reqId, true) end,
            function() CDZ.ResolveRequest(reqId, false, "Refus par le GM") end)
    end
    refreshActive()
end
function CDZ.GetRequests() ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}; return ChroniquesDuZephyrDB.requests or {} end
function CDZ.ResolveRequest(reqId, approved, reason)
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}; ChroniquesDuZephyrDB.requests = ChroniquesDuZephyrDB.requests or {}
    local list = ChroniquesDuZephyrDB.requests; local idx = nil
    for i, r in ipairs(list) do if r.id == reqId then idx = i; break end end
    if not idx then return end
    local r = list[idx]; table.remove(list, idx)
    if not approved then
        local target = r.requester; if target and target ~= "" then
            CDZ.Comm_Whisper(target, "TX_REFUSED", { reqId = reqId, reason = reason or "Refusé" })
        end
    end
    refreshActive()
end

-- ===== Snapshots (HELLO / FULL) =====
-- Export compact : joueurs (P), mapping ids (I), dépenses (E), lots (L)
function CDZ._SnapshotExport()
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}
    local players = ChroniquesDuZephyrDB.players or {}
    local ids     = (ChroniquesDuZephyrDB.ids and ChroniquesDuZephyrDB.ids.byId) or {}

    -- P, I
    local P, I = {}, {}
    for name, v in pairs(players) do
        local c = safenum(v.credit, 0); local d = safenum(v.debit, 0)
        P[#P+1] = string.format("%s:%d:%d", name, c, d)
    end
    for uid, name in pairs(ids) do I[#I+1] = string.format("%s:%s", uid, name) end

    -- E (dépenses) : "id:qty:copper:src(A/B/O):lotId:itemID"
    local E = {}
    local exp = (ChroniquesDuZephyrDB.expenses and ChroniquesDuZephyrDB.expenses.list) or {}
    for _, it in ipairs(exp) do
        local iid = 0
        if it.itemID then iid = safenum(it.itemID, 0)
        elseif it.itemLink and it.itemLink ~= "" and GetItemInfoInstant then
            local id = select(1, GetItemInfoInstant(it.itemLink)); iid = safenum(id, 0)
        end
        local src = (it.source == "HdV") and "A" or ((it.source == "Boutique") and "B" or "O")
        local lot = safenum(it.lotId, 0)
        E[#E+1] = string.format("%d:%d:%d:%s:%d:%d", safenum(it.id, 0), safenum(it.qty, 1), safenum(it.copper, 0), src, lot, iid)
    end

    -- L (lots) : "id:name:sessions:used:total:itemIdsCsv"
    local L = {}
    local lots = (ChroniquesDuZephyrDB.lots and ChroniquesDuZephyrDB.lots.list) or {}
    for _, l in ipairs(lots) do
        local idsCsv = ""
        if l.itemIds and #l.itemIds > 0 then idsCsv = table.concat(l.itemIds, ",") end
        local nm = tostring(l.name or ""):gsub(":", "‖")
        L[#L+1] = string.format("%d:%s:%d:%d:%d:%s", safenum(l.id, 0), nm, safenum(l.sessions, 1), safenum(l.used, 0), safenum(l.totalCopper or l.copper, 0), idsCsv)
    end

    local lm = safenum(ChroniquesDuZephyrDB.meta and ChroniquesDuZephyrDB.meta.lastModified, 0)
    local rv = safenum(ChroniquesDuZephyrDB.meta and ChroniquesDuZephyrDB.meta.rev, getRev())
    local fs = now()
    ChroniquesDuZephyrDB.meta = ChroniquesDuZephyrDB.meta or {}; ChroniquesDuZephyrDB.meta.fullStamp = fs
    return { lm = lm, fs = fs, rv = rv, P = P, I = I, E = E, L = L }
end

function CDZ._SnapshotApply(kv)
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}; ChroniquesDuZephyrDB.meta = ChroniquesDuZephyrDB.meta or {}
    local meta = ChroniquesDuZephyrDB.meta
    local rv   = safenum(kv.rv, -1); local myrv = safenum(meta.rev, 0)
    local lm   = safenum(kv.lm, -1); local mylm = safenum(meta.lastModified, 0)

    if rv >= 0 then if rv < myrv then return end else if lm >= 0 and lm < mylm then return end end

    -- P/I
    local P, I = kv.P or {}, kv.I or {}
    ChroniquesDuZephyrDB.players = {}
    for i = 1, #P do
        local name, c, d = string.match(P[i], "^(.-):(-?%d+):(-?%d+)$")
        if name then ChroniquesDuZephyrDB.players[name] = { credit = safenum(c, 0), debit = safenum(d, 0) } end
    end
    ChroniquesDuZephyrDB.ids = { counter = 0, byName = {}, byId = {} }
    for i = 1, #I do
        local uid, name = string.match(I[i], "^(.-):(.*)$")
        if uid and name then ChroniquesDuZephyrDB.ids.byId[uid] = name; ChroniquesDuZephyrDB.ids.byName[name] = uid end
    end

    -- E (dépenses)
    ChroniquesDuZephyrDB.expenses = ChroniquesDuZephyrDB.expenses or { recording=false, list = {}, nextId = 1 }
    local E = kv.E or {}
    local newList, maxId = {}, 0
    for i = 1, #E do
        local id,q,c,src,lot,iid = string.match(E[i], "^(%d+):(%d+):(%d+):([ABO]):(%d+):(%d+)$")
        if id then
            local rec = {
                id     = safenum(id, 0),
                qty    = safenum(q, 1),
                copper = safenum(c, 0),
                source = (src == "A") and "HdV" or ((src == "B") and "Boutique" or "Autre"),
            }
            local lotId = safenum(lot, 0); if lotId > 0 then rec.lotId = lotId end
            local itemId = safenum(iid, 0)
            if itemId > 0 then rec.itemID = itemId; rec.itemLink = "item:" .. tostring(itemId) end
            newList[#newList+1] = rec
            maxId = math.max(maxId, rec.id)
        end
    end
    ChroniquesDuZephyrDB.expenses.list   = newList
    ChroniquesDuZephyrDB.expenses.nextId = (maxId > 0) and (maxId + 1) or 1

    -- L (lots)
    ChroniquesDuZephyrDB.lots = ChroniquesDuZephyrDB.lots or { nextId = 1, list = {} }
    local L = kv.L or {}
    local lotList, maxLot = {}, 0
    for i = 1, #L do
        local id, nm, ses, used, tot, csv = string.match(L[i], "^(%d+):(.-):(%d+):(%d+):(%d+):(.*)$")
        if id then
            nm = (nm or ""):gsub("‖", ":")
            local l = {
                id = safenum(id, 0),
                name = nm,
                sessions = safenum(ses, 1),
                used = safenum(used, 0),
                totalCopper = safenum(tot, 0),
                itemIds = {},
            }
            for v in tostring(csv or ""):gmatch("(%-?%d+)") do l.itemIds[#l.itemIds+1] = safenum(v, 0) end
            lotList[#lotList+1] = l; maxLot = math.max(maxLot, l.id)
        end
    end
    ChroniquesDuZephyrDB.lots.list   = lotList
    ChroniquesDuZephyrDB.lots.nextId = (maxLot > 0) and (maxLot + 1) or 1

    meta.rev = (rv >= 0) and rv or myrv
    meta.lastModified = (lm >= 0) and lm or now()
    meta.fullStamp = safenum(kv.fs, now())
end

-- ===== Handshake / Init =====
function CDZ.Sync_RequestHello()
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}
    local snap = CDZ._SnapshotExport(); snap.who = UnitName("player")
    local m = (ChroniquesDuZephyrDB.meta and ChroniquesDuZephyrDB.meta.master) or nil
    if m and m ~= "" then CDZ.Comm_Whisper(m, "SYNC_HELLO", snap) else CDZ.Comm_Broadcast("SYNC_HELLO", snap) end
end

function CDZ.Comm_Init()
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

    -- Normalisation éventuelle du master stocké (realm)
    if ChroniquesDuZephyrDB and ChroniquesDuZephyrDB.meta and ChroniquesDuZephyrDB.meta.master then
        local m = ChroniquesDuZephyrDB.meta.master
        local n, r = m:match("^(.-)%-(.+)$")
        if n and r then ChroniquesDuZephyrDB.meta.master = n .. "-" .. r:gsub("%s+", ""):gsub("'", "") end
    end

    -- Listener CHAT_MSG_ADDON
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

    -- Auto-définition du master si GM et non défini
    C_Timer.After(5, function()
        if not IsInGuild or not IsInGuild() then return end
        ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}
        ChroniquesDuZephyrDB.meta = ChroniquesDuZephyrDB.meta or {}
        local m = ChroniquesDuZephyrDB.meta.master
        if not m or m == "" then
            local _, _, ri = GetGuildInfo("player")
            if ri == 0 then
                ChroniquesDuZephyrDB.meta.master = playerFullName()
                if ns.RefreshAll then ns.RefreshAll() end
            end
        end
    end)

    -- HELLO initial (léger) pour récupérer P/I/E/L
    C_Timer.After(3, function() if IsInGuild() then CDZ.Sync_RequestHello() end end)
end

-- ===== Slash =====
SLASH_CDZMASTER1 = "/cdzmaster"
SlashCmdList.CDZMASTER = function()
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}; ChroniquesDuZephyrDB.meta = ChroniquesDuZephyrDB.meta or {}
    ChroniquesDuZephyrDB.meta.master = playerFullName()
    print("|cff9ecbff[CDZ]|r Vous êtes maintenant maître:", ChroniquesDuZephyrDB.meta.master)
    if ns.RefreshAll then ns.RefreshAll() end
end

SLASH_CDZSYNC1 = "/cdzsync"
SlashCmdList.CDZSYNC = function()
    CDZ.Sync_RequestHello()
    print("|cff9ecbff[CDZ]|r Sync demandée (HELLO)")
end
