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
        db.requests = db.requests or {}

        -- Journal d'erreurs (côté GM)
        db.errors   = db.errors   or { list = {}, nextId = 1 }
        -- pas de errOutbox ici : on réutilise GuildLogisticsDB.pending (Comm)
    end

    -- La version d'addon est stockée dans mainAlt.shared[uid].addonVersion

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
end

-- Fonction de nettoyage (utilisée par Core.lua)
local function WipeDataStructures()
    local isMaster = (GLOG.IsMaster and GLOG.IsMaster()) or false
    local oldRev     = (GuildLogisticsDB_Char and GuildLogisticsDB_Char.meta and GuildLogisticsDB_Char.meta.rev) or 0
    local keepRev    = isMaster and oldRev or 0
    local keepMaster = (GuildLogisticsDB_Char and GuildLogisticsDB_Char.meta and GuildLogisticsDB_Char.meta.master) or nil

    GuildLogisticsDB_Char = {
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
    WipeDataStructures()
    if ns.Emit then ns.Emit("database:wiped") end
    if ns.RefreshAll then ns.RefreshAll() end
end

function GLOG.WipeAllSaved()
    WipeAllStructures()
    if ns.Emit then ns.Emit("database:wiped") end
    if ns.RefreshAll then ns.RefreshAll() end
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
