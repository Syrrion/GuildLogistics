local ADDON, ns = ...
local CDZ = ns.CDZ

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
        if CDZ._EnsureDB then CDZ._EnsureDB() end
        if CDZ.ClearDebugLogs then CDZ.ClearDebugLogs() end

        -- Slash /cdz
        SLASH_CDZ1 = "/cdz"
        SlashCmdList.CDZ = function()
            if ns.ToggleUI then ns.ToggleUI() end
        end

        if ns.UI and ns.UI.Finalize then ns.UI.Finalize() end
        if ns.UI and ns.UI.UpdateRequestsBadge then ns.UI.UpdateRequestsBadge() end
        if CDZ.Minimap_Init then CDZ.Minimap_Init() end

        if CDZ.Comm_Init then CDZ.Comm_Init() end

        -- relance automatique initiale
        if CDZ.RefreshGuildCache then
            if C_Timer and C_Timer.After then
                C_Timer.After(1.0, function() CDZ.RefreshGuildCache() end)
            else
                CDZ.RefreshGuildCache()
            end
        end

        -- si l’enregistrement dépenses était actif lors du reload, on remet les hooks
        if CDZ.IsExpensesRecording and CDZ.IsExpensesRecording() and CDZ.Expenses_InstallHooks then
            CDZ.Expenses_InstallHooks()
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        if CDZ.RefreshGuildCache then
            ns.Util.After(3.0, function() CDZ.RefreshGuildCache() end)
        end
        -- ➕ déclenche aussi l’envoi d’ilvl si on est sur le main
        if CDZ.UpdateOwnIlvlIfMain then
            ns.Util.After(5.0, function() CDZ.UpdateOwnIlvlIfMain() end)
        end
        -- ➕ déclenche la remontée de la clé (léger décalage)
        if CDZ.UpdateOwnKeystoneIfMain then
            ns.Util.After(7.0, function() CDZ.UpdateOwnKeystoneIfMain() end)
        end

    elseif event == "PLAYER_EQUIPMENT_CHANGED" or event == "PLAYER_AVG_ITEM_LEVEL_UPDATE" then
        if CDZ.UpdateOwnIlvlIfMain then CDZ.UpdateOwnIlvlIfMain() end

    elseif event == "BAG_UPDATE_DELAYED"
        or event == "CHALLENGE_MODE_START"
        or event == "CHALLENGE_MODE_COMPLETED"
        or event == "CHALLENGE_MODE_RESET" then
        if CDZ.UpdateOwnKeystoneIfMain then CDZ.UpdateOwnKeystoneIfMain() end

    elseif event == "GUILD_ROSTER_UPDATE" or event == "GET_ITEM_INFO_RECEIVED" then

        -- ➕ Demande une mise à jour du roster côté serveur
        if C_GuildInfo and C_GuildInfo.GuildRoster then
            C_GuildInfo.GuildRoster()
        elseif GuildRoster then
            GuildRoster()
        end

        -- ➕ Recharge notre cache local
        if CDZ.RefreshGuildCache then
            CDZ.RefreshGuildCache()
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
