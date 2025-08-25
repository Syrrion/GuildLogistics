local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns.GLOG, ns.UI
local PAD, SBW, GUT = UI.OUTER_PAD, UI.SCROLLBAR_W, UI.GUTTER

-- === Onglet "Membres de la guilde" : liste unique plein écran ===
local panel, lv, membersArea, noGuildMsg

-- Détecte si le personnage appartient à une guilde
local function _HasGuild()
    return (IsInGuild and IsInGuild()) and true or false
end

-- Affiche un message centré si aucune guilde, et masque la liste
local function _UpdateNoGuildUI()
    local hasGuild = _HasGuild()
    local showMsg = not hasGuild

    if noGuildMsg then noGuildMsg:SetShown(showMsg) end
    if membersPane then membersPane:SetShown(not showMsg) end

    -- Ajuste la navigation globale (onglets)
    if UI and UI.ApplyTabsForGuildMembership then
        UI.ApplyTabsForGuildMembership(hasGuild)
    end
end

-- ===== Colonnes (sans actions ni solde) =====
local cols = UI.NormalizeColumns({
    { key="alias",  title=Tr("col_alias"),          w=90,  justify="LEFT"   },
    { key="lvl",    title=Tr("col_level_short"),    w=44,  justify="CENTER" },
    { key="name",   title=Tr("col_name"),           min=200, flex=1         },
    { key="ilvl",   title=Tr("col_ilvl"),           w=100,  justify="CENTER" },
    { key="mplus",  title=Tr("col_mplus_score"),    w=100,  justify="CENTER" },
    { key="mkey",   title=Tr("col_mplus_key"),      w=300, justify="LEFT"   },
    { key="last",   title=Tr("col_attendance"),     w=100, justify="CENTER" },
})

-- Recherche d’infos agrégées guilde (main + rerolls)
local function FindGuildInfo(playerName)
    local guildRows = (GLOG.GetGuildRowsCached and GLOG.GetGuildRowsCached()) or {}
    local NormName = GLOG.NormName
    if not playerName or playerName == "" then return {} end

    -- Détermine le main affiché et sa clé
    local mainName = (GLOG.GetMainOf and GLOG.GetMainOf(playerName)) or playerName
    local mainKey  = NormName and NormName(mainName)
    local mainBase = (tostring(mainName):match('^([^%-]+)') or tostring(mainName))

    local info = {}

    -- Conserve idx/level du main uniquement
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

    -- Agrège la présence et le "last seen"
    local anyOnline, minDays, minHours = false, nil, nil
    for _, gr in ipairs(guildRows) do
        local rowNameKey = (gr.name_key) or ((NormName and NormName(gr.name_amb or gr.name_raw)) or nil)
        local rowMainKey = gr.main_key or ((gr.remark and NormName and NormName(strtrim(gr.remark))) or nil)

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
                    info.onlineAltBase = base
                    info.onlineAltFull = full
                    info.onlineAltIdx  = gr.idx
                    if gr.class and tostring(gr.class) ~= "" then
                        info.altClass = gr.class
                    end
                end
            end

            local d  = tonumber(gr.daysDerived  or nil)
            local hr = tonumber(gr.hoursDerived or nil)
            if gr.online then d, hr = 0, 0 end
            if d ~= nil then minDays  = (minDays  and math.min(minDays,  d))  or d end
            if hr ~= nil then minHours = (minHours and math.min(minHours, hr)) or hr end
        end
    end

    info.online = anyOnline
    info.days   = minDays
    info.hours  = minHours
    return info
end

