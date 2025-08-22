local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns.GLOG, ns.UI
local PAD, SBW, GUT = UI.OUTER_PAD, UI.SCROLLBAR_W, UI.GUTTER

local panel, lvActive, lvReserve, activeArea, reserveArea, footer, totalFS, noGuildMsg
-- État d’affichage ...
local reserveCollapsed = true
local reserveToggleBtn

-- ➕ État d’affichage des joueurs masqués (réserve)
local _showHiddenReserve = false
local _btnShowHiddenReserve -- référence bouton footer


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
    { key="lvl",    title=Tr("col_level_short"),    w=44, justify="CENTER" },
    { key="alias",  title=Tr("col_alias"),          w=80, justify="LEFT" },
    { key="name",   title=Tr("col_name"),           min=180, flex=1 },
    { key="ilvl",   title=Tr("col_ilvl"),           w=64, justify="CENTER" },
    { key="mkey",   title=Tr("col_mplus_key"),      w=200, justify="LEFT" },
    { key="last",   title=Tr("col_attendance"),     w=180 },
    { key="act",    title="",                        w=150 },
    { key="solde",  title=Tr("col_balance"),        w=70 },
})

-- Helpers
local function money(v)
    v = tonumber(v) or 0
    return (UI and UI.MoneyText) and UI.MoneyText(v) or (tostring(v).." po")
end

local function CanActOn(name)
    local isMaster = GLOG.IsMaster and GLOG.IsMaster()
    if isMaster then return true, true end
    local meFull = ns.Util.playerFullName and ns.Util.playerFullName()
    if (not meFull or meFull == "") and UnitFullName then
        local n, rlm = UnitFullName("player")
        local rn = (GetNormalizedRealmName and GetNormalizedRealmName()) or rlm
        meFull = (n and rn and rn ~= "") and (n.."-"..rn) or (n or UnitName("player"))
    end
    local isSelf = ns.Util.SamePlayer and ns.Util.SamePlayer(name, meFull)
    return isSelf, isMaster
end

function FindGuildInfo(playerName)
    local guildRows = (GLOG.GetGuildRowsCached and GLOG.GetGuildRowsCached()) or {}
    local NormName = GLOG.NormName
    if not playerName or playerName == "" then return {} end

    -- Détermine le main (si reroll), sinon le nom lui-même
    local mainName = (GLOG.GetMainOf and GLOG.GetMainOf(playerName)) or playerName
    local mainKey  = NormName and NormName(mainName)

    local info = {}

    -- Conserve idx/level du main uniquement (ne pas toucher aux autres éléments)
    for _, gr in ipairs(guildRows) do
        if NormName and NormName(gr.name_amb or gr.name_raw) == mainKey then
            info.idx = gr.idx
            if GetGuildRosterInfo and gr.idx then
                local _, _, _, level = GetGuildRosterInfo(gr.idx)
                info.level = tonumber(level)
            end
            break
        end
    end

    -- Agrège la présence sur tous les rerolls rattachés au main
    local anyOnline, minDays, minHours = false, nil, nil
    for _, gr in ipairs(guildRows) do
        local rowNameKey = NormName and NormName(gr.name_amb or gr.name_raw)
        local rowMainKey = (gr.remark and NormName and NormName(strtrim(gr.remark))) or nil

        -- Appartient au même main si :
        --  - la note de guilde pointe vers ce main (reroll),
        --  - ou c’est la fiche du main lui-même (pas de note ou note vide)
        local belongsToMain =
            (rowMainKey and rowMainKey == mainKey)
            or ((rowMainKey == nil or rowMainKey == "") and rowNameKey == mainKey)

        if belongsToMain then
            if gr.online then anyOnline = true end
            local d = gr.online and 0 or tonumber(gr.daysDerived)
            local h = gr.online and 0 or tonumber(gr.hoursDerived)
            if d ~= nil then minDays  = (minDays  == nil or d < minDays)  and d or minDays end
            if h ~= nil then minHours = (minHours == nil or h < minHours) and h or minHours end
        end
    end

    info.online = anyOnline
    info.days   = minDays
    info.hours  = minHours

    return info
end

-- Gestion robuste du solde : accepte soit l'objet "data" de ligne, soit un nom de joueur (string)
local function GetSolde(data)
    -- Si on reçoit directement le nom du joueur (string), lire le solde depuis la DB
    if type(data) == "string" then
        return (GLOG.GetSolde and GLOG.GetSolde(data)) or 0
    end

    -- Si on reçoit l'objet de données (table) de la ligne
    if type(data) == "table" then
        if data.solde ~= nil then
            return tonumber(data.solde) or 0
        end
        local cr = tonumber(data.credit) or 0
        local db = tonumber(data.debit) or 0
        return cr - db
    end

    -- Par défaut
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

