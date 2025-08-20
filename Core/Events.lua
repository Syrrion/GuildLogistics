local ADDON, ns = ...
local GMGR = ns.GMGR

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
-- ➕ Rafraîchissements asynchrones (icônes de classe, noms d’objets)
f:RegisterEvent("GUILD_ROSTER_UPDATE")
f:RegisterEvent("GET_ITEM_INFO_RECEIVED")
-- ➕ iLvl: mise à jour auto du main
f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
f:RegisterEvent("PLAYER_AVG_ITEM_LEVEL_UPDATE")

-- ➕ Clé M+: recalcul/émission sur évènements pertinents
f:RegisterEvent("BAG_UPDATE_DELAYED")
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
        if GMGR._EnsureDB then GMGR._EnsureDB() end
        if GMGR.ClearDebugLogs then GMGR.ClearDebugLogs() end

        -- Slash /cdz
        SLASH_GMGR1 = "/cdz"
        SlashCmdList.GMGR = function()
            if ns.ToggleUI then ns.ToggleUI() end
        end

        if ns.UI and ns.UI.Finalize then ns.UI.Finalize() end
        if ns.UI and ns.UI.RefreshTitle then ns.UI.RefreshTitle() end
        if ns.UI and ns.UI.UpdateRequestsBadge then ns.UI.UpdateRequestsBadge() end
        if GMGR.Minimap_Init then GMGR.Minimap_Init() end

        if GMGR.Comm_Init then GMGR.Comm_Init() end

        -- relance automatique initiale
        if GMGR.RefreshGuildCache then
            if C_Timer and C_Timer.After then
                C_Timer.After(1.0, function() GMGR.RefreshGuildCache() end)
            else
                GMGR.RefreshGuildCache()
            end
        end

        -- si l’enregistrement dépenses était actif lors du reload, on remet les hooks
        if GMGR.IsExpensesRecording and GMGR.IsExpensesRecording() and GMGR.Expenses_InstallHooks then
            GMGR.Expenses_InstallHooks()
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        if GMGR.RefreshGuildCache then
            ns.Util.After(3.0, function() GMGR.RefreshGuildCache() end)
        end
        -- ➕ déclenche aussi l’envoi d’ilvl si on est sur le main
        if GMGR.UpdateOwnIlvlIfMain then
            ns.Util.After(5.0, function() GMGR.UpdateOwnIlvlIfMain() end)
        end
        -- ➕ déclenche la remontée de la clé (léger décalage)
        if GMGR.UpdateOwnKeystoneIfMain then
            ns.Util.After(7.0, function() GMGR.UpdateOwnKeystoneIfMain() end)
        end

    elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_AVG_ITEM_LEVEL_UPDATE" then
        if GMGR.UpdateOwnIlvlIfMain then GMGR.UpdateOwnIlvlIfMain() end

    elseif event == "BAG_UPDATE_DELAYED"
        or event == "CHALLENGE_MODE_START"
        or event == "CHALLENGE_MODE_COMPLETED"
        or event == "CHALLENGE_MODE_RESET" then
        if GMGR.UpdateOwnKeystoneIfMain then GMGR.UpdateOwnKeystoneIfMain() end

    elseif event == "GUILD_ROSTER_UPDATE" or event == "GET_ITEM_INFO_RECEIVED" then

        -- ➕ Demande une mise à jour du roster côté serveur
        if C_GuildInfo and C_GuildInfo.GuildRoster then
            C_GuildInfo.GuildRoster()
        elseif GuildRoster then
            GuildRoster()
        end

        -- ➕ Recharge notre cache local
        if GMGR.RefreshGuildCache then
            GMGR.RefreshGuildCache()
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
