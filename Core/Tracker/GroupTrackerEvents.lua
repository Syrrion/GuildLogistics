local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
ns.UI   = ns.UI   or {}
ns.Util = ns.Util or {}
ns.Data = ns.Data or {}

local GLOG, UI, U, Data = ns.GLOG, ns.UI, ns.Util, ns.Data
local Tr = ns.Tr or function(s) return s end

local _G = _G
if setfenv then
    setfenv(1, setmetatable({}, { __index = _G, __newindex = _G }))
end

-- =========================
-- === GESTION ÉVÉNEMENTS ===
-- =========================

-- Abonnements dynamiques : owner commun + forward-declare pour usage avant définition
local GT_EVT_OWNER = "GroupTracker:active"

-- =========================
-- === UTILITAIRES CLEU ===
-- =========================

local function _isGroupSource(flags)
    if not flags then return false end
    local band = bit.band
    local mine  = COMBATLOG_OBJECT_AFFILIATION_MINE or 0x00000001
    local party = COMBATLOG_OBJECT_AFFILIATION_PARTY or 0x00000002
    local raid  = COMBATLOG_OBJECT_AFFILIATION_RAID or 0x00000004
    local player= COMBATLOG_OBJECT_TYPE_PLAYER or 0x00000400
    return (band(flags, player) ~= 0) and (band(flags, mine + party + raid) ~= 0)
end

-- =========================
-- === HANDLER PRINCIPAL ===
-- =========================

