local ADDON, ns = ...
local CDZ, UI, F = ns.CDZ, ns.UI, ns.Format
local PAD, SBW, GUT = UI.OUTER_PAD, UI.SCROLLBAR_W, UI.GUTTER

-- =========================
-- ======   RESSOURCES  ====
-- =========================
-- Vue combinée : Ressources libres (dépenses non rattachées) + Lots (consommables)

local panel, footer
local topPane, bottomPane
local lvFree, lvLots
local btnToggle, totalFS, btnClearAll, btnCreateLot

local selected = {} -- sélection : clés = index absolu dans expenses.list

-- Colonnes Ressources libres
local colsFree = UI.NormalizeColumns({
    { key="sel",    title="",        w=34  },  -- (masquée côté non-GM au niveau de la ligne)
    { key="qty",    title="Qté",     w=60  },
    { key="item",   title="Objet",   min=260, flex=1 },
    { key="source", title="Source",  w=120 },
    { key="amount", title="Montant", w=160 },
    { key="act",    title="Actions", w=120 },  -- (Supprimer masqué côté non-GM)
})

local colsLots = UI.NormalizeColumns({
    { key="name",   title="Lot",                 min=220, flex=1 },
    { key="type",   title="Utilisations",        w=110 },
    { key="status", title="Restantes",           w=110 },
    { key="count",  title="#",                   w=40  },
    { key="total",  title="Valeur totale",       w=120 },
    { key="act",    title="Actions",             w=160 },
})

-- ===== Utilitaires =====
local function resolveItemName(it)
    -- 1) Priorité à l’itemID (résolution paresseuse via cache WoW)
    if it.itemID then
        local name = GetItemInfo and select(1, GetItemInfo(it.itemID))
        if name and name ~= "" then return name end
    end

    -- 2) Fallback sur le lien si présent
    if it.itemLink and it.itemLink ~= "" then
        local name = GetItemInfo and select(1, GetItemInfo(it.itemLink))
        if name and name ~= "" then return name end
        local bracket = it.itemLink:match("%[(.-)%]"); if bracket and bracket ~= "" then return bracket end
    end

    -- 3) Fallback legacy : nom stocké
    if it.itemName and it.itemName ~= "" then return it.itemName end

    -- 4) Dernier recours : placeholder à partir de l’ID
    if it.itemID then return "Objet #"..tostring(it.itemID) end
    return ""
end

local function resolveItemIcon(it)
    -- 1) Priorité à l’itemID
    if it.itemID then
        if GetItemIcon then local tex = GetItemIcon(it.itemID); if tex then return tex end end
        if GetItemInfoInstant then local _,_,_,_,icon = GetItemInfoInstant(it.itemID); if icon then return icon end end
    end
    -- 2) Fallback sur le lien
    if it.itemLink and it.itemLink ~= "" then
        if GetItemIcon then local tex = GetItemIcon(it.itemLink); if tex then return tex end end
        if GetItemInfoInstant then local _,_,_,_,icon = GetItemInfoInstant(it.itemLink); if icon then return icon end end
    end
    return 134400 -- sac par défaut
end

-- ====== Ressources libres (ListView) ======
local function BuildRowFree(r)
    local f = {}
    f.sel    = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
    -- (plus de champ date)
    f.qty    = UI.Label(r)
    f.source = UI.Label(r)
    f.amount = UI.Label(r)
    f.item     = CreateFrame("Button", nil, r); f.item:SetHeight(UI.ROW_H)

    f.itemText = f.item:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.icon     = f.item:CreateTexture(nil, "ARTWORK"); f.icon:SetSize(16, 16)
    f.icon:SetPoint("LEFT", f.item, "LEFT", 0, 0)
    f.itemText:SetPoint("LEFT",  f.icon, "RIGHT", 3, 0)
    f.itemText:SetPoint("RIGHT", f.item, "RIGHT", 0, 0)
    f.itemText:SetJustifyH("LEFT")

    f.item:SetScript("OnEnter", function(self)
        if self._link and GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetHyperlink(self._link); GameTooltip:Show() end
    end)
    f.item:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    f.item:SetScript("OnMouseUp", function(self)
        if self._link and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then ChatEdit_InsertLink(self._link) end
    end)

    f.act = CreateFrame("Frame", nil, r); f.act:SetHeight(UI.ROW_H); f.act:SetFrameLevel(r:GetFrameLevel()+1)
    r.btnDelete = UI.Button(f.act, "Supprimer", { size="sm", variant="danger", minWidth=110 })
    r.btnDelete:SetShown(CDZ.IsMaster and CDZ.IsMaster()) -- masque pour non-GM
    UI.AttachRowRight(f.act, { r.btnDelete }, 8, -4, { leftPad = 8, align = "center" })
    return f
