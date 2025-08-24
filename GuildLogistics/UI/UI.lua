local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG = ns.GLOG

ns.UI = ns.UI or {}
local UI = ns.UI

UI.DEFAULT_W, UI.DEFAULT_H = 1360, 680
UI.OUTER_PAD, UI.SCROLLBAR_W, UI.GUTTER, UI.ROW_H = 16, 20, 8, 30
UI.FONT_YELLOW = {1, 0.82, 0}
UI.WHITE = {1,1,1}
UI.ACCENT = {0.22,0.55,0.95}
UI.FOOTER_RIGHT_PAD = UI.FOOTER_RIGHT_PAD or 8
UI.TITLE_SYNC_PAD_RIGHT = UI.TITLE_SYNC_PAD_RIGHT or 40
UI.NAV_SUBSEL_COLOR = { 0.16, 0.82, 0.27, 0.50 } -- r,g,b,a
-- Style des footers (centralisé)
UI.FOOTER_H            = UI.FOOTER_H            or 36
UI.FOOTER_BG           = UI.FOOTER_BG           or {0, 0, 0, 0.22}
UI.FOOTER_GRAD_TOP     = UI.FOOTER_GRAD_TOP     or {1, 1, 1, 0.05}
UI.FOOTER_GRAD_BOTTOM  = UI.FOOTER_GRAD_BOTTOM  or {0, 0, 0, 0.15}
UI.FOOTER_BORDER       = UI.FOOTER_BORDER       or {1, 1, 1, 0.12}

UI.TAB_EXTRA_GAP       = UI.TAB_EXTRA_GAP       or 14
UI.CONTENT_SIDE_PAD    = UI.CONTENT_SIDE_PAD    or -23
UI.CONTENT_BOTTOM_LIFT = UI.CONTENT_BOTTOM_LIFT or -20
UI.TAB_LEFT_PAD        = UI.TAB_LEFT_PAD        or 18
UI.CATEGORY_GAP_TOP    = UI.CATEGORY_GAP_TOP    or 10

-- Utilitaires : formatage avec séparateur de milliers
UI.NUM_THOUSANDS_SEP = UI.NUM_THOUSANDS_SEP or " "
function UI.FormatThousands(v, sep)
    local n  = math.floor(math.abs(tonumber(v) or 0))
    local s  = tostring(n)
    local sp = sep or UI.NUM_THOUSANDS_SEP or " "
    local out, k = s, 0
    repeat
        out, k = out:gsub("^(%d+)(%d%d%d)", function(a, b) return a .. sp .. b end)
    until k == 0
    return out
end

function UI.MoneyText(v)
    v = tonumber(v) or 0
    local n = math.floor(math.abs(v) + 0.5)
    local iconG = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t"
    local txt = UI.FormatThousands(n) .. " " .. iconG
    if v < 0 then return "|cffff4040-" .. txt .. "|r" else return txt end
end

function UI.MoneyFromCopper(copper)
    local n = tonumber(copper) or 0
    local abs = math.abs(n)
    local g = math.floor(abs / 10000); local rem = abs % 10000
    local s = math.floor(rem / 100);   local c   = rem % 100
    local iconG = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t"
    local iconS = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t"
    local iconC = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t"
    local parts = {}
    if g > 0 then table.insert(parts, UI.FormatThousands(g) .. " " .. iconG) end
    if s > 0 then table.insert(parts, s .. " " .. iconS) end
    if c > 0 or #parts == 0 then table.insert(parts, c .. " " .. iconC) end
    local txt = table.concat(parts, " ")
    if n < 0 then return "|cffff4040-" .. txt .. "|r" else return txt end
end

-- ========= Couleurs utilitaires =========
-- Convertit des RGB [0..1] en "rrggbb"
function UI.RGBHex(r, g, b)
    local function clamp(x) x = tonumber(x) or 0; if x < 0 then return 0 elseif x > 1 then return 1 else return x end end
    r, g, b = clamp(r), clamp(g), clamp(b)
    return string.format("%02x%02x%02x", math.floor(r*255+0.5), math.floor(g*255+0.5), math.floor(b*255+0.5))
end

-- Entoure un texte avec un code couleur WoW
function UI.Colorize(text, r, g, b)
    return "|cff" .. UI.RGBHex(r,g,b) .. tostring(text) .. "|r"
end

function UI.ColorizeOffline(text)
    local hex = UI.GRAY_OFFLINE_HEX or "999999"
    return "|cff" .. tostring(hex) .. tostring(text) .. "|r"
end

-- Couleur "difficulté de quête" pour un niveau donné (par rapport au joueur)
function UI.ColorizeLevel(level)
    local lvl = tonumber(level)
    if not lvl or lvl <= 0 then return "" end

    local c = GetQuestDifficultyColor and GetQuestDifficultyColor(lvl)
    if not c or not c.r then
        -- Fallback simple si l'API n'est pas dispo
        local pl   = (UnitLevel and UnitLevel("player")) or lvl
        local diff = (lvl - pl)
        local greenRange = (GetQuestGreenRange and GetQuestGreenRange()) or 5
        if diff >= 5 then
            c = { r=1,   g=0.1, b=0.1 }       -- rouge
        elseif diff >= 3 then
            c = { r=1,   g=0.5, b=0.25 }      -- orange
        elseif diff >= -2 then
            c = { r=1,   g=0.82, b=0 }        -- jaune
        elseif diff > -greenRange then
            c = { r=0.25,g=0.75, b=0.25 }     -- vert
        else
            c = { r=0.5, g=0.5,  b=0.5 }      -- gris
        end
    end
    return "|cff" .. UI.RGBHex(c.r,c.g,c.b) .. tostring(lvl) .. "|r"
end


function UI.GetPopupAmountFromSelf(popupSelf)
    if not popupSelf then return 0 end
    local eb = popupSelf.editBox or popupSelf.EditBox
    if not eb then
        local n = popupSelf.GetName and popupSelf:GetName()
        if n and _G[n.."EditBox"] then eb = _G[n.."EditBox"] end
    end
    if eb then
        if eb.GetNumber then return eb:GetNumber()
        elseif eb.GetText then return tonumber(eb:GetText()) or 0 end
    end
    return 0
end

function UI.Key(s)
    s = tostring(s or "")
    s = s:gsub("[^%w_]", "_")
    return s
end

-- ===================== Fenêtre principale =====================
local Main = CreateFrame("Frame", "GLOG_Main", UIParent, "BackdropTemplate")
UI.Main = Main
local saved = GLOG.GetSavedWindow and GLOG.GetSavedWindow() or {}
Main:SetSize(UI.DEFAULT_W, UI.DEFAULT_H)
Main:SetFrameStrata("HIGH")
Main:SetMovable(true)
Main:EnableMouse(true)
Main:RegisterForDrag("LeftButton")
Main:SetScript("OnDragStart", function(self) self:StartMoving() end)
Main:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, relTo, relPoint, x, y = self:GetPoint()
    if GLOG.SaveWindow then
        GLOG.SaveWindow(point, relTo and relTo:GetName() or nil, relPoint, x, y)
    end