-- Centralisation via Core/Events.lua
local function _OnEvent(_, event, ...)
    if event == "PLAYER_ENTERING_WORLD" then
        -- Rebuild des lookups
        if ns.GroupTrackerConsumables then
            if ns.GroupTrackerConsumables.RebuildCategoryLookup then
                ns.GroupTrackerConsumables.RebuildCategoryLookup()
            end
            if ns.GroupTrackerConsumables.RebuildCustomLookup then
                ns.GroupTrackerConsumables.RebuildCustomLookup()
            end
            if ns.GroupTrackerConsumables.EnsureDefaultCustomLists then
                ns.GroupTrackerConsumables.EnsureDefaultCustomLists(false)
            end
        end

        -- État initial
        local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
        local state = ns.GroupTrackerState and ns.GroupTrackerState.GetState() or {}
        state.enabled = (store.enabled == true)

        -- Détection combat initial
        local session = ns.GroupTrackerSession and ns.GroupTrackerSession.GetSession() or {}
        local inCombat = UnitAffectingCombat("player") and true or false
        
        if ns.GroupTrackerSession and ns.GroupTrackerSession.SetInCombat then
            ns.GroupTrackerSession.SetInCombat(inCombat)
        end

        if inCombat then
            local lbl, isBoss = "", false
            if ns.GroupTrackerSession and ns.GroupTrackerSession.ComputeEncounterLabel then
                lbl, isBoss = ns.GroupTrackerSession.ComputeEncounterLabel()
            end
            
            if ns.GroupTrackerSession then
                if ns.GroupTrackerSession.SetLabel then ns.GroupTrackerSession.SetLabel(lbl) end
                if ns.GroupTrackerSession.SetIsBoss then ns.GroupTrackerSession.SetIsBoss(isBoss) end
                if ns.GroupTrackerSession.SetStart then ns.GroupTrackerSession.SetStart(time and time() or 0) end
            end
            
            store.viewIndex = 0  -- live
            
            local roster = {}
            if ns.GroupTrackerSession and ns.GroupTrackerSession.BuildRosterSet then
                local rosterSet = ns.GroupTrackerSession.BuildRosterSet()
                if ns.GroupTrackerSession.BuildRosterArrayFromSet then
                    roster = ns.GroupTrackerSession.BuildRosterArrayFromSet(rosterSet)
                end
            end
            if ns.GroupTrackerSession and ns.GroupTrackerSession.SetRoster then
                ns.GroupTrackerSession.SetRoster(roster)
            end
        else
            if #store.segments == 0 then
                local maxIdx = #store.segments
                if store.viewIndex == 0 then
                    store.viewIndex = math.min(1, maxIdx)
                else
                    store.viewIndex = math.min(store.viewIndex or 1, maxIdx)
                end
            else
                if (store.viewIndex or 1) == 0 then store.viewIndex = 1 end
            end
        end

        -- Démarrage : si la fenêtre était ouverte la dernière fois, on la rouvre
        if store.winOpen == true then
            if GLOG and GLOG.GroupTracker_ShowWindow then
                GLOG.GroupTracker_ShowWindow(true)
            end
        elseif ns.GroupTrackerState and ns.GroupTrackerState.RecomputeEnabled then
            ns.GroupTrackerState.RecomputeEnabled()
        end

    elseif event == "ADDON_LOADED" then
        local name = ...
        if name == ADDON then
            if ns.GroupTrackerConsumables and ns.GroupTrackerConsumables.RebuildCategoryLookup then
                ns.GroupTrackerConsumables.RebuildCategoryLookup()
            end
            _RefreshEventSubscriptions()
        end

    elseif event == "PLAYER_LOGIN" then
        if ns.GroupTrackerConsumables and ns.GroupTrackerConsumables.RebuildCategoryLookup then
            ns.GroupTrackerConsumables.RebuildCategoryLookup()
        end
        _RefreshEventSubscriptions()

    elseif event == "GROUP_ROSTER_UPDATE" then
        if ns.GroupTrackerSession and ns.GroupTrackerSession.PurgeStale then
            ns.GroupTrackerSession.PurgeStale()
        end
        
        local state = ns.GroupTrackerState and ns.GroupTrackerState.GetState() or {}
        local win = state.win
        if win and win._Refresh then win:_Refresh() end

    elseif event == "ENCOUNTER_START" then
        local _, encounterName = ...
        if encounterName and encounterName ~= "" then
            if ns.GroupTrackerSession then
                if ns.GroupTrackerSession.SetLabel then ns.GroupTrackerSession.SetLabel(encounterName) end
                if ns.GroupTrackerSession.SetIsBoss then ns.GroupTrackerSession.SetIsBoss(true) end
            end
        end
        
        local state = ns.GroupTrackerState and ns.GroupTrackerState.GetState() or {}
        local win = state.win
        if win and win._Refresh then win:_Refresh() end

    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Entrée en combat
        if ns.GroupTrackerSession and ns.GroupTrackerSession.ClearLive then
            ns.GroupTrackerSession.ClearLive()
        end
        
        if ns.GroupTrackerSession and ns.GroupTrackerSession.SetInCombat then
            ns.GroupTrackerSession.SetInCombat(true)
        end
        
        if ns.GroupTrackerSession and ns.GroupTrackerSession.SetStart then
            ns.GroupTrackerSession.SetStart(time and time() or 0)
        end
        
        local lbl, isBoss = "", false
        if ns.GroupTrackerSession and ns.GroupTrackerSession.ComputeEncounterLabel then
            lbl, isBoss = ns.GroupTrackerSession.ComputeEncounterLabel()
        end
        
        if ns.GroupTrackerSession then
            if ns.GroupTrackerSession.SetLabel then ns.GroupTrackerSession.SetLabel(lbl) end
            if ns.GroupTrackerSession.SetIsBoss then ns.GroupTrackerSession.SetIsBoss(isBoss) end
        end
        
        local roster = {}
        if ns.GroupTrackerSession and ns.GroupTrackerSession.BuildRosterSet then
            local rosterSet = ns.GroupTrackerSession.BuildRosterSet()
            if ns.GroupTrackerSession.BuildRosterArrayFromSet then
                roster = ns.GroupTrackerSession.BuildRosterArrayFromSet(rosterSet)
            end
        end
        if ns.GroupTrackerSession and ns.GroupTrackerSession.SetRoster then
            ns.GroupTrackerSession.SetRoster(roster)
        end
        
        local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
        store.viewIndex = 0  -- Live
        
        local state = ns.GroupTrackerState and ns.GroupTrackerState.GetState() or {}
        local win = state.win
        if win and win._Refresh then win:_Refresh() end

    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Sortie de combat - créer un segment d'historique
        local seg = nil
        if ns.GroupTrackerSession and ns.GroupTrackerSession.CreateSegment then
            seg = ns.GroupTrackerSession.CreateSegment()
        end

        if ns.GroupTrackerSession and ns.GroupTrackerSession.SetInCombat then
            ns.GroupTrackerSession.SetInCombat(false)
        end
        
        if ns.GroupTrackerSession and ns.GroupTrackerSession.ClearLive then
            ns.GroupTrackerSession.ClearLive()
        end

        local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
        local maxIdx = store.segments and #store.segments or 0
        if store.viewIndex == 0 then
            store.viewIndex = math.min(1, maxIdx)
        else
            store.viewIndex = math.min(store.viewIndex or 1, maxIdx)
        end
        
        local state = ns.GroupTrackerState and ns.GroupTrackerState.GetState() or {}
        local win = state.win
        if win and win._Refresh then win:_Refresh() end

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        local state = ns.GroupTrackerState and ns.GroupTrackerState.GetState() or {}
        if not state.enabled then return end
        
        local unit, castGUID, spellID = ...
        if not unit or not spellID then return end
        if unit ~= "player" and (not unit:find("^raid") and not unit:find("^party")) then return end
        -- On confie l'enregistrement au CLEU pour éviter tout doublon (CAST_SUCCESS/AURA_APPLIED).
        return

    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        local state = ns.GroupTrackerState and ns.GroupTrackerState.GetState() or {}
        if not state.enabled then return end
        
        local ts, sub, _, sourceGUID, sourceName, sourceFlags, _, destGUID, destName, _, _, spellID, spellName =
            CombatLogGetCurrentEventInfo()
        if not _isGroupSource(sourceFlags) then return end

        -- On garde CAST_SUCCESS et AURA_APPLIED (utile pour potions/pierres).
        if sub == "SPELL_CAST_SUCCESS" or sub == "SPELL_AURA_APPLIED" then
            local normID = spellID
            if ns.GroupTrackerConsumables and ns.GroupTrackerConsumables.NormalizeSpellID then
                normID = ns.GroupTrackerConsumables.NormalizeSpellID(spellID)
            end
            
            local sName = spellName or ""
            if not sName or sName == "" then
                if GetSpellInfo and normID then
                    sName = select(1, GetSpellInfo(normID)) or ""
                end
            end
            
            local cat = nil
            if ns.GroupTrackerConsumables and ns.GroupTrackerConsumables.DetectCategory then
                cat = ns.GroupTrackerConsumables.DetectCategory(normID, sName)
            end
            
            local ids = {}
            if ns.GroupTrackerConsumables and ns.GroupTrackerConsumables.MatchCustomColumns then
                ids = ns.GroupTrackerConsumables.MatchCustomColumns(normID, sName)
            end

            if not cat and #ids == 0 then return end

            local now = ts or GetTime() -- même base partout pour la dédup
            local who = sourceName or destName
            
            local shouldAccept = true
            if ns.GroupTrackerSession and ns.GroupTrackerSession.ShouldAcceptEvent then
                shouldAccept = ns.GroupTrackerSession.ShouldAcceptEvent(sourceGUID, who, normID, now)
            end
            if not shouldAccept then return end

            -- Règle d'enregistrement unique (évite les doublons et l'entrée vide)
            if cat == "heal" or cat == "util" or cat == "stone" then
                -- Ces catégories alimentent le timer + compteur
                if ns.GroupTrackerAPI and ns.GroupTrackerAPI.OnConsumableUsed then
                    ns.GroupTrackerAPI.OnConsumableUsed(who, cat, normID, sName)
                end
                -- Pas d'OnCustomUsed en plus : les colonnes lisent déjà ces compteurs
            elseif cat == "cddef" or cat == "dispel" or cat == "taunt" or cat == "move"
                or cat == "kick" or cat == "cc" or cat == "special" then
                -- Catégories « action » : uniquement le/les compteurs de colonnes custom
                if #ids > 0 then
                    if ns.GroupTrackerAPI and ns.GroupTrackerAPI.OnCustomUsed then
                        for _, cid in ipairs(ids) do 
                            ns.GroupTrackerAPI.OnCustomUsed(who, cid, normID, sName) 
                        end
                    end
                else
                    -- fallback si pas de colonne
                    if ns.GroupTrackerAPI and ns.GroupTrackerAPI.OnConsumableUsed then
                        ns.GroupTrackerAPI.OnConsumableUsed(who, cat, normID, sName)
                    end
                end
            else
                -- Pas de cat connue mais colonnes custom matchées
                if ns.GroupTrackerAPI and ns.GroupTrackerAPI.OnCustomUsed then
                    for _, cid in ipairs(ids) do 
                        ns.GroupTrackerAPI.OnCustomUsed(who, cid, normID, sName) 
                    end
                end
            end
        end
    end
