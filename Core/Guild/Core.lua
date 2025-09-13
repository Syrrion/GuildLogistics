local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
local GLOG = ns.GLOG

-- --------- Cache guilde ---------
GLOG._guildCache = GLOG._guildCache or { rows=nil, mains=nil, byName={}, mainsClass={}, ts=0 }

local function aggregateRows(rows)
    local mainsMap, mainsClass = {}, {}
    local NormName = GLOG.NormName
    local mainOf = GLOG.GetMainOf

    for _, r in ipairs(rows or {}) do
        local full = r.name_amb or r.name_raw
        if full and full ~= "" then
            local mainName = (mainOf and mainOf(full)) or full
            local key = (NormName and NormName(mainName)) or (NormName and NormName(full)) or tostring(full):lower()

            local days  = (r.online and 0) or (tonumber(r.daysDerived)  or 9999)
            local hours = (r.online and 0) or (tonumber(r.hoursDerived) or 9999999)

            local e = mainsMap[key]
            if not e then
                -- Affiche toujours le nom du MAIN (pas celui d'un alt)
                local mainBase = tostring(mainName):match("^([^%-]+)") or tostring(mainName)
                e = { main = mainBase, key = key, count = 0, days = 999999, hours = 9999999, onlineCount = 0, mostRecentChar = full, classTag = nil, mainBase = mainBase }
                mainsMap[key] = e
            end

            e.count = e.count + 1
            if r.online then e.onlineCount = e.onlineCount + 1 end

            -- Détecte la ligne du main via NOM normalisé
            local rowKey = (NormName and NormName(full)) or tostring(full):lower()
            if rowKey == key then
                e.classTag = e.classTag or r.class
                if not e.mainBase then
                    local base = tostring(full):match("^([^%-]+)") or tostring(full)
                    e.mainBase = base
                    e.main = e.main or base
                end
            end

            if days < e.days then e.days = days; e.mostRecentChar = full end
            if hours < (e.hours or 9999999) then e.hours = hours end
        end
    end

    for k, e in pairs(mainsMap) do mainsClass[k] = e.classTag end

    -- Normalise e.main: fallback to mostRecentChar base if not set
    for _, e in pairs(mainsMap) do
        if not e.main then
            local base = tostring(e.mostRecentChar or ""):match("^([^%-]+)") or tostring(e.mostRecentChar or "")
            e.main = base
        end
    end

    local out = {}
    for _, e in pairs(mainsMap) do table.insert(out, e) end
    table.sort(out, function(a,b) return (a.key or "") < (b.key or "") end)

    return out, mainsClass
end

-- --------- Scanner asynchrone (centralisé via ns.Events) ---------
local Scanner = CreateFrame("Frame")  -- on garde la frame pour réutiliser le handler existant
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

        -- En ligne = connecté en jeu (pas "mobile")
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
            daysDerived  = (Y*365) + (M*30) + D                     -- plus d'arrondi via H
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
        local amb     = rr.name_amb or rr.name_raw
        -- ➕ Pré-calcule et stocke les clés normalisées pour réutilisation UI
        rr.name_key   = rr.name_key   or (amb and GLOG.NormName(amb)) or nil
        -- Unifie: mappe vers le main via API unifiée (manual > auto)
        local mainName = (GLOG.GetMainOf and amb and GLOG.GetMainOf(amb)) or amb
        local mainKey  = (mainName and GLOG.NormName and GLOG.NormName(mainName)) or ""

        local kFull   = rr.name_key
        local rec = { class = rr.class, main = mainKey or "" }
        if kFull and kFull ~= "" then GLOG._guildCache.byName[kFull] = rec end
        -- Par sécurité : indexe aussi la clé exacte lowercase si l'API remonte déjà "Name-Realm"
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

        -- Inscription via le hub, one-shot via UnregisterOwner
        ns.Events.Register("GUILD_ROSTER_UPDATE", Scanner, function()
            ns.Events.UnregisterOwner(Scanner) -- on annule l'écoute dès la 1re réponse
            if Scanner:GetScript("OnEvent") then
                Scanner:GetScript("OnEvent")(Scanner, "GUILD_ROSTER_UPDATE")
            end
        end)

        if C_GuildInfo and C_GuildInfo.GuildRoster then C_GuildInfo.GuildRoster() end

        -- Fallback si l'évènement ne revient pas (latence / pas de guilde)
        if C_Timer and C_Timer.After then
            C_Timer.After(0.8, function()
                if Scanner.pending and Scanner:GetScript("OnEvent") then
                    -- Même traitement que l'event : un seul passage
                    ns.Events.UnregisterOwner(Scanner)
                    Scanner:GetScript("OnEvent")(Scanner, "GUILD_ROSTER_UPDATE")
                end
            end)
        end
    end
end

-- Rebuilds derived parts of the guild cache (mains, byName, mainsClass) from existing rows
-- Useful after manual main/alt mapping changes (no server scan needed)
function GLOG.RebuildGuildCacheDerived()
    local c = GLOG._guildCache
    if not c or not c.rows then return end
    local rows = c.rows
    local agg, mainsClass = aggregateRows(rows)
    c.mains      = agg
    c.mainsClass = mainsClass or {}
    c.byName     = {}

    for _, rr in ipairs(rows) do
        local amb     = rr.name_amb or rr.name_raw
        rr.name_key   = rr.name_key or (amb and GLOG.NormName(amb)) or nil
        local mainName = (GLOG.GetMainOf and amb and GLOG.GetMainOf(amb)) or amb
        local mainKey  = (mainName and GLOG.NormName and GLOG.NormName(mainName)) or ""

        local kFull   = rr.name_key
        local rec = { class = rr.class, main = mainKey or "" }
        if kFull and kFull ~= "" then c.byName[kFull] = rec end
        local exactLower = amb and amb:lower() or nil
        if exactLower and exactLower ~= kFull then
            c.byName[exactLower] = c.byName[exactLower] or rec
        end
    end

    -- Bump timestamp to invalidate dependent memos
    c.ts = time()
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
        local full = r.name_amb or r.name_raw
        local mn   = (GLOG.GetMainOf and GLOG.GetMainOf(full)) or full
        local k    = (mn and GLOG.NormName and GLOG.NormName(mn)) or nil
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

-- ➕ Test d'appartenance guilde via le cache (léger, réutilisable)
function GLOG.IsGuildCharacter(name)
    if not name or name == "" then return false end
    local by = GLOG._guildCache and GLOG._guildCache.byName
    if not by then return false end
    local k = (GLOG.NormName and GLOG.NormName(name)) or tostring(name):lower()
    return (k ~= nil and by[k] ~= nil) and true or false
end

function GLOG.IsGuildCacheReady()
    local c = GLOG._guildCache
    return c and c.rows and #c.rows > 0
end

function GLOG.GetGuildCacheTimestamp()
    local c = GLOG._guildCache
    return (c and c.ts) or 0
end

-- Retourne les infos agrégées (main + rerolls) pour un joueur.
-- Recalcule un mémo interne seulement quand le cache guilde change.
function GLOG.GetMainAggregatedInfo(playerName)
    if not playerName or playerName == "" then return {} end

    local ts = (GLOG.GetGuildCacheTimestamp and GLOG.GetGuildCacheTimestamp()) or 0
    GLOG._mainAgg = GLOG._mainAgg or { ts = -1, byMain = {} }

    if GLOG._mainAgg.ts ~= ts then
        local rows     = (GLOG.GetGuildRowsCached and GLOG.GetGuildRowsCached()) or {}
        local NormName = GLOG.NormName
        local by = {}

        for _, gr in ipairs(rows) do
            local full       = gr.name_amb or gr.name_raw
            local rowNameKey = gr.name_key or (NormName and NormName(full)) or nil
            local mn         = (full and GLOG.GetMainOf and GLOG.GetMainOf(full)) or full
            local mainKey    = (mn and NormName and NormName(mn)) or rowNameKey

            if mainKey and mainKey ~= "" then
                local e = by[mainKey]
                if not e then
                    e = {
                        online = false, days = nil, hours = nil,
                        idx = nil, level = nil, mainBase = nil,
                        onlineAltBase = nil, onlineAltFull = nil, onlineAltIdx = nil, altClass = nil
                    }
                    by[mainKey] = e
                end

                -- Détection de la ligne du main
                if rowNameKey == mainKey then
                    e.idx = e.idx or gr.idx
                    if not e.mainBase then
                        local full = gr.name_amb or gr.name_raw or ""
                        e.mainBase = (tostring(full):match("^([^%-]+)")) or tostring(full)
                    end
                    if GetGuildRosterInfo and gr.idx and e.level == nil then
                        local _, _, _, level = GetGuildRosterInfo(gr.idx)
                        e.level = tonumber(level)
                    end
                end

                -- Présence + alt connecté (indépendant de l'ordre d'itération)
                if gr.online then
                    e.online = true
                    local full = gr.name_amb or gr.name_raw or ""
                    local base = tostring(full):match("^([^%-]+)") or tostring(full)

                    -- Si la ligne courante n'est pas celle du main, c'est un alt.
                    -- (Ne dépend plus de e.mainBase, qui peut ne pas être défini si le main n'a pas encore été vu)
                    if rowNameKey and mainKey and rowNameKey ~= mainKey then
                        if not e.onlineAltFull then
                            e.onlineAltBase = base
                            e.onlineAltFull = full
                            e.onlineAltIdx  = gr.idx
                            -- Privilégie la clé de classe exploitable par les icônes
                            e.altClass      = gr.classFile or gr.classTag or gr.class
                        end
                    end
                end

                -- Dernière activité
                local d  = tonumber(gr.daysDerived  or nil)
                local hr = tonumber(gr.hoursDerived or nil)
                if gr.online then d, hr = 0, 0 end
                if d  ~= nil then e.days  = (e.days  and math.min(e.days,  d))  or d  end
                if hr ~= nil then e.hours = (e.hours and math.min(e.hours, hr)) or hr end
            end
        end

        GLOG._mainAgg.ts    = ts
        GLOG._mainAgg.byMain = by
    end

    local NormName = GLOG.NormName
    local mainName = (GLOG.GetMainOf and GLOG.GetMainOf(playerName)) or playerName
    local key      = (NormName and NormName(mainName)) or nil
    local e        = key and GLOG._mainAgg.byMain[key] or nil
    if not e then return {} end

    return {
        online = e.online, days = e.days, hours = e.hours,
        idx = e.idx, level = e.level,
        onlineAltBase = e.onlineAltBase, onlineAltFull = e.onlineAltFull, onlineAltIdx = e.onlineAltIdx,
        altClass = e.altClass,
    }
end

-- helper utilisé par l'onglet Joueurs
function GLOG.GetGuildMainsAggregated()
    return GLOG.GetGuildMainsAggregatedCached()
end

-- Note-only fallback: derive main key from guild public note for a name (returns normalized key or nil)
function GLOG.GetMainOf_FromNotes(name)
    if not name or name == "" then return nil end
    local NormName = GLOG.NormName
    local key = NormName and NormName(name)
    if not key or key == "" then return nil end
    local rows = GLOG.GetGuildRowsCached and GLOG.GetGuildRowsCached() or {}
    for _, gr in ipairs(rows) do
        local rowKey = gr.name_key or (NormName and NormName(gr.name_amb or gr.name_raw)) or nil
        if rowKey == key then
            local noteMain = gr.remark and strtrim(gr.remark) or ""
            local mk = (noteMain ~= "" and NormName and NormName(noteMain)) or nil
            return mk
        end
    end
    return nil
end

-- Helpers exposés pour UI Roster_MainAlt (centralisation logique commune)
function GLOG.GetGuildNoteByName(name)
    if not name or name == "" then return "" end
    local rows = (GLOG.GetGuildRowsCached and GLOG.GetGuildRowsCached()) or {}
    local NormName = GLOG.NormName
    local k = (NormName and NormName(name)) or tostring(name):lower()
    for _, gr in ipairs(rows) do
        local rowKey = gr.name_key or (NormName and NormName(gr.name_amb or gr.name_raw)) or nil
        if rowKey == k then return (gr.remark and strtrim(gr.remark)) or "" end
    end
    return ""
end

function GLOG.GetGuildClassTag(name)
    if not name or name == "" then return nil end
    local by = (GLOG._guildCache and GLOG._guildCache.byName) or {}
    local k  = (GLOG.NormName and GLOG.NormName(name)) or tostring(name):lower()
    local rec = by[k]
    return rec and (rec.classFile or rec.classTag or rec.class) or nil
end

function GLOG.GetNameClass(name)
    local c = GLOG._guildCache
    local cls = nil

    if c then
        local by = c.byName or {}
        local k  = GLOG.NormName(name)
        local e  = k and by[k]
        local mainKey = e and e.main
        -- 1) classe du main ; 2) sinon classe du personnage scanné
        cls = (mainKey and c.mainsClass and c.mainsClass[mainKey]) or (e and e.class)
    end

    -- 🔁 Fallback : tenter via les unités du groupe/raid si pas en guilde
    if (not cls or cls == "") and ns and ns.Util and ns.Util.LookupClassForName then
        local fromUnits = ns.Util.LookupClassForName(name)
        if fromUnits and fromUnits ~= "" then
            return fromUnits
        end
    end

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
    local me = (ns and ns.Util and ns.Util.playerFullName and ns.Util.playerFullName())
            or (UnitName and UnitName("player")) or "?"
    local myKey   = GLOG.NormName and GLOG.NormName(me)
    local mainKey = GLOG.GetMainOf and GLOG.GetMainOf(me) or myKey
    return (mainKey == myKey)
