local ADDON, ns = ...
ns.GLOG  = ns.GLOG  or {}
ns.Util = ns.Util or {}

local GLOG, U = ns.GLOG, ns.Util

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

-- ⚙️ Corrige "Nom-Royaume-Royaume-..." -> "Nom-Royaume"
local function CleanFullName(full)
    local s = tostring(full or "")
    local base, tail = s:match("^([^%-]+)%-(.+)$")
    if not base then return s end

    -- Découpe les segments de royaume (certains clients du dernier patch dupliquent)
    local parts = {}
    for p in tail:gmatch("[^%-]+") do
        if p ~= "" then parts[#parts+1] = p end
    end
    if #parts <= 1 then return s end

    -- Si tous identiques (à casse/espaces/accents près), on garde le 1er ; sinon on garde le dernier.
    local function norm(x) x = tostring(x or ""):gsub("%s+",""):gsub("'",""); return x:lower() end
    local allSame = true
    for i = 2, #parts do
        if norm(parts[i]) ~= norm(parts[1]) then allSame = false; break end
    end
    local realm = allSame and parts[1] or parts[#parts]
    return (base .. "-" .. realm)
end

local function NormalizeFull(name, realm)
    name  = tostring(name or "?")

    -- Si déjà "Nom-..." on nettoie d'abord les éventuels doublons de royaume
    if name:find("%-") then
        return CleanFullName(name)
    end

    local nrm = realm
    if not nrm or nrm == "" then
        nrm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
    end
    nrm = tostring(nrm):gsub("%s+",""):gsub("'","")
    if nrm ~= "" then return name.."-"..nrm end
    return name
end

-- 🔁 Exposition util
U.CleanFullName  = CleanFullName
U.NormalizeFull  = NormalizeFull

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
    if GLOG and GLOG.GetGuildMasterCached then
        local gm = GLOG.GetGuildMasterCached()
        if gm and gm ~= "" then return gm end
    end
    -- Fallback minimal si roster indisponible
    GuildLogisticsDB = GuildLogisticsDB or {}; GuildLogisticsDB.meta = GuildLogisticsDB.meta or {}
    return GuildLogisticsDB.meta.master
end

-- Chef de guilde = override toujours vrai
-- Master désigné = strict si défini
-- Sinon (pas de master), autorise les grades avec vraies permissions officiers
function GLOG.IsMaster()
    -- 1) Chef de guilde : toujours autorisé
    if IsInGuild and IsInGuild() then
        local _, _, ri = GetGuildInfo("player")
        if ri == 0 then return true end
    end
    return false
end

-- ➕ Optionnel : utilitaire explicite (peut servir à l’UI)
function GLOG.IsGM()
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
    if GLOG.GetRev then return safenum(GLOG.GetRev(), 0) end
    GuildLogisticsDB = GuildLogisticsDB or {}; GuildLogisticsDB.meta = GuildLogisticsDB.meta or {}
    return safenum(GuildLogisticsDB.meta.rev, 0)
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
ns.GLOG = ns.GLOG or {}
if type(ns.GLOG.GetDebugLogs) ~= "function" then
    local _fallbackDebug = {}
    function ns.GLOG.GetDebugLogs() return _fallbackDebug end
end
if type(ns.GLOG._SetDebugLogsRef) ~= "function" then
    function ns.GLOG._SetDebugLogsRef(t)
        if type(t) == "table" then
            ns.GLOG.GetDebugLogs = function() return t end
        end
    end
end

-- ➕ Helpers UID/Roster centraux (dans ns.Util) + miroirs dans GLOG pour compat
local function EnsureDB()
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.meta    = GuildLogisticsDB.meta    or {}
    GuildLogisticsDB.players = GuildLogisticsDB.players or {}
    GuildLogisticsDB.uids    = GuildLogisticsDB.uids    or {}
    GuildLogisticsDB.meta.uidSeq = GuildLogisticsDB.meta.uidSeq or 1
    return GuildLogisticsDB
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

function U.MapUID(uid, name)
    local db = EnsureDB()
    local full = (U.NormalizeFull and U.NormalizeFull(name)) or tostring(name or "")
    db.uids[tostring(uid or "")] = full
    -- ⛑️ Création implicite = Réserve
    db.players[full] = db.players[full] or { credit = 0, debit = 0, reserved = true }
    return uid
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

function U.EnsureRosterLocal(name)
    local db = EnsureDB()
    local full = (U.NormalizeFull and U.NormalizeFull(name)) or tostring(name or "")
    -- ⛑️ Création implicite = Réserve
    db.players[full] = db.players[full] or { credit = 0, debit = 0, reserved = true }
    if db.players[full].reserved == nil then db.players[full].reserved = true end
    return db.players[full]
end

-- Miroirs compat dans GLOG (si absents)
if type(ns.GLOG.GetOrAssignUID) ~= "function" then ns.GLOG.GetOrAssignUID = U.GetOrAssignUID end
if type(ns.GLOG.GetNameByUID)  ~= "function" then ns.GLOG.GetNameByUID  = U.GetNameByUID  end
if type(ns.GLOG.MapUID)        ~= "function" then ns.GLOG.MapUID        = U.MapUID        end
if type(ns.GLOG.UnmapUID)      ~= "function" then ns.GLOG.UnmapUID      = U.UnmapUID      end
if type(ns.GLOG.EnsureRosterLocal) ~= "function" then ns.GLOG.EnsureRosterLocal = U.EnsureRosterLocal end
if type(ns.GLOG.FindUIDByName) ~= "function" then ns.GLOG.FindUIDByName = U.FindUIDByName end
if type(ns.GLOG.GetUID)        ~= "function" then ns.GLOG.GetUID        = U.FindUIDByName end


-- ➕ Gestion centrale des UID / Roster (idempotent)
local function EnsureDB()
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.meta    = GuildLogisticsDB.meta    or {}
    GuildLogisticsDB.players = GuildLogisticsDB.players or {}
    GuildLogisticsDB.uids    = GuildLogisticsDB.uids    or {}
    GuildLogisticsDB.meta.uidSeq = GuildLogisticsDB.meta.uidSeq or 1
    return GuildLogisticsDB
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

-- ➕ Utilitaires : guilde & titre principal
function GLOG.GetCurrentGuildName()
    if IsInGuild and IsInGuild() then
        local gname = GetGuildInfo("player")
        if type(gname) == "string" and gname ~= "" then
            return gname
        end
    end
    return nil
end

-- ➕ Nouveau : nom « officiel » de l’addon (TOC Title), avec fallback locales
function GLOG.GetAddonTitle()
    local title = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Title"))
               or (GetAddOnMetadata and GetAddOnMetadata(ADDON, "Title"))
    if type(title) == "string" and title ~= "" then
        -- Nettoie d’éventuels codes couleur dans le Title
        title = title:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        return title
    end
    local Tr = ns and ns.Tr
    return (Tr and Tr("app_title"))
end

function GLOG.BuildMainTitle()
    local g = GLOG.GetCurrentGuildName and GLOG.GetCurrentGuildName()
    if g and g ~= "" then
        return g
    end
    -- ➜ Si pas de guilde : affiche le nom de l’addon
    return (GLOG.GetAddonTitle and GLOG.GetAddonTitle())
end


function GLOG.GetAddonIconTexture()
    local icon = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "IconTexture"))
              or (GetAddOnMetadata and GetAddOnMetadata(ADDON, "IconTexture"))
    if type(icon) == "string" and icon ~= "" then return icon end
    return "Interface\\Icons\\INV_Misc_Book_09"
