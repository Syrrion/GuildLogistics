local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI, F = ns.GLOG, ns.UI, ns.Format
local PAD = UI.OUTER_PAD

local panel, lv

-- Colonnes normalisées
local cols = UI.NormalizeColumns({
    { key="main",  title="Joueur",             min=420, flex=1 },
    { key="last",  title="Dernière connexion", w=180 },
    { key="count", title="Rerolls",            w=120 },
    { key="act",   title="",                   w=220 },
})

-- Construction d’une ligne
local function BuildRow(r)
    local f = {}

    -- Widgets pour "data"
    f.main  = UI.CreateNameTag(r)
    f.last  = UI.Label(r, { justify = "CENTER" })
    f.count = UI.Label(r)

    -- Cellule d'actions = conteneur + bouton + libellé "dans le roster"
    f.act     = CreateFrame("Frame", nil, r); f.act:SetHeight(UI.ROW_H)
    f.inRoster = UI.Label(f.act)
    f.btnAdd  = UI.Button(f.act, "Ajouter au Roster", { size="sm", minWidth=160 })
    f.inRoster:SetText("Dans le roster")

    f.inRoster:SetJustifyH("CENTER")
    f.inRoster:Hide()

    UI.AttachRowRight(f.act, { f.btnAdd }, 8, -4, { leftPad = 8, align = "center" })

    -- Widgets pour "sep"
    f.sepBG = r:CreateTexture(nil, "BACKGROUND"); f.sepBG:Hide()
    f.sepBG:SetColorTexture(0.18, 0.18, 0.22, 0.6)
    f.sepBG:SetPoint("TOPLEFT", r, "TOPLEFT", -2, 0)
    f.sepBG:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 2, 0)
    f.sepTop = r:CreateTexture(nil, "BORDER"); f.sepTop:Hide()
    f.sepTop:SetColorTexture(0.9, 0.8, 0.2, 0.9)
    f.sepTop:SetPoint("TOPLEFT", f.sepBG, "TOPLEFT", 0, 1)
    f.sepTop:SetPoint("TOPRIGHT", f.sepBG, "TOPRIGHT", 0, 1)
    f.sepTop:SetHeight(2)
    f.sepLabel = r:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); f.sepLabel:Hide()
    f.sepLabel:SetTextColor(1, 0.95, 0.3)

    return f
end

-- Mise à jour d’une ligne
local function UpdateRow(i, r, f, it)
    local isSep = (it.kind == "sep")

    f.sepBG:SetShown(isSep); f.sepTop:SetShown(isSep); f.sepLabel:SetShown(isSep)
    if isSep then
        if f.main and f.main.text then f.main.text:SetText("") end
        if f.last then f.last:SetText("") end
        if f.count then f.count:SetText("") end
        if f.act then f.act:Hide() end
        f.sepLabel:ClearAllPoints()
        f.sepLabel:SetPoint("LEFT", r, "LEFT", 8, 0)
        f.sepLabel:SetText(it.label or "")
        return
    end

    if f.act then f.act:Show() end
    f.sepLabel:SetText("")

    UI.SetNameTag(f.main, it.main or "")
    f.count:SetText(it.count or 0)
    if it.onlineCount and it.onlineCount > 0 then
        local txt = (it.onlineCount > 1) and ("|cff40ff40En ligne ("..it.onlineCount..")|r") or "|cff40ff40En ligne|r"
        f.last:SetText(txt)
    else
        f.last:SetText(ns.Format.LastSeen(it.days or it.lastSeenDays, it.hours or it.lastSeenHours))
    end

    local inRoster = (ns.GLOG.HasPlayer and ns.GLOG.HasPlayer(it.main)) or false
    local isReserve = (ns.GLOG.IsReserved and ns.GLOG.IsReserved(it.main)) or false
    local canAdd = (ns.GLOG.IsMaster and ns.GLOG.IsMaster()) and true or false

    if inRoster then
        if f.btnAdd then f.btnAdd:Hide() end
        if f.inRoster then
            -- Montre explicitement le statut de réserve si applicable
            f.inRoster:SetText(isReserve and "En réserve" or "Dans le roster")
            f.inRoster:Show()
            f.inRoster:ClearAllPoints()
            f.inRoster:SetPoint("CENTER", f.act, "CENTER", 0, 0)
        end

    elseif not canAdd then
        -- Non-GM : pas de bouton et pas de message "Réservé au GM" -> on laisse vide
        if f.btnAdd then f.btnAdd:Hide() end
        if f.inRoster then f.inRoster:Hide() end

    else
        if f.inRoster then f.inRoster:Hide() end
        if f.btnAdd then
            f.btnAdd:Show()
            f.btnAdd:SetScript("OnClick", function()
                ns.GLOG.AddPlayer(it.main)
                if ns.RefreshAll then ns.RefreshAll() end
            end)
        end
    end

    if f.act and f.act._applyRowActionsLayout then f.act._applyRowActionsLayout() end
end

-- Construit un nom complet "Nom-Realm" pour l'affichage/ajout roster
local function EnsureFullMain(e)
    local m = tostring((e and e.main) or "")
    if m:find("-", 1, true) then return m end

    -- Cherche le royaume à partir des lignes scannées de la guilde
    local rows = (GLOG and GLOG.GetGuildRowsCached and GLOG.GetGuildRowsCached()) or {}
    for _, r in ipairs(rows) do
        local amb = r.name_amb or r.name_raw
        if amb and GLOG.NormName and GLOG.NormName(amb) == e.key then
            local raw = r.name_raw or amb
            local realm = tostring(raw or ""):match("^[^-]+%-(.+)$")
            if realm and realm ~= "" then
                return m .. "-" .. realm
            end
        end
    end

    -- Secours : royaume du joueur local
    if UnitFullName then
        local _, myRealm = UnitFullName("player")
        if myRealm and myRealm ~= "" then
            return m .. "-" .. myRealm
        end
    end
    return m
