local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI, F = ns.GLOG, ns.UI, ns.Format
local PAD = UI.OUTER_PAD

local panel, lv, footer

-- Rafraîchit immédiatement la popup (si ouverte) et l'UI globale
local function RefreshAllViews()
    if ns and ns.UI and ns.UI._rosterPopupUpdater then ns.UI._rosterPopupUpdater() end
    if ns and ns.RefreshAll then ns.RefreshAll() end
end

-- Helper : passage en réserve SANS confirmation (action immédiate)
local function _AttachDeleteHandler(btn, name, isMaster)
    btn:SetScript("OnClick", function()
        if not isMaster then return end

        -- ✅ On ne supprime pas l'entrée: on passe le joueur en réserve (immédiat)
        if GLOG.GM_SetReserved then
            GLOG.GM_SetReserved(name, true)   -- bascule + broadcast (GM only)
        elseif GLOG.SetReserve then
            -- rétro-compat très ancienne éventuelle
            GLOG.SetReserve(name, true)
        end

        -- Bascule instantanée du bouton -> "Ajouter au roster"
        if btn and btn.SetText and btn.SetOnClick then
            btn:SetText(Tr("btn_add_to_roster"))
            btn:SetOnClick(function()
                -- ➕ Sort de la réserve (reserve=false)
                if GLOG.GM_SetReserved then
                    GLOG.GM_SetReserved(name, false)
                elseif GLOG.SetReserve then
                    GLOG.SetReserve(name, false)
                end
                -- Re-bascule le bouton en "Retirer du roster"
                btn:SetText(Tr("btn_remove_from_roster"))
                _AttachDeleteHandler(btn, name, isMaster)
                RefreshAllViews()
            end)
        end

        if ns and ns.UI and ns.UI._rosterPopupUpdater then ns.UI._rosterPopupUpdater() end
        if ns and ns.RefreshAll then ns.RefreshAll() end
    end)
end

-- Colonnes normalisées
local cols = UI.NormalizeColumns({
    { key="alias",    title=Tr("col_alias"),     w=80 },
    { key="main",     title=Tr("col_player"),    min=180, flex=1 },
    { key="last",     title=Tr("col_last_seen"), w=100 },
    { key="count",    title=Tr("col_rerolls"),   w=60 },
    { key="ver",      title=Tr("col_version"),   w=90, justify="CENTER" }, -- ➕ Version après Rerolls
    { key="actAlias", title="",                  w=90 },
    { key="act",      title="",                  w=240 },
})

-- Construction d’une ligne
local function BuildRow(r)
    local f = {}

    -- Widgets pour "data"
    f.alias = UI.Label(r)
    f.main  = UI.CreateNameTag(r)
    f.last  = UI.Label(r, { justify = "CENTER" })
    f.count = UI.Label(r)
    f.ver = UI.Label(r, { justify = "CENTER" })

    -- Colonne d’actions ROSTER (un seul bouton toggle + un bouton supprimer réservé aux hors-guilde)
    f.act        = CreateFrame("Frame", nil, r); f.act:SetHeight(UI.ROW_H)
    f.btnToggle  = UI.Button(f.act, Tr("btn_add_to_roster"), { size="sm", minWidth=120, debounce=0.15 })
    f.btnDelete  = UI.Button(f.act, "X", { size="xs", variant="danger", minWidth=24, debounce=0.15 })

    -- Colonne « actions alias » séparée pour garder l’ergonomie précédente
    f.actAlias   = CreateFrame("Frame", nil, r); f.actAlias:SetHeight(UI.ROW_H)
    f.btnAlias   = UI.Button(f.actAlias, Tr("btn_set_alias"), { size="sm", variant="ghost", minWidth=80 })

    -- Placement dans les colonnes
    UI.AttachRowRight(f.act,      { f.btnToggle, f.btnDelete }, 6, -4, { leftPad = 8, align = "center" })
    UI.AttachRowRight(f.actAlias, { f.btnAlias }, 8, -4, { leftPad = 8, align = "center" })

    -- Widgets pour "sep"
    f.sepBG = r:CreateTexture(nil, "BACKGROUND"); f.sepBG:Hide()
    f.sepBG:SetColorTexture(0.18, 0.18, 0.22, 0.6)

    -- ✅ Padding haut de 10px (centralisé via UI.GetSeparatorTopPadding)
    local pad = (UI.GetSeparatorTopPadding and UI.GetSeparatorTopPadding()) or 10
    f.sepBG:ClearAllPoints()
    f.sepBG:SetPoint("TOPLEFT",     r, "TOPLEFT",     0, -pad)
    f.sepBG:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 2,  0)

    f.sepTop = r:CreateTexture(nil, "BORDER"); f.sepTop:Hide()
    f.sepTop:SetColorTexture(0.9, 0.8, 0.2, 0.9)
    f.sepTop:ClearAllPoints()
    f.sepTop:SetPoint("TOPLEFT",  f.sepBG, "TOPLEFT",  0, 1)
    f.sepTop:SetPoint("TOPRIGHT", f.sepBG, "TOPRIGHT", 0, 1)
    f.sepTop:SetHeight(2)

    f.sepLabel = r:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge"); f.sepLabel:Hide()
    f.sepLabel:SetTextColor(1, 0.95, 0.3)

    return f
