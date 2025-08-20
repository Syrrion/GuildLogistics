local ADDON, ns = ...
local GMGR, UI, F = ns.GMGR, ns.UI, ns.Format
local PAD, SBW, GUT = UI.OUTER_PAD, UI.SCROLLBAR_W, UI.GUTTER

-- =========================
-- ======   ÉTAT UI   ======
-- =========================
local panel, footer
local topPane, bottomPane
local lvFree, lvLots
local btnToggle, totalFS, btnClearAll, btnCreateLot
local selected = {} -- sélection : clés = index absolu dans expenses.list

-- =========================
-- ======   COLONNES   =====
-- =========================
local function BuildColsFree()
    local isGM = (GMGR.IsMaster and GMGR.IsMaster()) or false
    local cols = {
        { key="qty",    title="Qté",     w=44  },
        { key="item",   title="Objet",   min=260, flex=1 },
        { key="source", title="Source",  w=120 },
        { key="amount", title="Montant", w=160 },
    }
    if isGM then
        table.insert(cols, 1, { key="sel", title="", w=34 })
        table.insert(cols, 6, { key="act", title="", w=40 })
    end
    return UI.NormalizeColumns(cols)
end

local colsFree = BuildColsFree()

local colsLots = UI.NormalizeColumns({
    { key="name",   title="Lot",           min=220, flex=1 },
    { key="type",   title="Utilisations",  w=110 },
    { key="status", title="Restantes",     w=110 },
    { key="content",title="Contenu",       w=60 },
    { key="total",  title="Valeur totale", w=120 },
    { key="act",    title="",              w=(GMGR.IsMaster and GMGR.IsMaster()) and 40 or 0 },
})

-- =========================
-- ======   HELPERS   ======
-- =========================
local function moneyCopper(v)
    return UI.MoneyFromCopper(tonumber(v) or 0)
end

local function resolveItemName(it)
    if it.itemID then
        local name = GetItemInfo and select(1, GetItemInfo(it.itemID))
        if name and name ~= "" then return name end
    end
    if it.itemLink and it.itemLink ~= "" then
        local name = GetItemInfo and select(1, GetItemInfo(it.itemLink))
        if name and name ~= "" then return name end
        local bracket = it.itemLink:match("%[(.-)%]")
        if bracket and bracket ~= "" then return bracket end
    end
    if it.itemName and it.itemName ~= "" then return it.itemName end
    if it.itemID then return "Objet #"..tostring(it.itemID) end
    return ""
end

local function resolveItemIcon(it)
    if it.itemID then
        if GetItemIcon then local tex = GetItemIcon(it.itemID); if tex then return tex end end
        if GetItemInfoInstant then local _,_,_,_,icon = GetItemInfoInstant(it.itemID); if icon then return icon end end
    end
    if it.itemLink and it.itemLink ~= "" then
        if GetItemIcon then local tex = GetItemIcon(it.itemLink); if tex then return tex end end
        if GetItemInfoInstant then local _,_,_,_,icon = GetItemInfoInstant(it.itemLink); if icon then return icon end end
    end
    return 134400
end

-- =========================
-- === Gestionnaires BTN ===
-- =========================
local function AttachDeleteExpenseHandler(r, f, d)
    r.btnDelete:SetEnabled(not d.lotId)
    r.btnDelete:SetOnClick(function()
        local abs = r._abs
        local eid = tonumber(d.id or 0) or 0
        UI.PopupConfirm("Supprimer cette ligne de ressource ?", function()
            GMGR.DeleteExpense((eid > 0) and eid or abs)
            if ns.RefreshAll then ns.RefreshAll() end
        end)
    end)
end

local function AttachDeleteLotHandler(r, lot)
    -- Sécurise l'appel si le bouton n'existe pas (non-GM)
    if not r.btnDelete then return end
    local canDelete = (tonumber(lot.used or 0) or 0) == 0
    r.btnDelete:SetEnabled(canDelete)
    r.btnDelete:SetOnClick(function()
        if canDelete and GMGR.Lot_Delete then GMGR.Lot_Delete(lot.id) end
    end)
end

