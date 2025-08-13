-- Core/Comm.lua
local ADDON, ns = ...
ns.CDZ = ns.CDZ or {}
local CDZ, UI = ns.CDZ, ns.UI

-- ===== Constantes / Etat =====
local PREFIX = "CDZ1"
local MAX_PAY = 240
local Seq = 0

local Inbox = {} -- réassemblage
local Q, QBusy = {}, false
local QCounter = 0

-- ===== Utils =====
local function now() return (time and time()) or 0 end
local function safenum(v, d) v = tonumber(v); if v==nil then return d or 0 end; return v end

local function refreshActive()
    if ns.RefreshActive then ns.RefreshActive()
    elseif ns.RefreshAll then ns.RefreshAll() end
end

-- Debug log (avec paquet brut)
local function pushLog(dir, msgType, sz, channel, target, seq, part, total, raw)
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}
    ChroniquesDuZephyrDB.debug = ChroniquesDuZephyrDB.debug or {}
    local t = ChroniquesDuZephyrDB.debug
    t[#t+1] = { ts=now(), dir=dir, type=msgType, size=sz, chan=channel or "", target=target or "",
                seq=seq or 0, part=part or 1, total=total or 1, raw=raw or "" }
    if #t > 800 then table.remove(t, 1) end
end
function CDZ.GetDebugLogs()
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}
    return ChroniquesDuZephyrDB.debug or {}
end
-- Vide l’historique des messages
function CDZ.ClearDebugLogs()
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}
    ChroniquesDuZephyrDB.debug = {}
end