-- Construction d’une ligne
function BuildRow(r)
    local f = {}

    -- Widgets pour "data"
    f.alias = UI.Label(r, { justify = "LEFT"   })
    f.lvl   = UI.Label(r, { justify = "CENTER" })
    f.name  = UI.CreateNameTag(r)
    f.ilvl  = UI.Label(r, { justify = "CENTER" })
    f.mplus = UI.Label(r, { justify = "CENTER" })
    f.mkey  = UI.Label(r, { justify = "LEFT"   })
    f.last  = UI.Label(r, { justify = "CENTER" })

    -- Widgets pour "sep" (comme dans Joueurs.lua)
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
    local GHX = (UI and UI.GRAY_OFFLINE_HEX) or "999999"
    local function gray(t) return "|cff"..GHX..tostring(t).."|r" end

    local isSep = (it and it.kind == "sep")

    -- ===== Séparateur de section =====
    if f.sepBG then f.sepBG:SetShown(isSep) end
    if f.sepTop then f.sepTop:SetShown(isSep) end
    if f.sepLabel then f.sepLabel:SetShown(isSep) end

    if isSep then
        -- Vider toutes les cellules de données
        if f.name and f.name.text then f.name.text:SetText("") end
        if f.alias then f.alias:SetText("") end
        if f.lvl then f.lvl:SetText("") end
        if f.ilvl then f.ilvl:SetText("") end
        if f.mplus then f.mplus:SetText("") end
        if f.mkey then f.mkey:SetText("") end
        if f.last then f.last:SetText("") end

        -- 🔒 Empêche tout résidu visuel sur les lignes de séparation :
        -- 1) Icône de classe
        if f.name and f.name.icon then
            f.name.icon:SetTexture(nil)
            f.name.icon:Hide()
        end
        -- 2) Liseré gauche "même groupe"
        if UI and UI.SetRowAccent then UI.SetRowAccent(r, false) end
        -- 3) Dégradé horizontal "même groupe"
        if UI and UI.SetRowAccentGradient then UI.SetRowAccentGradient(r, false) end

        if f.sepLabel then
            f.sepLabel:ClearAllPoints()
            f.sepLabel:SetPoint("LEFT", r, "LEFT", 8, 0)
            f.sepLabel:SetText(tostring(it.label or ""))
        end
        return
    else
        if f.sepLabel then f.sepLabel:SetText("") end
        if f.sepBG then f.sepBG:Hide() end
        if f.sepTop then f.sepTop:Hide() end
    end

    local data = it -- pour lisibilité conserver le nom utilisé avant

    -- Nom (icône/couleur main gérés par CreateNameTag / SetNameTag)
    UI.SetNameTag(f.name, data.name or "")

    -- ➕ Marquage "même groupe/sous-groupe" : liseré + dégradé horizontal
    do
        local same = (GLOG.IsInMySubgroup and GLOG.IsInMySubgroup(data.name)) or false
        local st = (UI.GetListViewStyle and UI.GetListViewStyle()) or {}
        local c  = st.accent or { r = 1, g = 0.82, b = 0.00, a = 0.90 }

        if UI.SetRowAccent then
            UI.SetRowAccent(r, same, c.r, c.g, c.b, c.a)
        end
        if UI.SetRowAccentGradient then
            UI.SetRowAccentGradient(r, same, c.r, c.g, c.b, 0.30)
        end
    end
    
    -- Alias
    if f.alias then
        local a = (GLOG.GetAliasFor and GLOG.GetAliasFor(data.name)) or ""
        if a and a ~= "" then f.alias:SetText(" "..a) else f.alias:SetText("") end
    end

    -- Infos guilde agrégées
    local gi = FindGuildInfo(data.name or "")

    -- Présence (last)
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
        if mkeyTxt == "" then mkeyTxt = nil end
        if gi.online then
            f.mkey:SetText(mkeyTxt or gray(Tr("status_empty")))
        else
            f.mkey:SetText(mkeyTxt and gray(mkeyTxt) or gray(Tr("status_empty")))
        end
    end

    -- iLvl (équipé + max)
    if f.ilvl then
        local ilvl    = (GLOG.GetIlvl    and GLOG.GetIlvl(data.name))    or nil
        local ilvlMax = (GLOG.GetIlvlMax and GLOG.GetIlvlMax(data.name)) or nil

        local function fmtOnline()
            if ilvl and ilvl > 0 then
                if ilvlMax and ilvlMax > 0 then
                    return tostring(ilvl)..gray(" ("..tostring(ilvlMax)..")")
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

        f.ilvl:SetText( (FindGuildInfo(data.name or "").online) and fmtOnline() or fmtOffline() )
    end
end

-- Tri demandé :
-- 1) Online d’abord, triés par Alias (A→Z)
-- 2) Offline ensuite, triés par "plus récemment connecté" d’abord, puis Alias
local function _SortMembers(items)
    local online, offline = {}, {}

    for _, it in ipairs(items or {}) do
        local gi = FindGuildInfo(it.name or "")
        local alias = (GLOG.GetAliasFor and GLOG.GetAliasFor(it.name)) or ""
        if not alias or alias == "" then
            alias = (tostring(it.name):match("^([^%-]+)") or tostring(it.name) or "")
        end
        it._sortAlias = tostring(alias):lower()

        -- Heures depuis dernière connexion (plus petit = plus récent)
        local hrs = nil
        if gi.days ~= nil or gi.hours ~= nil then
            local d = tonumber(gi.days or 0)  or 0
            local h = tonumber(gi.hours or 0) or 0
            hrs = d * 24 + h
        end
        it._sortHrs = hrs or math.huge

        if gi.online then table.insert(online, it) else table.insert(offline, it) end
    end

    table.sort(online,  function(a,b)
        if a._sortAlias ~= b._sortAlias then return a._sortAlias < b._sortAlias end
        return tostring(a.name):lower() < tostring(b.name):lower()
    end)

    table.sort(offline, function(a,b)
        if a._sortHrs ~= b._sortHrs then return a._sortHrs < b._sortHrs end -- plus récent d’abord
        if a._sortAlias ~= b._sortAlias then return a._sortAlias < b._sortAlias end
        return tostring(a.name):lower() < tostring(b.name):lower()
    end)

    local out = {}
    for _, x in ipairs(online)  do table.insert(out, x) end
    for _, x in ipairs(offline) do table.insert(out, x) end
    return out
