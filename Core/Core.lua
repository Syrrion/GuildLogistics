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

    -- ➕ Par défaut : débug actif (Oui)
    if ChroniquesDuZephyrUI.debugEnabled == nil then ChroniquesDuZephyrUI.debugEnabled = true end
end

CDZ._EnsureDB = EnsureDB

-- ➕ API : état du débug
function CDZ.IsDebugEnabled()
    EnsureDB()
    return ChroniquesDuZephyrUI.debugEnabled ~= false
end

-- =========================
-- ======  PLAYERS    ======
-- =========================
local function GetOrCreatePlayer(name)
    EnsureDB()
    if not name or name == "" then return { credit=0, debit=0, reserved=false } end
    local p = ChroniquesDuZephyrDB.players[name]
    if not p then
        p = { credit = 0, debit = 0, reserved = false }  -- ➕ flag de réserve par défaut
        ChroniquesDuZephyrDB.players[name] = p
    else
        if p.reserved == nil then p.reserved = false end -- compat données anciennes
    end
    return p
end

-- ➕ Statut « en réserve » (tolérant plusieurs clés héritées)
function CDZ.IsReserved(name)
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}
    local p = ChroniquesDuZephyrDB.players and ChroniquesDuZephyrDB.players[name]
    if not p then return false end
    -- Tolère reserved / reserve / bench, ou un status textuel
    local v = p.reserved
           or p.reserve
           or p.bench
           or ((type(p.status)=="string") and (p.status:upper()=="RESERVE" or p.status:upper()=="RESERVED"))
    if type(v) == "boolean" then return v end
    if type(v) == "number"  then return v ~= 0 end
    if type(v) == "string"  then return v:lower() ~= "false" and v ~= "" end
    return false
end
-- Alias rétro-compatible si jamais du code appelle IsReserve()
CDZ.IsReserve = CDZ.IsReserved

function CDZ.GetPlayersArray()
    EnsureDB()
    local out = {}
    for name, p in pairs(ChroniquesDuZephyrDB.players) do
        local credit   = tonumber(p.credit) or 0
        local debit    = tonumber(p.debit)  or 0
        local reserved = (p.reserved == true)
        table.insert(out, {
            name   = name,
            credit = credit,
            debit  = debit,
            solde  = credit - debit,
            reserved = reserved,          -- ✅ on propage le statut pour les filtres en aval
        })
    end
    table.sort(out, function(a,b) return a.name:lower() < b.name:lower() end)
    return out
end

-- ➕ Sous-ensembles utiles à l’UI (actif / réserve)
function CDZ.GetPlayersArrayActive()
    local src = CDZ.GetPlayersArray()
    local out = {}
    for _, r in ipairs(src) do
        -- ✅ robuste même si un appelant fournit une ligne sans champ 'reserved'
        local isRes = (r.reserved ~= nil) and r.reserved
                      or (CDZ.IsReserved and CDZ.IsReserved(r.name)) or false
        if not isRes then out[#out+1] = r end
    end
    return out
end


function CDZ.GetPlayersArrayReserve()
    EnsureDB()
    local out = {}
    for name, p in pairs(ChroniquesDuZephyrDB.players) do
        if p.reserved then
            local credit = tonumber(p.credit) or 0
            local debit  = tonumber(p.debit) or 0
            out[#out+1] = {
                name = name, credit = credit, debit = debit,
                solde = credit - debit, reserved = true
            }
        end
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

-- ➕ Statut "en réserve" (alias bench pris en charge)
function CDZ.IsReserve(name)
    EnsureDB()
    if not name or name == "" then return false end
    local p = ChroniquesDuZephyrDB.players[name]
    return (p and ((p.reserve == true) or (p.bench == true))) or false
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

function CDZ.SamePlayer(a, b)
    if not a or not b then return false end
    -- Comparaison stricte sur le nom complet (insensible à la casse)
    return string.lower(tostring(a)) == string.lower(tostring(b))
end


-- ➕ Normalisation des clés joueurs (merge "Nom" et "Nom-Realm", dédoublonne les realms répétés)
function CDZ.NormalizePlayerKeys()
    if not ChroniquesDuZephyrDB then return end
    ChroniquesDuZephyrDB.players = ChroniquesDuZephyrDB.players or {}
    ChroniquesDuZephyrDB.uids    = ChroniquesDuZephyrDB.uids    or {}

    local function dedupRealm(full)
        full = tostring(full or "")
        local base, realm = full:match("^(.-)%-(.+)$")
        if not realm then
            -- si pas de realm : on rajoute celui du perso courant si disponible
            local rn = select(2, UnitFullName("player"))
            return (rn and rn ~= "" and (full.."-"..rn)) or full
        end
        -- garde uniquement le 1er segment de realm (évite A-B-C lors d’insertions successives)
        realm = realm:match("^([^%-]+)") or realm
        return string.format("%s-%s", base, realm)
    end

    -- 1) Rebuild players avec clés normalisées + fusion des soldes
    local rebuilt = {}
    for name, rec in pairs(ChroniquesDuZephyrDB.players) do
        local norm = (NormalizeFull and NormalizeFull(name)) or name
        norm = dedupRealm(norm)
        local dst = rebuilt[norm]
        if not dst then
            rebuilt[norm] = { credit = tonumber(rec.credit) or 0, debit = tonumber(rec.debit) or 0 }
        else
            dst.credit = (dst.credit or 0) + (tonumber(rec.credit) or 0)
            dst.debit  = (dst.debit  or 0) + (tonumber(rec.debit)  or 0)
        end
    end
    ChroniquesDuZephyrDB.players = rebuilt

    -- 2) Normalise aussi la table des UIDs -> noms
    local newUIDs = {}
    for uid, n in pairs(ChroniquesDuZephyrDB.uids) do
        local norm = (NormalizeFull and NormalizeFull(n)) or n
        newUIDs[tostring(uid)] = dedupRealm(norm)
    end
    ChroniquesDuZephyrDB.uids = newUIDs
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
        ChroniquesDuZephyrDB.players[name] = { credit = 0, debit = 0, reserved = false }
        created = true
    else
        if ChroniquesDuZephyrDB.players[name].reserved == nil then
            ChroniquesDuZephyrDB.players[name].reserved = false
        end
    end
    if created then ns.Emit("roster:upsert", name) end