end

function GLOG.GetConnectedMainName()
    if GLOG.IsConnectedMain and GLOG.IsConnectedMain() then
        return (ns and ns.Util and ns.Util.playerFullName and ns.Util.playerFullName())
            or (UnitName and UnitName("player"))
    end
    return nil
end

-- ➕ Récupère la zone (lieu) via l'index Roster, en restant robuste
function GLOG.GetRosterZone(idx)
    if not idx or not GetGuildRosterInfo then return nil end
    -- Dans l'API Retail, la zone est le 6e retour de GetGuildRosterInfo
    local _, _, _, _, _, zone = GetGuildRosterInfo(idx)
    zone = type(zone) == "string" and strtrim(zone) or nil
    return (zone ~= "" and zone) or nil
end

-- ➕ Retourne la zone d'un main : si le main est en ligne on prend sa zone,
--     sinon celle d'un de ses rerolls en ligne (le premier trouvé).
function GLOG.GetAnyOnlineZone(name)
    if not name or name == "" then return nil end
    local rows = (GLOG.GetGuildRowsCached and GLOG.GetGuildRowsCached()) or {}
    if not rows or #rows == 0 then return nil end

    local NormName = GLOG.NormName
    local mn       = (GLOG.GetMainOf and GLOG.GetMainOf(name)) or name
    local mainKey  = (mn and NormName and NormName(mn)) or (NormName and NormName(name)) or tostring(name):lower()

    local mainIdx, altIdx = nil, nil
    for _, gr in ipairs(rows) do
    local rowNameKey = gr.name_key or ((NormName and NormName(gr.name_amb or gr.name_raw)) or nil)
    local mngr       = (gr.name_amb or gr.name_raw)
    local mnKey      = (mngr and GLOG.GetMainOf and GLOG.GetMainOf(mngr) and NormName(GLOG.GetMainOf(mngr))) or rowNameKey
    local belongs    = (mnKey == mainKey)

        if belongs then
            if rowNameKey == mainKey then mainIdx = mainIdx or gr.idx end
            if gr.online then
                -- Priorité au main s'il est en ligne
                if rowNameKey == mainKey then
                    local z = GLOG.GetRosterZone(gr.idx)
                    if z then return z end
                else
                    altIdx = altIdx or gr.idx
                end
            end
        end
    end

    if altIdx then return GLOG.GetRosterZone(altIdx) end
    return nil
