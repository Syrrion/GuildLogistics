local ADDON, ns = ...
ns.GMGR  = ns.GMGR  or {}
ns.Util = ns.Util or {}

local GMGR, U = ns.GMGR, ns.Util

-- =========================
-- ===== Fonctions util =====
-- =========================
local function safenum(v, d) v = tonumber(v); if v == nil then return d or 0 end; return v end
local function truthy(v) v = tostring(v or ""); return (v == "1" or v:lower() == "true") end
local function now() return (time and time()) or 0 end
local function normalizeStr(s) s = tostring(s or ""):gsub("%s+",""):gsub("'",""); return s:lower() end

-- =========================
-- === Gestion des noms  ===
-- =========================
local function NormalizeFull(name, realm)
    name  = tostring(name or "?")
    -- Si déjà "Nom-Royaume", ne pas doubler
    if name:find("%-") then return name end

    local nrm = realm
    if not nrm or nrm == "" then
        nrm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
    end
    nrm = tostring(nrm):gsub("%s+",""):gsub("'","")
    if nrm ~= "" then return name.."-"..nrm end
    return name
end

local function SamePlayer(a,b)
    a, b = tostring(a or ""), tostring(b or ""); if a=="" or b=="" then return false end
    -- Égalité sur le nom complet uniquement
    return normalizeStr(a) == normalizeStr(b)
end

local function playerFullName()
    local n, r = UnitFullName and UnitFullName("player")
    if n and r and r ~= "" then return n.."-"..r:gsub("%s+",""):gsub("'","") end
    local short = (UnitName and UnitName("player")) or "?"
    local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
    if realm ~= "" then return short.."-"..realm:gsub("%s+",""):gsub("'","") end
    return short
end

-- =========================
-- ===  Accès DB / ver.  ===
-- =========================
local function masterName()
    -- ⚠️ Source de vérité = roster (GM = rang index 0)
    if GMGR and GMGR.GetGuildMasterCached then
        local gm = GMGR.GetGuildMasterCached()
        if gm and gm ~= "" then return gm end
    end
    -- Fallback minimal si roster indisponible
    GuildManagerDB = GuildManagerDB or {}; GuildManagerDB.meta = GuildManagerDB.meta or {}
    return GuildManagerDB.meta.master
end

-- Chef de guilde = override toujours vrai
-- Master désigné = strict si défini
-- Sinon (pas de master), autorise les grades avec vraies permissions officiers
function GMGR.IsMaster()
    -- 1) Chef de guilde : toujours autorisé
    if IsInGuild and IsInGuild() then
        local _, _, ri = GetGuildInfo("player")
        if ri == 0 then return true end
    end
    return false
end

-- ➕ Optionnel : utilitaire explicite (peut servir à l’UI)
function GMGR.IsGM()
    if IsInGuild and IsInGuild() then
        local _, _, ri = GetGuildInfo("player")
        if ri == 0 then return true end
        local function has(fn) return type(fn) == "function" and fn() end
        if has(CanGuildPromote)
        or has(CanGuildDemote)
        or has(CanGuildRemove)
        or has(CanGuildInvite)
        or has(CanEditMOTD)
        or has(CanEditGuildInfo)
        or has(CanEditPublicNote) then
            return true
        end
    end
    return false
end

local function getRev()
    if GMGR.GetRev then return safenum(GMGR.GetRev(), 0) end
    GuildManagerDB = GuildManagerDB or {}; GuildManagerDB.meta = GuildManagerDB.meta or {}
    return safenum(GuildManagerDB.meta.rev, 0)
end

-- =========================
-- ======  Tables     ======
-- =========================
function U.ShallowCopy(t) local o={}; for k,v in pairs(t or {}) do o[k]=v end; return o end
function U.DeepCopy(t, seen)
    if type(t)~="table" then return t end; seen=seen or {}; if seen[t] then return seen[t] end
    local o={}; seen[t]=o; for k,v in pairs(t) do o[U.DeepCopy(k,seen)] = U.DeepCopy(v,seen) end; return o
end

-- =========================
-- ===  Planification   ===
-- =========================
function U.After(sec, fn) if C_Timer and C_Timer.After and type(fn)=="function" then C_Timer.After(tonumber(sec) or 0, fn) else if type(fn)=="function" then pcall(fn) end end end

