-- ===================================================
-- Core/Core/DatabaseManager.lua - Gestionnaire de base de données
-- ===================================================
-- Responsable de l'initialisation et gestion des structures de données

local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
local GLOG = ns.GLOG

-- Références aux utilitaires centralisées
local U = ns.Util or {}

-- =========================
-- ======  DATABASE   ======
-- =========================

local function _InitSchema(db)
    db.players  = db.players  or {}
    db.history  = db.history  or { nextId = 1 }
    db.expenses = db.expenses or { recording = false, list = {}, nextId = 1 }
    db.lots     = db.lots     or { nextId = 1, list = {} }
    db.meta     = db.meta     or { lastModified = 0, fullStamp = 0, rev = 0, master = nil }
    if db.meta.lastMigration == nil then db.meta.lastMigration = tostring((ns and ns.GLOG and ns.GLOG.GetAddonVersion and ns.GLOG.GetAddonVersion()) or "") end
    db.requests = db.requests or {}
    if not db.account then db.account = { mains = {}, altToMain = {} } end
    db.account.mains     = db.account.mains     or {}
    db.account.altToMain = db.account.altToMain or {}
    db.errors   = db.errors   or { list = {}, nextId = 1 }
end

local function _getCurrentGuildKey()
    -- Returns a stable key for the player's current guild, or "__noguild__" if not in a guild
    local gname = (GetGuildInfo and GetGuildInfo("player")) or nil
    if not gname or gname == "" then return "__noguild__" end
    -- Normalize: strip spaces/apostrophes, lowercase
    gname = tostring(gname):gsub("%s+",""):gsub("'",""):lower()
    return gname
end

-- Returns the active bucket key depending on current mode and guild membership
local function _getActiveGuildBucketKey()
    local base = _getCurrentGuildKey()
    if base == "__noguild__" then return base end
    local mode = (GLOG and GLOG.GetMode and GLOG.GetMode()) or nil
    if mode == "standalone" then
        return "standalone_" .. tostring(base)
    else
        return base
    end
end

-- Expose helper for debugging/QA
GLOG.GetActiveGuildBucketKey = GLOG.GetActiveGuildBucketKey or _getActiveGuildBucketKey

