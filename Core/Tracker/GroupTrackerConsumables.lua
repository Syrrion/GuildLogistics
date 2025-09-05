local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
ns.UI   = ns.UI   or {}
ns.Util = ns.Util or {}
ns.Data = ns.Data or {}

local GLOG, UI, U, Data = ns.GLOG, ns.UI, ns.Util, ns.Data
local Tr = ns.Tr or function(s) return s end

local _G = _G
if setfenv then
    setfenv(1, setmetatable({}, { __index = _G, __newindex = _G }))
end

-- =========================
-- === LOOKUP CONSOMMABLES ==
-- =========================

-- Lookup Data.CONSUMABLE_CATEGORY (ItemID ou SpellID)
local _CategoryBySpellID   = {}
local _CategoryBySpellName = {} -- nom de sort (lower) → cat (fallback si ID inconnu)

-- Cache local pour GetItemSpell (évite les appels répétés)
local _ItemSpellCache = {} -- [itemID] = { sid = <spellID|false>, name = <useName|false> }

-- SpellID -> ItemID (pour récupérer l'icône d'objet si le sort provient d'un item)
local _ItemBySpellID = {}

-- =========================
-- === LOOKUP PERSONNALISÉ ==
-- =========================

local _CustomBySpellID   = {}   -- [spellID] = { colId1, colId2, ... }
local _CustomByKeyword   = {}   -- [lowerKeyword] = { colId1, colId2, ... }
local _CustomColsOrdered = {}   -- { {id=..., label=...}, ... } (colonnes actives)
local _CustomCooldownById= {}   -- [colId] = "heal"|"util"|"stone"|nil

-- =========================
-- === UTILITAIRES ITEMS ===
-- =========================

local function _GetUseFromItem(itemID)
    local iid = tonumber(itemID)
    if not iid then return nil, nil end
    local c = _ItemSpellCache[iid]
    if c then return (c.sid or nil), (c.name or nil) end
    local useName, useSpellID = GetItemSpell and GetItemSpell(iid)
    _ItemSpellCache[iid] = { sid = useSpellID or false, name = useName or false }
    return useSpellID, useName
end

-- Icône robuste pour un sort/objet : priorité à l'item si connu, sinon icône du sort
local function _GetSpellOrItemIcon(spellID)
    local sid = tonumber(spellID or 0) or 0
    if sid <= 0 then
        return "Interface/Icons/INV_Misc_QuestionMark"
    end
    local iid = _ItemBySpellID[sid]
    if iid and GetItemIcon then
        local icon = GetItemIcon(iid)
        if icon then return icon end
    end
    if C_Spell and C_Spell.GetSpellInfo then
        local si = C_Spell.GetSpellInfo(sid)
        if si and si.iconID then return si.iconID end
    end
    if GetSpellTexture then
        local tex = GetSpellTexture(sid)
        if tex then return tex end
    end
    return "Interface/Icons/INV_Misc_QuestionMark"
end

-- =========================
-- === REBUILD LOOKUP ===
-- =========================

local function _RebuildCategoryLookup()
    wipe(_CategoryBySpellID)
    wipe(_CategoryBySpellName)
    wipe(_ItemBySpellID)

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
        if useSpellID then
            mapSpellID(useSpellID, cat)
            _ItemBySpellID[useSpellID] = iid
        end
        if useName then
            _CategoryBySpellName[tostring(useName):lower()] = cat
        end
        -- Callback quand l'item est (re)chargé
        if (not useName or not useSpellID) and Item and Item.CreateFromItemID then
            local it = Item:CreateFromItemID(iid)
            it:ContinueOnItemLoad(function()
                local n2, s2 = GetItemSpell and GetItemSpell(iid)
                if s2 then
                    mapSpellID(s2, cat)
                    _ItemBySpellID[s2] = iid
                end
                if n2 then
                    _CategoryBySpellName[tostring(n2):lower()] = cat
                end
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
end

local function _RebuildCustomLookup()
    wipe(_CustomCooldownById)
    wipe(_CustomBySpellID)
    wipe(_CustomByKeyword)
    wipe(_CustomColsOrdered)

    local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
    local cfg = store.custom or {}
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

    -- Déduplication par id (évite d'empiler les colonnes à l'init)
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

-- =========================
-- === NORMALISATION ===
-- =========================

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

-- Détermine si un sort doit être exclu (par ID normalisé ou par nom)
local function _IsExcluded(spellID, spellName)
    local sid = _NormalizeSpellID(tonumber(spellID or 0) or 0)
    if Data and Data.CONSUMABLE_EXCLUDE_SPELLS and Data.CONSUMABLE_EXCLUDE_SPELLS[sid] then
        return true
    end
    if Data and Data.CONSUMABLE_EXCLUDE_NAMES and spellName and spellName ~= "" then
        local sn = tostring(spellName or ""):lower()
        if Data.CONSUMABLE_EXCLUDE_NAMES[sn] then
            return true
        end
    end
    return false
end

-- =========================
-- === DÉTECTION CATÉGORIE ===
-- =========================

local function _detectCategory(spellID, spellName)
    -- 0) Normaliser l'ID (overrides → base)
    spellID = _NormalizeSpellID(tonumber(spellID or 0) or 0)

    -- (-1) Exclusions explicites (IDs, puis noms)
    if _IsExcluded(spellID, spellName) then
        return nil
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

-- =========================
-- === COLONNES PERSONNALISÉES ===
-- =========================

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

-- =========================
-- === HELPERS POUR UI ===
-- =========================

local function _CatLabel(cat)
    if cat == "heal"    then return Tr("col_heal_potion")   or "" end
    if cat == "util"    then return Tr("col_other_potions") or "" end
    if cat == "stone"   then return Tr("col_healthstone")   or "" end
    if cat == "cddef"   then return Tr("col_cddef")         or "" end
    if cat == "dispel"  then return Tr("col_dispel")        or "" end
    if cat == "taunt"   then return Tr("col_taunt")         or "" end
    if cat == "move"    then return Tr("col_move")          or "" end
    if cat == "kick"    then return Tr("col_kick")          or "" end
    if cat == "cc"      then return Tr("col_cc")            or "" end
    if cat == "special" then return Tr("col_special")       or "" end

    -- Colonnes personnalisées : "c:<id>"
    if type(cat) == "string" and cat:find("^c:") then
        local id = cat:match("^c:(.+)$")
        if id and id ~= "" then
            local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
            local cols = (store.custom and store.custom.columns) or {}
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

-- =========================
-- === SEED LISTES DÉFAUT ===
-- =========================

-- Seed des listes par défaut (Potions, Prépot, Pierre de soins)
local function _EnsureDefaultCustomLists(force)
    local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
    store.custom = store.custom or {}
    store.custom.columns = store.custom.columns or {}
    store.custom.nextId  = tonumber(store.custom.nextId or 1) or 1

    local targetVer = tonumber((Data and Data.POTIONS_SEED_VERSION) or 0) or 0
    local applied   = tonumber(store.custom.seedVersion_potions or 0) or 0
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
    local dispelSpells,  dispelItems  = collectByCategory("dispel")
    local tauntSpells,   tauntItems   = collectByCategory("taunt")
    local moveSpells,    moveItems    = collectByCategory("move")
    local kickSpells,    kickItems    = collectByCategory("kick")
    local ccSpells,      ccItems      = collectByCategory("cc")
    local specialSpells, specialItems = collectByCategory("special")

    -- Fonction helper pour ajouter/mettre à jour une colonne
    local function addOrUpdateColumn(columnData)
        if ns.GLOG and ns.GLOG.GroupTracker_Custom_AddOrUpdate then
            ns.GLOG.GroupTracker_Custom_AddOrUpdate(columnData)
        end
    end

    -- Configuration des colonnes par défaut
    local defaultColumns = {
        {
            id = "DEFAULT_POTIONS",
            label = Tr("col_heal_potion"),
            enabled = true,
            spellIDs = healSpells,
            itemIDs = healItems,
            keywords = {},
            cooldownCat = "heal",
        },
        {
            id = "DEFAULT_PREPOT",
            label = Tr("col_other_potions"),
            enabled = true,
            spellIDs = utilSpells,
            itemIDs = utilItems,
            keywords = {},
            cooldownCat = "util",
        },
        {
            id = "DEFAULT_STONE",
            label = Tr("col_healthstone"),
            enabled = true,
            spellIDs = stoneSpells,
            itemIDs = stoneItems,
            keywords = {},
            cooldownCat = "stone",
        },
        {
            id = "DEFAULT_CDDEF",
            label = Tr("col_cddef"),
            enabled = true,
            spellIDs = cddefSpells,
            itemIDs = cddefItems,
            keywords = {},
        },
        {
            id = "DEFAULT_DISPEL",
            label = Tr("col_dispel"),
            enabled = true,
            spellIDs = dispelSpells,
            itemIDs = dispelItems,
            keywords = {},
        },
        {
            id = "DEFAULT_TAUNT",
            label = Tr("col_taunt"),
            enabled = false,
            spellIDs = tauntSpells,
            itemIDs = tauntItems,
            keywords = {},
        },
        {
            id = "DEFAULT_MOVE",
            label = Tr("col_move"),
            enabled = false,
            spellIDs = moveSpells,
            itemIDs = moveItems,
            keywords = {},
        },
        {
            id = "DEFAULT_KICK",
            label = Tr("col_kick"),
            enabled = false,
            spellIDs = kickSpells,
            itemIDs = kickItems,
            keywords = {},
        },
        {
            id = "DEFAULT_CC",
            label = Tr("col_cc"),
            enabled = false,
            spellIDs = ccSpells,
            itemIDs = ccItems,
            keywords = {},
        },
        {
            id = "DEFAULT_SPECIAL",
            label = Tr("col_special"),
            enabled = false,
            spellIDs = specialSpells,
            itemIDs = specialItems,
            keywords = {},
        },
    }

    -- Ajout de toutes les colonnes par défaut
    for _, columnData in ipairs(defaultColumns) do
        addOrUpdateColumn(columnData)
    end

    store.custom.seedVersion_potions = targetVer
end

-- =========================
-- ===   API PUBLIQUE    ===
-- =========================

ns.GroupTrackerConsumables = {
    -- Rebuild des lookups
    RebuildCategoryLookup = function() _RebuildCategoryLookup() end,
    RebuildCustomLookup = function() _RebuildCustomLookup() end,
    
    -- Détection
    DetectCategory = function(spellID, spellName) return _detectCategory(spellID, spellName) end,
    MatchCustomColumns = function(spellID, spellName) return _MatchCustomColumns(spellID, spellName) end,
    IsExcluded = function(spellID, spellName) return _IsExcluded(spellID, spellName) end,
    NormalizeSpellID = function(spellID) return _NormalizeSpellID(spellID) end,
    
    -- Utilitaires
    GetSpellOrItemIcon = function(spellID) return _GetSpellOrItemIcon(spellID) end,
    GetUseFromItem = function(itemID) return _GetUseFromItem(itemID) end,
    GetCategoryLabel = function(cat) return _CatLabel(cat) end,
    GetEnabledCustomColumnsOrdered = function() return _GetEnabledCustomColumnsOrdered() end,
    
    -- Accès aux données de lookup
    GetCustomCooldownById = function() return _CustomCooldownById end,
    GetItemBySpellID = function() return _ItemBySpellID end,
    
    -- Seed des listes par défaut
    EnsureDefaultCustomLists = function(force) _EnsureDefaultCustomLists(force == true) end,
}

-- Export vers le namespace global pour compatibilité
ns.GLOG.GroupTrackerConsumables = ns.GroupTrackerConsumables
