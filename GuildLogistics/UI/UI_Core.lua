local ADDON, ns = ...
local Tr = ns and ns.Tr
ns.UI = ns.UI or {}
local UI = ns.UI
local GLOG = ns.GLOG

-- Thème de cadre (NEUTRAL | ALLIANCE | HORDE)
UI.FRAME_THEME = "AUTO"

-- Constantes (prend celles de UI.lua si déjà définies)
UI.ROW_H           = UI.ROW_H           or 10
UI.SECTION_HEADER_H = UI.SECTION_HEADER_H or 26
UI.FONT_YELLOW = UI.FONT_YELLOW or {1, 0.82, 0}
UI.WHITE       = UI.WHITE       or {1,1,1}
UI.ACCENT      = UI.ACCENT      or {0.22,0.55,0.95}

-- Couleur par défaut du libellé des lignes "séparateur" (Joueurs conserve cette couleur)
UI.SEPARATOR_LABEL_COLOR = UI.SEPARATOR_LABEL_COLOR or { 1, 0.95, 0.3 } -- jaune doux

-- Padding (px) ajouté au-dessus des lignes "séparateur" (déjà utilisé)
UI.SEPARATOR_TOP_PAD = UI.SEPARATOR_TOP_PAD or 20

-- Récupère la ScrollBar d'un ScrollFrame "UIPanelScrollFrameTemplate"
function UI.GetScrollBar(scroll)
    if not scroll then return nil end
    local sb = scroll.ScrollBar or scroll.scrollbar
    if (not sb) and scroll.GetName then
        local n = scroll:GetName()
        if n then sb = _G[n .. "ScrollBar"] end
    end
    return sb
end

-- Supprime définitivement les flèches haut/bas et étire la barre sur toute la hauteur
function UI.StripScrollButtons(scrollOrBar)
    local sb = scrollOrBar
    if sb and sb.GetObjectType and sb:GetObjectType() == "ScrollFrame" then
        sb = UI.GetScrollBar(sb)
    end
    if not sb or sb._gl_noArrows then return end

    local parent = sb:GetParent() or sb
    local function strip(btn)
        if not btn then return end
        btn:Hide()
        if btn.EnableMouse then btn:EnableMouse(false) end
        if btn.SetAlpha then btn:SetAlpha(0) end
        if btn.SetSize then btn:SetSize(1, 1) end
        if btn.ClearAllPoints then btn:ClearAllPoints() end
        if not btn._gl_hideHook then
            btn:HookScript("OnShow", function(b) b:Hide() end)
            btn._gl_hideHook = true
        end
    end

    strip(sb.ScrollUpButton)
    strip(sb.ScrollDownButton)

    if sb.ClearAllPoints and sb.SetPoint then
        sb:ClearAllPoints()
        sb:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, 0)
        sb:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
    end

    sb._gl_noArrows = true
end


function UI.GetSeparatorTopPadding()
    local v = tonumber(UI.SEPARATOR_TOP_PAD)
    if not v or v < 0 then v = 0 end
    return v
end

-- === Colonnes: w/min/flex
function UI.ResolveColumns(totalWidth, cols, opts)
    opts = opts or {}
    local SAFE = (UI.SCROLLBAR_W or 20) + (UI.SCROLLBAR_INSET or 0)
    local fixed, flexUnits = 0, 0
    local out = {}

    for i, c in ipairs(cols or {}) do
        local min = c.min or c.w or 80
        local w   = c.w
        if w then
            fixed = fixed + w
            out[i] = { key=c.key, w=w, justify=c.justify, pad=c.pad }
        else
            flexUnits = flexUnits + (c.flex or 0)
            out[i] = { key=c.key, w=min, min=min, flex=c.flex or 0, justify=c.justify, pad=c.pad }
            fixed = fixed + min
        end
    end

    local contentW = totalWidth or 800
    local rem = math.max(0, contentW - fixed)

    if flexUnits > 0 and rem > 0 then
        for _, rc in ipairs(out) do
            if rc.flex and rc.flex > 0 then
                rc.w = rc.min + math.floor(rem * rc.flex / flexUnits + 0.5)
            end
        end
    end

    return out
end

function UI.MinWidthForColumns(cols)
    local sum = 0
    for _, c in ipairs(cols or {}) do
        sum = sum + (c.w or c.min or 80)
    end
    -- léger slack pour le padding visuel du header
    return sum + 8
end

-- ===== Header =====
function UI.CreateHeader(parent, cols)
    local header = CreateFrame("Frame", nil, parent)
    header:SetHeight(24)
    local labels = {}
    for i, c in ipairs(cols or {}) do
        local fs = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetText((Tr and Tr(c.title or "")) or (c.title or Tr("")))
        fs:SetJustifyH(c.justify or "LEFT")
        labels[i] = fs
    end
    return header, labels
end

function UI.LayoutHeader(header, cols, labels)
    local x = 0
    for i, c in ipairs(cols or {}) do
        local w = c.w or c.min or 80
        local fs = labels[i]
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", header, "LEFT", x + 4, 0)
        fs:SetWidth(w - 8)
        fs:SetHeight(24)
        x = x + w
    end
end

-- ===== Row =====
function UI.LayoutRow(row, cols, fields)
    local x = 0
    for _, c in ipairs(cols or {}) do
        local w = c.w or c.min or 80
        local f = fields[c.key]
        if f then
            f:ClearAllPoints()
            f:SetPoint("LEFT", row, "LEFT", x + 4, 0)
            if f.SetWidth  then f:SetWidth(w - 8) end
            if f.SetHeight then f:SetHeight(UI.ROW_H) end
            if f.SetJustifyH and c.justify then f:SetJustifyH(c.justify) end
            -- Empêche le débordement visuel/interaction hors cellule
            if f.SetClipsChildren then pcall(f.SetClipsChildren, f, true) end
            if UI.ApplyCellTruncation then UI.ApplyCellTruncation(f, w - 8) end
        end

        x = x + w
    end
end

