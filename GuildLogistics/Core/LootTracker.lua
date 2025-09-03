local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
ns.UI   = ns.UI   or {}
ns.Util = ns.Util or {}

local GLOG, UI, U = ns.GLOG, ns.UI, ns.Util
local Tr = ns.Tr or function(s) return s end
-- Boss/loot context helpers (forward declarations)
local _getCtx, _putCtx, _getCtxByLink
local _SaveLastMPlus, _LoadLastMPlus, _BackfillMPlus
local _GetRollFor, _RememberRoll
local _IsLootReceiptMessage, _IsSelfLootMessage

-- Stubs de sécurité (évite tout appel sur nil pendant /reload)
_GetRollFor   = _GetRollFor   or function() return nil, nil end
_RememberRoll = _RememberRoll or function() end

-- Dernier niveau M+ vu (persiste tant qu'on n'a pas un nouveau > 0)
local _mplusLevelLast = 0
-- Niveau M+ courant (API live)
local _mplusLevel = 0

local function _UpdateActiveKeystoneLevel()
    local level = 0
    if C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo then
        local _, lv = C_ChallengeMode.GetActiveKeystoneInfo()
        level = tonumber(lv or 0) or 0
    end
    _mplusLevel = level
    if level > 0 then
        _SaveLastMPlus(level)
    end

end

-- Getter public pour l'UI et les fallbacks Core
function GLOG.GetActiveKeystoneLevel()
    -- 1) Essai API "live"
    if C_ChallengeMode then
        if C_ChallengeMode.GetActiveKeystoneInfo then
            local _, lv = C_ChallengeMode.GetActiveKeystoneInfo()
            local v = tonumber(lv or 0) or 0
            if v > 0 then _SaveLastMPlus(v); return v end
        end
        -- 1b) Essai info de complétion (post-coffre)
        if C_ChallengeMode.GetCompletionInfo then
            local ok, a,b,c,d,e,f,g = pcall(C_ChallengeMode.GetCompletionInfo)
            if ok then
                -- Cherche un entier plausible (2..50) dans les retours
                local candidates = {a,b,c,d,e,f,g}
                for _,vv in ipairs(candidates) do
                    local n = tonumber(vv)
                    if n and n >= 2 and n <= 50 then _SaveLastMPlus(n); return n end
                end
            end
        end
    end
    -- 2) Valeur courante suivie (session)
    if (_mplusLevel or 0) > 0 then return _mplusLevel end
    -- 3) Dernière valeur connue dans la session
    if (_mplusLevelLast or 0) > 0 then return _mplusLevelLast end
    -- 4) Fallback persistant (<=3h)
    local saved = (_LoadLastMPlus and _LoadLastMPlus()) or 0
    if saved > 0 then return saved end
    return 0
end


-- Centralisation via Core/Events.lua
do
    local function _onMPlusEvent() _UpdateActiveKeystoneLevel() end
    ns.Events.Register("CHALLENGE_MODE_KEYSTONE_SLOTTED", _onMPlusEvent)
    ns.Events.Register("CHALLENGE_MODE_START",            _onMPlusEvent)
    ns.Events.Register("CHALLENGE_MODE_COMPLETED",        _onMPlusEvent)
    ns.Events.Register("CHALLENGE_MODE_RESET",            _onMPlusEvent)
    ns.Events.Register("PLAYER_ENTERING_WORLD",           _onMPlusEvent)
end
-- Init au chargement (utile si on /reload en pleine clé)

_UpdateActiveKeystoneLevel()

-- =========================
-- ===   STORE per-char  ===
-- =========================
local function _Store()
    GuildLogisticsDatas_Char = GuildLogisticsDatas_Char or {}
    local s = GuildLogisticsDatas_Char
    s.equipLoots = s.equipLoots or {}  -- liste d’entrées
    return s.equipLoots
end

-- === Config (par perso) pour le log de butin =========================
local function _Config()
    GuildLogisticsDatas_Char = GuildLogisticsDatas_Char or {}
    local s = GuildLogisticsDatas_Char
    s.config = s.config or {}
    local c = s.config
    -- Valeurs par défaut
    local EPIC = tonumber((Enum and Enum.ItemQuality and Enum.ItemQuality.Epic) or 4) or 4
    if c.lootMinQuality      == nil then c.lootMinQuality      = EPIC end                    -- épique par défaut
    if c.lootMinReqLevel     == nil then c.lootMinReqLevel     = 80 end
    if c.lootEquippableOnly  == nil then c.lootEquippableOnly  = true end
    if c.lootMinItemLevel    == nil then c.lootMinItemLevel    = 0 end
    if c.lootInstanceOnly    == nil then c.lootInstanceOnly    = true end
    return c
