local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
ns.UI   = ns.UI   or {}
ns.Util = ns.Util or {}
ns.Data = ns.Data or {}

local GLOG, UI, U, Data = ns.GLOG, ns.UI, ns.Util, ns.Data
local Tr = ns.Tr or function(s) return s end

local _G = _G
if setfenv then
    setfenv(1, setmetatable({}, { __index = _G }))
end

-- =========================
-- ===   ÉTAT & STORE   ===
-- =========================
local state = {
    enabled = false,
    uses = {},         -- [full] = { heal=0, util=0, stone=0 } (session live combat uniquement)
    win  = nil,        -- frame principale
    tick = nil,        -- ticker de refresh
}

-- 🔹 Forward-declare la variable locale (évite la capture globale nil)
local _Store

-- 🔹 Définition par assignation (ne pas redéclarer avec `local function _Store`)
_Store = function()
    GuildLogisticsUI_Char = GuildLogisticsUI_Char or {}
    GuildLogisticsUI_Char.groupTracker = GuildLogisticsUI_Char.groupTracker or {}
    local s = GuildLogisticsUI_Char.groupTracker

    s.cooldown   = s.cooldown   or { heal = 300, util = 300, stone = 300 }
    s.expiry     = s.expiry     or {}
    s.segments   = s.segments   or {}
    s.viewIndex  = s.viewIndex  or 1
    s.enabled    = (s.enabled == true)
    s.opacity    = tonumber(s.opacity    or 1.00) or 1.00   -- fonds/bordures
    s.textOpacity= tonumber(s.textOpacity or 1.00) or 1.00  -- texte
    s.btnOpacity = tonumber(s.btnOpacity  or 1.00) or 1.00  -- 🔹 boutons
    s.recording  = (s.recording == true)

    return s
end

local function _RecomputeEnabled()
    local s = _Store()
    local winShown = state.win and state.win:IsShown()
    state.enabled = (winShown or s.recording) and true or false
end

local function _Store()
    GuildLogisticsUI_Char = GuildLogisticsUI_Char or {}
    GuildLogisticsUI_Char.groupTracker = GuildLogisticsUI_Char.groupTracker or {}
    local s = GuildLogisticsUI_Char.groupTracker
    s.cooldown = s.cooldown or { heal = 300, util = 300, stone = 300 }
    s.expiry   = s.expiry   or {} -- [full] = { heal = epoch, util = epoch, stone = epoch }
    s.segments = s.segments or {}
    s.viewIndex = s.viewIndex or 1 -- 0 = live (uniquement en combat), 1 = segment le plus récent
    s.enabled   = (s.enabled == true)
    s.opacity   = tonumber(s.opacity or 0.95) or 0.95 -- transparence fenêtre (0.1..1.0)
    s.textOpacity = tonumber(s.textOpacity or 1.0) or 1.0 -- 🔹 transparence du TEXTE (0.1..1.0)
    s.recording = (s.recording == true) -- Enregistrement en arrière-plan (UI fermée)
    return s
end

-- =========================
-- ===  SESSION COMBAT   ===
-- =========================
local session = {
    inCombat = false,
    label    = nil,     -- nom de la rencontre (boss prioritaire)
    isBoss   = false,
    start    = 0,
    roster   = {},      -- snapshot des joueurs à l'entrée en combat
    hist     = {},      -- [full] = { {t,cat,spellID,spellName}, ... }
}

-- Anti-doublon CLEU : même joueur + même spellID dans une fenêtre courte
local _lastEventTS = {} -- key = guid:spellID (fallback name:spellID) -> epoch
local _DUP_WINDOW = 2.0

local function _antiDupKey(sourceGUID, sourceName, spellID)
    if sourceGUID and sourceGUID ~= "" then
        return tostring(sourceGUID) .. ":" .. tostring(spellID or 0)
    end
    return tostring(sourceName or "") .. ":" .. tostring(spellID or 0)
end

local function _shouldAcceptEvent(sourceGUID, sourceName, spellID, now)
    local k = _antiDupKey(sourceGUID, sourceName, spellID)
    local last = _lastEventTS[k]
    if last and (now - last) < _DUP_WINDOW then
        return false
    end
    _lastEventTS[k] = now
    return true
end

local function _clearLive()
    wipe(session.hist)
    wipe(state.uses)
    wipe(session.roster)
end

local function _pushEvent(full, cat, spellID, spellName, when)
    session.hist[full] = session.hist[full] or {}
    table.insert(session.hist[full], {
        t = when, cat = cat,
        spellID = tonumber(spellID) or 0,
        spellName = tostring(spellName or "")
    })
end

-- =========================
-- ===   OUTILS ROSTER   ===
-- =========================
local function _normalize(full)
    if GLOG and GLOG.NormalizeFull then return GLOG.NormalizeFull(full) end
    if U and U.NormalizeFull then return U.NormalizeFull(full) end
    return tostring(full or "")
end

local function _BuildRosterSet()
    local set = {}
    if IsInRaid and IsInRaid() then
        for i=1,(GetNumGroupMembers() or 0) do
            local u = "raid"..i
            if UnitExists(u) then
                local n, r = UnitName(u)
                set[_normalize((r and r~="" and (n.."-"..r)) or n)] = true
            end
        end
    else
        if UnitExists("player") then
            local n, r = UnitName("player")
            set[_normalize((r and r~="" and (n.."-"..r)) or n)] = true
        end
        for i=1,4 do
            local u = "party"..i
            if UnitExists(u) then
                local n, r = UnitName(u)
                set[_normalize((r and r~="" and (n.."-"..r)) or n)] = true
            end
        end
    end
    return set
end

