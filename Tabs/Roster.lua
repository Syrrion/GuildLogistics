local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns.GLOG, ns.UI
local PAD, SBW, GUT = UI.OUTER_PAD, UI.SCROLLBAR_W, UI.GUTTER

local panel, lvActive, lvReserve, activeArea, reserveArea, footer, totalFS, resourceFS, sepFS, bothFS, noGuildMsg, bankLeftFS, bankSepFS, bankRightFS

-- État d’affichage ...
local reserveCollapsed = true
local reserveToggleBtn

-- ➕ État d’affichage des joueurs masqués (réserve)
local _showHiddenReserve = false


-- Détecte si le personnage appartient à une guilde
local function _HasGuild()
    return (IsInGuild and IsInGuild()) and true or false
end

-- Affiche un message centré si aucune guilde, et masque les listes + footer
local function _UpdateNoGuildUI()
    local hasGuild = _HasGuild()
    local showMsg = not hasGuild

    if noGuildMsg then noGuildMsg:SetShown(showMsg) end
    if activeArea  then activeArea:SetShown(not showMsg) end
    if reserveArea then reserveArea:SetShown(not showMsg) end
    if footer      then footer:SetShown(not showMsg) end
    if reserveToggleBtn then reserveToggleBtn:SetShown(not showMsg) end

    -- Ajuste la navigation globale (onglets)
    if UI and UI.ApplyTabsForGuildMembership then
        UI.ApplyTabsForGuildMembership(hasGuild)
    end
end


local cols = UI.NormalizeColumns({
    { key="alias",  title=Tr("col_alias"),          w=90, justify="LEFT" },
    { key="lvl",    title=Tr("col_level_short"),    vsep=true,  w=44, justify="CENTER" },
    { key="name",   title=Tr("col_name"),           vsep=true,  min=200, flex=1 },
    { key="act",    title="",                       vsep=true,  w=120 },
    { key="solde",  title=Tr("col_balance"),        vsep=true,  w=70 },
})

-- Helpers
local function money(v)
    v = tonumber(v) or 0
    return (UI and UI.MoneyText) and UI.MoneyText(v) or (tostring(v).." po")
end

-- Affichage cuivre → g/s/c
local function moneyCopper(v)
    v = tonumber(v) or 0
    return (UI and UI.MoneyFromCopper) and UI.MoneyFromCopper(v) or (tostring(math.floor(v/10000)).." po")
end

local function CanActOn(name)
    local isMaster = (GLOG.CanModifyGuildData and GLOG.CanModifyGuildData()) or false
    if isMaster then return true, true end
    local meFull = ns.Util.playerFullName and ns.Util.playerFullName()
    local isSelf = ns.Util.SamePlayer and ns.Util.SamePlayer(name, meFull)
    return isSelf, isMaster
end

-- Retourne des infos d'agrégation par MAIN + le reroll en ligne (nom + classe)
local function FindGuildInfo(playerName)
    return (GLOG.GetMainAggregatedInfo and GLOG.GetMainAggregatedInfo(playerName)) or {}
end

-- Gestion robuste du solde : accepte soit l'objet "data" de ligne, soit un nom de joueur (string)
local function GetSolde(data)
    if type(data) == "string" then
        return (GLOG.GetSolde and GLOG.GetSolde(data)) or 0
    end
    if type(data) == "table" then
        return tonumber(data.solde) or 0
    end
    return 0
end

-- Boutons scripts
local function AttachDepositHandler(btn, name, canAct, isMaster)
    btn:SetScript("OnClick", function()
        if not canAct then return end
        UI.PopupPromptNumber(Tr("prefix_add_gold_to")..(name or ""), Tr("lbl_total_amount_gold_alt"), function(amt)
            amt = math.floor(tonumber(amt) or 0)
            if amt > 0 then
                if isMaster then
                    if GLOG.GM_AdjustAndBroadcast then GLOG.GM_AdjustAndBroadcast(name, amt) end
                else
                    if GLOG.RequestAdjust then GLOG.RequestAdjust(name, amt) end
                end
            end
        end)
    end)