-- kv encode/decode
local function esc(s) s=tostring(s or ""); s=s:gsub("\\","\\\\"):gsub("|","\\p"):gsub("\n","\\n"); return s end
local function unesc(s) s=tostring(s or ""); s=s:gsub("\\n","\n"):gsub("\\p","|"):gsub("\\\\","\\"); return s end
local function encode(tbl)
    local parts = {}
    for k,v in pairs(tbl or {}) do
        if type(v)=="table" then
            local arr = {}; for i=1,#v do arr[#arr+1]=esc(v[i]) end
            parts[#parts+1]=esc(k).."=["..table.concat(arr,",").."]"
        else
            parts[#parts+1]=esc(k).."="..esc(v)
        end
    end
    return table.concat(parts,"|")
end
local function decode(s)
    local out = {}
    for pair in string.gmatch(s or "","([^|]+)") do
        local k,v = pair:match("^(.-)=(.*)$")
        if k then
            if v:find("^%[") and v:sub(-1)=="]" then
                local body=v:sub(2,-2); local arr={}
                if body~="" then for item in string.gmatch(body,"([^,]+)") do arr[#arr+1]=unesc(item) end end
                out[unesc(k)]=arr
            else out[unesc(k)]=unesc(v) end
        end
    end
    return out
end

-- Identité
local function NormalizeFull(name, realm)
    realm = realm or ""
    realm = (realm=="" and (GetNormalizedRealmName and GetNormalizedRealmName()) or realm) or realm
    realm = realm:gsub("%s+",""):gsub("'","")
    return name.."-"..realm
end
local function playerFullName()
    local n=UnitName("player"); local rn=(GetNormalizedRealmName and GetNormalizedRealmName()) or GetRealmName()
    return NormalizeFull(n, rn)
end

local function normalizeStr(s) return (s or ""):gsub("%s+",""):gsub("'","") end
local function masterName()
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}; ChroniquesDuZephyrDB.meta = ChroniquesDuZephyrDB.meta or {}
    return ChroniquesDuZephyrDB.meta.master
end

function CDZ.IsMaster()
    local m = masterName()
    if m and m ~= "" then
        return normalizeStr(m) == normalizeStr(playerFullName())
    end
    -- Fallback : si aucun "maître" défini, seul le chef de guilde est GM.
    if IsInGuild and IsInGuild() then
        local guildName, rankName, rankIndex = GetGuildInfo("player")
        if guildName and rankIndex == 0 then
            return true
        end
    end
    return false
end

local function setMasterOnce(name)
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}; ChroniquesDuZephyrDB.meta = ChroniquesDuZephyrDB.meta or {}
    if not ChroniquesDuZephyrDB.meta.master or ChroniquesDuZephyrDB.meta.master=="" then
        local n,r = name:match("^(.-)%-(.+)$")
        if n and r then r=r:gsub("%s+",""):gsub("'",""); ChroniquesDuZephyrDB.meta.master=n.."-"..r
        else ChroniquesDuZephyrDB.meta.master=name end
    end
end

-- Version helpers
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

-- Envoi (fragmenté)
local function send(channel, target, msgType, payloadStr)
    Seq = (Seq + 1) % 1000000
    local total = math.max(1, math.ceil(#payloadStr / MAX_PAY))
    for i=1,total do
        local off=(i-1)*MAX_PAY
        local chunk=payloadStr:sub(off+1, off+MAX_PAY)
        local head=("v=1|t=%s|s=%d|p=%d|n=%d|"):format(msgType, Seq, i, total)
        local packet = head..chunk
        C_ChatInfo.SendAddonMessage(PREFIX, packet, channel, target)
        pushLog("send", msgType, #packet, channel, target, Seq, i, total, packet)
    end
end
function CDZ.Comm_Broadcast(msgType, tbl) send("GUILD", nil, msgType, encode(tbl or {})) end
function CDZ.Comm_Whisper(target, msgType, tbl) send("WHISPER", target, msgType, encode(tbl or {})) end

-- File séquentielle triée : lm ↑ puis rv ↑ puis ordre d'arrivée
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
    if QBusy then return end
    if #Q == 0 then return end
    sortQueue()
    local item = table.remove(Q, 1)
    QBusy = true
    local ok, err = pcall(item.handler, item.sender, item.msgType, item.kv)
    if not ok then geterrorhandler()(err) end
    C_Timer.After(0, function() QBusy=false; processNext() end)
end

local function enqueueComplete(sender, msgType, kv)
    QCounter = QCounter + 1
    local lm = tonumber(kv and kv.lm) or nil
    local rv = tonumber(kv and kv.rv) or nil
    table.insert(Q, {
        sender=sender, msgType=msgType, kv=kv, handler=ns.CDZ._HandleFull,
        orderLm = lm, orderRv = rv, arrival = QCounter,
    })
    processNext()
end


-- UID
function CDZ.GetUID(name) local m=ChroniquesDuZephyrDB and ChroniquesDuZephyrDB.ids; return m and m.byName and m.byName[name] end
function CDZ.MapUID(uid, name)
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}
    ChroniquesDuZephyrDB.ids = ChroniquesDuZephyrDB.ids or { counter=0, byName={}, byId={} }
    ChroniquesDuZephyrDB.ids.byId[uid]=name; if name and name~="" then ChroniquesDuZephyrDB.ids.byName[name]=uid end
end
function CDZ.GetNameByUID(uid) local m=ChroniquesDuZephyrDB and ChroniquesDuZephyrDB.ids; return m and m.byId and m.byId[uid] end
function CDZ.GetOrAssignUID(name)
    if not name or name=="" then return nil end
    local uid = CDZ.GetUID(name); if uid then return uid end
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}
    ChroniquesDuZephyrDB.ids = ChroniquesDuZephyrDB.ids or { counter=0, byName={}, byId={} }
    local ids = ChroniquesDuZephyrDB.ids
    ids.counter=(ids.counter or 0)+1
    uid = string.format("%08x",(time()%0x7FFFFFFF)).."-"..string.format("%04x", ids.counter%0xFFFF)
    ids.byName[name]=uid; ids.byId[uid]=name; return uid
end

-- ===== Handler principal =====
function CDZ._HandleFull(sender, msgType, kv)
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}; ChroniquesDuZephyrDB.meta = ChroniquesDuZephyrDB.meta or {}
    local meta = ChroniquesDuZephyrDB.meta

    local rv  = safenum(kv.rv, -1)
    local myrv= safenum(meta.rev, 0)
    local lm  = safenum(kv.lm, -1)
    local mylm= safenum(meta.lastModified, 0)

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
            meta.rev = (rv>=0) and rv or myrv
            meta.lastModified = (lm>=0) and lm or now()
            refreshActive()
        end
        setMasterOnce(sender)

    elseif msgType == "ROSTER_REMOVE" then
        if not shouldApply() then return end
        local name = kv.name
        if name and CDZ.RemovePlayerLocal then
            CDZ.RemovePlayerLocal(name, true)
            meta.rev = (rv>=0) and rv or myrv
            meta.lastModified = (lm>=0) and lm or now()
            refreshActive()
        end

    elseif msgType == "TX_REQ" then
        if CDZ.IsMaster() and CDZ.AddIncomingRequest then
            local uid = kv.uid
            if not uid and kv.name and CDZ.GetOrAssignUID then uid = CDZ.GetOrAssignUID(kv.name) end
            if uid then
                local delta = safenum(kv.delta, 0)
                local requester = kv.requester or sender
                local ts = safenum(kv.ts, now())
                CDZ.AddIncomingRequest(uid, delta, requester, ts)
            end
        end

    elseif msgType == "TX_APPLIED" then
        if not shouldApply() then return end
        local uid = kv.uid; local delta = safenum(kv.delta,0)
        local ts = (lm>=0) and lm or now()
        local by = kv.by or sender
        local nm = kv.name

        if uid and nm then
            if CDZ.MapUID then CDZ.MapUID(uid, nm) end
            if CDZ.EnsureRosterLocal then CDZ.EnsureRosterLocal(nm) end
        end

        if CDZ.ApplyApprovedAdjust then CDZ.ApplyApprovedAdjust(uid, delta, ts, by) end
        meta.rev = (rv>=0) and rv or myrv
        meta.lastModified = ts
        refreshActive()

        -- Popup uniquement pour la personne concernée par une clôture de raid non silencieuse
        if kv.reason == "RAID_CLOSE" and not kv.silent and delta < 0 then
            local me = UnitName("player")
            if me and nm and CDZ.NormName(me) == CDZ.NormName(nm) then
                local after = CDZ.GetSolde and CDZ.GetSolde(nm) or 0
                if ns.UI and ns.UI.PopupRaidDebit then ns.UI.PopupRaidDebit(nm, -delta, after) end
            end
        end

        -- Popup "Bon raid !" uniquement pour la personne concernée par une clôture de raid
        if kv.reason == "RAID_CLOSE" and delta < 0 then
            local my = UnitName("player")
            local targetName = CDZ.GetNameByUID(uid) or nm
            if my and targetName and CDZ.NormName and CDZ.NormName(my) == CDZ.NormName(targetName) then
                local after = (CDZ.GetSolde and CDZ.GetSolde(targetName)) or 0
                if ns.UI and ns.UI.PopupRaidDebit then
                    ns.UI.PopupRaidDebit(targetName, -delta, after)
                end
            end
        end

    elseif msgType == "TX_REFUSED" then
        UIErrorsFrame:AddMessage("|cffff6060[CDZ]|r Demande refusée : "..(kv.reason or "Refusé"), 1, 0.4, 0.4)

    elseif msgType == "SYNC_HELLO" then
        if shouldApply() and kv.P and kv.I then
            CDZ._SnapshotApply(kv)
            refreshActive()
        end
        local cli_rv, cli_lm = safenum(kv.rv,-1), safenum(kv.lm,-1)
        if (cli_rv>=0 and myrv>cli_rv) or (cli_rv<0 and mylm>cli_lm) then
            local snap = CDZ._SnapshotExport()
            CDZ.Comm_Whisper(sender, "SYNC_FULL", snap)
        end

    elseif msgType == "SYNC_FULL" then
        if not shouldApply() then return end
        CDZ._SnapshotApply(kv)
        refreshActive()
    end
end

-- ===== Réception (réassemblage) =====
local function onAddonMsg(prefix, message, channel, sender)
    if prefix ~= PREFIX then return end
    local t,s,p,n = message:match("v=1|t=([^|]+)|s=(%d+)|p=(%d+)|n=(%d+)|")
    local seq=safenum(s,0); local part=safenum(p,1); local total=safenum(n,1)
    pushLog("recv", t or "?", #message, channel, sender, seq, part, total, message)
    if not t then return end

    local payload = message:match("|n=%d+|(.*)$") or ""
    local key = sender.."#"..tostring(seq)
    local box = Inbox[key]
    if not box then box = { total=total, got=0, parts={} }; Inbox[key]=box end
    box.parts[part]=payload; box.got=box.got+1
    if box.got >= box.total then
        Inbox[key]=nil
        local full = table.concat(box.parts, "")
        local kv = decode(full)
        enqueueComplete(sender, t, kv)
    end
end

-- ===== Envoi mutations =====
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
    local p = { uid = uid, name = nm, delta = delta, rv = rv, lm = lm, by = playerFullName() }
    if type(extra) == "table" then for k,v in pairs(extra) do if p[k]==nil then p[k]=v end end end
    CDZ.Comm_Broadcast("TX_APPLIED", p)
end

function CDZ.GM_ApplyAndBroadcastByUID(uid, delta)
    if not (CDZ.IsMaster and CDZ.IsMaster()) then return end
    if not uid or uid == "" then return end
    local rv = incRev(); local lm = now()
    CDZ.Comm_Broadcast("TX_APPLIED", { uid = uid, delta = delta, rv = rv, lm = lm, by = playerFullName() })
end

-- Application locale d'un ajustement approuvé
function CDZ.ApplyApprovedAdjust(uid, delta, ts, by)
    local name = CDZ.GetNameByUID(uid); if not name or name=="" then return end
    if CDZ.AdjustSolde then CDZ.AdjustSolde(name, safenum(delta,0)) end
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}; ChroniquesDuZephyrDB.meta = ChroniquesDuZephyrDB.meta or {}
    ChroniquesDuZephyrDB.meta.lastModified = safenum(ts, now())
end

-- Demande côté joueur
function CDZ.RequestAdjust(name, delta)
    if not (CDZ.IsMaster and CDZ.IsMaster()) then
        local selfName = UnitName("player")
        if name ~= selfName then
            UIErrorsFrame:AddMessage("|cffff6060[CDZ]|r Action réservée à votre personnage.", 1, 0.4, 0.4)
            return
        end
    end
    local uid = CDZ.GetOrAssignUID(name) or CDZ.GetUID(name); if not uid then return end
    local payload = { uid=uid, delta=safenum(delta,0), requester=playerFullName(), ts=now() }
    local m = masterName()
    if m and m~="" then CDZ.Comm_Whisper(m, "TX_REQ", payload) else CDZ.Comm_Broadcast("TX_REQ", payload) end
end

-- Demandes (GM)
function CDZ.AddIncomingRequest(uid, delta, requester, ts)
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}; ChroniquesDuZephyrDB.requests = ChroniquesDuZephyrDB.requests or {}
    local reqId = string.format("%d.%03d", time(), math.random(0,999))
    table.insert(ChroniquesDuZephyrDB.requests, { id=reqId, uid=uid, delta=safenum(delta,0), requester=requester, ts=ts or now() })
    if ns.UI and ns.UI.PopupRequest then
        -- Nom d'affichage : mapping connu, sinon on tombe sur le demandeur (requester)
        local displayName = CDZ.GetNameByUID(uid) or requester or "?"
        ns.UI.PopupRequest(displayName, delta,
            function() CDZ.GM_ApplyAndBroadcastByUID(uid, safenum(delta,0)); CDZ.ResolveRequest(reqId, true) end,
            function() CDZ.ResolveRequest(reqId, false, "Refus par le GM") end)
    end
    refreshActive()