end

-- ➕ Version d’addon (ex: "1.1.7"), via TOC
function GLOG.GetAddonVersion()
    local v = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version"))
          or (GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version"))
          or (ns and ns.Version)
    v = tostring(v or "")
    return v
end

-- ➕ Comparaison sémantique a vs b : -1 / 0 / +1
function ns.Util.CompareVersions(a, b)
    local function parse(s)
        local out = {}
        for n in tostring(s or ""):gmatch("(%d+)") do out[#out+1] = tonumber(n) or 0 end
        return out
    end
    local A, B = parse(a), parse(b)
    local n = math.max(#A, #B)
    for i = 1, n do
        local x, y = A[i] or 0, B[i] or 0
        if x < y then return -1 elseif x > y then return 1 end
    end
    return 0
end

-- ➕ ====== Groupe & Raid: helpers ======
function GLOG.GetRaidSubgroupOf(name)
    if not name or name == "" then return nil end
    if not (IsInRaid and IsInRaid()) then return nil end

    local nf = (ns.Util and ns.Util.NormalizeFull) or function(n, r)
        if n and r and r ~= "" then return (tostring(n) .. "-" .. tostring(r):gsub("%s+",""):gsub("'","")) end
        local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
        realm = tostring(realm):gsub("%s+",""):gsub("'","")
        if realm ~= "" then return tostring(n or "") .. "-" .. realm end
        return tostring(n or "")
    end

    local target = nf(name)
    if target == "" then return nil end
    local N = (GetNumGroupMembers and GetNumGroupMembers()) or 0
    for i = 1, N do
        local unit = "raid"..i
        local rn, rr = UnitFullName and UnitFullName(unit)
        local full = nf(rn, rr)
        if full ~= "" and full:lower() == target:lower() then
            local _, _, subgroup = GetRaidRosterInfo(i)
            return tonumber(subgroup or 0) or 0
        end
    end
    return nil
end

function GLOG.GetMyRaidSubgroup()
    if not (IsInRaid and IsInRaid()) then return nil end
    local me = playerFullName and playerFullName() or nil
    if not me or me == "" then return nil end
    return GLOG.GetRaidSubgroupOf(me)
end

function GLOG.IsInMyParty(name)
    if not name or name == "" then return false end
    if IsInRaid and IsInRaid() then return false end
    if not (IsInGroup and IsInGroup()) then return false end

    local nf = (ns.Util and ns.Util.NormalizeFull) or function(n, r)
        if n and r and r ~= "" then return (tostring(n) .. "-" .. tostring(r):gsub("%s+",""):gsub("'","")) end
        local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
        realm = tostring(realm):gsub("%s+",""):gsub("'","")
        if realm ~= "" then return tostring(n or "") .. "-" .. realm end
        return tostring(n or "")
    end

    local target = nf(name)
    if target == "" then return false end

    -- le joueur lui-même
    local pn, pr = UnitFullName and UnitFullName("player")
    local pfull = nf(pn, pr)
    if pfull:lower() == target:lower() then return true end

    for i = 1, 4 do
        local unit = "party"..i
        if UnitExists and UnitExists(unit) then
            local n, r = UnitFullName(unit)
            local full = nf(n, r)
            if full ~= "" and full:lower() == target:lower() then
                return true
            end
        end
    end
    return false
end

function GLOG.IsInMySubgroup(name)
    -- En raid: même sous-groupe; en groupe: même party; sinon false
    if IsInRaid and IsInRaid() then
        local mine = GLOG.GetMyRaidSubgroup()
        local his  = GLOG.GetRaidSubgroupOf(name)
        return (tonumber(mine or 0) > 0) and (tonumber(mine or 0) == tonumber(his or -1))
    end
    return GLOG.IsInMyParty(name)
end
