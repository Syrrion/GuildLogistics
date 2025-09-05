-- ===================================================
-- Test simple pour BackupManager.lua
-- ===================================================
-- Ce fichier peut être utilisé pour tester les fonctions de backup/restore

local ADDON, ns = ...
local GLOG = ns.GLOG or {}

-- Test rapide de la fonctionnalité
local function testBackupFunctionality()
    print("=== Test BackupManager ===")
    
    -- Vérifier que les fonctions existent
    local functions = {
        "CreateDatabaseBackup",
        "RestoreDatabaseFromBackup", 
        "GetBackupInfo",
        "HasValidBackup",
        "DeleteBackup",
        "GetDatabaseSizes"
    }
    
    for _, funcName in ipairs(functions) do
        if GLOG[funcName] then
            print("✅ " .. funcName .. " existe")
        else
            print("❌ " .. funcName .. " manquante")
        end
    end
    
    -- Test info backup
    if GLOG.GetBackupInfo then
        local info = GLOG.GetBackupInfo()
        if info then
            print("📦 Backup trouvé:")
            print("   Date: " .. (info.date or "inconnue"))
            print("   Taille: " .. (info.size or 0) .. " éléments")
        else
            print("📦 Aucun backup existant")
        end
    end
    
    -- Test taille des bases
    if GLOG.GetDatabaseSizes then
        local sizes = GLOG.GetDatabaseSizes()
        print("📊 Tailles des bases:")
        if sizes.main then print("   Principale: " .. sizes.main .. " éléments") end
        if sizes.backup then print("   Backup: " .. sizes.backup .. " éléments") end
        if sizes.previous then print("   Précédente: " .. sizes.previous .. " éléments") end
    end
    
    print("=== Fin du test ===")
end

-- Fonction accessible globalement pour les tests manuels
GLOG_TestBackup = testBackupFunctionality

-- Auto-test après chargement (optionnel)
-- testBackupFunctionality()
