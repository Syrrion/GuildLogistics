-- Validation de la refactorisation des modules de communication
-- Ce script peut être exécuté pour vérifier que tous les modules sont correctement chargés

local ADDON, ns = ...

-- Test de validation des modules
local function validateRefactoring()
    local report = {
        success = true,
        errors = {},
        warnings = {},
        modules = {},
    }
    
    -- Vérifier que le namespace est correctement initialisé
    if not ns or not ns.GLOG then
        table.insert(report.errors, "Namespace ns.GLOG non initialisé")
        report.success = false
        return report
    end
    
    local GLOG = ns.GLOG
    
    -- Modules et leurs fonctions critiques
    local moduleChecks = {
        {
            name = "Serialization",
            functions = {"encodeKV", "decodeKV", "PackPayloadStr"},
            description = "Fonctions de sérialisation et compression"
        },
        {
            name = "DebugLogging", 
            functions = {"pushLog", "DebugLog"},
            description = "Système de logging réseau"
        },
        {
            name = "Transport",
            functions = {"_send", "OnAddonMessage"},
            description = "Couche transport avec fragmentation"
        },
        {
            name = "DataSync",
            functions = {"SnapshotExport", "SnapshotApply"},
            description = "Synchronisation de données"
        },
        {
            name = "NetworkDiscovery",
            functions = {"HandleHello", "HandleSyncOffer", "HandleSyncGrant"},
            description = "Découverte et handshake réseau"
        },
        {
            name = "Broadcasting",
            functions = {"BroadcastRosterUpsert", "BroadcastTxApplied"},
            description = "Diffusion de messages"
        },
        {
            name = "MessageHandlers",
            functions = {"HandleMessage", "_HandleFull"},
            description = "Gestionnaires de messages"
        },
        {
            name = "Comm",
            functions = {"InitComm", "StartNetworkSync", "GetCommStatus"},
            description = "Orchestrateur principal"
        }
    }
    
    -- Vérifier chaque module
    for _, module in ipairs(moduleChecks) do
        local moduleReport = {
            name = module.name,
            loaded = true,
            missingFunctions = {},
            description = module.description
        }
        
        for _, funcName in ipairs(module.functions) do
            if not GLOG[funcName] or type(GLOG[funcName]) ~= "function" then
                table.insert(moduleReport.missingFunctions, funcName)
                moduleReport.loaded = false
                report.success = false
            end
        end
        
        table.insert(report.modules, moduleReport)
    end
    
    -- Vérifier les fonctions de compatibilité backward
    local compatibilityChecks = {
        "_HandleFull", -- Alias pour HandleMessage
        "GetFirstSyncRebroadcastDone",
        "SetFirstSyncRebroadcastDone"
    }
    
    local missingCompat = {}
    for _, funcName in ipairs(compatibilityChecks) do
        if not GLOG[funcName] or type(GLOG[funcName]) ~= "function" then
            table.insert(missingCompat, funcName)
        end
    end
    
    if #missingCompat > 0 then
        table.insert(report.warnings, "Fonctions de compatibilité manquantes: " .. table.concat(missingCompat, ", "))
    end
    
    -- Vérifier les dépendances externes
    if not LibStub or not LibStub:GetLibrary("LibDeflate", true) then
        table.insert(report.errors, "LibDeflate non disponible - requis pour la compression")
        report.success = false
    end
    
    return report
end

-- Fonction publique pour générer un rapport de validation
function GLOG_ValidateRefactoring()
    local report = validateRefactoring()
    
    -- N'affiche le rapport détaillé qu'en cas d'erreur
    if not report.success then
        print("=== Rapport de validation de la refactorisation ===")
        print("Status global: " .. (report.success and "✅ SUCCÈS" or "❌ ÉCHEC"))
        print("")
        
        -- Rapport par module
        print("📋 Modules:")
        for _, module in ipairs(report.modules) do
            local status = module.loaded and "✅" or "❌"
            print(string.format("  %s %s: %s", status, module.name, module.description))
            
            if #module.missingFunctions > 0 then
                print("    ⚠️  Fonctions manquantes: " .. table.concat(module.missingFunctions, ", "))
            end
        end
        
        -- Erreurs
        if #report.errors > 0 then
            print("")
            print("🚨 Erreurs:")
            for _, error in ipairs(report.errors) do
                print("  • " .. error)
            end
        end
        
        -- Avertissements
        if #report.warnings > 0 then
            print("")
            print("⚠️  Avertissements:")
            for _, warning in ipairs(report.warnings) do
                print("  • " .. warning)
            end
        end
        
        print("===============================================")
        print("🔧 Des corrections sont nécessaires.")
    else
        -- Message de succès silencieux (optionnel: commenter pour aucun message)
        -- print("✅ GuildLogistics: Refactorisation validée avec succès")
    end
    
    return report
end

-- Auto-validation après un délai (pour laisser le temps aux modules de se charger)
if IsLoggedIn and IsLoggedIn() then
    C_Timer.After(2, function()
        GLOG_ValidateRefactoring()
    end)
else
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("PLAYER_LOGIN")
    frame:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_LOGIN" then
            C_Timer.After(2, function()
                GLOG_ValidateRefactoring()
            end)
            self:UnregisterEvent("PLAYER_LOGIN")
        end
    end)
end
