-- ===================================================
-- Core/Player/MainAlt.lua - Gestion Main/Alt (manuel + auto)
-- Stockage compact:
--   GuildLogisticsDB.account {
--     version = 2,
--     mains = { [uid] = {} or { alias = "..." } }, -- la présence d'une table marque un MAIN
--     altToMain = { [altUid] = mainUid }
--   }
-- Pas de main_uid par joueur dans DB.players (épargne mémoire et sync plus légère)
-- ===================================================

local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
local GLOG = ns.GLOG

-- Raccourcis utilitaires
local function EnsureDB() if GLOG.EnsureDB then GLOG.EnsureDB() end end
local function Norm(x) return (GLOG.NormName and GLOG.NormName(x)) or (tostring(x or "")):lower() end

-- Accès à la table compacte account
local function _MA()
    EnsureDB()
    _G.GuildLogisticsDB.account = _G.GuildLogisticsDB.account or { mains = {}, altToMain = {} }
    local t = _G.GuildLogisticsDB.account
    t.mains     = t.mains     or {}
    t.altToMain = t.altToMain or {}
    t.shared    = t.shared    or {}   -- données partagées par UID (solde, version, ...)
    return t
end

local function _uidFor(name)
    if not name or name == "" then return nil end
    local full = (GLOG and GLOG.ResolveFullName and GLOG.ResolveFullName(name)) or name
    return (GLOG.GetOrAssignUID and GLOG.GetOrAssignUID(full)) or nil
end

local function _nameFor(uid)
    return (GLOG.GetNameByUID and GLOG.GetNameByUID(uid)) or nil
end

-- Détection automatique par note non utilisée; uniquement des liens manuels, la note sert aux suggestions via GLOG.SuggestAltsForMain

-- ====== Helpers DB ======
-- Helpers internes pour limiter l'empreinte mémoire de la table players
local function _ensurePlayerRec(name)
    EnsureDB()
    local full = (GLOG and GLOG.ResolveFullName and GLOG.ResolveFullName(name)) or name
    local key = tostring(full or "")
    local db = _G.GuildLogisticsDB
    db.players = db.players or {}
    db.players[key] = db.players[key] or { reserved = true }
    if not db.players[key].uid then
        db.players[key].uid = (GLOG.GetOrAssignUID and GLOG.GetOrAssignUID(key)) or nil
    end
    return db.players[key], key, db.players[key].uid
end

-- ====== API publique Main/Alt ======

-- Confirme un joueur comme MAIN (main_uid = uid)
function GLOG.SetAsMain(name)
    if not name or name == "" then return false end
    local _, key, uid = _ensurePlayerRec(name)
    uid = tonumber(uid)
    if not uid then return false end
    local MA = _MA()
    MA.mains[uid] = (type(MA.mains[uid]) == "table") and MA.mains[uid] or {}
    MA.altToMain[uid] = nil -- un main ne peut pas être alt
    if ns.Emit then ns.Emit("mainalt:changed", "set-main", key, uid) end
    if GLOG.BroadcastSetAsMain then GLOG.BroadcastSetAsMain(key) end
    return true
end

-- Associe un ALT à un MAIN sélectionné
function GLOG.AssignAltToMain(altName, mainName)
    if not altName or altName == "" or not mainName or mainName == "" then return false end
    local _, mKey, mainUID = _ensurePlayerRec(mainName)
    local _, aKey, altUID  = _ensurePlayerRec(altName)
    mainUID = tonumber(mainUID); altUID = tonumber(altUID)
    if not mainUID or not altUID then return false end
    local MA = _MA()
    MA.mains[mainUID] = (type(MA.mains[mainUID]) == "table") and MA.mains[mainUID] or {}
    MA.altToMain[altUID] = mainUID
    MA.mains[altUID] = nil -- un alt ne doit pas être dans le set des mains
    if ns.Emit then ns.Emit("mainalt:changed", "assign-alt", aKey, mainUID) end
    if GLOG.BroadcastAssignAlt then GLOG.BroadcastAssignAlt(aKey, mKey or mainName) end
    return true
end

-- Dissocie un ALT (retour au pool)
function GLOG.UnassignAlt(name)
    local _, key, uid = _ensurePlayerRec(name)
    uid = tonumber(uid)
    if not uid then return false end
    local MA = _MA()
    MA.altToMain[uid] = nil
    if ns.Emit then ns.Emit("mainalt:changed", "unassign-alt", key) end
    if GLOG.BroadcastUnassignAlt then GLOG.BroadcastUnassignAlt(key) end
    return true
end