end)

Main:SetPoint(saved.point or "CENTER", UIParent, saved.relPoint or "CENTER", saved.x or 0, saved.y or 0)

-- Habillage atlas Neutral
local skin = UI.ApplyNeutralFrameSkin(Main, { showRibbon = false })

-- Conteneur borné pour le contenu des onglets
Main.Content = CreateFrame("Frame", nil, Main)
local L,R,T,B = UI.OUTER_PAD, UI.OUTER_PAD, UI.OUTER_PAD, UI.OUTER_PAD
if Main._cdzNeutral and Main._cdzNeutral.GetInsets then
    L,R,T,B = Main._cdzNeutral:GetInsets()
end
local TAB_Y, TAB_H = -40, 18
local GAP   = UI.TAB_EXTRA_GAP or 15
local SIDE  = UI.CONTENT_SIDE_PAD or 12
local BOT   = UI.CONTENT_BOTTOM_LIFT or 6
Main.Content:SetPoint("TOPLEFT",     Main, "TOPLEFT",     L + SIDE, (TAB_Y - TAB_H - GAP))
Main.Content:SetPoint("BOTTOMRIGHT", Main, "BOTTOMRIGHT", -(R + SIDE), B + BOT)
Main.Content:SetClipsChildren(true)

-- 🔶 Titre principal = nom de l’addon (jaune + plus grand)
Main.title = Main:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
Main.titleAddon = Main.title  -- alias pour compatibilité
local addonName = (GLOG.GetAddonTitle and GLOG.GetAddonTitle()) or (Tr and Tr("app_title")) or ADDON
Main.titleAddon:SetText(addonName)

do
    local y = UI.FONT_YELLOW or {1, 0.82, 0}
    Main.titleAddon:SetTextColor(y[1], y[2], y[3], 1)
    -- Grossit légèrement par rapport au GameFontHighlightLarge
    local f, sz, fl = Main.titleAddon:GetFont()
    if f then Main.titleAddon:SetFont(f, math.floor((sz or 14) * 1.25 + 0.5), fl) end
end

-- 🔸 Version à droite du nom (gris, entre parenthèses)
Main.titleVersion = Main:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
do
    local ver = (GLOG.GetAddonVersion and GLOG.GetAddonVersion()) or ""
    local txt = (ver ~= "" and ("("..ver..")")) or ""
    Main.titleVersion:SetText(txt)
    Main.titleVersion:SetTextColor(0.70, 0.70, 0.70, 1)
    Main.titleVersion:ClearAllPoints()
    -- collé à droite du nom de l’addon
    Main.titleVersion:SetPoint("LEFT", Main.titleAddon, "RIGHT", 8, 0)
    Main.titleVersion:SetShown(txt ~= "")
end

do
    local _, _, TOP = skin:GetInsets()
    Main.titleAddon:ClearAllPoints()
    Main.titleAddon:SetPoint("TOP", Main, "TOP", 0, -(TOP - 36))
end

-- 🔷 Sous-titre = nom de la guilde (blanc doux)
Main.titleGuild = Main:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
Main.titleGuild:SetText(GLOG.GetCurrentGuildName and (GLOG.GetCurrentGuildName() or "") or "")
Main.titleGuild:SetTextColor(0.98, 0.95, 0.90, 1)
Main.titleGuild:ClearAllPoints()
Main.titleGuild:SetPoint("TOP", Main.titleAddon, "BOTTOM", 0, -2)
Main.titleGuild:SetShown((Main.titleGuild:GetText() or "") ~= "")

