local ADDON, ns = ...
ns.GLOG  = ns.GLOG  or {}
ns.Util = ns.Util or {}
ns.UI = ns.UI or {}
local UI = ns.UI

local GLOG, U = ns.GLOG, ns.Util

-- =========================
-- ===== Fonctions util =====
-- =========================
local function safenum(v, d) v = tonumber(v); if v == nil then return d or 0 end; return v end
local function truthy(v) v = tostring(v or ""); return (v == "1" or v:lower() == "true") end
local function now() return (time and time()) or 0 end
local function normalizeStr(s) s = tostring(s or ""):gsub("%s+",""):gsub("'",""); return s:lower() end

function GLOG.PreciseToEpoch(ts)
    -- Convertit un timestamp "jeu" (GetTime*/GetTimePreciseSec) en epoch local
    -- Sécurité : si on reçoit déjà un epoch (>= ~2001-09-09), on renvoie tel quel
    ts = tonumber(ts or 0) or 0
    if ts >= 1000000000 then
        return math.floor(ts)
    end

    -- Base actuelle : epoch (local) moins temps relatif du client
    local epochNow = (time and time()) or 0
    local relNow   = (type(GetTimePreciseSec) == "function" and GetTimePreciseSec())
                  or (type(GetTime)           == "function" and GetTime())
                  or 0
    local offset   = epochNow - relNow

    return math.floor(offset + ts + 0.5)
end

-- Debounce/Throttle génériques (U)
local _debouncers = {}
function U.Debounce(key, delay, fn)
    if type(fn) ~= "function" then return end
    delay = tonumber(delay) or 0
    local t = _debouncers[key]
    if t and t.Cancel then t:Cancel() end
    if C_Timer and C_Timer.NewTimer then
        _debouncers[key] = C_Timer.NewTimer(delay, function()
            _debouncers[key] = nil
            local ok, err = pcall(fn)
            if not ok then geterrorhandler()(err) end
        end)
    else
        _debouncers[key] = nil
        fn()
    end
end

local _throttleNext = {}
function U.Throttle(key, interval)
    interval = tonumber(interval) or 0
    local nowp = (GetTimePreciseSec and GetTimePreciseSec())
              or (debugprofilestop and (debugprofilestop()/1000)) or 0
    local nextAt = _throttleNext[key] or 0
    if nowp < nextAt then return false end
    _throttleNext[key] = nowp + interval
    return true
end

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

-- Résout un "nom" (avec ou sans royaume) en "Nom-Royaume" exact.
-- opts.strict = true  -> ne JAMAIS compléter avec le royaume local si inconnu/ambigu.
-- Retourne nil si strict et non résoluble.
function GLOG.ResolveFullName(name, opts)
    opts = opts or {}
    local raw = tostring(name or "")
    if raw == "" then return nil end

    -- 1) Déjà complet → on nettoie (ex: "Name-Realm-Realm" -> "Name-Realm")
    if raw:find("%-") then
        if CleanFullName then return CleanFullName(raw) end
        return raw
    end

    -- 2) Clé base (nom court normalisé)
    local baseKey = (GLOG.NormName and GLOG.NormName(raw)) or raw:lower()

    -- 3) Cherche en BDD locale : si un unique "Name-Realm" existe, on le garde
    if GuildLogisticsDB and GuildLogisticsDB.players then
        local candidate = nil
        for full,_ in pairs(GuildLogisticsDB.players) do
            local base = full:match("^([^%-]+)%-.+$")
            if base and base:lower() == baseKey then
                if candidate and candidate ~= full then
                    candidate = "__AMB__"; break -- ambiguïté
                end
                candidate = full
            end
        end
        if candidate and candidate ~= "__AMB__" then return candidate end
    end

    -- 4) Scan du groupe/raid pour trouver le royaume réel
    local function tryUnit(u)
        if not UnitExists or not UnitExists(u) then return nil end
        local n, r = UnitName(u)
        if not n or n == "" then return nil end
        local k = (GLOG.NormName and GLOG.NormName(n)) or n:lower()
        if k ~= baseKey then return nil end
        local realm = (r and r ~= "" and r)
                   or (GetNormalizedRealmName and GetNormalizedRealmName())
                   or (GetRealmName and GetRealmName())
                   or ""
        realm = tostring(realm):gsub("%s+",""):gsub("'","")
        if realm == "" then return nil end
        return n .. "-" .. realm
    end

    local full = tryUnit("player") or tryUnit("target") or tryUnit("mouseover")
    if not full then
        for i=1,40 do full = tryUnit("raid"..i); if full then break end end
    end
    if not full then
        for i=1,4 do full = tryUnit("party"..i); if full then break end end
    end
    if full then return full end

    -- 5) Strict : on NE complète PAS avec le royaume local → on échoue
    if opts.strict then return nil end

    -- 6) fallback non-strict: royaume local (comportement legacy)
    local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
    realm = tostring(realm):gsub("%s+",""):gsub("'","")
    if realm == "" then return raw end
    return raw .. "-" .. realm
