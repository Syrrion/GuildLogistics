-- Tabs/Helpers_Trinkets.lua
local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns.GLOG, ns.UI
local Simc = ns and ns.Data and ns.Data.Simc

local panel, lv, filtersArea, metaFS
local classDD, specDD, targetsDD, ilvlDD
local selectedClass, selectedSpec, selectedTargets, selectedIlvl
local Refresh

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
    if not targetEntry or not (targetEntry.steps and #targetEntry.steps > 0) then
        selectedIlvl = nil
        return
    end

    local wanted = selectedIlvl and tostring(selectedIlvl) or nil
    local found
    for _, step in ipairs(targetEntry.steps) do
        if tostring(step) == wanted then
            found = step
            break
        end
    end
    selectedIlvl = found or targetEntry.steps[#targetEntry.steps]
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

    local rows, best = {}, nil
    for name, values in pairs(dataset.data or {}) do
        local score = values and values[ilvlKey]
        local numeric = tonumber(score)
        if numeric then
            rows[#rows + 1] = { name = name, score = numeric }
            if not best or numeric > best then
                best = numeric
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
        item.bestScore = best or item.score or 0
        if item.bestScore > 0 and item.score then
            item.diffPct = ((item.score / item.bestScore) - 1) * 100
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
    { key = "rank",    title = "#",            w = 40,  justify = "CENTER" },
    { key = "trinket", title = Tr("lbl_trinket") or "Trinket", flex = 1, min = 220, justify = "LEFT" },
    { key = "score",   title = Tr("lbl_score") or "Score",   w = 120, justify = "RIGHT" },
    { key = "delta",   title = Tr("lbl_diff")  or "Diff",    w = 90,  justify = "RIGHT" },
    { key = "source",  title = Tr("lbl_source") or "Source", w = 180, justify = "LEFT" },
})

local function buildRow(row)
    local f = {}
    f.rank = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.rank:SetJustifyH("CENTER")

    f.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.name:SetJustifyH("LEFT")
    f.name:SetWordWrap(false)

    f.score = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.score:SetJustifyH("RIGHT")

    f.delta = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.delta:SetJustifyH("RIGHT")

    f.source = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.source:SetJustifyH("LEFT")
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
            f.name:ClearAllPoints()
            f.name:SetPoint("LEFT", row, "LEFT", x + 8, 0)
            f.name:SetWidth(w - 12)
            local label = item and item.name or ""
            if item and item.legendary then
                label = label .. " |cffc69b6d★|r"
            end
            if item and item.rank == 1 then
                label = "|cff33ff33" .. label .. "|r"
            end
            f.name:SetText(label)

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
    if not entry or not (entry.steps and #entry.steps > 0) then
        return { makeDropdownEntry(Tr("msg_no_data") or "No data", nil, nil, true) }
    end

    local entries = {}
    for _, step in ipairs(entry.steps) do
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
    panel, _, _ = UI.CreateMainContainer(container, { footer = false })

    filtersArea = CreateFrame("Frame", nil, panel)
    filtersArea:SetHeight(44)
    filtersArea:SetPoint("TOPLEFT", panel, "TOPLEFT", UI.LEFT_PAD, -UI.TOP_PAD)
    filtersArea:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -UI.RIGHT_PAD, -UI.TOP_PAD)
    filtersArea:SetFrameLevel((panel:GetFrameLevel() or 0) + 1)

    local lblClass = UI.Label(filtersArea, { template = "GameFontNormal" })
    lblClass:SetPoint("LEFT", filtersArea, "LEFT", 0, 0)
    lblClass:SetPoint("TOP", filtersArea, "TOP", 0, -4)
    lblClass:SetText(Tr("lbl_class") or "Classe")

    classDD = UI.Dropdown(filtersArea, { width = 180, placeholder = Tr("lbl_class") or "Classe" })
    classDD:SetPoint("LEFT", lblClass, "RIGHT", 8, -2)
    classDD:SetBuilder(classMenu)
    attachZFix(classDD)

    local lblSpec = UI.Label(filtersArea, { template = "GameFontNormal" })
    lblSpec:SetPoint("LEFT", classDD, "RIGHT", 24, 4)
    lblSpec:SetText(Tr("lbl_spec") or "Spécialisation")

    specDD = UI.Dropdown(filtersArea, { width = 200, placeholder = Tr("lbl_spec") or "Spécialisation" })
    specDD:SetPoint("LEFT", lblSpec, "RIGHT", 8, -2)
    specDD:SetBuilder(specMenu)
    attachZFix(specDD)

    local lblTargets = UI.Label(filtersArea, { template = "GameFontNormal" })
    lblTargets:SetPoint("LEFT", specDD, "RIGHT", 24, 4)
    lblTargets:SetText(Tr("lbl_targets") or "Cibles")

    targetsDD = UI.Dropdown(filtersArea, { width = 140, placeholder = Tr("lbl_targets") or "Cibles" })
    targetsDD:SetPoint("LEFT", lblTargets, "RIGHT", 8, -2)
    targetsDD:SetBuilder(targetsMenu)
    attachZFix(targetsDD)

    local lblIlvl = UI.Label(filtersArea, { template = "GameFontNormal" })
    lblIlvl:SetPoint("LEFT", targetsDD, "RIGHT", 24, 4)
    lblIlvl:SetText(Tr("lbl_ilvl") or "ilvl")

    ilvlDD = UI.Dropdown(filtersArea, { width = 140, placeholder = Tr("lbl_ilvl") or "ilvl" })
    ilvlDD:SetPoint("LEFT", lblIlvl, "RIGHT", 8, -2)
    ilvlDD:SetBuilder(ilvlMenu)
    attachZFix(ilvlDD)

    metaFS = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    metaFS:SetPoint("TOPLEFT", filtersArea, "BOTTOMLEFT", 0, -6)
    metaFS:SetText("")

    lv = UI.ListView(panel, cols, {
        topOffset = (filtersArea:GetHeight() or 44) + 24,
        buildRow = buildRow,
        updateRow = updateRow,
    })

    ensureSelections(resolveRegistry())
    Refresh()
end

local function Layout()
    if lv then
        lv.opts.topOffset = (filtersArea and filtersArea:GetHeight() or 44) + 24
        lv:Layout()
    end
end

UI.RegisterTab(Tr("tab_trinkets") or "Trinkets", Build, Refresh, Layout, {
    category = Tr("cat_info"),
})

