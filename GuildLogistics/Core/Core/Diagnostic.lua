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
        print("✅ GuildLogisticsDB pointe vers GuildLogisticsDB_Char")
    else
        print("❌ GuildLogisticsDB ne pointe PAS vers GuildLogisticsDB_Char")
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

-- Fonction pour diagnostiquer la migration
function GLOG.TestMigration()
    print("=== TEST MIGRATION ===")
    
    local TARGET = "1.0.3"
    print("Version cible:", TARGET)
    
    if GuildLogisticsDB_Char and GuildLogisticsDB_Char.meta then
        local lm = GuildLogisticsDB_Char.meta.lastMigration
        print("Dernière migration:", lm or "AUCUNE")
        
        -- Test de comparaison de version
        local function cmp(a, b)
            local function parse(s)
                local out = {}
                for n in tostring(s or ""):gmatch("(%d+)") do out[#out+1] = tonumber(n) or 0 end
                return out
            end
            local A, B = parse(a), parse(b)
            local n = math.max(#A, #B)
            for i = 1, n do
                local x, y = A[i] or 0, B[i] or 0
                if x < y then return -1 elseif x > y then return 1 end
            end
            return 0
        end
        
        local needFlush = (not lm) or (cmp(lm, TARGET) < 0)
        print("Migration nécessaire:", needFlush and "OUI" or "NON")
        
        if lm then
            print("Comparaison", lm, "vs", TARGET, ":", cmp(lm, TARGET))
        end
    else
        print("❌ Pas de métadonnées de migration")
    end
    
    print("=== FIN TEST MIGRATION ===")
end

_G["GLMig"] = GLOG.TestMigration
