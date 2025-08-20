local ADDON, ns = ...
ns.GMGR = ns.GMGR or {}
local GMGR = ns.GMGR

-- Icône centrale de l’addon (réutilisable partout, y compris minimap)
GMGR.ICON_TEXTURE = GMGR.ICON_TEXTURE or "Interface\\AddOns\\GuildManager\\Ressources\\Media\\LogoAddonWoW128.tga"

function GMGR.GetAddonIconTexture(size)
    local base = "Interface\\AddOns\\GuildManager\\Ressources\\Media\\LogoAddonWoW"
    local pick
    if type(size) == "number" then
        if size <= 16 then       pick = "16"
        elseif size <= 32 then   pick = "32"
        elseif size <= 64 then   pick = "64"
        elseif size <= 128 then  pick = "128"
        elseif size <= 256 then  pick = "256"
        else                     pick = "400"
        end
    elseif type(size) == "string" then
        local s = string.lower(size)
        if s == "tiny" then                  pick = "16"
        elseif s == "minimap" or s == "sm" then pick = "32"
        elseif s == "small" then             pick = "64"
        elseif s == "medium" then            pick = "128"
        elseif s == "large" then             pick = "256"
        elseif s == "xlarge" or s == "xl" then pick = "400"
        end
    end
    pick = pick or "128"
    return base .. pick .. ".tga"
end

-- =========================
-- ======  DATABASE   ======
-- =========================
local function EnsureDB()
    GuildManagerDB = GuildManagerDB or {
        players = {},
        history = {},
        expenses = { recording = false, list = {}, nextId = 1 },
        lots     = { nextId = 1, list = {} },
        ids = { counter=0, byName={}, byId={} },
        meta = { lastModified=0, fullStamp=0, rev=0, master=nil }, -- + rev
        requests = {},
        historyNextId = 1,  -- ➕ compteur HID
        debug = {},
    }
    GuildManagerUI = GuildManagerUI or {
        point="CENTER", relTo=nil, relPoint="CENTER", x=0, y=0, width=1160, height=680,
        minimap = { hide = false, angle = 215 },
    }
    GuildManagerUI.minimap = GuildManagerUI.minimap or { hide=false, angle=215 }
    if GuildManagerUI.minimap.angle == nil then GuildManagerUI.minimap.angle = 215 end

    -- ➕ Par défaut : débug actif (Oui)
    if GuildManagerUI.debugEnabled == nil then GuildManagerUI.debugEnabled = true end
end

GMGR._EnsureDB = EnsureDB

-- ➕ API : état du débug
function GMGR.IsDebugEnabled()
    EnsureDB()
    return GuildManagerUI.debugEnabled ~= false
end

-- =========================
-- ======  PLAYERS    ======
-- =========================
local function GetOrCreatePlayer(name)
    EnsureDB()
    if not name or name == "" then return { credit=0, debit=0, reserved=false } end
    local p = GuildManagerDB.players[name]
    if not p then
        p = { credit = 0, debit = 0, reserved = false }  -- ➕ flag de réserve par défaut
        GuildManagerDB.players[name] = p
    else
        if p.reserved == nil then p.reserved = false end -- compat données anciennes
    end
    return p
end

-- ➕ Statut « en réserve » (tolérant plusieurs clés héritées)
function GMGR.IsReserved(name)
    GuildManagerDB = GuildManagerDB or {}
    local p = GuildManagerDB.players and GuildManagerDB.players[name]
    if not p then return false end
    -- Tolère reserved / reserve / bench, ou un status textuel
    local v = p.reserved
           or p.reserve
           or p.bench
           or ((type(p.status)=="string") and (p.status:upper()=="RESERVE" or p.status:upper()=="RESERVED"))
    if type(v) == "boolean" then return v end
    if type(v) == "number"  then return v ~= 0 end
    if type(v) == "string"  then return v:lower() ~= "false" and v ~= "" end
    return false
end
-- Alias rétro-compatible si jamais du code appelle IsReserve()
GMGR.IsReserve = GMGR.IsReserved

function GMGR.GetPlayersArray()
    EnsureDB()
    local out = {}
    for name, p in pairs(GuildManagerDB.players) do
        local credit   = tonumber(p.credit) or 0
        local debit    = tonumber(p.debit)  or 0
        local reserved = (p.reserved == true)
        table.insert(out, {
            name   = name,
            credit = credit,
            debit  = debit,
            solde  = credit - debit,
            reserved = reserved,          -- ✅ on propage le statut pour les filtres en aval
        })
    end
    table.sort(out, function(a,b) return a.name:lower() < b.name:lower() end)
    return out
end