end

-- Clé DB normalisée : toujours "Nom-Royaume" (résolution guilde + fallback realm local)
function ns.GLOG.NormalizeDBKey(name)
    local full = (ns and ns.Util and ns.Util.NormalizeFull and ns.Util.NormalizeFull(name))
                 or (ns and ns.GLOG and ns.GLOG.ResolveFullName and ns.GLOG.ResolveFullName(name))
                 or tostring(name or "")
    return full
end

-- 🔎 Récupération générique de la classe d'un joueur via les unités du groupe/raid
-- Retourne un classTag (ex: "WARRIOR") ou nil
function U.LookupClassForName(name)
    local targetKey = (ns and ns.GLOG and ns.GLOG.NormName and ns.GLOG.NormName(name))
                      or tostring(name or ""):lower()
    if not targetKey or targetKey == "" then return nil end

    local function classOf(unit)
        if not UnitExists or not UnitExists(unit) then return nil end
        local n, r = UnitName(unit)
        if not n or n == "" then return nil end
        local full = (r and r ~= "" and (n.."-"..r)) or n
        local key  = (ns and ns.GLOG and ns.GLOG.NormName and ns.GLOG.NormName(full))
                    or tostring(full or ""):lower()
        if key ~= targetKey then return nil end

        local _, classTag = UnitClass(unit)
        if classTag and classTag ~= "" then return classTag end

        local guid = UnitGUID and UnitGUID(unit)
        if guid and GetPlayerInfoByGUID then
            local _, _, _, _, _, classByGUID = GetPlayerInfoByGUID(guid)
            if classByGUID and classByGUID ~= "" then return classByGUID end
        end
        return nil
    end

    -- Priorité : player, puis raid, sinon party
    local c = classOf("player"); if c then return c end
    if IsInRaid and IsInRaid() then
        for i = 1, (GetNumGroupMembers() or 0) do
            c = classOf("raid"..i); if c then return c end
        end
    else
        for i = 1, 4 do
            c = classOf("party"..i); if c then return c end
        end
    end
    return nil
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

-- Raccourci d'affichage : "Nom-Royaume" → "Nom" (masque le serveur)
function ns.Util.ShortenFullName(full)
    local s = tostring(full or "")
    if Ambiguate then
        -- "short" cache le serveur, même inter-royaumes
        local ok, short = pcall(Ambiguate, s, "short")
        if ok and type(short) == "string" and short ~= "" then return short end
    end
    -- Fallback simple si Ambiguate indispo
    local base = s:match("^([^%-]+)") or s
    return base
end


-- =========================
-- ===  Accès DB / ver.  ===
-- =========================

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

-- Expose aussi les helpers génériques pour éviter les comparaisons avec nil ailleurs
U.safenum       = safenum         -- usage: U.safenum(x, default) -> number
U.truthy        = truthy          -- usage: U.truthy(x) -> boolean
U.now           = now             -- usage: U.now() -> epoch seconds
U.NormalizeStr  = normalizeStr    -- usage: U.NormalizeStr(" a 'b ") -> "ab"

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
    GuildLogisticsDB.meta.uidSeq = GuildLogisticsDB.meta.uidSeq or 1
    return GuildLogisticsDB