local function AttachDeleteHandler(btn, name, isMaster)
    btn:SetScript("OnClick", function()
        if not isMaster then return end
        UI.PopupConfirm(Tr("prefix_delete")..(name or "").." "..Tr("lbl_from_roster_question"), function()
            if GLOG.RemovePlayer then
                GLOG.RemovePlayer(name)
            elseif GLOG.BroadcastRosterRemove then
                local uid = (GLOG.GetUID and GLOG.GetUID(name)) or nil
                GLOG.BroadcastRosterRemove(uid or name)
            end
            if ns.RefreshAll then ns.RefreshAll() end
        end)
    end)
end

-- BuildRow
local function BuildRow(r, context)
    local f = {}
    f.lvl   = UI.Label(r, { justify = "CENTER" })
    f.alias = UI.Label(r, { justify = "LEFT"  })
    f.name  = UI.CreateNameTag(r)
    f.ilvl  = UI.Label(r, { justify = "CENTER" })
    f.mkey  = UI.Label(r, { justify = "LEFT"  })
    f.last  = UI.Label(r, { justify = "CENTER" })
    f.solde = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")

    -- Conteneur d’actions
    f.act = CreateFrame("Frame", nil, r)
    f.act:SetHeight(UI.ROW_H)
    f.act:SetFrameLevel(r:GetFrameLevel()+1)

    -- Actions financières (inchangé)
    r.btnDeposit  = UI.Button(f.act, Tr("btn_deposit_gold"),   { size="sm", minWidth=60 })
    r.btnWithdraw = UI.Button(f.act, Tr("btn_withdraw_gold"),  { size="sm", variant="ghost", minWidth=60 })

    -- Alignement des actions sur la droite
    UI.AttachRowRight(f.act, { r.btnDeposit, r.btnWithdraw, r.btnReserve, r.btnRoster }, 8, -4, { leftPad = 8, align = "center" })

    -- ✨ surlignage si même groupe/sous-groupe de raid
    if not r._highlight then
        local hl = r:CreateTexture(nil, "BACKGROUND")
        hl:SetAllPoints(r)
        hl:SetColorTexture(1, 0.90, 0, 0.08) -- jaune très léger
        hl:Hide()
        r._highlight = hl
    end

    return f
end

-- UpdateRow
local function UpdateRow(i, r, f, data)
    UI.SetNameTag(f.name, data.name or "")

    if f.alias then
        local a = (GLOG.GetAliasFor and GLOG.GetAliasFor(data.name)) or ""
        if a and a ~= "" then
            f.alias:SetText(a)
        else
            f.alias:SetText("")
        end
    end

    local gi = FindGuildInfo(data.name)

    if f.last then
        if gi.online then
            f.last:SetText("|cff40ff40"..Tr("status_online").."|r")
        elseif gi.days or gi.hours then
            f.last:SetText(ns.Format.LastSeen(gi.days, gi.hours))
        else
            f.last:SetText("|cffaaaaaa"..Tr("status_empty").."|r")
        end
    end

    if f.lvl then
        if gi.level and gi.level > 0 then
            -- Colorise comme l’écart de niveau de WoW
            f.lvl:SetText( (UI and UI.ColorizeLevel) and UI.ColorizeLevel(gi.level) or tostring(gi.level) )
        else
            f.lvl:SetText("")
        end
    end

    -- 🔧 M+ : afficher la clé en grisé pour les joueurs déconnectés s'ils en ont une
    if f.mkey then
        local mkeyTxt = (GLOG.GetMKeyText and GLOG.GetMKeyText(data.name)) or ""
        if gi.online then
            f.mkey:SetText(mkeyTxt or "")
        else
            if mkeyTxt ~= "" then
                f.mkey:SetText("|cffaaaaaa"..mkeyTxt.."|r")
            else
                f.mkey:SetText("|cffaaaaaa"..Tr("status_empty").."|r")
            end
        end
    end

    -- 🔧 iLvl : même logique que M+ — afficher l'ilvl en grisé si hors-ligne et connu
    if f.ilvl then
        local ilvl = (GLOG.GetIlvl and GLOG.GetIlvl(data.name)) or nil
        if gi.online then
            if ilvl and ilvl > 0 then
                f.ilvl:SetText(tostring(ilvl))
            else
                f.ilvl:SetText("|cffaaaaaa"..Tr("status_unknown").."|r")
            end
        else
            if ilvl and ilvl > 0 then
                f.ilvl:SetText("|cffaaaaaa"..tostring(ilvl).."|r")
            else
                f.ilvl:SetText("|cffaaaaaa"..Tr("status_empty").."|r")
            end
        end
    end

    -- ✨ Surlignage : même groupe (party) ou même sous-groupe de raid que moi
    if r._highlight then
        local hl = false
        if GLOG.IsInMySubgroup and GLOG.IsInMySubgroup(data.name) then
            hl = true
        end
        if hl then r._highlight:Show() else r._highlight:Hide() end
    end

    f.solde:SetText(money(GetSolde(data.name)))

    -- Autorisations & boutons
    local isSelf, isMaster = CanActOn(data.name)
    local canAct           = (isMaster or isSelf)       -- GM = tout voir/tout faire ; sinon soi-même

    if r.btnDeposit then
        r.btnDeposit:SetShown(canAct)                   -- ✅ masquer si non autorisé
        AttachDepositHandler(r.btnDeposit, data.name, canAct, isMaster)
    end
    if r.btnWithdraw then
        r.btnWithdraw:SetShown(canAct)                  -- ✅ masquer si non autorisé
        AttachWithdrawHandler(r.btnWithdraw, data.name, canAct, isMaster)
    end

    -- Recalcule l’alignement de la barre d’actions (ignore les boutons masqués)
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
        reserveToggleBtn:SetText(reserveCollapsed and "+" or "-")

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

    -- ➕ Affichage conditionnel du bouton "Afficher joueurs masqués" (GM uniquement)
    if _btnShowHiddenReserve then
        local isGM = (GLOG.IsMaster and GLOG.IsMaster()) and true or false
        local showBtn = (not reserveCollapsed) and isGM
        _btnShowHiddenReserve:SetShown(showBtn)

        -- Quand on replie la réserve, on réactive le masquage
        if reserveCollapsed and _showHiddenReserve then
            _showHiddenReserve = false
            if ns.RefreshAll then ns.RefreshAll() end
        end
    end
    
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
end

