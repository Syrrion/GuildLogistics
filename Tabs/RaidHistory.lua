local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI, F = ns.GLOG, ns.UI, ns.Format
local PAD, SBW, GUT = UI.OUTER_PAD, UI.SCROLLBAR_W, UI.GUTTER

local panel, lv, footer, histPane
local cols = UI.NormalizeColumns({
    { key="date",  title=Tr("col_date"),         w=140 },
    { key="total", title=Tr("col_total"),        vsep=true,  w=100 },
    { key="per",   title=Tr("col_invidual"),   vsep=true,  w=100 },
    { key="count", title=Tr("col_participants"), vsep=true,  w=100 },
    { key="state", title=Tr("col_state"),         vsep=true,  min=180, flex=1 },
    { key="act",   title="",      vsep=true,  w=300 },
})

local function histNow()
    return (GLOG.GetHistory and GLOG.GetHistory()) or ((GuildLogisticsDB and GuildLogisticsDB.history) or {})
end

local function ShowParticipants(names)
    if UI and UI.ShowParticipantsPopup then
        UI.ShowParticipantsPopup(names)
    end
end

local function BuildRow(r)
    local f = {}
    f.date  = UI.Label(r)
    f.total = UI.Label(r)
    f.per   = UI.Label(r)
    -- Colonne "count" = conteneur + bouton centré
    f.count = CreateFrame("Frame", nil, r)
    f.count:SetHeight(UI.ROW_H)

    f.countBtn = UI.Button(f.count, "0", { size="sm", minWidth=40 })
    f.countBtn:ClearAllPoints()
    f.countBtn:SetPoint("CENTER", f.count, "CENTER", 0, 0)


    f.state = UI.Label(r)
    f.act = CreateFrame("Frame", nil, r); f.act:SetHeight(UI.ROW_H); f.act:SetFrameLevel(r:GetFrameLevel()+1)
    r.btnLots   = UI.Button(f.act, Tr("lbl_bundles"), { size="sm", minWidth=80 })

    -- Boutons réservés GM
    r.btnRefund = UI.Button(f.act, Tr("btn_make_free"), { size="sm", variant="ghost", minWidth=140 })
    r.btnDelete = UI.Button(f.act, "X", { size="sm", variant="danger", minWidth=26, padX=12 })
    local isGM = (GLOG.CanModifyGuildData and GLOG.CanModifyGuildData()) or false
    r.btnRefund:SetShown(isGM)
    r.btnDelete:SetShown(isGM)

    -- Réorganisation : Lots toujours visible, autres seulement si GM
    UI.AttachRowRight(f.act, isGM and { r.btnDelete, r.btnRefund, r.btnLots } or { r.btnLots }, 8, -6, { leftPad = 10, align = "center" })

    return f
end