end
-- ====================================================================

-- =========================
-- ===   M+ level cache  ===
-- =========================
_SaveLastMPlus = function(level)
    level = tonumber(level or 0) or 0
    if level <= 0 then return end
    _mplusLevelLast = level
    GuildLogisticsDatas_Char = GuildLogisticsDatas_Char or {}
    local s = GuildLogisticsDatas_Char
    s._mplus = s._mplus or {}
    s._mplus.last = level
    s._mplus.ts   = (time and time()) or 0
end

_LoadLastMPlus = function()
    GuildLogisticsDatas_Char = GuildLogisticsDatas_Char or {}
    local s = GuildLogisticsDatas_Char
    local last = tonumber(s._mplus and s._mplus.last) or 0
    local ts   = tonumber(s._mplus and s._mplus.ts) or 0
    -- On accepte une valeur récente (< 3h) pour du backfill post-run
    if last > 0 and ts > 0 then
        local now = (time and time()) or 0
        if now == 0 or (now - ts) <= (3 * 60 * 60) then
            return last
        end
    end
    return 0
end

-- Essaie de compléter le niveau M+ pour les entrées récentes avec ce lien
_BackfillMPlus = function(link)
    if not link or not GLOG or not GLOG.GetActiveKeystoneLevel then return end
    local lv = tonumber(GLOG.GetActiveKeystoneLevel()) or 0
    if lv <= 0 then return end
    local list = _Store()
    -- on ne parcourt que les 30 premières lignes pour éviter le coût
    local maxn = math.min(#list, 30)
    local changed = false
    for i = 1, maxn do
        local it = list[i]
        if it and it.link == link and tonumber(it.diffID or 0) == 8 then
            if tonumber(it.mplus or 0) == 0 then
                it.mplus = lv
                changed = true
            end
        end
    end
    if changed and UI and UI.RefreshAll then UI.RefreshAll() end
end

local function _Now() return (time and time()) or 0 end

local function _fmtTime(ts)
    local t = date("*t", ts or _Now())
    return ("%02d:%02d:%02d"):format(t.hour or 0, t.min or 0, t.sec or 0)
end

local function _GetEquippedIlvl()
    if GetAverageItemLevel then
        local overall, equipped = GetAverageItemLevel()
        return math.floor((equipped or overall or 0) + 0.5)
    end
    return 0
end

-- Résolution nom d'instance depuis instID (UIMapID / instanceMapID)
local _mapNameCache = {}
function GLOG.ResolveInstanceName(instID)
    id = tonumber(instID or 0) or 0
    if id <= 0 then return "" end
    if _mapNameCache[instID] ~= nil then return _mapNameCache[instID] end

    local name = ""
    name = (GetRealZoneText and GetRealZoneText(instID))
    _mapNameCache[instID] = name or ""

    return _mapNameCache[instID]
end

-- Retourne: ok, instID, diffID, mplusLevel
-- instID = instanceMapID (fallback: UIMapID via C_Map.GetBestMapForUnit("player"))
local function _InstanceContext()
    -- Donjon / Raid / Scénario
    local inInst, instType = false, nil
    if IsInInstance then
        local a, b = IsInInstance()
        inInst, instType = (a and true) or false, b
    end
    if inInst and (instType == "party" or instType == "raid" or instType == "scenario") then
        local diffID, mplus, instID = 0, 0, 0
        if GetInstanceInfo then
            -- 8e retour = mapID de l'instance
            local _, _, did, _, _, _, _, mapID = GetInstanceInfo()
            diffID = tonumber(did) or 0

            -- On tente de convertir le mapID en ID Encounter Journal
            local ejID = nil
            if C_EncounterJournal and C_EncounterJournal.GetInstanceForMap then
                ejID = C_EncounterJournal.GetInstanceForMap(tonumber(mapID or 0) or 0)
            end

            instID = tonumber(ejID or 0) or 0  -- ✅ priorité à l'ID EJ
            if instID == 0 then
                instID = tonumber(mapID or 0) or 0  -- fallback: on garde le mapID
            end
        end

        do
            local lv = (GLOG and GLOG.GetActiveKeystoneLevel and GLOG.GetActiveKeystoneLevel()) or 0
            mplus = tonumber(lv) or 0
        end

        if (mplus == 0) and diffID == 8 then
            mplus = tonumber(_mplusLevel) or 0
        end
        if mplus <= 0 then mplus = nil end

        return true, instID, diffID, mplus
    end

    -- Gouffres (Delves)
    if C_Scenario and C_Scenario.IsInScenario and C_Scenario.IsInScenario() then
        local instID = 0
        local mapID = 0
        if GetInstanceInfo and IsInInstance and select(1, IsInInstance()) then
            local _, _, _, _, _, _, _, mid = GetInstanceInfo()
            mapID = tonumber(mid or 0) or 0
        end
        if mapID == 0 and C_Map and C_Map.GetBestMapForUnit then
            mapID = tonumber(C_Map.GetBestMapForUnit("player") or 0) or 0
        end
        -- Tentative d'ID EJ d'abord
        if C_EncounterJournal and C_EncounterJournal.GetInstanceForMap and mapID > 0 then
            local ejID = C_EncounterJournal.GetInstanceForMap(mapID)
            instID = tonumber(ejID or 0) or 0
        end
        if instID == 0 then
            instID = mapID -- fallback: on garde le UiMapID
        end

        local diffID = 0
        return true, instID, diffID, nil
    end

    return false
end

local function _ExtractLink(msg)
    if not msg then return nil end
    -- capture le 1er lien objet
    return msg:match("(|Hitem:%d+:[^|]+|h%[[^%]]+%]|h)") or msg:match("(|Hitem:[^|]+|h[^|]+|h)")
end

local function _IsEquippable(link)
    return (link and IsEquippableItem and IsEquippableItem(link)) and true or false
end

-- Snapshot du groupe/raid au moment de l'enregistrement
local function _SnapshotGroup()
    local roster = {}

    local function addUnit(unit)
        if UnitExists and UnitExists(unit) then
            local full = (GetUnitName and GetUnitName(unit, true)) or UnitName(unit)
            if full and full ~= "" then table.insert(roster, full) end
        end
    end

    if IsInRaid and IsInRaid() then
        local n = tonumber(GetNumGroupMembers and GetNumGroupMembers()) or 0
        for i = 1, n do addUnit("raid"..i) end
    elseif IsInGroup and IsInGroup() then
        -- party1..party4 n'inclut pas le joueur
        for i = 1, 4 do addUnit("party"..i) end
        addUnit("player")
    else
        addUnit("player")
    end

    -- Optionnel: tri pour une stabilité d'affichage/stockage
    table.sort(roster, function(a, b) return tostring(a) < tostring(b) end)
    return roster
end

-- Tente de déduire le looter depuis le message (self/groupe/raid)
local function _NameInGroupFromMessage(msg)
    if not msg or msg == "" then return UnitName("player") end

    -- Détection "moi" via modèles localisés
    local selfLoot = false
    local function matchPat(gs)
        if not gs then return false end
        local pat = tostring(gs):gsub("%%s", ".-"):gsub("%%d", "%%d+")
        return msg:find(pat, 1, false) ~= nil
    end
    if matchPat(LOOT_ITEM_SELF) or matchPat(LOOT_ITEM_SELF_MULTIPLE) or matchPat(LOOT_ITEM_PUSHED_SELF) then
        selfLoot = true
    end
    if selfLoot then return UnitName("player") end

    -- Pour les autres joueurs : on teste Name et Name-Realm avant le lien objet
    local linkPos = msg:find("|Hitem:", 1, true) or #msg + 1
    local function inHead(name)
        if not name or name == "" then return false end
        local idx = msg:find(name, 1, true)
        return idx and (idx < linkPos)
    end

    if IsInGroup and IsInGroup() then
        local n = GetNumGroupMembers() or 0
        local isRaid = IsInRaid and IsInRaid()
        for i = 1, n do
            local unit = isRaid and ("raid"..i) or ("party"..i)
            local short = UnitName(unit)
            local full  = GetUnitName and GetUnitName(unit, true) or short
            if inHead(full) then return full end
            if inHead(short) then return short end
        end
    end

    -- Dernier recours: si on trouve 'Nom-' juste avant le lien, on capture 'Nom-Realm'
    do
        local head = msg:sub(1, linkPos-1)
        local cand = head:match("([%w\128-\255'%-]+%-%w+)$") or head:match("([%w\128-\255'%-]+)$")
        if cand and cand ~= "" then return cand end
    end

    -- Si on n'a pas pu déterminer un nom et que ce n'est pas "moi",
    -- on renvoie nil pour éviter les attributions erronées.
    return nil
end


-- GetItemInfo peut être async => petit retry
local function _QueryItemInfo(link, cb, tries)
    tries = (tries or 0)
    local name, _, quality, itemLevel, reqLevel, class, subclass, _, equipLoc, icon = GetItemInfo(link)
    if name then
        cb({
            link = link, name = name,
            quality = tonumber(quality or 0) or 0,
            itemLevel = tonumber(itemLevel or 0) or 0,
            reqLevel  = tonumber(reqLevel  or 0) or 0,
            class = class, subclass = subclass, equipLoc = equipLoc, icon = icon,
        })
        return
    end
    if tries < 5 and C_Timer and C_Timer.After then
        C_Timer.After(0.25 * (tries + 1), function() _QueryItemInfo(link, cb, tries + 1) end)
    end
end

local function _AddIfEligible(link, looter)
    -- Anti-doublon court : si (looter|link) vient d'être vu, on ignore
    local who = tostring(looter or (UnitName and UnitName("player")) or "")
    if _IsRecentLoot and _IsRecentLoot(who, link) then
        return
    end

    if not link then return end

    -- Instance/Gouffre uniquement (paramétrable)
    local okInst, instID, diffID, mplusFromInst = _InstanceContext()
    local cfgEarly = _Config()
    if (cfgEarly.lootInstanceOnly ~= false) and (not okInst) then return end

    _QueryItemInfo(link, function(info)
        if not info or not info.link then return end

        -- === Filtres utilisateurs (GuildLogisticsDatas_Char.config) ===
        local cfg       = _Config()
        local quality   = tonumber(info.quality)  or 0
        local reqLevel  = tonumber(info.reqLevel) or 0
        local minQ      = tonumber(cfg.lootMinQuality or 0) or 0
        local minReq    = tonumber(cfg.lootMinReqLevel or 0) or 0
        local minILvl   = tonumber(cfg.lootMinItemLevel or 0) or 0
        local ilvl      = tonumber(info.itemLevel) or 0

        -- 1) Équippable ou non selon la case à cocher
        if (cfg.lootEquippableOnly ~= false) and (not _IsEquippable(info.link)) then return end
        -- 2) Rareté minimale (toujours appliquée)
        if quality < minQ then return end
        -- 3) Les filtres "Niveau requis" et "iLvl" ne s'appliquent
        --    QUE si "Équippable uniquement" est coché
        if (cfg.lootEquippableOnly ~= false) then
            if (minReq > 0) and (reqLevel < minReq) then return end
            if (minILvl > 0) and (ilvl < minILvl) then return end
        end

        -- Contexte boss/difficulté depuis ENCOUNTER_LOOT_RECEIVED (si dispo)
        local ctx = (_getCtx and _getCtx(looter or UnitName("player"), info.link)) or (_getCtxByLink and _getCtxByLink(info.link)) or nil
        local useDiffID  = tonumber((ctx and ctx.diffID)  or diffID        or 0) or 0
        local useMPlus   = tonumber((ctx and ctx.mplus)   or mplusFromInst or 0) or 0
        -- Fallback final si c'est une clé mythique sans niveau capturé
        if useMPlus == 0 and useDiffID == 8 and (_mplusLevel or 0) > 0 then
            useMPlus = _mplusLevel
        end

        -- Fallback final si c'est une clé mythique sans niveau capturé
        if useMPlus == 0 and useDiffID == 8 and GLOG and GLOG.GetActiveKeystoneLevel then
            local lv = tonumber(GLOG.GetActiveKeystoneLevel()) or 0
            if lv > 0 then useMPlus = lv end
        end

         local entry = {
            ts        = _Now(),
            link      = info.link,
            ilvl      = tonumber(info.itemLevel) or 0,
            reqLv     = reqLevel,
            looter    = looter or (ctx and ctx.player) or "",
            instID    = tonumber(instID or 0) or 0, 
            diffID    = useDiffID,
            mplus     = useMPlus,
            group     = _SnapshotGroup(),
        }

        -- Enrichissement : type & valeur du jet si connus (cache récent)
        do
            if _GetRollFor then
                local rType, rVal = _GetRollFor(looter or (ctx and ctx.player) or "", info.link)
                if rType then entry.roll = rType end
                if rVal  then entry.rollV = tonumber(rVal) end
            end
        end

        local store = _Store()
        table.insert(store, 1, entry)
        if #store > 500 then
            for i = #store, 401, -1 do table.remove(store, i) end
        end

        if UI and UI.RefreshAll then UI.RefreshAll() end

        -- Backfill asynchrone : si c'est une M+ sans niveau au moment T, on réessaye un peu plus tard
        if tonumber(entry.diffID or 0) == 8 and tonumber(entry.mplus or 0) == 0 then
            if C_Timer and C_Timer.After then
                C_Timer.After(0.20, function() _BackfillMPlus(entry.link) end)
                C_Timer.After(1.00, function() _BackfillMPlus(entry.link) end)
            else
                _BackfillMPlus(entry.link)
            end
        end

    end)

