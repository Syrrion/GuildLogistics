local ADDON, ns = ...
local CDZ, UI, F = ns.CDZ, ns.UI, ns.Format
local PAD, SBW, GUT = UI.OUTER_PAD, UI.SCROLLBAR_W, UI.GUTTER

local panel, lv, btnToggle, totalFS, btnClearAll, footer

local cols = UI.NormalizeColumns({
    { key="date",   title="Date",    w=200 },
    { key="qty",    title="Qté",     w=60  },
    { key="item",   title="Objet",   min=260, flex=1 },
    { key="source", title="Source",  w=120 },
    { key="amount", title="Montant", w=160 },
    { key="act",    title="Actions", w=120 },
})

local function resolveItemName(it)
    if it.itemLink and it.itemLink ~= "" then
        local name = GetItemInfo(it.itemLink)
        if name and name ~= "" then return name end
        local bracket = it.itemLink:match("%[(.-)%]")
        if bracket and bracket ~= "" then return bracket end
    end
    if it.itemName and it.itemName ~= "" then return it.itemName end
    return ""
end

local function resolveItemIcon(it)
    if it.itemLink and it.itemLink ~= "" then
        if GetItemIcon then
            local tex = GetItemIcon(it.itemLink); if tex then return tex end
        end
        if GetItemInfoInstant then
            local _,_,_,_,iconFileID = GetItemInfoInstant(it.itemLink)
            if iconFileID then return iconFileID end
        end
    end
    return nil
end

local function BuildRow(r)
    local f = {}
    f.date   = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.qty    = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.source = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.amount = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")

    f.item     = CreateFrame("Button", nil, r); f.item:SetHeight(UI.ROW_H)
    f.itemText = f.item:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.icon     = f.item:CreateTexture(nil, "ARTWORK"); f.icon:SetSize(16, 16)
    f.icon:SetPoint("LEFT", f.item, "LEFT", 0, 0)
    f.itemText:ClearAllPoints()
    f.itemText:SetPoint("LEFT",  f.icon, "RIGHT", 3, 0) -- même padding que le NameTag
    f.itemText:SetPoint("RIGHT", f.item, "RIGHT", 0, 0)
    f.itemText:SetJustifyH("LEFT")
    if f.itemText.SetWordWrap then f.itemText:SetWordWrap(false) end

    f.item:SetScript("OnEnter", function(self)
        if self._link and GameTooltip then GameTooltip:SetOwner(self, "ANCHOR_CURSOR"); GameTooltip:SetHyperlink(self._link); GameTooltip:Show() end
    end)
    f.item:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    f.item:SetScript("OnMouseUp", function(self)
        if self._link and IsModifiedClick("CHATLINK") and ChatEdit_InsertLink then ChatEdit_InsertLink(self._link) end
    end)

    f.act = CreateFrame("Frame", nil, r); f.act:SetHeight(UI.ROW_H); f.act:SetFrameLevel(r:GetFrameLevel()+1)
    r.btnDelete = UI.Button(f.act, "Supprimer", { size="sm", variant="danger", minWidth=110 })
    UI.AttachRowRight(f.act, { r.btnDelete }, 8, -4, { leftPad = 8, align = "center" })
    return f
end

local function UpdateRow(i, r, f, it)
    local d = it.data or it
    r._dataIndex = it._dbi or i

    local nameToShow = resolveItemName(d)
    f.date:SetText(F.DateTime(d.ts))
    f.item._link = d.itemLink
    f.itemText:SetText(nameToShow ~= "" and nameToShow or (d.itemName or ""))
    f.qty:SetText(tonumber(d.qty) or 1)
    f.source:SetText(d.source or "")
    f.amount:SetText(UI.MoneyFromCopper(d.copper or 0))
    local icon = resolveItemIcon(d)
    if icon then f.icon:SetTexture(icon); f.icon:Show() else f.icon:SetTexture(nil); f.icon:Hide() end

    r.btnDelete:SetScript("OnClick", function()
        local idx = r._dataIndex
        UI.PopupConfirm("Supprimer cette ligne de dépense ?", function()
            CDZ.DeleteExpense(idx)
            if ns and ns.RefreshAll then ns.RefreshAll() end
        end)
    end)
end

local function Layout()
    UI.AttachButtonsFooterRight(footer, { btnToggle, btnClearAll })
    totalFS:ClearAllPoints()
    totalFS:SetPoint("LEFT", footer, "LEFT", PAD, 0)
    totalFS:SetWidth(600)

    lv:Layout()
end

local function Refresh()
    local data, total = CDZ.GetExpenses()
    local items = {}
    for i = #data, 1, -1 do
        items[#items+1] = { _dbi = i, data = data[i] }
    end
    lv:SetData(items)

    totalFS:SetText("|cffffd200Total des dépenses enregistrées :|r " .. UI.MoneyFromCopper(total))
    btnToggle:SetText(CDZ.IsExpensesRecording() and "Stopper l'enregistrement" or "Démarrer l'enregistrement des dépenses")

    Layout()
end


local function Build(container)
    panel = container
    if UI.ApplySafeContentBounds then UI.ApplySafeContentBounds(panel, { side = 10, bottom = 6 }) end
    
    footer = UI.CreateFooter(panel, 36)

    lv = UI.ListView(panel, cols, { buildRow = BuildRow, updateRow = UpdateRow, topOffset = 0, bottomAnchor = footer })

    btnToggle = UI.Button(footer, "Démarrer l'enregistrement des dépenses", { size="sm", minWidth=260 })
    btnToggle:SetOnClick(function()
        local on = CDZ.ExpensesToggle()
        btnToggle:SetText(on and "Stopper l'enregistrement" or "Démarrer l'enregistrement des dépenses")
        if ns and ns.RefreshAll then ns.RefreshAll() end
    end)

    btnClearAll = UI.Button(footer, "Tout vider", { size="sm", variant="danger", minWidth=140 })
    btnClearAll:SetConfirm("Vider complètement la liste des dépenses ?", function()
        CDZ.ClearExpenses()
        if ns and ns.RefreshAll then ns.RefreshAll() end
    end)

    totalFS = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
end

UI.RegisterTab("Ressources", Build, Refresh, Layout)
