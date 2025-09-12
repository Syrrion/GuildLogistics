-- ===================================================
-- Core/Core/Core.lua - Coordinateur principal (refactorisé)
-- ===================================================
-- Fichier principal réduit à un coordinateur qui importe les modules spécialisés
-- et expose les fonctions utilitaires communes

local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
ns.Util = ns.Util or {}
local GLOG = ns.GLOG

-- ===== Fonction de traduction =====
ns.Tr = ns.Tr or function(input, ...)
    if input == nil then return "" end
    local s = tostring(input)
    local key = s
    local v = (ns.L and ns.L[key]) or s
    if select("#", ...) > 0 then
        local ok, out = pcall(string.format, v, ...)
        if ok then return out end
    end
    return v
end

-- ===== Notes de modularisation =====
-- Ce fichier Core.lua a été refactorisé et les fonctions ont été déplacées vers :
--
-- DatabaseManager.lua  - Gestion base de données et initialisation
-- Player/Manager.lua   - Gestion des joueurs, soldes, réserves, ajustements  
-- History.lua         - Gestion historique des sessions, remboursements
-- Economy/Lots.lua    - Gestion des lots, ressources et purges (consolidé avec existant)
--
-- Les modules sont chargés via .toc dans l'ordre de dépendance correct.

-- ===== Alias et compatibilité rétro =====

-- Alias rétro-compatible si jamais du code appelle IsReserve()
GLOG.IsReserve = GLOG.IsReserve or GLOG.IsReserved
