local ADDON, ns = ...

-- Module: LootTrackerParser
-- Responsabilités: Parsing des messages de loot, extraction des liens, détection des looters, anti-doublon
ns.LootTrackerParser = ns.LootTrackerParser or {}

-- Fonctions utilitaires
local function _Now() return (time and time()) or 0 end

local function _NormName(name)
    return tostring(name or ""):gsub("%-.*$", ""):lower()
end

local function _ExtractLink(msg)
    if not msg then return nil end
    -- Capture le 1er lien objet en conservant la couleur si présente
    -- Forme colorée typique: |cffa335ee|Hitem:...|h[Nom]|h|r
    local colored = msg:match("(|c%x%x%x%x%x%x%x%x|Hitem:%d+:[^|]+|h%[[^%]]+%]|h|r)")
    if colored then return colored end
    -- Fallback sans section [name] stricte
    colored = msg:match("(|c%x%x%x%x%x%x%x%x|Hitem:[^|]+|h[^|]+|h|r)")
    if colored then return colored end
    -- Liens sans couleur
    return msg:match("(|Hitem:%d+:[^|]+|h%[[^%]]+%]|h)") or msg:match("(|Hitem:[^|]+|h[^|]+|h)")
end

local function _IsEquippable(link)
    if not link or link == "" then return false end
    local itemID = tonumber(link:match("|Hitem:(%d+):"))
    -- Heuristique rapide via emplacement d'équipement
    if C_Item and C_Item.GetItemInventoryTypeByID and itemID then
        local invType = C_Item.GetItemInventoryTypeByID(itemID)
        -- 0 = non-équipable; >0 = un emplacement d'équipement
        if tonumber(invType or 0) and tonumber(invType or 0) > 0 then
            return true
        end
    end
    -- Fallback conservateur: inconnu → non équipable
    return false
end

-- Normalized link key compatible with LootTrackerRolls (itemID + lowercased name)
local function _NormLinkKey(link)
    if ns.LootTrackerRolls and ns.LootTrackerRolls.NormalizeLink then
        local ok, key = pcall(ns.LootTrackerRolls.NormalizeLink, link)
        if ok and key then return key end
    end
    if not link or link == "" then return nil end
    local itemID = link:match("|Hitem:(%d+):") or "?"
    local name = link:match("%[(.-)%]") or "?"
    return itemID .. "::" .. tostring(name):lower()
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
        -- Essayer différents patterns pour extraire le nom
        local cand = head:match("%[([%w\128-\255'%-]+%-%w+)%]") or       -- [Nom-Serveur]
                     head:match("%[([%w\128-\255'%-]+)%]") or             -- [Nom simple]
                     head:match("([%w\128-\255'%-]+%-%w+)$") or           -- Nom-Serveur à la fin
                     head:match("([%w\128-\255'%-]+)$") or                -- Nom simple à la fin
                     head:match("^([%w\128-\255'%-]+)")                   -- Nom au début du message
        if cand and cand ~= "" and not cand:find("|") and not cand:match("^c?f?f?%x%x%x%x%x%x$") then 
            return cand 
        end
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

-- Vérifie si une entrée (looter, link) existe déjà récemment dans le store
local function _HasStoreEntry(link, looter, cutoffSec)
    if not ns.LootTrackerState or not ns.LootTrackerState.GetStore then return false end
    local store = ns.LootTrackerState.GetStore()
    if type(store) ~= "table" then return false end
    local who = tostring(looter or "")
    local cutoff = (cutoffSec and tonumber(cutoffSec)) or 600 -- 10 minutes par défaut
    local now = (GetServerTime and GetServerTime()) or _Now()
    local targetKey = _NormLinkKey(link)
    for i = 1, #store do
        local e = store[i]
        if e and tostring(e.looter or "") == who then
            if targetKey and _NormLinkKey(e.link) == targetKey then
            local ts = tonumber(e.ts or 0) or 0
            if (now - ts) <= cutoff then
                return true
            end
            end
        end
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
    local lk = _NormLinkKey(link) or tostring(link or "")
    local k = tostring(looter or "") .. "|" .. lk
    local now = _Now()
    local last = _recentLoot[k]
    _recentLoot[k] = now
    return last and (now - last) <= 3
end

