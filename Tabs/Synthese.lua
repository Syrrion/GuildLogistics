local ADDON, ns = ...
local CDZ, UI = ns.CDZ, ns.UI
local PAD, SBW, GUT = UI.OUTER_PAD, UI.SCROLLBAR_W, UI.GUTTER

local panel, addBtn, lv, footer, totalFS


local cols = UI.NormalizeColumns({
    { key="name",   title="Nom",    min=240, flex=1 },
    { key="act",    title="", w=300 },
    { key="solde",  title="Solde",  w=140 },
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
    r.btnCredit = UI.Button(f.act, "Dépôt d’or", { size="sm", minWidth=90 })
    r.btnDebit  = UI.Button(f.act, "Retrait d’or", { size="sm", variant="ghost", minWidth=90 })
    r.btnDelete = UI.Button(f.act, "X", { size="sm", variant="danger", minWidth=28, padX=12 })
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

-- Deux ListViews
local lvActive, lvReserve, activeArea, reserveArea

local function Layout()
    if not (activeArea and reserveArea) then return end
    local panelH = panel:GetHeight()
    local footerH = (UI.FOOTER_H or 36)
    local gap = 10

    -- Répartition inspirée de "Démarrer un raid" : ~60% / 40%
    local usableH = panelH - footerH - (gap * 3)
    local hTop = math.floor(usableH * 0.60)
    local hBot = usableH - hTop

    activeArea:ClearAllPoints()
    activeArea:SetPoint("TOPLEFT",  panel, "TOPLEFT",  UI.OUTER_PAD, -(UI.OUTER_PAD))
    activeArea:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -UI.OUTER_PAD, -(UI.OUTER_PAD))
    activeArea:SetHeight(hTop)

    reserveArea:ClearAllPoints()
    reserveArea:SetPoint("TOPLEFT",  activeArea, "BOTTOMLEFT", 0, -gap)
    reserveArea:SetPoint("TOPRIGHT", activeArea, "BOTTOMRIGHT", 0, -gap)
    reserveArea:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", UI.OUTER_PAD, (UI.FOOTER_H or 36) + gap)
    reserveArea:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -UI.OUTER_PAD, (UI.FOOTER_H or 36) + gap)

    if lvActive  and lvActive.Layout  then lvActive:Layout()  end
    if lvReserve and lvReserve.Layout then lvReserve:Layout() end
    if lv and footer and lv.SetBottomAnchor then lv:SetBottomAnchor(footer) end
end

local function Refresh()
    local active  = (CDZ.GetPlayersArrayActive  and CDZ.GetPlayersArrayActive())  or {}
    local reserve = (CDZ.GetPlayersArrayReserve and CDZ.GetPlayersArrayReserve()) or {}

    if lvActive  then lvActive:SetData(active)   end
    if lvReserve then
        -- tag pour UpdateRow (savoir de quelle liste provient l’item)
        local wrapped = {}
        for i, it in ipairs(reserve) do wrapped[i] = { data = it, fromReserve = true } end
        lvReserve:SetData(wrapped)
    end

    -- ✅ Total cumulé des soldes (actif + réserve)
    do
        local total = 0
        for _, it in ipairs(active)  do total = total + (tonumber(it.solde) or 0) end
        for _, it in ipairs(reserve) do total = total + (tonumber(it.solde) or 0) end
        if totalFS then
            local txt = (UI and UI.MoneyText) and UI.MoneyText(total) or (tostring(total).." po")
            totalFS:SetText("|cffffd200Total soldes :|r " .. txt)
        end
    end

    if lvActive  and lvActive.Layout  then lvActive:Layout()  end
    if lvReserve and lvReserve.Layout then lvReserve:Layout() end
end

