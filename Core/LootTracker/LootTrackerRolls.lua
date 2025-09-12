local ADDON, ns = ...

-- Module: LootTrackerRolls
-- Responsabilités: Système de jets de dés (Need/Greed/DE/Pass), cache des rolls, parsing des messages système
ns.LootTrackerRolls = ns.LootTrackerRolls or {}

-- === Détection des messages de roll & cache court (joueur|lien) ===
local function _Now() return (time and time()) or 0 end

local function _EscapeForLuaPattern(s)
    if not s then return "" end
    local str = tostring(s)
    if str == "" then return "" end
    
    -- Échapper tous les caractères spéciaux de motif Lua
    return str:gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
end

local function _GS2Pat(gs)
    if not gs or gs == "" then return nil end
    
    -- Protection contre les valeurs invalides
    local success, result = pcall(function()
        -- D'abord remplacer %s et %d AVANT d'échapper
        local p = tostring(gs)
        p = p:gsub("%%s", "PLACEHOLDER_S")    -- remplacer temporairement
        p = p:gsub("%%d", "PLACEHOLDER_D")    -- remplacer temporairement
        
        -- Puis échapper les caractères spéciaux
        p = _EscapeForLuaPattern(p)
        
        -- Puis remettre les captures
        p = p:gsub("PLACEHOLDER_S", "(.+)")   -- capture texte/lien
        p = p:gsub("PLACEHOLDER_D", "(%d+)")  -- capture entier
        return p
    end)
    
    if success then
        return result
    else
        -- En cas d'erreur, retourner nil pour désactiver ce motif
        return nil
    end
end

local function _NormPlayer(name)
    name = tostring(name or ""):gsub("%-.*$", ""):lower()
    return name
end

-- Cache: [link][playerLower] = { type="need|greed|disenchant|pass", val=98, ts=... }
local _rollByItem = {}
-- Winner cache: [linkKey] = { player = "name", type = "need|greed|disenchant|transmog|pass", val = number, ts = now }
local _winnerByItem = {}

-- Normalisation d'un lien d'objet pour la clé du cache.
-- Objectif: faire correspondre les messages de rolls (souvent lien complet) et
-- les messages de loot (lien complet aussi) mais prévoir le cas où un format tronqué
-- serait rencontré. On se base sur itemID + nom extrait.
local function _LinkKey(link)
    if not link or link == "" then return nil end
    -- Extraire itemID
    local itemID = link:match("|Hitem:(%d+):") or "?"
    -- Nom entre crochets
    local name = link:match("%[(.-)%]") or "?"
    name = name:lower()
    return itemID .. "::" .. name
end

local function _RememberRoll(player, link, rollType, rollVal)
    if not player or not link or not rollType then return end
    local pn = _NormPlayer(player)
    local key = _LinkKey(link)
    if not key then return end
    _rollByItem[key] = _rollByItem[key] or {}
    local rec = _rollByItem[key][pn] or {}
    rec.type = rollType or rec.type
    rec.val  = tonumber(rollVal or rec.val)
    rec.ts   = _Now()
    _rollByItem[key][pn] = rec

    -- petit nettoyage des entrées > 5 min
    local now = rec.ts
    for lnk, map in pairs(_rollByItem) do
        for p, r in pairs(map) do
            if (now - (r.ts or 0)) > 300 then map[p] = nil end
        end
        if not next(map) then _rollByItem[lnk] = nil end
    end
end

local function _GetRollFor(player, link)
    if not player or not link then return nil, nil end
    local pn = _NormPlayer(player)
    local key = _LinkKey(link)
    if not key then return nil, nil end
    local rec = _rollByItem[key] and _rollByItem[key][pn]
    if not rec then
        return nil, nil
    end
    return rec.type, rec.val
end

-- Returns true if we have any recorded rolls for this link (recent window)
local function _HasActiveRollSession(link)
    local key = _LinkKey(link)
    if not key then return false end
    local m = _rollByItem[key]
    if not m then return false end
    -- ensure at least one recent entry (< 5 min)
    local now = _Now()
    for _, r in pairs(m) do
        if (now - (r.ts or 0)) <= 300 then return true end
    end
    return false