end

local function AttachWithdrawHandler(btn, name, canAct, isMaster)
    btn:SetScript("OnClick", function()
        if not canAct then return end
        UI.PopupPromptNumber(Tr("prefix_remove_gold_from")..(name or ""), Tr("lbl_total_amount_gold_alt"), function(amt)
            amt = math.floor(tonumber(amt) or 0)
            if amt > 0 then
                local delta = -amt
                if isMaster then
                    if GLOG.GM_AdjustAndBroadcast then GLOG.GM_AdjustAndBroadcast(name, delta) end
                else
                    if GLOG.RequestAdjust then GLOG.RequestAdjust(name, delta) end
                end
            end
        end)
    end)
end

-- BuildRow
-- Construit une ligne de la ListView (actifs/réserve)
local function BuildRow(r, context)
    local f = {}
    f.lvl   = UI.Label(r, { justify = "CENTER" })
    f.alias = UI.Label(r, { justify = "LEFT"  })
    f.name  = UI.CreateNameTag(r)
    -- Solde (fontstring simple pour compat thèmes)
    f.solde = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")

    -- Conteneur d’actions
    f.act = CreateFrame("Frame", nil, r)
    f.act:SetHeight(UI.ROW_H)
    f.act:SetFrameLevel(r:GetFrameLevel()+1)

    -- Actions financières
    r.btnDeposit  = UI.Button(f.act, Tr("btn_deposit_gold"),   { size="sm", minWidth=60 })
    r.btnWithdraw = UI.Button(f.act, Tr("btn_withdraw_gold"),  { size="sm", variant="ghost", minWidth=60 })

    -- Alignement des actions à droite
    UI.AttachRowRight(f.act, {  r.btnDeposit, r.btnWithdraw }, 8, -4, { leftPad = 8, align = "center" })

    return f
end

-- UpdateRow
local function UpdateRow(i, r, f, data)
    local GHX = (UI and UI.GRAY_OFFLINE_HEX) or "999999"
    local function gray(t) return "|cff"..GHX..tostring(t).."|r" end

    -- Nom (sans royaume) + ajout éventuel du reroll connecté (icône + nom)
    UI.SetNameTagShort(f.name, data.name or "")

    -- Récupère le reroll online attaché au main (si différent du main)
    local gi = FindGuildInfo(data.name or "")
    local altBase, altFull, altClass = gi and gi.onlineAltBase, gi and gi.onlineAltFull, gi and gi.altClass

    if altBase and altBase ~= "" then
        -- Icône de classe ronde (texture native)
        local function classIconMarkup(classTag, size)
            size = size or 14
            if not classTag or classTag == "" then return "" end
            local c = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classTag]
            if not c then return "" end
            local w, h = size, size
            return ("|TInterface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES:%d:%d:0:0:256:256:%d:%d:%d:%d|t")
                :format(w, h, c[1]*256, c[2]*256, c[3]*256, c[4]*256)
        end

        -- Nom du reroll (sans royaume), coloré classe
        local altShort   = (ns and ns.Util and ns.Util.ShortenFullName and ns.Util.ShortenFullName(altFull or altBase)) or altBase
        local altColored = (UI and UI.WrapTextClassColor and UI.WrapTextClassColor(altShort, nil, altClass)) or altShort
        local icon       = classIconMarkup(altClass, 14)

        -- On garde la casse du main ; parenthèses grises uniquement
        local baseText = (f.name and f.name.text and f.name.text:GetText()) or ""
        local altPart  = (" |cffaaaaaa( |r%s%s|cffaaaaaa )|r"):format((icon ~= "" and (icon.." ") or ""), altColored)

        if f.name and f.name.text then
            f.name.text:SetText(baseText .. altPart)
        end
    end

    -- Alias
    if f.alias then
        local a = (GLOG.GetAliasFor and GLOG.GetAliasFor(data.name)) or ""
        f.alias:SetText((" "..a and a ~= "") and " "..a or "")
    end

    -- Infos guilde agrégées (online/last seen/level + reroll en ligne)
    local gi = FindGuildInfo(data.name)

    -- Alias: griser si le joueur est hors ligne
    if f.alias then
        local a = (GLOG.GetAliasFor and GLOG.GetAliasFor(data.name)) or ""
        if a ~= "" and gi and not gi.online then
            f.alias:SetText(gray(" "..a))
        end
    end

    -- Niveau
    if f.lvl then
        if gi.level and gi.level > 0 then
            if gi.online then
                f.lvl:SetText((UI and UI.ColorizeLevel) and UI.ColorizeLevel(gi.level) or tostring(gi.level))
            else
                f.lvl:SetText(gray(tostring(gi.level)))
            end
        else
            f.lvl:SetText("")
        end
    end
    
    -- Solde banque perso
    if f.solde then f.solde:SetText(money(GetSolde(data.name))) end

    -- Autorisations & boutons
    local isSelf, isMaster = CanActOn(data.name)
    local canAct           = (isMaster or isSelf)       -- GM = tout voir/tout faire ; sinon soi-même

    if r.btnDeposit then
        r.btnDeposit:SetShown(canAct)
        AttachDepositHandler(r.btnDeposit, data.name, canAct, isMaster)
    end
    if r.btnWithdraw then
        r.btnWithdraw:SetShown(canAct)
        AttachWithdrawHandler(r.btnWithdraw, data.name, canAct, isMaster)
    end

    -- Recalage du container d’actions
    if f and f.act and f.act._applyRowActionsLayout then
        f.act._applyRowActionsLayout()
    end
