-- ===================================================
-- Core/Player/Manager.lua - Gestionnaire des joueurs
-- ===================================================
-- Responsable de la gestion des joueurs : CRUD, soldes, réserves, ajustements

local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
local GLOG = ns.GLOG

-- Références aux utilitaires centralisées
local U = ns.Util or {}
local safenum = U.safenum

-- Référence à EnsureDB (fournie par DatabaseManager)
local function EnsureDB()
    if GLOG.EnsureDB then
        GLOG.EnsureDB()
    end
end

-- Fonction utilitaire pour obtenir la DB de façon sûre
local function GetDB()
    EnsureDB()
    return GuildLogisticsDB or {}
end

-- =========================
-- ======  PLAYERS    ======
-- =========================

local function _MA()
    EnsureDB()
    GuildLogisticsDB.account = GuildLogisticsDB.account or { mains = {}, altToMain = {} }
    local t = GuildLogisticsDB.account
    t.mains  = t.mains  or {}
    t.altToMain = t.altToMain or {}
    return t
end

local function _uidFor(name)
    if not name or name == "" then return nil end
    -- Utiliser le vrai royaume si possible (roster/units), sinon fallback NormalizeFull
    local full = (GLOG.ResolveFullNameStrict and GLOG.ResolveFullNameStrict(name))
              or (GLOG.ResolveFullName and GLOG.ResolveFullName(name))
              or (ns.Util and ns.Util.NormalizeFull and ns.Util.NormalizeFull(name))
              or tostring(name or "")
    return (GLOG.GetOrAssignUID and GLOG.GetOrAssignUID(full)) or nil
end

-- Canonicalise un nom pour l'index DB: vrai royaume si connu, sinon fallback
local function _canonicalFull(name)
    local s = tostring(name or "")
    if s == "" then return s end
    if s:find("%-") then
        return (ns.Util and ns.Util.CleanFullName and ns.Util.CleanFullName(s)) or s
    end
    local strict = (GLOG.ResolveFullNameStrict and GLOG.ResolveFullNameStrict(s)) or nil
    if strict and strict ~= "" then return strict end
    local res = (GLOG.ResolveFullName and GLOG.ResolveFullName(s)) or nil
    if res and res ~= "" then return res end
    return (ns.Util and ns.Util.NormalizeFull and ns.Util.NormalizeFull(s)) or s
end

local function _mainUIDForName(name)
    local uid = _uidFor(name)
    if not uid then return nil end
    local MA = _MA()
    local mu = tonumber(MA.altToMain[uid])
    return mu or tonumber(uid)
end

local function _ensureRosterEntry(name)
    local db = GetDB()
    local key = _canonicalFull(name)
    db.players = db.players or {}
    -- Fusionner une éventuelle ancienne entrée basée sur un mauvais royaume local
    do
        local wrong = (ns.Util and ns.Util.NormalizeFull and ns.Util.NormalizeFull(name)) or tostring(name or "")
        if wrong ~= key and db.players[wrong] and not db.players[key] then
            db.players[key] = db.players[wrong]
            db.players[wrong] = nil
        end
    end
    db.players[key] = db.players[key] or {}
    if not db.players[key].uid then db.players[key].uid = _uidFor(key) end
    return db.players[key]
end

-- New unified balance accessors (UID-based)
local function _getBalanceByName(name)
    if not name or name == "" then return 0 end
    local uid = _uidFor(name)
    local MA = _MA()
    local mu = uid and (tonumber(MA.altToMain[uid]) or uid) or nil
    if mu and MA.mains and MA.mains[mu] and MA.mains[mu].solde ~= nil then
        return tonumber(MA.mains[mu].solde) or 0
    end
    -- No legacy fallback: authoritative value lives in account.mains
    return 0
end

local function _adjustBalanceByName(name, delta)
    if not name or name == "" then return end
    local uid = _uidFor(name)
    local MA = _MA()
    if uid then
        local mu = tonumber(MA.altToMain[uid]) or uid
        MA.mains[mu] = MA.mains[mu] or {}
        MA.mains[mu].solde = (tonumber(MA.mains[mu].solde) or 0) + (tonumber(delta) or 0)
    end
    -- Keep roster presence and legacy field in sync for UI/compat
    local p = _ensureRosterEntry(name)
    if p.solde ~= nil then p.solde = nil end -- authoritative value now lives in account.mains
end

