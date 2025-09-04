local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
ns.Util = ns.Util or {}
local GLOG, U = ns.GLOG, ns.Util

-- Renvoie le titre officiel de l'addon (métadonnée TOC), codes couleur retirés.
-- Fallback possible via système de traduction 'ns.Tr'.
function GLOG.GetAddonTitle()
    local title = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Title"))
               or (GetAddOnMetadata and GetAddOnMetadata(ADDON, "Title"))
    if type(title) == "string" and title ~= "" then
        return title:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    end
    local Tr = ns and ns.Tr
    return (Tr and Tr("app_title"))
end

-- Renvoie le chemin/ID d'icône déclaré dans le TOC ; fallback vers une icône générique.
function GLOG.GetAddonIconTexture()
    local icon = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "IconTexture"))
              or (GetAddOnMetadata and GetAddOnMetadata(ADDON, "IconTexture"))
    if type(icon) == "string" and icon ~= "" then
        return icon
    end
    return "Interface\\Icons\\INV_Misc_Book_09"
end

-- Renvoie la version déclarée (string). Utile pour affichage/compat.
function GLOG.GetAddonVersion()
    local v = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(ADDON, "Version"))
           or (GetAddOnMetadata and GetAddOnMetadata(ADDON, "Version"))
           or (ns and ns.Version)
    return tostring(v or "")
end

-- Compare deux versions sémantiques "a.b.c" ; retourne -1 / 0 / 1.
function U.CompareVersions(a, b)
    local function parse(s)
        local out = {}
        for n in tostring(s or ""):gmatch("(%d+)") do out[#out + 1] = tonumber(n) or 0 end
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

-- Lit la révision stockée en DB (GuildLogisticsDB.meta.rev) ou via GLOG.GetRev si défini.
local function getRev()
    if GLOG.GetRev then
        return U.safenum(GLOG.GetRev(), 0)
    end
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.meta = GuildLogisticsDB.meta or {}
    return U.safenum(GuildLogisticsDB.meta.rev, 0)
end

_G.getRev = _G.getRev or getRev
