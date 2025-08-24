local ADDON, ns = ...
local UI = ns.UI or {}; ns.UI = UI
UI.Colors = UI.Colors or {}

-- Crée un badge (fond teinté + gloss centré + ligne médiane + texte)
-- opts: width, font, centeredGloss (true), textShadow (false/true)
function UI.CreateBadgeCell(parent, opts)
    opts = opts or {}
    local h = math.max(20, (UI.ROW_H or 24) - 4)
    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(36, h)

    -- BACKDROP : uniquement la bordure (fond totalement transparent pour ne pas écraser la teinte)
    f:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
        insets = { left=1, right=1, top=1, bottom=1 },
    })
    f:SetBackdropBorderColor(0, 0, 0, 0.90)
    -- (Pas de bgFile; transparency)
    if f.SetBackdropColor then f:SetBackdropColor(0, 0, 0, 0) end

    -- FOND TEINTÉ (la couleur du tier sera appliquée dans _SetTierCell)
    local bg = f:CreateTexture(nil, "ARTWORK")
    bg:SetPoint("TOPLEFT",     f, "TOPLEFT",     1, -1)
    bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1,  1)
    bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    bg:SetVertexColor(0.30, 0.30, 0.30, 1)
    if bg.SetDrawLayer then bg:SetDrawLayer("ARTWORK", 0) end

    -- ANNEAU discret façon quickslot (au-dessus du fond)
    local ring = f:CreateTexture(nil, "ARTWORK")
    ring:SetPoint("CENTER", f, "CENTER")
    ring:SetSize(h * 0.9, h * 0.9)
    ring:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    ring:SetAlpha(0.20)
    if ring.SetDrawLayer then ring:SetDrawLayer("ARTWORK", 1) end

    -- GLOSS fin, additif (ne “grise” plus la couleur)
    local gloss = f:CreateTexture(nil, "ARTWORK")
    gloss:SetPoint("TOPLEFT",  f, "TOPLEFT",  1, -1)
    gloss:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    gloss:SetHeight(math.floor(h * 0.50))       -- 50% de la hauteur
    gloss:SetTexture("Interface\\Buttons\\WHITE8x8")
    gloss:SetBlendMode("ADD")
    if gloss.SetGradient and type(CreateColor) == "function" then
        gloss:SetGradient("VERTICAL", CreateColor(1,1,1,0.12), CreateColor(1,1,1,0.00))
    else
        gloss:SetVertexColor(1,1,1,0.08)
    end
    if gloss.SetDrawLayer then gloss:SetDrawLayer("ARTWORK", 2) end

    -- LETTRE DU TIER
    local txt = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    txt:SetPoint("CENTER", f, "CENTER", 0, 0)
    txt:SetText("")

    f.bg, f.txt, f.ring, f.gloss = bg, txt, ring, gloss
    return f
end

-- Applique une couleur et un texte sur un badge
-- rgb: {r,g,b} ou nil ; opts.forceTextColor = {r,g,b}
function UI.SetBadgeCell(cell, rgb, text, opts)
    if not cell or not cell.bg then return end
    opts = opts or {}
    local r, g, b = 0.6, 0.6, 0.6
    if type(rgb) == "table" then
        r, g, b = rgb[1] or 0.6, rgb[2] or 0.6, rgb[3] or 0.6
    end

    if cell.bg.SetColorTexture then cell.bg:SetColorTexture(r, g, b, 1)
    else cell.bg:SetVertexColor(r, g, b, 1) end

    if cell.SetBackdropBorderColor then
        cell:SetBackdropBorderColor(r*0.55, g*0.55, b*0.55, 1)
    end

    if cell.glossTop and cell.glossTop.SetGradient and type(CreateColor) == "function" then
        cell.glossTop:SetGradient("VERTICAL", CreateColor(1,1,1,0.10), CreateColor(1,1,1,0.00))
    end
    if cell.glossBottom and cell.glossBottom.SetGradient and type(CreateColor) == "function" then
        cell.glossBottom:SetGradient("VERTICAL", CreateColor(1,1,1,0.00), CreateColor(1,1,1,0.08))
    end
    if cell.glossMid then cell.glossMid:SetVertexColor(1, 1, 1, 0.10) end

    if cell.txt then
        cell.txt:SetText(text or "")
        if opts.forceTextColor then
            cell.txt:SetTextColor(opts.forceTextColor[1], opts.forceTextColor[2], opts.forceTextColor[3])
        else
            local tr, tg, tb = UI.Colors.AutoTextRGB(r, g, b)
            cell.txt:SetTextColor(tr, tg, tb)
        end
    end
end

-- Spécialisation pour les tiers (réutilise la palette & variant)
function UI.SetTierBadge(cell, tierBase, mod, labelOverride, palette)
    local pal = palette or (UI.Colors and UI.Colors.BIS_TIER_COLORS)
    local base = (pal and pal[tierBase]) or {0.6, 0.6, 0.6}
    local r, g, b = UI.Colors.Variant(base, mod)
    UI.SetBadgeCell(cell, { r, g, b }, labelOverride or tierBase)
end

-- Parse un label de rang type "S", "S+", "A-", etc. -> (base, mod, pretty)
function UI.ParseTierLabel(label)
    local s = tostring(label or "")
    local base = s:match("([SAFBEDCsa fbedc])") -- lettre S..F (insensible à la casse)
    base = base and base:upper() or "?"
    local mod  = s:match("([%+%-])")           -- '+' ou '-'
    local pretty = base .. (mod or "")
    return base, mod, pretty
end
