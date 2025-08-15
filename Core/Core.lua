local ADDON, ns = ...
ns.CDZ = ns.CDZ or {}
local CDZ = ns.CDZ

-- =========================
-- ======  DATABASE   ======
-- =========================
local function EnsureDB()
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {
        players = {},
        history = {},
        expenses = { recording = false, list = {}, nextId = 1 },
        lots     = { nextId = 1, list = {} },
        ids = { counter=0, byName={}, byId={} },
        meta = { lastModified=0, fullStamp=0, rev=0, master=nil }, -- + rev
        requests = {},
        debug = {},
    }
    ChroniquesDuZephyrUI = ChroniquesDuZephyrUI or {
        point="CENTER", relTo=nil, relPoint="CENTER", x=0, y=0, width=1160, height=680,
        minimap = { hide = false, angle = 215 },
    }
    ChroniquesDuZephyrUI.minimap = ChroniquesDuZephyrUI.minimap or { hide=false, angle=215 }
    if ChroniquesDuZephyrUI.minimap.angle == nil then ChroniquesDuZephyrUI.minimap.angle = 215 end
end

CDZ._EnsureDB = EnsureDB

-- =========================
-- ======  PLAYERS    ======
-- =========================
local function GetOrCreatePlayer(name)
    EnsureDB()
    if not name or name == "" then return { credit=0, debit=0 } end
    local p = ChroniquesDuZephyrDB.players[name]
    if not p then
        p = { credit = 0, debit = 0 }
        ChroniquesDuZephyrDB.players[name] = p
    end
    return p
end

function CDZ.GetPlayersArray()
    EnsureDB()
    local out = {}
    for name, p in pairs(ChroniquesDuZephyrDB.players) do
        local credit = tonumber(p.credit) or 0
        local debit  = tonumber(p.debit) or 0
        table.insert(out, { name=name, credit=credit, debit=debit, solde=credit-debit })
    end
    table.sort(out, function(a,b) return a.name:lower() < b.name:lower() end)
    return out
end

function CDZ.AddPlayer(name)
    if not name or name == "" then return end
    GetOrCreatePlayer(name)
    if CDZ.GetOrAssignUID then CDZ.GetOrAssignUID(name) end
    if CDZ.BroadcastRosterUpsert and CDZ.IsMaster and CDZ.IsMaster() then
        CDZ.BroadcastRosterUpsert(name)
    end
    return true
end


function CDZ.RemovePlayer(name)
    if not (CDZ.IsMaster and CDZ.IsMaster()) then
        UIErrorsFrame:AddMessage("|cffff6060[CDZ]|r Suppression du roster réservée au GM.", 1, 0.4, 0.4)
        return false
    end
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}
    local p = ChroniquesDuZephyrDB.players or {}
    if p[name] then p[name] = nil end
    -- Optionnel: retirer l'UID mappé
    if ChroniquesDuZephyrDB.ids and ChroniquesDuZephyrDB.ids.byName then
        local uid = ChroniquesDuZephyrDB.ids.byName[name]
        if uid then
            ChroniquesDuZephyrDB.ids.byName[name] = nil
            if ChroniquesDuZephyrDB.ids.byId then ChroniquesDuZephyrDB.ids.byId[uid] = nil end
        end
    end
    if ns.RefreshAll then ns.RefreshAll() end
    return true
end


function CDZ.HasPlayer(name)
    EnsureDB()
    if not name or name == "" then return false end
    return ChroniquesDuZephyrDB.players[name] ~= nil
end

function CDZ.Credit(name, amount)
    local p = GetOrCreatePlayer(name)
    local a = math.floor(tonumber(amount) or 0)
    p.credit = (p.credit or 0) + a
end

function CDZ.Debit(name, amount)
    local p = GetOrCreatePlayer(name)
    local a = math.floor(tonumber(amount) or 0)
    p.debit = (p.debit or 0) + a
end