-- Déco de base d'une ligne : dégradé vertical + hover + séparateur TOP 1px (pixel-perfect)
-- + liseré gauche (caché par défaut) pour marquer "même groupe"
function UI.DecorateRow(r)
    local st = (UI.GetListViewStyle and UI.GetListViewStyle()) or {
        oddTop={r=.13,g=.13,b=.13,a=.35}, oddBottom={r=.08,g=.08,b=.08,a=.35},
        evenTop={r=.15,g=.15,b=.15,a=.35}, evenBottom={r=.10,g=.10,b=.10,a=.35},
        hover={r=1,g=.82,b=0,a=.06}, sep={r=1,g=1,b=1,a=.20}, accent={r=1,g=.82,b=0,a=.90},
    }
    local WHITE = "Interface\\Buttons\\WHITE8x8"

    -- Fond (gradient appliqué dans UI.ApplyRowGradient)
    local bg = r:CreateTexture(nil, "BACKGROUND", nil, -8)
    bg:SetAllPoints(r)
    bg:SetTexture(WHITE)
    UI.SnapTexture(bg)
    r._bg = bg

    -- Hover (indépendant de l'opacité réglable pour garder la lisibilité)
    local hov = r:CreateTexture(nil, "HIGHLIGHT", nil, 0)
    hov:SetAllPoints(r)
    hov:SetTexture(WHITE)
    hov:SetVertexColor(st.hover.r, st.hover.g, st.hover.b, st.hover.a)
    hov:Hide()
    UI.SnapTexture(hov)
    r._hover = hov

    -- Séparateur haut (1 px)
    local sepTop = r:CreateTexture(nil, "OVERLAY", nil, -1)
    sepTop:SetTexture(WHITE)
    UI.SetPixelThickness(sepTop, 1)
    if PixelUtil and PixelUtil.SetPoint then
        PixelUtil.SetPoint(sepTop, "TOPLEFT",  r, "TOPLEFT",  0, 0)
        PixelUtil.SetPoint(sepTop, "TOPRIGHT", r, "TOPRIGHT", 0, 0)
    else
        sepTop:SetPoint("TOPLEFT",  r, "TOPLEFT",  0, 0)
        sepTop:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, 0)
    end
    sepTop:SetVertexColor(st.sep.r, st.sep.g, st.sep.b, st.sep.a)
    UI.SnapTexture(sepTop)
    r._sepTop = sepTop
    r._sepTopBaseA = st.sep.a or 1  -- 📌 alpha de référence

    -- Liseré gauche (optionnel)
    local acc = r:CreateTexture(nil, "ARTWORK", nil, 1)
    acc:SetTexture(WHITE)
    if PixelUtil and PixelUtil.SetPoint then
        PixelUtil.SetPoint(acc, "TOPLEFT",    r, "TOPLEFT",    0, 0)
        PixelUtil.SetPoint(acc, "BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
    else
        acc:SetPoint("TOPLEFT",    r, "TOPLEFT",    0, 0)
        acc:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
    end
    UI.SetPixelThickness(acc, 2)
    acc:SetVertexColor(st.accent.r, st.accent.g, st.accent.b, st.accent.a)
    acc:Hide()
    r._accentLeft = acc

    -- Séparateur bas (facultatif)
    local sepBot = r:CreateTexture(nil, "OVERLAY", nil, -1)
    sepBot:SetTexture(WHITE)
    UI.SetPixelThickness(sepBot, 1)
    sepBot:SetPoint("BOTTOMLEFT",  r, "BOTTOMLEFT",  0, 0)
    sepBot:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
    local botA = (st.sep.a or 1) * .55
    sepBot:SetVertexColor(st.sep.r, st.sep.g, st.sep.b, botA)
    r._sepBot = sepBot
    r._sepBotBaseA = botA       -- 📌 alpha de référence

    -- Dégradé pair/impair initial
    if UI.ApplyRowGradient then UI.ApplyRowGradient(r, true) end
    r._isEven   = true
    if r._alphaMul == nil then r._alphaMul = 1 end

    -- Première quantification (au cas où Layout ne soit pas encore passé)
    UI.SnapRegion(r)
    if r._sepTop then UI.SetPixelThickness(r._sepTop, 1) end
end


-- Applique le dégradé vertical pair/impair sur la texture de fond d'une ligne
function UI.ApplyRowGradient(row, isEven)
    if not (row and row._bg) then return end
    local st = (UI.GetListViewStyle and UI.GetListViewStyle()) or {}
    local top    = (isEven and (st.evenTop or st.even)) or (st.oddTop or st.odd)
    local bottom = (isEven and (st.evenBottom or st.even)) or (st.oddBottom or st.odd)
    if not (top and bottom) then return end

    -- 🔸 Multiplicateur d’alpha par ligne (utilisé par le "popup léger")
    local mul = tonumber(row._alphaMul or 1) or 1
    if mul < 0 then mul = 0 elseif mul > 1 then mul = 1 end

    local tex = row._bg
    tex:SetTexture("Interface\\Buttons\\WHITE8x8") -- sécurité

    -- Retail 11.x : SetGradient(Color, Color) ; fallback : SetGradientAlpha
    if tex.SetGradient and type(CreateColor) == "function" then
        tex:SetGradient("VERTICAL",
            CreateColor(top.r, top.g, top.b, (top.a or 1) * mul),
            CreateColor(bottom.r, bottom.g, bottom.b, (bottom.a or 1) * mul)
        )
    elseif tex.SetGradientAlpha then
        tex:SetGradientAlpha("VERTICAL",
            top.r or 1, top.g or 1, top.b or 1, (top.a or 1) * mul,
            bottom.r or 1, bottom.g or 1, bottom.b or 1, (bottom.a or 1) * mul
        )
    end
end

-- API : contrôle du liseré gauche (même groupe)
function UI.SetRowAccent(row, shown, r, g, b, a)
    if not row then return end
    local acc = row._accentLeft
    if not acc then
        UI.DecorateRow(row) ; acc = row._accentLeft
    end
    if not acc then return end
    if r and g and b then
        acc:SetVertexColor(tonumber(r) or 1, tonumber(g) or .82, tonumber(b) or 0, tonumber(a) or .9)
    end
    acc:SetShown(shown and true or false)
end

function UI.SetRowAccentGradient(row, shown, r, g, b, startAlpha)
    -- Applique/masque un dégradé horizontal sur toute la ligne,
    -- destiné à compléter le liseré "même groupe".
    -- startAlpha par défaut ~0.50 pour respecter la demande (50% -> 0%).
    if not row then return end
    local sa = tonumber(startAlpha) or 0.50

    -- Crée la texture si nécessaire
    local grad = row._accentGrad
    if not grad then
        -- On la place dans le BACKGROUND, au-dessus du fond mais
        -- sans gêner le hover et les textes (qui sont en OVERLAY).
        -- NB: le fond de ligne a de l’opacité, donc ce grad reste visible.
        grad = row:CreateTexture(nil, "BACKGROUND", nil, -6)
        row._accentGrad = grad
        grad:ClearAllPoints()
        grad:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        grad:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        grad:SetTexture("Interface\\Buttons\\WHITE8x8")
        if UI.SnapTexture then UI.SnapTexture(grad) end
    end

    -- Couleur et dégradé (HORIZONTAL, sa -> 0)
    r, g, b = tonumber(r) or 1, tonumber(g) or .82, tonumber(b) or 0
    if grad.SetGradient and type(CreateColor) == "function" then
        grad:SetGradient("HORIZONTAL",
            CreateColor(r, g, b, sa),
            CreateColor(r, g, b, 0)
        )
    elseif grad.SetGradientAlpha then
        grad:SetGradientAlpha("HORIZONTAL",
            r, g, b, sa,
            r, g, b, 0
        )
    else
        grad:SetVertexColor(r, g, b, sa) -- fallback (pas de vrai gradient)
    end

    grad:SetShown(shown and true or false)
end

function UI.CreateScroll(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    local list = CreateFrame("Frame", nil, scroll)
    scroll:SetScrollChild(list)
    list:SetPoint("TOPLEFT")
    list:SetPoint("TOPRIGHT")
    list:SetHeight(1)

    if UI.SkinScrollBar then UI.SkinScrollBar(scroll) end
    if UI.StripScrollButtons then UI.StripScrollButtons(scroll) end

    return scroll, list
end

function UI.SectionHeader(parent, title, opts)
    opts = opts or {}
    local padL  = tonumber(opts.padLeft) or 0
    local padR  = tonumber(opts.padRight) or 0
    local topPad= tonumber(opts.topPad) or 0

    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("TOPLEFT",  parent, "TOPLEFT",  padL, -(topPad + 2))
    fs:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -padR, -(topPad + 2))
    fs:SetJustifyH("LEFT")
    fs:SetText((Tr and Tr(title or "")) or tostring(title or ""))

    local sep = parent:CreateTexture(nil, "BORDER")
    sep:SetColorTexture(1, 1, 1, 0.08)
    sep:SetPoint("TOPLEFT",  fs, "BOTTOMLEFT",  0, -4)
    sep:SetPoint("TOPRIGHT", fs, "BOTTOMRIGHT", 0, -4)
    sep:SetHeight(1)

    return UI.SECTION_HEADER_H
end

-- ➕ Cadre à bordure qui englobe un contenu avec padding
function UI.PaddedBox(parent, opts)
    opts = opts or {}
    local outerPad = tonumber(opts.outerPad or UI.OUTER_PAD or 16)
    local pad      = tonumber(opts.pad or 12)

    -- Cadre visuel avec bordure
    local box = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    box:SetPoint("TOPLEFT",     parent, "TOPLEFT",     outerPad, -outerPad)
    box:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -outerPad,  outerPad)
    box:SetBackdrop({
        bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    box:SetBackdropColor(0, 0, 0, 0.25)
    box:SetBackdropBorderColor(0.2, 0.2, 0.2, 0.9)

    -- Sous-conteneur avec padding interne
    local content = CreateFrame("Frame", nil, box)
    content:SetPoint("TOPLEFT",     box, "TOPLEFT",     pad, -pad)
    content:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -pad,  pad)

    return box, content
end

-- Cadre utile pour le contenu
function UI.CreateMainContainer(frame, opts)
    cadre = frame
    opts = opts or {}
    local parent = frame:GetParent()
    local skin   = parent and parent._cdzNeutral
    local L,R,T,B = 0,0,0,0

    if skin and skin.GetInsets then
        L,R,T,B = skin:GetInsets()
    end

    local footerH = 36
    if(opts.footer and opts.footer == true) then
        footer = UI.CreateFooter(frame, footerH)
    else
        footerH = 0
        footer = nil
    end

    cadre:ClearAllPoints()
    cadre:SetPoint("TOPLEFT",     parent, "TOPLEFT",     L + UI.OUTER_PAD + UI.LEFT_PAD_BAR, -(T + UI.OUTER_PAD + UI.TOP_PAD))
    cadre:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -(R + UI.OUTER_PAD + UI.RIGHT_PAD), B + UI.OUTER_PAD + UI.BOTTOM_PAD + footerH )

    container = CreateFrame("Frame", nil, cadre)
    container:ClearAllPoints()
    container:SetPoint("TOPLEFT",     cadre, "TOPLEFT",     UI.INNER_PAD, -(UI.INNER_PAD))
    container:SetPoint("BOTTOMRIGHT", cadre, "BOTTOMRIGHT", -(UI.INNER_PAD),  UI.INNER_PAD)

    return container, footer, footerH