local function _BuildRosterArrayFromSet(set)
    local arr = {}
    for full in pairs(set) do arr[#arr+1] = full end
    table.sort(arr)
    return arr
end

local function _PurgeStale()
    local s = _Store()
    local roster = _BuildRosterSet()
    for full in pairs(s.expiry or {}) do
        if not roster[full] then s.expiry[full] = nil end
    end
    -- ⚠️ On NE purge PAS s.segments (historique de combats) !
    for full in pairs(state.uses or {}) do
        if not roster[full] then state.uses[full] = nil end
    end
end

-- =========================
-- === NOM DE RENCONTRE ===
-- =========================
local function _findBossName()
    for i=1,5 do
        local u = "boss"..i
        if UnitExists(u) then
            local n = UnitName(u)
            if n and n ~= "" then return n, true end
        end
    end
    return nil, false
end

local function _bestEnemyFromTargets()
    local bestName, bestHP = nil, -1
    if UnitExists("target") and UnitCanAttack("player","target") then
        local hp = UnitHealthMax("target") or 0
        if hp > bestHP then bestHP = hp; bestName = UnitName("target") end
    end
    if UnitExists("focus") and UnitCanAttack("player","focus") then
        local hp = UnitHealthMax("focus") or 0
        if hp > bestHP then bestHP = hp; bestName = UnitName("focus") end
    end
    if IsInRaid and IsInRaid() then
        for i=1,(GetNumGroupMembers() or 0) do
            local u = "raid"..i.."target"
            if UnitExists(u) and UnitCanAttack("player", u) then
                local hp = UnitHealthMax(u) or 0
                if hp > bestHP then bestHP = hp; bestName = UnitName(u) end
            end
        end
    else
        for i=1,4 do
            local u = "party"..i.."target"
            if UnitExists(u) and UnitCanAttack("player", u) then
                local hp = UnitHealthMax(u) or 0
                if hp > bestHP then bestHP = hp; bestName = UnitName(u) end
            end
        end
    end
    return bestName
end

local function _computeEncounterLabel()
    local n, isBoss = _findBossName()
    if n and n ~= "" then return n, true end
    local best = _bestEnemyFromTargets()
    if best and best ~= "" then return best, false end
    return Tr("history_combat") or "Combat", false
end

-- ====== Lookup Data.CONSUMABLE_CATEGORY (ItemID ou SpellID) ======
local _CategoryBySpellID   = {}
local _CategoryBySpellName = {} -- nom de sort (lower) → cat (fallback si ID inconnu)

local function _RebuildCategoryLookup()
    wipe(_CategoryBySpellID)
    wipe(_CategoryBySpellName)

    if not (Data and Data.CONSUMABLE_CATEGORY) then return end

    local function mapSpellFromName(name, cat)
        if not name or name == "" then return end
        local lower = name:lower()
        _CategoryBySpellName[lower] = cat
        if C_Spell and C_Spell.GetSpellInfo then
            local si = C_Spell.GetSpellInfo(name)
            if si and si.spellID then
                _CategoryBySpellID[si.spellID] = cat
            end
        end
    end

    local function mapFromItem(itemID, cat)
        -- Essai immédiat via GetItemSpell (souvent dispo si item en cache)
        local spellName = GetItemSpell and GetItemSpell(itemID)
        if spellName then
            mapSpellFromName(spellName, cat)
            return
        end
        -- Callback asynchrone : quand l'item est chargé, on mappe le sort
        if Item and Item.CreateFromItemID then
            local it = Item:CreateFromItemID(itemID)
            it:ContinueOnItemLoad(function()
                local sn = GetItemSpell and GetItemSpell(itemID)
                if sn then mapSpellFromName(sn, cat) end
            end)
        end
    end

    for id, cat in pairs(Data.CONSUMABLE_CATEGORY) do
        local num = tonumber(id)
        if num then
            -- 1) Si c'est un SpellID valide → direct
            local si = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(num)
            if si and si.spellID then
                _CategoryBySpellID[si.spellID] = cat
                _CategoryBySpellName[(si.name or ""):lower()] = cat
            else
                -- 2) Sinon on interprète comme un ItemID → récupère le sort de l'objet
                mapFromItem(num, cat)
            end
        end
    end
end

local function _detectCategory(spellID, spellName)
    spellID = tonumber(spellID or 0) or 0

    -- (-1) Exclusions explicites (IDs, puis noms)
    if Data and Data.CONSUMABLE_EXCLUDE_SPELLS and Data.CONSUMABLE_EXCLUDE_SPELLS[spellID] then
        return nil
    end
    if Data and Data.CONSUMABLE_EXCLUDE_NAMES and spellName then
        local sn = tostring(spellName or ""):lower()
        if Data.CONSUMABLE_EXCLUDE_NAMES[sn] then
            return nil
        end
    end

    -- 0) Mapping explicite pré-compilé (IDs directs)
    if _CategoryBySpellID[spellID] then
        return _CategoryBySpellID[spellID]
    end

    -- 🔸 Fallback dynamique : essayer de résoudre à la volée depuis les ItemIDs déclarés
    if Data and Data.CONSUMABLE_CATEGORY then
        for id, cat in pairs(Data.CONSUMABLE_CATEGORY) do
            local itemID = tonumber(id)
            if itemID then
                local useName, useSpellID = GetItemSpell and GetItemSpell(itemID)
                -- 1) Match direct sur l'ID du sort d'utilisation
                if useSpellID and useSpellID == spellID then
                    _CategoryBySpellID[spellID] = cat -- cache pour les suivants
                    return cat
                end
                -- 2) Match par nom du sort d'utilisation
                if useName then
                    local si = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(useName)
                    if si and si.spellID == spellID then
                        _CategoryBySpellID[spellID] = cat
                        return cat
                    end
                end
            end
        end
    end

    -- 0-bis) Si jamais Data contenait par erreur un SpellID direct (sécurité)
    if Data and Data.CONSUMABLE_CATEGORY and Data.CONSUMABLE_CATEGORY[spellID] then
        return Data.CONSUMABLE_CATEGORY[spellID]
    end

    -- 1) Healthstone priorité si connue
    if Data and Data.HEALTHSTONE_SPELLS and Data.HEALTHSTONE_SPELLS[spellID] then
        return "stone"
    end

    -- 2) Fallback par nom exact depuis Data (si on n'a pas d'ID mappé)
    local sn = tostring(spellName or ""):lower()
    if _CategoryBySpellName[sn] then
        return _CategoryBySpellName[sn]
    end

    -- 3) Heuristique via icône
    local icon = (C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID) and C_Spell.GetSpellInfo(spellID).iconID) or nil
    if type(icon) == "string" then
        local ic = icon:lower()
        if ic:find("healthstone") or ic:find("inv_stone") then return "stone" end
        if ic:find("inv_potion")  or ic:find("potion")    then return "util"  end
    end

    return nil