end

local function UpdateRowFree(i, r, f, it)
    local d = it.data or it
    r._abs = it._abs or i

    if CDZ.IsMaster and CDZ.IsMaster() then
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
    if r.btnDelete and r.btnDelete.SetShown then r.btnDelete:SetShown(CDZ.IsMaster and CDZ.IsMaster()) end

    f.qty:SetText(tostring(d.qty or 1))
    f.source:SetText(tostring(d.source or ""))
    f.amount:SetText(UI.MoneyFromCopper(tonumber(d.copper) or 0))
    -- date supprimée (ts non utilisé)
    if f.date then f.date:SetText("") end

    -- Résolution stricte depuis l’itemID (réduit la taille des données transportées)
    local itemID = tonumber(d.itemID or 0) or 0
    local link = (itemID > 0) and (select(2, GetItemInfo(itemID))) or d.itemLink
    local name = (link and link:match("%[(.-)%]")) or (GetItemInfo(itemID)) or d.itemName or "Objet inconnu"
    local icon = (itemID > 0) and (select(5, GetItemInfoInstant(itemID))) or resolveItemIcon(d)

    f.itemText:SetText(name or "")
    f.icon:SetTexture(icon or "Interface\\ICONS\\INV_Misc_QuestionMark")

    -- pour le tooltip de la cellule “Objet”
    if f.item then
        f.item._itemID = itemID
        f.item._link   = link
    end

    r.btnDelete:SetEnabled(not d.lotId)
    r.btnDelete:SetOnClick(function()
        -- Snapshot : on capture l'id stable et l'index absolu au moment du clic
        local abs = r._abs
        local eid = tonumber(d.id or 0) or 0
        UI.PopupConfirm("Supprimer cette ligne de ressource ?", function()
            -- On privilégie l'id stable (robuste même si la liste se réordonne)
            CDZ.DeleteExpense((eid > 0) and eid or abs)
            if ns.RefreshAll then ns.RefreshAll() end
        end)
    end)
end

-- ====== Lots (ListView) ======
local function BuildRowLots(r)
    local f = {}
    f.name   = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.type   = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.status = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.count  = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.total  = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")

    f.act = CreateFrame("Frame", nil, r); f.act:SetHeight(UI.ROW_H); f.act:SetFrameLevel(r:GetFrameLevel()+1)
    r.btnView   = UI.Button(f.act, "Voir", { size="sm", minWidth=70 })
    r.btnDelete = UI.Button(f.act, "Supprimer", { size="sm", variant="danger", minWidth=90 })
    r.btnDelete:SetShown(CDZ.IsMaster and CDZ.IsMaster()) -- masque pour non-GM
    UI.AttachRowRight(f.act, { r.btnDelete, r.btnView }, 8, -4, { leftPad = 8, align = "center" })
    return f
end

