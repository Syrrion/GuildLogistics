local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
local GLOG = ns.GLOG

function GLOG.NormName(name)
    if not name then return nil end
    local amb = Ambiguate(name, "none")
    amb = strtrim(amb or "")
    local p = amb:find("-")
    local base = p and amb:sub(1, p-1) or amb
    return base:lower()
end

-- --------- Cache guilde ---------
GLOG._guildCache = GLOG._guildCache or { rows=nil, mains=nil, byName={}, mainsClass={}, ts=0 }

local function aggregateRows(rows)
    local mainsMap, mainsClass = {}, {}

    for _, r in ipairs(rows or {}) do
        local noteMain = r.remark and strtrim(r.remark) or ""
        local key = (noteMain ~= "" and GLOG.NormName(noteMain)) or nil
        if key and key ~= "" then
            local days  = (r.online and 0) or (tonumber(r.daysDerived)  or 9999)
            local hours = (r.online and 0) or (tonumber(r.hoursDerived) or 9999999)

            local e = mainsMap[key]
            if not e then
                e = { main = noteMain, key = key, count = 0, days = 999999, hours = 9999999, onlineCount = 0, mostRecentChar = r.name_amb or r.name_raw, classTag = nil }
                mainsMap[key] = e
            end

            e.count = e.count + 1
            if r.online then e.onlineCount = e.onlineCount + 1 end

            -- Détecte la ligne du main via NOM normalisé (base + lowercase)
            if GLOG.NormName(r.name_amb or r.name_raw) == key then
                e.classTag = e.classTag or r.class
            end

            if days < e.days then e.days = days; e.mostRecentChar = r.name_amb or r.name_raw end
            if hours < (e.hours or 9999999) then e.hours = hours end
        end
    end

    for k, e in pairs(mainsMap) do mainsClass[k] = e.classTag end

    local out = {}
    for _, e in pairs(mainsMap) do table.insert(out, e) end
    table.sort(out, function(a,b) return (a.key or "") < (b.key or "") end)

    return out, mainsClass
end


-- --------- Scanner asynchrone ---------
local Scanner = CreateFrame("Frame")
Scanner.pending = false
Scanner.callbacks = {}

Scanner:SetScript("OnEvent", function(self, ev)
    if ev ~= "GUILD_ROSTER_UPDATE" then return end
    self:UnregisterEvent("GUILD_ROSTER_UPDATE")
    self.pending = false

    local rows = {}
    local n = (GetNumGuildMembers and GetNumGuildMembers())
            or (C_GuildInfo and C_GuildInfo.GetGuildRosterMemberCount and C_GuildInfo.GetGuildRosterMemberCount())
            or 0

    for i = 1, n do
        -- On récupère aussi le rang (rankName, rankIndex)
        local name, rankName, rankIndex, _, _, _, note, officerNote, online, _, classFileName, _, _, isMobile = GetGuildRosterInfo(i)
        local y, m, d, h = nil, nil, nil, nil
        local retCount = 0
        if GetGuildRosterLastOnline then
            y, m, d, h = GetGuildRosterLastOnline(i)
            retCount = select("#", GetGuildRosterLastOnline(i))
        end

        -- En ligne = connecté en jeu (pas “mobile”)
        local onlineChar = (online and not isMobile) and true or false

        -- Jours/Heures depuis la dernière connexion
        local daysDerived, hoursDerived
        if onlineChar then
            daysDerived, hoursDerived = 0, 0
        elseif y == nil and m == nil and d == nil and h == nil then
            daysDerived, hoursDerived = nil, nil
        else
            local Y = tonumber(y) or 0
            local M = tonumber(m) or 0
            local D = tonumber(d) or 0
            local H = tonumber(h) or 0
            daysDerived  = (Y*365) + (M*30) + D                     -- plus d’arrondi via H
            hoursDerived = ((Y*365) + (M*30) + D) * 24 + H
        end

        table.insert(rows, {
            idx = i,
            name_raw = name,
            name_amb = name and Ambiguate(name, "none") or nil,
            online = onlineChar,
            remark = note,
            class = classFileName or nil,
            rankIndex = rankIndex,
            rank = rankName,
            last_y = y, last_m = m, last_d = d, last_h = h,
            retCount = retCount,
            daysDerived = daysDerived,
            hoursDerived = hoursDerived,
        })
    end

    local agg, mainsClass = aggregateRows(rows)
    GLOG._guildCache.rows       = rows
    GLOG._guildCache.mains      = agg
    GLOG._guildCache.mainsClass = mainsClass or {}
    GLOG._guildCache.byName     = {}

    for _, rr in ipairs(rows) do
        local amb = rr.name_amb or rr.name_raw
        local kFull = GLOG.NormName(amb)
        local mainKey = (rr.remark and GLOG.NormName(rr.remark)) or ""

        local rec = { class = rr.class, main = mainKey or "" }
        if kFull and kFull ~= "" then GLOG._guildCache.byName[kFull] = rec end
        -- Par sécurité : indexe aussi la clé exacte lowercase si l’API remonte déjà "Name-Realm"
        local exactLower = amb and amb:lower() or nil
        if exactLower and exactLower ~= kFull then
            GLOG._guildCache.byName[exactLower] = GLOG._guildCache.byName[exactLower] or rec
        end
    end

    GLOG._guildCache.ts = time()

    local cbs = self.callbacks
    self.callbacks = {}
    for _, cb in ipairs(cbs) do pcall(cb, true) end
end)