end

function CDZ.GetRequests()
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}; return ChroniquesDuZephyrDB.requests or {}
end

function CDZ.ResolveRequest(reqId, approved, reason)
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}; ChroniquesDuZephyrDB.requests = ChroniquesDuZephyrDB.requests or {}
    local list = ChroniquesDuZephyrDB.requests; local idx=nil
    for i,r in ipairs(list) do if r.id==reqId then idx=i break end end
    if not idx then return end
    local r = list[idx]; table.remove(list, idx)
    if not approved then
        local target=r.requester; if target and target~="" then
            CDZ.Comm_Whisper(target, "TX_REFUSED", { reqId=reqId, reason=reason or "Refusé" })
        end
    end
    refreshActive()
end

-- Snapshot
function CDZ._SnapshotExport()
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}
    local players = ChroniquesDuZephyrDB.players or {}
    local ids = (ChroniquesDuZephyrDB.ids and ChroniquesDuZephyrDB.ids.byId) or {}
    local P, I = {}, {}
    for name,v in pairs(players) do
        local c=safenum(v.credit,0); local d=safenum(v.debit,0)
        P[#P+1]=string.format("%s:%d:%d", name, c, d)
    end
    for uid,name in pairs(ids) do I[#I+1]=string.format("%s:%s", uid, name) end
    local lm=safenum(ChroniquesDuZephyrDB.meta and ChroniquesDuZephyrDB.meta.lastModified, 0)
    local rv=safenum(ChroniquesDuZephyrDB.meta and ChroniquesDuZephyrDB.meta.rev, getRev())
    local fs=now()
    ChroniquesDuZephyrDB.meta=ChroniquesDuZephyrDB.meta or {}; ChroniquesDuZephyrDB.meta.fullStamp=fs
    return { lm=lm, fs=fs, rv=rv, P=P, I=I }
end

function CDZ._SnapshotApply(kv)
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}; ChroniquesDuZephyrDB.meta = ChroniquesDuZephyrDB.meta or {}
    local meta = ChroniquesDuZephyrDB.meta
    local rv  = safenum(kv.rv, -1); local myrv=safenum(meta.rev, 0)
    local lm  = safenum(kv.lm, -1); local mylm=safenum(meta.lastModified, 0)

    if rv >= 0 then if rv < myrv then return end
    else if lm >= 0 and lm < mylm then return end end

    local P, I = kv.P or {}, kv.I or {}
    ChroniquesDuZephyrDB.players = {}
    for i=1,#P do
        local name,c,d = string.match(P[i], "^(.-):(-?%d+):(-?%d+)$")
        if name then ChroniquesDuZephyrDB.players[name] = { credit=safenum(c,0), debit=safenum(d,0) } end
    end
    ChroniquesDuZephyrDB.ids = { counter=0, byName={}, byId={} }
    for i=1,#I do
        local uid,name = string.match(I[i], "^(.-):(.*)$")
        if uid and name then ChroniquesDuZephyrDB.ids.byId[uid]=name; ChroniquesDuZephyrDB.ids.byName[name]=uid end
    end

    meta.rev = (rv>=0) and rv or myrv
    meta.lastModified = (lm>=0) and lm or now()
    meta.fullStamp = safenum(kv.fs, now())
end

-- Handshake / Init
function CDZ.Sync_RequestHello()
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}
    local snap = CDZ._SnapshotExport(); snap.who = UnitName("player")
    local m = (ChroniquesDuZephyrDB.meta and ChroniquesDuZephyrDB.meta.master) or nil
    if m and m~="" then CDZ.Comm_Whisper(m, "SYNC_HELLO", snap) else CDZ.Comm_Broadcast("SYNC_HELLO", snap) end
