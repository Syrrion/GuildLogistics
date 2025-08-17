local ADDON, ns = ...
local CDZ, UI, F = ns.CDZ, ns.UI, ns.Format
local PAD, SBW, GUT = UI.OUTER_PAD, UI.SCROLLBAR_W, UI.GUTTER

local panel, lv, footer, backBtn
local cols = UI.NormalizeColumns({
    { key="date",  title="Date",         w=140 },
    { key="total", title="Total",        w=140 },
    { key="per",   title="Individuel",   w=160 },
    { key="count", title="Participants", w=160 },
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
    f.count = UI.Label(r)
    f.state = UI.Label(r)
    f.act = CreateFrame("Frame", nil, r); f.act:SetHeight(UI.ROW_H); f.act:SetFrameLevel(r:GetFrameLevel()+1)
    r.btnPlayers = UI.Button(f.act, "Joueurs", { size="sm", minWidth=90 })
    r.btnRefund  = UI.Button(f.act, "Rendre gratuit", { size="sm", variant="ghost", minWidth=140 })
    r.btnDelete  = UI.Button(f.act, "X", { size="sm", variant="danger", minWidth=26, padX=12 })

    -- Centré dans la cellule, avec marge interne à gauche, et un offset un peu plus fort à droite
    UI.AttachRowRight(f.act, { r.btnDelete, r.btnRefund, r.btnPlayers }, 8, -6, { leftPad = 10, align = "center" })

    return f
end

local function UpdateRow(i, r, f, s)
    local names = s.participants or {}
    local cnt   = (#names > 0 and #names) or (tonumber(s.count) or 0)

    f.date:SetText(F.DateTime(s.ts or s.date))
    f.total:SetText(UI.MoneyText(s.total or ((tonumber(s.perHead) or 0) * cnt)))
    f.per:SetText(UI.MoneyText(s.perHead))
    f.count:SetText(cnt)
    f.state:SetText(s.refunded and "|cff40ff40Remboursé|r" or "|cffffd200Clôturé|r")

    f.count:EnableMouse(true)
    f.count:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Participants ("..tostring(cnt)..")")
        local pdb = (ChroniquesDuZephyrDB and ChroniquesDuZephyrDB.players) or {}
        for _, n in ipairs(names) do
            local class, r, g, b, coords = nil, 1, 1, 1, nil
            if ns.CDZ and ns.CDZ.GetNameStyle then class, r, g, b, coords = ns.CDZ.GetNameStyle(n) end
            local icon = (class and UI.ClassIconMarkup and UI.ClassIconMarkup(class, 14)) or ""
            if pdb[n] then
                GameTooltip:AddLine(icon.." "..n, r or 1, g or 1, b or 1)
            else
                GameTooltip:AddLine(n.." (supprimé)", 1, 0.44, 0.44)
            end
        end
        GameTooltip:Show()
    end)
    f.count:SetScript("OnLeave", function() GameTooltip:Hide() end)

    r.btnPlayers:SetScript("OnClick", function()
        if ns and ns.UI and ns.UI.ShowParticipantsPopup then
            ns.UI.ShowParticipantsPopup(names)
        else
            ShowParticipants(names) -- fallback legacy
        end
    end)


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