local ADDON, ns = ...
local CDZ, UI = ns.CDZ, ns.UI
local PAD, SBW, GUT = UI.OUTER_PAD, UI.SCROLLBAR_W, UI.GUTTER

local panel, input, addBtn, lv, footer

local cols = UI.NormalizeColumns({
    { key="name",   title="Nom",    min=240, flex=1 },
    { key="solde",  title="Solde",  w=140 },
    { key="act",    title="Actions",w=300 },
})

local function money(v)
    v = tonumber(v) or 0
    return (UI and UI.MoneyText) and UI.MoneyText(v) or (tostring(v).." po")
end

local function BuildRow(r)
    local f = {}
    f.name  = UI.CreateNameTag(r)
    f.solde = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")

    f.act = CreateFrame("Frame", nil, r); f.act:SetHeight(UI.ROW_H); f.act:SetFrameLevel(r:GetFrameLevel()+1)
    r.btnDelete = UI.Button(f.act, "X", { size="sm", variant="danger", minWidth=28, padX=12 })
    r.btnCredit = UI.Button(f.act, "Dépôt d’or", { size="sm", minWidth=150 })
    r.btnDebit  = UI.Button(f.act, "Retrait d’or", { size="sm", variant="ghost", minWidth=150 })
    UI.AttachRowRight(f.act, { r.btnCredit, r.btnDebit, r.btnDelete }, 8, -4, { leftPad = 8, align = "center" })
    return f
end

local function UpdateRow(i, r, f, data)
    UI.SetNameTag(f.name, data.name or "")

    -- Solde : utilise data.solde si fourni, sinon calcule depuis credit/debit
    local solde = data.solde
    if solde == nil then
        local cr = tonumber(data.credit) or 0
        local db = tonumber(data.debit)  or 0
        solde = cr - db
    end
    f.solde:SetText(money(solde))

    local isMaster = CDZ.IsMaster and CDZ.IsMaster()
    local selfName = UnitName("player")
    local isSelf   = (data.name == selfName)

    -- Droits : non-GM ne peut agir que sur lui-même ; suppression réservée GM
    r.btnDelete:SetShown(isMaster)

    local canAct = isMaster or isSelf
    if r.btnCredit.SetEnabled then
        r.btnCredit:SetEnabled(canAct)
        r.btnDebit:SetEnabled(canAct)
    end

    r.btnCredit:SetScript("OnClick", function()
        if not canAct then
            UIErrorsFrame:AddMessage("|cffff6060[CDZ]|r Vous ne pouvez modifier que votre propre solde.", 1, 0.4, 0.4)
            return
        end
        UI.PopupPromptNumber("Ajouter de l’or à "..(data.name or ""), "Montant total (po) :", function(amt)
            amt = math.floor(tonumber(amt) or 0)
            if amt <= 0 then return end
            if isMaster then
                if CDZ.GM_AdjustAndBroadcast then CDZ.GM_AdjustAndBroadcast(data.name, amt) end
            else
                if CDZ.RequestAdjust then CDZ.RequestAdjust(data.name, amt) end
                UIErrorsFrame:AddMessage("|cffdadaff[CDZ]|r Demande envoyée au GM", 0.8, 0.8, 1)
            end
        end)
    end)

    r.btnDebit:SetScript("OnClick", function()
        if not canAct then
            UIErrorsFrame:AddMessage("|cffff6060[CDZ]|r Vous ne pouvez modifier que votre propre solde.", 1, 0.4, 0.4)
            return
        end
        UI.PopupPromptNumber("Retirer de l’or à "..(data.name or ""), "Montant total (po) :", function(amt)
            amt = math.floor(tonumber(amt) or 0)
            if amt <= 0 then return end
            local delta = -amt
            if isMaster then
                if CDZ.GM_AdjustAndBroadcast then CDZ.GM_AdjustAndBroadcast(data.name, delta) end
            else
                if CDZ.RequestAdjust then CDZ.RequestAdjust(data.name, delta) end
                UIErrorsFrame:AddMessage("|cffdadaff[CDZ]|r Demande envoyée au GM", 0.8, 0.8, 1)
            end
        end)
    end)

    r.btnDelete:SetScript("OnClick", function()
        if not isMaster then
            UIErrorsFrame:AddMessage("|cffff6060[CDZ]|r Suppression du roster réservée au GM.", 1, 0.4, 0.4)
            return
        end
        UI.PopupConfirm("Supprimer "..(data.name or "").." de la liste ?", function()
            if CDZ.RemovePlayer then CDZ.RemovePlayer(data.name) end
            -- La version RemovePlayer côté Core diffuse déjà si patch appliqué ; sinon :
            if CDZ.BroadcastRosterRemove then CDZ.BroadcastRosterRemove(data.name) end
            if ns.RefreshAll then ns.RefreshAll() end
        end)
    end)
