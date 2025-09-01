local ADDON, ns = ...
local Tr = ns and ns.Tr
ns.GLOG = ns.GLOG or {}
local GLOG = ns.GLOG

local function EnsureDB() if GLOG._EnsureDB then GLOG._EnsureDB() end end

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
    GuildLogisticsDB.meta.lastModified = (now and now() or time())

    if GLOG.BroadcastExpenseSplit then
        if GLOG and GLOG.Debug then GLOG.Debug("SplitExpense: envoi via BroadcastExpenseSplit") end
        GLOG.BroadcastExpenseSplit(payload)
    elseif GLOG.Comm_Broadcast then
        -- Fallback : on envoie directement le message avec versionning local
        if GLOG and GLOG.Debug then GLOG.Debug("SplitExpense: fallback direct Comm_Broadcast EXP_SPLIT") end
        GuildLogisticsDB.meta = GuildLogisticsDB.meta or {}
        local rv = tonumber(GuildLogisticsDB.meta.rev or 0) + 1
        GuildLogisticsDB.meta.rev = rv
        GuildLogisticsDB.meta.lastModified = now and now() or time()
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

-- ====== Hooks (Boutique / HdV) ======
function GLOG.Expenses_InstallHooks()
    if GLOG._expHooksInstalled then return end
    GLOG._expHooksInstalled = true
    EnsureDB()

    -- file d’attente HdV + dernier prix coté (commodities)
    GLOG._pendingAH = GLOG._pendingAH or {
        items = {},
        commodities = {},
        lastUnitPrice  = nil, -- COMMODITY_PRICE_UPDATED
        lastTotalPrice = nil, -- COMMODITY_PRICE_UPDATED
    }

    -- 1) Événements Retail HdV
        -- Centralisation via Core/Events.lua (hub)
    if not GLOG._ahEventsRegistered then
        local function _onAHEvent(_, event, ...)
            if not GLOG.IsExpensesRecording() then return end

            if event == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
                local auctionID = ...
                local p = GLOG._pendingAH.items[auctionID]
                if p then
                    local spent = tonumber(p.total)
                            or math.max((p.preMoney or 0) - (GetMoney() or 0), 0)
                    if spent and spent > 0 then
                        local qty = tonumber(p.qty) or 1
                        local unit = math.floor(spent / math.max(1, qty))
                        GLOG.LogExpense(GLOG.EXPENSE_SOURCE.AH,   p.itemID or p.link, p.name, qty, unit)
                    end
                    GLOG._pendingAH.items[auctionID] = nil
                else
                    -- Fallback robuste si Start/Confirm non vus
                    if C_AuctionHouse and C_AuctionHouse.GetAuctionInfoByID then
                        local info = C_AuctionHouse.GetAuctionInfoByID(auctionID)
                        if info then
                            local amount = tonumber(info.buyoutAmount or info.bidAmount)
                            if amount and amount > 0 then
                                local link = info.itemLink
                                local name = (link and link:match("%[(.-)%]")) or info.itemName or Tr("label_ah")
                                local iid  = (info.itemKey and info.itemKey.itemID)
                                        or (link and GetItemInfoInstant and select(1, GetItemInfoInstant(link)))
                                GLOG.LogExpense(GLOG.EXPENSE_SOURCE.AH,   iid or link, name, 1, amount)
                            end
                        end
                    end
                end

            elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
                local p = table.remove(GLOG._pendingAH.commodities, 1)
                if p then
                    local spent = tonumber(p.total)
                             or tonumber(GLOG._pendingAH.lastTotalPrice)
                             or ((GLOG._pendingAH.lastUnitPrice and p.qty) and (GLOG._pendingAH.lastUnitPrice * p.qty))
                             or math.max((p.preMoney or 0) - (GetMoney() or 0), 0)
                    if spent and spent > 0 then
                        GLOG.LogExpense(GLOG.EXPENSE_SOURCE.AH, p.itemID or p.link, p.name, p.qty or 1, spent)
                    end
                end

            elseif event == "COMMODITY_PURCHASE_FAILED" then
                table.remove(GLOG._pendingAH.commodities, 1)

            elseif event == "COMMODITY_PRICE_UPDATED" then
                local unitPrice, totalPrice = ...
                GLOG._pendingAH.lastUnitPrice  = tonumber(unitPrice)
                GLOG._pendingAH.lastTotalPrice = tonumber(totalPrice)
            end
        end

        ns.Events.Register("AUCTION_HOUSE_PURCHASE_COMPLETED", _onAHEvent)
        ns.Events.Register("COMMODITY_PURCHASE_SUCCEEDED",     _onAHEvent)
        ns.Events.Register("COMMODITY_PURCHASE_FAILED",        _onAHEvent)
        ns.Events.Register("COMMODITY_PRICE_UPDATED",          _onAHEvent)

        GLOG._ahEventsRegistered = true
    end


    -- 2) Attente du chargement de l’UI HdV pour poser les hooks de méthode
    local function InstallAHHooks()
        if not C_AuctionHouse or GLOG._ahHooksInstalled then return end

        -- Items (non-commodities)
        if C_AuctionHouse.StartItemPurchase and not GLOG._ahStartItemHook then
            hooksecurefunc(C_AuctionHouse, "StartItemPurchase", function(auctionID)
                local p = GLOG._pendingAH.items[auctionID] or { qty = 1 }
                p.preMoney = p.preMoney or (GetMoney() or 0)
                local info = C_AuctionHouse.GetAuctionInfoByID and C_AuctionHouse.GetAuctionInfoByID(auctionID)
                if info then
                    p.link   = info.itemLink
                    p.name   = info.itemName or (info.itemLink and info.itemLink:match("%[(.-)%]")) or p.name
                    p.itemID = p.itemID or (info.itemKey and info.itemKey.itemID) or (info.itemLink and GetItemInfoInstant and select(1, GetItemInfoInstant(info.itemLink)))
                end
                GLOG._pendingAH.items[auctionID] = p
            end)
            GLOG._ahStartItemHook = true
        end

        if C_AuctionHouse.ConfirmItemPurchase and not GLOG._ahConfirmItemHook then
            hooksecurefunc(C_AuctionHouse, "ConfirmItemPurchase", function(auctionID, expectedPrice)
                local p = GLOG._pendingAH.items[auctionID] or { qty = 1 }
                p.preMoney = p.preMoney or (GetMoney() or 0)
                p.total = tonumber(expectedPrice) or p.total
                if (not p.link) or (not p.name) or (not p.itemID) then
                    local info = C_AuctionHouse.GetAuctionInfoByID and C_AuctionHouse.GetAuctionInfoByID(auctionID)
                    if info then
                        p.link   = p.link   or info.itemLink
                        p.name   = p.name   or info.itemName or (info.itemLink and info.itemLink:match("%[(.-)%]"))
                        p.itemID = p.itemID or (info.itemKey and info.itemKey.itemID) or (info.itemLink and GetItemInfoInstant and select(1, GetItemInfoInstant(info.itemLink)))
                    end
                end
                GLOG._pendingAH.items[auctionID] = p
            end)
            GLOG._ahConfirmItemHook = true
        end

        if C_AuctionHouse.PlaceBid and not GLOG._ahPlaceBidHook then
            hooksecurefunc(C_AuctionHouse, "PlaceBid", function(auctionID, bidAmount)
                local p = GLOG._pendingAH.items[auctionID] or { qty = 1 }
                p.preMoney = p.preMoney or (GetMoney() or 0)
                p.total = p.total or tonumber(bidAmount)
                GLOG._pendingAH.items[auctionID] = p
            end)
            GLOG._ahPlaceBidHook = true
        end

        -- Commodities (matériaux en vrac)
        if C_AuctionHouse.StartCommoditiesPurchase and not GLOG._ahStartCommHook then
            hooksecurefunc(C_AuctionHouse, "StartCommoditiesPurchase", function(itemID, quantity)
                local name, link = GetItemInfo(itemID)
                table.insert(GLOG._pendingAH.commodities, {
                    itemID   = itemID,
                    qty      = quantity or 1,
                    name     = name,
                    link     = link,
                    preMoney = GetMoney() or 0,
                    total    = nil, -- fixée au Confirm / price-updated
                })
            end)
            GLOG._ahStartCommHook = true
        end

        if C_AuctionHouse.ConfirmCommoditiesPurchase and not GLOG._ahConfirmCommHook then
            hooksecurefunc(C_AuctionHouse, "ConfirmCommoditiesPurchase", function(itemID, quantity)
                -- On MET À JOUR la dernière entrée (créée par Start...), on n’en crée pas une nouvelle
                local idx = #GLOG._pendingAH.commodities
                if idx > 0 then
                    local p = GLOG._pendingAH.commodities[idx]
                    p.qty   = quantity or p.qty or 1
                    -- Priorité au dernier total coté remonté par COMMODITY_PRICE_UPDATED
                    p.total = p.total or GLOG._pendingAH.lastTotalPrice
                           or ((GLOG._pendingAH.lastUnitPrice and p.qty) and (GLOG._pendingAH.lastUnitPrice * p.qty))
                    GLOG._pendingAH.commodities[idx] = p
                else
                    -- Sécurité si Start n’a pas été capté (rare) : on crée une entrée minimaliste
                    local name, link = GetItemInfo(itemID)
                    table.insert(GLOG._pendingAH.commodities, {
                        itemID   = itemID,
                        qty      = quantity or 1,
                        name     = name,
                        link     = link,
                        preMoney = GetMoney() or 0,
                        total    = GLOG._pendingAH.lastTotalPrice
                                or ((GLOG._pendingAH.lastUnitPrice and quantity) and (GLOG._pendingAH.lastUnitPrice * quantity)),
                    })
                end
            end)
            GLOG._ahConfirmCommHook = true
        end

        GLOG._ahHooksInstalled = true
    end

    -- Installe tout de suite si l’API est déjà là
    InstallAHHooks()

    -- Et sinon, installe dès que l’UI HdV se charge (centralisé)
    if not GLOG._ahHookWaiterRegistered then
        local AHWaiter = {}
        ns.Events.Register("ADDON_LOADED", AHWaiter, function(_, _, addonName)
            if addonName == "Blizzard_AuctionHouse" or addonName == "Blizzard_AuctionHouseUI" then
                InstallAHHooks()
                ns.Events.UnregisterOwner(AHWaiter) -- one-shot
            end
        end)
        GLOG._ahHookWaiterRegistered = true
    end

    -- 3) HdV Legacy (PlaceAuctionBid)
    if _G.PlaceAuctionBid and not GLOG._legacyBidHook then
        hooksecurefunc("PlaceAuctionBid", function(listType, index, bid)
            if not GLOG.IsExpensesRecording() then return end
            local name, _, _, _, _, _, _, _, buyoutPrice = GetAuctionItemInfo(listType, index)
            local amount = (buyoutPrice and buyoutPrice > 0) and buyoutPrice or bid
            if amount and amount > 0 then
                local link = GetAuctionItemLink(listType, index)
                GLOG.LogExpense(GLOG.EXPENSE_SOURCE.AH,   link,               name,   1,    amount)
            end
        end)
        GLOG._legacyBidHook = true
    end

    -- 4) Boutique PNJ
    if BuyMerchantItem and not GLOG._merchantHook then
        hooksecurefunc("BuyMerchantItem", function(index, quantity)
            if not GLOG.IsExpensesRecording() then return end
            local name, _, price = GetMerchantItemInfo(index) -- copper
            local q = quantity or 1
            local extCostCount = GetMerchantItemCostInfo and GetMerchantItemCostInfo(index) or 0
            if extCostCount and extCostCount > 0 then return end -- achat non-or
            local link = GetMerchantItemLink and GetMerchantItemLink(index) or name
            local unit = math.floor((price or 0) / math.max(1, stackCount or 1))
            if unit > 0 then
                GLOG.LogExpense(GLOG.EXPENSE_SOURCE.SHOP, link,               name,   q,    unit)
            end
        end)
        GLOG._merchantHook = true
    end
end
