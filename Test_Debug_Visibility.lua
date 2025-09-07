-- Test script pour vérifier la visibilité des onglets Debug
-- Ce fichier peut être supprimé après les tests

local function TestDebugVisibility()
    -- Accéder aux namespaces globaux de l'addon
    local ns = _G.GuildLogistics_NS or _G.GLOG_NS
    if not ns then
        -- Essayer d'accéder via les frames existantes
        local mainFrame = _G.GLOG_Main
        if mainFrame and mainFrame.GetParent then
            local parent = mainFrame:GetParent()
            if parent and parent.namespace then
                ns = parent.namespace
            end
        end
    end
    
    if not ns or not ns.UI then 
        print("GLOG Test: UI non disponible, essai alternatif...")
        
        -- Test basique sans namespace
        local debugEnabled = (GuildLogisticsUI and GuildLogisticsUI.debugEnabled) == true
        print("Debug actuellement activé:", debugEnabled and "OUI" or "NON")
        
        -- Test simple de basculement
        print("Test de basculement...")
        GuildLogisticsUI = GuildLogisticsUI or {}
        GuildLogisticsUI.debugEnabled = not debugEnabled
        print("Debug maintenant:", GuildLogisticsUI.debugEnabled and "OUI" or "NON")
        
        return 
    end
    
    local UI = ns.UI
    local Tr = ns.Tr or function(s) return s end
    
    print("=== TEST VISIBILITÉ DEBUG ===")
    
    -- État actuel
    local debugEnabled = (GuildLogisticsUI and GuildLogisticsUI.debugEnabled) == true
    print("Debug actuellement activé:", debugEnabled and "OUI" or "NON")
    
    -- Vérification des onglets debug
    local debugTabs = {
        Tr("tab_debug"),
        Tr("tab_debug_db"), 
        Tr("tab_debug_events"),
        Tr("tab_debug_errors")
    }
    
    print("Visibilité des onglets debug:")
    for _, tabLabel in ipairs(debugTabs) do
        local btn = UI.GetTabButton and UI.GetTabButton(tabLabel)
        local visible = btn and btn.IsShown and btn:IsShown()
        print("  " .. tabLabel .. ":", visible and "VISIBLE" or "MASQUÉ")
    end
    
    -- Test basculement
    print("\n--- Test de basculement ---")
    print("Désactivation du debug...")
    if UI.SetDebugEnabled then
        UI.SetDebugEnabled(false)
    end
    
    -- Vérification après désactivation
    print("Après désactivation:")
    for _, tabLabel in ipairs(debugTabs) do
        local btn = UI.GetTabButton and UI.GetTabButton(tabLabel)
        local visible = btn and btn.IsShown and btn:IsShown()
        print("  " .. tabLabel .. ":", visible and "VISIBLE" or "MASQUÉ")
    end
    
    -- Réactivation
    print("\nRéactivation du debug...")
    if UI.SetDebugEnabled then
        UI.SetDebugEnabled(true)
    end
    
    print("Test terminé.")
end

-- Commande slash pour lancer le test
SLASH_GLOGTEST1 = "/glogtest"
SlashCmdList.GLOGTEST = function()
    TestDebugVisibility()
end

print("GLOG: Test de visibilité disponible avec /glogtest")
