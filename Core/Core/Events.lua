local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
local GLOG = ns.GLOG

-- ===== Bus d'événements internes pour GuildLogistics =====
-- Structure : { [eventName] = { callback1, callback2, ... } }
GLOG.__evt = GLOG.__evt or {}

-- S'abonner à un événem-- ➕ Throttle + garde-fou : on ne refresh que si l'UI doit être rafraîchie
local _pendingUIRefresh = false
local function _ScheduleActiveTabRefresh()
    if _pendingUIRefresh then return end
    _pendingUIRefresh = true
    local function doRefresh()
        _pendingUIRefresh = false
        -- ⏸️ Pause globale : utilise le nouveau système centralisé de pause UI
        if ns and ns.UI and ns.UI.ShouldRefreshUI and ns.UI.ShouldRefreshUI() then
            if ns.RefreshAll then ns.RefreshAll() end
        end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.15, doRefresh) else doRefresh() end
end-- @param event: string - nom de l'événement (ex: "roster:updated", "expenses:changed")
-- @param callback: function - fonction appelée quand l'événement est émis
function GLOG.On(event, callback)
    if type(event) ~= "string" or type(callback) ~= "function" then 
        return false
    end
    
    local L = GLOG.__evt[event]
    if not L then 
        L = {}
        GLOG.__evt[event] = L 
    end
    
    table.insert(L, callback)
    return true
end

-- Se désabonner d'un événement interne
-- @param event: string - nom de l'événement
-- @param callback: function - callback exact à supprimer
function GLOG.Off(event, callback)
    local L = GLOG.__evt and GLOG.__evt[event]
    if not L then return end
    
    for i = #L, 1, -1 do
        if L[i] == callback then 
            table.remove(L, i)
        end
    end
    
    -- Nettoyer la liste si elle est vide
    if #L == 0 then
        GLOG.__evt[event] = nil
    end
end

-- Émettre un événement interne avec des paramètres
-- @param event: string - nom de l'événement
-- @param ...: any - paramètres passés aux callbacks
function GLOG.Emit(event, ...)
    local L = GLOG.__evt and GLOG.__evt[event]
    if not L then return end
    
    for i = 1, #L do
        local ok = pcall(L[i], ...)
        -- Ignorer les erreurs pour ne pas casser la chaîne de traitement
    end
end

-- Alias pour ns.Emit (compatibilité avec d'autres modules)
if ns then
    ns.Emit = GLOG.Emit
end

-- === Hub d'évènements : ns.Events (autosuffisant & safe) ===========
ns.Events = ns.Events or {}
local E = ns.Events

if not E._inited then
    E._inited   = true
    E._handlers = {}
    E._frame    = CreateFrame("Frame")
    E._frame:SetScript("OnEvent", function(_, event, ...)
        local list = E._handlers[event]
        if list then
            for i = 1, #list do
                local h = list[i]
                local ok, err = pcall(h.fn, h.owner, event, ...)
                if not ok then geterrorhandler()(err) end
            end
        end
        if ns.Emit then ns.Emit("evt:" .. event, ...) end
    end)
end

-- Enregistre un callback (owner optionnel)
function E.Register(event, owner, fn)
    if type(owner) == "function" and fn == nil then
        fn, owner = owner, nil
    end
    if type(event) ~= "string" or type(fn) ~= "function" then return end

    local list = E._handlers[event]
    if not list then
        list = {}
        E._handlers[event] = list
    end
    table.insert(list, { owner = owner, fn = fn })

    -- Inscription paresseuse & idempotente
    if E._frame and not E._frame:IsEventRegistered(event) then
        E._frame:RegisterEvent(event)
    end
end

-- Désinscription fine
function E.Unregister(event, owner, fn)
    local list = E._handlers[event]
    if not list then return end
    for i = #list, 1, -1 do
        local h = list[i]
        local okOwner = (owner == nil) or (h.owner == owner)
        local okFn    = (fn == nil)    or (h.fn    == fn)
        if okOwner and okFn then table.remove(list, i) end
    end
    if #list == 0 then
        E._handlers[event] = nil
        -- On ne désenregistre pas l'event du frame (inutile et source d'effets de bord)
    end