end

-- Normalisation légère des colonnes (justif/tailles par type)
function UI.NormalizeColumns(cols)
    local out = {}
    for i, c in ipairs(cols or {}) do
        local cc = {}
        for k,v in pairs(c) do cc[k]=v end
        local key  = tostring(cc.key or "")
        local tit  = cc.title or cc.key or ""
        cc.min = cc.min or cc.w or 80

        if key=="act" then
            cc.justify = cc.justify or "CENTER"
            cc.w = cc.w or 200
        elseif key=="qty" or key=="count" then
            cc.justify = cc.justify or "CENTER"
        elseif key=="amount" or key=="total" or key=="per" or key=="solde" then
            cc.justify = cc.justify or "RIGHT"
        else
            cc.justify = cc.justify or "LEFT"
        end
        cc.title = tit
        out[i] = cc
    end
    return out
end

-- Création standard d'un FontString (réduit le boilerplate)
function UI.Label(parent, opts)
    opts = opts or {}
    local layer    = opts.layer    or "OVERLAY"
    local template = opts.template or "GameFontHighlight"
    local fs = parent:CreateFontString(nil, layer, template)
    if opts.justify then fs:SetJustifyH(opts.justify) end
    if opts.color and fs.SetTextColor then
        local c = opts.color
        fs:SetTextColor(c[1] or 1, c[2] or 1, c[3] or 1)
    end
    return fs
end

-- === Texte tronqué à la largeur (…)
-- Utilitaires UTF-8 (évite de couper en plein milieu d'un caractère accentué)
local function _utf8_iter(s)
    return string.gmatch(tostring(s or ""), "[%z\1-\127\194-\244][\128-\191]*")
end

local function _utf8_sub(s, codepoints)
    if not s or codepoints <= 0 then return "" end
    local out, n = {}, 0
    for ch in _utf8_iter(s) do
        n = n + 1
        out[n] = ch
        if n >= codepoints then break end
    end
    return table.concat(out, "")
end

-- Mesure de texte en copiant la police d'un FontString donné
function UI._MeasureStringWidthLike(fs, text)
    UI._MEASURE_FS = UI._MEASURE_FS or UIParent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    local m = UI._MEASURE_FS
    m:Hide()
    local file, size, flags = fs:GetFont()
    if file and size then m:SetFont(file, size, flags) end
    local fo = fs:GetFontObject()
    if fo then m:SetFontObject(fo) end
    m:SetText(tostring(text or ""))
    return m:GetStringWidth() or 0
end

-- Tronque proprement en conservant un éventuel |c...|r
function UI.TruncateTextToWidth(fs, fullText, maxWidth)
    local text = tostring(fullText or "")
    if maxWidth == nil or maxWidth <= 0 then return "" end
    -- Si chaînes spéciales (textures), ne pas tenter de tronquer automatiquement
    if string.find(text, "|T") then return text end

    -- Conserver enveloppe de couleur si présente
    local color = string.match(text, "^|c(%x%x%x%x%x%x%x%x)")
    local inner = text
    local hasClose = false
    if color then
        if string.sub(text, -2) == "|r" then
            inner = string.sub(text, 11, -3) -- après |cXXXXXXXX et avant |r
            hasClose = true
        else
            color = nil
        end
    end

    -- Déjà assez court ?
    local w = UI._MeasureStringWidthLike(fs, inner)
    if w <= maxWidth then
        return text
    end

    local ell = "…"
    local lo, hi = 0, 0
    for _ in _utf8_iter(inner) do hi = hi + 1 end
    if hi <= 1 then
        return (color and ("|c"..color..ell..(hasClose and "|r" or "")) or ell)
    end

    -- Recherche dichotomique du nombre max de glyphes avec "…"
    local best = 0
    while lo <= hi do
        local mid = math.floor((lo + hi) / 2)
        local cand = _utf8_sub(inner, mid) .. ell
        local cw = UI._MeasureStringWidthLike(fs, cand)
        if cw <= maxWidth then
            best = mid
            lo = mid + 1
        else
            hi = mid - 1
        end
    end

    local trimmed = _utf8_sub(inner, math.max(best, 0)) .. ell
    if color then
        return "|c" .. color .. trimmed .. (hasClose and "|r" or "")
    else
        return trimmed
    end
end

-- Applique la troncature à une "cellule" (FontString direct, ou frame avec .text)
function UI.ApplyCellTruncation(cell, availWidth)
    if cell and cell._noTruncation then return end
    if not cell or not availWidth or availWidth <= 0 then return end

    -- Trouve la cible texte
    local target = nil
    if type(cell.GetObjectType) == "function" and cell:GetObjectType() == "FontString" then
        target = cell
    elseif type(cell.GetObjectType) == "function" then
        if cell.text and type(cell.text.GetObjectType) == "function" and cell.text:GetObjectType() == "FontString" then
            target = cell.text
        elseif cell.GetFontString and type(cell.GetFontString) == "function" then
            local fs = cell:GetFontString()
            if fs and fs.GetObjectType and fs:GetObjectType() == "FontString" then target = fs end
        end
    end
    if not target then return end

    -- Désactive le word wrap et limite à 1 ligne
    if target.SetWordWrap then pcall(target.SetWordWrap, target, false) end
    if target.SetMaxLines then pcall(target.SetMaxLines, target, 1) end

    -- Hook SetText pour mémoriser le texte "complet"
    if not target._origSetText then
        target._origSetText = target.SetText
        target.SetText = function(self, s)
            self._fullText = tostring(s or "")
            return self:_origSetText(self._fullText)
        end
    end

    local full = target._fullText or (target.GetText and target:GetText()) or ""
    local show = UI.TruncateTextToWidth(target, full, availWidth)
    if target._origSetText then
        target:_origSetText(show)
    else
        target:SetText(show)
    end
end

-- Footer générique attaché au bas d’un panel
function UI.CreateFooter(parent, height)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(height or UI.FOOTER_H or 36)
    f:SetPoint("BOTTOMLEFT",  parent, "BOTTOMLEFT",  -UI.OUTER_PAD - 2, -(UI.OUTER_PAD + UI.INNER_PAD + height))
    f:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", (UI.INNER_PAD), 0) -- pleine largeur

    -- ✅ Toujours au-dessus du contenu (z-order)
    if f.SetFrameStrata then
        local pstrata = (parent.GetFrameStrata and parent:GetFrameStrata()) or "MEDIUM"
        f:SetFrameStrata(pstrata)
    end
    if f.SetFrameLevel and parent.GetFrameLevel then
        pcall(f.SetFrameLevel, f, (parent:GetFrameLevel() or 0) + 20)
    end

    -- Fond sombre (zone d'action)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    local c  = UI.FOOTER_BG or {0, 0, 0, 0.35}
    bg:SetColorTexture(c[1], c[2], c[3], c[4])
    bg:SetAllPoints(f)


    -- Léger dégradé vertical pour du relief
    local grad = f:CreateTexture(nil, "BACKGROUND")
    grad:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    grad:SetAllPoints(f)
    local gt = UI.FOOTER_GRAD_TOP    or {1, 1, 1, 0.05}
    local gb = UI.FOOTER_GRAD_BOTTOM or {0, 0, 0, 0.15}
    if grad.SetGradient then
        grad:SetGradient("VERTICAL", CreateColor(gt[1], gt[2], gt[3], gt[4]), CreateColor(gb[1], gb[2], gb[3], gb[4]))
    elseif grad.SetGradientAlpha then
        grad:SetGradientAlpha("VERTICAL", gt[1], gt[2], gt[3], gt[4], gb[1], gb[2], gb[3], gb[4])
    end

    -- Liseré supérieur (séparation nette)
    local line = f:CreateTexture(nil, "BORDER")
    local lb = UI.FOOTER_BORDER or {1, 1, 1, 0.12}
    line:SetColorTexture(lb[1], lb[2], lb[3], lb[4])
    line:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 1)
    line:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 1)
    line:SetHeight(1)

    return f
