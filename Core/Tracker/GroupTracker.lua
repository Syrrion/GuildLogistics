local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
ns.UI   = ns.UI   or {}
ns.Util = ns.Util or {}
ns.Data = ns.Data or {}

local GLOG, UI, U, Data = ns.GLOG, ns.UI, ns.Util, ns.Data
local Tr = ns.Tr or function(s) return s end

local _G = _G
if setfenv then
    setfenv(1, setmetatable({}, { __index = _G, __newindex = _G }))
end

-- =========================
-- ===  GROUP TRACKER    ===
-- =========================

--[[
    GroupTracker - Module principal
    
    Ce fichier sert de point d'entrée et d'orchestrateur pour le système GroupTracker.
    La logique métier est répartie dans les modules spécialisés suivants :
    
    - GroupTrackerState.lua      : Gestion d'état et stockage persistant
    - GroupTrackerSession.lua    : Session de combat et gestion du roster
    - GroupTrackerConsumables.lua: Détection des consommables et catégories
    - GroupTrackerUI.lua         : Interface utilisateur et affichage
    - GroupTrackerAPI.lua        : API publique exposée (GLOG.GroupTracker_*)
    - GroupTrackerEvents.lua     : Gestion des événements WoW
    
    Les modules sont automatiquement chargés par le système de fichiers de WoW
    dans l'ordre défini par le TOC ou la structure de dossiers.
]]

-- =========================
-- === INITIALISATION ===
-- =========================

-- Point d'entrée principal - sera appelé quand tous les modules sont chargés
local function Initialize()
    -- Vérification que tous les modules nécessaires sont chargés
    local requiredModules = {
        "GroupTrackerState",
        "GroupTrackerSession", 
        "GroupTrackerConsumables",
        "GroupTrackerUI",
        "GroupTrackerAPI",
        "GroupTrackerEvents"
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
    
    -- Initialisation réussie
    return true
end

-- =========================
-- === COMPATIBILITÉ ===
-- =========================

-- Assure la rétro-compatibilité en exposant les fonctions dans l'ancienne structure
-- Toutes les vraies implémentations sont maintenant dans GroupTrackerAPI.lua

-- Les fonctions sont automatiquement exposées par chaque module dans ns.GLOG.*
-- Aucun mapping supplémentaire n'est nécessaire ici.

-- =========================
-- === BOOTSTRAP ===
-- =========================

-- Délai d'initialisation pour s'assurer que tous les modules sont chargés
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
            Initialize()
            self:UnregisterAllEvents()
        end
    end)
end