end

local function _isGroupSource(flags)
    if not flags then return false end
    local band = bit.band
    local mine  = COMBATLOG_OBJECT_AFFILIATION_MINE or 0x00000001
    local party = COMBATLOG_OBJECT_AFFILIATION_PARTY or 0x00000002
    local raid  = COMBATLOG_OBJECT_AFFILIATION_RAID or 0x00000004
    local player= COMBATLOG_OBJECT_TYPE_PLAYER or 0x00000400
    return (band(flags, player) ~= 0) and (band(flags, mine + party + raid) ~= 0)
end

-- =========================
-- ===     MÀJ DATA     ===
-- =========================
local function _onConsumableUsed(sourceName, cat, spellID, spellName)
    if not sourceName or not cat then return end
    local full = _normalize(sourceName)
    if full == "" then return end

    -- Compteurs (session live combat)
    state.uses[full] = state.uses[full] or { heal=0, util=0, stone=0 }
    state.uses[full][cat] = (state.uses[full][cat] or 0) + 1

    -- Expiration absolue persistante (résiste au /reload)
    local s = _Store()
    s.expiry[full] = s.expiry[full] or {}
    local cd = (GLOG.GroupTrackerGetCooldown and GLOG.GroupTrackerGetCooldown(cat)) or 0
    s.expiry[full][cat] = (time and time() or 0) + cd

    -- Historique live combat
    _pushEvent(full, cat, spellID, spellName, time and time() or 0)

    if state.win and state.win._Refresh then state.win:_Refresh() end
end

-- =========================
-- ===       UI          ===
-- =========================
local function _fmt(rem)
    rem = math.floor(tonumber(rem) or 0 + 0.5)
    if rem <= 0 then
        local ready = Tr("status_ready") or ""
        return "|cff44ff44"..ready.."|r"
    end
    local m = math.floor(rem / 60); local s = rem % 60
    return (m > 0) and string.format("%d:%02d", m, s) or (s .. "s")
end

local function _rowForLive(full)
    local s = _Store()
    local e = s.expiry[full] or {}
    local now = (time and time() or 0)
    local u = state.uses[full] or { heal=0, util=0, stone=0 }
    return {
        name  = full,
        healR = math.max(0, (tonumber(e.heal or 0)  or 0) - now),
        utilR = math.max(0, (tonumber(e.util or 0)  or 0) - now),
        stoneR= math.max(0, (tonumber(e.stone or 0) or 0) - now),
        healN = u.heal or 0,
        utilN = u.util or 0,
        stoneN= u.stone or 0,
    }
end

