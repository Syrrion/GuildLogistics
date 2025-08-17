local ADDON, ns = ...
local CDZ = ns.CDZ

ns.UI = ns.UI or {}
local UI = ns.UI

UI.DEFAULT_W, UI.DEFAULT_H = 1160, 680
UI.OUTER_PAD, UI.SCROLLBAR_W, UI.GUTTER, UI.ROW_H = 16, 20, 8, 28
UI.FONT_YELLOW = {1, 0.82, 0}
UI.WHITE = {1,1,1}
UI.ACCENT = {0.22,0.55,0.95}
UI.FOOTER_RIGHT_PAD = UI.FOOTER_RIGHT_PAD or 8


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
local Main = CreateFrame("Frame", "CDZ_Main", UIParent, "BackdropTemplate")
UI.Main = Main
local saved = CDZ.GetSavedWindow and CDZ.GetSavedWindow() or {}
Main:SetSize(saved.width or UI.DEFAULT_W, saved.height or UI.DEFAULT_H)
Main:SetFrameStrata("HIGH")
Main:SetMovable(true)
Main:EnableMouse(true)
Main:RegisterForDrag("LeftButton")
Main:SetScript("OnDragStart", function(self) self:StartMoving() end)
Main:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, relTo, relPoint, x, y = self:GetPoint()
    if CDZ.SaveWindow then
        CDZ.SaveWindow(point, relTo and relTo:GetName() or nil, relPoint, x, y, self:GetWidth(), self:GetHeight())
    end
