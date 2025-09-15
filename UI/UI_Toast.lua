local ADDON, ns = ...
ns.UI = ns.UI or {}
local UI = ns.UI
local Tr = ns.Tr

-- ==============================
--  UI.Toast : toasts génériques
-- ==============================
-- API :
--   UI.Toast({
--     title = "Titre",
--     text  = "Contenu du toast",
--     icon  = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew",
--     variant = "info" | "success" | "warning" | "error",
--     duration = 6,                         -- secondes ; <=0/false = illimitée
--     sticky = true,                        -- alias : durée illimitée
--     onClick  = function(frame) end,       -- clic sur le toast (ferme par défaut)
--     actionText = "Voir",                  -- (optionnel) bouton d'action
--     onAction   = function(frame) end,     -- callback bouton d'action
--     sound = SOUNDKIT.RAID_WARNING,        -- (optionnel)
--     key = "dedupe-key-optional",          -- dédoublonnage souple
--   })
--
--   UI.ToastError("Message", opts) -- raccourci variant="error"
--
-- Implementation : pile de toasts en haut-droite, auto-hide, clickable.
-- ==============================

local anchor
local active = {}
local dedupe = {}

local function _EnsureAnchor()
    if anchor then return anchor end
    anchor = CreateFrame("Frame", ADDON.."ToastAnchor", UIParent)
    anchor:SetSize(1,1)
    -- Place toasts where achievement notifications usually appear: top-center area
    anchor:SetPoint("TOP", UIParent, "TOP", 0, -120)
    anchor.toasts = {}
    return anchor
end

local function _VariantColors(variant)
    if variant == "success" then
        return { bg={0,0.35,0.15,0.92}, border={0.2,0.9,0.4,1} }
    elseif variant == "warning" then
        return { bg={0.35,0.25,0,0.92}, border={1,0.7,0.2,1} }
    elseif variant == "error" then
        return { bg={0.35,0,0,0.92}, border={1,0.25,0.25,1} }
    else -- info / default
        return { bg={0,0,0,0.85}, border={0.35,0.6,1,1} }
    end
end

local function _Reflow()
    local y = 0
    for i=1,#active do
        local f = active[i]
        f:ClearAllPoints()
        f:SetPoint("TOP", anchor, "TOP", 0, -y)
        y = y + f:GetHeight() + 8
    end
end

local function _Remove(f)
    for i=1,#active do
        if active[i] == f then
            table.remove(active, i)
            break
        end
    end
    _Reflow()
    f:Hide()
    f:SetScript("OnUpdate", nil)
end