-- =========================
-- === RESSOURCES LIBRES ===
-- =========================
local function BuildRowFree(r)
    local f = {}
    f.sel    = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
    f.qty    = UI.Label(r)
    f.source = UI.Label(r)
    f.amount = UI.Label(r)
    f.item   = UI.CreateItemCell(r, { size = 16, width = 220 })

    f.act = CreateFrame("Frame", nil, r)
    f.act:SetHeight(UI.ROW_H)
    f.act:SetFrameLevel(r:GetFrameLevel()+1)

    r.btnDelete = UI.Button(f.act, "X", { size="sm", variant="danger", minWidth=30 })
    r.btnDelete:SetShown(GMGR.IsMaster and GMGR.IsMaster())
    UI.AttachRowRight(f.act, { r.btnDelete }, 8, -4, { leftPad=8, align="center" })
    return f
end

local function UpdateRowFree(i, r, f, it)
    local d = it.data or it
    r._abs = it._abs or i

    if GMGR.IsMaster and GMGR.IsMaster() then
        f.sel:Show()
        f.sel:SetChecked(selected[r._abs] or false)
        f.sel:SetScript("OnClick", function(self)
            selected[r._abs] = self:GetChecked()
            if ns.RefreshActive then ns.RefreshActive() end
        end)
    else
        f.sel:Hide()
        f.sel:SetScript("OnClick", nil)
    end
    if r.btnDelete and r.btnDelete.SetShown then r.btnDelete:SetShown(GMGR.IsMaster and GMGR.IsMaster()) end

    f.qty:SetText(tostring(d.qty or 1))
    f.source:SetText(tostring(d.source or ""))
    f.amount:SetText(moneyCopper(d.copper))
    UI.SetItemCell(f.item, d)

    AttachDeleteExpenseHandler(r, f, d)
end

-- =========================
-- ========= LOTS ==========
-- =========================
local function BuildRowLots(r)
    local f = {}
    f.name    = UI.Label(r)
    f.type    = UI.Label(r)
    f.status  = UI.Label(r)
    f.content = UI.Button(r, "0", { size="sm", minWidth=40 })
    f.total   = UI.Label(r)

    f.act = CreateFrame("Frame", nil, r)
    f.act:SetHeight(UI.ROW_H)
    f.act:SetFrameLevel(r:GetFrameLevel()+1)

    -- Bouton X uniquement pour le GM
    if GMGR.IsMaster and GMGR.IsMaster() then
        r.btnDelete = UI.Button(f.act, "X", { size="sm", variant="danger", minWidth=30 })
        UI.AttachRowRight(f.act, { r.btnDelete }, 8, -4, { leftPad=8, align="center" })
    end
    return f
end

