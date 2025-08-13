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
        expenses = { recording = false, list = {} },
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
    return ((p and p.credit) or 0) - ((p and p.debit) or 0)
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

-- Insertion locale (côté client) d'un joueur reçu via ROSTER_UPSERT
function CDZ.EnsureRosterLocal(name)
    if not name or name == "" then return end
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}
    ChroniquesDuZephyrDB.players = ChroniquesDuZephyrDB.players or {}
    if not ChroniquesDuZephyrDB.players[name] then
        ChroniquesDuZephyrDB.players[name] = { credit = 0, debit = 0 }
    end
end

-- Suppression locale silencieuse (sans vérif de droits, sans broadcast)
function CDZ.RemovePlayerLocal(name, silent)
    if not name or name=="" then return false end
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}
    local p = ChroniquesDuZephyrDB.players or {}
    if p[name] then p[name] = nil end
    if ChroniquesDuZephyrDB.ids and ChroniquesDuZephyrDB.ids.byName then
        local uid = ChroniquesDuZephyrDB.ids.byName[name]
        if uid then
            ChroniquesDuZephyrDB.ids.byName[name] = nil
            if ChroniquesDuZephyrDB.ids.byId then ChroniquesDuZephyrDB.ids.byId[uid] = nil end
        end
    end
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
    ChroniquesDuZephyrDB = { players = {}, history = {}, expenses = { recording=false, list={} } }
end

-- Purge complète : DB + préférences UI
function CDZ.WipeAllSaved()
    ChroniquesDuZephyrDB = { players = {}, history = {}, expenses = { recording=false, list={} } }
    ChroniquesDuZephyrUI = { point="CENTER", relTo=nil, relPoint="CENTER", x=0, y=0, width=1160, height=680 }
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
-- ===== Window Save  ======
-- =========================
function CDZ.GetSavedWindow() EnsureDB(); return ChroniquesDuZephyrUI end
function CDZ.SaveWindow(point, relTo, relPoint, x, y, w, h)
    ChroniquesDuZephyrUI = {
        point = point, relTo = relTo, relPoint = relPoint, x = x, y = y, width = w, height = h,
    }
end
