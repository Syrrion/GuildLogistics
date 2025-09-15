local ADDON, ns = ...
local Tr = ns and ns.Tr
ns.UI = ns.UI or {}
local UI = ns.UI
local GLOG = ns.GLOG

-- ===== SYSTÈME D'OPTIMISATION DES TIMERS =====
-- Accumule les tâches à exécuter sur le prochain frame pour éviter les timers multiples
local _batchedTasks = {}
local _batchTimer = nil

local function ExecuteBatchedTasks()
    local tasks = _batchedTasks
    _batchedTasks = {}
    _batchTimer = nil
    
    for i = 1, #tasks do
        local task = tasks[i]
        if task and type(task) == "function" then
            local success, err = pcall(task)
            if not success then
                -- Optionnel : log l'erreur sans arrêter les autres tâches
                -- print("Erreur tâche batch UI:", err)
            end
        end
    end
end

-- Fonction optimisée pour remplacer C_Timer.After(0, func)
function UI.NextFrame(func)
    if type(func) ~= "function" then return end
    
    _batchedTasks[#_batchedTasks + 1] = func
    
    -- Démarre le timer seulement s'il n'y en a pas déjà un
    if not _batchTimer then
        _batchTimer = C_Timer.After(0, ExecuteBatchedTasks)
    end
end

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
UI.SEPARATOR_TOP_PAD = 20

-- Opacité (multiplicateur) des séparateurs verticaux de ListView
UI.VCOL_SEP_ALPHA = UI.VCOL_SEP_ALPHA or 0.05

-- Registre (faible) des SectionHeaders pour rafraîchissement dynamique des couleurs
UI._SECTION_HEADERS = UI._SECTION_HEADERS or setmetatable({}, { __mode = "k" })

-- Fallback local si UI.Colors.GetHeaderRGB() n'existe pas (compat projets plus anciens)
local function _HeaderRGB()
    if UI and UI.Colors and UI.Colors.GetHeaderRGB then
        local ok, r, g, b = pcall(UI.Colors.GetHeaderRGB)
        if ok and r then return r, g, b end
    end
    local tag = tostring(UI.FRAME_THEME or "AUTO"):upper()
    if tag == "AUTO" and UnitFactionGroup then
        tag = tostring(UnitFactionGroup("player") or "NEUTRAL"):upper()
    end
    local MAP = {
        ALLIANCE = { 0.17, 0.52, 0.95 },
        HORDE    = { 0.85, 0.20, 0.20 },
        NEUTRAL  = { 0.58, 0.42, 0.18 },
    }
    local c = MAP[tag] or MAP.NEUTRAL
    return c[1], c[2], c[3]
end

-- API : force la recolorisation de tous les SectionHeaders existants
function UI.RefreshSectionHeaders()
    local r, g, b = _HeaderRGB()
    for fs, sep in pairs(UI._SECTION_HEADERS or {}) do
        if fs and fs.SetTextColor then fs:SetTextColor(r, g, b) end
        if sep and sep.SetColorTexture then sep:SetColorTexture(r, g, b, 0.18) end
    end
end

-- Enregistrement d'un header (fs = FontString, sep = Texture du séparateur)
function UI._RegisterSectionHeader(fs, sep)
    if not fs then return end
    UI._SECTION_HEADERS[fs] = sep or true
end

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
            -- propage "vsep"
            out[i] = { key=c.key, w=w, justify=c.justify, pad=c.pad, vsep = (c.vsep and true) or nil }
        else
            flexUnits = flexUnits + (c.flex or 0)
            -- propage "vsep" aussi sur la branche flex
            out[i] = { key=c.key, w=min, min=min, flex=c.flex or 0, justify=c.justify, pad=c.pad, vsep = (c.vsep and true) or nil }
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
        if UI and UI.ApplyFont then UI.ApplyFont(fs) end

        fs:SetJustifyH(c.justify or "LEFT")
        labels[i] = fs
    end
    return header, labels
end

function UI.LayoutHeader(header, cols, labels)
    header._vseps = header._vseps or {}
    local st = (UI.GetListViewStyle and UI.GetListViewStyle()) or { sep={r=1,g=1,b=1,a=.20} }
    local mul = tonumber(UI.VCOL_SEP_ALPHA or 0.15) or 0.15
    if mul < 0 then mul = 0 elseif mul > 1 then mul = 1 end

    local x = 0
    local active = {}

    for i, c in ipairs(cols or {}) do
        local w  = c.w or c.min or 80
        local fs = labels[i]
        if fs then
            fs:ClearAllPoints()
            fs:SetPoint("LEFT", header, "LEFT", x + 4, 0)
            fs:SetWidth(w - 8)
            fs:SetHeight(24)
        end

        -- Séparateur vertical à GAUCHE de la colonne si demandé
        if c.vsep then
            local t = header._vseps[i]
            if not t then
                -- Calque OVERLAY haut ➜ garanti au-dessus des fonds et des gradients
                t = header:CreateTexture(nil, "OVERLAY", nil, 7)
                header._vseps[i] = t
            else
                if t.SetDrawLayer then t:SetDrawLayer("OVERLAY", 7) end
            end

            -- couleur + snap
            t:SetColorTexture(1,1,1,1)
            if UI.SetPixelWidth then UI.SetPixelWidth(t, 1) else t:SetWidth(1) end
            t:ClearAllPoints()

            -- pas de clipping sur le header
            if header.SetClipsChildren then header:SetClipsChildren(false) end

            local px = (UI.RoundToPixelOn and UI.RoundToPixelOn(header, x))
                    or (UI.RoundToPixel and UI.RoundToPixel(x)) or x
            if PixelUtil and PixelUtil.SetPoint then
                PixelUtil.SetPoint(t, "TOPLEFT",    header, "TOPLEFT",    px, 0)
                PixelUtil.SetPoint(t, "BOTTOMLEFT", header, "BOTTOMLEFT", px, 0)
            else
                t:SetPoint("TOPLEFT",    header, "TOPLEFT",    px, 0)
                t:SetPoint("BOTTOMLEFT", header, "BOTTOMLEFT", px, 0)
            end

            -- Alpha de base = uniquement la constante (évite double atténuation)
            local baseA = tonumber(UI.VCOL_SEP_ALPHA or 0.15) or 0.15
            t:SetAlpha(baseA)
            t._baseA = baseA

            if UI.SnapTexture then UI.SnapTexture(t) end
            t:Show()
            active[i] = true

        end

        x = x + w
    end

    -- Cache les séparateurs non utilisés
    for i, t in pairs(header._vseps) do
        if not active[i] and t.Hide then t:Hide() end
    end

    -- Ne pas afficher les séparateurs verticaux dans l'entête
    if UI.SetVSepsVisible then
        UI.SetVSepsVisible(header, false)
    elseif header._vseps then
        for _, t in pairs(header._vseps) do if t and t.Hide then t:Hide() end end
    end

end


-- ===== Row =====
function UI.LayoutRow(row, cols, fields)
    -- Alpha des v-seps centralisée + flag pour ignorer les v-seps sur les lignes "sep"
    local baseA = tonumber(UI.VCOL_SEP_ALPHA or 0.15) or 0.15
    if baseA < 0 then baseA = 0 elseif baseA > 1 then baseA = 1 end
    local allowVSeps = (row._isSep ~= true)

    row._vseps = row._vseps or {}
    local st = (UI.GetListViewStyle and UI.GetListViewStyle()) or { sep={r=1,g=1,b=1,a=.20} }
    local mul = tonumber(UI.VCOL_SEP_ALPHA or 0.15) or 0.15
    if mul < 0 then mul = 0 elseif mul > 1 then mul = 1 end

    local x = 0
    local active = {}

    for i, c in ipairs(cols or {}) do
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
            -- Option de colonne: autoriser le multi-ligne et/ou désactiver la troncature
            if c.wrapLines or c.noTruncate then
                -- Désactive la troncature automatique pour cette cellule
                f._noTruncation = true
                if c.wrapLines then
                    if f.SetWordWrap then pcall(f.SetWordWrap, f, true) end
                    if f.SetMaxLines then pcall(f.SetMaxLines, f, tonumber(c.wrapLines) or 2) end
                    if f.SetJustifyV then pcall(f.SetJustifyV, f, "MIDDLE") end
                end
            else
                if UI.ApplyCellTruncation then UI.ApplyCellTruncation(f, w - 8) end
            end
        end

        if allowVSeps and c.vsep then
            local t = row._vseps[i]
            if not t then
                -- OVERLAY haut pour passer devant les backgrounds de ligne
                t = row:CreateTexture(nil, "OVERLAY", nil, 7)
                row._vseps[i] = t
            else
                if t.SetDrawLayer then t:SetDrawLayer("OVERLAY", 7) end
            end

            -- anti-clipping : la ligne ne doit jamais être masquée par les cellules
            if row.SetClipsChildren then row:SetClipsChildren(false) end

            t:SetColorTexture(1,1,1,1)
            if UI.SetPixelWidth then UI.SetPixelWidth(t, 1) else t:SetWidth(1) end
            t:ClearAllPoints()

            local px = (UI.RoundToPixelOn and UI.RoundToPixelOn(row, x))
                or (UI.RoundToPixel and UI.RoundToPixel(x)) or x

            if PixelUtil and PixelUtil.SetPoint then
                PixelUtil.SetPoint(t, "TOPLEFT",    row, "TOPLEFT",    px, 0)
                PixelUtil.SetPoint(t, "BOTTOMLEFT", row, "BOTTOMLEFT", px, 0)
            else
                t:SetPoint("TOPLEFT",    row, "TOPLEFT",    px, 0)
                t:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", px, 0)
            end

            -- Ne pousse l'alpha que si elle change (évite du travail GPU inutile)
            if t._baseA ~= baseA then
                t:SetAlpha(baseA)
                t._baseA = baseA
            end

            if UI.SnapTexture then UI.SnapTexture(t) end
            t:Show()
            active[i] = true
        end
        x = x + w
    end

    -- Cache les séparateurs non utilisés
    for i, t in pairs(row._vseps) do
        if not active[i] and t.Hide then t:Hide() end
    end

    -- Masquer tous les v-seps pour les lignes "sep"
    if row._isSep then
        if row._vseps then
            for _, t in pairs(row._vseps) do
                if t and t.Hide then t:Hide() end
            end
        end
    end

end

-- Déco de base d'une ligne : dégradé vertical + hover + séparateur TOP 1px (pixel-perfect)
-- + liseré gauche (caché par défaut) pour marquer "même groupe"
function UI.DecorateRow(r)
    local st = (UI.GetListViewStyle and UI.GetListViewStyle()) or {
        oddTop        = { r = 0, g = 0, b = 0, a = 0.05 },
        oddBottom     = { r = 0, g = 0, b = 0, a = 0.20 },
        -- Lignes paires
        -- dupliquer explicitement pour éviter la référence à des variables non définies
        evenTop       = { r = 0, g = 0, b = 0, a = 0.05 },
        evenBottom    = { r = 0, g = 0, b = 0, a = 0.20 },
        -- Survol & séparateur
        hover      = { r = 1.00, g = 0.82, b = 0.00, a = 0.06 },
        sep        = { r = 1.00, g = 1.00, b = 1.00, a = 0.2 },
        -- ➕ Couleur par défaut du liseré "même groupe"
        accent     = { r = 1.00, g = 0.82, b = 0.00, a = 0.90 }, -- jaune Blizzard
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
    local botA = (st.sep.a or 1) * .1
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
    if not row then return end
    -- ⛔ Pas d’allocation si on masque
    if not shown then
        if row._accentGrad then row._accentGrad:Hide() end
        return
    end

    local sa = tonumber(startAlpha) or 0.50
    local grad = row._accentGrad
    if not grad then
        grad = row:CreateTexture(nil, "BACKGROUND", nil, -6)
        row._accentGrad = grad
        grad:ClearAllPoints()
        grad:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
        grad:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
        grad:SetTexture("Interface\\Buttons\\WHITE8x8")
        if UI.SnapTexture then UI.SnapTexture(grad) end
    end

    r, g, b = tonumber(r) or 1, tonumber(g) or .82, tonumber(b) or 0
    if grad.SetGradient and type(CreateColor) == "function" then
        grad:SetGradient("HORIZONTAL", CreateColor(r, g, b, sa), CreateColor(r, g, b, 0))
    else
        grad:SetVertexColor(r, g, b, sa)
    end
    grad:Show()
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
    local padL   = tonumber(opts.padLeft)  or 0
    local padR   = tonumber(opts.padRight) or 0
    local topPad = tonumber(opts.topPad)   or 0

    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("TOPLEFT",  parent, "TOPLEFT",  padL, -(topPad + 2))
    fs:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -padR, -(topPad + 2))
    fs:SetJustifyH("LEFT")
    fs:SetText((Tr and Tr(title or "")) or tostring(title or ""))

    -- Couleur selon le thème
    local r, g, b = _HeaderRGB()
    if fs.SetTextColor then fs:SetTextColor(r, g, b) end

    local sep = parent:CreateTexture(nil, "BORDER")
    sep:SetColorTexture(r, g, b, 0.18)
    sep:SetPoint("TOPLEFT",  fs, "BOTTOMLEFT",  0, -4)
    sep:SetPoint("TOPRIGHT", fs, "BOTTOMRIGHT", 0, -4)
    sep:SetHeight(1)

    -- Enregistrer pour pouvoir rafraîchir la couleur quand on change de thème
    if UI and UI._RegisterSectionHeader then UI._RegisterSectionHeader(fs, sep) end

    -- Return height first for backward compatibility, plus the FontString and separator
    return UI.SECTION_HEADER_H, fs, sep
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
        cc.justify = cc.justify or "LEFT"
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
    
    -- Applique immédiatement la police personnalisée
    if UI and UI.ApplyFont and fs then
        UI.ApplyFont(fs)
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
    -- Respect explicit flags to disable truncation (wrap/multi-line cells)
    if cell and (cell._noTruncation or cell._allowWrap) then return end
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

    -- Si la cible est déjà configurée pour wrap multi-ligne, ne pas tronquer
    if target._allowWrap then return end
    if target.GetMaxLines and target:GetMaxLines() and target:GetMaxLines() > 1 then
        return
    end
    local existingText = (target.GetText and target:GetText()) or ""
    if type(existingText) == "string" and existingText:find("\n") then
        return
    end

    -- Désactive le word wrap et limite à 1 ligne (mode troncature)
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
    -- Si le contenu contient une nouvelle ligne, ne pas tronquer
    if type(full) == "string" and full:find("\n") then
        if target._origSetText then
            target:_origSetText(full)
        else
            target:SetText(full)
        end
        return
    end
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
    if grad.SetGradient and type(CreateColor) == "function" then
        grad:SetGradient("VERTICAL", CreateColor(gt[1], gt[2], gt[3], gt[4]), CreateColor(gb[1], gb[2], gb[3], gb[4]))
    else
        grad:SetVertexColor((gt[1]+gb[1])/2, (gt[2]+gb[2])/2, (gt[3]+gb[3])/2, (gt[4]+gb[4])/2)
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

    -- Lier une tooltip (item / sort / lien) à un frame
    -- Usage : UI.BindItemOrSpellTooltip(frame, itemID, spellID, link, anchor)
    function UI.BindItemOrSpellTooltip(frame, itemID, spellID, link, anchor)
        if not frame or not frame.SetScript then return end
        frame._itemID  = tonumber(itemID or 0) or 0
        frame._spellID = tonumber(spellID or 0) or 0
        frame._link    = link
        frame:EnableMouse(true)
        local anch = tostring(anchor or "ANCHOR_RIGHT")

        frame:SetScript("OnEnter", function(self)
            local iid, sid = tonumber(self._itemID or 0) or 0, tonumber(self._spellID or 0) or 0
            if iid > 0 then
                GameTooltip:SetOwner(self, anch)
                GameTooltip:SetItemByID(iid)
                GameTooltip:Show()
            elseif self._link then
                GameTooltip:SetOwner(self, anch)
                GameTooltip:SetHyperlink(self._link)
                GameTooltip:Show()
            elseif sid > 0 and GameTooltip.SetSpellByID then
                GameTooltip:SetOwner(self, anch)
                GameTooltip:SetSpellByID(sid)
                GameTooltip:Show()
            end
        end)
        frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

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
    -- Fallback pour anciens enregistrements: certains stockaient l'itemID dans 'id'
    if not itemID and item.id then
        local alt = tonumber(item.id)
        if alt and alt > 5000 then itemID = alt end
    end

    -- 2) Résolution du lien (préférer GetItemInfo; sinon garder un lien texte complet s'il existe)
    local link = nil
    if not link and type(item.itemLink) == "string" and string.find(item.itemLink, "|Hitem:") then
        link = item.itemLink
    end

    -- 3) Nom affiché
    local function _isNumericString(s)
        return type(s) == "string" and s:match("^%d+$") ~= nil
    end

    local name = item.itemName
    if name and _isNumericString(name) then name = nil end
    if not name and type(link) == "string" then
        name = string.match(link, "%[(.-)%]") -- extrait le nom entre crochets
    end
    local usedFallback = false
    if not name then
        -- Try fast C_Item name first (non-deprecated, instant if cached)
        if itemID and C_Item and C_Item.GetItemNameByID then
            local n = C_Item.GetItemNameByID(itemID)
            if n and n ~= "" then name = n end
        end
    end
    if not name then
        name = "Objet #" .. tostring(itemID or "?")
        usedFallback = true
    end

    -- 4) Icône (sélection sûre sans typer la variable)
    do
        local defaultIcon = "Interface/Icons/INV_Misc_QuestionMark"
        local ic = nil
        if itemID and C_Item and C_Item.GetItemInfoInstant then
            local _, _, _, _, fileID = C_Item.GetItemInfoInstant(itemID)
            ic = fileID
        end
        if ic then cell.icon:SetTexture(ic) else cell.icon:SetTexture(defaultIcon) end
    end
    cell.text:SetText(name or "")
    cell.btn._itemID = itemID           -- SetItemByID sera utilisé si présent
    cell.btn._link   = (type(link)=="string") and link or nil -- fallback Hyperlink si pas d'ID

    -- If we had to fallback to a placeholder name, try to resolve asynchronously and update
    if itemID and Item and Item.CreateFromItemID then
        local btn = cell.btn
        local obj = Item:CreateFromItemID(itemID)
        obj:ContinueOnItemLoad(function()
            -- Only update if the cell still represents the same itemID
            if btn and btn._itemID == itemID and cell and cell.text then
                local n
                if obj.GetItemName then n = obj:GetItemName() end
                if (not n or n == "") and C_Item and C_Item.GetItemNameByID then
                    n = C_Item.GetItemNameByID(itemID)
                end
                if n and n ~= "" and not _isNumericString(n) then
                    cell.text:SetText(n)
                end
            end
        end)
    end
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
            self.txt:SetText(tostring(v))
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