end

local function Layout()
    -- Footer : input + bouton
    input:ClearAllPoints()
    input:SetPoint("LEFT", footer, "LEFT", PAD, 0)
    addBtn:ClearAllPoints()
    addBtn:SetPoint("LEFT", input, "RIGHT", 8, 0)
    if lv and lv.Layout then lv:Layout() end
end

local function Refresh()
    local players = CDZ.GetPlayersArray and CDZ.GetPlayersArray() or {}
    -- Attendu : { {name=, credit=, debit=, solde=?}, ... }
    lv:SetData(players)
    Layout()
end

local function Build(container)
    panel = container
    if UI.ApplySafeContentBounds then UI.ApplySafeContentBounds(panel, { side = 10, bottom = 6 }) end

    footer = UI.CreateFooter(panel, 36)
    input = CreateFrame("EditBox", nil, footer, "InputBoxTemplate")
    input:SetAutoFocus(false); input:SetHeight(28); input:SetWidth(320)

    addBtn = UI.Button(footer, "+ Ajouter", { size="sm", variant="primary", minWidth=120 })
    addBtn:SetOnClick(function()
        local name = (input:GetText() or ""):gsub("^%s+",""):gsub("%s+$","")
        if name == "" then return end
        if not (CDZ.IsMaster and CDZ.IsMaster()) then
            UIErrorsFrame:AddMessage("|cffff6060[CDZ]|r Ajout au roster réservé au GM.", 1, 0.4, 0.4)
            return
        end
        if CDZ.AddPlayer and CDZ.AddPlayer(name) then
            input:SetText("")
            if ns.RefreshAll then ns.RefreshAll() end
        end
    end)

    -- Bouton footer (droite) : popup d’ajout depuis la guilde
    local btnGuild = UI.Button(footer, "Ajouter membre de la guilde", { size="sm", minWidth=220 })
    btnGuild:SetOnClick(function()
        if not (CDZ.IsMaster and CDZ.IsMaster()) then
            UIErrorsFrame:AddMessage("|cffff6060[CDZ]|r Ajout au roster réservé au GM.", 1, 0.4, 0.4)
            return
        end
        if UI.ShowGuildRosterPopup then UI.ShowGuildRosterPopup() end
    end)
    if UI.AttachButtonsFooterRight then
        UI.AttachButtonsFooterRight(footer, { btnGuild })
    else
        btnGuild:ClearAllPoints()
        btnGuild:SetPoint("RIGHT", footer, "RIGHT", 0, 0)
    end

    -- Masquer le bouton + désactiver l’input pour les non-GM
    if not (CDZ.IsMaster and CDZ.IsMaster()) then
        addBtn:Hide()
        if input.Disable then input:Disable() else input:ClearFocus(); input:EnableMouse(false) end
    end

    lv = UI.ListView(panel, cols, { buildRow = BuildRow, updateRow = UpdateRow, topOffset = 0, bottomAnchor = footer })
end

UI.RegisterTab("Roster", Build, Refresh, Layout)
