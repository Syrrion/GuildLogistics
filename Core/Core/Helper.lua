local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
ns.Util = ns.Util or {}
local U = ns.Util

-- Convertit 'v' en nombre ; retourne 'd' (ou 0) si la conversion échoue.
-- Utile pour sécuriser les lectures d'options/DB.
local function safenum(v, d)
    v = tonumber(v)
    if v == nil then
        return d or 0
    end
    return v
end

-- Interprète une valeur texte/numérique comme booléen vrai si "1" ou "true" (insensible à la casse).
local function truthy(v)
    v = tostring(v or "")
    return (v == "1" or v:lower() == "true")
end

-- Renvoie l'heure locale en secondes depuis l'epoch (fallback si 'time' indisponible).
local function now()
    return (time and time()) or 0
end

-- Normalise une chaîne : supprime espaces/apostrophes et passe en minuscules.
-- Idéal pour créer des clés de comparaison sans accents ni espaces.
local function normalizeStr(s)
    s = tostring(s or ""):gsub("%s+", ""):gsub("'", "")
    return s:lower()
end

-- Compare deux identités "Nom-Royaume" après normalisation stricte.
-- Retourne true si identiques (indépendant des espaces/casse).
local function SamePlayer(a, b)
    a, b = tostring(a or ""), tostring(b or "")
    if a == "" or b == "" then
        return false
    end
    return normalizeStr(a) == normalizeStr(b)
end

-- Copie superficielle (un seul niveau) d'un tableau.
function U.ShallowCopy(t)
    local o = {}
    for k, v in pairs(t or {}) do
        o[k] = v
    end
    return o
end

-- Copie profonde d'un tableau (gère les références circulaires via 'seen').
function U.DeepCopy(t, seen)
    if type(t) ~= "table" then
        return t
    end
    seen = seen or {}
    if seen[t] then
        return seen[t]
    end
    local o = {}
    seen[t] = o
    for k, v in pairs(t) do
        o[U.DeepCopy(k, seen)] = U.DeepCopy(v, seen)
    end
    return o
end

-- Contraint un nombre 'v' dans l'intervalle [min, max].
function U.Clamp(v, min, max)
    v = tonumber(v) or 0
    if min and v < min then v = min end
    if max and v > max then v = max end
    return v
end

-- Lit une option numérique dans 'store[key]', applique défaut et bornes.
function U.GetClampedOption(store, key, default, min, max)
    local a = tonumber(store and store[key] or default) or default or 0
    return U.Clamp(a, min, max)
end

-- Exposition util (namespaces + globales contrôlées)
U.safenum        = safenum
U.truthy         = truthy
U.normalizeStr   = normalizeStr
U.NormalizeStr   = normalizeStr
U.now            = now
U.SamePlayer     = SamePlayer

_G.safenum       = _G.safenum or safenum
_G.truthy        = _G.truthy or truthy
_G.normalizeStr  = _G.normalizeStr or normalizeStr
_G.now           = _G.now or now

-- =========================
-- ===== UI UTILITIES ======
-- =========================

-- Constante d'icône centrale de l'addon
local GLOG = ns.GLOG
GLOG.ICON_TEXTURE = GLOG.ICON_TEXTURE or "Interface\\AddOns\\GuildLogistics\\Ressources\\Media\\LogoAddonWoW128.tga"

-- Sélecteur intelligent de taille d'icône basé sur la taille demandée
function GLOG.GetAddonIconTexture(size)
    local base = "Interface\\AddOns\\GuildLogistics\\Ressources\\Media\\LogoAddonWoW"
    local pick
    if type(size) == "number" then
        if size <= 16 then       pick = "16"
        elseif size <= 32 then   pick = "32"
        elseif size <= 64 then   pick = "64"
        elseif size <= 128 then  pick = "128"
        elseif size <= 256 then  pick = "256"
        else                     pick = "400"
        end
    elseif type(size) == "string" then
        local s = string.lower(size)
        if s == "tiny" then                  pick = "16"
        elseif s == "minimap" or s == "sm" then pick = "32"
        elseif s == "small" then             pick = "64"
        elseif s == "medium" then            pick = "128"
        elseif s == "large" then             pick = "256"
        elseif s == "xlarge" or s == "xl" then pick = "400"
        end
    end
    pick = pick or "128"
    return base .. pick .. ".tga"