local function EnsureDB()
    -- Re-entrancy / long-frame safeguard
    if GLOG._ensureDBRunning then return end
    GLOG._ensureDBRunning = true
    local _startT = debugprofilestop and debugprofilestop() or nil
    -- Legacy version-gated wipe (pre-4.0.0): now marker-only to avoid destroying data before shared migration
    do
        local cur = (ns and ns.GLOG and ns.GLOG.GetAddonVersion and ns.GLOG.GetAddonVersion()) or (ns and ns.Version) or ""
        local cmp = ns and ns.Util and ns.Util.CompareVersions
        if type(cur) == "string" and cur ~= "" and type(cmp) == "function" then
            -- Read last migration marker from DB_Char.meta.lastMigration (string)
            local lastMig = nil
            if type(_G.GuildLogisticsDB_Char) == "table" and type(_G.GuildLogisticsDB_Char.meta) == "table" then
                lastMig = tostring(_G.GuildLogisticsDB_Char.meta.lastMigration or "")
            end

            local needsWipe = (cmp(cur, "4.0.0") >= 0) and (not lastMig or cmp(lastMig, "4.0.0") < 0)
            if needsWipe then
                -- Do NOT wipe here anymore. Just tag the legacy store; the real migration happens below.
                _G.GuildLogisticsDB_Char = _G.GuildLogisticsDB_Char or {}
                _G.GuildLogisticsDB_Char.meta = _G.GuildLogisticsDB_Char.meta or { lastModified=0, fullStamp=0, rev=0, master=nil }
                _G.GuildLogisticsDB_Char.meta.lastMigration = "4.0.0"
            end
        end
    end

    GuildLogisticsDB_Char = GuildLogisticsDB_Char or {}
    GuildLogisticsStandalone_Char = GuildLogisticsStandalone_Char or nil -- legacy (will migrate)
    GuildLogisticsUI_Char = GuildLogisticsUI_Char or {}
    GuildLogisticsShared = GuildLogisticsShared or { guilds = {} }
    GuildLogisticsShared.guilds = GuildLogisticsShared.guilds or {}

    -- Resolve base and active buckets (do not init schema before migration)
    local baseKey   = _getCurrentGuildKey()
    local activeKey = _getActiveGuildBucketKey() -- defaults to base (guild) if mode is unset
    -- Base bucket reference (do NOT create yet to avoid blank structure on first run)
    local baseBucket = GuildLogisticsShared.guilds[baseKey]

    -- MIGRATION: assume 'guild' as default for legacy (pre-standalone) and migrate immediately without pre-creating blank base
    local wipedLegacyChar = false
    local wipedLegacyStandalone = false
    do
        local function _isPristine(bucket)
            return type(bucket) == "table"
                and (bucket.players == nil) and (bucket.history == nil)
                and (bucket.lots == nil) and (bucket.account == nil)
        end
        local function _hasContent(t)
            if type(t) ~= "table" then return false end
            for _ in pairs(t) do return true end
            return false
        end
        local function _mergeIntoByKey(targetKey, src, label)
            if type(src) ~= "table" then return false end
            local dest = GuildLogisticsShared.guilds[targetKey]
            if dest and not _isPristine(dest) then return false end
            if not dest then dest = {}; GuildLogisticsShared.guilds[targetKey] = dest end
            dest.players  = src.players  or {}
            dest.history  = src.history  or { nextId = 1 }
            dest.expenses = src.expenses or { recording = false, list = {}, nextId = 1 }
            dest.lots     = src.lots     or { nextId = 1, list = {} }
            dest.meta     = src.meta     or { lastModified = 0, fullStamp = 0, rev = 0, master = nil }
            dest.requests = src.requests or {}
            dest.account  = src.account  or { mains = {}, altToMain = {} }
            dest.errors   = src.errors   or { list = {}, nextId = 1 }
            dest.meta.lastModified = time and time() or (dest.meta.lastModified or 0)
            if GLOG and GLOG.pushLog then
                GLOG.pushLog("info", "db:migration", "Migrated legacy store", { source = label, targetKey = targetKey })
            end
            return true
        end

        -- Targets: baseKey (guild) and standalone_{guild}
        local standaloneKey = (baseKey ~= "__noguild__") and ("standalone_" .. tostring(baseKey)) or baseKey
        local migratedDB = false
        local migratedSO = false

        if _hasContent(GuildLogisticsDB_Char) then
            migratedDB = _mergeIntoByKey(baseKey, GuildLogisticsDB_Char, "DB_Char")
            -- refresh local ref if created now
            baseBucket = GuildLogisticsShared.guilds[baseKey]
        end
        if _hasContent(GuildLogisticsStandalone_Char) then
            migratedSO = _mergeIntoByKey(standaloneKey, GuildLogisticsStandalone_Char, "Standalone_Char")
        end

        -- Wipe legacy stores ONLY if they existed (table) and (migrated or empty)
        local ver = (ns and ns.GLOG and ns.GLOG.GetAddonVersion and ns.GLOG.GetAddonVersion()) or "4.0.0"
        if type(GuildLogisticsDB_Char) == "table" and (migratedDB or not _hasContent(GuildLogisticsDB_Char)) then
            GuildLogisticsDB_Char = { meta = { lastMigration = tostring(ver), lastModified = time and time() or 0, fullStamp = 0, rev = 0, master = nil } }
            wipedLegacyChar = true
        end
        if type(GuildLogisticsStandalone_Char) == "table" and (migratedSO or not _hasContent(GuildLogisticsStandalone_Char)) then
            GuildLogisticsStandalone_Char = { meta = { lastMigration = tostring(ver), lastModified = time and time() or 0, fullStamp = 0, rev = 0, master = nil } }
            wipedLegacyStandalone = true
        end
    end

    -- If base bucket exists (due to migration), fill any missing parts after migration
    if baseBucket then _InitSchema(baseBucket) end

    -- Active bucket (guild or standalone_guild or __noguild__)
    local bucket = GuildLogisticsShared.guilds[activeKey]
    if not bucket then bucket = {}; GuildLogisticsShared.guilds[activeKey] = bucket end
    _InitSchema(bucket)

    -- Bind runtime aliases to ACTIVE SHARED BUCKET (account-wide per-guild store)
    local active = bucket

    -- Bind runtime aliases
    GuildLogisticsDB = active
    GuildLogisticsUI = GuildLogisticsUI_Char

    -- Lightweight helpers for potentially heavy cleanups (can be deferred if init runs long)
    local function _migr_drop_medal()
        active.meta = active.meta or {}
        local migKey = "migr:drop_mplus_medal"
        if active.meta[migKey] then return end
        local removed = 0
        if type(active.players) == "table" then
            for _, p in pairs(active.players) do
                local maps = p and p.mplusMaps
                if type(maps) == "table" then
                    for _, s in pairs(maps) do
                        if type(s) == "table" and s.medal ~= nil then
                            s.medal = nil
                            removed = removed + 1
                        end
                    end
                end
            end
        end
        active.meta[migKey] = time and time() or true
        if removed > 0 and GLOG and GLOG.pushLog then
            GLOG.pushLog("info", "db:migration", "Dropped legacy medal fields", { count = removed })
        end
    end

    -- One-time migration: key mplusMaps by mapID instead of map name
    do
        active.meta = active.meta or {}
        local migKey = "migr:mplus_maps_key_to_id"
        if not active.meta[migKey] then
            local converted = 0
            if type(active.players) == "table" then
                for _, p in pairs(active.players) do
                    local maps = p and p.mplusMaps
                    if type(maps) == "table" then
                        local needs = false
                        for k, _ in pairs(maps) do
                            if type(k) ~= "number" then needs = true; break end
                        end
                        if needs then
                            local out = {}
                            for k, v in pairs(maps) do
                                local entry = (type(v) == "table") and v or {}
                                local mid = tonumber(entry.mapID or 0) or 0
                                if mid == 0 then
                                    -- Try to resolve from key string if possible
                                    if type(k) == "number" then mid = k
                                    elseif type(k) == "string" then
                                        -- No robust reverse lookup by name here; keep as 0 which will be dropped
                                        mid = tonumber(entry.mapChallengeModeID or 0) or 0
                                    end
                                end
                                if mid and mid > 0 then
                                    local prev = out[mid]
                                    if prev then
                                        -- Merge: keep the better (higher score, then best level)
                                        local sc1 = tonumber(prev.score or 0) or 0
                                        local sc2 = tonumber(entry.score or 0) or 0
                                        if sc2 > sc1 or (sc2 == sc1 and (entry.best or 0) > (prev.best or 0)) then
                                            out[mid] = entry
                                        end
                                    else
                                        out[mid] = entry
                                    end
                                end
                            end
                            -- Replace only if we produced some numeric keys
                            if next(out) ~= nil then p.mplusMaps = out; converted = converted + 1 end
                        end
                    end
                end
            end
            active.meta[migKey] = time and time() or true
            if converted > 0 and GLOG and GLOG.pushLog then
                GLOG.pushLog("info", "db:migration", "Converted mplusMaps to ID keys", { players = converted })
            end
        end
    end

    local function _migr_drop_inner_mapid()
        active.meta = active.meta or {}
        local migKey = "migr:drop_mplus_inner_mapid"
        if active.meta[migKey] then return end
        local dropped = 0
        if type(active.players) == "table" then
            for _, p in pairs(active.players) do
                local maps = p and p.mplusMaps
                if type(maps) == "table" then
                    for _, s in pairs(maps) do
                        if type(s) == "table" and s.mapID ~= nil then
                            s.mapID = nil
                            dropped = dropped + 1
                        end
                    end
                end
            end
        end
        active.meta[migKey] = time and time() or true
        if dropped > 0 and GLOG and GLOG.pushLog then
            GLOG.pushLog("info", "db:migration", "Dropped inner mapID fields from mplusMaps", { count = dropped })
        end
    end

    -- One-time data hygiene: remove legacy overall Mythic+ fields (mplusOverall/mplusOverallTS)
    do
        active.meta = active.meta or {}
        local migKey = "migr:drop_mplus_overall_fields_v1"
        if not active.meta[migKey] then
            local removed = 0
            if type(active.players) == "table" then
                for _, p in pairs(active.players) do
                    if type(p) == "table" then
                        if p.mplusOverall ~= nil then p.mplusOverall = nil; removed = removed + 1 end
                        if p.mplusOverallTS ~= nil then p.mplusOverallTS = nil; removed = removed + 1 end
                    end
                end
            end
            active.meta[migKey] = time and time() or true
            if removed > 0 and GLOG and GLOG.pushLog then
                GLOG.pushLog("info", "db:migration", "Dropped legacy mplusOverall fields", { count = removed })
            end
        end
    end

    local function _migr_drop_runs()
        active.meta = active.meta or {}
        local migKey = "migr:drop_mplus_runs_v1"
        if active.meta[migKey] then return end
        local removed = 0
        if type(active.players) == "table" then
            for _, p in pairs(active.players) do
                local maps = p and p.mplusMaps
                if type(maps) == "table" then
                    for _, s in pairs(maps) do
                        if type(s) == "table" and s.runs ~= nil then
                            s.runs = nil
                            removed = removed + 1
                        end
                    end
                end
            end
        end
        active.meta[migKey] = time and time() or true
        if removed > 0 and GLOG and GLOG.pushLog then
            GLOG.pushLog("info", "db:migration", "Dropped deprecated 'runs' from mplusMaps", { count = removed })
        end
    end

    -- Decide whether to defer heavy cleanups based on elapsed time to avoid long frames
    local _elapsedMs = (_startT and debugprofilestop) and (debugprofilestop() - _startT) or 0
    local _shouldDefer = _elapsedMs and (_elapsedMs > 20) -- if EnsureDB already used >20ms, defer the remaining heavy loops
    if _shouldDefer and U and U.After then
        -- Stagger across frames to spread the cost
        U.After(0.00, _migr_drop_inner_mapid)
        U.After(0.05, _migr_drop_medal)
        U.After(0.10, _migr_drop_runs)
    else
        -- Run immediately if we're still within budget
        _migr_drop_inner_mapid()
        _migr_drop_medal()
        _migr_drop_runs()
    end

    -- Initialize schemas (legacy stores kept for compatibility, but no longer used at runtime)
    if not wipedLegacyChar then _InitSchema(GuildLogisticsDB_Char) end -- keep initialized for potential future reads when not wiped
    if GuildLogisticsStandalone_Char and not wipedLegacyStandalone then _InitSchema(GuildLogisticsStandalone_Char) end

    -- Initialisation UI avec sauvegarde des valeurs existantes (base par personnage)
    do
        local ui = GuildLogisticsUI_Char
        ui.point    = ui.point    or "CENTER"
        ui.relTo    = ui.relTo    or nil
        ui.relPoint = ui.relPoint or "CENTER"
        ui.x        = ui.x        or 0
        ui.y        = ui.y        or 0
        ui.width    = ui.width    or 1160
        ui.height   = ui.height   or 680
        
        -- Minimap
        ui.minimap         = ui.minimap         or {}
        ui.minimap.hide    = ui.minimap.hide    or false
        ui.minimap.angle   = ui.minimap.angle   or 215
        
        -- Options par défaut
        if ui.debugEnabled == nil then ui.debugEnabled = true end
        if ui.autoOpen     == nil then ui.autoOpen     = true end
    end

    -- Note: no runtime migrations here; data model now natively stores UID participants

    -- Basic instrumentation (debug only) to detect unusually long init
    if _startT and (GLOG and GLOG.IsDebugEnabled and GLOG.IsDebugEnabled()) and debugprofilestop then
        local dt = (debugprofilestop() - _startT)
        if dt > 50 then -- >50ms considered heavy
            if GLOG.pushLog then
                GLOG.pushLog("warn", "db:init:slow", "EnsureDB took long", { ms = dt })
            elseif print then
                print("[GLOG] EnsureDB slow init:", dt, "ms")
            end
        end
    end
    GLOG._ensureDBRunning = nil