end

-- Layout
local function Layout()
    if not (activeArea and reserveArea) then return end
    local panelH = panel:GetHeight()
    local footerH = (UI.FOOTER_H or 36)
    local gap = 10

    activeArea:ClearAllPoints()
    reserveArea:ClearAllPoints()

    if reserveCollapsed then
        -- Actif plein écran ; Réserve : entête seule
        reserveArea:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", UI.OUTER_PAD, footerH + gap)
        reserveArea:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -UI.OUTER_PAD, footerH + gap)
        reserveArea:SetHeight((UI.SECTION_HEADER_H or 26))

        activeArea:SetPoint("TOPLEFT",  panel, "TOPLEFT",  UI.OUTER_PAD, -(UI.OUTER_PAD))
        activeArea:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -UI.OUTER_PAD, -(UI.OUTER_PAD))
        activeArea:SetPoint("BOTTOMLEFT", reserveArea, "TOPLEFT",  0, gap)
        activeArea:SetPoint("BOTTOMRIGHT", reserveArea, "TOPRIGHT", 0, gap)
        activeArea:Show()
    else
        -- Réserve dépliée : elle prend toute la hauteur ; Actif complètement masqué
        activeArea:Hide()

        reserveArea:SetPoint("TOPLEFT",  panel, "TOPLEFT",  UI.OUTER_PAD, -(UI.OUTER_PAD))
        reserveArea:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -UI.OUTER_PAD, -(UI.OUTER_PAD))
        reserveArea:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", UI.OUTER_PAD, footerH + gap)
        reserveArea:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -UI.OUTER_PAD, footerH + gap)
    end

    if lvActive  and lvActive.Layout  then lvActive:Layout()  end
    if lvReserve and lvReserve.Layout then lvReserve:Layout() end
end


