-- Configuration de chargement des modules de communication
-- Ce fichier doit être chargé avant Comm.lua pour s'assurer que tous les modules sont disponibles

local ADDON, ns = ...

-- Liste des modules dans l'ordre de chargement requis
local COMM_MODULES = {
    "Core/Serialization",       -- Fonctions de base pour encoding/compression
    "Core/DebugLogging",        -- Système de logging avant transport
    "Core/Transport",           -- Couche transport (utilise logging)
    "Core/DataSync",            -- Synchronisation de données (utilise serialization)
    "Core/NetworkDiscovery",    -- Découverte réseau (utilise transport)
    "Core/Broadcasting",        -- Diffusion de messages (utilise transport)
    "Core/MessageHandlers",     -- Gestionnaires de messages (utilise tous les précédents)
    "Core/Comm",               -- Orchestrateur principal (utilise tous les modules)
}

-- Fonction pour vérifier si un module est chargé
local function isModuleLoaded(modulePath)
    -- Cette fonction sera implémentée selon le système de chargement de WoW
    -- Pour l'instant, on retourne true car les modules sont chargés par l'ordre des fichiers
    return true
end

-- Fonction pour charger un module
local function loadModule(modulePath)
    -- Dans WoW, les modules sont généralement chargés par l'ordre dans le .toc
    -- Cette fonction sert principalement pour le debugging
    if ns.Debug then 
        ns.Debug("ModuleLoader", "Loading " .. modulePath)
    end
end

-- Initialisation des modules
local function initModules()
    local success = true
    
    for _, module in ipairs(COMM_MODULES) do
        if not isModuleLoaded(module) then
            loadModule(module)
            if not isModuleLoaded(module) then
                local msg = "Échec du chargement du module: " .. module
                if geterrorhandler then
                    geterrorhandler()(msg)
                else
                    print(msg)
                end
                success = false
            end
        end
    end
    
    if success and ns.Debug then
        ns.Debug("ModuleLoader", "Tous les modules de communication chargés avec succès")
    end
    
    return success
end

-- Fonction publique pour diagnostiquer le chargement des modules
function GLOG_DiagnoseModules()
    print("=== Diagnostic des modules GuildLogistics ===")
    for i, module in ipairs(COMM_MODULES) do
        local status = isModuleLoaded(module) and "✅ Chargé" or "❌ Manquant"
        print(string.format("%d. %s: %s", i, module, status))
    end
    print("==============================================")
end

-- Auto-initialisation
initModules()

-- Export pour utilisation externe
ns.CommModules = COMM_MODULES
ns.InitModules = initModules