-- Bouton fermer standard (possibilité d'utiliser l'atlas UI-Frame-Neutral-ExitButtonBorder plus tard)
local close = CreateFrame("Button", nil, Main, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", Main, "TOPRIGHT", 2, 2)

-- ➕ Bouton Reload au même niveau que la croix (dans la barre titre)
local reloadBtn = CreateFrame("Button", ADDON.."ReloadButton", Main, "UIPanelButtonTemplate")
reloadBtn:SetSize(60, 20)
reloadBtn:SetText(Tr("btn_reload"))
-- S'assure d'être au-dessus du contenu, comme le bouton X
reloadBtn:SetFrameStrata(close:GetFrameStrata())
reloadBtn:SetFrameLevel(close:GetFrameLevel())

-- Placé juste à gauche du X
reloadBtn:ClearAllPoints()
reloadBtn:SetPoint("TOPRIGHT", close, "TOPLEFT", -6, 0)
reloadBtn:SetScript("OnClick", function() ReloadUI() end)

-- ➕ Expose des références globales pour contrôle de visibilité
UI.ReloadButton = reloadBtn

-- ➕ Indicateur de synchronisation (barre de titre, aligné à droite)
local syncPanel = CreateFrame("Frame", nil, Main)
syncPanel:Hide()
-- Même strata/level que la croix : passe au-dessus de l'overlay du skin
syncPanel:SetFrameStrata(close:GetFrameStrata())
syncPanel:SetFrameLevel(close:GetFrameLevel())

-- Positionneur : ancre au bord droit du bandeau rouge (titleRight),
-- centré verticalement dans ce bandeau, avec un padding configurable.
local function PositionSyncIndicator()
    syncPanel:ClearAllPoints()
    local pad = tonumber(UI.TITLE_SYNC_PAD_RIGHT or 12)

    local s  = Main._cdzNeutral
    local tr = s and s.title and s.title.right or nil
    if tr then
        -- Centré verticalement dans le bandeau + collé au bord droit du "TitleRight"
        syncPanel:SetPoint("RIGHT", tr, "RIGHT", -pad, 0)
    elseif reloadBtn and reloadBtn.GetObjectType then
        syncPanel:SetPoint("TOPRIGHT", reloadBtn, "TOPLEFT", -12, 0)
    else
        syncPanel:SetPoint("TOPRIGHT", Main, "TOPRIGHT", -64, -2)
    end
end
PositionSyncIndicator()
syncPanel:SetHeight(20)

local syncText = syncPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
syncText:SetDrawLayer("OVERLAY", 3)
syncText:SetPoint("RIGHT", syncPanel, "RIGHT", 0, 0)
syncText:SetJustifyH("RIGHT")
syncText:SetText("")

-- Animation par points « … »
local syncTicker
local function _startSyncAnim(base)
    -- si 'base' est une clé, on traduit ; si c'est l'ancien texte FR/EN, l'alias fera le relais
    local keyOrLegacy = base or "sync_data"
    base = (Tr and Tr(keyOrLegacy)) or tostring(keyOrLegacy)
    if syncTicker and syncTicker.Cancel then syncTicker:Cancel() end
    local dots = 0
    syncPanel:Show()
    syncText:SetText(base .. "…")
    syncPanel:SetWidth(syncText:GetStringWidth() + 4)
    syncTicker = C_Timer.NewTicker(0.4, function()
        dots = (dots % 3) + 1
        local suffix = string.rep(".", dots)
        syncText:SetText(string.format("%s%s", base, suffix))
        syncPanel:SetWidth(syncText:GetStringWidth() + 4)
    end)
end

local function _stopSyncAnim()
    if syncTicker and syncTicker.Cancel then syncTicker:Cancel() end
    syncTicker = nil
    syncPanel:Hide()
end

-- API publique
function UI.SyncIndicatorShow(msg) _startSyncAnim(msg) end
function UI.SyncIndicatorHide() _stopSyncAnim() end

-- Coupe l’animation si la fenêtre est masquée
Main:HookScript("OnHide", function()
    if UI.SyncIndicatorHide then UI.SyncIndicatorHide() end
end)

-- Branchements : affichage dès réception du 1er fragment, arrêt à la fin
if ns and ns.On then
    ns.On("sync:begin", function()
        if UI.SyncIndicatorShow then UI.SyncIndicatorShow("sync_data") end
    end)
    ns.On("sync:end", function()
        if UI.SyncIndicatorHide then UI.SyncIndicatorHide() end
    end)
end

-- ===================== Tabs =====================
local Registered, Panels, Tabs = {}, {}, {}
UI._tabIndexByLabel = {}

-- UI.RegisterTab(label, build, refresh, layout, opts?) ; opts.hidden pour masquer le bouton d’onglet
function UI.RegisterTab(label, buildFunc, refreshFunc, layoutFunc, opts)
    opts = opts or {}
    table.insert(Registered, {
        label   = label,
        build   = buildFunc,
        refresh = refreshFunc,
        layout  = layoutFunc,
        hidden  = opts.hidden or false,
        category= opts.category, -- << NOUVEAU
    })
    UI._tabIndexByLabel[label] = #Registered
end

local function ShowPanel(idx)
    for i,p in ipairs(Panels) do p:SetShown(i == idx) end
    UI._current = idx

    for i, def in ipairs(Registered) do
        local b = def._btn
        if b then
            local isSel = (i == idx)
            if b.sel     then b.sel:SetShown(isSel)     end
            if b.selGrad then b.selGrad:SetShown(isSel) end  -- << dégradé activé sur la sous-sélection

            -- Ajuste la mise en forme selon le type de bouton
            if b.txt and b.txt.SetFontObject then
                b.txt:SetFontObject(isSel and "GameFontHighlightSmall" or "GameFontHighlightSmall")
            elseif b.SetNormalFontObject then
                b:SetNormalFontObject(isSel and "GameFontHighlightLarge" or "GameFontHighlight")
            end
        end
    end
end
UI.ShowPanel = ShowPanel

-- Création d’un bouton d’onglet basé sur le précédent visible
-- Remplace : Création d’un bouton d’onglet
-- Si la barre latérale existe, on fabrique un sous-élément intégré à la sidebar.
-- Sinon, on retombe sur l’ancien bouton horizontal en haut.
local function _CreateTopTabButton(prevBtn, text)
    local b = CreateFrame("Button", nil, Main, "UIPanelButtonTemplate")
    b:SetText(text)
    b:SetSize(150, 26)
    if not prevBtn then
        local L = UI.OUTER_PAD
        if Main._cdzNeutral and Main._cdzNeutral.GetInsets then
            L = (Main._cdzNeutral:GetInsets())
        end
        b:SetPoint("TOPLEFT", Main, "TOPLEFT", L + (UI.TAB_LEFT_PAD or 12), -52)
    else
        b:SetPoint("LEFT", prevBtn, "RIGHT", 8, 0)
    end

    local sel = b:CreateTexture(nil, "OVERLAY")
    sel:SetColorTexture(UI.ACCENT[1], UI.ACCENT[2], UI.ACCENT[3], 0.8)
    sel:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 6, -3)
    sel:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -6, -3)
    sel:SetHeight(3)
    sel:Hide()
    b.sel = sel
    return b
end

local function _SubTabButton(parent, text)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetHeight(24) -- plus petit pour marquer la hiérarchie

    -- Fond & hover
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints(b)
    b.bg:SetColorTexture(0,0,0,0.50)

    b.hover = b:CreateTexture(nil, "OVERLAY")
    b.hover:SetAllPoints(b)
    b.hover:SetColorTexture(1,1,1,0.12)
    b.hover:Hide()

    -- === Couleur du liseré (source du dégradé) ===
    local cr, cg, cb, ca = 0.16, 0.82, 0.27, 0.50
    if UI and UI.NAV_SUBSEL_COLOR then
        cr = UI.NAV_SUBSEL_COLOR[1] or cr
        cg = UI.NAV_SUBSEL_COLOR[2] or cg
        cb = UI.NAV_SUBSEL_COLOR[3] or cb
        ca = UI.NAV_SUBSEL_COLOR[4] or ca
    end

    -- Liseré vertical à gauche
    b.sel = b:CreateTexture(nil, "OVERLAY")
    b.sel:SetPoint("TOPLEFT", b, "TOPLEFT", 0,  0)
    b.sel:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 8, 0)
    b.sel:SetWidth(3)
    b.sel:SetColorTexture(cr, cg, cb, ca)
    b.sel:Hide()

    -- Dégradé horizontal (gauche -> droite), même teinte que le liseré,
    -- qui disparaît vers la droite (alpha 0).
    b.selGrad = b:CreateTexture(nil, "ARTWORK")
    b.selGrad:SetTexture("Interface\\Buttons\\WHITE8x8") -- IMPORTANT : base de texture pour le gradient
    b.selGrad:ClearAllPoints()
    b.selGrad:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    b.selGrad:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)

    local startAlpha = math.max(0.25, math.min(0.50, (ca or 0.5) * 0.9))
    if b.selGrad.SetGradient and type(CreateColor) == "function" then
        b.selGrad:SetGradient("HORIZONTAL",
            CreateColor(cr, cg, cb, startAlpha),
            CreateColor(cr, cg, cb, 0)
        )
    elseif b.selGrad.SetGradientAlpha then
        b.selGrad:SetGradientAlpha("HORIZONTAL",
            cr, cg, cb, startAlpha,
            cr, cg, cb, 0
        )
    else
        -- Fallback très ancien client
        b.selGrad:SetColorTexture(cr, cg, cb, startAlpha)
    end
    b.selGrad:Hide()

    -- Texte (petite taille + indentation pour signifier « sous-élément »)
    b.txt = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.txt:SetPoint("LEFT", b, "LEFT", 18, 0)
    b.txt:SetJustifyH("LEFT")
    b.txt:SetText(text)

    b:SetScript("OnEnter", function(self) self.hover:Show() end)
    b:SetScript("OnLeave", function(self) self.hover:Hide() end)

    return b