-- ➕ Sous-ensembles utiles à l’UI (actif / réserve)
function GMGR.GetPlayersArrayActive()
    local src = GMGR.GetPlayersArray()
    local out = {}
    for _, r in ipairs(src) do
        -- ✅ robuste même si un appelant fournit une ligne sans champ 'reserved'
        local isRes = (r.reserved ~= nil) and r.reserved
                      or (GMGR.IsReserved and GMGR.IsReserved(r.name)) or false
        if not isRes then out[#out+1] = r end
    end
    return out
end


function GMGR.GetPlayersArrayReserve()
    EnsureDB()
    local out = {}
    for name, p in pairs(GuildManagerDB.players) do
        if p.reserved then
            local credit = tonumber(p.credit) or 0
            local debit  = tonumber(p.debit) or 0
            out[#out+1] = {
                name = name, credit = credit, debit = debit,
                solde = credit - debit, reserved = true
            }
        end
    end
    table.sort(out, function(a,b) return a.name:lower() < b.name:lower() end)
    return out
end

function GMGR.AddPlayer(name)
    if not name or name == "" then return end
    GetOrCreatePlayer(name)
    if GMGR.GetOrAssignUID then GMGR.GetOrAssignUID(name) end
    if GMGR.BroadcastRosterUpsert and GMGR.IsMaster and GMGR.IsMaster() then
        GMGR.BroadcastRosterUpsert(name)
    end
    return true
end


function GMGR.RemovePlayer(name)
    if not (GMGR.IsMaster and GMGR.IsMaster()) then
        UIErrorsFrame:AddMessage("|cffff6060[GMGR]|r Suppression du roster réservée au GM.", 1, 0.4, 0.4)
        return false
    end
    GuildManagerDB = GuildManagerDB or {}
    local p = GuildManagerDB.players or {}
    if p[name] then p[name] = nil end
    -- Optionnel: retirer l'UID mappé
    if GuildManagerDB.ids and GuildManagerDB.ids.byName then
        local uid = GuildManagerDB.ids.byName[name]
        if uid then
            GuildManagerDB.ids.byName[name] = nil
            if GuildManagerDB.ids.byId then GuildManagerDB.ids.byId[uid] = nil end
        end
    end
    if ns.RefreshAll then ns.RefreshAll() end
    return true
end


function GMGR.HasPlayer(name)
    EnsureDB()
    if not name or name == "" then return false end
    return GuildManagerDB.players[name] ~= nil
end

-- ➕ Statut "en réserve" (alias bench pris en charge)
function GMGR.IsReserve(name)
    EnsureDB()
    if not name or name == "" then return false end
    local p = GuildManagerDB.players[name]
    return (p and ((p.reserve == true) or (p.bench == true))) or false
end

function GMGR.Credit(name, amount)
    local p = GetOrCreatePlayer(name)
    local a = math.floor(tonumber(amount) or 0)
    p.credit = (p.credit or 0) + a
end

function GMGR.Debit(name, amount)
    local p = GetOrCreatePlayer(name)
    local a = math.floor(tonumber(amount) or 0)
    p.debit = (p.debit or 0) + a
end

function GMGR.GetSolde(name)
    local p = GetOrCreatePlayer(name)
    return (p.credit or 0) - (p.debit or 0)
end

function GMGR.SamePlayer(a, b)
    if not a or not b then return false end
    -- Comparaison stricte sur le nom complet (insensible à la casse)
    return string.lower(tostring(a)) == string.lower(tostring(b))
end


-- ➕ Normalisation des clés joueurs (merge "Nom" et "Nom-Realm", dédoublonne les realms répétés)
function GMGR.NormalizePlayerKeys()
    if not GuildManagerDB then return end
    GuildManagerDB.players = GuildManagerDB.players or {}
    GuildManagerDB.uids    = GuildManagerDB.uids    or {}

    local function dedupRealm(full)
        full = tostring(full or "")
        local base, realm = full:match("^(.-)%-(.+)$")
        if not realm then
            -- si pas de realm : on rajoute celui du perso courant si disponible
            local rn = select(2, UnitFullName("player"))
            return (rn and rn ~= "" and (full.."-"..rn)) or full
        end
        -- garde uniquement le 1er segment de realm (évite A-B-C lors d’insertions successives)
        realm = realm:match("^([^%-]+)") or realm
        return string.format("%s-%s", base, realm)
    end

    -- 1) Rebuild players avec clés normalisées + fusion des soldes
    local rebuilt = {}
    for name, rec in pairs(GuildManagerDB.players) do
        local norm = (NormalizeFull and NormalizeFull(name)) or name
        norm = dedupRealm(norm)
        local dst = rebuilt[norm]
        if not dst then
            rebuilt[norm] = { credit = tonumber(rec.credit) or 0, debit = tonumber(rec.debit) or 0 }
        else
            dst.credit = (dst.credit or 0) + (tonumber(rec.credit) or 0)
            dst.debit  = (dst.debit  or 0) + (tonumber(rec.debit)  or 0)
        end
    end
    GuildManagerDB.players = rebuilt

    -- 2) Normalise aussi la table des UIDs -> noms
    local newUIDs = {}
    for uid, n in pairs(GuildManagerDB.uids) do
        local norm = (NormalizeFull and NormalizeFull(n)) or n
        newUIDs[tostring(uid)] = dedupRealm(norm)
    end
    GuildManagerDB.uids = newUIDs
end

-- Ajuste directement le solde d’un joueur : delta > 0 => ajoute de l’or, delta < 0 => retire de l’or
function GMGR.AdjustSolde(name, delta)
    local d = math.floor(tonumber(delta) or 0)
    if d == 0 then return GMGR.GetSolde(name) end
    if d > 0 then GMGR.Credit(name, d) else GMGR.Debit(name, -d) end
    return GMGR.GetSolde(name)
end

-- Marquer la modif + broadcast par le GM depuis une seule API dédiée
function GMGR.GM_AdjustAndBroadcast(name, delta)
    if GMGR.GM_ApplyAndBroadcast then GMGR.GM_ApplyAndBroadcast(name, delta) end
end

-- Helpers conviviaux
function GMGR.AddGold(name, amount)
    return GMGR.AdjustSolde(name, math.floor(tonumber(amount) or 0))
end

function GMGR.RemoveGold(name, amount)
    return GMGR.AdjustSolde(name, -math.floor(tonumber(amount) or 0))
end

-- === Bus d’événements minimal ===
ns._ev = ns._ev or {}
function ns.On(evt, fn)
    if not evt or type(fn)~="function" then return end
    ns._ev[evt] = ns._ev[evt] or {}
    table.insert(ns._ev[evt], fn)
end
function ns.Emit(evt, ...)
    local t = ns._ev and ns._ev[evt]
    if not t then return end
    for i=1,#t do
        local ok,err = pcall(t[i], ...)
        if not ok then geterrorhandler()(err) end
    end
end

