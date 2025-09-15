-- ===================================================
-- Core/Core/BackupManager.lua - Gestionnaire de backup/restore
-- ===================================================
-- Responsable du backup et restore complet de la base de données

local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
local GLOG = ns.GLOG

-- Références aux utilitaires centralisées
local U = ns.Util or {}

-- ===== Fonctions utilitaires =====

-- Copie profonde d'une table
local function deepCopy(original)
    if type(original) ~= "table" then
        return original
    end
    
    local copy = {}
    for k, v in pairs(original) do
        copy[k] = deepCopy(v)
    end
    return copy
end

-- Calcule la taille approximative d'une table
local function calculateSize(data)
    if type(data) ~= "table" then
        return 1
    end
    
    local count = 0
    for k, v in pairs(data) do
        count = count + 1 + calculateSize(v)
    end
    return count
end

-- =========================
-- ===== BACKUP =====
-- =========================

function GLOG.CreateDatabaseBackup()
    -- Vérification de l'existence de la base active (partagée par guilde)
    if not GuildLogisticsDB then
        return false, ns.Tr("err_no_main_db") or "Aucune base de données principale trouvée"
    end
    
    -- Créer une copie complète de la base de données active
    local backup = deepCopy(GuildLogisticsDB)
    
    -- Ajouter des métadonnées de backup
    backup._backupMeta = {
        timestamp = time(),
        date = date("%Y-%m-%d %H:%M:%S"),
    source = "GuildLogisticsDB",
        version = (GLOG.GetAddonVersion and GLOG.GetAddonVersion()) or "unknown",
        playerName = (UnitName and UnitName("player")) or "unknown",
        realm = (GetRealmName and GetRealmName()) or "unknown",
        size = calculateSize(backup)
    }
    
    -- Sauvegarder dans la variable globale de backup
    GuildLogisticsDB_Backup = backup
    
    local size = backup._backupMeta.size
    return true, string.format(
        ns.Tr("msg_backup_created") or "Backup créé avec succès (%d éléments)",
        size
    )
end

-- =========================
-- ===== RESTORE =====
-- =========================

function GLOG.RestoreDatabaseFromBackup()
    -- Vérification de l'existence du backup
    if not GuildLogisticsDB_Backup then
        return false, ns.Tr("err_no_backup") or "Aucun backup trouvé"
    end
    
    -- Vérification que le backup contient des données valides
    if type(GuildLogisticsDB_Backup) ~= "table" then
        return false, ns.Tr("err_invalid_backup") or "Backup invalide"
    end
    
    -- Capturer la révision actuelle pour préserver le versionning
    -- IMPORTANT: On capture au moment de la restauration pour éviter tout décalage temporel
    local currentRev = nil
    if GuildLogisticsDB and GuildLogisticsDB.meta and GuildLogisticsDB.meta.rev then
        currentRev = GuildLogisticsDB.meta.rev
    end
    
    -- Créer une copie du backup (sans les métadonnées de backup)
    local restored = deepCopy(GuildLogisticsDB_Backup)
    
    -- Supprimer les métadonnées de backup de la copie restaurée
    restored._backupMeta = nil
    
    -- Sauvegarder la base actuelle comme "previous" au cas où
    if GuildLogisticsDB then
        GuildLogisticsDB_Previous = deepCopy(GuildLogisticsDB)
        -- Stocker la révision actuelle dans les métadonnées de "previous" pour traçabilité
        if GuildLogisticsDB_Previous then
            GuildLogisticsDB_Previous._restoreMeta = {
                timestamp = time(),
                date = date("%Y-%m-%d %H:%M:%S"),
                revisionAtRestore = currentRev,
                restoredFromBackup = (GuildLogisticsDB_Backup._backupMeta and GuildLogisticsDB_Backup._backupMeta.date) or "unknown"
            }
        end
    end
    
    -- Restaurer la base de données
    GuildLogisticsDB = restored
    
    -- Restaurer la révision actuelle pour ne pas perturber le versionning
    if currentRev then
        GuildLogisticsDB.meta = GuildLogisticsDB.meta or {}
        GuildLogisticsDB.meta.rev = currentRev
    end
    
    -- Aussi mettre à jour l'alias global si il existe
    -- Rebind de l'alias global déjà effectué ci-dessus
    
    -- Forcer le rechargement des modules qui dépendent de la DB
    if GLOG.EnsureDB then GLOG.EnsureDB() end
    
    -- Informer les autres modules du changement
    if ns.Emit then
        ns.Emit("database:restored")
    end
    
    -- Rafraîchir l'interface
    if ns.RefreshAll then
        ns.RefreshAll()
    end
    
    -- Si c'est un GM, forcer une synchronisation complète (comme "Forcer ma version (GM)")
    if GLOG.IsMaster and GLOG.IsMaster() then
        if GLOG._SnapshotExport and GLOG.Comm_Broadcast and GLOG.IncRev then
            local newrv = GLOG.IncRev()
            local snap = GLOG._SnapshotExport()
            if newrv then snap.rv = newrv end
            GLOG.Comm_Broadcast("SYNC_FULL", snap)
            
            -- Optionnel : informer l'utilisateur
            if ns.UI and ns.UI.Toast then
                ns.UI.Toast("Synchronisation complète lancée après restauration")
            end
        end
    end
    
    local meta = GuildLogisticsDB_Backup._backupMeta
    local backupDate = (meta and meta.date) or ns.Tr("unknown_date") or "date inconnue"
    
    return true, string.format(
        ns.Tr("msg_backup_restored") or "Base de données restaurée depuis le backup du %s. Synchronisation forcée.",
        backupDate
    )
end

-- =========================
-- ===== INFO BACKUP =====
-- =========================

function GLOG.GetBackupInfo()
    if not GuildLogisticsDB_Backup then
        return nil
    end
    
    local meta = GuildLogisticsDB_Backup._backupMeta
    if not meta then
        return {
            exists = true,
            size = calculateSize(GuildLogisticsDB_Backup),
            date = ns.Tr("unknown_date") or "Date inconnue",
            isValid = true
        }
    end
    
    return {
        exists = true,
        timestamp = meta.timestamp,
        date = meta.date,
        source = meta.source,
        version = meta.version,
        playerName = meta.playerName,
        realm = meta.realm,
        size = meta.size,
        isValid = true
    }
end

function GLOG.HasValidBackup()
    return GuildLogisticsDB_Backup and type(GuildLogisticsDB_Backup) == "table"
end

-- =========================
-- ===== CLEANUP =====
-- =========================

function GLOG.DeleteBackup()
    if not GuildLogisticsDB_Backup then
        return false, ns.Tr("err_no_backup") or "Aucun backup trouvé"
    end
    
    GuildLogisticsDB_Backup = nil
    
    return true, ns.Tr("msg_backup_deleted") or "Backup supprimé"
end

-- =========================
-- ===== DIAGNOSTIC =====
-- =========================

function GLOG.GetDatabaseSizes()
    local sizes = {}
    
    if GuildLogisticsDB then
        sizes.main = calculateSize(GuildLogisticsDB)
    end
    
    if GuildLogisticsDB_Backup then
        sizes.backup = calculateSize(GuildLogisticsDB_Backup)
    end
    
    if GuildLogisticsDB_Previous then
        sizes.previous = calculateSize(GuildLogisticsDB_Previous)
    end
    
    return sizes
end

-- =========================
-- ===== COMPATIBILITY =====
-- =========================

-- Alias pour compatibilité
GLOG.BackupDatabase = GLOG.CreateDatabaseBackup
GLOG.RestoreDatabase = GLOG.RestoreDatabaseFromBackup