end

local function CreateTabButton(prevBtn, text)
    if UI._catBar and UI._catBar._subList then
        return _SubTabButton(UI._catBar._subList, text)
    else
        return _CreateTopTabButton(prevBtn, text)
    end
end

function UI.Finalize()
    -- 1) Crée la barre catégories AVANT de construire le contenu, pour que
    -- ApplySafeContentBounds connaisse la marge gauche.
    if not UI._catBar and UI.CreateCategorySidebar then
        UI.CreateCategorySidebar()
    end

    local lastBtn
    for i, def in ipairs(Registered) do
        local panel = CreateFrame("Frame", nil, Main.Content, "BackdropTemplate")
        panel:SetAllPoints(Main.Content)
        Panels[i] = panel
        def.panel = panel

        local bg = panel:CreateTexture(nil, "BACKGROUND")
        bg:SetColorTexture(1,1,1,0.03)
        bg:SetAllPoints()

        if def.build then def.build(panel) end

        if not def.hidden then
            local btn = CreateTabButton(lastBtn, def.label)
            btn:SetScript("OnClick", function()
                -- Bascule auto de catégorie si besoin
                if UI.SelectCategoryForLabel then UI.SelectCategoryForLabel(def.label) end
                ShowPanel(i)
                if def.refresh then def.refresh() end
            end)
            def._btn = btn
            lastBtn = btn
            table.insert(Tabs, btn)
        else
            def._btn = nil
        end
    end

    -- Applique le filtre catégorie sur les boutons (si la barre existe)
    if UI._activeCategory and UI.SetActiveCategory then
        UI.SetActiveCategory(UI._activeCategory)
    end
end

-- Navigation par label
function UI.ShowTabByLabel(label)
    -- Si l'onglet n'est pas visible dans la catégorie courante, on bascule vers la bonne catégorie
    if UI.SelectCategoryForLabel and UI.SelectCategoryForLabel(label) then
        -- la catégorie a été ajustée pour révéler cet onglet
    end

    local idx = UI._tabIndexByLabel and UI._tabIndexByLabel[label]
    if idx then
        -- Rendre visible le bouton si caché uniquement par le filtre de catégorie
        local def = Registered[idx]
        if def and def._btn and def._sysShown ~= false then
            def._btn:Show()
        end
        ShowPanel(idx)
        if def and def.refresh then def.refresh() end
        UI.RelayoutTabs()
    end
end

function UI.RefreshAll()
    local i = UI._current
    if i and Registered[i] and Registered[i].refresh then Registered[i].refresh() end
    -- Rafraîchit les indicateurs globaux (pastilles, icônes d'état, etc.)
    if UI.RefreshTopIndicators then UI.RefreshTopIndicators() end
end
ns.RefreshAll = UI.RefreshAll

-- ➕ Récupération du bouton d'un onglet par label
function UI.GetTabButton(label)
    local idx = UI._tabIndexByLabel and UI._tabIndexByLabel[label]
    local def = idx and Registered[idx] or nil
    return def and def._btn, idx
end

-- ➕ Reflow des onglets visibles
function UI.RelayoutTabs()
    -- Si la barre latérale avec sous-liste existe, on dispose les onglets comme sous-éléments
    if UI._catBar and UI._catBar._subList then
        local bar    = UI._catBar
        local sub    = bar._subList
        local list   = bar._list
        local active = UI._activeCategory
        local GAP_CAT = UI.CATEGORY_GAP_TOP or 5  -- espacement conditionnel
        local GAP_LINE = 1                         -- fin trait / interligne

        -- 1) Comptage des sous-onglets "présents" par catégorie (indépendant de la catégorie active)
        local perCatCount = {}
        for _, def in ipairs(Registered or {}) do
            local cat = def.category
            if cat and (def.hidden ~= true) and (def._sysShown ~= false) then
                perCatCount[cat] = (perCatCount[cat] or 0) + 1
            end
        end

        -- 2) Affiche/masque les boutons de catégories selon perCatCount
        if bar._btns then
            for _, cb in ipairs(bar._btns) do
                local label = cb.txt and cb.txt:GetText()
                local show  = (perCatCount[label] or 0) > 0
                cb:SetShown(show)
            end
        end

        -- 3) Si la catégorie active est vide, bascule vers la première non vide
        if (not active) or (perCatCount[active] or 0) == 0 then
            local firstNonEmpty
            for _, cb in ipairs(bar._btns or {}) do
                if cb:IsShown() and cb.txt then
                    firstNonEmpty = cb.txt:GetText()
                    break
                end
            end
            if firstNonEmpty and UI.SetActiveCategory then
                UI.SetActiveCategory(firstNonEmpty)
                return
            end
        end

        -- 4) Récupère les sous-onglets visibles (déjà filtrés par SetActiveCategory)
        local visibles = {}
        for _, def in ipairs(Registered or {}) do
            local b = def._btn
            if b and b:IsShown() and ((not def.category) or def.category == active) then
                table.insert(visibles, b)
            end
        end

        -- 5) Trouve le bouton de catégorie actif
        local selCatBtn
        for _, b in ipairs(bar._btns or {}) do
            if b:IsShown() and b.txt and (b.txt:GetText() == active) then
                selCatBtn = b
                break
            end
        end

        -- Aucune catégorie visible (toutes vides) : on masque la sous-liste et on compacte
        if not selCatBtn then
            sub:Hide()
            local prev
            for _, b in ipairs(bar._btns or {}) do
                if b:IsShown() then
                    b:ClearAllPoints()
                    if not prev then
                        b:SetPoint("TOPLEFT",  list, "TOPLEFT",  0, 0)
                    else
                        b:SetPoint("TOPLEFT",  prev, "BOTTOMLEFT", 0, -GAP_LINE)
                    end
                    b:SetPoint("RIGHT", list, "RIGHT", -1, 0)
                    prev = b
                end
            end
            if bar._filler and prev then
                bar._filler:ClearAllPoints()
                bar._filler:SetPoint("TOPLEFT",     prev, "BOTTOMLEFT", 0, -GAP_LINE)
                bar._filler:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -1, 0)
                bar._filler:SetColorTexture(1,1,1,0.04)
            end
            return
        end

        -- 6) Positionne la sous-liste & sous-onglets (PLEINE LARGEUR des sous-éléments)
        local GAP, TOP_PAD, BOTTOM_PAD = 1, 1, 1

        -- Sous-liste ancrée juste sous le bouton de catégorie (1 px d’air)
        sub:ClearAllPoints()
        sub:SetPoint("TOPLEFT",  selCatBtn, "BOTTOMLEFT", 0, -TOP_PAD)
        sub:SetPoint("RIGHT",    bar, "RIGHT", -1, 0)

        -- Disposition des boutons (pleine largeur : LEFT=0, RIGHT=0)
        local totalH = TOP_PAD + BOTTOM_PAD
        local prevRow
        for i, b in ipairs(visibles) do
            b:ClearAllPoints()
            if not prevRow then
                b:SetPoint("TOPLEFT", sub, "TOPLEFT", 0, -TOP_PAD)
            else
                b:SetPoint("TOPLEFT", prevRow, "BOTTOMLEFT", 0, -GAP)
            end
            b:SetPoint("RIGHT", sub, "RIGHT", 0, 0) -- << pleine largeur
            prevRow = b
            totalH = totalH + (b:GetHeight() or 24)
            if i > 1 then totalH = totalH + GAP end
        end
        sub:SetHeight(totalH)
        sub:SetShown(#visibles > 0)

        -- 7) Reflow des catégories
        --    * Ajoute GAP_CAT au-dessus de la catégorie active (sauf si première visible)
        --    * Ajoute GAP_CAT entre la catégorie active (ouverte) et la suivante
        local prev
        for _, b in ipairs(bar._btns or {}) do
            if b:IsShown() then
                b:ClearAllPoints()
                if not prev then
                    -- Première visible : jamais d'espacement au-dessus
                    b:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
                else
                    local extra = 0
                    -- si la précédente est la catégorie active : on réserve la sous-liste
                    if prev == selCatBtn then
                        extra = (sub:IsShown() and sub:GetHeight() or 0)
                        -- et on ajoute l'espacement sous la catégorie active ouverte
                        extra = extra + GAP_CAT
                    end
                    -- si la catégorie courante est la catégorie active : espacement au-dessus,
                    -- sauf si c'est la toute première (déjà gérée par le cas not prev)
                    if b == selCatBtn then
                        extra = extra + GAP_CAT
                    end
                    b:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -(GAP_LINE + extra))
                end
                b:SetPoint("RIGHT", list, "RIGHT", -1, 0)
                prev = b
            end
        end

        -- 8) Filler visuel sous la dernière catégorie
        if bar._filler and prev then
            bar._filler:ClearAllPoints()
            bar._filler:SetPoint("TOPLEFT",     prev, "BOTTOMLEFT", 0, -GAP_LINE)
            bar._filler:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -1, 0)
            bar._filler:SetColorTexture(1,1,1,0.04)
        end

        return
    end

    -- Fallback : ancien layout horizontal en haut (au cas où)
    local Main = UI.Main
    local lastBtn
    for _, def in ipairs(Registered or {}) do
        local b = def._btn
        if b then
            b:ClearAllPoints()
            if b:IsShown() then
                if not lastBtn then
                    local L = UI.OUTER_PAD
                    if Main and Main._cdzNeutral and Main._cdzNeutral.GetInsets then
                        L = (Main._cdzNeutral:GetInsets())
                    end
                    b:SetPoint("TOPLEFT", Main, "TOPLEFT", L + (UI.TAB_LEFT_PAD or 12), -52)
                else
                    b:SetPoint("LEFT", lastBtn, "RIGHT", 8, 0)
                end
                lastBtn = b
            end
        end
    end