end

-- Génère la liste (avec séparateurs)
local function buildItemsFromAgg(agg)

    local actives, olds = {}, {}
    for _, e in ipairs(agg or {}) do
        local d = tonumber(e.days) or 999999
        if d < 30 then table.insert(actives, e) else table.insert(olds, e) end
    end
    table.sort(actives, function(a,b) return a.main:lower() < b.main:lower() end)
    table.sort(olds,    function(a,b) return a.main:lower() < b.main:lower() end)

    local items = {}
    if #actives > 0 then
        table.insert(items, {kind="sep", label="Connectés < 1 mois (perso le + récent)"} )
        for _, e in ipairs(actives) do table.insert(items, {kind="data", main=EnsureFullMain(e), days=e.days, hours=e.hours, count=e.count, onlineCount=e.onlineCount}) end
    end
    if #olds > 0 then
        table.insert(items, {kind="sep", label="Dernière connexion ≥ 1 mois"} )
        for _, e in ipairs(olds) do table.insert(items, {kind="data", main=EnsureFullMain(e), days=e.days, hours=e.hours, count=e.count, onlineCount=e.onlineCount}) end
    end
    if #items == 0 then table.insert(items, {kind="sep", label="Aucun joueur trouvé (Remarque = pseudo du main)."}) end
    return items
end

local function Layout()
    -- Rien à positionner au-dessus → on laisse ListView gérer
    lv:Layout()
end

local function Refresh()
    local need = (not GLOG.IsGuildCacheReady or not GLOG.IsGuildCacheReady())
    if not need and GLOG.GetGuildCacheTimestamp then
        local age = time() - GLOG.GetGuildCacheTimestamp()
        if age > 60 then need = true end
    end
    if need then
        lv:SetData({ {kind="sep", label="Scan du roster en cours…"} })
        GLOG.RefreshGuildCache(function()
            if ns and ns.UI and ns.UI._rosterPopupUpdater then ns.UI._rosterPopupUpdater() end
            if ns and ns.UI and ns.UI.RefreshAll then ns.UI.RefreshAll() end
        end)
        return
    end

    local items = buildItemsFromAgg(GLOG.GetGuildMainsAggregated())
    lv:SetData(items)
    lv:Layout()
end

local function Build(container)
    panel = container
    if UI.ApplySafeContentBounds then UI.ApplySafeContentBounds(panel, { side = 10, bottom = 6 }) end

    lv = UI.ListView(panel, cols, {
        buildRow = BuildRow,
        updateRow = UpdateRow,
        rowHeight = UI.ROW_H,
        rowHeightForItem = function(item) return (item.kind == "sep") and (UI.ROW_H + 10) or UI.ROW_H end,
    })
end

-- Popup roster à largeur dynamique + auto-refresh à la fin du scan
function UI.ShowGuildRosterPopup()
    local dlg = UI.CreatePopup({ title = Tr("add_guild_member"), height = 670 })


    -- Largeur mini des colonnes + scrollbar + marges internes
    local sb  = (UI.SCROLLBAR_W or 20) + (UI.SCROLLBAR_INSET or 0)
    local cMin = (UI.MinWidthForColumns and UI.MinWidthForColumns(cols)) or (function()
        local s=0; for _,c in ipairs(cols or {}) do s = s + (c.w or c.min or 80) end; return s+8
    end)()
    local innerMargins = 24
    local wantedDlgW  = cMin + sb + innerMargins
    local screenMax   = math.floor((UIParent and UIParent:GetWidth() or 1280) - 80)
    local finalW      = math.min(wantedDlgW, screenMax)
    dlg:SetWidth(finalW)
    if dlg.SetResizeBounds then dlg:SetResizeBounds(finalW, 220) end

    -- ListView
    local pv = UI.ListView(dlg.content, cols, {
        buildRow = BuildRow,
        updateRow = UpdateRow,
        rowHeight = UI.ROW_H,
        rowHeightForItem = function(item) return (item.kind == "sep") and (UI.ROW_H + 10) or UI.ROW_H end,
    })

    -- Fonction d’update spécifique à la popup (utilisée par le callback du scan)
    local function updatePopup()
        if not dlg or not dlg:IsShown() then return end
        local items = buildItemsFromAgg(GLOG.GetGuildMainsAggregated())
        pv:SetData(items)
        pv:Layout()
    end
    ns.UI._rosterPopupUpdater = updatePopup
    dlg:SetScript("OnHide", function() if ns and ns.UI then ns.UI._rosterPopupUpdater = nil end end)

    -- État initial : cache prêt récent -> data directe, sinon message + scan avec callback local
    local need = (not GLOG.IsGuildCacheReady or not GLOG.IsGuildCacheReady())
    if not need and GLOG.GetGuildCacheTimestamp then
        local age = time() - GLOG.GetGuildCacheTimestamp()
        if age > 60 then need = true end
    end

    if need then
        pv:SetData({ {kind="sep", label="Scan du roster en cours…"} })
        GLOG.RefreshGuildCache(updatePopup)
    else
        updatePopup()
    end

    dlg:SetButtons({ { text = CLOSE, default = true } })
    dlg:Show()
end