end

function CDZ.Comm_Init()
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    if ChroniquesDuZephyrDB and ChroniquesDuZephyrDB.meta and ChroniquesDuZephyrDB.meta.master then
        local m=ChroniquesDuZephyrDB.meta.master; local n,r=m:match("^(.-)%-(.+)$")
        if n and r then ChroniquesDuZephyrDB.meta.master = n.."-"..r:gsub("%s+",""):gsub("'","") end
    end
    if not CDZ._commFrame then
        local f=CreateFrame("Frame")
        f:RegisterEvent("CHAT_MSG_ADDON")
        f:SetScript("OnEvent", function(_,_,prefix,msg,channel,sender) onAddonMsg(prefix,msg,channel,sender) end)
        CDZ._commFrame=f
    end
    
    C_Timer.After(5, function()
        if not IsInGuild or not IsInGuild() then return end
        ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}
        ChroniquesDuZephyrDB.meta = ChroniquesDuZephyrDB.meta or {}
        local m = ChroniquesDuZephyrDB.meta.master
        if not m or m == "" then
            local g, rn, ri = GetGuildInfo("player")
            if g and ri == 0 then
                ChroniquesDuZephyrDB.meta.master = playerFullName()
                if ns.RefreshAll then ns.RefreshAll() end
            end
        end
    end)

    C_Timer.After(3, function() if IsInGuild() then CDZ.Sync_RequestHello() end end)
end

-- Slashes
SLASH_CDZMASTER1="/cdzmaster"
SlashCmdList.CDZMASTER=function()
    ChroniquesDuZephyrDB=ChroniquesDuZephyrDB or {}; ChroniquesDuZephyrDB.meta=ChroniquesDuZephyrDB.meta or {}
    ChroniquesDuZephyrDB.meta.master = playerFullName()
    print("|cff9ecbff[CDZ]|r Vous êtes maintenant maître:", ChroniquesDuZephyrDB.meta.master)
    if ns.RefreshAll then ns.RefreshAll() end
end

SLASH_CDZSYNC1="/cdzsync"
SlashCmdList.CDZSYNC=function() CDZ.Sync_RequestHello(); print("|cff9ecbff[CDZ]|r Sync demandée (HELLO)") end
