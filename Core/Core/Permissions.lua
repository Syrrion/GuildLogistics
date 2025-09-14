-- Centralized permissions and editor allowlist
-- Extends GM-only rights to: (1) all GM alts; (2) mains explicitly granted by GM (and thus their alts)

local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
local GLOG = ns.GLOG

local U = ns.Util or {}

-- Internal helpers
local function _ensure()
    if GLOG.EnsureDB then GLOG.EnsureDB() end
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.account = GuildLogisticsDB.account or { mains = {}, altToMain = {} }
    GuildLogisticsDB.account.mains     = GuildLogisticsDB.account.mains     or {}
    GuildLogisticsDB.account.altToMain = GuildLogisticsDB.account.altToMain or {}
    GuildLogisticsDB.account.editors   = GuildLogisticsDB.account.editors   or {}
end

local function _resolveUID(nameOrUID)
    if not nameOrUID or nameOrUID == "" then return nil end
    local s = tostring(nameOrUID)
    if s:find("%-") then
        -- Looks like a FullName-Realm
        return (GLOG.GetOrAssignUID and GLOG.GetOrAssignUID(s)) or nil
    end
    -- If the token is a known UID, keep it; otherwise try to resolve as name
    local byUID = (GLOG.GetNameByUID and GLOG.GetNameByUID(s)) or nil
    if byUID then return s end
    return (GLOG.GetOrAssignUID and GLOG.GetOrAssignUID(s)) or nil
end

local function _mainOf(uid)
    _ensure()
    local t = GuildLogisticsDB.account
    if not uid or uid == "" then return nil end
    local mu = t.altToMain and t.altToMain[uid]
    return tostring(mu or uid)
end

-- Cached GM cluster main UID, invalidated on roster or main/alt changes
local _gmMainUID, _gmCacheTS = nil, 0
local function _computeGMClusterMainUID()
    _ensure()
    local gmName = GLOG.GetGuildMasterCached and select(1, GLOG.GetGuildMasterCached()) or nil
    if not gmName or gmName == "" then return nil end
    -- Normalize name if utility exists
    local full = (GLOG.ResolveFullNameStrict and GLOG.ResolveFullNameStrict(gmName))
              or (U and U.CleanFullName and U.CleanFullName(gmName))
              or tostring(gmName)
    local uid = _resolveUID(full)
    if not uid then return nil end
    return _mainOf(uid)
end

local function _getGMMainUID()
    -- Basic time-based or event-based invalidation is handled by events below
    if not _gmMainUID or _gmMainUID == "" then
        _gmMainUID = _computeGMClusterMainUID()
        _gmCacheTS = (U and U.now and U.now()) or (time and time()) or 0
    end
    return _gmMainUID
end

-- Public: return true if the provided name/uid (or current player when nil) is authorized to modify guild data
function GLOG.CanModifyGuildData(nameOrUID)
    _ensure()
    -- Resolve candidate
    local candidate
    if not nameOrUID or nameOrUID == "" then
        local me = (U and U.playerFullName and U.playerFullName()) or (UnitName and UnitName("player")) or nil
        candidate = me
    else
        candidate = nameOrUID
    end
    local uid = _resolveUID(candidate)
    if not uid then return false end

    local mu = _mainOf(uid)
    if not mu or mu == "" then return false end

    -- Fast path: if checking current player (default call-site) and the API confirms GM (rank 0), allow immediately
    -- This avoids false negatives early on when the guild roster cache is not ready yet.
    do
        local me = (U and U.playerFullName and U.playerFullName()) or (UnitName and UnitName("player")) or nil
        if me and GLOG.GetOrAssignUID and GLOG.IsMaster and GLOG.IsMaster() then
            local myUID = GLOG.GetOrAssignUID(me)
            local myMain = _mainOf(myUID)
            if myMain and uid == myUID then
                return true
            end
        end
    end

    -- Rule 1: GM cluster (GM and all their alts)
    local gmMain = _getGMMainUID()
    if gmMain and mu == gmMain then return true end

    -- Rule 2: In explicit allowlist (main-level) granted by GM
    local editors = GuildLogisticsDB.account.editors or {}
    if editors[mu] then return true end

    return false
