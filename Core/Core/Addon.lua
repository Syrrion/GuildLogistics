local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
ns.Util = ns.Util or {}
local GLOG, U = ns.GLOG, ns.Util

-- Ensure account-level SavedVariables (GuildLogisticsShared) exists ASAP
_G.GuildLogisticsShared = _G.GuildLogisticsShared or { guilds = {} }
if type(_G.GuildLogisticsShared.guilds) ~= "table" then _G.GuildLogisticsShared.guilds = {} end

-- Helper sûr pour lire les métadonnées du TOC sans référencer de globales non définies
local _metaCache = { Title = nil, IconTexture = nil, Version = nil }
local function _GetMeta(key)
    -- Cache les valeurs lues une fois par session (évite des milliers d'appels lors des refresh UI)
    if _metaCache and _metaCache[key] ~= nil then
        return _metaCache[key]
    end
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        local v = C_AddOns.GetAddOnMetadata(ADDON, key)
        if _metaCache then _metaCache[key] = v end
        return v
    end
    do
        local m = _G and rawget(_G, "GetAddOnMetadata")
        if type(m) == "function" then
            local v = m(ADDON, key)
            if _metaCache then _metaCache[key] = v end
            return v
        end
    end
    return nil
end

-- Tables pour le suivi des versions d'addon
GLOG._playerVersions = GLOG._playerVersions or {}
-- Cache léger pour les recherches de version par nom (évite de rescanner la DB à chaque frame)
local _versionLookupCache = {} -- [normalizedName] = { v = "1.2.3", ts = now }
local _versionLookupTTL = 5 -- secondes
GLOG._lastVersionNotifications = GLOG._lastVersionNotifications or {}

-- Renvoie le titre officiel de l'addon (métadonnée TOC), codes couleur retirés.
-- Fallback possible via système de traduction 'ns.Tr'.
function GLOG.GetAddonTitle()
    local title = _GetMeta("Title")
    if type(title) == "string" and title ~= "" then
        return title:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    end
    local Tr = ns and ns.Tr
    return (Tr and Tr("app_title"))
end

-- Renvoie le chemin/ID d'icône déclaré dans le TOC ; fallback vers une icône générique.
function GLOG.GetAddonIconTexture()
    local icon = _GetMeta("IconTexture")
    if type(icon) == "string" and icon ~= "" then
        return icon
    end
    return "Interface\\Icons\\INV_Misc_Book_09"
end

-- Renvoie la version déclarée (string). Utile pour affichage/compat.
function GLOG.GetAddonVersion()
    -- Version stable pour la session: lit une fois et réutilise
    if _metaCache and type(_metaCache.Version) == "string" and _metaCache.Version ~= "" then
        return tostring(_metaCache.Version)
    end
    local v = _GetMeta("Version") or (ns and ns.Version)
    v = tostring(v or "")
    if _metaCache then _metaCache.Version = v end
    return v
end

-- Compare deux versions sémantiques "a.b.c" ; retourne -1 / 0 / 1.
function U.CompareVersions(a, b)
    local function parse(s)
        local out = {}
        for n in tostring(s or ""):gmatch("(%d+)") do out[#out + 1] = tonumber(n) or 0 end
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

-- Lit la révision stockée en DB (GuildLogisticsDB.meta.rev) ou via GLOG.GetRev si défini.
local function getRev()
    if GLOG.GetRev then
        return U.safenum(GLOG.GetRev(), 0)
    end
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.meta = GuildLogisticsDB.meta or {}
    return U.safenum(GuildLogisticsDB.meta.rev, 0)
end

_G.getRev = _G.getRev or getRev

-- ===== Gestion des versions d'addon des autres joueurs =====

-- Cache des versions des autres joueurs
-- Structure : { [playerName] = { version = "2.3.1", timestamp = 123456789, seenBy = "PlayerWhoReported" } }
GLOG._playerVersions = GLOG._playerVersions or {}

-- Enregistrer la version d'un autre joueur
-- @param name: string - nom du joueur (avec realm)
-- @param version: string - version de l'addon 
-- @param timestamp: number - timestamp de la dernière vue
-- @param reportedBy: string - joueur qui a rapporté cette version
function GLOG.SetPlayerAddonVersion(name, version, timestamp, reportedBy)
    if not name or name == "" or not version or version == "" then return end
    
    local key = tostring(name)
    local ts = tonumber(timestamp) or time()
    local by = tostring(reportedBy or "")
    
    -- Ne mettre à jour que si la version est plus récente
    local existing = GLOG._playerVersions[key]
    if existing and tonumber(existing.timestamp or 0) > ts then
        return -- Version existante plus récente
    end
    
    -- Vérifier si cette version est plus récente que la nôtre
    local myVersion = GLOG.GetAddonVersion() or ""
    local theirVersion = tostring(version)
    
    if myVersion ~= "" and theirVersion ~= "" and U.CompareVersions then
        local comparison = U.CompareVersions(myVersion, theirVersion)
        if comparison < 0 then -- Notre version est plus ancienne
            -- Vérifier si on a déjà affiché cette notification récemment
            local notifKey = "version_notif_" .. theirVersion
            local lastNotif = GLOG._lastVersionNotifications and GLOG._lastVersionNotifications[notifKey] or 0
            local now = time()
            
            -- Afficher maximum une fois par heure pour une version donnée
            if (now - lastNotif) > 3600 then
                GLOG._lastVersionNotifications = GLOG._lastVersionNotifications or {}
                GLOG._lastVersionNotifications[notifKey] = now
                
                -- Vérifier que le joueur n'est pas en combat ou en instance
                local inCombat = InCombatLockdown and InCombatLockdown() or false
                local inInstance = IsInInstance and IsInInstance() or false
                
                if not inCombat and not inInstance then
                    -- Afficher la popup de version obsolète immédiatement
                    if ns and ns.UI and ns.UI.ShowOutdatedAddonPopup then
                        ns.UI.ShowOutdatedAddonPopup(myVersion, theirVersion, name)
                    end
                else
                    -- Reporter l'affichage de la popup quand le joueur sortira de combat/instance
                    GLOG._pendingVersionNotification = {
                        myVersion = myVersion,
                        theirVersion = theirVersion,
                        fromPlayer = name
                    }
                    
                    -- Créer un timer pour vérifier périodiquement si on peut afficher la popup
                    if not GLOG._versionNotificationTimer then
                        GLOG._versionNotificationTimer = C_Timer.NewTicker(60, function()
                            local stillInCombat = InCombatLockdown and InCombatLockdown() or false
                            local stillInInstance = IsInInstance and IsInInstance() or false
                            
                            if not stillInCombat and not stillInInstance and GLOG._pendingVersionNotification then
                                local pending = GLOG._pendingVersionNotification
                                GLOG._pendingVersionNotification = nil
                                
                                if ns and ns.UI and ns.UI.ShowOutdatedAddonPopup then
                                    ns.UI.ShowOutdatedAddonPopup(pending.myVersion, pending.theirVersion, pending.fromPlayer)
                                end
                                
                                -- Arrêter le timer
                                if GLOG._versionNotificationTimer then
                                    GLOG._versionNotificationTimer:Cancel()
                                    GLOG._versionNotificationTimer = nil
                                end
                            end
                        end)
                    end
                end
            end
        end
    end
    
    GLOG._playerVersions[key] = {
        version = tostring(version),
        timestamp = ts,
        seenBy = by
    }
    -- Invalide le cache de lookup pour ce joueur pour refléter immédiatement la nouvelle valeur
    local norm = (ns.Util and ns.Util.NormalizeFull and ns.Util.NormalizeFull(name)) or tostring(name)
    if norm and _versionLookupCache[norm] then _versionLookupCache[norm] = nil end
end

-- Obtenir la version d'un autre joueur
-- @param name: string - nom du joueur
-- @return string|nil: version de l'addon ou nil si inconnue
function GLOG.GetPlayerAddonVersion(name)
    if not name or name == "" then return nil end
    -- normaliser le nom pour une clé stable
    local key = (ns.Util and ns.Util.NormalizeFull and ns.Util.NormalizeFull(name)) or tostring(name)

    -- 0) Cache court-terme pour éviter des appels répétés dans la même seconde (ex: rafraîchissements UI)
    do
        local c = _versionLookupCache[key]
        if c then
            local now = time()
            if (now - (tonumber(c.ts) or 0)) <= _versionLookupTTL then
                return c.v
            else
                _versionLookupCache[key] = nil
            end
        end
    end
    local data = GLOG._playerVersions[key]
    
    -- Si présent en cache et non périmé, utiliser cette valeur
    if data then
        local cutoff = time() - (7 * 24 * 60 * 60)
        if tonumber(data.timestamp or 0) >= cutoff then
            local v = data.version
            _versionLookupCache[key] = { v = v, ts = time() }
            return v
        else
            -- purge cache périmé
            GLOG._playerVersions[key] = nil
        end
    end

    -- Lire depuis account.mains[mainUID].addonVersion
    if GLOG.EnsureDB then GLOG.EnsureDB() end
    local db = _G.GuildLogisticsDB or {}
    db.account = db.account or { mains = {}, altToMain = {} }
    local uid = nil
    do
        -- Utiliser l'UID connu si présent en roster, sinon un lookup non-créateur
        db.players = db.players or {}
        local p = db.players[key]
        uid = tostring(p and p.uid or "")
        if not uid then
            if GLOG.FindUIDByName then
                uid = tostring(GLOG.FindUIDByName(key) or "")
            elseif GLOG.GetUID then
                uid = tostring(GLOG.GetUID(key) or "")
            end
        end
    end
    if uid and uid ~= "" and db.account then
        local mu = (db.account.altToMain and db.account.altToMain[uid]) or uid
        local mrec = db.account.mains and db.account.mains[mu]
        local ver = mrec and mrec.addonVersion
        if ver and ver ~= "" then
            local v = tostring(ver)
            _versionLookupCache[key] = { v = v, ts = time() }
            return v
        end
    end

    -- Fallback 2 (lecture seule): ancienne position players[*].addonVersion
    -- Aucune lecture legacy: la version doit être en account.mains ou cache
    
    _versionLookupCache[key] = { v = nil, ts = time() }
    return nil
end

-- Nettoyer les versions anciennes
-- @param maxAge: number - âge maximum en secondes (défaut: 7 jours)
function GLOG.CleanupPlayerVersions(maxAge)
    maxAge = tonumber(maxAge) or (7 * 24 * 60 * 60) -- 7 jours par défaut
    local cutoff = time() - maxAge
    local cleaned = 0
    
    for name, data in pairs(GLOG._playerVersions or {}) do
        if tonumber(data.timestamp or 0) < cutoff then
            GLOG._playerVersions[name] = nil
            cleaned = cleaned + 1
        end
    end
    
    return cleaned
end

-- Aliases pour compatibilité
GLOG.playerVersions = GLOG._playerVersions