-- 🆕 Variante avancée: identique à SetNameTagShort mais permet de forcer la classe (icône + couleur)
-- Utilisée pour afficher la classe propre du personnage (et non celle de son main) dans certains écrans
function UI.SetNameTagShortEx(tag, name, overrideClassTag)
    if not tag then return end
    local raw = (GLOG and GLOG.ResolveFullName and GLOG.ResolveFullName(name)) or tostring(name or "")
    local display = (ns and ns.Util and ns.Util.ShortenFullName and ns.Util.ShortenFullName(raw)) or raw

    local r, g, b = 1, 1, 1
    local coords = nil

    if overrideClassTag and overrideClassTag ~= "" then
        local classTag = tostring(overrideClassTag):upper()
        -- Couleur de classe
        if C_ClassColor and C_ClassColor.GetClassColor then
            local col = C_ClassColor.GetClassColor(classTag)
            if col and col.GetRGB then r, g, b = col:GetRGB() end
        end
        if RAID_CLASS_COLORS and (r == 1 and g == 1 and b == 1) then
            local col = RAID_CLASS_COLORS[classTag]
            if col then r, g, b = col.r or 1, col.g or 1, col.b or 1 end
        end
        -- Icône de classe
        if CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classTag] then
            coords = CLASS_ICON_TCOORDS[classTag]
        end
    else
        -- Fallback: style global (peut privilégier la classe du main)
        if GLOG and GLOG.GetNameStyle then
            local _, rr, gg, bb, cc = GLOG.GetNameStyle(raw)
            r, g, b, coords = rr or 1, gg or 1, bb or 1, cc
        end
    end

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