function CDZ.GetSolde(name)
    local p = GetOrCreatePlayer(name)
    return (p.credit or 0) - (p.debit or 0)
end

function CDZ.ShortName(name)
    if not name or name == "" then return name end
    local short = name:match("^[^-]+") or name
    return short
end

function CDZ.SamePlayer(a, b)
    if not a or not b then return false end
    local sa = string.lower(CDZ.ShortName(a))
    local sb = string.lower(CDZ.ShortName(b))
    return sa == sb
end


-- Ajuste directement le solde d’un joueur : delta > 0 => ajoute de l’or, delta < 0 => retire de l’or
function CDZ.AdjustSolde(name, delta)
    local d = math.floor(tonumber(delta) or 0)
    if d == 0 then return CDZ.GetSolde(name) end
    if d > 0 then CDZ.Credit(name, d) else CDZ.Debit(name, -d) end
    return CDZ.GetSolde(name)
end

-- Marquer la modif + broadcast par le GM depuis une seule API dédiée
function CDZ.GM_AdjustAndBroadcast(name, delta)
    if CDZ.GM_ApplyAndBroadcast then CDZ.GM_ApplyAndBroadcast(name, delta) end
end

-- Helpers conviviaux
function CDZ.AddGold(name, amount)
    return CDZ.AdjustSolde(name, math.floor(tonumber(amount) or 0))
end

function CDZ.RemoveGold(name, amount)
    return CDZ.AdjustSolde(name, -math.floor(tonumber(amount) or 0))
end

-- === Bus d’événements minimal ===
ns._ev = ns._ev or {}
function ns.On(evt, fn)
    if not evt or type(fn)~="function" then return end
    ns._ev[evt] = ns._ev[evt] or {}
    table.insert(ns._ev[evt], fn)
end
function ns.Emit(evt, ...)
    local t = ns._ev and ns._ev[evt]
    if not t then return end
    for i=1,#t do
        local ok,err = pcall(t[i], ...)
        if not ok then geterrorhandler()(err) end
    end
end

function CDZ.EnsureRosterLocal(name)
    if not name or name == "" then return end
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}
    ChroniquesDuZephyrDB.players = ChroniquesDuZephyrDB.players or {}
    local created = false
    if not ChroniquesDuZephyrDB.players[name] then
        ChroniquesDuZephyrDB.players[name] = { credit = 0, debit = 0 }
        created = true
    end
    if created then ns.Emit("roster:upsert", name) end
end

function CDZ.RemovePlayerLocal(name, silent)
    if not name or name=="" then return false end
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}
    local p = ChroniquesDuZephyrDB.players or {}
    local existed = not not p[name]
    if p[name] then p[name] = nil end
    if ChroniquesDuZephyrDB.ids and ChroniquesDuZephyrDB.ids.byName then
        local uid = ChroniquesDuZephyrDB.ids.byName[name]
        if uid then
            ChroniquesDuZephyrDB.ids.byName[name] = nil
            if ChroniquesDuZephyrDB.ids.byId then ChroniquesDuZephyrDB.ids.byId[uid] = nil end
        end
    end
    if existed then ns.Emit("roster:removed", name) end
    if not silent and ns.RefreshAll then ns.RefreshAll() end
    return true
end


-- Suppression orchestrée : réservée au GM + broadcast
-- Remplace la version précédente de RemovePlayer si déjà présente
function CDZ.RemovePlayer(name)
    if not (CDZ.IsMaster and CDZ.IsMaster()) then
        UIErrorsFrame:AddMessage("|cffff6060[CDZ]|r Suppression du roster réservée au GM.", 1, 0.4, 0.4)
        return false
    end
    if not name or name=="" then return false end
    local uid = CDZ.GetUID and CDZ.GetUID(name) or nil
    CDZ.RemovePlayerLocal(name, true)
    -- Diffuse la suppression à toute la guilde
    if CDZ.Comm_Broadcast then
        CDZ.Comm_Broadcast("ROSTER_REMOVE", { uid = uid, name = name })
    end
    if ns.RefreshAll then ns.RefreshAll() end
    return true
