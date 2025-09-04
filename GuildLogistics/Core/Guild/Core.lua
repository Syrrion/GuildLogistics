local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
local GLOG = ns.GLOG

-- True si le joueur est chef de guilde (rank index 0) — autorisation maximale.
function GLOG.IsMaster()
    if IsInGuild and IsInGuild() then
        local _, _, ri = GetGuildInfo("player")
        if ri == 0 then return true end
    end
    return false
end

-- True si le joueur est chef de guilde ou possède des permissions officiers majeures.
function GLOG.IsGM()
    if IsInGuild and IsInGuild() then
        local _, _, ri = GetGuildInfo("player")
        if ri == 0 then return true end
        local function has(fn) return type(fn) == "function" and fn() end
        if has(CanGuildPromote) or has(CanGuildDemote) or has(CanGuildRemove)
        or has(CanGuildInvite) or has(CanEditMOTD) or has(CanEditGuildInfo)
        or has(CanEditPublicNote) then
            return true
        end
    end
    return false
end

-- Renvoie le nom de la guilde du joueur s'il est en guilde, sinon nil.
function GLOG.GetCurrentGuildName()
    if IsInGuild and IsInGuild() then
        local gname = GetGuildInfo("player")
        if type(gname) == "string" and gname ~= "" then return gname end
    end
    return nil
end