end

-- =========================
-- ===   API publique    ===
-- =========================
function GLOG.LootTracker_List() return _Store() end

function GLOG.LootTracker_Delete(index)
    local store = _Store()
    index = tonumber(index)
    if not index or index < 1 or index > #store then return end
    table.remove(store, index)
    if UI and UI.RefreshAll then UI.RefreshAll() end
end

-- Handler appelé depuis Events.lua
function GLOG.LootTracker_HandleChatMsgLoot(message)
    local msg = tostring(message or "")

    -- On ne traite que les vraies réceptions d’objets
    if not _IsLootReceiptMessage(msg) then return end

    local link = _ExtractLink(msg)
    if not link then return end

    local who = _NameInGroupFromMessage and _NameInGroupFromMessage(msg) or nil

    -- 🔒 Hors raid / butin direct : si message SELF et nom non résolu, on te met comme looteur
    if (not who or who == "") and _IsSelfLootMessage(msg) and UnitName then
        who = UnitName("player")
    end

    _AddIfEligible(link, who)
end

-- Vrai message "self" (loot direct/poussé sur le joueur)
_IsSelfLootMessage = function(msg)
    if not msg or msg == "" then return false end
    local function pat(gs)
        if not gs or gs == "" then return nil end
        return tostring(gs):gsub("%%s", ".-"):gsub("%%d", "%%d+")
    end
    local keep = {
        pat(LOOT_ITEM_SELF),
        pat(LOOT_ITEM_SELF_MULTIPLE),
        pat(LOOT_ITEM_PUSHED_SELF),
    }
    for _, p in ipairs(keep) do
        if p and msg:find(p, 1, false) then return true end
    end
    return false
