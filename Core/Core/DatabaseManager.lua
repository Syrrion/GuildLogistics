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

local function EnsureDB()
    -- Version-gated migration: wipe DB when local addon version reaches >= 4.0.0 (one-time)
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
                -- Use public wipe API if available, else perform a minimal wipe inline
                GLOG.WipeAllData()
                _G.GuildLogisticsDB_Char = _G.GuildLogisticsDB_Char or {}
                _G.GuildLogisticsDB_Char.meta = _G.GuildLogisticsDB_Char.meta or { lastModified=0, fullStamp=0, rev=0, master=nil }
                _G.GuildLogisticsDB_Char.meta.rev = 0
                _G.GuildLogisticsDB_Char.meta.lastMigration = "4.0.0"
                -- Rebind runtime aliases
                _G.GuildLogisticsDB = _G.GuildLogisticsDB_Char
                -- Notify UI
                if ns and ns.Emit then ns.Emit("database:wiped", "migrate-4.0.0") end
            end
        end
    end

    GuildLogisticsDB_Char = GuildLogisticsDB_Char or {}
    GuildLogisticsUI_Char = GuildLogisticsUI_Char or {}

    -- Initialisation habituelle (base par personnage)
    -- Assigner GuildLogisticsDB à la base par personnage
    GuildLogisticsDB = GuildLogisticsDB_Char
    GuildLogisticsUI = GuildLogisticsUI_Char

    -- Initialisation des structures dans la base par personnage
    do
        local db = GuildLogisticsDB_Char
        db.players  = db.players  or {}
        db.history  = db.history  or { nextId = 1 }
        db.expenses = db.expenses or { recording = false, list = {}, nextId = 1 }
        db.lots     = db.lots     or { nextId = 1, list = {} }
        db.meta     = db.meta     or { lastModified = 0, fullStamp = 0, rev = 0, master = nil }
    -- Track lastMigration as version string (for one-time wipes)
    if db.meta.lastMigration == nil then db.meta.lastMigration = tostring((ns and ns.GLOG and ns.GLOG.GetAddonVersion and ns.GLOG.GetAddonVersion()) or "") end
        db.requests = db.requests or {}

        -- Stockage des liens main/alt et données par compte
        -- Nouveau modèle: toutes les données (alias, solde, reserve, addonVersion)
        -- résident dans db.account.mains[mainUID]
        if not db.account then
            db.account = { mains = {}, altToMain = {} }
        end
        db.account.mains     = db.account.mains     or {}
        db.account.altToMain = db.account.altToMain or {}

        -- Journal d'erreurs (côté GM)
        db.errors   = db.errors   or { list = {}, nextId = 1 }
        -- pas de errOutbox ici : on réutilise GuildLogisticsDB.pending (Comm)
    end

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
end

-- Fonction de nettoyage (utilisée par Core.lua)
local function WipeDataStructures()
    local isMaster = (GLOG.IsMaster and GLOG.IsMaster()) or false
    local oldRev     = (GuildLogisticsDB_Char and GuildLogisticsDB_Char.meta and GuildLogisticsDB_Char.meta.rev) or 0
    local keepRev    = isMaster and oldRev or 0
    local keepMaster = (GuildLogisticsDB_Char and GuildLogisticsDB_Char.meta and GuildLogisticsDB_Char.meta.master) or nil

    GuildLogisticsDB_Char = {
        account       = {},
        players       = {},
        history       = { nextId = 1 },
        expenses      = { recording = false, list = {}, nextId = 1 },
        lots          = { nextId = 1, list = {} },
        meta          = { lastModified=0, fullStamp=0, rev=keepRev, master=keepMaster },
        requests      = {},
    }

    -- Rebind des alias runtime
    GuildLogisticsDB = GuildLogisticsDB_Char
end

-- Purge complète : DB + préférences UI
local function WipeAllStructures()
    local isMaster = (GLOG.IsMaster and GLOG.IsMaster()) or false
    local oldRev     = (GuildLogisticsDB_Char and GuildLogisticsDB_Char.meta and GuildLogisticsDB_Char.meta.rev) or 0
    local keepRev    = isMaster and oldRev or 0
    local keepMaster = (GuildLogisticsDB_Char and GuildLogisticsDB_Char.meta and GuildLogisticsDB_Char.meta.master) or nil

    -- Purge les 2 SV par personnage
    GuildLogisticsDB_Char = {
        account       = {},
        players       = {},
        history       = { nextId = 1 },
        expenses      = { recording = false, list = {}, nextId = 1 },
        lots          = { nextId = 1, list = {} },
        meta          = { lastModified=0, fullStamp=0, rev=keepRev, master=keepMaster },
        requests      = {},
    }

    GuildLogisticsUI_Char = {
        point="CENTER", relTo=nil, relPoint="CENTER", x=0, y=0, width=1160, height=680,
        minimap = { hide=false, angle=215 },
        -- Par défaut : options pratiques
        debugEnabled = true, autoOpen = true,
    }

    -- Rebind des alias runtime pour la session courante
    GuildLogisticsDB = GuildLogisticsDB_Char
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
    local isMaster = (GLOG.IsMaster and GLOG.IsMaster()) or false
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