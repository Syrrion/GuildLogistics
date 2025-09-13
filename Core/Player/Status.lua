local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
local GLOG = ns.GLOG

-- =========================
-- =====  iLvl (main)  =====
-- =========================

-- Lecture simple (nil si inconnu)
function GLOG.GetIlvl(name)
    if not name or name == "" then return nil end
    GLOG.EnsureDB()
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.players = GuildLogisticsDB.players or {}
    local p = GuildLogisticsDB.players[name]
    return p and tonumber(p.ilvl or nil) or nil
end

function GLOG.GetIlvlMax(name)
    if not name or name == "" then return nil end
    GLOG.EnsureDB()
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.players = GuildLogisticsDB.players or {}
    local p = GuildLogisticsDB.players[name]
    return p and tonumber(p.ilvlMax or nil) or nil
end

-- Application locale + signal UI (protégée)
local function _SetIlvlLocal(name, ilvl, ts, by, ilvlMax)
    if not name or name == "" then return end
    GLOG.EnsureDB()
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.players = GuildLogisticsDB.players or {}
    local p = GuildLogisticsDB.players[name]
    if not p then return end

    local nowts   = tonumber(ts) or time()
    local prev_ts = tonumber(p.statusTimestamp or 0) or 0
    if nowts >= prev_ts then
        p.ilvl   = math.floor(tonumber(ilvl) or 0)
        if ilvlMax ~= nil then
            p.ilvlMax = math.floor(tonumber(ilvlMax) or 0)
        end
        p.statusTimestamp = nowts
        if ns.Emit then ns.Emit("ilvl:changed", name) end
    end
end

-- Lecture immédiate de mon iLvl max (sans diffusion)
if not GLOG.ReadOwnMaxIlvl then
    function GLOG.ReadOwnMaxIlvl()
        if not GetAverageItemLevel then return nil end
        local overall = (select(1, GetAverageItemLevel()))
        if not overall then return nil end
        return math.max(0, math.floor((tonumber(overall) or 0) + 0.5))
    end
end

-- Lecture immédiate de mon iLvl équipé (sans diffusion)
if not GLOG.ReadOwnEquippedIlvl then
    function GLOG.ReadOwnEquippedIlvl()
        local equipped
        if GetAverageItemLevel then
            local overall, eq = GetAverageItemLevel()
            equipped = eq or overall
        end
        if not equipped then return nil end
        return math.max(0, math.floor((tonumber(equipped) or 0) + 0.5))
    end
end

-- ➕ ======  CLÉ MYTHIQUE : stockage local + formatage + diffusion ======
-- Lecture formatée pour l'UI ("NomDuDonjon +17", avec +X en orange)
function GLOG.GetMKeyText(name)
    if not name or name == "" then return "" end
    GLOG.EnsureDB()
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.players = GuildLogisticsDB.players or {}

    local p = GuildLogisticsDB.players[name]
    if not p then return "" end

    local lvl = tonumber(p.mkeyLevel or 0) or 0
    if lvl <= 0 then return "" end

    local label = ""
    local mid = tonumber(p.mkeyMapId or 0) or 0
    if mid > 0 and GLOG.ResolveMKeyMapName then
        local nm = GLOG.ResolveMKeyMapName(mid)
        if nm and nm ~= "" then label = nm end
    end
    if label == "" then label = "Clé" end

    local levelText = string.format("|cffffa500+%d|r", lvl)
    return string.format("%s %s", levelText, label)
end