end

-- Désinscription globale par owner (one-shot pratique)
function E.UnregisterOwner(owner)
    if not owner then return end
    for _, list in pairs(E._handlers) do
        for i = #list, 1, -1 do
            if list[i].owner == owner then table.remove(list, i) end
        end
    end
end

-- === Session Event Logger (debug léger, mémoire session uniquement) ===
do
    local E = ns.Events
    if E and not E._loggerHooked then
        E._log        = {}
        E._logMax     = 1000
        E._logEnabled = false   -- ⬅️ pause par défaut (aucun log tant qu’on ne reprend pas)
        E._logRev     = E._logRev or 0
        E._logNewCnt  = 0
        E._lastRevTs  = 0
        E._maxArgs    = 6

        function E.GetDebugLog() return E._log end
        function E.ClearDebugLog()
            local log = E._log
            for i = #log, 1, -1 do log[i] = nil end
            E._logRev = (E._logRev or 0) + 1
        end
        function E.SetDebugLogging(on) E._logEnabled = (on ~= false) end
        function E.IsDebugLoggingEnabled() return E._logEnabled end

        -- Compteur de révision du log (augmente à chaque modification)
        E._logRev = E._logRev or 0
        function E.GetDebugLogRev() return E._logRev end

        -- Wrap du OnEvent du hub : on log puis on délègue à l’ancien handler
        local prev = E._frame and E._frame:GetScript("OnEvent")
        if not E._frame then E._frame = CreateFrame("Frame") end

        local function _startsWith(s, prefix)
            if type(s) ~= "string" or type(prefix) ~= "string" then return false end
            return string.sub(s, 1, #prefix) == prefix
        end

        local function _isDebugOptionOn()
            -- Option globale depuis l’onglet Réglages
            return (GuildLogisticsUI and GuildLogisticsUI.debugEnabled) == true
        end

        local function _shouldLog(event, ...)
            -- 0) Si le débug UI est désactivé → ne rien historiser
            if not _isDebugOptionOn() then
                return false
            end
            
            -- 1) Filtre CLEU à contenu vide
            if event == "COMBAT_LOG_EVENT_UNFILTERED" then
                if select("#", ...) == 0 then
                    return false
                end
            end

            -- 2) Filtre AddonMsg
            if event == "CHAT_MSG_ADDON" then
                local expected = (ns and ns.GLOG and ns.GLOG.PREFIX)
                local prefix, msg = ...
                -- Si le param 'prefix' ne matche pas et que le 'msg' ne commence pas par expected → ignorer
                if (prefix ~= expected) and (not _startsWith(msg, expected)) then
                    return false
                end
            end

            if event == "CVAR_UPDATE" then
                return false
            end

            return true
        end

        E._frame:SetScript("OnEvent", function(self, event, ...)
            if E._logEnabled and _shouldLog(event, ...) then
                local ts = (GetTimePreciseSec and GetTimePreciseSec())
                        or (GetTime and GetTime())
                        or (time and time()) or 0
                -- Copie bornée des args (max 6)
                local argsN = select("#", ...)
                local maxN  = E._maxArgs or 6
                local argsT = {}
                for i = 1, math.min(argsN, maxN) do
                    argsT[i] = select(i, ...)
                end

                local entry = { ts = ts, event = event, args = argsT }
                local log = E._log
                log[#log+1] = entry
                if #log > (E._logMax or 1000) then table.remove(log, 1) end

                -- Coalescing des révisions : au plus ~1/sec ou sur burst≥25
                E._logNewCnt = (E._logNewCnt or 0) + 1
                local now = (GetTimePreciseSec and GetTimePreciseSec()) or (GetTime and GetTime()) or (time and time()) or 0
                if (now - (E._lastRevTs or 0)) >= 0.75 or E._logNewCnt >= 25 then
                    E._logRev  = (E._logRev or 0) + 1
                    E._logNewCnt = 0
                    E._lastRevTs = now
                end
            end
            if type(prev) == "function" then return prev(self, event, ...) end
        end)

        E._loggerHooked = true
    end
end
-- ======================================================================

local f = CreateFrame("Frame")
f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("GUILD_ROSTER_UPDATE")
-- ➕ iLvl: mise à jour auto du main
f:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
f:RegisterEvent("PLAYER_AVG_ITEM_LEVEL_UPDATE")

-- ➕ Clé M+: recalcul/émission sur évènements pertinents
f:RegisterEvent("BAG_UPDATE_DELAYED")
-- ➕ plus robustes quand la clé est donnée par un PNJ / lootée
f:RegisterEvent("ITEM_PUSH")
f:RegisterEvent("GOSSIP_CLOSED")
-- ➕ utile quand on insère/enlève la clé dans le réceptacle
f:RegisterEvent("CHALLENGE_MODE_KEYSTONE_SLOTTED")

f:RegisterEvent("CHALLENGE_MODE_START")
f:RegisterEvent("CHALLENGE_MODE_COMPLETED")
f:RegisterEvent("CHALLENGE_MODE_RESET")


-- ➕ Throttle + garde-fou : on ne refresh que si l’UI est visible
local _pendingUIRefresh = false
local function _ScheduleActiveTabRefresh()
    if _pendingUIRefresh then return end
    _pendingUIRefresh = true
    local function doRefresh()
        _pendingUIRefresh = false
        if ns and ns.RefreshAll and ns.UI and ns.UI.Main and ns.UI.Main:IsShown() then
            ns.RefreshAll()
        end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0.15, doRefresh) else doRefresh() end