function GLOG.RefreshGuildCache(cb)
    table.insert(Scanner.callbacks, type(cb)=="function" and cb or function() end)
    if not Scanner.pending then
        Scanner.pending = true
        Scanner:RegisterEvent("GUILD_ROSTER_UPDATE")
        if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end
        -- Fallback si l’évènement ne revient pas (latence / pas de guilde)
        if C_Timer and C_Timer.After then
            C_Timer.After(0.8, function()
                if Scanner.pending and Scanner:GetScript("OnEvent") then
                    Scanner:GetScript("OnEvent")(Scanner, "GUILD_ROSTER_UPDATE")
                end
            end)
        end
    end
end

function GLOG.GetGuildMainsAggregatedCached()
    return (GLOG._guildCache and GLOG._guildCache.mains) or {}
end

-- Retourne l'inactivité (en jours) pour un MAIN (clé normalisée ou nom complet).
-- Prend le "last seen" le plus récent parmi ses personnages dans le cache guilde.
function GLOG.GetMainLastSeenDays(mainKey)
    mainKey = (GLOG.NormName and GLOG.NormName(mainKey)) or nil
    if not mainKey or mainKey == "" then return 9999 end

    local rows = (GLOG._guildCache and GLOG._guildCache.rows) or {}
    local minHours = nil

    for _, r in ipairs(rows) do
        local noteMain = r.remark and strtrim(r.remark) or ""
        local k = (noteMain ~= "" and GLOG.NormName(noteMain)) or nil
        if k == mainKey then
            local h = (r.online and 0) or tonumber(r.hoursDerived) or nil
            if h then
                minHours = (not minHours or h < minHours) and h or minHours
            end
        end
    end

    return (minHours and math.floor(minHours / 24)) or 9999
end

function GLOG.GetGuildRowsCached()
    return GLOG._guildCache and GLOG._guildCache.rows or {}
end

-- Résout un nom court en "Nom-Royaume" en s'appuyant sur le roster en cache.
-- Nettoie aussi les doublons de royaume éventuels.
function GLOG.ResolveFullName(name)
    local n = tostring(name or "")
    if n == "" then return n end

    -- ⚙️ Si on reçoit déjà "Nom-...", on le nettoie (évite "Royaume-Royaume-...")
    if n:find("%-") then
        local cleaner = ns and ns.Util and ns.Util.CleanFullName
        return (cleaner and cleaner(n)) or n
    end

    -- Sinon, essaie de résoudre via le cache de guilde (sans inventer le royaume local)
    local rows = (GLOG.GetGuildRowsCached and GLOG.GetGuildRowsCached()) or {}
    local key  = (GLOG.NormName and GLOG.NormName(n)) or n:lower()
    for _, r in ipairs(rows) do
        local full = r.name_raw or r.name_amb or r.name or ""
        if full ~= "" then
            local base = (full:match("^([^%-]+)%-") or full)
            if base and (base:lower() == key) then
                local cleaner = ns and ns.Util and ns.Util.CleanFullName
                return (cleaner and cleaner(full)) or full
            end
        end
    end
    return n
