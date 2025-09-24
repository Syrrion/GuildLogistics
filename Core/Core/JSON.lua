-- Core/Core/JSON.lua
-- Lightweight JSON decoding helpers exposed via ns.Util.
local ADDON, ns = ...
ns.Util = ns.Util or {}
local U = ns.Util

local function utf8FromCodePoint(cp)
    if cp <= 0x7F then
        return string.char(cp)
    elseif cp <= 0x7FF then
        local b1 = 0xC0 + math.floor(cp / 0x40)
        local b2 = 0x80 + (cp % 0x40)
        return string.char(b1, b2)
    elseif cp <= 0xFFFF then
        local b1 = 0xE0 + math.floor(cp / 0x1000)
        local b2 = 0x80 + (math.floor(cp / 0x40) % 0x40)
        local b3 = 0x80 + (cp % 0x40)
        return string.char(b1, b2, b3)
    elseif cp <= 0x10FFFF then
        local b1 = 0xF0 + math.floor(cp / 0x40000)
        local b2 = 0x80 + (math.floor(cp / 0x1000) % 0x40)
        local b3 = 0x80 + (math.floor(cp / 0x40) % 0x40)
        local b4 = 0x80 + (cp % 0x40)
        return string.char(b1, b2, b3, b4)
    end
    return ""
end