-- Reusable cached updater for NameTag widgets (icon + colored name + optional suffix)
-- suffix: optional plain text appended after the display name (e.g., "(Suggested)")
-- suffixColor: optional {r,g,b} for the suffix (default green)
function UI.UpdateNameTagCached(tag, name, overrideClassTag, suffix, suffixColor)
    if not tag then return end
    local raw = (GLOG and GLOG.ResolveFullName and GLOG.ResolveFullName(name)) or tostring(name or "")
    local baseDisp = (ns and ns.Util and ns.Util.ShortenFullName and ns.Util.ShortenFullName(raw)) or raw

    local cls = overrideClassTag or ""
    if tag._lastNameRaw ~= raw or tag._lastClassTag ~= cls then
        if UI.SetNameTagShortEx then
            UI.SetNameTagShortEx(tag, raw, (cls ~= "" and cls) or nil)
        else
            UI.SetNameTagShort(tag, raw)
        end
        tag._lastNameRaw  = raw
        tag._lastClassTag = cls
        tag._lastComposed = nil
        tag._baseDisplay  = baseDisp
    end

    local composed = tag._baseDisplay or baseDisp
    if suffix and suffix ~= "" then
        local c = suffixColor or {0,1,0}
        local r,g,b = tonumber(c[1] or 0), tonumber(c[2] or 1), tonumber(c[3] or 0)
        local hex = string.format("%02x%02x%02x", math.floor(r*255+0.5), math.floor(g*255+0.5), math.floor(b*255+0.5))
        composed = string.format("%s |cff%s%s|r", composed, hex, tostring(suffix))
    end

    if tag.text and tag._lastComposed ~= composed then
        tag.text:SetText(composed)
        tag._lastComposed = composed
    end