local function UpdateRow(i, r, f, s)
    local names = s.participants or {}
    local cnt   = (#names > 0 and #names) or (tonumber(s.count) or 0)

    f.date:SetText(F.DateTime(s.ts or s.date))
    f.total:SetText(UI.MoneyText(s.total or ((tonumber(s.perHead) or 0) * cnt)))
    f.per:SetText(UI.MoneyText(s.perHead))
    f.countBtn:SetText(tostring(cnt))
    f.countBtn:SetWidth( math.max(30, f.countBtn:GetFontString():GetStringWidth() + 16) )
    f.countBtn:SetOnClick(function()
        if ns and ns.UI and ns.UI.ShowParticipantsPopup then
            ns.UI.ShowParticipantsPopup(names)
        else
            ShowParticipants(names)
        end
    end)

    f.state:SetText(s.refunded and "|cff40ff40"..Tr("lbl_refunded").."|r" or "|cffffd200"..Tr("lbl_closed").."|r")

    r.btnRefund:SetEnabled(true)
    r.btnRefund:SetText(s.refunded and Tr("btn_remove_free") or Tr("btn_make_free"))
    do
        local idx = i  -- capture de l’index CORRECT
        r.btnRefund:SetScript("OnClick", function()
            local h = histNow()
            local curr = h[idx]
            local isUnrefund = curr and curr.refunded or false
            local msg = isUnrefund
                and Tr("confirm_cancel_free_session")
                or  Tr("confirm_make_free_session")
            UI.PopupConfirm(msg, function()
                local ok = isUnrefund and GLOG.UnrefundSession(idx) or GLOG.RefundSession(idx)
                if ok and ns.RefreshAll then ns.RefreshAll() end
            end)
        end)
    end

    r.btnDelete:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(Tr("tooltip_remove_history1"))
    GameTooltip:AddLine(Tr("tooltip_remove_history2"), 1,1,1, true)
    GameTooltip:AddLine(Tr("tooltip_remove_history3"), 1,1,1, true)
    GameTooltip:AddLine(Tr("tooltip_remove_history4"), 1,1,1, true)
    GameTooltip:Show()
end)
r.btnDelete:SetScript("OnLeave", function() GameTooltip:Hide() end)

    do
        local idx = i
        r.btnDelete:SetScript("OnClick", function()
            UI.PopupConfirm(Tr("confirm_delete_history_line_permanent"), function()
                if GLOG.DeleteHistory and GLOG.DeleteHistory(idx) and ns.RefreshAll then ns.RefreshAll() end
            end)
        end)

        r.btnLots:SetOnClick(function()
            local lots = s.lots or {}
            if #lots == 0 then
                UI.PopupText(Tr("lbl_used_bundles"), Tr("hint_no_bundle_for_raid"))
                return
            end

            -- Résumé pour CETTE sortie : #lots & Σ charges utilisées (1 charge par lot et par raid)
            local nbLots, usedCharges = #lots, 0
            for _ , _ in ipairs(lots) do
                usedCharges = usedCharges + 1
            end

            local dlg = UI.CreatePopup({ 
                title  = Tr("lbl_used_bundles"), 
                width  = 600, 
                height = 460 
            })

            -- Ajoute la ligne de précision sous le titre
            if dlg.title then
                local fs = dlg:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                fs:SetText(string.format("%s : %d   •   %s : %d", Tr("lbl_used_bundles"), nbLots, Tr("lbl_used_charges"), usedCharges))
                fs:SetPoint("TOP", dlg.title, "BOTTOM", 0, -4)
            end

            local cols = UI.NormalizeColumns({
                { key="lot",  title=Tr("col_bundle"),    min=120 },
                { key="qty",  title=Tr("col_qty_short"),    vsep=true,  w=60, justify="RIGHT" },
                { key="item", title=Tr("col_item"),  vsep=true,  min=140, flex=1 },
                { key="amt",  title=Tr("col_value"), vsep=true,  w=120, justify="RIGHT" },
            })

            local lv = UI.ListView(dlg.content, cols, {
                buildRow = function(r2)
                    local f2 = {}
                    f2.lot  = r2:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                    f2.qty  = r2:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                    f2.amt  = r2:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                    f2.item = UI.CreateItemCell(r2, { size = 20, width = 240 })
                    return f2
                end,
                updateRow = function(i2, r2, f2, row)
                    local lot  = row.lot
                    local exp  = row.item

                    f2.lot:SetText(lot.name or (Tr("lbl_lot")..tostring(lot.id)))

                    -- ✅ Qté/Valeur AU PRORATA des charges utilisées pour CE raid
                    local qtyText = row.qtyText
                    local amtText = row.amtText
                    if not qtyText then
                        local q = tonumber(row.qtyP or (exp and exp.qty)) or 0
                        if math.abs(q - math.floor(q)) < 0.001 then
                            qtyText = tostring(math.floor(q + 0.0001))
                        else
                            qtyText = string.format("%.1f", q)
                        end
                    end
                    f2.qty:SetText(qtyText or "")
                    f2.amt:SetText(amtText or UI.MoneyFromCopper(math.floor(tonumber(row.amtP or (exp and exp.copper) or 0))))

                    if exp then
                        UI.SetItemCell(f2.item, exp)
                    else
                        -- Ligne synthétique (lot "or uniquement" ou lot sans dépenses listées)
                        f2.item.icon:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
                        f2.item.text:SetText(Tr("lbl_bundle_gold_only"))
                        f2.item.btn._itemID = nil
                        f2.item.btn._link   = nil
                    end
                end,
            })

            -- Reconstruit les lignes depuis la DB
            local rows = {}
            local dbLots = (GuildLogisticsDB and GuildLogisticsDB.lots and GuildLogisticsDB.lots.list) or {}
            local dbExp  = (GuildLogisticsDB and GuildLogisticsDB.expenses and GuildLogisticsDB.expenses.list) or {}

            for _, lotRef in ipairs(lots) do
                -- On retrouve le lot complet en DB
                local lot
                for _, l in ipairs(dbLots) do
                    if l.id == lotRef.id then lot = l break end
                end

                if lot then
                    local addedAny = false
                    -- Cherche toutes les dépenses liées à ce lot
                    for _, e in ipairs(dbExp) do
                        if e.lotId == lot.id then
                            -- ✅ PRORATA : 1 charge utilisée pour ce raid / charges max du lot
                            local N = tonumber(lot.sessions or 1) or 1
                            if N <= 0 then N = 1 end
                            local frac = 1 / N

                            local baseQty    = tonumber(e.qty or 0) or 0
                            local baseCopper = tonumber(e.copper or 0) or 0
                            local qtyP = baseQty * frac
                            local amtP = math.floor(baseCopper * frac + 0.5)

                            local qtyText
                            if math.abs(qtyP - math.floor(qtyP)) < 0.001 then
                                qtyText = tostring(math.floor(qtyP + 0.0001))
                            else
                                qtyText = string.format("%.1f", qtyP)
                            end
                            local amtText = UI.MoneyFromCopper(amtP)

                            table.insert(rows, { lot = lot, item = e, qtyP = qtyP, amtP = amtP, qtyText = qtyText, amtText = amtText })
                            addedAny = true
                        end
                    end

                    -- ⚠️ Aucun "expense" lié : ligne synthétique (ex. lot en or)
                    if not addedAny then
                        local N = tonumber(lot.sessions or 1) or 1
                        if N <= 0 then N = 1 end
                        local frac = 1 / N

                        local totalCopper = tonumber(lot.totalCopper or 0) or 0
                        local amtP = math.floor(totalCopper * frac + 0.5)

                        table.insert(rows, {
                            lot     = lot,
                            item    = nil,         -- ➜ ligne synthétique
                            qtyP    = nil,
                            amtP    = amtP,
                            qtyText = "",          -- vide (pas de quantité)
                            amtText = UI.MoneyFromCopper(amtP),
                            _synthetic = true,
                        })
                    end
                end
            end

            lv:SetData(rows)
            dlg._lv = lv
            dlg:SetButtons({ { text = CLOSE, default = true } })
            dlg:Show()
        end)
    end
