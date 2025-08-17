local ADDON, ns = ...
local CDZ, UI, F = ns.CDZ, ns.UI, ns.Format
local PAD, SBW, GUT = UI.OUTER_PAD, UI.SCROLLBAR_W, UI.GUTTER

local panel, lv, footer, backBtn
local cols = UI.NormalizeColumns({
    { key="date",  title="Date",         w=140 },
    { key="total", title="Total",        w=100 },
    { key="per",   title="Individuel",   w=100 },
    { key="count", title="Participants", w=100 },
    { key="state", title="État",         min=180, flex=1 },
    { key="act",   title="Actions",      w=300 },
})

local function histNow()
    return (CDZ.GetHistory and CDZ.GetHistory()) or ((ChroniquesDuZephyrDB and ChroniquesDuZephyrDB.history) or {})
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
    r.btnLots   = UI.Button(f.act, "Lots", { size="sm", minWidth=80 })
    r.btnRefund = UI.Button(f.act, "Rendre gratuit", { size="sm", variant="ghost", minWidth=140 })
    r.btnDelete = UI.Button(f.act, "X", { size="sm", variant="danger", minWidth=26, padX=12 })

    -- Réorganisation : Lots / Refund / Delete
    UI.AttachRowRight(f.act, { r.btnDelete, r.btnRefund, r.btnLots }, 8, -6, { leftPad = 10, align = "center" })


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

    f.state:SetText(s.refunded and "|cff40ff40Remboursé|r" or "|cffffd200Clôturé|r")

    r.btnRefund:SetEnabled(true)
    r.btnRefund:SetText(s.refunded and "Annuler gratuité" or "Rendre gratuit")
    do
        local idx = i  -- capture de l’index CORRECT
        r.btnRefund:SetScript("OnClick", function()
            local h = histNow()
            local curr = h[idx]
            local isUnrefund = curr and curr.refunded or false
            local msg = isUnrefund
                and "Annuler la gratuité et revenir à l’état initial ?"
                or  "Rendre cette session gratuite pour tous les participants ?"
            UI.PopupConfirm(msg, function()
                local ok = isUnrefund and CDZ.UnrefundSession(idx) or CDZ.RefundSession(idx)
                if ok and ns.RefreshAll then ns.RefreshAll() end
            end)
        end)
    end

    r.btnDelete:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Supprimer cette ligne d’historique")
    GameTooltip:AddLine("• Suppression sans ajuster les soldes.", 1,1,1, true)
    GameTooltip:AddLine("• Si REMBOURSÉE : aucun débit ne sera recrédité.", 1,1,1, true)
    GameTooltip:AddLine("• Si CLÔTURÉE : aucun remboursement ne sera effectué.", 1,1,1, true)
    GameTooltip:Show()
end)
r.btnDelete:SetScript("OnLeave", function() GameTooltip:Hide() end)

    do
        local idx = i
        r.btnDelete:SetScript("OnClick", function()
            UI.PopupConfirm("Supprimer définitivement cette ligne d’historique ?", function()
                if CDZ.DeleteHistory and CDZ.DeleteHistory(idx) and ns.RefreshAll then ns.RefreshAll() end
            end)
        end)

        r.btnLots:SetOnClick(function()
            local lots = s.lots or {}
            if #lots == 0 then
                UI.PopupText("Lots utilisés", "Aucun lot n’a été associé à ce raid.")
                return
            end

            -- Calcule les charges utilisées et max
            local used, maxSessions = 0, 0
            for _, lot in ipairs(lots) do
                local l = CDZ.Lot_GetById and CDZ.Lot_GetById(lot.id)
                if l then
                    used       = used + (tonumber(l.used or 0) or 0)
                    maxSessions= maxSessions + (tonumber(l.sessions or 1) or 1)
                end
            end

            local dlg = UI.CreatePopup({ 
                title  = "Lots utilisés", 
                width  = 600, 
                height = 460 
            })

            -- Ajoute la ligne de précision sous le titre
            if dlg.title then
                local fs = dlg:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                fs:SetText(string.format("Charges utilisées : %d / %d", used, maxSessions))
                fs:SetPoint("TOP", dlg.title, "BOTTOM", 0, -4)
            end

            local cols = UI.NormalizeColumns({
                { key="lot",  title="Lot",    min=120 },
                { key="qty",  title="Qté",    w=60, justify="RIGHT" },
                { key="item", title="Objet",  min=140, flex=1 },
                { key="amt",  title="Valeur", w=120, justify="RIGHT" },
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

                    f2.lot:SetText(lot.name or ("Lot "..tostring(lot.id)))

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

                    UI.SetItemCell(f2.item, exp)
                end,
            })

            -- Reconstruit les lignes depuis la DB
            local rows = {}
            local dbLots = (ChroniquesDuZephyrDB and ChroniquesDuZephyrDB.lots and ChroniquesDuZephyrDB.lots.list) or {}
            local dbExp  = (ChroniquesDuZephyrDB and ChroniquesDuZephyrDB.expenses and ChroniquesDuZephyrDB.expenses.list) or {}

            for _, lotRef in ipairs(lots) do
                -- On retrouve le lot complet en DB
                local lot
                for _, l in ipairs(dbLots) do
                    if l.id == lotRef.id then lot = l break end
                end

                if lot then
                    -- Cherche toutes les dépenses liées à ce lot
                    for _, e in ipairs(dbExp) do
                        if e.lotId == lot.id then
                            -- ✅ PRORATA : (n charges utilisées pour CE raid) / (N charges max du lot)
                            local N = tonumber(lotRef.N or lot.sessions or 1) or 1
                            if N <= 0 then N = 1 end
                            local nUsed = tonumber(lotRef.n or 1) or 1
                            if nUsed < 0 then nUsed = 0 end
                            if nUsed > N then nUsed = N end
                            local frac       = nUsed / N

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
                        end
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
    panel = container
    if UI.ApplySafeContentBounds then UI.ApplySafeContentBounds(panel, { side = 10, bottom = 6 }) end

    footer = UI.CreateFooter(panel, 36)
    backBtn = UI.Button(footer, "< Retour", { size="sm", minWidth=110 })
    backBtn:SetOnClick(function() if UI and UI.ShowTabByLabel then UI.ShowTabByLabel("Roster") end end)
    backBtn:ClearAllPoints()
    backBtn:SetPoint("LEFT", footer, "LEFT", PAD, 0)

    lv = UI.ListView(panel, cols, { buildRow = BuildRow, updateRow = UpdateRow, bottomAnchor = footer })
end

-- Masqué de la barre d’onglets
UI.RegisterTab("Historique", Build, Refresh, Layout, { hidden = true })