end

-- ➕ Cellule standard "Objet" avec icône + texte + tooltip
function UI.CreateItemCell(parent, opts)
    opts = opts or {}
    local size = opts.size or 20
    local width = opts.width or 240

    local frame = CreateFrame("Frame", nil, parent)
    frame:SetHeight(UI.ROW_H)

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(size, size)
    icon:SetPoint("LEFT", frame, "LEFT", 0, 0)

    local btn = CreateFrame("Button", nil, frame)
    btn:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    btn:SetSize(width, UI.ROW_H)

    local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetJustifyH("LEFT")
    text:SetPoint("LEFT", btn, "LEFT", 0, 0)

    btn:SetScript("OnEnter", function(self)
        if self._itemID and self._itemID > 0 then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self._itemID)
        elseif self._link then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self._link)
        end
    end)
    btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    frame.icon = icon
    frame.text = text
    frame.btn  = btn

    return frame
end

-- ➕ Setter pour remplir une cellule d’objet
function UI.SetItemCell(cell, item)
    if not cell or not item then return end

    -- 1) Résolution robuste de l'itemID (prend item.itemID, puis itemLink numérique, puis "item:12345")
    local itemID = tonumber(item.itemID)
    if not itemID then
        if type(item.itemLink) == "number" then
            itemID = tonumber(item.itemLink)
        elseif type(item.itemLink) == "string" then
            local idstr = string.match(item.itemLink, "^item:(%d+)")
            if idstr then itemID = tonumber(idstr) end
        end
    end

    -- 2) Résolution du lien (préférer GetItemInfo; sinon garder un lien texte complet s'il existe)
    local link = nil
    if itemID and GetItemInfo then
        link = select(2, GetItemInfo(itemID))
    end
    if not link and type(item.itemLink) == "string" and string.find(item.itemLink, "|Hitem:") then
        link = item.itemLink
    end

    -- 3) Nom affiché
    local name = item.itemName
    if not name and type(link) == "string" then
        name = string.match(link, "%[(.-)%]") -- extrait le nom entre crochets
    end
    if not name and itemID and GetItemInfo then
        name = select(1, GetItemInfo(itemID))
    end
    if not name then
        name = "Objet #" .. tostring(itemID or "?")
    end

    -- 4) Icône
    local icon = (itemID and GetItemIcon and GetItemIcon(itemID)) or "Interface/Icons/INV_Misc_QuestionMark"

    -- 5) Remplissage de la cellule + données tooltip
    cell.icon:SetTexture(icon)
    cell.text:SetText(name or "")
    cell.btn._itemID = itemID           -- SetItemByID sera utilisé si présent
    cell.btn._link   = (type(link)=="string") and link or nil -- fallback Hyperlink si pas d'ID
end

-- == Badge cell (generic): colored badge with gloss + optional medal texture ==
function UI.CreateBadgeCell(parent, opts)
    opts = opts or {}
    local w   = tonumber(opts.width)  or 36
    local h   = tonumber(opts.height) or math.max(20, (UI.ROW_H or 24) - 4)

    local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    f:SetSize(w, h)

    -- border + dark base
    f:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        tile = false, edgeSize = 1,
        insets = { left = 1, right = 1, top = 1, bottom = 1 },
    })
    f:SetBackdropColor(0.10, 0.10, 0.10, 1)
    f:SetBackdropBorderColor(0, 0, 0, 0.90)

    -- colored fill (inset)
    local fill = f:CreateTexture(nil, "BACKGROUND")
    fill:SetPoint("TOPLEFT",     f, "TOPLEFT",     1, -1)
    fill:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -1,  1)
    fill:SetTexture("Interface\\Buttons\\WHITE8x8")
    fill:SetVertexColor(0.20, 0.20, 0.20, 1)

    -- decorative ring (subtle WoW feel)
    local medal = f:CreateTexture(nil, "ARTWORK")
    medal:SetPoint("CENTER", f, "CENTER", 0, 0)
    medal:SetSize(h * 0.9, h * 0.9)
    medal:SetTexture("Interface\\Buttons\\UI-Quickslot2")
    medal:SetAlpha(0.18)

    -- top gloss
    local gloss = f:CreateTexture(nil, "OVERLAY")
    gloss:SetPoint("TOPLEFT",  f, "TOPLEFT",  1, -1)
    gloss:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
    gloss:SetHeight(math.floor(h * 0.55))
    gloss:SetTexture("Interface\\Buttons\\WHITE8x8")
    if gloss.SetGradient and type(CreateColor) == "function" then
        gloss:SetGradient("VERTICAL",
            CreateColor(1,1,1,0.18),
            CreateColor(1,1,1,0.02)
        )
    else
        gloss:SetVertexColor(1,1,1,0.08)
    end

    -- label
    local lbl = f:CreateFontString(nil, "OVERLAY", opts.font or "GameFontNormalLarge")
    lbl:SetPoint("CENTER", f, "CENTER", 0, 0)
    lbl:SetJustifyH("CENTER")
    lbl:SetText("")
    lbl:SetShadowColor(0,0,0,0.9)
    lbl:SetShadowOffset(1, -1)

    f._fill  = fill
    f._medal = medal
    f._label = lbl

    return f
end

-- Helper: apply +/- variants on a base RGB
function UI.GetVariantColor(base, mod)
    local r,g,b = (base and base[1] or 0.6), (base and base[2] or 0.6), (base and base[3] or 0.6)
    local factor = 1
    if mod == "plus" then
        factor = 1.16
    elseif mod == "doubleplus" then
        factor = 1.32
    elseif mod == "minus" then
        factor = 0.88
    end
    r, g, b = r * factor, g * factor, b * factor
    -- clamp [0,1]
    r = (r < 0 and 0) or (r > 1 and 1) or r
    g = (g < 0 and 0) or (g > 1 and 1) or g
    b = (b < 0 and 0) or (b > 1 and 1) or b
    return r, g, b
end

-- Fill a badge cell using a tier definition (base letter + optional mod, label override)
-- colors: table of base colors, ex: UI.BIS_TIER_COLORS
function UI.SetTierBadge(cell, tierBase, mod, labelOverride, colors)
    if not cell then return end
    local colorKey = tierBase or "?"
    local base = (colors and colors[colorKey]) or {0.6, 0.6, 0.6}
    local r, g, b = UI.GetVariantColor(base, mod)

    if cell._fill then
        if cell._fill.SetColorTexture then
            cell._fill:SetColorTexture(r, g, b, 1)
        else
            cell._fill:SetVertexColor(r, g, b, 1)
        end
    end

    if cell._label then
        cell._label:SetText(labelOverride or tierBase or "?")
        -- black/white depending on luminance for readability
        local luma = 0.2126*r + 0.7152*g + 0.0722*b
        if luma >= 0.80 then
            cell._label:SetTextColor(0, 0, 0, 1)
        else
            cell._label:SetTextColor(1, 1, 1, 1)
        end
    end

    -- subtle ring intensity by rank (S a bit brighter)
    if cell._medal then
        cell._medal:SetTexture("Interface\\Buttons\\UI-Quickslot2")
        cell._medal:SetAlpha((tierBase == "S" and 0.28) or (tierBase == "A" and 0.22) or 0.18)
    end
end


-- ➕ Pastille (badge) réutilisable
UI.BADGE_BG       = UI.BADGE_BG       or {0.92, 0.22, 0.22, 1.0}  -- rouge un peu plus saturé
UI.BADGE_TEXT     = UI.BADGE_TEXT     or "GameFontWhiteSmall"
UI.BADGE_INSET_X  = UI.BADGE_INSET_X  or 6
UI.BADGE_OFFSET_X = UI.BADGE_OFFSET_X or -6
UI.BADGE_OFFSET_Y = UI.BADGE_OFFSET_Y or  6
UI.BADGE_MAX      = UI.BADGE_MAX      or 99
UI.BADGE_SHADOW_A = UI.BADGE_SHADOW_A or 0.35                     -- ombre portée pour le contraste