end

-- ➕ Masquer/afficher un onglet avec fallback si on masque l'onglet actif
function UI.SetTabVisible(label, shown)
    local idx = UI._tabIndexByLabel and UI._tabIndexByLabel[label]
    if not idx then return end
    local def = Registered[idx]
    local b   = def and def._btn
    if not b then return end

    -- Mémorise la visibilité “système” (droits, états, options…)
    def._sysShown = (shown and true) or false

    -- Filtre par catégorie active
    local inCat = true
    local active = UI._activeCategory
    if active and def.category and (def.category ~= active) then
        inCat = false
    end

    local willShow = def._sysShown and inCat
    local wasShown = b:IsShown()
    b:SetShown(willShow)

    -- Si on masque l’onglet actif, bascule sur le premier visible
    if wasShown and (not willShow) and UI._current == idx then
        for i, d in ipairs(Registered) do
            if d._btn and d._btn:IsShown() then
                UI.ShowPanel(i)
                if d.refresh then d.refresh() end
                break
            end
        end
    end
    UI.RelayoutTabs()
end

-- ➕ Visibilité des onglets selon l'appartenance à une guilde
function UI.ApplyTabsForGuildMembership(inGuild)
    local keepInfo     = Tr("tab_roster")     -- renommé « Info » via locales
    local keepSettings = Tr("tab_settings")
    local keepDebug    = Tr("tab_debug")
    local reqLabel     = Tr("tab_requests")

    -- État GM + nombre de demandes en attente
    local isGM = (ns.GLOG and ns.GLOG.IsMaster and ns.GLOG.IsMaster()) or false
    local reqCount = 0
    if isGM and ns.GLOG and ns.GLOG.GetRequests then
        local t = ns.GLOG.GetRequests()
        reqCount = (type(t) == "table") and #t or 0
    end

    for _, def in ipairs(Registered) do
        local lab = def.label
        local shown

        if lab == keepDebug then
            -- Le débug reste contrôlé par l’option UI
            shown = (GuildLogisticsUI and GuildLogisticsUI.debugEnabled) and true or false

        elseif lab == reqLabel then
            -- ⚠️ Jamais visible pour un joueur ; visible pour le GM seulement s'il existe des demandes
            shown = isGM and (reqCount > 0)
            UI.SetTabBadge(reqLabel, reqCount)

        else
            -- Visibilité standard selon appartenance à une guilde
            if inGuild then
                shown = true
            else
                shown = (lab == keepInfo) or (lab == keepSettings)
            end
        end

        UI.SetTabVisible(lab, shown)
    end
end

-- ➕ Bascule « débug » centralisée (persistance + visibilité)
function UI.SetDebugEnabled(enabled)
    GuildLogisticsUI = GuildLogisticsUI or {}
    GuildLogisticsUI.debugEnabled = (enabled ~= false)

    -- Affiche/masque l’onglet Debug si présent (même si l’accès principal est par le bouton)
    if UI.SetTabVisible then
        UI.SetTabVisible(Tr("tab_debug"), GuildLogisticsUI.debugEnabled)
    end

    -- ➕ Affiche/masque les boutons d’en-tête
    if UI.DebugButton and UI.DebugButton.SetShown then
        UI.DebugButton:SetShown(GuildLogisticsUI.debugEnabled)
    end
    if UI.ReloadButton and UI.ReloadButton.SetShown then
        UI.ReloadButton:SetShown(GuildLogisticsUI.debugEnabled)
    end

    -- Rafraîchit l'UI courante pour refléter le changement
    if UI.RefreshAll then UI.RefreshAll() end