end

local function Layout()
    if lv and lv.Layout then lv:Layout() end
end

local function Refresh()
    if lv then lv:SetData(histNow()) end
end

-- Gestion des événements : rafraîchir la liste si l’onglet est visible
if ns and ns.On then
    ns.On("history:changed", function()
        if panel and panel:IsShown() then
            Refresh()
        end
    end)
end

local function Build(container)
    -- Création du conteneur
    panel, footer, footerH = UI.CreateMainContainer(container, {footer = false})

    -- 📦 Conteneur interne paddé (comme Synthese/Guilde)
    histPane = CreateFrame("Frame", nil, panel)
    histPane:ClearAllPoints()
    histPane:SetPoint("TOPLEFT",     panel, "TOPLEFT",     UI.OUTER_PAD, -UI.OUTER_PAD)
    histPane:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -UI.OUTER_PAD,  UI.OUTER_PAD)

    -- 🧩 En-tête de section (même pattern visuel que "Roster actif")
    -- On réutilise la clé d’onglet pour le titre pour éviter d’ajouter une locale dédiée.
    UI.SectionHeader(histPane, Tr("tab_history"), { topPad = 2 })

    -- 📋 ListView plein écran dans le conteneur, ancrée sur le footer global
    lv = UI.ListView(histPane, cols, {
        buildRow    = BuildRow,
        updateRow   = UpdateRow,
        topOffset   = (UI.SECTION_HEADER_H or 26) + 6, -- espace sous le header de section
        bottomAnchor= footer,                           -- occupe tout jusqu’au footer
    })
end

UI.RegisterTab(Tr("tab_history"), Build, Refresh, Layout, {
    category = Tr("cat_raids"),
})