end

-- Fonction de nettoyage (utilisée par Core.lua)
local function WipeDataStructures()
    local isMaster = (GLOG.IsMaster and GLOG.IsMaster()) or false
    -- Target the current ACTIVE shared per-guild bucket (mode-aware)
    local guildKey = _getActiveGuildBucketKey()
    GuildLogisticsShared = GuildLogisticsShared or { guilds = {} }
    GuildLogisticsShared.guilds = GuildLogisticsShared.guilds or {}
    local dbActive = GuildLogisticsShared.guilds[guildKey]
    local oldRev     = (dbActive and dbActive.meta and dbActive.meta.rev) or 0
    local keepRev    = isMaster and oldRev or 0
    local keepMaster = (dbActive and dbActive.meta and dbActive.meta.master) or nil

    local fresh = {
        account       = {},
        players       = {},
        history       = { nextId = 1 },
        expenses      = { recording = false, list = {}, nextId = 1 },
        lots          = { nextId = 1, list = {} },
        meta          = { lastModified=0, fullStamp=0, rev=keepRev, master=keepMaster },
        requests      = {},
    }
    -- Replace the guild bucket content
    GuildLogisticsShared.guilds[guildKey] = fresh
    GuildLogisticsDB = GuildLogisticsShared.guilds[guildKey]
