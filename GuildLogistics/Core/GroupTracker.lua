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
    -- 🔹 Suivi personnalisé : structure de configuration
    s.custom = s.custom or {}
    s.custom.columns = s.custom.columns or {}
    s.custom.nextId  = tonumber(s.custom.nextId or 1) or 1

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
    s.winOpen = (s.winOpen == true)
    -- Visibilité des 3 dernières colonnes (fenêtre flottante du Tracker)
    s.colVis = s.colVis or { heal = true, util = true, stone = true }
    -- 🔹 Suivi personnalisé : structure de configuration
    s.custom = s.custom or {}
    s.custom.columns = s.custom.columns or {}
    s.custom.nextId  = tonumber(s.custom.nextId or 1) or 1

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

    -- Source unique : Data.CONSUMABLES_TYPED (ItemIDs + SpellIDs)
    if not (Data and Data.CONSUMABLES_TYPED) then return end

    local function mapSpellID(spellID, cat)
        local sid = tonumber(spellID)
        if not sid then return end
        _CategoryBySpellID[sid] = cat
        if C_Spell and C_Spell.GetSpellInfo then
            local si = C_Spell.GetSpellInfo(sid)
            if si and si.name then
                _CategoryBySpellName[(si.name or ""):lower()] = cat
            end
        end
    end

    local function mapItemID(itemID, cat)
        local iid = tonumber(itemID)
        if not iid then return end
        -- Essai immédiat (si item en cache)
        local useName, useSpellID = GetItemSpell and GetItemSpell(iid)
        if useSpellID then mapSpellID(useSpellID, cat) end
        if useName   then _CategoryBySpellName[tostring(useName):lower()] = cat end
        -- Callback quand l'item est (re)chargé
        if (not useName or not useSpellID) and Item and Item.CreateFromItemID then
            local it = Item:CreateFromItemID(iid)
            it:ContinueOnItemLoad(function()
                local n2, s2 = GetItemSpell and GetItemSpell(iid)
                if s2 then mapSpellID(s2, cat) end
                if n2 then _CategoryBySpellName[tostring(n2):lower()] = cat end
            end)
        end
    end

    for cat, lists in pairs(Data.CONSUMABLES_TYPED) do
        if type(lists) == "table" then
            if type(lists.spells) == "table" then
                for _, sid in ipairs(lists.spells) do mapSpellID(sid, cat) end
            end
            if type(lists.items) == "table" then
                for _, iid in ipairs(lists.items) do mapItemID(iid, cat) end
            end
        end
    end

    -- Santé : support optionnel des Healthstones explicitement déclarées
    if Data and Data.HEALTHSTONE_SPELLS then
        for sid, ok in pairs(Data.HEALTHSTONE_SPELLS) do
            if ok then mapSpellID(sid, "stone") end
        end
    end
end

-- Normalise un SpellID vers son sort « de base » (gère les overrides/talents)
local function _NormalizeSpellID(id)
    id = tonumber(id or 0) or 0
    if id <= 0 then return id end

    if FindBaseSpellByID then
        local base = FindBaseSpellByID(id)
        if base and base > 0 then return base end
    end
    if FindSpellOverrideByID then
        local ov = FindSpellOverrideByID(id)
        if ov and ov > 0 and ov ~= id then
            if FindBaseSpellByID then
                local base2 = FindBaseSpellByID(ov)
                if base2 and base2 > 0 then return base2 end
            end
            return ov
        end
    end
    return id
end

local function _detectCategory(spellID, spellName)
    -- 0) Normaliser l'ID (overrides → base)
    spellID = _NormalizeSpellID(tonumber(spellID or 0) or 0)

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

    -- 1) Mapping explicite par ID (précompilé depuis Data)
    if _CategoryBySpellID[spellID] then
        return _CategoryBySpellID[spellID]
    end

    -- 2) Fallback par NOM (précompilé depuis Data — sûr car limité à tes listes)
    if spellName and spellName ~= "" then
        local sn = tostring(spellName):lower()
        local catByName = _CategoryBySpellName[sn]
        if catByName then
            return catByName
        end
    end

    -- 3) Heuristique via icône (ultime secours)
    local si = C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
    local icon = si and si.iconID or nil
    if type(icon) == "string" then
        local ic = icon:lower()
        if ic:find("healthstone") or ic:find("inv_stone") then return "stone" end
        if ic:find("inv_potion")  or ic:find("potion")    then return "util"  end
    end

    return nil
