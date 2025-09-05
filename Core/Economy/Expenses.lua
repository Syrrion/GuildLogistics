-- ===================================================
-- Core/Economy/Expenses.lua - Gestion de base des dépenses
-- ===================================================
-- API principale pour l'enregistrement et la gestion des dépenses

local ADDON, ns = ...
local Tr = ns and ns.Tr
ns.GLOG = ns.GLOG or {}
local GLOG = ns.GLOG

-- Références aux utilitaires centralisées
local U = ns.Util or {}
local safenum = U.safenum

-- Fonction utilitaire pour EnsureDB sécurisée
local function EnsureDB()
    if GLOG.EnsureDB then
        return GLOG.EnsureDB()
    end
    return nil
end

-- Sources de dépenses (constantes)
GLOG.EXPENSE_SOURCE = GLOG.EXPENSE_SOURCE or {
    AH = 1,     -- Hôtel des ventes
    SHOP = 2,   -- Boutique PNJ
    MANUAL = 3  -- Ajout manuel
}

-- ====== State & API ======
function GLOG.IsExpensesRecording()
    EnsureDB()
    return GuildLogisticsDB.expenses and GuildLogisticsDB.expenses.recording
end

function GLOG.ExpensesStart()
    EnsureDB()
    GuildLogisticsDB.expenses.recording = true
    if GLOG.Expenses_InstallHooks then GLOG.Expenses_InstallHooks() end
    return true
end

function GLOG.ExpensesStop()
    EnsureDB()
    GuildLogisticsDB.expenses.recording = false
    return true
end

function GLOG.ExpensesToggle()
    EnsureDB()
    local e = GuildLogisticsDB.expenses
    e.recording = not e.recording
    if e.recording and GLOG.Expenses_InstallHooks then GLOG.Expenses_InstallHooks() end
    return e.recording
end

function GLOG.LogExpense(sourceId, itemLink, itemName, qty, copper)
    EnsureDB()
    local e = GuildLogisticsDB.expenses
    if not (e and e.recording) then return end
    local amount = tonumber(copper) or 0
    if amount <= 0 then return end

    -- ➕ identifiant stable
    e.nextId = e.nextId or 1
    local nid = e.nextId; e.nextId = nid + 1

    -- ➕ résolution d'ID d'objet fiable (1er retour de GetItemInfoInstant)
    local iid = nil
    if itemLink and itemLink ~= "" and GetItemInfoInstant then
        local id = select(1, GetItemInfoInstant(itemLink))
        iid = tonumber(id)
    end
    -- si pas de lien mais on a l'id (cas commodities), on normalise un lien minimal
    local normalizedLink = itemLink
    if (not normalizedLink or normalizedLink == "") and iid and iid > 0 then
        normalizedLink = "item:" .. tostring(iid)
    end

    table.insert(e.list, {
        id = nid,
        ts = time(),
        sourceId = tonumber(sourceId) or 0,
        itemID = iid,
        itemLink = normalizedLink,
        itemName = itemName,
        qty = tonumber(qty) or 1,
        copper = amount,
    })

    -- ➕ diffusion aux joueurs (le GM seul diffuse)
    if GLOG.BroadcastExpenseAdd and GLOG.IsMaster and GLOG.IsMaster() then
        GLOG.BroadcastExpenseAdd({
            id  = nid,
            sid = tonumber(sourceId) or 0,            -- <-- nouvel ID diffusé
            src = (GLOG.GetExpenseSourceLabel and GLOG.GetExpenseSourceLabel(sourceId)) or nil, -- compat anciens clients
            i   = iid or 0,
            q   = tonumber(qty) or 1,
            c   = amount
        })
    end

    if ns and ns.RefreshAll then ns.RefreshAll() end
end

function GLOG.GetExpenses()
    EnsureDB()
    local e = GuildLogisticsDB.expenses or { list = {} }
    local total = 0
    for _, it in ipairs(e.list or {}) do total = total + (tonumber(it.copper) or 0) end
    return e.list or {}, total
end

-- === Suppression / Vidage des dépenses ===
function GLOG.DeleteExpense(ref)
    EnsureDB()
    local e = GuildLogisticsDB.expenses
    if not (e and e.list) then return false end

    local i = tonumber(ref)
    if not i then return false end

    -- Résolution robuste : accepte un index absolu OU un id stable
    local idx = nil
    if i >= 1 and i <= #e.list then idx = i end
    if not idx then
        for k, it in ipairs(e.list) do
            if tonumber(it.id or 0) == i then idx = k break end
        end
    end
    if not idx then return false end

    local eid = e.list[idx] and e.list[idx].id
    table.remove(e.list, idx)
    if ns and ns.RefreshAll then ns.RefreshAll() end

    -- Diffusion GM : notifier les autres clients
    if GLOG.GM_RemoveExpense and GLOG.IsMaster and GLOG.IsMaster() and tonumber(eid or 0) > 0 then
        GLOG.GM_RemoveExpense(eid)
    end
    return true
end