end

-- Purge complète : DB + préférences UI
local function WipeAllStructures()
    local isMaster = (GLOG.IsMaster and GLOG.IsMaster()) or false
    local guildKey = _getActiveGuildBucketKey()
    GuildLogisticsShared = GuildLogisticsShared or { guilds = {} }
    GuildLogisticsShared.guilds = GuildLogisticsShared.guilds or {}
    local dbActive = GuildLogisticsShared.guilds[guildKey]
    local oldRev     = (dbActive and dbActive.meta and dbActive.meta.rev) or 0
    local keepRev    = isMaster and oldRev or 0
    local keepMaster = (dbActive and dbActive.meta and dbActive.meta.master) or nil

    local fresh = {
        account       = {},
        players       = {},
        history       = { nextId = 1 },
        expenses      = { recording = false, list = {}, nextId = 1 },
        lots          = { nextId = 1, list = {} },
        meta          = { lastModified=0, fullStamp=0, rev=keepRev, master=keepMaster },
        requests      = {},
    }
    GuildLogisticsShared.guilds[guildKey] = fresh
    GuildLogisticsDB = GuildLogisticsShared.guilds[guildKey]

    GuildLogisticsUI_Char = {
        point="CENTER", relTo=nil, relPoint="CENTER", x=0, y=0, width=1160, height=680,
        minimap = { hide=false, angle=215 },
        -- Par défaut : options pratiques
        debugEnabled = true, autoOpen = true,
    }

    -- Rebind UI alias
    GuildLogisticsUI = GuildLogisticsUI_Char

    -- Optionnel : nettoyer quelques caches mémoire visibles avant le ReloadUI
    GLOG._guildCache = {}
    GLOG._lastOwnIlvl, GLOG._lastOwnMPlusScore, GLOG._lastOwnMKeyId, GLOG._lastOwnMKeyLvl = nil, nil, nil, nil