-- Supprime un MAIN confirmé et dissocie tous ses alts
function GLOG.RemoveMain(name)
    local _, key, uid = _ensurePlayerRec(name)
    uid = tonumber(uid)
    if not uid then return false end
    local MA = _MA()
    -- Dissocie tous les alts pointant vers ce main
    for a, m in pairs(MA.altToMain) do if tonumber(m) == uid then MA.altToMain[a] = nil end end
    MA.mains[uid] = nil
    if ns.Emit then ns.Emit("mainalt:changed", "remove-main", key, uid) end
    if GLOG.BroadcastRemoveMain then GLOG.BroadcastRemoveMain(key) end
    return true
end

-- Liste des mains confirmés
function GLOG.GetConfirmedMains()
    EnsureDB()
    local MA = _MA()
    local out = {}
    for uid, isMain in pairs(MA.mains or {}) do
        if isMain then
            local name = _nameFor(uid)
            if name and name ~= "" then out[#out+1] = { name = name, uid = uid } end
        end
    end
    table.sort(out, function(a,b) return (a.name or ""):lower() < (b.name or ""):lower() end)
    return out
end

-- Liste des alts d'un main
function GLOG.GetAltsOf(mainName)
    local _, _k, mainUID = _ensurePlayerRec(mainName)
    mainUID = tonumber(mainUID)
    if not mainUID then return {} end
    local MA = _MA()
    local out = {}
    for altUID, m in pairs(MA.altToMain or {}) do
        if tonumber(m) == mainUID and tonumber(altUID) ~= mainUID then
            local name = _nameFor(altUID)
            if name and name ~= "" then out[#out+1] = { name = name, uid = tonumber(altUID) } end
        end
    end
    table.sort(out, function(a,b) return (a.name or ""):lower() < (b.name or ""):lower() end)
    return out
end

-- Joueurs non assignés (pool)
function GLOG.GetUnassignedPool()
    EnsureDB()
    local MA = _MA()
    local out = {}
    for full, rec in pairs((_G.GuildLogisticsDB and _G.GuildLogisticsDB.players) or {}) do
        local uid = tonumber(rec and rec.uid) or (GLOG.GetOrAssignUID and GLOG.GetOrAssignUID(full)) or nil
        if uid and not MA.mains[uid] and (MA.altToMain[uid] == nil) then
            out[#out+1] = { name = full }
        end
    end
    table.sort(out, function(a,b) return (a.name or ""):lower() < (b.name or ""):lower() end)
    return out
end

-- Suggestions: propose les joueurs du pool dont la note de guilde pointe sur ce main
function GLOG.SuggestAltsForMain(mainName)
    -- Suggestions basées UNIQUEMENT sur la note de guilde, limitées au pool
    if not mainName or mainName == "" then return {} end
    local target = Norm(mainName)
    local pool = (GLOG.GetUnassignedPool and GLOG.GetUnassignedPool()) or {}
    local poolSet = {}
    for _, p in ipairs(pool) do poolSet[Norm(p.name)] = p end
    local rows = (GLOG.GetGuildRowsCached and GLOG.GetGuildRowsCached()) or {}
    local out = {}
    for _, gr in ipairs(rows) do
        local full = gr.name_amb or gr.name_raw
        if full and full ~= "" then
            local key = gr.name_key or (GLOG.NormName and GLOG.NormName(full)) or tostring(full):lower()
            local p = poolSet[key]
            if p then
                local note = (gr.remark and strtrim(gr.remark)) or ""
                if note ~= "" then
                    local nk = (GLOG.NormName and GLOG.NormName(note)) or string.lower(note)
                    if nk == target then out[#out+1] = p end
                end
            end
        end
    end
    table.sort(out, function(a,b) return (a.name or ""):lower() < (b.name or ""):lower() end)
    return out
end

function GLOG.GetMainOf(name)
    if not name or name == "" then return nil end
    EnsureDB()
    -- 1) Lien manuel (table compacte)
    do
        local uid = _uidFor(name)
        local MA = _MA()
        if uid then
            if MA.mains[uid] then
                local n = _nameFor(uid)
                if n and n ~= "" then return n end
            end
            local m = uid and MA.altToMain[uid] or nil
            if m then
                local n = _nameFor(m)
                if n and n ~= "" then return n end
            end
        end
    end
    -- 2) Retour par défaut: self (pas de détection automatique par note)
    return name
end

-- ➕ Helper: a-t-on un lien manuel (main ou alt) sur ce joueur ?
function GLOG.HasManualLink(name)
    local uid = _uidFor(name)
    if not uid then return false end
    local MA = _MA()
    if MA.mains[uid] then return true end
    if MA.altToMain[uid] ~= nil then return true end
    return false
end

-- Promotion d'un ALT en MAIN
-- Effets:
--  - Transfère le solde du main actuel vers l'alt promu
--  - L'alt devient MAIN ; l'ancien MAIN devient ALT du nouveau
--  - Tous les anciens alts du main pointent maintenant vers le nouveau main
--  - Émet l'événement "mainalt:changed", op="promote-alt"
function GLOG.PromoteAltToMain(altName, currentMainName)
    if not altName or altName == "" then return false end
    EnsureDB()
    local _, _, altUID  = _ensurePlayerRec(altName)
    local _, _, mainUID = _ensurePlayerRec(currentMainName)
    altUID  = tonumber(altUID)
    mainUID = tonumber(mainUID)
    if not altUID then return false end

    local MA = _MA()
    -- Si currentMainName non fourni ou invalide, tenter de déduire via mapping
    if not mainUID or (MA.altToMain[altUID] and tonumber(MA.altToMain[altUID]) ~= mainUID) then
        mainUID = tonumber(MA.altToMain[altUID]) or mainUID
    end
    if not mainUID then return false end
    if tonumber(MA.altToMain[altUID]) ~= mainUID then return false end -- pas un alt de ce main

    -- Noms complets pour soldes
    local mainName = _nameFor(mainUID)
    local altFull  = _nameFor(altUID) or altName

    -- Échanger l'intégralité des données partagées (solde, addonVersion, etc.)
    if GLOG.SwapSharedBetweenUIDs then
        GLOG.SwapSharedBetweenUIDs(mainUID, altUID)
    else
    -- Alternative minimale: ne gérer que le solde
        if GLOG.GetSoldeByUID and GLOG.SetSoldeByUID then
            local balMain = tonumber(GLOG.GetSoldeByUID(mainUID)) or 0
            local balAlt  = tonumber(GLOG.GetSoldeByUID(altUID))  or 0
            GLOG.SetSoldeByUID(mainUID, balAlt)
            GLOG.SetSoldeByUID(altUID,  balMain)
        elseif GLOG.GetSolde and GLOG.AdjustSolde then
            -- Alternative : transférer tout le solde du main vers l'alt
            local balMain = tonumber(GLOG.GetSolde(mainName)) or 0
            if balMain ~= 0 then
                GLOG.AdjustSolde(altFull,  balMain)
                GLOG.AdjustSolde(mainName, -balMain)
            end
        end
    end

    -- Transfert de l'attribut 'reserved':
    --  - le NOUVEAU main (alt promu) récupère la valeur actuelle du main
    --  - l'ancien main (qui devient alt) est remis à reserved=true
    do
        local recMain = select(1, _ensurePlayerRec(mainName))
        local recAlt  = select(1, _ensurePlayerRec(altFull))
        local r = (recMain and recMain.reserved)
        if r == nil then r = true end
        if recAlt then recAlt.reserved = r end
        if recMain then recMain.reserved = true end
    end

    -- Capturer les métadonnées du main AVANT de modifier les tables
    local oldMainEntry = MA.mains[mainUID]
    local newMainEntry = MA.mains[altUID]

    -- Repointage des liens ALT -> nouveau main (inclut l'ancien main qui devient alt)
    for a, m in pairs(MA.altToMain) do
        if tonumber(m) == mainUID then
            MA.altToMain[a] = altUID
        end
    end
    -- L'alt promu devient main
    MA.altToMain[altUID] = nil
    MA.mains[altUID] = (type(MA.mains[altUID]) == "table") and MA.mains[altUID] or {}
    -- L'ancien main cesse d'être main
    MA.mains[mainUID] = nil
    -- S'assurer que l'ancien main est bien marqué comme alt du nouveau
    MA.altToMain[mainUID] = altUID

    -- Transférer/Préserver les métadonnées du main (alias, etc.)
    do
        local tgt = MA.mains[altUID]
        if type(tgt) ~= "table" then tgt = {} end
        if type(oldMainEntry) == "table" then
            -- Copier le contenu de l'ancien main dans le nouveau (écrase alias si défini)
            for k,v in pairs(oldMainEntry) do tgt[k] = v end
        end
        MA.mains[altUID] = tgt
    end

    if ns.Emit then ns.Emit("mainalt:changed", "promote-alt", altFull, mainName) end
    if GLOG.BroadcastPromoteAlt then GLOG.BroadcastPromoteAlt(altFull, mainName) end
    return true
end
