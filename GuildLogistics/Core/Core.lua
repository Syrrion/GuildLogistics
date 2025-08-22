local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
local GLOG = ns.GLOG

-- Icône centrale de l’addon (réutilisable partout, y compris minimap)
GLOG.ICON_TEXTURE = GLOG.ICON_TEXTURE or "Interface\\AddOns\\GuildLogistics\\Ressources\\Media\\LogoAddonWoW128.tga"

function GLOG.GetAddonIconTexture(size)
    local base = "Interface\\AddOns\\GuildLogistics\\Ressources\\Media\\LogoAddonWoW"
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
    -- ➕ 1) Bascule SV « par personnage » + migration one-shot depuis l’ancienne base compte
    GuildLogisticsDB_Char = GuildLogisticsDB_Char or {}
    GuildLogisticsUI_Char = GuildLogisticsUI_Char or {}

    -- Migration DB (compte -> personnage) si pas encore faite sur ce perso
    if not GuildLogisticsDB_Char._migr_perchar_1 then
        if type(GuildLogisticsDB) == "table" and next(GuildLogisticsDB) ~= nil then
            -- Copie superficielle suffisante ici (les sous-tables sont réutilisées telles quelles)
            for k, v in pairs(GuildLogisticsDB) do
                GuildLogisticsDB_Char[k] = v
            end
            GuildLogisticsDB_Char.meta = GuildLogisticsDB_Char.meta or {}
            GuildLogisticsDB_Char.meta.migrFromAccount = true
            GuildLogisticsDB_Char.meta.migrAt = (time and time()) or 0
        end
        GuildLogisticsDB_Char._migr_perchar_1 = true
    end

    -- Migration UI (compte -> personnage) si pas encore faite
    if not GuildLogisticsUI_Char._migr_perchar_1 then
        if type(GuildLogisticsUI) == "table" and next(GuildLogisticsUI) ~= nil then
            for k, v in pairs(GuildLogisticsUI) do
                GuildLogisticsUI_Char[k] = v
            end
        end
        GuildLogisticsUI_Char._migr_perchar_1 = true
    end

    -- ➕ 2) Alias runtime : le code existant continue d'utiliser GuildLogisticsDB/UI
    GuildLogisticsDB = GuildLogisticsDB_Char
    GuildLogisticsUI = GuildLogisticsUI_Char

    -- ➕ 3) Initialisation habituelle (désormais sur la base « par personnage »)
    GuildLogisticsDB = GuildLogisticsDB or {
        players = {},
        history = {},
        expenses = { recording = false, list = {}, nextId = 1 },
        lots     = { nextId = 1, list = {} },
        ids = { counter=0, byName={}, byId={} },
        meta = { lastModified=0, fullStamp=0, rev=0, master=nil }, -- + rev
        requests = {},
        historyNextId = 1,  -- ➕ compteur HID
        debug = {},
        aliases = {},       -- ➕ Alias par joueur (clé = main normalisé)
    }
    GuildLogisticsDB.aliases = GuildLogisticsDB.aliases or {}

    GuildLogisticsUI = GuildLogisticsUI or {
        point="CENTER", relTo=nil, relPoint="CENTER", x=0, y=0, width=1160, height=680,
        minimap = { hide = false, angle = 215 },
    }
    GuildLogisticsUI.minimap = GuildLogisticsUI.minimap or { hide=false, angle=215 }
    if GuildLogisticsUI.minimap.angle == nil then GuildLogisticsUI.minimap.angle = 215 end

    -- ✏️ Par défaut : debug/autoOpen
    if GuildLogisticsUI.debugEnabled == nil then GuildLogisticsUI.debugEnabled = true end
    if GuildLogisticsUI.autoOpen   == nil then GuildLogisticsUI.autoOpen   = true  end

    -- ➕ 4) Marqueur d’identification du profil (utile en debug et pour éviter les confusions)
    GuildLogisticsDB.meta = GuildLogisticsDB.meta or {}
    do
        local n, r = (UnitFullName and UnitFullName("player"))
        local gName = (GetGuildInfo and GetGuildInfo("player")) or nil
        GuildLogisticsDB.meta.character = (n and r) and (n.."-"..r) or (n or "?")
        GuildLogisticsDB.meta.guildName = gName
    end
end


GLOG._EnsureDB = EnsureDB

-- ➕ API : état du débug
function GLOG.IsDebugEnabled()
    EnsureDB()
    return GuildLogisticsUI.debugEnabled ~= false
end

-- =========================
-- ======  PLAYERS    ======
-- =========================
local function GetOrCreatePlayer(name)
    EnsureDB()
    if not name or name == "" then return { credit=0, debit=0, reserved=true } end
    local p = GuildLogisticsDB.players[name]
    if not p then
        -- ⛑️ Création implicite = en "Réserve" par défaut
        p = { credit = 0, debit = 0, reserved = true }
        GuildLogisticsDB.players[name] = p
    else
        if p.reserved == nil then p.reserved = true end -- compat données anciennes
    end
    return p
end

-- Alias rétro-compatible si jamais du code appelle IsReserve()
GLOG.IsReserve = GLOG.IsReserved

