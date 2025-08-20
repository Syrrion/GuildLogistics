local ADDON, ns = ...
ns.GMGR = ns.GMGR or {}
local GMGR = ns.GMGR

local function EnsureDB() if GMGR._EnsureDB then GMGR._EnsureDB() end end

-- ====== State & API ======
function GMGR.IsExpensesRecording()
    EnsureDB()
    return GuildManagerDB.expenses and GuildManagerDB.expenses.recording
end

function GMGR.ExpensesStart()
    EnsureDB()
    GuildManagerDB.expenses.recording = true
    if GMGR.Expenses_InstallHooks then GMGR.Expenses_InstallHooks() end
    return true
end

function GMGR.ExpensesStop()
    EnsureDB()
    GuildManagerDB.expenses.recording = false
    return true
end

function GMGR.ExpensesToggle()
    EnsureDB()
    local e = GuildManagerDB.expenses
    e.recording = not e.recording
    if e.recording and GMGR.Expenses_InstallHooks then GMGR.Expenses_InstallHooks() end
    return e.recording
end

function GMGR.LogExpense(source, itemLink, itemName, qty, copper)
    EnsureDB()
    local e = GuildManagerDB.expenses
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
        source = source,                 -- "Boutique" | "HdV"
        itemID = iid,                    -- ➕ ID WoW de l'objet
        itemLink = normalizedLink,       -- lien minimal si besoin
        itemName = itemName,             -- fallback UI
        qty = tonumber(qty) or 1,
        copper = amount,
    })

    -- ➕ diffusion aux joueurs (le GM seul diffuse)
    if GMGR.BroadcastExpenseAdd and GMGR.IsMaster and GMGR.IsMaster() then
        GMGR.BroadcastExpenseAdd({
            id = nid, src = source, i = iid or 0,
            q = tonumber(qty) or 1, c = amount
        })
    end

    if ns and ns.RefreshAll then ns.RefreshAll() end
end


function GMGR.GetExpenses()
    EnsureDB()
    local e = GuildManagerDB.expenses or { list = {} }
    local total = 0
    for _, it in ipairs(e.list or {}) do total = total + (tonumber(it.copper) or 0) end
    return e.list or {}, total
end

-- === Suppression / Vidage des dépenses ===
function GMGR.DeleteExpense(ref)
    EnsureDB()
    local e = GuildManagerDB.expenses
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

    -- Interdit de supprimer une dépense rattachée à un lot
    if e.list[idx] and e.list[idx].lotId then
        if UIErrorsFrame then UIErrorsFrame:AddMessage("|cffff60...ce rattachée à un lot : suppression impossible.", 1,0.4,0.4) end
        return false
    end

    local eid = e.list[idx] and e.list[idx].id
    table.remove(e.list, idx)
    if ns and ns.RefreshAll then ns.RefreshAll() end

    -- Diffusion GM : notifier les autres clients
    if GMGR.GM_RemoveExpense and GMGR.IsMaster and GMGR.IsMaster() and tonumber(eid or 0) > 0 then
        GMGR.GM_RemoveExpense(eid)
    end
    return true
end


function GMGR.ClearExpenses()
    EnsureDB()
    local e = GuildManagerDB.expenses
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
function GMGR.GetExpenseById(id)
    EnsureDB()
    local e = GuildManagerDB.expenses
    for idx, it in ipairs(e.list or {}) do
        if it.id == id then return idx, it end
    end
end