end

-- Build panel
local function Build(container)
    panel = container
    -- Padding global (respecte la sidebar catégorie via CATEGORY_BAR_W)
    if UI.ApplySafeContentBounds then
        UI.ApplySafeContentBounds(panel, { side = 10, bottom = 6 })
    end

    -- Conteneur de l’onglet avec padding interne (comme Synthese)
    membersPane = CreateFrame("Frame", nil, panel)
    membersPane:ClearAllPoints()
    membersPane:SetPoint("TOPLEFT",     panel, "TOPLEFT",     UI.OUTER_PAD, -UI.OUTER_PAD)
    membersPane:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -UI.OUTER_PAD,  UI.OUTER_PAD)

    -- En-tête de section (comme "Roster actif")
    UI.SectionHeader(membersPane, Tr("lbl_guild_members"), { topPad = 2 })

    -- Liste unique, plein écran (pas de footer local -> pleine hauteur)
    lv = UI.ListView(membersPane, cols, {
        buildRow     = function(r) return BuildRow(r) end,
        updateRow    = function(i, r, f, it) UpdateRow(i, r, f, it.data or it) end,
        topOffset    = (UI.SECTION_HEADER_H or 26) + 6,
        bottomAnchor = nil, -- plein parent => pleine hauteur

        -- 🎨 Couleur spécifique aux séparateurs pour l’onglet Guilde : BLANC
        sepLabelColor = UI.MIDGREY,
    })


    -- Message « pas de guilde »
    if not noGuildMsg then
        noGuildMsg = membersPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        noGuildMsg:SetPoint("CENTER", membersPane, "CENTER", 0, 0)
        noGuildMsg:SetJustifyH("CENTER"); noGuildMsg:SetJustifyV("MIDDLE")
        noGuildMsg:SetText(Tr("msg_no_guild"))
        noGuildMsg:Hide()
    end

    _UpdateNoGuildUI()
end

-- Layout : laisser la ListView gérer sa taille
local function Layout()
    if lv and lv.Layout then lv:Layout() end
end

-- Refresh
function Refresh()
    _UpdateNoGuildUI()
    if not _HasGuild() then
        if lv then lv:SetData({}) end
        if lv and lv.Layout then lv:Layout() end
        return
    end

    -- Rafraîchit le cache guilde si nécessaire
    local need = (not GLOG.IsGuildCacheReady or not GLOG.IsGuildCacheReady())
    if not need and GLOG.GetGuildCacheTimestamp then
        local age = time() - GLOG.GetGuildCacheTimestamp()
        if age > 60 then need = true end
    end
    if need and GLOG.RefreshGuildCache then
        if lv then lv:SetData({}) end
        GLOG.RefreshGuildCache(function()
            if ns and ns.RefreshAll then ns.RefreshAll() end
        end)
        return
    end

    -- Construit la base: TOUS les mains agrégés
    local base = {}
    local agg = (GLOG.GetGuildMainsAggregated and GLOG.GetGuildMainsAggregated()) or
                (GLOG.GetGuildMainsAggregatedCached and GLOG.GetGuildMainsAggregatedCached()) or {}

    for _, e in ipairs(agg or {}) do
        -- Résout en "Nom-Royaume" pour peupler ilvl / score / clé M+ comme dans Synthese
        local full = (GLOG.ResolveFullName and GLOG.ResolveFullName(e.main)) or e.mostRecentChar or e.main
        table.insert(base, { name = full })
    end

    -- Tri demandé (online par alias A→Z, puis offline par "plus récent" → alias)
    local sorted = _SortMembers(base or {})

    -- Sépare Online / Offline
    local online, offline = {}, {}  -- ✅ corrige l'initialisation
    for _, it in ipairs(sorted) do
        local gi = FindGuildInfo(it.name or "")
        if gi.online then
            table.insert(online, it)
        else
            table.insert(offline, it)
        end
    end

    -- Injecte les séparateurs
    local out = {}
    if #online > 0 then
        table.insert(out, { kind = "sep", label = Tr("lbl_sep_online") or Tr("status_online") })
        for _, x in ipairs(online) do table.insert(out, x) end
    end
    if #offline > 0 then
        table.insert(out, { kind = "sep", label = Tr("lbl_sep_offline") or "Déconnectés" })
        for _, x in ipairs(offline) do table.insert(out, x) end
    end

    if lv then lv:SetData(out) end
    if lv and lv.Layout then lv:Layout() end
end

UI.RegisterTab(Tr("tab_guild_members"), Build, Refresh, Layout, {
    category = Tr("cat_guild"),
})