end

-- Mise à jour d’une ligne
local function UpdateRow(i, r, f, it)
    local isSep = (it.kind == "sep")

    -- ===== Séparateur de section =====
    f.sepBG:SetShown(isSep); f.sepTop:SetShown(isSep); f.sepLabel:SetShown(isSep)
    if isSep then
        -- vider les cellules de données + masquer actions
        if f.main and f.main.text then f.main.text:SetText("") end
        if f.alias then f.alias:SetText("") end
        if f.last then f.last:SetText("") end
        if f.count then f.count:SetText("") end
        if f.act then f.act:Hide() end
        if f.actAlias then f.actAlias:Hide() end

        f.sepLabel:ClearAllPoints()
        f.sepLabel:SetPoint("LEFT", r, "LEFT", 8, 0)
        f.sepLabel:SetText(tostring(it.label or ""))

        return
    end

    -- ===== Ligne de données =====
    if f.sepLabel then f.sepLabel:SetText("") end
    if f.act then f.act:Show() end
    if f.actAlias then f.actAlias:Show() end

    local name = tostring(it.main or "")
    -- Nom + classe
    if f.main then ns.UI.SetNameTag(f.main, name) end

    -- Alias textuel
    if f.alias then
        local key   = ns.GLOG.NormName and ns.GLOG.NormName(name)
        local alias = key and GuildLogisticsDB and GuildLogisticsDB.aliases and GuildLogisticsDB.aliases[key]
        f.alias:SetText(alias or "")
    end

    -- Compteur de rerolls
    if f.count then f.count:SetText(it.count or 0) end

    if f.ver then
        local name = tostring(it.main or "")
        local ver  = (ns.GLOG.GetPlayerAddonVersion and ns.GLOG.GetPlayerAddonVersion(name)) or ""
        f.ver:SetText((ver ~= "" and ver) or "—")
    end

    -- Statut "hors guilde" (section dédiée)
    local isOut = (it.outOfGuild == true)

    -- Colonne "Dernière connexion" / en ligne
    if isOut then
        if f.last then f.last:SetText("|cff909090—|r") end
    elseif it.onlineCount and it.onlineCount > 0 then
        local txt = (it.onlineCount > 1)
            and ("|cff40ff40"..Tr("status_online").." ("..it.onlineCount..")|r")
            or  ("|cff40ff40"..Tr("status_online").."|r")
        if f.last then f.last:SetText(txt) end
    else
        if f.last then f.last:SetText(ns.Format.LastSeen(it.days or it.lastSeenDays, it.hours or it.lastSeenHours)) end
    end

    -- ===== Actions =====
    local canGM = (ns.GLOG.IsMaster and ns.GLOG.IsMaster()) or false

    -- Détermine le nom complet (Nom-Royaume) si besoin pour interroger la DB
    local fullName = (EnsureFullMain and EnsureFullMain(it)) or name

    -- "Dans le roster" = présent dans la DB ET pas en réserve
    local isReserved = (ns.GLOG.IsReserved and (ns.GLOG.IsReserved(fullName) or ns.GLOG.IsReserved(name))) or false
    local inRoster  = ((ns.GLOG.HasPlayer and (ns.GLOG.HasPlayer(fullName) or ns.GLOG.HasPlayer(name))) and not isReserved) or false

    -- Bouton alias (toujours affiché)
    if f.btnAlias then
        f.btnAlias:SetShown(true)
        f.btnAlias:SetOnClick(function()
            ns.UI.PopupPromptText(Tr("popup_set_alias_title"), Tr("lbl_alias"), function(val)
                if ns.GLOG.GM_SetAlias then ns.GLOG.GM_SetAlias(name, val) end
                RefreshAllViews()
            end, { strata = "FULLSCREEN_DIALOG" })
        end)
    end

    -- Bouton Add / Remove (toggle)
    if f.btnToggle then
        if isOut or not canGM then
            f.btnToggle:Hide()
        else
            f.btnToggle:Show()
            if not inRoster then
                -- ➕ Ajouter au roster => sort le joueur de la réserve (reserve=false)
                f.btnToggle:SetText(Tr("btn_add_to_roster"))
                f.btnToggle:SetOnClick(function()
                    if ns.GLOG.GM_SetReserved then
                        ns.GLOG.GM_SetReserved(fullName, false)
                    elseif ns.GLOG.SetReserve then
                        ns.GLOG.SetReserve(fullName, false)
                    end
                    f.btnToggle:SetText(Tr("btn_remove_from_roster"))
                    _AttachDeleteHandler(f.btnToggle, fullName, canGM)
                    RefreshAllViews()
                end)
            else
                -- ➖ Retirer du roster => passe le joueur en réserve (reserve=true)
                f.btnToggle:SetText(Tr("btn_remove_from_roster"))
                _AttachDeleteHandler(f.btnToggle, fullName, canGM)
            end
        end
    end

    -- Bouton supprimer : uniquement pour les joueurs hors guilde (et GM)
    if f.btnDelete then
        if isOut and canGM then
            f.btnDelete:Show()
            f.btnDelete:SetOnClick(function()
                UI.PopupConfirm(Tr("confirm_delete") or "Supprimer ?", function()
                    ns.GLOG.RemovePlayer(fullName)
                    RefreshAllViews()
                end, nil, { strata = "FULLSCREEN_DIALOG", enforceAction = true })
            end)
        else
            f.btnDelete:Hide()
        end
    end

    -- Relayout des groupes d’actions si nécessaire
    if f.actAlias and f.actAlias._applyRowActionsLayout then f.actAlias._applyRowActionsLayout() end
    if f.act      and f.act._applyRowActionsLayout      then f.act._applyRowActionsLayout()      end
