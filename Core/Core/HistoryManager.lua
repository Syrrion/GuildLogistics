-- ===================================================
-- Core/Core/HistoryManager.lua - Gestionnaire de l'historique
-- ===================================================
-- Responsable de la gestion de l'historique des sessions : ajout, remboursements, suppression

local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
local GLOG = ns.GLOG

-- Références aux utilitaires centralisées
local U = ns.Util or {}

-- Référence à EnsureDB (fournie par DatabaseManager)
local EnsureDB = function()
    if GLOG.EnsureDB then
        GLOG.EnsureDB()
    end
end

-- =========================
-- ======  HISTORY    ======
-- =========================

function GLOG.AddHistorySession(total, perHead, participants, ctx)
    EnsureDB()
    GuildLogisticsDB.history = GuildLogisticsDB.history or {}

    -- Convertir la liste des participants en UIDs (ShortId strings)
    local U = {}
    for _, v in ipairs(participants or {}) do
        local s = tostring(v or "")
        local uid = s
        if s:find("%-") then
            -- ressemble à un nom complet → mapper vers UID
            uid = (GLOG.GetOrAssignUID and GLOG.GetOrAssignUID(s)) or s
        else
            -- suppose déjà un UID
            uid = s
        end
        if uid and uid ~= "" then U[#U+1] = uid end
    end

    local s = {
        count = #U,
        lots = {},  -- Initialiser lots comme table vide  
        participants = U, -- stocke uniquement des UIDs
        perHead = math.floor(perHead or 0),
        refunded = false,
        total = math.floor(total or 0),
        ts = time()
    }

    -- Ajouter les lots si fournis dans le contexte (simplifiés : id + name seulement)
    if type(ctx) == "table" and ctx.lots then
        for _, lot in ipairs(ctx.lots) do
            if type(lot) == "table" then
                s.lots[#s.lots + 1] = {
                    id = tonumber(lot.id or 0) or 0,
                    name = tostring(lot.name or ("Lot " .. tostring(lot.id or 0)))
                }
            end
        end
    end
    
    table.insert(GuildLogisticsDB.history, 1, s)

    -- Diffusion réseau (petit message) si GM
    if GLOG.IsMaster and GLOG.IsMaster() and GLOG.Comm_Broadcast then
        GuildLogisticsDB.meta = GuildLogisticsDB.meta or {}
        local rv = (GuildLogisticsDB.meta.rev or 0) + 1
        GuildLogisticsDB.meta.rev = rv
        GuildLogisticsDB.meta.lastModified = time()

        -- ➕ sérialise les lots pour l'ajout (liste de CSV "id,name")
        local Lraw = {}
        for _, li in ipairs(s.lots or {}) do
            if type(li) == "table" then
                local id   = tonumber(li.id or 0) or 0
                local name = tostring(li.name or ("Lot " .. tostring(id)))
                Lraw[#Lraw+1] = table.concat({ id, name }, ",")
            end
        end

        -- Diffuse les UIDs des participants dans P
        GLOG.Comm_Broadcast("HIST_ADD", {
            ts = s.ts, total = s.total, per = s.perHead, cnt = s.count,
            r = s.refunded and 1 or 0, P = s.participants, L = Lraw, -- UIDs
            rv = rv, lm = GuildLogisticsDB.meta.lastModified,
        })
    end
    if ns.Emit then ns.Emit("history:changed") end
end

function GLOG.GetHistory()
    EnsureDB()
    return GuildLogisticsDB.history
end

function GLOG.RefundSession(idx)
    EnsureDB()
    local s = GuildLogisticsDB.history[idx]
    if not s or s.refunded then return false end
    local per = tonumber(s.perHead) or 0
    local parts = s.participants or {}

    if GLOG.IsMaster and GLOG.IsMaster() and GLOG.GM_BroadcastBatch then
        local adjusts = {}
        for _, uid in ipairs(parts) do 
            local name = (GLOG.GetNameByUID and GLOG.GetNameByUID(uid)) or nil
            if name then adjusts[#adjusts+1] = { name = name, delta = per } end
        end
        GLOG.GM_BroadcastBatch(adjusts, { reason = "REFUND", silent = true })
    else
        for _, uid in ipairs(parts) do 
            local name = (GLOG.GetNameByUID and GLOG.GetNameByUID(uid)) or nil
            if name and GuildLogisticsDB.players[name] and GLOG.Credit then 
                GLOG.Credit(name, per) 
            end 
        end
    end

    s.refunded = true

    -- Diffusion du changement d'état si GM
    if GLOG.IsMaster and GLOG.IsMaster() and GLOG.Comm_Broadcast then
        GuildLogisticsDB.meta = GuildLogisticsDB.meta or {}
        local rv = (GuildLogisticsDB.meta.rev or 0) + 1
        GuildLogisticsDB.meta.rev = rv
        GuildLogisticsDB.meta.lastModified = time()
        GLOG.Comm_Broadcast("HIST_REFUND", { 
            ts = s.ts, r = 1,
            rv = rv, lm = GuildLogisticsDB.meta.lastModified 
        })
    end
    if ns.Emit then ns.Emit("history:changed") end
    return true
end

function GLOG.UnrefundSession(idx)
    EnsureDB()
    local s = GuildLogisticsDB.history[idx]
    if not s or not s.refunded then return false end
    local per = tonumber(s.perHead) or 0
    local parts = s.participants or {}

    if GLOG.IsMaster and GLOG.IsMaster() and GLOG.GM_BroadcastBatch then
        local adjusts = {}
        for _, uid in ipairs(parts) do 
            local name = (GLOG.GetNameByUID and GLOG.GetNameByUID(uid)) or nil
            if name then adjusts[#adjusts+1] = { name = name, delta = -per } end
        end
        GLOG.GM_BroadcastBatch(adjusts, { reason = "REFUND", silent = true })
    else
        for _, uid in ipairs(parts) do 
            local name = (GLOG.GetNameByUID and GLOG.GetNameByUID(uid)) or nil
            if name and GuildLogisticsDB.players[name] and GLOG.Debit then 
                GLOG.Debit(name, per) 
            end 
        end
    end

    s.refunded = false

    -- Diffusion du changement d'état si GM
    if GLOG.IsMaster and GLOG.IsMaster() and GLOG.Comm_Broadcast then
        GuildLogisticsDB.meta = GuildLogisticsDB.meta or {}
        local rv = (GuildLogisticsDB.meta.rev or 0) + 1
        GuildLogisticsDB.meta.rev = rv
        GuildLogisticsDB.meta.lastModified = time()
        GLOG.Comm_Broadcast("HIST_REFUND", { 
            ts = s.ts, r = 0, 
            rv = rv, lm = GuildLogisticsDB.meta.lastModified 
        })
    end
    if ns.Emit then ns.Emit("history:changed") end
    return true
end

function GLOG.DeleteHistory(idx)
    EnsureDB()
    local hist = GuildLogisticsDB.history or {}
    local s = hist[idx]; if not s then return false end
    table.remove(hist, idx)

    -- Diffusion de la suppression si GM via la fonction centralisée
    if GLOG.IsMaster and GLOG.IsMaster() and GLOG.BroadcastHistoryDelete then
        GLOG.BroadcastHistoryDelete(s.ts)  -- ✅ Passe le timestamp (identifiant unique des entrées)
    end
    if ns.Emit then ns.Emit("history:changed") end
    return true
end
