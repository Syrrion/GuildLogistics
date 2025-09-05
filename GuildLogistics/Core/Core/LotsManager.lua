-- ===================================================
-- Core/Core/LotsManager.lua - Gestionnaire des lots et ressources
-- ===================================================
-- Responsable de la gestion des lots de consommables, ressources et fonctions de purge

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
-- ======   LOTS      ======
-- =========================
-- Lots consommables : 1 session (100%) ou multi-sessions (1/N par clôture).
-- Le contenu d'un lot est figé à la création. Les éléments proviennent des
-- "Ressources libres" (dépenses non rattachées).

local function _ensureLots()
    EnsureDB()
    GuildLogisticsDB.lots     = GuildLogisticsDB.lots     or { nextId = 1, list = {} }
    GuildLogisticsDB.expenses = GuildLogisticsDB.expenses or { recording=false, list = {}, nextId = 1 }
end

function GLOG.GetLots()
    _ensureLots()
    return GuildLogisticsDB.lots.list
end

function GLOG.Lot_GetById(id)
    _ensureLots()
    for _, l in ipairs(GuildLogisticsDB.lots.list or {}) do
        if l.id == id then return l end
    end
end

function GLOG.Lot_Status(lot)
    if not lot then return "?" end
    local used = tonumber(lot.used or 0) or 0
    local N    = tonumber(lot.sessions or 1) or 1
    if used <= 0 then return "A_UTILISER" end
    if used < N  then return "EN_COURS"  end
    return "EPU"
end

function GLOG.Lot_IsSelectable(lot)
    return lot and (not lot.__pendingConsume) and GLOG.Lot_Status(lot) ~= "EPU"
end

-- Coût par utilisation (ex-ShareGold) en or entiers — pas de PA/PC.
function GLOG.Lot_ShareGold(lot)  -- compat : on conserve le nom
    local totalC = tonumber(lot.totalCopper or lot.copper or 0) or 0
    local N      = tonumber(lot.sessions or 1) or 1
    return math.floor( math.floor(totalC / 10000) / N )
end

-- ➕ Utilitaires "charges"
function GLOG.Lot_UseCostGold(lot)  -- alias explicite
    return GLOG.Lot_ShareGold(lot)
end

function GLOG.Lot_Remaining(lot)   -- utilisations restantes
    local used = tonumber(lot.used or 0) or 0
    local N    = tonumber(lot.sessions or 1) or 1
    return math.max(0, N - used)
end

-- Valeur restante (en cuivre) d'un lot en tenant compte des utilisations consommées
function GLOG.Lot_RemainingCopper(lot)
    _ensureLots()
    if not lot then return 0 end
    local total = tonumber(lot.totalCopper or lot.copper or 0) or 0
    local N     = tonumber(lot.sessions or 1) or 1
    local used  = tonumber(lot.used or 0) or 0
    if N <= 0 then return 0 end
    local remUses = math.max(0, math.min(N, N - used))
    return math.floor((total * remUses) / N) -- arrondi inf. pour ne jamais surestimer
end

-- Somme totale des ressources disponibles (ressources libres + valeur restante des lots non épuisés), en cuivre
function GLOG.Resources_TotalAvailableCopper()
    EnsureDB(); _ensureLots()
    local free = 0
    local e = GuildLogisticsDB.expenses or { list = {} }
    for _, it in ipairs(e.list or {}) do
        local lid = tonumber(it.lotId or 0) or 0
        if lid == 0 then
            free = free + (tonumber(it.copper) or 0)
        end
    end

    local remainLots = 0
    for _, l in ipairs(GuildLogisticsDB.lots.list or {}) do
        remainLots = remainLots + (GLOG.Lot_RemainingCopper(l) or 0)
    end
    return free + remainLots
end