-- ====== Hooks (Boutique / HdV) ======
function GMGR.Expenses_InstallHooks()
    if GMGR._expHooksInstalled then return end
    GMGR._expHooksInstalled = true
    EnsureDB()

    -- file d’attente HdV + dernier prix coté (commodities)
    GMGR._pendingAH = GMGR._pendingAH or {
        items = {},
        commodities = {},
        lastUnitPrice  = nil, -- COMMODITY_PRICE_UPDATED
        lastTotalPrice = nil, -- COMMODITY_PRICE_UPDATED
    }

    -- 1) Événements Retail HdV
    if not GMGR._ahEventFrame then
        local ev = CreateFrame("Frame")
        ev:RegisterEvent("AUCTION_HOUSE_PURCHASE_COMPLETED") -- auctionID
        ev:RegisterEvent("COMMODITY_PURCHASE_SUCCEEDED")
        ev:RegisterEvent("COMMODITY_PURCHASE_FAILED")
        ev:RegisterEvent("COMMODITY_PRICE_UPDATED") -- unit,total

        ev:SetScript("OnEvent", function(_, event, ...)
            if not GMGR.IsExpensesRecording() then return end

            if event == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
                local auctionID = ...
                local p = GMGR._pendingAH.items[auctionID]
                if p then
                    local spent = tonumber(p.total)
                            or math.max((p.preMoney or 0) - (GetMoney() or 0), 0)
                    if spent and spent > 0 then
                        local qty = tonumber(p.qty) or 1
                        local unit = math.floor(spent / math.max(1, qty))
                        GMGR.LogExpense("HdV", p.itemID or p.link, p.name or "Achat HdV", qty, unit)
                    end

                    GMGR._pendingAH.items[auctionID] = nil
                else
                    -- Fallback robuste si l’entrée Start/Confirm n’a pas été vue
                    if C_AuctionHouse and C_AuctionHouse.GetAuctionInfoByID then
                        local info = C_AuctionHouse.GetAuctionInfoByID(auctionID)
                        if info then
                            local amount = tonumber(info.buyoutAmount or info.bidAmount)
                            if amount and amount > 0 then
                                local link = info.itemLink
                                local name = (link and link:match("%[(.-)%]")) or info.itemName or "Achat HdV"
                                local iid  = (info.itemKey and info.itemKey.itemID)
                                        or (link and GetItemInfoInstant and select(1, GetItemInfoInstant(link)))
                                GMGR.LogExpense("HdV", iid or link, name, 1, amount)
                            end
                        end
                    end
                end

            elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
                local p = table.remove(GMGR._pendingAH.commodities, 1)
                if p then
                    local spent = tonumber(p.total)
                            or tonumber(GMGR._pendingAH.lastTotalPrice)
                            or ((GMGR._pendingAH.lastUnitPrice and p.qty) and (GMGR._pendingAH.lastUnitPrice * p.qty))
                            or math.max((p.preMoney or 0) - (GetMoney() or 0), 0)
                    if spent and spent > 0 then
                        GMGR.LogExpense("HdV", p.itemID or p.link, p.name or "Achat HdV", p.qty or 1, spent)
                    end
                end

            elseif event == "COMMODITY_PURCHASE_FAILED" then
                table.remove(GMGR._pendingAH.commodities, 1)

            elseif event == "COMMODITY_PRICE_UPDATED" then
                local unitPrice, totalPrice = ...
                GMGR._pendingAH.lastUnitPrice  = tonumber(unitPrice)
                GMGR._pendingAH.lastTotalPrice = tonumber(totalPrice)
            end
        end)

        GMGR._ahEventFrame = ev
    end

    -- 2) Attente du chargement de l’UI HdV pour poser les hooks de méthode
    local function InstallAHHooks()
        if not C_AuctionHouse or GMGR._ahHooksInstalled then return end

        -- Items (non-commodities)
        if C_AuctionHouse.StartItemPurchase and not GMGR._ahStartItemHook then
            hooksecurefunc(C_AuctionHouse, "StartItemPurchase", function(auctionID)
                local p = GMGR._pendingAH.items[auctionID] or { qty = 1 }
                p.preMoney = p.preMoney or (GetMoney() or 0)
                local info = C_AuctionHouse.GetAuctionInfoByID and C_AuctionHouse.GetAuctionInfoByID(auctionID)
                if info then
                    p.link   = info.itemLink
                    p.name   = info.itemName or (info.itemLink and info.itemLink:match("%[(.-)%]")) or p.name
                    p.itemID = p.itemID or (info.itemKey and info.itemKey.itemID) or (info.itemLink and GetItemInfoInstant and select(1, GetItemInfoInstant(info.itemLink)))
                end
                GMGR._pendingAH.items[auctionID] = p
            end)
            GMGR._ahStartItemHook = true
        end

        if C_AuctionHouse.ConfirmItemPurchase and not GMGR._ahConfirmItemHook then
            hooksecurefunc(C_AuctionHouse, "ConfirmItemPurchase", function(auctionID, expectedPrice)
                local p = GMGR._pendingAH.items[auctionID] or { qty = 1 }
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
                GMGR._pendingAH.items[auctionID] = p
            end)
            GMGR._ahConfirmItemHook = true
        end

        if C_AuctionHouse.PlaceBid and not GMGR._ahPlaceBidHook then
            hooksecurefunc(C_AuctionHouse, "PlaceBid", function(auctionID, bidAmount)
                local p = GMGR._pendingAH.items[auctionID] or { qty = 1 }
                p.preMoney = p.preMoney or (GetMoney() or 0)
                p.total = p.total or tonumber(bidAmount)
                GMGR._pendingAH.items[auctionID] = p
            end)
            GMGR._ahPlaceBidHook = true
        end

        -- Commodities (matériaux en vrac)
        if C_AuctionHouse.StartCommoditiesPurchase and not GMGR._ahStartCommHook then
            hooksecurefunc(C_AuctionHouse, "StartCommoditiesPurchase", function(itemID, quantity)
                local name, link = GetItemInfo(itemID)
                table.insert(GMGR._pendingAH.commodities, {
                    itemID   = itemID,
                    qty      = quantity or 1,
                    name     = name,
                    link     = link,
                    preMoney = GetMoney() or 0,
                    total    = nil, -- fixée au Confirm / price-updated
                })
            end)
            GMGR._ahStartCommHook = true
        end

        if C_AuctionHouse.ConfirmCommoditiesPurchase and not GMGR._ahConfirmCommHook then
            hooksecurefunc(C_AuctionHouse, "ConfirmCommoditiesPurchase", function(itemID, quantity)
                -- On MET À JOUR la dernière entrée (créée par Start...), on n’en crée pas une nouvelle
                local idx = #GMGR._pendingAH.commodities
                if idx > 0 then
                    local p = GMGR._pendingAH.commodities[idx]
                    p.qty   = quantity or p.qty or 1
                    -- Priorité au dernier total coté remonté par COMMODITY_PRICE_UPDATED
                    p.total = p.total or GMGR._pendingAH.lastTotalPrice
                           or ((GMGR._pendingAH.lastUnitPrice and p.qty) and (GMGR._pendingAH.lastUnitPrice * p.qty))
                    GMGR._pendingAH.commodities[idx] = p
                else
                    -- Sécurité si Start n’a pas été capté (rare) : on crée une entrée minimaliste
                    local name, link = GetItemInfo(itemID)
                    table.insert(GMGR._pendingAH.commodities, {
                        itemID   = itemID,
                        qty      = quantity or 1,
                        name     = name,
                        link     = link,
                        preMoney = GetMoney() or 0,
                        total    = GMGR._pendingAH.lastTotalPrice
                                or ((GMGR._pendingAH.lastUnitPrice and quantity) and (GMGR._pendingAH.lastUnitPrice * quantity)),
                    })
                end
            end)
            GMGR._ahConfirmCommHook = true
        end

        GMGR._ahHooksInstalled = true
    end

    -- Installe tout de suite si l’API est déjà là
    InstallAHHooks()

    -- Et sinon, installe dès que l’UI HdV se charge
    if not GMGR._ahHookWaiter then
        GMGR._ahHookWaiter = CreateFrame("Frame")
        GMGR._ahHookWaiter:RegisterEvent("ADDON_LOADED")
        GMGR._ahHookWaiter:SetScript("OnEvent", function(_, _, addonName)
            if addonName == "Blizzard_AuctionHouse" or addonName == "Blizzard_AuctionHouseUI" then
                InstallAHHooks()
            end
        end)
    end

    -- 3) HdV Legacy (PlaceAuctionBid)
    if _G.PlaceAuctionBid and not GMGR._legacyBidHook then
        hooksecurefunc("PlaceAuctionBid", function(listType, index, bid)
            if not GMGR.IsExpensesRecording() then return end
            local name, _, _, _, _, _, _, _, buyoutPrice = GetAuctionItemInfo(listType, index)
            local amount = (buyoutPrice and buyoutPrice > 0) and buyoutPrice or bid
            if amount and amount > 0 then
                local link = GetAuctionItemLink(listType, index)
                GMGR.LogExpense("HdV", link, name or "Achat HdV", 1, amount)
            end
        end)
        GMGR._legacyBidHook = true
    end

    -- 4) Boutique PNJ
    if BuyMerchantItem and not GMGR._merchantHook then
        hooksecurefunc("BuyMerchantItem", function(index, quantity)
            if not GMGR.IsExpensesRecording() then return end
            local name, _, price = GetMerchantItemInfo(index) -- copper
            local q = quantity or 1
            local extCostCount = GetMerchantItemCostInfo and GetMerchantItemCostInfo(index) or 0
            if extCostCount and extCostCount > 0 then return end -- achat non-or
            local link = GetMerchantItemLink and GetMerchantItemLink(index) or name
            local unit = math.floor((price or 0) / math.max(1, stackCount or 1))
            if unit > 0 then
                GMGR.LogExpense("Boutique", link, name, q, unit)
            end
        end)
        GMGR._merchantHook = true
    end
end
