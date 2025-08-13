local ADDON, ns = ...
local CDZ = ns.CDZ

ns.UI = ns.UI or {}
local UI = ns.UI

UI.DEFAULT_W, UI.DEFAULT_H = 1160, 680
UI.OUTER_PAD, UI.SCROLLBAR_W, UI.GUTTER, UI.ROW_H = 16, 20, 8, 28
UI.FONT_YELLOW = {1, 0.82, 0}
UI.WHITE = {1,1,1}
UI.ACCENT = {0.22,0.55,0.95}

UI.TAB_EXTRA_GAP       = UI.TAB_EXTRA_GAP       or 14
UI.CONTENT_SIDE_PAD    = UI.CONTENT_SIDE_PAD    or -23
UI.CONTENT_BOTTOM_LIFT = UI.CONTENT_BOTTOM_LIFT or -20
UI.TAB_LEFT_PAD        = UI.TAB_LEFT_PAD        or 18

function UI.MoneyText(v)
    v = tonumber(v) or 0
    local n = math.floor(math.abs(v) + 0.5)
    local iconG = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t"
    local txt = n .. " " .. iconG
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
    if g > 0 then table.insert(parts, g .. " " .. iconG) end
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
