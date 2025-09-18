-- Core/Core/Consumables.lua
-- Lightweight loader/registry for Bloodmallet potions & phials datasets.
-- Mirrors the Simc trinket loader pattern but simpler (only one target set, tiny step list).
local ADDON, ns = ...
ns.Data = ns.Data or {}
ns.Util = ns.Util or {}
local U = ns.Util

local Consum = ns.Data.Consumables or {}
ns.Data.Consumables = Consum

Consum._datasets = Consum._datasets or {}   -- key => dataset
Consum._index    = Consum._index or {}      -- classToken => specKey => dataset
Consum._cache    = Consum._cache or {}

-- Pattern of generated globals: ns.Consum_<class>_<spec>_potions / _flacons
local function parseKey(key)
    return key:match("^Consum_([%w_]+)_([%w_]+)_([%a]+)$") -- class, spec, kind
end

local function normalizeLabel(text)
    if type(text) ~= "string" or text == "" then return "" end
    local cleaned = text:gsub("_", " "):gsub("-", " ")
    cleaned = cleaned:gsub("(%l)(%u)", "%1 %2")
    local parts = {}
    for w in cleaned:gmatch("%S+") do
        local lower = w:lower()
        if lower == "of" or lower == "the" or lower == "and" then
            parts[#parts+1] = lower
        else
            parts[#parts+1] = lower:gsub("^%l", string.upper)
        end
    end
    return table.concat(parts, " ")
end

local function parseClassID(raw)
    local cid = raw and raw:match("\"class_id\"%s*:%s*(%d+)")
    return cid and tonumber(cid) or nil
end

local function parseSpecID(raw)
    local sid = raw and raw:match("\"spec_id\"%s*:%s*(%d+)")
    return sid and tonumber(sid) or nil
end

local function parseTimestamp(raw)
    return raw and raw:match("\"timestamp\"%s*:%s*\"([^\"]+)\"") or nil
end

local function registerDataset(nsKey, raw, classToken, specKey, kind)
    if not (nsKey and raw and classToken and specKey and kind) then return end
    local ds = Consum._datasets[nsKey]
    if not ds then
        ds = { nsKey = nsKey, classToken = classToken:upper(), specKey = specKey, kind = kind }
        Consum._datasets[nsKey] = ds
    end
    ds.raw = ds.raw or raw
    ds.classID = ds.classID or parseClassID(raw)
    ds.specID = ds.specID or parseSpecID(raw)
    ds.timestamp = ds.timestamp or parseTimestamp(raw)
    ds.specLabel = ds.specLabel or normalizeLabel(specKey)

    local token = ds.classToken
    Consum._index[token] = Consum._index[token] or {}
    Consum._index[token][specKey] = Consum._index[token][specKey] or {}
    Consum._index[token][specKey][kind] = ds
end

local function bootstrap()
    for key, value in pairs(ns) do
        if type(value) == "string" then
            local className, specName, kind = parseKey(key)
            if className and specName and kind then
                registerDataset(key, value, className, specName, kind)
                ns[key] = nil
            end
        end
    end
end

local function decode(ds)
    if not ds or ds.data then return ds end
    local raw = ds.raw
    if not raw and ds.nsKey and ns[ds.nsKey] then
        raw = ns[ds.nsKey]
        ns[ds.nsKey] = nil
    end
    if not raw then return ds end
    local parsed, err = U.JSONDecode(raw)
    if not parsed then return ds end
    ds.data = parsed
    ds.raw = nil
    if ds.data and ds.data.metadata and ds.data.metadata.timestamp and not ds.timestamp then
        ds.timestamp = ds.data.metadata.timestamp
    end
    return ds
end

function Consum.GetDataset(classToken, specKey, kind)
    bootstrap()
    if not (classToken and specKey and kind) then return nil end
    local idx = Consum._index[classToken:upper()]
    local specIdx = idx and idx[specKey] or nil
    local ds = specIdx and specIdx[kind] or nil
    if not ds then return nil end
    return decode(ds)
end

function Consum.Iterate(classToken, specKey)
    bootstrap()
    local idx = Consum._index[classToken:upper()] or {}
    local specIdx = idx[specKey] or {}
    local order = { "flacons", "potions" }
    local i = 0
    return function()
        i = i + 1
        local k = order[i]
        if not k then return nil end
        return k, decode(specIdx[k])
    end
end

function Consum.GetKinds()
    return { "flacons", "potions" }
end

-- Build a registry similar to Simc for class/spec listing convenience.
function Consum.GetRegistry(opts)
    bootstrap()
    if opts and opts.refresh then Consum._cache.registry = nil end
    if Consum._cache.registry then return Consum._cache.registry end
    local reg = { classes = {}, classOrder = {} }
    for _, ds in pairs(Consum._datasets) do
        local token = ds.classToken
        local ce = reg.classes[token]
        if not ce then
            ce = { token = token, classID = ds.classID, specs = {}, specOrder = {} }
            reg.classes[token] = ce
            reg.classOrder[#reg.classOrder+1] = token
        end
        local se = ce.specs[ds.specKey]
        if not se then
            se = { key = ds.specKey, specID = ds.specID, label = ds.specLabel, kinds = {}, kindOrder = {} }
            ce.specs[ds.specKey] = se
            ce.specOrder[#ce.specOrder+1] = ds.specKey
        end
        if not se.kinds[ds.kind] then
            se.kinds[ds.kind] = ds
            se.kindOrder[#se.kindOrder+1] = ds.kind
        end
    end
    table.sort(reg.classOrder)
    for _, token in ipairs(reg.classOrder) do
        local ce = reg.classes[token]
        table.sort(ce.specOrder)
        for _, sk in ipairs(ce.specOrder) do
            local se = ce.specs[sk]
            table.sort(se.kindOrder)
        end
    end
    Consum._cache.registry = reg
    return reg
end

return Consum