local function _CreateToast(opts)
    local f = CreateFrame("Button", nil, _EnsureAnchor(), "BackdropTemplate")
    -- Target width; height will be forced by background atlas aspect ratio
    local TARGET_W = 360
    f:SetSize(TARGET_W, 64) -- temporary, height fixed after bg atlas is set
    f:SetFrameStrata("TOOLTIP")
    f:SetClampedToScreen(true)
    f:SetMovable(false)
    f:SetAlpha(0.999) -- évite un clignotement

    local colors = _VariantColors(opts.variant)
    -- Allow per-toast color overrides for background/border
    if type(opts.colors) == "table" then
        if type(opts.colors.bg) == "table" then colors.bg = opts.colors.bg end
        if type(opts.colors.border) == "table" then colors.border = opts.colors.border end
    end
    if type(opts.bg) == "table" then colors.bg = opts.bg end
    if type(opts.border) == "table" then colors.border = opts.border end

    -- Background using atlas frame (Centaur slate), lightly tinted by variant/colors
    -- This replaces the simple backdrop to achieve a nicer look with borders/corners.
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints(f)
    local _ATLAS = "UI-Centaur-Reward-Slate"
    f.bg:SetAtlas(_ATLAS, false)
    -- Preserve original atlas ratio: compute height from desired width
    local ratio = 0.5 -- fallback ratio if atlas info unavailable
    if C_Texture and C_Texture.GetAtlasInfo then
        local info = C_Texture.GetAtlasInfo(_ATLAS)
        if info and info.width and info.height and info.width > 0 then
            ratio = (info.height / info.width)
        end
    end
    local forcedH = math.max(64, math.floor(TARGET_W * ratio + 0.5))
    f:SetSize(TARGET_W, forcedH)
    -- Derive a subtle tint from the variant's border color (more saturated) or bg as fallback
    local cb = colors.border or {1,1,1,1}
    local tr = (cb[1] or 1)
    local tg = (cb[2] or 1)
    local tb = (cb[3] or 1)
    -- Gentle mix towards white for subtle coloration
    local function _mixToWhite(r,g,b, mix)
        mix = mix or 0.25 -- 25% white, 75% color
        return r*(1-mix)+1*mix, g*(1-mix)+1*mix, b*(1-mix)+1*mix
    end
    local r,g,b = _mixToWhite(tr, tg, tb, 0.20)
    f._tint = { r=r, g=g, b=b }
    f.bg:SetVertexColor(r, g, b, 1)

    -- Icone agrandie et centrée sur la bordure gauche du toast
    f.icon = f:CreateTexture(nil, "ARTWORK")
    local ICON_SIZE = 40
    f.icon:SetSize(ICON_SIZE, ICON_SIZE)
    -- Centre de l'icône aligné sur le bord gauche, centré verticalement sur la hauteur du toast
    f.icon:ClearAllPoints()
    f.icon:SetPoint("CENTER", f, "LEFT", 0, 0)
    f.icon:SetTexture(opts.icon or "Interface\\FriendsFrame\\InformationIcon")

    -- Titre
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    -- Aligner en haut-gauche avec un léger padding
    local PAD_L, PAD_T = 32, 16
    -- Slightly to the right so the icon center sits exactly on the inner border of the slate
    f.icon:SetPoint("CENTER", f, "LEFT", 6, 0)
    f.title:ClearAllPoints()
    f.title:SetPoint("TOPLEFT", f, "TOPLEFT", PAD_L, -PAD_T)
    f.title:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    f.title:SetJustifyH("LEFT")
    if f.title.SetWordWrap then f.title:SetWordWrap(true) end
    -- Applique d'abord la police, puis le texte pour garantir des métriques correctes
    if UI and UI.ApplyFont and f.title then UI.ApplyFont(f.title) end
    -- Agrandissement léger du titre
    do
        local font, size, flags = f.title:GetFont()
        if font and size then pcall(f.title.SetFont, f.title, font, size + 1, flags) end
    end
    f.title:SetText(opts.title or Tr("lbl_notification") or "Notification")

    -- Ligne dégradée sous le titre (teinte du toast)
    f.sep = f:CreateTexture(nil, "ARTWORK")
    f.sep:SetTexture("Interface\\Buttons\\WHITE8x8")
    f.sep:SetHeight(1)
    -- espace: 4 px sous le titre, longueur réduite de 4 px (2 px de chaque côté)
    f.sep:SetPoint("TOPLEFT",  f.title, "BOTTOMLEFT",  2, -4)
    f.sep:SetPoint("TOPRIGHT", f.title, "BOTTOMRIGHT", -2, -4)
    do
        -- Utilise la même couleur que le toast (teinte appliquée au fond)
        local tint = f._tint or {}
        local r = tint.r or (colors and colors.border and colors.border[1]) or (colors and colors.bg and colors.bg[1]) or 1
        local g = tint.g or (colors and colors.border and colors.border[2]) or (colors and colors.bg and colors.bg[2]) or 1
        local b = tint.b or (colors and colors.border and colors.border[3]) or (colors and colors.bg and colors.bg[3]) or 1
        local a1, a2 = 0.90, 0.05
        if f.sep.SetGradient and CreateColor then
            f.sep:SetGradient("HORIZONTAL", CreateColor(r,g,b,a1), CreateColor(r,g,b,a2))
        else
            -- Fallback : couleur pleine (sans dégradé) si API gradient indisponible
            f.sep:SetVertexColor(r,g,b,a1)
        end
    end

    -- Colorise le titre avec une teinte pastel basée sur la couleur du toast
    do
        local tint = f._tint or {}
        local tr = tint.r or (colors and colors.border and colors.border[1]) or (colors and colors.bg and colors.bg[1]) or 1
        local tg = tint.g or (colors and colors.border and colors.border[2]) or (colors and colors.bg and colors.bg[2]) or 1
        local tb = tint.b or (colors and colors.border and colors.border[3]) or (colors and colors.bg and colors.bg[3]) or 1
        local pr, pg, pb = _mixToWhite(tr, tg, tb, 0.55)
        if f.title.SetTextColor then f.title:SetTextColor(pr, pg, pb, 1) end
    end

    -- Texte principal
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    -- Texte sous le séparateur avec un petit espacement
    f.text:ClearAllPoints()
    f.text:SetPoint("TOPLEFT", f.sep, "BOTTOMLEFT", 0, -6)
    f.text:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    f.text:SetJustifyH("LEFT")
    f.text:SetSpacing(2)
    -- Applique d'abord la police, puis le texte (évite un calcul de hauteur sur mauvaise fonte)
    if UI and UI.ApplyFont and f.text then UI.ApplyFont(f.text) end
    if f.text.SetWordWrap then f.text:SetWordWrap(true) end
    if f.text.SetNonSpaceWrap then f.text:SetNonSpaceWrap(true) end
    -- Augmente légèrement la taille du texte (sans toucher au titre)
    do
        local font, size, flags = f.text:GetFont()
        if font and size then pcall(f.text.SetFont, f.text, font, size + 1, flags) end
    end
    f.text:SetText(opts.text or "")

    -- Indice (footer) centré en bas : "Cliquer pour fermer la notification"
    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    if UI and UI.ApplyFont then UI.ApplyFont(f.hint) end
    -- Plus petit et semi-transparent
    do
        local font, size, flags = f.hint:GetFont()
        if font and size then pcall(f.hint.SetFont, f.hint, font, math.max(8, size - 1), flags) end
    end
    f.hint:SetText((Tr and Tr("toast_hint_click_close")) or "Click to dismiss the notification")
    f.hint:SetJustifyH("CENTER")
    f.hint:ClearAllPoints()
    f.hint:SetPoint("BOTTOM", f, "BOTTOM", 0, 17)
    if f.hint.SetTextColor then f.hint:SetTextColor(0.8, 0.8, 0.8, 0.5) end

    -- Bouton action (optionnel)
    if opts.actionText and opts.onAction then
        f.action = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.action:SetText(opts.actionText)
        f.action:SetSize(80, 20)
        f.action:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 8)
        f.action:SetScript("OnClick", function()
            pcall(opts.onAction, f)
            _Remove(f)
        end)
    end

    -- Resize toast height to fit multi-line text (no trimming)
    local function _resizeToFit()
        if not f.text then return end
        -- Insets inside the slate to avoid edges
        local topInset, bottomInset = PAD_T, 10
        -- Hauteurs des éléments
        local sepH = (f.sep and f.sep.GetHeight and f.sep:GetHeight()) or 0
        local betweenTitle = sepH + 4 + 6 -- 4px au-dessus du sep, 6px en-dessous avant le texte
        local actionH = (f.action and 24 or 0) + (f.action and 6 or 0)
        local hintH = (f.hint and f.hint.GetStringHeight and f.hint:GetStringHeight()) or 10

    -- Définir explicitement la largeur pour garantir le word-wrap
    local TEXT_LEFT = PAD_L + 2
    local TEXT_RIGHT = 10
    local textW = math.max(50, (f:GetWidth() or TARGET_W) - TEXT_LEFT - TEXT_RIGHT)
    if f.text.SetWidth then f.text:SetWidth(textW) end

    -- Utiliser le texte complet et mesurer la hauteur réelle
        local full = f._origText or (f.text.GetText and f.text:GetText()) or ""
        f._origText = full
        f.text:SetText(full)

        -- Assurer que les métriques sont à jour pour cette largeur
        local th = (f.title and f.title.GetStringHeight and f.title:GetStringHeight()) or 0
    local txh = (f.text and f.text.GetStringHeight and f.text:GetStringHeight()) or 0

        local needed = math.max(forcedH, math.floor(topInset + th + betweenTitle + txh + hintH + actionH + bottomInset + 2))
        if math.abs((f:GetHeight() or 0) - needed) > 0.5 then
            f:SetHeight(needed)
            -- Reflow the stack since our height changed
            if type(_Reflow) == "function" then _Reflow() end
        end
    end
    _resizeToFit()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, _resizeToFit)
    end
    f:HookScript("OnShow", function()
        if C_Timer and C_Timer.After then C_Timer.After(0, _resizeToFit) end
    end)

    -- Interactions
    f:SetScript("OnEnter", function(self)
        -- Lighten the tint slightly on hover
        local t = self._tint or { r=1, g=1, b=1 }
        local hr = math.min(1, t.r*1.05)
        local hg = math.min(1, t.g*1.05)
        local hb = math.min(1, t.b*1.05)
        if self.bg then self.bg:SetVertexColor(hr, hg, hb, 1) end
    end)
    f:SetScript("OnLeave", function(self)
        local t = self._tint or { r=1, g=1, b=1 }
        if self.bg then self.bg:SetVertexColor(t.r, t.g, t.b, 1) end
    end)
    f:SetScript("OnClick", function(self)
        if opts.onClick then pcall(opts.onClick, self) end
        _Remove(self)
    end)

    -- Auto-hide (durée illimitée si sticky=true, ou duration<=0 / false / nil)
    local sticky = (opts.sticky == true)
                   or (opts.duration == false)
                   or (type(opts.duration) == "number" and opts.duration <= 0)
    if not sticky then
        local t0, dur = GetTime(), tonumber(opts.duration or 6)
        f:SetScript("OnUpdate", function(self)
            if (GetTime() - t0) >= dur then _Remove(self) end
        end)
    else
        f:SetScript("OnUpdate", nil) -- pas d'auto-hide, clic pour fermer
    end


    -- Son
    if opts.sound then
        pcall(PlaySound, opts.sound)
    end

    return f
end

function UI.Toast(opts)
    opts = type(opts)=="table" and opts or { text = tostring(opts or "") }
    -- Dédoublonnage souple court (3s) par clé
    if opts.key and dedupe[opts.key] then
        if (GetTime() - dedupe[opts.key]) < 3 then return end
    end
    if opts.key then dedupe[opts.key] = GetTime() end

    local f = _CreateToast(opts)
    table.insert(active, 1, f)
    _Reflow()
    f:Show()
    return f
end

function UI.ToastError(text, opts)
    opts = opts or {}
    opts.text    = text
    opts.variant = "error"
    opts.icon    = opts.icon or "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew"
    opts.title   = opts.title or (Tr and Tr("toast_error_title")) or "Lua Error"
    opts.sound   = false--(opts.sound ~= false) and (SOUNDKIT and SOUNDKIT.RAID_WARNING) or nil
    return UI.Toast(opts)
end