-- Application locale (sans créer d'entrée ; timestamp dominant)
local function _SetMKeyLocal(name, mapId, level, mapName, ts, by)
    if not name or name == "" then return end
    GLOG.EnsureDB()
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.players = GuildLogisticsDB.players or {}
    local p = GuildLogisticsDB.players[name]
    if not p then return end

    local nowts   = tonumber(ts) or time()
    local prev_ts = tonumber(p.statusTimestamp or 0) or 0
    if nowts >= prev_ts then
        p.mkeyMapId = tonumber(mapId) or 0
        p.mkeyLevel = math.max(0, tonumber(level) or 0)
        p.statusTimestamp = nowts
        if ns.Emit then ns.Emit("mkey:changed", name) end
    end
end

-- ✨ M+ Score : getter + setter local protégés
function GLOG.GetMPlusScore(name)
    if not name or name == "" then return nil end
    GLOG.EnsureDB()
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.players = GuildLogisticsDB.players or {}
    local p = GuildLogisticsDB.players[name]
    return p and tonumber(p.mplusScore or nil) or nil
end

local function _SetMPlusScoreLocal(name, score, ts, by)
    if not name or name == "" then return end
    GLOG.EnsureDB()
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.players = GuildLogisticsDB.players or {}
    local p = GuildLogisticsDB.players[name]
    if not p then return end

    local nowts   = tonumber(ts) or time()
    local prev_ts = tonumber(p.statusTimestamp or 0) or 0
    if nowts >= prev_ts then
        p.mplusScore = math.max(0, tonumber(score) or 0)
        p.statusTimestamp = nowts
        if ns.Emit then ns.Emit("mplus:changed", name) end
        if ns.RefreshAll then ns.RefreshAll() end
    end
end

-- ✨ Application locale de la version de l'addon (protégée)
local function _SetAddonVersionLocal(name, version, ts, by)
    if not name or name == "" then return end
    GLOG.EnsureDB()
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.players = GuildLogisticsDB.players or {}
    local p = GuildLogisticsDB.players[name]
    if not p then return end

    local nowts = tonumber(ts) or time()
    local prev_ts = tonumber(p.statusTimestamp or 0) or 0
    if nowts >= prev_ts then
        -- Écrire la version au niveau du main: account.mains[mainUID].addonVersion (ShortId string)
        local uid = tostring(p.uid or (GLOG.GetOrAssignUID and GLOG.GetOrAssignUID(name)) or "")
        if uid and uid ~= "" then
            GuildLogisticsDB.account = GuildLogisticsDB.account or { mains = {}, altToMain = {} }
            local t = GuildLogisticsDB.account
            local mu = (t.altToMain and t.altToMain[uid]) or uid
            t.mains = t.mains or {}
            t.mains[mu] = (type(t.mains[mu]) == "table") and t.mains[mu] or {}
            t.mains[mu].addonVersion = tostring(version or "")
        end
        p.statusTimestamp = nowts
        -- Pas d'événement spécifique pour la version, cela sera inclus dans le refresh global
    end
end

-- ✨ Lecture immédiate de ma Côte M+ (Retail)
if not GLOG.ReadOwnMythicPlusScore then
    function GLOG.ReadOwnMythicPlusScore()
        if C_ChallengeMode and C_ChallengeMode.GetOverallDungeonScore then
            local s = C_ChallengeMode.GetOverallDungeonScore()
            if s and s > 0 then return math.floor(s) end
        end
        return nil
    end
end

-- ➕ Résolution du nom de donjon depuis un mapId (avec cache)
GLOG._mkeyNameCache = GLOG._mkeyNameCache or {}
function GLOG.ResolveMKeyMapName(mapId)
    local mid = tonumber(mapId) or 0
    if mid <= 0 then return nil end
    local cached = GLOG._mkeyNameCache[mid]
    if cached and cached ~= "" then
        return cached
    end

    local name
    local src = "NONE"

    -- 1) API moderne (Retail 11.x)
    if C_MythicPlus then
        if C_MythicPlus.GetMapUIInfo then
            local ok, res = pcall(C_MythicPlus.GetMapUIInfo, mid)
            if ok and res then
                if type(res) == "table" and res.name then
                    name = tostring(res.name)
                elseif type(res) == "string" then
                    name = res
                end
                if name and name ~= "" then src = "C_MythicPlus.GetMapUIInfo" end
            end
        end
        if not name and C_MythicPlus.GetMapInfo then
            local ok2, info = pcall(C_MythicPlus.GetMapInfo, mid)
            if ok2 and type(info) == "table" and info.name then
                name = tostring(info.name)
                if name and name ~= "" then src = "C_MythicPlus.GetMapInfo" end
            end
        end
    end

    -- 2) Fallback API héritée
    if not name and C_ChallengeMode then
        if C_ChallengeMode.GetMapUIInfo then
            local ok3, nm = pcall(C_ChallengeMode.GetMapUIInfo, mid)
            if ok3 and nm then
                name = type(nm) == "string" and nm or tostring(nm)
                if name and name ~= "" then src = "C_ChallengeMode.GetMapUIInfo" end
            end
        end
        if not name and C_ChallengeMode.GetMapInfo then
            local ok4, inf = pcall(C_ChallengeMode.GetMapInfo, mid)
            if ok4 and type(inf) == "table" and inf.name then
                name = tostring(inf.name)
                if name and name ~= "" then src = "C_ChallengeMode.GetMapInfo" end
            end
        end
    end

    if name and name ~= "" then
        GLOG._mkeyNameCache[mid] = name
    end

    return name
