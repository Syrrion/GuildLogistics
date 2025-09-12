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

local function GetOrCreatePlayer(name)
    local db = GetDB()
    if not name or name == "" then return { solde=0, reserved=true } end
    local key = (ns.Util and ns.Util.NormalizeFull and ns.Util.NormalizeFull(name)) or tostring(name or "")
    if not db.players then db.players = {} end
    local p = db.players[key]
    if not p then
        -- Création implicite = en "Réserve" par défaut
        p = { solde = 0, reserved = true }
        db.players[key] = p
    else
        if p.reserved == nil then p.reserved = true end
    end
    return p
end

function GLOG.GetPlayersArray()
    local db = GetDB()
    if not db.players then return {} end
    local out = {}
    for name, p in pairs(db.players) do
        local reserved = (p.reserved == true)
        table.insert(out, {
            name     = name,
            solde    = tonumber(p.solde) or 0,
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
    for name, p in pairs(GetDB().players or {}) do
        local main = (GLOG.GetMainOf and GLOG.GetMainOf(name)) or name
        local mk   = (GLOG.NormName and GLOG.NormName(main)) or tostring(main):lower()
        local display = activeSet[mk]
        if display then
            local b = agg[mk]
            if not b then
                b = { name = display, solde = 0, reserved = false }
                agg[mk] = b
            end
            b.solde = (b.solde or 0) + (tonumber(p.solde) or 0)
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
    for name, p in pairs(GetDB().players or {}) do
        local main = (GLOG.GetMainOf and GLOG.GetMainOf(name)) or name
        local mk   = (GLOG.NormName and GLOG.NormName(main)) or tostring(main):lower()

        if mk and mk ~= "" and not activeSet[mk] then
            local b = agg[mk]
            if not b then
                local display = (GLOG.ResolveFullName and GLOG.ResolveFullName(main)) or main
                b = { name = display, solde = 0, reserved = true, canPurge = true }
                agg[mk] = b
            end
            b.solde = (b.solde or 0) + (tonumber(p.solde) or 0)
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
    local p = GetDB().players[key]
    if p then return true end  -- déjà présent
    
    GetDB().players[key] = { solde = 0, reserved = true }
    
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
    
    local full = (ns.Util and ns.Util.NormalizeFull and ns.Util.NormalizeFull(name)) or tostring(name or "")
    if not GetDB().players[full] then return false end
    
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
    local key = (ns.Util and ns.Util.NormalizeFull and ns.Util.NormalizeFull(name)) or tostring(name or "")
    return GetDB().players[key] ~= nil
end

function GLOG.IsReserve(name)
    return GLOG.IsReserved(name)
end

function GLOG.Credit(name, amount)
    local p = GetOrCreatePlayer(name)
    p.solde = (tonumber(p.solde) or 0) + (tonumber(amount) or 0)
    if ns.RefreshAll then ns.RefreshAll() end
end

function GLOG.Debit(name, amount)
    local p = GetOrCreatePlayer(name)
    p.solde = (tonumber(p.solde) or 0) - (tonumber(amount) or 0)
    if ns.RefreshAll then ns.RefreshAll() end
end

function GLOG.GetSolde(name)
    local p = GetOrCreatePlayer(name)
    return tonumber(p.solde) or 0
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
                existing.solde = (tonumber(existing.solde) or 0) + (tonumber(v.solde) or 0)
                if v.reserved == false then existing.reserved = false end
                -- alias is no longer stored on per-player records
                if v.uid then existing.uid = v.uid end
            else
                db.players[newKey] = v
            end
        end
    end
    
    if ns.RefreshAll then ns.RefreshAll() end
end

function GLOG.AdjustSolde(name, delta)
    local p = GetOrCreatePlayer(name)
    p.solde = (tonumber(p.solde) or 0) + (tonumber(delta) or 0)
    
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
    local p = GetOrCreatePlayer(name)
    p.solde = (tonumber(p.solde) or 0) + (tonumber(delta) or 0)
end

function GLOG.ApplyBatch(kv)
    EnsureDB()
    for name, info in pairs(kv or {}) do
        if type(info) == "table" then
            local normName = (ns.Util and ns.Util.NormalizeFull and ns.Util.NormalizeFull(name)) or tostring(name or "")
            if normName ~= "" then
                local p = GetOrCreatePlayer(normName)
                
                if info.solde ~= nil then p.solde = tonumber(info.solde) or 0 end
                if info.reserved ~= nil then p.reserved = (info.reserved == true) end
                -- ignore legacy info.alias to keep players clean
                if info.uid ~= nil then p.uid = tonumber(info.uid) end
            end
        elseif type(info) == "number" then
            -- Ancien format : juste le solde
            local normName = (ns.Util and ns.Util.NormalizeFull and ns.Util.NormalizeFull(name)) or tostring(name or "")
            if normName ~= "" then
                local p = GetOrCreatePlayer(normName)
                p.solde = tonumber(info) or 0
            end
        end
    end
    if ns.RefreshAll then ns.RefreshAll() end
end

function GLOG.EnsureRosterLocal(name)
    local db = GetDB()
    if not db.players then db.players = {} end
    local full = tostring(name or "")
    db.players[full] = db.players[full] or { solde=0, reserved=true }
    if db.players[full].reserved == nil then 
        db.players[full].reserved = true 
    end
    return db.players[full]
end

function GLOG.RemovePlayerLocal(name, silent)
    local db = GetDB()
    if not db.players then return false end
    local full = tostring(name or "")
    if not GetDB().players[full] then return false end
    
    GetDB().players[full] = nil
    if not silent then
        if ns.RefreshAll then ns.RefreshAll() end
    end
    return true
end

function GLOG.IsReserved(name)
    EnsureDB()
    local full = tostring(name or "")
    local p = GetDB().players[full]
    return p and (p.reserved == true)
end

function GLOG.GM_SetReserved(name, flag)
    EnsureDB()
    local full = tostring(name or "")
    local p = GetDB().players[full]
    if not p then return false end
    
    p.reserved = (flag == true)
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
