-- Tabs/Helpers_Consumables.lua
-- Side-by-side view for Bloodmallet phials (flacons) and potions (two distinct lists).
-- No target/ilvl filters; each dataset has a few upgrade steps. Buttons removed (both shown by default).
local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns.GLOG, ns.UI
local Consum = ns.Data and ns.Data.Consumables

local panel, footerBar, metaFS, sourceFS
local emptyLeftFS, emptyRightFS
local introArea, introFS
local lvFlacons, lvPotions
local classDD, specDD
local selectedClass, selectedSpec
local Refresh

local function resolveRegistry()
    if Consum and Consum.GetRegistry then
        return Consum.GetRegistry()
    end
    return { classes = {}, classOrder = {} }
end

local function classLabel(entry, token)
    if not token then return "" end
    local label
    if entry and UI and UI.ClassName then
        label = UI.ClassName(entry.classID, token)
    end
    if not label or label == "" then
        label = entry and entry.label or token
    end
    return label
end

local function specLabel(entry)
    if not entry then return "" end
    if UI and UI.SpecName and entry.specID then
        local classID = entry.classID
        local ok = pcall(UI.SpecName, classID, entry.specID)
        if ok then
            local name = UI.SpecName(classID, entry.specID)
            if name and name ~= "" then return name end
        end
    end
    return entry.label or entry.key or ""
end

local function ensureSelections(reg)
    reg = reg or resolveRegistry()
    if UI and UI.ResolvePlayerClassSpec then
        local pClassID, pClassTag, pSpecID = UI.ResolvePlayerClassSpec()
        if (not selectedClass) or (not reg.classes[selectedClass]) then
            if pClassTag and reg.classes[pClassTag] then
                selectedClass = pClassTag
            else
                selectedClass = reg.classOrder[1]
            end
        end
        local classEntry = selectedClass and reg.classes[selectedClass]
        if classEntry then
            if (not selectedSpec) or (not classEntry.specs[selectedSpec]) then
                local picked
                if pSpecID then
                    for sk, se in pairs(classEntry.specs or {}) do
                        if se.specID == pSpecID then picked = sk; break end
                    end
                end
                selectedSpec = picked or classEntry.specOrder[1]
            end
        end
    end
    if not selectedClass or not reg.classes[selectedClass] then
        selectedClass = reg.classOrder[1]
    end
    local ce = selectedClass and reg.classes[selectedClass]
    if not ce then selectedSpec = nil return end
    if not selectedSpec or not ce.specs[selectedSpec] then
        selectedSpec = ce.specOrder[1]
    end
end