end

-- =========================
-- ======  HISTORY    ======
-- =========================
function CDZ.AddHistorySession(total, perHead, participants)
    EnsureDB()
    local s = {
        ts = time(),
        total = math.floor(total or 0),
        perHead = math.floor(perHead or 0),
        count = #participants,
        participants = { unpack(participants or {}) },
        refunded = false,
    }
    table.insert(ChroniquesDuZephyrDB.history, 1, s)
end

function CDZ.GetHistory()
    EnsureDB()
    return ChroniquesDuZephyrDB.history
end

function CDZ.RefundSession(idx)
    EnsureDB()
    local s = ChroniquesDuZephyrDB.history[idx]
    if not s or s.refunded then return false end
    local per = tonumber(s.perHead) or 0
    local parts = s.participants or {}

    if CDZ.IsMaster and CDZ.IsMaster() and CDZ.GM_BroadcastBatch then
        local adjusts = {}
        for _, name in ipairs(parts) do adjusts[#adjusts+1] = { name = name, delta = per } end
        CDZ.GM_BroadcastBatch(adjusts, { reason = "REFUND", silent = true })
    else
        for _, name in ipairs(parts) do if ChroniquesDuZephyrDB.players[name] then CDZ.Credit(name, per) end end
    end

    s.refunded = true
    return true
end

function CDZ.UnrefundSession(idx)
    EnsureDB()
    local s = ChroniquesDuZephyrDB.history[idx]
    if not s or not s.refunded then return false end
    local per = tonumber(s.perHead) or 0
    local parts = s.participants or {}

    if CDZ.IsMaster and CDZ.IsMaster() and CDZ.GM_BroadcastBatch then
        local adjusts = {}
        for _, name in ipairs(parts) do adjusts[#adjusts+1] = { name = name, delta = -per } end
        CDZ.GM_BroadcastBatch(adjusts, { reason = "REFUND", silent = true })
    else
        for _, name in ipairs(parts) do if ChroniquesDuZephyrDB.players[name] then CDZ.Debit(name, per) end end
    end

    s.refunded = false
    return true
end


function CDZ.DeleteHistory(idx)
    EnsureDB()
    local hist = ChroniquesDuZephyrDB.history or {}
    if not hist[idx] then return false end
    -- Suppression "non-compensatrice" : n'ajuste jamais les soldes.
    table.remove(hist, idx)
    return true
end


function CDZ.WipeAllData()
    -- Conserver la version uniquement pour le GM (joueurs : réinitialiser à 0)
    local isMaster = (CDZ.IsMaster and CDZ.IsMaster())
        or (IsInGuild and IsInGuild() and select(3, GetGuildInfo("player")) == 0)
        or false
    local oldRev     = (ChroniquesDuZephyrDB and ChroniquesDuZephyrDB.meta and ChroniquesDuZephyrDB.meta.rev) or 0
    local keepRev    = isMaster and oldRev or 0
    local keepMaster = (ChroniquesDuZephyrDB and ChroniquesDuZephyrDB.meta and ChroniquesDuZephyrDB.meta.master) or nil
    ChroniquesDuZephyrDB = {
        players  = {},
        history  = {},
        expenses = { recording = false, list = {}, nextId = 1 },
        lots     = { nextId = 1, list = {} },
        ids      = { counter=0, byName={}, byId={} },
        meta     = { lastModified=0, fullStamp=0, rev=keepRev, master=keepMaster },
        requests = {},
        debug    = {},
    }
end

-- Purge complète : DB + préférences UI
function CDZ.WipeAllSaved()
    -- Conserver la version uniquement pour le GM (joueurs : réinitialiser à 0)
    local isMaster = (CDZ.IsMaster and CDZ.IsMaster())
        or (IsInGuild and IsInGuild() and select(3, GetGuildInfo("player")) == 0)
        or false
    local oldRev     = (ChroniquesDuZephyrDB and ChroniquesDuZephyrDB.meta and ChroniquesDuZephyrDB.meta.rev) or 0
    local keepRev    = isMaster and oldRev or 0
    local keepMaster = (ChroniquesDuZephyrDB and ChroniquesDuZephyrDB.meta and ChroniquesDuZephyrDB.meta.master) or nil
    ChroniquesDuZephyrDB = {
        players  = {},
        history  = {},
        expenses = { recording = false, list = {}, nextId = 1 },
        lots     = { nextId = 1, list = {} },
        ids      = { counter=0, byName={}, byId={} },
        meta     = { lastModified=0, fullStamp=0, rev=keepRev, master=keepMaster },
        requests = {},
        debug    = {},
    }
    ChroniquesDuZephyrUI = { point="CENTER", relTo=nil, relPoint="CENTER", x=0, y=0, width=1160, height=680, minimap = { hide=false, angle=215 } }
end

function CDZ.GetRev()
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}
    ChroniquesDuZephyrDB.meta = ChroniquesDuZephyrDB.meta or {}
    return ChroniquesDuZephyrDB.meta.rev or 0
end

function CDZ.IncRev()
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}
    ChroniquesDuZephyrDB.meta = ChroniquesDuZephyrDB.meta or {}
    ChroniquesDuZephyrDB.meta.rev = (ChroniquesDuZephyrDB.meta.rev or 0) + 1
    return ChroniquesDuZephyrDB.meta.rev
