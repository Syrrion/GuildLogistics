-- ===================================================
-- Core/Player/Alias.lua - Système d'alias de joueurs
-- ===================================================
-- Gestion des alias et pseudonymes pour les joueurs

local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
local GLOG = ns.GLOG

-- Small helpers to access compact Main/Alt mapping
local function _MA()
    if GLOG.EnsureDB then GLOG.EnsureDB() end
    _G.GuildLogisticsDB.mainAlt = _G.GuildLogisticsDB.mainAlt or { version = 2, mains = {}, altToMain = {} }
    local t = _G.GuildLogisticsDB.mainAlt
    t.mains       = t.mains       or {}
    t.altToMain   = t.altToMain   or {}
    return t
end

local function _uidFor(name)
    if not name or name == "" then return nil end
    local full = (GLOG and GLOG.ResolveFullName and GLOG.ResolveFullName(name)) or name
    return (GLOG.GetOrAssignUID and GLOG.GetOrAssignUID(full)) or nil
end

-- ===== Système d'alias de joueurs =====

-- Recherche d'un nom complet unique par nom de base (sans realm)
-- @param baseName: string - nom sans realm
-- @return string|nil: nom complet unique ou nil si ambigu/introuvable
local function _FindUniqueFullByBase(baseName)
    if not baseName or baseName == "" then return nil end
    local norm = (GLOG.NormName and GLOG.NormName(baseName)) or tostring(baseName):lower()
    local found
    
    local function scan(db)
        if not (db and db.players) then return end
        for full,_ in pairs(db.players) do
            local b = full:match("^([^%-]+)") or full
            local nb = (GLOG.NormName and GLOG.NormName(b)) or b:lower()
            if nb == norm then
                if found and found ~= full then
                    found = "__AMB__" -- plusieurs royaumes → ambigu
                    return
                end
                found = full
            end
        end
    end
    
    scan(_G.GuildLogisticsDB_Char) 
    if found == "__AMB__" then return nil end
    
    scan(_G.GuildLogisticsDB)     
    if found == "__AMB__" then return nil end
    
    return found
end

-- Résoudre une clé de joueur sans deviner le realm
-- @param name: string - nom avec ou sans realm
-- @return string|nil: nom complet ou nil
local function _AliasPlayerKey_NoGuess(name)
    if not name or name == "" then return nil end
    local s = tostring(name)
    if s:find("%-") then
        return s -- full fourni → on ne touche pas
    end
    -- pas de royaume → chercher un match unique
    return _FindUniqueFullByBase(s)
end

-- Obtenir l'alias d'un joueur
-- @param name: string - nom du joueur
-- @return string|nil: alias du joueur ou nil
function GLOG.GetAliasFor(name)
    if GLOG.EnsureDB then GLOG.EnsureDB() end
    if not name or name == "" then return nil end
    local MA = _MA()
    -- Resolve to main UID first
    local uid = _uidFor(name)
    if not uid then return nil end
    local mainUID = uid
    if not MA.mains[uid] then
        local m = MA.altToMain[uid]
        if m then mainUID = tonumber(m) end
    end
    if not mainUID then return nil end
    local entry = MA.mains[tonumber(mainUID)]
    local alias = (type(entry) == "table") and entry.alias or nil
    if alias and alias ~= "" then return alias end
    return nil
end

-- Définir l'alias d'un joueur localement
-- @param name: string - nom du joueur  
-- @param alias: string - alias à définir
function GLOG.SetAliasLocal(name, alias)
    if GLOG.EnsureDB then GLOG.EnsureDB() end
    local uid = _uidFor(name)
    if not uid then
        if ns and ns.Debug then ns.Debug("alias:set", "uid_not_found", tostring(name)) end
        return
    end
    local MA = _MA()
    -- Determine main UID holder for alias
    local mainUID = uid
    if not MA.mains[uid] then
        local m = MA.altToMain[uid]
        if m then mainUID = tonumber(m) end
    end
    if not mainUID then return end
    local val = tostring(alias or ""):gsub("^%s+",""):gsub("%s+$","")
    local stored = (val ~= "") and val or nil
    local entry = MA.mains[tonumber(mainUID)]
    if type(entry) ~= "table" then entry = {} end
    entry.alias = stored
    MA.mains[tonumber(mainUID)] = entry

    -- Source d'autorité unique: mainAlt.aliasByMain

    if ns and ns.Emit then ns.Emit("alias:changed", tostring(mainUID), stored) end
    if ns and ns.RefreshAll then ns.RefreshAll() end
end

-- Action GM : définit l'alias d'un joueur et le diffuse via ROSTER_UPSERT
function GLOG.GM_SetAlias(name, alias)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then
        if UIErrorsFrame then
            UIErrorsFrame:AddMessage("|cffff6060[GLOG]|r Définition d'alias réservée au GM.", 1, .4, .4)
        end
        return false
    end
    if not name or name=="" then return false end
    GLOG.SetAliasLocal(name, alias)

    GuildLogisticsDB.meta = GuildLogisticsDB.meta or {}
    local rv = (GuildLogisticsDB.meta.rev or 0) + 1
    GuildLogisticsDB.meta.rev = rv
    GuildLogisticsDB.meta.lastModified = time()

    -- Broadcast a roster upsert on the MAIN holder to refresh displays on all clients
    if GLOG.BroadcastRosterUpsert then
        local MA = _MA(); local uid = _uidFor(name)
        local mainUID = uid
        if uid and not MA.mains[uid] then mainUID = tonumber(MA.altToMain[uid] or uid) end
        local mainName = (mainUID and GLOG.GetNameByUID and GLOG.GetNameByUID(mainUID)) or name
        GLOG.BroadcastRosterUpsert(mainName)
    end
    return true
end

-- alias stockés dans mains[uid].alias (schéma v2)

-- ===== Export des fonctions utilitaires =====

-- Export des fonctions utilitaires privées pour autres modules
GLOG._FindUniqueFullByBase = _FindUniqueFullByBase
GLOG._AliasPlayerKey_NoGuess = _AliasPlayerKey_NoGuess
