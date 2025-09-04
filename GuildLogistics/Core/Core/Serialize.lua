local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
local GLOG = ns.GLOG

-- Retourne (true, n) si 't' est un tableau séquentiel 1..n sans trous, sinon (false, n).
function GLOG.IsArrayTable(t)
    if type(t) ~= "table" then return false, 0 end
    local n = #t
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or k % 1 ~= 0 or k > n then
            return false, n
        end
    end
    return true, n
end

-- Compte le nombre total de clés (y compris non-numériques) d'une table.
function GLOG.TableKeyCount(t)
    if type(t) ~= "table" then return 0 end
    local c = 0
    for _ in pairs(t) do c = c + 1 end
    return c
end

-- Sérialise 'v' en littéral Lua lisible (indenté). Gère tableaux & tables clé/valeur.
function GLOG.SerializeLua(v, depth)
    depth = depth or 0
    local t = type(v)
    if t == "string" then return string.format("%q", v) end
    if t == "number" or t == "boolean" or t == "nil" then return tostring(v) end
    if t ~= "table" then return "\"<" .. t .. ">\"" end

    local indent  = string.rep("    ", depth)
    local indent2 = string.rep("    ", depth + 1)
    local isArray, n = GLOG.IsArrayTable(v)
    local parts = {}

    if isArray then
        for i = 1, n do
            parts[#parts + 1] = indent2 .. GLOG.SerializeLua(v[i], depth + 1)
        end
    else
        for k, val in pairs(v) do
            local key
            if type(k) == "string" and k:match("^%a[%w_]*$") then
                key = k
            else
                key = "[" .. GLOG.SerializeLua(k, 0) .. "]"
            end
            parts[#parts + 1] = indent2 .. key .. " = " .. GLOG.SerializeLua(val, depth + 1)
        end
    end

    if #parts == 0 then return "{}" end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end

-- Évalue un littéral Lua et retourne (valeur, nil) ou (nil, message d'erreur).
function GLOG.DeserializeLua(text)
    local s = tostring(text or "")
    if s == "" then return nil, "empty" end
    local chunk, err = loadstring("return " .. s)
    if not chunk then return nil, err end
    local ok, val = pcall(chunk)
    if not ok then return nil, val end
    return val, nil
end