local function Build(container)
    panel = container
    if UI.ApplySafeContentBounds then UI.ApplySafeContentBounds(panel) end

    -- ➕ Deux zones analogues à "Démarrer un raid"
    activeArea  = CreateFrame("Frame", nil, panel)
    reserveArea = CreateFrame("Frame", nil, panel)

    UI.SectionHeader(activeArea,  "Roster actif",      { topPad = 2 })
    UI.SectionHeader(reserveArea, "Joueurs en réserve",{ topPad = 2 })

    -- colonnes héritées de la liste existante (nom / solde / actions)
    local cols = cols or nil  -- on réutilise la définition existante du fichier

    -- Listes (topOffset = hauteur de l’entête de section)
    lvActive  = UI.ListView(activeArea,  cols, { buildRow = BuildRow,  updateRow = function(i, r, f, it)
        -- sur la liste "active", it = donnée brute
        UpdateRow(i, r, f, it)  -- logique existante pour crédit/débit/supp.
        -- ➕ bouton "Mettre en réserve" (GM uniquement)
        if not r.btnReserve then
            r.btnReserve = UI.Button(r, "Mettre en réserve", { size="sm", minWidth=120, tooltip="Basculer ce joueur en Réserve" })
            if r.btnDelete then r.btnReserve:SetPoint("RIGHT", r.btnDelete, "LEFT", -6, 0) end
        end
        local isMaster = (CDZ.IsMaster and CDZ.IsMaster()) or false
        r.btnReserve:SetShown(isMaster)
        if isMaster then
            r.btnReserve:SetOnClick(function()
                if CDZ.GM_SetReserved then CDZ.GM_SetReserved(it.name, true) end
            end)
        end
    end, topOffset = UI.SECTION_HEADER_H or 26 })

    lvReserve = UI.ListView(reserveArea, cols, { buildRow = BuildRow, updateRow = function(i, r, f, it)
        -- sur la liste "réserve", it = { data=..., fromReserve=true }
        local data = it.data or it
        UpdateRow(i, r, f, data)
        -- ➕ bouton "Intégrer au roster" (GM uniquement)
        if not r.btnReserve then
            r.btnReserve = UI.Button(r, "Intégrer au roster", { size="sm", minWidth=120, tooltip="Renvoyer ce joueur dans le Roster actif" })
            if r.btnDelete then r.btnReserve:SetPoint("RIGHT", r.btnDelete, "LEFT", -6, 0) end
        end
        local isMaster = (CDZ.IsMaster and CDZ.IsMaster()) or false
        r.btnReserve:SetShown(isMaster)
        if isMaster then
            r.btnReserve:SetText("Intégrer au roster")
            r.btnReserve:SetOnClick(function()
                if CDZ.GM_SetReserved then CDZ.GM_SetReserved(data.name, false) end
            end)
        end
    end, topOffset = UI.SECTION_HEADER_H or 26, bottomAnchor = footer })

    footer = UI.CreateFooter(panel, 36)

    -- Total cumulé (gauche) — même principe que l'onglet Ressources
    totalFS = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    totalFS:SetPoint("LEFT", footer, "LEFT", PAD, 0)

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

    -- Bouton footer (droite) : popup membres guilde (consultation pour non-GM)
    local isGM   = (CDZ.IsMaster and CDZ.IsMaster()) or false
    local label  = isGM and "Ajouter un membre de la guilde" or "Membres de la guilde"
    local btnGuild = UI.Button(footer, label, { size="sm", minWidth=220 })
    btnGuild:SetOnClick(function()
        -- Non-GM : consultation autorisée
        if UI.ShowGuildRosterPopup then UI.ShowGuildRosterPopup() end
    end)

    -- Bouton Historique (déjà demandé précédemment)
    local histBtn = UI.Button(footer, "Historique des raids", { size="...", minWidth=120, tooltip="Voir l’historique des raids" })
    histBtn:SetOnClick(function() UI.ShowTabByLabel("Historique") end)

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


end

UI.RegisterTab("Roster", Build, Refresh, Layout)