local function UpdateRowLots(i, r, f, it)
    local lot = it.data
    local st  = CDZ.Lot_Status and CDZ.Lot_Status(lot) or "?"
    local N   = tonumber(lot.sessions or 1) or 1
    local used= tonumber(lot.used or 0) or 0
    local totalGold = (CDZ.Lot_ShareGold and CDZ.Lot_ShareGold(lot) or 0) * N

    f.name:SetText(lot.name or ("Lot "..tostring(lot.id)))
    f.type:SetText(N>1 and (N.." utilisations") or "1 utilisation")
    f.status:SetText( (st=="EPU" and "Épuisé") or (CDZ.Lot_Remaining and (CDZ.Lot_Remaining(lot).." restantes")) or ((N-used).." restantes") )
    f.total:SetText(UI.MoneyText(totalGold))
    f.count:SetText(tostring(#(lot.itemIds or {})))
    f.total:SetText(UI.MoneyText(totalGold))
    
        r.btnView:SetOnClick(function()
        local dlg = UI.CreatePopup({ title = "Contenu du lot : " .. (lot.name or ("Lot " .. tostring(lot.id))), width = 580, height = 440 })
        local cols = UI.NormalizeColumns({
            { key="qty",  title="Qté",   w=60,  justify="RIGHT" },
            { key="item", title="Objet", min=320, flex=1 },
            { key="src",  title="Source", w=120 },
            { key="amt",  title="Montant", w=120, justify="RIGHT" },
        })

        local lv = UI.ListView(dlg.content, cols, {
            buildRow = function(r2)
                local ff = {}
                ff.qty   = r2:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                ff.src   = r2:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                ff.amt   = r2:CreateFontString(nil, "OVERLAY", "GameFontHighlight")

                -- cellule “Objet” avec icône + bouton tooltip
                ff.itemFrame = CreateFrame("Frame", nil, r2); ff.itemFrame:SetHeight(UI.ROW_H)
                ff.icon  = ff.itemFrame:CreateTexture(nil, "ARTWORK"); ff.icon:SetSize(20,20); ff.icon:SetPoint("LEFT", ff.itemFrame, "LEFT", 0, 0)
                ff.btn   = CreateFrame("Button", nil, ff.itemFrame); ff.btn:SetPoint("LEFT", ff.icon, "RIGHT", 6, 0); ff.btn:SetSize(240, UI.ROW_H)
                ff.text  = ff.btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); ff.text:SetJustifyH("LEFT"); ff.text:SetPoint("LEFT", ff.btn, "LEFT", 0, 0)

                ff.btn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
                    if self._itemID and self._itemID > 0 then
                        GameTooltip:SetItemByID(self._itemID)
                    elseif self._link and self._link ~= "" then
                        GameTooltip:SetHyperlink(self._link)
                    else
                        GameTooltip:Hide()
                    end
                end)
                ff.btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
                -- pour LayoutRow
                ff.item = ff.itemFrame
                return ff
            end,
            updateRow = function(i2, r2, ff, item)
                local itemID = tonumber(item.itemID or 0) or 0
                local link   = (itemID > 0) and (select(2, GetItemInfo(itemID))) or item.itemLink
                local name   = (link and link:match("%[(.-)%]")) or (GetItemInfo(itemID)) or item.itemName or "Objet inconnu"
                local icon   = (itemID > 0) and (select(5, GetItemInfoInstant(itemID))) or "Interface\\ICONS\\INV_Misc_QuestionMark"

                ff.qty:SetText(tostring(item.qty or 1))
                ff.src:SetText(tostring(item.source or ""))
                ff.amt:SetText(UI.MoneyFromCopper(tonumber(item.copper) or 0))

                ff.text:SetText(name or "")
                ff.icon:SetTexture(icon or "Interface\\ICONS\\INV_Misc_QuestionMark")
                ff.btn._itemID = itemID
                ff.btn._link   = link
            end,
            topOffset = 0,
        })

        local rows = {}
        if CDZ.GetExpenseById then
            for _, eid in ipairs(lot.itemIds or {}) do
                local _, it = CDZ.GetExpenseById(eid)
                if it then table.insert(rows, it) end
            end
        end
        lv:SetData(rows)
        dlg:SetButtons({ { text="Fermer", default=true } })
        dlg:Show()
    end)

    local canDelete = (tonumber(lot.used or 0) or 0) == 0
    r.btnDelete:SetEnabled(canDelete)
    r.btnDelete:SetOnClick(function()
        if canDelete and CDZ.Lot_Delete then CDZ.Lot_Delete(lot.id) end
    end)