end

function CDZ.RemovePlayerLocal(name, silent)
    if not name or name=="" then return false end
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}
    local p = ChroniquesDuZephyrDB.players or {}
    local existed = not not p[name]
    if p[name] then p[name] = nil end

    -- ancien mapping (legacy)
    if ChroniquesDuZephyrDB.ids and ChroniquesDuZephyrDB.ids.byName then
        local _uid = ChroniquesDuZephyrDB.ids.byName[name]
        if _uid then
            ChroniquesDuZephyrDB.ids.byName[name] = nil
            if ChroniquesDuZephyrDB.ids.byId then ChroniquesDuZephyrDB.ids.byId[_uid] = nil end
        end
    end

    -- purge aussi la table des UID actifs
    if ChroniquesDuZephyrDB.uids then
        local uid = nil
        if CDZ.FindUIDByName then
            uid = CDZ.FindUIDByName(name)
        elseif ns and ns.Util and ns.Util.FindUIDByName then
            uid = ns.Util.FindUIDByName(name)
        end
        if not uid then
            for k,v in pairs(ChroniquesDuZephyrDB.uids) do if v == name then uid = k break end end
        end
        if uid then ChroniquesDuZephyrDB.uids[uid] = nil end
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

    -- Applique localement (GM)
    CDZ.RemovePlayerLocal(name, true)

    -- Incrémente la révision et horodate pour les clients qui filtrent sur rv/lm
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}
    ChroniquesDuZephyrDB.meta = ChroniquesDuZephyrDB.meta or {}
    local rv = (ChroniquesDuZephyrDB.meta.rev or 0) + 1
    ChroniquesDuZephyrDB.meta.rev = rv
    ChroniquesDuZephyrDB.meta.lastModified = time()

    -- Diffuse la suppression à toute la guilde avec rv/lm
    if CDZ.Comm_Broadcast then
        CDZ.Comm_Broadcast("ROSTER_REMOVE", {
            uid = uid,
            name = name,
            rv  = rv,
            lm  = ChroniquesDuZephyrDB.meta.lastModified,
        })
    end

    if ns.RefreshAll then ns.RefreshAll() end
    return true
end

-- ➕ API réserve : lecture + application locale + commande GM + broadcast
function CDZ.IsReserved(name)
    EnsureDB()
    local p = name and ChroniquesDuZephyrDB.players and ChroniquesDuZephyrDB.players[name]
    return (p and p.reserved) and true or false
end

local function _SetReservedLocal(name, flag)
    local p = GetOrCreatePlayer(name)
    local prev = not not p.reserved
    p.reserved = not not flag
    if prev ~= p.reserved and ns.Emit then ns.Emit("roster:reserve", name, p.reserved) end
end

