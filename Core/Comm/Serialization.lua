-- Module de sérialisation et compression pour GuildLogistics
-- Gère l'encodage/décodage des structures de données et la compression via LibDeflate

local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
local GLOG = ns.GLOG

-- Chargement de LibDeflate (obligatoire)
local LD = assert(LibStub and LibStub:GetLibrary("LibDeflate"), "LibDeflate requis")

-- Seuil de compression : ne pas compresser les tout petits messages
local COMPRESS_MIN_SIZE = 200

-- ===== Petit cache LRU pour payloads déjà compressés/encodés =====
-- Clé: signature simple (FastSig si dispo) + taille brute.
local _SER_CACHE = {}
local _SER_ORDER = {}
local _SER_CAP = 64
local function _serMakeKey(tblOrStr)
    if type(tblOrStr) == 'table' then
        local U = ns.Util
        if U and U.PayloadSig then return 'T:'..U.PayloadSig(tblOrStr) end
        return 'T:'..tostring(#tblOrStr)
    end
    local s = tostring(tblOrStr or '')
    return 'S:'..tostring(#s)..':'..(s:sub(1,8))
end
local function _serCacheGet(key)
    local e = _SER_CACHE[key]
    if not e then return nil end
    e.hits = (e.hits or 0) + 1
    e.ts = (GetTimePreciseSec and GetTimePreciseSec()) or (time and time()) or 0
    return e.payload
end
local function _serCachePut(key, payload)
    if not key or not payload then return end
    if _SER_CACHE[key] then
        _SER_CACHE[key].payload = payload
        _SER_CACHE[key].ts = (GetTimePreciseSec and GetTimePreciseSec()) or (time and time()) or 0
        return
    end
    if #_SER_ORDER >= _SER_CAP then
        -- Expulse l'entrée la plus ancienne (ordre d'insertion simple)
        local old = table.remove(_SER_ORDER, 1)
        if old then _SER_CACHE[old] = nil end
    end
    _SER_ORDER[#_SER_ORDER+1] = key
    _SER_CACHE[key] = { payload = payload, ts = (GetTimePreciseSec and GetTimePreciseSec()) or (time and time()) or 0 }
end

-- ===== Fonctions de compression =====
local function _compressStr(s)
    if not s or #s < COMPRESS_MIN_SIZE then return nil end
    local comp = LD:CompressDeflate(s, { level = 6 })
    return comp and LD:EncodeForWoWAddonChannel(comp) or nil
end

local function _decompressStr(s)
    if not s or s == "" then return nil end
    local decoded = LD:DecodeForWoWAddonChannel(s)
    if not decoded then return nil end
    local ok, raw = pcall(function() return LD:DecompressDeflate(decoded) end)
    return ok and raw or nil
end

-- ===== Sérialisation des tables (format clé-valeur) =====
function GLOG.EncodeKV(t, out)
    -- ✅ Tolérance : si on nous passe déjà une chaîne encodée, renvoyer tel quel
    if type(t) ~= "table" then
        return tostring(t or "")
    end
    out = out or {}

    -- échappement sûr pour les éléments de tableau (gère virgules, crochets, pipes, retours ligne)
    local function escArrElem(s)
        s = tostring(s or "")
        s = s:gsub("\\", "\\\\")     -- antislash
             :gsub("|", "||")        -- pipe
             :gsub("\n", "\\n")      -- newline
             :gsub(",", "\\,")       -- virgule (séparateur d'array)
             :gsub("%]", "\\]")      -- crochet fermant d'array
        return s
    end

    for k, v in pairs(t) do
        local vt = type(v)
        if vt == "table" then
            local arr = {}
            for i = 1, #v do
                arr[#arr+1] = escArrElem(v[i])
            end
            out[#out+1] = k .. "=[" .. table.concat(arr, ",") .. "]"
        else
            v = tostring(v)
            v = v:gsub("|", "||"):gsub("\n", "\\n")
            out[#out+1] = k .. "=" .. v
        end
    end
    return table.concat(out, "|")
end

function GLOG.DecodeKV(s)
    local t = {}
    s = tostring(s or "")
    local len = #s
    local i   = 1
    local buf = {}

    local function flush(part)
        if part == "" then return end
        local eq = part:find("=", 1, true)
        if not eq then return end
        local k = part:sub(1, eq - 1)
        local v = part:sub(eq + 1)

        if v:match("^%[.*%]$") then
            -- Array: on réutilise le parseur existant (échappements \n, \\, \,, \], ||)
            local body = v:sub(2, -2)
            local list, abuf, esc = {}, {}, false
            for p = 1, #body do
                local ch = body:sub(p, p)
                if esc then
                    abuf[#abuf+1] = ch; esc = false
                else
                    if ch == "\\" then
                        esc = true
                    elseif ch == "," then
                        list[#list+1] = table.concat(abuf); abuf = {}
                    else
                        abuf[#abuf+1] = ch
                    end
                end
            end
            list[#list+1] = table.concat(abuf)

            for idx = 1, #list do
                local x = list[idx]
                x = x:gsub("\\n", "\n")
                     :gsub("||", "|")
                     :gsub("\\,", ",")
                     :gsub("\\%]", "]")
                     :gsub("\\\\", "\\")
                list[idx] = x
            end
            t[k] = list
        else
            -- String simple (|| = pipe littéral)
            v = v:gsub("\\n", "\n"):gsub("||", "|")
            t[k] = v
        end
    end

    -- Scanner top-level: '||' = pipe échappé, '|' seul = séparateur
    while i <= len do
        local ch = s:sub(i, i)
        if ch == "|" then
            if s:sub(i + 1, i + 1) == "|" then
                buf[#buf+1] = "|"  -- pipe littéral
                i = i + 2
            else
                flush(table.concat(buf)); buf = {}
                i = i + 1
            end
        else
            buf[#buf+1] = ch
            i = i + 1
        end
    end
    flush(table.concat(buf))
    return t
end

-- ===== Fonctions de compactage pour les messages réseau =====
function GLOG.PackPayloadStr(kv_or_str)
    -- ✅ Si on reçoit déjà une chaîne encodée, ne pas ré-encoder (on compresse éventuellement)
    local plain
    if type(kv_or_str) == "table" then
        plain = GLOG.EncodeKV(kv_or_str)
    else
        plain = tostring(kv_or_str or "")
    end
    -- Lookup cache sur la version brute (non compressée) : si renvoie déjà un wrapper compressé, réutiliser
    local key = _serMakeKey(kv_or_str)
    local cached = _serCacheGet(key)
    if cached then return cached end
    local comp = _compressStr(plain)
    if comp and #comp < #plain then
        local out = "c=z|" .. comp
        _serCachePut(key, out)
        return out
    end
    _serCachePut(key, plain)
    return plain
end

function GLOG.UnpackPayloadStr(s)
    s = tostring(s or "")
    if s:find("^c=z|") then
        local plain = _decompressStr(s:sub(5))
        if plain and plain ~= "" then return plain end
    end
    return s
end

-- ===== Helpers XOR et hash compatibles WoW =====
-- XOR compatible WoW (Lua 5.1) : utilise bit.bxor si présent, sinon fallback pur Lua
local bxor = (bit and bit.bxor) or function(a, b)
    a = tonumber(a) or 0; b = tonumber(b) or 0
    local res, bitv = 0, 1
    while a > 0 or b > 0 do
        local abit, bbit = a % 2, b % 2
        if (abit + bbit) == 1 then res = res + bitv end
        a = math.floor(a / 2); b = math.floor(b / 2); bitv = bitv * 2
    end
    return res
end

function GLOG.HashHint(s)
    s = tostring(s or "")
    local h = 2166136261
    for i = 1, #s do
        h = (bxor(h, s:byte(i)) * 16777619) % 2^32
    end
    return h
end

-- Générateur hex "safe WoW" (évite les overflows de %x sur 32 bits)
function GLOG.RandHex8()
    -- Concatène deux mots 16 bits pour obtenir 8 hex digits sans jamais dépasser INT_MAX
    return string.format("%04x%04x", math.random(0, 0xFFFF), math.random(0, 0xFFFF))
end

-- ===== Aliases pour compatibilité =====
-- Ces fonctions sont utilisées dans d'autres parties du code
GLOG.encodeKV = GLOG.EncodeKV
GLOG.decodeKV = GLOG.DecodeKV
GLOG.packPayloadStr = GLOG.PackPayloadStr
GLOG.unpackPayloadStr = GLOG.UnpackPayloadStr

-- Fonctions globales pour compatibilité avec le code existant
encode = GLOG.EncodeKV
decode = GLOG.DecodeKV
encodeKV = GLOG.EncodeKV
decodeKV = GLOG.DecodeKV
packPayloadStr = GLOG.PackPayloadStr
unpackPayloadStr = GLOG.UnpackPayloadStr
_compressStr = _compressStr
_decompressStr = _decompressStr
