-- Script de test pour vérifier le bon fonctionnement de la communication
-- Peut être exécuté en jeu avec /script pour diagnostiquer les problèmes

local ADDON, ns = ...
local function getGLOG() return (ns and ns.GLOG) or _G.GLOG end

local function testCommunication()
    local GLOG = getGLOG()
    print("=== Test de communication GuildLogistics ===")
    
    -- Vérifier que GLOG existe
    if not GLOG then
        print("❌ GLOG namespace non trouvé")
        return false
    end
    
    -- Vérifier les fonctions critiques
    local criticalFunctions = {
        "_send", "OnAddonMessage", "InitTransport", "StopTransport",
        "HandleHello", "StartDiscovery", "HandleMessage",
        "encodeKV", "pushLog"
    }
    
    local missing = {}
    for _, func in ipairs(criticalFunctions) do
        if not GLOG[func] or type(GLOG[func]) ~= "function" then
            missing[#missing + 1] = func
        end
    end
    
    if #missing > 0 then
        print("❌ Fonctions manquantes: " .. table.concat(missing, ", "))
        return false
    end
    
    print("✅ Toutes les fonctions critiques sont présentes")
    
    -- Vérifier l'état du transport
    if GLOG._transportReady then
        print("✅ Transport initialisé")
    else
        print("⚠️  Transport non initialisé - essai d'initialisation")
        GLOG.InitTransport()
        if GLOG._transportReady then
            print("✅ Transport initialisé avec succès")
        else
            print("❌ Échec d'initialisation du transport")
            return false
        end
    end
    
    -- Vérifier que le prefix est enregistré
    local prefixes = C_ChatInfo.GetRegisteredAddonMessagePrefixes()
    local glog2Found = false
    for _, prefix in ipairs(prefixes) do
        if prefix == "GLOG2" then
            glog2Found = true
            break
        end
    end

    if glog2Found then
        print("✅ Prefix GLOG2 enregistré")
    else
        print("❌ Prefix GLOG2 non enregistré")
        return false
    end
    
    -- Test d'envoi d'un message HELLO
    print("📤 Test d'envoi HELLO...")
    if GLOG.Sync_RequestHello then
        GLOG.Sync_RequestHello()
        print("✅ HELLO envoyé")
    else
        print("❌ Fonction Sync_RequestHello non trouvée")
        return false
    end
    
    -- Afficher les statistiques
    if GLOG.GetTransportStats then
        local stats = GLOG.GetTransportStats()
        print("📊 Statistiques transport:")
        print("  - Queue sortante: " .. (stats.outq or 0))
        print("  - Boîte de réception: " .. (stats.inbox or 0))
    end
    
    if GLOG.GetDiscoveryStats then
        local stats = GLOG.GetDiscoveryStats()
        print("📊 Statistiques découverte:")
        print("  - Elections HELLO: " .. (stats.helloElect or 0))
        print("  - Découvertes actives: " .. (stats.discovery or 0))
    end
    
    print("🎉 Test de communication terminé avec succès!")
    return true
end

-- Fonction accessible globalement
GLOG_TestCommunication = testCommunication

-- Auto-test après un délai si connecté
if IsLoggedIn and IsLoggedIn() then
    C_Timer.After(3, function()
        print("🔍 Auto-test de communication...")
        testCommunication()
    end)
end