end

-- ======= API PUBLIQUE =======

-- Expose l'initialisation DB comme API publique (et conserve l'alias legacy)
GLOG.EnsureDB = EnsureDB

function GLOG.IsDebugEnabled()
    return (GuildLogisticsUI and GuildLogisticsUI.debugEnabled) or false
end

function GLOG.WipeAllData()
    -- Évite ré-entrance pendant un wipe
    if GLOG._wipeInProgress then return end
    GLOG._wipeInProgress = true
    WipeDataStructures()
    if ns.Emit then ns.Emit("database:wiped") end
    -- Rafraîchit l'UI de façon asynchrone pour éviter un long blocage dans la même frame
    if ns.RefreshAll and ns.Util and ns.Util.After then
        ns.Util.After(0.01, function()
            pcall(ns.RefreshAll)
            GLOG._wipeInProgress = nil
        end)
    else
        if ns.RefreshAll then pcall(ns.RefreshAll) end
        GLOG._wipeInProgress = nil
    end
end

function GLOG.WipeAllSaved()
    if GLOG._wipeInProgress then return end
    GLOG._wipeInProgress = true
    WipeAllStructures()
    if ns.Emit then ns.Emit("database:wiped") end
    if ns.RefreshAll and ns.Util and ns.Util.After then
        ns.Util.After(0.01, function()
            pcall(ns.RefreshAll)
            GLOG._wipeInProgress = nil
        end)
    else
        if ns.RefreshAll then pcall(ns.RefreshAll) end
        GLOG._wipeInProgress = nil
    end
