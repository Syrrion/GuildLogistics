local ADDON, ns = ...

-- Module: LootTrackerRolls
-- Responsabilités: Système de jets de dés (Need/Greed/DE/Pass), cache des rolls, parsing des messages système
ns.LootTrackerRolls = ns.LootTrackerRolls or {}

-- === Détection des messages de roll & cache court (joueur|lien) ===
local function _Now() return (time and time()) or 0 end

local function _EscapeForLuaPattern(s)
    return (tostring(s or ""):gsub("([%%%^%$%(%)%.%[%]%*%+%-%?])", "%%%1"))
end

local function _GS2Pat(gs)
    if not gs or gs == "" then return nil end
    local p = _EscapeForLuaPattern(gs)
    p = p:gsub("%%s", "(.+)")    -- capture texte/lien
    p = p:gsub("%%d", "(%%d+)")  -- capture entier - échappement correct
    return p
end

local function _NormPlayer(name)
    name = tostring(name or ""):gsub("%-.*$", ""):lower()
    return name
end

-- Cache: [link][playerLower] = { type="need|greed|disenchant|pass", val=98, ts=... }
local _rollByItem = {}

local function _RememberRoll(player, link, rollType, rollVal)
    if not player or not link or not rollType then return end
    local pn = _NormPlayer(player)
    _rollByItem[link] = _rollByItem[link] or {}
    local rec = _rollByItem[link][pn] or {}
    rec.type = rollType or rec.type
    rec.val  = tonumber(rollVal or rec.val)
    rec.ts   = _Now()
    _rollByItem[link][pn] = rec

    -- petit nettoyage des entrées > 5 min
    local now = rec.ts
    for lnk, map in pairs(_rollByItem) do
        for p, r in pairs(map) do
            if (now - (r.ts or 0)) > 300 then map[p] = nil end
        end
        if not next(map) then _rollByItem[lnk] = nil end
    end
end

local function _GetRollFor(player, link)
    if not player or not link then return nil, nil end
    local pn = _NormPlayer(player)
    local rec = _rollByItem[link] and _rollByItem[link][pn]
    if not rec then return nil, nil end
    return rec.type, rec.val
end

-- Motifs localisés des messages de roll
local _PAT_NEED        = _GS2Pat(LOOT_ROLL_NEED)
local _PAT_GREED       = _GS2Pat(LOOT_ROLL_GREED)
local _PAT_DE          = _GS2Pat(LOOT_ROLL_DISENCHANT)
local _PAT_PASS        = _GS2Pat(LOOT_ROLL_PASSED)
local _PAT_PASS_AUTO   = _GS2Pat(LOOT_ROLL_PASSED_AUTO)

-- "X won: %s with a roll of %d for %s"
local _PAT_WON         = _GS2Pat(LOOT_ROLL_WON)
-- "You rolled %d (Need) for: %s" (pas de nom → on mappe sur player)
local _PAT_ROLLED_NEED = _GS2Pat(LOOT_ROLL_ROLLED_NEED)
local _PAT_ROLLED_GREED= _GS2Pat(LOOT_ROLL_ROLLED_GREED)
local _PAT_ROLLED_DE   = _GS2Pat(LOOT_ROLL_ROLLED_DE)

local function _ParseRollMessage(msg)
    -- Sélections (contiennent toujours le joueur + lien)
    if _PAT_NEED then
        local who, link = msg:match(_PAT_NEED)
        if who and link then return who, link, "need", nil end
    end
    if _PAT_GREED then
        local who, link = msg:match(_PAT_GREED)
        if who and link then return who, link, "greed", nil end
    end
    if _PAT_DE then
        local who, link = msg:match(_PAT_DE)
        if who and link then return who, link, "disenchant", nil end
    end
    if _PAT_PASS then
        local who, link = msg:match(_PAT_PASS)
        if who and link then return who, link, "pass", nil end
    end
    if _PAT_PASS_AUTO then
        local who, link = msg:match(_PAT_PASS_AUTO)
        if who and link then return who, link, "pass", nil end
    end

    -- Gain (on récupère surtout la valeur de jet)
    if _PAT_WON then
        local who, link, val = msg:match(_PAT_WON)
        if who and link and val then return who, link, nil, tonumber(val) end
    end

    -- "You rolled %d ..." (on ne connaît pas le nom → self)
    local me = UnitName and UnitName("player")
    if me and _PAT_ROLLED_NEED then
        local val, link = msg:match(_PAT_ROLLED_NEED)
        if val and link then return me, link, "need", tonumber(val) end
    end
    if me and _PAT_ROLLED_GREED then
        local val, link = msg:match(_PAT_ROLLED_GREED)
        if val and link then return me, link, "greed", tonumber(val) end
    end
    if me and _PAT_ROLLED_DE then
        local val, link = msg:match(_PAT_ROLLED_DE)
        if val and link then return me, link, "disenchant", tonumber(val) end
    end

    return nil
end

-- =========================
-- ===   API du module   ===
-- =========================
ns.LootTrackerRolls = {
    -- Cache des rolls
    RememberRoll = _RememberRoll,
    GetRollFor = _GetRollFor,
    
    -- Parsing des messages de roll
    ParseRollMessage = _ParseRollMessage,
    
    -- Handler : messages système de jets (Need/Greed/DE/Pass/Won)
    HandleChatMsgSystem = function(message)
        local msg = tostring(message or "")
        if msg == "" then return end

        local who, link, rType, rVal = _ParseRollMessage(msg)
        if not who or not link then return end

        -- Si on ne reçoit que la valeur (ex: "X won ... roll of %d"), on tente de
        -- récupérer le type déjà mémorisé pour (joueur, lien) et on met à jour.
        if (not rType) and rVal then
            local prevType = _GetRollFor(who, link)
            if prevType then rType = prevType end
        end

        if rType then
            _RememberRoll(who, link, rType, rVal) -- met en cache 5 min
        end
    end,
}