-- Met à jour l’UI du pliage/dépliage de la réserve
local function UpdateReserveCollapseUI()
    -- Bouton + / -
    if reserveToggleBtn then
        reserveToggleBtn:SetText(reserveCollapsed and Tr("btn_expand") or Tr("btn_collapse") or (reserveCollapsed and "+" or "-"))

        -- Ajustement d’alignement : décale légèrement le bouton vers la gauche et vers le haut (appliqué une seule fois)
        if not reserveToggleBtn._nudgeApplied then
            local p, relTo, relP, x, y = reserveToggleBtn:GetPoint(1)
            reserveToggleBtn:ClearAllPoints()
            reserveToggleBtn:SetPoint(p or "LEFT", relTo, relP, (x or 0) - 8, (y or 0) + 10)
            reserveToggleBtn._nudgeApplied = true

            -- Agrandit un peu la zone cliquable côté gauche pour compenser le décalage
            if reserveToggleBtn.SetHitRectInsets then
                reserveToggleBtn:SetHitRectInsets(-6, -2, -2, -2)
            end
        end
    end

    -- Bouton "Afficher joueurs masqués" supprimé définitivement
    
    -- Masque/affiche le contenu de la ListView "réserve" (et force l’état de l’entête)
    if lvReserve and lvReserve.scroll then
        if lvReserve.SetHeaderForceHidden then
            lvReserve:SetHeaderForceHidden(reserveCollapsed)
        end
        if reserveCollapsed then
            lvReserve.scroll:Hide()
        else
            lvReserve.scroll:Show()
        end
    end

    -- Recalcule la mise en page liée à l’état
    if Layout then Layout() end

    -- Rafraîchit les lignes visibles immédiatement si possible
    if lvActive and lvActive.UpdateVisibleRows then lvActive:UpdateVisibleRows() end
    if lvReserve and lvReserve.UpdateVisibleRows then lvReserve:UpdateVisibleRows() end

    -- Et planifie un Refresh léger pour recharger les données après le relayout
    if C_Timer and C_Timer.After then
        C_Timer.After(0.05, function()
            if Refresh then Refresh() end
        end)
    else
        if Refresh then Refresh() end
    end
end


-- Tri: en ligne d'abord (ordre alpha à l'intérieur), puis hors-ligne (ordre alpha)
local function _SortOnlineFirst(arr)
    if not arr or #arr == 0 then return end
    table.sort(arr, function(a, b)
        -- a/b sont des enregistrements { name=..., ... } (mains agrégés)
        local na = (a.name or ""):lower()
        local nb = (b.name or ""):lower()

        local giA = FindGuildInfo(a.name) or {}
        local giB = FindGuildInfo(b.name) or {}
        local oa  = giA.online and 1 or 0
        local ob  = giB.online and 1 or 0
        if oa ~= ob then
            return oa > ob            -- 1 (en ligne) doit passer avant 0 (hors-ligne)
        end
        return na < nb                -- sinon, simple alpha par Nom
    end)
end