-- Création : fige le contenu depuis une liste d'index ABSOLUS de GuildLogisticsDB.expenses.list
-- isMulti = true/false ; sessions = N si multi (>=1)
function GLOG.Lot_Create(name, isMulti, sessions, absIdxs)
    _ensureLots()
    name = name or "Lot"
    local e = GuildLogisticsDB.expenses
    local L = GuildLogisticsDB.lots
    local id = L.nextId or 1

    local itemIds, total = {}, 0
    for _, abs in ipairs(absIdxs or {}) do
        local it = e.list[abs]
        if it and not it.lotId then
            table.insert(itemIds, it.id or 0)
            total = total + (tonumber(it.copper) or 0)
            it.lotId = id
        end
    end

    local l = { 
        id = id, 
        name = name, 
        sessions = isMulti and (tonumber(sessions) or 2) or 1, 
        used = 0, 
        totalCopper = total, 
        itemIds = itemIds 
    }
    table.insert(L.list, l); L.nextId = id + 1
    if ns.Emit then ns.Emit("lots:changed") end

    -- ➕ Diffusion GM
    if GLOG.BroadcastLotCreate and GLOG.IsMaster and GLOG.IsMaster() then 
        GLOG.BroadcastLotCreate(l) 
    end
    return l
end

-- Création d'un lot "or uniquement" (sans rattacher d'objets)
-- name: string, amountCopper: number (cuivre), isMulti: bool, sessions: N
function GLOG.Lot_CreateFromAmount(name, amountCopper, isMulti, sessions)
    _ensureLots()
    local L = GuildLogisticsDB.lots
    local id = L.nextId or 1

    local N = tonumber(sessions) or 1
    if N < 1 then N = 1 end
    if not isMulti then N = 1 end

    local l = {
        id = id,
        name = name or "Lot",
        sessions = N,
        used = 0,
        totalCopper = tonumber(amountCopper) or 0,
        itemIds = {},     -- aucun objet rattaché
    }

    table.insert(L.list, l)
    L.nextId = id + 1

    if ns.Emit then ns.Emit("lots:changed") end
    if ns.RefreshActive then ns.RefreshActive() end

    -- ➕ Diffusion GM
    if GLOG.BroadcastLotCreate and GLOG.IsMaster and GLOG.IsMaster() then
        GLOG.BroadcastLotCreate(l)
    end
    return true
end

-- Suppression possible uniquement si jamais utilisé (rend les ressources libres)
function GLOG.Lot_Delete(id)
    _ensureLots()
    local L = GuildLogisticsDB.lots
    local list = L.list or {}
    local idx = nil
    for i, l in ipairs(list) do 
        if l.id == id then 
            idx = i 
            break 
        end 
    end
    if not idx then return false end
    
    table.remove(list, idx)
    for _, it in ipairs(GuildLogisticsDB.expenses.list or {}) do 
        if it.lotId == id then 
            it.lotId = nil 
        end 
    end
    
    if ns.Emit then ns.Emit("lots:changed") end
    if ns.RefreshActive then ns.RefreshActive() end -- ✅ disparition immédiate à l'écran

    -- ➕ Diffusion GM
    if GLOG.BroadcastLotDelete and GLOG.IsMaster and GLOG.IsMaster() then 
        GLOG.BroadcastLotDelete(id) 
    end
    return true
end

