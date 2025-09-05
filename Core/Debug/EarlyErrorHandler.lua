-- ===================================================
-- Core/Debug/EarlyErrorHandler.lua - Hook précoce des erreurs
-- ===================================================
-- Hook minimal installé en premier pour capturer toutes les erreurs

local ADDON, ns = ...

-- Hook minimal immédiat (avant même l'initialisation de GLOG)
do
    -- Queue temporaire pour les erreurs capturées avant l'init complète
    local _earlyErrors = {}
    
    -- Fonction de filtrage minimale
    local function isOurError(msg)
        local m = tostring(msg or "")
        local first = m:match("^[^\r\n]+") or ""
        
        -- Détection plus flexible - chercher GuildLogistics dans le chemin
        return first:find("GuildLogistics", 1, true) ~= nil
    end
    
    -- Handler minimal
    local prev = geterrorhandler and geterrorhandler() or nil
    local function earlyHandler(msg)
        -- Si c'est notre erreur, la stocker
        if isOurError(msg) then
            local errorInfo = {
                msg = tostring(msg or ""),
                stack = (debugstack and debugstack(3)) or "",
                ts = (time and time()) or 0,
                early = true -- marqueur que c'est une erreur précoce
            }
            table.insert(_earlyErrors, errorInfo)
        end
        
        -- Chaîner avec le handler précédent
        if prev then prev(msg) end
    end
    
    -- Installer le hook immédiatement
    if seterrorhandler then 
        seterrorhandler(earlyHandler)
    end
    
    -- Fonction pour récupérer les erreurs précoces (appelée plus tard par le système principal)
    ns.GetEarlyErrors = function()
        return _earlyErrors
    end
    
    -- Fonction pour effacer les erreurs traitées
    ns.ClearEarlyErrors = function()
        _earlyErrors = {}
    end
end
