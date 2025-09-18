-- Core/Core/Consumables.lua
-- Clean rebuilt module for consumable (phials & potions) datasets.
-- Mirrors Simc trinket loader architecture: single bootstrap + registry + dataset access.
-- Performance: single pass capture, memory cleanup of raw globals, lazy JSON decode.

local ADDON, ns = ...
ns.Data = ns.Data or {}
ns.Util = ns.Util or {}
local U = ns.Util

local Consum = ns.Data.Consumables or {}
ns.Data.Consumables = Consum

-- Internal stores (fresh rebuild)
Consum._datasets = {}          -- nsKey => dataset
Consum._index    = {}          -- classToken => specKey => kind => dataset
Consum._cache    = { registry = nil }

-- Generated key naming pattern from update_simc_data.py
-- Example: ns.Consum_hunter_beast_mastery_flacons / ns.Consum_hunter_beast_mastery_potions
local KEY_PATTERN = '^Consum_([%w_]+)_([%w_]+)_([%a]+)$' -- class, spec, kind

---------------------------------------------------------------------
-- Utility helpers
---------------------------------------------------------------------
local function parseKey(key)
    return key:match(KEY_PATTERN)
end

local function normalizeLabel(txt)
    if type(txt) ~= 'string' or txt == '' then return '' end
    local cleaned = txt:gsub('_',' '):gsub('-',' '):gsub('(%l)(%u)','%1 %2')
    local out = {}
    for w in cleaned:gmatch('%S+') do
        local lw = w:lower()
        if lw == 'of' or lw == 'the' or lw == 'and' then
            out[#out+1] = lw
        else
            out[#out+1] = lw:gsub('^%l', string.upper)
        end
    end
    return table.concat(out, ' ')
end

local function parseClassID(raw)
    local cid = raw and raw:match('"class_id"%s*:%s*(%d+)')
    return cid and tonumber(cid) or nil
end
local function parseSpecID(raw)
    local sid = raw and raw:match('"spec_id"%s*:%s*(%d+)')
    return sid and tonumber(sid) or nil
end
local function parseTimestamp(raw)
    return raw and raw:match('"timestamp"%s*:%s*"([^"]+)"') or nil
end
local function parseSpecLabel(raw, fallback)
    local spec = raw and raw:match('"spec"%s*:%s*"([^"]+)"') or fallback
    return normalizeLabel(spec or fallback or '')
end

local function canonicalClassToken(classID, rawToken)
    local token = tostring(rawToken or ''):upper()
    if classID and C_CreatureInfo and C_CreatureInfo.GetClassInfo then
        local ok, info = pcall(C_CreatureInfo.GetClassInfo, classID)
        if ok and info and info.classFile then
            token = tostring(info.classFile):upper()
        end
    end
    -- Always strip underscores so multi-word classes unify (DEMON_HUNTER -> DEMONHUNTER, DEATH_KNIGHT -> DEATHKNIGHT)
    -- This prevents duplicate class entries when some datasets lack class_id (raw slug preserved with underscore)
    token = token:gsub('_','')
    return token
end

---------------------------------------------------------------------
-- Registration & bootstrap
---------------------------------------------------------------------
local function registerDataset(nsKey, raw, className, specName, kind)
    if not (nsKey and raw and className and specName and kind) then return end
    local existing = Consum._datasets[nsKey]
    if existing and existing.data then return end -- already decoded

    local classID  = parseClassID(raw)
    local specID   = parseSpecID(raw)
    local ts       = parseTimestamp(raw)
    local label    = parseSpecLabel(raw, specName)
    local canonical = canonicalClassToken(classID, className)

    local ds = existing or {
        nsKey      = nsKey,
        raw        = raw,
        classToken = canonical,  -- normalized game class token (e.g. HUNTER, DEATHKNIGHT)
        className  = className,  -- raw slug form from key (e.g. hunter, death_knight)
        specKey    = specName,   -- raw spec slug (e.g. beast_mastery)
        specID     = specID,
        classID    = classID,
        kind       = kind,       -- 'flacons' or 'potions'
    }
    if not existing then
        Consum._datasets[nsKey] = ds
    elseif not ds.raw and raw then
        ds.raw = raw
    end
    ds.timestamp = ds.timestamp or ts
    ds.specLabel = ds.specLabel or label

    -- Index
    Consum._index[ds.classToken] = Consum._index[ds.classToken] or {}
    local specMap = Consum._index[ds.classToken]
    specMap[ds.specKey] = specMap[ds.specKey] or {}
    specMap[ds.specKey][kind] = ds
end

local function bootstrap()
    for key, value in pairs(ns) do
        if type(value) == 'string' then
            local className, specName, kind = parseKey(key)
            if className and specName and kind then
                registerDataset(key, value, className, specName, kind)
                ns[key] = nil -- free memory
            end
        end
    end
end

---------------------------------------------------------------------
-- Decode (lazy JSON parsing)
---------------------------------------------------------------------
local function decode(ds)
    if not ds or ds.data then return ds end
    local raw = ds.raw
    if not raw and ds.nsKey and ns[ds.nsKey] then
        raw = ns[ds.nsKey]
        ns[ds.nsKey] = nil
    end
    if not raw then return ds end
    local parsed = U.JSONDecode and select(1, U.JSONDecode(raw)) or nil
    if not parsed then return ds end
    ds.data = parsed
    ds.raw = nil
    local meta = parsed.metadata
    if meta and meta.timestamp and not ds.timestamp then
        ds.timestamp = meta.timestamp
    end
    return ds
end

---------------------------------------------------------------------
-- Registry builder
---------------------------------------------------------------------
local function buildRegistry()
    bootstrap()
    local reg = { classes = {}, classOrder = {} }
    for _, ds in pairs(Consum._datasets) do
        local ct = ds.classToken
        if ct and ct ~= '' then
            local ce = reg.classes[ct]
            if not ce then
                ce = { token = ct, classID = ds.classID, label = normalizeLabel(ds.className or ct), specs = {}, specOrder = {} }
                reg.classes[ct] = ce
                reg.classOrder[#reg.classOrder+1] = ct
            elseif (not ce.classID) and ds.classID then
                ce.classID = ds.classID
            end
            local sk = ds.specKey
            local se = ce.specs[sk]
            if not se then
                se = { key = sk, specID = ds.specID, label = ds.specLabel or normalizeLabel(sk), kinds = {}, kindOrder = {} }
                ce.specs[sk] = se
                ce.specOrder[#ce.specOrder+1] = sk
            elseif (not se.specID) and ds.specID then
                se.specID = ds.specID
            end
            if not se.kinds[ds.kind] then
                se.kinds[ds.kind] = ds
                se.kindOrder[#se.kindOrder+1] = ds.kind
            end
        end
    end
    table.sort(reg.classOrder, function(a,b)
        local ca, cb = reg.classes[a], reg.classes[b]
        return tostring(ca and ca.label or a) < tostring(cb and cb.label or b)
    end)
    for _, token in ipairs(reg.classOrder) do
        local ce = reg.classes[token]
        local seen, ordered = {}, {}
        for _, sk in ipairs(ce.specOrder) do if not seen[sk] then seen[sk]=true; ordered[#ordered+1]=sk end end
        table.sort(ordered, function(a,b)
            local sa = ce.specs[a] and ce.specs[a].label or a
            local sb = ce.specs[b] and ce.specs[b].label or b
            return tostring(sa) < tostring(sb)
        end)
        ce.specOrder = ordered
        for _, sk in ipairs(ce.specOrder) do
            local se = ce.specs[sk]
            local seenK, ordK = {}, {}
            for _, kd in ipairs(se.kindOrder) do if not seenK[kd] then seenK[kd]=true; ordK[#ordK+1]=kd end end
            table.sort(ordK)
            se.kindOrder = ordK
        end
    end
    Consum._cache.registry = reg
    return reg
end

---------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------
function Consum.GetRegistry(opts)
    if opts and opts.refresh then Consum._cache.registry = nil end
    return Consum._cache.registry or buildRegistry()
end

local function resolve(classToken, specKey)
    Consum.GetRegistry() -- ensure bootstrap
    if not classToken or not specKey then return nil end
    local token = classToken:upper()
    local idx = Consum._index[token] or Consum._index[token:gsub('_','')] or nil
    if not idx then return nil end
    local specIdx = idx[specKey]
    if not specIdx then
        local want = specKey:lower():gsub('_','')
        for sk, map in pairs(idx) do
            if type(sk)=='string' and sk:lower():gsub('_','') == want then
                specIdx = map; break
            end
        end
    end
    return specIdx
end

function Consum.GetDataset(classToken, specKey, kind)
    if not (classToken and specKey and kind) then return nil end
    local specIdx = resolve(classToken, specKey)
    if not specIdx then return nil end
    local ds = specIdx[kind]
    if not ds then return nil end
    return decode(ds)
end

function Consum.Iterate(classToken, specKey)
    local specIdx = resolve(classToken, specKey) or {}
    local order = { 'flacons', 'potions' }
    local i = 0
    return function()
        i = i + 1
        local k = order[i]
        if not k then return nil end
        return k, decode(specIdx[k])
    end
end

function Consum.GetKinds()
    return { 'flacons', 'potions' }
end

function Consum.Flush()
    Consum._cache.registry = nil
end

return Consum
