-- ===================================================
-- Core/Debug/ErrorHandler.lua - Détection et traitement des erreurs Lua
-- ===================================================
-- Filtrage, anti-spam et construction des rapports d'erreurs

local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
ns.Util = ns.Util or {}

local GLOG, U = ns.GLOG, ns.Util

-- =========================
-- === Utilitaires base ===
-- =========================

-- Helper pour nom complet du joueur
local function playerFullName()
    if U and U.playerFullName then return U.playerFullName() end
    local n, r = UnitName and UnitName("player"), GetNormalizedRealmName and GetNormalizedRealmName()
    if n and r and r ~= "" then return (tostring(n) .. "-" .. tostring(r):gsub("%s+",""):gsub("'","")) end
    return tostring(n or "player")
end

-- =========================
-- === Filtrage erreurs ===
-- =========================

-- Ne garde que les erreurs dont **la ligne fautive** (1ʳᵉ ligne du message)
-- pointe dans notre AddOn. On **ignore la pile d'appel**.
local function isOurError(msg, _stack)
    local m = tostring(msg or "")
    -- Extraire uniquement la 1ʳᵉ ligne (format standard WoW: "Interface\AddOns\...\file.lua:123: ...")
    local first = m:match("^[^\r\n]+") or ""

    -- Détection plus flexible - chercher GuildLogistics dans le chemin
    if first:find("GuildLogistics", 1, true) then
        return true
    end

    -- Si la 1ʳᵉ ligne n'indique pas un fichier de notre AddOn, on rejette
    return false
end

-- =========================
-- === Anti-spam système ===
-- =========================

-- Anti-spam par signature (mémoire session)
local _seen = {}
local function generateSignature(msg, stack)
    local line1 = tostring(msg or ""):gsub("%s+"," "):sub(1, 160)
    local top   = tostring(stack or ""):match("([^\n\r]+)") or ""
    return line1 .. " | " .. top
end

-- Vérifie si une erreur a déjà été vue récemment (anti-spam 60s)
local function isSpamError(msg, stack)
    local key = generateSignature(msg, stack)
    local now = (time and time()) or 0
    if _seen[key] and (now - _seen[key]) < 60 then 
        return true 
    end
    _seen[key] = now
    return false
end

-- =========================
-- === Construction rapport ===
-- =========================

-- Construction d'un rapport compact
local function buildReport(msg)
    return {
        ts  = (time and time()) or 0,
        who = playerFullName(),
        ver = (GLOG.GetAddonVersion and GLOG.GetAddonVersion()) or "",
        msg = tostring(msg or ""),
        st  = tostring((debugstack and debugstack(3)) or ""),
    }
end

-- =========================
-- === API publique ===
-- =========================

function GLOG.ErrorHandler_IsOurError(msg, stack)
    return isOurError(msg, stack)
end

function GLOG.ErrorHandler_IsSpam(msg, stack)
    return isSpamError(msg, stack)
end

function GLOG.ErrorHandler_BuildReport(msg)
    return buildReport(msg)
end

