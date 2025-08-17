local ADDON, ns = ...
local CDZ = ns.CDZ

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("GUILD_ROSTER_UPDATE")       -- pour les icônes de classe
f:RegisterEvent("GET_ITEM_INFO_RECEIVED")    -- pour les noms d’objets

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

    -- ➕ Dès que la guilde ou les items sont prêts, on rafraîchit le panneau affiché
    elseif event == "GUILD_ROSTER_UPDATE" or event == "GET_ITEM_INFO_RECEIVED" then
        if ns and ns.RefreshAll then ns.RefreshAll() end
    end
end)




