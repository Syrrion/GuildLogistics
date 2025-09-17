-- Tabs/Helpers_Trinkets.lua
local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns.GLOG, ns.UI
local Simc = ns and ns.Data and ns.Data.Simc

local panel, lv, filtersArea, metaFS
local introArea, introFS, headerArea, headerH, listArea
local footerBar, sourceFS
local classDD, specDD, targetsDD, ilvlDD
local selectedClass, selectedSpec, selectedTargets, selectedIlvl
local Refresh

-- Item levels explicitly excluded from user selection (UI filtering only).
-- Requirement: remove 681, 688, 694, 701, 707, 714, 720 from selectable iLvls.
-- We do NOT mutate the underlying generated dataset; we filter at presentation time.
local EXCLUDED_ILVLS = {
    [681] = true, [688] = true, [694] = true, [701] = true, [707] = true, [714] = true, [720] = true,
}

-- Returns a cached filtered list of steps for a target entry, excluding unwanted ilvls.
local function getFilteredSteps(targetEntry)
    if not targetEntry then return nil end
    if targetEntry._filteredSteps then return targetEntry._filteredSteps end
    local src = targetEntry.steps
    if not (src and #src > 0) then
        targetEntry._filteredSteps = {}
        return targetEntry._filteredSteps
    end
    -- Build filtered list once; keep ordering.
    local filtered = {}
    for i = 1, #src do
        local v = src[i]
        local num = tonumber(v)
        if not (num and EXCLUDED_ILVLS[num]) then
            filtered[#filtered + 1] = v
        end
    end
    targetEntry._filteredSteps = filtered
    return filtered
end

-- ====== Helpers ======
local function resolveRegistry()
    if Simc and Simc.GetRegistry then
        return Simc.GetRegistry()
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
    -- Prefer localized specialization name via specID when available
    if UI and UI.SpecName and entry.specID then
        local classID = entry.classID or (UI.GetClassIDForToken and UI.GetClassIDForToken(selectedClass))
        local ok = pcall(UI.SpecName, classID, entry.specID)
        if ok then
            local name = UI.SpecName(classID, entry.specID)
            if name and name ~= "" then return name end
        end
    end
    return entry.label or entry.key or ""
end

local function formatTargetsLabel(count)
    local n = tonumber(count)
    if not n then return Tr("lbl_targets") or "Targets" end
    if n == 1 then
        return Tr("lbl_target_single") or "1 target"
    end
    return string.format(Tr("lbl_target_plural") or "%d targets", n)
end

local function ensureSelections(reg)
    reg = reg or resolveRegistry()

    -- Prefer current player's class/spec when available
    if UI and UI.ResolvePlayerClassSpec then
        local pClassID, pClassTag, pSpecID = UI.ResolvePlayerClassSpec()
        -- Class: if not set or invalid, use player class when present in registry
        if (not selectedClass) or (not reg.classes[selectedClass]) then
            if pClassTag and reg.classes[pClassTag] then
                selectedClass = pClassTag
            else
                selectedClass = reg.classOrder[1]
            end
        end
        -- Spec: if invalid or not set, try to use the player's spec key for the selected class
        local classEntryTmp = selectedClass and reg.classes[selectedClass] or nil
        if classEntryTmp then
            if (not selectedSpec) or (not classEntryTmp.specs[selectedSpec]) then
                -- try to find specKey whose specID matches player's specID
                local picked
                if pSpecID then
                    for sk, se in pairs(classEntryTmp.specs or {}) do
                        if se and se.specID == pSpecID then picked = sk; break end
                    end
                end
                selectedSpec = picked or classEntryTmp.specOrder[1]
            end
        end
    end

    if not (selectedClass and reg.classes[selectedClass]) then
        selectedClass = reg.classOrder[1]
    end
    local classEntry = selectedClass and reg.classes[selectedClass] or nil
    if not classEntry then
        selectedClass, selectedSpec, selectedTargets, selectedIlvl = nil, nil, nil, nil
        return
    end

    if not (selectedSpec and classEntry.specs[selectedSpec]) then
        selectedSpec = classEntry.specOrder[1]
    end
    local specEntry = selectedSpec and classEntry.specs[selectedSpec] or nil
    if not specEntry then
        selectedSpec, selectedTargets, selectedIlvl = nil, nil, nil
        return
    end

    local targetMatch
    for _, tk in ipairs(specEntry.targetOrder or {}) do
        if selectedTargets == tk or tostring(selectedTargets) == tostring(tk) then
            targetMatch = tk
            break
        end
    end
    if not targetMatch then
        targetMatch = specEntry.targetOrder[1]
    end
    selectedTargets = targetMatch

    local targetEntry = selectedTargets and specEntry.targets[selectedTargets] or nil
    local filteredSteps = getFilteredSteps(targetEntry)
    if not targetEntry or not (filteredSteps and #filteredSteps > 0) then
        selectedIlvl = nil
        return
    end

    local wanted = selectedIlvl and tostring(selectedIlvl) or nil
    local found
    for _, step in ipairs(filteredSteps) do
        if tostring(step) == wanted then
            found = step
            break
        end
    end
    selectedIlvl = found or filteredSteps[#filteredSteps]
end

local function currentDatasetMeta()
    local reg = resolveRegistry()
    local classEntry = selectedClass and reg.classes[selectedClass] or nil
    local specEntry = classEntry and classEntry.specs[selectedSpec] or nil
    if not specEntry then return nil end
    return specEntry.targets and specEntry.targets[selectedTargets] or nil
end

local function updateDropdownTexts(reg)
    reg = reg or resolveRegistry()
    local classEntry = selectedClass and reg.classes[selectedClass] or nil
    local specEntry = classEntry and selectedSpec and classEntry.specs[selectedSpec] or nil

    if classDD then
        classDD:SetSelected(selectedClass or "", classLabel(classEntry, selectedClass))
    end
    if specDD then
        specDD:SetSelected(selectedSpec or "", specLabel(specEntry))
    end
    if targetsDD then
        targetsDD:SetSelected(selectedTargets or "", formatTargetsLabel(selectedTargets))
    end
    if ilvlDD then
        local label
        if selectedIlvl then
            label = string.format(Tr("lbl_ilvl_value") or "ilvl %d", tonumber(selectedIlvl) or selectedIlvl)
        else
            label = Tr("lbl_ilvl") or "Item level"
        end
        ilvlDD:SetSelected(selectedIlvl or "", label)
    end
end

local function updateMetadataLabel(entry)
    if not metaFS then return end
    entry = entry or currentDatasetMeta()
    if not entry then
        metaFS:SetText("")
        return
    end

    local parts = {}
    if selectedTargets then parts[#parts + 1] = formatTargetsLabel(selectedTargets) end
    if selectedIlvl then
        local fmt = Tr("lbl_ilvl_value") or "ilvl %d"
        parts[#parts + 1] = string.format(fmt, tonumber(selectedIlvl) or selectedIlvl)
    end
    if entry.timestamp and entry.timestamp ~= "" then
        parts[#parts + 1] = entry.timestamp
    end
    metaFS:SetText(table.concat(parts, " • "))
end

local function buildRows(entry)
    if not entry or not entry.data then return {} end

    local dataset = entry.data
    local ilvlKey = selectedIlvl and tostring(selectedIlvl)
    if not ilvlKey or ilvlKey == "" then return {} end

    local rows, best, worst = {}, nil, nil
    for name, values in pairs(dataset.data or {}) do
        local score = values and values[ilvlKey]
        local numeric = tonumber(score)
        if numeric then
            rows[#rows + 1] = { name = name, score = numeric }
            if not best or numeric > best then
                best = numeric
            end
            if not worst or numeric < worst then
                worst = numeric
            end
        end
    end

    table.sort(rows, function(a, b)
        return (a.score or 0) > (b.score or 0)
    end)

    local sources = dataset.data_sources or {}
    local ids = dataset.item_ids or {}
    local legendary = dataset.data_legendary or {}

    for idx, item in ipairs(rows) do
        item.rank = idx
        -- Ecart vs LAST entry: last is 0.00%, first is biggest positive
        local base = worst or item.score or 0
        item.baseScore = base
        if base and base > 0 and item.score then
            item.diffPct = ((item.score / base) - 1) * 100
        else
            item.diffPct = 0
        end
        item.source = sources[item.name]
        item.itemID = ids[item.name]
        item.legendary = legendary[item.name] and true or false
    end

    return rows
end

-- ====== UI wiring ======
local cols = UI.NormalizeColumns({
    { key = "rank",    title = "#",            w = 36,  justify = "CENTER", vsep = true },
    { key = "trinket", title = Tr("lbl_trinket") or "Trinket", flex = 1, min = 220, justify = "LEFT", vsep = true },
    { key = "score",   title = Tr("lbl_score") or "Score",   w = 120, justify = "CENTER", vsep = true },
    { key = "delta",   title = Tr("lbl_diff")  or "Diff",    w = 90,  justify = "CENTER", vsep = true },
    { key = "source",  title = Tr("lbl_source") or "Source", w = 200, justify = "CENTER", vsep = true },
})

local function buildRow(row)
    local f = {}
    f.rank = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.rank:SetJustifyH("CENTER")

    -- Use standard item cell to get icon + localized name + tooltip
    f.item = UI.CreateItemCell(row, { size = 18, width = 300 })

    f.score = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.score:SetJustifyH("CENTER")

    f.delta = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.delta:SetJustifyH("CENTER")

    f.source = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.source:SetJustifyH("CENTER")
    f.source:SetWordWrap(false)

    return f
end

local function updateRow(_, row, f, item)
    if not (row and f) then return end
    local resolved = UI.ResolveColumns(row:GetWidth() or UI.MinWidthForColumns(cols), cols)
    local x = 0
    for _, c in ipairs(resolved) do
        local w = c.w or c.min or 80
        if c.key == "rank" then
            f.rank:ClearAllPoints()
            f.rank:SetPoint("LEFT", row, "LEFT", x, 0)
            f.rank:SetWidth(w)
            local txt = item and item.rank and tostring(item.rank) or ""
            if item and item.rank == 1 then
                txt = "|cff33ff33" .. txt .. "|r"
            end
            f.rank:SetText(txt)

        elseif c.key == "trinket" then
            local cell = f.item
            cell:ClearAllPoints()
            cell:SetPoint("LEFT", row, "LEFT", x + 4, 0)
            if cell.SetWidth then cell:SetWidth(w - 6) end
            -- Fill with itemID to localize name + show icon/tooltip
            local iid = (item and tonumber(item.itemID)) or nil
            UI.SetItemCell(cell, {
                itemID = iid,
                itemName = item and item.name or nil,
                itemLevel = selectedIlvl, -- propagate selected ilvl for tooltip display
            })
            -- Color all items as epic (purple)
            if cell.text and cell.text.SetTextColor then cell.text:SetTextColor(0.64, 0.21, 0.93) end

        elseif c.key == "score" then
            f.score:ClearAllPoints()
            f.score:SetPoint("RIGHT", row, "LEFT", x + w - 6, 0)
            f.score:SetWidth(w - 6)
            local val = item and item.score or nil
            local text = val and UI.FormatThousands(math.floor(val + 0.5)) or ""
            f.score:SetText(text)

        elseif c.key == "delta" then
            f.delta:ClearAllPoints()
            f.delta:SetPoint("RIGHT", row, "LEFT", x + w - 6, 0)
            f.delta:SetWidth(w - 6)
            local diff = item and item.diffPct or 0
            local text = string.format("%+.2f%%", diff)
            f.delta:SetText(text)

        elseif c.key == "source" then
            f.source:ClearAllPoints()
            f.source:SetPoint("LEFT", row, "LEFT", x + 8, 0)
            f.source:SetWidth(w - 12)
            local src = item and item.source or ""
            if item and item.legendary then
                src = (src ~= "" and (src .. " • ") or "") .. (Tr("label_legendary") or "Legendary")
            end
            f.source:SetText(src)
        end
        x = x + w
    end
end

-- ====== Dropdown builders ======
local function makeDropdownEntry(text, checked, onClick, isTitle)
    local info = UIDropDownMenu_CreateInfo()
    info.text = text
    info.isTitle = isTitle or false
    info.notCheckable = isTitle or false
    info.checked = not isTitle and checked or nil
    info.func = onClick
    return info
end

local function classMenu()
    local reg = resolveRegistry()
    local entries = {}
    for _, token in ipairs(reg.classOrder or {}) do
        local entry = reg.classes[token]
        entries[#entries + 1] = makeDropdownEntry(classLabel(entry, token), token == selectedClass, function()
            selectedClass = token
            selectedSpec, selectedTargets, selectedIlvl = nil, nil, nil
            Refresh()
        end)
    end
    if #entries == 0 then
        entries[1] = makeDropdownEntry(Tr("msg_no_data") or "No data", nil, nil, true)
    end
    return entries
end

local function specMenu()
    local reg = resolveRegistry()
    local classEntry = selectedClass and reg.classes[selectedClass] or nil
    if not classEntry then
        return { makeDropdownEntry(Tr("msg_no_data") or "No data", nil, nil, true) }
    end

    local entries = {}
    for _, specKey in ipairs(classEntry.specOrder or {}) do
        local specEntry = classEntry.specs[specKey]
        entries[#entries + 1] = makeDropdownEntry(specLabel(specEntry), specKey == selectedSpec, function()
            selectedSpec = specKey
            selectedTargets, selectedIlvl = nil, nil
            Refresh()
        end)
    end

    if #entries == 0 then
        entries[1] = makeDropdownEntry(Tr("msg_no_data") or "No data", nil, nil, true)
    end
    return entries
end

local function targetsMenu()
    local reg = resolveRegistry()
    local classEntry = selectedClass and reg.classes[selectedClass] or nil
    local specEntry = classEntry and classEntry.specs[selectedSpec] or nil
    if not specEntry then
        return { makeDropdownEntry(Tr("msg_no_data") or "No data", nil, nil, true) }
    end

    local entries = {}
    for _, count in ipairs(specEntry.targetOrder or {}) do
        entries[#entries + 1] = makeDropdownEntry(formatTargetsLabel(count), count == selectedTargets, function()
            selectedTargets = count
            selectedIlvl = nil
            Refresh()
        end)
    end

    if #entries == 0 then
        entries[1] = makeDropdownEntry(Tr("msg_no_data") or "No data", nil, nil, true)
    end
    return entries
end

local function ilvlMenu()
    local entry = currentDatasetMeta()
    local steps = getFilteredSteps(entry)
    if not entry or not (steps and #steps > 0) then
        return { makeDropdownEntry(Tr("msg_no_data") or "No data", nil, nil, true) }
    end

    local entries = {}
    for _, step in ipairs(steps) do
        entries[#entries + 1] = makeDropdownEntry(string.format("ilvl %s", step), step == selectedIlvl, function()
            selectedIlvl = step
            Refresh()
        end)
    end
    return entries
end

local function attachZFix(dd)
    if UI and UI.AttachDropdownZFix then
        UI.AttachDropdownZFix(dd, panel)
    end
end

-- ====== Refresh ======
local function doRefresh()
    local reg = resolveRegistry()
    ensureSelections(reg)
    updateDropdownTexts(reg)
    local meta = currentDatasetMeta()
    local datasetEntry, err
    if Simc and Simc.GetDataset and selectedClass and selectedSpec and selectedTargets ~= nil then
        datasetEntry, err = Simc.GetDataset(selectedClass, selectedSpec, selectedTargets)
        if not datasetEntry and err and GLOG and GLOG.Debug then
            GLOG.Debug("Simc dataset load failed", err, selectedClass, selectedSpec, selectedTargets)
        end
    end
    updateMetadataLabel(meta or datasetEntry)
    if lv then
        UI.RefreshListData(lv, buildRows(datasetEntry))
    end
end

Refresh = doRefresh

-- ====== Build ======
local function Build(container)
    panel, footerBar, _ = UI.CreateMainContainer(container, { footer = true })

    -- Intro text (adapted to SimCraft context)
    introArea = CreateFrame("Frame", nil, panel)
    introArea:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
    introArea:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 0)
    introArea:SetFrameLevel((panel:GetFrameLevel() or 0) + 1)

    introFS = introArea:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    introFS:SetPoint("TOPLEFT", introArea, "TOPLEFT", 0, 0)
    introFS:SetPoint("TOPRIGHT", introArea, "TOPRIGHT", 0, 0)
    introFS:SetJustifyH("LEFT"); introFS:SetJustifyV("TOP")
    if introFS.SetWordWrap then introFS:SetWordWrap(true) end
    if introFS.SetNonSpaceWrap then introFS:SetNonSpaceWrap(true) end
    introFS:SetText(Tr("simc_intro") or "This tab shows trinket rankings simulated by class/spec and number of targets. Use the filters below to change class, spec, targets, and item level. Source data: bloodmallet.com")
    do
        local fontPath, fontSize, fontFlags = introFS:GetFont()
        if fontPath and fontSize then introFS:SetFont(fontPath, (fontSize + 2), fontFlags) end
        introFS:SetTextColor(1,1,1)
        if introFS.SetShadowOffset then introFS:SetShadowOffset(1, -1) end
    end
    introArea:SetHeight(math.max(24, (introFS:GetStringHeight() or 16)))

    -- Subheader: Filters
    headerArea = CreateFrame("Frame", nil, panel)
    headerArea:SetPoint("TOPLEFT", introArea, "BOTTOMLEFT", 0, -10)
    headerArea:SetPoint("TOPRIGHT", introArea, "BOTTOMRIGHT", 0, -10)
    headerH = UI.SectionHeader(headerArea, Tr("lbl_bis_filters") or "Filters", { topPad = 0 }) or (UI.SECTION_HEADER_H or 26)
    headerArea:SetHeight(headerH)

    filtersArea = CreateFrame("Frame", nil, panel)
    filtersArea:SetHeight(44)
    filtersArea:SetPoint("TOPLEFT", headerArea, "BOTTOMLEFT", 0, -8)
    filtersArea:SetPoint("TOPRIGHT", headerArea, "BOTTOMRIGHT", 0, -8)
    filtersArea:SetFrameLevel((panel:GetFrameLevel() or 0) + 1)

    local lblClass = UI.Label(filtersArea, { template = "GameFontNormal" })
    lblClass:SetPoint("LEFT", filtersArea, "LEFT", 0, 0)
    lblClass:SetPoint("TOP", filtersArea, "TOP", 0, -4)
    lblClass:SetText(Tr("lbl_class") or "Classe")

    classDD = UI.Dropdown(filtersArea, { width = 160, placeholder = Tr("lbl_class") or "Classe" })
    classDD:SetPoint("LEFT", lblClass, "RIGHT", 8, -2)
    classDD:SetBuilder(classMenu)
    attachZFix(classDD)

    local lblSpec = UI.Label(filtersArea, { template = "GameFontNormal" })
    lblSpec:SetPoint("LEFT", classDD, "RIGHT", 24, 4)
    lblSpec:SetText(Tr("lbl_spec") or "Spécialisation")

    specDD = UI.Dropdown(filtersArea, { width = 120, placeholder = Tr("lbl_spec") or "Spécialisation" })
    specDD:SetPoint("LEFT", lblSpec, "RIGHT", 8, -2)
    specDD:SetBuilder(specMenu)
    attachZFix(specDD)

    local lblTargets = UI.Label(filtersArea, { template = "GameFontNormal" })
    lblTargets:SetPoint("LEFT", specDD, "RIGHT", 24, 4)
    lblTargets:SetText(Tr("lbl_targets") or "Cibles")

    targetsDD = UI.Dropdown(filtersArea, { width = 80, placeholder = Tr("lbl_targets") or "Cibles" })
    targetsDD:SetPoint("LEFT", lblTargets, "RIGHT", 8, -2)
    targetsDD:SetBuilder(targetsMenu)
    attachZFix(targetsDD)

    local lblIlvl = UI.Label(filtersArea, { template = "GameFontNormal" })
    lblIlvl:SetPoint("LEFT", targetsDD, "RIGHT", 24, 4)
    lblIlvl:SetText(Tr("lbl_ilvl") or "ilvl")

    ilvlDD = UI.Dropdown(filtersArea, { width = 80, placeholder = Tr("lbl_ilvl") or "ilvl" })
    ilvlDD:SetPoint("LEFT", lblIlvl, "RIGHT", 8, -2)
    ilvlDD:SetBuilder(ilvlMenu)
    attachZFix(ilvlDD)

    -- Footer: left = source, right = meta (targets • ilvl • date)
    if footerBar then
        sourceFS = footerBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        sourceFS:SetPoint("LEFT", footerBar, "LEFT", UI.LEFT_PAD or 12, 0)
        sourceFS:SetText(Tr("footer_source_bloodmallet") or "Source: https://bloodmallet.com/")

        metaFS = footerBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        metaFS:SetPoint("RIGHT", footerBar, "RIGHT", -(UI.RIGHT_PAD or 12), 0)
        metaFS:SetJustifyH("RIGHT")
        metaFS:SetText("")
        if metaFS.SetWordWrap then metaFS:SetWordWrap(false) end
    else
        -- Fallback (should not happen): place meta under filters
        metaFS = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        metaFS:SetPoint("TOPLEFT", filtersArea, "BOTTOMLEFT", 0, -6)
        metaFS:SetText("")
        if metaFS.SetWordWrap then metaFS:SetWordWrap(true) end
    end

    -- Dedicated list area between filters and footer for robust layout
    listArea = CreateFrame("Frame", nil, panel)
    listArea:SetPoint("TOPLEFT", filtersArea, "BOTTOMLEFT", 0, 0)
    listArea:SetPoint("TOPRIGHT", filtersArea, "BOTTOMRIGHT", 0, 0)
    listArea:SetPoint("BOTTOMLEFT", footerBar, "TOPLEFT", 0, (UI.INNER_PAD and (UI.INNER_PAD - 0) or 0))
    listArea:SetPoint("BOTTOMRIGHT", footerBar, "TOPRIGHT", 0, 0)
    listArea:SetFrameLevel((panel:GetFrameLevel() or 0) + 1)

    lv = UI.ListView(listArea, cols, {
        buildRow = buildRow,
        updateRow = updateRow,
        bottomAnchor = footerBar,
    })

    ensureSelections(resolveRegistry())
    Refresh()
end

local function Layout()
    -- Anchors handle layout; no explicit work needed.
end

UI.RegisterTab(Tr("tab_trinkets") or "Trinkets", Build, Refresh, Layout, {
    category = Tr("cat_info"),
})