local function Refresh()

    -- Mode « sans guilde » : message centré, pas de listes ni footer
    _UpdateNoGuildUI()
    if not _HasGuild() then
        if lvActive then lvActive:SetData({}) end
        if lvReserve then lvReserve:SetData({}) end
        if lvActive and lvActive.Layout then lvActive:Layout() end
        if lvReserve and lvReserve.Layout then lvReserve:Layout() end
        return
    end

    local active  = (GLOG.GetPlayersArrayActive  and GLOG.GetPlayersArrayActive())  or {}

    -- ➕ Masque par défaut les réserves inactives sans solde ;
    --    si le GM a cliqué "Afficher joueurs masqués", on lève le filtre
    local reserve = (GLOG.GetPlayersArrayReserve and GLOG.GetPlayersArrayReserve({
        showHidden = _showHiddenReserve,  -- false par défaut → masque
        cutoffDays = 30
    })) or {}

    _SortOnlineFirst(active)
    _SortOnlineFirst(reserve)

    if lvActive then
        local wrappedA = {}
        for i, it in ipairs(active) do wrappedA[i] = { data = it, fromActive = true } end
        lvActive:SetData(wrappedA)
    end
    if lvReserve then
        local wrappedR = {}
        for i, it in ipairs(reserve) do wrappedR[i] = { data = it, fromReserve = true } end
        lvReserve:SetData(wrappedR)
    end

    local total = 0
    for _, it in ipairs(active)  do total = total + (tonumber(it.solde) or 0) end
    for _, it in ipairs(reserve) do total = total + (tonumber(it.solde) or 0) end
    if totalFS then
        local txt = (UI and UI.MoneyText) and UI.MoneyText(total) or (tostring(total).." po")
        totalFS:SetText("|cffffd200"..Tr("lbl_total_balance").." :|r " .. txt)
    end
    -- Total ressources (en cuivre -> arrondi à l'or comme les soldes)
    local rcopper = 0
    if GLOG and GLOG.Resources_TotalAvailableCopper then
        rcopper = GLOG.Resources_TotalAvailableCopper() or 0
    end

    if resourceFS then
        local rtxt = (UI and UI.MoneyText) and UI.MoneyText(rcopper / 10000) or (tostring(math.floor(rcopper / 10000 + 0.5)).." po")
        resourceFS:SetText("|cffffd200"..Tr("lbl_total_resources").." :|r " .. rtxt)
    end

    -- Total cumulé = soldes (en or) + ressources (converties en or), même arrondi que MoneyText
    if bothFS then
        local combinedGold = (tonumber(total) or 0) - (rcopper / 10000)
        local ctxt = (UI and UI.MoneyText) and UI.MoneyText(combinedGold) or (tostring(math.floor(combinedGold + 0.5)).." po")
        bothFS:SetText("|cffffd200"..Tr("lbl_total_both").." :|r " .. ctxt)
    end

    -- Banque et Équilibre (alignés à droite, labels orange, séparateur gris comme à gauche)
    if bankRightFS and bankLeftFS then
        local bankCopper = GLOG.GetGuildBankBalanceCopper and GLOG.GetGuildBankBalanceCopper() or nil
        local combinedGold = (tonumber(total) or 0) - (rcopper / 10000)
        local xTxt, yTxt
        if bankCopper == nil then
            -- Bank unknown: show grey 'No data' and tooltip for both X and Y
            local nd = "|cffaaaaaa"..(Tr("no_data") or "Aucune données").."|r"
            xTxt = nd
            yTxt = nd
        else
            local bankGold   = bankCopper / 10000
            local equilibrium = (bankGold or 0) - (combinedGold or 0)
            xTxt = (UI and UI.MoneyText and UI.MoneyText(bankGold))
                or tostring(math.floor(bankGold + 0.5)).." po"
            do
                local base = (UI and UI.MoneyText) and UI.MoneyText(equilibrium) or (tostring(math.floor(equilibrium + 0.5)).." po")
                if equilibrium and equilibrium > 0 then
                    -- Positive equilibrium in green; negative already red via MoneyText
                    yTxt = "|cff40ff40"..base.."|r"
                else
                    yTxt = base
                end
            end
        end
        local orange = "|cffffd200"; local reset = "|r"
        bankLeftFS:SetText(orange..(Tr("lbl_bank_balance") or "Solde Banque").." :"..reset.." "..xTxt)
        -- Tooltip on values when data is missing
        if (bankCopper == nil) and UI and UI.SetTooltip then
            local hint = Tr("hint_open_gbank_to_update") or "Ouvrir la banque de guilde pour mettre à jour cette donnée"
            UI.SetTooltip(bankLeftFS, hint)
            UI.SetTooltip(bankRightFS, hint)
        else
            -- Remove tooltips if previously set (safe no-op)
            if bankLeftFS.SetScript then bankLeftFS:SetScript("OnEnter", nil); bankLeftFS:SetScript("OnLeave", nil) end
            if bankRightFS.SetScript then bankRightFS:SetScript("OnEnter", nil); bankRightFS:SetScript("OnLeave", nil) end
        end
        bankRightFS:SetText(orange..(Tr("lbl_equilibrium") or "Équilibre").." :"..reset.." "..yTxt)
    end
end

-- Footer
-- Boutons footer supprimés: aucun bouton spécifique dans le footer du Roster


-- Build panel
local function Build(container)
    -- Création du conteneur
    panel, footer = UI.CreateMainContainer(container, {footer = true})
    activeArea  = CreateFrame("Frame", nil, panel)
    reserveArea = CreateFrame("Frame", nil, panel)

    UI.SectionHeader(activeArea,  Tr("lbl_active_roster"),      { topPad = 2 })
    -- L’entête de la réserve garde un padding à gauche pour le petit bouton +/-
    UI.SectionHeader(reserveArea, Tr("lbl_reserved_players"),   { topPad = 2, padLeft = 18 })

    if panel and panel.GetFrameLevel then
        local base = (panel:GetFrameLevel() or 0)
        if activeArea and activeArea.SetFrameLevel then
            activeArea:SetFrameLevel(base + 1)
        end
        if reserveArea and reserveArea.SetFrameLevel then
            reserveArea:SetFrameLevel(base + 1)
        end
    end

    -- Petit bouton + / - à gauche du texte d’entête de la réserve
    reserveToggleBtn = CreateFrame("Button", nil, reserveArea, "UIPanelButtonTemplate")
    reserveToggleBtn:SetSize(20, 20)
    reserveToggleBtn:SetPoint("TOPLEFT", reserveArea, "TOPLEFT", 0, -(4 + 4))
    reserveToggleBtn:SetText("+")
    reserveToggleBtn:SetScript("OnClick", function()
        reserveCollapsed = not reserveCollapsed
        UpdateReserveCollapseUI()
    end)

    lvActive = UI.ListView(activeArea, cols, {
        buildRow = function(r) return BuildRow(r, "active") end,
        updateRow = function(i, r, f, it)
            local data = it.data or it
            UpdateRow(i, r, f, data)
            if r.btnReserve then
                local isMaster = (GLOG.CanModifyGuildData and GLOG.CanModifyGuildData()) or false
                r.btnReserve:SetShown(isMaster)
                if r.btnRoster then r.btnRoster:SetShown(false) end
                if isMaster then
                    r.btnReserve:SetOnClick(function()
                        if GLOG.GM_SetReserved then GLOG.GM_SetReserved(data.name, true) end
                    end)
                end
            end
        end,
        topOffset = UI.SECTION_HEADER_H or 26
    })

    lvReserve = UI.ListView(reserveArea, cols, {
        buildRow = function(r) return BuildRow(r, "reserve") end,
        updateRow = function(i, r, f, it)
            local data = it.data or it
            UpdateRow(i, r, f, data)
            if r.btnRoster then
                local isMaster = (GLOG.CanModifyGuildData and GLOG.CanModifyGuildData()) or false
                r.btnRoster:SetShown(isMaster)
                if r.btnReserve then r.btnReserve:SetShown(false) end
                if isMaster then
                    r.btnRoster:SetOnClick(function()
                        if GLOG.GM_SetReserved then GLOG.GM_SetReserved(data.name, false) end
                    end)
                end
            end
        end,
        topOffset = UI.SECTION_HEADER_H or 26,
        bottomAnchor = footer
    })

    -- Masque de fond englobant (header + contenu) pour la ListView des Actifs
    do
        -- Cache (par prudence) le containerBG générique si présent pour éviter un double assombrissement
        if lvActive and lvActive._containerBG and lvActive._containerBG.Hide then
            lvActive._containerBG:Hide()
        end

        local col = (UI.GetListViewContainerColor and UI.GetListViewContainerColor()) or { r = 0, g = 0, b = 0, a = 0.20 }
        local bg = activeArea:CreateTexture(nil, "BACKGROUND")
        bg:SetColorTexture(col.r or 0, col.g or 0, col.b or 0, col.a or 0.20)

        -- Englobe exactement le header de colonnes + la zone scroll de la ListView
        if lvActive and lvActive.header and lvActive.scroll then
            bg:SetPoint("TOPLEFT",     lvActive.header, "TOPLEFT",     0, 0)
            bg:SetPoint("BOTTOMRIGHT", lvActive.scroll, "BOTTOMRIGHT", 0, 0)
        end

        -- Si la vue est relayoutée, on recale proprement le masque
        if lvActive and lvActive.Layout and not lvActive._synth_bg_hook then
            local _old = lvActive.Layout
            function lvActive:Layout(...)
                local res = _old(self, ...)
                if bg and self.header and self.scroll then
                    bg:ClearAllPoints()
                    bg:SetPoint("TOPLEFT",     self.header, "TOPLEFT",     0, 0)
                    bg:SetPoint("BOTTOMRIGHT", self.scroll, "BOTTOMRIGHT", 0, 0)
                end
                return res
            end
            lvActive._synth_bg_hook = true
        end
    end

    totalFS = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    totalFS:SetPoint("LEFT", footer, "LEFT", PAD, 0)

    -- Compteur "Total ressources" (si vous l'avez déjà créé, ce bloc est idempotent)
    if not resourceFS then
        resourceFS = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        resourceFS:SetPoint("LEFT", totalFS, "RIGHT", 24, 0)
    end

    -- Séparateur visuel (léger, gris)
    if not sepFS then
        sepFS = footer:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        sepFS:SetPoint("LEFT", resourceFS, "RIGHT", 16, 0)
        sepFS:SetText("|")
    end

    -- Compteur "Total cumulé" (soldes + ressources)
    if not bothFS then
        bothFS = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        bothFS:SetPoint("LEFT", sepFS, "RIGHT", 16, 0)
    end

    -- Bloc aligné à droite: "Solde Banque : X | Équilibre : Y" avec séparateur gris et espacement identique
    if not bankRightFS then
        bankRightFS = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        bankRightFS:SetPoint("RIGHT", footer, "RIGHT", - (UI.FOOTER_RIGHT_PAD or 8), 0)
        bankRightFS:SetJustifyH("RIGHT")
    end
    if not bankSepFS then
        bankSepFS = footer:CreateFontString(nil, "OVERLAY", "GameFontDisable")
        bankSepFS:SetPoint("RIGHT", bankRightFS, "LEFT", -16, 0)
        bankSepFS:SetText("|")
    end
    if not bankLeftFS then
        bankLeftFS = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        bankLeftFS:SetPoint("RIGHT", bankSepFS, "LEFT", -16, 0)
        bankLeftFS:SetJustifyH("RIGHT")
    end


    -- Aucun bouton footer à créer dans l'onglet Roster

    if not noGuildMsg then
        noGuildMsg = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        noGuildMsg:SetPoint("CENTER", panel, "CENTER", 0, 0)
        noGuildMsg:SetJustifyH("CENTER"); noGuildMsg:SetJustifyV("MIDDLE")
        noGuildMsg:SetText(Tr("msg_no_guild"))
        noGuildMsg:Hide()
    end

    -- Applique l’état par défaut (“réserve” repliée) et ajuste la mise en page
    UpdateReserveCollapseUI()
    _UpdateNoGuildUI()
end

-- ➕ Surveille les changements de groupe pour mettre à jour le surlignage
do
    local function _onGroupChanged()
        -- MàJ légère si possible (affecte surtout l'accent des lignes)
        if lvActive and lvActive.UpdateVisibleRows then lvActive:UpdateVisibleRows() end
        if lvReserve and lvReserve.UpdateVisibleRows then lvReserve:UpdateVisibleRows() end
        -- Et debounce un Refresh complet pour re-trier si nécessaire
        if ns and ns.Util and ns.Util.Debounce then
            ns.Util.Debounce("tab:roster:refresh", 0.15, function()
                if Refresh then Refresh() end
            end)
        else
            if Refresh then Refresh() end
        end
    end
    ns.Events.Register("GROUP_ROSTER_UPDATE", _onGroupChanged)
end

-- Rafraîchir le footer quand la banque de guilde met à jour son solde
do
    local function _onGuildBankUpdated()
        -- Rafraîchit uniquement si l'UI principale est visible
        if ns and ns.UI and ns.UI.Main and ns.UI.Main:IsShown() then
            if C_Timer and C_Timer.After then
                C_Timer.After(0.1, function()
                    if Refresh then Refresh() end
                end)
            else
                if Refresh then Refresh() end
            end
        end
    end
    if GLOG and GLOG.On then GLOG.On("guildbank:updated", _onGuildBankUpdated) end
end


UI.RegisterTab(Tr("tab_roster"), Build, Refresh, Layout, {
    category = Tr("cat_raids"),
})
