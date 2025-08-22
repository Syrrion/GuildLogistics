local ADDON, ns = ...
local GLOG = ns.GLOG

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("GUILD_ROSTER_UPDATE")
f:RegisterEvent("PLAYER_GUILD_UPDATE")  -- ➕ changement appartenance guilde
f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
-- ➕ iLvl: mise à jour auto du main
f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
f:RegisterEvent("PLAYER_AVG_ITEM_LEVEL_UPDATE")

-- ➕ Clé M+: recalcul/émission sur évènements pertinents
f:RegisterEvent("BAG_UPDATE_DELAYED")
-- ➕ plus robustes quand la clé est donnée par un PNJ / lootée
f:RegisterEvent("ITEM_PUSH")
f:RegisterEvent("CHAT_MSG_LOOT")
f:RegisterEvent("GOSSIP_CLOSED")
-- ➕ utile quand on insère/enlève la clé dans le réceptacle
f:RegisterEvent("CHALLENGE_MODE_KEYSTONE_SLOTTED")

f:RegisterEvent("CHALLENGE_MODE_START")
f:RegisterEvent("CHALLENGE_MODE_COMPLETED")
f:RegisterEvent("CHALLENGE_MODE_RESET")


-- ➕ Throttle + garde-fou : on ne refresh que si l’UI est visible
local _pendingUIRefresh = false
local function _ScheduleActiveTabRefresh()
    if _pendingUIRefresh then return end
    _pendingUIRefresh = true
    local function doRefresh()
        _pendingUIRefresh = false
        if ns and ns.RefreshAll and ns.UI and ns.UI.Main and ns.UI.Main:IsShown() then
            ns.RefreshAll()
        end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.15, doRefresh) else doRefresh() end
end

f:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name ~= ADDON then return end
        if GLOG._EnsureDB then GLOG._EnsureDB() end
        if GLOG.ClearDebugLogs then GLOG.ClearDebugLogs() end

        -- STATUS_UPDATE automatique toutes les 3 minutes (rafraîchit localement iLvl/Clé/Côte via la fonction existante)
        if not GLOG._statusAutoTicker and C_Timer and C_Timer.NewTicker then
            GLOG._statusAutoTicker = C_Timer.NewTicker(180, function()
                if GLOG and GLOG.BroadcastStatusUpdate then
                    GLOG.BroadcastStatusUpdate()
                end
            end)
        end

        -- Slash /glog
        SLASH_GLOG1 = "/glog"
        SlashCmdList.GLOG = function()
            if ns.ToggleUI then ns.ToggleUI() end
        end

        if ns.UI and ns.UI.Finalize then ns.UI.Finalize() end
        if ns.UI and ns.UI.ApplyTabsForGuildMembership then
            ns.UI.ApplyTabsForGuildMembership((IsInGuild and IsInGuild()) and true or false)
        end
        if ns.UI and ns.UI.RefreshTitle then ns.UI.RefreshTitle() end

        if ns.UI and ns.UI.UpdateRequestsBadge then ns.UI.UpdateRequestsBadge() end
        if GLOG.Minimap_Init then GLOG.Minimap_Init() end

        if GLOG.Comm_Init then GLOG.Comm_Init() end

        -- relance automatique initiale
        if GLOG.RefreshGuildCache then
            if C_Timer and C_Timer.After then
                C_Timer.After(1.0, function() GLOG.RefreshGuildCache() end)
            else
                GLOG.RefreshGuildCache()
            end
        end

        -- si l’enregistrement dépenses était actif lors du reload, on remet les hooks
        if GLOG.IsExpensesRecording and GLOG.IsExpensesRecording() and GLOG.Expenses_InstallHooks then
            GLOG.Expenses_InstallHooks()
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        if GLOG.RefreshGuildCache then
            ns.Util.After(3.0, function() GLOG.RefreshGuildCache() end)
        end
        -- ✨ déclenche le statut unifié si on est sur le main
        if GLOG.UpdateOwnStatusIfMain then
            ns.Util.After(5.0, function() GLOG.UpdateOwnStatusIfMain() end)
        end

    elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_AVG_ITEM_LEVEL_UPDATE" then
        if GLOG.UpdateOwnStatusIfMain then GLOG.UpdateOwnStatusIfMain() end

    elseif event == "BAG_UPDATE_DELAYED"
        or event == "ITEM_PUSH"
        or event == "CHAT_MSG_LOOT"
        or event == "GOSSIP_CLOSED"
        or event == "CHALLENGE_MODE_KEYSTONE_SLOTTED"
        or event == "CHALLENGE_MODE_START"
        or event == "CHALLENGE_MODE_COMPLETED"
        or event == "CHALLENGE_MODE_RESET" then

        if GLOG.UpdateOwnStatusIfMain then
            if event == "GOSSIP_CLOSED" and ns and ns.Util and ns.Util.After then
                ns.Util.After(0.25, function() GLOG.UpdateOwnStatusIfMain() end)
            else
                GLOG.UpdateOwnStatusIfMain()
            end
        end

    elseif event == "GUILD_ROSTER_UPDATE" or event == "GET_ITEM_INFO_RECEIVED" then

        -- ➕ Demande une mise à jour du roster côté serveur
        if C_GuildInfo and C_GuildInfo.GuildRoster then
            C_GuildInfo.GuildRoster()
        elseif GuildRoster then
            GuildRoster()
        end

        -- ➕ Recharge notre cache local
        if GLOG.RefreshGuildCache then
            GLOG.RefreshGuildCache()
        end

        -- ➕ Met à jour le titre si la guilde a changé / est disponible
        if ns.UI and ns.UI.RefreshTitle then
            ns.UI.RefreshTitle()
        end

        _ScheduleActiveTabRefresh()
    end
end)

-- ➕ Rafraîchissement visuel quand un iLvl change (centralisé)
if ns and ns.On then
    ns.On("ilvl:changed", function() _ScheduleActiveTabRefresh() end)
    -- ➕ et aussi quand une clé change
    ns.On("mkey:changed", function() _ScheduleActiveTabRefresh() end)
end