local function decode(str)
    if type(str) ~= "string" then return nil, "not_string" end
    local i, len = 1, #str

    local function peek()
        return str:sub(i, i)
    end

    local function advance(n)
        i = i + (n or 1)
    end

    local function skipWhitespace()
        while i <= len do
            local c = peek()
            if c == " " or c == "\n" or c == "\r" or c == "\t" then
                advance()
            else
                break
            end
        end
    end

    local parseValue

    local function parseUnicodeEscape()
        local hex = str:sub(i, i + 3)
        if #hex < 4 then return nil, "bad_unicode" end
        local cp = tonumber(hex, 16)
        if not cp then return nil, "bad_unicode" end
        advance(4)
        if cp >= 0xD800 and cp <= 0xDBFF then
            if str:sub(i, i) == "\\" and str:sub(i + 1, i + 1) == "u" then
                advance(2)
                local hex2 = str:sub(i, i + 3)
                local cp2 = tonumber(hex2, 16)
                if cp2 and cp2 >= 0xDC00 and cp2 <= 0xDFFF then
                    advance(4)
                    cp = ((cp - 0xD800) * 0x400) + (cp2 - 0xDC00) + 0x10000
                else
                    return nil, "bad_surrogate"
                end
            else
                return nil, "missing_surrogate"
            end
        end
        return utf8FromCodePoint(cp)
    end

    local function parseString()
        -- Optimized string parser: scan chunks between escapes / quotes instead of char-by-char loop
        advance() -- skip opening quote
        local buf = {}
        local startPos = i
        while i <= len do
            local nextPos = string.find(str, '[\\"]', i) -- next backslash or quote
            if not nextPos then
                return nil, "unterminated_string"
            end
            local segment = str:sub(i, nextPos - 1)
            if #segment > 0 then buf[#buf+1] = segment end
            local ch = str:sub(nextPos, nextPos)
            i = nextPos + 1
            if ch == '"' then
                return table.concat(buf)
            else -- escape sequence
                local esc = peek()
                if esc == '"' or esc == '\\' or esc == '/' then
                    buf[#buf+1] = esc
                    advance()
                elseif esc == 'b' then buf[#buf+1] = '\b'; advance()
                elseif esc == 'f' then buf[#buf+1] = '\f'; advance()
                elseif esc == 'n' then buf[#buf+1] = '\n'; advance()
                elseif esc == 'r' then buf[#buf+1] = '\r'; advance()
                elseif esc == 't' then buf[#buf+1] = '\t'; advance()
                elseif esc == 'u' then
                    advance()
                    local uch, err = parseUnicodeEscape()
                    if err then return nil, err end
                    buf[#buf+1] = uch
                else
                    return nil, 'bad_escape'
                end
            end
        end
        return nil, 'unterminated_string'
    end

    local function parseNumber()
        local start = i
        local c = peek()
        if c == "-" then advance(); c = peek() end
        if c < "0" or c > "9" then return nil, "bad_number" end
        if c == "0" then
            advance()
        else
            while i <= len and str:sub(i, i):match("%d") do advance() end
        end
        if str:sub(i, i) == "." then
            advance()
            if not str:sub(i, i):match("%d") then return nil, "bad_number" end
            while i <= len and str:sub(i, i):match("%d") do advance() end
        end
        local ch = str:sub(i, i)
        if ch == "e" or ch == "E" then
            advance()
            local sign = str:sub(i, i)
            if sign == "+" or sign == "-" then advance() end
            if not str:sub(i, i):match("%d") then return nil, "bad_number" end
            while i <= len and str:sub(i, i):match("%d") do advance() end
        end
        local num = tonumber(str:sub(start, i - 1))
        if not num then return nil, "bad_number" end
        return num
    end

    local function parseLiteral(lit, val)
        if str:sub(i, i + #lit - 1) == lit then
            advance(#lit)
            return val
        end
        return nil, "bad_literal"
    end

    local function parseArray()
        advance()
        local arr = {}
        skipWhitespace()
        if peek() == "]" then
            advance()
            return arr
        end
        while true do
            skipWhitespace()
            local v, err = parseValue()
            if err then return nil, err end
            arr[#arr + 1] = v
            skipWhitespace()
            local ch = peek()
            if ch == "," then
                advance()
            elseif ch == "]" then
                advance()
                break
            else
                return nil, "bad_array"
            end
        end
        return arr
    end

    local function parseObject()
        advance()
        local obj = {}
        skipWhitespace()
        if peek() == "}" then
            advance()
            return obj
        end
        while true do
            skipWhitespace()
            if peek() ~= '"' then return nil, "bad_key" end
            local key, err = parseString()
            if err then return nil, err end
            skipWhitespace()
            if peek() ~= ":" then return nil, "bad_key" end
            advance()
            skipWhitespace()
            local val, err2 = parseValue()
            if err2 then return nil, err2 end
            if key ~= nil then obj[key] = val end
            skipWhitespace()
            local ch = peek()
            if ch == "," then
                advance()
            elseif ch == "}" then
                advance()
                break
            else
                return nil, "bad_object"
            end
        end
        return obj
    end

    function parseValue()
        skipWhitespace()
        local ch = peek()
        if ch == "" then return nil, "eof" end
        if ch == '"' then return parseString() end
        if ch == "{" then return parseObject() end
        if ch == "[" then return parseArray() end
        if ch == "t" then return parseLiteral("true", true) end
        if ch == "f" then return parseLiteral("false", false) end
        if ch == "n" then return parseLiteral("null", nil) end
        if ch == "-" or ch:match("%d") then return parseNumber() end
        return nil, "bad_value"
    end

    skipWhitespace()
    local result, err = parseValue()
    if err then return nil, err end
    skipWhitespace()
    if i <= len then
        if str:sub(i):match("^%s*$") then
            return result
        end
        return nil, "trailing"
    end
    return result
end

function U.JSONDecode(str)
    -- Optional timing instrumentation (debug builds only)
    local t0 = debugprofilestop and debugprofilestop() or nil
    local v, err = decode(str)
    if t0 and GuildLogisticsUI and GuildLogisticsUI.debugEnabled then
        U._jsonStats = U._jsonStats or { last = 0, max = 0 }
        local dt = (debugprofilestop() - t0)
        U._jsonStats.last = dt
        if dt > (U._jsonStats.max or 0) then U._jsonStats.max = dt end
    end
    return v, err
end

function U.JSONDecodeSafe(str)
    local ok, value, err = pcall(decode, str)
    if not ok then
        return nil, value
    end
    return value, err
end

-- Keep decode locally accessible for advanced callers if needed.
U._JSONDecodeRaw = decode