end

-- Construit un nom complet "Nom-Realm" pour l'affichage/ajout roster
local function EnsureFullMain(e)
    local m = tostring((e and e.main) or "")
    if m:find("-", 1, true) then return m end

    -- Cherche le royaume à partir des lignes scannées de la guilde
    local rows = (GLOG and GLOG.GetGuildRowsCached and GLOG.GetGuildRowsCached()) or {}
    for _, r in ipairs(rows) do
        local amb = r.name_amb or r.name_raw
        if amb and GLOG.NormName and GLOG.NormName(amb) == e.key then
            local raw = r.name_raw or amb
            local realm = tostring(raw or ""):match("^[^-]+%-(.+)$")
            if realm and realm ~= "" then
                return m .. "-" .. realm
            end
        end
    end

    -- Secours : royaume du joueur local
    if UnitFullName then
        local _, myRealm = UnitFullName("player")
        if myRealm and myRealm ~= "" then
            return m .. "-" .. myRealm
        end
    end
    return m
end

-- Regroupe les entrées (actifs / anciens) puis produit la liste (avec séparateurs)
local function buildItemsFromAgg(agg)
    -- Séparation < 30j / ≥ 30j
    local actives, olds = {}, {}
    for _, e in ipairs(agg or {}) do
        local d = tonumber(e.days) or 999999
        if d < 30 then table.insert(actives, e) else table.insert(olds, e) end
    end
    table.sort(actives, function(a,b) return tostring(a.main):lower() < tostring(b.main):lower() end)
    table.sort(olds,    function(a,b) return tostring(a.main):lower() < tostring(b.main):lower() end)

    local items = {}

    if #actives > 0 then
        table.insert(items, { kind="sep", label=Tr("lbl_recent_online") })
        for _, e in ipairs(actives) do
            table.insert(items, {
                kind="data",
                main=e.main, key=e.key,
                days=e.days, hours=e.hours,
                count=e.count, onlineCount=e.onlineCount,
            })
        end
    end

    if #olds > 0 then
        table.insert(items, { kind="sep", label=Tr("lbl_old_online") })
        for _, e in ipairs(olds) do
            table.insert(items, {
                kind="data",
                main=e.main, key=e.key,
                days=e.days, hours=e.hours,
                count=e.count, onlineCount=e.onlineCount,
            })
        end
    end

    -- Ajout : joueurs présents en DB locale mais absents de la guilde
    local guildSet = {}
    do
        local rows = (ns.GLOG.GetGuildRowsCached and ns.GLOG.GetGuildRowsCached()) or {}
        for _, r in ipairs(rows) do
            local amb = r.name_amb or r.name_raw
            local k = amb and (ns.GLOG.NormName and ns.GLOG.NormName(amb)) or nil
            if k and k ~= "" then guildSet[k] = true end
        end
    end

    local outs, seen = {}, {}
    do
        local arr = (ns.GLOG.GetPlayersArray and ns.GLOG.GetPlayersArray()) or {}
        for _, rec in ipairs(arr) do
            local n = rec.name
            local k = n and (ns.GLOG.NormName and ns.GLOG.NormName(n)) or nil
            if k and not guildSet[k] and not seen[k] then
                table.insert(outs, { main = n, key = k })
                seen[k] = true
            end
        end
    end
    table.sort(outs, function(a,b) return tostring(a.main):lower() < tostring(b.main):lower() end)

    if #outs > 0 then
        table.insert(items, { kind="sep", label=Tr("lbl_out_of_guild") })
        for _, e in ipairs(outs) do
            table.insert(items, {
                kind="data",
                main = e.main,
                count = 0,
                outOfGuild = true, -- drapeau UI (statut, actions)
            })
        end
    end

    if #items == 0 then
        table.insert(items, { kind="sep", label=Tr("lbl_no_player_found") })
    end
    return items
