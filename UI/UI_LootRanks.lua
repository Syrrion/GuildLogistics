local ADDON, ns = ...
ns.UI = ns.UI or {}
ns.Util = ns.Util or {}
ns.Data = ns.Data or {}
local UI, U, Simc = ns.UI, ns.Util, (ns.Data and ns.Data.Simc)

-- UI/UI_LootRanks.lua
-- Popup ranking an item (trinket) for each group member using SimC datasets

local Tr = ns and ns.Tr or function(s) return s end

-- Recent popup guard to prevent duplicate popups for same item within a short window
local _recentRankPopups = {}
local _RECENT_WINDOW = 600 -- seconds
local function _ShouldShowRankPopup(itemID)
    local iid = tonumber(itemID)
    if not iid then return false end
    local now = (GetTime and GetTime()) and GetTime() or (time and time()) or 0
    local last = _recentRankPopups[iid]
    if last and (now - last) < _RECENT_WINDOW then
        return false
    end
    _recentRankPopups[iid] = now
    return true
end

-- Finds the closest simulated step for a given ilvl
local function _NearestStep(steps, ilvl)
    if not (type(steps) == "table" and #steps > 0) then return nil end
    ilvl = tonumber(ilvl or 0) or 0
    local best, bestDiff
    for i = 1, #steps do
        local s = tonumber(steps[i]) or 0
        local d = math.abs(s - ilvl)
        if not best or d < bestDiff then
            best, bestDiff = s, d
        end
    end
    return best
end

-- Build a rank map for a class/spec at ilvl/targets: returns { byName = {name->{rank,score}}, byItemID = {id->{rank,score}} }
local function _BuildRanksFor(classToken, specKey, targets, ilvl)
    if not (Simc and Simc.GetDataset) then return nil end
    local ds = Simc.GetDataset(classToken, specKey, targets)
    if not (ds and ds.data and ds.data.data) then return nil end

    -- Find best step to use
    local step = _NearestStep(ds.steps or {}, ilvl)
    step = tostring(step or ilvl)

    local rows = {}
    for name, values in pairs(ds.data.data or {}) do
        local v = values and values[step]
        local num = tonumber(v)
        if num then
            rows[#rows+1] = { name = name, score = num }
        end
    end
    table.sort(rows, function(a,b) return (a.score or 0) > (b.score or 0) end)

    local byName, byItemID = {}, {}
    local ids = ds.data.item_ids or {}
    for i = 1, #rows do
        local it = rows[i]
        it.rank = i
        local rec = { rank = i, score = it.score, name = it.name }
        byName[it.name] = rec
        local iid = ids[it.name]
        if iid then byItemID[tonumber(iid) or iid] = rec end
    end
    return { byName = byName, byItemID = byItemID, dataset = ds, step = step }
end

-- For a class: find the best spec (lowest rank) for a given itemID
local function _BestSpecForItem(classToken, targets, ilvl, itemID)
    if not (Simc and Simc.GetClass) then return nil end
    local classEntry = Simc.GetClass(classToken)
    if not classEntry then return nil end
    local best
    for _, specKey in ipairs(classEntry.specOrder or {}) do
        local ranks = _BuildRanksFor(classToken, specKey, targets, ilvl)
        if ranks and ranks.byItemID[itemID] then
            local R = ranks.byItemID[itemID]
            if not best or (R.rank or 1e9) < (best.rank or 1e9) then
                best = {
                    classToken = classToken,
                    specKey = specKey,
                    specID = (classEntry.specs[specKey] and classEntry.specs[specKey].specID) or nil,
                    rank = R.rank,
                    score = R.score,
                    dataset = ranks.dataset,
                    step = ranks.step,
                }
            end
        end
    end
    return best
end

-- Resolve class token for a name (uses Player/Class.lua util if present)
local function _ClassTokenForName(name)
    if ns.Util and ns.Util.LookupClassForName then
        local tok = ns.Util.LookupClassForName(name)
        if tok and tok ~= "" then return tok:upper() end
    end
    return nil
end

-- Resolve class and spec according to opts.playersMeta[name] or best-of-class fallback
local function _ComputePlayerRank(name, itemID, ilvl, targets, meta)
    local classToken, specKey, specID
    if meta and meta[name] then
        classToken = meta[name].classToken or meta[name].class
        specKey    = meta[name].specKey
        specID     = meta[name].specID
    else
        classToken = _ClassTokenForName(name)
    end
    if not classToken then
        return { name = name, classToken = nil, specKey = nil, specID = nil, rank = nil, score = nil }
    end

    if specKey then
        local ranks = _BuildRanksFor(classToken, specKey, targets, ilvl)
        if ranks and ranks.byItemID[itemID] then
            local R = ranks.byItemID[itemID]
            return { name = name, classToken = classToken, specKey = specKey, specID = specID or ((ranks.dataset and ranks.dataset.specID) or nil), rank = R.rank, score = R.score }
        else
            -- If explicit spec has no data for this item, fall back to best-of-class
            local best = _BestSpecForItem(classToken, targets, ilvl, itemID)
            if best then
                return { name = name, classToken = classToken, specKey = best.specKey, specID = best.specID, rank = best.rank, score = best.score }
            end
            return { name = name, classToken = classToken }
        end
    end

    -- Best-of-class fallback
    local best = _BestSpecForItem(classToken, targets, ilvl, itemID)
    if best then
        return { name = name, classToken = classToken, specKey = best.specKey, specID = best.specID, rank = best.rank, score = best.score }
    end
    return { name = name, classToken = classToken }
end

-- Public: Show ranking popup; opts: { group = {...names}, playersMeta = { [name] = {classToken, specKey, specID} }, targets = 1 }
function UI.ShowTrinketRankPopupForGroup(item, ilvl, opts)
    opts = opts or {}
    local itemID
    if type(item) == "number" then itemID = item
    elseif type(item) == "string" then itemID = tonumber(item:match("|Hitem:(%d+):")) end
    if not itemID then return end

    local group = opts.group
    if not (group and #group > 0) then
        if ns.LootTrackerInstance and ns.LootTrackerInstance.SnapshotGroup then
            group = ns.LootTrackerInstance.SnapshotGroup()
        else
            group = { UnitName and UnitName("player") or (ns.Util and ns.Util.playerFullName and ns.Util.playerFullName()) or "" }
        end
    end

    local targets = tonumber(opts.targets or 1) or 1

    -- Guard: avoid duplicates for the same item in a short time window
    if not _ShouldShowRankPopup(itemID) then
        return
    end

    -- Build player rows
    local rows = {}
    for _, name in ipairs(group or {}) do
        local rec = _ComputePlayerRank(name, itemID, ilvl, targets, opts.playersMeta)
        rows[#rows+1] = rec
    end

    -- Sort by rank ascending (nil ranks at bottom, keep name as tiebreaker)
    table.sort(rows, function(a,b)
        local ra, rb = tonumber(a.rank), tonumber(b.rank)
        if ra and rb then
            if ra ~= rb then return ra < rb end
            return (tostring(a.name or "")):lower() < (tostring(b.name or "")):lower()
        elseif ra then
            return true
        elseif rb then
            return false
        else
            return (tostring(a.name or "")):lower() < (tostring(b.name or "")):lower()
        end
    end)

    -- Build popup
    -- Slightly wider to avoid truncation and fit localized texts comfortably
    local dlg = UI.CreatePopup({ title = "loot_rank_title", width = 700, height = 480 })

    -- Top item header area
    local header = CreateFrame("Frame", nil, dlg.content)
    header:SetPoint("TOPLEFT", dlg.content, "TOPLEFT", 0, 0)
    header:SetPoint("TOPRIGHT", dlg.content, "TOPRIGHT", 0, 0)
    header:SetHeight(36)

    local itemCell = UI.CreateItemCell(header, { size = 20, width = 420 })
    itemCell:SetPoint("LEFT", header, "LEFT", 8, -5) -- slight downward offset for visual spacing
    -- Ensure the item cell has a visible footprint in the header
    itemCell:SetSize(480, 24)
    UI.SetItemCell(itemCell, { itemID = itemID, itemLevel = ilvl })
    -- Pass ilvl override to tooltip hook
    if itemCell.btn then itemCell.btn._overrideILvl = tonumber(ilvl) or 0 end
    -- Color the item name as epic (purple)
    if itemCell.text and itemCell.text.SetTextColor then
        itemCell.text:SetTextColor(0.64, 0.21, 0.93)
    end

    local ilvlFS = header:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    if UI and UI.ApplyFont then UI.ApplyFont(ilvlFS) end
    ilvlFS:SetPoint("RIGHT", header, "RIGHT", -4, 0)
    ilvlFS:SetText(string.format(Tr("lbl_ilvl_value") or "ilvl %d", tonumber(ilvl) or 0))

    -- Disclaimer under header (informational)
    local disclaimerFS = dlg.content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    if UI and UI.ApplyFont then UI.ApplyFont(disclaimerFS) end
    disclaimerFS:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 8, -2)
    disclaimerFS:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", -4, -2)
    disclaimerFS:SetJustifyH("LEFT")
    if disclaimerFS.SetWordWrap then disclaimerFS:SetWordWrap(true) end
    disclaimerFS:SetText(Tr("loot_rank_disclaimer") or "These rankings are indicative and should be adapted to your current raid composition and items already obtained.")
    local disclaimerH = math.max(12, (disclaimerFS.GetStringHeight and disclaimerFS:GetStringHeight()) or 12)

    local cols = UI.NormalizeColumns({
        { key = "player",  title = Tr("col_player") or "Player",    min = 240, flex = 1, justify = "LEFT",   vsep = true },
        { key = "spec",    title = Tr("col_spec")   or "Spec",      w   = 220, justify = "LEFT",  vsep = true },
        { key = "rank",    title = Tr("col_rank")   or "Rank",      w   = 120, justify = "CENTER", vsep = true },
    })

    local lv = UI.ListView(dlg.content, cols, {
        topOffset = 36 + 8 + disclaimerH + 4,
        buildRow = function(r)
            local f = {}
            f.player = UI.CreateNameTag(r)
            f.spec   = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            if UI and UI.ApplyFont then UI.ApplyFont(f.spec) end
            -- Rank: centered number + medal atlas on its left (same style as Guild tab)
            f.rank   = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            if UI and UI.ApplyFont then UI.ApplyFont(f.rank) end
            f.medal = r:CreateTexture(nil, "ARTWORK")  -- will use challenges-medal-* atlases
            f.medal:SetSize(18,18)
            f.medal:Hide()
            return f
        end,
        updateRow = function(i, r, f, it)
            -- Colored name + class icon (override with the player's classToken when known)
            if UI.UpdateNameTagCached then
                UI.UpdateNameTagCached(f.player, it.name or "?", it.classToken)
            else
                UI.SetNameTag(f.player, it.name or "?")
            end
            -- Spec label: prefer localized spec name via specID; fallback to specKey
            local specText = ""
            if it.specID and UI.SpecNameBySpecID then
                specText = UI.SpecNameBySpecID(it.specID) or it.specKey or ""
            else
                specText = it.specKey or ""
            end
            f.spec:SetText(specText)

            if tonumber(it.rank) then
                local s = tostring(it.rank)
                if tonumber(it.rank) == 1 then s = "|cff33ff33"..s.."|r" end
                f.rank:SetText(s)
                -- Medal atlas based purely on rank, placed at the LEFT of the Rank column
                f.medal:ClearAllPoints()
                f.medal:SetPoint("LEFT", f.rank, "LEFT", 0, 0)
                local rnk = tonumber(it.rank)
                if rnk == 1 then
                    if f.medal.SetAtlas then f.medal:SetAtlas("challenges-medal-gold") end
                    f.medal:Show()
                elseif rnk == 2 then
                    if f.medal.SetAtlas then f.medal:SetAtlas("challenges-medal-silver") end
                    f.medal:Show()
                elseif rnk == 3 then
                    if f.medal.SetAtlas then f.medal:SetAtlas("challenges-medal-bronze") end
                    f.medal:Show()
                else
                    f.medal:Hide()
                end
            else
                f.rank:SetText("-")
                if f.medal then f.medal:Hide() end
            end
        end,
    })
    lv:SetData(rows)
    dlg._lv = lv

    dlg:SetButtons({ { text = Tr("btn_close"), default = true } })
    dlg:Show()
    return dlg
end

-- Debug helper: pick a dataset item and 10 random players (random classes/specs)
function UI.Debug_ShowRandomTrinketRankPopup()
    if not (Simc and Simc.GetRegistry) then return end
    local reg = Simc.GetRegistry()
    local classToken = reg.classOrder and reg.classOrder[1]
    local specKey, dataset
    if classToken then
        local classEntry = reg.classes[classToken]
        specKey = classEntry and classEntry.specOrder and classEntry.specOrder[1]
        local specEntry = specKey and classEntry and classEntry.specs[specKey]
        local targets = specEntry and specEntry.targetOrder and specEntry.targetOrder[1] or 1
        dataset = Simc.GetDataset(classToken, specKey, targets)
    end
    if not (dataset and dataset.data and dataset.data.item_ids) then return end
    local anyName, anyID
    for nm, id in pairs(dataset.data.item_ids) do anyName, anyID = nm, id; break end
    if not anyID then return end
    local steps = dataset.steps or {}
    local ilvl = steps[#steps] or steps[1] or 550

    local names, meta = {}, {}
    local pick = {}
    for _, ct in ipairs(reg.classOrder or {}) do
        local ce = reg.classes[ct]
        for _, sk in ipairs(ce.specOrder or {}) do
            pick[#pick+1] = { classToken = ct, specKey = sk, specID = ce.specs[sk] and ce.specs[sk].specID }
        end
    end
    for i = 1, 10 do
        local p = pick[((i-1) % #pick) + 1]
        local name = string.format("Test%d-Realm", i)
        names[#names+1] = name
        meta[name] = { classToken = p.classToken, specKey = p.specKey, specID = p.specID }
    end
    UI.ShowTrinketRankPopupForGroup(tonumber(anyID), ilvl, { group = names, playersMeta = meta, targets = 1 })
end