function GMGR.EnsureRosterLocal(name)
    if not name or name == "" then return end
    GuildManagerDB = GuildManagerDB or {}
    GuildManagerDB.players = GuildManagerDB.players or {}
    local created = false
    if not GuildManagerDB.players[name] then
        GuildManagerDB.players[name] = { credit = 0, debit = 0, reserved = false }
        created = true
    else
        if GuildManagerDB.players[name].reserved == nil then
            GuildManagerDB.players[name].reserved = false
        end
    end
    if created then ns.Emit("roster:upsert", name) end
end

function GMGR.RemovePlayerLocal(name, silent)
    if not name or name=="" then return false end
    GuildManagerDB = GuildManagerDB or {}
    local p = GuildManagerDB.players or {}
    local existed = not not p[name]
    if p[name] then p[name] = nil end

    -- ancien mapping (legacy)
    if GuildManagerDB.ids and GuildManagerDB.ids.byName then
        local _uid = GuildManagerDB.ids.byName[name]
        if _uid then
            GuildManagerDB.ids.byName[name] = nil
            if GuildManagerDB.ids.byId then GuildManagerDB.ids.byId[_uid] = nil end
        end
    end

    -- purge aussi la table des UID actifs
    if GuildManagerDB.uids then
        local uid = nil
        if GMGR.FindUIDByName then
            uid = GMGR.FindUIDByName(name)
        elseif ns and ns.Util and ns.Util.FindUIDByName then
            uid = ns.Util.FindUIDByName(name)
        end
        if not uid then
            for k,v in pairs(GuildManagerDB.uids) do if v == name then uid = k break end end
        end
        if uid then GuildManagerDB.uids[uid] = nil end
    end

    if existed then ns.Emit("roster:removed", name) end
    if not silent and ns.RefreshAll then ns.RefreshAll() end
    return true
end

-- Suppression orchestrée : réservée au GM + broadcast
-- Remplace la version précédente de RemovePlayer si déjà présente
function GMGR.RemovePlayer(name)
    if not (GMGR.IsMaster and GMGR.IsMaster()) then
        UIErrorsFrame:AddMessage("|cffff6060[GMGR]|r Suppression du roster réservée au GM.", 1, 0.4, 0.4)
        return false
    end
    if not name or name=="" then return false end

    local uid = GMGR.GetUID and GMGR.GetUID(name) or nil

    -- Applique localement (GM)
    GMGR.RemovePlayerLocal(name, true)

    -- Incrémente la révision et horodate pour les clients qui filtrent sur rv/lm
    GuildManagerDB = GuildManagerDB or {}
    GuildManagerDB.meta = GuildManagerDB.meta or {}
    local rv = (GuildManagerDB.meta.rev or 0) + 1
    GuildManagerDB.meta.rev = rv
    GuildManagerDB.meta.lastModified = time()

    -- Diffuse la suppression à toute la guilde avec rv/lm
    if GMGR.Comm_Broadcast then
        GMGR.Comm_Broadcast("ROSTER_REMOVE", {
            uid = uid,
            name = name,
            rv  = rv,
            lm  = GuildManagerDB.meta.lastModified,
        })
    end

    if ns.RefreshAll then ns.RefreshAll() end
    return true
end

-- ➕ API réserve : lecture + application locale + commande GM + broadcast
function GMGR.IsReserved(name)
    EnsureDB()
    local p = name and GuildManagerDB.players and GuildManagerDB.players[name]
    return (p and p.reserved) and true or false
end

local function _SetReservedLocal(name, flag)
    local p = GetOrCreatePlayer(name)
    local prev = not not p.reserved
    p.reserved = not not flag
    if prev ~= p.reserved and ns.Emit then ns.Emit("roster:reserve", name, p.reserved) end
end

function GMGR.GM_SetReserved(name, flag)
    if not (GMGR.IsMaster and GMGR.IsMaster()) then
        if UIErrorsFrame then
            UIErrorsFrame:AddMessage("|cffff6060[GMGR]|r Changement d’attribution réservé au GM.", 1, .4, .4)
        end
        return false
    end
    if not name or name=="" then return false end

    _SetReservedLocal(name, flag)

    GuildManagerDB.meta = GuildManagerDB.meta or {}
    local rv = (GuildManagerDB.meta.rev or 0) + 1
    GuildManagerDB.meta.rev = rv
    GuildManagerDB.meta.lastModified = time()

    local uid = (GMGR.GetUID and GMGR.GetUID(name)) or (GMGR.FindUIDByName and GMGR.FindUIDByName(name)) or nil
    if GMGR.Comm_Broadcast then
        GMGR.Comm_Broadcast("ROSTER_RESERVE", {
            uid = uid, name = name, res = flag and 1 or 0,
            rv = rv, lm = GuildManagerDB.meta.lastModified
        })
    end
    if ns.RefreshAll then ns.RefreshAll() end
    return true
end

-- =========================
-- =====  iLvl (main)  =====
-- =========================

-- Lecture simple (nil si inconnu)
function GMGR.GetIlvl(name)
    if not name or name == "" then return nil end
    GuildManagerDB = GuildManagerDB or {}
    GuildManagerDB.players = GuildManagerDB.players or {}
    local p = GuildManagerDB.players[name]
    return p and tonumber(p.ilvl or nil) or nil
end

-- Application locale + signal UI (protégée)
local function _SetIlvlLocal(name, ilvl, ts, by)
    if not name or name == "" then return end
    GuildManagerDB = GuildManagerDB or {}
    GuildManagerDB.players = GuildManagerDB.players or {}
    -- ⚠️ Ne pas créer d'entrée : si le joueur n'est pas dans le roster (actif/réserve), on sort.
    local p = GuildManagerDB.players[name]
    if not p then return end

    local nowts   = tonumber(ts) or time()
    local prev_ts = tonumber(p.ilvlTs or 0) or 0
    if nowts >= prev_ts then
        p.ilvl     = math.floor(tonumber(ilvl) or 0)
        p.ilvlTs   = nowts
        p.ilvlAuth = tostring(by or "")
        if ns.Emit then ns.Emit("ilvl:changed", name) end
        if ns.RefreshAll then ns.RefreshAll() end
    end