-- Traiter les erreurs précoces capturées avant l'init
function GLOG.ErrorHandler_ProcessEarlyErrors()
    if not ns.GetEarlyErrors then return end
    
    local earlyErrors = ns.GetEarlyErrors()
    if not earlyErrors or #earlyErrors == 0 then return end
    
    -- Vérifier si le système de communication est prêt
    if not GLOG.GetGuildMasterCached or not GLOG.ErrorComm_SendOrQueue then
        -- Programmer un délai pour réessayer quand le système sera prêt
        C_Timer.After(5, function()
            GLOG.ErrorHandler_ProcessEarlyErrors()
        end)
        return
    end
    
    for _, errorInfo in ipairs(earlyErrors) do
        -- Anti-spam : ignorer si vue récemment
        if not isSpamError(errorInfo.msg, errorInfo.stack) then
            local rep = {
                ts = errorInfo.ts,
                who = playerFullName(),
                ver = (GLOG.GetAddonVersion and GLOG.GetAddonVersion()) or "",
                msg = errorInfo.msg,
                st = errorInfo.stack,
                early = true
            }
            
            -- Routing selon le rôle
            if GLOG and GLOG.IsMaster and GLOG.IsMaster() then
                -- GM : ajout direct au journal local
                if GLOG.ErrorJournal_AddReport then
                    GLOG.ErrorJournal_AddReport(rep, rep.who)
                else
                    -- Fallback si module journal pas encore chargé
                    GuildLogisticsDB = GuildLogisticsDB or {}
                    GuildLogisticsDB.errors = GuildLogisticsDB.errors or { list = {}, nextId = 1 }
                    local t = GuildLogisticsDB.errors
                    local id = tonumber(t.nextId or 1) or 1
                    rep.id = id
                    rep.done = false
                    t.list[#t.list+1] = rep
                    t.nextId = id + 1
                    if ns.Emit then ns.Emit("errors:changed") end
                end
            else
                -- Client : Pour les erreurs précoces, forcer l'ajout à la queue pending
                -- même si le GM semble offline (système pas encore initialisé)
                if GLOG.Pending_AddERRRPT then
                    GLOG.Pending_AddERRRPT(rep)
                end
            end
        end
    end
    
    -- Effacer les erreurs traitées pour éviter de les retraiter
    if ns.ClearEarlyErrors then
        ns.ClearEarlyErrors()
    end
    
    -- Programmer un flush dans quelques secondes pour s'assurer que les erreurs précoces
    -- soient envoyées quand le système sera complètement prêt
    C_Timer.After(10, function()
        if GLOG.Pending_FlushToMaster then
            local gmName = GLOG.GetGuildMasterCached and select(1, GLOG.GetGuildMasterCached())
            if gmName then
                GLOG.Pending_FlushToMaster(gmName)
            end
        end
    end)
end

-- =========================
-- === Hook global handler ===
-- =========================

-- Hook global error handler (chainé, sûr)
do
    local prev = geterrorhandler and geterrorhandler() or nil
    local function handler(msg)
        local ok, err = pcall(function()
            local stack = (debugstack and debugstack(3)) or ""
            
            -- Filtrage : seulement nos erreurs
            if not isOurError(msg, stack) then 
                return 
            end

            -- Anti-spam : ignorer si vue récemment
            if isSpamError(msg, stack) then 
                return 
            end

            -- Construire le rapport
            local rep = buildReport(msg)

            -- Routing selon le rôle
            if GLOG and GLOG.IsMaster and GLOG.IsMaster() then
                -- GM : ajout direct au journal local
                if GLOG.ErrorJournal_AddReport then
                    GLOG.ErrorJournal_AddReport(rep, rep.who)
                else
                    -- Fallback si module journal pas encore chargé
                    GuildLogisticsDB = GuildLogisticsDB or {}
                    GuildLogisticsDB.errors = GuildLogisticsDB.errors or { list = {}, nextId = 1 }
                    local t = GuildLogisticsDB.errors
                    local id = tonumber(t.nextId or 1) or 1
                    rep.id   = id
                    rep.done = false
                    t.list[#t.list+1] = rep
                    t.nextId = id + 1
                    if ns.Emit then ns.Emit("errors:changed") end
                end
            else
                -- Client : envoi vers GM (direct ou pending)
                if GLOG.ErrorComm_SendOrQueue then
                    GLOG.ErrorComm_SendOrQueue(rep)
                end
            end
        end)
        
        -- Chaîner avec le handler précédent
        if prev then prev(msg) end
    end
    
    if seterrorhandler then 
        seterrorhandler(handler)
    else
        -- Fallback : hook sur geterrorhandler si seterrorhandler n'existe pas
        _G.geterrorhandler = function() return handler end
    end
end