-- GetItemInfo peut être async => petit retry
local function _QueryItemInfo(link, cb, tries)
    tries = (tries or 0)
    if not link or link == "" then return end
    local itemID = tonumber(link:match("|Hitem:(%d+):"))
    local function done()
        local quality, icon
        if itemID and C_Item then
            if C_Item.GetItemQualityByID then
                quality = tonumber(C_Item.GetItemQualityByID(itemID)) or nil
            end
            if C_Item.GetItemIconByID then
                icon = C_Item.GetItemIconByID(itemID)
            end
        end
        local ilvl = 0
        if C_Item and C_Item.GetDetailedItemLevelInfo then
            local ok, lvl = pcall(C_Item.GetDetailedItemLevelInfo, link)
            if ok and tonumber(lvl) then ilvl = tonumber(lvl) or 0 end
        end
        local nameFromLink = link:match("%[(.-)%]")
        cb({
            link = link,
            name = nameFromLink or "",
            quality = quality or 0,
            itemLevel = ilvl or 0,
            reqLevel  = nil, -- inconnu sans GetItemInfo; le filtre le traitera prudemment
            class = nil, subclass = nil, equipLoc = nil, icon = icon,
        })
    end
    if Item and Item.CreateFromItemLink then
        local it = Item:CreateFromItemLink(link)
        it:ContinueOnItemLoad(function()
            done()
        end)
        return
    end
    -- Fallback sans API Item: essaye plus tard quelques fois (cache live)
    if tries < 5 and C_Timer and C_Timer.After then
        C_Timer.After(0.25 * (tries + 1), function() _QueryItemInfo(link, cb, tries + 1) end)
    else
        -- Dernier recours: renvoie un minimum
        done()
    end
end

