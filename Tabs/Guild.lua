local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns.GLOG, ns.UI
local PAD, SBW, GUT = UI.OUTER_PAD, UI.SCROLLBAR_W, UI.GUTTER

-- ===== Rafraîchissement live des zones (hors cache) =====
local _LiveZoneTicker, _LiveEvt, _lastRosterRefresh = nil, nil, 0

-- Forward declare to allow early use
local FindGuildInfo

-- Forward declaration for ListView instance used by handlers
local lv

-- DB key normalizer: always use full "Name-Realm" for DB-backed lookups
local function _DBKey(name)
    if GLOG and GLOG.NormalizeDBKey then return GLOG.NormalizeDBKey(name) end
    return tostring(name or "")
end

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
        -- ⏸️ Pause globale : ne pas rafraîchir le roster si l'UI principale est fermée
        if UI and UI.ShouldRefreshUI and not UI.ShouldRefreshUI() then return end
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
        if not (membersPane and membersPane.IsShown and membersPane:IsShown()) then return end
        -- Mise à jour légère des lignes visibles si possible (zones/online changent souvent)
    -- lv est un upvalue défini plus bas (ListView instance)
    if _G and lv and lv.UpdateVisibleRows then
            if ns and ns.Util and ns.Util.Debounce then
                ns.Util.Debounce("tab:guild:updateVisible", 0.10, function()
                    if _G and lv and lv.UpdateVisibleRows then lv:UpdateVisibleRows() end
                end)
            else
                if lv and lv.UpdateVisibleRows then lv:UpdateVisibleRows() end
            end
        else
            if UI and UI.RefreshAll then UI.RefreshAll() else if Refresh then Refresh() end end
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
local panel, membersArea, noGuildMsg
-- Classement M+ top-3: [fullName] = 1|2|3
local _mplusRanks = nil
-- Classement iLvl top-3: [fullName] = 1|2|3
local _ilvlRanks = nil

-- Icône médaille (atlas challenges-medal-*) or/silver/bronze
local function _RankIcon(rank, size)
    size = size or 28
    local atlas
    if rank == 1 then atlas = "challenges-medal-gold"
    elseif rank == 2 then atlas = "challenges-medal-silver"
    elseif rank == 3 then atlas = "challenges-medal-bronze" end
    if not atlas then return "" end
    return ("|A:%s:%d:%d|a"):format(atlas, size, size)
end

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
        -- Optional ping column on the far left (hidden in standalone mode)
        (function()
            local isStandalone = (GLOG and GLOG.IsStandaloneMode and GLOG.IsStandaloneMode()) or false
            if not isStandalone then return { key = "ping", title = "", w = 28, justify = "CENTER" } end
            return nil
        end)(),
        { key="alias",  title=Tr("col_alias"),          vsep=true,  w=90,  justify="LEFT"   },
        { key="lvl",    title=Tr("col_level_short"),    vsep=true,  w=44,  justify="CENTER" },
        { key="name",   title=Tr("col_name"),           vsep=true,  min=50, flex=1         },
        { key="last",   title=Tr("col_attendance"),     vsep=true,  w=200,  justify="LEFT" },
        { key="ilvl",   title=Tr("col_ilvl"),           vsep=true,  w=120, justify="CENTER" },
        { key="mplus",  title=Tr("col_mplus_score"),    vsep=true,  w=120,  justify="CENTER" },
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
        bottomAnchor = footer,
        maxCreatePerFrame = 80
    })

end

-- Recherche d’infos agrégées guilde (main + rerolls) – O(1)
local function FindGuildInfo(playerName)
    return (GLOG.GetMainAggregatedInfo and GLOG.GetMainAggregatedInfo(playerName)) or {}
end

-- Ping cooldown state (per recipient, keyed by normalized full name) and helpers
local _pingCooldown = {}
local function _normalizeName(full)
    local nf = (ns and ns.Util and ns.Util.NormalizeFull) and ns.Util.NormalizeFull or tostring
    local s = nf(full or "")
    return s:lower()
end
local function _pingRemaining(full)
    local key = _normalizeName(full)
    local t = (GetTimePreciseSec and GetTimePreciseSec()) or (GetTime and GetTime()) or 0
    local untilT = tonumber(_pingCooldown[key] or 0) or 0
    local left = math.ceil(math.max(0, untilT - t))
    return left
