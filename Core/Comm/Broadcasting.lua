-- Module de broadcasting pour GuildLogistics
-- Gère toutes les fonctions de diffusion réseau des mutations de données

local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
local GLOG = ns.GLOG

-- Références aux utilitaires centralisées
local U = ns.Util or {}
local safenum = U.safenum
local now = U.now
local playerFullName = U.playerFullName

-- ===== Helpers de versioning =====
local function incRev()
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.meta = GuildLogisticsDB.meta or {}
    GuildLogisticsDB.meta.rev = safenum(GuildLogisticsDB.meta.rev, 0) + 1
    GuildLogisticsDB.meta.lastModified = now()
    return GuildLogisticsDB.meta.rev
end

-- ===== Roster Broadcasts =====
function GLOG.BroadcastRosterUpsert(name)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
    if not name or name=="" then return end
    -- 🔒 Toujours travailler sur un nom complet strict
    local full = (GLOG.ResolveFullNameStrict and GLOG.ResolveFullNameStrict(name))
              or (type(name)=="string" and name:find("%-") and ((ns.Util and ns.Util.CleanFullName and ns.Util.CleanFullName(name)) or name))
    if not full or full == "" then return end

    local uid = GLOG.GetOrAssignUID(full)
    if not uid then return end
    local rv = incRev()
    local alias = (GLOG.GetAliasFor and GLOG.GetAliasFor(full)) or nil
    
    if GLOG.Comm_Broadcast then
        GLOG.Comm_Broadcast("ROSTER_UPSERT", {
            uid = uid, name = full, alias = alias,
            rv = rv, lm = GuildLogisticsDB.meta.lastModified
        })
    end
end

function GLOG.BroadcastRosterRemove(idOrName)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
    if not idOrName or idOrName=="" then return end

    local uid, name = nil, nil
    local s = tostring(idOrName or "")

    -- Heuristique: si cela ressemble à un nom complet (avec '-') → c'est un nom; sinon, essaye comme UID d'abord
    if s:find("%-") then
        name = s
        uid  = (GLOG.FindUIDByName and GLOG.FindUIDByName(name)) or (GLOG.GetUID and GLOG.GetUID(name)) or nil
    else
        uid  = s
        name = (GLOG.GetNameByUID and GLOG.GetNameByUID(uid)) or nil
        if not name then
            name = s
            uid  = (GLOG.FindUIDByName and GLOG.FindUIDByName(name)) or (GLOG.GetUID and GLOG.GetUID(name)) or nil
        end
    end

    local rv = incRev()

    -- On diffuse toujours les deux champs (uid + name) si disponibles pour une réception robuste
    if GLOG.Comm_Broadcast then
        GLOG.Comm_Broadcast("ROSTER_REMOVE", {
            uid = uid, name = name, rv = rv, lm = GuildLogisticsDB.meta.lastModified
        })
    end
end

function GLOG.BroadcastRosterReserve(name, reserved)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
    if not name or name == "" then return end

    local full = (GLOG.ResolveFullNameStrict and GLOG.ResolveFullNameStrict(name))
              or (type(name)=="string" and name:find("%-") and name)
    if not full or full == "" then return end

    local uid = GLOG.GetOrAssignUID(full)
    local rv = incRev()

    if GLOG.Comm_Broadcast then
        GLOG.Comm_Broadcast("ROSTER_RESERVE", {
            uid = uid, name = full, res = reserved and 1 or 0,
            rv = rv, lm = GuildLogisticsDB.meta.lastModified
        })
    end
end