end

-- Icône de type de jet (Need/Greed/DE/Pass) + libellé
function UI.SetRollIcon(tex, rollType)
    if not tex or (tex.GetObjectType and tex:GetObjectType() ~= "Texture") then return end
    if not rollType or rollType == "" then
        if tex.SetAtlas then tex:SetAtlas(nil) end
        tex:SetTexture(nil)
        tex:Hide()
        return
    end

    local ATLAS = {
        need       = "loottoast-roll-need",
        greed      = "loottoast-roll-greed",
        disenchant = "loottoast-roll-disenchant",
        pass       = "loottoast-roll-pass",
        transmog   = "loottoast-roll-transmog",
    }
    local FILES = {
        need       = "Interface\\Buttons\\UI-GroupLoot-Dice-Up",
        greed      = "Interface\\Buttons\\UI-GroupLoot-Coin-Up",
        disenchant = "Interface\\Buttons\\UI-GroupLoot-DE-Up",
        pass       = "Interface\\Buttons\\UI-GroupLoot-Pass-Up",
        transmog   = "Interface\\Buttons\\UI-GroupLoot-Coin-Up",
    }

    local ok = false
    if tex.SetAtlas and C_Texture and C_Texture.GetAtlasInfo then
        local a = ATLAS[rollType]
        if a and C_Texture.GetAtlasInfo(a) then
            tex:SetAtlas(a); ok = true
        end
    end
    if not ok then
        local f = FILES[rollType]
        if f then tex:SetTexture(f); ok = true end
    end

    if ok then tex:Show() else tex:Hide() end