end

-- ➕ Joueur autorisé à émettre ? (présent en actif OU réserve)
function GLOG.IsPlayerInRosterOrReserve(name)
    if not name or name == "" then return false end
    GLOG.EnsureDB()
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.players = GuildLogisticsDB.players or {}
    return GuildLogisticsDB.players[name] ~= nil
end

-- Lit la clé possédée (API M+ si dispo, sinon parsing sacs)
local function _ReadOwnedKeystone()
    local lvl, mid = 0, 0
    local src = "NONE"

    -- 1) API Blizzard (Retail 11.x)
    if C_MythicPlus then
        local okMid, vMid = pcall(C_MythicPlus.GetOwnedKeystoneChallengeMapID)
        local okLvl, vLvl = pcall(C_MythicPlus.GetOwnedKeystoneLevel)
        if okMid and type(vMid) == "number" then mid = vMid or 0 end
        if okLvl and type(vLvl) == "number" then lvl = vLvl or 0 end
        if (lvl > 0 and mid > 0) then src = "API" end
    end

    local mapName = ""

    -- 2) Nom depuis l'API ChallengeMode (source fiable)
    if mapName == "" and mid and mid > 0 and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
        local okn, nm = pcall(C_ChallengeMode.GetMapUIInfo, mid)
        if okn and nm then
            mapName = type(nm) == "string" and nm or tostring(nm)
        end
    end

    -- 3) Dernier recours : résolveur basé sur mid
    if mapName == "" and mid and mid > 0 then
        local nm = GLOG.ResolveMKeyMapName and GLOG.ResolveMKeyMapName(mid)
        if nm and nm ~= "" then mapName = nm end
    end

    return mid or 0, lvl or 0, mapName or ""
end

-- ➕ Expose un lecteur public de la clé possédée (fallback si déjà défini ailleurs)
if not GLOG.ReadOwnedKeystone then
    function GLOG.ReadOwnedKeystone()
        return _ReadOwnedKeystone()
    end
end

