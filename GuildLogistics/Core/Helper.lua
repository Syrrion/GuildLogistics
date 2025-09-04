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