local function buildRowsFor(kindKey)
    local cls = (selectedClass or ''):upper()
    local ds
    if cls:find('_') then
        ds = Consum.GetDataset(cls, selectedSpec, kindKey) or Consum.GetDataset(cls:gsub('_',''), selectedSpec, kindKey)
    else
        ds = Consum.GetDataset(cls, selectedSpec, kindKey)
    end
    if not ds then
        if GLOG and GLOG.Debug then GLOG.Debug("Consumables: dataset missing", cls, selectedSpec, kindKey) end
        return {}, nil
    end
    if not ds.data then
        -- Force decode (GetDataset should already do it, but be defensive)
        Consum.GetDataset(cls, selectedSpec, kindKey)
    end
    if not (ds.data) then
        if GLOG and GLOG.Debug then GLOG.Debug("Consumables: no data after decode", cls, selectedSpec, kindKey) end
        return {}, ds.timestamp
    end
    local data = ds.data
    -- Fallback: some generators may nest differently; accept both ds.data.data and ds.data (if it directly contains item entries)
    local payload = data.data and data.data or data
    if not payload or type(payload) ~= 'table' then
        if GLOG and GLOG.Debug then GLOG.Debug("Consumables: payload missing/invalid", cls, selectedSpec, kindKey) end
        return {}, ds.timestamp
    end
    -- If payload represents an error blob (Bloodmallet returned an error) show nothing gracefully
    if payload.status == 'error' then
        if GLOG and GLOG.Debug then GLOG.Debug("Consumables: remote dataset status=error", cls, selectedSpec, kindKey, payload.message) end
        return {}, ds.timestamp
    end
    local base = payload.baseline
    local baselineScore
    if base then for _, v in pairs(base) do baselineScore = tonumber(v); break end end
    local rows = {}
    for name, values in pairs(payload) do
        if name ~= 'baseline' then
            if type(values) == 'table' then
                local best
                for _, v in pairs(values) do
                    local num = tonumber(v)
                    if num and (not best or num > best) then best = num end
                end
                if best then
                    local diffPct = 0
                    if baselineScore and baselineScore > 0 then
                        diffPct = ((best / baselineScore) - 1) * 100
                    end
                    rows[#rows+1] = {
                        name = name,
                        score = best,
                        diffPct = diffPct,
                        itemID = (data.item_ids or {})[name],
                    }
                end
            else
                -- Skip non-table entries (e.g., status/message) safely
            end
        end
    end
    table.sort(rows, function(a,b) return (a.score or 0) > (b.score or 0) end)
    for i, r in ipairs(rows) do r.rank = i end
    return rows, ds.timestamp
end

-- Columns
local cols = UI.NormalizeColumns({
    { key = 'rank', title = '#', w = 30, justify = 'CENTER', vsep = true },
    { key = 'item', title = Tr('lbl_item') or 'Item', flex = 1, min = 180, justify = 'LEFT', vsep = true },
    { key = 'score', title = Tr('lbl_score') or 'Score', w = 110, justify = 'CENTER', vsep = true },
    { key = 'delta', title = Tr('lbl_diff') or 'Diff', w = 85, justify = 'CENTER', vsep = true },
})

local function buildRow(row)
    local f = {}
    -- category column removed in dual-list layout
    f.rank = row:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    f.rank:SetJustifyH('CENTER')
    f.item = UI.CreateItemCell(row, { size = 18, width = 300 })
    f.score = row:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    f.score:SetJustifyH('CENTER')
    f.delta = row:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    f.delta:SetJustifyH('CENTER')
    return f
end

local function updateRow(_, row, f, item)
    if not (row and f) then return end
    local resolved = UI.ResolveColumns(row:GetWidth() or UI.MinWidthForColumns(cols), cols)
    local x = 0
    for _, c in ipairs(resolved) do
        local w = c.w or c.min or 80
        if c.key == 'rank' then
            f.rank:ClearAllPoints(); f.rank:SetPoint('LEFT', row, 'LEFT', x, 0); f.rank:SetWidth(w)
            local txt = item and item.rank and tostring(item.rank) or ''
            if item and item.rank == 1 then txt = '|cff33ff33'..txt..'|r' end
            f.rank:SetText(txt)
        elseif c.key == 'item' then
            local cell = f.item
            cell:ClearAllPoints(); cell:SetPoint('LEFT', row, 'LEFT', x+4, 0)
            if cell.SetWidth then cell:SetWidth(w-6) end
            local iid = item and tonumber(item.itemID) or nil
            UI.SetItemCell(cell, { itemID = iid, itemName = item and item.name })
            if cell.text and cell.text.SetTextColor then cell.text:SetTextColor(0.64,0.21,0.93) end
        elseif c.key == 'score' then
            f.score:ClearAllPoints(); f.score:SetPoint('RIGHT', row, 'LEFT', x + w - 6, 0); f.score:SetWidth(w-6)
            local val = item and item.score or nil
            f.score:SetText(val and UI.FormatThousands(math.floor(val+0.5)) or '')
        elseif c.key == 'delta' then
            f.delta:ClearAllPoints(); f.delta:SetPoint('RIGHT', row, 'LEFT', x + w - 6, 0); f.delta:SetWidth(w-6)
            local diff = item and item.diffPct or 0
            f.delta:SetText(string.format('%+.2f%%', diff))
        end
        x = x + w
    end