function GLOG.GetPlayersArray()
    local db = GetDB()
    if not db.players then return {} end
    local out = {}
    for name, p in pairs(db.players) do
        local reserved
        do
            local mu = _mainUIDForName(name)
            local MA = _MA()
            -- New semantics: only store false explicitly; nil means reserved
            if mu and MA.mains[mu] and MA.mains[mu].reserve == false then
                reserved = false
            else
                reserved = not (p.reserved == false)
            end
        end
        table.insert(out, {
            name     = name,
            solde    = _getBalanceByName(name),
            reserved = reserved,
        })
    end

    table.sort(out, function(a,b) return a.name:lower() < b.name:lower() end)
    return out
end

-- Sous-ensembles utiles à l'UI (actif / réserve)
function GLOG.GetPlayersArrayActive()
    EnsureDB()
    local out, agg = {}, {}

    -- 1) Déterminer les MAINS "actifs" (au moins un perso non réservé/bench)
    local activeSet = {}  -- [mk] = displayName
    for name, p in pairs(GetDB().players or {}) do
        local isRes = (GLOG.IsReserved and GLOG.IsReserved(name)) or false
        if not isRes then
            local main = (GLOG.GetMainOf and GLOG.GetMainOf(name)) or name
            local mk   = (GLOG.NormName and GLOG.NormName(main)) or tostring(main):lower()
            if mk and mk ~= "" then
                local display = (GLOG.ResolveFullName and GLOG.ResolveFullName(main)) or main
                activeSet[mk] = display
            end
        end
    end

    -- 2) Agréger les crédits/débits de TOUS les persos appartenant à ces mains actifs
    local seenMain = {}
    for name, p in pairs(GetDB().players or {}) do
        local main = (GLOG.GetMainOf and GLOG.GetMainOf(name)) or name
        local mk   = (GLOG.NormName and GLOG.NormName(main)) or tostring(main):lower()
        local display = activeSet[mk]
        if display then
            local mu = _mainUIDForName(name)
            if mu and not seenMain[mu] then
                local b = agg[mk]
                if not b then
                    b = { name = display, solde = 0, reserved = false }
                    agg[mk] = b
                end
                b.solde = _getBalanceByName(name)
                seenMain[mu] = true
            end
        end
    end

    -- 3) Normaliser la sortie
    for _, v in pairs(agg) do
        v.solde = tonumber(v.solde) or 0
        out[#out+1] = v
    end

    table.sort(out, function(a, b) return (a.name or ""):lower() < (b.name or ""):lower() end)
    return out
end

-- opts (optionnel) :
--    { showHidden = boolean, cutoffDays = number }
--    - showHidden = true  -> conserve tout (comportement historique)
--    - showHidden = false -> masque inactifs >= cutoffDays ET solde == 0
function GLOG.GetPlayersArrayReserve(opts)
    EnsureDB()
    local out, agg = {}, {}

    -- Ensemble des MAINS déjà ACTIFS (au moins un perso non réservé)
    local activeSet = {}
    do
        local arr = (GLOG.GetPlayersArrayActive and GLOG.GetPlayersArrayActive()) or {}
        for _, r in ipairs(arr) do
            local main = (GLOG.GetMainOf and GLOG.GetMainOf(r.name)) or r.name
            local mk   = (GLOG.NormName and GLOG.NormName(main)) or tostring(main):lower()
            if mk and mk ~= "" then activeSet[mk] = true end
        end
    end

    -- Regroupe par main (clé normalisée), ignore ceux déjà actifs
    local seenMain = {}
    for name, p in pairs(GetDB().players or {}) do
        local main = (GLOG.GetMainOf and GLOG.GetMainOf(name)) or name
        local mk   = (GLOG.NormName and GLOG.NormName(main)) or tostring(main):lower()

        if mk and mk ~= "" and not activeSet[mk] then
            local mu = _mainUIDForName(name)
            if mu and not seenMain[mu] then
                local b = agg[mk]
                if not b then
                    local display = (GLOG.ResolveFullName and GLOG.ResolveFullName(main)) or main
                    b = { name = display, solde = 0, reserved = true, canPurge = true }
                    agg[mk] = b
                end
                b.solde = _getBalanceByName(name)
                seenMain[mu] = true
            end
        end
    end

    -- Filtrage si opts.showHidden = false
    local showHidden = (opts and opts.showHidden) or true
    local cutoffDays = (opts and tonumber(opts.cutoffDays)) or 90

    for _, v in pairs(agg) do
        v.solde = tonumber(v.solde) or 0
        local shouldShow = showHidden

        if not showHidden then
            -- Masquer si : balance nulle ET inactif >= cutoffDays
            local bal = tonumber(v.solde) or 0
            if bal == 0 then
                local isOldInactive = true  -- logique simplifiée ici
                if GLOG.GetGuildRowsCached then
                    -- Vérifier l'activité récente
                    local rows = GLOG.GetGuildRowsCached()
                    for _, row in ipairs(rows or {}) do
                        if row.name and (GLOG.SamePlayer and GLOG.SamePlayer(row.name, v.name)) then
                            local days = tonumber(row.daysDerived) or 9999
                            if days < cutoffDays then
                                isOldInactive = false
                                break
                            end
                        end
                    end
                end
                shouldShow = not isOldInactive
            end
        end

        if shouldShow then
            out[#out+1] = v
        end
    end

    table.sort(out, function(a, b) return (a.name or ""):lower() < (b.name or ""):lower() end)
    return out
end

function GLOG.AddPlayer(name)
    EnsureDB()
    if not name or name == "" then return false end
    
    local key = _canonicalFull(name)
    local p = GetDB().players[key]
    if p then return true end  -- déjà présent
    -- Fusionner une éventuelle ancienne entrée sous mauvais royaume
    do
        local wrong = (ns.Util and ns.Util.NormalizeFull and ns.Util.NormalizeFull(name)) or tostring(name or "")
        if wrong ~= key and GetDB().players[wrong] then
            GetDB().players[key] = GetDB().players[wrong]
            GetDB().players[wrong] = nil
        end
    end
    GetDB().players[key] = GetDB().players[key] or {}
    -- Ensure main-level record exists
    do
        local mu = _mainUIDForName(key)
        if mu then
            local MA = _MA()
            MA.mains[mu] = MA.mains[mu] or {}
        end
    end
    
    -- Diffusion
    if GLOG.IsMaster and GLOG.IsMaster() and GLOG.Comm_Broadcast then
        local meta = GetDB().meta or {}
        local rv = (meta.rev or 0) + 1
        meta.rev = rv
        meta.lastModified = time()
        
        GLOG.Comm_Broadcast("ROSTER_UPSERT", {
            name = key, balance = 0, reserved = true,
            rv = rv, lm = meta.lastModified
        })
    end
    
    if ns.RefreshAll then ns.RefreshAll() end
    return true
end

function GLOG.RemovePlayer(name)
    EnsureDB()
    if not name or name == "" then return false end
    
    local full = _canonicalFull(name)
    if not GetDB().players[full] then return false end
    
    -- Clear main-level reserve flag for this main
    do
        local mu = _mainUIDForName(full)
        if mu then
            local MA = _MA()
            if MA.mains and MA.mains[mu] then
                MA.mains[mu].reserve = nil
            end
        end
    end
    GetDB().players[full] = nil
    
    -- Diffusion GM
    if GLOG.IsMaster and GLOG.IsMaster() and GLOG.Comm_Broadcast then
        local meta = GetDB().meta or {}
        local rv = (meta.rev or 0) + 1
        meta.rev = rv
        meta.lastModified = time()
        
        GLOG.Comm_Broadcast("ROSTER_DELETE", {
            name = full,
            rv = rv, lm = meta.lastModified
        })
    end
    
    if ns.RefreshAll then ns.RefreshAll() end
    return true
end

function GLOG.HasPlayer(name)
    EnsureDB()
    if not name or name == "" then return false end
    local key = _canonicalFull(name)
    return GetDB().players[key] ~= nil
end

function GLOG.IsReserve(name)
    return GLOG.IsReserved(name)
end

function GLOG.Credit(name, amount)
    _adjustBalanceByName(name, tonumber(amount) or 0)
    if ns.RefreshAll then ns.RefreshAll() end
end

function GLOG.Debit(name, amount)
    _adjustBalanceByName(name, - (tonumber(amount) or 0))
    if ns.RefreshAll then ns.RefreshAll() end
end

function GLOG.GetSolde(name)
    return _getBalanceByName(name)
end

-- Helpers by UID (public)
function GLOG.GetSoldeByUID(uid)
    uid = tonumber(uid)
    if not uid or uid <= 0 then return 0 end
    local MA = _MA()
    local mu = uid and (tonumber(MA.altToMain[uid]) or uid) or nil
    if mu and MA.mains and MA.mains[mu] then
        return tonumber(MA.mains[mu].solde) or 0
    end
    return 0
end

function GLOG.SetSoldeByUID(uid, value)
    uid = tonumber(uid)
    if not uid or uid <= 0 then return end
    local MA = _MA()
    local mu = tonumber(MA.altToMain[uid]) or uid
    MA.mains[mu] = MA.mains[mu] or {}
    MA.mains[mu].solde = tonumber(value) or 0
end

-- Swap the entire main-level payload between two UIDs (solde, addonVersion, etc.)
-- This is used when promoting an alt to main so that all aggregated data
-- follows the "bank" identity. O(1) swap of table references.
function GLOG.SwapSharedBetweenUIDs(uidA, uidB)
    uidA = tonumber(uidA); uidB = tonumber(uidB)
    if not uidA or not uidB or uidA == uidB then return false end
    local MA = _MA()
    local muA = tonumber(MA.altToMain[uidA]) or uidA
    local muB = tonumber(MA.altToMain[uidB]) or uidB
    local a = MA.mains[muA]
    local b = MA.mains[muB]
    MA.mains[muA], MA.mains[muB] = b, a
    return true
end

function GLOG.SamePlayer(a, b)
    local normA = (ns.Util and ns.Util.NormalizeFull and ns.Util.NormalizeFull(a)) or tostring(a or "")
    local normB = (ns.Util and ns.Util.NormalizeFull and ns.Util.NormalizeFull(b)) or tostring(b or "")
    return normA == normB
end

function GLOG.NormalizePlayerKeys()
    local db = GetDB()
    if not db.players then return end
    
    local old = db.players
    db.players = {}
    
    for k, v in pairs(old or {}) do
        local newKey = (ns.Util and ns.Util.NormalizeFull and ns.Util.NormalizeFull(k)) or tostring(k or "")
        if newKey ~= "" then
            -- Fusion si clé existante
            local existing = db.players[newKey]
            if existing then
                -- Merge legacy balances into shared by target key's UID
                local inc = tonumber(v.solde) or 0
                if inc ~= 0 then _adjustBalanceByName(newKey, inc) end
                if v.reserved == false then existing.reserved = false end
                -- alias is no longer stored on per-player records
                if v.uid then existing.uid = v.uid end
            else
                -- Drop legacy balance into shared under this key's UID
                local inc = tonumber(v.solde) or 0
                v.solde = nil
                db.players[newKey] = v
                if inc ~= 0 then _adjustBalanceByName(newKey, inc) end
            end
        end
    end
    
    if ns.RefreshAll then ns.RefreshAll() end
end

function GLOG.AdjustSolde(name, delta)
    _adjustBalanceByName(name, tonumber(delta) or 0)
    
    -- Mise à jour des métadonnées pour le GM
    if GLOG.IsMaster and GLOG.IsMaster() then
        GuildLogisticsDB = GuildLogisticsDB or {}
        GuildLogisticsDB.meta = GuildLogisticsDB.meta or {}
        local meta = GuildLogisticsDB.meta
        meta.rev = (meta.rev or 0) + 1
        local U = ns.Util or {}
        local now = U.now or function() return time() end
        meta.lastModified = now()
    end
    
    if ns.RefreshAll then ns.RefreshAll() end
end

function GLOG.GM_AdjustAndBroadcast(name, delta)
    -- Délègue au pipeline TX_APPLIED moderne pour garantir l'application locale + diffusion
    if GLOG.GM_ApplyAndBroadcast then
        return GLOG.GM_ApplyAndBroadcast(name, delta)
    elseif GLOG.GM_ApplyAndBroadcastEx then
        return GLOG.GM_ApplyAndBroadcastEx(name, delta, {})
    elseif GLOG.GM_ApplyAndBroadcastByUID and GLOG.GetOrAssignUID then
        local uid = GLOG.GetOrAssignUID(name)
        if uid then return GLOG.GM_ApplyAndBroadcastByUID(uid, delta, {}) end
    end
end

function GLOG.AddGold(name, amount)
    GLOG.Credit(name, amount)
end

function GLOG.RemoveGold(name, amount)
    GLOG.Debit(name, amount)
end

function GLOG.ApplyDeltaByName(name, delta, by)
    _adjustBalanceByName(name, tonumber(delta) or 0)
end

function GLOG.ApplyBatch(kv)
    EnsureDB()
    for name, info in pairs(kv or {}) do
        if type(info) == "table" then
            local normName = _canonicalFull(name)
            if normName ~= "" then
                local p = _ensureRosterEntry(normName)
                if info.solde ~= nil then
                    -- Explicit set of balance: set main UID solde directly
                    local uid = _uidFor(normName)
                    local MA = _MA()
                    if uid then
                        local mu = tonumber(MA.altToMain[uid]) or uid
                        MA.mains[mu] = MA.mains[mu] or {}
                        MA.mains[mu].solde = tonumber(info.solde) or 0
                    end
                end
                if info.reserved ~= nil then
                    -- New semantics: only store explicit false
                    local isFalse = (info.reserved == false)
                    p.reserved = isFalse and false or nil
                    local mu = _mainUIDForName(normName)
                    if mu then
                        local MA = _MA()
                        MA.mains[mu] = MA.mains[mu] or {}
                        MA.mains[mu].reserve = isFalse and false or nil
                    end
                end
                -- ignore legacy info.alias to keep players clean
                if info.uid ~= nil then p.uid = tonumber(info.uid) end
            end
        elseif type(info) == "number" then
            -- Ancien format : juste le solde
            local normName = _canonicalFull(name)
            if normName ~= "" then
                local uid = _uidFor(normName)
                local MA = _MA()
                if uid then
                    local mu = tonumber(MA.altToMain[uid]) or uid
                    MA.mains[mu] = MA.mains[mu] or {}
                    MA.mains[mu].solde = tonumber(info) or 0
                end
                _ensureRosterEntry(normName)
            end
        end
    end
    if ns.RefreshAll then ns.RefreshAll() end
end

function GLOG.EnsureRosterLocal(name)
    local db = GetDB()
    if not db.players then db.players = {} end
    local full = _canonicalFull(name)
    db.players[full] = db.players[full] or {}
    return db.players[full]
end

function GLOG.RemovePlayerLocal(name, silent)
    local db = GetDB()
    if not db.players then return false end
    local full = _canonicalFull(name)
    if not GetDB().players[full] then return false end
    
    -- Clear main-level reserve flag for this main
    do
        local mu = _mainUIDForName(full)
        if mu then
            local MA = _MA()
            if MA.mains and MA.mains[mu] then
                MA.mains[mu].reserve = nil
            end
        end
    end
    GetDB().players[full] = nil
    if not silent then
        if ns.RefreshAll then ns.RefreshAll() end
    end
    return true
end

function GLOG.IsReserved(name)
    EnsureDB()
    local full = _canonicalFull(name)
    -- Authoritative: account.mains[mainUID].reserve stores only false; nil means reserved
    local mu = _mainUIDForName(full)
    if mu then
        local MA = _MA()
        if MA.mains[mu] and MA.mains[mu].reserve == false then
            return false
        end
    end
    -- Legacy/per-char mirror: only false stored; nil means reserved
    local p = GetDB().players[full]
    if p and p.reserved == false then return false end
    return true
end

function GLOG.GM_SetReserved(name, flag)
    EnsureDB()
    local full = _canonicalFull(name)
    local p = GetDB().players[full]
    if not p then return false end

    -- Set main-level reserve flag in mains using new semantics
    do
        local mu = _mainUIDForName(full)
        if mu then
            local MA = _MA()
            MA.mains[mu] = MA.mains[mu] or {}
            if flag == false then
                MA.mains[mu].reserve = false
            else
                MA.mains[mu].reserve = nil -- implicit reserved
            end
        end
    end
    -- Keep legacy/per-char mirror: only store false explicitly; reserved (true) is nil
    p.reserved = (flag == false) and false or nil
    local alias = ""
    if GLOG.GetAliasFor then
        alias = tostring(GLOG.GetAliasFor(full) or "")
    end
    
    -- Diffusion GM
    if GLOG.IsMaster and GLOG.IsMaster() and GLOG.Comm_Broadcast then
        local meta = GetDB().meta or {}
        local rv = (meta.rev or 0) + 1
        meta.rev = rv
        meta.lastModified = time()
        
        local uid = tonumber(p.uid)
        GLOG.Comm_Broadcast("ROSTER_RESERVE", {
            uid = uid, name = full, res = flag and 1 or 0,
            alias = alias,
            rv = rv, lm = meta.lastModified
        })
    end
    
    if ns.RefreshAll then ns.RefreshAll() end
    return true
end
