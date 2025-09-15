-- ===================================================
-- Diagnostic.lua - Outils de diagnostic du refactoring
-- ===================================================

local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
local GLOG = ns.GLOG

-- Fonction de diagnostic complète
function GLOG.Diagnostic()
    print("=== DIAGNOSTIC GUILD LOGISTICS ===")
    
    -- 1. Vérifier les variables globales
    print("1. Variables globales :")
    print("   GuildLogisticsDB:", type(GuildLogisticsDB))
    print("   GuildLogisticsDB_Char:", type(GuildLogisticsDB_Char))
    print("   GuildLogisticsUI:", type(GuildLogisticsUI))
    print("   GuildLogisticsUI_Char:", type(GuildLogisticsUI_Char))
    
    -- 2. Vérifier la structure de la DB
    if GuildLogisticsDB then
        print("2. Structure GuildLogisticsDB :")
        print("   players:", type(GuildLogisticsDB.players), GuildLogisticsDB.players and "(" .. tostring(#GuildLogisticsDB.players) .. " entrées)" or "")
        print("   history:", type(GuildLogisticsDB.history))
        print("   meta:", type(GuildLogisticsDB.meta))
        
        if GuildLogisticsDB.players then
            local count = 0
            for _ in pairs(GuildLogisticsDB.players) do count = count + 1 end
            print("   Nombre total de joueurs:", count)
        end
    else
        print("2. ⚠️ GuildLogisticsDB est nil")
    end
    
    -- 3. Vérifier les modules
    print("3. Modules chargés :")
    print("   EnsureDB:", GLOG.EnsureDB and "✅" or "❌")
    print("   GetPlayersArray:", GLOG.GetPlayersArray and "✅" or "❌")
    print("   AddHistorySession:", GLOG.AddHistorySession and "✅" or "❌")
    print("   GetLots:", GLOG.GetLots and "✅" or "❌")
    
    -- 4. Test d'exécution
    print("4. Test d'exécution :")
    if GLOG.EnsureDB then
        GLOG.EnsureDB()
        print("   EnsureDB() exécuté")
    end
    
    if GLOG.GetPlayersArray then
        local players = GLOG.GetPlayersArray()
        print("   GetPlayersArray() retourne", #players, "joueurs")
        if #players > 0 then
            print("   Premier joueur:", players[1].name, "solde:", players[1].solde)
        end
    end
    
    print("=== FIN DIAGNOSTIC ===")
end

-- Commande raccourcie
GLOG.Diag = GLOG.Diagnostic

-- Fonction accessible globalement pour le diagnostic
_G["GLDiagnostic"] = GLOG.Diagnostic
_G["GLDiag"] = GLOG.Diagnostic

-- Test rapide de la DB
function GLOG.TestDB()
    print("=== TEST RAPIDE DB ===")
    if GLOG.EnsureDB then
        GLOG.EnsureDB()
        print("EnsureDB() appelé")
    end
    
    print("GuildLogisticsDB type:", type(GuildLogisticsDB))
    print("GuildLogisticsDB_Char type:", type(GuildLogisticsDB_Char))
    
    -- Vérification des références
        if GuildLogisticsDB == GuildLogisticsDB_Char then
            print("ℹ️ Legacy alias still bound to per-character DB (unexpected)")
        else
            print("✅ GuildLogisticsDB pointe vers le bucket partagé actif (par guilde)")
        end
    
    local db = GuildLogisticsDB or {}
    local dbChar = GuildLogisticsDB_Char or {}
    
    print("players dans DB:", type(db.players))
    print("players dans DB_Char:", type(dbChar.players))
    
    if db.players then
        local count = 0
        for _ in pairs(db.players) do count = count + 1 end
        print("Nombre joueurs DB:", count)
    end
    
    if dbChar.players then
        local countChar = 0
        for _ in pairs(dbChar.players) do countChar = countChar + 1 end
        print("Nombre joueurs DB_Char:", countChar)
    end
    
    if GLOG.GetPlayersArray then
        local arr = GLOG.GetPlayersArray()
        print("GetPlayersArray() retourne:", #arr, "joueurs")
    end
    
    print("=== FIN TEST ===")
end

_G["GLTest"] = GLOG.TestDB

-- Migration diagnostic removed; no runtime migrations remain
