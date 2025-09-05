local ADDON, ns = ...

-- Module: LootTrackerState
-- Responsabilités: Gestion de l'état persistant, configuration utilisateur, cache M+
ns.LootTrackerState = ns.LootTrackerState or {}

-- =========================
-- ===   STORE per-char  ===
-- =========================
local function _Store()
    GuildLogisticsDatas_Char = GuildLogisticsDatas_Char or {}
    local s = GuildLogisticsDatas_Char
    s.equipLoots = s.equipLoots or {}  -- liste d'entrées
    return s.equipLoots
end

-- === Config (par perso) pour le log de butin =========================
local function _Config()
    GuildLogisticsDatas_Char = GuildLogisticsDatas_Char or {}
    local s = GuildLogisticsDatas_Char
    s.config = s.config or {}
    local c = s.config
    -- Valeurs par défaut
    local EPIC = tonumber((Enum and Enum.ItemQuality and Enum.ItemQuality.Epic) or 4) or 4
    if c.lootMinQuality      == nil then c.lootMinQuality      = EPIC end                    -- épique par défaut
    if c.lootMinReqLevel     == nil then c.lootMinReqLevel     = 80 end
    if c.lootEquippableOnly  == nil then c.lootEquippableOnly  = true end
    if c.lootMinItemLevel    == nil then c.lootMinItemLevel    = 0 end
    if c.lootInstanceOnly    == nil then c.lootInstanceOnly    = true end
    return c
end

-- =========================
-- ===   M+ level cache  ===
-- =========================
local _mplusLevelLast = 0  -- Dernier niveau M+ vu (persiste tant qu'on n'a pas un nouveau > 0)
local _mplusLevel = 0      -- Niveau M+ courant (API live)

local function _SaveLastMPlus(level)
    level = tonumber(level or 0) or 0
    if level <= 0 then return end
    _mplusLevelLast = level
    GuildLogisticsDatas_Char = GuildLogisticsDatas_Char or {}
    local s = GuildLogisticsDatas_Char
    s._mplus = s._mplus or {}
    s._mplus.last = level
    s._mplus.ts   = (time and time()) or 0
end

local function _LoadLastMPlus()
    GuildLogisticsDatas_Char = GuildLogisticsDatas_Char or {}
    local s = GuildLogisticsDatas_Char
    local last = tonumber(s._mplus and s._mplus.last) or 0
    local ts   = tonumber(s._mplus and s._mplus.ts) or 0
    -- On accepte une valeur récente (< 3h) pour du backfill post-run
    if last > 0 and ts > 0 then
        local now = (time and time()) or 0
        if now == 0 or (now - ts) <= (3 * 60 * 60) then
            return last
        end
    end
    return 0
end

local function _UpdateActiveKeystoneLevel()
    local level = 0
    if C_ChallengeMode and C_ChallengeMode.GetActiveKeystoneInfo then
        local _, lv = C_ChallengeMode.GetActiveKeystoneInfo()
        level = tonumber(lv or 0) or 0
    end
    _mplusLevel = level
    if level > 0 then
        _SaveLastMPlus(level)
    end
end

-- =========================
-- ===   API du module   ===
-- =========================
ns.LootTrackerState = {
    -- Accès au store des loots
    GetStore = _Store,
    
    -- Accès à la configuration
    GetConfig = _Config,
    
    -- Gestion du niveau M+
    UpdateActiveKeystoneLevel = _UpdateActiveKeystoneLevel,
    SaveLastMPlus = _SaveLastMPlus,
    LoadLastMPlus = _LoadLastMPlus,
    
    -- Getters pour les niveaux M+
    GetCurrentMPlusLevel = function() return _mplusLevel end,
    GetLastMPlusLevel = function() return _mplusLevelLast end,
    
    -- Getter public pour l'UI et les fallbacks Core
    GetActiveKeystoneLevel = function()
        -- 1) Essai API "live"
        if C_ChallengeMode then
            if C_ChallengeMode.GetActiveKeystoneInfo then
                local _, lv = C_ChallengeMode.GetActiveKeystoneInfo()
                local v = tonumber(lv or 0) or 0
                if v > 0 then _SaveLastMPlus(v); return v end
            end
            -- 1b) Essai info de complétion (post-coffre)
            if C_ChallengeMode.GetCompletionInfo then
                local ok, a,b,c,d,e,f,g = pcall(C_ChallengeMode.GetCompletionInfo)
                if ok then
                    -- Cherche un entier plausible (2..50) dans les retours
                    local candidates = {a,b,c,d,e,f,g}
                    for _,vv in ipairs(candidates) do
                        local n = tonumber(vv)
                        if n and n >= 2 and n <= 50 then _SaveLastMPlus(n); return n end
                    end
                end
            end
        end
        -- 2) Valeur courante suivie (session)
        if (_mplusLevel or 0) > 0 then return _mplusLevel end
        -- 3) Dernière valeur connue dans la session
        if (_mplusLevelLast or 0) > 0 then return _mplusLevelLast end
        -- 4) Fallback persistant (<=3h)
        local saved = _LoadLastMPlus() or 0
        if saved > 0 then return saved end
        return 0
    end,
    
    -- Essaie de compléter le niveau M+ pour les entrées récentes avec ce lien
    BackfillMPlus = function(link)
        if not link then return end
        local lv = tonumber(ns.LootTrackerState.GetActiveKeystoneLevel()) or 0
        if lv <= 0 then return end
        local list = _Store()
        -- on ne parcourt que les 30 premières lignes pour éviter le coût
        local maxn = math.min(#list, 30)
        local changed = false
        for i = 1, maxn do
            local it = list[i]
            if it and it.link == link and tonumber(it.diffID or 0) == 8 then
                if tonumber(it.mplus or 0) == 0 then
                    it.mplus = lv
                    changed = true
                end
            end
        end
        if changed and ns.UI and ns.UI.RefreshAll then ns.UI.RefreshAll() end
    end,
}