end

-- Calcul & diffusion : uniquement si le perso connecté EST le main
function GMGR.UpdateOwnIlvlIfMain()
    if not (GMGR.IsConnectedMain and GMGR.IsConnectedMain()) then return end

    -- Throttle anti-spam
    local tnow = GetTimePreciseSec and GetTimePreciseSec() or (debugprofilestop and (debugprofilestop()/1000)) or 0
    GMGR._ilvlNextSendAt = GMGR._ilvlNextSendAt or 0
    if tnow < GMGR._ilvlNextSendAt then return end
    GMGR._ilvlNextSendAt = tnow + 5.0

    local name, realm = UnitFullName("player")
    local me = (name or "") .. "-" .. (realm or "")
    local equipped = nil
    if GetAverageItemLevel then
        local overall, equippedRaw = GetAverageItemLevel()
        equipped = equippedRaw or overall
    end
    if not equipped then return end

    -- 🚫 Stop si pas dans roster/réserve
    if not (GMGR.IsPlayerInRosterOrReserve and GMGR.IsPlayerInRosterOrReserve(me)) then
        return
    end

    local ilvl = math.max(0, math.floor((tonumber(equipped) or 0) + 0.5))
    local changed = (GMGR._lastOwnIlvl or -1) ~= ilvl
    GMGR._lastOwnIlvl = ilvl

    -- Stocke local + diffuse si variation
    local ts = time()
    _SetIlvlLocal(me, ilvl, ts, me)
    if changed and GMGR.BroadcastIlvlUpdate then
        GMGR.BroadcastIlvlUpdate(me, ilvl, ts, me)
    end
end


-- ➕ ======  CLÉ MYTHIQUE : stockage local + formatage + diffusion ======
-- Lecture formatée pour l'UI ("NomDuDonjon +17", avec +X en orange)
function GMGR.GetMKeyText(name)
    if not name or name == "" then return "" end
    GuildManagerDB = GuildManagerDB or {}
    GuildManagerDB.players = GuildManagerDB.players or {}
    local p = GuildManagerDB.players[name]
    if not p then return "" end
    local lvl = tonumber(p.mkeyLevel or 0) or 0
    if lvl <= 0 then return "" end

    local label = (p.mkeyName and p.mkeyName ~= "") and p.mkeyName or ""
    if (label == "" or label == "Clé") and tonumber(p.mkeyMapId or 0) > 0 then
        local nm = GMGR.ResolveMKeyMapName and GMGR.ResolveMKeyMapName(tonumber(p.mkeyMapId))
        if nm and nm ~= "" then label = nm end
    end
    if label == "" then label = "Clé" end

    -- ✨ Coloration orange du niveau
    local levelText = string.format("|cffffa500+%d|r", lvl)

    return string.format("%s %s", label, levelText)
end

-- Application locale (sans créer d’entrée ; timestamp dominant)
local function _SetMKeyLocal(name, mapId, level, mapName, ts, by)
    if not name or name == "" then return end
    GuildManagerDB = GuildManagerDB or {}
    GuildManagerDB.players = GuildManagerDB.players or {}
    local p = GuildManagerDB.players[name]
    if not p then return end

    local nowts   = tonumber(ts) or time()
    local prev_ts = tonumber(p.mkeyTs or 0) or 0
    if nowts >= prev_ts then
        p.mkeyMapId = tonumber(mapId) or 0
        p.mkeyLevel = math.max(0, tonumber(level) or 0)
        p.mkeyName  = tostring(mapName or "")
        p.mkeyTs    = nowts
        p.mkeyAuth  = tostring(by or "")
        if ns.Emit then ns.Emit("mkey:changed", name) end
        if ns.RefreshAll then ns.RefreshAll() end
    end
end

-- ➕ Résolution du nom de donjon depuis un mapId (avec cache)
GMGR._mkeyNameCache = GMGR._mkeyNameCache or {}
function GMGR.ResolveMKeyMapName(mapId)
    local mid = tonumber(mapId) or 0
    if mid <= 0 then return nil end
    local cached = GMGR._mkeyNameCache[mid]
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
        GMGR._mkeyNameCache[mid] = name
    end

    return name
end

-- ➕ Joueur autorisé à émettre ? (présent en actif OU réserve)
function GMGR.IsPlayerInRosterOrReserve(name)
    if not name or name == "" then return false end
    GuildManagerDB = GuildManagerDB or {}
    GuildManagerDB.players = GuildManagerDB.players or {}
    return GuildManagerDB.players[name] ~= nil
end

