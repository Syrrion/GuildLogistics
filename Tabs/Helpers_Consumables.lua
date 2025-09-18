-- Tabs/Helpers_Consumables.lua
-- Combined view for Bloodmallet phials (flacons) and potions.
-- Simpler than trinkets: no targets or ilvl filters; each dataset has a few upgrade steps.
local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns.GLOG, ns.UI
local Consum = ns.Data and ns.Data.Consumables

local panel, lv, footerBar, metaFS
local classDD, specDD, kindCheckFlasks, kindCheckPotions
local selectedClass, selectedSpec
local showFlacons, showPotions = true, true
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

local function datasetList()
    if not (Consum and Consum.GetDataset) then return {} end
    local items = {}
    local kinds = {
        { key = 'flacons', enabled = showFlacons, label = Tr('lbl_phials') or 'Phials' },
        { key = 'potions', enabled = showPotions, label = Tr('lbl_potions') or 'Potions' },
    }
    for _, k in ipairs(kinds) do
        if k.enabled then
            local ds = Consum.GetDataset((selectedClass or ''):upper(), selectedSpec, k.key)
            if ds and ds.data and ds.data.data then
                items[#items+1] = { kind = k.key, label = k.label, dataset = ds }
            end
        end
    end
    return items
end

local function buildRows()
    local rows = {}
    local blocks = datasetList()
    for _, block in ipairs(blocks) do
        local data = block.dataset.data
        local base = data and data.data and data.data.baseline
        local baselineScore
        if base then
            for _, v in pairs(base) do baselineScore = tonumber(v); break end
        end
        for name, values in pairs(data.data or {}) do
            if name ~= 'baseline' then
                -- pick best score (max) among steps 1..3 etc.
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
                        kind = block.kind,
                        category = block.label,
                        name = name,
                        score = best,
                        diffPct = diffPct,
                        itemID = (data.item_ids or {})[name],
                        timestamp = block.dataset.timestamp,
                    }
                end
            end
        end
    end
    table.sort(rows, function(a,b)
        if a.kind == b.kind then
            return (a.score or 0) > (b.score or 0)
        end
        return a.kind < b.kind
    end)
    local rankByKind = {}
    for _, r in ipairs(rows) do
        rankByKind[r.kind] = rankByKind[r.kind] or 0
        rankByKind[r.kind] = rankByKind[r.kind] + 1
        r.rank = rankByKind[r.kind]
    end
    return rows
end

-- Columns
local cols = UI.NormalizeColumns({
    { key = 'category', title = Tr('lbl_type') or 'Type', w = 80, justify = 'CENTER', vsep = true },
    { key = 'rank', title = '#', w = 30, justify = 'CENTER', vsep = true },
    { key = 'item', title = Tr('lbl_item') or 'Item', flex = 1, min = 220, justify = 'LEFT', vsep = true },
    { key = 'score', title = Tr('lbl_score') or 'Score', w = 120, justify = 'CENTER', vsep = true },
    { key = 'delta', title = Tr('lbl_diff') or 'Diff', w = 90, justify = 'CENTER', vsep = true },
})

local function buildRow(row)
    local f = {}
    f.category = row:CreateFontString(nil, 'OVERLAY', 'GameFontHighlightSmall')
    f.category:SetJustifyH('CENTER')
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
        if c.key == 'category' then
            f.category:ClearAllPoints(); f.category:SetPoint('LEFT', row, 'LEFT', x, 0); f.category:SetWidth(w)
            local txt = item and item.category or ''
            f.category:SetText(txt)
        elseif c.key == 'rank' then
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
    for _, token in ipairs(reg.classOrder or {}) do
        local entry = reg.classes[token]
        entries[#entries+1] = makeEntry(classLabel(entry, token), token == selectedClass, function() selectedClass = token; selectedSpec = nil; Refresh() end)
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
        entries[#entries+1] = makeEntry(specLabel(se), sk == selectedSpec, function() selectedSpec = sk; Refresh() end)
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

local function updateMeta()
    if not metaFS then return end
    local blocks = datasetList()
    local timestamps = {}
    for _, b in ipairs(blocks) do if b.dataset and b.dataset.timestamp then timestamps[#timestamps+1] = b.dataset.timestamp end end
    local ts = table.concat(timestamps, ' / ')
    metaFS:SetText(ts)
end

local function doRefresh()
    ensureSelections(resolveRegistry())
    updateDropdownTexts()
    if lv then UI.RefreshListData(lv, buildRows()) end
    updateMeta()
end
Refresh = doRefresh

local function Build(container)
    panel, footerBar = UI.CreateMainContainer(container, { footer = true })

    -- Filters area (class/spec + kind toggles)
    local filters = CreateFrame('Frame', nil, panel)
    filters:SetPoint('TOPLEFT', panel, 'TOPLEFT', 0, 0)
    filters:SetPoint('TOPRIGHT', panel, 'TOPRIGHT', 0, 0)
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

    -- Kind toggles
    local toggleFlask = UI.Button(filters, Tr('lbl_phials') or 'Phials', { small = true })
    toggleFlask:SetPoint('LEFT', specDD, 'RIGHT', 24, 0)
    toggleFlask:SetScript('OnClick', function()
        showFlacons = not showFlacons; Refresh() end)

    local togglePotion = UI.Button(filters, Tr('lbl_potions') or 'Potions', { small = true })
    togglePotion:SetPoint('LEFT', toggleFlask, 'RIGHT', 12, 0)
    togglePotion:SetScript('OnClick', function()
        showPotions = not showPotions; Refresh() end)

    -- List area
    local listArea = CreateFrame('Frame', nil, panel)
    listArea:SetPoint('TOPLEFT', filters, 'BOTTOMLEFT', 0, 0)
    listArea:SetPoint('TOPRIGHT', filters, 'BOTTOMRIGHT', 0, 0)
    listArea:SetPoint('BOTTOMLEFT', footerBar, 'TOPLEFT', 0, (UI.INNER_PAD or 0))
    listArea:SetPoint('BOTTOMRIGHT', footerBar, 'TOPRIGHT', 0, 0)
    listArea:SetFrameLevel((panel:GetFrameLevel() or 0) + 1)

    lv = UI.ListView(listArea, cols, { buildRow = buildRow, updateRow = updateRow, bottomAnchor = footerBar })

    if footerBar then
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