end

-- =========================
-- == WINDOW PERSISTENCE ===
-- =========================

function GLOG.GetSavedWindow() 
    GLOG.EnsureDB(); 
    return GuildLogisticsUI 
end

function GLOG.SaveWindow(point, relTo, relPoint, x, y)
    GuildLogisticsUI = GuildLogisticsUI or {}
    GuildLogisticsUI.point    = point
    GuildLogisticsUI.relTo    = relTo
    GuildLogisticsUI.relPoint = relPoint
    GuildLogisticsUI.x        = x
    GuildLogisticsUI.y        = y
end

-- Lecture d'une option de popup (défaut = true si non défini)
function GLOG.IsPopupEnabled(key)
    local saved = (GLOG.GetSavedWindow and GLOG.GetSavedWindow()) or GuildLogisticsUI or {}
    saved.popups = saved.popups or {}
    local v = saved.popups[key]
    if v == nil then return true end
    return v and true or false
end

-- ➕ Persistance : dernier onglet actif (par personnage)
function GLOG.GetLastActiveTabLabel()
    GLOG.EnsureDB()
    GuildLogisticsUI = GuildLogisticsUI or {}
    return GuildLogisticsUI.lastTabLabel
end

function GLOG.SetLastActiveTabLabel(label)
    if not label or label == "" then return end
    GLOG.EnsureDB()
    GuildLogisticsUI = GuildLogisticsUI or {}
    GuildLogisticsUI.lastTabLabel = tostring(label)
end

-- =========================
-- ====== MODE (UI) ========
-- =========================

-- Persisted account-wide per guild in GuildLogisticsShared.guilds[guildKey].uiModeByUID[uid]
-- Values: "guild" | "standalone" | nil (unset → triggers first-run chooser)
function GLOG.GetMode()
    -- IMPORTANT: do NOT call EnsureDB here to avoid recursion, since EnsureDB consults GetMode.
    -- Read raw shared bucket directly; store by unique UID for the character
    local Shared = _G.GuildLogisticsShared or { guilds = {} }
    Shared.guilds = Shared.guilds or {}
    -- IMPORTANT: if we created a fresh table, persist it back to the global so SavedVariables exists
    _G.GuildLogisticsShared = Shared
    -- Compute identifiers for this character: prefer GUID; also compute name-realm as fallback/binding key
    local guid = (UnitGUID and UnitGUID("player")) or ""
    local pname = (UnitName and UnitName("player")) or "?"
    local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
    local nameKey = (realm ~= "" and (pname.."-"..realm)) or pname
    local uid = (guid and guid ~= "") and guid or nameKey
    -- Resolve base guild bucket key (mode-independent) to store/read uiModeByUID
    local gname = (GetGuildInfo and GetGuildInfo("player")) or nil
    local guildKey = (function()
        if not gname or gname == "" then return "__noguild__" end
        local k = tostring(gname):gsub("%s+",""):gsub("'",""):lower()
        return k
    end)()
    local bucket = Shared.guilds[guildKey]
    if not bucket then
        bucket = {}
        Shared.guilds[guildKey] = bucket
    end
    bucket.uiModeByUID = bucket.uiModeByUID or {}

    -- Read per-UID mode from shared per-guild bucket
    -- Try both GUID and nameKey to be robust across early/late availability
    local m = bucket.uiModeByUID[guid] or bucket.uiModeByUID[nameKey]

    -- Fallback 1: legacy shorthand at bucket level
    if m == nil and (bucket.uiMode == "guild" or bucket.uiMode == "standalone") then
        m = bucket.uiMode
        bucket.uiModeByUID[uid] = m
    end

    -- Fallback 2: migrate from __noguild__ bucket if it was written before guild info became available
    if m == nil and guildKey ~= "__noguild__" then
        local noGuild = Shared.guilds["__noguild__"]
        local by = noGuild and noGuild.uiModeByUID or nil
        local prev = by and (by[guid] or by[nameKey])
        if prev == "guild" or prev == "standalone" then
            -- Promote to current guild bucket under both keys
            if guid and guid ~= "" then bucket.uiModeByUID[guid] = prev end
            bucket.uiModeByUID[nameKey] = prev
            m = prev
            -- optional cleanup: leave old entry intact to be safe; uncomment to remove
            -- by[uid] = nil
        end
    end

    -- Fallback 3: global per-UID mode (guild-agnostic) saved when choice happened while guild was unresolved
    if m == nil then
        Shared.uiModeByUID_Global = Shared.uiModeByUID_Global or {}
        local gprev = Shared.uiModeByUID_Global[guid] or Shared.uiModeByUID_Global[nameKey]
        if gprev == "guild" or gprev == "standalone" then
            if guid and guid ~= "" then bucket.uiModeByUID[guid] = gprev end
            bucket.uiModeByUID[nameKey] = gprev
            m = gprev
        end
    end

    -- Fallback 4: back-compat migration from legacy per-character store
    if m == nil then
        local src = _G.GuildLogisticsUI_Char or _G.GuildLogisticsUI or {}
        local legacy = tostring((src and src.mode) or "")
        if legacy == "guild" or legacy == "standalone" then
            if guid and guid ~= "" then bucket.uiModeByUID[guid] = legacy end
            bucket.uiModeByUID[nameKey] = legacy
            m = legacy
        end
    end
    if m == "guild" or m == "standalone" then return m end
    return nil
