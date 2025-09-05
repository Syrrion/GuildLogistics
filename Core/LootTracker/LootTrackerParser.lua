local ADDON, ns = ...

-- Module: LootTrackerParser
-- Responsabilités: Parsing des messages de loot, extraction des liens, détection des looters, anti-doublon
ns.LootTrackerParser = ns.LootTrackerParser or {}

-- Fonctions utilitaires
local function _Now() return (time and time()) or 0 end

local function _ExtractLink(msg)
    if not msg then return nil end
    -- capture le 1er lien objet
    return msg:match("(|Hitem:%d+:[^|]+|h%[[^%]]+%]|h)") or msg:match("(|Hitem:[^|]+|h[^|]+|h)")
end

local function _IsEquippable(link)
    return (link and IsEquippableItem and IsEquippableItem(link)) and true or false
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

-- Vrai message "self" (loot direct/poussé sur le joueur)
local function _IsSelfLootMessage(msg)
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

-- Messages de loot à conserver : uniquement les messages "X reçoit du butin"
local function _IsLootReceiptMessage(msg)
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
    local now = _Now()
    local last = _recentLoot[k]
    _recentLoot[k] = now
    return last and (now - last) <= 3
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
    if _IsRecentLoot(who, link) then
        return
    end

    if not link then return end

    -- Instance/Gouffre uniquement (paramétrable)
    local okInst, instID, diffID, mplusFromInst = false, 0, 0, 0
    if ns.LootTrackerInstance and ns.LootTrackerInstance.GetInstanceContext then
        okInst, instID, diffID, mplusFromInst = ns.LootTrackerInstance.GetInstanceContext()
    end
    
    local cfgEarly = nil
    if ns.LootTrackerState and ns.LootTrackerState.GetConfig then
        cfgEarly = ns.LootTrackerState.GetConfig()
        if (cfgEarly.lootInstanceOnly ~= false) and (not okInst) then return end
    end

    _QueryItemInfo(link, function(info)
        if not info or not info.link then return end

        -- === Filtres utilisateurs (GuildLogisticsDatas_Char.config) ===
        local cfg = cfgEarly
        if not cfg and ns.LootTrackerState and ns.LootTrackerState.GetConfig then
            cfg = ns.LootTrackerState.GetConfig()
        end
        if not cfg then return end
        
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
        local ctx = nil
        if ns.LootTrackerInstance then
            ctx = ns.LootTrackerInstance.GetBossContext(looter or UnitName("player"), info.link)
            if not ctx then
                ctx = ns.LootTrackerInstance.GetBossContextByLink(info.link)
            end
        end
        
        local useDiffID  = tonumber((ctx and ctx.diffID)  or diffID        or 0) or 0
        local useMPlus   = tonumber((ctx and ctx.mplus)   or mplusFromInst or 0) or 0
        
        -- Fallback final si c'est une clé mythique sans niveau capturé
        if useMPlus == 0 and useDiffID == 8 and ns.LootTrackerState then
            local mplusLevel = ns.LootTrackerState.GetCurrentMPlusLevel()
            if (mplusLevel or 0) > 0 then
                useMPlus = mplusLevel
            end
        end

        -- Fallback final si c'est une clé mythique sans niveau capturé
        if useMPlus == 0 and useDiffID == 8 and ns.LootTrackerState then
            local lv = tonumber(ns.LootTrackerState.GetActiveKeystoneLevel()) or 0
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
            group     = ns.LootTrackerInstance and ns.LootTrackerInstance.SnapshotGroup() or {},
        }

        -- Enrichissement : type & valeur du jet si connus (cache récent)
        if ns.LootTrackerRolls and ns.LootTrackerRolls.GetRollFor then
            local rType, rVal = ns.LootTrackerRolls.GetRollFor(looter or (ctx and ctx.player) or "", info.link)
            if rType then entry.roll = rType end
            if rVal  then entry.rollV = tonumber(rVal) end
        end

        -- Sauvegarde
        if ns.LootTrackerState and ns.LootTrackerState.GetStore then
            local store = ns.LootTrackerState.GetStore()
            table.insert(store, 1, entry)
            if #store > 500 then
                for i = #store, 401, -1 do table.remove(store, i) end
            end
        end

        if ns.UI and ns.UI.RefreshAll then ns.UI.RefreshAll() end

        -- Backfill asynchrone : si c'est une M+ sans niveau au moment T, on réessaye un peu plus tard
        if tonumber(entry.diffID or 0) == 8 and tonumber(entry.mplus or 0) == 0 and ns.LootTrackerState then
            if C_Timer and C_Timer.After then
                C_Timer.After(0.20, function() ns.LootTrackerState.BackfillMPlus(entry.link) end)
                C_Timer.After(1.00, function() ns.LootTrackerState.BackfillMPlus(entry.link) end)
            else
                ns.LootTrackerState.BackfillMPlus(entry.link)
            end
        end

    end)
end

-- =========================
-- ===   API du module   ===
-- =========================
ns.LootTrackerParser = {
    -- Extraction et validation
    ExtractLink = _ExtractLink,
    IsEquippable = _IsEquippable,
    
    -- Détection des messages
    IsLootReceiptMessage = _IsLootReceiptMessage,
    IsSelfLootMessage = _IsSelfLootMessage,
    
    -- Détection des looters
    NameInGroupFromMessage = _NameInGroupFromMessage,
    
    -- Anti-doublon
    IsRecentLoot = _IsRecentLoot,
    
    -- Traitement principal
    AddIfEligible = _AddIfEligible,
    
    -- Handler appelé depuis Events.lua
    HandleChatMsgLoot = function(message)
        local msg = tostring(message or "")

        -- On ne traite que les vraies réceptions d'objets
        if not _IsLootReceiptMessage(msg) then return end

        local link = _ExtractLink(msg)
        if not link then return end

        local who = _NameInGroupFromMessage(msg)

        -- 🔒 Hors raid / butin direct : si message SELF et nom non résolu, on te met comme looteur
        if (not who or who == "") and _IsSelfLootMessage(msg) and UnitName then
            who = UnitName("player")
        end

        _AddIfEligible(link, who)
    end,
}