-- Scinder une dépense libre en deux lignes (modifie l'existante + crée une nouvelle)
function GLOG.SplitExpense(ref, qtySplit)
    EnsureDB()
    local e = GuildLogisticsDB.expenses
    if not (e and e.list) then
        if GLOG and GLOG.Warn then GLOG.Warn("SplitExpense: DB invalide") end
        return false
    end

    local id = tonumber(ref)
    -- Recherche par ID strict, puis par index si besoin
    local idx, it
    if id then
        -- Cherche l'élément par ID dans la liste
        for k, v in ipairs(e.list) do
            if tonumber(v.id) == id then idx, it = k, v; break end
        end
    end
    if not it then
        local i2 = tonumber(ref)
        if i2 and e.list[i2] then idx = i2; it = e.list[i2]; id = tonumber(it.id) end
    end

    if not idx or not it then
        if GLOG and GLOG.Warn then GLOG.Warn("SplitExpense: entrée introuvable ref=",ref) end
        return false
    end
    if tonumber(it.lotId or 0) ~= nil and tonumber(it.lotId or 0) ~= 0 then
        if GLOG and GLOG.Warn then GLOG.Warn("SplitExpense: interdit sur lotId") end
        return false
    end

    local q0 = tonumber(it.qty or 0) or 0
    local qs = tonumber(qtySplit or 0) or 0
    if qs <= 0 or qs >= q0 then
        if GLOG and GLOG.Warn then GLOG.Warn("SplitExpense: quantité invalide qs=",qs," q0=",q0) end
        return false
    end

    local c0 = tonumber(it.copper or 0) or 0
    local unit = math.floor(c0 / math.max(1, q0))
    local addCopper = unit * qs
    local remainQty = q0 - qs
    local remainCopper = c0 - addCopper

    if GLOG and GLOG.Debug then
        GLOG.Debug("SplitExpense","id=",id,"idx=",idx,"q0=",q0,"qs=",qs,"c0=",c0,"unit=",unit)
    end

    -- ✏️ Mise à jour de la ligne existante
    it.qty = remainQty
    it.copper = remainCopper

    -- ➕ Nouvelle ligne (mêmes méta / item)
    -- Sécurise nextId en évitant les collisions si la DB est décalée
    local nid = tonumber(e.nextId or 1) or 1
    local maxId = 0
    for _, x in ipairs(e.list) do
        local xid = tonumber(x.id or 0) or 0
        if xid > maxId then maxId = xid end
    end
    if nid <= maxId then nid = maxId + 1 end
    e.nextId = nid + 1

    local newEntry = {
        id = nid,
        ts = time(),
        sourceId = tonumber(it.sourceId) or 0,
        itemID = tonumber(it.itemID) or 0,
        itemLink = it.itemLink,
        itemName = it.itemName,
        qty = qs,
        copper = addCopper,
    }
    table.insert(e.list, newEntry)

    if ns and ns.RefreshAll then ns.RefreshAll() end

    -- ➕ Diffusion unique "EXP_SPLIT"
    local payload = {
        id = id,
        nq = remainQty,
        nc = remainCopper,
        add = {
            id  = nid,
            i   = tonumber(it.itemID) or 0,
            q   = qs,
            c   = addCopper,
            sid = tonumber(it.sourceId) or 0,
        }
    }

    -- Important : on met à jour la révision AVANT un éventuel sync complet automatique
    GuildLogisticsDB.meta = GuildLogisticsDB.meta or {}
    GuildLogisticsDB.meta.rev = safenum(GuildLogisticsDB.meta.rev, 0) + 1
    GuildLogisticsDB.meta.lastModified = time()

    if GLOG.BroadcastExpenseSplit then
        if GLOG and GLOG.Debug then GLOG.Debug("SplitExpense: envoi via BroadcastExpenseSplit") end
        GLOG.BroadcastExpenseSplit(payload)
    elseif GLOG.Comm_Broadcast then
        -- Fallback : on envoie directement le message avec versionning local
        if GLOG and GLOG.Debug then GLOG.Debug("SplitExpense: fallback direct Comm_Broadcast EXP_SPLIT") end
        GuildLogisticsDB.meta = GuildLogisticsDB.meta or {}
        local rv = tonumber(GuildLogisticsDB.meta.rev or 0) + 1
        GuildLogisticsDB.meta.rev = rv
        GuildLogisticsDB.meta.lastModified = time()
        payload.rv = rv
        payload.lm = GuildLogisticsDB.meta.lastModified
        GLOG.Comm_Broadcast("EXP_SPLIT", payload)
    else
        if GLOG and GLOG.Warn then GLOG.Warn("SplitExpense: aucun transport de broadcast disponible") end
        -- On ne fait plus échouer l'opération locale pour un problème de transport
    end

    return true
end

function GLOG.ClearExpenses()
    EnsureDB()
    local e = GuildLogisticsDB.expenses
    if not e then return false end
    local keep = {}
    for _, it in ipairs(e.list or {}) do
        if it.lotId then table.insert(keep, it) end
    end
    e.list = keep
    if ns and ns.RefreshAll then ns.RefreshAll() end
    return true
end

-- Récupérer une dépense par id stable (retourne l'index courant et l'entrée)
function GLOG.GetExpenseById(id)
    EnsureDB()
    local e = GuildLogisticsDB.expenses
    for idx, it in ipairs(e.list or {}) do
        if it.id == id then return idx, it end
    end
end

-- Helper pour obtenir le label d'une source de dépense
function GLOG.GetExpenseSourceLabel(sourceId)
    local id = tonumber(sourceId) or 0
    if id == GLOG.EXPENSE_SOURCE.AH then return "Hôtel des ventes"
    elseif id == GLOG.EXPENSE_SOURCE.SHOP then return "Boutique"
    elseif id == GLOG.EXPENSE_SOURCE.MANUAL then return "Manuel"
    else return "Inconnu"
    end
end