end
local function _norm(s) return (normalizeStr and normalizeStr(s)) or tostring(s or ""):gsub("%s+",""):lower() end

-- Retourne le nom complet par UID numérique en parcourant players
if type(U.GetNameByUID) ~= "function" then
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
end

-- Trouve l’UID numérique d’un joueur (stocké dans players[full].uid)
if type(U.FindUIDByName) ~= "function" then
    function U.FindUIDByName(name)
        local db   = EnsureDB()
        local full = (U.NormalizeFull and U.NormalizeFull(name)) or tostring(name or "")
        local p = db.players[full]
        return p and p.uid or nil
    end
end

-- Force un mapping UID<->player sur l’entrée players (pas de table uids)
function U.MapUID(uid, name)
    local db   = EnsureDB()
    local full = (U.NormalizeFull and U.NormalizeFull(name)) or tostring(name or "")
    local nuid = tonumber(uid)
    if not nuid then return nil end
    db.players[full] = db.players[full] or { solde = 0, reserved = true }
    db.players[full].uid = nuid
    return nuid
end

-- Supprime l’UID sur l’entrée player concernée
if type(U.UnmapUID) ~= "function" then
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
end

-- Retourne l’UID numérique existant ou l’assigne si absent (séquence purement numérique)
if type(U.GetOrAssignUID) ~= "function" then
    function U.GetOrAssignUID(name)
        local db   = EnsureDB()
        local full = (U.NormalizeFull and U.NormalizeFull(name)) or tostring(name or "")
        db.players[full] = db.players[full] or { solde = 0, reserved = true }
        if db.players[full].uid then return db.players[full].uid end
        local nextId = tonumber(db.meta.uidSeq or 1) or 1
        db.players[full].uid = nextId
        db.meta.uidSeq = nextId + 1
        return db.players[full].uid
    end
end

function U.EnsureRosterLocal(name)
    local db   = EnsureDB()
    local full = (U.NormalizeFull and U.NormalizeFull(name)) or tostring(name or "")
    db.players[full] = db.players[full] or { solde = 0, reserved = true }
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
    GuildLogisticsDB.meta.uidSeq = GuildLogisticsDB.meta.uidSeq or 1
    return GuildLogisticsDB
end
local function _norm(s) return normalizeStr and normalizeStr(s) or tostring(s or ""):gsub("%s+",""):lower() end

if type(U.GetNameByUID) ~= "function" then
    function U.GetNameByUID(uid)
        local db = EnsureDB()
        local n = tonumber(uid)
        if not n then return nil end
        for full, rec in pairs(db.players or {}) do
            if tonumber(rec and rec.uid) == n then return full end
        end
        return nil
    end
end

if type(U.FindUIDByName) ~= "function" then
    function U.FindUIDByName(name)
        local db   = EnsureDB()
        local full = U.NormalizeFull and U.NormalizeFull(name) or tostring(name or "")
        local p = db.players[full]
        return p and p.uid or nil
    end
end

if type(U.UnmapUID) ~= "function" then
    function U.UnmapUID(uid)
        local db = EnsureDB()
        local n  = tonumber(uid)
        if not n then return end
        for _, rec in pairs(db.players or {}) do
            if tonumber(rec and rec.uid) == n then rec.uid = nil; return end
        end
    end
end

if type(U.GetOrAssignUID) ~= "function" then
    function U.GetOrAssignUID(name)
        local db = EnsureDB()
        local n  = U.NormalizeFull and U.NormalizeFull(name) or tostring(name or "")
        db.players[n] = db.players[n] or { solde = 0, reserved = true }
        if db.players[n].uid then return db.players[n].uid end
        local nextId = tonumber(db.meta.uidSeq or 1) or 1
        db.players[n].uid = nextId
        db.meta.uidSeq = nextId + 1
        return db.players[n].uid
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

    -- 🔁 Itération robuste : raid1..raid40 (évite les soucis HOME/INSTANCE)
    for i = 1, 40 do
        local unit = "raid"..i
        if UnitExists and UnitExists(unit) then
            local rn, rr = UnitFullName and UnitFullName(unit)
            local full = nf(rn, rr)
            if full ~= "" and full:lower() == target:lower() then
                local _, _, subgroup = GetRaidRosterInfo(i)
                return tonumber(subgroup or 0) or 0
            end
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

