-- ===================================================
-- Core/Core/PlayersManager.lua - Gestionnaire des joueurs
-- ===================================================
-- Responsable de la gestion des joueurs : CRUD, soldes, réserves, ajustements

local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
local GLOG = ns.GLOG

-- Références aux utilitaires centralisées
local U = ns.Util or {}
local safenum = U.safenum

-- Référence à EnsureDB (fournie par DatabaseManager)
local EnsureDB = function()
    if GLOG.EnsureDB then
        GLOG.EnsureDB()
    end
end

-- =========================
-- ======  PLAYERS    ======
-- =========================

-- Shared storage under mainAlt.shared[uid].solde
local function _MA()
    EnsureDB()
    GuildLogisticsDB.mainAlt = GuildLogisticsDB.mainAlt or { version = 2, mains = {}, altToMain = {}, shared = {} }
    local t = GuildLogisticsDB.mainAlt
    t.mains  = t.mains  or {}
    t.altToMain = t.altToMain or {}
    t.shared = t.shared or {}
    return t
end

local function _uidFor(name)
    if not name or name == "" then return nil end
    local full = (ns.Util and ns.Util.NormalizeFull and ns.Util.NormalizeFull(name)) or tostring(name or "")
    return (GLOG.GetOrAssignUID and GLOG.GetOrAssignUID(full)) or nil
end

local function _ensureRosterEntry(name)
    EnsureDB()
    local key = (ns.Util and ns.Util.NormalizeFull and ns.Util.NormalizeFull(name)) or tostring(name or "")
    local p = GuildLogisticsDB.players[key]
    if not p then
        -- Guild-only gate: allow only for guild members or the local player
        local function allow(fullName)
            if not fullName or fullName == "" then return false end
            local me = (ns.Util and ns.Util.playerFullName and ns.Util.playerFullName()) or nil
            if ns.Util and ns.Util.NormalizeFull then
                if me then me = ns.Util.NormalizeFull(me) end
                fullName = ns.Util.NormalizeFull(fullName)
            end
            if me and fullName == me then return true end
            if GLOG and GLOG.IsGuildCharacter and GLOG.IsGuildCharacter(fullName) then return true end
            return false
        end
        if not allow(key) then
            return { reserved = true }
        end
        p = { reserved = true }
        GuildLogisticsDB.players[key] = p
    end
    if p.reserved == nil then p.reserved = true end
    if not p.uid then p.uid = _uidFor(key) end
    return p
end

function GLOG.GetPlayersArray()
    EnsureDB()
    local out = {}
    for name, p in pairs(GuildLogisticsDB.players) do
        local reserved = (p.reserved == true)
        local bal
        do
            local uid = tonumber(p.uid) or _uidFor(name)
            local MA = _MA()
            bal = (uid and MA.shared and MA.shared[uid] and tonumber(MA.shared[uid].solde)) or tonumber(p.solde) or 0
        end
        table.insert(out, { name = name, solde = bal, reserved = reserved })
    end

    table.sort(out, function(a,b) return a.name:lower() < b.name:lower() end)
    return out
end

-- ➕ Sous-ensembles utiles à l'UI (actif / réserve)
function GLOG.GetPlayersArrayActive()
    EnsureDB()
    local out, agg = {}, {}

    -- 1) Déterminer les MAINS "actifs" (au moins un perso non réservé/bench)
    local activeSet = {}  -- [mk] = displayName
    for name, p in pairs(GuildLogisticsDB.players or {}) do
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
    for name, p in pairs(GuildLogisticsDB.players or {}) do
        local main = (GLOG.GetMainOf and GLOG.GetMainOf(name)) or name
        local mk   = (GLOG.NormName and GLOG.NormName(main)) or tostring(main):lower()
        local display = activeSet[mk]
        if display then
            local b = agg[mk]
            if not b then
                b = { name = display, solde = 0, reserved = false }
                agg[mk] = b
            end
            local uid = tonumber(p.uid) or _uidFor(name)
            local MA = _MA()
            local inc = (uid and MA.shared and MA.shared[uid] and tonumber(MA.shared[uid].solde)) or tonumber(p.solde) or 0
            b.solde = (b.solde or 0) + inc
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
    for name, p in pairs(GuildLogisticsDB.players or {}) do
        local main = (GLOG.GetMainOf and GLOG.GetMainOf(name)) or name
        local mk   = (GLOG.NormName and GLOG.NormName(main)) or tostring(main):lower()

        if mk and mk ~= "" and not activeSet[mk] then
            local b = agg[mk]
            if not b then
                local display = (GLOG.ResolveFullName and GLOG.ResolveFullName(main)) or main
                b = { name = display, solde = 0, reserved = true, canPurge = true }
                agg[mk] = b
            end
            local uid = tonumber(p.uid) or _uidFor(name)
            local MA = _MA()
            local inc = (uid and MA.shared and MA.shared[uid] and tonumber(MA.shared[uid].solde)) or tonumber(p.solde) or 0
            b.solde = (b.solde or 0) + inc
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
    
    local key = (ns.Util and ns.Util.NormalizeFull and ns.Util.NormalizeFull(name)) or tostring(name or "")
    local p = GuildLogisticsDB.players[key]
    if p then return true end  -- déjà présent
    
    GuildLogisticsDB.players[key] = { reserved = true }
    
    -- Diffusion
    if GLOG.IsMaster and GLOG.IsMaster() and GLOG.Comm_Broadcast then
        local meta = GuildLogisticsDB.meta or {}
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