function CDZ.GM_SetReserved(name, flag)
    if not (CDZ.IsMaster and CDZ.IsMaster()) then
        if UIErrorsFrame then
            UIErrorsFrame:AddMessage("|cffff6060[CDZ]|r Changement d’attribution réservé au GM.", 1, .4, .4)
        end
        return false
    end
    if not name or name=="" then return false end

    _SetReservedLocal(name, flag)

    ChroniquesDuZephyrDB.meta = ChroniquesDuZephyrDB.meta or {}
    local rv = (ChroniquesDuZephyrDB.meta.rev or 0) + 1
    ChroniquesDuZephyrDB.meta.rev = rv
    ChroniquesDuZephyrDB.meta.lastModified = time()

    local uid = (CDZ.GetUID and CDZ.GetUID(name)) or (CDZ.FindUIDByName and CDZ.FindUIDByName(name)) or nil
    if CDZ.Comm_Broadcast then
        CDZ.Comm_Broadcast("ROSTER_RESERVE", {
            uid = uid, name = name, res = flag and 1 or 0,
            rv = rv, lm = ChroniquesDuZephyrDB.meta.lastModified
        })
    end
    if ns.RefreshAll then ns.RefreshAll() end
    return true
end

-- =========================
-- ======  HISTORY    ======
-- =========================
function CDZ.AddHistorySession(total, perHead, participants, ctx)
    EnsureDB()
    local s = {
        ts = time(),
        total = math.floor(total or 0),
        perHead = math.floor(perHead or 0),
        count = #(participants or {}),
        participants = { unpack(participants or {}) },
        refunded = false,
    }
    if type(ctx) == "table" and ctx.lots then
        s.lots = ctx.lots
    end
    table.insert(ChroniquesDuZephyrDB.history, 1, s)

    -- Diffusion réseau (petit message) si GM
    if CDZ.IsMaster and CDZ.IsMaster() and CDZ.Comm_Broadcast then
        ChroniquesDuZephyrDB.meta = ChroniquesDuZephyrDB.meta or {}
        local rv = (ChroniquesDuZephyrDB.meta.rev or 0) + 1
        ChroniquesDuZephyrDB.meta.rev = rv
        ChroniquesDuZephyrDB.meta.lastModified = time()
        CDZ.Comm_Broadcast("HIST_ADD", {
            ts = s.ts, total = s.total, per = s.perHead, cnt = s.count,
            r = s.refunded and 1 or 0, P = s.participants,
            rv = rv, lm = ChroniquesDuZephyrDB.meta.lastModified,
        })
    end
    if ns.Emit then ns.Emit("history:changed") end
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

    -- Diffusion du changement d'état si GM
    if CDZ.IsMaster and CDZ.IsMaster() and CDZ.Comm_Broadcast then
        ChroniquesDuZephyrDB.meta = ChroniquesDuZephyrDB.meta or {}
        local rv = (ChroniquesDuZephyrDB.meta.rev or 0) + 1
        ChroniquesDuZephyrDB.meta.rev = rv
        ChroniquesDuZephyrDB.meta.lastModified = time()
        CDZ.Comm_Broadcast("HIST_REFUND", { ts = s.ts, rv = rv, lm = ChroniquesDuZephyrDB.meta.lastModified })
    end
    if ns.Emit then ns.Emit("history:changed") end
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

    -- Diffusion du changement d'état si GM
    if CDZ.IsMaster and CDZ.IsMaster() and CDZ.Comm_Broadcast then
        ChroniquesDuZephyrDB.meta = ChroniquesDuZephyrDB.meta or {}
        local rv = (ChroniquesDuZephyrDB.meta.rev or 0) + 1
        ChroniquesDuZephyrDB.meta.rev = rv
        ChroniquesDuZephyrDB.meta.lastModified = time()
        CDZ.Comm_Broadcast("HIST_UNREFUND", { ts = s.ts, rv = rv, lm = ChroniquesDuZephyrDB.meta.lastModified })
    end
    if ns.Emit then ns.Emit("history:changed") end
    return true
end

function CDZ.DeleteHistory(idx)
    EnsureDB()
    local hist = ChroniquesDuZephyrDB.history or {}
    local s = hist[idx]; if not s then return false end
    local ts = s.ts
    table.remove(hist, idx)

    -- Diffusion de la suppression si GM
    if CDZ.IsMaster and CDZ.IsMaster() and CDZ.Comm_Broadcast then
        ChroniquesDuZephyrDB.meta = ChroniquesDuZephyrDB.meta or {}
        local rv = (ChroniquesDuZephyrDB.meta.rev or 0) + 1
        ChroniquesDuZephyrDB.meta.rev = rv
        ChroniquesDuZephyrDB.meta.lastModified = time()
        CDZ.Comm_Broadcast("HIST_DEL", { ts = ts, rv = rv, lm = ChroniquesDuZephyrDB.meta.lastModified })
    end
    if ns.Emit then ns.Emit("history:changed") end
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
    return lot and (not lot.__pendingConsume) and CDZ.Lot_Status(lot) ~= "EPU"
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
    if ns.RefreshActive then ns.RefreshActive() end -- ✅ disparition immédiate à l’écran

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
        -- Optimistic UI : marquer les lots comme "en attente" pour les masquer immédiatement.
        local L = ChroniquesDuZephyrDB.lots
        for _, id in ipairs(ids) do
            for _, l in ipairs(L.list or {}) do
                if l.id == id then l.__pendingConsume = true end
            end
        end
        if ns.Emit then ns.Emit("lots:changed") end
        if ns.RefreshActive then ns.RefreshActive() end

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
-- ===== Purges (GM)  ======
-- =========================