local function _buildRows()
    local s = _Store()
    local view = tonumber(s.viewIndex or 1) or 1
    local rows = {}

    if session.inCombat and view == 0 then
        -- Vue live combat
        _PurgeStale()
        local roster = _BuildRosterSet()
        do
            local n, r = UnitName("player")
            if n then roster[_normalize((r and r~="" and (n.."-"..r)) or n)] = true end
        end
        for full in pairs(roster) do
            rows[#rows+1] = _rowForLive(full)
        end
        table.sort(rows, function(a,b)
            local ma = math.max(a.healR or 0, a.utilR or 0, a.stoneR or 0)
            local mb = math.max(b.healR or 0, b.utilR or 0, b.stoneR or 0)
            if ma ~= mb then return ma > mb end
            return (a.name or "") < (b.name or "")
        end)
    else
        -- Vue segment (historique) : on affiche les CD restants actuels si présents
        if (not session.inCombat) and view == 0 then view = 1 end
        local seg = s.segments[view]
        if seg then
            local names = {}
            if seg.roster and #seg.roster > 0 then
                for i=1,#seg.roster do names[#names+1] = seg.roster[i] end
            end
            if #names == 0 and seg.data then
                for full in pairs(seg.data) do names[#names+1] = full end
            end
            table.sort(names)
            local now = time and time() or 0
            for _, full in ipairs(names) do
                local evs = (seg.data and seg.data[full] and seg.data[full].events) or {}
                local cnt = { heal=0, util=0, stone=0 }
                for i=1,#evs do
                    local cat = evs[i].cat
                    if cat and cnt[cat] ~= nil then cnt[cat] = cnt[cat] + 1 end
                end
                local e = s.expiry[full] or {}
                local healR = math.max(0, (tonumber(e.heal or 0)  or 0) - now)
                local utilR = math.max(0, (tonumber(e.util or 0)  or 0) - now)
                local stoneR= math.max(0, (tonumber(e.stone or 0) or 0) - now)
                rows[#rows+1] = {
                    name  = full,
                    healR = healR, utilR = utilR, stoneR = stoneR,
                    healN = cnt.heal, utilN = cnt.util, stoneN = cnt.stone,
                }
            end
        end
    end

    return rows
end

local function _CatLabel(cat)
    if cat == "heal"  then return Tr("col_heal_potion") or "" end
    if cat == "stone" then return Tr("col_healthstone") or "" end
    return Tr("col_other_potions") or ""
end

-- Popup standard d'historique pour un joueur (segment courant affiché ou live combat)
local function _ShowHistoryPopup(full)
    local s = _Store()
    local view = tonumber(s.viewIndex or 1) or 1
    local arr

    if session.inCombat and view == 0 then
        arr = session.hist[full] or {}
    else
        if (not session.inCombat) and view == 0 then view = 1 end
        local seg = s.segments[view]
        arr = (seg and seg.data[full] and seg.data[full].events) or {}
    end

    local rows = {}
    for i=1,#arr do rows[i] = arr[i] end
    table.sort(rows, function(a,b) return (a.t or 0) > (b.t or 0) end)

    -- Libellés (segment courant / live)
    local label, posStr
    if session.inCombat and s.viewIndex == 0 then
        label  = session.label or (Tr("history_combat") or "Combat")
        posStr = "[Live]"
    else
        local view2 = (s.viewIndex == 0) and 1 or s.viewIndex
        local seg   = s.segments[view2]
        label  = (seg and seg.label) or (Tr("history_combat") or "Combat")
        posStr = (seg and seg.posStr) or string.format("[%d/%d]", view2, #s.segments)
    end

    -- Popup
    local p = UI.CreatePopup and UI.CreatePopup({
        title  = string.format("%s\n%s",
                  Tr("group_tracker_title"),
                  (GLOG and GLOG.ExtractNameOnly and GLOG.ExtractNameOnly(full)) or full or ""),
        width  = 520,
        height = 360,
        strata = "DIALOG",
        enforceAction = false,
    }) or nil
    if not p then return end

    -- Zone : on libère le footer et on étire la zone de contenu
    do
        local L, R, T, B = 8, 8, 8, 8
        local POP_SIDE, POP_TOP, POP_BOT = (UI.POPUP_SIDE_PAD or 6), (UI.POPUP_TOP_EXTRA_GAP or 18), (UI.POPUP_BOTTOM_LIFT or 4)
        if p.content then
            p.content:ClearAllPoints()
            p.content:SetPoint("TOPLEFT",     p, "TOPLEFT",     L + POP_SIDE, -(T + POP_TOP))
            p.content:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -(R + POP_SIDE), B + POP_BOT)
        end
        if p.footer and p.footer.Hide then p.footer:Hide() end
    end

    -- Liste : rowHeight honoré + scrollbar optionnelle masquée
    local cols = UI.NormalizeColumns({
        { key="time",  title=Tr("col_time"),     w=120,  justify="CENTER" },
        { key="cat",   title=Tr("col_category"), w=120,  justify="CENTER" },
        { key="spell", title=Tr("col_spell"),    min=200, flex=1, justify="LEFT" },
    })

    local lv = UI.ListView(p.content, cols, {
        topOffset = 40,
        buildRow = function(r)
            local w = {}
            w.time  = UI.Label(r, { justify = "CENTER" })
            w.cat   = UI.Label(r, { justify = "CENTER" })
            w.spell = UI.Label(r, { justify = "LEFT" })
            return w
        end,
        updateRow = function(i, r, w, it)
            if not it then return end
            local hhmm = date and date("%H:%M:%S", tonumber(it.t or 0)) or tostring(it.t or "")
            w.time:SetText(hhmm)
            w.cat:SetText(_CatLabel(it.cat))
            w.spell:SetText(it.spellName or "")
        end,
    })

    -- Applique le masquage de la scrollbar + supprime l'espace à droite
    if UI and UI.ListView_SetScrollbarVisible then
        UI.ListView_SetScrollbarVisible(lv, false)
    end

    -- ➕ Transparence (déjà en place)
    state.popup = p
    if p then p._lv = lv end
    do
        local a = (GLOG and GLOG.GroupTracker_GetOpacity and GLOG.GroupTracker_GetOpacity()) or 1
        if UI and UI.ListView_SetVisualOpacity then UI.ListView_SetVisualOpacity(lv, a) end
        if UI and UI.ListView_SetRowGradientOpacity then UI.ListView_SetRowGradientOpacity(lv, a) end
    end

    -- Données
    if lv and lv.SetData then lv:SetData(rows) end

    -- Nettoyage
    state.lastPopup = p
    if p.SetScript then
        p:SetScript("OnHide", function()
            if state.lastPopup == p then state.lastPopup = nil end
            if state.popup == p then state.popup = nil end
        end)
    end
end

-- ===== Vue & navigation =====
local function _setViewIndex(idx)
    local s = _Store()
    local max = #s.segments
    idx = tonumber(idx) or 0
    local minIdx = (session.inCombat and 0) or 1
    if idx < minIdx then idx = minIdx end
    if idx > max then idx = max end
    s.viewIndex = idx
    if state.win and state.win._Refresh then state.win:_Refresh() end
end

-- === Action publique : vider l'historique (avec confirmation) ===
function GLOG.GroupTracker_ClearHistory()
    local s = _Store()
    wipe(s.segments)
    s.viewIndex = session.inCombat and 0 or 1
    if state.win and state.win._Refresh then state.win:_Refresh() end
end

-- Fenêtre principale (épurée via UI.CreatePlainWindow)
local function _ensureWindow()
    if state.win and state.win:IsShown() then return state.win end
    if not (UI and UI.CreatePlainWindow and UI.ListView and UI.NormalizeColumns) then return nil end

    local f = UI.CreatePlainWindow({
        title   = "group_tracker_title",
        width   = 275,
        height  = 308,
        headerHeight = 25,
        strata  = "FULLSCREEN_DIALOG",
        level   = 220,
        saveKey = "GroupTrackerWindow",
        defaultPoint    = "LEFT",
        defaultRelPoint = "LEFT",
        defaultX        = 24,
        defaultY        = 0,
    })
    state.win = f

    -- Conteneur stable pour les boutons de navigation + reset
    if f.hctrl and f.   hctrl.Hide then f.hctrl:Hide() end
    f.hctrl = CreateFrame("Frame", nil, f.header)
    -- Laisse 28 px pour le bouton de fermeture (22 + marge 6)
    f.hctrl:ClearAllPoints()
    f.hctrl:SetPoint("RIGHT", f.header, "RIGHT", -28, 0)
    f.hctrl:SetSize(92, 22) -- largeur suffisante pour 3x20 + espacements
    f.hctrl:SetFrameLevel(f.header:GetFrameLevel() + 3)

    -- '>' (plus récent / vers Live)
    if not f.nextBtn then
        f.nextBtn = CreateFrame("Button", nil, f.hctrl)
        f.nextBtn:SetSize(20, 20)
        local txN = f.nextBtn:CreateTexture(nil, "OVERLAY"); txN:SetAllPoints()
        txN:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
        f.nextBtn:SetScript("OnClick", function()
            local s = _Store()
            _setViewIndex((s.viewIndex or 1) - 1) -- vers plus récent / Live
        end)
    else
        f.nextBtn:SetParent(f.hctrl)
        f.nextBtn:SetSize(20, 20)
    end
    f.nextBtn:ClearAllPoints()
    f.nextBtn:SetPoint("RIGHT", f.hctrl, "RIGHT", 0, 0)
    f.nextBtn:SetFrameLevel(f.hctrl:GetFrameLevel() + 1)

    -- '<' (plus ancien)
    if not f.prevBtn then
        f.prevBtn = CreateFrame("Button", nil, f.hctrl)
        f.prevBtn:SetSize(20, 20)
        local txP = f.prevBtn:CreateTexture(nil, "OVERLAY"); txP:SetAllPoints()
        txP:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
        f.prevBtn:SetScript("OnClick", function()
            local s = _Store()
            _setViewIndex((s.viewIndex or 1) + 1) -- vers plus ancien
        end)
    else
        f.prevBtn:SetParent(f.hctrl)
        f.prevBtn:SetSize(20, 20)
    end
    f.prevBtn:ClearAllPoints()
    f.prevBtn:SetPoint("RIGHT", f.nextBtn, "LEFT", -4, 0)
    f.prevBtn:SetFrameLevel(f.hctrl:GetFrameLevel() + 1)

    -- Corbeille (vider l'historique)
    if f.clearBtn and f.clearBtn.Hide then f.clearBtn:Hide() end
    if not f.clearBtn then
        f.clearBtn = CreateFrame("Button", nil, f.hctrl)
        f.clearBtn:SetSize(20, 20)
        local texPath = "Interface\\PaperDollInfoFrame\\UI-GearManager-LeaveItem-Transparent"
        f.clearBtn:SetNormalTexture(texPath)
        f.clearBtn:SetPushedTexture(texPath)
        f.clearBtn:SetDisabledTexture(texPath)
        f.clearBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        local nrm = f.clearBtn:GetNormalTexture();   if nrm then nrm:SetVertexColor(1, 0.25, 0.25, 1) end
        local psh = f.clearBtn:GetPushedTexture();   if psh then psh:SetVertexColor(1, 0.25, 0.25, 1) end
        local dis = f.clearBtn:GetDisabledTexture(); if dis then dis:SetVertexColor(1, 0.25, 0.25, 0.45); dis:SetDesaturated(true) end
        local hl  = f.clearBtn:GetHighlightTexture(); if hl then hl:SetAlpha(0.22) end
        f.clearBtn:SetScript("OnClick", function()
            if UI and UI.PopupConfirm then
                UI.PopupConfirm(Tr("confirm_clear_history"), function()
                    if GLOG and GLOG.GroupTracker_ClearHistory then
                        GLOG.GroupTracker_ClearHistory()
                    end
                end, nil, { strata = "FULLSCREEN_DIALOG" })
            else
                if GLOG and GLOG.GroupTracker_ClearHistory then
                    GLOG.GroupTracker_ClearHistory()
                end
            end
        end)
        -- Tooltip
        f.clearBtn:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(Tr("btn_reset_data"))
            GameTooltip:Show()
        end)
        f.clearBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    else
        f.clearBtn:SetParent(f.hctrl)
        f.clearBtn:SetSize(20, 20)
    end
    f.clearBtn:ClearAllPoints()
    f.clearBtn:SetPoint("RIGHT", f.prevBtn, "LEFT", -6, 0)
    f.clearBtn:SetFrameLevel(f.hctrl:GetFrameLevel() + 2)

    -- Recalage automatique si la fenêtre est redimensionnée
    f:HookScript("OnSizeChanged", function()
        if not f.hctrl then return end
        f.hctrl:ClearAllPoints()
        f.hctrl:SetPoint("RIGHT", f.header, "RIGHT", -28, 0)
    end)

    -- Colonnes
    local cols = UI.NormalizeColumns({
        { key="name",   title=Tr("col_name"),          w=95, min=95, flex=1, justify="LEFT"  },
        { key="heal",   title=Tr("col_heal_potion"),   w=49,  justify="CENTER" },
        { key="util",   title=Tr("col_other_potions"), w=49,  justify="CENTER" },
        { key="stone",  title=Tr("col_healthstone"),   w=49,  justify="CENTER" },
    })

    local lv = UI.ListView(f.content, cols, {
        topOffset = 0,
        safeRight = false,  -- pas besoin d'espace pour une barre
        rowHeight = 22,
        buildRow = function(r)
            r:EnableMouse(true)
            r:SetScript("OnMouseUp", function(self, button)
                if button == "LeftButton" and self._full then
                    _ShowHistoryPopup(self._full)
                end
            end)
            local w = {}
            w.name  = UI.CreateNameTag(r)
            w.heal  = UI.Label(r, { justify = "CENTER" })
            w.util  = UI.Label(r, { justify = "CENTER" })
            w.stone = UI.Label(r, { justify = "CENTER" })
            return w
        end,
        updateRow = function(i, r, w, it)
            if not it then return end
            r._full = it.name

            -- ✅ Affichage sans serveur, tout en conservant le style (classe/couleur/icone)
            if UI and UI.SetNameTagShort and w.name then
                UI.SetNameTagShort(w.name, it.name or "")
            elseif UI and UI.SetNameTag and w.name then
                -- Fallback si jamais la fonction n’est pas encore chargée
                local short = (ns and ns.Util and ns.Util.ShortenFullName and ns.Util.ShortenFullName(it.name)) or (it.name or "")
                w.name.text:SetText(short)
                UI.SetNameTag(w.name, it.name or "")
            end

            local function cell(rem, n)
                rem = tonumber(rem or 0) or 0
                local base
                if rem <= 0 then
                    local ready = Tr("status_ready") or ""
                    base = "|cff44ff44"..ready.."|r"
                else
                    local m = math.floor(rem / 60); local s = rem % 60
                    base = (m > 0) and string.format("%d:%02d", m, s) or (s .. "s")
                end
                if (n or 0) > 0 then
                    base = base .. " |cffa0a0a0("..tostring(n)..")|r"
                end
                return base
            end
            w.heal:SetText(  cell(it.healR  or 0, it.healN  or 0) )
            w.util:SetText(  cell(it.utilR  or 0, it.utilN  or 0) )
            w.stone:SetText( cell(it.stoneR or 0, it.stoneN or 0) )
        end,

    })
    -- ➕ Référence pour appliquer la transparence aux éléments de la ListView
    f._lv = lv
    do
        local a = (GLOG and GLOG.GroupTracker_GetOpacity and GLOG.GroupTracker_GetOpacity()) or 1
        if UI and UI.ListView_SetVisualOpacity then UI.ListView_SetVisualOpacity(lv, a) end
    end

    -- Libérer totalement l'espace réservé à la scrollbar (popup light)
    do
        -- API de la ListView si disponible
        if lv and lv.HideScrollbar       then lv:HideScrollbar(true) end
        if lv and lv.SetReserveScrollbar then lv:SetReserveScrollbar(false) end
        if lv and lv.SetRightPadding     then lv:SetRightPadding(30) end

        -- Masquer la barre existante
        local sb = lv and (lv.ScrollBar or (lv.scroll and (lv.scroll.ScrollBar or lv.scrollbar)))
        if sb and sb.Hide then
            sb:Hide()
            if sb.SetWidth    then sb:SetWidth(1) end
            if sb.EnableMouse then sb:EnableMouse(false) end
        end

        -- ✅ Re-ancrer le ScrollFrame sur le conteneur principal (évite la boucle de dépendance)
        if lv and lv.scroll and f and f.content and lv.scroll.ClearAllPoints and lv.scroll.SetPoint then
            lv.scroll:ClearAllPoints()
            lv.scroll:SetPoint("TOPLEFT",     f.content, "TOPLEFT",     0, 0)
            lv.scroll:SetPoint("BOTTOMRIGHT", f.content, "BOTTOMRIGHT", 0, 0)
        end
    end

    local function _updateHeaderTitle()
        local s = _Store()
        local f = state.win
        if not f then return end

        -- Garde-fous pour éviter les comparaisons nil
        local segCount = (s.segments and #s.segments) or 0
        local view     = tonumber(s.viewIndex)
        if view == nil then view = (segCount > 0) and 1 or 0 end
        if view < 0 then view = 0 end
        if view > segCount then view = segCount end

        -- ====== Ton bloc : calcul du libellé et de la position ======
        local label, posStr
        if view == 0 then
            -- session "live" (en combat) si disponible
            local session = state.liveSession or s.liveSession or {}
            local inCombat = (session.inCombat == true)
            if not inCombat then
                -- si pas en combat, on retombe sur un segment valide si possible
                if segCount > 0 then
                    view = math.min(tonumber(s.viewIndex or 1) or 1, segCount)
                else
                    view = 1
                end
            end

            label  = session.label or Tr("history_combat")
            posStr = "[Live]"
        else
            if (not s.segments or not s.segments[view]) and segCount > 0 then
                -- garde-fou si view est hors bornes
                view = math.min(math.max(view, 1), segCount)
            end
            label  = (s.segments and s.segments[view] and s.segments[view].label) or Tr("history_combat")
            posStr = string.format("[%d/%d]", view, segCount)
        end

        -- Titre de la fenêtre principale (on NE TOUCHE PAS au titre de la popup ici)
        if f.title and f.title.SetText then
            f.title:SetText(string.format("%s %s\n%s",
                Tr("group_tracker_title"), posStr or "", label or ""))
        elseif f.header and f.header.title and f.header.title.SetText then
            f.header.title:SetText(string.format("%s - %s %s",
                Tr("group_tracker_title"), label or "", posStr or ""))
        end

        -- États/alpha des boutons (multiplie par l'opacité des boutons)
        local canNext  = (view > 1)
        local canPrev  = (view < segCount)
        local canClear = (segCount > 0)

        if f.nextBtn  then f.nextBtn:SetEnabled(canNext)  end
        if f.prevBtn  then f.prevBtn:SetEnabled(canPrev)  end
        if f.clearBtn then f.clearBtn:SetEnabled(canClear) end

        local sA = (GLOG and GLOG.GroupTracker_GetButtonsOpacity and GLOG.GroupTracker_GetButtonsOpacity()) or 1
        if UI and UI.SetButtonAlphaScaled then
            if f.nextBtn  then UI.SetButtonAlphaScaled(f.nextBtn,  canNext  and 1 or 0.35, sA) end
            if f.prevBtn  then UI.SetButtonAlphaScaled(f.prevBtn,  canPrev  and 1 or 0.35, sA) end
            if f.clearBtn then UI.SetButtonAlphaScaled(f.clearBtn, canClear and 1 or 0.35, sA) end
            if f.close    then UI.SetButtonAlphaScaled(f.close,    1.00,          sA) end
        else
            if f.nextBtn  then f.nextBtn:SetAlpha(canNext  and 1 or 0.35) end
            if f.prevBtn  then f.prevBtn:SetAlpha(canPrev  and 1 or 0.35) end
            if f.clearBtn then f.clearBtn:SetAlpha(canClear and 1 or 0.35) end
        end
    end


    function f:_Refresh()
        local rows = _buildRows()
        if lv and lv.SetData then lv:SetData(rows) end
        -- Sécurise l'appel si la fonction n'est pas encore injectée
        if _updateHeaderTitle then _updateHeaderTitle() end
    end


    -- Ticker : mise à jour continue quand visible
    if state.tick and state.tick.Cancel then state.tick:Cancel() end
    if C_Timer and C_Timer.NewTicker then
        state.tick = C_Timer.NewTicker(1, function()
            if f:IsShown() then f:_Refresh() end
        end)
    end

    f:Show()
    f:_Refresh()
    return f
end

-- =========================
-- ===   API PUBLIQUE   ===
-- =========================
function GLOG.GroupTrackerIsEnabled()
    return _Store().enabled == true
end

function GLOG.GroupTrackerSetEnabled(on)
    local s = _Store()
    s.enabled = (on == true)
    state.enabled = s.enabled
    if on then
        GLOG.GroupTracker_ShowWindow(true)
    else
        GLOG.GroupTracker_ShowWindow(false)
    end
end

function GLOG.GroupTrackerSetCooldown(cat, sec)
end

function GLOG.GroupTrackerGetCooldown(cat)
    return 300
end

function GLOG.GroupTracker_Reset()
    _clearLive()
    local s = _Store(); wipe(s.expiry)
    if state.win and state.win._Refresh then state.win:_Refresh() end
end

function GLOG.GroupTracker_ClearHistory()
    local s = _Store()
    wipe(s.segments)
    s.viewIndex = session.inCombat and 0 or 1
    if state.win and state.win._Refresh then state.win:_Refresh() end
end

function GLOG.GroupTracker_ShowWindow(show)
    local s = _Store()
    if show then
        state.enabled = true
        _ensureWindow()
        if state.win then
            -- 🔸 Opacité des cadres (fonds/bordures), 0..1
            local a = (GLOG.GroupTracker_GetOpacity and GLOG.GroupTracker_GetOpacity()) or 0.95
            if UI and UI.SetFrameVisualOpacity then
                UI.SetFrameVisualOpacity(state.win, a)
            end

            -- ➕ Applique aussi l’opacité aux éléments visuels de la ListView
            if state.win._lv and UI and UI.ListView_SetVisualOpacity then
                UI.ListView_SetVisualOpacity(state.win._lv, a)
            end

            -- 🔸 Opacité du texte & des boutons (indépendante)
            local ta = (GLOG.GroupTracker_GetTextOpacity and GLOG.GroupTracker_GetTextOpacity()) or 1.0
            if UI and UI.ApplyTextAlpha then UI.ApplyTextAlpha(state.win, ta) end
            if UI and UI.ApplyButtonsAlpha then UI.ApplyButtonsAlpha(state.win, ta) end

            -- Ancrage par défaut si nécessaire (bord gauche)
            if not state.win._glog_default_anchored then
                local hasPoints = (state.win.GetNumPoints and state.win:GetNumPoints() or 0) > 0
                if not hasPoints then
                    state.win:ClearAllPoints()
                    state.win:SetPoint("LEFT", UIParent, "LEFT", 24, 0)
                end
                state.win._glog_default_anchored = true
            end

            state.win:Show()

            -- 🔹 Applique l'opacité des boutons à l'ouverture de la fenêtre
            if UI and UI.ApplyButtonsOpacity and GLOG and GLOG.GroupTracker_GetButtonsOpacity then
                UI.ApplyButtonsOpacity(state.win, GLOG.GroupTracker_GetButtonsOpacity())
            end
            if state.win._Refresh then state.win:_Refresh() end
        end
    else
        if state.win and state.win.Hide then state.win:Hide() end
        local winShown = state.win and state.win:IsShown()
        state.enabled = (winShown or s.recording) and true or false
    end
end

function GLOG.GroupTracker_GetOpacity()
    local s = _Store()
    local a = tonumber(s.opacity or 1) or 1
    if a < 0 then a = 0 elseif a > 1 then a = 1 end
    return a
end

function GLOG.GroupTracker_SetOpacity(a)
    local s = _Store()
    a = tonumber(a or 0.95) or 0.95
    if a < 0 then a = 0 elseif a > 1 then a = 1 end
    s.opacity = a

    -- Fenêtre principale
    if state.win and UI and UI.SetFrameVisualOpacity then
        UI.SetFrameVisualOpacity(state.win, a)
    end
        -- ➕ Et sur la ListView de la fenêtre principale
        if state.win._lv and UI and UI.ListView_SetVisualOpacity then
            UI.ListView_SetVisualOpacity(state.win._lv, a)
        end

    -- Popup d'historique + ListView interne
    if state.popup then
        if UI and UI.SetFrameVisualOpacity then UI.SetFrameVisualOpacity(state.popup, a) end
        if state.popup._lv and UI and UI.ListView_SetVisualOpacity then
            UI.ListView_SetVisualOpacity(state.popup._lv, a)
        end
    end
end

function GLOG.GroupTracker_GetTextOpacity()
    local s = _Store()
    local a = tonumber(s.textOpacity or 1.0) or 1.0
    if a < 0.1 then a = 0.1 elseif a > 1 then a = 1 end
    return a
end

function GLOG.GroupTracker_SetTextOpacity(a)
    local s = _Store()
    a = tonumber(a or 1.0) or 1.0
    if a < 0.1 then a = 0.1 elseif a > 1 then a = 1 end
    s.textOpacity = a
    if state.win and UI and UI.ApplyTextAlpha then
        UI.ApplyTextAlpha(state.win, a)
    end
end

function GLOG.GroupTracker_GetButtonsOpacity()
    local s = _Store()
    local a = tonumber(s.btnOpacity or 1.0) or 1.0
    if a < 0 then a = 0 elseif a > 1 then a = 1 end
    return a
end

function GLOG.GroupTracker_SetButtonsOpacity(a)
    local s = _Store()
    a = tonumber(a or 1.0) or 1.0
    if a < 0 then a = 0 elseif a > 1 then a = 1 end
    s.btnOpacity = a

    -- Applique immédiatement à la fenêtre principale (si ouverte)
    if state.win and UI and UI.ApplyButtonsOpacity then
        UI.ApplyButtonsOpacity(state.win, a)
    end
    -- Applique à la popup d’historique (si ouverte)
    if state.popup and UI and UI.ApplyButtonsOpacity then
        UI.ApplyButtonsOpacity(state.popup, a)
    end
end


function GLOG.GroupTracker_GetRecordingEnabled()
    local s = _Store()
    return s.recording == true
end

function GLOG.GroupTracker_SetRecordingEnabled(enabled)
    local s = _Store()
    s.recording = (enabled == true)

    if s.recording then
        -- Le suivi est activé : on ne force pas l'ouverture de la fenêtre ici.
        -- (/glog track s'en charge si besoin)
        _RecomputeEnabled()
    else
        -- Le suivi est désactivé : masquer la fenêtre si elle est ouverte
        if state.win and state.win:IsShown() then
            GLOG.GroupTracker_ShowWindow(false) -- fera aussi _RecomputeEnabled()
        else
            _RecomputeEnabled()
        end
    end
end

function GLOG.GroupTracker_IsPopupTitleHidden()
    local s = _Store()
    return s.popupTitleTextHidden == true
end

function GLOG.GroupTracker_SetPopupTitleHidden(hidden)
    local s = _Store()
    s.popupTitleTextHidden = (hidden == true)
    if state.popup and UI and UI.SetFrameTitleVisibility then
        UI.SetFrameTitleVisibility(state.popup, not s.popupTitleTextHidden)
    end
end

function GLOG.GroupTracker_TogglePopupTitleHidden()
    local s = _Store()
    GLOG.GroupTracker_SetPopupTitleHidden(not (s.popupTitleTextHidden == true))
end

-- =========================
-- ===      EVENTS      ===
-- =========================
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("ENCOUNTER_START")

ev:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        local s = _Store()
         _RebuildCategoryLookup()
        state.enabled = (s.enabled == true)

        session.inCombat = UnitAffectingCombat("player") and true or false
        if session.inCombat then
            local lbl, isBoss = _computeEncounterLabel()
            session.label  = lbl
            session.isBoss = isBoss
            session.start  = time and time() or 0
            s.viewIndex = 0  -- live
            session.roster = _BuildRosterArrayFromSet(_BuildRosterSet())
        else
            if #s.segments == 0 then
                local maxIdx = #s.segments
                if s.viewIndex == 0 then
                    s.viewIndex = math.min(1, maxIdx) -- tu étais en Live → on reste sur le dernier combat créé (1)
                else
                    s.viewIndex = math.min(s.viewIndex or 1, maxIdx) -- ne pas sauter vers un "nouveau" segment
                end
            else
                if (s.viewIndex or 1) == 0 then s.viewIndex = 1 end
            end
        end

        if state.enabled then GLOG.GroupTracker_ShowWindow(true) end

    elseif event == "ADDON_LOADED" then
        local name = ...
        if name == ADDON then
            _RebuildCategoryLookup()
        end

    elseif event == "PLAYER_LOGIN" then
        _RebuildCategoryLookup()

    elseif event == "BAG_UPDATE_DELAYED" then
        _RebuildCategoryLookup()
    
    elseif event == "GROUP_ROSTER_UPDATE" then
        _PurgeStale()
        if state.win and state.win._Refresh then state.win:_Refresh() end

    elseif event == "ENCOUNTER_START" then
        local _, encounterName = ...
        if encounterName and encounterName ~= "" then
            session.label  = encounterName
            session.isBoss = true
        end
        if state.win and state.win._Refresh then state.win:_Refresh() end

    elseif event == "PLAYER_REGEN_DISABLED" then
        _clearLive()
        session.inCombat = true
        session.start    = time and time() or 0
        local lbl, isBoss = _computeEncounterLabel()
        session.label  = lbl
        session.isBoss = isBoss
        session.roster = _BuildRosterArrayFromSet(_BuildRosterSet())
        _Store().viewIndex = 0  -- Live
        if state.win and state.win._Refresh then state.win:_Refresh() end

    elseif event == "PLAYER_REGEN_ENABLED" then
        local s = _Store()
        local seg = {
            label  = session.label or (Tr("history_combat") or "Combat"),
            start  = session.start or (time and time() or 0),
            stop   = time and time() or 0,
            isBoss = (session.isBoss == true),
            roster = {},
            data   = {},
        }
        for i=1,#session.roster do seg.roster[i] = session.roster[i] end
        for i=1,#seg.roster do
            local full = seg.roster[i]
            seg.data[full] = seg.data[full] or { events = {} }
        end
        for full, arr in pairs(session.hist) do
            seg.data[full] = seg.data[full] or { events = {} }
            for i=1,#arr do seg.data[full].events[i] = arr[i] end
        end

        table.insert(s.segments, 1, seg)
        while #s.segments > 30 do table.remove(s.segments, #s.segments) end

        session.inCombat = false
        _clearLive()

        local maxIdx = #s.segments
        if s.viewIndex == 0 then
            s.viewIndex = math.min(1, maxIdx)
        else
            s.viewIndex = math.min(s.viewIndex or 1, maxIdx)
        end
        if state.win and state.win._Refresh then state.win:_Refresh() end

    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if not state.enabled then return end
        local _, sub, _, sourceGUID, sourceName, sourceFlags, _, destGUID, destName, _, _, spellID, spellName =
            CombatLogGetCurrentEventInfo()
        if not _isGroupSource(sourceFlags) then return end

        if (sub == "SPELL_CAST_SUCCESS" or sub == "SPELL_AURA_APPLIED") then
            local cat = _detectCategory(spellID, spellName)
            if cat then
                local now = (time and time() or 0)
                -- ✅ Anti-doublon : ignore APPLIED si CAST_SUCCESS vient d’arriver (et vice-versa)
                if _shouldAcceptEvent(sourceGUID, (sourceName or destName), spellID, now) then
                    _onConsumableUsed(sourceName or destName, cat, spellID, spellName)
                end
            end
        end
    end
end)