end

function GLOG.GetRev()
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.meta = GuildLogisticsDB.meta or {}
    return GuildLogisticsDB.meta.rev or 0
end

function GLOG.IncRev()
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.meta = GuildLogisticsDB.meta or {}
    GuildLogisticsDB.meta.rev = (GuildLogisticsDB.meta.rev or 0) + 1
    return GuildLogisticsDB.meta.rev
end

-- Incrémente / réinitialise la révision selon le rôle
function GLOG.BumpRevisionLocal()
    EnsureDB()
    local isMaster = (GLOG.CanModifyGuildData and GLOG.CanModifyGuildData()) or (GLOG.IsMaster and GLOG.IsMaster()) or false
    local rv = tonumber(GuildLogisticsDB.meta.rev or 0) or 0
    GuildLogisticsDB.meta.rev = isMaster and (rv + 1) or 0
    GuildLogisticsDB.meta.lastModified = time()
end

-- Expose les demandes pour l'UI (badge/onglet)
function GLOG.GetRequests()
    EnsureDB()
    GuildLogisticsDB.requests = GuildLogisticsDB.requests or {}
    return GuildLogisticsDB.requests
end

-- =========================
-- ======  MIGRATION  ======
-- =========================
-- Base62 ShortId helper (0-9, A-Z, a-z) – 4 chars
-- NOTE: 62^4 ≈ 14,776,336 combinaisons → suffisant pour un environnement guilde
local _SID_CHARS  = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
local _SID_WIDTH  = 4
local function _powi(a,b) local r=1; for _=1,b do r=r*a end; return r end
local _SID_MOD    = _powi(#_SID_CHARS, _SID_WIDTH) -- 62^4

local function _toBaseChars(n, chars, width)
    local base = #chars
    local z = chars:sub(1,1)
    if n == 0 then return z:rep(width or 1) end
    local t = {}
    while n > 0 do
        local r = n % base
        t[#t+1] = chars:sub(r+1, r+1)
        n = math.floor(n / base)
    end
    local s = table.concat(t):reverse()
    if width and #s < width then s = z:rep(width - #s) .. s end
    return s
end

-- DJB2 borné 53 bits (sûr en nombres Lua)
local function _hash53_djb2(s)
    local MOD = 9007199254740991 -- 2^53 - 1
    local h = 5381
    for i = 1, #s do
        h = (h * 33 + string.byte(s, i)) % MOD
    end
    return h
end

local function _normalizeFullName(name)
    local nf = (ns and ns.Util and ns.Util.NormalizeFull) and ns.Util.NormalizeFull or tostring
    return (nf(name or ""):gsub("%s+", ""))
end

local function _shortId(name)
    local norm = _normalizeFullName(name)
    local h = _hash53_djb2(norm)
    local n = h % _SID_MOD
    return _toBaseChars(n, _SID_CHARS, _SID_WIDTH)
end

-- Expose l'API si non définie
GLOG.ShortId = GLOG.ShortId or _shortId