end

function UI.RollLabel(rollType)
    local Tr = ns.Tr or function(s) return s end
    local map = {
        need       = Tr("roll_need")       or "Besoin",
        greed      = Tr("roll_greed")      or "Cupidité",
        disenchant = Tr("roll_disenchant") or "Désenchant.",
        pass       = Tr("roll_pass")       or "Passer",
        transmog   = Tr("roll_transmog")   or "Transmo",
    }
    return map[rollType] or ""
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

function GLOG.Minimap_Init()
    if GLOG.EnsureDB then GLOG.EnsureDB() end
    GuildLogisticsUI = GuildLogisticsUI or {}
    GuildLogisticsUI.minimap = GuildLogisticsUI.minimap or { hide=false, angle=215 }
    if GuildLogisticsUI.minimap.angle == nil then
        GuildLogisticsUI.minimap.angle = 215
    end
    if GuildLogisticsUI.minimap.hide then return end

    do
        local mb = _G and _G["GLOG_MinimapButton"]
        if mb then
            local r = (Minimap:GetWidth() / 2) - 5
            local rad = math.rad(GuildLogisticsUI.minimap.angle or 215)
            mb:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * r, math.sin(rad) * r)
            return
        end
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
        if info then return (info.className or info.classFile or "") end
    end
    return classTag or ""
