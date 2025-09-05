local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
local GLOG = ns.GLOG

-- Retourne le tampon courant des logs debug (table). Stub sûr tant que Comm n'est pas prêt.
if type(GLOG.GetDebugLogs) ~= "function" then
    local _fallbackDebug = {}
    function GLOG.GetDebugLogs()
        return _fallbackDebug
    end
end

-- Définit une table 't' comme source des logs debug (référence partagée).
if type(GLOG._SetDebugLogsRef) ~= "function" then
    function GLOG._SetDebugLogsRef(t)
        if type(t) == "table" then
            GLOG.GetDebugLogs = function()
                return t
            end
        end
    end
end

-- True si l'affichage des erreurs Lua (scriptErrors) est activé.
function GLOG.IsScriptErrorsEnabled()
    if type(GetCVar) == "function" then
        local v = tostring(GetCVar("scriptErrors") or "0")
        return (v == "1") or (v:lower() == "true")
    end
    return false
end

-- Active/désactive l'affichage des erreurs Lua ; renvoie l'état final.
function GLOG.SetScriptErrorsEnabled(enabled)
    local v = enabled and "1" or "0"
    if type(SetCVar) == "function" then
        pcall(SetCVar, "scriptErrors", v)
    end
    return GLOG.IsScriptErrorsEnabled()
end
