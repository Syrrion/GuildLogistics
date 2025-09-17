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
    else
        -- Fallback if uid cannot be computed; store a shorthand and a global fallback
        bucket.uiMode = mode
        -- Use name-realm as best-effort key for global map if available
        local n = (UnitName and UnitName("player")) or "?"
        local rn = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
        local key = (rn ~= "" and (n.."-"..rn)) or n
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

-- =========================
-- === FastSig (lightweight signature) ===
-- Génère une signature numérique rapide pour un tableau séquentiel OU associatif.
-- Usage: comparer deux datasets (ex: ListView) sans faire un deep compare coûteux.
-- Non cryptographique, collisions possibles mais rares sur petits ensembles.
function U.FastSig(t)
    if type(t) ~= "table" then return tostring(t) end
    local acc, c = 0, 1
    for k, v in pairs(t) do
        local vk = type(k)
        if vk == "number" then
            acc = acc + k * 3
        elseif vk == "string" then
            acc = acc + #k * 7
        else
            acc = acc + 11
        end
        local tv = type(v)
        if tv == "number" then
            acc = acc + (v * c)
        elseif tv == "string" then
            acc = acc + (#v * (c + 13))
        elseif tv == "boolean" then
            acc = acc + (v and 97 or 41)
        elseif tv == "table" then
            -- shallow incorporate (no recursion to remain fast)
            local ln = 0
            if v[1] ~= nil then ln = #v end
            acc = acc + ln * 5
        else
            acc = acc + 19
        end
        c = (c + 3) % 17 + 1
    end
    return tostring(acc)
end

-- Signature d'une liste ordonnée (préserve l'ordre)
function U.FastSigArray(arr)
    if type(arr) ~= "table" then return tostring(arr) end
    local acc = 0
    for i = 1, #arr do
        local v = arr[i]
        local tv = type(v)
        if tv == "number" then
            acc = acc * 33 + v
        elseif tv == "string" then
            acc = acc * 33 + #v * 7
        elseif tv == "boolean" then
            acc = acc * 33 + (v and 1 or 0)
        elseif tv == "table" then
            local ln = 0
            if v[1] ~= nil then ln = #v end
            acc = acc * 33 + ln
        else
            acc = acc * 33 + 5
        end
        if acc > 2^53 then acc = acc % 10^9 end -- clamp pour rester dans plage int sûre
    end
    return tostring(acc)
end

-- Combine plusieurs signatures (concat protégée)
function U.CombineSig(...)
    local n = select('#', ...)
    if n == 0 then return '0' end
    local parts = {}
    for i = 1, n do
        parts[i] = tostring(select(i, ...))
    end
    return table.concat(parts, ':')
end

-- =========================
-- == RingQueue (O(1) FIFO) ==
-- Evite table.remove(1) O(n). Politique: overwrite le plus ancien si plein.
function U.NewRingQueue(cap)
    cap = tonumber(cap) or 128
    if cap < 8 then cap = 8 end
    local q = { _cap = cap, _head = 0, _tail = 0, _size = 0, _data = {} }
    function q:clear()
        self._head, self._tail, self._size = 0, 0, 0
    end
    function q:push(v)
        local cap = self._cap
        if self._size >= cap then
            self._head = (self._head + 1) % cap
            self._size = self._size - 1
        end
        self._data[self._tail] = v
        self._tail = (self._tail + 1) % cap
        self._size = self._size + 1
    end
    function q:pop()
        if self._size == 0 then return nil end
        local v = self._data[self._head]
        self._data[self._head] = nil
        self._head = (self._head + 1) % self._cap
        self._size = self._size - 1
        return v
    end
    function q:size() return self._size end
    function q:isEmpty() return self._size == 0 end
    function q:iter()
        local idx, remaining = self._head, self._size
        local cap = self._cap
        return function()
            if remaining <= 0 then return nil end
            local v = self._data[idx]
            idx = (idx + 1) % cap
            remaining = remaining - 1
            return v
        end
    end
    return q
end

-- =========================
-- == Temp Table Pool ==
local _tempPool = {}
function U.AcquireTemp()
    local t = _tempPool[#_tempPool]
    if t then _tempPool[#_tempPool] = nil; return t end
    return {}
end
function U.ReleaseTemp(t)
    if type(t) ~= 'table' then return end
    for k in pairs(t) do t[k] = nil end
    _tempPool[#_tempPool+1] = t
end
function U.PoolStats() return #_tempPool end

-- =========================
-- == Payload Signature (cache hint) ==
function U.PayloadSig(tbl)
    if type(tbl) ~= 'table' then return tostring(tbl) end
    local acc, n = 0, 0
    for k,v in pairs(tbl) do
        n = n + 1
        local tk = type(k)
        if tk == 'string' then acc = acc + #k * 7 elseif tk == 'number' then acc = acc + k * 3 else acc = acc + 11 end
        local tv = type(v)
        if tv == 'string' then acc = acc + #v * 13 elseif tv == 'number' then acc = acc + v * 5 elseif tv == 'boolean' then acc = acc + (v and 97 or 41) else acc = acc + 19 end
    end
    return tostring(acc) .. ':' .. tostring(n)
end