end

-- Winner helpers
local function _SetWinner(link, player, rType, rVal)
    local key = _LinkKey(link)
    if not key or not player then return end
    _winnerByItem[key] = {
        player = player,
        type   = rType,
        val    = rVal and tonumber(rVal) or nil,
        ts     = _Now(),
    }
end

local function _GetWinner(link)
    local key = _LinkKey(link)
    if not key then return nil end
    local w = _winnerByItem[key]
    if not w then return nil end
    if (_Now() - (w.ts or 0)) > 600 then -- expire after 10 minutes
        _winnerByItem[key] = nil
        return nil
    end
    return w.player, w.type, w.val
end

-- Motifs localisés des messages de roll
local _PAT_NEED        = _GS2Pat(LOOT_ROLL_NEED)
local _PAT_GREED       = _GS2Pat(LOOT_ROLL_GREED)
local _PAT_DE          = _GS2Pat(LOOT_ROLL_DISENCHANT)
local _PAT_PASS        = _GS2Pat(LOOT_ROLL_PASSED)
local _PAT_PASS_AUTO   = _GS2Pat(LOOT_ROLL_PASSED_AUTO)
-- Dragonflight+ roll type: Transmog
local _PAT_TRANSMOG    = _GS2Pat((pcall(getglobal, "LOOT_ROLL_TRANSMOG") and getglobal("LOOT_ROLL_TRANSMOG")) or nil)

-- "X won: %s with a roll of %d for %s"
local _PAT_WON         = _GS2Pat(LOOT_ROLL_WON)
-- "You rolled %d (Need) for: %s" (pas de nom → on mappe sur player)
local _PAT_ROLLED_NEED = _GS2Pat(LOOT_ROLL_ROLLED_NEED)
local _PAT_ROLLED_GREED= _GS2Pat(LOOT_ROLL_ROLLED_GREED)
local _PAT_ROLLED_DE   = _GS2Pat(LOOT_ROLL_ROLLED_DE)
local _PAT_ROLLED_TRANSMOG = _GS2Pat((pcall(getglobal, "LOOT_ROLL_ROLLED_TRANSMOG") and getglobal("LOOT_ROLL_ROLLED_TRANSMOG")) or nil)

local function _ParseRollMessage(msg)
    if not msg or msg == "" then return nil end
    
    -- Fonction helper pour match sécurisé
    local function safeMatch(pattern, text)
        if not pattern or not text then return nil end
        local success, result1, result2, result3 = pcall(string.match, text, pattern)
        if success then
            return result1, result2, result3
        else
            return nil
        end
    end
    
    -- Sélections (contiennent toujours le joueur + lien)
    if _PAT_NEED then
        local who, link = safeMatch(_PAT_NEED, msg)
        if who and link then return who, link, "need", nil end
    end
    if _PAT_GREED then
        local who, link = safeMatch(_PAT_GREED, msg)
        if who and link then return who, link, "greed", nil end
    end
    if _PAT_DE then
        local who, link = safeMatch(_PAT_DE, msg)
        if who and link then return who, link, "disenchant", nil end
    end
    if _PAT_TRANSMOG then
        local who, link = safeMatch(_PAT_TRANSMOG, msg)
        if who and link then return who, link, "transmog", nil end
    end
    if _PAT_PASS then
        local who, link = safeMatch(_PAT_PASS, msg)
        if who and link then return who, link, "pass", nil end
    end
    if _PAT_PASS_AUTO then
        local who, link = safeMatch(_PAT_PASS_AUTO, msg)
        if who and link then return who, link, "pass", nil end
    end

    -- Gain (on récupère surtout la valeur de jet)
    if _PAT_WON then
        local who, link, val = safeMatch(_PAT_WON, msg)
        if who and link and val then return who, link, nil, tonumber(val) end
    end

    -- "You rolled %d ..." (on ne connaît pas le nom → self)
    local me = UnitName and UnitName("player")
    if me and _PAT_ROLLED_NEED then
        local val, link = safeMatch(_PAT_ROLLED_NEED, msg)
        if val and link then return me, link, "need", tonumber(val) end
    end
    if me and _PAT_ROLLED_GREED then
        local val, link = safeMatch(_PAT_ROLLED_GREED, msg)
        if val and link then return me, link, "greed", tonumber(val) end
    end
    if me and _PAT_ROLLED_DE then
        local val, link = safeMatch(_PAT_ROLLED_DE, msg)
        if val and link then return me, link, "disenchant", tonumber(val) end
    end
    if me and _PAT_ROLLED_TRANSMOG then
        local val, link = safeMatch(_PAT_ROLLED_TRANSMOG, msg)
        if val and link then return me, link, "transmog", tonumber(val) end
    end

    return nil
