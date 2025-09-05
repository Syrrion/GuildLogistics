-- ===================================================
-- Core/Player/Alias.lua - Système d'alias de joueurs
-- ===================================================
-- Gestion des alias et pseudonymes pour les joueurs

local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
local GLOG = ns.GLOG

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
    local key = _AliasPlayerKey_NoGuess(name) 
    if not key then return nil end
    
    local rec = (GuildLogisticsDB and GuildLogisticsDB.players and GuildLogisticsDB.players[key])
            or (GuildLogisticsDB_Char and GuildLogisticsDB_Char.players and GuildLogisticsDB_Char.players[key])
    return rec and rec.alias or nil
end

-- Définir l'alias d'un joueur localement
-- @param name: string - nom du joueur  
-- @param alias: string - alias à définir
function GLOG.SetAliasLocal(name, alias)
    if GLOG.EnsureDB then GLOG.EnsureDB() end
    local key = _AliasPlayerKey_NoGuess(name)
    if not key then
        -- pas de clé fiable → ne rien créer (évite les entrées fantômes sur ton royaume)
        if ns and ns.Debug then ns.Debug("alias:set", "ambiguous_or_not_found", tostring(name)) end
        return
    end

    -- Écrit côté DB compte (si dispo), sinon côté perso
    local db = _G.GuildLogisticsDB or _G.GuildLogisticsDB_Char
    db.players = db.players or {}
    local rec = db.players[key] or { solde=0, reserved=true }

    local val = tostring(alias or ""):gsub("^%s+",""):gsub("%s+$","")
    rec.alias = (val ~= "") and val or nil
    db.players[key] = rec

    if ns and ns.Emit then ns.Emit("alias:changed", key, val) end
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

    if GLOG.BroadcastRosterUpsert then
        GLOG.BroadcastRosterUpsert(name)  -- inclura l'alias (voir Comm.lua)
    end
    return true
end

-- ===== Export des fonctions utilitaires =====

-- Export des fonctions utilitaires privées pour autres modules
GLOG._FindUniqueFullByBase = _FindUniqueFullByBase
GLOG._AliasPlayerKey_NoGuess = _AliasPlayerKey_NoGuess
