local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns.GLOG, ns.UI
local PAD, SBW, GUT = UI.OUTER_PAD, UI.SCROLLBAR_W, UI.GUTTER

-- ===== Rafraîchissement live des zones (hors cache) =====
local _LiveZoneTicker, _LiveEvt, _lastRosterRefresh = nil, nil, 0

-- Retourne la "vraie" zone depuis le roster si dispo, sinon fallback cache
local function _GetLiveZoneForMember(playerName, gi)
    gi = gi or FindGuildInfo(playerName or "")
    if gi then
        local idx = gi.onlineAltIdx or gi.idx
        if idx and GetGuildRosterInfo then
            local name, rank, rankIndex, level, classDisplayName, zone, note, officerNote, online = GetGuildRosterInfo(idx)
            if online and zone and zone ~= "" then
                return zone
            end
        end
    end
    -- Fallback (cache interne)
    return (GLOG.GetAnyOnlineZone and GLOG.GetAnyOnlineZone(playerName)) or nil
end

-- Lance/arrête un ticker qui demande un refresh du roster (léger)
local function _StartLiveZoneTicker()
    if _LiveZoneTicker or not C_Timer then return end
    _LiveZoneTicker = C_Timer.NewTicker(10, function()
        -- Throttle pour éviter spam serveur
        local now = time()
        if now - (_lastRosterRefresh or 0) >= 5 then
            _lastRosterRefresh = now
            if C_GuildInfo and C_GuildInfo.GuildRoster then
                C_GuildInfo.GuildRoster()
            end
        end
    end)
end
local function _StopLiveZoneTicker()
    if _LiveZoneTicker then _LiveZoneTicker:Cancel(); _LiveZoneTicker = nil end
end

-- Événements roster : quand ça bouge, on re-render le panneau si visible
local function _EnsureLiveZoneEvents()
    if _LiveEvt then return end
    _LiveEvt = {} -- marqueur de création (plus de frame)

    local function _onGuildEvt()
        if membersPane and membersPane:IsShown() then
            if UI and UI.RefreshAll then UI.RefreshAll() else Refresh() end
        end
    end

    ns.Events.Register("GUILD_ROSTER_UPDATE", _onGuildEvt)
    ns.Events.Register("PLAYER_GUILD_UPDATE", _onGuildEvt)
    ns.Events.Register("GROUP_ROSTER_UPDATE", _onGuildEvt)
end

-- ===== Détection zones instance/raid/gouffre (robuste) =====
local function _strip_accents(s)
    local map = {
        ["à"]="a",["á"]="a",["â"]="a",["ä"]="a",["ã"]="a",["å"]="a",
        ["ç"]="c",
        ["è"]="e",["é"]="e",["ê"]="e",["ë"]="e",
        ["ì"]="i",["í"]="i",["î"]="i",["ï"]="i",
        ["ñ"]="n",
        ["ò"]="o",["ó"]="o",["ô"]="o",["ö"]="o",["õ"]="o",
        ["ù"]="u",["ú"]="u",["û"]="u",["ü"]="u",
        ["ý"]="y",["ÿ"]="y",
        ["œ"]="oe",["æ"]="ae",
        ["À"]="a",["Á"]="a",["Â"]="a",["Ä"]="a",["Ã"]="a",["Å"]="a",
        ["Ç"]="c",
        ["È"]="e",["É"]="e",["Ê"]="e",["Ë"]="e",
        ["Ì"]="i",["Í"]="i",["Î"]="i",["Ï"]="i",
        ["Ñ"]="n",
        ["Ò"]="o",["Ó"]="o",["Ô"]="o",["Ö"]="o",["Õ"]="o",
        ["Ù"]="u",["Ú"]="u",["Û"]="u",["Ü"]="u",
        ["Ý"]="y",["Œ"]="oe",["Æ"]="ae",
    }
    return (tostring(s or ""):gsub("[%z\1-\127\194-\244][\128-\191]*", function(ch) return map[ch] or ch end))
end