end

-- Cache global des spécialisations: specID -> { name=..., classID=... }
UI._specCache = UI._specCache or nil

-- Construit (une fois) un cache specID -> (name, classID)
local function _BuildSpecCache()
    if UI._specCache then return UI._specCache end
    local cache = {}
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
    return UI.SpecNameBySpecID(specID)
end


-- Human-readable specialization name; ⚙️ robuste pour n'importe quelle classe
-- (duplicate removed)

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

-- Sécurise tout SetTexCoord en s’assurant que les UV restent dans [0,1]
-- et que left < right, top < bottom (évite "TexCoord out of range").
function UI.SafeSetTexCoord(tex, left, right, top, bottom)
    if not (tex and tex.SetTexCoord) then return end

    local l = tonumber(left)   or 0
    local r = tonumber(right)  or 1
    local t = tonumber(top)    or 0
    local b = tonumber(bottom) or 1

    -- Évite NaN
    if l ~= l or r ~= r or t ~= t or b ~= b then
        tex:SetTexCoord(0, 1, 0, 1)
        return
    end

    if r < l then l, r = r, l end
    if b < t then t, b = b, t end

    -- Clamp
    if l < 0 then l = 0 end
    if r > 1 then r = 1 end
    if t < 0 then t = 0 end
    if b > 1 then b = 1 end
    if l == r then r = math.min(1, l + 0.001) end
    if t == b then b = math.min(1, t + 0.001) end

    tex:SetTexCoord(l, r, t, b)
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

