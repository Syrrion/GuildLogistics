local ADDON, ns = ...

-- Point d'entrée principal du LootTracker modulaire
-- Ce fichier orchestre tous les modules et assure la compatibilité avec l'API existante

-- Initialisation des références principales
ns.GLOG = ns.GLOG or {}
ns.UI   = ns.UI   or {}
ns.Util = ns.Util or {}

-- Point d'entrée principal - sera appelé quand tous les modules sont chargés
local function Initialize()
    -- Vérification que tous les modules nécessaires sont chargés
    local requiredModules = {
        "LootTrackerState",
        "LootTrackerInstance",
        "LootTrackerRolls",
        "LootTrackerParser",
        "LootTrackerAPI"
    }
    
    local missing = {}
    for _, module in ipairs(requiredModules) do
        if not ns[module] then
            table.insert(missing, module)
        end
    end
    
    if #missing > 0 then
        return false
    end
    
    -- Enregistrement des événements
    if ns.LootTrackerAPI and ns.LootTrackerAPI.RegisterEvents then
        ns.LootTrackerAPI.RegisterEvents()
    end
    
    -- Initialisation du niveau M+ au chargement (utile si on /reload en pleine clé)
    if ns.LootTrackerState and ns.LootTrackerState.UpdateActiveKeystoneLevel then
        ns.LootTrackerState.UpdateActiveKeystoneLevel()
    end
    
    return true
end

-- Lancement différé de l'initialisation pour s'assurer que tous les modules sont chargés
if C_Timer and C_Timer.After then
    C_Timer.After(0.1, function()
        Initialize()
    end)
else
    -- Fallback si C_Timer n'est pas disponible
    local frame = CreateFrame("Frame")
    frame:RegisterEvent("ADDON_LOADED")
    frame:SetScript("OnEvent", function(self, event, addonName)
        if addonName == ADDON then
            self:UnregisterEvent("ADDON_LOADED")
            Initialize()
        end
    end)
end