end

-- =========================
-- ======   LOTS      ======
-- =========================
-- Lots consommables : 1 session (100%) ou multi-sessions (1/N par clôture).
-- Le contenu d'un lot est figé à la création. Les éléments proviennent des
-- "Ressources libres" (dépenses non rattachées).

local function _ensureLots()
    CDZ._EnsureDB()
    ChroniquesDuZephyrDB.lots     = ChroniquesDuZephyrDB.lots     or { nextId = 1, list = {} }
    ChroniquesDuZephyrDB.expenses = ChroniquesDuZephyrDB.expenses or { recording=false, list = {}, nextId = 1 }
end

function CDZ.GetLots()
    _ensureLots()
    return ChroniquesDuZephyrDB.lots.list
end

function CDZ.Lot_GetById(id)
    _ensureLots()
    for _, l in ipairs(ChroniquesDuZephyrDB.lots.list or {}) do
        if l.id == id then return l end
    end
end

function CDZ.Lot_Status(lot)
    if not lot then return "?" end
    local used = tonumber(lot.used or 0) or 0
    local N    = tonumber(lot.sessions or 1) or 1
    if used <= 0 then return "A_UTILISER" end
    if used < N  then return "EN_COURS"  end
    return "EPU"
end

function CDZ.Lot_IsSelectable(lot)
    return lot and CDZ.Lot_Status(lot) ~= "EPU"
end

-- Coût par utilisation (ex-ShareGold) en or entiers — pas de PA/PC.
function CDZ.Lot_ShareGold(lot)  -- compat : on conserve le nom
    local totalC = tonumber(lot.totalCopper or lot.copper or 0) or 0
    local N      = tonumber(lot.sessions or 1) or 1
    return math.floor( math.floor(totalC / 10000) / N )
end

-- ➕ Utilitaires "charges"
function CDZ.Lot_UseCostGold(lot)  -- alias explicite
    return CDZ.Lot_ShareGold(lot)
end

function CDZ.Lot_Remaining(lot)   -- utilisations restantes
    local used = tonumber(lot.used or 0) or 0
    local N    = tonumber(lot.sessions or 1) or 1
    return math.max(0, N - used)
end