end

local function Layout()
    -- Rien à positionner au-dessus → on laisse ListView gérer
    lv:Layout()
end

local function Refresh()
    local need = (not GLOG.IsGuildCacheReady or not GLOG.IsGuildCacheReady())
    if not need and GLOG.GetGuildCacheTimestamp then
        local age = time() - GLOG.GetGuildCacheTimestamp()
        if age > 60 then need = true end
    end
    if need then
        lv:SetData({ {kind="sep", label=Tr("lbl_scan_roster_progress")} })
        GLOG.RefreshGuildCache(function()
            if ns and ns.UI and ns.UI._rosterPopupUpdater then ns.UI._rosterPopupUpdater() end
            if ns and ns.UI and ns.UI.RefreshAll then ns.UI.RefreshAll() end
        end)
        return
    end

    local items = buildItemsFromAgg(GLOG.GetGuildMainsAggregated())
    lv:SetData(items)
    lv:Layout()
end

local function Build(container)
    -- Création du conteneur
    panel, footer, footerH = UI.CreateMainContainer(container, {footer = true})

    -- Bouton "Ajouter un joueur" (dans le MÊME footer que "Close")
    btnAdd = UI.Button(footer, Tr("btn_add_player"), { size="sm", variant="primary", minWidth=120 })
    btnAdd:SetOnClick(function()
        -- Vérification GM au moment du clic (évite l'effet cache obsolète)
        local isGM = (GLOG.IsMaster and GLOG.IsMaster()) or false
        if not isGM then return end
        UI.PopupPromptText(Tr("btn_add_player"), Tr("prompt_external_player_name"), function(name)
            name = tostring(name or ""):gsub("^%s+",""):gsub("%s+$","")
            if name == "" then return end
            if GLOG.AddPlayer and GLOG.AddPlayer(name) then
                if RefreshAllViews then RefreshAllViews() end
            end
        end, { width = 460 })
    end)

    -- Ancrage à droite comme ailleurs ; le bouton "Close" reste géré par l'hôte
    if UI.AttachButtonsFooterRight then
        UI.AttachButtonsFooterRight(footer, { btnAdd })
    end

    -- Visibilité dynamique selon le statut GM
    local function updateAddVisibility()
        local isGM = (GLOG.IsMaster and GLOG.IsMaster()) or false
        btnAdd:SetShown(isGM)
    end
    updateAddVisibility()
    if panel and panel.HookScript then
        panel:HookScript("OnShow", updateAddVisibility)
    elseif panel and panel.SetScript and panel.GetScript and not panel:GetScript("OnShow") then
        panel:SetScript("OnShow", updateAddVisibility)
    end

    -- Liste au-dessus du footer hôte
    lv = UI.ListView(panel, cols, {
        buildRow = BuildRow,
        updateRow = UpdateRow,
        rowHeight = UI.ROW_H,
        rowHeightForItem = function(item) return (item.kind == "sep") and (UI.ROW_H + 10) or UI.ROW_H end,
        bottomAnchor = footer,
    })
end


-- Popup roster à largeur dynamique + auto-refresh à la fin du scan
function UI.ShowGuildRosterPopup()
    local dlg = UI.CreatePopup({ title = Tr("add_guild_member"), height = 670 })

    -- Largeur mini des colonnes + scrollbar + marges internes
    local sb  = (UI.SCROLLBAR_W or 20) + (UI.SCROLLBAR_INSET or 0)
    local cMin = (UI.MinWidthForColumns and UI.MinWidthForColumns(cols)) or (function()
        local s=0; for _,c in ipairs(cols or {}) do s = s + (c.w or c.min or 80) end; return s+8
    end)()
    local innerMargins = 24
    local wantedDlgW  = cMin + sb + innerMargins
    local screenMax   = math.floor((UIParent and UIParent:GetWidth() or 1280) - 80)
    local finalW      = math.min(wantedDlgW, screenMax)
    dlg:SetWidth(finalW)
    if dlg.SetResizeBounds then dlg:SetResizeBounds(finalW, 220) end

    -- ListView
    local pv = UI.ListView(dlg.content, cols, {
        buildRow = BuildRow,
        updateRow = UpdateRow,
        rowHeight = UI.ROW_H,
        rowHeightForItem = function(item) return (item.kind == "sep") and (UI.ROW_H + 10) or UI.ROW_H end,
    })

    -- Fonction d’update spécifique à la popup (utilisée par le callback du scan)
    local function updatePopup()
        if not dlg or not dlg:IsShown() then return end
        local need = not (GLOG.IsGuildCacheReady and GLOG.IsGuildCacheReady())
        if not need and GLOG.GetGuildCacheTimestamp then
            local age = time() - GLOG.GetGuildCacheTimestamp()
            if age > 60 then need = true end
        end

        if need then
            pv:SetData({ {kind="sep", label=Tr("lbl_scan_roster_progress")} })
            GLOG.RefreshGuildCache(updatePopup)
        else
            local data = buildItemsFromAgg(GLOG.GetGuildMainsAggregated())
            pv:SetData(data)
        end
    end

    -- Expose l’update pour un refresh externe
    ns.UI = ns.UI or {}
    ns.UI._rosterPopupUpdater = updatePopup

    -- Premier affichage
    local need = not (GLOG.IsGuildCacheReady and GLOG.IsGuildCacheReady())
    if not need and GLOG.GetGuildCacheTimestamp then
        local age = time() - GLOG.GetGuildCacheTimestamp()
        if age > 60 then need = true end
    end

    if need then
        pv:SetData({ {kind="sep", label=Tr("lbl_scan_roster_progress")} })
        GLOG.RefreshGuildCache(updatePopup)
    else
        updatePopup()
    end

    -- Footer: Close + (optionnel) Ajouter un joueur comme dans l'onglet Joueurs
    local isGM = (GLOG.IsMaster and GLOG.IsMaster()) or false
    local btns = {}
    table.insert(btns, { text = CLOSE, default = true })
    if isGM then
        table.insert(btns, {
            text    = "btn_add_player",
            variant = "primary",
            width   = 140,
            close   = false, -- ne pas fermer la popup
            onClick = function()
                UI.PopupPromptText(Tr("btn_add_player"), Tr("prompt_external_player_name"), function(name)
                    name = tostring(name or ""):gsub("^%s+",""):gsub("%s+$","")
                    if name == "" then return end
                    if GLOG.AddPlayer and GLOG.AddPlayer(name) then
                        -- Rafraîchir la popup + l'UI globale
                        if ns and ns.UI and ns.UI._rosterPopupUpdater then ns.UI._rosterPopupUpdater() end
                        if ns and ns.RefreshAll then ns.RefreshAll() end
                    end
                end, { width = 460 })
            end,
        })
    end
    dlg:SetButtons(btns)
    dlg:Show()
end

-- Nouvel onglet "Gestion des membres" dans la catégorie Raids
UI.RegisterTab(Tr("add_guild_member"), Build, Refresh, Layout, {
    -- Comme auparavant le bouton n'était visible que pour le GM, on garde la visibilité conditionnelle :
    hidden   = not (GLOG.IsMaster and GLOG.IsMaster()),
    category = Tr("cat_raids"),
})