-- Fonction simplifiée pour usage local (pas de broadcast)
local function RemovePlayerLocal(name)
    EnsureDB()
    if not name or name == "" then return false end
    
    local key = (ns.Util and ns.Util.NormalizeFull and ns.Util.NormalizeFull(name)) or tostring(name or "")
    if not GuildLogisticsDB.players[key] then return false end
    
    GuildLogisticsDB.players[key] = nil
    
    if ns.RefreshAll then ns.RefreshAll() end
    return true
end

function GLOG.HasPlayer(name)
    EnsureDB()
    if not name or name == "" then return false end
    local key = (ns.Util and ns.Util.NormalizeFull and ns.Util.NormalizeFull(name)) or tostring(name or "")
    return GuildLogisticsDB.players[key] ~= nil
end

function GLOG.IsReserve(name)
    return GLOG.IsReserved(name)
end

function GLOG.Credit(name, amount)
    local uid = _uidFor(name)
    local MA = _MA()
    if uid then
        MA.shared[uid] = MA.shared[uid] or { solde = 0 }
        MA.shared[uid].solde = (tonumber(MA.shared[uid].solde) or 0) + (tonumber(amount) or 0)
    end
    _ensureRosterEntry(name)
    if ns.RefreshAll then ns.RefreshAll() end
end

function GLOG.Debit(name, amount)
    local uid = _uidFor(name)
    local MA = _MA()
    if uid then
        MA.shared[uid] = MA.shared[uid] or { solde = 0 }
        MA.shared[uid].solde = (tonumber(MA.shared[uid].solde) or 0) - (tonumber(amount) or 0)
    end
    _ensureRosterEntry(name)
    if ns.RefreshAll then ns.RefreshAll() end
end

function GLOG.GetSolde(name)
    local uid = _uidFor(name)
    local MA = _MA()
    if uid and MA.shared and MA.shared[uid] then
        return tonumber(MA.shared[uid].solde) or 0
    end
    -- legacy fallback
    local key = (ns.Util and ns.Util.NormalizeFull and ns.Util.NormalizeFull(name)) or tostring(name or "")
    local p = GuildLogisticsDB.players[key]
    return (p and tonumber(p.solde)) or 0
end

function GLOG.SamePlayer(a, b)
    local normA = (ns.Util and ns.Util.NormalizeFull and ns.Util.NormalizeFull(a)) or tostring(a or "")
    local normB = (ns.Util and ns.Util.NormalizeFull and ns.Util.NormalizeFull(b)) or tostring(b or "")
    return normA == normB
end

function GLOG.NormalizePlayerKeys()
    EnsureDB()
    local old = GuildLogisticsDB.players
    GuildLogisticsDB.players = {}
    
    for k, v in pairs(old or {}) do
        local newKey = (ns.Util and ns.Util.NormalizeFull and ns.Util.NormalizeFull(k)) or tostring(k or "")
        if newKey ~= "" then
            -- Fusion si clé existante
            local existing = GuildLogisticsDB.players[newKey]
            if existing then
                local inc = tonumber(v.solde) or 0
                if inc ~= 0 then
                    local uid = tonumber(existing.uid) or _uidFor(newKey)
                    local MA = _MA()
                    if uid then
                        MA.shared[uid] = MA.shared[uid] or { solde = 0 }
                        MA.shared[uid].solde = (tonumber(MA.shared[uid].solde) or 0) + inc
                    end
                end
                if v.reserved == false then existing.reserved = false end
                -- alias: deprecated on per-player records
                if v.uid then existing.uid = v.uid end
            else
                local inc = tonumber(v.solde) or 0
                v.solde = 0
                GuildLogisticsDB.players[newKey] = v
                if inc ~= 0 then
                    local uid = tonumber(v.uid) or _uidFor(newKey)
                    local MA = _MA()
                    if uid then
                        MA.shared[uid] = MA.shared[uid] or { solde = 0 }
                        MA.shared[uid].solde = (tonumber(MA.shared[uid].solde) or 0) + inc
                    end
                end
            end
        end
    end
    
    if ns.RefreshAll then ns.RefreshAll() end
end

function GLOG.AdjustSolde(name, delta)
    local uid = _uidFor(name)
    local MA = _MA()
    if uid then
        MA.shared[uid] = MA.shared[uid] or { solde = 0 }
        MA.shared[uid].solde = (tonumber(MA.shared[uid].solde) or 0) + (tonumber(delta) or 0)
    end
    _ensureRosterEntry(name)
    if ns.RefreshAll then ns.RefreshAll() end