-- Création : fige le contenu depuis une liste d'index ABSOLUS de ChroniquesDuZephyrDB.expenses.list
-- isMulti = true/false ; sessions = N si multi (>=1)
function CDZ.Lot_Create(name, isMulti, sessions, absIdxs)
    _ensureLots()
    name = name or "Lot"
    local e = ChroniquesDuZephyrDB.expenses
    local L = ChroniquesDuZephyrDB.lots
    local id = L.nextId or 1

    local itemIds, total = {}, 0
    for _, abs in ipairs(absIdxs or {}) do
        local it = e.list[abs]
        if it and not it.lotId then
            table.insert(itemIds, it.id or 0)
            total = total + (tonumber(it.copper) or 0)
            it.lotId = id
        end
    end

    local l = { id = id, name = name, sessions = isMulti and (tonumber(sessions) or 2) or 1, used = 0, totalCopper = total, itemIds = itemIds }
    table.insert(L.list, l); L.nextId = id + 1
    if ns.Emit then ns.Emit("lots:changed") end

    -- ➕ Diffusion GM
    if CDZ.BroadcastLotCreate and CDZ.IsMaster and CDZ.IsMaster() then CDZ.BroadcastLotCreate(l) end
    return l
end

-- Suppression possible uniquement si jamais utilisé (rend les ressources libres)
function CDZ.Lot_Delete(id)
    _ensureLots()
    local L = ChroniquesDuZephyrDB.lots
    local list = L.list or {}
    local idx = nil
    for i, l in ipairs(list) do if l.id == id then idx = i break end end
    if not idx then return false end
    table.remove(list, idx)
    for _, it in ipairs(ChroniquesDuZephyrDB.expenses.list or {}) do if it.lotId == id then it.lotId = nil end end
    if ns.Emit then ns.Emit("lots:changed") end
    -- ➕ Diffusion GM
    if CDZ.BroadcastLotDelete and CDZ.IsMaster and CDZ.IsMaster() then CDZ.BroadcastLotDelete(id) end
    return true
end


function CDZ.Lot_ListSelectable()
    _ensureLots()
    local out = {}
    for _, l in ipairs(ChroniquesDuZephyrDB.lots.list or {}) do
        if CDZ.Lot_IsSelectable(l) then out[#out+1] = l end
    end
    return out
end

function CDZ.Lot_Consume(id)
    _ensureLots()
    local l = CDZ.Lot_GetById(id); if not l then return false end
    local N = tonumber(l.sessions or 1) or 1
    local u = tonumber(l.used or 0) or 0
    l.used = math.min(u + 1, N)  -- ne décrémente que d'1, borné au max
    if ns.RefreshAll then ns.RefreshAll() end
    return true
end

function CDZ.Lots_ConsumeMany(ids)
    _ensureLots()
    ids = ids or {}

    local isMaster = CDZ.IsMaster and CDZ.IsMaster()
    if isMaster then
        -- GM : ne pas appliquer localement pour éviter un double comptage.
        -- La diffusion réappliquera pour tous (y compris GM) via le handler LOT_CONSUME.
        if CDZ.BroadcastLotsConsume then CDZ.BroadcastLotsConsume(ids) end
    else
        -- Client : applique localement sans diffusion.
        local L = ChroniquesDuZephyrDB.lots
        for _, id in ipairs(ids) do
            for _, l in ipairs(L.list or {}) do
                if l.id == id then l.used = (tonumber(l.used or 0) or 0) + 1 end
            end
        end
        if ns.Emit then ns.Emit("lots:changed") end
    end
end

function CDZ.Lots_ComputeGoldTotal(ids)
    local g = 0
    for _, id in ipairs(ids or {}) do
        local l = CDZ.Lot_GetById(id)
        if l and CDZ.Lot_IsSelectable(l) then g = g + CDZ.Lot_ShareGold(l) end
    end
    return g
end

-- =========================
-- ===== Window Save  ======
-- =========================
function CDZ.GetSavedWindow() EnsureDB(); return ChroniquesDuZephyrUI end
function CDZ.SaveWindow(point, relTo, relPoint, x, y, w, h)
    ChroniquesDuZephyrUI = {
        point = point, relTo = relTo, relPoint = relPoint, x = x, y = y, width = w, height = h,
    }
end