end

f:SetScript("OnEvent", function(self, event, name)
    if event == "ADDON_LOADED" then
        if name ~= ADDON then return end
        if GLOG.EnsureDB then GLOG.EnsureDB() end
        -- 🎯 Applique immédiatement l’échelle sauvegardée à toutes les frames protégées
        do
            local v = (GuildLogisticsUI and tonumber(GuildLogisticsUI.uiScale)) or nil
            if ns and ns.UI and ns.UI.Scale then
                if v then ns.UI.Scale.TARGET_EFF_SCALE = v end
                if ns.UI.Scale.ApplyAll then
                    -- petit délai 0 pour laisser finir les constructions de frames
                    if C_Timer and C_Timer.After then
                        C_Timer.After(0, function()
                            ns.UI.Scale.ApplyAll(v or ns.UI.Scale.TARGET_EFF_SCALE)
                            -- relayout des listviews pour purger tout jitter de scale
                            if ns.UI.ListView_RelayoutAll then ns.UI.ListView_RelayoutAll() end
                        end)
                    else
                        ns.UI.Scale.ApplyAll(v or ns.UI.Scale.TARGET_EFF_SCALE)
                        if ns.UI.ListView_RelayoutAll then ns.UI.ListView_RelayoutAll() end
                    end
                end
            end
        end

        if GLOG.ClearDebugLogs then GLOG.ClearDebugLogs() end
        
        -- Traiter les erreurs précoces capturées pendant le chargement
        if GLOG.ErrorHandler_ProcessEarlyErrors then
            GLOG.ErrorHandler_ProcessEarlyErrors()
        end
        
        -- Seed des listes par défaut du suivi personnalisé (versionné)
        if GLOG.GroupTracker_EnsureDefaultCustomLists then
            GLOG.GroupTracker_EnsureDefaultCustomLists(false)
        end

        -- STATUS_UPDATE automatique toutes les 3 minutes (rafraîchit localement iLvl/Clé/Côte via la fonction existante)
        if not GLOG._statusAutoTicker and C_Timer and C_Timer.NewTicker then
            GLOG._statusAutoTicker = C_Timer.NewTicker(180, function()
                if GLOG and GLOG.BroadcastStatusUpdate then
                    GLOG.BroadcastStatusUpdate()
                end
            end)
        end

        -- Slash /glog (ouvre l'UI principale) + sous-commande "track" pour ouvrir le suivi
        -- et activer l'enregistrement en arrière-plan
        SLASH_GLOG1 = "/glog"
        SlashCmdList.GLOG = function(msg)
            local txt = tostring(msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
            if txt == "mem" or txt == "memory" or txt == "ram" then
                local f = ns and ns.GLOG and ns.GLOG.Debug_PrintMemStats
                if f then f() else print("GLOG: outil mémoire indisponible") end
                return
            elseif txt == "gc" or txt == "collect" then
                local before = collectgarbage("count")
                collectgarbage("collect")
                local after  = collectgarbage("count")
                print(("GLOG GC: %.1f KiB -> %.1f KiB (%.1f libérés)"):format(before, after, before-after))
                return
            elseif txt == "bc" or txt == "bulk" then
                if ns and ns.GLOG and ns.GLOG.Debug_BulkCleanup then
                    ns.GLOG.Debug_BulkCleanup()
                end
                return
            elseif txt == "debugname" then
                -- Message avec un vrai lien d'item
                local message = "|cfa335eeRamassé par |r|Hplayer:TestPlayer-Realm:123:GUILD|h[TestPlayer-Realm]|h|cfa335ee: |r|cffa335ee|Hitem:123456::::::::80:257::3:4:6652:1472:6646:7756:1:28:456|h[Test Item]|h|r"
                print("=== TEST EXTRACTION NOM ===")
                print("Message:", message)
                
                local module = ns.LootTrackerParser
                if module and module.NameInGroupFromMessage then
                    print("Appel de NameInGroupFromMessage...")
                    local nom = module.NameInGroupFromMessage(message)
                    print("Nom extrait:", nom)
                else
                    print("GLOG: Fonction NameInGroupFromMessage indisponible")
                end
                return
            elseif txt == "testlootroll" then
                print("=== TEST LOOT RÉALISTE AVEC ROLLS ===")
                
                if ns.LootTrackerRolls then
                    local link = "|cffa335ee|Hitem:193001::::::::70:577::13:4:8836:8840:8902:8806::::::|h[Plastron de Raid]|h|r"
                    
                    -- D'abord, affichons les patterns WoW réels
                    print("0. Patterns WoW détectés :")
                    if LOOT_ROLL_NEED then print("NEED pattern:", LOOT_ROLL_NEED) end
                    if LOOT_ROLL_GREED then print("GREED pattern:", LOOT_ROLL_GREED) end
                    if LOOT_ROLL_PASSED then print("PASS pattern:", LOOT_ROLL_PASSED) end
                    if LOOT_ROLL_WON then print("WON pattern:", LOOT_ROLL_WON) end
                    
                    -- Testons manuellement avec des patterns simples
                    print("0b. Test manuel de patterns...")
                    local testMsg = "TestPlayer1 a choisi Besoin pour : " .. link
                    print("Message test:", testMsg)
                    
                    -- Test simple avec pattern manuel
                    local manualPattern = "(.+) a choisi Besoin pour : (.+)"
                    local who, itemLink = testMsg:match(manualPattern)
                    print("Match manuel - who:", who, "link:", itemLink and "TROUVÉ" or "nil")
                    
                    -- 1. Utilisons les patterns WoW réels pour générer les messages
                    print("1. Messages de rolls générés depuis patterns WoW...")
                    
                    local rollMessages = {}
                    
                    -- Utiliser le vrai nom du joueur pour le test
                    local playerName = UnitName("player") or "TestPlayer1"
                    print("Nom du joueur utilisé pour le test:", playerName)
                    
                    -- Générer des messages basés sur les patterns WoW réels
                    if LOOT_ROLL_NEED then
                        local msg = LOOT_ROLL_NEED:gsub("%%s", playerName, 1):gsub("%%s", link, 1)
                        table.insert(rollMessages, msg)
                        print("Message NEED généré:", msg)
                    end
                    
                    if LOOT_ROLL_GREED then
                        local msg = LOOT_ROLL_GREED:gsub("%%s", "TestPlayer2", 1):gsub("%%s", link, 1)
                        table.insert(rollMessages, msg)
                        print("Message GREED généré:", msg)
                    end
                    
                    if LOOT_ROLL_PASSED then
                        local msg = LOOT_ROLL_PASSED:gsub("%%s", "TestPlayer3", 1):gsub("%%s", link, 1)
                        table.insert(rollMessages, msg)
                        print("Message PASS généré:", msg)
                    end
                    
                    -- Traiter les messages comme le ferait le vrai système
                    print("2. Traitement des messages...")
                    for i, msg in ipairs(rollMessages) do
                        print("Traitement message " .. i .. ":", msg)
                        if ns.LootTrackerRolls.HandleChatMsgSystem then
                            ns.LootTrackerRolls.HandleChatMsgSystem(msg)
                        end
                    end
                    
                    -- Vérifier le cache après traitement des messages réels
                    print("3. Vérification du cache...")
                    local playerLower = (playerName or ""):lower()
                    local rType1, rVal1 = ns.LootTrackerRolls.GetRollFor(playerLower, link)
                    local rType2, rVal2 = ns.LootTrackerRolls.GetRollFor("testplayer2", link)
                    local rType3, rVal3 = ns.LootTrackerRolls.GetRollFor("testplayer3", link)
                    print("Roll " .. playerName .. ":", rType1 and (rType1 .. " (" .. (rVal1 or "?") .. ")") or "nil")
                    print("Roll TestPlayer2:", rType2 and (rType2 .. " (" .. (rVal2 or "?") .. ")") or "nil")
                    print("Roll TestPlayer3:", rType3 and (rType3 .. " (" .. (rVal3 or "?") .. ")") or "nil")
                    
                    -- 4. Simuler le message de loot réel
                    print("4. Message de loot réel...")
                    local lootMessage = "Ramassé par " .. playerName .. " : " .. link
                    print("Message loot:", lootMessage)
                    
                    if ns.LootTrackerParser and ns.LootTrackerParser.HandleChatMsgLoot then
                        ns.LootTrackerParser.HandleChatMsgLoot(lootMessage)
                        print("Message de loot traité!")
                        print("5. Maintenant vérifiez l'interface /glog > Tracker > Loots")
                        print("   -> La colonne 'Ramassé par' devrait afficher '" .. playerName .. "'")
                        print("   -> La colonne 'Roll' devrait afficher 'B' (Besoin)")
                    end
                else
                    print("Module LootTrackerRolls indisponible")
                end
                return
            end

            -- Comportement par défaut : ouvrir/afficher l’UI principale
            if ns and ns.ToggleUI then ns.ToggleUI() end
        end

        if ns.UI and ns.UI.Finalize then ns.UI.Finalize() end
        if ns.UI and ns.UI.ApplyTabsForGuildMembership then
            ns.UI.ApplyTabsForGuildMembership((IsInGuild and IsInGuild()) and true or false)
        end
        if ns.UI and ns.UI.RefreshTitle then ns.UI.RefreshTitle() end

        if ns.UI and ns.UI.UpdateRequestsBadge then ns.UI.UpdateRequestsBadge() end
        if GLOG.Minimap_Init then GLOG.Minimap_Init() end

        if GLOG.Comm_Init then GLOG.Comm_Init() end

        -- relance automatique initiale
        if GLOG.RefreshGuildCache then
            if C_Timer and C_Timer.After then
                C_Timer.After(1.0, function() GLOG.RefreshGuildCache() end)
            else
                GLOG.RefreshGuildCache()
            end
        end

        -- si l’enregistrement dépenses était actif lors du reload, on remet les hooks
        if GLOG.IsExpensesRecording and GLOG.IsExpensesRecording() and GLOG.Expenses_InstallHooks then
            GLOG.Expenses_InstallHooks()
        end

    elseif event == "PLAYER_ENTERING_WORLD" then
        if GLOG.RefreshGuildCache then
            ns.Util.After(3.0, function() GLOG.RefreshGuildCache() end)
        end
        -- ✨ déclenche le statut unifié si on est sur le main
        if GLOG.UpdateOwnStatusIfMain then
            ns.Util.After(5.0, function() GLOG.UpdateOwnStatusIfMain() end)
        end

    elseif event == "PLAYER_AVG_ITEM_LEVEL_UPDATE" then
        C_Timer.After(1, function()
            if GLOG.UpdateOwnStatusIfMain then GLOG.UpdateOwnStatusIfMain() end
        end)

    elseif event == "CHALLENGE_MODE_KEYSTONE_SLOTTED"
        or event == "CHALLENGE_MODE_START"
        or event == "CHALLENGE_MODE_COMPLETED"
        or event == "CHALLENGE_MODE_RESET" then

        if GLOG.UpdateOwnStatusIfMain then
            GLOG.UpdateOwnStatusIfMain()
        end

    elseif event == "CHAT_MSG_SYSTEM" then
        local msg = name
        if GLOG and GLOG.LootTracker_HandleChatMsgSystem and msg then
            GLOG.LootTracker_HandleChatMsgSystem(msg)
        end

        
    elseif event == "GUILD_ROSTER_UPDATE" then

        -- ➕ Demande une mise à jour du roster côté serveur
        if C_GuildInfo and C_GuildInfo.GuildRoster then
            C_GuildInfo.GuildRoster()
        end

        -- ➕ Recharge notre cache local
        if GLOG.RefreshGuildCache then
            GLOG.RefreshGuildCache()
        end

        -- ➕ Met à jour le titre si la guilde a changé / est disponible
        if ns.UI and ns.UI.RefreshTitle then
            ns.UI.RefreshTitle()
        end

        _ScheduleActiveTabRefresh()
    end
end)

-- ➕ Rafraîchissement visuel quand un iLvl change (centralisé)
if ns and ns.On then
    ns.On("ilvl:changed", function() _ScheduleActiveTabRefresh() end)
    -- ➕ et aussi quand une clé change
    ns.On("mkey:changed", function() _ScheduleActiveTabRefresh() end)
end

-- === Dispatch hub + conservation du handler existant ================
do
    local prev = f:GetScript("OnEvent") -- handler déjà défini plus haut
    f:SetScript("OnEvent", function(self, event, ...)
        -- 1) Appel des handlers enregistrés via ns.Events
        local E = ns.Events
        local list = E and E._handlers and E._handlers[event]
        if list then
            for i = 1, #list do
                local h = list[i]
                local ok, err = pcall(h.fn, h.owner, event, ...)
                if not ok then geterrorhandler()(err) end
            end
        end
        -- 2) Re-broadcast interne si votre bus d'events est utilisé
        if ns.Emit then ns.Emit("evt:" .. event, ...) end
        -- 3) Appel du handler d’origine pour ne rien casser
        if type(prev) == "function" then
            return prev(self, event, ...)
        end
    end)
end
-- ===================================================================
-- === App state (centralisé) : écran de chargement ===
ns.App = ns.App or {}
ns.App.loadingActive = false

-- Flag global alimenté par les évènements natifs
ns.Events.Register("LOADING_SCREEN_ENABLED", "core.loadingflag", function()
    ns.App.loadingActive = true
end)

ns.Events.Register("LOADING_SCREEN_DISABLED", "core.loadingflag", function()
    ns.App.loadingActive = false
end)