end


-- ====== Suivi personnalisé : lookup rapide ======
local _CustomBySpellID   = {}   -- [spellID] = { colId1, colId2, ... }
local _CustomByKeyword   = {}   -- [lowerKeyword] = { colId1, colId2, ... }
local _CustomColsOrdered = {}   -- { {id=..., label=...}, ... } (colonnes actives)
local _CustomCooldownById= {}   -- [colId] = "heal"|"util"|"stone"|nil

local function _RebuildCustomLookup()
    wipe(_CustomCooldownById)
    wipe(_CustomBySpellID)
    wipe(_CustomByKeyword)
    wipe(_CustomColsOrdered)

    local s   = _Store()
    local cfg = s.custom or {}
    local cols = cfg.columns or {}

    local function addSpellMap(sid, colId)
        sid = tonumber(sid)
        if not sid then return end
        _CustomBySpellID[sid] = _CustomBySpellID[sid] or {}
        table.insert(_CustomBySpellID[sid], tostring(colId))
    end

    local function addKeyword(key, colId)
        key = tostring(key or ""):lower()
        if key == "" then return end
        _CustomByKeyword[key] = _CustomByKeyword[key] or {}
        table.insert(_CustomByKeyword[key], tostring(colId))
    end

    -- 🔒 Déduplication par id (évite d'empiler les colonnes à l'init)
    local seen = {}

    for idx, c in ipairs(cols) do
        if c and (c.enabled ~= false) and (tostring(c.label or "") ~= "") then
            local id = tostring(c.id or "")
            if id == "" then id = tostring(idx) end
            if not seen[id] then
                table.insert(_CustomColsOrdered, { id = id, label = tostring(c.label) })
                seen[id] = true

                if c.cooldownCat then
                    _CustomCooldownById[id] = tostring(c.cooldownCat)
                end
                if type(c.spellIDs) == "table" then
                    for _, sid in ipairs(c.spellIDs) do addSpellMap(sid, id) end
                end
                if type(c.itemIDs) == "table" and GetItemSpell then
                    for _, iid in ipairs(c.itemIDs) do
                        local _, sid = GetItemSpell(tonumber(iid) or 0)
                        if sid then addSpellMap(sid, id) end
                    end
                end
                if type(c.keywords) == "table" then
                    for _, kw in ipairs(c.keywords) do addKeyword(kw, id) end
                end
            end
        end
    end
end


