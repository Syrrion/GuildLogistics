local ADDON, ns = ...
local CDZ, UI = ns.CDZ, ns.UI
local PAD = UI.OUTER_PAD

-- Split vertical : joueurs en haut, lots en bas (sélection directe)
local panel, totalLabel, totalInput, closeBtn, lv, footer, histBtn
local topPane, lotsPane, lotsLV

local includes = {}
local chosenLots = {} -- [lotId]=true
local lotsDirty = true -- flag d’invalidation des lots

local cols = {
    { key="check", title="",      w=34,  justify="LEFT"  },
    { key="name",  title="Nom",   min=300, flex=1, justify="LEFT" },
    { key="solde", title="Solde", w=160, justify="LEFT"  },
    { key="after", title="Après", w=160, justify="LEFT"  },
}

-- ===== Utilitaires =====
local function SelectedCount()
    local n = 0
    for name, v in pairs(includes) do
        if v and CDZ.HasPlayer and CDZ.HasPlayer(name) then n = n + 1 end
    end
    return n
end

local function ComputePerHead()
    local total = tonumber(totalInput:GetText() or "0") or 0
    local selected = SelectedCount()
    return (selected > 0) and math.floor(total / selected) or 0
end

-- Gestion des événements : mise à jour des lots
if ns and ns.On then
    ns.On("lots:changed", function()
        lotsDirty = true
        if panel and panel:IsVisible() then
            if ns.RefreshActive then ns.RefreshActive() else if Refresh then Refresh() end end
        end
    end)
end


-- ===== ListView Joueurs =====
local function BuildRow(r)
    local f = {}
    f.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
    f.name  = UI.CreateNameTag(r)
    f.solde = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.after = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    return f
end

local function UpdateRow(i, r, f, d)
    if includes[d.name] == nil then includes[d.name] = true end
    f.check:SetChecked(includes[d.name])
    f.check:SetScript("OnClick", function(self) includes[d.name] = self:GetChecked() and true or false; ns.RefreshAll() end)
    UI.SetNameTag(f.name, d.name or "")
    local solde = (d.credit or 0) - (d.debit or 0)
    f.solde:SetText(UI.MoneyText(solde))
    local per = ComputePerHead()
    local isIncluded = includes[d.name] and true or false
    local after = isIncluded and (solde - per) or solde
    f.after:SetText(UI.MoneyText(after))
end

-- ===== ListView Lots =====
local function BuildRowLots(r)
    local f = {}
    f.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
    f.name  = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.frac  = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.gold  = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    return f
end

local function UpdateRowLots(i, r, f, it)
    local l = it.data
    local used = tonumber(l.used or 0) or 0
    local N    = tonumber(l.sessions or 1) or 1
    local remaining = math.max(0, N - used)
    local shareGold = (CDZ.Lot_ShareGold and CDZ.Lot_ShareGold(l)) or math.floor( (math.floor((tonumber(l.totalCopper or 0) or 0)/10000)) / N )
    f.name:SetText(l.name or ("Lot "..tostring(l.id)))
    f.frac:SetText((remaining).." rest.")
    f.gold:SetText(UI.MoneyText(shareGold))
    f.check:SetChecked(chosenLots[l.id] and true or false)
    f.check:SetScript("OnClick", function(self)
        chosenLots[l.id] = self:GetChecked() and true or nil
        local total = 0
        for id,_ in pairs(chosenLots) do
            local l2 = CDZ.Lot_GetById and CDZ.Lot_GetById(id)
            if l2 then
                local g = (CDZ.Lot_ShareGold and CDZ.Lot_ShareGold(l2)) or math.floor( (math.floor((tonumber(l2.totalCopper or 0) or 0)/10000)) / (tonumber(l2.sessions or 1) or 1) )
                total = total + (g or 0)
            end
        end
        if totalInput and totalInput.SetNumber then totalInput:SetNumber(total) end
        if ns.RefreshActive then ns.RefreshActive() end
    end)
end

-- ===== Layout / Refresh / Build =====
local function Layout()
    local pad = PAD
    if not panel or not panel.GetWidth then return end
    local W = panel:GetWidth() or 0
    local H = panel:GetHeight() or 0
    -- Si le panneau n'est pas encore dimensionné, on sort (évite les W/H=0 et les ancrages foireux)
    if W <= 0 or H <= 0 then return end

    local footerH = (footer and footer:GetHeight() or 0) + 6
    local availH = math.max(0, H - footerH - (pad*2))
    local topH   = math.floor(availH * 0.60)

    -- Zone lots (bas)
    lotsPane:ClearAllPoints()
    lotsPane:SetPoint("TOPLEFT",  panel, "TOPLEFT",  pad, -pad - topH - 6)
    lotsPane:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -pad, -pad - topH - 6)
    lotsPane:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", pad, pad + footerH)
    lotsPane:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -pad, pad + footerH)

    -- Zone joueurs (haut) : bornée entre le haut du panel et le haut de lotsPane
    topPane:ClearAllPoints()
    topPane:SetPoint("TOPLEFT",  panel,   "TOPLEFT",  pad, -pad)
    topPane:SetPoint("TOPRIGHT", panel,   "TOPRIGHT", -pad, -pad)
    topPane:SetPoint("BOTTOMLEFT", lotsPane, "TOPLEFT",  0,  6)
    topPane:SetPoint("BOTTOMRIGHT", lotsPane, "TOPRIGHT", 0,  6)


    -- Laisse chaque ListView recalculer sa hauteur en fonction de son anchor/bottomAnchor
    if lotsLV and lotsLV.Layout then lotsLV:Layout() end
    if lv and lv.Layout then lv:Layout() end