function UI.AttachBadge(frame)
    if frame._badge then return frame._badge end
    local b = CreateFrame("Frame", nil, frame)
    b:SetFrameStrata(frame:GetFrameStrata() or "MEDIUM")
    b:SetFrameLevel((frame:GetFrameLevel() or 0) + 10)
    -- Ancrage par défaut : coin haut-droit (compatibilité avec les usages existants)
    b:SetPoint("TOPRIGHT", frame, "TOPRIGHT", UI.BADGE_OFFSET_X, UI.BADGE_OFFSET_Y)
    b:Hide()

    -- Ombre circulaire (pour le contraste)
    b.shadow = b:CreateTexture(nil, "BACKGROUND")
    b.shadow:SetColorTexture(0, 0, 0, UI.BADGE_SHADOW_A)

    -- Fond de la pastille
    b.bg = b:CreateTexture(nil, "ARTWORK")
    local c = UI.BADGE_BG
    b.bg:SetColorTexture(c[1], c[2], c[3], c[4])

    -- Masque circulaire commun (même masque pour ombre + fond)
    if b.CreateMaskTexture and b.bg.AddMaskTexture then
        local mask = b:CreateMaskTexture(nil, "BACKGROUND")
        mask:SetTexture("Interface/CHARACTERFRAME/TempPortraitAlphaMask") -- masque rond natif
        mask:SetAllPoints(b)
        b.bg.AddMaskTexture(b.bg, mask)
        b.shadow.AddMaskTexture(b.shadow, mask)
        b._mask = mask
    end

    -- Texte lisible (blanc + ombre)
    b.txt = b:CreateFontString(nil, "OVERLAY", UI.BADGE_TEXT)
    b.txt:SetPoint("CENTER", b, "CENTER")
    if b.txt.SetTextColor   then b.txt:SetTextColor(1, 1, 1) end
    if b.txt.SetShadowColor then b.txt:SetShadowColor(0, 0, 0, 0.9) end
    if b.txt.SetShadowOffset then b.txt:SetShadowOffset(1, -1) end

    -- API publique
    function b:SetCount(n)
        local v = tonumber(n) or 0
        if v <= 0 then self:Hide(); return end

        local max = UI.BADGE_MAX or 99
        if v > max then
            self.txt:SetText(max .. "+")
        else
            self.txt:SetText(v)
        end

        -- Taille en fonction du contenu (pastille circulaire)
        local pad = UI.BADGE_INSET_X
        local w = math.ceil(self.txt:GetStringWidth()) + pad * 2
        local h = math.ceil(self.txt:GetStringHeight()) + 2
        local d = math.max(16, w, h)
        self:SetSize(d, d)

        self.bg:ClearAllPoints()
        self.bg:SetAllPoints(self)

        self.shadow:ClearAllPoints()
        self.shadow:SetPoint("CENTER", self, "CENTER", 0, 0)
        self.shadow:SetSize(d + 3, d + 3)

        self:Show()
    end

    -- ✅ Nouvelle API : re-ancrage pratique (pour aligner la pastille sur un texte)
    function b:AnchorTo(target, point, relativePoint, xOff, yOff)
        if not (target and target.GetObjectType) then return end
        self:ClearAllPoints()
        self:SetPoint(point or "LEFT", target, relativePoint or "RIGHT", xOff or 8, yOff or 0)
    end

    frame._badge = b
    return b
end

-- ➕ Icône d'état générique (petit point circulaire coloré)
-- Usage : local ico = UI.AttachStateIcon(btn); ico:AnchorTo(btn.txt, "LEFT", "RIGHT", 8, 0); ico:SetOn(true)
function UI.AttachStateIcon(frame, opts)
    if frame._stateIcon then return frame._stateIcon end
    opts = opts or {}
    local size = tonumber(opts.size) or 12
    local color = opts.color or {0.92, 0.22, 0.22, 1.0} -- rouge par défaut

    local f = CreateFrame("Frame", nil, frame)
    f:SetFrameStrata(frame:GetFrameStrata() or "MEDIUM")
    f:SetFrameLevel((frame:GetFrameLevel() or 0) + 10)
    f:SetSize(size, size)
    f:Hide()

    -- Ombre légère
    f.shadow = f:CreateTexture(nil, "BACKGROUND")
    f.shadow:SetColorTexture(0, 0, 0, UI.BADGE_SHADOW_A or 0.35)

    -- Disque coloré
    f.dot = f:CreateTexture(nil, "ARTWORK")
    f.dot:SetColorTexture(color[1], color[2], color[3], color[4])

    -- Masque circulaire (pour un vrai disque)
    if f.CreateMaskTexture and f.dot.AddMaskTexture then
        local mask = f:CreateMaskTexture(nil, "BACKGROUND")
        mask:SetTexture("Interface/CHARACTERFRAME/TempPortraitAlphaMask")
        mask:SetAllPoints(f)
        f.dot.AddMaskTexture(f.dot, mask)
        f.shadow.AddMaskTexture(f.shadow, mask)
        f._mask = mask
    end

    -- API
    function f:SetOn(on)
        if on then
            self.shadow:ClearAllPoints()
            self.shadow:SetPoint("CENTER", self, "CENTER", 0, 0)
            self.shadow:SetSize(size + 3, size + 3)
            self.dot:ClearAllPoints()
            self.dot:SetAllPoints(self)
            self:Show()
        else
            self:Hide()
        end
    end

    function f:AnchorTo(target, point, relativePoint, xOff, yOff)
        if not (target and target.GetObjectType) then return end
        self:ClearAllPoints()
        self:SetPoint(point or "LEFT", target, relativePoint or "RIGHT", xOff or 8, yOff or 0)
    end

    frame._stateIcon = f
    return f
end