end

-- =========================
-- ===   API du module   ===
-- =========================
ns.LootTrackerRolls = {
    -- Cache des rolls
    RememberRoll = _RememberRoll,
    GetRollFor = _GetRollFor,
    NormalizeLink = _LinkKey,
    HasActiveRollSession = _HasActiveRollSession,
    GetWinner = _GetWinner,
    
    -- Parsing des messages de roll
    ParseRollMessage = _ParseRollMessage,
    
    -- Handler : messages système de jets (Need/Greed/DE/Pass/Won)
    HandleChatMsgSystem = function(message)
        local msg = tostring(message or "")
        if msg == "" then return end

        local who, link, rType, rVal = _ParseRollMessage(msg)
        if not who or not link then return end

        -- Si on ne reçoit que la valeur (ex: "X won ... roll of %d"), on tente de
        -- récupérer le type déjà mémorisé pour (joueur, lien) et on met à jour.
        if (not rType) and rVal then
            local prevType = _GetRollFor(who, link)
            if prevType then rType = prevType end
        end

        if rType then
            _RememberRoll(who, link, rType, rVal) -- met en cache 5 min
        end
        
        -- Si c'est un message de gain (won), notifier le système de loot
        -- pour qu'il marque cet objet comme réellement obtenu
        if rVal and _PAT_WON then
            local success, winner, winLink, winVal = pcall(string.match, msg, _PAT_WON)
            if success and winner and winLink and winVal then
                -- Enregistre le gagnant + type de jet si connu
                local prevType = rType
                if not prevType then
                    prevType = select(1, _GetRollFor(winner, winLink))
                end
                _SetWinner(winLink, winner, prevType, tonumber(winVal))
                -- Notifier que cet objet a été réellement gagné (signature: itemLink, playerName)
                if ns.LootTrackerParser and ns.LootTrackerParser.MarkAsWon then
                    ns.LootTrackerParser.MarkAsWon(winLink, winner)
                end
            end
        end
    end,
    
    -- Fonction de test pour simuler des rolls
    TestRolls = function()
        if not ns.LootTrackerRolls then return end
        
        print("=== Test LootTracker Rolls ===")
        
        -- D'abord, affichons les patterns réels
        print("Patterns WoW détectés:")
        if LOOT_ROLL_NEED then print("NEED:", LOOT_ROLL_NEED) end
        if LOOT_ROLL_GREED then print("GREED:", LOOT_ROLL_GREED) end
        if LOOT_ROLL_DISENCHANT then print("DE:", LOOT_ROLL_DISENCHANT) end
        if LOOT_ROLL_PASSED then print("PASS:", LOOT_ROLL_PASSED) end
        if LOOT_ROLL_WON then print("WON:", LOOT_ROLL_WON) end
        if LOOT_ROLL_ROLLED_NEED then print("ROLLED_NEED:", LOOT_ROLL_ROLLED_NEED) end
        
        -- Test avec les patterns réels (en utilisant les globales WoW)
        local testLink = "|cffa335ee|Hitem:193001::::::::70:577::13:4:8836:8840:8902:8806::::::|h[Plastron de test]|h|r"
        
        -- Générer des messages basés sur les patterns réels
        local testMessages = {}
        
        if LOOT_ROLL_NEED then
            -- Format: "%s a choisi Besoin pour : %s"
            local msg = LOOT_ROLL_NEED:gsub("%%s", "TestJoueur1", 1):gsub("%%s", testLink, 1)
            table.insert(testMessages, msg)
        end
        
        if LOOT_ROLL_GREED then
            local msg = LOOT_ROLL_GREED:gsub("%%s", "TestJoueur2", 1):gsub("%%s", testLink, 1)
            table.insert(testMessages, msg)
        end
        
        if LOOT_ROLL_DISENCHANT then
            local msg = LOOT_ROLL_DISENCHANT:gsub("%%s", "TestJoueur3", 1):gsub("%%s", testLink, 1)
            table.insert(testMessages, msg)
        end
        
        if LOOT_ROLL_WON then
            -- Format: "%s a gagné : %s avec un jet de %d"
            local msg = LOOT_ROLL_WON:gsub("%%s", "TestJoueur1", 1):gsub("%%s", testLink, 1):gsub("%%d", "95", 1)
            table.insert(testMessages, msg)
        end
        
        -- Tester chaque message
        for i, msg in ipairs(testMessages) do
            print("Test " .. i .. ": " .. msg)
            ns.LootTrackerRolls.HandleChatMsgSystem(msg)
        end
        
        print("=== Fin des tests ===")
        print("Vérifiez l'onglet Loots pour voir les résultats")
    end,
    
    -- Test avec vrais messages WoW
    TestRealMessages = function()
        print("=== Test Messages Réels WoW ===")
        
        -- Afficher d'abord les patterns réels de votre client
        print("=== Patterns WoW détectés ===")
        if LOOT_ROLL_NEED then print("NEED:", LOOT_ROLL_NEED) end
        if LOOT_ROLL_GREED then print("GREED:", LOOT_ROLL_GREED) end
        if LOOT_ROLL_DISENCHANT then print("DE:", LOOT_ROLL_DISENCHANT) end
        if LOOT_ROLL_PASSED then print("PASS:", LOOT_ROLL_PASSED) end
        if LOOT_ROLL_WON then print("WON:", LOOT_ROLL_WON) end
        if LOOT_ITEM then print("LOOT_ITEM:", LOOT_ITEM) end
        if LOOT_ITEM_SELF then print("LOOT_ITEM_SELF:", LOOT_ITEM_SELF) end
        
        local testLink = "|cffa335ee|Hitem:193001::::::::70:577::13:4:8836:8840:8902:8806::::::|h[Plastron de test]|h|r"
        
        -- Ajouter directement au cache pour contourner les patterns
        print("=== Ajout direct au cache ===")
        _RememberRoll("TestJoueur1", testLink, "NEED", 95)
        _RememberRoll("TestJoueur2", testLink, "GREED", 45)
        _RememberRoll("TestJoueur3", testLink, "DE", 23)
        _RememberRoll("TestJoueur4", testLink, "PASS", 0)
        
        -- Vérifier le cache
        if ns.LootTrackerRolls and ns.LootTrackerRolls.GetRollFor then
            local rType, rVal = ns.LootTrackerRolls.GetRollFor("TestJoueur1", testLink)
            print("Cache après ajout direct pour TestJoueur1: " .. (rType or "nil") .. " (" .. (rVal or "nil") .. ")")
        end
        
        -- Messages de loot pour déclencher l'enregistrement
        if ns.LootTrackerParser and ns.LootTrackerParser.HandleChatMsgLoot then
            -- Essayons différents formats de message de loot
            local lootMessages = {
                "TestJoueur1 reçoit le butin : " .. testLink,
                "TestJoueur1 obtient l'objet : " .. testLink,
            }
            
            -- Si LOOT_ITEM existe, utilisons le format exact
            if LOOT_ITEM then
                local exactMsg = LOOT_ITEM:gsub("%%s", "TestJoueur1", 1):gsub("%%s", testLink, 1)
                table.insert(lootMessages, exactMsg)
                print("Message LOOT_ITEM exact: " .. exactMsg)
            end
            
            for i, lootMsg in ipairs(lootMessages) do
                print("Test loot " .. i .. ": " .. lootMsg)
                ns.LootTrackerParser.HandleChatMsgLoot(lootMsg)
            end
        end
        
        print("=== Test terminé ===")
    end,
}