-- =========================
-- == Exposition globale ==
-- =========================
_G.safenum        = _G.safenum        or safenum
_G.truthy         = _G.truthy         or truthy
_G.normalizeStr   = _G.normalizeStr   or normalizeStr
_G.now            = _G.now            or now
_G.playerFullName = _G.playerFullName or playerFullName
_G.masterName     = _G.masterName     or masterName
_G.getRev         = _G.getRev         or getRev

U.safenum        = safenum
U.truthy         = truthy
U.normalizeStr   = normalizeStr
U.now            = now
U.NormalizeFull  = NormalizeFull
U.playerFullName = playerFullName
U.SamePlayer     = SamePlayer

-- -- Journal/Debug : stub sûr pour éviter les nil avant le chargement de Comm.lua
ns.GMGR = ns.GMGR or {}
if type(ns.GMGR.GetDebugLogs) ~= "function" then
    local _fallbackDebug = {}
    function ns.GMGR.GetDebugLogs() return _fallbackDebug end
end
if type(ns.GMGR._SetDebugLogsRef) ~= "function" then
    function ns.GMGR._SetDebugLogsRef(t)
        if type(t) == "table" then
            ns.GMGR.GetDebugLogs = function() return t end
        end
    end
end

-- ➕ Helpers UID/Roster centraux (dans ns.Util) + miroirs dans GMGR pour compat
local function EnsureDB()
    GuildManagerDB = GuildManagerDB or {}
    GuildManagerDB.meta    = GuildManagerDB.meta    or {}
    GuildManagerDB.players = GuildManagerDB.players or {}
    GuildManagerDB.uids    = GuildManagerDB.uids    or {}
    GuildManagerDB.meta.uidSeq = GuildManagerDB.meta.uidSeq or 1
    return GuildManagerDB
end
local function _norm(s) return (normalizeStr and normalizeStr(s)) or tostring(s or ""):gsub("%s+",""):lower() end

if type(U.GetNameByUID) ~= "function" then
    function U.GetNameByUID(uid)
        local db = EnsureDB()
        return db.uids[tostring(uid or "")]
    end
end

if type(U.FindUIDByName) ~= "function" then
    function U.FindUIDByName(name)
        local db = EnsureDB()
        local n0 = _norm((U.NormalizeFull and U.NormalizeFull(name)) or name)
        for uid, stored in pairs(db.uids) do
            if _norm(stored) == n0 then return uid end
        end
        return nil
    end
end

if type(U.MapUID) ~= "function" then
    function U.MapUID(uid, name)
        local db = EnsureDB()
        local full = (U.NormalizeFull and U.NormalizeFull(name)) or tostring(name or "")
        db.uids[tostring(uid or "")] = full
        db.players[full] = db.players[full] or { credit = 0, debit = 0 }
        return uid
    end
end

if type(U.UnmapUID) ~= "function" then
    function U.UnmapUID(uid)
        local db = EnsureDB()
        db.uids[tostring(uid or "")] = nil
    end
end

if type(U.GetOrAssignUID) ~= "function" then
    function U.GetOrAssignUID(name)
        local db = EnsureDB()
        local full = (U.NormalizeFull and U.NormalizeFull(name)) or tostring(name or "")
        local uid = U.FindUIDByName(full)
        if uid then return uid end
        local nextId = tonumber(db.meta.uidSeq or 1) or 1
        uid = string.format("P%06d", nextId)
        db.meta.uidSeq = nextId + 1
        U.MapUID(uid, full)
        return uid
    end
end

if type(U.EnsureRosterLocal) ~= "function" then
    function U.EnsureRosterLocal(name)
        local db = EnsureDB()
        local full = (U.NormalizeFull and U.NormalizeFull(name)) or tostring(name or "")
        db.players[full] = db.players[full] or { credit = 0, debit = 0 }
        return db.players[full]
    end
end