end

-- =========================
-- === GESTION ABONNEMENTS ===
-- =========================

local function _UnregisterActiveEvents()
    if ns.Events and ns.Events.UnregisterOwner then
        ns.Events.UnregisterOwner(GT_EVT_OWNER)
    end
    local state = ns.GroupTrackerState and ns.GroupTrackerState.GetState() or {}
    if ns.GroupTrackerState and ns.GroupTrackerState.SetActiveEventsRegistered then
        ns.GroupTrackerState.SetActiveEventsRegistered(false)
    end
end

-- Abonnements dynamiques aux events du GroupTracker
local function _RegisterActiveEvents()
    local state = ns.GroupTrackerState and ns.GroupTrackerState.GetState() or {}
    local registered = false
    if ns.GroupTrackerState and ns.GroupTrackerState.GetActiveEventsRegistered then
        registered = ns.GroupTrackerState.GetActiveEventsRegistered()
    end
    if registered then return end
    
    if ns.Events and ns.Events.Register then
        ns.Events.Register("PLAYER_ENTERING_WORLD",       GT_EVT_OWNER, _OnEvent)
        ns.Events.Register("GROUP_ROSTER_UPDATE",         GT_EVT_OWNER, _OnEvent)
        ns.Events.Register("COMBAT_LOG_EVENT_UNFILTERED", GT_EVT_OWNER, _OnEvent)
        ns.Events.Register("PLAYER_REGEN_DISABLED",       GT_EVT_OWNER, _OnEvent)
        ns.Events.Register("PLAYER_REGEN_ENABLED",        GT_EVT_OWNER, _OnEvent)
        ns.Events.Register("ENCOUNTER_START",             GT_EVT_OWNER, _OnEvent)
        ns.Events.Register("UNIT_SPELLCAST_SUCCEEDED",    GT_EVT_OWNER, _OnEvent)
    end
    
    if ns.GroupTrackerState and ns.GroupTrackerState.SetActiveEventsRegistered then
        ns.GroupTrackerState.SetActiveEventsRegistered(true)
    end