end)
Main:SetResizable(true)
if Main.SetResizeBounds then Main:SetResizeBounds(980, 600) end
Main:SetScript("OnSizeChanged", function(self, w, h)
    if UI._layout then UI._layout() end
    local point, relTo, relPoint, x, y = self:GetPoint()
    if CDZ.SaveWindow then
        CDZ.SaveWindow(point, relTo and relTo:GetName() or nil, relPoint, x, y, w, h)
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

-- Titre centré sur la barre de titre
Main.title = Main:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
Main.title:SetText("Chroniques du Zéphyr - Comptabilité")
Main.title:SetTextColor(0.98, 0.95, 0.80)
do
    local _, _, TOP = skin:GetInsets()
    Main.title:ClearAllPoints()
    Main.title:SetPoint("TOP", Main, "TOP", 0, -(TOP - 38)) -- visuellement centré sur la frise
end

-- Bouton fermer standard (possibilité d'utiliser l'atlas UI-Frame-Neutral-ExitButtonBorder plus tard)
local close = CreateFrame("Button", nil, Main, "UIPanelCloseButton")
close:SetPoint("TOPRIGHT", Main, "TOPRIGHT", 2, 2)

-- ➕ Bouton Reload au même niveau que la croix (dans la barre titre)
local reloadBtn = CreateFrame("Button", ADDON.."ReloadButton", Main, "UIPanelButtonTemplate")
reloadBtn:SetSize(60, 20)
reloadBtn:SetText("Reload")
-- S'assure d'être au-dessus du contenu, comme le bouton X
reloadBtn:SetFrameStrata(close:GetFrameStrata())
reloadBtn:SetFrameLevel(close:GetFrameLevel())
-- Placé juste à gauche du X
reloadBtn:ClearAllPoints()
reloadBtn:SetPoint("TOPRIGHT", close, "TOPLEFT", -6, 0)
reloadBtn:SetScript("OnClick", function() ReloadUI() end)

-- ===================== Tabs =====================
local Registered, Panels, Tabs = {}, {}, {}
UI._tabIndexByLabel = {}


-- UI.RegisterTab(label, build, refresh, layout, opts?) ; opts.hidden pour masquer le bouton d’onglet
function UI.RegisterTab(label, buildFunc, refreshFunc, layoutFunc, opts)
    table.insert(Registered, {
        label  = label,
        build  = buildFunc,
        refresh= refreshFunc,
        layout = layoutFunc,
        hidden = opts and opts.hidden or false,
    })
    UI._tabIndexByLabel[label] = #Registered
end

local function ShowPanel(idx)
    for i,p in ipairs(Panels) do p:SetShown(i == idx) end
    UI._current = idx
    for i, def in ipairs(Registered) do
        local b = def._btn
        if b then
            if i == idx then
                b.sel:Show()
                b:SetNormalFontObject("GameFontHighlightLarge")
            else
                b.sel:Hide()
                b:SetNormalFontObject("GameFontHighlight")
            end
        end
    end
end
UI.ShowPanel = ShowPanel

-- Création d’un bouton d’onglet basé sur le précédent visible
local function CreateTabButton(prevBtn, text)
    local b = CreateFrame("Button", nil, Main, "UIPanelButtonTemplate")
    b:SetText(text)
    b:SetSize(150, 26)
    if not prevBtn then
        local L = UI.OUTER_PAD
        if Main._cdzNeutral and Main._cdzNeutral.GetInsets then
            L = (Main._cdzNeutral:GetInsets())  -- récupère L,R,T,B ; on ne garde que L
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

function UI.Finalize()
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
            btn:SetScript("OnClick", function() ShowPanel(i); if def.refresh then def.refresh() end end)
            def._btn = btn
            lastBtn = btn
            table.insert(Tabs, btn)
        else
            def._btn = nil
        end
    end
    UI._layout = function()
        for i, def in ipairs(Registered) do
            if Panels[i]:IsShown() and def.layout then def.layout() end
        end
    end
end

-- Navigation par label (ex: UI.ShowTabByLabel("Historique"))
function UI.ShowTabByLabel(label)
    local idx = UI._tabIndexByLabel and UI._tabIndexByLabel[label]
    if idx then
        ShowPanel(idx)
        local def = Registered[idx]
        if def and def.refresh then def.refresh() end
    end
end


function UI.RefreshAll()
    local i = UI._current
    if i and Registered[i] and Registered[i].refresh then Registered[i].refresh() end
end
ns.RefreshAll = UI.RefreshAll

-- ➕ Récupération du bouton d'un onglet par label
function UI.GetTabButton(label)
    local idx = UI._tabIndexByLabel and UI._tabIndexByLabel[label]
    local def = idx and Registered[idx] or nil
    return def and def._btn, idx
end

-- ➕ Reflow des onglets visibles (sans « trous »)
function UI.RelayoutTabs()
    local lastBtn
    for i, def in ipairs(Registered) do
        local b = def._btn
        if b then
            b:ClearAllPoints()
            if b:IsShown() then
                if not lastBtn then
                    local L = UI.OUTER_PAD
                    if Main._cdzNeutral and Main._cdzNeutral.GetInsets then
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
    local b, idx = UI.GetTabButton(label)
    if not b then return end
    local wasShown = b:IsShown()
    b:SetShown(shown and true or false)
    if (wasShown and not b:IsShown()) and UI._current == idx then
        -- bascule vers le 1er onglet visible
        for i, def in ipairs(Registered) do
            if def._btn and def._btn:IsShown() then
                UI.ShowPanel(i)
                if def.refresh then def.refresh() end
                break
            end
        end
    end
    UI.RelayoutTabs()
end

-- ➕ Pastille sur un onglet
function UI.SetTabBadge(label, count)
    local b = UI.GetTabButton(label)
    if not b or not UI.AttachBadge then return end
    UI.AttachBadge(b):SetCount(tonumber(count) or 0)
end

-- ➕ Règle métier pour l'onglet "Demandes"
function UI.UpdateRequestsBadge()
    local isGM = (ns.CDZ and ns.CDZ.IsMaster and ns.CDZ.IsMaster()) or false
    local cnt = 0
    if isGM and ns.CDZ and ns.CDZ.GetRequests then
        local t = ns.CDZ.GetRequests()
        cnt = (type(t)=="table") and #t or 0
    end
    UI.SetTabBadge("Demandes", cnt)
    UI.SetTabVisible("Demandes", isGM and cnt > 0)
end

-- ➕ Hook « RefreshActive » utilisé par Comm.lua
function UI.RefreshActive()
    local isGM = (ns.CDZ and ns.CDZ.IsMaster and ns.CDZ.IsMaster()) or false
    if UI.SetTabVisible then
        UI.SetTabVisible("Démarrer un raid", isGM)
    end
    UI.UpdateRequestsBadge()
    UI.RefreshAll()
end

ns.RefreshActive = UI.RefreshActive

function ns.ToggleUI()
    if Main:IsShown() then
        Main:Hide()
    else
        Main:Show()

        -- refresh guilde si nécessaire (cache vide ou > 60s)
        if CDZ and CDZ.RefreshGuildCache then
            local ts = CDZ.GetGuildCacheTimestamp and CDZ.GetGuildCacheTimestamp() or 0
            local now = (time and time() or 0)
            local stale = (now - ts) > 60
            if stale or (CDZ.IsGuildCacheReady and not CDZ.IsGuildCacheReady()) then
                CDZ.RefreshGuildCache(function()
                    if ns.RefreshAll then ns.RefreshAll() end
                end)
            end
        end

        ShowPanel(1)
        if Registered[1] and Registered[1].refresh then Registered[1].refresh() end
    end
end

Main:Hide()

-- Ouvrir à l'ouverture du jeu + appliquer le thème sauvegardé
local _openAtLogin = CreateFrame("Frame")
_openAtLogin:RegisterEvent("PLAYER_LOGIN")
_openAtLogin:SetScript("OnEvent", function()
    local saved = CDZ.GetSavedWindow and CDZ.GetSavedWindow() or {}

    -- Applique le thème stocké (défaut: AUTO) et re-skin global
    if UI.SetTheme then UI.SetTheme(saved.theme or "AUTO") end

    -- Ouverture auto uniquement si activée par l'utilisateur
    if not (saved and saved.autoOpen) then return end
    if not Main:IsShown() then
        Main:Show()
        ShowPanel(1)
        if Registered[1] and Registered[1].refresh then Registered[1].refresh() end
    end
end)