local function _MatchCustomColumns(spellID, spellName)
    local res, seen = {}, {}
    local sid = tonumber(spellID) or 0
    for _, id in ipairs(_CustomBySpellID[sid] or {}) do
        if not seen[id] then res[#res+1] = id; seen[id] = true end
    end
    local name = tostring(spellName or ""):lower()
    if name ~= "" then
        for key, arr in pairs(_CustomByKeyword) do
            if string.find(name, key, 1, true) then
                for _, id in ipairs(arr) do
                    if not seen[id] then res[#res+1] = id; seen[id] = true end
                end
            end
        end
    end
    return res
end

local function _GetEnabledCustomColumnsOrdered()
    local out, seen = {}, {}
    for _, c in ipairs(_CustomColsOrdered) do
        local id = tostring(c.id or "")
        if id ~= "" and not seen[id] then
            table.insert(out, { id = id, label = tostring(c.label or "") })
            seen[id] = true
        end
    end
    return out
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

-- Compteur pour colonnes personnalisées
local function _onCustomUsed(sourceName, colId, spellID, spellName)
    if not sourceName or not colId then return end
    local full = _normalize(sourceName)
    if full == "" then return end

    state.uses[full] = state.uses[full] or { heal=0, util=0, stone=0 }
    state.uses[full].custom = state.uses[full].custom or {}
    state.uses[full].custom[tostring(colId)] = (state.uses[full].custom[tostring(colId)] or 0) + 1

    -- Historique live combat (cat = "c:<id>")
    _pushEvent(full, "c:"..tostring(colId), spellID, spellName, time and time() or 0)

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
    if cat == "heal"   then return Tr("col_heal_potion")   or "" end
    if cat == "util"   then return Tr("col_other_potions") or "" end
    if cat == "stone"  then return Tr("col_healthstone")   or "" end
    if cat == "cddef"  then return Tr("col_cddef")         or "" end

    -- Colonnes personnalisées : "c:<id>"
    if type(cat) == "string" and cat:find("^c:") then
        local id = cat:match("^c:(.+)$")
        if id and id ~= "" then
            local s = _Store()
            local cols = (s.custom and s.custom.columns) or {}
            for i=1,#cols do
                if tostring(cols[i].id) == tostring(id) then
                    return tostring(cols[i].label or "")
                end
            end
        end
    end

    -- Fallback
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
        topOffset = 0,
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

    -- ➕ Transparence
    state.popup = p
    if p then p._lv = lv end
    do
        local a = (GLOG and GLOG.GroupTracker_GetOpacity and GLOG.GroupTracker_GetOpacity()) or 1
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


-- Applique la visibilité des colonnes (heal/util/stone) à un frame contenant la ListView
local function _ApplyColumnsVisibilityToFrame(f)
    if not (f and f._lv) then return end
    local lv = f._lv
    local s  = _Store()
    local vis = s.colVis or { heal=true, util=true, stone=true }

    local base = f._baseCols or lv.cols or {}
    local cols = {}

    -- lookup : idCustom → "heal"|"util"|"stone" (pour colonnes en mode cooldown)
    local cooldownById = {}
    do
        local cfg = s.custom or {}
        for _, c in ipairs(cfg.columns or {}) do
            if c and (c.enabled ~= false) and c.cooldownCat then
                cooldownById[tostring(c.id)] = tostring(c.cooldownCat)
            end
        end
    end

    for _, c in ipairs(base) do
        local cc = {}
        for k, v in pairs(c) do cc[k] = v end
        local key = tostring(cc.key or "")
        local show = true

        -- Colonnes personnalisées « cust:ID » : respectent la visibilité de leur catégorie cooldown
        if key:find("^cust:") then
            local id  = key:match("^cust:(.+)$")
            local cat = id and cooldownById[id]
            if cat and (vis[cat] == false) then
                show = false
            end
        end

        if not show then
            cc.w, cc.min, cc.flex = 0, 0, 0
        end
        cols[#cols+1] = cc
    end

    lv.cols = cols
    if lv.header and UI and UI.LayoutHeader then
        UI.LayoutHeader(lv.header, lv.cols, lv.hLabels)
    end
    if lv.Refresh then lv:Refresh() elseif lv.Layout then lv:Layout() end
end

-- Calcule la largeur minimale requise par la ListView + bordures
local function _ComputeMinWindowWidth(f)
    if not (f and f._lv) then
        return math.max(200, (f and f:GetWidth() or 200))
    end
    local lv = f._lv
    local cols = lv.cols or {}

    local sum, visible = 0, 0
    for _, c in ipairs(cols) do
        -- On prend la meilleure estimation "minimale" : max(w, min)
        local w   = tonumber(c and c.w)   or 0
        local wmn = tonumber(c and c.min) or 0
        local ww  = math.max(w, wmn, 0)

        if ww > 0 then
            sum = sum + ww
            visible = visible + 1
        end
    end

    local colSpacing = 0
    local spacing    = (visible > 0) and (colSpacing * (visible - 1)) or 0
    local scrollW    = (lv.scroll and 16) or 16 -- largeur scroll barre verticale
    local padX       = (lv.padX or 12) * 2      -- padding interne ListView
    local frameEdge  = 28                       -- marges/bordures de la fenêtre

    local minW = sum + spacing + scrollW + padX + frameEdge
    -- On borne pour éviter une fenêtre trop petite
    return math.max(50, math.floor(minW + 0.5))
end

-- Applique la largeur minimale ET ajuste la largeur active (snap)
local function _ApplyMinWidthAndResize(f, snapToMin)
    if not f then return end
    local minW = _ComputeMinWindowWidth(f)
    local minH = 160

    if f.SetResizeBounds then
        f:SetResizeBounds(minW, minH)
    elseif f.SetMinResize then
        f:SetMinResize(minW, minH)
    end

    -- Adaptation automatique de la largeur active :
    -- - Si on ajoute une colonne => élargit à minW
    -- - Si on retire une colonne => réduit à minW
    if snapToMin ~= false then
        f:SetWidth(minW)
    else
        -- Variante "non agressive" (on n'utilise pas ici) : seulement si trop petit
        local cur = f:GetWidth() or minW
        if cur < minW then f:SetWidth(minW) end
    end
end

-- Fenêtre principale (épurée via UI.CreatePlainWindow)
local function _ensureWindow()
    if state.win and state.win:IsShown() then return state.win end
    if not (UI and UI.CreatePlainWindow and UI.ListView and UI.NormalizeColumns) then return nil end

    local f = UI.CreatePlainWindow({
        title   = "group_tracker_title",
        height  = 160,
        headerHeight = 25,
        strata  = "FULLSCREEN_DIALOG",
        level   = 220,
        saveKey = "GroupTrackerWindow",
        defaultPoint    = "LEFT",
        defaultRelPoint = "LEFT",
        defaultX        = 24,
        defaultY        = 0,
        contentPadBottomExtra = -30,
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
-- Colonnes (plus de colonnes statiques heal/util/stone)
    local cols = UI.NormalizeColumns({
        { key="name", title=Tr("col_name"), min=50, flex=1, justify="LEFT" },
    })

    -- ➕ Colonnes personnalisées actives
    local _customCols = _GetEnabledCustomColumnsOrdered()
    for _, c in ipairs(_customCols) do
        table.insert(cols, { key = "cust:"..tostring(c.id), title = tostring(c.label), w = 54, justify = "CENTER" })
    end

    -- Table de correspondance "colonne custom" → catégorie cooldown ('heal'|'util'|'stone')
    local _cooldownById = {}
    do
        local s = _Store()
        local cfg = s.custom or {}
        for _, c in ipairs(cfg.columns or {}) do
            if c and (c.enabled ~= false) and c.cooldownCat then
                _cooldownById[tostring(c.id)] = tostring(c.cooldownCat)
            end
        end
    end

    local lv = UI.ListView(f.content, cols, {
        topOffset = 0,
        rowHeight = 22,
        buildRow = function(r)
            r:EnableMouse(true)
            r:SetScript("OnMouseUp", function(self, button)
                if button == "LeftButton" and self._full then
                    _ShowHistoryPopup(self._full)
                end
            end)
            local w = {}
            w.name = UI.CreateNameTag(r)
            -- Champs dynamiques pour toutes les colonnes personnalisées
            if _customCols then
                for _, c in ipairs(_customCols) do
                    w["cust:"..tostring(c.id)] = UI.Label(r, { justify = "CENTER" })
                end
            end
            return w
        end,
        updateRow = function(i, r, w, it)
            if not it then return end
            r._full = it.name

            -- ✅ Affichage sans serveur, tout en conservant le style
            if UI and UI.SetNameTagShort and w.name then
                UI.SetNameTagShort(w.name, it.name or "")
            elseif UI and UI.SetNameTag and w.name then
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

            local function timerFor(cat)
                if cat == "heal"  then return (it.healR  or 0),  (it.healN  or 0) end
                if cat == "util"  then return (it.utilR  or 0),  (it.utilN  or 0) end
                if cat == "stone" then return (it.stoneR or 0),  (it.stoneN or 0) end
                return 0, 0
            end

            -- Colonnes personnalisées : certaines en cooldown (timer), les autres en compteur
            if _customCols then
                local s = _Store()
                local view = tonumber(s.viewIndex or 1) or 1
                local function customCount(full, colId)
                    if session.inCombat and view == 0 then
                        local cu = state.uses[full] and state.uses[full].custom or {}
                        return tonumber(cu[tostring(colId)] or 0) or 0
                    else
                        if (not session.inCombat) and view == 0 then view = 1 end
                        local seg = s.segments[view]
                        if not seg then return 0 end
                        local evs = (seg.data and seg.data[full] and seg.data[full].events) or {}
                        local key = "c:"..tostring(colId)
                        local n = 0
                        for i=1,#evs do if evs[i].cat == key then n = n + 1 end end
                        return n
                    end
                end

                for _, c in ipairs(_customCols) do
                    local field = w["cust:"..tostring(c.id)]
                    if field and field.SetText then
                        local cat = _cooldownById[tostring(c.id)]
                        if cat == "heal" or cat == "util" or cat == "stone" then
                            local rem, n = timerFor(cat)
                            field:SetText(cell(rem, n))
                        else
                            local n = customCount(it.name, c.id)
                            field:SetText((n > 0) and tostring(n) or "|cffaaaaaa—|r")
                        end
                    end
                end
            end
        end,

    })
    -- ➕ Référence pour appliquer la transparence aux éléments de la ListView
    f._lv = lv
    do
        local a = (GLOG and GLOG.GroupTracker_GetOpacity and GLOG.GroupTracker_GetOpacity()) or 1
        if UI and UI.ListView_SetVisualOpacity then UI.ListView_SetVisualOpacity(lv, a) end
    end

    -- Mémorise le modèle de colonnes pour les recalculs (show/hide)
    f._baseCols = cols
    -- Applique la visibilité des colonnes selon les préférences
    _ApplyColumnsVisibilityToFrame(f)
    -- Ajuste la largeur minimale ET la largeur active selon les colonnes visibles
    _ApplyMinWidthAndResize(f, true)

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
            -- session "live" (en combat)
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
    local s = _Store()
    s.cooldown = s.cooldown or { heal = 300, util = 300, stone = 300 }
    if cat and s.cooldown[cat] ~= nil then
        s.cooldown[cat] = math.max(0, tonumber(sec) or s.cooldown[cat] or 300)
    end
end

function GLOG.GroupTrackerGetCooldown(cat)
    local s = _Store()
    local cd = (s.cooldown and s.cooldown[cat or ""]) or 300
    return tonumber(cd) or 300
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
        if not state.win then return end

        local f = state.win
        
        -- 🧷 Mémorise l’ouverture et hooke OnShow/OnHide (une seule fois)
        s.winOpen = true
        if not f._openStateHooked then
            f:HookScript("OnShow", function()
                local st = _Store()
                st.winOpen = true
                _RecomputeEnabled()
            end)
            f:HookScript("OnHide", function()
                local st = _Store()
                st.winOpen = false
                _RecomputeEnabled()
            end)
            f._openStateHooked = true
        end

        -- Applique les réglages actuels
        local aWin  = (GLOG.GroupTracker_GetOpacity        and GLOG.GroupTracker_GetOpacity())       or 0.95
        local aText = (GLOG.GroupTracker_GetTextOpacity    and GLOG.GroupTracker_GetTextOpacity())   or 1.00
        local aBtnS = (GLOG.GroupTracker_GetButtonsOpacity and GLOG.GroupTracker_GetButtonsOpacity()) or 1.00
        local rowH  = (GLOG.GroupTracker_GetRowHeight      and GLOG.GroupTracker_GetRowHeight())     or 22

        if UI and UI.SetFrameVisualOpacity then UI.SetFrameVisualOpacity(f, aWin) end
        if UI and UI.SetTextAlpha         then UI.SetTextAlpha(f, aText)            end
        if f._lv and UI and UI.ListView_SetVisualOpacity then UI.ListView_SetVisualOpacity(f._lv, aWin) end
        if f._lv and UI and UI.ListView_SetRowHeight     then UI.ListView_SetRowHeight(f._lv, rowH)     end
        -- Respecte le masquage/affichage des colonnes choisi par l’utilisateur
        _ApplyColumnsVisibilityToFrame(f)
        -- Adapte la largeur minimale + largeur active en fonction des colonnes visibles
        _ApplyMinWidthAndResize(f, true)

        -- Assure une ancre gauche du titre (déjà fait côté PlainWindow, on sécurise)
        if f.title and f.header then
            f.title:ClearAllPoints()
            f.title:SetPoint("LEFT", f.header, "LEFT", 8, 0)
            if f.title.SetJustifyH then f.title:SetJustifyH("LEFT") end
        end

        -- Le X ferme toute la fenêtre (sécurisation)
        if f.close then
            f.close:SetScript("OnClick", function() f:Hide() end)
        end

        f:Show()
        if f._Refresh then f:_Refresh() end
    else
        state.enabled = false
        local s = _Store()
        s.winOpen = false
        if state.win then state.win:Hide() end
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

-- === Visibilité des colonnes (fenêtre flottante) ===
function GLOG.GroupTracker_GetColumnVisible(key)
    local s = _Store()
    local v = (s.colVis or {})[tostring(key or "")]
    if v == nil then return true end
    return v == true
end

function GLOG.GroupTracker_SetColumnVisible(key, visible)
    key = tostring(key or "")
    if key ~= "heal" and key ~= "util" and key ~= "stone" then return end
    local s = _Store()
    s.colVis = s.colVis or { heal=true, util=true, stone=true }
    s.colVis[key] = (visible == true)

    -- Applique immédiatement si la fenêtre est ouverte
    if state.win then _ApplyColumnsVisibilityToFrame(state.win) end
    -- Ajuste la largeur minimale et la largeur active (réduction/agrandissement auto)
    if state.win then _ApplyMinWidthAndResize(state.win, true) end

end

-- Hauteur de ligne de la listview (fenêtre minimaliste)
function GLOG.GroupTracker_GetRowHeight()
    local s = _Store()
    local h = tonumber(s.rowHeight or 22) or 22
    if h < 12 then h = 12 elseif h > 48 then h = 48 end
    return h
end

function GLOG.GroupTracker_SetRowHeight(px)
    local s = _Store()
    local v = tonumber(px)
    if not v then return end
    if v < 12 then v = 12 elseif v > 48 then v = 48 end
    s.rowHeight = v

    -- Si la fenêtre est ouverte, applique immédiatement
    if state and state.win and state.win._lv and UI and UI.ListView_SetRowHeight then
        UI.ListView_SetRowHeight(state.win._lv, v)
        if state.win._Refresh then state.win:_Refresh() end
    end
end

-- === API Suivi personnalisé (CRUD colonnes) ===
function GLOG.GroupTracker_Custom_List()
    local s = _Store()
    return (s.custom and s.custom.columns) or {}
end

function GLOG.GroupTracker_Custom_AddOrUpdate(obj)
    if type(obj) ~= "table" then return nil end
    local s = _Store()
    s.custom = s.custom or {}; s.custom.columns = s.custom.columns or {}; s.custom.nextId = tonumber(s.custom.nextId or 1) or 1

    local function normList(t)
        local out = {}
        if type(t) == "table" then
            for _, v in ipairs(t) do
                local n = tonumber(v)
                if n then table.insert(out, n) end
            end
        end
        return out
    end
    obj.spellIDs = normList(obj.spellIDs)
    obj.itemIDs  = normList(obj.itemIDs)
    local kws = {}
    if type(obj.keywords) == "table" then
        for _, k in ipairs(obj.keywords) do
            local s = tostring(k or ""):gsub("^%s+",""):gsub("%s+$","")
            if s ~= "" then table.insert(kws, s) end
        end
    end
    obj.keywords = kws

    local id = tostring(obj.id or "")
    if id == "" then
        id = "C" .. tostring(s.custom.nextId)
        s.custom.nextId = s.custom.nextId + 1
        obj.id = id
        table.insert(s.custom.columns, obj)
    else
        local found = false
        for i, c in ipairs(s.custom.columns) do
            if tostring(c.id) == id then
                s.custom.columns[i] = obj
                found = true
                break
            end
        end
        if not found then table.insert(s.custom.columns, obj) end
    end

    _RebuildCustomLookup()
    if GLOG and GLOG.GroupTracker_RecreateWindow then GLOG.GroupTracker_RecreateWindow() end
    return id
end

function GLOG.GroupTracker_Custom_Delete(id)
    local s = _Store()
    local cols = (s.custom and s.custom.columns) or {}
    for i = #cols, 1, -1 do
        if tostring(cols[i].id) == tostring(id) then table.remove(cols, i) end
    end
    _RebuildCustomLookup()
    if GLOG and GLOG.GroupTracker_RecreateWindow then GLOG.GroupTracker_RecreateWindow() end
end

function GLOG.GroupTracker_RecreateWindow()
    if state.win then
        local wasOpen = state.win:IsShown()
        state.win:Hide()
        state.win = nil
        if wasOpen and GLOG and GLOG.GroupTracker_ShowWindow then
            GLOG.GroupTracker_ShowWindow(true)
        end
    end
end

-- === Seed des listes par défaut (Potions, Prépot, Pierre de soins) ===
local function _EnsureDefaultCustomLists(force)
    local s = _Store()
    s.custom = s.custom or {}
    s.custom.columns = s.custom.columns or {}
    s.custom.nextId  = tonumber(s.custom.nextId or 1) or 1

    local targetVer = tonumber((Data and Data.POTIONS_SEED_VERSION) or 0) or 0
    local applied   = tonumber(s.custom.seedVersion_potions or 0) or 0
    if not force and applied >= targetVer then
        return
    end

    local function uniqPush(dst, seen, v)
        local n = tonumber(v)
        if not n then return end
        if not seen[n] then table.insert(dst, n); seen[n] = true end
    end

    local function collectByCategory(cat)
        local spells, items = {}, {}
        local seenS, seenI = {}, {}
        if Data and Data.CONSUMABLES_TYPED and Data.CONSUMABLES_TYPED[cat] then
            local t = Data.CONSUMABLES_TYPED[cat]
            if type(t.spells) == "table" then
                for _, sid in ipairs(t.spells) do uniqPush(spells, seenS, sid) end
            end
            if type(t.items) == "table" then
                for _, iid in ipairs(t.items) do uniqPush(items, seenI, iid) end
            end
        end
        return spells, items
    end

    local healSpells, healItems   = collectByCategory("heal")
    local utilSpells, utilItems   = collectByCategory("util")
    local stoneSpells, stoneItems = collectByCategory("stone")
    local cddefSpells, cddefItems = collectByCategory("cddef")

    -- 1) Potions (util)
    -- Potions de soin → catégorie 'heal'
    GLOG.GroupTracker_Custom_AddOrUpdate({
        id       = "DEFAULT_POTIONS",
        label    = Tr("col_heal_potion"),
        enabled  = true,
        spellIDs = healSpells,
        itemIDs  = healItems,
        keywords = {},
        cooldownCat = "heal",
    })

    -- Prépot → catégorie 'util'
    GLOG.GroupTracker_Custom_AddOrUpdate({
        id       = "DEFAULT_PREPOT",
        label    = Tr("col_other_potions"),
        enabled  = true,
        spellIDs = utilSpells,
        itemIDs  = utilItems,
        keywords = {},
        cooldownCat = "util",
    })

    -- Pierre de soins → catégorie 'stone'
    GLOG.GroupTracker_Custom_AddOrUpdate({
        id       = "DEFAULT_STONE",
        label    = Tr("col_healthstone"),
        enabled  = true,
        spellIDs = stoneSpells,
        itemIDs  = stoneItems,
        keywords = {},
        cooldownCat = "stone",
    })

    -- Pierre de soins → catégorie 'stone'
    GLOG.GroupTracker_Custom_AddOrUpdate({
        id       = "DEFAULT_CDDEF",
        label    = Tr("col_cddef"),
        enabled  = true,
        spellIDs = cddefSpells,
        itemIDs  = cddefItems,
        keywords = {},
    })


    s.custom.seedVersion_potions = targetVer
end

-- API publique (appelable côté Events)
function GLOG.GroupTracker_EnsureDefaultCustomLists(force)
    _EnsureDefaultCustomLists(force == true)
end


function GLOG.GroupTracker_RebuildCustomMapping()
    _RebuildCustomLookup()
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
ev:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")

ev:SetScript("OnEvent", function(_, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        local s = _Store()
        _RebuildCategoryLookup()
        _RebuildCustomLookup()
        -- Seed des listes par défaut du suivi personnalisé (versionné)
        if GLOG and GLOG.GroupTracker_EnsureDefaultCustomLists then
            GLOG.GroupTracker_EnsureDefaultCustomLists(false)
        end

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

        -- Démarrage : si la fenêtre était ouverte la dernière fois, on la rouvre
        if s.winOpen == true then
            GLOG.GroupTracker_ShowWindow(true)
        else
            _RecomputeEnabled() 
        end

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

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if not state.enabled then return end
        local unit, castGUID, spellID = ...
        if not unit or not spellID then return end
        if unit ~= "player" and (not unit:find("^raid") and not unit:find("^party")) then return end
        -- On confie l'enregistrement au CLEU pour éviter tout doublon (CAST_SUCCESS/AURA_APPLIED).
        return


    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        if not state.enabled then return end
        local ts, sub, _, sourceGUID, sourceName, sourceFlags, _, destGUID, destName, _, _, spellID, spellName =
            CombatLogGetCurrentEventInfo()
        if not _isGroupSource(sourceFlags) then return end

        -- On garde CAST_SUCCESS et AURA_APPLIED (utile pour potions/pierres).
        if sub == "SPELL_CAST_SUCCESS" or sub == "SPELL_AURA_APPLIED" then
            local normID = _NormalizeSpellID(spellID)
            local sName  = spellName or (GetSpellInfo and select(1, GetSpellInfo(normID))) or ""
            local cat    = _detectCategory(normID, sName)
            local ids    = _MatchCustomColumns(normID, sName)

            if not cat and #ids == 0 then return end

            local now = ts or GetTime() -- même base partout pour la dédup
            local who = sourceName or destName
            if not _shouldAcceptEvent(sourceGUID, who, normID, now) then return end

            -- 🔸 Règle d’enregistrement unique (évite les doublons et l'entrée vide) :
            if cat == "heal" or cat == "util" or cat == "stone" then
                -- Ces catégories alimentent le timer + compteur
                _onConsumableUsed(who, cat, normID, sName)
                -- Pas d'_onCustomUsed en plus : les colonnes lisent déjà ces compteurs
            elseif cat == "cddef" then
                -- Défensifs : uniquement le/les compteurs de colonnes custom
                if #ids > 0 then
                    for _, cid in ipairs(ids) do _onCustomUsed(who, cid, normID, sName) end
                else
                    _onConsumableUsed(who, "cddef", normID, sName) -- fallback si pas de colonne
                end
            else
                -- Pas de cat connue mais colonnes custom matchées
                for _, cid in ipairs(ids) do _onCustomUsed(who, cid, normID, sName) end
            end
        end
    end
end)