function GLOG.GetPlayersArray()
    EnsureDB()
    local out = {}
    for name, p in pairs(GuildLogisticsDB.players) do
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
function GLOG.GetPlayersArrayActive()
    EnsureDB()
    local out, agg = {}, {}

    -- 1) Déterminer les MAINS "actifs" (au moins un perso non réservé/bench)
    local activeSet = {}  -- [mk] = displayName
    for name, p in pairs(GuildLogisticsDB.players or {}) do
        local isRes = (GLOG.IsReserved and GLOG.IsReserved(name)) or false
        if not isRes then
            local main = (GLOG.GetMainOf and GLOG.GetMainOf(name)) or name
            local mk   = (GLOG.NormName and GLOG.NormName(main)) or tostring(main):lower()
            if mk and mk ~= "" then
                local display = (GLOG.ResolveFullName and GLOG.ResolveFullName(main)) or main
                activeSet[mk] = display
            end
        end
    end

    -- 2) Agréger les crédits/débits de TOUS les persos appartenant à ces mains actifs
    for name, p in pairs(GuildLogisticsDB.players or {}) do
        local main = (GLOG.GetMainOf and GLOG.GetMainOf(name)) or name
        local mk   = (GLOG.NormName and GLOG.NormName(main)) or tostring(main):lower()
        local display = activeSet[mk]
        if display then
            local b = agg[mk]
            if not b then
                b = { name = display, credit = 0, debit = 0, reserved = false }
                agg[mk] = b
            end
            b.credit = (b.credit or 0) + (tonumber(p.credit) or 0)
            b.debit  = (b.debit  or 0) + (tonumber(p.debit)  or 0)
        end
    end

    -- 3) Normaliser la sortie
    for _, v in pairs(agg) do
        v.solde = (tonumber(v.credit) or 0) - (tonumber(v.debit) or 0)
        out[#out+1] = v
    end

    table.sort(out, function(a, b) return (a.name or ""):lower() < (b.name or ""):lower() end)
    return out
end

-- opts (optionnel) :
--    { showHidden = boolean, cutoffDays = number }
--    - showHidden = true  -> conserve tout (comportement historique)
--    - showHidden = false -> masque inactifs >= cutoffDays ET solde == 0
function GLOG.GetPlayersArrayReserve(opts)
    EnsureDB()
    local out, agg = {}, {}

    -- Ensemble des MAINS déjà ACTIFS (au moins un perso non réservé)
    local activeSet = {}
    do
        local arr = (GLOG.GetPlayersArrayActive and GLOG.GetPlayersArrayActive()) or {}
        for _, r in ipairs(arr) do
            local main = (GLOG.GetMainOf and GLOG.GetMainOf(r.name)) or r.name
            local mk   = (GLOG.NormName and GLOG.NormName(main)) or tostring(main):lower()
            if mk and mk ~= "" then activeSet[mk] = true end
        end
    end

    -- Regroupe par main (clé normalisée), ignore ceux déjà actifs
    local function ensureBucket(mk, display)
        if not mk or mk == "" then return nil end
        if activeSet[mk] then return nil end
        local b = agg[mk]
        if not b then
            b = { name = display or mk, credit = 0, debit = 0, reserved = true }
            agg[mk] = b
        elseif display and (b.name == "" or b.name == mk) then
            b.name = display
        end
        return b
    end

    -- 1) BDD locale "réserve" → agrégation par main
    for name, p in pairs(GuildLogisticsDB.players or {}) do
        if p and ((GLOG.IsReserved and GLOG.IsReserved(name)) or p.reserved) then
            local main = (GLOG.GetMainOf and GLOG.GetMainOf(name)) or name
            local mk   = (GLOG.NormName and GLOG.NormName(main)) or tostring(main):lower()
            if mk and not activeSet[mk] then
                local display = (GLOG.ResolveFullName and GLOG.ResolveFullName(main)) or main
                local b = ensureBucket(mk, display)
                if b then
                    b.credit = (b.credit or 0) + (tonumber(p.credit) or 0)
                    b.debit  = (b.debit  or 0) + (tonumber(p.debit)  or 0)
                end
            end
        end
    end

    -- 2) Ajoute les mains guilde non actifs localement
    do
        local mainsAgg = (GLOG.GetGuildMainsAggregatedCached and GLOG.GetGuildMainsAggregatedCached()) or {}
        for _, e in ipairs(mainsAgg) do
            local mk = e.key or (GLOG.NormName and GLOG.NormName(e.main)) or nil
            if mk and not activeSet[mk] then
                local display = (GLOG.ResolveFullName and GLOG.ResolveFullName(e.main)) or e.main
                ensureBucket(mk, display)
            end
        end
    end

    -- Sortie normalisée
    for _, v in pairs(agg) do
        v.solde = (tonumber(v.credit) or 0) - (tonumber(v.debit) or 0)
        out[#out+1] = v
    end

    table.sort(out, function(a, b) return (a.name or ""):lower() < (b.name or ""):lower() end)

    -- ➕ Filtrage inactifs (>= cutoffDays) ET solde == 0, si demandé
    local showHidden = (type(opts) == "table") and (opts.showHidden == true)
    if not showHidden then
        local cutoff = (type(opts) == "table" and tonumber(opts.cutoffDays)) or 30
        local filtered = {}
        for _, v in ipairs(out) do
            local mk    = (GLOG.NormName and GLOG.NormName(v.name)) or nil
            local solde = tonumber(v.solde) or 0
            local days  = (GLOG.GetMainLastSeenDays and GLOG.GetMainLastSeenDays(mk)) or 9999
            if not (solde == 0 and days >= cutoff) then
                filtered[#filtered+1] = v
            end
        end
        out = filtered
    end

    return out
end

function GLOG.AddPlayer(name)
    if not name or name == "" then return end

    -- Normalise le nom : si aucun suffixe de royaume n’est fourni,
    -- tenter d’abord de résoudre via la guilde ; sinon suffixer avec "-Externe" localisé.
    local raw = tostring(name or "")
    if not raw:find("%-") then
        local resolved = (GLOG.ResolveFullName and GLOG.ResolveFullName(raw)) or raw
        if resolved and resolved:find("%-") then
            name = resolved
        else
            local ext = (ns and ns.Tr and ns.Tr("realm_external")) or "Externe"
            name = raw .. "-" .. ext
        end
    else
        name = raw
    end

    -- Crée l’entrée si besoin (par défaut en Réserve)
    GetOrCreatePlayer(name)

    -- ⚑ N’activer automatiquement que si le joueur appartient à la guilde
    local inGuild = (GLOG.IsGuildCharacter and GLOG.IsGuildCharacter(name)) or false
    if inGuild and GLOG.GM_SetReserved and GLOG.IsMaster and GLOG.IsMaster() then
        GLOG.GM_SetReserved(name, false) -- bascule en "Actif" et broadcast le statut
    end

    -- UID & upsert réseau
    if GLOG.GetOrAssignUID then GLOG.GetOrAssignUID(name) end
    if GLOG.BroadcastRosterUpsert and GLOG.IsMaster and GLOG.IsMaster() then
        GLOG.BroadcastRosterUpsert(name)
    end
    return true
end

function GLOG.RemovePlayer(name)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then
        UIErrorsFrame:AddMessage("|cffff6060[GLOG]|r Suppression du roster réservée au GM.", 1, 0.4, 0.4)
        return false
    end
    GuildLogisticsDB = GuildLogisticsDB or {}
    local p = GuildLogisticsDB.players or {}
    if p[name] then p[name] = nil end
    -- Optionnel: retirer l'UID mappé
    if GuildLogisticsDB.ids and GuildLogisticsDB.ids.byName then
        local uid = GuildLogisticsDB.ids.byName[name]
        if uid then
            GuildLogisticsDB.ids.byName[name] = nil
            if GuildLogisticsDB.ids.byId then GuildLogisticsDB.ids.byId[uid] = nil end
        end
    end
    if ns.RefreshAll then ns.RefreshAll() end
    return true
end


function GLOG.HasPlayer(name)
    EnsureDB()
    if not name or name == "" then return false end
    return GuildLogisticsDB.players[name] ~= nil
end

-- ➕ Statut "en réserve" (alias bench pris en charge)
function GLOG.IsReserve(name)
    EnsureDB()
    if not name or name == "" then return false end
    local p = GuildLogisticsDB.players[name]
    return (p and ((p.reserve == true) or (p.bench == true))) or false
end

function GLOG.Credit(name, amount)
    EnsureDB()
    if not name or name == "" then return end
    GuildLogisticsDB.players = GuildLogisticsDB.players or {}
    local existed = not not GuildLogisticsDB.players[name]

    local p = GetOrCreatePlayer(name)
    local a = math.floor(tonumber(amount) or 0)
    p.credit = (p.credit or 0) + a

    -- Premier mouvement d’or => apparition en BDD et flag "réserve" par défaut
    if not existed then p.reserved = true end
end

function GLOG.Debit(name, amount)
    EnsureDB()
    if not name or name == "" then return end
    GuildLogisticsDB.players = GuildLogisticsDB.players or {}
    local existed = not not GuildLogisticsDB.players[name]

    local p = GetOrCreatePlayer(name)
    local a = math.floor(tonumber(amount) or 0)
    p.debit = (p.debit or 0) + a

    -- Premier mouvement d’or => apparition en BDD et flag "réserve" par défaut
    if not existed then p.reserved = true end
end

function GLOG.GetSolde(name)
    local p = GetOrCreatePlayer(name)
    return (p.credit or 0) - (p.debit or 0)
end

function GLOG.SamePlayer(a, b)
    if not a or not b then return false end
    -- Comparaison stricte sur le nom complet (insensible à la casse)
    return string.lower(tostring(a)) == string.lower(tostring(b))
end


-- ➕ Normalisation des clés joueurs (merge "Nom" et "Nom-Realm", dédoublonne les realms répétés)
function GLOG.NormalizePlayerKeys()
    if not GuildLogisticsDB then return end
    GuildLogisticsDB.players = GuildLogisticsDB.players or {}
    GuildLogisticsDB.uids    = GuildLogisticsDB.uids    or {}

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
    for name, rec in pairs(GuildLogisticsDB.players) do
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
    GuildLogisticsDB.players = rebuilt

    -- 2) Normalise aussi la table des UIDs -> noms
    local newUIDs = {}
    for uid, n in pairs(GuildLogisticsDB.uids) do
        local norm = (NormalizeFull and NormalizeFull(n)) or n
        newUIDs[tostring(uid)] = dedupRealm(norm)
    end
    GuildLogisticsDB.uids = newUIDs
end

-- Ajuste directement le solde d’un joueur : delta > 0 => ajoute de l’or, delta < 0 => retire de l’or
function GLOG.AdjustSolde(name, delta)
    local d = math.floor(tonumber(delta) or 0)
    if d == 0 then return GLOG.GetSolde(name) end
    if d > 0 then GLOG.Credit(name, d) else GLOG.Debit(name, -d) end
    return GLOG.GetSolde(name)
end

-- Marquer la modif + broadcast par le GM depuis une seule API dédiée
function GLOG.GM_AdjustAndBroadcast(name, delta)
    if GLOG.GM_ApplyAndBroadcast then GLOG.GM_ApplyAndBroadcast(name, delta) end
end

-- Helpers conviviaux
function GLOG.AddGold(name, amount)
    return GLOG.AdjustSolde(name, math.floor(tonumber(amount) or 0))
end

function GLOG.RemoveGold(name, amount)
    return GLOG.AdjustSolde(name, -math.floor(tonumber(amount) or 0))
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

function GLOG.EnsureRosterLocal(name)
    if not name or name == "" then return end
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.players = GuildLogisticsDB.players or {}
    local created = false
    if not GuildLogisticsDB.players[name] then
        -- ⛑️ Toute matérialisation locale = Réserve par défaut
        GuildLogisticsDB.players[name] = { credit = 0, debit = 0, reserved = true }
        created = true
    else
        if GuildLogisticsDB.players[name].reserved == nil then
            GuildLogisticsDB.players[name].reserved = true
        end
    end
    if created and ns.Emit then ns.Emit("roster:upsert", name) end
end

function GLOG.RemovePlayerLocal(name, silent)
    if not name or name=="" then return false end
    GuildLogisticsDB = GuildLogisticsDB or {}
    local p = GuildLogisticsDB.players or {}
    local existed = not not p[name]
    if p[name] then p[name] = nil end

    -- ancien mapping (legacy)
    if GuildLogisticsDB.ids and GuildLogisticsDB.ids.byName then
        local _uid = GuildLogisticsDB.ids.byName[name]
        if _uid then
            GuildLogisticsDB.ids.byName[name] = nil
            if GuildLogisticsDB.ids.byId then GuildLogisticsDB.ids.byId[_uid] = nil end
        end
    end

    -- purge aussi la table des UID actifs
    if GuildLogisticsDB.uids then
        local uid = nil
        if GLOG.FindUIDByName then
            uid = GLOG.FindUIDByName(name)
        elseif ns and ns.Util and ns.Util.FindUIDByName then
            uid = ns.Util.FindUIDByName(name)
        end
        if not uid then
            for k,v in pairs(GuildLogisticsDB.uids) do if v == name then uid = k break end end
        end
        if uid then GuildLogisticsDB.uids[uid] = nil end
    end

    if existed then ns.Emit("roster:removed", name) end
    if not silent and ns.RefreshAll then ns.RefreshAll() end
    return true
end

-- Suppression orchestrée : réservée au GM + broadcast
-- Remplace la version précédente de RemovePlayer si déjà présente
function GLOG.RemovePlayer(name)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then
        UIErrorsFrame:AddMessage("|cffff6060[GLOG]|r Suppression du roster réservée au GM.", 1, 0.4, 0.4)
        return false
    end
    if not name or name=="" then return false end

    local uid = GLOG.GetUID and GLOG.GetUID(name) or nil

    -- Applique localement (GM)
    GLOG.RemovePlayerLocal(name, true)

    -- Incrémente la révision et horodate pour les clients qui filtrent sur rv/lm
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.meta = GuildLogisticsDB.meta or {}
    local rv = (GuildLogisticsDB.meta.rev or 0) + 1
    GuildLogisticsDB.meta.rev = rv
    GuildLogisticsDB.meta.lastModified = time()

    -- Diffuse la suppression à toute la guilde avec rv/lm
    if GLOG.Comm_Broadcast then
        GLOG.Comm_Broadcast("ROSTER_REMOVE", {
            uid = uid,
            name = name,
            rv  = rv,
            lm  = GuildLogisticsDB.meta.lastModified,
        })
    end

    if ns.RefreshAll then ns.RefreshAll() end
    return true
end

-- IsReserved tolérant les anciens champs (reserved / reserve / bench / status texte)
function GLOG.IsReserved(name)
    GuildLogisticsDB = GuildLogisticsDB or {}
    local p = GuildLogisticsDB.players and GuildLogisticsDB.players[name]
    if not p then return false end

    local v = p.reserved or p.reserve or p.bench
            or ((type(p.status)=="string") and (p.status:upper()=="RESERVE" or p.status:upper()=="RESERVED"))

    if type(v) == "boolean" then return v end
    if type(v) == "number"  then return v ~= 0 end
    if type(v) == "string"  then return v:lower() ~= "false" and v ~= "" end
    return false
end

-- Alias rétro-compat
GLOG.IsReserve = GLOG.IsReserved

local function _SetReservedLocal(name, flag)
    local p = GetOrCreatePlayer(name)
    local prev = not not p.reserved
    p.reserved = not not flag
    if prev ~= p.reserved and ns.Emit then ns.Emit("roster:reserve", name, p.reserved) end
end

function GLOG.GM_SetReserved(name, flag)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then
        if UIErrorsFrame then
            UIErrorsFrame:AddMessage("|cffff6060[GLOG]|r Changement d’attribution réservé au GM.", 1, .4, .4)
        end
        return false
    end
    if not name or name=="" then return false end

    _SetReservedLocal(name, flag)

    GuildLogisticsDB.meta = GuildLogisticsDB.meta or {}
    local rv = (GuildLogisticsDB.meta.rev or 0) + 1
    GuildLogisticsDB.meta.rev = rv
    GuildLogisticsDB.meta.lastModified = time()

    local uid = (GLOG.GetUID and GLOG.GetUID(name)) or (GLOG.FindUIDByName and GLOG.FindUIDByName(name)) or nil
    local alias = (GLOG.GetAliasFor and GLOG.GetAliasFor(name)) or nil
    if GLOG.Comm_Broadcast then
        GLOG.Comm_Broadcast("ROSTER_RESERVE", {
            uid = uid, name = name, res = flag and 1 or 0,
            alias = alias,                                        -- ➕ transmettre l’alias
            rv = rv, lm = GuildLogisticsDB.meta.lastModified
        })
    end
    if ns.RefreshAll then ns.RefreshAll() end
    return true
end

-- =========================
-- =====  iLvl (main)  =====
-- =========================

-- Lecture simple (nil si inconnu)
function GLOG.GetIlvl(name)
    if not name or name == "" then return nil end
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.players = GuildLogisticsDB.players or {}
    local p = GuildLogisticsDB.players[name]
    return p and tonumber(p.ilvl or nil) or nil
end

function GLOG.GetIlvlMax(name)
    if not name or name == "" then return nil end
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.players = GuildLogisticsDB.players or {}
    local p = GuildLogisticsDB.players[name]
    return p and tonumber(p.ilvlMax or nil) or nil
end

-- Application locale + signal UI (protégée)
local function _SetIlvlLocal(name, ilvl, ts, by, ilvlMax)
    if not name or name == "" then return end
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.players = GuildLogisticsDB.players or {}
    -- ⚠️ Ne pas créer d'entrée : si le joueur n'est pas dans le roster (actif/réserve), on sort.
    local p = GuildLogisticsDB.players[name]
    if not p then return end

    local nowts   = tonumber(ts) or time()
    local prev_ts = tonumber(p.ilvlTs or 0) or 0
    if nowts >= prev_ts then
        p.ilvl     = math.floor(tonumber(ilvl) or 0)
        if ilvlMax ~= nil then
            p.ilvlMax   = math.floor(tonumber(ilvlMax) or 0)
            p.ilvlMaxTs = nowts
        end
        p.ilvlTs   = nowts
        p.ilvlAuth = tostring(by or "")
        if ns.Emit then ns.Emit("ilvl:changed", name) end
        if ns.RefreshAll then ns.RefreshAll() end
    end
end

-- Déclarations anticipées pour les setters locaux utilisés ci-dessous
-- (évite qu'ils soient vus comme des globals nil à la compilation)
local _SetMKeyLocal
local _SetMPlusScoreLocal

-- ✨ Fusion : calcule iLvl (équipé + max) + Clé M+ et envoie un UNIQUE STATUS_UPDATE si changement
function GLOG.UpdateOwnStatusIfMain()

    if not (GLOG.IsConnectedMain and GLOG.IsConnectedMain()) then return end

    -- Throttle anti-spam (fusionné)
    local nowp = (GetTimePreciseSec and GetTimePreciseSec()) or (debugprofilestop and (debugprofilestop()/1000)) or 0
    GLOG._statusNextSendAt = GLOG._statusNextSendAt or 0
    if nowp < GLOG._statusNextSendAt then return end
    GLOG._statusNextSendAt = nowp + 5.0

    -- Nom canonique du joueur
    local n, r = UnitFullName and UnitFullName("player")
    local me = ((n or "") .. "-" .. (r or ""))
    if ns and ns.Util and ns.Util.NormalizeFull then me = ns.Util.NormalizeFull(me) end

    -- 🚫 Stop si pas dans roster/réserve (ne crée PAS d’entrée)
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


if not GLOG.ReadOwnMaxIlvl then
    function GLOG.ReadOwnMaxIlvl()
        if not GetAverageItemLevel then return nil end
        local overall = (select(1, GetAverageItemLevel()))
        if not overall then return nil end
        return math.max(0, math.floor((tonumber(overall) or 0) + 0.5))
    end
end

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
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.players = GuildLogisticsDB.players or {}

    local p = GuildLogisticsDB.players[name]
    if not p then return "" end

    local lvl = tonumber(p.mkeyLevel or 0) or 0
    if lvl <= 0 then return "" end

    local label = (p.mkeyName and p.mkeyName ~= "") and p.mkeyName or ""
    if (label == "" or label == "Clé") and tonumber(p.mkeyMapId or 0) > 0 then
        local nm = GLOG.ResolveMKeyMapName and GLOG.ResolveMKeyMapName(tonumber(p.mkeyMapId))
        if nm and nm ~= "" then label = nm end
    end
    if label == "" then label = "Clé" end

    local levelText = string.format("|cffffa500+%d|r", lvl)
    -- Niveau AVANT le nom du donjon
    return string.format("%s %s", levelText, label)
end

-- Application locale (sans créer d’entrée ; timestamp dominant)
_SetMKeyLocal = function(name, mapId, level, mapName, ts, by)
    if not name or name == "" then return end
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.players = GuildLogisticsDB.players or {}
    local p = GuildLogisticsDB.players[name]
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

-- ✨ M+ Score : getter + setter local protégés
function GLOG.GetMPlusScore(name)
    if not name or name == "" then return nil end
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.players = GuildLogisticsDB.players or {}
    local p = GuildLogisticsDB.players[name]
    return p and tonumber(p.mplusScore or nil) or nil
end

_SetMPlusScoreLocal = function(name, score, ts, by)
    if not name or name == "" then return end
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.players = GuildLogisticsDB.players or {}
    local p = GuildLogisticsDB.players[name]
    if not p then return end

    local nowts   = tonumber(ts) or time()
    local prev_ts = tonumber(p.mplusTs or 0) or 0
    if nowts >= prev_ts then
        p.mplusScore = math.max(0, tonumber(score) or 0)
        p.mplusTs    = nowts
        p.mplusAuth  = tostring(by or "")
        if ns.Emit then ns.Emit("mplus:changed", name) end
        if ns.RefreshAll then ns.RefreshAll() end
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
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.players = GuildLogisticsDB.players or {}
    return GuildLogisticsDB.players[name] ~= nil
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

-- ➕ Lecture immédiate de mon iLvl équipé (sans diffusion)
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
    if not (GLOG.IsPlayerInRosterOrReserve and GLOG.IsPlayerInRosterOrReserve(me)) then
        return
    end

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
    if changed and GLOG.BroadcastStatusUpdate then
        local equipped = GLOG.ReadOwnEquippedIlvl and GLOG.ReadOwnEquippedIlvl() or nil
        local overall  = GLOG.ReadOwnMaxIlvl     and GLOG.ReadOwnMaxIlvl()     or nil
        GLOG.BroadcastStatusUpdate({
            ilvl = equipped, ilvlMax = overall,
            mid = mid or 0, lvl = lvl or 0, map = tostring(mapName or ""),
            ts = ts, by = me,
        })
    end
end


-- =========================
-- ======  HISTORY    ======
-- =========================
function GLOG.AddHistorySession(total, perHead, participants, ctx)

    EnsureDB()
    GuildLogisticsDB.historyNextId = GuildLogisticsDB.historyNextId or 1

    local s = {
        ts = time(),
        total = math.floor(total or 0),
        perHead = math.floor(perHead or 0),
        count = #(participants or {}),
        participants = { unpack(participants or {}) },
        refunded = false,
        hid = GuildLogisticsDB.historyNextId, -- ➕ ID unique
    }
    GuildLogisticsDB.historyNextId = GuildLogisticsDB.historyNextId + 1

    if type(ctx) == "table" and ctx.lots then
        s.lots = ctx.lots
    end
    table.insert(GuildLogisticsDB.history, 1, s)

    -- Diffusion réseau (petit message) si GM
    if GLOG.IsMaster and GLOG.IsMaster() and GLOG.Comm_Broadcast then
        GuildLogisticsDB.meta = GuildLogisticsDB.meta or {}
        local rv = (GuildLogisticsDB.meta.rev or 0) + 1
        GuildLogisticsDB.meta.rev = rv
        GuildLogisticsDB.meta.lastModified = time()

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

        GLOG.Comm_Broadcast("HIST_ADD", {
            ts = s.ts, total = s.total, per = s.perHead, cnt = s.count,
            r = s.refunded and 1 or 0, P = s.participants, L = Lraw, -- ➕
            rv = rv, lm = GuildLogisticsDB.meta.lastModified,
        })
    end
    if ns.Emit then ns.Emit("history:changed") end
end

function GLOG.GetHistory()
    EnsureDB()
    return GuildLogisticsDB.history
end

function GLOG.RefundSession(idx)
    EnsureDB()
    local s = GuildLogisticsDB.history[idx]
    if not s or s.refunded then return false end
    local per = tonumber(s.perHead) or 0
    local parts = s.participants or {}

    if GLOG.IsMaster and GLOG.IsMaster() and GLOG.GM_BroadcastBatch then
        local adjusts = {}
        for _, name in ipairs(parts) do adjusts[#adjusts+1] = { name = name, delta = per } end
        GLOG.GM_BroadcastBatch(adjusts, { reason = "REFUND", silent = true })
    else
        for _, name in ipairs(parts) do if GuildLogisticsDB.players[name] then GLOG.Credit(name, per) end end
    end

    s.refunded = true

    -- Diffusion du changement d'état si GM
    if GLOG.IsMaster and GLOG.IsMaster() and GLOG.Comm_Broadcast then
        GuildLogisticsDB.meta = GuildLogisticsDB.meta or {}
        local rv = (GuildLogisticsDB.meta.rev or 0) + 1
        GuildLogisticsDB.meta.rev = rv
        GuildLogisticsDB.meta.lastModified = time()
        GLOG.Comm_Broadcast("HIST_REFUND", { ts = s.ts, h = s.hid, rv = rv, lm = GuildLogisticsDB.meta.lastModified })
    end
    if ns.Emit then ns.Emit("history:changed") end
    return true
end

function GLOG.UnrefundSession(idx)
    EnsureDB()
    local s = GuildLogisticsDB.history[idx]
    if not s or not s.refunded then return false end
    local per = tonumber(s.perHead) or 0
    local parts = s.participants or {}

    if GLOG.IsMaster and GLOG.IsMaster() and GLOG.GM_BroadcastBatch then
        local adjusts = {}
        for _, name in ipairs(parts) do adjusts[#adjusts+1] = { name = name, delta = -per } end
        GLOG.GM_BroadcastBatch(adjusts, { reason = "REFUND", silent = true })
    else
        for _, name in ipairs(parts) do if GuildLogisticsDB.players[name] then GLOG.Debit(name, per) end end
    end

    s.refunded = false

    -- Diffusion du changement d'état si GM
    if GLOG.IsMaster and GLOG.IsMaster() and GLOG.Comm_Broadcast then
        GuildLogisticsDB.meta = GuildLogisticsDB.meta or {}
        local rv = (GuildLogisticsDB.meta.rev or 0) + 1
        GuildLogisticsDB.meta.rev = rv
        GuildLogisticsDB.meta.lastModified = time()
        GLOG.Comm_Broadcast("HIST_REFUND", { ts = s.ts, h = s.hid, r = 0, rv = rv, lm = GuildLogisticsDB.meta.lastModified })
    end
    if ns.Emit then ns.Emit("history:changed") end
    return true
end

function GLOG.DeleteHistory(idx)
    EnsureDB()
    local hist = GuildLogisticsDB.history or {}
    local s = hist[idx]; if not s then return false end
    local ts = s.ts
    table.remove(hist, idx)

    -- Diffusion de la suppression si GM
    if GLOG.IsMaster and GLOG.IsMaster() and GLOG.Comm_Broadcast then
        GuildLogisticsDB.meta = GuildLogisticsDB.meta or {}
        local rv = (GuildLogisticsDB.meta.rev or 0) + 1
        GuildLogisticsDB.meta.rev = rv
        GuildLogisticsDB.meta.lastModified = time()
        GLOG.Comm_Broadcast("HIST_DEL", { ts = ts, h = s.hid, rv = rv, lm = GuildLogisticsDB.meta.lastModified })
    end
    if ns.Emit then ns.Emit("history:changed") end
    return true
end

function GLOG.WipeAllData()
    EnsureDB()  -- garantit la bascule _Char et les alias
    -- Conserver la version uniquement pour le GM (joueurs : réinitialiser à 0)
    local isMaster = (GLOG.IsMaster and GLOG.IsMaster())
        or (IsInGuild and IsInGuild() and select(3, GetGuildInfo("player")) == 0)
        or false
    local oldRev     = (GuildLogisticsDB_Char and GuildLogisticsDB_Char.meta and GuildLogisticsDB_Char.meta.rev) or 0
    local keepRev    = isMaster and oldRev or 0
    local keepMaster = (GuildLogisticsDB_Char and GuildLogisticsDB_Char.meta and GuildLogisticsDB_Char.meta.master) or nil

    -- ⚠️ Purge la SV par personnage (et pas seulement l’alias runtime)
    GuildLogisticsDB_Char = {
        players       = {},
        history       = {},
        expenses      = { recording = false, list = {}, nextId = 1 },
        lots          = { nextId = 1, list = {} },
        ids           = { counter=0, byName={}, byId={} },
        meta          = { lastModified=0, fullStamp=0, rev=keepRev, master=keepMaster },
        requests      = {},
        historyNextId = 1,
        debug         = {},
        aliases       = {},
        _migr_perchar_1 = true, -- évite toute re-migration depuis l’ancienne DB compte
    }
    -- Rebind des alias runtime
    GuildLogisticsDB = GuildLogisticsDB_Char
end

-- Purge complète : DB + préférences UI
function GLOG.WipeAllSaved()
    EnsureDB()
    -- Conserver la version uniquement pour le GM (joueurs : réinitialiser à 0)
    local isMaster = (GLOG.IsMaster and GLOG.IsMaster())
        or (IsInGuild and IsInGuild() and select(3, GetGuildInfo("player")) == 0)
        or false
    local oldRev     = (GuildLogisticsDB_Char and GuildLogisticsDB_Char.meta and GuildLogisticsDB_Char.meta.rev) or 0
    local keepRev    = isMaster and oldRev or 0
    local keepMaster = (GuildLogisticsDB_Char and GuildLogisticsDB_Char.meta and GuildLogisticsDB_Char.meta.master) or nil

    -- ⚠️ Purge les 2 SV par personnage
    GuildLogisticsDB_Char = {
        players       = {},
        history       = {},
        expenses      = { recording = false, list = {}, nextId = 1 },
        lots          = { nextId = 1, list = {} },
        ids           = { counter=0, byName={}, byId={} },
        meta          = { lastModified=0, fullStamp=0, rev=keepRev, master=keepMaster },
        requests      = {},
        historyNextId = 1,
        debug         = {},
        aliases       = {},
        _migr_perchar_1 = true,
    }
    GuildLogisticsUI_Char = {
        point="CENTER", relTo=nil, relPoint="CENTER", x=0, y=0, width=1160, height=680,
        minimap = { hide=false, angle=215 },
        _migr_perchar_1 = true,
        -- ✏️ Par défaut : options pratiques
        debugEnabled = true, autoOpen = true,
    }

    -- Rebind des alias runtime pour la session courante
    GuildLogisticsDB = GuildLogisticsDB_Char
    GuildLogisticsUI = GuildLogisticsUI_Char

    -- Optionnel : nettoyer quelques caches mémoire visibles avant le ReloadUI
    GLOG._guildCache = {}
    GLOG._lastOwnIlvl, GLOG._lastOwnMPlusScore, GLOG._lastOwnMKeyId, GLOG._lastOwnMKeyLvl = nil, nil, nil, nil
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

-- =========================
-- ======   LOTS      ======
-- =========================
-- Lots consommables : 1 session (100%) ou multi-sessions (1/N par clôture).
-- Le contenu d'un lot est figé à la création. Les éléments proviennent des
-- "Ressources libres" (dépenses non rattachées).

local function _ensureLots()
    GLOG._EnsureDB()
    GuildLogisticsDB.lots     = GuildLogisticsDB.lots     or { nextId = 1, list = {} }
    GuildLogisticsDB.expenses = GuildLogisticsDB.expenses or { recording=false, list = {}, nextId = 1 }
end

function GLOG.GetLots()
    _ensureLots()
    return GuildLogisticsDB.lots.list
end

function GLOG.Lot_GetById(id)
    _ensureLots()
    for _, l in ipairs(GuildLogisticsDB.lots.list or {}) do
        if l.id == id then return l end
    end
end

function GLOG.Lot_Status(lot)
    if not lot then return "?" end
    local used = tonumber(lot.used or 0) or 0
    local N    = tonumber(lot.sessions or 1) or 1
    if used <= 0 then return "A_UTILISER" end
    if used < N  then return "EN_COURS"  end
    return "EPU"
end

function GLOG.Lot_IsSelectable(lot)
    return lot and (not lot.__pendingConsume) and GLOG.Lot_Status(lot) ~= "EPU"
end

-- Coût par utilisation (ex-ShareGold) en or entiers — pas de PA/PC.
function GLOG.Lot_ShareGold(lot)  -- compat : on conserve le nom
    local totalC = tonumber(lot.totalCopper or lot.copper or 0) or 0
    local N      = tonumber(lot.sessions or 1) or 1
    return math.floor( math.floor(totalC / 10000) / N )
end

-- ➕ Utilitaires "charges"
function GLOG.Lot_UseCostGold(lot)  -- alias explicite
    return GLOG.Lot_ShareGold(lot)
end

function GLOG.Lot_Remaining(lot)   -- utilisations restantes
    local used = tonumber(lot.used or 0) or 0
    local N    = tonumber(lot.sessions or 1) or 1
    return math.max(0, N - used)
end

-- Création : fige le contenu depuis une liste d'index ABSOLUS de GuildLogisticsDB.expenses.list
-- isMulti = true/false ; sessions = N si multi (>=1)
function GLOG.Lot_Create(name, isMulti, sessions, absIdxs)
    _ensureLots()
    name = name or "Lot"
    local e = GuildLogisticsDB.expenses
    local L = GuildLogisticsDB.lots
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
    if GLOG.BroadcastLotCreate and GLOG.IsMaster and GLOG.IsMaster() then GLOG.BroadcastLotCreate(l) end
    return l
end

-- Suppression possible uniquement si jamais utilisé (rend les ressources libres)
function GLOG.Lot_Delete(id)
    _ensureLots()
    local L = GuildLogisticsDB.lots
    local list = L.list or {}
    local idx = nil
    for i, l in ipairs(list) do if l.id == id then idx = i break end end
    if not idx then return false end
    table.remove(list, idx)
    for _, it in ipairs(GuildLogisticsDB.expenses.list or {}) do if it.lotId == id then it.lotId = nil end end
    if ns.Emit then ns.Emit("lots:changed") end
    if ns.RefreshActive then ns.RefreshActive() end -- ✅ disparition immédiate à l’écran

    -- ➕ Diffusion GM
    if GLOG.BroadcastLotDelete and GLOG.IsMaster and GLOG.IsMaster() then GLOG.BroadcastLotDelete(id) end
    return true
end

function GLOG.Lot_ListSelectable()
    _ensureLots()
    local out = {}
    for _, l in ipairs(GuildLogisticsDB.lots.list or {}) do
        if GLOG.Lot_IsSelectable(l) then out[#out+1] = l end
    end
    return out
end

function GLOG.Lot_Consume(id)
    _ensureLots()
    local l = GLOG.Lot_GetById(id); if not l then return false end
    local N = tonumber(l.sessions or 1) or 1
    local u = tonumber(l.used or 0) or 0
    l.used = math.min(u + 1, N)  -- ne décrémente que d'1, borné au max
    if ns.RefreshAll then ns.RefreshAll() end
    return true
end

function GLOG.Lots_ConsumeMany(ids)
    _ensureLots()
    ids = ids or {}

    local isMaster = GLOG.IsMaster and GLOG.IsMaster()
    if isMaster then
        -- GM : applique directement la consommation (évite le blocage __pendingConsume)
        local L = GuildLogisticsDB.lots
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
        if GLOG.BroadcastLotsConsume then GLOG.BroadcastLotsConsume(ids) end

    else
        -- Client : applique localement sans diffusion (borné).
        local L = GuildLogisticsDB.lots
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

function GLOG.Lots_ComputeGoldTotal(ids)
    local g = 0
    for _, id in ipairs(ids or {}) do
        local l = GLOG.Lot_GetById(id)
        if l and GLOG.Lot_IsSelectable(l) then g = g + GLOG.Lot_ShareGold(l) end
    end
    return g
end

-- =========================
-- ===== Purges (GM)  ======
-- =========================

-- Incrémente / réinitialise la révision selon le rôle
local function _BumpRevisionLocal()
    EnsureDB()
    local isMaster = (GLOG.IsMaster and GLOG.IsMaster()) or false
    local rv = tonumber(GuildLogisticsDB.meta.rev or 0) or 0
    GuildLogisticsDB.meta.rev = isMaster and (rv + 1) or 0
    GuildLogisticsDB.meta.lastModified = time()
end

-- Supprime tous les lots épuisés + tous leurs objets associés
function GLOG.PurgeLotsAndItemsExhausted()
    EnsureDB(); _ensureLots()
    local L = GuildLogisticsDB.lots
    local E = GuildLogisticsDB.expenses

    local purgeLots   = {}
    local purgeItems  = {}

    for _, l in ipairs(L.list or {}) do
        if (GLOG.Lot_Status and GLOG.Lot_Status(l) == "EPU") then
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
function GLOG.PurgeAllResources()
    EnsureDB(); _ensureLots()
    local L = GuildLogisticsDB.lots
    local E = GuildLogisticsDB.expenses

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

function GLOG.GetSavedWindow() EnsureDB(); return GuildLogisticsUI end
function GLOG.SaveWindow(point, relTo, relPoint, x, y, w, h)
    GuildLogisticsUI = GuildLogisticsUI or {}
    GuildLogisticsUI.point    = point
    GuildLogisticsUI.relTo    = relTo
    GuildLogisticsUI.relPoint = relPoint
    GuildLogisticsUI.x        = x
    GuildLogisticsUI.y        = y
    GuildLogisticsUI.width    = w
    GuildLogisticsUI.height   = h
end

-- =========================
-- ==== Demandes (GM) ======
-- =========================
function GLOG.GetRequests()
    EnsureDB()
    GuildLogisticsDB.requests = GuildLogisticsDB.requests or {}
    return GuildLogisticsDB.requests
end

-- Expose les demandes pour l’UI (badge/onglet)
function GLOG.GetRequests()
    EnsureDB()
    GuildLogisticsDB.requests = GuildLogisticsDB.requests or {}
    return GuildLogisticsDB.requests
end

ns.Tr = ns.Tr or function(input, ...)
    if input == nil then return "" end
    local s = tostring(input)
    local key = s
    local v = (ns.L and ns.L[key]) or s
    if select("#", ...) > 0 then
        local ok, out = pcall(string.format, v, ...)
        if ok then return out end
    end
    return v
end

-- ===== Dépenses : table de correspondance des sources (IDs stables) =====
GLOG.EXPENSE_SOURCE = GLOG.EXPENSE_SOURCE or {
    SHOP = 1,        -- Boutique PNJ
    AH   = 2,        -- Hôtel des Ventes
}

function GLOG.GetExpenseSourceLabel(id)
    local v = tonumber(id) or 0
    if v == (GLOG.EXPENSE_SOURCE and GLOG.EXPENSE_SOURCE.SHOP) then
        return (ns.Tr and ns.Tr("lbl_shop")) or "Shop"
    elseif v == (GLOG.EXPENSE_SOURCE and GLOG.EXPENSE_SOURCE.AH) then
        return (ns.Tr and ns.Tr("lbl_ah")) or "AH"
    end
    return ""
end

-- ===== Bus d'événements interne, simple et réutilisable =====
GLOG.__evt = GLOG.__evt or {}

function GLOG.On(event, callback)
    if type(event) ~= "string" or type(callback) ~= "function" then return end
    local L = GLOG.__evt[event]
    if not L then L = {}; GLOG.__evt[event] = L end
    table.insert(L, callback)
end

function GLOG.Off(event, callback)
    local L = GLOG.__evt and GLOG.__evt[event]
    if not L then return end
    for i = #L, 1, -1 do
        if L[i] == callback then table.remove(L, i) end
    end
end

function GLOG.Emit(event, ...)
    local L = GLOG.__evt and GLOG.__evt[event]
    if not L then return end
    for i = 1, #L do
        local ok = pcall(L[i], ...)
        -- on ignore les erreurs pour ne pas casser la chaîne de traitement
    end
end

-- =========================
-- ======  ALIAS API  ======
-- =========================

-- Renvoie la clé "main" normalisée (base du nom sans royaume + lowercase)
local function _AliasMainKey(name)
    if not name or name == "" then return nil end
    local main = (GLOG.GetMainOf and GLOG.GetMainOf(name)) or name
    return (GLOG.NormName and GLOG.NormName(main)) or tostring(main):lower()
end

function GLOG.GetAliasFor(name)
    EnsureDB()
    local key = _AliasMainKey(name)
    if not key then return nil end
    return (GuildLogisticsDB.aliases or {})[key]
end

function GLOG.SetAliasLocal(name, alias)
    EnsureDB()
    GuildLogisticsDB.aliases = GuildLogisticsDB.aliases or {}
    local key = _AliasMainKey(name); if not key then return end
    alias = tostring(alias or ""):gsub("^%s+", ""):gsub("%s+$","")
    if alias == "" then
        GuildLogisticsDB.aliases[key] = nil
    else
        GuildLogisticsDB.aliases[key] = alias
    end
    if ns.Emit then ns.Emit("alias:changed", key, alias) end
    if ns.RefreshAll then ns.RefreshAll() end
end

-- Action GM : définit l’alias d’un joueur et le diffuse via ROSTER_UPSERT
function GLOG.GM_SetAlias(name, alias)
    if not (GLOG.IsMaster and GLOG.IsMaster()) then
        if UIErrorsFrame then
            UIErrorsFrame:AddMessage("|cffff6060[GLOG]|r Définition d’alias réservée au GM.", 1, .4, .4)
        end
        return false
    end
    if not name or name=="" then return false end
    GLOG.SetAliasLocal(name, alias)

    GuildLogisticsDB.meta = GuildLogisticsDB.meta or {}
    local rv = (GuildLogisticsDB.meta.rev or 0) + 1
    GuildLogisticsDB.meta.rev = rv
    GuildLogisticsDB.meta.lastModified = time()

    if GLOG.BroadcastRosterUpsert then
        GLOG.BroadcastRosterUpsert(name)  -- inclura l'alias (voir Comm.lua)
    end
    return true
end

-- Stocke la version d’addon au niveau du MAIN (fallback: émetteur), avec cache léger.
function GLOG.SetPlayerAddonVersion(name, ver, ts, by)
    if not name or name == "" then return end
    ver = tostring(ver or "")
    if ver == "" then return end

    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.players = GuildLogisticsDB.players or {}
    GuildLogisticsDB.meta    = GuildLogisticsDB.meta    or {}
    GuildLogisticsDB.meta.versions = GuildLogisticsDB.meta.versions or {}

    local now  = (time and time()) or 0
    local when = tonumber(ts) or now

    local main   = (GLOG.GetMainOf and GLOG.GetMainOf(name)) or name
    local kMain  = (GLOG.NormName and GLOG.NormName(main)) or tostring(main):lower()
    local fullS  = (GLOG.ResolveFullName and GLOG.ResolveFullName(name)) or tostring(name)
    local fullM  = (GLOG.ResolveFullName and GLOG.ResolveFullName(main)) or tostring(main)

    -- 1) Met à jour la fiche du MAIN si elle existe
    do
        local p = GuildLogisticsDB.players[fullM]
        if p then
            local prev = tonumber(p.addonVerTs or 0) or 0
            if when >= prev then
                p.addonVer     = ver
                p.addonVerTs   = when
                p.addonVerAuth = tostring(by or "")
            end
        end
    end
    -- 2) Met à jour la fiche du personnage émetteur si elle existe (utile en Debug)
    do
        local p = GuildLogisticsDB.players[fullS]
        if p then
            local prev = tonumber(p.addonVerTs or 0) or 0
            if when >= prev then
                p.addonVer     = ver
                p.addonVerTs   = when
                p.addonVerAuth = tostring(by or "")
            end
        end
    end
    -- 3) Cache léger par MAIN pour l’onglet Joueurs (si pas d’entrée joueurs)
    do
        local e = GuildLogisticsDB.meta.versions[kMain] or {}
        local prev = tonumber(e.ts or 0) or 0
        if when >= prev then
            e.ver  = ver
            e.ts   = when
            e.by   = tostring(by or "")
            e.name = main
            GuildLogisticsDB.meta.versions[kMain] = e
        end
    end
end

-- Récupère la version d’addon affichée par l’onglet Joueurs (clé MAIN prioritaire)
function GLOG.GetPlayerAddonVersion(name)
    if not name or name == "" then return "" end
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.players = GuildLogisticsDB.players or {}
    GuildLogisticsDB.meta    = GuildLogisticsDB.meta    or {}

    local main   = (GLOG.GetMainOf and GLOG.GetMainOf(name)) or name
    local kMain  = (GLOG.NormName and GLOG.NormName(main)) or tostring(main):lower()
    local fullM  = (GLOG.ResolveFullName and GLOG.ResolveFullName(main)) or tostring(main)
    local fullS  = (GLOG.ResolveFullName and GLOG.ResolveFullName(name)) or tostring(name)

    -- 1) DB.players[fullMain]
    do
        local p = GuildLogisticsDB.players[fullM]
        local v = p and p.addonVer
        if v and v ~= "" then return tostring(v) end
    end
    -- 2) Cache meta.versions[kMain]
    do
        local e = GuildLogisticsDB.meta.versions and GuildLogisticsDB.meta.versions[kMain]
        local v = e and e.ver
        if v and v ~= "" then return tostring(v) end
    end
    -- 3) Fallback: fiche du personnage émetteur si fournie
    do
        local p = GuildLogisticsDB.players[fullS]
        local v = p and p.addonVer
        if v and v ~= "" then return tostring(v) end
    end
    return ""
end