end

-- Public: who can grant/revoke editor rights? only GM cluster (GM and their alts)
function GLOG.CanGrantEditor(nameOrUID)
    -- Only the actual GM (rank 0) can grant/revoke rights
    return (GLOG.IsMaster and GLOG.IsMaster()) or false
end

-- Grant editor rights to a main (and thus all their alts). Accepts name or UID (any alt/main under that main).
function GLOG.GM_GrantEditor(nameOrUID)
    if not GLOG.CanGrantEditor() then return false end
    _ensure()
    local uid = _resolveUID(nameOrUID)
    if not uid then return false end
    local mu = _mainOf(uid)
    if not mu or mu == "" then return false end

    -- Do not store GM cluster itself (implicit); harmless if we do, but we can skip
    local gmMain = _getGMMainUID()
    if gmMain and mu == gmMain then
        if ns and ns.UI and ns.UI.Toast then
            local Tr = ns.Tr or function(s) return s end
            ns.UI.Toast({ title = Tr("Permissions"), text = Tr("GM already has full rights"), variant = "info", duration = 6 })
        end
        return true
    end

    local editors = GuildLogisticsDB.account.editors
    if not editors[mu] then
        editors[mu] = true
        if ns and ns.Emit then ns.Emit("editors:changed", "grant", mu) end
        -- Broadcast to guild: single grant event
        if GLOG.BroadcastEditorGrant then pcall(GLOG.BroadcastEditorGrant, mu) end
    end
    return true
end

function GLOG.GM_RevokeEditor(nameOrUID)
    if not GLOG.CanGrantEditor() then return false end
    _ensure()
    local uid = _resolveUID(nameOrUID)
    if not uid then return false end
    local mu = _mainOf(uid)
    if not mu or mu == "" then return false end

    local editors = GuildLogisticsDB.account.editors
    if editors[mu] then
        editors[mu] = nil
        if ns and ns.Emit then ns.Emit("editors:changed", "revoke", mu) end
        -- Broadcast to guild: single revoke event
        if GLOG.BroadcastEditorRevoke then pcall(GLOG.BroadcastEditorRevoke, mu) end
    end
    return true
end

function GLOG.GetEditors()
    _ensure()
    return GuildLogisticsDB.account.editors or {}
end

-- Alias for readability at call sites
GLOG.IsAuthorizedEditor = GLOG.CanModifyGuildData

-- Invalidate cached GM cluster on key signals
if ns and ns.Events and ns.Events.Register then
    ns.Events.Register("GUILD_ROSTER_UPDATE", GLOG, function()
        _gmMainUID, _gmCacheTS = nil, 0
    end)
    ns.Events.Register("PLAYER_GUILD_UPDATE", GLOG, function()
        _gmMainUID, _gmCacheTS = nil, 0
    end)
end
if GLOG and GLOG.On then
    GLOG.On("mainalt:changed", function()
        _gmMainUID, _gmCacheTS = nil, 0
    end)
    GLOG.On("gm:changed", function()
        _gmMainUID, _gmCacheTS = nil, 0
    end)
end

-- Optional: proactively share editors list on login if GM (accelerates convergence)
do
    local _edrSent = false
    local function _maybeBroadcastEditors()
        if _edrSent then return end
        if GLOG.CanGrantEditor and GLOG.CanGrantEditor() then
            _edrSent = true
            if GLOG.BroadcastEditorsFull then pcall(GLOG.BroadcastEditorsFull) end
        end
    end
    if ns and ns.Events and ns.Events.Register then
        ns.Events.Register("PLAYER_ENTERING_WORLD", GLOG, function()
            if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
                C_Timer.After(2.0, _maybeBroadcastEditors)
            else
                _maybeBroadcastEditors()
            end
        end)
    end
end
