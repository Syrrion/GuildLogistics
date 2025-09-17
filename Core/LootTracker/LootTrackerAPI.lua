local ADDON, ns = ...

-- Module: LootTrackerAPI
-- Responsabilités: API publique GLOG.LootTracker_*, handlers d'événements, fonctions exposées
ns.LootTrackerAPI = ns.LootTrackerAPI or {}

-- Référence vers les modules de l'addon principal
local GLOG = ns.GLOG or {}

-- =========================
-- ===   API publique    ===
-- =========================
function GLOG.LootTracker_List()
    if ns.LootTrackerState and ns.LootTrackerState.GetStore then
        return ns.LootTrackerState.GetStore()
    end
    return {}
end

function GLOG.LootTracker_Delete(index)
    if not ns.LootTrackerState or not ns.LootTrackerState.GetStore then return end
    
    local store = ns.LootTrackerState.GetStore()
    index = tonumber(index)
    if not index or index < 1 or index > #store then return end
    table.remove(store, index)
    if ns.UI and ns.UI.RefreshAll then ns.UI.RefreshAll() end
end

-- Getter public pour l'UI et les fallbacks Core
function GLOG.GetActiveKeystoneLevel()
    if ns.LootTrackerState and ns.LootTrackerState.GetActiveKeystoneLevel then
        return ns.LootTrackerState.GetActiveKeystoneLevel()
    end
    return 0
end

-- Résolution nom d'instance depuis instID (UIMapID / instanceMapID)
function GLOG.ResolveInstanceName(instID)
    if ns.LootTrackerInstance and ns.LootTrackerInstance.ResolveInstanceName then
        return ns.LootTrackerInstance.ResolveInstanceName(instID)
    end
    return ""
end

-- =========================
-- ===   Event Handlers  ===
-- =========================

-- Handler appelé depuis Events.lua pour CHAT_MSG_LOOT
function GLOG.LootTracker_HandleChatMsgLoot(message)
    if ns.LootTrackerParser and ns.LootTrackerParser.HandleChatMsgLoot then
        ns.LootTrackerParser.HandleChatMsgLoot(message)
    end
end

-- Handler : messages système de jets (Need/Greed/DE/Pass/Won)
function GLOG.LootTracker_HandleChatMsgSystem(message)
    if ns.LootTrackerRolls and ns.LootTrackerRolls.HandleChatMsgSystem then
        ns.LootTrackerRolls.HandleChatMsgSystem(message)
    end
end

-- Handler pour ENCOUNTER_LOOT_RECEIVED
function GLOG.LootTracker_HandleEncounterLoot(encounterID, itemID, itemLink, quantity, player, difficultyID)
    if ns.LootTrackerInstance and ns.LootTrackerInstance.HandleEncounterLoot then
        -- Utilise seulement les paramètres nécessaires
        ns.LootTrackerInstance.HandleEncounterLoot(encounterID, itemID, itemLink, quantity, player, difficultyID)
    end
end

-- Handler pour les événements M+
function GLOG.LootTracker_HandleMPlusEvent()
    if ns.LootTrackerState and ns.LootTrackerState.UpdateActiveKeystoneLevel then
        ns.LootTrackerState.UpdateActiveKeystoneLevel()
    end
end

-- Fonction de test pour simuler des rolls (accessible via GLOG.TestLootRolls())
function GLOG.TestLootRolls()
    if ns.LootTrackerRolls and ns.LootTrackerRolls.TestRolls then
        ns.LootTrackerRolls.TestRolls()
    else
        print("GLOG: Module LootTrackerRolls non disponible")
    end
end

-- Test direct en ajoutant dans le cache
function GLOG.TestDirectRolls()
    if ns.LootTrackerRolls and ns.LootTrackerRolls.TestDirectRolls then
        ns.LootTrackerRolls.TestDirectRolls()
    else
        print("GLOG: Module LootTrackerRolls non disponible")
    end
end

-- Test avec vrais messages WoW
function GLOG.TestRealMessages()
    if ns.LootTrackerRolls and ns.LootTrackerRolls.TestRealMessages then
        ns.LootTrackerRolls.TestRealMessages()
    else
        print("GLOG: Module LootTrackerRolls non disponible")
    end
end