local function _norm(s)
    s = _strip_accents(s):lower()
    -- retire espaces, ponctuation, guillemets, tirets, apostrophes (’ '), etc.
    s = s:gsub("[^%w]", "")
    -- enlève un éventuel "l" (pour l') collé après normalisation
    s = s:gsub("^l", "")
    return s
end

local _INST -- index des noms d’instances/raids/M+ normalisés
local function _ensureInstanceIndex()
    if _INST then return _INST end
    _INST = {}

    -- Encounter Journal (donjons + raids)
    local function addEJ()
        local ok = true
        if not EJ_GetNumTiers and UIParentLoadAddOn then ok = pcall(UIParentLoadAddOn, "Blizzard_EncounterJournal") end
        if not (ok and EJ_GetNumTiers) then return end
        local tiers = EJ_GetNumTiers() or 0
        for t = 1, tiers do
            if EJ_SelectTier then EJ_SelectTier(t) end
            for _, isRaid in ipairs({ false, true }) do
                local idx = 1
                while true do
                    local id, name = EJ_GetInstanceByIndex(idx, isRaid)
                    if not id or not name then break end
                    _INST[_norm(name)] = true
                    idx = idx + 1
                end
            end
        end
    end

    -- Mythique+ (Challenge Mode)
    local function addMPlus()
        if not (C_ChallengeMode and C_ChallengeMode.GetMapTable) then return end
        local maps = C_ChallengeMode.GetMapTable()
        if type(maps) == "table" then
            for _, mapID in ipairs(maps) do
                local name = C_ChallengeMode.GetMapUIInfo and C_ChallengeMode.GetMapUIInfo(mapID)
                if name and name ~= "" then
                    _INST[_norm(name)] = true
                end
            end
        end
    end

    addEJ()
    addMPlus()

    -- Mots-clés génériques FR/EN sur les gouffres
    _INST["gouffre"] = true ; _INST["gouffres"] = true
    _INST["delve"]   = true ; _INST["delves"]  = true

    return _INST
end

local function _isInstanceLikeZoneName(zoneName)
    if not zoneName or zoneName == "" then return false end
    local z = _norm(zoneName)
    local set = _ensureInstanceIndex()
    if set[z] then return true end
    -- Matching partiel (ex: "Gouffre : Les Archives", "Uldaman : l'heritage de Tyr (M+)")
    for key in pairs(set) do
        if #key >= 4 and (z:find(key, 1, true) or key:find(z, 1, true)) then
            return true
        end
    end
    return false
end

local function _red(t) return "|cffff4040"..tostring(t).."|r" end


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

-- ===== Colonnes (dynamiques : ajout de la version en mode debug) =====
local function _BuildColumns()
    local base = {
        { key="alias",  title=Tr("col_alias"),          w=90,  justify="LEFT"   },
        { key="lvl",    title=Tr("col_level_short"),    vsep=true,  w=44,  justify="CENTER" },
        { key="name",   title=Tr("col_name"),           vsep=true,  min=50, flex=1         },
        { key="last",   title=Tr("col_attendance"),     vsep=true,  w=200,  justify="LEFT" },
        { key="ilvl",   title=Tr("col_ilvl"),           vsep=true,  w=100, justify="CENTER" },
        { key="mplus",  title=Tr("col_mplus_score"),    vsep=true,  w=100,  justify="CENTER" },
        { key="mkey",   title=Tr("col_mplus_key"),      vsep=true,  w=240,  justify="LEFT"   },
        { key="ver",    title=Tr("col_version_short"),  vsep=true,  w=60,  justify="CENTER" }
    }

    return UI.NormalizeColumns(base)
end

-- (Re)création de la ListView avec les colonnes adaptées au mode debug
local function _RecreateListView()
    if not membersPane then return end

    local cols = _BuildColumns()

    -- Démonte proprement l'ancienne LV si présente (header + scroll)
    if lv and lv.header then lv.header:Hide(); lv.header:SetParent(nil) end
    if lv and lv.scroll then lv.scroll:Hide(); lv.scroll:SetParent(nil) end
    lv = nil

    -- Nouvelle LV
    lv = UI.ListView(membersPane, cols, {
        buildRow     = function(r) return BuildRow(r) end,
        updateRow    = function(i, r, f, it) UpdateRow(i, r, f, it.data or it) end,
        -- 🎨 Couleur spécifique des séparateurs pour l’onglet Guilde
        sepLabelColor = UI.MIDGREY,
        topOffset = UI.SECTION_HEADER_H or 26,
        bottomAnchor = footer
    })

end

-- Recherche d’infos agrégées guilde (main + rerolls) – O(1)
local function FindGuildInfo(playerName)
    return (GLOG.GetMainAggregatedInfo and GLOG.GetMainAggregatedInfo(playerName)) or {}
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
    f.last  = UI.Label(r, { justify = "LEFT" })
    -- ➕ Version (ajoutée uniquement si la colonne existe côté header)
    f.ver   = UI.Label(r, { justify = "CENTER" })

    -- Widgets pour "sep" (comme dans Joueurs.lua)
    f.sepBG = r:CreateTexture(nil, "BACKGROUND"); f.sepBG:Hide()
    f.sepBG:SetColorTexture(0.18, 0.18, 0.22, 0.6)

    -- ✅ Padding haut de 10px
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

    f.sepLabel = r:CreateFontString(nil, "OVERLAY", "GameFontNormal"); f.sepLabel:Hide()
    f.sepLabel:SetTextColor(1, 0.95, 0.3)

    return f
end

-- Mise à jour d’une ligne
function UpdateRow(i, r, f, it)
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
        if f.ver then f.ver:SetText("") end

        -- 🔒 Nettoyage visuel
        if f.name and f.name.icon then
            f.name.icon:SetTexture(nil)
            f.name.icon:Hide()
        end
        if UI and UI.SetRowAccent then UI.SetRowAccent(r, false) end
        if UI and UI.SetRowAccentGradient then UI.SetRowAccentGradient(r, false) end

        if f.sepLabel then
            f.sepLabel:ClearAllPoints()
            f.sepLabel:SetPoint("LEFT", r, "LEFT", 8, 0)
            f.sepLabel:SetText(tostring(it.label or ""))
        end
        return
    end

    -- ===== Ligne de données =====
    if f.sepLabel then f.sepLabel:SetText("") end

    local data = it -- pour lisibilité

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

    -- ➕ Marquage "dans mon groupe/raid (tous sous-groupes confondus)"
    do
        local same = (GLOG.IsInMyGroup and GLOG.IsInMyGroup(data.name)) or false
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
        if a and a ~= "" then f.alias:SetText("   "..a) else f.alias:SetText(" ") end
    end

    -- Infos guilde agrégées
    local gi = FindGuildInfo(data.name or "")

    -- Présence (last) : zone "live" via GetGuildRosterInfo, fallback cache
    if f.last then
        if gi.online then
            local loc = _GetLiveZoneForMember(data.name, gi)
            if loc and loc ~= "" then
                if _isInstanceLikeZoneName and _isInstanceLikeZoneName(loc) then
                    f.last:SetText(_red(loc))
                else
                    f.last:SetText(tostring(loc))
                end
            else
                f.last:SetText(Tr("status_online"))
            end
        elseif gi.days or gi.hours then
            f.last:SetText(ns.Format.LastSeen(gi.days, gi.hours))
        else
            f.last:SetText(gray(Tr("status_empty")))
        end
    end

    -- ➕ Version d'addon (uniquement si la colonne existe dans la LV)
    if f.ver then
        local v = (GLOG.GetPlayerAddonVersion and GLOG.GetPlayerAddonVersion(data.name)) or ""
        f.ver:SetText((v ~= "" and "v"..v) or "—")
    end

    -- Niveau
    if f.lvl then
        if gi.level and gi.level > 0 then
            if gi.online then
                f.lvl:SetText(tostring(gi.level))
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
function Build(container)

    -- Création du conteneur
    membersPane, footer = UI.CreateMainContainer(container, {footer = false})

    -- En-tête de section
    UI.SectionHeader(membersPane, Tr("lbl_guild_members"), { topPad = 2 })

    -- Live zones: events + ticker tant que le panneau est visible
    _EnsureLiveZoneEvents()
    if membersPane then
        membersPane:HookScript("OnShow", function()
            _StartLiveZoneTicker()
            -- Demande un roster immédiat pour un 1er affichage frais
            if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
        end)
        membersPane:HookScript("OnHide", function()
            _StopLiveZoneTicker()
        end)
    end

    -- 🔁 ListView dépend du mode debug → (re)création dédiée
    _RecreateListView()

    -- 📥 Données initiales
    Refresh()

    -- 🎨 Masque de fond (même logique que Roster)
    -- Cache le containerBG générique pour éviter le double assombrissement
    if lv and lv._containerBG and lv._containerBG.Hide then
        lv._containerBG:Hide()
    end

    -- Crée un fond englobant (depuis les couleurs centralisées UI.GetListViewContainerColor)
    do
        local col = (UI.GetListViewContainerColor and UI.GetListViewContainerColor()) or { r = 0, g = 0, b = 0, a = 0.20 }
        local bg  = membersPane:CreateTexture(nil, "BACKGROUND")
        bg:SetColorTexture(col.r or 0, col.g or 0, col.b or 0, col.a or 0.20)

        -- Ancre sur l'entête + la zone scroll
        if lv and lv.header and lv.scroll then
            bg:SetPoint("TOPLEFT",     lv.header, "TOPLEFT",     0, 0)
            bg:SetPoint("BOTTOMRIGHT", lv.scroll, "BOTTOMRIGHT", 0, 0)
        end

        -- Recalage automatique si la ListView se relayout
        if lv and lv.Layout and not lv._synth_bg_hook then
            local _oldLayout = lv.Layout
            function lv:Layout(...)
                local res = _oldLayout(self, ...)
                if bg and self.header and self.scroll then
                    bg:ClearAllPoints()
                    bg:SetPoint("TOPLEFT",     self.header, "TOPLEFT",     0, 0)
                    bg:SetPoint("BOTTOMRIGHT", self.scroll, "BOTTOMRIGHT", 0, 0)
                    -- garde la teinte en phase avec le thème
                    if UI.GetListViewContainerColor then
                        local c = UI.GetListViewContainerColor()
                        if c then bg:SetColorTexture(c.r or 0, c.g or 0, c.b or 0, c.a or 0.20) end
                    end
                end
                return res
            end
            lv._synth_bg_hook = true
        end
    end

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
            if UI.RefreshAll then UI.RefreshAll() end
        end)
        return
    end

    -- Construit la base : agrégat des mains guilde
    local base = {}
    local agg = (GLOG.GetGuildMainsAggregated and GLOG.GetGuildMainsAggregated()) or
                (GLOG.GetGuildMainsAggregatedCached and GLOG.GetGuildMainsAggregatedCached()) or {}

    for _, e in ipairs(agg or {}) do
        local full = (GLOG.ResolveFullName and GLOG.ResolveFullName(e.main)) or e.mostRecentChar or e.main
        table.insert(base, { name = full })
    end

    -- Tri demandé (online par alias A→Z, puis offline par "plus récent" → alias)
    local sorted = _SortMembers(base or {})

    -- Sépare Online / Offline
    local online, offline = {}, {}
    for _, it in ipairs(sorted) do
        local gi = FindGuildInfo(it.name or "")
        if gi.online then table.insert(online, it) else table.insert(offline, it) end
    end

    -- Injecte les séparateurs
    local out = {}
    if #online > 0 then
        table.insert(out, { kind = "sep", extraTop = 0,  label = Tr("lbl_sep_online") or Tr("status_online") })
        for _, x in ipairs(online)  do table.insert(out, x) end
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