end


local function Refresh()
    -- ✅ seulement le roster ACTIF
    local players = (CDZ.GetPlayersArrayActive and CDZ.GetPlayersArrayActive()) or CDZ.GetPlayersArray()
    lv:SetData(players)

    local selectable = (CDZ.Lot_ListSelectable and CDZ.Lot_ListSelectable()) or {}
    local rows = {}; for _, l in ipairs(selectable) do rows[#rows+1] = { data = l } end
    lotsLV:SetData(rows)

    -- recalc montant global si des lots sont cochés
    local total = 0
    for id,_ in pairs(chosenLots) do
        local l = CDZ.Lot_GetById and CDZ.Lot_GetById(id)
        if l then
            local g = (CDZ.Lot_ShareGold and CDZ.Lot_ShareGold(l)) or 0
            total = total + (g or 0)
        end
    end
    if totalInput and totalInput.SetNumber then totalInput:SetNumber(total) end

    Layout()
end

local function Build(container)
    panel = container
    if UI.ApplySafeContentBounds then UI.ApplySafeContentBounds(panel, { side = 10, bottom = 6 }) end

    footer = UI.CreateFooter(panel, 36)

    totalLabel = footer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    totalLabel:SetText("Montant global (po) :")

    totalInput = CreateFrame("EditBox", nil, footer, "InputBoxTemplate")
    totalInput:SetAutoFocus(false); totalInput:SetNumeric(true); totalInput:SetSize(120, 28)
    totalInput:SetScript("OnTextChanged", function() ns.RefreshAll() end)

    closeBtn = UI.Button(footer, "Valider les participants", { size="sm", minWidth=220 })
    closeBtn:SetOnClick(function()
        local total = tonumber(totalInput:GetText() or "0") or 0
        local selected = {}
        for name, v in pairs(includes) do if v then table.insert(selected, name) end end
        table.sort(selected)
        local per = (#selected > 0) and math.floor(total / #selected) or 0

        local function sendBatch(silentFlag)
            local adjusts = {}
            for _, n in ipairs(selected) do
                adjusts[#adjusts+1] = { name = n, delta = -per }
            end
            -- Contexte lots compact pour la popup
            local Lctx = {}
            for id,_ in pairs(chosenLots) do
                local l = CDZ.Lot_GetById and CDZ.Lot_GetById(id)
                if l then
                    local used = tonumber(l.used or 0) or 0
                    local N    = tonumber(l.sessions or 1) or 1
                    local k    = used + 1
                    local g    = (CDZ.Lot_ShareGold and CDZ.Lot_ShareGold(l)) or math.floor( (math.floor((tonumber(l.totalCopper or 0) or 0)/10000)) / N )
                    Lctx[#Lctx+1] = { id = id, name = l.name or ("Lot " .. tostring(id)), k = k, N = N, n = 1, gold = g }
                end
            end

            if CDZ.GM_BroadcastBatch then
                CDZ.GM_BroadcastBatch(adjusts, { reason = "RAID_CLOSE", silent = silentFlag, L = Lctx })
            else
                -- fallback très anciens clients
                for _, a in ipairs(adjusts) do
                    if CDZ.GM_ApplyAndBroadcastEx then
                        CDZ.GM_ApplyAndBroadcastEx(a.name, a.delta, { reason = "RAID_CLOSE", silent = silentFlag, L = Lctx })
                    elseif CDZ.GM_ApplyAndBroadcast then
                        CDZ.GM_ApplyAndBroadcast(a.name, a.delta)
                    end
                end
            end

            -- Politique popups :
            -- - Notifier (non silencieux) : essayer le réseau, sinon fallback local après un court délai.
            -- - Valider (silencieux)     : popup locale immédiate (aucun envoi réseau).
            local meFull = (ns and ns.Util and ns.Util.playerFullName and ns.Util.playerFullName()) or UnitName("player")
            local myShort = (meFull and meFull:match("^(.-)%-.+$")) or (UnitName and UnitName("player")) or meFull
            local function isMe(name)
                if CDZ.SamePlayer then return CDZ.SamePlayer(name, meFull) end
                return string.lower(tostring(name or "")) == string.lower(tostring(meFull or ""))
            end
            local amISelected = false
            for _, n in ipairs(selected) do if isMe(n) then amISelected = true; break end end
            
            if silentFlag then
                -- Mode silencieux : aucune popup réseau -> montrer local si je suis débité
                if amISelected and ns.UI and ns.UI.PopupRaidDebit then
                    -- ✅ GM : le batch est déjà appliqué localement → on lit le solde actuel
                    local after = (CDZ.GetSolde and CDZ.GetSolde(meFull)) or 0
                    ns.UI.PopupRaidDebit(meFull, per, after, { L = Lctx })
                end
            else
                -- Mode notifié : pas de popup locale si la popup réseau arrive.
                if amISelected and C_Timer and C_Timer.After then
                    local seen = false
                    if ns and ns.On then
                        ns.On("raid:popup-shown", function(who)
                            if isMe(who) then seen = true end
                        end)
                    end
                    ns.Util.After(1.0, function()
                        if not seen and ns.UI and ns.UI.PopupRaidDebit then
                            -- ✅ Fallback GM : lit le solde réellement en DB (pas de re-soustraction)
                            local after = (CDZ.GetSolde and CDZ.GetSolde(meFull)) or 0
                            ns.UI.PopupRaidDebit(meFull, per, after, { L = Lctx })
                        end
                    end)
                end
            end

            -- Marque les lots comme consommés + journalise
            local ids = {}
            for id,_ in pairs(chosenLots) do ids[#ids+1] = id end
            table.sort(ids)

            if CDZ.Lots_ConsumeMany then
                CDZ.Lots_ConsumeMany(ids)   -- consommation locale (inclut la diffusion côté GM)
            else
                -- fallback très ancien Core
                if CDZ.Lot_Consume then for _, id in ipairs(ids) do CDZ.Lot_Consume(id) end end
            end
            -- (diffusion retirée : déjà gérée dans Lots_ConsumeMany pour le GM)

            local Hctx = {}
            for id,_ in pairs(chosenLots) do
                local l = CDZ.Lot_GetById and CDZ.Lot_GetById(id)
                if l then Hctx[#Hctx+1] = { id=id, name=l.name, k=(tonumber(l.used or 0) or 0), N=(tonumber(l.sessions or 1) or 1) } end
            end
            CDZ.AddHistorySession(total, per, selected, { lots = Hctx })
            chosenLots = {}

        end

        local dlg = UI.CreatePopup({ title = "Valider les participants", width = 520, height = 220 })
        dlg:SetMessage(("Vous allez débiter %d joueur(s) de %s chacun.")
            :format(#selected, UI.MoneyText(per)))
        dlg:SetButtons({
            { text = "Notifier les joueurs", default = true, onClick = function() sendBatch(false) end },
            { text = "Valider", onClick = function() sendBatch(true); if UI.ShowTabByLabel then UI.ShowTabByLabel("Historique") end end },
            { text = "Annuler", variant = "ghost" },
        })
        dlg:Show()
    end)

    -- Panneau supérieur (joueurs) avec padding identique à Ressources
    topPane = CreateFrame("Frame", nil, panel)

    -- Panneau lots (bas)
    lotsPane = CreateFrame("Frame", nil, panel)

    -- Titre + trait : joueurs participants (dans le conteneur paddé)
    UI.SectionHeader(topPane, "Joueurs participants")

    -- Liste des joueurs (haut), enfant de topPane
    lv = UI.ListView(topPane, cols, {
        buildRow   = BuildRow,
        updateRow  = UpdateRow,
        topOffset  = (UI.SECTION_HEADER_H or 26),
        bottomAnchor = lotsPane,  -- ✅ bornée juste au-dessus du panneau des lots
    })

    -- Titre + trait : lots utilisables
    local colsLots = UI.NormalizeColumns({
        { key="check", title="",    w=34 },
        { key="name",  title="Lot", min=260, flex=1 },
        { key="frac",  title="Restant", w=90 },
        { key="gold",  title="Montant",  w=120 },
    })

    -- Header + liste des lots
    UI.SectionHeader(lotsPane, "Lots utilisables")
    lotsLV = UI.ListView(lotsPane, colsLots, {
        buildRow = BuildRowLots,
        updateRow = UpdateRowLots,
        topOffset = (UI.SECTION_HEADER_H or 26),
        bottomAnchor = footer,
    })


    -- Alignement footer
    if UI.AttachButtonsFooterRight then
        UI.AttachButtonsFooterRight(footer, { closeBtn })
    end
end

UI.RegisterTab("Démarrer un raid", Build, Refresh, Layout, { hidden = not (CDZ.IsMaster and CDZ.IsMaster()) })