-- ✨ Fusion : calcule iLvl (équipé + max) + Clé M+ et envoie un UNIQUE STATUS_UPDATE si changement
function GLOG.UpdateOwnStatusIfMain()
    -- Autorise aussi les personnages présents dans le roster/réserve (pas uniquement le main connecté)

    -- Throttle anti-spam (fusionné)
    local nowp = (GetTimePreciseSec and GetTimePreciseSec()) or (debugprofilestop and (debugprofilestop()/1000)) or 0
    GLOG._statusNextSendAt = GLOG._statusNextSendAt or 0
    local interval = 0.5 -- coalescer les rafales d'évènements d'équipement
    if nowp < GLOG._statusNextSendAt then return end
    GLOG._statusNextSendAt = nowp + interval

    -- Nom canonique du joueur (robuste)
    local me = (ns and ns.Util and ns.Util.playerFullName and ns.Util.playerFullName())
            or ((ns and ns.Util and ns.Util.NormalizeFull) and ns.Util.NormalizeFull((UnitName and UnitName("player"))))
            or (UnitName and UnitName("player")) or "?"
    -- Assure qu'une entrée existe pour le main connecté afin d'autoriser l'application locale et la diffusion
    do
        if GLOG.IsConnectedMain and GLOG.IsConnectedMain() then
            if GLOG.EnsureDB then GLOG.EnsureDB() end
            GuildLogisticsDB = GuildLogisticsDB or {}
            GuildLogisticsDB.players = GuildLogisticsDB.players or {}
            if not GuildLogisticsDB.players[me] then
                GuildLogisticsDB.players[me] = { createdAt = time and time() or 0 }
            end
        end
    end
    if not (GLOG.IsPlayerInRosterOrReserve and GLOG.IsPlayerInRosterOrReserve(me)) then return end

    -- ===== iLvl =====
    local ilvl, ilvlMax = nil, nil
    if GLOG.ReadOwnEquippedIlvl then ilvl = GLOG.ReadOwnEquippedIlvl() end
    if GLOG.ReadOwnMaxIlvl     then ilvlMax = GLOG.ReadOwnMaxIlvl()   end
    if ilvl    ~= nil then ilvl    = math.max(0, math.floor((tonumber(ilvl)    or 0) + 0.5)) end
    if ilvlMax ~= nil then ilvlMax = math.max(0, math.floor((tonumber(ilvlMax) or 0) + 0.5)) end
    local changedIlvl = (ilvl ~= nil) and ((GLOG._lastOwnIlvl or -1) ~= ilvl) or false
    if ilvl ~= nil then GLOG._lastOwnIlvl = ilvl end

    -- ✨ ===== Côte M+ =====
    local score = GLOG.ReadOwnMythicPlusScore and GLOG.ReadOwnMythicPlusScore() or nil
    if score ~= nil then score = math.max(0, math.floor((tonumber(score) or 0) + 0.5)) end
    local changedScore = (score ~= nil) and ((GLOG._lastOwnMPlusScore or -1) ~= score) or false
    if score ~= nil then GLOG._lastOwnMPlusScore = score end

    -- ===== Clé M+ =====
    local mid, lvl, map = 0, 0, ""
    if GLOG.ReadOwnedKeystone then mid, lvl, map = GLOG.ReadOwnedKeystone() end
    if (not map or map == "" or map == "Clé") and mid and mid > 0 and GLOG.ResolveMKeyMapName then
        local nm = GLOG.ResolveMKeyMapName(mid); if nm and nm ~= "" then map = nm end
    end
    local changedM = ((GLOG._lastOwnMKeyId or -1) ~= (mid or 0)) or ((GLOG._lastOwnMKeyLvl or -1) ~= (lvl or 0))
    GLOG._lastOwnMKeyId  = mid or 0
    GLOG._lastOwnMKeyLvl = lvl or 0

    -- ===== Écriture locale + diffusion unifiée =====
    local ts = time()
    if ilvl ~= nil then _SetIlvlLocal(me, ilvl, ts, me, ilvlMax) end
    if score ~= nil then _SetMPlusScoreLocal(me, score, ts, me) end
    if (mid or 0) > 0 or (lvl or 0) > 0 or (tostring(map or "") ~= "") then
        _SetMKeyLocal(me, mid or 0, lvl or 0, tostring(map or ""), ts, me)
    end
    
    -- ✨ Mise à jour de la version de l'addon
    local currentVersion = (GLOG.GetAddonVersion and GLOG.GetAddonVersion()) or ""
    if currentVersion ~= "" then
        _SetAddonVersionLocal(me, currentVersion, ts, me)
    end

    -- Invalide immédiatement le cache de statut, pour que le prochain payload reflète les nouvelles valeurs
    if GLOG.InvalidateStatusCache then GLOG.InvalidateStatusCache() end

    if (changedIlvl or changedM or changedScore) and GLOG.BroadcastStatusUpdate then
        GLOG.BroadcastStatusUpdate({
            ilvl = ilvl, ilvlMax = ilvlMax,
            score = score,
            mid = mid or 0, lvl = lvl or 0, map = tostring(map or ""),
            ts = ts, by = me,
            localApplied = true,   -- ✅ déjà appliqué en local dans cette fonction
        })
    end
