local ADDON, ns = ...
ns.Util = ns.Util or {}
local U = ns.Util

-- Retourne (name, icon) pour un sort, compatible 11.x (C_Spell) et versions antérieures.
function U.SpellInfoCompat(idOrName)
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