end

-- Dropdown menus
local function makeEntry(text, checked, onClick, isTitle)
    local info = UIDropDownMenu_CreateInfo()
    info.text = text; info.isTitle = isTitle or false; info.notCheckable = isTitle or false; info.checked = not isTitle and checked or nil; info.func = onClick
    return info
end

local function classMenu()
    local reg = resolveRegistry(); local entries = {}
    -- classOrder should already be unique, but add a defensive de-duplication layer in case
    local seen = {}
    for _, token in ipairs(reg.classOrder or {}) do
        if token and not seen[token] then
            seen[token] = true
            local entry = reg.classes[token]
            entries[#entries+1] = makeEntry(classLabel(entry, token), token == selectedClass, function()
                selectedClass = token; selectedSpec = nil; Refresh()
            end)
        end
    end
    if #entries == 0 then entries[1] = makeEntry(Tr('msg_no_data') or 'No data', nil, nil, true) end
    return entries
end

local function specMenu()
    local reg = resolveRegistry(); local ce = selectedClass and reg.classes[selectedClass]
    if not ce then return { makeEntry(Tr('msg_no_data') or 'No data', nil, nil, true) } end
    local entries = {}
    for _, sk in ipairs(ce.specOrder or {}) do
        local se = ce.specs[sk]
        entries[#entries+1] = makeEntry(specLabel(se), sk == selectedSpec, function()
            selectedSpec = sk; Refresh()
        end)
    end
    if #entries == 0 then entries[1] = makeEntry(Tr('msg_no_data') or 'No data', nil, nil, true) end
    return entries
end

local function attachZFix(dd) if UI and UI.AttachDropdownZFix then UI.AttachDropdownZFix(dd, panel) end end

local function updateDropdownTexts()
    local reg = resolveRegistry(); local ce = selectedClass and reg.classes[selectedClass]; local se = ce and ce.specs[selectedSpec]
    if classDD then classDD:SetSelected(selectedClass or '', classLabel(ce, selectedClass)) end
    if specDD then specDD:SetSelected(selectedSpec or '', specLabel(se)) end
end

