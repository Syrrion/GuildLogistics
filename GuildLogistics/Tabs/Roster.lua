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
    { key="alias",  title=Tr("col_alias"),          w=90, justify="LEFT" },
    { key="lvl",    title=Tr("col_level_short"),    w=44, justify="CENTER" },
    { key="name",   title=Tr("col_name"),           min=200, flex=1 },
    { key="ilvl",   title=Tr("col_ilvl"),           w=120, justify="CENTER" },
    { key="last",   title=Tr("col_attendance"),     w=120 },
    { key="act",    title="",                       w=120 },
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

-- Retourne des infos d'agrégation par MAIN + le reroll en ligne (nom + classe)
function FindGuildInfo(playerName)
    local guildRows = (GLOG.GetGuildRowsCached and GLOG.GetGuildRowsCached()) or {}
    local NormName = GLOG.NormName
    if not playerName or playerName == "" then return {} end

    -- Détermine le main affiché et sa clé
    local mainName = (GLOG.GetMainOf and GLOG.GetMainOf(playerName)) or playerName
    local mainKey  = NormName and NormName(mainName)
    local mainBase = (tostring(mainName):match('^([^%-]+)') or tostring(mainName))

    local info = {}

    -- Conserve idx/level du main uniquement (ne pas toucher aux autres éléments)
    for _, gr in ipairs(guildRows) do
        local rowKey = (gr.name_key) or (NormName and NormName(gr.name_amb or gr.name_raw))
        if rowKey == mainKey then
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
        local rowNameKey = (gr.name_key) or ((NormName and NormName(gr.name_amb or gr.name_raw)) or nil)
        local rowMainKey = gr.main_key or ((gr.remark and NormName and NormName(strtrim(gr.remark))) or nil)

        -- Appartenance au même main
        local belongsToMain =
            (rowMainKey and rowMainKey == mainKey)
            or ((rowMainKey == nil or rowMainKey == "") and rowNameKey == mainKey)

        if belongsToMain then
            if gr.online then anyOnline = true end

            -- Si un reroll (différent du main) est en ligne, capture son nom + classe
            if gr.online then
                local full = gr.name_amb or gr.name_raw or ""
                local base = tostring(full):match("^([^%-]+)") or tostring(full)
                if base ~= "" and base:lower() ~= tostring(mainBase or ""):lower() then
                    info.onlineAltBase = base      -- "Altruis"
                    info.onlineAltFull = full      -- "Altruis-KirinTor"
                    info.onlineAltIdx  = gr.idx

                    -- Classe du reroll via roster guilde
                    local classTag = nil
                    if GetGuildRosterInfo and gr.idx then
                        classTag = select(11, GetGuildRosterInfo(gr.idx))  -- classFileName (ex: "DEMONHUNTER")
                    end
                    -- Fallbacks éventuels selon votre cache
                    classTag = classTag or gr.classFile or gr.classTag or gr.class
                    info.onlineAltClassTag = classTag
                end
            end

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
-- Construit une ligne de la ListView (actifs/réserve)
local function BuildRow(r, context)
    local f = {}
    f.lvl   = UI.Label(r, { justify = "CENTER" })
    f.alias = UI.Label(r, { justify = "LEFT"  })
    f.name  = UI.CreateNameTag(r)
    f.ilvl  = UI.Label(r, { justify = "CENTER" })
    f.mplus = UI.Label(r, { justify = "CENTER" })
    f.mkey  = UI.Label(r, { justify = "LEFT"  })
    f.last  = UI.Label(r, { justify = "CENTER" })
    -- ➕ cellule "Version"
    f.ver   = UI.Label(r, { justify = "CENTER" })
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
    UI.AttachRowRight(f.act, { r.btnDeposit }, 8, -4, { leftPad = 8, align = "center" })

    return f
end