end

-- True si le joueur est chef de guilde (rank index 0) — autorisation maximale.
function GLOG.IsMaster()
    -- Cache-first to avoid flaky early false
    if type(GLOG._isMaster) == "boolean" then return GLOG._isMaster end
    -- Compute once synchronously as best-effort
    local v = false
    if IsInGuild and IsInGuild() then
        local _, _, ri = GetGuildInfo("player")
        if type(ri) == "number" and ri == 0 then v = true end
        if not v then
            -- Fallback via roster cache (detect actual GM and compare to self)
            local me = (ns and ns.Util and ns.Util.playerFullName and ns.Util.playerFullName())
                    or (UnitName and UnitName("player")) or nil
            if me and GLOG.IsNameGuildMaster and GLOG.IsNameGuildMaster(me) then
                v = true
            end
        end
    end
    GLOG._isMaster = v
    return v
end

-- True si le joueur est chef de guilde ou possède des permissions officiers majeures.
function GLOG.IsGM()
    if IsInGuild and IsInGuild() then
        local _, _, ri = GetGuildInfo("player")
        if ri == 0 then return true end
        local function has(fn) return type(fn) == "function" and fn() end
        if has(CanGuildPromote) or has(CanGuildDemote) or has(CanGuildRemove)
        or has(CanGuildInvite) or has(CanEditMOTD) or has(CanEditGuildInfo)
        or has(CanEditPublicNote) then
            return true
        end
    end
    return false