-- ===== Transaction Broadcasts =====
function GLOG.GM_ApplyAndBroadcast(name, delta)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
    -- 🔒 Résolution stricte du nom
    local full = (GLOG.ResolveFullNameStrict and GLOG.ResolveFullNameStrict(name))
              or (type(name)=="string" and name:find("%-") and ((ns.Util and ns.Util.CleanFullName and ns.Util.CleanFullName(name)) or name))
    if not full or full == "" then return end

    local uid = GLOG.GetOrAssignUID(full)
    if not uid then return end
    local rv = incRev()
    local nm = GLOG.GetNameByUID(uid) or full
    
    -- ✅ Application LOCALE côté GM (on n'attend pas notre propre message réseau)
    if delta and delta ~= 0 and GLOG.ApplyDeltaByName then
        GLOG.ApplyDeltaByName(nm, safenum(delta, 0), playerFullName())
        if ns.RefreshAll then ns.RefreshAll() end
    end
    
    if GLOG.Comm_Broadcast then
        GLOG.Comm_Broadcast("TX_APPLIED", { 
            uid=uid, name=nm, delta=delta, rv=rv, 
            lm=GuildLogisticsDB.meta.lastModified, by=playerFullName() 
        })
    end
end

function GLOG.GM_ApplyAndBroadcastEx(name, delta, extra)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
    -- 🔒 Résolution stricte du nom
    local full = (GLOG.ResolveFullNameStrict and GLOG.ResolveFullNameStrict(name))
              or (type(name)=="string" and name:find("%-") and ((ns.Util and ns.Util.CleanFullName and ns.Util.CleanFullName(name)) or name))
    if not full or full == "" then return end

    local uid = GLOG.GetOrAssignUID(full)
    if not uid then return end
    local rv = incRev()
    local nm = GLOG.GetNameByUID(uid) or full
    local p = { uid=uid, name=nm, delta=delta, rv=rv, lm=GuildLogisticsDB.meta.lastModified, by=playerFullName() }
    if type(extra)=="table" then 
        for k,v in pairs(extra) do 
            if p[k]==nil then p[k]=v end 
        end 
    end
    
    -- ✅ Application LOCALE côté GM
    if delta and delta ~= 0 and GLOG.ApplyDeltaByName then
        GLOG.ApplyDeltaByName(nm, safenum(delta, 0), playerFullName())
        if ns.RefreshAll then ns.RefreshAll() end
    end
    
    if GLOG.Comm_Broadcast then
        GLOG.Comm_Broadcast("TX_APPLIED", p)
    end
end

function GLOG.GM_ApplyAndBroadcastByUID(uid, delta, extra)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
    local rv = incRev()
    local p = {
        uid   = uid,
        name  = (GLOG.GetNameByUID and GLOG.GetNameByUID(uid)) or tostring(uid),
        delta = delta,
        rv    = rv,
        lm    = GuildLogisticsDB.meta.lastModified,
        by    = playerFullName(),
    }
    if type(extra) == "table" then
        for k, v in pairs(extra) do 
            if p[k] == nil then p[k] = v end 
        end
    end
    
    -- ✅ Application LOCALE côté GM
    if p.name and delta and delta ~= 0 and GLOG.ApplyDeltaByName then
        GLOG.ApplyDeltaByName(p.name, safenum(delta, 0), playerFullName())
        if ns.RefreshAll then ns.RefreshAll() end
    end
    
    if GLOG.Comm_Broadcast then
        GLOG.Comm_Broadcast("TX_APPLIED", p)
    end
end

function GLOG.GM_ApplyBatchAndBroadcast(uids, deltas, names, reason, silent, extra)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end

    -- Versionnage unique partagé avec le broadcast
    local rv = incRev()

    -- ✅ Application LOCALE côté GM (on n'attend pas notre propre message réseau)
    do
        local U, D, N = uids or {}, deltas or {}, names or {}
        for i = 1, math.max(#U, #D, #N) do
            local name  = N[i] or (GLOG.GetNameByUID and GLOG.GetNameByUID(U[i])) or nil
            local delta = safenum(D[i], 0)
            if name and delta ~= 0 and GLOG.ApplyDeltaByName then
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

    if GLOG.Comm_Broadcast then
        GLOG.Comm_Broadcast("TX_BATCH", p)
    end
end

-- Fonction plus simple pour les appels externes
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

-- ===== Expense Broadcasts =====
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
        -- S'assure que la séquence locale reste > id
        local nextId = safenum(GuildLogisticsDB.expenses.nextId, 1)
        if (id + 1) > nextId then GuildLogisticsDB.expenses.nextId = id + 1 end
    end

    local rv = incRev()

    if GLOG.Comm_Broadcast then
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
end

function GLOG.BroadcastExpenseSplit(p)
    local rv = incRev()

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
    if GLOG.Comm_Broadcast then
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
end

function GLOG.GM_RemoveExpense(id)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
    local rv = incRev()
    
    if GLOG.Comm_Broadcast then
        GLOG.Comm_Broadcast("EXP_REMOVE", { 
            id = safenum(id,0), rv = rv, lm = GuildLogisticsDB.meta.lastModified 
        })
    end
end

-- ===== Lot Broadcasts =====
function GLOG.BroadcastLotCreate(l)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
    local rv = incRev()

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

    for _, eid in ipairs(l.itemIds or {}) do 
        payload.I[#payload.I+1] = safenum(eid, 0) 
    end
    
    if GLOG.Comm_Broadcast then
        GLOG.Comm_Broadcast("LOT_CREATE", payload)
    end
end

function GLOG.BroadcastLotDelete(id)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
    local rv = incRev()
    
    if GLOG.Comm_Broadcast then
        GLOG.Comm_Broadcast("LOT_DELETE", { 
            id = safenum(id,0), rv = rv, lm = GuildLogisticsDB.meta.lastModified 
        })
    end
end

function GLOG.BroadcastLotsConsume(ids)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
    local rv = incRev()
    
    if GLOG.Comm_Broadcast then
        GLOG.Comm_Broadcast("LOT_CONSUME", { 
            ids = ids or {}, rv = rv, lm = GuildLogisticsDB.meta.lastModified 
        })
    end
end

-- Fonctions GM simplifiées
function GLOG.GM_CreateLot(name, sessions, totalCopper, itemIds)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.lots = GuildLogisticsDB.lots or { list = {}, nextId = 1 }

    local id = safenum(GuildLogisticsDB.lots.nextId, 1)
    GuildLogisticsDB.lots.nextId = id + 1

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

    GLOG.BroadcastLotCreate({
        id = id,
        name = name,
        sessions = safenum(sessions, 1),
        used = 0,
        totalCopper = safenum(total, 0),
        itemIds = itemIds or {},
    })
end

function GLOG.GM_DeleteLot(id)
    GLOG.BroadcastLotDelete(id)
end

function GLOG.GM_ConsumeLots(ids)
    GLOG.BroadcastLotsConsume(ids)
end

-- ===== History Broadcasts =====
function GLOG.BroadcastHistoryAdd(p)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
    local rv = incRev()
    
    if GLOG.Comm_Broadcast then
        -- Normaliser participants → UIDs
        local P = {}
        if type(p.participants) == "table" then
            for _, v in ipairs(p.participants) do
                local s = tostring(v or "")
                local uid = s
                if s:find("%-") then
                    uid = (GLOG.GetOrAssignUID and GLOG.GetOrAssignUID(s)) or s
                end
                if uid and uid ~= "" then P[#P+1] = uid end
            end
        elseif type(p.names) == "table" then
            for _, name in ipairs(p.names) do
                local full = tostring(name or "")
                local uid = (GLOG.GetOrAssignUID and GLOG.GetOrAssignUID(full)) or full
                if uid and uid ~= "" then P[#P+1] = uid end
            end
        end
        local cnt = safenum(p.count or p.c or #P, 0)
        GLOG.Comm_Broadcast("HIST_ADD", {
            h  = safenum(p.hid,0),
            ts = safenum(p.ts, now()),
            t  = safenum(p.total or p.t, 0),
            p  = safenum(p.per or p.p, 0),
            c  = cnt,
            P  = P,
            L  = p.L or {},
            r  = safenum(p.r or (p.refunded and 1 or 0), 0),
            rv = rv, lm = GuildLogisticsDB.meta.lastModified,
        })
    end
end

function GLOG.BroadcastHistoryRefund(hid, ts, flag)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
    local rv = incRev()
    
    if GLOG.Comm_Broadcast then
        GLOG.Comm_Broadcast("HIST_REFUND", {
            h  = safenum(hid, 0),
            ts = safenum(ts, 0),
            r  = flag and 1 or 0,
            rv = rv,
            lm = GuildLogisticsDB.meta.lastModified,
        })
    end
end

function GLOG.BroadcastHistoryDelete(ts)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
    local rv = incRev()
    
    if GLOG.Comm_Broadcast then
        GLOG.Comm_Broadcast("HIST_DEL", {
            ts = safenum(ts, 0),  -- ✅ Utilise timestamp au lieu de hid
            rv = rv, lm = GuildLogisticsDB.meta.lastModified,
        })
    end
end

-- ===== Main/Alt Broadcasts =====
local function _maIncRv()
    return incRev()
end

-- Diffuse l'état complet Main/Alt (compact) — utile après opérations complexes
function GLOG.BroadcastMainAltFull()
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
    GuildLogisticsDB = GuildLogisticsDB or {}
    local rv = _maIncRv()
    local MAv = 2
    local MA, AM = {}, {}
    do
    local t = GuildLogisticsDB.account or {}
    for uid, flag in pairs(t.mains or {}) do if flag then MA[#MA+1] = tostring(uid) end end
        for a, m in pairs(t.altToMain or {}) do AM[#AM+1] = tostring(a)..":"..tostring(m) end
        table.sort(MA); table.sort(AM)
    end
    if GLOG.Comm_Broadcast then
        GLOG.Comm_Broadcast("MA_FULL", { MAv = MAv, MA = MA, AM = AM, rv = rv, lm = GuildLogisticsDB.meta.lastModified })
    end
end

function GLOG.BroadcastSetAsMain(name)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
    local full = (GLOG.ResolveFullNameStrict and GLOG.ResolveFullNameStrict(name)) or name
    if not full or full == "" then return end
    local uid = GLOG.GetOrAssignUID(full); if not uid then return end
    local rv = _maIncRv()
    if GLOG.Comm_Broadcast then
        GLOG.Comm_Broadcast("MA_SET_MAIN", { u = uid, rv = rv, lm = GuildLogisticsDB.meta.lastModified })
    end
end

function GLOG.BroadcastAssignAlt(altName, mainName)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
    local a = (GLOG.ResolveFullNameStrict and GLOG.ResolveFullNameStrict(altName)) or altName
    local m = (GLOG.ResolveFullNameStrict and GLOG.ResolveFullNameStrict(mainName)) or mainName
    if not a or a == "" or not m or m == "" then return end
    local au = GLOG.GetOrAssignUID(a); local mu = GLOG.GetOrAssignUID(m)
    if not au or not mu then return end
    local rv = _maIncRv()
    if GLOG.Comm_Broadcast then
        GLOG.Comm_Broadcast("MA_ASSIGN", { a = au, m = mu, rv = rv, lm = GuildLogisticsDB.meta.lastModified })
    end
end

function GLOG.BroadcastUnassignAlt(name)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
    local full = (GLOG.ResolveFullNameStrict and GLOG.ResolveFullNameStrict(name)) or name
    if not full or full == "" then return end
    local uid = GLOG.GetOrAssignUID(full); if not uid then return end
    local rv = _maIncRv()
    if GLOG.Comm_Broadcast then
        GLOG.Comm_Broadcast("MA_UNASSIGN", { a = uid, rv = rv, lm = GuildLogisticsDB.meta.lastModified })
    end
end

function GLOG.BroadcastRemoveMain(name)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
    local full = (GLOG.ResolveFullNameStrict and GLOG.ResolveFullNameStrict(name)) or name
    if not full or full == "" then return end
    local uid = GLOG.GetOrAssignUID(full); if not uid then return end
    local rv = _maIncRv()
    if GLOG.Comm_Broadcast then
        GLOG.Comm_Broadcast("MA_REMOVE_MAIN", { u = uid, rv = rv, lm = GuildLogisticsDB.meta.lastModified })
    end
end

function GLOG.BroadcastPromoteAlt(altName, mainName)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
    local a = (GLOG.ResolveFullNameStrict and GLOG.ResolveFullNameStrict(altName)) or altName
    local m = (GLOG.ResolveFullNameStrict and GLOG.ResolveFullNameStrict(mainName)) or mainName
    if not a or a == "" or not m or m == "" then return end
    local au = GLOG.GetOrAssignUID(a); local mu = GLOG.GetOrAssignUID(m)
    if not au or not mu then return end
    local rv = _maIncRv()
    if GLOG.Comm_Broadcast then
        GLOG.Comm_Broadcast("MA_PROMOTE", { a = au, m = mu, rv = rv, lm = GuildLogisticsDB.meta.lastModified })
    end
end

-- ===== Status Update Broadcasts =====
-- Cache pour éviter de recalculer le tableau S à chaque appel
local _statusCacheTime = 0
local _statusCacheData = nil
local STATUS_CACHE_DURATION = 5  -- Cache pendant 5 secondes

-- Fonction pour invalider le cache manuellement (à appeler quand on sait que les données ont changé)
function GLOG.InvalidateStatusCache()
    _statusCacheTime = 0
    _statusCacheData = nil
end

function GLOG.CreateStatusUpdatePayload(overrides)
    overrides = overrides or {}
    local me = playerFullName()
    local nf = (ns and ns.Util and ns.Util.NormalizeFull) and ns.Util.NormalizeFull or tostring
    me = nf(me)

    if not (GLOG.IsPlayerInRosterOrReserve and GLOG.IsPlayerInRosterOrReserve(me)) then return nil end

    local ts = safenum(overrides.ts, now())
    local by = tostring(overrides.by or me)
    local myUID = (GLOG.GetOrAssignUID and GLOG.GetOrAssignUID(me)) or nil
    
    local payload = {
        name = me, ts = ts, by = by, uid = myUID,
    }

    -- Optimisation : utilise un cache pour le tableau S pour éviter de retraiter tous les joueurs
    local currentTime = GetTime()
    if not _statusCacheData or (currentTime - _statusCacheTime) > STATUS_CACHE_DURATION then
        -- Regenerer le cache
        GuildLogisticsDB = GuildLogisticsDB or {}
        GuildLogisticsDB.players = GuildLogisticsDB.players or {}
        local S = {}
        local processedCount = 0
        
    for full, rec in pairs(GuildLogisticsDB.players) do
            -- Limite le nombre de joueurs traités par appel pour éviter les freezes
            if processedCount >= 50 then break end  -- Limite arbitraire
            
            local ts2 = safenum(rec.statusTimestamp, 0)
            if ts2 > 0 then
                local uid = tostring(rec.uid or (GLOG.GetOrAssignUID and GLOG.GetOrAssignUID(full)) or "")
                if uid ~= "" then
                    local il   = (rec.ilvl       ~= nil) and math.floor(tonumber(rec.ilvl)    or 0) or -1
                    local ilMx = (rec.ilvlMax    ~= nil) and math.floor(tonumber(rec.ilvlMax) or 0) or -1
                    local mid2 = (rec.mkeyMapId  ~= nil) and safenum(rec.mkeyMapId,  -1)          or -1
                    local lvl2 = (rec.mkeyLevel  ~= nil) and safenum(rec.mkeyLevel,  -1)          or -1
                    local sc   = (rec.mplusScore ~= nil) and safenum(rec.mplusScore, -1)          or -1
                    -- Lire la version depuis account.mains[mainUID].addonVersion
                    local ver = ""
                    do
                        GuildLogisticsDB.account = GuildLogisticsDB.account or { mains = {}, altToMain = {} }
                        local t = GuildLogisticsDB.account
                        local mu = (t.altToMain and t.altToMain[uid]) or uid
                        local mrec = t.mains and t.mains[mu]
                        if mrec and mrec.addonVersion then ver = tostring(mrec.addonVersion) end
                        -- Utiliser la version cache runtime si connue
                        if (not ver or ver == "") and GLOG.GetPlayerAddonVersion then
                            local cached = GLOG.GetPlayerAddonVersion(full)
                            if cached and cached ~= "" then ver = tostring(cached) end
                        end
                        -- La version doit venir de mains ou du cache runtime
                    end
                    if (il >= 0) or (ilMx >= 0) or (mid2 >= 0) or (lvl2 >= 0) or (sc >= 0) or (ver ~= "") then
                        S[#S+1] = string.format("%s;%d;%d;%d;%d;%d;%d;%s", uid, ts2, il, ilMx, mid2, lvl2, sc, ver)
                        processedCount = processedCount + 1
                    end
                end
            end
        end
        
        _statusCacheData = S
        _statusCacheTime = currentTime
    end
    
    if #_statusCacheData > 0 then payload.S = _statusCacheData end

    -- ➕ Ajoute l'état Banque de guilde (instantané local) avec timestamp
    -- NOTE: encodeur KV ne supporte pas les objets imbriqués → utiliser des champs plats
    do
        local gbc = (GLOG.GetGuildBankBalanceCopper and GLOG.GetGuildBankBalanceCopper()) or nil
        local gbt = (GLOG.GetGuildBankTimestamp and GLOG.GetGuildBankTimestamp()) or 0
        if type(gbc) == "number" and gbc >= 0 and gbt and gbt > 0 then
            payload.gbc  = gbc  -- guild bank copper
            payload.gbts = gbt  -- guild bank timestamp
        end
    end
    
    return payload
end

-- ✨ Diffusion unifiée (iLvl + M+) dans un seul message
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
        local nm = GLOG.ResolveMKeyMapName(mid)
        if nm and nm ~= "" then map = nm end
    end

    -- ✨ Côte M+
    local score = overrides.score
    if score == nil and GLOG.ReadOwnMythicPlusScore then 
        score = GLOG.ReadOwnMythicPlusScore() 
    end
    score = safenum(score, 0)

    local ts = safenum(overrides.ts, now())
    local by = tostring(overrides.by or me)

    -- ✅ Application locale systématique (si pas déjà appliquée en amont)
    if not overrides.localApplied then
        GuildLogisticsDB = GuildLogisticsDB or {}
        GuildLogisticsDB.players = GuildLogisticsDB.players or {}
        local p = GuildLogisticsDB.players[me]   -- ⚠️ ne crée pas d'entrée
        if p then
            -- Garde-fou: ne pas appliquer iLvl/clé/score aux ALTs
            local isAlt = false
            do
                local uid = tostring(p.uid or (GLOG.GetOrAssignUID and GLOG.GetOrAssignUID(me)) or "")
                if uid ~= "" then
                    GuildLogisticsDB.account = GuildLogisticsDB.account or { mains = {}, altToMain = {} }
                    local t = GuildLogisticsDB.account
                    local mu = t.altToMain and t.altToMain[uid]
                    if mu and mu ~= uid then isAlt = true end
                end
            end
            local prev = safenum(p.statusTimestamp, 0)
            local changed = false

            -- iLvl
            if not isAlt then
                if ilvl ~= nil and ts >= prev then
                    p.ilvl = math.floor(tonumber(ilvl) or 0)
                    if ilvlMax ~= nil then p.ilvlMax = math.floor(tonumber(ilvlMax) or 0) end
                    changed = true
                    if ns.Emit then ns.Emit("ilvl:changed", me) end
                end
            end

            -- Clé M+
            if not isAlt then
                if safenum(lvl,0) > 0 and ts >= prev then
                    if mid ~= nil then p.mkeyMapId = safenum(mid, 0) end
                    p.mkeyLevel = safenum(lvl, 0)
                    changed = true
                    if ns.Emit then ns.Emit("mkey:changed", me) end
                end
            end

            -- Côte M+
            if not isAlt then
                if safenum(score, -1) >= 0 and ts >= prev then
                    p.mplusScore = safenum(score, 0)
                    changed = true
                    if ns.Emit then ns.Emit("mplus:changed", me) end
                end
            end

            -- Version de l'addon: n'écris au niveau du MAIN que si mappé alt->main OU déjà main confirmé
            local currentVersion = (GLOG.GetAddonVersion and GLOG.GetAddonVersion()) or ""
            if currentVersion ~= "" then
                local uid = tostring(p.uid or (GLOG.GetOrAssignUID and GLOG.GetOrAssignUID(me)) or "")
                if uid ~= "" then
                    GuildLogisticsDB.account = GuildLogisticsDB.account or { mains = {}, altToMain = {} }
                    local t = GuildLogisticsDB.account
                    local mapped = t.altToMain and t.altToMain[uid] or nil
                    local mu = (mapped or uid)
                    t.mains = t.mains or {}
                    if mapped and mapped ~= uid then
                        -- Alt connu: autorisé à créer/mettre à jour l'entrée du MAIN
                        t.mains[mu] = (type(t.mains[mu]) == "table") and t.mains[mu] or {}
                        t.mains[mu].addonVersion = currentVersion
                        changed = true
                    elseif type(t.mains[mu]) == "table" then
                        -- MAIN déjà confirmé: mise à jour uniquement
                        t.mains[mu].addonVersion = currentVersion
                        changed = true
                    else
                        -- Ni mappé, ni main confirmé → ne pas créer d'entrée MAIN implicite
                        -- Stocker une copie locale par personnage et cache runtime
                        p.addonVersion = currentVersion
                        if GLOG.SetPlayerAddonVersion then
                            GLOG.SetPlayerAddonVersion(me, currentVersion, ts, me)
                        end
                        changed = true
                    end
                end
            end

            if changed and ts > prev then
                p.statusTimestamp = ts
                if ns.RefreshAll then ns.RefreshAll() end
                -- Invalide le cache de statut après changement
                if GLOG.InvalidateStatusCache then GLOG.InvalidateStatusCache() end
            end
        end
    end

    -- ✉️ Diffusion réseau - Utiliser la fonction utilitaire pour créer le payload complet
    local payload = GLOG.CreateStatusUpdatePayload({ ts = ts, by = by })
    if not payload then return end -- Pas de payload si pas dans le roster

    if GLOG.Comm_Broadcast then
        GLOG.Comm_Broadcast("STATUS_UPDATE", payload)
    end
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
    GLOG.BroadcastStatusUpdate({ 
        mid = mid, lvl = lvl, ts = safenum(ts, now()), by = tostring(by or "") 
    })
end

-- ✅ Fonction manquante pour compatibilité : simple wrapper vers TX_APPLIED
function GLOG.BroadcastTxApplied(uid, name, delta, rv, lastModified, by)
    if not GLOG.Comm_Broadcast then return end
    
    GLOG.Comm_Broadcast("TX_APPLIED", {
        uid = uid,
        name = tostring(name or ""),
        delta = safenum(delta, 0),
        rv = safenum(rv, 0),
        lm = safenum(lastModified, now()),
        by = tostring(by or "")
    })
end
