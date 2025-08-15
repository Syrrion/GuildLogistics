local ADDON, ns = ...
ns.CDZ  = ns.CDZ  or {}
ns.Util = ns.Util or {}

local CDZ, U = ns.CDZ, ns.Util

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
    realm = realm or (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
    realm = tostring(realm):gsub("%s+",""):gsub("'","")
    if realm ~= "" then return name.."-"..realm end
    return name
end

local function playerFullName()
    local n, r = UnitFullName and UnitFullName("player")
    if n and r and r ~= "" then return n.."-"..r:gsub("%s+",""):gsub("'","") end
    local short = (UnitName and UnitName("player")) or "?"
    local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
    if realm ~= "" then return short.."-"..realm:gsub("%s+",""):gsub("'","") end
    return short
end

local function ShortName(full) full = tostring(full or ""); return (full:match("^(.-)%-.+$") or full) end
local function SamePlayer(a,b)
    a, b = tostring(a or ""), tostring(b or ""); if a=="" or b=="" then return false end
    local sa, sb = ShortName(a), ShortName(b)
    return normalizeStr(sa) == normalizeStr(sb) or normalizeStr(a) == normalizeStr(b)
end

-- =========================
-- ===  Accès DB / ver.  ===
-- =========================
local function masterName()
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}; ChroniquesDuZephyrDB.meta = ChroniquesDuZephyrDB.meta or {}
    return ChroniquesDuZephyrDB.meta.master
end
local function getRev()
    if CDZ.GetRev then return safenum(CDZ.GetRev(), 0) end
    ChroniquesDuZephyrDB = ChroniquesDuZephyrDB or {}; ChroniquesDuZephyrDB.meta = ChroniquesDuZephyrDB.meta or {}
    return safenum(ChroniquesDuZephyrDB.meta.rev, 0)
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
_G.NormalizeFull  = _G.NormalizeFull  or NormalizeFull
_G.playerFullName = _G.playerFullName or playerFullName
_G.masterName     = _G.masterName     or masterName
_G.getRev         = _G.getRev         or getRev

U.safenum        = safenum
U.truthy         = truthy
U.normalizeStr   = normalizeStr
U.now            = now
U.NormalizeFull  = NormalizeFull
U.playerFullName = playerFullName
U.ShortName      = ShortName
U.SamePlayer     = SamePlayer
