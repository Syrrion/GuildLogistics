local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
ns.Util = ns.Util or {}
local GLOG, U = ns.GLOG, ns.Util

-- Mémoïseur léger (faible empreinte mémoire)
GLOG._normCache = GLOG._normCache or setmetatable({}, { __mode = "kv" })

-- Hot path: normalisation de nom ultra-fréquente → on mémorise
function GLOG.NormName(name)
    if not name or name == "" then return nil end
    local key = tostring(name)

    local cached = GLOG._normCache[key]
    if cached ~= nil then return cached end

    local amb = Ambiguate(key, "none")
    amb = strtrim(amb or "")
    if amb == "" then
        GLOG._normCache[key] = nil
        return nil
    end

    local p = amb:find("-", 1, true)
    local base = p and amb:sub(1, p-1) or amb
    local out  = base:lower()

    -- on mémorise à la fois l'entrée brute et l'ambiguée
    GLOG._normCache[key] = out
    if amb ~= key then GLOG._normCache[amb] = out end
    return out
end

-- (exposé plus bas après définition)

-- Corrige les doublons de royaume dans "Nom-Royaume-Royaume-..." -> "Nom-Royaume".
local function CleanFullName(full)
    local s = tostring(full or "")
    local base, tail = s:match("^([^%-]+)%-(.+)$")
    if not base then return s end

    local parts = {}
    for p in tail:gmatch("[^%-]+") do
        if p ~= "" then parts[#parts + 1] = p end
    end
    if #parts <= 1 then return s end

    local function norm(x)
        x = tostring(x or ""):gsub("%s+", ""):gsub("'", "")
        return x:lower()
    end
    local allSame = true
    for i = 2, #parts do
        if norm(parts[i]) ~= norm(parts[1]) then allSame = false; break end
    end
    local realm = allSame and parts[1] or parts[#parts]
    return (base .. "-" .. realm)
end

-- Construit "Nom-Royaume" à partir d'un nom court. Déduit le royaume local si absent.
local function NormalizeFull(name, realm)
    name = tostring(name or "?")
    if name:find("%-") then
        return CleanFullName(name)
    end
    local nrm = realm
    if not nrm or nrm == "" then
        nrm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
    end
    nrm = tostring(nrm):gsub("%s+", ""):gsub("'", "")
    if nrm ~= "" then
        return name .. "-" .. nrm
    end
    return name
end

-- Raccourci d'affichage : "Nom-Royaume" -> "Nom" (Ambiguate si dispo).
function U.ShortenFullName(full)
    local s = tostring(full or "")
    if Ambiguate then
        local ok, short = pcall(Ambiguate, s, "short")
        if ok and type(short) == "string" and short ~= "" then
            return short
        end
    end
    return (s:match("^([^%-]+)") or s)
end

-- Renvoie le nom complet du joueur local "Nom-Royaume" en nettoyant le royaume.
local function playerFullName()
    local n, r = nil, nil
    if UnitFullName then n, r = UnitFullName("player") end
    if n and r and r ~= "" then
        return n .. "-" .. r:gsub("%s+", ""):gsub("'", "")
    end
    local short = (UnitName and UnitName("player")) or "?"
    local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
    if realm ~= "" then
        return short .. "-" .. realm:gsub("%s+", ""):gsub("'", "")
    end
    return short
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

    -- Sinon, résolution via index rapide du cache de guilde (sans inventer le royaume local)
    GLOG._resolveMemo = GLOG._resolveMemo or { ts = -1, byKey = {} }
    local ts = (GLOG.GetGuildCacheTimestamp and GLOG.GetGuildCacheTimestamp()) or 0
    if GLOG._resolveMemo.ts ~= ts then
        GLOG._resolveMemo.ts  = ts
        GLOG._resolveMemo.byKey = {}
    end

    local key = (GLOG.NormName and GLOG.NormName(n)) or n:lower()
    local memo = GLOG._resolveMemo.byKey[key]
    if memo ~= nil then return memo end

    local byKey = GLOG._guildCache and GLOG._guildCache.fullByKey or nil
    if byKey then
        local full = byKey[key]
        if full and full ~= "" then
            local cleaner = ns and ns.Util and ns.Util.CleanFullName
            full = (cleaner and cleaner(full)) or full
            GLOG._resolveMemo.byKey[key] = full
            return full
        end
    end

    -- Fallback: un scan léger des rows (une seule fois par clé/ts), puis mémo.
    do
        local rows = (GLOG.GetGuildRowsCached and GLOG.GetGuildRowsCached()) or {}
        for _, r in ipairs(rows) do
            local full = r.name_raw or r.name_amb or r.name or ""
            if full ~= "" then
                local base = (full:match("^([^%-]+)%-") or full)
                if base and ((base:lower()) == key) then
                    local cleaner = ns and ns.Util and ns.Util.CleanFullName
                    full = (cleaner and cleaner(full)) or full
                    GLOG._resolveMemo.byKey[key] = full
                    return full
                end
            end
        end
    end

    -- Aucune info fiable
    GLOG._resolveMemo.byKey[key] = n
    return n
end

-- Variante stricte : retourne "Nom-Royaume" ou nil si introuvable (aucun fallback local).
function GLOG.ResolveFullNameStrict(name)
    local n = tostring(name or "")
    if n == "" then return nil end

    -- Déjà complet → nettoyage simple
    if n:find("%-") then
        local cleaner = ns and ns.Util and ns.Util.CleanFullName
        return (cleaner and cleaner(n)) or n
    end

    -- 1) Units (rapide, si la personne est dans la portée)
    local function tryUnit(u)
        if not UnitExists or not UnitExists(u) then return nil end
        local nn, rr = UnitName(u)
        if not nn or nn == "" then return nil end
        local ok = ((GLOG.NormName and GLOG.NormName(nn)) or nn:lower())
                   == ((GLOG.NormName and GLOG.NormName(n)) or n:lower())
        if not ok then return nil end
        return (rr and rr ~= "" and (nn.."-"..rr)) or nil
    end
    local full = tryUnit("player") or tryUnit("target") or tryUnit("mouseover") or tryUnit("focus")
    if not full and IsInRaid and IsInRaid() then
        for i=1,40 do full = tryUnit("raid"..i); if full then break end end
    end
    if not full then
        for i=1,4 do full = tryUnit("party"..i); if full then break end end
    end
    if full then
        local cleaner = ns and ns.Util and ns.Util.CleanFullName
        return (cleaner and cleaner(full)) or full
    end

    -- 2) Index rapide du cache guilde (strict)
    do
        local key = (GLOG.NormName and GLOG.NormName(n)) or n:lower()
        local byKey = GLOG._guildCache and GLOG._guildCache.fullByKey or nil
        local full2 = byKey and byKey[key] or nil
        if full2 and full2 ~= "" then
            local cleaner = ns and ns.Util and ns.Util.CleanFullName
            return (cleaner and cleaner(full2)) or full2
        end
    end

    -- 3) Fallback: scan léger des rows en cache (strict)
    do
        local rows = (GLOG.GetGuildRowsCached and GLOG.GetGuildRowsCached()) or {}
        local key = (GLOG.NormName and GLOG.NormName(n)) or n:lower()
        for _, r in ipairs(rows) do
            local full = r.name_raw or r.name_amb or r.name or ""
            if full ~= "" then
                local base = (full:match("^([^%-]+)%-") or full)
                if base and ((base:lower()) == key) then
                    local cleaner = ns and ns.Util and ns.Util.CleanFullName
                    return (cleaner and cleaner(full)) or full
                end
            end
        end
    end

    -- 4) Déduire depuis la DB locale si UNE seule correspondance existe
    do
        if GuildLogisticsDB and GuildLogisticsDB.players then
            local key = (GLOG.NormName and GLOG.NormName(n)) or n:lower()
            local found
            for full,_ in pairs(GuildLogisticsDB.players) do
                local base = full:match("^([^%-]+)%-")
                if base then
                    local bk = (GLOG.NormName and GLOG.NormName(base)) or base:lower()
                    if bk == key then
                        if found and found ~= full then found = "__AMB__"; break end
                        found = full
                    end
                end
            end
            if found and found ~= "__AMB__" then
                local cleaner = ns and ns.Util and ns.Util.CleanFullName
                return (cleaner and cleaner(found)) or found
            end
        end
    end

    -- 5) Strict: inconnu
    return nil
end

-- Force la clé DB au format "Nom-Royaume" (utilise NormalizeFull ou ResolveFullName).
function GLOG.NormalizeDBKey(name)
    return (U.NormalizeFull(name) or GLOG.ResolveFullName(name) or tostring(name or ""))
end

-- Exposition Util + globales utiles
U.NormalizeFull  = NormalizeFull
U.playerFullName = playerFullName
-- Expose aussi CleanFullName pour compat ascendante (certains appels peuvent l'utiliser)
U.CleanFullName = U.CleanFullName or CleanFullName

_G.playerFullName = _G.playerFullName or playerFullName