local function UpdateRowLots(i, r, f, it)
    local lot = it.data
    local st  = GMGR.Lot_Status and GMGR.Lot_Status(lot) or "?"
    local N   = tonumber(lot.sessions or 1) or 1
    local used= tonumber(lot.used or 0) or 0
    local totalGold = (GMGR.Lot_ShareGold and GMGR.Lot_ShareGold(lot) or 0) * N

    f.name:SetText(lot.name or ("Lot "..tostring(lot.id)))
    f.type:SetText(N>1 and (N.." utilisations") or "1 utilisation")
    f.status:SetText( (st=="EPU" and "Épuisé") or (GMGR.Lot_Remaining and (GMGR.Lot_Remaining(lot).." restantes")) or ((N-used).." restantes") )
    f.content:SetText(tostring(#(lot.itemIds or {})))
    f.total:SetText(UI.MoneyText(totalGold))

    f.content:SetOnClick(function()
        local dlg = UI.CreatePopup({ title="Contenu du lot : " .. (lot.name or ("Lot " .. tostring(lot.id))), width=580, height=440 })
        local cols = UI.NormalizeColumns({
            { key="qty",  title="Qté",   w=60,  justify="RIGHT" },
            { key="item", title="Objet", min=320, flex=1 },
            { key="src",  title="Source", w=120 },
            { key="amt",  title="Montant", w=120, justify="RIGHT" },
        })
        local lv = UI.ListView(dlg.content, cols, {
            buildRow = function(r2)
                local ff = {}
                ff.qty   = UI.Label(r2, { justify="RIGHT" })
                ff.src   = UI.Label(r2)
                ff.amt   = UI.Label(r2, { justify="RIGHT" })
                ff.item  = UI.CreateItemCell(r2, { size=20, width=240 })
                return ff
            end,
            updateRow = function(i2, r2, ff, exp)
                ff.qty:SetText(exp.qty or 1)
                ff.src:SetText(exp.source or "")
                ff.amt:SetText(moneyCopper(exp.copper))
                UI.SetItemCell(ff.item, exp)
            end,
        })
        local rows = {}
        if GMGR.GetExpenseById then
            for _, eid in ipairs(lot.itemIds or {}) do
                local _, it = GMGR.GetExpenseById(eid)
                if it then table.insert(rows, it) end
            end
        end
        lv:SetData(rows)
        dlg:SetButtons({ { text="Fermer", default=true } })
        dlg:Show()
    end)

    AttachDeleteLotHandler(r, lot)
end

-- =========================
-- ====== LAYOUT/REF =======
-- =========================
local function Layout()
    local pad = PAD
    local W, H = panel:GetWidth(), panel:GetHeight()
    local footerH = footer:GetHeight() + 6
    local availH = H - footerH - (pad*2)
    local topH   = math.floor(availH * 0.60)

    topPane:ClearAllPoints()
    topPane:SetPoint("TOPLEFT",  panel, "TOPLEFT",  pad, -pad)
    topPane:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -pad, -pad)
    topPane:SetHeight(topH)

    bottomPane:ClearAllPoints()
    bottomPane:SetPoint("TOPLEFT",  topPane, "BOTTOMLEFT", 0, -6)
    bottomPane:SetPoint("TOPRIGHT", topPane, "BOTTOMRIGHT", 0, -6)
    bottomPane:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", pad, pad + footerH)
    bottomPane:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -pad, pad + footerH)

    if UI.AttachButtonsFooterRight then
        local buttons = {}
        local isGM = (GMGR.IsMaster and GMGR.IsMaster()) or false
        if isGM and btnCreateLot then table.insert(buttons, btnCreateLot) end
        if isGM then
            if btnToggle   then btnToggle:Show()   table.insert(buttons, btnToggle)   end
            if btnClearAll then btnClearAll:Show() table.insert(buttons, btnClearAll) end
        else
            if btnToggle   then btnToggle:Hide() end
            if btnClearAll then btnClearAll:Hide() end
        end
        UI.AttachButtonsFooterRight(footer, buttons, 8, nil)
    end

    if lvFree and lvFree.Layout then lvFree:Layout() end
    if lvLots and lvLots.Layout then lvLots:Layout() end
end