end

-- ====== Layout & Refresh ======
local function Layout()
    local pad = PAD
    local W, H = panel:GetWidth(), panel:GetHeight()
    local footerH = footer:GetHeight() + 6
    local availH = H - footerH - (pad*2)
    local topH   = math.floor(availH * 0.60)

    -- Top (Ressources libres)
    topPane:ClearAllPoints()
    topPane:SetPoint("TOPLEFT",  panel, "TOPLEFT",  pad, -pad)
    topPane:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -pad, -pad)
    topPane:SetHeight(topH)

    -- Bottom (Lots)
    bottomPane:ClearAllPoints()
    bottomPane:SetPoint("TOPLEFT",  topPane, "BOTTOMLEFT", 0, -6)
    bottomPane:SetPoint("TOPRIGHT", topPane, "BOTTOMRIGHT", 0, -6)
    bottomPane:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", pad, pad + footerH)
    bottomPane:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -pad, pad + footerH)

    if UI.AttachButtonsFooterRight then
        local buttons = {}
        local isGM = (CDZ.IsMaster and CDZ.IsMaster()) or false

        if isGM and btnCreateLot then table.insert(buttons, btnCreateLot) end

        if isGM then
            if btnToggle   then btnToggle:Show()   table.insert(buttons, btnToggle)   end
            if btnClearAll then btnClearAll:Show() table.insert(buttons, btnClearAll) end
        else
            if btnToggle   then btnToggle:Hide()   end
            if btnClearAll then btnClearAll:Hide() end
        end

        UI.AttachButtonsFooterRight(footer, buttons, 8, nil)
    end

    if lvFree and lvFree.Layout then lvFree:Layout() end
    if lvLots and lvLots.Layout then lvLots:Layout() end
end

