local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
ns.Util = ns.Util or {}
local GLOG, U = ns.GLOG, ns.Util

-- Expose aussi CleanFullName pour compat ascendante (certains appels peuvent l'utiliser)
U.CleanFullName = U.CleanFullName or CleanFullName

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
    local n, r = UnitFullName and UnitFullName("player")
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

-- Résout un nom (avec/without royaume) en "Nom-Royaume" exact via DB et unités.
-- opts.strict = true => n'ajoute pas le royaume local si introuvable.
function GLOG.ResolveFullName(name, opts)
    opts = opts or {}
    local raw = tostring(name or "")
    if raw == "" then return nil end

    if raw:find("%-") then
        return CleanFullName(raw)
    end

    local baseKey = (GLOG.NormName and GLOG.NormName(raw)) or raw:lower()

    if GuildLogisticsDB and GuildLogisticsDB.players then
        local candidate = nil
        for full in pairs(GuildLogisticsDB.players) do
            local base = full:match("^([^%-]+)%-.+$")
            if base and base:lower() == baseKey then
                if candidate and candidate ~= full then
                    candidate = "__AMB__"; break
                end
                candidate = full
            end
        end
        if candidate and candidate ~= "__AMB__" then return candidate end
    end

    local function tryUnit(u)
        if not UnitExists or not UnitExists(u) then return nil end
        local n, r = UnitName(u)
        if not n or n == "" then return nil end
        local k = (GLOG.NormName and GLOG.NormName(n)) or n:lower()
        if k ~= baseKey then return nil end
        local realm = (r and r ~= "" and r)
                   or (GetNormalizedRealmName and GetNormalizedRealmName())
                   or (GetRealmName and GetRealmName())
                   or ""
        realm = tostring(realm):gsub("%s+", ""):gsub("'", "")
        if realm == "" then return nil end
        return n .. "-" .. realm
    end

    local full = tryUnit("player") or tryUnit("target") or tryUnit("mouseover")
    if not full then
        for i = 1, 40 do full = tryUnit("raid" .. i); if full then break end end
    end
    if not full then
        for i = 1, 4 do full = tryUnit("party" .. i); if full then break end end
    end
    if full then return full end

    if opts.strict then return nil end

    local realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or ""
    realm = tostring(realm):gsub("%s+", ""):gsub("'", "")
    if realm == "" then return raw end
    return raw .. "-" .. realm
end

-- Force la clé DB au format "Nom-Royaume" (utilise NormalizeFull ou ResolveFullName).
function GLOG.NormalizeDBKey(name)
    return (U.NormalizeFull(name) or GLOG.ResolveFullName(name) or tostring(name or ""))
end

-- Exposition Util + globales utiles
U.NormalizeFull  = NormalizeFull
U.playerFullName = playerFullName

_G.playerFullName = _G.playerFullName or playerFullName
