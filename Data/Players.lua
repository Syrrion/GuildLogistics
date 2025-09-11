local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
ns.Util = ns.Util or {}
local GLOG, U = ns.GLOG, ns.Util

-- Initialise et renvoie la DB globale (GuildLogisticsDB) avec champs meta/players/uidSeq.
local function EnsureDB()
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.meta    = GuildLogisticsDB.meta    or {}
    GuildLogisticsDB.players = GuildLogisticsDB.players or {}
    GuildLogisticsDB.meta.uidSeq = GuildLogisticsDB.meta.uidSeq or 1
    return GuildLogisticsDB
end

-- Expose le point d'accès DB central (sans wrapper supplémentaire ailleurs).
GLOG.EnsureDB = GLOG.EnsureDB or EnsureDB

-- Scanne la DB pour retrouver le "Nom-Royaume" correspondant à un UID numérique.
function U.GetNameByUID(uid)
    local db = EnsureDB()
    local n = tonumber(uid)
    if not n then return nil end
    for full, rec in pairs(db.players or {}) do
        if tonumber(rec and rec.uid) == n then
            return full
        end
    end
    return nil
end

-- Retourne l'UID numérique si présent pour 'name' (normalisé en Nom-Royaume), sinon nil.
function U.FindUIDByName(name)
    local db   = EnsureDB()
    local full = U.NormalizeFull(name) or tostring(name or "")
    local p = db.players[full]
    return p and p.uid or nil
end

-- Force l'association UID <-> joueur 'name' (création d'entrée si nécessaire).
function U.MapUID(uid, name)
    local db   = EnsureDB()
    local full = U.NormalizeFull(name) or tostring(name or "")
    local nuid = tonumber(uid)
    if not nuid then return nil end

    -- Guild-only gate: only persist for guild members or the local player
    local function allow(fullName)
        if not fullName or fullName == "" then return false end
        local me = (U.playerFullName and U.playerFullName()) or nil
        local nf = ns and ns.Util and ns.Util.NormalizeFull
        if nf then
            if me then me = nf(me) end
            fullName = nf(fullName)
        end
        if me and fullName == me then return true end
        if GLOG and GLOG.IsGuildCharacter and GLOG.IsGuildCharacter(fullName) then return true end
        return false
    end

    -- If record exists already, allow updating UID; otherwise, gate creation
    if db.players[full] or allow(full) then
        db.players[full] = db.players[full] or { solde = 0, reserved = true }
        db.players[full].uid = nuid
        return nuid
    end
    return nil
end

-- Supprime l'UID sur l'entrée joueur possédant 'uid' (si trouvée).
function U.UnmapUID(uid)
    local db = EnsureDB()
    local n  = tonumber(uid)
    if not n then return end
    for full, rec in pairs(db.players or {}) do
        if tonumber(rec and rec.uid) == n then
            rec.uid = nil
            return
        end
    end
end

-- Renvoie l'UID existant pour 'name' ou alloue le prochain identifiant séquentiel.
function U.GetOrAssignUID(name)
    local db   = EnsureDB()
    local full = U.NormalizeFull(name) or tostring(name or "")

    -- Guild-only gate: do not create entries for non-guild names
    local function allow(fullName)
        if not fullName or fullName == "" then return false end
        local me = (U.playerFullName and U.playerFullName()) or nil
        local nf = ns and ns.Util and ns.Util.NormalizeFull
        if nf then
            if me then me = nf(me) end
            fullName = nf(fullName)
        end
        if me and fullName == me then return true end
        if GLOG and GLOG.IsGuildCharacter and GLOG.IsGuildCharacter(fullName) then return true end
        return false
    end

    local rec = db.players[full]
    if not rec then
        if not allow(full) then return nil end
        rec = { solde = 0, reserved = true }
        db.players[full] = rec
    end
    if rec.uid then return rec.uid end
    local nextId = tonumber(db.meta.uidSeq or 1) or 1
    rec.uid = nextId
    db.meta.uidSeq = nextId + 1
    return rec.uid
end

-- Garantit l'existence d'une entrée locale joueur et la retourner
function U.EnsureRosterLocal(name)
    local db   = EnsureDB()
    local full = U.NormalizeFull(name) or tostring(name or "")

    -- Guild-only gate
    local function allow(fullName)
        if not fullName or fullName == "" then return false end
        local me = (U.playerFullName and U.playerFullName()) or nil
        local nf = ns and ns.Util and ns.Util.NormalizeFull
        if nf then
            if me then me = nf(me) end
            fullName = nf(fullName)
        end
        if me and fullName == me then return true end
        if GLOG and GLOG.IsGuildCharacter and GLOG.IsGuildCharacter(fullName) then return true end
        return false
    end

    if not db.players[full] then
        if not allow(full) then return nil end
        db.players[full] = { solde = 0, reserved = true }
    end
    if db.players[full].reserved == nil then db.players[full].reserved = true end
    return db.players[full]
end
