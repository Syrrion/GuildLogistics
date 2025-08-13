local ADDON, ns = ...
ns.Format = ns.Format or {}
local F = ns.Format

-- Dates standardisées
function F.DateTime(ts, fmt)
    local n = tonumber(ts) or 0
    if n > 0 then return date(fmt or "le %H:%M à %d/%m/%Y", n) end
    return tostring(ts or "")
end

function F.Date(ts, fmt)
    local n = tonumber(ts) or 0
    if n > 0 then return date(fmt or "le %d/%m/%Y", n) end
    return tostring(ts or "")
end

-- Durée relative: secondes -> libellé court
function F.RelativeFromSeconds(sec)
    local n = tonumber(sec); if not n then return "" end
    local s = math.abs(n)
    local d = math.floor(s/86400); s = s%86400
    local h = math.floor(s/3600);  s = s%3600
    local m = math.floor(s/60)
    if d > 0 then return (d.."j "..h.."h") end
    if h > 0 then return (h.."h "..m.."m") end
    return (m.."m")
end

function F.LastSeen(days, hours)
    local d = tonumber(days)
    local h = tonumber(hours)

    if d and d <= 0 then
        -- en ligne géré côté appelant via onlineCount ; si d==0 et pas en ligne, on utilisera h
        if h and h > 0 then return h .. " h" else return "≤ 1 h" end
    end

    d = d or 9999
    if d < 1 then
        if h and h > 0 then return h .. " h" else return "≤ 1 h" end
    elseif d < 30 then
        return d .. " j"
    elseif d < 365 then
        return (math.floor(d/30)) .. " mois"
    else
        return (math.floor(d/365)) .. " ans"
    end
end