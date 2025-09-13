local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
ns.Util = ns.Util or {}
local GLOG, U = ns.GLOG, ns.Util

-- Initialise et renvoie la DB globale (GuildLogisticsDB) avec champs meta/players.
local function EnsureDB()
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.meta    = GuildLogisticsDB.meta    or {}
    GuildLogisticsDB.players = GuildLogisticsDB.players or {}
    return GuildLogisticsDB
end

-- Expose le point d'accès DB central (sans wrapper supplémentaire ailleurs).
GLOG.EnsureDB = GLOG.EnsureDB or EnsureDB

-- ShortId helper (base62, 4 chars) – fourni par DatabaseManager; fallback local si besoin
local function _ShortId(name)
    if GLOG.ShortId then return GLOG.ShortId(name) end
    -- Fallback minimal (base62) si helper indisponible temporairement
    local s = (ns and ns.Util and ns.Util.NormalizeFull and ns.Util.NormalizeFull(name)) or tostring(name or "")
    local h = 5381
    -- Utilise la lib bit (WoW) si disponible, sinon approximation arithmétique
    local bitlib = bit -- WoW provides 'bit' in 5.1; no bit32 in this environment
    local MASK = 536870911 -- 0x1fffffff
    for i=1,#s do
        local c = string.byte(s, i)
        if bitlib and bitlib.bxor and bitlib.band then
            h = bitlib.band(bitlib.bxor(h * 33, c), MASK)
        else
            -- Fallback sans bits: mélange simple et modulo MASK
            h = ((h * 33) + c) % MASK
        end
    end
    local chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
    local function toBase(n)
        if n == 0 then return chars:sub(1,1) end
        local t = {}
        local b = #chars
        while n > 0 do local r = (n % b) + 1; t[#t+1] = chars:sub(r,r); n = math.floor(n / b) end
        local out = table.concat(t):reverse()
        if #out < 4 then out = chars:sub(1,1):rep(4-#out)..out end
        return out
    end
    return toBase(h)
end

-- Scanne la DB pour retrouver le "Nom-Royaume" correspondant à un UID (ShortId string).
function U.GetNameByUID(uid)
    local db = EnsureDB()
    local id = tostring(uid or "")
    if id == "" then return nil end
    for full, rec in pairs(db.players or {}) do
        if rec and rec.uid == id then
            return full
        end
    end
    return nil
end

-- Retourne l'UID (ShortId) si présent pour 'name' (normalisé), sinon nil.
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
    local sid  = tostring(uid or "")
    if sid == "" then return nil end

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
        db.players[full] = db.players[full] or {}
        db.players[full].uid = sid
        return sid
    end
    return nil
end

-- Supprime l'UID sur l'entrée joueur possédant 'uid' (si trouvée).
function U.UnmapUID(uid)
    local db = EnsureDB()
    local id = tostring(uid or "")
    if id == "" then return end
    for full, rec in pairs(db.players or {}) do
        if rec and rec.uid == id then
            rec.uid = nil
            return
        end
    end
end

-- Renvoie l'UID existant (ShortId) pour 'name' ou l'alloue de façon déterministe.
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
        rec = {}
        db.players[full] = rec
    end
    if rec.uid and rec.uid ~= "" then return rec.uid end
    local sid = _ShortId(full)
    rec.uid = sid
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
        db.players[full] = {}
    end
    return db.players[full]
end
