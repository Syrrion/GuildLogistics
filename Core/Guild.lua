local ADDON, ns = ...
ns.CDZ = ns.CDZ or {}
local CDZ = ns.CDZ

function CDZ.NormName(name)
    if not name then return nil end
    local amb = Ambiguate(name, "none")
    amb = strtrim(amb or "")
    local p = amb:find("-")
    local base = p and amb:sub(1, p-1) or amb
    return base:lower()
end

-- --------- Cache guilde ---------
CDZ._guildCache = CDZ._guildCache or { rows=nil, mains=nil, byName={}, mainsClass={}, ts=0 }

local function aggregateRows(rows)
    local mainsMap, mainsClass = {}, {}

    for _, r in ipairs(rows or {}) do
        local noteMain = r.remark and strtrim(r.remark) or ""
        local key = (noteMain ~= "" and CDZ.NormName(noteMain)) or nil
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
            if CDZ.NormName(r.name_amb or r.name_raw) == key then
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
        local name, _, _, _, _, _, note, _, online, _, classFileName, _, _, isMobile = GetGuildRosterInfo(i)
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
            last_y = y, last_m = m, last_d = d, last_h = h,
            retCount = retCount,
            daysDerived = daysDerived,
            hoursDerived = hoursDerived,
        })

    end

    local agg, mainsClass = aggregateRows(rows)
    CDZ._guildCache.rows       = rows
    CDZ._guildCache.mains      = agg
    CDZ._guildCache.mainsClass = mainsClass or {}
    CDZ._guildCache.byName     = {}

    for _, rr in ipairs(rows) do
        local amb = rr.name_amb or rr.name_raw
        local kFull = CDZ.NormName(amb)                 -- ex: "aratoryx"
        local mainKey = (rr.remark and CDZ.NormName(rr.remark)) or ""

        local rec = { class = rr.class, main = mainKey or "" }
        if kFull and kFull ~= "" then CDZ._guildCache.byName[kFull] = rec end
        -- Par sécurité : indexe aussi la clé exacte lowercase si l’API remonte déjà "Name-Realm"
        local exactLower = amb and amb:lower() or nil
        if exactLower and exactLower ~= kFull then
            CDZ._guildCache.byName[exactLower] = CDZ._guildCache.byName[exactLower] or rec
        end
    end

    CDZ._guildCache.ts = time()

    local cbs = self.callbacks
    self.callbacks = {}
    for _, cb in ipairs(cbs) do pcall(cb, true) end
end)

function CDZ.RefreshGuildCache(cb)
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


function CDZ.GetGuildMainsAggregatedCached()
    return (CDZ._guildCache and CDZ._guildCache.mains) or {}
end

function CDZ.GetGuildRowsCached()
    return (CDZ._guildCache and CDZ._guildCache.rows) or {}
end

function CDZ.IsGuildCacheReady()
    local c = CDZ._guildCache
    return c and c.rows and #c.rows > 0
end

function CDZ.GetGuildCacheTimestamp()
    local c = CDZ._guildCache
    return (c and c.ts) or 0
end

-- helper utilisé par l’onglet Joueurs
function CDZ.GetGuildMainsAggregated()
    return CDZ.GetGuildMainsAggregatedCached()
end

function CDZ.GetMainOf(name)
    local k = CDZ.NormName(name)
    local by = CDZ._guildCache and CDZ._guildCache.byName
    local e = by and k and by[k]
    return (e and e.main ~= "" and e.main) or nil
end

function CDZ.GetNameClass(name)
    local c = CDZ._guildCache
    if not c then return nil end
    local by = c.byName or {}
    local k  = CDZ.NormName(name)
    local e  = k and by[k]
    local mainKey = e and e.main
    -- 1) classe du main (clé déjà normalisée) ; 2) sinon classe du perso scanné
    local cls = (mainKey and c.mainsClass and c.mainsClass[mainKey]) or (e and e.class)
    return cls
end

function CDZ.GetNameStyle(name)
    local class = CDZ.GetNameClass(name)
    local col = (RAID_CLASS_COLORS and class and RAID_CLASS_COLORS[class]) or {r=1,g=1,b=1}
    local coords = CLASS_ICON_TCOORDS and class and CLASS_ICON_TCOORDS[class] or nil
    return class, col.r, col.g, col.b, coords
end