local function updateMeta(tsFlacon, tsPotion)
    if not metaFS then return end
    local parts = {}
    if tsFlacon then parts[#parts+1] = (Tr('lbl_phials') or 'Phials')..': '..tsFlacon end
    if tsPotion then parts[#parts+1] = (Tr('lbl_potions') or 'Potions')..': '..tsPotion end
    metaFS:SetText(table.concat(parts, '  |  '))
end

local function doRefresh()
    ensureSelections(resolveRegistry())
    updateDropdownTexts()
    local rowsFlacon, tsF = buildRowsFor('flacons')
    local rowsPotion, tsP = buildRowsFor('potions')
    -- Invalidate signatures so both lists recompute even if the item ordering is identical between specs.
    -- (Potions often share identical item sets across specs; without this, the right list would keep old diff/score values.)
    if lvFlacons then lvFlacons._lastDataSig = nil end
    if lvPotions then lvPotions._lastDataSig = nil end
    if lvFlacons then UI.RefreshListData(lvFlacons, rowsFlacon) end
    if lvPotions then UI.RefreshListData(lvPotions, rowsPotion) end
    -- Empty state messages (visible only when corresponding list has no rows)
    if emptyLeftFS then
        if rowsFlacon and #rowsFlacon == 0 then
            emptyLeftFS:Show()
        else
            emptyLeftFS:Hide()
        end
    end
    if emptyRightFS then
        if rowsPotion and #rowsPotion == 0 then
            emptyRightFS:Show()
        else
            emptyRightFS:Hide()
        end
    end
    updateMeta(tsF, tsP)
end
Refresh = doRefresh

local function Build(container)
    panel, footerBar = UI.CreateMainContainer(container, { footer = true })
    -- Force a registry refresh on first build to pick up any datasets registered late in load order.
    if Consum and Consum.GetRegistry then
        Consum.GetRegistry({ refresh = true })
    end

    -- Intro area (mirrors trinkets style but shorter)
    introArea = CreateFrame('Frame', nil, panel)
    introArea:SetPoint('TOPLEFT', panel, 'TOPLEFT', 0, 0)
    introArea:SetPoint('TOPRIGHT', panel, 'TOPRIGHT', 0, 0)
    introArea:SetHeight(46)
    introFS = introArea:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    introFS:SetPoint('TOPLEFT', introArea, 'TOPLEFT', 0, 0)
    introFS:SetPoint('TOPRIGHT', introArea, 'TOPRIGHT', 0, 0)
    introFS:SetJustifyH('LEFT'); introFS:SetJustifyV('TOP')
    if introFS.SetWordWrap then introFS:SetWordWrap(true) end
    if introFS.SetNonSpaceWrap then introFS:SetNonSpaceWrap(true) end
    introFS:SetText(Tr('consum_intro') or 'This tab lists offensive phials (left) and potions (right) by class/spec.')

    -- Filters area (class/spec)
    local filters = CreateFrame('Frame', nil, panel)
    filters:SetPoint('TOPLEFT', introArea, 'BOTTOMLEFT', 0, -4)
    filters:SetPoint('TOPRIGHT', introArea, 'BOTTOMRIGHT', 0, -4)
    filters:SetHeight(44)

    local lblClass = UI.Label(filters, { template = 'GameFontNormal' })
    lblClass:SetPoint('LEFT', filters, 'LEFT', 0, 0)
    lblClass:SetPoint('TOP', filters, 'TOP', 0, -4)
    lblClass:SetText(Tr('lbl_class') or 'Classe')

    classDD = UI.Dropdown(filters, { width = 160, placeholder = Tr('lbl_class') or 'Classe' })
    classDD:SetPoint('LEFT', lblClass, 'RIGHT', 8, -2)
    classDD:SetBuilder(classMenu)
    attachZFix(classDD)

    local lblSpec = UI.Label(filters, { template = 'GameFontNormal' })
    lblSpec:SetPoint('LEFT', classDD, 'RIGHT', 24, 4)
    lblSpec:SetText(Tr('lbl_spec') or 'Spécialisation')

    specDD = UI.Dropdown(filters, { width = 120, placeholder = Tr('lbl_spec') or 'Spécialisation' })
    specDD:SetPoint('LEFT', lblSpec, 'RIGHT', 8, -2)
    specDD:SetBuilder(specMenu)
    attachZFix(specDD)

    -- Columns headers labels (above each list)
    local listsFrame = CreateFrame('Frame', nil, panel)
    listsFrame:SetPoint('TOPLEFT', filters, 'BOTTOMLEFT', 0, 0)
    listsFrame:SetPoint('TOPRIGHT', filters, 'BOTTOMRIGHT', 0, 0)
    listsFrame:SetPoint('BOTTOMLEFT', footerBar, 'TOPLEFT', 0, (UI.INNER_PAD or 0))
    listsFrame:SetPoint('BOTTOMRIGHT', footerBar, 'TOPRIGHT', 0, 0)
    listsFrame:SetFrameLevel((panel:GetFrameLevel() or 0) + 1)

    local midPad = 12
    local fWidth = function()
        local w = listsFrame:GetWidth() or 800
        return (w - midPad) * 0.5
    end

    local leftHeader = UI.Label(listsFrame, { template = 'GameFontNormal' })
    leftHeader:SetPoint('TOPLEFT', listsFrame, 'TOPLEFT', 0, -2)
    leftHeader:SetText(Tr('lbl_phials') or 'Phials')

    local rightHeader = UI.Label(listsFrame, { template = 'GameFontNormal' })
    rightHeader:SetPoint('TOPLEFT', listsFrame, 'TOPLEFT', (listsFrame:GetWidth() or 0)/2 + midPad/2, -2)
    rightHeader:SetText(Tr('lbl_potions') or 'Potions')

    local leftList = CreateFrame('Frame', nil, listsFrame)
    leftList:SetPoint('TOPLEFT', leftHeader, 'BOTTOMLEFT', 0, -4)
    leftList:SetPoint('BOTTOMLEFT', footerBar, 'TOPLEFT', 0, (UI.INNER_PAD or 0))
    leftList:SetWidth(fWidth())

    local rightList = CreateFrame('Frame', nil, listsFrame)
    rightList:SetPoint('TOPRIGHT', listsFrame, 'TOPRIGHT', 0, -18)
    rightList:SetPoint('BOTTOMRIGHT', footerBar, 'TOPRIGHT', 0, (UI.INNER_PAD or 0))
    rightList:SetWidth(fWidth())

    lvFlacons = UI.ListView(leftList, cols, { buildRow = buildRow, updateRow = updateRow, bottomAnchor = footerBar })
    lvPotions = UI.ListView(rightList, cols, { buildRow = buildRow, updateRow = updateRow, bottomAnchor = footerBar })

    -- Empty state fontstrings
    emptyLeftFS = leftList:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
    emptyLeftFS:SetPoint('TOPLEFT', leftList, 'TOPLEFT', 4, -4)
    emptyLeftFS:SetPoint('RIGHT', leftList, 'RIGHT', -4, 0)
    emptyLeftFS:SetJustifyH('LEFT'); emptyLeftFS:SetJustifyV('TOP')
    emptyLeftFS:SetText((Tr('msg_no_data') or 'No data')..' – '..(Tr('lbl_phials') or 'Phials'))
    emptyLeftFS:Hide()
    emptyRightFS = rightList:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
    emptyRightFS:SetPoint('TOPLEFT', rightList, 'TOPLEFT', 4, -4)
    emptyRightFS:SetPoint('RIGHT', rightList, 'RIGHT', -4, 0)
    emptyRightFS:SetJustifyH('LEFT'); emptyRightFS:SetJustifyV('TOP')
    emptyRightFS:SetText((Tr('msg_no_data') or 'No data')..' – '..(Tr('lbl_potions') or 'Potions'))
    emptyRightFS:Hide()

    -- Responsive resize hook
    listsFrame:SetScript('OnSizeChanged', function()
        local half = fWidth()
        leftList:SetWidth(half)
        rightList:SetWidth(half)
        rightHeader:ClearAllPoints()
        rightHeader:SetPoint('TOPLEFT', listsFrame, 'TOPLEFT', half + midPad, -2)
    end)

    if footerBar then
        -- Left: Source attribution (bloodmallet) like Trinkets tab
        sourceFS = footerBar:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
        sourceFS:SetPoint('LEFT', footerBar, 'LEFT', UI.LEFT_PAD or 12, 0)
        sourceFS:SetJustifyH('LEFT')
        sourceFS:SetText(Tr('footer_source_bloodmallet') or 'Source: https://bloodmallet.com/')

        -- Right: timestamps for both datasets
        metaFS = footerBar:CreateFontString(nil, 'OVERLAY', 'GameFontDisableSmall')
        metaFS:SetPoint('RIGHT', footerBar, 'RIGHT', -(UI.RIGHT_PAD or 12), 0)
        metaFS:SetJustifyH('RIGHT')
        metaFS:SetText('')
    end

    ensureSelections(resolveRegistry())
    Refresh()
end

local function Layout() end

UI.RegisterTab(Tr('tab_consumables') or 'Consumables', Build, Refresh, Layout, { category = Tr('cat_info') })