-- Footer
local function BuildFooterButtons(footer, isGM)
    local btnGuild
    local btnHist  = UI.Button(footer, Tr("btn_raids_history"), { size="sm", minWidth=160 })

    -- ➕ Bouton "Afficher joueurs masqués" (GM uniquement, rendu visible selon l'état de la réserve)
    if isGM then
        _btnShowHiddenReserve = UI.Button(footer, Tr("btn_show_hidden_reserve"), { size="sm", minWidth=200 })
        _btnShowHiddenReserve:SetOnClick(function()
            _showHiddenReserve = true
            if ns.RefreshAll then ns.RefreshAll() end
        end)
        _btnShowHiddenReserve:Hide() -- rendu visible par UpdateReserveCollapseUI
    end

    if isGM then
        btnGuild = UI.Button(footer, Tr("add_guild_member"), { size="sm", minWidth=220 })
        btnGuild:SetOnClick(function()
            if UI.ShowGuildRosterPopup then UI.ShowGuildRosterPopup() end
        end)
        if UI.AttachButtonsFooterRight then
            UI.AttachButtonsFooterRight(footer, { btnHist, btnGuild, _btnShowHiddenReserve })
        end
    else
        if UI.AttachButtonsFooterRight then
            UI.AttachButtonsFooterRight(footer, { btnHist })
        end
    end

    btnHist:SetOnClick(function()
        UI.ShowTabByLabel(Tr("tab_history"))
    end)
end

-- Build panel
local function Build(container)
    panel = container
    if UI.ApplySafeContentBounds then UI.ApplySafeContentBounds(panel) end

    activeArea  = CreateFrame("Frame", nil, panel)
    reserveArea = CreateFrame("Frame", nil, panel)

    UI.SectionHeader(activeArea,  Tr("lbl_active_roster"),      { topPad = 2 })
    -- L’entête de la réserve garde un padding à gauche pour le petit bouton +/-
    UI.SectionHeader(reserveArea, Tr("lbl_reserved_players"),   { topPad = 2, padLeft = 18 })

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
                local isMaster = GLOG.IsMaster and GLOG.IsMaster()
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
                local isMaster = GLOG.IsMaster and GLOG.IsMaster()
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

    footer = UI.CreateFooter(panel, 36)
    totalFS = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    totalFS:SetPoint("LEFT", footer, "LEFT", PAD, 0)

    local isGM = GLOG.IsMaster and GLOG.IsMaster()
    BuildFooterButtons(footer, isGM)

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
local _GL_RosterGroupWatcher = CreateFrame("Frame")
_GL_RosterGroupWatcher:RegisterEvent("GROUP_ROSTER_UPDATE")
_GL_RosterGroupWatcher:SetScript("OnEvent", function()
    if Refresh then Refresh() end
end)

UI.RegisterTab(Tr("tab_roster"), Build, Refresh, Layout)
