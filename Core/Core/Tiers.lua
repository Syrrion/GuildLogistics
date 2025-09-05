local ADDON, ns = ...
ns.Util = ns.Util or {}
local U = ns.Util

U.TIER_ORDER = U.TIER_ORDER or { "S", "A", "B", "C", "D", "E", "F" }

-- Décompose une clé de tier ("A+", "B-", "S") en (base, mod, label).
-- 'mod' vaut "plus"/"minus" ou nil ; 'label' est la forme normalisée.
function U.ParseTierKey(key)
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
    local label = (mod == "plus") and (base .. "+") or (mod == "minus" and (base .. "-") or base)
    return base, mod, label
end

-- Renvoie l'indice d'un tier selon 'order' (U.TIER_ORDER par défaut), pour trier facilement.
function U.TierIndex(base, order)
    order = order or U.TIER_ORDER
    if not base or not order then return math.huge end
    for i, v in ipairs(order) do
        if v == base then return i end
    end
    return math.huge
end