end

-- === Détection des messages de roll & cache court (joueur|lien) ===
local function _Now() return (time and time()) or 0 end

local function _EscapeForLuaPattern(s)
    return (tostring(s or ""):gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"))
end
local function _GS2Pat(gs)
    if not gs or gs == "" then return nil end
    local p = _EscapeForLuaPattern(gs)
    p = p:gsub("%%s", "(.+)")  -- capture texte/lien
    p = p:gsub("%%d", "(%%d+)") -- capture entier
    return p
end
local function _NormPlayer(name)
    name = tostring(name or ""):gsub("%-.*$", ""):lower()
    return name
end

-- Cache: [link][playerLower] = { type="need|greed|disenchant|pass", val=98, ts=... }
local _rollByItem = {}

_RememberRoll = function(player, link, rollType, rollVal)
    if not player or not link or not rollType then return end
    local pn = _NormPlayer(player)
    _rollByItem[link] = _rollByItem[link] or {}
    local rec = _rollByItem[link][pn] or {}
    rec.type = rollType or rec.type
    rec.val  = tonumber(rollVal or rec.val)
    rec.ts   = _Now()
    _rollByItem[link][pn] = rec

    -- petit nettoyage des entrées > 5 min
    local now = rec.ts
    for lnk, map in pairs(_rollByItem) do
        for p, r in pairs(map) do
            if (now - (r.ts or 0)) > 300 then map[p] = nil end
        end
        if not next(map) then _rollByItem[lnk] = nil end
    end
end

_GetRollFor = function(player, link)
    if not player or not link then return nil, nil end
    local pn = _NormPlayer(player)
    local rec = _rollByItem[link] and _rollByItem[link][pn]
    if not rec then return nil, nil end
    return rec.type, rec.val
end

-- Motifs localisés des messages de roll
local _PAT_NEED        = _GS2Pat(LOOT_ROLL_NEED)
local _PAT_GREED       = _GS2Pat(LOOT_ROLL_GREED)
local _PAT_DE          = _GS2Pat(LOOT_ROLL_DISENCHANT)
local _PAT_PASS        = _GS2Pat(LOOT_ROLL_PASSED)
local _PAT_PASS_AUTO   = _GS2Pat(LOOT_ROLL_PASSED_AUTO)

-- "X won: %s with a roll of %d for %s"
local _PAT_WON         = _GS2Pat(LOOT_ROLL_WON)
-- "You rolled %d (Need) for: %s" (pas de nom → on mappe sur player)
local _PAT_ROLLED_NEED = _GS2Pat(LOOT_ROLL_ROLLED_NEED)
local _PAT_ROLLED_GREED= _GS2Pat(LOOT_ROLL_ROLLED_GREED)
local _PAT_ROLLED_DE   = _GS2Pat(LOOT_ROLL_ROLLED_DE)

local function _ParseRollMessage(msg)
    -- Sélections (contiennent toujours le joueur + lien)
    if _PAT_NEED then
        local who, link = msg:match(_PAT_NEED)
        if who and link then return who, link, "need", nil end
    end
    if _PAT_GREED then
        local who, link = msg:match(_PAT_GREED)
        if who and link then return who, link, "greed", nil end
    end
    if _PAT_DE then
        local who, link = msg:match(_PAT_DE)
        if who and link then return who, link, "disenchant", nil end
    end
    if _PAT_PASS then
        local who, link = msg:match(_PAT_PASS)
        if who and link then return who, link, "pass", nil end
    end
    if _PAT_PASS_AUTO then
        local who, link = msg:match(_PAT_PASS_AUTO)
        if who and link then return who, link, "pass", nil end
    end

    -- Gain (on récupère surtout la valeur de jet)
    if _PAT_WON then
        local who, link, val = msg:match(_PAT_WON)
        if who and link and val then return who, link, nil, tonumber(val) end
    end

    -- "You rolled %d ..." (on ne connaît pas le nom → self)
    local me = UnitName and UnitName("player")
    if me and _PAT_ROLLED_NEED then
        local val, link = msg:match(_PAT_ROLLED_NEED)
        if val and link then return me, link, "need", tonumber(val) end
    end
    if me and _PAT_ROLLED_GREED then
        local val, link = msg:match(_PAT_ROLLED_GREED)
        if val and link then return me, link, "greed", tonumber(val) end
    end
    if me and _PAT_ROLLED_DE then
        local val, link = msg:match(_PAT_ROLLED_DE)
        if val and link then return me, link, "disenchant", tonumber(val) end
    end

    return nil
end

-- Handler : messages système de jets (Need/Greed/DE/Pass/Won)
function GLOG.LootTracker_HandleChatMsgSystem(message)
    local msg = tostring(message or "")
    if msg == "" then return end

    local who, link, rType, rVal = _ParseRollMessage(msg)
    if not who or not link then return end

    -- Si on ne reçoit que la valeur (ex: "X won ... roll of %d"), on tente de
    -- récupérer le type déjà mémorisé pour (joueur, lien) et on met à jour.
    if (not rType) and rVal and _GetRollFor then
        local prevType = _GetRollFor(who, link)
        if prevType then rType = prevType end
    end

    if rType then
        _RememberRoll(who, link, rType, rVal) -- met en cache 5 min
    end
end

-- Messages de loot à conserver : uniquement les messages "X reçoit du butin"
_IsLootReceiptMessage = function(msg)
    if not msg or msg == "" then return false end
    local function pat(gs)
        if not gs or gs == "" then return nil end
        -- Convertit les GlobalStrings en motif littéral (compatible FR/EN/etc.)
        return tostring(gs):gsub("%%s", ".-"):gsub("%%d", "%%d+")
    end
    local keep = {
        pat(LOOT_ITEM_SELF),
        pat(LOOT_ITEM_SELF_MULTIPLE),
        pat(LOOT_ITEM_PUSHED_SELF),
        pat(LOOT_ITEM),
        pat(LOOT_ITEM_MULTIPLE),
        pat(LOOT_ITEM_PUSHED),
    }
    for _, p in ipairs(keep) do
        if p and msg:find(p, 1, false) then return true end
    end
    return false
end


-- Anti-doublon court : (looter|link) vu dans les 3s => on ignore
local _recentLoot = {}
local function _IsRecentLoot(looter, link)
    local k = tostring(looter or "") .. "|" .. tostring(link or "")
    local now = (_Now and _Now()) or (time and time()) or 0
    local last = _recentLoot[k]
    _recentLoot[k] = now
    return last and (now - last) <= 3
end

-- ===========
--  Cache "loot de boss" (clé: player|link) alimenté par ENCOUNTER_LOOT_RECEIVED
-- ===========
local _bossCtx = {}  -- [key] = { ts, boss, diffID, diffName, mplus, instName, player, link }
local function _now() return (time and time()) or 0 end
local function _normName(name) name = tostring(name or ""):gsub("%-.*$", ""):lower(); return name end
local function _mkKey(player, link) return _normName(player or UnitName("player") or "") .. "|" .. tostring(link or "") end

_putCtx = function(player, link, ctx)
    ctx = ctx or {}
    ctx.ts    = _now()
    ctx.player= player
    ctx.link  = link
    _bossCtx[_mkKey(player, link)] = ctx
end

_getCtx = function(player, link)
    local ctx = _bossCtx[_mkKey(player, link)]
    if not ctx then return nil end
    if (_now() - (ctx.ts or 0)) > 150 then
        _bossCtx[_mkKey(player, link)] = nil
        return nil
    end
    return ctx
end

_getCtxByLink = function(link)
    local best, bestTs = nil, -1
    for _, ctx in pairs(_bossCtx) do
        if ctx.link == link and (ctx.ts or 0) > bestTs then
            best, bestTs = ctx, (ctx.ts or 0)
        end
    end
    -- Expire si trop vieux
    if best and (_now() - (best.ts or 0)) > 150 then return nil end
    return best
end

do
    local function _onChatMsgLoot(_, _, msg)
        if msg and GLOG and GLOG.LootTracker_HandleChatMsgLoot then
            GLOG.LootTracker_HandleChatMsgLoot(msg)
        end
    end
    ns.Events.Register("CHAT_MSG_LOOT", _onChatMsgLoot)
end

-- Centralisation via Core/Events.lua
do
    local function _onEncounterLoot(_, _, ...)
        -- Filtre instance/delve paramétrable
        local cfg = _Config()
        if (cfg.lootInstanceOnly ~= false) and _InstanceContext then
            local okInst = select(1, _InstanceContext())
            if not okInst then return end
        end

        -- Args: encounterID, itemID, itemLink, quantity, player, ... , difficultyID
        local encounterID, _, itemLink, _, player, _, _, _, _, _, _, _, difficultyID = ...
        if not itemLink or not player then return end

        local boss = nil
        if EJ_GetEncounterInfo and tonumber(encounterID) then
            boss = EJ_GetEncounterInfo(encounterID)
        elseif C_EncounterJournal and C_EncounterJournal.GetEncounterInfo and tonumber(encounterID) then
            local info = C_EncounterJournal.GetEncounterInfo(encounterID)
            boss = (type(info) == "table" and info.name) or info
        end

        local diffID   = tonumber(difficultyID) or 0
        local diffName = GetDifficultyInfo and GetDifficultyInfo(diffID) or nil
        diffName = (diffName ~= "" and diffName) or nil

        local instName = (GetInstanceInfo and select(1, GetInstanceInfo())) or nil
        local keystoneLevel = tonumber(GLOG and GLOG.GetActiveKeystoneLevel and GLOG.GetActiveKeystoneLevel()) or nil

        -- Fallback M+ si la valeur live est absente
        if (not keystoneLevel or keystoneLevel == 0) and diffID == 8 and GLOG and GLOG.GetActiveKeystoneLevel then
            local lv = tonumber(GLOG.GetActiveKeystoneLevel()) or 0
            if lv > 0 then keystoneLevel = lv end
        end

        _putCtx(player, itemLink, {
            boss      = boss,
            diffID    = diffID,
            diffName  = diffName,
            mplus     = keystoneLevel,
            instName  = instName,
            player    = player,
            link      = itemLink,
        })

        if diffID == 8 then
            _BackfillMPlus(itemLink)
        end
    end
    ns.Events.Register("ENCOUNTER_LOOT_RECEIVED", _onEncounterLoot)
end