-- UpdateRow
local function UpdateRow(i, r, f, data)
    local GHX = (UI and UI.GRAY_OFFLINE_HEX) or "999999"
    local function gray(t) return "|cff"..GHX..tostring(t).."|r" end

    -- Nom (icône/couleur main gérés par CreateNameTag / SetNameTag)
    UI.SetNameTag(f.name, data.name or "")

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

    -- 🎨 Colonne Nom : masque le royaume + ajoute (icône + NomReroll) en gris avec couleur/icone de classe
    do
        local function classIconMarkup(classTag, size)
            size = size or 14
            if not classTag or classTag == "" then return "" end
            local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classTag]
            if not coords then return "" end
            local w, h = size, size
            return ("|TInterface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES:%d:%d:0:0:256:256:%d:%d:%d:%d|t")
                :format(w, h, coords[1]*256, coords[2]*256, coords[3]*256, coords[4]*256)
        end

        local name = data.name or ""
        local mainKey = (ns.Util and ns.Util.NormName) and ns.Util.NormName(name) or name
        local baseText = (gi and gi.base) or name
        local altNameColored, altClass = (gi and gi.onlineAltName) or "", (gi and gi.onlineAltClass) or nil

        if altNameColored ~= "" then
            local icon = classIconMarkup(altClass, 14)
            local altPart = ("|cffaaaaaa(|r%s%s|cffaaaaaa)|r"):format((icon ~= "" and (icon .. " ") or ""), altNameColored)
            baseText = baseText .. " " .. altPart
        end

        if f.name and f.name.text then
            f.name.text:SetText(baseText)
        end
    end

    -- ➕ Liseré "même groupe/sous-groupe"
    do
        local same = (GLOG.IsInMySubgroup and GLOG.IsInMySubgroup(data.name)) or false
        local st = (UI.GetListViewStyle and UI.GetListViewStyle()) or {}
        local c  = st.accent or { r = 1, g = 0.82, b = 0.00, a = 0.90 }
        if UI.SetRowAccent then UI.SetRowAccent(r, same, c.r, c.g, c.b, c.a) end
    end

    -- Présence
    if f.last then
        if gi.online then
            f.last:SetText("|cff40ff40"..Tr("status_online").."|r")
        elseif gi.days or gi.hours then
            f.last:SetText(ns.Format.LastSeen(gi.days, gi.hours))
        else
            f.last:SetText(gray(Tr("status_empty")))
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

    -- Score M+
    if f.mplus then
        local score = (GLOG.GetMPlusScore and GLOG.GetMPlusScore(data.name)) or nil
        if gi.online then
            f.mplus:SetText(score and score > 0 and tostring(score) or gray(Tr("status_empty")))
        else
            f.mplus:SetText(score and score > 0 and gray(score) or gray(Tr("status_empty")))
        end
    end

    -- Clé M+
    if f.mkey then
        local mkeyTxt = (GLOG.GetMKeyText and GLOG.GetMKeyText(data.name)) or ""
        if gi.online then
            f.mkey:SetText(mkeyTxt or "")
        else
            f.mkey:SetText(mkeyTxt ~= "" and gray(mkeyTxt) or gray(Tr("status_empty")))
        end
    end

    -- iLvl
    if f.ilvl then
        local ilvl    = (GLOG.GetIlvl     and GLOG.GetIlvl(data.name))     or nil
        local ilvlMax = (GLOG.GetIlvlMax  and GLOG.GetIlvlMax(data.name))  or nil

        local function fmtOnline()
            if ilvl and ilvl > 0 then
                if ilvlMax and ilvlMax > 0 then
                    return tostring(ilvl).." ("..tostring(ilvlMax)..")"
                else
                    return tostring(ilvl)
                end
            else
                return gray(Tr("status_empty"))
            end
        end

        local function fmtOffline()
            if ilvl and ilvl > 0 then
                if ilvlMax and ilvlMax > 0 then
                    return gray(tostring(ilvl).." ("..tostring(ilvlMax)..")")
                else
                    return gray(tostring(ilvl))
                end
            else
                return gray(Tr("status_empty"))
            end
        end

        f.ilvl:SetText( gi.online and fmtOnline() or fmtOffline() )
    end

    -- ➕ Version Addon (si la colonne existe)
    if f.ver then
        local v = (GLOG.GetPlayerAddonVersion and GLOG.GetPlayerAddonVersion(data.name)) or ""
        if v == "" then
            f.ver:SetText(gray(Tr("status_empty")))
        else
            f.ver:SetText(gi.online and v or gray(v))
        end
    end
    
    -- Solde banque perso (si affiché)
    if f.solde then
        local balance = (GLOG.GetBalance and GLOG.GetBalance(data.name)) or 0
        f.solde:SetText((UI and UI.MoneyText) and UI.MoneyText(balance) or tostring(balance).." po")
    end
    f.solde:SetText(money(GetSolde(data.name)))

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
    -- ➕ Bouton "Afficher joueurs masqués" (GM uniquement, rendu visible selon l'état de la réserve)
    if isGM then
        _btnShowHiddenReserve = UI.Button(footer, Tr("btn_show_hidden_reserve"), { size="sm", minWidth=200 })
        _btnShowHiddenReserve:SetOnClick(function()
            _showHiddenReserve = true
            if ns.RefreshAll then ns.RefreshAll() end
        end)
        _btnShowHiddenReserve:Hide() -- rendu visible par UpdateReserveCollapseUI

        -- Aligne à droite uniquement ce bouton (suppression de "Gestion des membres")
        if UI.AttachButtonsFooterRight then
            UI.AttachButtonsFooterRight(footer, { _btnShowHiddenReserve })
        end
    else
        if UI.AttachButtonsFooterRight then
            UI.AttachButtonsFooterRight(footer)
        end
    end
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

UI.RegisterTab(Tr("tab_roster"), Build, Refresh, Layout, {
    category = Tr("cat_raids"),
})