-- Lit la clé possédée (API M+ si dispo, sinon parsing sacs)
local function _ReadOwnedKeystone()
    local lvl, mid = 0, 0
    local src = "NONE"

    -- utilitaire pour extraire le nom lisible du donjon depuis le texte du lien
    local function _nameFromLinkText(link)
        if not link or link == "" then return nil end
        local inside = link:match("%[(.-)%]") or ""   -- texte entre crochets
        if inside == "" then return nil end
        -- enlève le préfixe éventuel "Clé mythique :" ou "Keystone:"
        local after = inside:match(":%s*(.+)") or inside
        -- supprime la partie "(+15)" ou "(15)" en fin de texte
        after = after:gsub("%s*%(%+?%d+%)%s*$", "")
        after = after:gsub("^%s+", ""):gsub("%s+$", "")
        return (after ~= "" and after) or nil
    end

    -- 1) API Blizzard (Retail 11.x)
    if C_MythicPlus then
        local okMid, vMid = pcall(C_MythicPlus.GetOwnedKeystoneChallengeMapID)
        local okLvl, vLvl = pcall(C_MythicPlus.GetOwnedKeystoneLevel)
        if okMid and type(vMid) == "number" then mid = vMid or 0 end
        if okLvl and type(vLvl) == "number" then lvl = vLvl or 0 end
        if (lvl > 0 and mid > 0) then src = "API" end
    end

    local mapName = ""

    -- 2) Nom depuis l’API ChallengeMode (source fiable)
    if mapName == "" and mid and mid > 0 and C_ChallengeMode and C_ChallengeMode.GetMapUIInfo then
        local okn, nm = pcall(C_ChallengeMode.GetMapUIInfo, mid)
        if okn and nm then
            mapName = type(nm) == "string" and nm or tostring(nm)
        end
    end

    -- 3) Dernier recours : résolveur basé sur mid
    if mapName == "" and mid and mid > 0 then
        local nm = GMGR.ResolveMKeyMapName and GMGR.ResolveMKeyMapName(mid)
        if nm and nm ~= "" then mapName = nm end
    end

    return mid or 0, lvl or 0, mapName or ""
end

-- ➕ Expose un lecteur public de la clé possédée (fallback si déjà défini ailleurs)
if not GMGR.ReadOwnedKeystone then
    function GMGR.ReadOwnedKeystone()
        return _ReadOwnedKeystone()
    end
end

-- ➕ Lecture immédiate de mon iLvl équipé (sans diffusion)
if not GMGR.ReadOwnEquippedIlvl then
    function GMGR.ReadOwnEquippedIlvl()
        local equipped
        if GetAverageItemLevel then
            local overall, eq = GetAverageItemLevel()
            equipped = eq or overall
        end
        if not equipped then return nil end
        return math.max(0, math.floor((tonumber(equipped) or 0) + 0.5))
    end
end

-- Calcul & diffusion de MA propre clé (uniquement si le perso connecté est le main)
function GMGR.UpdateOwnKeystoneIfMain()
    if not (GMGR.IsConnectedMain and GMGR.IsConnectedMain()) then return end

    -- Throttle anti-spam
    local tnow = (GetTimePreciseSec and GetTimePreciseSec()) or (debugprofilestop and (debugprofilestop()/1000)) or 0
    GMGR._mkeyNextSendAt = GMGR._mkeyNextSendAt or 0
    if tnow < GMGR._mkeyNextSendAt then return end
    GMGR._mkeyNextSendAt = tnow + 5.0

    -- Lecture robuste (API M+ -> fallback sacs)
    local mid, lvl, mapName = _ReadOwnedKeystone()

    -- ✅ Nom canonique (évite "Nom-" quand prealm est nil ; normalise le royaume)
    local function _MyFull()
        local n, r = UnitFullName and UnitFullName("player")
        if not n or n == "" then n = (UnitName and UnitName("player")) or "?" end
        local realm = r and r:gsub("%s+",""):gsub("'","")
        if (not realm or realm == "") then
            realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
            realm = realm and realm:gsub("%s+",""):gsub("'","") or ""
        end
        return (realm ~= "" and (n.."-"..realm)) or n
    end
    local me = _MyFull()
    if ns and ns.Util and ns.Util.NormalizeFull then me = ns.Util.NormalizeFull(me) end

    -- 🚫 Stop si pas dans roster/réserve (et ne crée **pas** d’entrée)
    if not (GMGR.IsPlayerInRosterOrReserve and GMGR.IsPlayerInRosterOrReserve(me)) then
        return
    end

    -- Complète le nom du donjon si absent (via résolveur dédié)
    if (not mapName or mapName == "" or mapName == "Clé") and mid and mid > 0 then
        local nm2 = GMGR.ResolveMKeyMapName and GMGR.ResolveMKeyMapName(mid)
        if nm2 and nm2 ~= "" then mapName = nm2 end
    end

    local changed = (GMGR._lastOwnMKeyId or -1) ~= (mid or 0) or (GMGR._lastOwnMKeyLvl or -1) ~= (lvl or 0)
    GMGR._lastOwnMKeyId  = mid or 0
    GMGR._lastOwnMKeyLvl = lvl or 0

    local ts = time()
    _SetMKeyLocal(me, mid or 0, lvl or 0, mapName or "", ts, me)
    if changed and GMGR.BroadcastMKeyUpdate then
        GMGR.BroadcastMKeyUpdate(me, mid or 0, lvl or 0, mapName or "", ts, me)
    end
end