-- Incrémente / réinitialise la révision selon le rôle
local function _BumpRevisionLocal()
    EnsureDB()
    local isMaster = (CDZ.IsMaster and CDZ.IsMaster()) or false
    local rv = tonumber(ChroniquesDuZephyrDB.meta.rev or 0) or 0
    ChroniquesDuZephyrDB.meta.rev = isMaster and (rv + 1) or 0
    ChroniquesDuZephyrDB.meta.lastModified = time()
end

-- Supprime tous les lots épuisés + tous leurs objets associés
function CDZ.PurgeLotsAndItemsExhausted()
    EnsureDB(); _ensureLots()
    local L = ChroniquesDuZephyrDB.lots
    local E = ChroniquesDuZephyrDB.expenses

    local purgeLots   = {}
    local purgeItems  = {}

    for _, l in ipairs(L.list or {}) do
        if (CDZ.Lot_Status and CDZ.Lot_Status(l) == "EPU") then
            purgeLots[l.id] = true
            for _, eid in ipairs(l.itemIds or {}) do purgeItems[eid] = true end
        end
    end

    -- Filtre des dépenses (objets)
    local newE, removedItems = {}, 0
    for _, it in ipairs(E.list or {}) do
        local id = it.id
        local kill = (purgeItems[id] == true) or (it.lotId and purgeLots[it.lotId])
        if kill then
            removedItems = removedItems + 1
        else
            newE[#newE+1] = it
        end
    end
    E.list = newE

    -- Filtre des lots
    local newL, removedLots = {}, 0
    for _, l in ipairs(L.list or {}) do
        if purgeLots[l.id] then
            removedLots = removedLots + 1
        else
            newL[#newL+1] = l
        end
    end
    L.list = newL

    if ns.Emit then ns.Emit("expenses:changed") end
    if ns.Emit then ns.Emit("lots:changed") end
    if ns.RefreshAll then ns.RefreshAll() end

    _BumpRevisionLocal()
    return removedLots, removedItems
end

-- Supprime absolument tous les lots + tous les objets
function CDZ.PurgeAllResources()
    EnsureDB(); _ensureLots()
    local L = ChroniquesDuZephyrDB.lots
    local E = ChroniquesDuZephyrDB.expenses

    local removedLots  = #(L.list or {})
    local removedItems = #(E.list or {})

    L.list, E.list = {}, {}
    L.nextId, E.nextId = 1, 1

    if ns.Emit then ns.Emit("expenses:changed") end
    if ns.Emit then ns.Emit("lots:changed") end
    if ns.RefreshAll then ns.RefreshAll() end

    _BumpRevisionLocal()
    return removedLots, removedItems
end

-- =========================
-- ===== Window Save  ======
-- =========================

function CDZ.GetSavedWindow() EnsureDB(); return ChroniquesDuZephyrUI end
function CDZ.SaveWindow(point, relTo, relPoint, x, y, w, h)
    ChroniquesDuZephyrUI = ChroniquesDuZephyrUI or {}
    ChroniquesDuZephyrUI.point    = point
    ChroniquesDuZephyrUI.relTo    = relTo
    ChroniquesDuZephyrUI.relPoint = relPoint
    ChroniquesDuZephyrUI.x        = x
    ChroniquesDuZephyrUI.y        = y
    ChroniquesDuZephyrUI.width    = w
    ChroniquesDuZephyrUI.height   = h
end

-- =========================
-- ==== Demandes (GM) ======
-- =========================
function CDZ.GetRequests()
    EnsureDB()
    ChroniquesDuZephyrDB.requests = ChroniquesDuZephyrDB.requests or {}
    return ChroniquesDuZephyrDB.requests
end

-- Expose les demandes pour l’UI (badge/onglet)
function CDZ.GetRequests()
    EnsureDB()
    ChroniquesDuZephyrDB.requests = ChroniquesDuZephyrDB.requests or {}
    return ChroniquesDuZephyrDB.requests
end