function GLOG.Lot_ListSelectable()
    _ensureLots()
    local out = {}
    for _, l in ipairs(GuildLogisticsDB.lots.list or {}) do
        if GLOG.Lot_IsSelectable(l) then 
            out[#out+1] = l 
        end
    end
    return out
end

function GLOG.Lot_Consume(id)
    _ensureLots()
    local l = GLOG.Lot_GetById(id); if not l then return false end
    local N = tonumber(l.sessions or 1) or 1
    local u = tonumber(l.used or 0) or 0
    l.used = math.min(u + 1, N)  -- ne décrémente que d'1, borné au max
    if ns.RefreshAll then ns.RefreshAll() end
    return true
end

function GLOG.Lots_ConsumeMany(ids)
    _ensureLots()
    ids = ids or {}

    local isMaster = GLOG.IsMaster and GLOG.IsMaster()
    if isMaster then
        -- GM : applique directement la consommation (évite le blocage __pendingConsume)
        local L = GuildLogisticsDB.lots
        for _, id in ipairs(ids) do
            for _, l in ipairs(L.list or {}) do
                if l.id == id then
                    local u = tonumber(l.used or 0) or 0
                    local N = tonumber(l.sessions or 1) or 1
                    l.used = math.min(u + 1, N) -- ✅ bornage sécurité
                end
            end
        end
        if ns.Emit then ns.Emit("lots:changed") end
        if ns.RefreshActive then ns.RefreshActive() end

        -- Diffusion : les autres clients (et GM aussi) recevront LOT_CONSUME,
        -- mais côté GM on a déjà appliqué => aucun lot bloqué en "pending".
        if GLOG.BroadcastLotsConsume then 
            GLOG.BroadcastLotsConsume(ids) 
        end
    else
        -- Client : applique localement sans diffusion (borné).
        local L = GuildLogisticsDB.lots
        for _, id in ipairs(ids) do
            for _, l in ipairs(L.list or {}) do
                if l.id == id then
                    local u = tonumber(l.used or 0) or 0
                    local N = tonumber(l.sessions or 1) or 1
                    l.used = math.min(u + 1, N) -- ✅ bornage sécurité
                end
            end
        end
        if ns.Emit then ns.Emit("lots:changed") end
    end
end

function GLOG.Lots_ComputeGoldTotal(ids)
    local g = 0
    for _, id in ipairs(ids or {}) do
        local l = GLOG.Lot_GetById(id)
        if l and GLOG.Lot_IsSelectable(l) then 
            g = g + GLOG.Lot_ShareGold(l) 
        end
    end
    return g
end

-- =========================
-- ===== Purges (GM)  ======
-- =========================

-- Supprime tous les lots épuisés + tous leurs objets associés
function GLOG.PurgeLotsAndItemsExhausted()
    EnsureDB(); _ensureLots()
    local L = GuildLogisticsDB.lots
    local E = GuildLogisticsDB.expenses

    local purgeLots   = {}
    local purgeItems  = {}

    for _, l in ipairs(L.list or {}) do
        if (GLOG.Lot_Status and GLOG.Lot_Status(l) == "EPU") then
            purgeLots[l.id] = true
            for _, eid in ipairs(l.itemIds or {}) do 
                purgeItems[eid] = true 
            end
        end
    end

    -- Filtre des dépenses (objets)
    local newE, removedItems = {}, 0
    for _, it in ipairs(E.list or {}) do
        local id = it.id
        local kill = (purgeItems[id] == true) or (it.lotId and purgeLots[it.lotId])
        if kill then
            removedItems = removedItems + 1
        else
            newE[#newE+1] = it
        end
    end
    E.list = newE

    -- Filtre des lots
    local newL, removedLots = {}, 0
    for _, l in ipairs(L.list or {}) do
        if purgeLots[l.id] then
            removedLots = removedLots + 1
        else
            newL[#newL+1] = l
        end
    end
    L.list = newL

    if ns.Emit then ns.Emit("expenses:changed") end
    if ns.Emit then ns.Emit("lots:changed") end
    if ns.RefreshAll then ns.RefreshAll() end

    if GLOG.BumpRevisionLocal then
        GLOG.BumpRevisionLocal()
    end
    return removedLots, removedItems
end

-- Supprime absolument tous les lots + tous les objets
function GLOG.PurgeAllResources()
    EnsureDB(); _ensureLots()
    local L = GuildLogisticsDB.lots
    local E = GuildLogisticsDB.expenses

    local removedLots  = #(L.list or {})
    local removedItems = #(E.list or {})

    L.list, E.list = {}, {}
    L.nextId, E.nextId = 1, 1

    if ns.Emit then ns.Emit("expenses:changed") end
    if ns.Emit then ns.Emit("lots:changed") end
    if ns.RefreshAll then ns.RefreshAll() end

    if GLOG.BumpRevisionLocal then
        GLOG.BumpRevisionLocal()
    end
    return removedLots, removedItems
end

-- ===== Dépenses : table de correspondance des sources (IDs stables) =====
GLOG.EXPENSE_SOURCE = GLOG.EXPENSE_SOURCE or {
    SHOP = 1,        -- Boutique PNJ
    AH   = 2,        -- Hôtel des Ventes
}

function GLOG.GetExpenseSourceLabel(id)
    local v = tonumber(id) or 0
    if v == (GLOG.EXPENSE_SOURCE and GLOG.EXPENSE_SOURCE.SHOP) then
        return (ns.Tr and ns.Tr("lbl_shop")) or "Shop"
    elseif v == (GLOG.EXPENSE_SOURCE and GLOG.EXPENSE_SOURCE.AH) then
        return (ns.Tr and ns.Tr("lbl_ah")) or "AH"
    end
    return ""
end