-- =========================
-- ======  HISTORY    ======
-- =========================
function GMGR.AddHistorySession(total, perHead, participants, ctx)

    EnsureDB()
    GuildManagerDB.historyNextId = GuildManagerDB.historyNextId or 1

    local s = {
        ts = time(),
        total = math.floor(total or 0),
        perHead = math.floor(perHead or 0),
        count = #(participants or {}),
        participants = { unpack(participants or {}) },
        refunded = false,
        hid = GuildManagerDB.historyNextId, -- ➕ ID unique
    }
    GuildManagerDB.historyNextId = GuildManagerDB.historyNextId + 1

    if type(ctx) == "table" and ctx.lots then
        s.lots = ctx.lots
    end
    table.insert(GuildManagerDB.history, 1, s)

    -- Diffusion réseau (petit message) si GM
    if GMGR.IsMaster and GMGR.IsMaster() and GMGR.Comm_Broadcast then
        GuildManagerDB.meta = GuildManagerDB.meta or {}
        local rv = (GuildManagerDB.meta.rev or 0) + 1
        GuildManagerDB.meta.rev = rv
        GuildManagerDB.meta.lastModified = time()

        -- ➕ sérialise les lots pour l'ajout (liste de CSV "id,name,k,N,n,g")
        local Lraw = {}
        for _, li in ipairs(s.lots or {}) do
            if type(li) == "table" then
                local id   = tonumber(li.id or 0) or 0
                local name = tostring(li.name or ("Lot " .. tostring(id)))
                local k    = tonumber(li.k or 0) or 0
                local N    = tonumber(li.N or 1) or 1
                local n    = tonumber(li.n or 1) or 1
                local g    = tonumber(li.gold or 0) or 0
                Lraw[#Lraw+1] = table.concat({ id, name, k, N, n, g }, ",")
            end
        end

        GMGR.Comm_Broadcast("HIST_ADD", {
            ts = s.ts, total = s.total, per = s.perHead, cnt = s.count,
            r = s.refunded and 1 or 0, P = s.participants, L = Lraw, -- ➕
            rv = rv, lm = GuildManagerDB.meta.lastModified,
        })
    end
    if ns.Emit then ns.Emit("history:changed") end
end

function GMGR.GetHistory()
    EnsureDB()
    return GuildManagerDB.history
end

function GMGR.RefundSession(idx)
    EnsureDB()
    local s = GuildManagerDB.history[idx]
    if not s or s.refunded then return false end
    local per = tonumber(s.perHead) or 0
    local parts = s.participants or {}

    if GMGR.IsMaster and GMGR.IsMaster() and GMGR.GM_BroadcastBatch then
        local adjusts = {}
        for _, name in ipairs(parts) do adjusts[#adjusts+1] = { name = name, delta = per } end
        GMGR.GM_BroadcastBatch(adjusts, { reason = "REFUND", silent = true })
    else
        for _, name in ipairs(parts) do if GuildManagerDB.players[name] then GMGR.Credit(name, per) end end
    end

    s.refunded = true

    -- Diffusion du changement d'état si GM
    if GMGR.IsMaster and GMGR.IsMaster() and GMGR.Comm_Broadcast then
        GuildManagerDB.meta = GuildManagerDB.meta or {}
        local rv = (GuildManagerDB.meta.rev or 0) + 1
        GuildManagerDB.meta.rev = rv
        GuildManagerDB.meta.lastModified = time()
        GMGR.Comm_Broadcast("HIST_REFUND", { ts = s.ts, h = s.hid, rv = rv, lm = GuildManagerDB.meta.lastModified })
    end
    if ns.Emit then ns.Emit("history:changed") end
    return true
end

function GMGR.UnrefundSession(idx)
    EnsureDB()
    local s = GuildManagerDB.history[idx]
    if not s or not s.refunded then return false end
    local per = tonumber(s.perHead) or 0
    local parts = s.participants or {}

    if GMGR.IsMaster and GMGR.IsMaster() and GMGR.GM_BroadcastBatch then
        local adjusts = {}
        for _, name in ipairs(parts) do adjusts[#adjusts+1] = { name = name, delta = -per } end
        GMGR.GM_BroadcastBatch(adjusts, { reason = "REFUND", silent = true })
    else
        for _, name in ipairs(parts) do if GuildManagerDB.players[name] then GMGR.Debit(name, per) end end
    end

    s.refunded = false

    -- Diffusion du changement d'état si GM
    if GMGR.IsMaster and GMGR.IsMaster() and GMGR.Comm_Broadcast then
        GuildManagerDB.meta = GuildManagerDB.meta or {}
        local rv = (GuildManagerDB.meta.rev or 0) + 1
        GuildManagerDB.meta.rev = rv
        GuildManagerDB.meta.lastModified = time()
        GMGR.Comm_Broadcast("HIST_REFUND", { ts = s.ts, h = s.hid, r = 0, rv = rv, lm = GuildManagerDB.meta.lastModified })
    end
    if ns.Emit then ns.Emit("history:changed") end
    return true
end

function GMGR.DeleteHistory(idx)
    EnsureDB()
    local hist = GuildManagerDB.history or {}
    local s = hist[idx]; if not s then return false end
    local ts = s.ts
    table.remove(hist, idx)

    -- Diffusion de la suppression si GM
    if GMGR.IsMaster and GMGR.IsMaster() and GMGR.Comm_Broadcast then
        GuildManagerDB.meta = GuildManagerDB.meta or {}
        local rv = (GuildManagerDB.meta.rev or 0) + 1
        GuildManagerDB.meta.rev = rv
        GuildManagerDB.meta.lastModified = time()
        GMGR.Comm_Broadcast("HIST_DEL", { ts = ts, h = s.hid, rv = rv, lm = GuildManagerDB.meta.lastModified })
    end
    if ns.Emit then ns.Emit("history:changed") end
    return true
end

function GMGR.WipeAllData()
    -- Conserver la version uniquement pour le GM (joueurs : réinitialiser à 0)
    local isMaster = (GMGR.IsMaster and GMGR.IsMaster())
        or (IsInGuild and IsInGuild() and select(3, GetGuildInfo("player")) == 0)
        or false
    local oldRev     = (GuildManagerDB and GuildManagerDB.meta and GuildManagerDB.meta.rev) or 0
    local keepRev    = isMaster and oldRev or 0
    local keepMaster = (GuildManagerDB and GuildManagerDB.meta and GuildManagerDB.meta.master) or nil
    GuildManagerDB = {
        players  = {},
        history  = {},
        expenses = { recording = false, list = {}, nextId = 1 },
        lots     = { nextId = 1, list = {} },
        ids      = { counter=0, byName={}, byId={} },
        meta     = { lastModified=0, fullStamp=0, rev=keepRev, master=keepMaster },
        requests = {},
        debug    = {},
    }
end

-- Purge complète : DB + préférences UI
function GMGR.WipeAllSaved()
    -- Conserver la version uniquement pour le GM (joueurs : réinitialiser à 0)
    local isMaster = (GMGR.IsMaster and GMGR.IsMaster())
        or (IsInGuild and IsInGuild() and select(3, GetGuildInfo("player")) == 0)
        or false
    local oldRev     = (GuildManagerDB and GuildManagerDB.meta and GuildManagerDB.meta.rev) or 0
    local keepRev    = isMaster and oldRev or 0
    local keepMaster = (GuildManagerDB and GuildManagerDB.meta and GuildManagerDB.meta.master) or nil
    GuildManagerDB = {
        players  = {},
        history  = {},
        expenses = { recording = false, list = {}, nextId = 1 },
        lots     = { nextId = 1, list = {} },
        ids      = { counter=0, byName={}, byId={} },
        meta     = { lastModified=0, fullStamp=0, rev=keepRev, master=keepMaster },
        requests = {},
        debug    = {},
    }
    GuildManagerUI = { point="CENTER", relTo=nil, relPoint="CENTER", x=0, y=0, width=1160, height=680, minimap = { hide=false, angle=215 } }
end

function GMGR.GetRev()
    GuildManagerDB = GuildManagerDB or {}
    GuildManagerDB.meta = GuildManagerDB.meta or {}
    return GuildManagerDB.meta.rev or 0
end

function GMGR.IncRev()
    GuildManagerDB = GuildManagerDB or {}
    GuildManagerDB.meta = GuildManagerDB.meta or {}
    GuildManagerDB.meta.rev = (GuildManagerDB.meta.rev or 0) + 1
    return GuildManagerDB.meta.rev
end

-- =========================
-- ======   LOTS      ======
-- =========================
-- Lots consommables : 1 session (100%) ou multi-sessions (1/N par clôture).
-- Le contenu d'un lot est figé à la création. Les éléments proviennent des
-- "Ressources libres" (dépenses non rattachées).

local function _ensureLots()
    GMGR._EnsureDB()
    GuildManagerDB.lots     = GuildManagerDB.lots     or { nextId = 1, list = {} }
    GuildManagerDB.expenses = GuildManagerDB.expenses or { recording=false, list = {}, nextId = 1 }
end

function GMGR.GetLots()
    _ensureLots()
    return GuildManagerDB.lots.list
end

function GMGR.Lot_GetById(id)
    _ensureLots()
    for _, l in ipairs(GuildManagerDB.lots.list or {}) do
        if l.id == id then return l end
    end
end

function GMGR.Lot_Status(lot)
    if not lot then return "?" end
    local used = tonumber(lot.used or 0) or 0
    local N    = tonumber(lot.sessions or 1) or 1
    if used <= 0 then return "A_UTILISER" end
    if used < N  then return "EN_COURS"  end
    return "EPU"
end

function GMGR.Lot_IsSelectable(lot)
    return lot and (not lot.__pendingConsume) and GMGR.Lot_Status(lot) ~= "EPU"
end

-- Coût par utilisation (ex-ShareGold) en or entiers — pas de PA/PC.
function GMGR.Lot_ShareGold(lot)  -- compat : on conserve le nom
    local totalC = tonumber(lot.totalCopper or lot.copper or 0) or 0
    local N      = tonumber(lot.sessions or 1) or 1
    return math.floor( math.floor(totalC / 10000) / N )
end

-- ➕ Utilitaires "charges"
function GMGR.Lot_UseCostGold(lot)  -- alias explicite
    return GMGR.Lot_ShareGold(lot)
end

function GMGR.Lot_Remaining(lot)   -- utilisations restantes
    local used = tonumber(lot.used or 0) or 0
    local N    = tonumber(lot.sessions or 1) or 1
    return math.max(0, N - used)
end

-- Création : fige le contenu depuis une liste d'index ABSOLUS de GuildManagerDB.expenses.list
-- isMulti = true/false ; sessions = N si multi (>=1)
function GMGR.Lot_Create(name, isMulti, sessions, absIdxs)
    _ensureLots()
    name = name or "Lot"
    local e = GuildManagerDB.expenses
    local L = GuildManagerDB.lots
    local id = L.nextId or 1

    local itemIds, total = {}, 0
    for _, abs in ipairs(absIdxs or {}) do
        local it = e.list[abs]
        if it and not it.lotId then
            table.insert(itemIds, it.id or 0)
            total = total + (tonumber(it.copper) or 0)
            it.lotId = id
        end
    end

    local l = { id = id, name = name, sessions = isMulti and (tonumber(sessions) or 2) or 1, used = 0, totalCopper = total, itemIds = itemIds }
    table.insert(L.list, l); L.nextId = id + 1
    if ns.Emit then ns.Emit("lots:changed") end

    -- ➕ Diffusion GM
    if GMGR.BroadcastLotCreate and GMGR.IsMaster and GMGR.IsMaster() then GMGR.BroadcastLotCreate(l) end
    return l
end

-- Suppression possible uniquement si jamais utilisé (rend les ressources libres)
function GMGR.Lot_Delete(id)
    _ensureLots()
    local L = GuildManagerDB.lots
    local list = L.list or {}
    local idx = nil
    for i, l in ipairs(list) do if l.id == id then idx = i break end end
    if not idx then return false end
    table.remove(list, idx)
    for _, it in ipairs(GuildManagerDB.expenses.list or {}) do if it.lotId == id then it.lotId = nil end end
    if ns.Emit then ns.Emit("lots:changed") end
    if ns.RefreshActive then ns.RefreshActive() end -- ✅ disparition immédiate à l’écran

    -- ➕ Diffusion GM
    if GMGR.BroadcastLotDelete and GMGR.IsMaster and GMGR.IsMaster() then GMGR.BroadcastLotDelete(id) end
    return true
end

function GMGR.Lot_ListSelectable()
    _ensureLots()
    local out = {}
    for _, l in ipairs(GuildManagerDB.lots.list or {}) do
        if GMGR.Lot_IsSelectable(l) then out[#out+1] = l end
    end
    return out
end

function GMGR.Lot_Consume(id)
    _ensureLots()
    local l = GMGR.Lot_GetById(id); if not l then return false end
    local N = tonumber(l.sessions or 1) or 1
    local u = tonumber(l.used or 0) or 0
    l.used = math.min(u + 1, N)  -- ne décrémente que d'1, borné au max
    if ns.RefreshAll then ns.RefreshAll() end
    return true
end

function GMGR.Lots_ConsumeMany(ids)
    _ensureLots()
    ids = ids or {}

    local isMaster = GMGR.IsMaster and GMGR.IsMaster()
    if isMaster then
        -- GM : applique directement la consommation (évite le blocage __pendingConsume)
        local L = GuildManagerDB.lots
        for _, id in ipairs(ids) do
            for _, l in ipairs(L.list or {}) do
                if l.id == id then
                    local u = tonumber(l.used or 0) or 0
                    local N = tonumber(l.sessions or 1) or 1
                    l.used = math.min(u + 1, N) -- ✅ bornage sécurité
                end
            end
        end
        if ns.Emit then ns.Emit("lots:changed") end
        if ns.RefreshActive then ns.RefreshActive() end

        -- Diffusion : les autres clients (et GM aussi) recevront LOT_CONSUME,
        -- mais côté GM on a déjà appliqué => aucun lot bloqué en "pending".
        if GMGR.BroadcastLotsConsume then GMGR.BroadcastLotsConsume(ids) end

    else
        -- Client : applique localement sans diffusion (borné).
        local L = GuildManagerDB.lots
        for _, id in ipairs(ids) do
            for _, l in ipairs(L.list or {}) do
                if l.id == id then
                    local u = tonumber(l.used or 0) or 0
                    local N = tonumber(l.sessions or 1) or 1
                    l.used = math.min(u + 1, N) -- ✅ bornage sécurité
                end
            end
        end
        if ns.Emit then ns.Emit("lots:changed") end
    end

end

function GMGR.Lots_ComputeGoldTotal(ids)
    local g = 0
    for _, id in ipairs(ids or {}) do
        local l = GMGR.Lot_GetById(id)
        if l and GMGR.Lot_IsSelectable(l) then g = g + GMGR.Lot_ShareGold(l) end
    end
    return g
end

-- =========================
-- ===== Purges (GM)  ======
-- =========================

-- Incrémente / réinitialise la révision selon le rôle
local function _BumpRevisionLocal()
    EnsureDB()
    local isMaster = (GMGR.IsMaster and GMGR.IsMaster()) or false
    local rv = tonumber(GuildManagerDB.meta.rev or 0) or 0
    GuildManagerDB.meta.rev = isMaster and (rv + 1) or 0
    GuildManagerDB.meta.lastModified = time()
end

-- Supprime tous les lots épuisés + tous leurs objets associés
function GMGR.PurgeLotsAndItemsExhausted()
    EnsureDB(); _ensureLots()
    local L = GuildManagerDB.lots
    local E = GuildManagerDB.expenses

    local purgeLots   = {}
    local purgeItems  = {}

    for _, l in ipairs(L.list or {}) do
        if (GMGR.Lot_Status and GMGR.Lot_Status(l) == "EPU") then
            purgeLots[l.id] = true
            for _, eid in ipairs(l.itemIds or {}) do purgeItems[eid] = true end
        end
    end

    -- Filtre des dépenses (objets)
    local newE, removedItems = {}, 0
    for _, it in ipairs(E.list or {}) do
        local id = it.id
        local kill = (purgeItems[id] == true) or (it.lotId and purgeLots[it.lotId])
        if kill then
            removedItems = removedItems + 1
        else
            newE[#newE+1] = it
        end
    end
    E.list = newE

    -- Filtre des lots
    local newL, removedLots = {}, 0
    for _, l in ipairs(L.list or {}) do
        if purgeLots[l.id] then
            removedLots = removedLots + 1
        else
            newL[#newL+1] = l
        end
    end
    L.list = newL

    if ns.Emit then ns.Emit("expenses:changed") end
    if ns.Emit then ns.Emit("lots:changed") end
    if ns.RefreshAll then ns.RefreshAll() end

    _BumpRevisionLocal()
    return removedLots, removedItems
end

-- Supprime absolument tous les lots + tous les objets
function GMGR.PurgeAllResources()
    EnsureDB(); _ensureLots()
    local L = GuildManagerDB.lots
    local E = GuildManagerDB.expenses

    local removedLots  = #(L.list or {})
    local removedItems = #(E.list or {})

    L.list, E.list = {}, {}
    L.nextId, E.nextId = 1, 1

    if ns.Emit then ns.Emit("expenses:changed") end
    if ns.Emit then ns.Emit("lots:changed") end
    if ns.RefreshAll then ns.RefreshAll() end

    _BumpRevisionLocal()
    return removedLots, removedItems
end

-- =========================
-- ===== Window Save  ======
-- =========================

function GMGR.GetSavedWindow() EnsureDB(); return GuildManagerUI end
function GMGR.SaveWindow(point, relTo, relPoint, x, y, w, h)
    GuildManagerUI = GuildManagerUI or {}
    GuildManagerUI.point    = point
    GuildManagerUI.relTo    = relTo
    GuildManagerUI.relPoint = relPoint
    GuildManagerUI.x        = x
    GuildManagerUI.y        = y
    GuildManagerUI.width    = w
    GuildManagerUI.height   = h
end

-- =========================
-- ==== Demandes (GM) ======
-- =========================
function GMGR.GetRequests()
    EnsureDB()
    GuildManagerDB.requests = GuildManagerDB.requests or {}
    return GuildManagerDB.requests
end

-- Expose les demandes pour l’UI (badge/onglet)
function GMGR.GetRequests()
    EnsureDB()
    GuildManagerDB.requests = GuildManagerDB.requests or {}
    return GuildManagerDB.requests
end