-- Peut-on afficher une modale maintenant ? (combat/instance/loading)
function UI.CanOpenModalNow()
    if ns and ns.App and ns.App.loadingActive then return false end
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        return false
    end
    local inInstance = IsInInstance and select(1, IsInInstance())
    if inInstance then return false end
    return true
end

-- Le calendrier est-il visible ?
function UI.IsCalendarOpen()
    return CalendarFrame and CalendarFrame:IsShown()
end

-- Ouvrir l’UI calendrier (idempotent)
function UI.OpenCalendar()
    if UI.IsCalendarOpen() then return end
    if not CalendarFrame then
        if UIParentLoadAddOn then
            UIParentLoadAddOn("Blizzard_Calendar")
        elseif C_AddOns and C_AddOns.LoadAddOn then
            pcall(C_AddOns.LoadAddOn, "Blizzard_Calendar")
        end
    end
    if CalendarFrame and CalendarFrame.Show then
        CalendarFrame:Show()
    elseif ToggleCalendar then
        ToggleCalendar()
    elseif Calendar_Toggle then
        Calendar_Toggle()
    end
end

-- === Suspension globale de l'UI & exceptions "always-on" ===
UI._alwaysOnFrames = UI._alwaysOnFrames or setmetatable({}, { __mode = "k" })
UI._popupFrames = UI._popupFrames or setmetatable({}, { __mode = "k" })

