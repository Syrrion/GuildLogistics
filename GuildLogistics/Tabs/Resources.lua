local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI, F = ns.GLOG, ns.UI, ns.Format
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
    local isGM = (GLOG.IsMaster and GLOG.IsMaster()) or false
    local cols = {
        { key="qty",    title=Tr("col_qty_short"),     w=44  },
        { key="item",   title=Tr("col_item"),   min=260, flex=1 },
        { key="source", title=Tr("col_source"),  w=120 },
        { key="amount", title=Tr("col_amount"), w=160 },
    }
    if isGM then
        table.insert(cols, 1, { key="sel", title="", w=34 })
        table.insert(cols, 6, { key="act", title="", w=40 })
    end
    return UI.NormalizeColumns(cols)
end

local colsFree = BuildColsFree()

local colsLots = UI.NormalizeColumns({
    { key="name",   title=Tr("col_bundle"),           min=220, flex=1 },
    { key="type",   title=Tr("col_uses"),  w=110 },
    { key="status", title=Tr("col_remaining"),     w=110 },
    { key="content",title=Tr("col_content"),       w=60 },
    { key="total",  title=Tr("col_total_value"), w=120 },
    { key="act",    title="",              w=(GLOG.IsMaster and GLOG.IsMaster()) and 40 or 0 },
})

-- =========================
-- ======   HELPERS   ======
-- =========================
local function moneyCopper(v)
    return UI.MoneyFromCopper(tonumber(v) or 0)
end

