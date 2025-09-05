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
-- ===   ÉTAT & STORE   ===
-- =========================

-- État local du GroupTracker
local state = {
    enabled = false,
    uses = {},         -- [full] = { heal=0, util=0, stone=0 } (session live combat uniquement)
    win  = nil,        -- frame principale
    tick = nil,        -- ticker de refresh
    popup = nil,       -- popup d'historique
    lastPopup = nil,   -- référence à la dernière popup
    _activeEventsRegistered = false,
}

-- Store unique (perso) — écrit bien dans les SavedVariables globales via _G
local function _Store()
    _G.GuildLogisticsUI_Char = _G.GuildLogisticsUI_Char or {}
    _G.GuildLogisticsUI_Char.groupTracker = _G.GuildLogisticsUI_Char.groupTracker or {}
    local s = _G.GuildLogisticsUI_Char.groupTracker

    s.cooldown   = s.cooldown   or { heal = 300, util = 300, stone = 300 }
    s.expiry     = s.expiry     or {}  -- [full] = { heal=epoch, util=epoch, stone=epoch }
    s.segments   = s.segments   or {}
    s.viewIndex  = s.viewIndex  or 1   -- 1 = segment le plus récent
    s.enabled    = (s.enabled == true)

    -- Opacités / UI
    s.opacity          = tonumber(s.opacity          or 0.95) or 0.95
    s.textOpacity      = tonumber(s.textOpacity      or 1.00) or 1.00
    s.titleTextOpacity = tonumber(s.titleTextOpacity or 1.00) or 1.00
    s.btnOpacity       = tonumber(s.btnOpacity       or 1.00) or 1.00

    -- États & options
    s.recording  = (s.recording == true)
    s.winOpen    = (s.winOpen == true)
    s.locked     = (s.locked == true)
    s.colVis     = s.colVis or { heal = true, util = true, stone = true }

    -- Suivi personnalisé
    s.custom = s.custom or {}
    s.custom.columns = s.custom.columns or {}
    s.custom.nextId  = tonumber(s.custom.nextId or 1) or 1

    -- Autres options
    s.rowHeight = tonumber(s.rowHeight or 22) or 22
    s.popupTitleTextHidden = (s.popupTitleTextHidden == true)

    return s
end

-- Recalcule l'état enabled basé sur les conditions actuelles
local function _RecomputeEnabled()
    local s = _Store()
    local winShown = state.win and state.win:IsShown()
    state.enabled = (winShown or s.recording) and true or false
end

-- =========================
-- ===   API D'ACCÈS    ===
-- =========================

-- Interface publique pour accéder aux données d'état
ns.GroupTrackerState = {
    -- Accès à l'état local
    GetState = function() return state end,
    
    -- Accès au store persistant
    GetStore = function() return _Store() end,
    
    -- Recalcul de l'état enabled
    RecomputeEnabled = function() return _RecomputeEnabled() end,
    
    -- Getters/Setters pour les propriétés communes
    IsEnabled = function() return state.enabled end,
    SetEnabled = function(enabled) state.enabled = (enabled == true) end,
    
    GetWindow = function() return state.win end,
    SetWindow = function(win) state.win = win end,
    
    GetPopup = function() return state.popup end,
    SetPopup = function(popup) state.popup = popup end,
    
    GetLastPopup = function() return state.lastPopup end,
    SetLastPopup = function(popup) state.lastPopup = popup end,
    
    GetTicker = function() return state.tick end,
    SetTicker = function(ticker) state.tick = ticker end,
    
    GetUses = function() return state.uses end,
    ClearUses = function() wipe(state.uses) end,
    
    -- État des événements
    GetActiveEventsRegistered = function() return state._activeEventsRegistered end,
    SetActiveEventsRegistered = function(registered) state._activeEventsRegistered = (registered == true) end,
}

-- Export vers le namespace global pour compatibilité
ns.GLOG.GroupTrackerState = ns.GroupTrackerState
