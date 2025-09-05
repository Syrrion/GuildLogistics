local ADDON, ns = ...
ns.Util = ns.Util or {}
local U = ns.Util

local _debouncers = {}
local _throttleNext = {}

-- Programme 'fn' après 'delay' secondes en annulant les appels précédents pour la même 'key'.
-- "Dernier appel gagne" — utile pour limiter les rafales d'événements.
function U.Debounce(key, delay, fn)
    if type(fn) ~= "function" then return end
    delay = tonumber(delay) or 0
    local t = _debouncers[key]
    if t and t.Cancel then t:Cancel() end
    if C_Timer and C_Timer.NewTimer then
        _debouncers[key] = C_Timer.NewTimer(delay, function()
            _debouncers[key] = nil
            local ok, err = pcall(fn)
            if not ok then geterrorhandler()(err) end
        end)
    else
        _debouncers[key] = nil
        fn()
    end
end

-- Retourne true si l'intervalle est écoulé depuis le dernier passage pour 'key',
-- et réserve le prochain créneau ; sinon false.
function U.Throttle(key, interval)
    interval = tonumber(interval) or 0
    local nowp = (GetTimePreciseSec and GetTimePreciseSec())
              or (debugprofilestop and (debugprofilestop() / 1000))
              or 0
    local nextAt = _throttleNext[key] or 0
    if nowp < nextAt then return false end
    _throttleNext[key] = nowp + interval
    return true
end

-- Exécute 'fn' après 'sec' secondes (fallback exécution immédiate si C_Timer indisponible).
function U.After(sec, fn)
    if C_Timer and C_Timer.After and type(fn) == "function" then
        C_Timer.After(tonumber(sec) or 0, fn)
    elseif type(fn) == "function" then
        pcall(fn)
    end
end
