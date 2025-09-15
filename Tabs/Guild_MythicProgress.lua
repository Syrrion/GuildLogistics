-- Tabs/Guild_MythicProgress.lua
local ADDON, ns = ...
local Tr = ns and ns.Tr
ns.GLOG = ns.GLOG or {}
ns.UI = ns.UI or {}
ns.Util = ns.Util or {}
local GLOG, UI, U = ns.GLOG, ns.UI, ns.Util

-- Build a list of guild mains and show per-dungeon scores from GLOG DB (p.mplusMaps)

local panel, lv

local function _collectData()
    local rows = {}
    if not (GLOG and GLOG.GetGuildMainsAggregatedCached) then return rows end

    local mains = GLOG.GetGuildMainsAggregatedCached() or {}
    -- Determine all dungeon names encountered to create dynamic columns
    local mapIndex, mapOrder = {}, {}

    local function addMap(name)
        if not name or name == "" then return end
        if not mapIndex[name] then mapIndex[name] = #mapOrder + 1; mapOrder[#mapOrder+1] = name end
    end

    -- Precompute key -> fullName map once (avoids nested scans)
    local keyToFull = {}
    if GLOG and GLOG.GetGuildRowsCached then
        for _, gr in ipairs(GLOG.GetGuildRowsCached() or {}) do
            local amb = gr.name_amb or gr.name_raw
            local rowKey = gr.name_key or (GLOG.NormName and GLOG.NormName(amb)) or nil
            if rowKey and amb then keyToFull[rowKey] = amb end
        end
    end

    for _, e in ipairs(mains) do
        local base = e.mainBase or e.main or "?"
        local fullName = (e and e.key and keyToFull[e.key]) or base
        -- Always resolve to a DB key (Name-Realm) to match storage
        if GLOG and GLOG.NormalizeDBKey then
            fullName = GLOG.NormalizeDBKey(fullName)
        elseif U and U.NormalizeFull then
            fullName = U.NormalizeFull(fullName)
        end

        if GLOG.EnsureDB then GLOG.EnsureDB() end
        local p = GuildLogisticsDB and GuildLogisticsDB.players and GuildLogisticsDB.players[fullName]
        if p and p.mplusMaps then
            for mapName, _ in pairs(p.mplusMaps) do addMap(mapName) end
        end
    end

    table.sort(mapOrder)

    -- Compose rows (collect activity data for sorting)
    for _, e in ipairs(mains) do
        local base = e.mainBase or e.main or "?"
        local fullName = (e and e.key and keyToFull[e.key]) or base
        -- Normalize for DB access
        if GLOG and GLOG.NormalizeDBKey then
            fullName = GLOG.NormalizeDBKey(fullName)
        elseif U and U.NormalizeFull then
            fullName = U.NormalizeFull(fullName)
        end
        local rec = { player = base }
        if GLOG.EnsureDB then GLOG.EnsureDB() end
        local p = GuildLogisticsDB and GuildLogisticsDB.players and GuildLogisticsDB.players[fullName]
        if p and p.mplusMaps then
            for i = 1, #mapOrder do
                local m = mapOrder[i]
                local s = p.mplusMaps[m]
                if s then
                    rec[m] = {
                        score = math.floor(tonumber(s.score or 0) + 0.5),
                        best  = tonumber(s.best or 0) or 0,
                        timed = (s.timed == true) and true or false,
                        durMS = tonumber(s.durMS or 0) or 0,
                    }
                else
                    rec[m] = nil
                end
            end
        end
    rec._overall = p and tonumber(p.mplusScore or 0) or 0
        rec._fullName = fullName
        -- Activity metrics from aggregated mains entry: e.days / e.hours (smaller => more recent)
        rec._days = tonumber(e.days or 999999) or 999999
        rec._hours = tonumber(e.hours or (rec._days*24)) or (rec._days*24)
        rows[#rows+1] = rec
    end

    -- Sort: most recent first => smaller hours first (online = 0), then name ascending
    table.sort(rows, function(a,b)
        local ha, hb = a._hours or 99999999, b._hours or 99999999
        if ha ~= hb then return ha < hb end
        local na, nb = tostring(a.player or ""), tostring(b.player or "")
        return na:lower() < nb:lower()
    end)

    -- Build per-dungeon ranking (gold/silver/bronze) based on score then key level (best), descending
    -- We only compute ranks for non-zero scores.
    local ranking = {}  -- ranking[mapName] = { {rowIndex=idx, score=.., best=..}, ... sorted }
    for mi = 1, #mapOrder do
        local m = mapOrder[mi]
        local bucket = {}
        for idx, rec in ipairs(rows) do
            local v = rec[m]
            if v and type(v)=="table" then
                local sc = tonumber(v.score or 0) or 0
                local lvl = tonumber(v.best or 0) or 0
                if sc > 0 or lvl > 0 then
                    bucket[#bucket+1] = { rowIndex = idx, score = sc, best = lvl }
                end
            end
        end
        if #bucket > 0 then
            table.sort(bucket, function(a,b)
                if a.score ~= b.score then return a.score > b.score end
                if a.best ~= b.best then return a.best > b.best end
                return a.rowIndex < b.rowIndex
            end)
            ranking[m] = bucket
        end
    end
    -- Assign rank (1..n) but we only care about 1..3; tie handling: identical (score,best) => same rank, skip next ranks accordingly.
    for mapName, bucket in pairs(ranking) do
        local lastScore, lastBest, lastRank
        local used = 0
        for i, entry in ipairs(bucket) do
            local rk
            if lastScore and entry.score == lastScore and entry.best == lastBest then
                rk = lastRank
            else
                rk = (used + 1)
            end
            if not (lastScore and entry.score == lastScore and entry.best == lastBest) then
                used = rk
            end
            lastScore, lastBest, lastRank = entry.score, entry.best, rk
            if rk <= 3 then
                local rec = rows[entry.rowIndex]
                rec._ranks = rec._ranks or {}
                rec._ranks[mapName] = rk
            else
                break -- we don't need further ranks beyond 3 for medal display
            end
        end
    end

    return rows, mapOrder
end

local function _buildColumns(mapOrder)
    -- Header font size: reduce by 1px to squeeze more columns
    if UI and UI.SetFontDeltaForFrame and lv and lv.header then
        UI.SetFontDeltaForFrame(lv.header, -1, true)
    end
    local cols = UI.NormalizeColumns({
        { key = "player",  title = Tr("col_player") or "Joueur", w = 180, justify = "LEFT" },
        { key = "overall", title = Tr("col_mplus_overall") or "Score mythique", w = 90, justify = "CENTER", vsep = true },
    })
    -- Target narrower cells and enable wrapping for 2 lines (level + score)
    for _, m in ipairs(mapOrder or {}) do
        cols[#cols+1] = { key = m, title = m, w = 100, justify = "CENTER", vsep = true, wrapLines = 2 }
    end
    return cols
end

local function buildRow(r)
    local f = {}
    -- Player cell rendered with class icon + color
    if UI and UI.CreateClassCell then
        f.player = UI.CreateClassCell(r, { width = 180, iconSize = 16 })
    else
        f.player = UI.Label(r, { justify = "LEFT" })
    end
    f.overall = UI.Label(r, { justify = "CENTER" })
    -- dynamic score labels stored per column key when updating
    return f
end

local function updateRow(i, r, f, item)
    -- Player: set icon + color
    if f.player and f.player.text and UI and UI.SetClassCell and GLOG and GLOG.GetNameClass then
        local classTag = GLOG.GetNameClass(item._fullName or item.player)
        UI.SetClassCell(f.player, { classTag = classTag })
        if f.player.SetText then f.player:SetText(item.player or "") end
    else
        f.player:SetText(item.player or "")
    end
    local resolved = UI.ResolveColumns(r:GetWidth() or (UI.SumWidths(lv.cols)), lv.cols)
    local x = 0
    for _, c in ipairs(resolved) do
        local w = c.w or c.min or 80
        if c.key == "player" then
            f.player:ClearAllPoints()
            f.player:SetPoint("LEFT", r, "LEFT", x + 8, 0)
            f.player:SetWidth(w - 16)
        elseif c.key == "overall" then
            f.overall:ClearAllPoints()
            f.overall:SetPoint("CENTER", r, "LEFT", x + w/2, 0)
            f.overall:SetWidth(w - 10)
            local ov = tonumber(item._overall or 0) or 0
            f.overall:SetText(tostring(ov))
            f.overall:SetTextColor(1, 0.82, 0)
        else
            -- create or reuse label for this map key
            local cell = f[c.key]
            if not cell or not cell._isTwoLine then
                cell = CreateFrame("Frame", nil, r)
                cell._isTwoLine = true
                cell:SetHeight(UI.ROW_H)
                cell.top = UI.Label(cell, { justify = "CENTER" })
                cell.bot = UI.Label(cell, { justify = "CENTER" })
                -- Medal texture (hidden by default)
                cell.medal = cell:CreateTexture(nil, "ARTWORK")
                cell.medal:SetSize(18, 18)
                cell.medal:SetPoint("TOPLEFT", cell, "TOPLEFT", 0, 0)
                cell.medal:Hide()
                -- Apply a persistent font delta immediately so first open shows the larger size
                if UI and UI.SetFontDeltaForFrame then UI.SetFontDeltaForFrame(cell.top, 3, false) end
                if UI and UI.ApplyFont then UI.ApplyFont(cell.top) end
                -- Hook tooltip once
                cell:EnableMouse(true)
                cell:SetScript("OnEnter", function(self)
                    local v = self._valueForTip
                    if not v then return end
                    local d = tonumber(v.durMS or 0) or 0
                    if d and d > 0 then
                        local secs = math.floor(d/1000)
                        local h = math.floor(secs/3600)
                        local m = math.floor((secs%3600)/60)
                        local s = secs % 60
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetText(string.format("%d:%02d:%02d", h, m, s))
                        GameTooltip:Show()
                    end
                end)
                cell:SetScript("OnLeave", function() GameTooltip:Hide() end)
                f[c.key] = cell
            end
            local L = cell
            L:ClearAllPoints()
            -- Slight downward offset to visually center the two lines within the row
            L:SetPoint("CENTER", r, "LEFT", x + w/2, -1)
            L:SetWidth(w - 10)
            -- layout inner labels: minimal spacing between level (top) and score (bottom)
            L.top:ClearAllPoints(); L.bot:ClearAllPoints()
            if L.top.SetJustifyV then L.top:SetJustifyV("MIDDLE") end
            if L.bot.SetJustifyV then L.bot:SetJustifyV("MIDDLE") end
            -- Slight downward shift for better vertical centering visually
            L.top:SetPoint("TOP", L, "TOP", 0, -2)
            L.bot:SetPoint("TOP", L.top, "BOTTOM", 0, -1)

            local val = item[c.key]
            -- Ensure the font delta is applied every update as well (in case of external font re-apply)
            if UI and UI.SetFontDeltaForFrame then UI.SetFontDeltaForFrame(L.top, 3, false) end
            if UI and UI.ApplyFont then UI.ApplyFont(L.top) end

            if not val then
                L.top:SetText("")
                L.bot:SetText("-")
                L.bot:SetTextColor(0.7, 0.7, 0.7)
                L._valueForTip = nil
            else
                if type(val) == "table" then
                    local lvl = tonumber(val.best or 0) or 0
                    local sc  = tonumber(val.score or 0) or 0
                    if sc <= 0 and lvl <= 0 then
                        L.top:SetText("")
                        L.bot:SetText("-")
                        L.bot:SetTextColor(0.7, 0.7, 0.7)
                        L._valueForTip = nil
                    else
                        -- Apply a persistent font delta to the level line so it survives font re-applies
                        if UI and UI.SetFontDeltaForFrame then UI.SetFontDeltaForFrame(L.top, 3, true) end
                        if lvl > 0 then
                            L.top:SetText("+" .. tostring(lvl))
                            -- Keep level in Blizzard orange/yellow
                            L.top:SetTextColor(1, 0.82, 0)
                        else
                            L.top:SetText("")
                        end
                        -- Colors: timed -> score white; not timed -> score grey
                        L.bot:SetText(string.format("%d", sc))
                        if val.timed == false then
                            L.bot:SetTextColor(0.67, 0.67, 0.67)
                        else
                            L.bot:SetTextColor(1, 1, 1)
                        end
                        L._valueForTip = val
                    end
                else
                    L.top:SetText("")
                    L.bot:SetText(tostring(val))
                    L.bot:SetTextColor(1, 1, 1)
                    L._valueForTip = nil
                end
            end
            -- Medal handling
            if L.medal then
                local rk = item._ranks and item._ranks[c.key]
                if rk == 1 then L.medal:SetAtlas("challenges-medal-gold")
                elseif rk == 2 then L.medal:SetAtlas("challenges-medal-silver")
                elseif rk == 3 then L.medal:SetAtlas("challenges-medal-bronze") end
                L.medal:SetShown(rk == 1 or rk == 2 or rk == 3)
            end
        end
        x = x + w
    end
end

local function Build(container)
    panel = UI.CreateMainContainer(container, { footer = false })
    local data, maps = _collectData()
    local cols = _buildColumns(maps)

    lv = UI.ListView(panel, cols, {
        topOffset = 0,
        buildRow  = buildRow,
        updateRow = updateRow,
        emptyText = "lbl_no_data",
        virtualWindow = true,
    })
    lv:RefreshData(data)
end

local function Refresh()
    if not lv then return end
    local data, maps = _collectData()
    lv.cols = _buildColumns(maps)
    if lv.header and lv.header.Hide then lv.header:Hide() end
    lv.header, lv.hLabels = UI.CreateHeader(lv.parent, lv.cols)
    -- Reduce header font size slightly to fit more columns
    if UI and UI.SetFontDeltaForFrame and lv.header then
        UI.SetFontDeltaForFrame(lv.header, -1, true)
    end
    lv:RefreshData(data)
end

local function Layout()
    if lv then lv:Layout() end
end

UI.RegisterTab(Tr("tab_mythic_progress") or "Progression Mythique", Build, Refresh, Layout, {
    category = Tr("cat_guild") or "Guilde",
})

-- Auto-refresh when data updates
if ns and ns.On then
    ns.On("mplus:maps-updated", function()
        if Refresh then Refresh() end
    end)
end
