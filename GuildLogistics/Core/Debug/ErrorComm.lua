-- ===================================================
-- Core/Debug/ErrorComm.lua - Communication des erreurs réseau
-- ===================================================
-- Envoi et réception des rapports d'erreurs entre clients et GM

local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}

local GLOG = ns.GLOG

-- =========================
-- === Émission (clients) ===
-- =========================

-- Emission vers GM (même principe que TX_REQ) : direct si GM en ligne, sinon pending
function GLOG.ErrorComm_SendOrQueue(rep)
    local gmName = GLOG.GetGuildMasterCached and select(1, GLOG.GetGuildMasterCached())
    local online = (GLOG.IsMasterOnline and GLOG.IsMasterOnline()) or false
    
    if gmName and online and GLOG.Comm_Whisper then
        -- GM en ligne : envoi direct
        GLOG.Comm_Whisper(gmName, "ERR_REPORT", rep)
    else
        -- GM hors ligne ou indisponible : mise en attente
        if GLOG.Pending_AddERRRPT then
            GLOG.Pending_AddERRRPT(rep)
        end
    end
end

-- =========================
-- === Rétro-compatibilité ===
-- =========================

-- Alias pour compatibilité avec l'ancien système
function GLOG.Errors_SendOrQueue(rep)
    return GLOG.ErrorComm_SendOrQueue(rep)
end