end

function GLOG.SetMode(mode)
    if mode ~= "guild" and mode ~= "standalone" then return false end
    -- Write into shared per-guild bucket; store by unique UID so each character can differ
    _G.GuildLogisticsShared = _G.GuildLogisticsShared or { guilds = {} }
    _G.GuildLogisticsShared.guilds = _G.GuildLogisticsShared.guilds or {}
    local gname = (GetGuildInfo and GetGuildInfo("player")) or nil
    local guildKey = (function()
        if not gname or gname == "" then return "__noguild__" end
        local k = tostring(gname):gsub("%s+",""):gsub("'",""):lower()
        return k
    end)()
    local bucket = _G.GuildLogisticsShared.guilds[guildKey]
    if not bucket then bucket = {}; _G.GuildLogisticsShared.guilds[guildKey] = bucket end
    bucket.uiModeByUID = bucket.uiModeByUID or {}

    local guid = (UnitGUID and UnitGUID("player")) or ""
    local uid
    if guid and guid ~= "" then
        uid = guid
    else
        local n = (UnitName and UnitName("player")) or "?"
        local rn = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
        uid = (rn ~= "" and (n.."-"..rn)) or n
    end
    if uid and uid ~= "" then
        bucket.uiModeByUID[uid] = mode
        -- If we don't yet know the guild at selection time, also persist a global per-UID fallback
        if guildKey == "__noguild__" then
            _G.GuildLogisticsShared.uiModeByUID_Global = _G.GuildLogisticsShared.uiModeByUID_Global or {}
            _G.GuildLogisticsShared.uiModeByUID_Global[uid] = mode
        end
    else
        -- Fallback if uid cannot be computed; store a shorthand and a global fallback
        bucket.uiMode = mode
        _G.GuildLogisticsShared.uiModeByUID_Global = _G.GuildLogisticsShared.uiModeByUID_Global or {}
        -- Use name-realm as best-effort key for global map if available
        local n = (UnitName and UnitName("player")) or "?"
        local rn = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
        local key = (rn ~= "" and (n.."-"..rn)) or n
        if key and key ~= "" then _G.GuildLogisticsShared.uiModeByUID_Global[key] = mode end
    end
    return true
end

function GLOG.IsStandaloneMode()
    return (GLOG.GetMode and GLOG.GetMode() == "standalone") or false
end

-- Convenience: should the communication stack be enabled in this session?
function GLOG.ShouldEnableComm()
    -- Only enable when explicitly in guild mode; disabled in standalone or unset (first run)
    local m = GLOG.GetMode and GLOG.GetMode()
    return m == "guild"
end