-- Nom + icône de classe
function UI.CreateNameTag(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(16,16)
    f.icon:SetPoint("LEFT", f, "LEFT", 0, 0)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.text:SetJustifyH("LEFT")
    f.text:SetPoint("LEFT", f.icon, "RIGHT", 3, 0) -- padding réduit
    f.text:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    return f
end

function UI.SetNameTag(tag, name)
    if not tag then return end

    -- Résoudre le "Nom-Royaume" à partir du cache de guilde (pas d'ajout arbitraire du royaume local)
    local display = (GLOG and GLOG.ResolveFullName and GLOG.ResolveFullName(name)) or tostring(name or "")

    local class, r, g, b, coords = nil, 1, 1, 1, nil
    if GLOG and GLOG.GetNameStyle then class, r, g, b, coords = GLOG.GetNameStyle(display) end

    if tag.text then
        tag.text:SetText(display or "")
        tag.text:SetTextColor(r or 1, g or 1, b or 1)
    end

    if tag.icon and coords then
        tag.icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CharacterCreate-Classes")
        tag.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        tag.icon:Show()
    elseif tag.icon then
        tag.icon:SetTexture(nil)
        tag.icon:Hide()
    end
end

-- ✅ Nouveau : même rendu (couleur/icone) mais sans le "-Royaume" dans le texte
function UI.SetNameTagShort(tag, name)
    if not tag then return end
    local display = (GLOG and GLOG.ResolveFullName and GLOG.ResolveFullName(name)) or tostring(name or "")
    local short   = (ns and ns.Util and ns.Util.ShortenFullName and ns.Util.ShortenFullName(display)) or display

    local class, r, g, b, coords = nil, 1, 1, 1, nil
    if GLOG and GLOG.GetNameStyle then class, r, g, b, coords = GLOG.GetNameStyle(display) end

    if tag.text then
        tag.text:SetText(short or "")
        tag.text:SetTextColor(r or 1, g or 1, b or 1)
    end

    if tag.icon and coords then
        tag.icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CharacterCreate-Classes")
        tag.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        tag.icon:Show()
    elseif tag.icon then
        tag.icon:SetTexture(nil)
        tag.icon:Hide()
    end
end

-- ✅ Nouveau : alpha dédié pour les boutons (icônes, textes & états)
function UI.SetButtonAlpha(btn, a)
    if not btn then return end
    a = tonumber(a or 1) or 1
    if a < 0 then a = 0 elseif a > 1 then a = 1 end

    local function SA(t) if t and t.SetAlpha then t:SetAlpha(a) end end
    if btn.GetNormalTexture   then SA(btn:GetNormalTexture())   end
    if btn.GetPushedTexture   then SA(btn:GetPushedTexture())   end
    if btn.GetDisabledTexture then SA(btn:GetDisabledTexture()) end
    if btn.GetHighlightTexture then
        local hl = btn:GetHighlightTexture()
        if hl and hl.SetAlpha then hl:SetAlpha(math.min(1, a + 0.15)) end -- léger bonus de lisibilité
    end

    if btn.Icon and btn.Icon.SetAlpha then btn.Icon:SetAlpha(a) end
    if btn.icon and btn.icon.SetAlpha then btn.icon:SetAlpha(a) end
    if btn.Text and btn.Text.SetAlpha then btn.Text:SetAlpha(a) end
    if btn.text and btn.text.SetAlpha then btn.text:SetAlpha(a) end
end

-- ✅ Nouveau : applique l'alpha “interactif” standard aux contrôles connus d’un conteneur
function UI.ApplyButtonsAlpha(container, a)
    if not container then return end
    if container.close    then UI.SetButtonAlpha(container.close,    a) end
    if container.prevBtn  then UI.SetButtonAlpha(container.prevBtn,  a) end
    if container.nextBtn  then UI.SetButtonAlpha(container.nextBtn,  a) end
    if container.clearBtn then UI.SetButtonAlpha(container.clearBtn, a) end

    -- Parcourt aussi les boutons directement dans le header (popup skinnée, etc.)
    local hdr = container.header
    if hdr and hdr.GetChildren then
        local children = { hdr:GetChildren() }
        for _, c in ipairs(children) do
            if c and c.GetObjectType and c:GetObjectType() == "Button" then
                UI.SetButtonAlpha(c, a)
            end
        end
    end
end

-- 🆕 Variante: affiche le nom sans le serveur tout en conservant la couleur/classe
function UI.SetNameTagShort(tag, name)
    if not tag then return end
    local raw = (GLOG and GLOG.ResolveFullName and GLOG.ResolveFullName(name)) or tostring(name or "")
    local display = (ns and ns.Util and ns.Util.ShortenFullName and ns.Util.ShortenFullName(raw)) or raw

    local class, r, g, b, coords = nil, 1, 1, 1, nil
    if GLOG and GLOG.GetNameStyle then class, r, g, b, coords = GLOG.GetNameStyle(raw) end

    if tag.text then
        tag.text:SetText(display or "")
        tag.text:SetTextColor(r or 1, g or 1, b or 1)
    end

    if tag.icon and coords then
        tag.icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CharacterCreate-Classes")
        tag.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        tag.icon:Show()
    elseif tag.icon then
        tag.icon:SetTexture(nil)
        tag.icon:Hide()
    end
end

-- 🆕 Applique une opacité uniquement sur les textes (FontString) d'un frame et ses enfants
function UI.SetTextAlpha(frame, a)
    a = tonumber(a or 1) or 1
    if a < 0 then a = 0 elseif a > 1 then a = 1 end
    if not frame then return end

    local function apply(fs)
        if fs and fs.GetObjectType and fs:GetObjectType() == "FontString" and fs.SetAlpha then
            fs:SetAlpha(a)
        end
    end

    local regions = { frame:GetRegions() }
    for _, r in ipairs(regions) do apply(r) end

    local function walkChildren(parent)
        local num = parent.GetNumChildren and parent:GetNumChildren() or 0
        for i = 1, num do
            local child = select(i, parent:GetChildren())
            if child then
                local regs = { child:GetRegions() }
                for _, rr in ipairs(regs) do apply(rr) end
                walkChildren(child)
            end
        end
    end
    walkChildren(frame)
end

function UI.ClassIconMarkup(classTag, size)
    if not classTag or not CLASS_ICON_TCOORDS or not CLASS_ICON_TCOORDS[classTag] then return "" end
    local c = CLASS_ICON_TCOORDS[classTag]
    local l, r, t, b = math.floor(c[1]*256), math.floor(c[2]*256), math.floor(c[3]*256), math.floor(c[4]*256)
    local s = tonumber(size) or 14
    return string.format("|TInterface\\GLUES\\CHARACTERCREATE\\UI-CharacterCreate-Classes:%d:%d:0:0:256:256:%d:%d:%d:%d|t", s, s, l, r, t, b)
end

function UI.RaiseCloseButton(btn, owner)
    local f = owner or btn:GetParent()
    btn:SetFrameStrata("TOOLTIP")
    btn:SetFrameLevel((f and f:GetFrameLevel() or 1) + 10)
end

-- ========== UTIL: Format (ex-Format.lua) ==========
ns.Format = ns.Format or {}
do
    local F = ns.Format

    function F.DateTime(ts, fmt)
        local n = tonumber(ts) or 0
        if n > 0 then return date(fmt or "le %H:%M à %d/%m/%Y", n) end
        return tostring(ts or "")
    end

    function F.Date(ts, fmt)
        local n = tonumber(ts) or 0
        if n > 0 then return date(fmt or "le %d/%m/%Y", n) end
        return tostring(ts or "")
    end

    function F.RelativeFromSeconds(sec)
        local n = tonumber(sec); if not n then return "" end
        local s = math.abs(n)
        local d = math.floor(s/86400); s = s%86400
        local h = math.floor(s/3600);  s = s%3600
        local m = math.floor(s/60)
        if d > 0 then return (d.."j "..h.."h") end
        if h > 0 then return (h.."h "..m.."m") end
        return (m.."m")
    end

    function F.LastSeen(days, hours)
        local d = tonumber(days)
        local h = tonumber(hours)

        if d and d <= 0 then
            if h and h > 0 then return h .. " h" else return "≤ 1 h" end
        end

        d = d or 9999
        if d < 1 then
            if h and h > 0 then return h .. " h" else return "≤ 1 h" end
        elseif d < 30 then
            return d .. " j"
        elseif d < 365 then
            return (math.floor(d/30)) .. " mois"
        else
            return (math.floor(d/365)) .. " ans"
        end
    end
end
-- (Fin ex-Format.lua)  :contentReference[oaicite:4]{index=4}

-- ========== MINIMAP (ex-Minimap.lua) ==========
function GLOG.Minimap_Init()
    if GLOG._EnsureDB then GLOG._EnsureDB() end
    GuildLogisticsUI = GuildLogisticsUI or {}
    GuildLogisticsUI.minimap = GuildLogisticsUI.minimap or { hide=false, angle=215 }
    if GuildLogisticsUI.minimap.angle == nil then
        GuildLogisticsUI.minimap.angle = 215
    end
    if GuildLogisticsUI.minimap.hide then return end

    if _G.GLOG_MinimapButton then
        local r = (Minimap:GetWidth() / 2) - 5
        local rad = math.rad(GuildLogisticsUI.minimap.angle or 215)
        _G.GLOG_MinimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * r, math.sin(rad) * r)
        return
    end

    local b = CreateFrame("Button", "GLOG_MinimapButton", Minimap)
    b:SetSize(32, 32)
    b:SetFrameStrata("MEDIUM")
    b:SetMovable(true)
    b:RegisterForDrag("LeftButton")
    b:RegisterForClicks("AnyUp")

    -- Icône centrale (logo uniquement)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture((GLOG.GetAddonIconTexture and GLOG.GetAddonIconTexture("minimap")) or GLOG.ICON_TEXTURE or "Interface\\Icons\\INV_Misc_Book_09")
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", b, "CENTER", 1, 0)
    -- Exposer explicitement l’icône (pour les addons « collecteurs »)
    b.icon = icon

    -- Masque circulaire sur le logo
    local mask = b:CreateMaskTexture()
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)

    -- ➕ Fond blanc circulaire (derrière le logo, non capté par les addons)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(1, 1, 1, 1)
    bg:SetSize(24, 24)
    bg:SetPoint("CENTER", b, "CENTER", 0, 0)
    if b.CreateMaskTexture and bg.AddMaskTexture then
        local bgMask = b:CreateMaskTexture()
        bgMask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask")
        bgMask:SetAllPoints(bg)
        bg:AddMaskTexture(bgMask)
    end
    b._decorBG = bg

    -- ➕ Anneau doré autour (décoratif, séparé de l’icône)
    local ring = b:CreateTexture(nil, "OVERLAY")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    ring:SetSize(60, 60)
    ring:SetPoint("CENTER", b, "CENTER", 12, -12)
    b._decorRing = ring

    -- Survol standard
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    hl:SetBlendMode("ADD")
    hl:SetAllPoints(b)

    -- Tooltip
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        local title = (GLOG.BuildMainTitle and GLOG.BuildMainTitle()) or Tr("app_title")
        GameTooltip:SetText(Tr("app_title"))
        GameTooltip:AddLine("<"..title..">")
        GameTooltip:AddLine(Tr("tooltip_minimap_left"), 1,1,1)
        GameTooltip:AddLine(Tr("tooltip_minimap_drag"), 1,1,1)
        GameTooltip:Show()
    end)

    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Drag (déplacement)
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function(btn)
            local mx, my = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            local dx, dy = (cx/scale - mx), (cy/scale - my)
            local angle = math.deg(math.atan2(dy, dx))
            if angle < 0 then angle = angle + 360 end
            GuildLogisticsUI.minimap.angle = angle
            local r = (Minimap:GetWidth() / 2) - 5
            local rad = math.rad(angle or 215)
            btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * r, math.sin(rad) * r)
        end)
    end)
    b:SetScript("OnDragStop",  function(self) self:SetScript("OnUpdate", nil) end)

    -- Clic : toggle UI
    b:SetScript("OnClick", function() if ns.ToggleUI then ns.ToggleUI() end end)

    local r = (Minimap:GetWidth() / 2) - 5
    local rad = math.rad(GuildLogisticsUI.minimap.angle or 215)
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * r, math.sin(rad) * r)
end
-- (Fin ex-Minimap.lua)  :contentReference[oaicite:5]{index=5}

