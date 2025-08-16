local ADDON, ns = ...
local CDZ, UI = ns.CDZ, ns.UI
local PAD, SBW, GUT = UI.OUTER_PAD, UI.SCROLLBAR_W, UI.GUTTER

local panel, addBtn, lv, footer

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
    -- Affiche désormais le nom complet (Nom-Royaume)
    UI.SetNameTag(f.name, data.name or "")

    -- ✅ Autorisations : GM partout ; sinon uniquement sa propre ligne (comparaison Nom-Royaume)
    local isGM   = (ns and ns.Util and ns.Util.IsGM and ns.Util.IsGM()) or (ns and ns.CDZ and ns.CDZ.IsGM and ns.CDZ.IsGM()) or false

    -- Nom complet normalisé du joueur local (ex: Syrrions-KirinTor)
    local meFull = (ns and ns.Util and ns.Util.playerFullName and ns.Util.playerFullName())
    if (not meFull or meFull == "") and UnitFullName then
        local n, r = UnitFullName("player")
        local rn   = (GetNormalizedRealmName and GetNormalizedRealmName()) or r
        meFull     = (n and rn and rn ~= "") and (n.."-"..rn) or (n or UnitName("player"))
    end

    local isSelf = false
    if ns and ns.Util and ns.Util.SamePlayer then
        isSelf = ns.Util.SamePlayer(data.name, meFull)
    else
        -- Fallback : compare les noms complets (insensible à la casse)
        local a = tostring(data.name or "")
        local b = tostring(meFull or "")
        isSelf = string.lower(a) == string.lower(b)
    end
    local canClick = isGM or isSelf

    -- Active/désactive proprement les deux boutons (noms possibles selon ta factory)
    local withdraw = f.btnWithdraw or f.withdraw
    local deposit  = f.btnDeposit  or f.deposit
    if withdraw then
        withdraw:EnableMouse(true)
        if canClick then withdraw:Enable() else withdraw:Disable() end
        withdraw:SetAlpha(canClick and 1 or 0.5)
    end
    if deposit then
        deposit:EnableMouse(true)
        if canClick then deposit:Enable() else deposit:Disable() end
        deposit:SetAlpha(canClick and 1 or 0.5)
    end


    -- Solde : utilise data.solde si fourni, sinon calcule depuis credit/debit
    local solde = data.solde
    if solde == nil then
        local cr = tonumber(data.credit) or 0
        local db = tonumber(data.debit)  or 0
        solde = cr - db
    end
    f.solde:SetText(money(solde))

    local isMaster = CDZ.IsMaster and CDZ.IsMaster()

    -- Compare sur Nom-Royaume normalisé
    local selfFull = (ns and ns.Util and ns.Util.playerFullName and ns.Util.playerFullName())
    if (not selfFull or selfFull == "") and UnitFullName then
        local n, r = UnitFullName("player")
        local rn   = (GetNormalizedRealmName and GetNormalizedRealmName()) or r
        selfFull   = (n and rn and rn ~= "") and (n.."-"..rn) or (n or UnitName("player"))
    end
    local isSelf = string.lower(tostring(data.name or "")) == string.lower(tostring(selfFull or ""))

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
            UIErrorsFrame:AddMessage("|cffff6060[CDZ]|r Suppression d'un membre du roster réservée au GM.", 1, 0.4, 0.4)
            return
        end
        UI.PopupConfirm("Supprimer "..(data.name or "").." du roster ?", function()
            if CDZ.RemovePlayer then
                CDZ.RemovePlayer(data.name)  -- diffuse déjà ROSTER_REMOVE avec uid+name
            elseif CDZ.BroadcastRosterRemove then
                local uid = (CDZ.GetUID and CDZ.GetUID(data.name)) or nil
                CDZ.BroadcastRosterRemove(uid or data.name)
            end
            if ns.RefreshAll then ns.RefreshAll() end
        end)
    end)
end

local function Layout()
    -- Footer : tous les boutons sont gérés par AttachButtonsFooterRight
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

    -- Bouton Ajouter un joueur
    addBtn = UI.Button(footer, "Ajouter un joueur", { size="sm", variant="primary", minWidth=120 })
    addBtn:SetOnClick(function()
        if not (CDZ.IsMaster and CDZ.IsMaster()) then
            UIErrorsFrame:AddMessage("|cffff6060[CDZ]|r Ajout au roster réservé au GM.", 1, 0.4, 0.4)
            return
        end
        UI.PopupPromptText("Ajouter un joueur", "Nom du joueur externe à inclure dans le roster", function(name)
            name = tostring(name or ""):gsub("^%s+",""):gsub("%s+$","")
            if name == "" then return end
            if CDZ.AddPlayer and CDZ.AddPlayer(name) then
                if ns.RefreshAll then ns.RefreshAll() end
            end
        end, { width = 460 })
    end)

    -- Bouton footer (droite) : popup d’ajout depuis la guilde
    local btnGuild = UI.Button(footer, "Ajouter un membre de la guilde", { size="sm", minWidth=220 })
    btnGuild:SetOnClick(function()
        if not (CDZ.IsMaster and CDZ.IsMaster()) then
            UIErrorsFrame:AddMessage("|cffff6060[CDZ]|r Ajout au roster réservé au GM.", 1, 0.4, 0.4)
            return
        end
        if UI.ShowGuildRosterPopup then UI.ShowGuildRosterPopup() end
    end)

    -- Bouton Historique (déjà demandé précédemment)
    local histBtn = UI.Button(footer, "Historique", { size="sm", minWidth=120, tooltip="Voir l’historique des répartitions" })
    histBtn:SetOnClick(function() UI.ShowTabByLabel("Historique des sorties") end)

    -- Aligner à droite : Historique | Ajouter membre guilde | + Ajouter
    if UI.AttachButtonsFooterRight then
        UI.AttachButtonsFooterRight(footer, { histBtn, btnGuild, addBtn })
    else
        addBtn:ClearAllPoints()
        addBtn:SetPoint("RIGHT", footer, "RIGHT", 0, 0)
        btnGuild:ClearAllPoints()
        btnGuild:SetPoint("RIGHT", addBtn, "LEFT", -8, 0)
        histBtn:ClearAllPoints()
        histBtn:SetPoint("RIGHT", btnGuild, "LEFT", -8, 0)
    end

    -- Visibilité : bouton + réservé au GM
    if not (CDZ.IsMaster and CDZ.IsMaster()) then
        addBtn:Hide()
    end

    lv = UI.ListView(panel, cols, { buildRow = BuildRow, updateRow = UpdateRow, topOffset = 0, bottomAnchor = footer })
end

UI.RegisterTab("Roster", Build, Refresh, Layout)