end

-- ➕ Pastille sur un onglet
function UI.SetTabBadge(label, count)
    -- Attache/maj la pastille sur l’onglet concerné
    local b, idx = UI.GetTabButton(label)
    if not b or not UI.AttachBadge then return end

    local badge = UI.AttachBadge(b)

    -- ✅ Alignement vertical sur le texte pour les sous-onglets (barre latérale)
    --    (on n’altère pas la position du texte, on aligne juste la pastille sur son centre Y)
    if b.txt and UI._catBar and UI._catBar._subList and b:GetParent() == UI._catBar._subList then
        if badge.AnchorTo then badge:AnchorTo(b.txt, "LEFT", "RIGHT", 8, 0) end
    end

    badge:SetCount(tonumber(count) or 0)

    -- ✅ Cascade : la catégorie mère affiche la pastille (somme des sous-onglets)
    UI._tabBadgeCounts = UI._tabBadgeCounts or {}
    UI._tabBadgeCounts[label] = tonumber(count) or 0

    -- Récupère la catégorie de cet onglet
    local def = (idx and Registered and Registered[idx]) and Registered[idx] or nil
    local cat = def and def.category or nil
    if not cat then return end

    -- Additionne les pastilles de la catégorie
    local total = 0
    for _, d in ipairs(Registered or {}) do
        if d.category == cat then
            local lab = d.label
            total = total + (UI._tabBadgeCounts[lab] or 0)
        end
    end

    -- Trouve le bouton de catégorie et applique la pastille (alignée au texte)
    local catBtn = UI.GetCategoryButton and UI.GetCategoryButton(cat) or nil
    if catBtn and UI.AttachBadge then
        local catBadge = UI.AttachBadge(catBtn)
        if catBtn.txt and catBadge.AnchorTo then
            catBadge:AnchorTo(catBtn.txt, "LEFT", "RIGHT", 8, 0)
        end
        catBadge:SetCount(total)
    end
end

-- ➕ Récupération du bouton de catégorie par label (sans modifier la création)
function UI.GetCategoryButton(catLabel)
    local bar = UI._catBar
    if not (bar and bar._btns) then return nil end
    for _, btn in ipairs(bar._btns) do
        if btn and btn.txt and btn.txt.GetText and (btn.txt:GetText() == catLabel) then
            return btn
        end
    end
    return nil
end

-- ➕ Indicateur d’enregistrement « Ressources »
function UI.UpdateResourcesRecordingIcon()
    local on = (ns.GLOG and ns.GLOG.IsExpensesRecording and ns.GLOG.IsExpensesRecording()) or false

    -- Sous-onglet « Ressources »
    local tabBtn = UI.GetTabButton and UI.GetTabButton(Tr("tab_resources")) or nil
    if tabBtn and UI.AttachStateIcon then
        local ico = UI.AttachStateIcon(tabBtn, { size = 12 })
        if tabBtn.txt and ico.AnchorTo then
            ico:AnchorTo(tabBtn.txt, "LEFT", "RIGHT", 8, 0)
        end
        ico:SetOn(on)
    end

    -- Catégorie mère « Raids »
    local catBtn = UI.GetCategoryButton and UI.GetCategoryButton(Tr("cat_raids")) or nil
    if catBtn and UI.AttachStateIcon then
        local ico = UI.AttachStateIcon(catBtn, { size = 12 })
        if catBtn.txt and ico.AnchorTo then
            ico:AnchorTo(catBtn.txt, "LEFT", "RIGHT", 8, 0)
        end
        ico:SetOn(on)
    end
end

-- ➕ Regroupe les indicateurs globaux à rafraîchir
function UI.RefreshTopIndicators()
    if UI.UpdateRequestsBadge then UI.UpdateRequestsBadge() end
    if UI.UpdateResourcesRecordingIcon then UI.UpdateResourcesRecordingIcon() end
end


-- ➕ Règle métier pour l'onglet "Demandes"
function UI.UpdateRequestsBadge()
    local isGM = (ns.GLOG and ns.GLOG.IsMaster and ns.GLOG.IsMaster()) or false
    local cnt = 0
    if isGM and ns.GLOG and ns.GLOG.GetRequests then
        local t = ns.GLOG.GetRequests()
        cnt = (type(t)=="table") and #t or 0
    end
    UI.SetTabBadge(Tr("tab_requests"), cnt)
    UI.SetTabVisible(Tr("tab_requests"), isGM and cnt > 0)
end

-- Wrapper sûr : met à jour la pastille "Demandes" si disponible, sinon masque proprement
function UI.SafeUpdateRequestsBadge()
    if type(UI.UpdateRequestsBadge) == "function" then
        UI.UpdateRequestsBadge()
        return
    end
    -- Fallback côté non-GM / chargement partiel : aucune demande visible
    if UI.SetTabBadge then UI.SetTabBadge(Tr("tab_requests"), 0) end
    if UI.SetTabVisible then UI.SetTabVisible(Tr("tab_requests"), false) end
end

-- ➕ Indicateur d’enregistrement « Ressources »
function UI.UpdateResourcesRecordingIcon()
    local on = (ns.GLOG and ns.GLOG.IsExpensesRecording and ns.GLOG.IsExpensesRecording()) or false

    -- Sous-onglet « Ressources »
    local tabBtn = UI.GetTabButton and UI.GetTabButton(Tr("tab_resources")) or nil
    if tabBtn and UI.AttachStateIcon then
        local ico = UI.AttachStateIcon(tabBtn, { size = 12 })
        if tabBtn.txt and ico.AnchorTo then
            ico:AnchorTo(tabBtn.txt, "LEFT", "RIGHT", 8, 0)
        end
        ico:SetOn(on)
    end

    -- Catégorie mère « Raids »
    local catBtn = UI.GetCategoryButton and UI.GetCategoryButton(Tr("cat_raids")) or nil
    if catBtn and UI.AttachStateIcon then
        local ico = UI.AttachStateIcon(catBtn, { size = 12 })
        if catBtn.txt and ico.AnchorTo then
            ico:AnchorTo(catBtn.txt, "LEFT", "RIGHT", 8, 0)
        end
        ico:SetOn(on)
    end
end

-- ➕ Regroupe les indicateurs globaux à rafraîchir
function UI.RefreshTopIndicators()
    if UI.UpdateRequestsBadge then UI.UpdateRequestsBadge() end
    if UI.UpdateResourcesRecordingIcon then UI.UpdateResourcesRecordingIcon() end
end