end

-- Robustly keep _isMaster in sync with the game state
do
    local function _recomputeIsMaster()
        local before = GLOG._isMaster
        local nowVal = false
        if IsInGuild and IsInGuild() then
            local _, _, ri = GetGuildInfo("player")
            if type(ri) == "number" and ri == 0 then
                nowVal = true
            else
                local me = (ns and ns.Util and ns.Util.playerFullName and ns.Util.playerFullName())
                        or (UnitName and UnitName("player")) or nil
                if me and GLOG.IsNameGuildMaster and GLOG.IsNameGuildMaster(me) then
                    nowVal = true
                end
            end
        end
        if before ~= nowVal then
            GLOG._isMaster = nowVal
            if ns.Emit then ns.Emit("gm:changed", nowVal) end
            -- Refresh UI affordances that depend on GM status
            if ns and ns.UI and ns.UI.RefreshTitle then pcall(ns.UI.RefreshTitle) end
            if ns and ns.UI and ns.UI.RefreshActive then pcall(ns.UI.RefreshActive) end
        else
            GLOG._isMaster = nowVal -- ensure it's set even if same
        end
    end

    -- Events that signal guild/roster/rank updates
    if ns and ns.Events and ns.Events.Register then
        ns.Events.Register("GUILD_ROSTER_UPDATE", GLOG, function() _recomputeIsMaster() end)
        ns.Events.Register("PLAYER_GUILD_UPDATE", GLOG, function() _recomputeIsMaster() end)
        ns.Events.Register("GUILD_RANKS_UPDATE", GLOG, function() _recomputeIsMaster() end)
        -- First pass after entering world, with a couple of delayed retries to wait for data
        ns.Events.Register("PLAYER_ENTERING_WORLD", GLOG, function()
            _recomputeIsMaster()
            if C_Timer and C_Timer.After then
                C_Timer.After(0.5, _recomputeIsMaster)
                C_Timer.After(1.5, _recomputeIsMaster)
                C_Timer.After(3.0, _recomputeIsMaster)
            end
        end)
    end
