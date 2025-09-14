-- Module des handlers de messages pour GuildLogistics
-- Décompose la fonction _HandleFull massive en handlers spécialisés par type de message

local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
local GLOG = ns.GLOG

-- Références aux utilitaires centralisées
local U = ns.Util or {}
local safenum = U.safenum
local now = U.now
local truthy = U.truthy
local playerFullName = U.playerFullName

-- ===== File complète → traitement ordonné =====
local CompleteQ = {}
local function enqueueComplete(sender, t, kv)
    -- Tri d'application : lm ↑, puis rv ↑, puis ordre d'arrivée
    kv._sender = sender
    kv._t = t
    kv._lm = safenum(kv.lm, now())
    kv._rv = safenum(kv.rv, -1)
    CompleteQ[#CompleteQ+1] = kv
    table.sort(CompleteQ, function(a,b)
        if a._lm ~= b._lm then return a._lm < b._lm end
        if a._rv ~= b._rv then return a._rv < b._rv end
        return false
    end)
    while true do
        local item = table.remove(CompleteQ, 1)
        if not item then break end
        GLOG.HandleMessage(item._sender, item._t, item)
    end
end

local function refreshActive()
    -- Prefer a full, coalesced UI refresh across the addon when incoming state changes occur
    if ns and ns.RefreshAll then
        ns.RefreshAll()
    elseif ns and ns.UI and ns.UI.RefreshActive then
        ns.UI.RefreshActive()
    end
end

-- ===== Handlers spécialisés par type de message =====
-- ===== Main/Alt Handlers =====
local function _maShouldApply(kv)
    local meta = GuildLogisticsDB and GuildLogisticsDB.meta
    local rv = safenum(kv.rv, -1)
    local myrv = safenum(meta and meta.rev, 0)
    local lm = safenum(kv.lm, -1)
    local mylm = safenum(meta and meta.lastModified, 0)
    if rv >= 0 then return rv >= myrv end
    if lm >= 0 then return lm >= mylm end
    return false
end

local function handleMAFull(sender, kv)
    if not _maShouldApply(kv) then return end
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.account = { mains = {}, altToMain = {} }
    local t = GuildLogisticsDB.account
    -- account.version is deprecated; kv.MAv is interpreted but not persisted
    for _, s in ipairs(kv.MA or {}) do
        local u = tostring(s)
        if u ~= "" then t.mains[u] = {} end
    end
    for _, s in ipairs(kv.AM or {}) do
        local a, m = tostring(s):match("^([^:]+):([^:]+)$")
        if a and m then t.altToMain[tostring(a)] = tostring(m) end
    end
    local meta = GuildLogisticsDB.meta; meta.rev = safenum(kv.rv, meta.rev or 0); meta.lastModified = safenum(kv.lm, now())
    if ns.Emit then ns.Emit("mainalt:changed", "net-full") end
    refreshActive()
end

local function handleMASetMain(sender, kv)
    if not _maShouldApply(kv) then return end
    local u = tostring(kv.u or ""); if u == "" then return end
    GuildLogisticsDB = GuildLogisticsDB or {}
    local t = GuildLogisticsDB.account or { version = 2, mains = {}, altToMain = {} }
    t.mains[u] = (type(t.mains[u]) == "table") and t.mains[u] or {}; t.altToMain[u] = nil
    GuildLogisticsDB.account = t
    local meta = GuildLogisticsDB.meta; meta.rev = safenum(kv.rv, meta.rev or 0); meta.lastModified = safenum(kv.lm, now())
    if ns.Emit then ns.Emit("mainalt:changed", "net-set-main") end
    refreshActive()
end

local function handleMAAssign(sender, kv)
    if not _maShouldApply(kv) then return end
    local au, mu = tostring(kv.a or ""), tostring(kv.m or "")
    if au == "" or mu == "" then return end
    GuildLogisticsDB = GuildLogisticsDB or {}
    local t = GuildLogisticsDB.account or { version = 2, mains = {}, altToMain = {} }
    t.mains[mu] = (type(t.mains[mu]) == "table") and t.mains[mu] or {}; t.mains[au] = nil; t.altToMain[au] = mu
    GuildLogisticsDB.account = t
    local meta = GuildLogisticsDB.meta; meta.rev = safenum(kv.rv, meta.rev or 0); meta.lastModified = safenum(kv.lm, now())
    if ns.Emit then ns.Emit("mainalt:changed", "net-assign") end
    refreshActive()
end

local function handleMAUnassign(sender, kv)
    if not _maShouldApply(kv) then return end
    local au = tostring(kv.a or ""); if au == "" then return end
    GuildLogisticsDB = GuildLogisticsDB or {}
    local t = GuildLogisticsDB.account or { version = 2, mains = {}, altToMain = {} }
    t.altToMain[au] = nil
    GuildLogisticsDB.account = t
    local meta = GuildLogisticsDB.meta; meta.rev = safenum(kv.rv, meta.rev or 0); meta.lastModified = safenum(kv.lm, now())
    if ns.Emit then ns.Emit("mainalt:changed", "net-unassign") end
    refreshActive()
end

local function handleMARemoveMain(sender, kv)
    if not _maShouldApply(kv) then return end
    local u = tostring(kv.u or ""); if u == "" then return end
    GuildLogisticsDB = GuildLogisticsDB or {}
    local t = GuildLogisticsDB.account or { version = 2, mains = {}, altToMain = {} }
    t.mains[u] = nil
    -- ne force pas les alts → pool
    for a, m in pairs(t.altToMain) do if tostring(m) == u then t.altToMain[a] = nil end end
    GuildLogisticsDB.account = t
    local meta = GuildLogisticsDB.meta; meta.rev = safenum(kv.rv, meta.rev or 0); meta.lastModified = safenum(kv.lm, now())
    if ns.Emit then ns.Emit("mainalt:changed", "net-remove-main") end
    refreshActive()
end

local function handleMAPromote(sender, kv)
    if not _maShouldApply(kv) then return end
    local au, mu = tostring(kv.a or ""), tostring(kv.m or "")
    if au == "" or mu == "" then return end
    GuildLogisticsDB = GuildLogisticsDB or {}
    local t = GuildLogisticsDB.account or { version = 2, mains = {}, altToMain = {} }

    -- Conserver l'entrée du main avant mutation pour transférer les métadonnées (solde, alias, version, reserve...)
    local oldMainEntry = t.mains and t.mains[mu] or nil

    -- Repointage des alts de mu vers au, et mu devient alt
    for a, m in pairs(t.altToMain) do if tostring(m) == mu then t.altToMain[a] = au end end
    t.altToMain[mu] = au
    t.altToMain[au] = nil

    -- Nouveau main: garantir la table et transférer les métadonnées de l'ancien main
    t.mains[mu] = nil
    t.mains[au] = (type(t.mains[au]) == "table") and t.mains[au] or {}
    if type(oldMainEntry) == "table" then
        for k, v in pairs(oldMainEntry) do t.mains[au][k] = v end
    end

    -- Transférer l'état "reserved" explicite si présent dans players
    do
        local nf = (ns and ns.Util and ns.Util.NormalizeFull) and ns.Util.NormalizeFull or tostring
        local mainName = (GLOG.GetNameByUID and GLOG.GetNameByUID(mu)) or nil
        local altName  = (GLOG.GetNameByUID and GLOG.GetNameByUID(au)) or nil
        if mainName and altName then
            GuildLogisticsDB.players = GuildLogisticsDB.players or {}
            local mKey = nf(mainName)
            local aKey = nf(altName)
            local recMain = GuildLogisticsDB.players[mKey]
            local recAlt  = GuildLogisticsDB.players[aKey]
            if recMain or recAlt then
                local mainIsFalse = recMain and (recMain.reserved == false)
                if recAlt then recAlt.reserved = mainIsFalse and false or nil end
                if recMain then recMain.reserved = nil end
            end
        end
    end

    GuildLogisticsDB.account = t
    local meta = GuildLogisticsDB.meta; meta.rev = safenum(kv.rv, meta.rev or 0); meta.lastModified = safenum(kv.lm, now())
    -- Rebuild derived guild cache (class/byName/mains) to reflect new main immediately
    if GLOG.RebuildGuildCacheDerived then pcall(GLOG.RebuildGuildCacheDerived) end
    if ns.Emit then ns.Emit("mainalt:changed", "net-promote") end
    refreshActive()
end

-- ===== Editors allowlist Handlers =====
local function _edShouldApply(kv)
    local meta = GuildLogisticsDB and GuildLogisticsDB.meta
    local rv = safenum(kv.rv, -1)
    local myrv = safenum(meta and meta.rev, 0)
    local lm = safenum(kv.lm, -1)
    local mylm = safenum(meta and meta.lastModified, 0)
    if rv >= 0 then return rv >= myrv end
    if lm >= 0 then return lm >= mylm end
    return false
end

local function handleEditorsFull(sender, kv)
    if not _edShouldApply(kv) then return end
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.account = GuildLogisticsDB.account or { mains = {}, altToMain = {} }
    local t = GuildLogisticsDB.account
    -- Capture previous local editor status (before overwrite)
    local wasEditor = false
    do
        local me = playerFullName()
        local main = (GLOG and GLOG.GetMainOf and GLOG.GetMainOf(me)) or me
        local mu = (GLOG and GLOG.GetOrAssignUID and GLOG.GetOrAssignUID(main)) or nil
        if mu and t and t.editors and t.editors[mu] then wasEditor = true end
    end
    t.editors = {}
    for _, s in ipairs(kv.E or {}) do
        local mu = tostring(s or "")
        if mu ~= "" then t.editors[mu] = true end
    end
    local meta = GuildLogisticsDB.meta
    meta.rev = (safenum(kv.rv, -1) >= 0) and safenum(kv.rv, -1) or safenum(meta.rev, 0)
    meta.lastModified = (safenum(kv.lm, -1) >= 0) and safenum(kv.lm, -1) or now()
    if ns.Emit then ns.Emit("editors:changed", "net-full") end
    -- Show reload prompt if local status changed (promotion/demotion)
    do
        local becameEditor = false
        local me = playerFullName()
        local main = (GLOG and GLOG.GetMainOf and GLOG.GetMainOf(me)) or me
        local mu = (GLOG and GLOG.GetOrAssignUID and GLOG.GetOrAssignUID(main)) or nil
        if mu and t and t.editors and t.editors[mu] then becameEditor = true end
        if wasEditor ~= becameEditor then
            local UI = ns and ns.UI
            if UI and UI.PopupReloadPrompt then
                local Tr = ns.Tr or function(s) return s end
                local msg = becameEditor and (Tr("msg_editor_promo") or "Vous avez été promu éditeur. Certaines options nécessitent un rechargement.")
                                        or  (Tr("msg_editor_demo")  or "Vous avez été dégradé. L'interface doit être rechargée pour refléter les changements.")
                UI.PopupReloadPrompt(msg)
            end
        end
    end
end

local function handleEditorGrant(sender, kv)
    if not _edShouldApply(kv) then return end
    local mu = tostring(kv.m or "")
    if mu == "" then return end
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.account = GuildLogisticsDB.account or { mains = {}, altToMain = {} }
    local t = GuildLogisticsDB.account
    t.editors = t.editors or {}
    t.editors[mu] = true
    local meta = GuildLogisticsDB.meta
    meta.rev = (safenum(kv.rv, -1) >= 0) and safenum(kv.rv, -1) or safenum(meta.rev, 0)
    meta.lastModified = (safenum(kv.lm, -1) >= 0) and safenum(kv.lm, -1) or now()
    if ns.Emit then ns.Emit("editors:changed", "net-grant", mu) end
    -- If message concerns me, prompt reload instead of dynamic refresh
    do
        local me = playerFullName()
        local main = (GLOG and GLOG.GetMainOf and GLOG.GetMainOf(me)) or me
        local myMu = (GLOG and GLOG.GetOrAssignUID and GLOG.GetOrAssignUID(main)) or nil
        if myMu and tostring(mu) == tostring(myMu) then
            local UI = ns and ns.UI
            if UI and UI.PopupReloadPrompt then
                local Tr = ns.Tr or function(s) return s end
                UI.PopupReloadPrompt(Tr("msg_editor_promo") or "Vous avez été promu éditeur. Certaines options nécessitent un rechargement.")
            end
        end
    end
end

local function handleEditorRevoke(sender, kv)
    if not _edShouldApply(kv) then return end
    local mu = tostring(kv.m or "")
    if mu == "" then return end
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.account = GuildLogisticsDB.account or { mains = {}, altToMain = {} }
    local t = GuildLogisticsDB.account
    t.editors = t.editors or {}
    t.editors[mu] = nil
    local meta = GuildLogisticsDB.meta
    meta.rev = (safenum(kv.rv, -1) >= 0) and safenum(kv.rv, -1) or safenum(meta.rev, 0)
    meta.lastModified = (safenum(kv.lm, -1) >= 0) and safenum(kv.lm, -1) or now()
    if ns.Emit then ns.Emit("editors:changed", "net-revoke", mu) end
    -- If message concerns me, prompt reload instead of dynamic refresh
    do
        local me = playerFullName()
        local main = (GLOG and GLOG.GetMainOf and GLOG.GetMainOf(me)) or me
        local myMu = (GLOG and GLOG.GetOrAssignUID and GLOG.GetOrAssignUID(main)) or nil
        if myMu and tostring(mu) == tostring(myMu) then
            local UI = ns and ns.UI
            if UI and UI.PopupReloadPrompt then
                local Tr = ns.Tr or function(s) return s end
                UI.PopupReloadPrompt(Tr("msg_editor_demo") or "Vous avez été dégradé. L'interface doit être rechargée pour refléter les changements.")
            end
        end
    end
end


-- ===== Roster Handlers =====
local function handleRosterUpsert(sender, kv)
    local function shouldApply()
        local meta = GuildLogisticsDB and GuildLogisticsDB.meta
        local rv = safenum(kv.rv, -1)
        local myrv = safenum(meta and meta.rev, 0)
        local lm = safenum(kv.lm, -1)
        local mylm = safenum(meta and meta.lastModified, 0)
        
        if rv >= 0 then return rv >= myrv end
        if lm >= 0 then return lm >= mylm end
        return false
    end
    
    if not shouldApply() then return end
    
    local uid, name = kv.uid, kv.name
    if uid and name then
        local nf = (ns and ns.Util and ns.Util.NormalizeFull) and ns.Util.NormalizeFull or tostring
        local full = nf(name)
        if GLOG.MapUID then GLOG.MapUID(uid, full) end
        if GLOG.EnsureRosterLocal then GLOG.EnsureRosterLocal(full) end
        -- 🔤 Appliquer l'alias reçu (stockage autoritatif au niveau du MAIN)
        do
            local alias = kv.alias
            if alias ~= nil then
                GuildLogisticsDB = GuildLogisticsDB or {}
                GuildLogisticsDB.account = GuildLogisticsDB.account or { mains = {}, altToMain = {} }
                local t = GuildLogisticsDB.account
                t.mains = t.mains or {}; t.altToMain = t.altToMain or {}
                -- Déterminer le holder MAIN (UID de main)
                local mu = tostring(uid or "")
                if mu == "" then
                    local _uid = (GLOG.GetOrAssignUID and GLOG.GetOrAssignUID(full)) or nil
                    mu = tostring(_uid or "")
                end
                if mu ~= "" then
                    local mainUID = t.altToMain[mu] or mu
                    t.mains[mainUID] = t.mains[mainUID] or {}
                    local stored = nil
                    if type(alias) == "string" then
                        local trimmed = alias:gsub("^%s+",""):gsub("%s+$","")
                        if trimmed ~= "" then stored = trimmed end
                    end
                    t.mains[mainUID].alias = stored
                    if ns.Emit then ns.Emit("alias:changed", tostring(mainUID), stored) end
                end
            end
        end
        
        local meta = GuildLogisticsDB.meta
        meta.rev = (safenum(kv.rv, -1) >= 0) and safenum(kv.rv, -1) or safenum(meta.rev, 0)
        meta.lastModified = safenum(kv.lm, now())
        refreshActive()
        if ns.Emit then ns.Emit("roster:upsert", full) end
        if ns.RefreshAll then ns.RefreshAll() end

        -- ✏️ Si l'UPSERT me concerne et que je suis connecté, envoyer un message unifié
        local me = nf(playerFullName())
        if me == full then
            local ilvl    = (GLOG.ReadOwnEquippedIlvl and GLOG.ReadOwnEquippedIlvl()) or nil
            local ilvlMax = (GLOG.ReadOwnMaxIlvl     and GLOG.ReadOwnMaxIlvl())       or nil
            local mid, lvl, map = 0, 0, ""
            if GLOG.ReadOwnedKeystone then mid, lvl, map = GLOG.ReadOwnedKeystone() end
            if (not map or map == "" or map == "Clé") and safenum(mid, 0) > 0 and GLOG.ResolveMKeyMapName then
                local nm = GLOG.ResolveMKeyMapName(mid)
                if nm and nm ~= "" then map = nm end
            end
            if GLOG.BroadcastStatusUpdate then
                GLOG.BroadcastStatusUpdate({
                    ilvl = ilvl, ilvlMax = ilvlMax,
                    mid = safenum(mid, 0), lvl = safenum(lvl, 0), map = tostring(map or ""),
                    ts = now(), by = me,
                })
            end
        end
    end
end

local function handleRosterRemove(sender, kv)
    -- Tolère les anciens messages (sans rv/lm) : on applique quand même.
    local hasVersioning = (kv.rv ~= nil) or (kv.lm ~= nil)
    local function shouldApply()
        local meta = GuildLogisticsDB and GuildLogisticsDB.meta
        local rv = safenum(kv.rv, -1)
        local myrv = safenum(meta and meta.rev, 0)
        local lm = safenum(kv.lm, -1)
        local mylm = safenum(meta and meta.lastModified, 0)
        
        if rv >= 0 then return rv >= myrv end
        if lm >= 0 then return lm >= mylm end
        return true -- Sans versioning, on applique
    end
    
    if hasVersioning and not shouldApply() then return end

    local uid  = kv.uid
    -- Récupérer le nom AVANT de défaire le mapping UID -> name.
    local name = (uid and GLOG.GetNameByUID and GLOG.GetNameByUID(uid)) or kv.name

    if uid and GLOG.UnmapUID then GLOG.UnmapUID(uid) end

    -- Purge du roster local (nom complet si possible)
    if name and name ~= "" then
        if GLOG.RemovePlayerLocal then
            GLOG.RemovePlayerLocal(name, true)
        else
            GuildLogisticsDB = GuildLogisticsDB or {}
            GuildLogisticsDB.players = GuildLogisticsDB.players or {}
            GuildLogisticsDB.players[name] = nil
        end
    end

    if hasVersioning then
        local meta = GuildLogisticsDB.meta
        meta.rev = (safenum(kv.rv, -1) >= 0) and safenum(kv.rv, -1) or safenum(meta.rev, 0)
        meta.lastModified = safenum(kv.lm, now())
    else
        -- Pas de versioning transmis : on marque juste une modif locale.
        GuildLogisticsDB.meta.lastModified = now()
    end
    refreshActive()
end

local function handleRosterReserve(sender, kv)
    local function shouldApply()
        local meta = GuildLogisticsDB and GuildLogisticsDB.meta
        local rv = safenum(kv.rv, -1)
        local myrv = safenum(meta and meta.rev, 0)
        local lm = safenum(kv.lm, -1)
        local mylm = safenum(meta and meta.lastModified, 0)
        
        if rv >= 0 then return rv >= myrv end
        if lm >= 0 then return lm >= mylm end
        return false
    end
    
    if not shouldApply() then return end
    
    GuildLogisticsDB.players = GuildLogisticsDB.players or {}
    local uid, name = kv.uid, kv.name
    -- récupérer le nom complet via l'UID si besoin
    if (not name or name == "") and uid and GLOG.GetNameByUID then
        name = GLOG.GetNameByUID(uid)
    end
    if name and name ~= "" then
        local full = (GLOG.ResolveFullName and GLOG.ResolveFullName(name, { strict = true }))
                or (name:find("%-") and name)
                or (uid and GLOG.GetNameByUID and GLOG.GetNameByUID(uid))
        if full and full ~= "" then
            -- Write authoritative flag at account.mains[mainUID]
            local mu
            do
                local _uid = uid or (GLOG.GetOrAssignUID and GLOG.GetOrAssignUID(full)) or nil
                if _uid and GLOG.GetMainOf then
                    local main = GLOG.GetMainOf(full) or full
                    mu = (GLOG.GetOrAssignUID and GLOG.GetOrAssignUID(main)) or _uid
                else
                    mu = _uid
                end
            end
            if mu then
                GuildLogisticsDB.account = GuildLogisticsDB.account or { mains = {}, altToMain = {} }
                local t = GuildLogisticsDB.account
                t.mains[mu] = (type(t.mains[mu]) == "table") and t.mains[mu] or {}
                -- New semantics: only store explicit false at main-level; nil means reserved
                local res_val = tonumber(kv.res) or 0
                if res_val == 0 then
                    t.mains[mu].reserve = false
                else
                    t.mains[mu].reserve = nil
                end
            end
            -- Maintain legacy per-character flag for UI compatibility (only explicit false)
            local p = GuildLogisticsDB.players[full] or {}
            local res_val = tonumber(kv.res) or 0
            if res_val == 0 then
                p.reserved = false
            else
                p.reserved = nil
            end
            GuildLogisticsDB.players[full] = p
            
            local meta = GuildLogisticsDB.meta
            meta.rev = (safenum(kv.rv, -1) >= 0) and safenum(kv.rv, -1) or safenum(meta.rev, 0)
            meta.lastModified = safenum(kv.lm, now())
            if ns.Emit then ns.Emit("roster:reserve", full, p.reserved) end
            refreshActive()
        end
    end
end

-- ===== Transaction Handlers =====
local function handleTxReq(sender, kv)
    -- Autorisé pour les éditeurs (GM cluster + éditeurs accordés)
    if not (GLOG.CanModifyGuildData and GLOG.CanModifyGuildData()) then
        return
    end

    if GLOG.AddIncomingRequest then GLOG.AddIncomingRequest(kv) end
    refreshActive()

    -- Popup côté GM
    local ui = ns.UI
    if ui and ui.PopupRequest then
        local _id = tostring(kv.uid or "") .. ":" .. tostring(kv.ts or now())
        local extra = nil
        do
            local r = tostring(kv.reason or "")
            if r == "GBANK_DEPOSIT" then
                extra = (ns.Tr and ns.Tr("tx_reason_gbank_deposit")) or "Guild Bank deposit"
            elseif r == "GBANK_WITHDRAW" then
                extra = (ns.Tr and ns.Tr("tx_reason_gbank_withdraw")) or "Guild Bank withdraw"
            elseif r == "CLIENT_REQ" or r == "MANUAL" then
                extra = (ns.Tr and ns.Tr("tx_reason_manual_request")) or "Manual request"
            end
        end
        ui.PopupRequest(kv.who or sender, safenum(kv.delta,0),
            function()
                -- ⚠️ IMPORTANT : appliquer par NOM (kv.who) et non par UID local (non global)
                local who = kv.who or sender
                local ctx = { reason = (kv.reason or "PLAYER_REQUEST"), requester = who, uid = kv.uid }
                if GLOG.GM_ApplyAndBroadcastEx then
                    GLOG.GM_ApplyAndBroadcastEx(who, safenum(kv.delta,0), ctx)
                elseif GLOG.GM_ApplyAndBroadcast then
                    GLOG.GM_ApplyAndBroadcast(who, safenum(kv.delta,0))
                elseif GLOG.GM_ApplyAndBroadcastByUID then
                    -- Fallback ultime si l'API ci-dessus n'existe pas
                    GLOG.GM_ApplyAndBroadcastByUID(kv.uid, safenum(kv.delta,0), ctx)
                end
                if GLOG.ResolveRequest then GLOG.ResolveRequest(_id, true, playerFullName()) end
            end,
            function()
                if GLOG.ResolveRequest then GLOG.ResolveRequest(_id, false, playerFullName()) end
            end,
            extra
        )
    end
end

local function handleTxApplied(sender, kv)
    local function shouldApply()
        local meta = GuildLogisticsDB and GuildLogisticsDB.meta
        local rv = safenum(kv.rv, -1)
        local myrv = safenum(meta and meta.rev, 0)
        local lm = safenum(kv.lm, -1)
        local mylm = safenum(meta and meta.lastModified, 0)
        
        if rv >= 0 then return rv >= myrv end
        if lm >= 0 then return lm >= mylm end
        return false
    end
    
    if not shouldApply() then return end
    
    local applied = false
    if GLOG.ApplyDeltaByName and kv.name and kv.delta then
        GLOG.ApplyDeltaByName(kv.name, safenum(kv.delta,0), kv.by or sender)
        applied = true
    else
        -- ➕ Fallback : appliquer localement si l'API n'est pas disponible
        GuildLogisticsDB = GuildLogisticsDB or {}
        GuildLogisticsDB.players = GuildLogisticsDB.players or {}
        local nf = (ns and ns.Util and ns.Util.NormalizeFull) and ns.Util.NormalizeFull or tostring
        local full = nf(kv.name or "")
        local existed = not not GuildLogisticsDB.players[full]
        local rec = GuildLogisticsDB.players[full] or {}
        -- Route vers stockage partagé si possible
        if GLOG.ApplyDeltaByName then
            GLOG.ApplyDeltaByName(full, safenum(kv.delta,0), kv.by or sender)
            -- no legacy field anymore
        else
            -- legacy path: avoid writing to rec.solde; apply nothing here as shared path is unavailable
        end
        GuildLogisticsDB.players[full] = rec
        applied = true
    end
    if applied then
        local meta = GuildLogisticsDB.meta
        meta.rev = (safenum(kv.rv, -1) >= 0) and safenum(kv.rv, -1) or safenum(meta.rev, 0)
        meta.lastModified = safenum(kv.lm, now())
        refreshActive()
    end
end

local function handleTxBatch(sender, kv)
    local function shouldApply()
        local meta = GuildLogisticsDB and GuildLogisticsDB.meta
        local rv = safenum(kv.rv, -1)
        local myrv = safenum(meta and meta.rev, 0)
        local lm = safenum(kv.lm, -1)
        local mylm = safenum(meta and meta.lastModified, 0)
        
        if rv >= 0 then return rv >= myrv end
        if lm >= 0 then return lm >= mylm end
        return false
    end
    
    if not shouldApply() then return end
    
    local done = false
    if GLOG.ApplyBatch then
        GLOG.ApplyBatch(kv)
        done = true
    else
        -- ➕ Fallback : boucle sur les éléments du batch
        GuildLogisticsDB = GuildLogisticsDB or {}
        GuildLogisticsDB.players = GuildLogisticsDB.players or {}
        local U, D, N = kv.U or {}, kv.D or {}, kv.N or {}
        local nf = (ns and ns.Util and ns.Util.NormalizeFull) and ns.Util.NormalizeFull or tostring
        for i = 1, math.max(#U, #D, #N) do
            local name = N[i] or (GLOG.GetNameByUID and GLOG.GetNameByUID(U[i])) or "?"
            local full = nf(name)
            local d = safenum(D[i], 0)
            local existed = not not GuildLogisticsDB.players[full]
            local rec = GuildLogisticsDB.players[full] or {}
            if GLOG.ApplyDeltaByName then
                GLOG.ApplyDeltaByName(full, d, sender)
                -- no legacy field anymore
            else
                -- legacy path: avoid writing to rec.solde; apply nothing here as shared path is unavailable
            end
            GuildLogisticsDB.players[full] = rec
        end
        done = true
    end
    if done then
        local meta = GuildLogisticsDB.meta
        meta.rev = (safenum(kv.rv, -1) >= 0) and safenum(kv.rv, -1) or safenum(meta.rev, 0)
        meta.lastModified = safenum(kv.lm, now())
        refreshActive()

        -- ➕ Popup réseau pour les joueurs impactés (si non silencieux)
        if not truthy(kv.S) and ns and ns.UI and ns.UI.PopupRaidDebit then
            local nf = (ns and ns.Util and ns.Util.NormalizeFull) and ns.Util.NormalizeFull or tostring
            local meFull = playerFullName()
            local meK = nf(meFull)
            local U, D, N = kv.U or {}, kv.D or {}, kv.N or {}
            for i = 1, math.max(#U, #D, #N) do
                local name = N[i] or (GLOG.GetNameByUID and GLOG.GetNameByUID(U[i])) or "?"
                if nf(name) == meK then
                    local d = safenum(D[i], 0)
                    local per   = -d
                    local before = (GLOG.GetSolde and GLOG.GetSolde(meFull)) or 0
                    local after = before + d  -- Calculate manually: before + delta (delta is negative for debit)

                    -- Parse kv.L (CSV "id,name") → tableau d'objets
                    local Lctx, Lraw = {}, kv and kv.L
                    if type(Lraw) == "table" then
                        for j = 1, #Lraw do
                            local s = Lraw[j]
                            if type(s) == "string" then
                                local id,name,kUse,Ns,n,g = s:match("^(%-?%d+),(.-),(%-?%d+),(%-?%d+),(%-?%d+),(%-?%d+)$")
                                if id then
                                    Lctx[#Lctx+1] = {
                                        id   = tonumber(id),
                                        name = name,
                                        k    = tonumber(kUse),
                                        N    = tonumber(Ns),
                                        n    = tonumber(n),
                                        gold = tonumber(g),
                                    }
                                end
                            elseif type(s) == "table" then
                                -- tolérance (anciens GM locaux)
                                Lctx[#Lctx+1] = s
                            end
                        end
                    end

                    -- Respecte l'option "Notification de participation à un raid"
                    local _sv = (GLOG.GetSavedWindow and GLOG.GetSavedWindow())
                    _sv.popups = _sv.popups or {}
                    if _sv.popups.raidParticipation ~= false then
                        -- Suppress the personal toast while showing the specialized raid popup
                        if GLOG and GLOG._PushSuppressPersonalToast then GLOG._PushSuppressPersonalToast() end
                        ns.UI.PopupRaidDebit(meFull, per, after, { L = Lctx })
                        if GLOG and GLOG._PopSuppressPersonalToast then GLOG._PopSuppressPersonalToast() end
                    end
                    if ns.Emit then ns.Emit("raid:popup-shown", meFull) end
                    break
                end
            end
        end
    end
end

-- ===== Status Update Handler =====
local function handleStatusUpdate(sender, kv)
    -- Compat: conserve le traçage de version d'addon si présent
    do
        local v_status = tostring(kv.ver or "")
        if v_status ~= "" and GLOG.SetPlayerAddonVersion then
            local who = tostring(kv.name or sender or "")
            GLOG.SetPlayerAddonVersion(who, v_status, tonumber(kv.ts) or now(), sender)
        end
    end

    local function _applyOne(pname, info)
        if not pname or pname == "" then return end
        GuildLogisticsDB = GuildLogisticsDB or {}
        GuildLogisticsDB.players = GuildLogisticsDB.players or {}
        local p = GuildLogisticsDB.players[pname]      -- ⚠️ ne jamais créer ici
        if not p then return end

        -- Garde-fou: ignorer les stats pour les ALTs (déterminé via db.account.altToMain)
        local isAlt = false
        do
            local uid = tostring(p.uid or (GLOG.GetOrAssignUID and GLOG.GetOrAssignUID(pname)) or "")
            if uid ~= "" then
                GuildLogisticsDB.account = GuildLogisticsDB.account or { mains = {}, altToMain = {} }
                local t = GuildLogisticsDB.account
                local mu = t.altToMain and t.altToMain[uid]
                if mu and mu ~= uid then
                    isAlt = true
                    -- Garde-fou fort: un ALT ne doit jamais figurer dans la table des mains
                    if t.mains and t.mains[uid] ~= nil then t.mains[uid] = nil end
                end
            end
        end

        local n_ts   = safenum(info.ts, now())
        local prev   = safenum(p.statusTimestamp, 0)
        local changed= false

        -- ===== iLvl =====
        if not isAlt then
            local n_ilvl    = safenum(info.ilvl, -1)
            local n_ilvlMax = safenum(info.ilvlMax, -1)
            if n_ilvl >= 0 and n_ts >= prev then
                p.ilvl = math.floor(n_ilvl)
                if n_ilvlMax >= 0 then p.ilvlMax = math.floor(n_ilvlMax) end
                changed = true
                if ns.Emit then ns.Emit("ilvl:changed", pname) end
            end
        end

        -- ===== Clé M+ (mid/lvl) =====
        if not isAlt then
            local n_mid = safenum(info.mid, -1)
            local n_lvl = safenum(info.lvl, -1)
            if (n_mid >= 0 or n_lvl >= 0) and n_ts >= prev then
                if n_mid >= 0 then p.mkeyMapId = n_mid end
                if n_lvl >= 0 then p.mkeyLevel = n_lvl end
                changed = true
                if ns.Emit then ns.Emit("mkey:changed", pname) end
            end
        end

        -- ✨ ===== Score M+ =====
        if not isAlt then
            local n_score = safenum(info.score, -1)
            if n_score >= 0 and n_ts >= prev then
                p.mplusScore = n_score
                changed = true
                if ns.Emit then ns.Emit("mplus:changed", pname) end
            end
        end

    -- ✨ ===== Version de l'addon =====
        local version = tostring(info.version or "")
        if version ~= "" and n_ts >= prev then
            -- Stocker la version au niveau du MAIN uniquement si:
            --  - le joueur est déjà mappé comme ALT -> MAIN (écrire sur MAIN, autorisé à créer l'entrée MAIN)
            --  - OU l'UID cible est déjà un MAIN confirmé (ne pas promouvoir implicitement)
            local uid = tostring(p.uid or (GLOG.GetOrAssignUID and GLOG.GetOrAssignUID(pname)) or "")
            if uid ~= "" then
                GuildLogisticsDB.account = GuildLogisticsDB.account or { mains = {}, altToMain = {} }
                local t = GuildLogisticsDB.account
                local mapped = t.altToMain and t.altToMain[uid]
                local mu = tostring(mapped or uid)
                t.mains = t.mains or {}
                if mapped and mapped ~= uid then
                    -- Alt connu: NE PAS créer d'entrée MAIN implicite. Mettre à jour seulement si le MAIN existe déjà.
                    if type(t.mains[mu]) == "table" then
                        t.mains[mu].addonVersion = version
                        changed = true
                    else
                        -- Le MAIN n'existe pas encore → copie locale pour affichage
                        p.addonVersion = version
                        changed = true
                    end
                elseif type(t.mains[mu]) == "table" then
                    -- MAIN déjà confirmé: mise à jour uniquement
                    t.mains[mu].addonVersion = version
                    changed = true
                else
                    -- Ni mappé, ni main confirmé → ne pas créer une entrée MAIN
                    -- Conserver une copie locale au niveau du personnage
                    p.addonVersion = version
                    changed = true
                end
            end
            -- Utiliser aussi la fonction de traçage de version si disponible
            if GLOG.SetPlayerAddonVersion then
                GLOG.SetPlayerAddonVersion(pname, version, n_ts, sender)
            end
            -- Sécurité supplémentaire: sanitiser immédiatement après un changement potentiel
            if GLOG.SanitizeMainAltState then pcall(GLOG.SanitizeMainAltState) end
        end

        if changed and n_ts > prev then p.statusTimestamp = n_ts end
        if changed and ns.RefreshAll then ns.RefreshAll() end
    end

    local function _applyByUID(uid, info)
        uid = tostring(uid or "")
        if uid == "" then return end
        local name = (GLOG.GetNameByUID and GLOG.GetNameByUID(uid)) or nil
        if not name or name == "" then return end -- ⚠️ on n'invente pas d'entrée
        _applyOne(name, info)
    end

    -- 1) Batch (nouveau) : kv.S peut être une liste de chaînes "uid;ts;ilvl;ilvlMax;mid;lvl;score;version"
    if type(kv.S) == "table" then
        for _, rec in ipairs(kv.S) do
            if type(rec) == "string" then
                -- Format UID + ';' avec version
                local uid, ts, ilvl, ilvlMax, mid, lvl, score, version =
                    rec:match("^([^;]+);([%-%d]+);([%-%d]+);([%-%d]+);([%-%d]+);([%-%d]+);([%-%d]+);(.*)$")
                if uid and ts then
                    _applyByUID(uid, {
                        ts = safenum(ts, now()),
                        ilvl = safenum(ilvl, -1),
                        ilvlMax = safenum(ilvlMax, -1),
                        mid = safenum(mid, -1),
                        lvl = safenum(lvl, -1),
                        score = safenum(score, -1),
                        version = tostring(version or ""),
                    })
                end
            elseif type(rec) == "table" then
                local uid = rec.uid or rec.u
                local name = rec.name or rec.n
                local info = {
                    ts = safenum(rec.ts, now()),
                    ilvl = rec.ilvl, ilvlMax = rec.ilvlMax,
                    mid = rec.mid,   lvl = rec.lvl,
                    score = rec.score,
                    version = tostring(rec.version or ""),
                }
                if uid then _applyByUID(uid, info)
                elseif name then _applyOne(name, info) end
            end
        end
    end

    -- 1.bis) Banque de guilde: appliquer la valeur la plus récente si fournie
    do
        local c   = tonumber(kv.gbc)
        local ts  = tonumber(kv.gbts)
        if not (c and ts) then
            -- Fallback compat: nested object (older dev build)
            local gb = kv.gbank
            if type(gb) == "table" then
                c  = tonumber(gb.c or gb.copper)
                ts = tonumber(gb.ts or gb.t)
            end
        end
        if c and c >= 0 and ts and ts > 0 then
            local myTs = (GLOG.GetGuildBankTimestamp and GLOG.GetGuildBankTimestamp()) or 0
            if ts > myTs then
                if GLOG.SetGuildBankBalanceCopper then
                    GLOG.SetGuildBankBalanceCopper(c, ts)
                end
            end
        end
    end

    -- 2) Compat (ancien) : enregistrement unitaire (accepte aussi kv.uid) - SUPPRIMÉ LES CHAMPS REDONDANTS
    do
        local uid  = tostring(kv.uid or "")
        local name = tostring(kv.name or "")
        local info = {
            ts = safenum(kv.ts, now()),
            -- Les champs ilvl, ilvlMax, mid, lvl, score sont maintenant uniquement dans le tableau S
        }
        if uid ~= "" then
            _applyByUID(uid, info)
        elseif name ~= "" then
            _applyOne(name, info)
        end
    end
end

-- ===== Error Report Handler =====
local function handleErrReport(sender, kv)
    -- Autorisé pour les éditeurs (GM cluster + éditeurs accordés)
    if not (GLOG.CanModifyGuildData and GLOG.CanModifyGuildData()) then
        return
    end
    if GLOG.Errors_AddIncomingReport then
        GLOG.Errors_AddIncomingReport(kv, sender)
    else
        -- Fallback minimal si le module n'est pas chargé
        GuildLogisticsDB = GuildLogisticsDB or {}
        GuildLogisticsDB.errors = GuildLogisticsDB.errors or { list = {}, nextId = 1 }
        local t = GuildLogisticsDB.errors
        local id = tonumber(t.nextId or 1) or 1
        t.list[#t.list+1] = { id = id, ts = kv.ts, who = kv.who or sender, ver = kv.ver, msg = kv.msg, st = kv.st }
        t.nextId = id + 1
        if ns.Emit then ns.Emit("errors:changed") end
    end
end

-- ===== Handlers de lots =====
local function handleLotCreate(sender, kv)
    local function shouldApply()
        local meta = GuildLogisticsDB and GuildLogisticsDB.meta
        local rv = safenum(kv.rv, -1)
        local myrv = safenum(meta and meta.rev, 0)
        local lm = safenum(kv.lm, -1)
        local mylm = safenum(meta and meta.lastModified, 0)
        
        if rv >= 0 then return rv >= myrv end
        if lm >= 0 then return lm >= mylm end
        return false
    end
    
    if not shouldApply() then return end
    
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.lots = GuildLogisticsDB.lots or { nextId = 1, list = {} }
    GuildLogisticsDB.expenses = GuildLogisticsDB.expenses or { list = {}, nextId = 1 }
    
    local id = safenum(kv.id, 0)
    if id <= 0 then return end
    
    -- Vérifier si le lot existe déjà
    for _, existing in ipairs(GuildLogisticsDB.lots.list) do
        if safenum(existing.id, 0) == id then return end -- Lot déjà existant
    end
    
    -- Créer le nouveau lot
    local newLot = {
        id = id,
        name = tostring(kv.n or ("Lot " .. id)),
        sessions = safenum(kv.N, 1),
        used = safenum(kv.u, 0),
        totalCopper = safenum(kv.tc, 0),
        itemIds = {}
    }
    
    -- Ajouter les IDs d'items et marquer les expenses comme rattachées au lot
    if type(kv.I) == "table" then
        for _, eid in ipairs(kv.I) do
            local itemId = safenum(eid, 0)
            if itemId > 0 then
                newLot.itemIds[#newLot.itemIds + 1] = itemId
                
                -- Trouver l'expense correspondante et la marquer avec le lotId
                for _, expense in ipairs(GuildLogisticsDB.expenses.list) do
                    if safenum(expense.id, 0) == itemId and not expense.lotId then
                        expense.lotId = id
                        break -- Une seule expense par itemId
                    end
                end
            end
        end
    end
    
    -- Ajouter le lot à la liste
    table.insert(GuildLogisticsDB.lots.list, newLot)
    
    -- Mettre à jour nextId
    if (id + 1) > (GuildLogisticsDB.lots.nextId or 1) then
        GuildLogisticsDB.lots.nextId = id + 1
    end
    
    -- Mettre à jour les métadonnées
    local meta = GuildLogisticsDB.meta
    meta.rev = (safenum(kv.rv, -1) >= 0) and safenum(kv.rv, -1) or safenum(meta.rev, 0)
    meta.lastModified = safenum(kv.lm, now())
    
    refreshActive()
    if ns.Emit then ns.Emit("lots:changed") end
    if ns.Emit then ns.Emit("expenses:changed") end -- Notifier que les expenses ont changé aussi
end

local function handleLotDelete(sender, kv)
    local function shouldApply()
        local meta = GuildLogisticsDB and GuildLogisticsDB.meta
        local rv = safenum(kv.rv, -1)
        local myrv = safenum(meta and meta.rev, 0)
        local lm = safenum(kv.lm, -1)
        local mylm = safenum(meta and meta.lastModified, 0)
        
        if rv >= 0 then return rv >= myrv end
        if lm >= 0 then return lm >= mylm end
        return false
    end
    
    if not shouldApply() then return end
    
    local id = safenum(kv.id, 0)
    if id <= 0 then return end
    
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.lots = GuildLogisticsDB.lots or { list = {} }
    GuildLogisticsDB.expenses = GuildLogisticsDB.expenses or { list = {} }
    
    -- Trouver le lot à supprimer pour récupérer ses itemIds
    local lotToDelete = nil
    for _, lot in ipairs(GuildLogisticsDB.lots.list) do
        if safenum(lot.id, 0) == id then
            lotToDelete = lot
            break
        end
    end
    
    -- Libérer les objets (expenses) rattachés au lot avant suppression
    if lotToDelete and lotToDelete.itemIds then
        for _, itemId in ipairs(lotToDelete.itemIds) do
            for _, expense in ipairs(GuildLogisticsDB.expenses.list) do
                if safenum(expense.id, 0) == itemId and expense.lotId == id then
                    expense.lotId = nil -- Libérer l'objet
                    break
                end
            end
        end
    end
    
    -- Supprimer le lot de la liste
    local newList = {}
    for _, lot in ipairs(GuildLogisticsDB.lots.list) do
        if safenum(lot.id, 0) ~= id then
            newList[#newList + 1] = lot
        end
    end
    GuildLogisticsDB.lots.list = newList
    
    -- Mettre à jour les métadonnées
    local meta = GuildLogisticsDB.meta
    meta.rev = (safenum(kv.rv, -1) >= 0) and safenum(kv.rv, -1) or safenum(meta.rev, 0)
    meta.lastModified = safenum(kv.lm, now())
    
    refreshActive()
    if ns.Emit then ns.Emit("lots:changed") end
    if ns.Emit then ns.Emit("expenses:changed") end -- Notifier que les expenses ont changé aussi
end

local function handleLotConsume(sender, kv)
    local function shouldApply()
        local meta = GuildLogisticsDB and GuildLogisticsDB.meta
        local rv = safenum(kv.rv, -1)
        local myrv = safenum(meta and meta.rev, 0)
        local lm = safenum(kv.lm, -1)
        local mylm = safenum(meta and meta.lastModified, 0)
        
        if rv >= 0 then return rv >= myrv end
        if lm >= 0 then return lm >= mylm end
        return false
    end
    
    if not shouldApply() then return end
    
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.lots = GuildLogisticsDB.lots or { list = {} }
    
    -- ✅ Support des deux formats : `id` (ancien) et `ids` (nouveau tableau)
    local lotIds = {}
    if kv.ids and type(kv.ids) == "table" then
        -- Format moderne : tableau d'IDs
        for _, idStr in ipairs(kv.ids) do
            local id = safenum(idStr, 0)
            if id > 0 then
                lotIds[id] = true
            end
        end
    elseif kv.id then
        -- Format legacy : ID unique avec valeur `u` (utilisé)
        local id = safenum(kv.id, 0)
        local u = safenum(kv.u, 0)
        if id > 0 then
            -- Traitement legacy : mettre lot.used = u
            for _, lot in ipairs(GuildLogisticsDB.lots.list) do
                if safenum(lot.id, 0) == id then
                    local oldUsed = safenum(lot.used, 0)
                    if u > oldUsed then -- Seulement si consommation plus élevée
                        lot.used = u
                        -- Nettoyer __pendingConsume si présent
                        if lot.__pendingConsume then
                            lot.__pendingConsume = nil
                        end
                    end
                    break
                end
            end
            
            -- Mettre à jour les métadonnées et sortir
            local meta = GuildLogisticsDB.meta
            meta.rev = (safenum(kv.rv, -1) >= 0) and safenum(kv.rv, -1) or safenum(meta.rev, 0)
            meta.lastModified = safenum(kv.lm, now())
            refreshActive()
            if ns.Emit then ns.Emit("lots:changed") end
            return
        end
    end
    
    -- Format moderne : incrémenter tous les lots dans le set
    for _, lot in ipairs(GuildLogisticsDB.lots.list) do
        local id = safenum(lot.id, 0)
        if lotIds[id] then
            lot.__pendingConsume = nil -- ✅ fin d'attente locale (optimistic UI)
            lot.used = safenum(lot.used, 0) + 1
        end
    end
    
    -- Mettre à jour les métadonnées
    local meta = GuildLogisticsDB.meta
    meta.rev = (safenum(kv.rv, -1) >= 0) and safenum(kv.rv, -1) or safenum(meta.rev, 0)
    meta.lastModified = safenum(kv.lm, now())
    
    refreshActive()
    if ns.Emit then ns.Emit("lots:changed") end
end

-- ===== Handlers d'expenses =====
local function handleExpAdd(sender, kv)
    local function shouldApply()
        local meta = GuildLogisticsDB and GuildLogisticsDB.meta
        local rv = safenum(kv.rv, -1)
        local myrv = safenum(meta and meta.rev, 0)
        local lm = safenum(kv.lm, -1)
        local mylm = safenum(meta and meta.lastModified, 0)
        
        if rv >= 0 then return rv >= myrv end
        if lm >= 0 then return lm >= mylm end
        return false
    end
    
    if not shouldApply() then return end
    
    GuildLogisticsDB.expenses = GuildLogisticsDB.expenses or { list = {}, nextId = 1 }
    local id = safenum(kv.id, 0)
    if id <= 0 then return end
    for _, e in ipairs(GuildLogisticsDB.expenses.list) do 
        if safenum(e.id,0) == id then return end 
    end

    -- Normalisations : 'sid' = ID source stable, 'src' = libellé (compat), lotId 0 -> nil
    local _src = kv.src or kv.s
    local _sid = safenum(kv.sid, 0)
    local _lot = (kv.l and safenum(kv.l, 0) ~= 0) and safenum(kv.l, 0) or nil

    local e = {
        id = id,
        qty = safenum(kv.q,0),
        copper = safenum(kv.c,0),
        source  = _src,               -- compat anciens enregistrements
        sourceId = (_sid > 0) and _sid or nil,
        lotId  = _lot,
        itemID = safenum(kv.i,0),
    }
    table.insert(GuildLogisticsDB.expenses.list, e)
    GuildLogisticsDB.expenses.nextId = math.max(GuildLogisticsDB.expenses.nextId or 1, id + 1)
    
    local meta = GuildLogisticsDB.meta
    meta.rev = (safenum(kv.rv, -1) >= 0) and safenum(kv.rv, -1) or safenum(meta.rev, 0)
    meta.lastModified = (safenum(kv.lm, -1) >= 0) and safenum(kv.lm, -1) or now()
    refreshActive()
end

local function handleExpSplit(sender, kv)
    -- 🔒 Évite le double-traitement chez l'émetteur (GM) : on ignore notre propre message
    do
        local isSelf = false
        if sender then
            local me = playerFullName()
            local same = (U and U.SamePlayer and U.SamePlayer(sender, me)) or (sender == me)
            if same then isSelf = true end
        end

        if isSelf then
            if GLOG.Debug then GLOG.Debug("RECV","EXP_SPLIT","ignored self") end
            return
        end
    end

    local function shouldApply()
        local meta = GuildLogisticsDB and GuildLogisticsDB.meta
        local rv = safenum(kv.rv, -1)
        local myrv = safenum(meta and meta.rev, 0)
        local lm = safenum(kv.lm, -1)
        local mylm = safenum(meta and meta.lastModified, 0)
        
        if rv >= 0 then return rv >= myrv end
        if lm >= 0 then return lm >= mylm end
        return false
    end
    
    if not shouldApply() then return end
    
    GuildLogisticsDB.expenses = GuildLogisticsDB.expenses or { list = {}, nextId = 1 }

    local id  = safenum(kv.id, 0)
    local nq  = safenum(kv.nq, 0)
    local nc  = safenum(kv.nc, 0)

    -- ✅ Supporte message "aplati" et ancien format objet
    local addId  = safenum(kv.addId, 0)
    if addId == 0 and kv.add then addId = safenum(kv.add.id, 0) end
    local addI   = safenum(kv.addI,  0)
    if addI  == 0 and kv.add then addI  = safenum(kv.add.i,  0) end
    local addQ   = safenum(kv.addQ,  0)
    if addQ  == 0 and kv.add then addQ  = safenum(kv.add.q,  0) end
    local addC   = safenum(kv.addC,  0)
    if addC  == 0 and kv.add then addC  = safenum(kv.add.c,  0) end
    local addSid = safenum(kv.addSid,0)
    if addSid== 0 and kv.add then addSid= safenum(kv.add.sid,0) end
    local addLot = safenum(kv.addLot,0)
    if addLot== 0 and kv.add then addLot= safenum(kv.add.l,  0) end

    -- ✏️ Mise à jour + capture méta
    local baseMeta
    for _, it in ipairs(GuildLogisticsDB.expenses.list) do
        if safenum(it.id, 0) == id then
            it.qty    = nq
            it.copper = nc
            baseMeta  = it
            break
        end
    end

    -- ➕ Insertion robuste SANS dépendre d'helpers externes
    if addId > 0 or addQ > 0 or addC > 0 then
        -- anti-collision ID
        local used, maxId = {}, 0
        for _, x in ipairs(GuildLogisticsDB.expenses.list) do
            local xid = safenum(x.id, 0)
            used[xid] = true
            if xid > maxId then maxId = xid end
        end
        local insId = (addId > 0) and addId or (maxId + 1)
        while used[insId] do insId = insId + 1 end

        -- normalisation
        local _lot = (addLot ~= 0) and addLot or nil
        local newLine = {
            id       = insId,
            ts       = now(),
            qty      = (addQ > 0) and addQ or 1,
            copper   = addC,
            sourceId = (addSid > 0) and addSid or (baseMeta and baseMeta.sourceId) or nil,
            itemID   = (addI   > 0) and addI  or (baseMeta and baseMeta.itemID)   or 0,
            itemLink = baseMeta and baseMeta.itemLink or nil,
            itemName = baseMeta and baseMeta.itemName or nil,
            lotId    = _lot,
        }
        table.insert(GuildLogisticsDB.expenses.list, newLine)

        local nextId = safenum(GuildLogisticsDB.expenses.nextId, 1)
        if (insId + 1) > nextId then GuildLogisticsDB.expenses.nextId = insId + 1 end
    else
        if GLOG.Debug then GLOG.Debug("EXP_SPLIT","add-part manquante (id/q/c)") end
    end

    local meta = GuildLogisticsDB.meta
    meta.rev = (safenum(kv.rv, -1) >= 0) and safenum(kv.rv, -1) or safenum(meta.rev, 0)
    meta.lastModified = (safenum(kv.lm, -1) >= 0) and safenum(kv.lm, -1) or now()
    refreshActive()
    if ns.Emit then ns.Emit("expenses:changed") end
end

local function handleExpRemove(sender, kv)
    local function shouldApply()
        local meta = GuildLogisticsDB and GuildLogisticsDB.meta
        local rv = safenum(kv.rv, -1)
        local myrv = safenum(meta and meta.rev, 0)
        local lm = safenum(kv.lm, -1)
        local mylm = safenum(meta and meta.lastModified, 0)
        
        if rv >= 0 then return rv >= myrv end
        if lm >= 0 then return lm >= mylm end
        return false
    end
    
    if not shouldApply() then return end
    
    GuildLogisticsDB.expenses = GuildLogisticsDB.expenses or { list = {}, nextId = 1 }
    local id = safenum(kv.id, 0)
    if id <= 0 then return end

    local e = GuildLogisticsDB.expenses
    if e and e.list then
        local keep = {}
        for _, it in ipairs(e.list) do 
            if safenum(it.id, 0) ~= id then 
                keep[#keep+1] = it 
            end 
        end
        e.list = keep
    end
    
    local meta = GuildLogisticsDB.meta
    meta.rev = (safenum(kv.rv, -1) >= 0) and safenum(kv.rv, -1) or safenum(meta.rev, 0)
    meta.lastModified = (safenum(kv.lm, -1) >= 0) and safenum(kv.lm, -1) or now()

    -- ✏️ Alignement avec EXP_ADD : rafraîchit l'onglet/écran actif (Ressources inclus)
    refreshActive()
    if ns.Emit then ns.Emit("expenses:changed") end
end

-- ===== Handler d'historique =====
local function handleHistAdd(sender, kv)
    local function shouldApply()
        local meta = GuildLogisticsDB and GuildLogisticsDB.meta
        local rv = safenum(kv.rv, -1)
        local myrv = safenum(meta and meta.rev, 0)
        local lm = safenum(kv.lm, -1)
        local mylm = safenum(meta and meta.lastModified, 0)
        
        if rv >= 0 then return rv >= myrv end
        if lm >= 0 then return lm >= mylm end
        return false
    end
    
    if not shouldApply() then return end
    
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.history = GuildLogisticsDB.history or {}
    
    -- Extraire les données du message réseau (format HistoryManager)
    local ts = safenum(kv.ts, now())
    local total = safenum(kv.total, 0)
    local perHead = safenum(kv.per, 0)
    local count = safenum(kv.cnt, 0)
    local refunded = safenum(kv.r, 0) == 1
    local participants = kv.P or {}
    
    -- Vérifier si l'entrée existe déjà (par timestamp uniquement)
    for _, rec in ipairs(GuildLogisticsDB.history) do
        local rts = (type(rec) == "table" and rec.ts) or 0
        if safenum(rts, 0) == ts then 
            return 
        end
    end
    
    -- Parser les lots associés (kv.L = array de CSV "id,name")
    local lots = {}
    if kv.L and type(kv.L) == "table" then
        for _, lotCsv in ipairs(kv.L) do
            if type(lotCsv) == "string" then
                local parts = {}
                for part in string.gmatch(lotCsv, "([^,]+)") do
                    parts[#parts + 1] = part
                end
                if #parts >= 2 then
                    lots[#lots + 1] = {
                        id = tonumber(parts[1]) or 0,
                        name = parts[2] or ""
                    }
                end
            end
        end
    end
    
    -- Créer l'entrée d'historique en stockant UNIQUEMENT des UIDs dans participants
    local pUIDs = {}
    for _, v in ipairs(participants or {}) do pUIDs[#pUIDs+1] = tostring(v or "") end
    local rec = {
        count = count,
        lots = lots,
        participants = pUIDs,          -- UIDs seulement
        perHead = perHead,
        refunded = refunded,
        total = total,
        ts = ts
    }
    
    -- Ajouter l'entrée
    table.insert(GuildLogisticsDB.history, 1, rec)
    
    -- Débit automatique de tous les participants (pas seulement le joueur local)
    if perHead > 0 and participants and type(participants) == "table" and GLOG.Debit then
        for _, uid in ipairs(participants) do
            local participantName = (GLOG.GetNameByUID and GLOG.GetNameByUID(uid)) or nil
            if participantName and participantName ~= "" then
                -- Débiter chaque participant (via nom)
                GLOG.Debit(participantName, perHead)
            end
        end
        
        -- Afficher la popup de notification uniquement pour le joueur local (respects les préférences)
        local playerName = UnitName("player")
        local playerFullName = GetUnitName("player", true) or playerName
        local isLocalPlayerParticipant = false
        
        for _, uid in ipairs(participants) do
            local pname = (GLOG.GetNameByUID and GLOG.GetNameByUID(uid)) or ""
            if pname == playerName or pname == playerFullName then
                isLocalPlayerParticipant = true
                break
            end
        end
        
        if isLocalPlayerParticipant and ns.UI and ns.UI.PopupRaidDebit then
            local before = (GLOG.GetSolde and GLOG.GetSolde(playerFullName)) or 0
            local after = before - perHead  -- Calculate: before - deducted amount
            local _sv = (GLOG.GetSavedWindow and GLOG.GetSavedWindow()) or {}
            _sv.popups = _sv.popups or {}
            if _sv.popups.raidParticipation ~= false then
                -- Suppress the personal toast while showing the specialized raid popup
                if GLOG and GLOG._PushSuppressPersonalToast then GLOG._PushSuppressPersonalToast() end
                ns.UI.PopupRaidDebit(playerFullName, perHead, after, { L = lots })
                if GLOG and GLOG._PopSuppressPersonalToast then GLOG._PopSuppressPersonalToast() end
            end
        end
    end
    
    -- Mettre à jour les métadonnées
    local meta = GuildLogisticsDB.meta
    meta.rev = (safenum(kv.rv, -1) >= 0) and safenum(kv.rv, -1) or safenum(meta.rev, 0)
    meta.lastModified = safenum(kv.lm, now())
    
    refreshActive()
    if ns.Emit then ns.Emit("history:changed") end
end

local function handleHistRefund(sender, kv)
    local function shouldApply()
        local meta = GuildLogisticsDB and GuildLogisticsDB.meta
        local rv = safenum(kv.rv, -1)
        local myrv = safenum(meta and meta.rev, 0)
        local lm = safenum(kv.lm, -1)
        local mylm = safenum(meta and meta.lastModified, 0)
        
        if rv >= 0 then return rv >= myrv end
        if lm >= 0 then return lm >= mylm end
        return false
    end
    
    if not shouldApply() then return end
    
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.history = GuildLogisticsDB.history or {}
    
    local ts = safenum(kv.ts, 0)
    local flag = safenum(kv.r, 1) ~= 0  -- r=1 remboursé, r=0 non remboursé
    
    -- Chercher l'entrée par timestamp uniquement
    for _, h in ipairs(GuildLogisticsDB.history) do
        local hts = (type(h) == "table" and h.ts) or 0
        if ts > 0 and safenum(hts, 0) == ts then
            if type(h) == "table" then
                local wasRefunded = h.refunded
                h.refunded = flag
                -- Gestion des changements d'état de remboursement
                local perHead = h.perHead
                local participants = h.participants
                if perHead and perHead > 0 and participants and type(participants) == "table" then
                    if flag and not wasRefunded then
                        -- Cas 1: Activation du remboursement (gratuit) → créditer tous les participants
                        if GLOG.CreditByUID then
                            for i, participantUID in ipairs(participants) do
                                if participantUID and participantUID ~= "" then
                                    GLOG.CreditByUID(participantUID, perHead)
                                end
                            end
                        end
                    elseif (not flag) and wasRefunded then
                        -- Cas 2: Annulation du remboursement (re-payant) → débiter tous les participants
                        if GLOG.DebitByUID then
                            for i, participantUID in ipairs(participants) do
                                if participantUID and participantUID ~= "" then
                                    GLOG.DebitByUID(participantUID, perHead)
                                end
                            end
                        end
                    end
                end
            end
            break
        end
    end
    
    -- Mettre à jour les métadonnées  
    local meta = GuildLogisticsDB.meta
    meta.rev = (safenum(kv.rv, -1) >= 0) and safenum(kv.rv, -1) or safenum(meta.rev, 0)
    meta.lastModified = safenum(kv.lm, now())
    
    refreshActive()
    if ns.Emit then ns.Emit("history:changed") end
end

local function handleHistDel(sender, kv)
    local function shouldApply()
        local meta = GuildLogisticsDB and GuildLogisticsDB.meta
        local rv = safenum(kv.rv, -1)
        local myrv = safenum(meta and meta.rev, 0)
        local lm = safenum(kv.lm, -1)
        local mylm = safenum(meta and meta.lastModified, 0)
        
        if rv >= 0 then return rv >= myrv end
        if lm >= 0 then return lm >= mylm end
        return false
    end
    
    if not shouldApply() then return end
    
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.history = GuildLogisticsDB.history or {}
    
    local ts = safenum(kv.ts, 0)
    local hid = safenum(kv.h or kv.hid, 0)
    
    -- ✅ Supprimer seulement l'entrée exacte correspondante - pas de wildcard
    local removed = false
    for i = #GuildLogisticsDB.history, 1, -1 do
        local rec = GuildLogisticsDB.history[i]
        local matchHid = (hid > 0 and safenum(rec.hid, 0) == hid)
        local matchTs = (ts > 0 and hid <= 0 and safenum(rec.ts or rec.date, 0) == ts)
        
        if matchHid or matchTs then
            table.remove(GuildLogisticsDB.history, i)
            removed = true
            break -- Ne supprimer qu'UNE entrée
        end
    end
    
    -- Mettre à jour les métadonnées seulement si une suppression a eu lieu
    if removed then
        local meta = GuildLogisticsDB.meta
        meta.rev = (safenum(kv.rv, -1) >= 0) and safenum(kv.rv, -1) or safenum(meta.rev, 0)
        meta.lastModified = safenum(kv.lm, now())
        
        refreshActive()
        if ns.Emit then ns.Emit("history:changed") end
    end
end

-- ===== Table des handlers =====
local MESSAGE_HANDLERS = {
    -- Synchronisation
    ["HELLO"]      = function(sender, kv) GLOG.HandleHello(sender, kv) end,
    ["SYNC_OFFER"] = function(sender, kv) GLOG.HandleSyncOffer(sender, kv) end,
    ["SYNC_GRANT"] = function(sender, kv) GLOG.HandleSyncGrant(sender, kv) end,
    ["SYNC_FULL"]  = function(sender, kv) GLOG.HandleSyncFull(sender, kv) end,
    ["SYNC_ACK"]   = function(sender, kv) GLOG.HandleSyncAck(sender, kv) end,
    
    -- Roster
    ["ROSTER_UPSERT"]  = handleRosterUpsert,
    ["ROSTER_REMOVE"]  = handleRosterRemove,
    ["ROSTER_DELETE"]  = handleRosterRemove, -- alias for backward/forward compatibility
    ["ROSTER_RESERVE"] = handleRosterReserve,
    
    -- Transactions
    ["TX_REQ"]     = handleTxReq,
    ["TX_APPLIED"] = handleTxApplied,
    ["TX_BATCH"]   = handleTxBatch,
    
    -- Statut
    ["STATUS_UPDATE"] = handleStatusUpdate,
    
    -- Erreurs
    ["ERR_REPORT"] = handleErrReport,
    
    -- Dépenses
    ["EXP_ADD"]    = handleExpAdd,
    ["EXP_SPLIT"]  = handleExpSplit,
    ["EXP_REMOVE"] = handleExpRemove,
    
    -- Lots
    ["LOT_CREATE"]  = handleLotCreate,
    ["LOT_DELETE"]  = handleLotDelete,
    ["LOT_CONSUME"] = handleLotConsume,
    
    -- Historique
    ["HIST_ADD"]    = handleHistAdd,
    ["HIST_REFUND"] = handleHistRefund,
    ["HIST_DEL"]    = handleHistDel,

    -- Main/Alt
    ["MA_FULL"]        = handleMAFull,
    ["MA_SET_MAIN"]    = handleMASetMain,
    ["MA_ASSIGN"]      = handleMAAssign,
    ["MA_UNASSIGN"]    = handleMAUnassign,
    ["MA_REMOVE_MAIN"] = handleMARemoveMain,
    ["MA_PROMOTE"]     = handleMAPromote,

    -- Editors allowlist
    ["EDITORS_FULL"]   = handleEditorsFull,
    ["EDITOR_GRANT"]   = handleEditorGrant,
    ["EDITOR_REVOKE"]  = handleEditorRevoke,
}

-- ===== Handler principal =====
function GLOG.HandleMessage(sender, msgType, kv)
    msgType = tostring(msgType or ""):upper()
    
    -- 🚫 Ignorer les messages de soi-même (sauf pour les types SYNC qui peuvent être nécessaires)
    if sender and sender ~= "" then
        local nf = (ns and ns.Util and ns.Util.NormalizeFull) and ns.Util.NormalizeFull or tostring
        local me = (ns and ns.Util and ns.Util.playerFullName and ns.Util.playerFullName()) 
                or (UnitName and UnitName("player")) or ""
        me = nf(me)
        local normalizedSender = nf(sender)
        
        -- Ne pas traiter ses propres messages, sauf les messages SYNC qui peuvent être légitimes
        if normalizedSender == me and not msgType:match("^SYNC_") then
            if GLOG.Debug then 
                GLOG.Debug("RECV", "IGNORED_SELF_MESSAGE", msgType, sender) 
            end
            return
        end
    end
    
    -- ➕ Double sécurité : en mode bootstrap (rev=0), n'accepter que SYNC_*, HELLO et STATUS_UPDATE
    if safenum((GuildLogisticsDB and GuildLogisticsDB.meta and GuildLogisticsDB.meta.rev), 0) == 0 then
        local allowed = tostring(msgType or ""):match("^SYNC_") or msgType == "HELLO" or msgType == "STATUS_UPDATE"
        if not allowed then
            if GLOG.Debug then GLOG.Debug("RECV","BOOTSTRAP_SKIP", msgType) end
            return
        end
    end

    local handler = MESSAGE_HANDLERS[msgType]
    if handler then
        local ok, err = pcall(handler, sender, kv)
        if not ok then
            local eh = geterrorhandler() or print
            eh("Error handling " .. msgType .. ": " .. tostring(err))
        end
    else
        if GLOG.Debug then 
            GLOG.Debug("RECV", "UNKNOWN_MESSAGE_TYPE", msgType) 
        end
    end
end

-- ===== Helpers pour compatibilité =====
GLOG._HandleFull = GLOG.HandleMessage
GLOG.enqueueComplete = enqueueComplete

-- Fonctions globales pour compatibilité
enqueueComplete = enqueueComplete