-- Applique le surlignage « même groupe/sous-groupe » à TOUS les rerolls d’un joueur :
-- Si n'importe quel perso appartenant au même MAIN que `name` est dans ma party
-- (ou dans mon sous-groupe de raid), renvoie true.
function GLOG.IsInMySubgroup(name)
    if not name or name == "" then return false end

    local function normKey(n)
        return (GLOG.NormName and GLOG.NormName(n)) or (tostring(n or "")):lower()
    end
    local function mainKeyOfName(n)
        if not n or n == "" then return nil end
        local mk = (GLOG.GetMainOf and GLOG.GetMainOf(n)) or nil
        if mk and mk ~= "" then return mk end
        return normKey(n)
    end
    local function mainKeyOfUnit(unitId)
        if not (UnitExists and UnitExists(unitId)) then return nil end
        local uName = UnitName and UnitName(unitId)
        return mainKeyOfName(uName)
    end

    local targetMainKey = mainKeyOfName(name)
    if not targetMainKey or targetMainKey == "" then return false end

    -- 🛡️ RAID : seulement si même sous-groupe (robuste en instance)
    if IsInRaid and IsInRaid() then
        local mySub = GLOG.GetMyRaidSubgroup and GLOG.GetMyRaidSubgroup()
        if not (tonumber(mySub or 0) > 0) then return false end

        for i = 1, 40 do
            local unit = "raid"..i
            if UnitExists and UnitExists(unit) then
                local _, _, subgroup = GetRaidRosterInfo(i)
                if tonumber(subgroup or -1) == tonumber(mySub) then
                    if mainKeyOfUnit(unit) == targetMainKey then
                        return true
                    end
                end
            end
        end
        return false
    end

    -- 👥 PARTY (non-raid)
    if IsInGroup and IsInGroup() then
        if mainKeyOfUnit("player") == targetMainKey then return true end
        for i = 1, 4 do
            if mainKeyOfUnit("party"..i) == targetMainKey then
                return true
            end
        end
        return false
    end

    return false
end

-- == BiS / Tiers : constantes & helpers réutilisables ==
ns.Util.TIER_ORDER = ns.Util.TIER_ORDER or { "S","A","B","C","D","E","F" }

-- Analyse une clé de tier ("S", "A+", "B-minus"/"B-moins") -> base, mod, label
function ns.Util.ParseTierKey(key)
    key = type(key) == "string" and key or ""
    local base = key:match("^([A-Z])")
    if not base then return nil end
    local lower = key:lower()
    local mod
    if lower:find("plus", 2, true) or lower:find("%+", 2, true) then
        mod = "plus"
    elseif lower:find("minus", 2, true) or lower:find("moins", 2, true) or lower:find("%-", 2, true) then
        mod = "minus"
    end
    local label = base
    if mod == "plus" then
        label = base .. "+"
    elseif mod == "minus" then
        label = base .. "-"
    end
    return base, mod, label
end

-- Donne l'index d'ordre d'un tier (S > A > B ...) pour trier facilement
function ns.Util.TierIndex(base, order)
    order = order or ns.Util.TIER_ORDER
    if not base or not order then return math.huge end
    for i, v in ipairs(order) do
        if v == base then return i end
    end
    return math.huge
end