local function _AddIfEligible(link, looter)
    if not link then return end
    local who = tostring(looter or (UnitName and UnitName("player")) or "")

    -- Pending guard (race condition prevention): if an async insertion for (who,link) is already scheduled, skip.
    -- Without this, two near-simultaneous _AddIfEligible calls (e.g. MarkAsWon then chat loot message)
    -- can both schedule _QueryItemInfo before the store contains the entry, producing duplicates.
    ns.__lootPendingAdds = ns.__lootPendingAdds or {}
    local _pendingKey = _NormName(who) .. "|" .. (_NormLinkKey(link) or link)
    local nowPending = _Now()
    local pend = ns.__lootPendingAdds[_pendingKey]
    if pend and (nowPending - pend) < 10 then
        -- Another insertion still pending (<=10s window); let the first complete.
        return
    end
    -- Mark as pending immediately (cleared / updated after async completion)
    ns.__lootPendingAdds[_pendingKey] = nowPending

    -- Déduplication forte: si une entrée existe déjà récemment pour (looter, link), on ignore
    if _HasStoreEntry(link, who, 600) then
        return
    end

    -- If a roll session is active for this link, only accept the final winner; otherwise skip for now
    if ns.LootTrackerRolls and ns.LootTrackerRolls.HasActiveRollSession and ns.LootTrackerRolls.HasActiveRollSession(link) then
        local winName = nil
        if ns.LootTrackerRolls.GetWinner then
            winName = select(1, ns.LootTrackerRolls.GetWinner(link))
        end
        if not winName then
            -- winner not known yet; wait for MarkAsWon() to create the entry
            return
        end
        if _NormName(winName) ~= _NormName(who) then
            -- not the winner; ignore
            return
        end
    end
    -- Anti-doublon court : si (looter|link) vient d'être vu, on ignore
    if _IsRecentLoot(who, link) then
        return
    end

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

        -- If a previous async already inserted (store check), abort and keep pending time (avoid rapid re-add)
        if _HasStoreEntry(info.link, who, 600) then return end

        -- === Filtres utilisateurs (GuildLogisticsDatas_Char.config) ===
        local cfg = cfgEarly
        if not cfg and ns.LootTrackerState and ns.LootTrackerState.GetConfig then
            cfg = ns.LootTrackerState.GetConfig()
        end
        if not cfg then return end
        
    local quality   = tonumber(info.quality)  or 0
    local reqLevel  = (info.reqLevel ~= nil) and tonumber(info.reqLevel) or nil
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
            if (minReq > 0) and (reqLevel ~= nil) and (reqLevel < minReq) then return end
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
            won       = false,  -- Par défaut, on ne sait pas si l'objet a été réellement gagné
        }

        -- Enrichissement : type & valeur du jet si connus (cache récent)
        if ns.LootTrackerRolls and ns.LootTrackerRolls.GetRollFor then
            local rType, rVal = ns.LootTrackerRolls.GetRollFor(looter, info.link)
            if rType then entry.roll = rType end
            if rVal  then entry.rollV = tonumber(rVal) end
        end

        -- If not found in the per-player roll cache, try the winner cache
        if (not entry.roll) and ns.LootTrackerRolls and ns.LootTrackerRolls.GetWinner then
            local winName, wType, wVal = ns.LootTrackerRolls.GetWinner(info.link)
            if winName and _NormName(winName) == _NormName(entry.looter) then
                if wType then entry.roll = wType end
                if wVal  then entry.rollV = tonumber(wVal) end
            end
        end

        -- Sauvegarde
        if ns.LootTrackerState and ns.LootTrackerState.GetStore then
            local store = ns.LootTrackerState.GetStore()
            -- Final safety: scan a few recent entries to ensure no duplicate (who, normalized link)
            local dup = false
            local targetKey = _NormLinkKey(entry.link)
            for i = 1, math.min(25, #store) do
                local e = store[i]
                if e and _NormName(e.looter) == _NormName(entry.looter) then
                    if targetKey and _NormLinkKey(e.link) == targetKey then
                        dup = true; break
                    end
                end
            end
            if not dup then
                table.insert(store, 1, entry)
                if #store > 500 then
                    for i = #store, 401, -1 do table.remove(store, i) end
                end
            end
        end

        if ns and ns.RefreshAll then
            ns.RefreshAll()
        elseif ns.UI and ns.UI.RefreshAll then
            ns.UI.RefreshAll()
        end

        -- Backfill asynchrone : si c'est une M+ sans niveau au moment T, on réessaye un peu plus tard
        if tonumber(entry.diffID or 0) == 8 and tonumber(entry.mplus or 0) == 0 and ns.LootTrackerState then
            if C_Timer and C_Timer.After then
                C_Timer.After(0.20, function() ns.LootTrackerState.BackfillMPlus(entry.link) end)
                C_Timer.After(1.00, function() ns.LootTrackerState.BackfillMPlus(entry.link) end)
            else
                ns.LootTrackerState.BackfillMPlus(entry.link)
            end
        end

        -- Update pending marker timestamp to extend protection for a short while
        if ns.__lootPendingAdds then
            ns.__lootPendingAdds[_pendingKey] = _Now()
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
    
    -- Marquer un objet comme gagné (appelé depuis LootTrackerRolls)
    MarkAsWon = function(itemLink, playerName)
        if not itemLink or not playerName then return end
        local store = ns.LootTrackerState and ns.LootTrackerState.GetStore and ns.LootTrackerState.GetStore() or {}

        local cutoffTime = (GetServerTime and GetServerTime() or _Now()) - 600
        local idxFound = nil
        for i, entry in ipairs(store) do
            if entry.link == itemLink and _NormName(entry.looter) == _NormName(playerName) and entry.ts >= cutoffTime then
                idxFound = i
                break
            end
        end

        -- If no entry yet (likely skipped due to gating), add it now
        if not idxFound then
            -- Avoid racing with a pending async insert already scheduled
            local _pendKey = _NormName(playerName) .. "|" .. (_NormLinkKey(itemLink) or itemLink)
            local pend = ns.__lootPendingAdds and ns.__lootPendingAdds[_pendKey]
            if not pend or ((_Now() - pend) > 10) then
                _AddIfEligible(itemLink, playerName)
            end
            for i, entry in ipairs(store) do
                local same = (_NormName(entry.looter) == _NormName(playerName))
                if same then
                    local k1 = _NormLinkKey(entry.link)
                    local k2 = _NormLinkKey(itemLink)
                    if k1 and k2 and k1 == k2 and entry.ts >= cutoffTime then
                    idxFound = i; break
                    end
                end
            end
        end

        if idxFound then
            local entry = store[idxFound]
            entry.won = true
            -- backfill roll info from winner cache when possible
            if ns.LootTrackerRolls and ns.LootTrackerRolls.GetWinner then
                local winName, wType, wVal = ns.LootTrackerRolls.GetWinner(itemLink)
                if winName and _NormName(winName) == _NormName(playerName) then
                    if wType then entry.roll = wType end
                    if wVal then entry.rollV = tonumber(wVal) end
                end
            end
            if ns and ns.RefreshAll then
                ns.RefreshAll()
            elseif ns.UI and ns.UI.RefreshAll then
                ns.UI.RefreshAll()
            end
        end
    end,
}