end

function _RefreshEventSubscriptions()
    if ns.GroupTrackerState and ns.GroupTrackerState.RecomputeEnabled then
        ns.GroupTrackerState.RecomputeEnabled()
    end
    
    local state = ns.GroupTrackerState and ns.GroupTrackerState.GetState() or {}
    if state.enabled then
        _RegisterActiveEvents()
    else
        _UnregisterActiveEvents()
    end
end

-- =========================
-- ===   API PUBLIQUE    ===
-- =========================

ns.GroupTrackerEvents = {
    -- Gestion des abonnements
    RegisterActiveEvents = function() _RegisterActiveEvents() end,
    UnregisterActiveEvents = function() _UnregisterActiveEvents() end,
    RefreshSubscriptions = function() _RefreshEventSubscriptions() end,
    
    -- Handler principal
    OnEvent = _OnEvent,
}

-- Export vers le namespace global pour compatibilité
ns.GLOG.GroupTrackerEvents = ns.GroupTrackerEvents

-- =========================
-- === BOOTSTRAP ===
-- =========================

-- Bootstrap minimal : toujours écouté pour initialiser l'état
if ns.Events and ns.Events.Register then
    ns.Events.Register("ADDON_LOADED", _OnEvent)
    ns.Events.Register("PLAYER_LOGIN", _OnEvent)
end

-- Active/arrête les autres events selon l'état courant
_RefreshEventSubscriptions()