-- ➕ Hook « RefreshActive » utilisé par Comm.lua
function UI.RefreshActive()
    local isGM = (ns.GLOG and ns.GLOG.IsMaster and ns.GLOG.IsMaster()) or false

    -- Onglet "Démarrer un raid" visible uniquement pour GM
    if UI.SetTabVisible then
        UI.SetTabVisible(Tr("tab_start_raid"), isGM)
    end

    -- Sécurisé : met à jour/masque la pastille "Demandes" sans crasher
    if UI.SafeUpdateRequestsBadge then
        UI.SafeUpdateRequestsBadge()
    end

    -- Cycle de rafraîchissement global
    if ns.RefreshAll then
        ns.RefreshAll()
    elseif UI.RefreshAll then
        UI.RefreshAll()
    end
end


ns.RefreshActive = UI.RefreshActive

function ns.ToggleUI()
    if Main:IsShown() then
        Main:Hide()
    else
        Main:Show()

        -- refresh guilde si nécessaire (cache vide ou > 60s)
        if GLOG and GLOG.RefreshGuildCache then
            local ts = GLOG.GetGuildCacheTimestamp and GLOG.GetGuildCacheTimestamp() or 0
            local now = (time and time() or 0)
            local stale = (now - ts) > 60
            if stale or (GLOG.IsGuildCacheReady and not GLOG.IsGuildCacheReady()) then
                GLOG.RefreshGuildCache(function()
                    if ns.RefreshAll then ns.RefreshAll() end
                end)
            end
        end

        ShowPanel(1)
        if Registered[1] and Registered[1].refresh then Registered[1].refresh() end
    end
end

Main:Hide()

-- Ouvrir à l'ouverture du jeu + appliquer le thème et l'état de debug sauvegardés
local _openAtLogin = CreateFrame("Frame")
_openAtLogin:RegisterEvent("PLAYER_LOGIN")
_openAtLogin:SetScript("OnEvent", function()
    local saved = GLOG.GetSavedWindow and GLOG.GetSavedWindow() or {}

    -- Applique le thème stocké (défaut: AUTO) et re-skin global
    if UI.SetTheme then UI.SetTheme(saved.theme or "AUTO") end

    -- ✏️ Applique l'état de debug (défaut : false → boutons masqués)
    local debugOn = (saved and saved.debugEnabled) == true
    if UI.SetDebugEnabled then UI.SetDebugEnabled(debugOn) end

    -- Ouverture auto uniquement si activée par l'utilisateur
    if not (saved and saved.autoOpen) then return end
    if not Main:IsShown() then
        Main:Show()
        ShowPanel(1)
        if Registered[1] and Registered[1].refresh then Registered[1].refresh() end
    end
end)

-- ➕ Met à jour le titre selon la guilde
function UI.RefreshTitle()
    if not Main then return end

    -- Nom Addon (ligne 1)
    local addonTitle = (GLOG.GetAddonTitle and GLOG.GetAddonTitle()) or (Tr and Tr("app_title")) or ADDON
    if Main.titleAddon and Main.titleAddon.SetText then
        Main.titleAddon:SetText(addonTitle)
    elseif Main.title and Main.title.SetText then
        Main.title:SetText(addonTitle) -- compat si titleAddon n’existe pas
    end

    -- Version (à droite, grise et entre parenthèses)
    if Main.titleVersion and Main.titleVersion.SetText then
        local ver = (GLOG.GetAddonVersion and GLOG.GetAddonVersion()) or ""
        local txt = (ver ~= "" and ("("..ver..")")) or ""
        Main.titleVersion:SetText(txt)
        Main.titleVersion:SetShown(txt ~= "")
        -- Recalage au cas où la largeur du nom change (locales)
        Main.titleVersion:ClearAllPoints()
        Main.titleVersion:SetPoint("LEFT", Main.titleAddon or Main.title, "RIGHT", 6, 0)
    end

    -- Nom de guilde (ligne 2)
    if Main.titleGuild and Main.titleGuild.SetText then
        local g = GLOG.GetCurrentGuildName and GLOG.GetCurrentGuildName() or ""
        Main.titleGuild:SetText(g or "")
        Main.titleGuild:SetShown(g ~= "")
    end
end


-- ===================== Catégories (sidebar) =====================
local function _CatIcons()
    return {
        [Tr("cat_guild")]    = "Interface\\ICONS\\inv_shirt_guildtabard_01",
        [Tr("cat_raids")]    = "Interface\\ICONS\\achievement_boss_lichking",
        [Tr("cat_tools")]    = "Interface\\ICONS\\INV_Hammer_20",
        [Tr("cat_info")]     = "Interface\\ICONS\\trade_archaeology_draenei_tome",
        [Tr("cat_settings")] = "Interface\\ICONS\\trade_engineering",
        [Tr("cat_debug")]    = "Interface\\ICONS\\inv_inscription_pigment_bug04",
    }
end

local function _CatOrder()
    return {
        Tr("cat_guild"),
        Tr("cat_raids"),
        Tr("cat_tools"),
        Tr("cat_info"),
        Tr("cat_settings"),
        Tr("cat_debug"),
    }
end

-- Bouton « carrelage » avec icône + survol + sélection (style proche capture)
local function _CategoryButton(parent, text, iconPath)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(168, 52)  -- un peu plus haut pour loger l’icône 48x48 confortablement

    -- Fond
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints(b)
    b.bg:SetColorTexture(1,1,1,0.08)

    -- Survol
    b.hover = b:CreateTexture(nil, "OVERLAY")
    b.hover:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    b.hover:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    b.hover:SetColorTexture(1,1,1,0.07)
    b.hover:Hide()

    -- Sélection (liseré + bande verte)
    b.sel = b:CreateTexture(nil, "OVERLAY")
    b.sel:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    b.sel:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", 0, 0)
    b.sel:SetColorTexture(0.16, 0.82, 0.27, 0.22) -- vert doux
    b.sel:Hide()

    -- Petite barre gauche accent
    b.bar = b:CreateTexture(nil, "OVERLAY")
    b.bar:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
    b.bar:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 0, 0)
    b.bar:SetWidth(3)
    b.bar:SetColorTexture(0.16, 0.82, 0.27, 0.85)
    b.bar:Hide()

    -- Icône (48x48) + crop 5px + couche forcée
    b.icon = b:CreateTexture(nil, "OVERLAY", nil, 1)  -- couche haute pour éviter d’être masqué
    b.icon:SetSize(48, 48)
    b.icon:SetPoint("LEFT", b, "LEFT", 12, 0)

    if UI and UI.TrySetIcon then
        UI.TrySetIcon(b.icon, iconPath)
    else
        b.icon:SetTexture(iconPath or "Interface\\ICONS\\INV_Misc_QuestionMark")
    end

    if UI and UI.CropIcon then
        UI.CropIcon(b.icon, 5)     -- rogne 5px sur chaque bord (icône type 64x64)
    end
    if UI and UI.EnsureIconVisible then
        UI.EnsureIconVisible(b.icon, 1)
    end

    -- Texte
    b.txt = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    b.txt:SetPoint("LEFT", b.icon, "RIGHT", 8, 0)
    b.txt:SetText(text)

    b:SetScript("OnEnter", function(self) self.hover:Show() end)
    b:SetScript("OnLeave", function(self) self.hover:Hide() end)

    return b