end

-- ➕ Test d’appartenance guilde via le cache (léger, réutilisable)
function GLOG.IsGuildCharacter(name)
    if not name or name == "" then return false end
    local by = GLOG._guildCache and GLOG._guildCache.byName
    if not by then return false end
    local k = (GLOG.NormName and GLOG.NormName(name)) or tostring(name):lower()
    return (k ~= nil and by[k] ~= nil) and true or false
end

-- ✏️ Est-ce que le GM effectif (rang 0) est en ligne ?
function GLOG.IsMasterOnline()
    if not GLOG.GetGuildMasterCached then return false end
    local gmName, gmRow = GLOG.GetGuildMasterCached()
    return gmRow and gmRow.online and true or false
end

function GLOG.IsGuildCacheReady()
    local c = GLOG._guildCache
    return c and c.rows and #c.rows > 0
end

function GLOG.GetGuildCacheTimestamp()
    local c = GLOG._guildCache
    return (c and c.ts) or 0
end

-- helper utilisé par l’onglet Joueurs
function GLOG.GetGuildMainsAggregated()
    return GLOG.GetGuildMainsAggregatedCached()
end

function GLOG.GetMainOf(name)
    local k = GLOG.NormName(name)
    local by = GLOG._guildCache and GLOG._guildCache.byName
    local e = by and k and by[k]
    return (e and e.main ~= "" and e.main) or nil
end

function GLOG.GetNameClass(name)
    local c = GLOG._guildCache
    if not c then return nil end
    local by = c.byName or {}
    local k  = GLOG.NormName(name)
    local e  = k and by[k]
    local mainKey = e and e.main
    -- 1) classe du main (clé déjà normalisée) ; 2) sinon classe du perso scanné
    local cls = (mainKey and c.mainsClass and c.mainsClass[mainKey]) or (e and e.class)
    return cls
end

function GLOG.GetNameStyle(name)
    local class = GLOG.GetNameClass(name)
    local col = (RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]) or {r=1,g=1,b=1}
    local coords = CLASS_ICON_TCOORDS and class and CLASS_ICON_TCOORDS[class] or nil
    return class, col.r, col.g, col.b, coords
end

-- ➕ Qui est le GM (rang 0) dans le roster ?
function GLOG.GetGuildMasterCached()
    for _, r in ipairs(GLOG.GetGuildRowsCached() or {}) do
        if tonumber(r.rankIndex or 99) == 0 then
            return r.name_amb or r.name_raw, r
        end
    end
    return nil, nil
end

-- ➕ Le GM effectif est-il en ligne ?
function GLOG.IsMasterOnline()
    local gmName, gmRow = GLOG.GetGuildMasterCached()
    return gmRow and gmRow.online and true or false
end

function GLOG.IsNameGuildMaster(name)
    if not name or name == "" then return false end
    local gmName = GLOG.GetGuildMasterCached and select(1, GLOG.GetGuildMasterCached())
    if not gmName or gmName == "" then return false end
    return GLOG.NormName(name) == GLOG.NormName(gmName)
end

-- ===== iLvl (helpers main connecté) =====
function GLOG.IsConnectedMain()
    local pname, prealm = UnitFullName("player")
    local me = (pname or "") .. "-" .. (prealm or "")
    local myKey  = GLOG.NormName and GLOG.NormName(me)
    local mainKey = GLOG.GetMainOf and GLOG.GetMainOf(me) or myKey
    return (mainKey == myKey)
end

function GLOG.GetConnectedMainName()
    if GLOG.IsConnectedMain and GLOG.IsConnectedMain() then
        local pname, prealm = UnitFullName("player")
        return (pname or "") .. "-" .. (prealm or "")
    end
    return nil
end