end

-- Calcul & diffusion de MA propre clé (uniquement si le perso connecté est le main)
function GLOG.UpdateOwnKeystoneIfMain()
    if not (GLOG.IsConnectedMain and GLOG.IsConnectedMain()) then return end

    -- Throttle anti-spam
    local tnow = (GetTimePreciseSec and GetTimePreciseSec()) or (debugprofilestop and (debugprofilestop()/1000)) or 0
    GLOG._mkeyNextSendAt = GLOG._mkeyNextSendAt or 0
    if tnow < GLOG._mkeyNextSendAt then return end
    GLOG._mkeyNextSendAt = tnow + 5.0

    -- Lecture robuste (API M+ -> fallback sacs)
    local mid, lvl, mapName = _ReadOwnedKeystone()

    -- ✅ Nom canonique (évite "Nom-" quand prealm est nil ; normalise le royaume)
    local function _MyFull()
        if ns and ns.Util and ns.Util.playerFullName then
            return ns.Util.playerFullName()
        end
        -- Fallback minimaliste
        local n = (UnitName and UnitName("player")) or "?"
        if GetNormalizedRealmName then return n.."-"..GetNormalizedRealmName() end
        return n
    end

    local me = _MyFull()
    if ns and ns.Util and ns.Util.NormalizeFull then me = ns.Util.NormalizeFull(me) end

    -- 🚫 Stop si pas dans roster/réserve (et ne crée **pas** d'entrée)
    do
        -- Assure qu'une entrée existe pour le main connecté afin d'autoriser l'application locale et la diffusion
        if GLOG.IsConnectedMain and GLOG.IsConnectedMain() then
            if GLOG.EnsureDB then GLOG.EnsureDB() end
            GuildLogisticsDB = GuildLogisticsDB or {}
            GuildLogisticsDB.players = GuildLogisticsDB.players or {}
            if not GuildLogisticsDB.players[me] then
                GuildLogisticsDB.players[me] = { createdAt = time and time() or 0 }
            end
        end
    end
    if not (GLOG.IsPlayerInRosterOrReserve and GLOG.IsPlayerInRosterOrReserve(me)) then return end

    -- Complète le nom du donjon si absent (via résolveur dédié)
    if (not mapName or mapName == "" or mapName == "Clé") and mid and mid > 0 then
        local nm2 = GLOG.ResolveMKeyMapName and GLOG.ResolveMKeyMapName(mid)
        if nm2 and nm2 ~= "" then mapName = nm2 end
    end

    local changed = (GLOG._lastOwnMKeyId or -1) ~= (mid or 0) or (GLOG._lastOwnMKeyLvl or -1) ~= (lvl or 0)
    GLOG._lastOwnMKeyId  = mid or 0
    GLOG._lastOwnMKeyLvl = lvl or 0

    local ts = time()
    _SetMKeyLocal(me, mid or 0, lvl or 0, mapName or "", ts, me)
    
    -- ✨ Mise à jour de la version de l'addon
    local currentVersion = (GLOG.GetAddonVersion and GLOG.GetAddonVersion()) or ""
    if currentVersion ~= "" then
        _SetAddonVersionLocal(me, currentVersion, ts, me)
    end
    
    if changed and GLOG.BroadcastStatusUpdate then
        local equipped = GLOG.ReadOwnEquippedIlvl and GLOG.ReadOwnEquippedIlvl() or nil
        local overall  = GLOG.ReadOwnMaxIlvl     and GLOG.ReadOwnMaxIlvl()     or nil
        GLOG.BroadcastStatusUpdate({
            ilvl = equipped, ilvlMax = overall,
            mid = mid or 0, lvl = lvl or 0,
            ts = ts, by = me,
        })
    end
end