end

-- ===== Guild Bank balance (local snapshot) =====
do
    local function _ensure()
        if GLOG.EnsureDB then GLOG.EnsureDB() end
        GuildLogisticsDB_Char = GuildLogisticsDB_Char or {}
        GuildLogisticsDB_Char.meta = GuildLogisticsDB_Char.meta or {}
    end

    function GLOG.SetGuildBankBalanceCopper(copper, ts)
        _ensure()
        local v = tonumber(copper) or 0
        GuildLogisticsDB_Char.meta.guildBankCopper = v
        local t = tonumber(ts) or (time and time()) or (GuildLogisticsDB_Char.meta.guildBankTs or 0)
        GuildLogisticsDB_Char.meta.guildBankTs = t
        GuildLogisticsDB_Char.meta.lastModified = time and time() or (GuildLogisticsDB_Char.meta.lastModified or 0)
        if ns.Emit then ns.Emit("guildbank:updated", v, t) end
    end

    function GLOG.GetGuildBankBalanceCopper()
        _ensure()
        local v = GuildLogisticsDB_Char.meta.guildBankCopper
        if v == nil then return nil end
        return tonumber(v) or 0
    end
    
    function GLOG.GetGuildBankTimestamp()
        _ensure()
        return tonumber(GuildLogisticsDB_Char.meta.guildBankTs or 0) or 0
    end

    -- Capture la valeur dès ouverture/maj de la BdG
    local _lastBankCopper = nil
    local _pendingGuildBankCopper = 0 -- delta en cuivre, signe: + dépôt (banque augmente), - retrait (banque diminue)
    local _pendingOrigin = nil       -- "GBANK_DEPOSIT" | "GBANK_WITHDRAW"

    local function _selfMainName()
        local me = (ns and ns.Util and ns.Util.playerFullName and ns.Util.playerFullName()) or (UnitName and UnitName("player")) or nil
        local main = (GLOG.GetMainOf and me and GLOG.GetMainOf(me)) or me
        local resolved = (GLOG.ResolveFullName and main and GLOG.ResolveFullName(main)) or main
        return resolved or me
    end

    local function _applyPendingDeltaIfAny()
        if (_pendingGuildBankCopper or 0) == 0 then return end
        local copper = _pendingGuildBankCopper
        _pendingGuildBankCopper = 0
        local gold = (tonumber(copper) or 0) / 10000
        if gold == 0 then return end

        local target = _selfMainName()
        if not target or target == "" then return end

        -- Affiche une notification locale à l'utilisateur
        if ns and ns.UI and ns.UI.Toast then
            local Tr = ns.Tr or function(s) return s end
            local isDeposit = (_pendingOrigin == "GBANK_DEPOSIT")
            local icon = isDeposit and "Interface\\Icons\\garrison_building_tradingpost" or "Interface\\Icons\\INV_Misc_Coin_01"
            local title = isDeposit and Tr("toast_gbank_deposit_title") or Tr("toast_gbank_withdraw_title")
            local text
                text = (isDeposit and Tr("toast_gbank_deposit_text_fmt") or Tr("toast_gbank_withdraw_text_fmt")):format(ns.UI.MoneyText(math.abs(gold), { h = 11, y = -2 }))
            ns.UI.Toast({
                title = title,
                text = text,
                icon = icon,
                variant = isDeposit and "success" or "warning",
                duration = 15,
                key = string.format("gbank:%s:%d", isDeposit and "dep" or "wd", math.floor((time and time()) or 0)),
            })
        end

        if GLOG.IsMaster and GLOG.IsMaster() then
            if GLOG.GM_AdjustAndBroadcast then GLOG.GM_AdjustAndBroadcast(target, gold) end
        else
            if GLOG.RequestAdjust then GLOG.RequestAdjust(target, gold, { reason = _pendingOrigin or "CLIENT_REQ" }) end
        end
        _pendingOrigin = nil
    end

    local function _capture()
        if not GetGuildBankMoney then return end
        local c = GetGuildBankMoney()
        if type(c) == "number" and c >= 0 then
            -- Note l'ancien pour détecter l'évolution (au besoin)
            _lastBankCopper = _lastBankCopper or (GLOG.GetGuildBankBalanceCopper and GLOG.GetGuildBankBalanceCopper()) or nil
            GLOG.SetGuildBankBalanceCopper(c)
            -- Après mise à jour confirmée par l'API, on applique le delta en attente si c'était nous
            _applyPendingDeltaIfAny()
            _lastBankCopper = c
            return true
        end
        return false
    end

    local function _captureWithRetry(tries, delay)
        tries = tries or 8
        delay = delay or 0.1
        local function step(rem)
            if rem <= 0 then return end
            local ok = _capture()
            if ok then return end
            if C_Timer and C_Timer.After then C_Timer.After(delay, function() step(rem - 1) end) end
        end
        step(tries)
    end

    if ns and ns.Events and ns.Events.Register then
        ns.Events.Register("GUILDBANKFRAME_OPENED", GLOG, function()
            -- Petite latence + retries pour laisser les données arriver
            if C_Timer and C_Timer.After then C_Timer.After(0.05, function() _captureWithRetry(20, 0.1) end) else _capture() end
        end)
        ns.Events.Register("GUILDBANK_UPDATE_MONEY", GLOG, function()
            _capture()
        end)
        -- Sécurité: à la fermeture, on tente une dernière capture
        ns.Events.Register("GUILDBANKFRAME_CLOSED", GLOG, function()
            _capture()
        end)

        -- Retail: ouverture via le manager d'interactions (certains UIs)
        ns.Events.Register("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", GLOG, function(_, _, interactionType)
            if type(Enum) == "table" and type(Enum.PlayerInteractionType) == "table" then
                -- Tolérer différentes clés possibles selon versions (GuildBank, GuildBanker)
                local gb = rawget(Enum.PlayerInteractionType, "GuildBank")
                local gb2 = rawget(Enum.PlayerInteractionType, "GuildBanker")
                local target = gb or gb2
                if target ~= nil and interactionType == target then
                    _captureWithRetry(20, 0.1)
                end
            end
        end)
    end

    -- Hooks locaux: détecter dépôts/retraits faits par le joueur et aligner les soldes via le même pipeline que les boutons UI
    do
        local function safeHook(name, fn)
            if type(hooksecurefunc) == "function" and type(_G[name]) == "function" then
                hooksecurefunc(name, fn)
            end
        end

        -- Dépôt direct dans la banque de guilde (montant en cuivre)
        safeHook("DepositGuildBankMoney", function(amount)
            local v = tonumber(amount) or 0
            if v ~= 0 then 
                _pendingGuildBankCopper = (_pendingGuildBankCopper or 0) + v 
                _pendingOrigin = "GBANK_DEPOSIT"
            end
        end)

        -- Retrait: on prend l'or depuis la banque (montant en cuivre)
        -- Certaines UIs utilisent PickupGuildBankMoney; couvrons ce cas
        safeHook("PickupGuildBankMoney", function(amount)
            local v = tonumber(amount) or 0
            if v ~= 0 then 
                _pendingGuildBankCopper = (_pendingGuildBankCopper or 0) - v 
                _pendingOrigin = "GBANK_WITHDRAW"
            end
        end)

        -- Certains UIs utilisent explicitement WithdrawGuildBankMoney
        safeHook("WithdrawGuildBankMoney", function(amount)
            local v = tonumber(amount) or 0
            if v ~= 0 then 
                _pendingGuildBankCopper = (_pendingGuildBankCopper or 0) - v 
                _pendingOrigin = "GBANK_WITHDRAW"
            end
        end)
    end
end

-- Renvoie le nom de la guilde du joueur s'il est en guilde, sinon nil.
function GLOG.GetCurrentGuildName()
    if IsInGuild and IsInGuild() then
        local gname = GetGuildInfo("player")
        if type(gname) == "string" and gname ~= "" then return gname end
    end
    return nil
end

-- Sync derived cache immediately after manual main/alt changes
if GLOG and GLOG.On then
    GLOG.On("mainalt:changed", function()
        if GLOG.RebuildGuildCacheDerived then GLOG.RebuildGuildCacheDerived() end
        if ns and ns.RefreshAll then ns.RefreshAll() end
    end)
end