-- Résout la source à afficher depuis l'ID (fallback sur l'ancien champ texte)
local function resolveSourceLabel(it)
    if it and it.sourceId and ns and ns.GLOG and ns.GLOG.GetExpenseSourceLabel then
        return ns.GLOG.GetExpenseSourceLabel(it.sourceId)
    end
    return tostring(it and it.source or "")
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
local function AttachSplitExpenseHandler(r, f, d)
    if not r.btnSplit then return end
    local qty = tonumber(d.qty or 1) or 1
    local canSplit = (not d.lotId) and (qty > 1)
    r.btnSplit:SetEnabled(canSplit)
    r.btnSplit:SetOnClick(function()
        if not canSplit then return end
        UI.PopupPromptNumber(Tr("popup_split_title"), Tr("lbl_split_qty"), function(v)
            local qs = tonumber(v or 0) or 0
            if qs <= 0 or qs >= qty then
                UI.PopupConfirm(Tr("err_split_qty_invalid"))
                return
            end
            -- ID solide depuis la ligne (renseigné lors de l'update visuelle)
            local eid = tonumber(r._expenseId) or tonumber(d.id) or tonumber(r._abs) or tonumber(r._index)
            if GLOG and GLOG.Debug then GLOG.Debug("CLICK","SPLIT","eid=",eid,"qs=",qs) end
            if not eid or eid <= 0 then
                UI.PopupConfirm(Tr("err_split_failed"))
                return
            end
            local ok = (GLOG.SplitExpense and GLOG.SplitExpense(eid, qs)) and true or false
            if not ok then
                UI.PopupConfirm(Tr("err_split_failed"))
                return
            end
            if ns and ns.RefreshAll then ns.RefreshAll() end
        end)
    end)
end

local function AttachDeleteExpenseHandler(r, f, d)
    r.btnDelete:SetEnabled(not d.lotId)
    r.btnDelete:SetOnClick(function()
        local abs = r._abs
        local eid = tonumber(d.id or 0) or 0
        UI.PopupConfirm(Tr("confirm_delete_resource_line"), function()
            GLOG.DeleteExpense((eid > 0) and eid or abs)
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
        if canDelete and GLOG.Lot_Delete then GLOG.Lot_Delete(lot.id) end
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

    r.btnSplit  = UI.Button(f.act, Tr("btn_split"), { size="sm", minWidth=30, tooltip=Tr("hint_split_resource") })
    r.btnSplit:SetShown(GLOG.IsMaster and GLOG.IsMaster())

    r.btnDelete = UI.Button(f.act, Tr("btn_delete_short"), { size="sm", variant="danger", minWidth=30 })
    r.btnDelete:SetShown(GLOG.IsMaster and GLOG.IsMaster())

    UI.AttachRowRight(f.act, { r.btnDelete, r.btnSplit }, 8, -4, { leftPad=8, align="center" })
    return f
end


local function UpdateRowFree(i, r, f, it)
    local d = it.data or it
    r._abs = it._abs or i

    if GLOG.IsMaster and GLOG.IsMaster() then
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
    if r.btnDelete and r.btnDelete.SetShown then r.btnDelete:SetShown(GLOG.IsMaster and GLOG.IsMaster()) end
    if r.btnSplit  and r.btnSplit.SetShown  then r.btnSplit:SetShown(GLOG.IsMaster and GLOG.IsMaster()) end

    f.qty:SetText(tostring(d.qty or 1))
    f.source:SetText(resolveSourceLabel(d))
    f.amount:SetText(moneyCopper(d.copper))
    UI.SetItemCell(f.item, d)

    -- Mémorise l'ID exact de la dépense pour les handlers
    r._expenseId = tonumber(d.id or 0)

    AttachSplitExpenseHandler(r, f, d)
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
    if GLOG.IsMaster and GLOG.IsMaster() then
        r.btnDelete = UI.Button(f.act, Tr("btn_delete_short"), { size="sm", variant="danger", minWidth=30 })
        UI.AttachRowRight(f.act, { r.btnDelete }, 8, -4, { leftPad=8, align="center" })
    end
    return f
end

local function UpdateRowLots(i, r, f, it)
    local lot = it.data
    local st  = GLOG.Lot_Status and GLOG.Lot_Status(lot) or "?"
    local N   = tonumber(lot.sessions or 1) or 1
    local used= tonumber(lot.used or 0) or 0
    local totalCopper = tonumber(lot.totalCopper or lot.copper or 0) or 0

    f.name:SetText(lot.name or (Tr("lbl_lot")..tostring(lot.id)))
    f.type:SetText(N>1 and (N..Tr("lbl_uses")) or "1"..Tr("lbl_use"))
    f.status:SetText( (st=="EPU" and Tr("badge_exhausted")) or (GLOG.Lot_Remaining and (GLOG.Lot_Remaining(lot).." "..Tr("suffix_remaining"))) or ((N-used).." "..Tr("suffix_remaining")))
    -- Somme des quantités d'objets sur les dépenses du lot
    local sumQty = 0
    if GLOG and GLOG.GetExpenseById then
        for _, eid in ipairs(lot.itemIds or {}) do
            local _, exp = GLOG.GetExpenseById(eid)
            local q = tonumber(exp and exp.qty or 0) or 0
            if q > 0 then sumQty = sumQty + 1 end
        end
    end
    -- Lot “or uniquement” : 0 objets si pas de lignes mais du cuivre total
    if sumQty == 0 and totalCopper > 0 then
        f.content:SetText("0")
    else
        f.content:SetText(tostring(sumQty))
    end

    f.total:SetText(moneyCopper(totalCopper))

    f.content:SetOnClick(function()
        local dlg = UI.CreatePopup({ title=Tr("lbl_bundle_contents") .. (lot.name or (Tr("lbl_lot") .. tostring(lot.id))), width=580, height=440 })
        local cols = UI.NormalizeColumns({
            { key="qty",  title=Tr("col_qty_short"),   w=40,  justify="RIGHT" },
            { key="item", title=Tr("col_item"), min=240, flex=1 },
            { key="src",  title=Tr("col_source"), w=70 },
            { key="amt",  title=Tr("col_amount"), w=120, justify="RIGHT" },
        })
        local lv = UI.ListView(dlg.content, cols, {
            buildRow = function(r2)
                local ff = {}
                ff.qty   = UI.Label(r2, { justify="RIGHT" })
                ff.src   = UI.Label(r2)
                ff.unit  = UI.Label(r2, { justify="RIGHT" })
                ff.amt   = UI.Label(r2, { justify="RIGHT" })
                ff.item  = UI.CreateItemCell(r2, { size=20, width=240 })
                return ff
            end,
            updateRow = function(i2, r2, ff, exp)
                local q  = tonumber(exp.qty or 1) or 1
                local cp = tonumber(exp.copper or 0) or 0
                local unitCopper = (q > 0) and math.floor((cp / q) + 0.5) or 0

                ff.qty:SetText(q)
                ff.src:SetText(resolveSourceLabel(exp))
                ff.unit:SetText(moneyCopper(unitCopper))
                ff.amt:SetText(moneyCopper(cp))
                UI.SetItemCell(ff.item, exp)
            end,
        })

        local rows = {}
        if GLOG.GetExpenseById then
            -- Chemin normal : à partir des expenseIds du lot
            for _, eid in ipairs(lot.itemIds or {}) do
                local _, it = GLOG.GetExpenseById(eid)
                if it then table.insert(rows, it) end
            end
            -- Fallback : si la liste est vide, balayer les dépenses et filtrer par lotId
            if #rows == 0 and GLOG.GetExpenses then
                local list = GLOG.GetExpenses()  -- renvoie list,total : ici Lua garde le 1er retour
                for _, it in ipairs(list or {}) do
                    if tonumber(it.lotId or 0) == tonumber(lot.id or 0) then
                        table.insert(rows, it)
                    end
                end
            end
        end
        lv:SetData(rows)

        dlg:SetButtons({ { text=Tr("btn_close"), default=true } })
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
        local isGM = (GLOG.IsMaster and GLOG.IsMaster()) or false
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
    local e = (GuildLogisticsDB and GuildLogisticsDB.expenses) or { list = {} }
    local items, total = {}, 0
    for idx, it in ipairs(e.list or {}) do
        if (not it.lotId) or (it.lotId == 0) then
            total = total + (tonumber(it.copper) or 0)
            items[#items+1] = { _abs=idx, data=it }
        end
    end
    lvFree:SetData(items)
    totalFS:SetText("|cffffd200"..Tr("lbl_free_resources").."|r " .. moneyCopper(total))

    local lots = (GLOG.GetLots and GLOG.GetLots()) or {}
    table.sort(lots, function(a,b)
        local an = (a and a.name or ""):lower()
        local bn = (b and b.name or ""):lower()
        if an == bn then return (a and a.id or 0) < (b and b.id or 0) end
        return an < bn
    end)

    local rows = {}
    for _, l in ipairs(lots) do
        local pending = (l.__pendingConsume or l.__pendingDelete)
        if (not pending) and not (GLOG.Lot_Status and GLOG.Lot_Status(l) == "EPU") then
            rows[#rows+1] = { data=l }
        end
    end
    lvLots:SetData(rows)

    btnCreateLot:SetShown(GLOG.IsMaster and GLOG.IsMaster())
    btnClearAll:SetEnabled(true)
    local on = GLOG.IsExpensesRecording and GLOG.IsExpensesRecording()
    btnToggle:SetText(on and Tr("btn_stop_recording") or Tr("btn_start_recording_expenses"))

    Layout()
end

-- =========================
-- ========= BUILD =========
-- =========================
local function Build(container)
    -- Création du conteneur
    panel, footer, footerH = UI.CreateMainContainer(container, {footer = true})
    
    topPane  = CreateFrame("Frame", nil, panel)
    bottomPane = CreateFrame("Frame", nil, panel)

    UI.SectionHeader(topPane,    Tr("lbl_item_reserve"))
    lvFree = UI.ListView(topPane, colsFree, { buildRow=BuildRowFree, updateRow=UpdateRowFree, topOffset=UI.SECTION_HEADER_H or 26 })

    UI.SectionHeader(bottomPane, Tr("lbl_usable_bundles_raids"))
    lvLots = UI.ListView(bottomPane, colsLots, { buildRow=BuildRowLots, updateRow=UpdateRowLots, topOffset=UI.SECTION_HEADER_H or 26})

    btnCreateLot = UI.Button(footer, Tr("btn_create_bundle"), { size="sm", minWidth=140, tooltip=Tr("hint_select_resources_bundle") })
    btnCreateLot:SetOnClick(function()
        if not (GLOG.IsMaster and GLOG.IsMaster()) then return end
        local idxs = {}
        for abs,v in pairs(selected) do 
            if v then idxs[#idxs+1] = abs end 
        end
        table.sort(idxs)

        if #idxs == 0 then
            -- Aucun objet sélectionné : proposer la création d'un lot "or uniquement"
            local dlg = UI.CreatePopup({ title=Tr("btn_create_bundle"), width=480, height=240 })

            -- Nom du lot
            local nameLabel = dlg.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            nameLabel:SetText(Tr("lbl_bundle_name"))
            local nameInput = CreateFrame("EditBox", nil, dlg.content, "InputBoxTemplate")
            nameInput:SetSize(280, 28); nameInput:SetAutoFocus(true)

            -- Nombre d'utilisations (multi-session)
            local nLabel = dlg.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            nLabel:SetText(Tr("lbl_num_uses"))
            local nInput = CreateFrame("EditBox", nil, dlg.content, "InputBoxTemplate")
            nInput:SetSize(80, 28); nInput:SetNumeric(true); nInput:SetNumber(1)

            -- Montant (en or)
            local gLabel = dlg.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            gLabel:SetText(Tr("lbl_amount_gold"))
            local gInput = CreateFrame("EditBox", nil, dlg.content, "InputBoxTemplate")
            gInput:SetSize(120, 28); gInput:SetNumeric(true); gInput:SetNumber(0)

            -- Layout simple
            nameLabel:SetPoint("TOPLEFT", dlg.content, "TOPLEFT", 6, -14)
            nameInput:SetPoint("LEFT", nameLabel, "RIGHT", 8, 0)

            nLabel:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -14)
            nInput:SetPoint("LEFT", nLabel, "RIGHT", 8, 0)

            gLabel:SetPoint("TOPLEFT", nLabel, "BOTTOMLEFT", 0, -14)
            gInput:SetPoint("LEFT", gLabel, "RIGHT", 8, 0)

            dlg:SetButtons({
                { text=Tr("btn_create"), default=true, onClick=function()
                    local nm = nameInput:GetText() or ""
                    if nm == "" then nm = Tr("lbl_bundle") end

                    local N = tonumber(nInput:GetNumber() or 1) or 1
                    if N < 1 then N = 1 end
                    local isMulti = (N > 1)

                    local gold = tonumber(gInput:GetNumber() or 0) or 0
                    if gold <= 0 then
                        UI.PopupConfirm(Tr("err_amount_invalid"))
                        return
                    end
                    local copper = gold * 10000

                    if GLOG.Lot_CreateFromAmount then
                        GLOG.Lot_CreateFromAmount(nm, copper, isMulti, N)
                        selected = {}
                        if ns.RefreshAll then ns.RefreshAll() end
                    end
                end },
                { text=Tr("btn_cancel"), variant="ghost" },
            })

            return
        end

        local dlg = UI.CreatePopup({ title=Tr("btn_create_bundle"), width=420, height=220 })
        local nameLabel = dlg.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); nameLabel:SetText(Tr("lbl_bundle_name"))
        local nameInput = CreateFrame("EditBox", nil, dlg.content, "InputBoxTemplate"); nameInput:SetSize(240, 28); nameInput:SetAutoFocus(true)
        local nLabel   = dlg.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); nLabel:SetText(Tr("lbl_num_uses"))
        local nInput   = CreateFrame("EditBox", nil, dlg.content, "InputBoxTemplate"); nInput:SetSize(80, 28); nInput:SetNumeric(true); nInput:SetNumber(1)
        nameLabel:SetPoint("TOPLEFT", dlg.content, "TOPLEFT", 6, -14)
        nameInput:SetPoint("LEFT", nameLabel, "RIGHT", 8, 0)
        nLabel:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -14)
        nInput:SetPoint("LEFT", nLabel, "RIGHT", 8, 0)

        dlg:SetButtons({
            { text=Tr("btn_create"), default=true, onClick=function()
                local nm = nameInput:GetText() or ""
                if nm == "" then nm = Tr("lbl_bundle") end
                local N  = tonumber(nInput:GetNumber() or 1) or 1
                if N < 1 then N = 1 end
                local isMulti = (N > 1)
                if GLOG.Lot_Create then
                    GLOG.Lot_Create(nm, isMulti, N, idxs)
                    selected = {}
                    if ns.RefreshAll then ns.RefreshAll() end
                end
            end },
            { text=Tr("btn_cancel"), variant="ghost" },
        })
        dlg:Show()
    end)

    btnToggle = UI.Button(footer, Tr("btn_start_recording_expenses"), { size="sm", minWidth=260 })
    btnToggle:SetOnClick(function()
        local isRecording = GLOG.IsExpensesRecording and GLOG.IsExpensesRecording()
        if isRecording and GLOG.ExpensesStop then
            GLOG.ExpensesStop()
        elseif (not isRecording) and GLOG.ExpensesStart then
            GLOG.ExpensesStart()
        end
        local nowOn = GLOG.IsExpensesRecording and GLOG.IsExpensesRecording()
        btnToggle:SetText(nowOn and Tr("btn_stop_recording") or Tr("btn_start_recording_expenses"))
        if ns and ns.RefreshAll then ns.RefreshAll() end
    end)

    btnClearAll = UI.Button(footer, Tr("btn_clear_all_free"), { size="sm", variant="danger", minWidth=160 })
    btnClearAll:SetConfirm(Tr("confirm_clear_free_resources"), function()
        if GLOG.ClearExpenses then GLOG.ClearExpenses() end
        if ns and ns.RefreshAll then ns.RefreshAll() end
    end)

    totalFS = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    totalFS:SetPoint("LEFT", footer, "LEFT", PAD, 0)
end

UI.RegisterTab(Tr("tab_resources"), Build, Refresh, Layout, {
    category = Tr("cat_raids"),
})