-- Debug: show a sample trinket ranking popup (10 random players)
function GLOG.TestTrinketRanks()
    if ns.UI and ns.UI.Debug_ShowRandomTrinketRankPopup then
        ns.UI.Debug_ShowRandomTrinketRankPopup()
    else
        print("GLOG: UI.Debug_ShowRandomTrinketRankPopup indisponible")
    end
end

-- =========================
-- ===   Initialisation  ===
-- =========================
ns.LootTrackerAPI = {
    -- Enregistrement des événements via Core/Events.lua
    RegisterEvents = function()
        if not ns.Events or not ns.Events.Register then return end
        
        -- Messages de loot
        ns.Events.Register("CHAT_MSG_LOOT", function(_, _, msg)
            if msg and GLOG and GLOG.LootTracker_HandleChatMsgLoot then
                GLOG.LootTracker_HandleChatMsgLoot(msg)
            end
        end)
        
        -- Messages système de rolls
        ns.Events.Register("CHAT_MSG_SYSTEM", function(_, _, msg)
            if msg and GLOG and GLOG.LootTracker_HandleChatMsgSystem then
                GLOG.LootTracker_HandleChatMsgSystem(msg)
            end
        end)
        
        -- Loot de boss
        ns.Events.Register("ENCOUNTER_LOOT_RECEIVED", function(_, _, ...)
            if GLOG and GLOG.LootTracker_HandleEncounterLoot then
                GLOG.LootTracker_HandleEncounterLoot(...)
            end
            -- Opportunistic: show per-player rank popup when an equippable trinket drops
            local encounterID, itemID, itemLink, quantity, player, difficultyID = ...
            if ns and ns.LootTrackerParser and ns.LootTrackerParser.IsEquippable then
                -- Fast type check via inventory type or link parse
                local isEquip = ns.LootTrackerParser.IsEquippable(itemLink)
                -- Respect Settings toggle (default ON when nil)
                local showPopup = true
                if GLOG and GLOG.GetSavedWindow then
                    local saved = GLOG.GetSavedWindow() or {}
                    local pop = saved.popups or {}
                    if pop.trinketRankPopup == false then showPopup = false end
                end
                if isEquip and showPopup and ns.UI and ns.UI.ShowTrinketRankPopupForGroup then
                    -- Determine if trinket (INVTYPE_TRINKET = 12); prefer C_Item API if available
                    local invType
                    if C_Item and C_Item.GetItemInventoryTypeByID and itemID then
                        invType = C_Item.GetItemInventoryTypeByID(itemID)
                    end
                    -- No deprecated API fallback; if inventory type is unknown, skip popup
                    if invType == 12 then
                        -- Extract actual ilvl for the dropped item
                        local ilvl = 0
                        if C_Item and C_Item.GetDetailedItemLevelInfo then
                            local ok, lvl = pcall(C_Item.GetDetailedItemLevelInfo, itemLink)
                            if ok and tonumber(lvl) then ilvl = tonumber(lvl) or 0 end
                        end
                        if ilvl <= 0 then ilvl = ns.LootTrackerInstance and ns.LootTrackerInstance.GetEquippedIlvl and ns.LootTrackerInstance.GetEquippedIlvl() or 0 end
                        local group = ns.LootTrackerInstance and ns.LootTrackerInstance.SnapshotGroup and ns.LootTrackerInstance.SnapshotGroup() or nil
                        ns.UI.ShowTrinketRankPopupForGroup(tonumber(itemID), ilvl, { group = group, targets = 1 })
                    end
                end
            end
        end)
        
        -- Événements M+
        local function onMPlusEvent() 
            if GLOG and GLOG.LootTracker_HandleMPlusEvent then
                GLOG.LootTracker_HandleMPlusEvent()
            end
        end
        
        ns.Events.Register("CHALLENGE_MODE_KEYSTONE_SLOTTED", onMPlusEvent)
        ns.Events.Register("CHALLENGE_MODE_START", onMPlusEvent)
        ns.Events.Register("CHALLENGE_MODE_COMPLETED", onMPlusEvent)
        ns.Events.Register("CHALLENGE_MODE_RESET", onMPlusEvent)
        ns.Events.Register("PLAYER_ENTERING_WORLD", onMPlusEvent)
    end,
}