-- Miroirs compat dans GMGR (si absents)
if type(ns.GMGR.GetOrAssignUID) ~= "function" then ns.GMGR.GetOrAssignUID = U.GetOrAssignUID end
if type(ns.GMGR.GetNameByUID)  ~= "function" then ns.GMGR.GetNameByUID  = U.GetNameByUID  end
if type(ns.GMGR.MapUID)        ~= "function" then ns.GMGR.MapUID        = U.MapUID        end
if type(ns.GMGR.UnmapUID)      ~= "function" then ns.GMGR.UnmapUID      = U.UnmapUID      end
if type(ns.GMGR.EnsureRosterLocal) ~= "function" then ns.GMGR.EnsureRosterLocal = U.EnsureRosterLocal end
if type(ns.GMGR.FindUIDByName) ~= "function" then ns.GMGR.FindUIDByName = U.FindUIDByName end
if type(ns.GMGR.GetUID)        ~= "function" then ns.GMGR.GetUID        = U.FindUIDByName end


-- ➕ Gestion centrale des UID / Roster (idempotent)
local function EnsureDB()
    GuildManagerDB = GuildManagerDB or {}
    GuildManagerDB.meta    = GuildManagerDB.meta    or {}
    GuildManagerDB.players = GuildManagerDB.players or {}
    GuildManagerDB.uids    = GuildManagerDB.uids    or {}
    GuildManagerDB.meta.uidSeq = GuildManagerDB.meta.uidSeq or 1
    return GuildManagerDB
end
local function _norm(s) return normalizeStr and normalizeStr(s) or tostring(s or ""):gsub("%s+",""):lower() end

if type(U.GetNameByUID) ~= "function" then
    function U.GetNameByUID(uid)
        local db = EnsureDB()
        return db.uids[tostring(uid or "")]
    end
end

if type(U.FindUIDByName) ~= "function" then
    function U.FindUIDByName(name)
        local db = EnsureDB()
        local n = U.NormalizeFull and U.NormalizeFull(name) or tostring(name or "")
        local n0 = _norm(n)
        for uid, stored in pairs(db.uids) do
            if _norm(stored) == n0 then return uid end
        end
        return nil
    end
end

if type(U.MapUID) ~= "function" then
    function U.MapUID(uid, name)
        local db = EnsureDB()
        local n = U.NormalizeFull and U.NormalizeFull(name) or tostring(name or "")
        db.uids[tostring(uid or "")] = n
        -- optionnel : créer l’entrée joueur si absente
        db.players[n] = db.players[n] or { credit = 0, debit = 0 }
        return uid
    end
end

if type(U.UnmapUID) ~= "function" then
    function U.UnmapUID(uid)
        local db = EnsureDB()
        db.uids[tostring(uid or "")] = nil
    end
end

if type(U.GetOrAssignUID) ~= "function" then
    function U.GetOrAssignUID(name)
        local db = EnsureDB()
        local n = U.NormalizeFull and U.NormalizeFull(name) or tostring(name or "")
        local uid = U.FindUIDByName(n)
        if uid then return uid end
        local nextId = tonumber(db.meta.uidSeq or 1) or 1
        uid = string.format("P%06d", nextId)
        db.meta.uidSeq = nextId + 1
        U.MapUID(uid, n)
        return uid
    end
end

if type(U.EnsureRosterLocal) ~= "function" then
    function U.EnsureRosterLocal(name)
        local db = EnsureDB()
        local n = U.NormalizeFull and U.NormalizeFull(name) or tostring(name or "")
        db.players[n] = db.players[n] or { credit = 0, debit = 0 }
        return db.players[n]
    end
end

-- ➕ Utilitaires : guilde & titre principal
function GMGR.GetCurrentGuildName()
    if IsInGuild and IsInGuild() then
        local gname = GetGuildInfo("player")
        if type(gname) == "string" and gname ~= "" then
            return gname
        end
    end
    return nil
end

function GMGR.BuildMainTitle()
    local g = GMGR.GetCurrentGuildName and GMGR.GetCurrentGuildName()
    if g and g ~= "" then
        return string.format("%s", g)
    end
    return ""
end

function GMGR.GetAddonIconTexture()
    -- Préfère l'API moderne, sinon rétro-compatibilité
    local icon = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "IconTexture"))
              or (GetAddOnMetadata and GetAddOnMetadata(ADDON, "IconTexture"))
    if type(icon) == "string" and icon ~= "" then
        return icon -- ex: "Interface\\AddOns\\MonAddon\\media\\icon.blp" OU une texture Interface\\Icons\\*
    end
    -- Fallback : icône livre par défaut (ne dépend pas de fichiers de l'addon)
    return "Interface\\Icons\\INV_Misc_Book_09"
end