end
local function _setPingCooldown(full, seconds)
    local key = _normalizeName(full)
    local t = (GetTimePreciseSec and GetTimePreciseSec()) or (GetTime and GetTime()) or 0
    _pingCooldown[key] = t + (seconds or 90)
end

-- Cached current player full name for self-comparisons
local _meFull
local function _GetMeFull()
    if _meFull ~= nil then return _meFull end
    local name = UnitName and UnitName("player") or nil
    local realm = GetRealmName and GetRealmName() or nil
    if name and name ~= "" then
        if ns and ns.Util and ns.Util.NormalizeFull then
            _meFull = ns.Util.NormalizeFull(name, realm)
        else
            _meFull = (realm and realm ~= "") and (name.."-"..realm) or name
        end
    else
        _meFull = ""
    end
    return _meFull
end


-- Construction d’une ligne
function BuildRow(r)
    local f = {}

    -- Widgets pour "data"
    -- Host for ping button if column exists
    f.ping = CreateFrame("Frame", nil, r)
    f.alias = UI.Label(r, { justify = "LEFT"   })
    f.lvl   = UI.Label(r, { justify = "CENTER" })
    f.name  = UI.CreateNameTag(r)
    f.ilvl  = UI.Label(r, { justify = "CENTER" })
    f.mplus = UI.Label(r, { justify = "CENTER" })
    f.mkey  = UI.Label(r, { justify = "LEFT"   })
    f.last  = UI.Label(r, { justify = "LEFT" })
    -- ➕ Version (ajoutée uniquement si la colonne existe côté header)
    f.ver   = UI.Label(r, { justify = "CENTER" })

    -- Médailles alignées à gauche des cellules (icônes séparées, texte centré)
    do
        local size = 28
        f.ilvlMedal = r:CreateTexture(nil, "ARTWORK") ; f.ilvlMedal:Hide()
        f.ilvlMedal:SetSize(size, size)
        f.ilvlMedal:SetPoint("LEFT", f.ilvl, "LEFT", 0, 0)

        f.mplusMedal = r:CreateTexture(nil, "ARTWORK") ; f.mplusMedal:Hide()
        f.mplusMedal:SetSize(size, size)
        f.mplusMedal:SetPoint("LEFT", f.mplus, "LEFT", 0, 0)
    end

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

    -- Ping icon button (only when ping column is present)
    do
        local isStandalone = (GLOG and GLOG.IsStandaloneMode and GLOG.IsStandaloneMode()) or false
        if not isStandalone and f.ping then
            local ICON = "Interface\\ICONS\\INV_Misc_Bell_01"
            local btn = UI.IconButton(f.ping, ICON, { size = 18, tooltip = Tr and Tr("tip_ping") or "Ping" })
            btn:SetPoint("CENTER", f.ping, "CENTER", 0, 0)
            btn._isPing = true
            r._pingBtn = btn

            -- Allow hover scripts to run even when disabled (so tooltip still appears)
            if btn.SetMotionScriptsWhileDisabled then btn:SetMotionScriptsWhileDisabled(true) end
            btn:EnableMouse(true)
            btn:SetScript("OnEnter", function(self)
                local data = r._lastItemRef or r._itemData or r._data or r._item
                local name = data and data.name
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if name and name ~= "" then
                    local left = _pingRemaining(name)
                    if not self:IsEnabled() then
                        if left > 0 then
                            GameTooltip:SetText((Tr and Tr("tip_disabled_ping_cd_fmt") or "On cooldown: %ds remaining"):format(left))
                        else
                            GameTooltip:SetText((Tr and Tr("tip_disabled_offline_group")) or "Disabled: none of this player's characters are online")
                        end
                    else
                        GameTooltip:SetText((Tr and Tr("tip_ping")) or "Ping this player")
                    end
                end
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
    end

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

        if f.ilvlMedal then f.ilvlMedal:Hide() end
        if f.mplusMedal then f.mplusMedal:Hide() end

        -- Hide ping button on separator rows
        if r._pingBtn then r._pingBtn:Hide() end

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
    -- Cache guild info per item to avoid repeated lookups
    local gi = data._gi or FindGuildInfo(data.name or "")
    -- Ping button state (online + cooldown) and click handler (only for data rows)
    do
        local btn = r._pingBtn
        if btn then
            -- Hide on separators or when the row represents the current player
            local isSelf = false
            local me = _GetMeFull()
            if me and me ~= "" then
                if ns and ns.Util and ns.Util.SamePlayer then
                    isSelf = ns.Util.SamePlayer(data.name, me)
                else
                    local nf = (ns and ns.Util and ns.Util.NormalizeFull) and ns.Util.NormalizeFull or tostring
                    local a = nf(data.name or "")
                    local b = nf(me)
                    isSelf = (tostring(a):lower() == tostring(b):lower())
                end
            end

            -- ✅ Masquer la cloche si : séparateur, soi-même, ou version addon absente / trop ancienne (< 4.2.4)
            local hideForVersion = false
            if not isSep and not isSelf then
                local key = _DBKey(data.name)
                local ver = (GLOG.GetPlayerAddonVersion and GLOG.GetPlayerAddonVersion(key)) or ""
                if ver == "" then
                    hideForVersion = true
                else
                    local cmp = (ns and ns.Util and ns.Util.CompareVersions) or nil
                    if cmp and cmp(ver, "4.2.4") < 0 then
                        hideForVersion = true
                    end
                end
            end

            if isSep or isSelf or hideForVersion then
                btn:Hide()
            else
                -- Determine recipient: prefer an online alt full name if present
                local online = gi and gi.online and true or false
                local recipient = (gi and gi.onlineAltFull) or data.name
                -- Hide when offline (no tooltip noise for offline targets)
                if not online then
                    btn:Hide()
                else
                    btn:Show()
                    -- Bypass cooldown for authorized editors/GM cluster and officers
                    -- Keep editor rights check (CanModifyGuildData) and add officers via new GLOG.IsOfficer()
                    local isPrivileged = false
                    if GLOG then
                        if GLOG.CanModifyGuildData and GLOG.CanModifyGuildData() then
                            isPrivileged = true
                        elseif GLOG.IsOfficer and GLOG.IsOfficer() then
                            isPrivileged = true
                        end
                    end
                    local cdLeft = isPrivileged and 0 or _pingRemaining(recipient)
                    local enabled = online and (cdLeft <= 0)
                    if btn.SetEnabled then btn:SetEnabled(enabled) end
                    btn:SetAlpha(enabled and 1 or 0.45)
                    btn:SetOnClick(function()
                        if not enabled then return end
                        local target = recipient
                        if not (GLOG and GLOG.Comm_Whisper and target and target ~= "") then return end

                        -- Ask for an optional message to accompany the ping
                        local function send(msg)
                            local payload = { ts = (GetTime and GetTime()) or 0 }
                            if type(msg) == "string" then
                                -- Properly trim leading/trailing whitespace
                                local trimmed = (msg:gsub("^%s+", "")):gsub("%s+$", "")
                                if trimmed ~= "" then payload.msg = trimmed end
                            end
                            GLOG.Comm_Whisper(target, "PING", payload)
                            if not isPrivileged then _setPingCooldown(recipient, 90) end
                            if lv and lv.UpdateVisibleRows then lv:InvalidateVisibleRowsCache(); lv:UpdateVisibleRows() end
                        end

                        if UI and UI.PopupPromptText then
                            UI.PopupPromptText(Tr and Tr("popup_ping_title") or "Ping", Tr and Tr("lbl_ping_message") or "Message (optionnel)", function(text)
                                -- Défense: trim + coupe à 120 caractères
                                local t = type(text) == "string" and text or ""
                                t = (t:gsub("^%s+", "")):gsub("%s+$", "")
                                if #t > 120 then t = string.sub(t, 1, 120) end
                                send(t)
                            end, { width = 420, placeholder = Tr and Tr("ph_ping_message") or "Ex: besoin d'un coup de main?", maxLen = 120 })
                        else
                            -- Fallback: send without extra message
                            send(nil)
                        end
                    end)
                end
            end
        end
    end


    -- Nom (sans royaume) + ajout éventuel du reroll connecté (icône + nom)
    UI.SetNameTagShort(f.name, data.name or "")

    -- Récupère le reroll online attaché au main (si différent du main)
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

    -- Infos guilde agrégées (déjà récupérées ci-dessus)

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
        local key = _DBKey(data.name)
        local v = (GLOG.GetPlayerAddonVersion and GLOG.GetPlayerAddonVersion(key)) or ""
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
        local key = _DBKey(data.name)
        local score = (GLOG.GetMPlusScore and GLOG.GetMPlusScore(key)) or nil
        local rank = _mplusRanks and _mplusRanks[key]
        -- Positionne l'icône de médaille à gauche (sans perturber le centrage du texte)
        if f.mplusMedal then
            if rank == 1 then f.mplusMedal:SetAtlas("challenges-medal-gold")
            elseif rank == 2 then f.mplusMedal:SetAtlas("challenges-medal-silver")
            elseif rank == 3 then f.mplusMedal:SetAtlas("challenges-medal-bronze")
            else f.mplusMedal:SetAtlas(nil) end
            f.mplusMedal:SetShown(rank == 1 or rank == 2 or rank == 3)
        end
        if gi.online then
            if score and score > 0 then
                f.mplus:SetText(tostring(score))
            else
                f.mplus:SetText(gray(Tr("status_empty")))
            end
        else
            if score and score > 0 then
                -- texte grisé, médaille conservée (texture à part)
                f.mplus:SetText(gray(score))
            else
                f.mplus:SetText(gray(Tr("status_empty")))
            end
        end
    end

    -- Clé M+
    if f.mkey then
        local key = _DBKey(data.name)
        local mkeyTxt = (GLOG.GetMKeyText and GLOG.GetMKeyText(key)) or ""
        if gi.online then
            f.mkey:SetText((mkeyTxt ~= "" and mkeyTxt) or gray(Tr("status_empty")))
        else
            f.mkey:SetText((mkeyTxt ~= "" and gray(mkeyTxt)) or gray(Tr("status_empty")))
        end
    end

    -- iLvl (équipé + max) + médaille top-3 (basée sur iLvl MAX)
    if f.ilvl then
        local key     = _DBKey(data.name)
        local ilvl    = (GLOG.GetIlvl    and GLOG.GetIlvl(key))    or nil
        local ilvlMax = (GLOG.GetIlvlMax and GLOG.GetIlvlMax(key)) or nil
        local rank    = _ilvlRanks and _ilvlRanks[key]
        -- Positionne l'icône de médaille à gauche (sans perturber le centrage du texte)
        if f.ilvlMedal then
            if rank == 1 then f.ilvlMedal:SetAtlas("challenges-medal-gold")
            elseif rank == 2 then f.ilvlMedal:SetAtlas("challenges-medal-silver")
            elseif rank == 3 then f.ilvlMedal:SetAtlas("challenges-medal-bronze")
            else f.ilvlMedal:SetAtlas(nil) end
            f.ilvlMedal:SetShown(rank == 1 or rank == 2 or rank == 3)
        end

        local function fmtOnline()
            if ilvl and ilvl > 0 then
                local base = tostring(ilvl)
                if ilvlMax and ilvlMax > 0 then
                    base = base .. gray(" ("..tostring(ilvlMax)..")")
                end
                return base
            else
                return gray(Tr("status_empty"))
            end
        end

        local function fmtOffline()
            if ilvl and ilvl > 0 then
                local base = gray(tostring(ilvl))
                if ilvlMax and ilvlMax > 0 then
                    base = gray(tostring(ilvl).." ("..tostring(ilvlMax)..")")
                end
                return base
            else
                return gray(Tr("status_empty"))
            end
        end

        f.ilvl:SetText( gi.online and fmtOnline() or fmtOffline() )
    end
end

-- Tri demandé :
-- 1) Online d’abord, triés par Alias (A→Z)
-- 2) Offline ensuite, triés par "plus récemment connecté" d’abord, puis Alias
local function _SortMembers(items)
    local online, offline = {}, {}

    for i = 1, #(items or {}) do
        local it = items[i]
        local gi = it._gi or FindGuildInfo(it.name or "")
        it._gi = gi
        local alias = (GLOG.GetAliasFor and GLOG.GetAliasFor(it.name)) or ""
        if not alias or alias == "" then
            alias = (tostring(it.name):match("^([^%-]+)") or tostring(it.name) or "")
        end
        it._sortAlias = tostring(alias):lower()

        -- Heures depuis dernière connexion (plus petit = plus récent)
        local hrs = nil
        if gi and (gi.days ~= nil or gi.hours ~= nil) then
            local d = tonumber(gi.days or 0)  or 0
            local h = tonumber(gi.hours or 0) or 0
            hrs = d * 24 + h
        end
        it._sortHrs = hrs or math.huge

        if gi and gi.online then table.insert(online, it) else table.insert(offline, it) end
    end

    table.sort(online,  function(a,b)
        if a._sortAlias ~= b._sortAlias then return a._sortAlias < b._sortAlias end
        local an, bn = a.name or "", b.name or ""
        an, bn = an:lower(), bn:lower()
        return an < bn
    end)

    table.sort(offline, function(a,b)
        if a._sortHrs ~= b._sortHrs then return a._sortHrs < b._sortHrs end -- plus récent d’abord
        if a._sortAlias ~= b._sortAlias then return a._sortAlias < b._sortAlias end
        local an, bn = a.name or "", b.name or ""
        an, bn = an:lower(), bn:lower()
        return an < bn
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
local function _DoRefresh()
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

    do
        local resolve = GLOG.ResolveFullName
        for i = 1, #agg do
            local e = agg[i]
            local full = (resolve and resolve(e.main)) or e.mostRecentChar or e.main
            -- Pre-cache guild info to avoid repeated lookups in UpdateRow/Sort
            local gi = FindGuildInfo(full or "")
            base[#base+1] = { name = full, _gi = gi }
        end
    end

    -- Calcule le top 3 M+ (or/argent/bronze) avec ex aequo
    do
        local ranks = {}
        for _, it in ipairs(base) do
            local key = _DBKey(it.name)
            local s = (GLOG.GetMPlusScore and GLOG.GetMPlusScore(key)) or 0
            if s and s > 0 then
                ranks[#ranks+1] = { name = key, s = s }
            end
        end
        table.sort(ranks, function(a,b) return (a.s or 0) > (b.s or 0) end)

        -- Détermine les 3 meilleures VALEURS uniques (ex aequo partagent le même rang)
        local topVals, seen = {}, {}
        for i = 1, #ranks do
            local v = ranks[i].s or 0
            if not seen[v] then
                topVals[#topVals+1] = v
                seen[v] = true
                if #topVals >= 3 then break end
            end
        end
        local valToPlace = {}
        for idx, v in ipairs(topVals) do valToPlace[v] = idx end

        _mplusRanks = {}
        if #topVals > 0 then
            for i = 1, #ranks do
                local v = ranks[i].s or 0
                local place = valToPlace[v]
                if place then _mplusRanks[ranks[i].name] = place end
            end
        end
    end

    -- Calcule le top 3 iLvl (basé STRICTEMENT sur iLvl MAX) avec ex aequo
    do
        local ranks = {}
        for _, it in ipairs(base) do
            local key = _DBKey(it.name)
            local maximum  = (GLOG.GetIlvlMax and GLOG.GetIlvlMax(key)) or 0
            local v = tonumber(maximum or 0) or 0
            if v and v > 0 then
                ranks[#ranks+1] = { name = key, v = v }
            end
        end
        table.sort(ranks, function(a,b) return (a.v or 0) > (b.v or 0) end)

        -- Détermine les 3 meilleures VALEURS uniques
        local topVals, seen = {}, {}
        for i = 1, #ranks do
            local v = ranks[i].v or 0
            if not seen[v] then
                topVals[#topVals+1] = v
                seen[v] = true
                if #topVals >= 3 then break end
            end
        end
        local valToPlace = {}
        for idx, v in ipairs(topVals) do valToPlace[v] = idx end

        _ilvlRanks = {}
        if #topVals > 0 then
            for i = 1, #ranks do
                local v = ranks[i].v or 0
                local place = valToPlace[v]
                if place then _ilvlRanks[ranks[i].name] = place end
            end
        end
    end

    -- Tri demandé (online par alias A→Z, puis offline par "plus récent" → alias)
    local sorted = _SortMembers(base or {})

    -- Sépare Online / Offline
    local online, offline = {}, {}
    for i = 1, #sorted do
        local it = sorted[i]
        local gi = it._gi or FindGuildInfo(it.name or "")
        if gi and gi.online then online[#online+1] = it else offline[#offline+1] = it end
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

function Refresh()
    if ns and ns.Util and ns.Util.Debounce then
        ns.Util.Debounce("tab:guild:refresh", 0.10, _DoRefresh)
    else
        _DoRefresh()
    end
end

UI.RegisterTab(Tr("tab_guild_members"), Build, Refresh, Layout, {
    category = Tr("cat_guild"),
})