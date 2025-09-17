-- Core/Core/Simc.lua
-- SimCraft dataset registry with on-demand JSON decoding.
local ADDON, ns = ...
ns.Data = ns.Data or {}
ns.Util = ns.Util or {}
local U = ns.Util

local Simc = ns.Data.Simc or {}
ns.Data.Simc = Simc

Simc._datasets = Simc._datasets or {}
Simc._index    = Simc._index    or {}
Simc._cache    = Simc._cache    or {}

local function normalizeLabel(text)
    if type(text) ~= "string" or text == "" then return "" end
    local cleaned = text:gsub("_", " "):gsub("-", " ")
    cleaned = cleaned:gsub("(%l)(%u)", "%1 %2")
    local parts = {}
    for word in cleaned:gmatch("%S+") do
        local lower = word:lower()
        if lower == "of" or lower == "the" or lower == "and" then
            parts[#parts + 1] = lower
        else
            parts[#parts + 1] = lower:gsub("^%l", string.upper)
        end
    end
    return table.concat(parts, " ")
end

local function parseSteps(raw)
    local steps = {}
    local block = raw and raw:match("\"simulated_steps\"%s*:%s*%[(.-)%]")
    if block then
        for num in block:gmatch("(%-?%d+)") do
            local n = tonumber(num)
            if n then steps[#steps + 1] = n end
        end
        table.sort(steps)
        local uniq, ordered = {}, {}
        for _, n in ipairs(steps) do
            if not uniq[n] then
                uniq[n] = true
                ordered[#ordered + 1] = n
            end
        end
        steps = ordered
    end
    return steps
end

local function parseTimestamp(raw)
    return raw and raw:match("\"timestamp\"%s*:%s*\"([^\"]+)\"") or nil
end

local function parseClassID(raw)
    local cid = raw and raw:match("\"class_id\"%s*:%s*(%d+)")
    return cid and tonumber(cid) or nil
end

local function parseSpecLabel(raw, fallback)
    local spec = raw and raw:match("\"spec\"%s*:%s*\"([^\"]+)\"") or fallback
    return normalizeLabel(spec or fallback or "")
end

local function parseKey(key)
    return key:match("^Datas_([%w_]+)_([%w_]+)_([%d]+)$")
end

local function registerDataset(nsKey, raw, className, specName, targetCount)
    if not nsKey or not className or not specName or not targetCount then return end

    local dataset = Simc._datasets[nsKey]
    local targetKey = tonumber(targetCount) or targetCount

    if not dataset then
        dataset = {
            nsKey      = nsKey,
            classToken = className:upper(),
            className  = className,
            specKey    = specName,
            targetKey  = targetKey,
        }
        Simc._datasets[nsKey] = dataset
    end

    if raw and dataset.raw == nil and dataset.data == nil then
        dataset.raw = raw
    end

    dataset.classID   = dataset.classID   or parseClassID(raw)
    dataset.specLabel = dataset.specLabel or parseSpecLabel(raw, specName)
    dataset.steps     = dataset.steps     or parseSteps(raw) or {}
    dataset.timestamp = dataset.timestamp or parseTimestamp(raw)

    Simc._index[dataset.classToken] = Simc._index[dataset.classToken] or {}
    Simc._index[dataset.classToken][dataset.specKey] = Simc._index[dataset.classToken][dataset.specKey] or {}
    Simc._index[dataset.classToken][dataset.specKey][targetKey] = dataset
end

local function bootstrap()
    for key, value in pairs(ns) do
        if type(value) == "string" then
            local className, specName, targets = parseKey(key)
            if className and specName and targets then
                registerDataset(key, value, className, specName, targets)
                -- Drop global string reference to avoid duplicates; keep copy in dataset
                ns[key] = nil
            end
        end
    end
end

local function buildRegistry()
    bootstrap()

    local registry = { classes = {}, classOrder = {} }

    for _, dataset in pairs(Simc._datasets) do
        local classToken = dataset.classToken
        local classEntry = registry.classes[classToken]
        if not classEntry then
            classEntry = {
                token     = classToken,
                classID   = dataset.classID,
                rawName   = dataset.className,
                label     = normalizeLabel(dataset.className or classToken),
                specs     = {},
                specOrder = {},
            }
            registry.classes[classToken] = classEntry
            registry.classOrder[#registry.classOrder + 1] = classToken
        elseif (not classEntry.classID) and dataset.classID then
            classEntry.classID = dataset.classID
        end

        local specKey = dataset.specKey
        local specEntry = classEntry.specs[specKey]
        if not specEntry then
            specEntry = {
                key         = specKey,
                label       = dataset.specLabel or normalizeLabel(specKey),
                targets     = {},
                targetOrder = {},
            }
            classEntry.specs[specKey] = specEntry
            classEntry.specOrder[#classEntry.specOrder + 1] = specKey
        end

        specEntry.targets[dataset.targetKey] = dataset
        specEntry.targetOrder[#specEntry.targetOrder + 1] = dataset.targetKey
    end

    table.sort(registry.classOrder, function(a, b)
        local ca, cb = registry.classes[a], registry.classes[b]
        local la = ca and ca.label or a
        local lb = cb and cb.label or b
        return tostring(la) < tostring(lb)
    end)

    for _, classToken in ipairs(registry.classOrder) do
        local classEntry = registry.classes[classToken]
        local seenSpec, orderedSpec = {}, {}
        for _, specKey in ipairs(classEntry.specOrder) do
            if not seenSpec[specKey] then
                seenSpec[specKey] = true
                orderedSpec[#orderedSpec + 1] = specKey
            end
        end
        classEntry.specOrder = orderedSpec

        table.sort(classEntry.specOrder, function(a, b)
            local sa = classEntry.specs[a] and classEntry.specs[a].label or a
            local sb = classEntry.specs[b] and classEntry.specs[b].label or b
            return tostring(sa) < tostring(sb)
        end)

        for _, specKey in ipairs(classEntry.specOrder) do
            local specEntry = classEntry.specs[specKey]
            local seenTarget, orderedTarget = {}, {}
            for _, tk in ipairs(specEntry.targetOrder) do
                if not seenTarget[tk] then
                    seenTarget[tk] = true
                    orderedTarget[#orderedTarget + 1] = tk
                end
            end
            table.sort(orderedTarget, function(a, b)
                local na, nb = tonumber(a), tonumber(b)
                if na and nb then return na < nb end
                if na then return true end
                if nb then return false end
                return tostring(a) < tostring(b)
            end)
            specEntry.targetOrder = orderedTarget
        end
    end

    Simc._cache.registry = registry
    return registry
end

function Simc.GetRegistry(opts)
    if opts and opts.refresh then
        Simc._cache.registry = nil
    end
    if Simc._cache.registry then
        return Simc._cache.registry
    end
    return buildRegistry()
end

local function resolveDataset(classToken, specKey, targetKey)
    Simc.GetRegistry() -- ensures bootstrap and registry
    local classIdx = Simc._index[classToken]
    if not classIdx then return nil end
    local specIdx = classIdx[specKey]
    if not specIdx then return nil end
    local tk = targetKey
    if specIdx[tk] then return specIdx[tk] end
    tk = tonumber(targetKey)
    if tk and specIdx[tk] then return specIdx[tk] end
    return nil
end

function Simc.GetDataset(classToken, specKey, targetKey)
    if not classToken or not specKey or targetKey == nil then return nil, "invalid" end
    local dataset = resolveDataset(classToken, specKey, targetKey)
    if not dataset then return nil, "not_found" end

    if not dataset.data then
        local raw = dataset.raw
        if not raw and dataset.nsKey and ns[dataset.nsKey] then
            raw = ns[dataset.nsKey]
            ns[dataset.nsKey] = nil
        end
        if not raw then
            return nil, "no_source"
        end
        local parsed, err = U.JSONDecode(raw)
        if not parsed then
            return nil, err or "decode_failed"
        end
        dataset.data = parsed
        dataset.raw = nil
        if dataset.nsKey and ns[dataset.nsKey] then
            ns[dataset.nsKey] = nil
        end
        if parsed.simulated_steps and type(parsed.simulated_steps) == "table" then
            dataset.steps = {}
            for _, step in ipairs(parsed.simulated_steps) do
                dataset.steps[#dataset.steps + 1] = tonumber(step) or step
            end
            table.sort(dataset.steps)
        end
        local meta = parsed.metadata
        if meta and meta.timestamp and dataset.timestamp == nil then
            dataset.timestamp = meta.timestamp
        end
    end

    return dataset
end

function Simc.IterateClasses()
    local reg = Simc.GetRegistry()
    local i = 0
    return function()
        i = i + 1
        local token = reg.classOrder[i]
        if not token then return nil end
        return token, reg.classes[token]
    end
end

function Simc.GetClass(token)
    local reg = Simc.GetRegistry()
    return reg.classes[token]
end

function Simc.GetSpec(classToken, specKey)
    local classEntry = Simc.GetClass(classToken)
    if not classEntry then return nil end
    return classEntry.specs[specKey]
end

function Simc.Flush()
    Simc._cache.registry = nil
end

return Simc