-- Résolution générique de la classe/spé du joueur avec fallback sur une DB { [CLASS_TOKEN] = ... }
function ns.Util.ResolvePlayerClassSpec(dataByClassTag)
    local useTag, useID, useSpec

    if UnitClass then
        local _, token, classID = UnitClass("player")
        useTag = token and token:upper() or nil
        if type(classID) == "number" then
            useID = classID
        elseif C_CreatureInfo and C_CreatureInfo.GetClassInfo and useTag then
            for cid = 1, 30 do
                local ok, info = pcall(C_CreatureInfo.GetClassInfo, cid)
                if ok and info and info.classFile and info.classFile:upper() == useTag then
                    useID = cid
                    break
                end
            end
        end
    end

    if GetSpecialization and GetSpecializationInfo then
        local specIndex = GetSpecialization()
        local id = specIndex and select(1, GetSpecializationInfo(specIndex)) or nil
        if id and id ~= 0 then useSpec = id end
    end

    -- Fallback via la DB passée (utile très tôt au chargement si l’API n’est pas prête)
    if (not useID) and type(dataByClassTag) == "table" then
        for tag in pairs(dataByClassTag) do
            useTag = useTag or tag
            if C_CreatureInfo and C_CreatureInfo.GetClassInfo then
                for cid = 1, 30 do
                    local ok, info = pcall(C_CreatureInfo.GetClassInfo, cid)
                    if ok and info and info.classFile and info.classFile:upper() == tag then
                        useID = cid
                        break
                    end
                end
            end
            if useID then break end
        end
    end

    return useID, useTag, useSpec
end

-- Harmonise tout le rendu "1 px" sur n'importe quel scale/moniteur.
function UI.GetPhysicalPixel()
    local _, ph = GetPhysicalScreenSize()
    local scale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
    if not ph or ph <= 0 then ph = 768 end
    if not scale or scale <= 0 then scale = 1 end
    return 768 / ph / scale
end

function UI.RoundToPixel(v)
    local p = UI.GetPhysicalPixel()
    return math.floor((v / p) + 0.5) * p
end

-- Pixel physique ramené à l'échelle EFFECTIVE d'une région
function UI.GetPhysicalPixelFor(region)
    local _, ph = GetPhysicalScreenSize()
    local eff = (region and region.GetEffectiveScale and region:GetEffectiveScale())
             or (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale())
             or 1
    if not ph or ph <= 0 then ph = 768 end
    if not eff or eff <= 0 then eff = 1 end
    return 768 / ph / eff
end

-- Arrondi au pixel pour une région donnée (évite les sous-pixels quand la frame est scalée)
function UI.RoundToPixelOn(region, v)
    local p = UI.GetPhysicalPixelFor(region)
    return math.floor((v / p) + 0.5) * p
end

function UI.SnapTexture(tex)
    if tex and tex.SetSnapToPixelGrid then
        tex:SetSnapToPixelGrid(true)
        tex:SetTexelSnappingBias(0)
    end
    return tex
end

function UI.SnapRegion(region)
    if not region then return end
    local function Q(v)
        if UI.RoundToPixelOn then return UI.RoundToPixelOn(region, v) end
        return UI.RoundToPixel(v)
    end

    -- Taille
    local w, h = region:GetSize()
    if w and w > 0 then
        local qw = Q(w)
        if PixelUtil and PixelUtil.SetWidth then PixelUtil.SetWidth(region, qw) else region:SetWidth(qw) end
    end
    if h and h > 0 then
        local qh = Q(h)
        if PixelUtil and PixelUtil.SetHeight then PixelUtil.SetHeight(region, qh) else region:SetHeight(qh) end
    end

    -- Points d'ancrage
    local n = region:GetNumPoints()
    if n and n > 0 then
        for i = 1, n do
            local p, rel, rp, x, y = region:GetPoint(i)
            if p then
                local nx, ny = Q(x or 0), Q(y or 0)
                local changed = (not x) or (not y)
                    or math.abs((x or 0) - nx) > 1e-3
                    or math.abs((y or 0) - ny) > 1e-3
                if changed then
                    if PixelUtil and PixelUtil.SetPoint then
                        PixelUtil.SetPoint(region, p, rel, rp, nx, ny)
                    else
                        region:SetPoint(p, rel, rp, nx, ny)
                    end
                end
            end
        end
    end
end

-- Fixe l'épaisseur d'une ligne à N pixels physiques exacts (par défaut 1).
function UI.SetPixelThickness(tex, n)
    n = n or 1
    local h = (UI.GetPhysicalPixelFor and UI.GetPhysicalPixelFor(tex) or UI.GetPhysicalPixel()) * n
    if PixelUtil and PixelUtil.SetHeight then PixelUtil.SetHeight(tex, h) else tex:SetHeight(h) end
end