end

function GLOG.GM_AdjustAndBroadcast(name, delta)
    GLOG.AdjustSolde(name, delta)
end

function GLOG.AddGold(name, amount)
    GLOG.Credit(name, amount)
end

function GLOG.RemoveGold(name, amount)
    GLOG.Debit(name, amount)
end

function GLOG.ApplyDeltaByName(name, delta, by)
    EnsureDB()
    local uid = _uidFor(name)
    local MA = _MA()
    if uid then
        MA.shared[uid] = MA.shared[uid] or { solde = 0 }
        MA.shared[uid].solde = (tonumber(MA.shared[uid].solde) or 0) + (tonumber(delta) or 0)
    end
    _ensureRosterEntry(name)
end

function GLOG.ApplyBatch(kv)
    EnsureDB()
    for name, info in pairs(kv or {}) do
        if type(info) == "table" then
            local normName = (ns.Util and ns.Util.NormalizeFull and ns.Util.NormalizeFull(name)) or tostring(name or "")
            if normName ~= "" then
                local p = _ensureRosterEntry(normName)
                if info.solde ~= nil then
                    local uid = _uidFor(normName)
                    local MA = _MA()
                    if uid then
                        MA.shared[uid] = MA.shared[uid] or { solde = 0 }
                        MA.shared[uid].solde = tonumber(info.solde) or 0
                    end
                end
                if info.reserved ~= nil then p.reserved = (info.reserved == true) end
                -- ignore legacy info.alias
                if info.uid ~= nil then p.uid = tonumber(info.uid) end
            end
        elseif type(info) == "number" then
            -- Ancien format : juste le solde
            local normName = (ns.Util and ns.Util.NormalizeFull and ns.Util.NormalizeFull(name)) or tostring(name or "")
            if normName ~= "" then
                local uid = _uidFor(normName)
                local MA = _MA()
                if uid then
                    MA.shared[uid] = MA.shared[uid] or { solde = 0 }
                    MA.shared[uid].solde = tonumber(info) or 0
                end
                _ensureRosterEntry(normName)
            end
        end
    end
    if ns.RefreshAll then ns.RefreshAll() end
end

function GLOG.EnsureRosterLocal(name)
    EnsureDB()
    local full = tostring(name or "")
    -- Guild-only gate
    local function allow(fullName)
        if not fullName or fullName == "" then return false end
        local me = (ns.Util and ns.Util.playerFullName and ns.Util.playerFullName()) or nil
        if ns.Util and ns.Util.NormalizeFull then
            if me then me = ns.Util.NormalizeFull(me) end
            fullName = ns.Util.NormalizeFull(fullName)
        end
        if me and fullName == me then return true end
        if GLOG and GLOG.IsGuildCharacter and GLOG.IsGuildCharacter(fullName) then return true end
        return false
    end
    if not GuildLogisticsDB.players[full] then
        if not allow(full) then return nil end
        GuildLogisticsDB.players[full] = { solde=0, reserved=true }
    end
    if GuildLogisticsDB.players[full].reserved == nil then 
        GuildLogisticsDB.players[full].reserved = true 
    end
    return GuildLogisticsDB.players[full]
end

function GLOG.RemovePlayerLocal(name, silent)
    EnsureDB()
    local full = tostring(name or "")
    if not GuildLogisticsDB.players[full] then return false end
    
    GuildLogisticsDB.players[full] = nil
    if not silent then
        if ns.RefreshAll then ns.RefreshAll() end
    end
    return true
end
function GLOG.RemovePlayer(name)
    EnsureDB()
    if not name or name == "" then return false end
    
    local full = (ns.Util and ns.Util.NormalizeFull and ns.Util.NormalizeFull(name)) or tostring(name or "")
    if not GuildLogisticsDB.players[full] then return false end
    
    GuildLogisticsDB.players[full] = nil
    
    -- Diffusion GM
    if GLOG.IsMaster and GLOG.IsMaster() and GLOG.Comm_Broadcast then
        local meta = GuildLogisticsDB.meta or {}
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

function GLOG.IsReserved(name)
    EnsureDB()
    local full = tostring(name or "")
    local p = GuildLogisticsDB.players[full]
    return p and (p.reserved == true)
end

function GLOG.GM_SetReserved(name, flag)
    EnsureDB()
    local full = tostring(name or "")
    local p = GuildLogisticsDB.players[full]
    if not p then return false end
    
    p.reserved = (flag == true)
    local alias = ""
    if GLOG.GetAliasFor then
        alias = tostring(GLOG.GetAliasFor(full) or "")
    end
    
    -- Diffusion GM
    if GLOG.IsMaster and GLOG.IsMaster() and GLOG.Comm_Broadcast then
        local meta = GuildLogisticsDB.meta or {}
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