local function Refresh()
    local e = (GuildManagerDB and GuildManagerDB.expenses) or { list = {} }
    local items, total = {}, 0
    for idx, it in ipairs(e.list or {}) do
        if (not it.lotId) or (it.lotId == 0) then
            total = total + (tonumber(it.copper) or 0)
            items[#items+1] = { _abs=idx, data=it }
        end
    end
    lvFree:SetData(items)
    totalFS:SetText("|cffffd200Ressources libres :|r " .. moneyCopper(total))

    local lots = (GMGR.GetLots and GMGR.GetLots()) or {}
    table.sort(lots, function(a,b)
        local an = (a and a.name or ""):lower()
        local bn = (b and b.name or ""):lower()
        if an == bn then return (a and a.id or 0) < (b and b.id or 0) end
        return an < bn
    end)

    local rows = {}
    for _, l in ipairs(lots) do
        local pending = (l.__pendingConsume or l.__pendingDelete)
        if (not pending) and not (GMGR.Lot_Status and GMGR.Lot_Status(l) == "EPU") then
            rows[#rows+1] = { data=l }
        end
    end
    lvLots:SetData(rows)

    btnCreateLot:SetShown(GMGR.IsMaster and GMGR.IsMaster())
    btnClearAll:SetEnabled(true)
    local on = GMGR.IsExpensesRecording and GMGR.IsExpensesRecording()
    btnToggle:SetText(on and "Stopper l'enregistrement" or "Démarrer l'enregistrement des dépenses")

    Layout()
end

-- =========================
-- ========= BUILD =========
-- =========================
local function Build(container)
    panel = container
    if UI.ApplySafeContentBounds then UI.ApplySafeContentBounds(panel, { side=10, bottom=6 }) end

    footer   = UI.CreateFooter(panel, 36)
    topPane  = CreateFrame("Frame", nil, panel)
    bottomPane = CreateFrame("Frame", nil, panel)

    UI.SectionHeader(topPane,    "Réserve d'objets")
    lvFree = UI.ListView(topPane, colsFree, { buildRow=BuildRowFree, updateRow=UpdateRowFree, topOffset=UI.SECTION_HEADER_H or 26 })

    UI.SectionHeader(bottomPane, "Lots utilisables pour les raids")
    lvLots = UI.ListView(bottomPane, colsLots, { buildRow=BuildRowLots, updateRow=UpdateRowLots, topOffset=UI.SECTION_HEADER_H or 26})

    btnCreateLot = UI.Button(footer, "Créer un lot", { size="sm", minWidth=140, tooltip="Sélectionnez des ressources pour créer un lot (contenu figé)." })
    btnCreateLot:SetOnClick(function()
        if not (GMGR.IsMaster and GMGR.IsMaster()) then return end
        local idxs = {}
        for abs,v in pairs(selected) do if v then idxs[#idxs+1] = abs end end
        table.sort(idxs)
        if #idxs == 0 then
            UIErrorsFrame:AddMessage("|cffff6060[GMGR]|r Aucune ressource sélectionnée.", 1,0.4,0.4)
            return
        end
        local dlg = UI.CreatePopup({ title="Créer un lot", width=420, height=220 })
        local nameLabel = dlg.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); nameLabel:SetText("Nom du lot :")
        local nameInput = CreateFrame("EditBox", nil, dlg.content, "InputBoxTemplate"); nameInput:SetSize(240, 28); nameInput:SetAutoFocus(true)
        local nLabel   = dlg.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); nLabel:SetText("Nombre d'utilisations")
        local nInput   = CreateFrame("EditBox", nil, dlg.content, "InputBoxTemplate"); nInput:SetSize(80, 28); nInput:SetNumeric(true); nInput:SetNumber(1)
        nameLabel:SetPoint("TOPLEFT", dlg.content, "TOPLEFT", 6, -14)
        nameInput:SetPoint("LEFT", nameLabel, "RIGHT", 8, 0)
        nLabel:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -14)
        nInput:SetPoint("LEFT", nLabel, "RIGHT", 8, 0)

        dlg:SetButtons({
            { text="Créer", default=true, onClick=function()
                local nm = nameInput:GetText() or ""
                if nm == "" then nm = "Lot" end
                local N  = tonumber(nInput:GetNumber() or 1) or 1
                if N < 1 then N = 1 end
                local isMulti = (N > 1)
                if GMGR.Lot_Create then
                    GMGR.Lot_Create(nm, isMulti, N, idxs)
                    selected = {}
                    if ns.RefreshAll then ns.RefreshAll() end
                end
            end },
            { text=CANCEL, variant="ghost" },
        })
        dlg:Show()
    end)

    btnToggle = UI.Button(footer, "Démarrer l'enregistrement des dépenses", { size="sm", minWidth=260 })
    btnToggle:SetOnClick(function()
        local isRecording = GMGR.IsExpensesRecording and GMGR.IsExpensesRecording()
        if isRecording and GMGR.ExpensesStop then
            GMGR.ExpensesStop()
        elseif (not isRecording) and GMGR.ExpensesStart then
            GMGR.ExpensesStart()
        end
        local nowOn = GMGR.IsExpensesRecording and GMGR.IsExpensesRecording()
        btnToggle:SetText(nowOn and "Stopper l'enregistrement" or "Démarrer l'enregistrement des dépenses")
        if ns and ns.RefreshAll then ns.RefreshAll() end
    end)

    btnClearAll = UI.Button(footer, "Tout vider (libres)", { size="sm", variant="danger", minWidth=160 })
    btnClearAll:SetConfirm("Vider la liste des ressources libres ? (les lots ne sont pas affectés)", function()
        if GMGR.ClearExpenses then GMGR.ClearExpenses() end
        if ns and ns.RefreshAll then ns.RefreshAll() end
    end)

    totalFS = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    totalFS:SetPoint("LEFT", footer, "LEFT", PAD, 0)
end

UI.RegisterTab("Ressources", Build, Refresh, Layout)