-- Positionne un titre au centre d’une zone (par ex. bandeau drag)
-- frame  = FontString du titre
-- anchor = zone de référence (souvent le drag invisible)
-- yOffset = décalage vertical manuel (optionnel, défaut -28)
function UI.PositionTitle(frame, anchor, yOffset)
    if not frame or not anchor then return end
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", anchor, "CENTER", 0, yOffset or -28)
end

-- Marges internes standardisées pour éviter que le contenu passe sous les bordures.
UI.SAFE_INSET = UI.SAFE_INSET or { left = 10, right = 10, top = 8, bottom = 10 }

-- Applique deux points (TOPLEFT/BOTTOMRIGHT) avec des insets cohérents.
-- topOffset: décalage vertical supplémentaire (ex: hauteur des filtres).
function UI.SafeInsetPoints(frame, parent, topOffset, insets)
    local ins = insets or UI.SAFE_INSET
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", parent, "TOPLEFT", ins.left, -((topOffset or 0) + ins.top))
    frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -ins.right, ins.bottom)
end

-- ========= Classes & Specializations helpers =========
-- Safe wrapper around C_CreatureInfo.GetClassInfo
function UI.GetClassInfoByID(cid)
    if not cid or type(cid) ~= "number" then return nil end
    if C_CreatureInfo and C_CreatureInfo.GetClassInfo then
        local ok, info = pcall(C_CreatureInfo.GetClassInfo, cid)
        if ok then return info end
    end
    -- Fallback: nil when not available yet
    return nil
end

-- Resolve a classID from a CLASS tag/token (e.g., "MAGE", "WARRIOR")
function UI.GetClassIDForToken(token)
    token = token and tostring(token):upper() or nil
    if not token then return nil end
    for cid = 1, 30 do
        local info = UI.GetClassInfoByID(cid)
        if info and info.classFile and info.classFile:upper() == token then
            return cid
        end
    end
    return nil
end

-- Human-readable class name, from classID if available, else falls back to classTag
function UI.ClassName(classID, classTag)
    if classID then
        local info = UI.GetClassInfoByID(classID)
        if info then return (info.className or info.name or info.classFile) end
    end
    return classTag or ""
end

-- Cache global des spécialisations: specID -> { name=..., classID=... }
UI._specCache = UI._specCache or nil

-- Construit (une fois) un cache specID -> (name, classID)
local function _BuildSpecCache()
    if UI._specCache then return UI._specCache end
    local cache = {}
    if GetNumSpecializationsForClassID and GetSpecializationInfoForClassID then
        for cid = 1, 30 do
            local n = GetNumSpecializationsForClassID(cid)
            if type(n) == "number" then
                for i = 1, n do
                    local id, name = GetSpecializationInfoForClassID(cid, i)
                    if id and name then
                        cache[id] = { name = name, classID = cid }
                    end
                end
            end
        end
    end
    UI._specCache = cache
    return cache
end

-- Récupère un nom de spé à partir du specID seul (indépendant du joueur)
function UI.SpecNameBySpecID(specID)
    local sid = tonumber(specID)
    if not sid or sid == 0 then
        return (Tr and Tr("lbl_spec")) or "Specialization"
    end
    local cache = _BuildSpecCache()
    local e = cache[sid]
    return (e and e.name) or ((Tr and Tr("lbl_spec")) or "Specialization")
end

-- ⚙️ Human-readable specialization name; robuste pour n'importe quelle classe
function UI.SpecName(classID, specID)
    if not specID or specID == 0 then
        return (Tr and Tr("lbl_spec")) or "Specialization"
    end

    -- 1) Si la classe est connue : résolution directe via l’API Blizzard
    if classID and GetNumSpecializationsForClassID and GetSpecializationInfoForClassID then
        local n = GetNumSpecializationsForClassID(classID) or 0
        for i = 1, n do
            local id, name = GetSpecializationInfoForClassID(classID, i)
            if id == specID and name then
                return name
            end
        end
    end

    -- 2) Fallback générique : par specID (indépendant du joueur/sa classe)
    return UI.SpecNameBySpecID(specID)
end


-- Human-readable specialization name; ⚙️ robuste pour n'importe quelle classe
function UI.SpecName(classID, specID)
    if not specID or specID == 0 then
        return (Tr and Tr("lbl_spec")) or "Specialization"
    end

    -- 1) Si la classe est connue : résolution directe via l’API
    if classID and GetNumSpecializationsForClassID and GetSpecializationInfoForClassID then
        local n = GetNumSpecializationsForClassID(classID) or 0
        for i = 1, n do
            local id, name = GetSpecializationInfoForClassID(classID, i)
            if id == specID and name then
                return name
            end
        end
    end

    -- 2) Fallback générique : par specID (indépendant du joueur/sa classe)
    return UI.SpecNameBySpecID(specID)
end

-- Returns the player's (classID, classTag, specID!=0 when possible)
function UI.ResolvePlayerClassSpec()
    local useTag, useID, useSpec

    if UnitClass then
        local _, token, classID = UnitClass("player")
        useTag = token and token:upper() or nil
        useID  = (type(classID) == "number") and classID or UI.GetClassIDForToken(useTag)
    end

    if GetSpecialization and GetSpecializationInfo then
        local specIndex = GetSpecialization()
        if specIndex then
            local id = select(1, GetSpecializationInfo(specIndex))
            if id and id ~= 0 then useSpec = id end
        end
    end

    -- Fallbacks intentionally omitted (no addon-specific tables here)
    return useID, useTag, useSpec
end

-- Texte Oui/Non coloré, localisé
function UI.YesNoText(v)
    local yes = (Tr and Tr("opt_yes")) or "Yes"
    local no  = (Tr and Tr("opt_no"))  or "No"
    if v then
        return "|cff33ff33" .. yes .. "|r"
    else
        return "|cffff4040" .. no .. "|r"
    end
end

-- ============================================================
-- Helpers textures (génériques)
-- ============================================================

-- UI.CropIcon(texture, px, srcW, srcH)
-- Rogne 'px' pixels sur chaque bord (par défaut source 64x64).
function UI.CropIcon(tex, px, srcW, srcH)
    if not tex or not tex.SetTexCoord then return end
    local p = tonumber(px) or 0
    if p <= 0 then tex:SetTexCoord(0,1,0,1); return end

    local w = tonumber(srcW) or 64
    local h = tonumber(srcH) or w

    -- Clamp pour garder des UV valides quoi qu'il arrive
    local maxPxW = math.max(0, math.min(p, (w/2) - 1))
    local maxPxH = math.max(0, math.min(p, (h/2) - 1))

    local u = maxPxW / w
    local v = maxPxH / h
    tex:SetTexCoord(u, 1 - u, v, 1 - v)