local function Refresh()
    -- Ressources libres = dépenses sans lotId
    local e = (ChroniquesDuZephyrDB and ChroniquesDuZephyrDB.expenses) or { list = {} }
    local items, total = {}, 0
    for idx, it in ipairs(e.list or {}) do
        if (not it.lotId) or (it.lotId == 0) then
            total = total + (tonumber(it.copper) or 0)
            items[#items+1] = { _abs = idx, data = it }
        end
    end

    lvFree:SetData(items)
    totalFS:SetText("|cffffd200Ressources libres :|r " .. UI.MoneyFromCopper(total))

    -- Lots (masquer les épuisés + tri alphabétique)
    local lots = (CDZ.GetLots and CDZ.GetLots()) or {}

    -- Tri par nom (alpha, insensible à la casse), puis par id pour stabiliser
    table.sort(lots, function(a, b)
        local an = (a and a.name or ""):lower()
        local bn = (b and b.name or ""):lower()
        if an == bn then return (a and a.id or 0) < (b and b.id or 0) end
        return an < bn
    end)

    -- Filtrer : ne garder que les lots visibles (non-épuisés et non en attente locale)
    local rows = {}
    for _, l in ipairs(lots) do
        local pending = (l.__pendingConsume or l.__pendingDelete)
        if (not pending) and not (CDZ.Lot_Status and CDZ.Lot_Status(l) == "EPU") then
            rows[#rows+1] = { data = l }
        end
    end

    lvLots:SetData(rows)

    -- Boutons
    btnCreateLot:SetShown(CDZ.IsMaster and CDZ.IsMaster())
    btnClearAll:SetEnabled(true)
    local on = CDZ.IsExpensesRecording and CDZ.IsExpensesRecording()
    btnToggle:SetText(on and "Stopper l'enregistrement" or "Démarrer l'enregistrement des dépenses")

    Layout()
end

local function Build(container)
    panel = container
    if UI.ApplySafeContentBounds then UI.ApplySafeContentBounds(panel, { side = 10, bottom = 6 }) end

    footer   = UI.CreateFooter(panel, 36)
    topPane  = CreateFrame("Frame", nil, panel)
    bottomPane = CreateFrame("Frame", nil, panel)

    -- Titre + trait pour chaque liste
    UI.SectionHeader(topPane,    "Réserve d'objets")
    lvFree = UI.ListView(topPane, colsFree, { buildRow = BuildRowFree, updateRow = UpdateRowFree, topOffset = UI.SECTION_HEADER_H or 26 })

    UI.SectionHeader(bottomPane, "Lots utilisables pour les raids")
    lvLots = UI.ListView(bottomPane, colsLots, { buildRow = BuildRowLots, updateRow = UpdateRowLots, topOffset = UI.SECTION_HEADER_H or 26, bottomAnchor = footer })

    btnCreateLot = UI.Button(footer, "Créer un lot", { size="sm", minWidth=140, tooltip="Sélectionnez des ressources pour créer un lot (contenu figé)." })
    btnCreateLot:SetOnClick(function()
        if not (CDZ.IsMaster and CDZ.IsMaster()) then return end
        local idxs = {}
        for abs, v in pairs(selected) do if v then idxs[#idxs+1] = abs end end
        table.sort(idxs)
        if #idxs == 0 then
            UIErrorsFrame:AddMessage("|cffff6060[CDZ]|r Aucune ressource sélectionnée.", 1,0.4,0.4)
            return
        end
        local dlg = UI.CreatePopup({ title = "Créer un lot", width = 420, height = 220 })
        local nameLabel = dlg.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); nameLabel:SetText("Nom du lot :")
        local nameInput = CreateFrame("EditBox", nil, dlg.content, "InputBoxTemplate"); nameInput:SetSize(240, 28); nameInput:SetAutoFocus(true)

        -- 🗑️ (Ligne "Type :" supprimée)

        local nLabel   = dlg.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); nLabel:SetText("Nombre d'utilisations")
        local nInput   = CreateFrame("EditBox", nil, dlg.content, "InputBoxTemplate"); nInput:SetSize(80, 28); nInput:SetNumeric(true); nInput:SetNumber(1)

        -- ➕ léger espacement haut
        nameLabel:SetPoint("TOPLEFT", dlg.content, "TOPLEFT", 6, -14)
        nameInput:SetPoint("LEFT", nameLabel, "RIGHT", 8, 0)

        -- (typeLabel supprimé) : on accroche directement la ligne suivante
        nLabel:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 0, -14)
        nInput:SetPoint("LEFT", nLabel, "RIGHT", 8, 0)

        dlg:SetButtons({
            { text = "Créer", default = true, onClick = function()
                local nm = nameInput:GetText() or ""
                if nm == "" then nm = "Lot" end -- ➕ nom par défaut
                local N  = tonumber(nInput:GetNumber() or 1) or 1
                if N < 1 then N = 1 end
                local isMulti = (N > 1)
                if CDZ.Lot_Create then
                    CDZ.Lot_Create(nm, isMulti, N, idxs)
                    selected = {}
                    if ns.RefreshAll then ns.RefreshAll() end
                end
                end},
            { text = CANCEL, variant = "ghost" },
        })
        dlg:Show()
    end)

    btnToggle = UI.Button(footer, "Démarrer l'enregistrement des dépenses", { size="sm", minWidth=260 })
    btnToggle:SetOnClick(function()
        local on = CDZ.ExpensesToggle and CDZ.ExpensesToggle() or CDZ.ExpensesStart()
        btnToggle:SetText(on and "Stopper l'enregistrement" or "Démarrer l'enregistrement des dépenses")
        if ns and ns.RefreshAll then ns.RefreshAll() end
    end)

    btnClearAll = UI.Button(footer, "Tout vider (libres)", { size="sm", variant="danger", minWidth=160 })
    btnClearAll:SetConfirm("Vider la liste des ressources libres ? (les lots ne sont pas affectés)", function()
        if CDZ.ClearExpenses then CDZ.ClearExpenses() end
        if ns and ns.RefreshAll then ns.RefreshAll() end
    end)

    totalFS = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge"); totalFS:SetPoint("LEFT", footer, "LEFT", PAD, 0)
end

UI.RegisterTab("Ressources", Build, Refresh, Layout)
