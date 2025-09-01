local ADDON, ns = ...
local UI = ns.UI or {}; ns.UI = UI
UI.Colors = UI.Colors or {}

local function clamp01(x)
    if x < 0 then return 0 elseif x > 1 then return 1 else return x end
end

-- Variante plus claire / plus sombre
function UI.Colors.Variant(rgb, mod)
    local r, g, b = (rgb[1] or 0.6), (rgb[2] or 0.6), (rgb[3] or 0.6)
    if mod == "plus" then
        r = r + (1 - r) * 0.20
        g = g + (1 - g) * 0.20
        b = b + (1 - b) * 0.20
    elseif mod == "minus" then
        r = r * 0.80
        g = g * 0.80
        b = b * 0.80
    end
    return clamp01(r), clamp01(g), clamp01(b)
end

-- Couleur de texte lisible selon la luminance du fond
function UI.Colors.AutoTextRGB(r, g, b)
    local l = 0.2126*r + 0.7152*g + 0.0722*b
    if l >= 0.80 then return 0, 0, 0 else return 1, 1, 1 end
end

-- Couleur par rareté d’objet (WoW API/constantes)
function UI.Colors.QualityRGB(q)
    local r, g, b = 1, 1, 1
    if GetItemQualityColor and q ~= nil then
        r, g, b = GetItemQualityColor(q)
    elseif ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q] then
        local c = ITEM_QUALITY_COLORS[q]; if c then r, g, b = c.r, c.g, c.b end
    end
    return r, g, b
end

-- Palette par défaut pour les tiers BiS (réutilisable partout)
UI.Colors.BIS_TIER_COLORS = UI.Colors.BIS_TIER_COLORS or {
    S = { 1.00, 0.65, 0.10 }, -- légendaire (orange)
    A = { 0.64, 0.21, 0.93 }, -- épique (violet)
    B = { 0.17, 0.52, 0.95 }, -- rare (bleu)
    C = { 0.20, 0.82, 0.30 }, -- peu commun (vert)
    D = { 0.90, 0.90, 0.90 }, -- commun (blanc/gris clair)
    E = { 0.70, 0.70, 0.70 }, -- pauvre (gris)
    F = { 0.40, 0.40, 0.40 }, -- très faible (gris foncé)
}

-- Gris utilisé pour les valeurs hors-ligne / placeholders (légèrement plus sombre qu'avant)
UI.GRAY_OFFLINE      = UI.GRAY_OFFLINE      or { 0.30, 0.30, 0.30 }                 
UI.GRAY_OFFLINE_HEX  = UI.GRAY_OFFLINE_HEX  or (UI.RGBHex and UI.RGBHex(0.45, 0.45, 0.45)) or "999999"

-- =========================
--   Couleurs par Faction/Thème
-- =========================
UI.Colors.FACTION_HEADER = UI.Colors.FACTION_HEADER or {
    ALLIANCE = { 0.17, 0.52, 0.95 }, -- bleu
    HORDE    = { 0.85, 0.20, 0.20 }, -- rouge
    NEUTRAL  = { 0.58, 0.42, 0.18 }, -- brun/parchemin
}

-- Renvoie la couleur d'en-tête selon UI.FRAME_THEME ("AUTO" => faction joueur)
function UI.Colors.GetHeaderRGB()
    local tag = (UI and UI.FRAME_THEME) or "AUTO"
    local key = tostring(tag or "AUTO"):upper()

    if key == "AUTO" then
        local f = (UnitFactionGroup and UnitFactionGroup("player")) or "Neutral"
        key = tostring(f):upper()
    end

    if key ~= "ALLIANCE" and key ~= "HORDE" and key ~= "NEUTRAL" then
        key = "NEUTRAL"
    end
    local rgb = UI.Colors.FACTION_HEADER[key] or UI.Colors.FACTION_HEADER.NEUTRAL
    return rgb[1], rgb[2], rgb[3]
end