local function _isOpen()
    if UI and UI.IsOpen then return UI.IsOpen() end
    return (UI and UI.Main and UI.Main.IsShown and UI.Main:IsShown()) or false
end

local function _isDescendantOf(child, parent)
    if not (child and parent and child.GetParent) then return false end
    local p = child
    while p do
        if p == parent then return true end
        p = p:GetParent()
    end
    return false
end

-- Vérifie si une popup est visible
local function _hasVisiblePopup()
    for f in pairs(UI._popupFrames) do
        if f and f.IsShown and f:IsShown() then
            return true
        end
    end
    return false
end

-- Marque/démarque une frame comme autorisée même UI fermée (ex: tracker flottant)
function UI.MarkAlwaysOn(frame, on)
    if not frame then return end
    if on == false then
        UI._alwaysOnFrames[frame] = nil
    else
        UI._alwaysOnFrames[frame] = true
    end
end

-- Marque/démarque une frame comme popup (toujours autorisée)
function UI.MarkAsPopup(frame, on)
    if not frame then return end
    if on == false then
        UI._popupFrames[frame] = nil
    else
        UI._popupFrames[frame] = true
    end
end

-- La frame (ou l'un de ses parents) appartient-elle à une zone "always-on" visible ?
function UI.IsWithinAlwaysOn(frame)
    if not (frame and frame.GetParent) then return false end
    for f in pairs(UI._alwaysOnFrames) do
        if f and f.IsShown and f:IsShown() and _isDescendantOf(frame, f) then
            return true
        end
    end
    return false
end

-- La frame (ou l'un de ses parents) appartient-elle à une popup visible ?
function UI.IsWithinPopup(frame)
    if not (frame and frame.GetParent) then return false end
    for f in pairs(UI._popupFrames) do
        if f and f.IsShown and f:IsShown() and _isDescendantOf(frame, f) then
            return true
        end
    end
    return false
end

-- Doit-on exécuter un traitement UI ? (true si UI ouverte OU frame dans une zone always-on OU popup visible)
function UI.ShouldProcess(ownerFrame)
    if _isOpen() then return true end
    if ownerFrame and UI.IsWithinAlwaysOn(ownerFrame) then return true end
    if ownerFrame and UI.IsWithinPopup(ownerFrame) then return true end
    return false
end

-- Doit-on exécuter un rafraîchissement UI ? (même chose que ShouldProcess mais nom plus explicite)
function UI.ShouldRefreshUI(ownerFrame)
    return UI.ShouldProcess(ownerFrame)
end