function UI.SetPixelWidth(tex, n)
    n = n or 1
    local w = (UI.GetPhysicalPixelFor and UI.GetPhysicalPixelFor(tex) or UI.GetPhysicalPixel()) * n
    if PixelUtil and PixelUtil.SetWidth then PixelUtil.SetWidth(tex, w) else tex:SetWidth(w) end
end


-- ===============================
-- === Compat API Spell Info  ===
-- ===============================
-- Retourne (name, icon) pour un spell id/nom, compatible 11.x (C_Spell) & versions antérieures
-- icon peut être un fileID (number) ou un chemin (string).
function ns.Util.SpellInfoCompat(idOrName)
    local name, icon

    if C_Spell and C_Spell.GetSpellInfo then
        local si = C_Spell.GetSpellInfo(idOrName)
        if si then
            name = si.name
            icon = si.iconID
        end
    end

    if (not name) and GetSpellInfo then
        local n, _, ic = GetSpellInfo(idOrName)
        name = name or n
        icon = icon or ic
    end

    return name, icon
end

-- ===============================
-- ===  Erreurs Lua (scriptErrors)
-- ===============================
function GLOG.IsScriptErrorsEnabled()
    if type(GetCVar) == "function" then
        local v = tostring(GetCVar("scriptErrors") or "0")
        return (v == "1") or (v:lower() == "true")
    end
    return false
end

function GLOG.SetScriptErrorsEnabled(enabled)
    local v = enabled and "1" or "0"
    if type(SetCVar) == "function" then
        pcall(SetCVar, "scriptErrors", v)
    end
    return GLOG.IsScriptErrorsEnabled()
end

-- =========================
-- ======  GENERIC DB  =====
-- =========================

-- Retourne vrai si 't' est un tableau séquentiel (1..n) + sa taille 'n'.
function GLOG.IsArrayTable(t)
    if type(t) ~= "table" then return false, 0 end
    local n = #t
    -- Vérifie qu'aucune clé non-numérique n'existe et qu'il n'y a pas de trous < n
    for k, _ in pairs(t) do
        if type(k) ~= "number" or k < 1 or k % 1 ~= 0 or k > n then
            return false, n
        end
    end
    return true, n
end

function GLOG.TableKeyCount(t)
    if type(t) ~= "table" then return 0 end
    local c = 0
    for _ in pairs(t) do c = c + 1 end
    return c
end

-- Sérialisation simple en littéral Lua (lisible, indenté).
function GLOG.SerializeLua(v, depth)
    depth = depth or 0
    local t = type(v)
    if t == "string" then return string.format("%q", v) end
    if t == "number" or t == "boolean" or t == "nil" then return tostring(v) end
    if t ~= "table" then return "\"<"..t..">\"" end

    local indent  = string.rep("  ", depth)
    local indent2 = string.rep("  ", depth + 1)
    local isArray, n = GLOG.IsArrayTable(v)
    local parts = {}

    if isArray then
        for i = 1, n do
            parts[#parts+1] = indent2 .. GLOG.SerializeLua(v[i], depth + 1)
        end
    else
        for k, val in pairs(v) do
            local key
            if type(k) == "string" and k:match("^%a[%w_]*$") then
                key = k
            else
                key = "["..GLOG.SerializeLua(k, 0).."]"
            end
            parts[#parts+1] = indent2 .. key .. " = " .. GLOG.SerializeLua(val, depth + 1)
        end
    end

    if #parts == 0 then return "{}" end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end

-- Parse un littéral Lua et retourne la valeur (ou nil + msg d'erreur)
function GLOG.DeserializeLua(text)
    local s = tostring(text or "")
    if s == "" then return nil, "empty" end
    local chunk, err = loadstring("return " .. s)
    if not chunk then return nil, err end
    local ok, val = pcall(chunk)
    if not ok then return nil, val end
    return val, nil
end

-- Contrôle d'affichage des séparateurs verticaux attachés à une région (header/row)
function UI.SetVSepsVisible(region, visible)
    if not region or not region._vseps then return end
    for _, t in pairs(region._vseps) do
        if t then
            if visible == false then
                if t.Hide then t:Hide() end
            else
                if t.Show then t:Show() end
            end
        end
    end
end