end

-- Restaure l’icone pleine (utile en fallback)
function UI.ResetTexCoord(tex)
    if not tex or not tex.SetTexCoord then return end
    tex:SetTexCoord(0,1,0,1)
end

-- Force la visibilité par couche + alpha, pour éviter d’être masqué par un overlay
function UI.EnsureIconVisible(tex, subLevel)
    if not tex then return end
    tex:SetDrawLayer("OVERLAY", subLevel or 1) -- au-dessus des ARTWORK/hover
    tex:SetDesaturated(false)
    tex:SetAlpha(1)
    tex:Show()
end

-- Pose une icône depuis un path de fichier, avec fallback atlas si 'iconPath' est un atlas Blizzard
function UI.TrySetIcon(tex, iconPath)
    if not tex then return end
    local function AtlasExists(name)
        return C_Texture and C_Texture.GetAtlasInfo and name and C_Texture.GetAtlasInfo(name) ~= nil
    end
    local path = iconPath or "Interface\\ICONS\\INV_Misc_QuestionMark"
    tex:SetTexture(path)
    local ok = tex:GetTexture()
    if (not ok) and iconPath and AtlasExists(iconPath) then
        tex:SetAtlas(iconPath, true)
    end
end

function UI.RegisterEscapeClose(frame)
    -- Ferme 'frame' avec la touche ÉCHAP.
    -- Si la frame a un nom global, on l’enregistre dans UISpecialFrames (comportement natif Blizzard).
    -- Sinon, on capte le clavier et on cache manuellement sur ESCAPE.
    if not frame or type(frame) ~= "table" or not frame.GetObjectType then
        return
    end

    local name = frame.GetName and frame:GetName() or nil
    if name and name ~= "" then
        -- Évite les doublons
        for i = 1, #UISpecialFrames do
            if UISpecialFrames[i] == name then
                return
            end
        end
        table.insert(UISpecialFrames, name)
    else
        -- Fallback si la frame n’a pas de nom (très rare dans ce projet)
        if frame.EnableKeyboard then frame:EnableKeyboard(true) end
        if frame.SetPropagateKeyboardInput then frame:SetPropagateKeyboardInput(false) end
        frame:HookScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                self:Hide()
            end
        end)
    end
end

function UI.ApplyTextAlpha(frame, a)
    a = tonumber(a or 1) or 1
    if a < 0 then a = 0 elseif a > 1 then a = 1 end
    if not (frame and frame.GetObjectType) then return end

    local function applyTo(obj)
        if not obj then return end
        local ot = (obj.GetObjectType and obj:GetObjectType()) or ""

        -- FontString
        if ot == "FontString" and obj.SetAlpha then
            obj:SetAlpha(a)
        end

        -- Boutons/frames avec fontstring intégrée
        if obj.GetFontString then
            local fs = obj:GetFontString()
            if fs and fs.SetAlpha then fs:SetAlpha(a) end
        end

        -- Widgets NameTag : appliquer aussi à l'icône de classe
        if obj.icon and obj.icon.SetAlpha then
            obj.icon:SetAlpha(a)
        end
        if obj.Icon and obj.Icon.SetAlpha then
            obj.Icon:SetAlpha(a)
        end
        if obj.text and obj.text.SetAlpha then
            obj.text:SetAlpha(a)
        end
    end

    -- Régions directes
    local regions = { frame:GetRegions() }
    for _, r in ipairs(regions) do applyTo(r) end

    -- Enfants (récursif)
    local children = { frame:GetChildren() }
    for _, c in ipairs(children) do
        applyTo(c)
        UI.ApplyTextAlpha(c, a)
    end
end

-- Applique alpha = base * scale (base = 1 ou 0.35 selon activé/désactivé)
function UI.SetButtonAlphaScaled(btn, base, scale)
    if not (btn and btn.SetAlpha) then return end
    local b = tonumber(base or 1)  or 1
    local s = tonumber(scale or 1) or 1
    if s < 0 then s = 0 elseif s > 1 then s = 1 end
    btn:SetAlpha(b * s)
end

-- Applique l'opacité aux boutons connus d'un conteneur + tous les boutons du header
function UI.ApplyButtonsOpacity(container, scale)
    if not container then return end
    local function apply(btn)
        if not btn then return end
        local base = (btn.IsEnabled and (btn:IsEnabled() and 1 or 0.35)) or 1
        UI.SetButtonAlphaScaled(btn, base, scale)
    end

    -- Boutons connus
    apply(container.close)
    apply(container.nextBtn)
    apply(container.prevBtn)
    apply(container.clearBtn)

    -- Tous les boutons éventuels dans le header
    local hdr = container.header
    if hdr and hdr.GetChildren then
        local children = { hdr:GetChildren() }
        for _, c in ipairs(children) do
            if c and c.GetObjectType and c:GetObjectType() == "Button" then
                apply(c)
            end
        end
    end
end

-- Alpha uniquement sur le texte du titre d'un frame (header/title connus)
function UI.SetFrameTitleTextAlpha(frame, a)
    if not frame then return end
    a = tonumber(a or 1) or 1
    if a < 0 then a = 0 elseif a > 1 then a = 1 end

    local function setFS(fs)
        if fs and fs.GetObjectType and fs:GetObjectType() == "FontString" and fs.SetAlpha then
            fs:SetAlpha(a)
        end
    end

    -- Variantes fréquentes dans notre UI
    if frame.title then setFS(frame.title) end

    if frame.header then
        setFS(frame.header.title)
        setFS(frame.header.text)
        setFS(frame.header.Title)
        setFS(frame.header.TitleText)
    end
end

function UI.SetFrameTitleVisibility(frame, visible)
    if not frame then return end
    local function setFS(fs)
        if not fs or not fs.GetObjectType or fs:GetObjectType() ~= "FontString" then return end
        if visible then fs:Show() else fs:Hide() end
    end

    -- Header classique
    if frame.header then
        if frame.header.title then setFS(frame.header.title) end
        if frame.header.text  then setFS(frame.header.text)  end
        if frame.header.Title then setFS(frame.header.Title) end
        if frame.header.TitleText then setFS(frame.header.TitleText) end
        -- scan de secours dans le header
        local regs = { frame.header:GetRegions() }
        for _, r in ipairs(regs) do
            local name = (r.GetName and r:GetName()) or ""
            if type(name) == "string" and name:lower():find("title") then
                setFS(r)
            end
        end
    end

    -- Titres éventuels directement sur la frame
    if frame.title     then setFS(frame.title)     end
    if frame.Title     then setFS(frame.Title)     end
    if frame.TitleText then setFS(frame.TitleText) end

    -- scan global (fallback)
    local regs = { frame:GetRegions() }
    for _, r in ipairs(regs) do
        local name = (r.GetName and r:GetName()) or ""
        if type(name) == "string" and name:lower():find("title") then
            setFS(r)
        end
    end
end

-- Active/désactive la capture souris pour un frame et tous ses enfants (boutons inclus)
function UI.SetMouseEnabledDeep(frame, enabled)
    if not frame then return end
    local function walk(obj)
        if obj.EnableMouse then obj:EnableMouse(enabled and true or false) end
        if obj.EnableMouseWheel then obj:EnableMouseWheel(enabled and true or false) end
        local t = obj.GetObjectType and obj:GetObjectType()
        if t == "Button" then
            if not enabled and obj.Disable then obj:Disable()
            elseif enabled and obj.Enable then obj:Enable() end
        end
        local n = obj.GetNumChildren and obj:GetNumChildren() or 0
        for i=1,n do
            local child = select(i, obj:GetChildren())
            if child then walk(child) end
        end
    end
    walk(frame)
end

-- Verrouille/déverrouille l'interaction d'une fenêtre PlainWindow (header/resize/list/etc.)
function UI.PlainWindow_SetLocked(win, locked)
    if not win then return end
    locked = (locked == true)
    -- Drag sur l'entête + coin de resize
    if win.header and win.header.EnableMouse then win.header:EnableMouse(not locked) end
    if win.resize and win.resize.EnableMouse then win.resize:EnableMouse(not locked) end
    -- Tout le reste (contenu, scroll, lignes de la ListView, boutons…)
    UI.SetMouseEnabledDeep(win, not locked)
end
