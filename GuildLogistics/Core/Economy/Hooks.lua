-- ===================================================
-- Core/Economy/Hooks.lua - Hooks d'achat (AH, boutiques)
-- ===================================================
-- Surveillance automatique des achats pour l'enregistrement des dépenses

local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
local GLOG = ns.GLOG

-- ====== Hooks (Boutique / HdV) ======
function GLOG.Expenses_InstallHooks()
    if GLOG._expHooksInstalled then return end
    GLOG._expHooksInstalled = true
    local EnsureDB = GLOG.EnsureDB
    EnsureDB()

    -- file d'attente HdV + dernier prix coté (commodities)
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
                        GLOG.LogExpense(GLOG.EXPENSE_SOURCE.AH, p.itemID or p.link, p.name, qty, unit)
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
                                local name = (link and link:match("%[(.-)%]")) or info.itemName or "Achat HdV"
                                local iid  = (info.itemKey and info.itemKey.itemID)
                                        or (link and GetItemInfoInstant and select(1, GetItemInfoInstant(link)))
                                GLOG.LogExpense(GLOG.EXPENSE_SOURCE.AH, iid or link, name, 1, amount)
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

    -- 2) Attente du chargement de l'UI HdV pour poser les hooks de méthode
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
                -- On MET À JOUR la dernière entrée (créée par Start...), on n'en crée pas une nouvelle
                local idx = #GLOG._pendingAH.commodities
                if idx > 0 then
                    local p = GLOG._pendingAH.commodities[idx]
                    p.qty   = quantity or p.qty or 1
                    -- Priorité au dernier total coté remonté par COMMODITY_PRICE_UPDATED
                    p.total = p.total or GLOG._pendingAH.lastTotalPrice
                           or ((GLOG._pendingAH.lastUnitPrice and p.qty) and (GLOG._pendingAH.lastUnitPrice * p.qty))
                    GLOG._pendingAH.commodities[idx] = p
                else
                    -- Sécurité si Start n'a pas été capté (rare) : on crée une entrée minimaliste
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

    -- Installe tout de suite si l'API est déjà là
    InstallAHHooks()

    -- Et sinon, installe dès que l'UI HdV se charge (centralisé)
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
                GLOG.LogExpense(GLOG.EXPENSE_SOURCE.AH, link, name, 1, amount)
            end
        end)
        GLOG._legacyBidHook = true
    end

    -- 4) Boutique PNJ
    if BuyMerchantItem and not GLOG._merchantHook then
        hooksecurefunc("BuyMerchantItem", function(index, quantity)
            if not GLOG.IsExpensesRecording() then return end
            local name, _, price, stackCount = GetMerchantItemInfo(index) -- copper
            local q = quantity or 1
            local extCostCount = GetMerchantItemCostInfo and GetMerchantItemCostInfo(index) or 0
            if extCostCount and extCostCount > 0 then return end -- achat non-or
            local link = GetMerchantItemLink and GetMerchantItemLink(index) or name
            
            
            local totalItems = (stackCount or 1)
            local totalCost  = (price or 0)
            
            if totalCost > 0 then
                -- LogExpense attend (qty, prix_total) donc (10, 200)
                GLOG.LogExpense(GLOG.EXPENSE_SOURCE.SHOP, link, name, totalItems, totalCost)
            end
        end)
        GLOG._merchantHook = true
    end
end