end


-- Déduit la catégorie d’un label d’onglet
local function _CategoryOfLabel(label)
    for _, def in ipairs(Registered) do
        if def.label == label then
            return def.category
        end
    end
end

-- Public : sélectionne la catégorie pour un label d’onglet (retourne true si bascule)
function UI.SelectCategoryForLabel(tabLabel)
    local cat = _CategoryOfLabel(tabLabel)
    if cat and cat ~= UI._activeCategory then
        UI.SetActiveCategory(cat)
        return true
    end
    return false
end

function UI.CreateCategorySidebar()
    if UI._catBar then return UI._catBar end
    local Main = UI.Main
    if not Main then return end

    local L,R,T,B = UI.OUTER_PAD, UI.OUTER_PAD, UI.OUTER_PAD, UI.OUTER_PAD
    if Main._cdzNeutral and Main._cdzNeutral.GetInsets then
        L,R,T,B = Main._cdzNeutral:GetInsets()
    end

    -- === Cadre barre latérale ===
    local bar = CreateFrame("Frame", "GLOG_CategoryBar", Main, "BackdropTemplate")
    UI._catBar = bar
    bar:SetPoint("TOPLEFT",     Main, "TOPLEFT",     L + 4, -(T + 22))
    bar:SetPoint("BOTTOMLEFT",  Main, "BOTTOMLEFT",  L + 4,  B + 2)
    bar:SetWidth(192)

    -- Fond tuilé (style parchemin Blizzard)
    if UI.ApplyTiledBackdrop then
        UI.ApplyTiledBackdrop(
            bar,
            "Interface\\FrameGeneral\\UIFrameNecrolordBackground",
            128,
            1,
            { left = 0, right = 1, top = 0, bottom = 0 }
        )
    end

    -- Liseré de séparation à droite
    local sepDark = bar:CreateTexture(nil, "BORDER")
    sepDark:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 0, 0)
    sepDark:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 0, 0)
    sepDark:SetWidth(1)
    sepDark:SetColorTexture(0, 0, 0, 0.60)

    local sepLight = bar:CreateTexture(nil, "BORDER")
    sepLight:SetPoint("TOPRIGHT", bar, "TOPRIGHT", -1, 0)
    sepLight:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -1, 0)
    sepLight:SetWidth(1)
    sepLight:SetColorTexture(1, 1, 1, 0.08)

    -- === Conteneur des catégories ===
    local list = CreateFrame("Frame", nil, bar)
    bar._list = list
    list:SetPoint("TOPLEFT",     bar, "TOPLEFT",  0, 0)
    list:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -1, 0)
    list:SetClipsChildren(false)

    -- Réserve l’espace global
    UI.CATEGORY_BAR_W = bar:GetWidth() + 3
    UI.TAB_LEFT_PAD   = (UI.CATEGORY_BAR_W or 0) + 12

    -- Construit la liste de catégories réellement utilisées
    local hasCat = {}
    for _, def in ipairs(Registered or {}) do
        local c = def.category
        if c and (def.hidden ~= true) then hasCat[c] = true end
    end
    local order = _CatOrder and _CatOrder() or {}
    local icons = _CatIcons and _CatIcons() or {}

    -- === Boutons de catégories ===
    bar._btns = {}
    local prev
    local firstCat
    for _, catLabel in ipairs(order) do
        if hasCat[catLabel] then
            firstCat = firstCat or catLabel

            local b = _CategoryButton(list, catLabel, icons[catLabel])
            b:ClearAllPoints()
            if not prev then
                b:SetPoint("TOPLEFT",  list, "TOPLEFT",  0, 1)
            else
                b:SetPoint("TOPLEFT",  prev, "BOTTOMLEFT", 0, -1)
            end
            b:SetPoint("RIGHT", list, "RIGHT", -1, 0)

            b:SetScript("OnClick", function() UI.SetActiveCategory(catLabel) end)

            table.insert(bar._btns, b)
            prev = b
        end
    end

    -- === Sous-liste d'onglets (affichée uniquement pour la catégorie active) ===
    local sub = CreateFrame("Frame", nil, bar)
    bar._subList = sub
    sub:Hide()
    sub:SetClipsChildren(true)

    -- Fond subtil derrière les sous-onglets
    sub._bg = sub:CreateTexture(nil, "BACKGROUND")
    sub._bg:SetAllPoints(sub)
    sub._bg:SetColorTexture(1,1,1,0.06)

    -- Catégorie par défaut
    UI._activeCategory = UI._activeCategory or firstCat
    
    -- Rafraîchit les indicateurs globaux maintenant que la barre est construite
    if UI.RefreshTopIndicators then UI.RefreshTopIndicators() end

    return bar
end



function UI.SetActiveCategory(catLabel)
    UI._activeCategory = catLabel

    -- Visuel boutons
    if UI._catBar and UI._catBar._btns then
        for _, b in ipairs(UI._catBar._btns) do
            local sel = (b.txt:GetText() == catLabel)
            b.sel:SetShown(sel)
            b.bar:SetShown(sel)
        end
    end

    -- Applique le filtre sur les onglets
    for _, def in ipairs(Registered) do
        local b = def._btn
        if b then
            local inCat = (not def.category) or (def.category == catLabel)
            local allow = (def._sysShown ~= false) and inCat
            b:SetShown(allow)
        end
    end

    UI.RelayoutTabs()

    -- Affiche le premier onglet visible de la catégorie
    for i, d in ipairs(Registered) do
        if d._btn and d._btn:IsShown() then
            UI.ShowPanel(i)
            if d.refresh then d.refresh() end
            break
        end
    end

    if UI._layout then UI._layout() end
end

-- Ouverture par label, avec bascule catégorie
function UI.ShowTabByLabel(label)
    if UI.SelectCategoryForLabel then UI.SelectCategoryForLabel(label) end
    local idx = UI._tabIndexByLabel and UI._tabIndexByLabel[label]
    if idx then
        UI.ShowPanel(idx)
        if Registered[idx] and Registered[idx].refresh then Registered[idx].refresh() end
        UI.RelayoutTabs()
    end
end

-- Instancie la barre à l’ouverture de la fenêtre (sécurité si Finalize est différé)
if UI.Main and UI.Main.SetScript then
    UI.Main:HookScript("OnShow", function()
        if not UI._catBar then UI.CreateCategorySidebar() end
    end)
end