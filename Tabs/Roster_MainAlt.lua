local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns.GLOG, ns.UI

local panel, footer, footerH
local leftPane, midPane, rightPane
local lvPool, lvMains, lvAlts
local selectedMainName -- full name
local selectedMainRow -- row frame for immediate selection highlight
local Layout -- forward decl for local function used in callbacks
local buildPoolData, buildMainsData, buildAltsData -- forward decl for data builders
local poolDataCache -- incremental cache for left list
-- Helper to check guild master permissions
local function _IsGM()
    -- Use project-level master flag (can be customized in Core.Guild)
    return (GLOG and GLOG.IsMaster and GLOG.IsMaster()) or false
end
local function _schedulePoolRebuild()
    local fn = function()
        poolDataCache = buildPoolData()
        if lvPool and lvPool.SetData then lvPool:SetData(poolDataCache) end
    end
    if ns and ns.Util and ns.Util.Debounce then
        ns.Util.Debounce("Roster_MainAlt.poolRebuild", 0.05, fn)
    else
        if UI and UI.NextFrame then UI.NextFrame(fn) else fn() end
    end
end

-- Use requested atlases for icons
local ICON_MAIN_ATLAS = "GO-icon-Header-Assist-Applied"
local ICON_ALT_ATLAS  = "GO-icon-Assist-Available"

-- Helper: get the character's own class tag from guild cache (ignores main's class)
local function _SelfClassTag(name)
    return (GLOG and GLOG.GetGuildClassTag and GLOG.GetGuildClassTag(name)) or nil
end

local function _refreshAll()
    if lvPool and lvPool.Refresh then lvPool:RefreshData(nil) end
    if lvMains and lvMains.Refresh then lvMains:RefreshData(nil) end
    if lvAlts and lvAlts.Refresh then lvAlts:RefreshData(nil) end
end

-- Incremental removal from pool cache by name
local function _removeFromPoolByName(name)
    if not (poolDataCache and name and name ~= "") then return false end
    local nk = (GLOG and GLOG.NormName and GLOG.NormName(name)) or string.lower(name)
    for idx = #poolDataCache, 1, -1 do
        local it = poolDataCache[idx]
        local nk2 = (GLOG and GLOG.NormName and GLOG.NormName(it.name)) or string.lower(it.name or "")
        if nk == nk2 then
            table.remove(poolDataCache, idx)
            return true
        end
    end
    return false
end

-- ===== Pool (50%) =====
local poolCols = {
    { key = "name",  title = Tr("lbl_player") or "Joueur", flex = 1, min = 150 },
    { key = "note",  title = Tr("lbl_guild_note") or "Guild note",   flex = 1, min = 120, justify = "LEFT" },
    { key = "act",   title = Tr("lbl_actions") or "Actions", min = 120 },
}

local function BuildRowPool(r)
    local f = {}
    f.name = UI.CreateNameTag(r)
    -- Note column (guild note / remark)
    f.note = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.note:SetJustifyH("LEFT")

    -- Actions container
    f.act  = CreateFrame("Frame", nil, r); f.act:SetHeight(UI.ROW_H)
    if _IsGM() then
        -- Crown = set as Main (classic button with larger embedded atlas)
        local crown = (CreateAtlasMarkup and CreateAtlasMarkup(ICON_MAIN_ATLAS, 18, 18)) or ("|A:"..ICON_MAIN_ATLAS..":18:18|a")
        r.btnCrown = UI.Button(f.act, crown, { size="xs", variant="ghost", minWidth=30, padX=6, tooltip = Tr("tip_set_main") or "Confirmer en main" })
        -- Plus = assign as Alt to selected Main (localized tooltip)
        r.btnAlt   = UI.Button(f.act, "+", { size="xs", variant="ghost", minWidth=22, tooltip=Tr("tip_assign_alt") or "Associer en alt au main sélectionné" })
    end
    UI.AttachRowRight(f.act, { r.btnCrown, r.btnAlt }, 6, -4, { leftPad=4, align="center" })
    return f
end

local function UpdateRowPool(i, r, f, it)
    local data = it.data or it
    do
        local cls = data.classTag or _SelfClassTag(data.name)
        if UI and UI.SetNameTagShortEx then
            UI.SetNameTagShortEx(f.name, data.name or "", cls)
        else
            UI.SetNameTagShort(f.name, data.name or "")
        end
        -- Append suggestion tag to player name (green), not in note column
        if data.suggested and f.name and f.name.text then
            local raw = (GLOG and GLOG.ResolveFullName and GLOG.ResolveFullName(data.name)) or tostring(data.name or "")
            local display = (ns and ns.Util and ns.Util.ShortenFullName and ns.Util.ShortenFullName(raw)) or raw
            f.name.text:SetText(string.format("%s |cff00ff00(%s)|r", display, Tr("lbl_suggested") or "Suggéré"))
        end
    end

    local note = data.note or ""
    local prefix = ""
    if note ~= "" then
        local nkNote = (GLOG and GLOG.NormName and GLOG.NormName(note)) or string.lower(note)
        local nkName = (GLOG and GLOG.NormName and GLOG.NormName(data.name)) or string.lower(data.name or "")
        if nkNote == nkName then
            if CreateAtlasMarkup then
                prefix = (CreateAtlasMarkup(ICON_MAIN_ATLAS, 14, 14) or "") .. " "
            else
                prefix = "|A:"..ICON_MAIN_ATLAS..":14:14|a "
            end
        else
            if CreateAtlasMarkup then
                prefix = (CreateAtlasMarkup(ICON_ALT_ATLAS, 14, 14) or "") .. " "
            else
                prefix = "|A:"..ICON_ALT_ATLAS..":14:14|a "
            end
        end
    end
    -- Only show icon prefix in note; suggestion marker is now on player name
    note = prefix .. note
    if f.note and f.note.SetText then f.note:SetText(note) end

    -- Buttons
    local gm = _IsGM()
        if r.btnCrown then r.btnCrown:SetShown(gm) end
        if r.btnAlt then r.btnAlt:SetShown(gm) end
    if r.btnCrown then
        r.btnCrown:SetOnClick(function()
            GLOG.SetAsMain(data.name)
            if _removeFromPoolByName(data.name) then
                if lvPool and lvPool.SetData then lvPool:SetData(poolDataCache); lvPool:Layout() end
            end
            -- update mains list; alts unaffected
            if lvMains and lvMains.SetData then lvMains:SetData(buildMainsData()); lvMains:Layout() end
        end)
    end

    if r.btnAlt then
        -- Disable if no main selected
        local can = (selectedMainName and selectedMainName ~= "") and true or false
        r.btnAlt:SetEnabled(can)
        if UI and UI.SetButtonAlpha then UI.SetButtonAlpha(r.btnAlt, can and 1 or 0.4) end
        r.btnAlt:SetOnClick(function()
            local mainName = selectedMainName
            if not mainName or mainName == "" then return end
            -- Resolve full name for safety
            local fullMain = (GLOG and GLOG.ResolveFullName and GLOG.ResolveFullName(mainName)) or mainName
            local altFull = (GLOG and GLOG.ResolveFullName and GLOG.ResolveFullName(data.name)) or data.name
            local altBal = (GLOG and GLOG.GetSolde and tonumber(GLOG.GetSolde(altFull))) or 0

            local function doAssignWithOptionalMerge()
                -- Merge balance first if needed
                if altBal ~= 0 and GLOG and GLOG.AdjustSolde then
                    GLOG.AdjustSolde(fullMain, altBal)
                    GLOG.AdjustSolde(altFull, -altBal)
                end
                GLOG.AssignAltToMain(altFull, fullMain)
                if _removeFromPoolByName(altFull) then
                    if lvPool and lvPool.SetData then lvPool:SetData(poolDataCache); lvPool:Layout() end
                end
                -- update current main's alts incrementally
                if lvAlts and lvAlts.SetData then lvAlts:SetData(buildAltsData()); lvAlts:Layout() end
            end

            if altBal ~= 0 and UI and UI.PopupConfirm then
                local Tr = ns.Tr or function(s) return s end
                local amt = (UI.MoneyText and UI.MoneyText(altBal)) or tostring(altBal)
                local body = (Tr("msg_merge_balance_body") or "Transfer %s from %s to %s and set %s to 0?")
                body = string.format(body, amt, altFull, fullMain, altFull)
                UI.PopupConfirm(body, function()
                    doAssignWithOptionalMerge()
                end, nil, { title = Tr("msg_merge_balance_title") or "Merge balance?" })
            else
                doAssignWithOptionalMerge()
            end
        end)
    end
end

-- ===== Mains (25%) =====
local mainsCols = {
    { key = "name",  title = Tr("lbl_mains") or "Mains", flex = 1, min = 140 },
    { key = "solde", title = Tr("col_balance") or "Solde", w = 90, justify = "RIGHT" },
    { key = "act",   title = "", min = 26 },
}

local function BuildRowMains(r)
    local f = {}
    -- Enable mouse to catch clicks for selection
    if r.EnableMouse then r:EnableMouse(true) end
    f.name = UI.CreateNameTag(r)
    f.solde = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.act  = CreateFrame("Frame", nil, r); f.act:SetHeight(UI.ROW_H)
    if _IsGM() then
        r.btnDel = UI.Button(f.act, "X", { size="xs", variant="ghost", minWidth=22, tooltip=Tr("tip_remove_main") or "Supprimer" })
    end
    UI.AttachRowRight(f.act, { r.btnDel }, 6, -4, { leftPad=4, align="center" })
    -- Hover highlight setup (subtle) for mains list
    if r.EnableMouse then r:EnableMouse(true) end
    if not r._hover then
        local h = r:CreateTexture(nil, "ARTWORK", nil, 1)
        h:SetAllPoints(r)
        h:SetTexture("Interface\\Buttons\\WHITE8x8")
        if UI and UI.SnapTexture then UI.SnapTexture(h) end
        h:SetVertexColor(1, 1, 1, 0.06) -- subtle light overlay
        h:Hide()
        r._hover = h
    end
    local function showHover() if r._hover then r._hover:Show() end end
    local function hideHover() if r._hover then r._hover:Hide() end end
    r:HookScript("OnEnter", showHover)
    r:HookScript("OnLeave", hideHover)
    if f.act and f.act.HookScript then
        f.act:HookScript("OnEnter", showHover)
        f.act:HookScript("OnLeave", hideHover)
    end
    if r.btnDel and r.btnDel.HookScript then
        r.btnDel:HookScript("OnEnter", showHover)
        r.btnDel:HookScript("OnLeave", hideHover)
    end
    -- GM-only delete button (no-op if not created)
    if r.btnDel then r.btnDel:SetShown(_IsGM()) end
    return f
end

local function UpdateRowMains(i, r, f, it)
    local data = it.data or it
    do
        local cls = _SelfClassTag(data.name)
        if UI and UI.SetNameTagShortEx then
            UI.SetNameTagShortEx(f.name, data.name or "", cls)
        else
            UI.SetNameTagShort(f.name, data.name or "")
        end
    end
    -- Solde en or
    if f.solde then
        local bal = (GLOG and GLOG.GetSolde and GLOG.GetSolde(data.name)) or 0
        if UI and UI.MoneyText then
            f.solde:SetText(UI.MoneyText(tonumber(bal) or 0))
        else
            f.solde:SetText(tostring(tonumber(bal) or 0))
        end
        if f.solde.SetJustifyH then f.solde:SetJustifyH("RIGHT") end
    end

    -- highlight selection
    local sel = selectedMainName and GLOG.SamePlayer and GLOG.SamePlayer(selectedMainName, data.name)
    -- Ensure selection overlay exists (independent from gradient)
    if not r._sel then
        local t = r:CreateTexture(nil, "ARTWORK", nil, 2)
        t:SetAllPoints(r)
        t:SetTexture("Interface\\Buttons\\WHITE8x8")
        if UI and UI.SnapTexture then UI.SnapTexture(t) end
        t:Hide()
        r._sel = t
    end
    -- Base gradient always applied
    if UI.ApplyRowGradient then UI.ApplyRowGradient(r, (i % 2 == 0)) end
    -- Selection tint above gradient
    if r._sel then
        if sel then
            -- softer green tint for better readability
            r._sel:SetVertexColor(0.18, 0.70, 0.30, 0.12)
            r._sel:Show()
        else
            r._sel:Hide()
        end
    end

    -- Ensure GM-only visibility reflects current status
    if r.btnDel then r.btnDel:SetShown(_IsGM()) end

    local function handleSelect()
        selectedMainName = data.name
        -- Immediate visual selection without a full list refresh
        if selectedMainRow and selectedMainRow._sel then selectedMainRow._sel:Hide() end
        selectedMainRow = r
    if r._sel then r._sel:SetVertexColor(0.18, 0.70, 0.30, 0.12); r._sel:Show() end
        -- Update alts immediately for snappy selection
        if lvAlts and lvAlts.SetData then lvAlts:SetData(buildAltsData()) end
        -- Update dynamic header without a full layout
        if rightPane and rightPane._sectionHeaderFS then
            rightPane._sectionHeaderFS:SetText((Tr("lbl_main_prefix") or "Main: ") .. (selectedMainName or ""))
        end
        -- Rebuild pool (for suggestions ordering) lightly after a short delay
        _schedulePoolRebuild()
    end
    r:SetScript("OnMouseDown", function(btn)
        if r.btnDel and r.btnDel:IsMouseOver() then return end
        handleSelect()
    end)
    r:SetScript("OnMouseUp", function(btn)
        if r.btnDel and r.btnDel:IsMouseOver() then return end
        handleSelect()
    end)

    if r.btnDel then
        r.btnDel:SetOnClick(function()
            if selectedMainName and GLOG.SamePlayer and GLOG.SamePlayer(selectedMainName, data.name) then
                selectedMainName = nil
            end
            GLOG.RemoveMain(data.name)
            _refreshAll()
        end)
    end
end

-- ===== Alts (25%) =====
local altsCols = {
    { key = "name",  title = Tr("lbl_associated_alts") or "Alts associés", flex = 1, min = 140 },
    { key = "act",   title = "", min = 26 },
}

local function BuildRowAlts(r)
    local f = {}
    f.name = UI.CreateNameTag(r)
    f.act  = CreateFrame("Frame", nil, r); f.act:SetHeight(UI.ROW_H)
    if _IsGM() then
        local crown = (CreateAtlasMarkup and CreateAtlasMarkup(ICON_MAIN_ATLAS, 18, 18)) or ("|A:"..ICON_MAIN_ATLAS..":18:18|a")
        r.btnPromote = UI.Button(f.act, crown, { size="xs", variant="ghost", minWidth=30, padX=6, tooltip = Tr("tip_set_main") or "Confirmer en main" })
        r.btnDel = UI.Button(f.act, "X", { size="xs", variant="ghost", minWidth=22, tooltip=Tr("tip_unassign_alt") or "Dissocier" })
    end
    UI.AttachRowRight(f.act, { r.btnPromote, r.btnDel }, 6, -4, { leftPad=4, align="center" })

    -- Hover highlight (same as mains list)
    if r.EnableMouse then r:EnableMouse(true) end
    if not r._hover then
        local h = r:CreateTexture(nil, "ARTWORK", nil, 1)
        h:SetAllPoints(r)
        h:SetTexture("Interface\\Buttons\\WHITE8x8")
        if UI and UI.SnapTexture then UI.SnapTexture(h) end
        h:SetVertexColor(1, 1, 1, 0.06)
        h:Hide()
        r._hover = h
    end
    local function showHover() if r._hover then r._hover:Show() end end
    local function hideHover() if r._hover then r._hover:Hide() end end
    r:HookScript("OnEnter", showHover)
    r:HookScript("OnLeave", hideHover)
    if f.act and f.act.HookScript then
        f.act:HookScript("OnEnter", showHover)
        f.act:HookScript("OnLeave", hideHover)
    end
    if r.btnPromote and r.btnPromote.HookScript then
        r.btnPromote:HookScript("OnEnter", showHover)
        r.btnPromote:HookScript("OnLeave", hideHover)
    end
    if r.btnDel and r.btnDel.HookScript then
        r.btnDel:HookScript("OnEnter", showHover)
        r.btnDel:HookScript("OnLeave", hideHover)
    end
    return f
end

local function UpdateRowAlts(i, r, f, it)
    local data = it.data or it
    do
        local cls = _SelfClassTag(data.name)
        if UI and UI.SetNameTagShortEx then
            UI.SetNameTagShortEx(f.name, data.name or "", cls)
        else
            UI.SetNameTagShort(f.name, data.name or "")
        end
    end
    -- Base gradient for zebra effect
    if UI.ApplyRowGradient then UI.ApplyRowGradient(r, (i % 2 == 0)) end
    -- Ensure GM-only visibility reflects current status (no-op if buttons weren't created)
    if r.btnPromote then r.btnPromote:SetShown(_IsGM()) end
    if r.btnDel then r.btnDel:SetShown(_IsGM()) end
    if r.btnPromote then
        r.btnPromote:SetOnClick(function()
            if not selectedMainName or selectedMainName == "" then return end
            local fullMain = (GLOG and GLOG.ResolveFullName and GLOG.ResolveFullName(selectedMainName)) or selectedMainName
            GLOG.PromoteAltToMain(data.name, fullMain)
            -- Keep selection on the new main (the promoted alt)
            selectedMainName = data.name
            -- Refresh lists: mains changed (swap), alts for new main changed, pool likely unchanged
            if lvMains and lvMains.SetData then lvMains:SetData(buildMainsData()); lvMains:Layout() end
            if lvAlts and lvAlts.SetData then lvAlts:SetData(buildAltsData()); lvAlts:Layout() end
        end)
    end
    if r.btnDel then
        r.btnDel:SetOnClick(function()
            GLOG.UnassignAlt(data.name)
            _refreshAll()
        end)
    end
end

-- ===== Refresh data builders =====
function buildPoolData()
    local rows = {}
    local pool = (GLOG.GetUnassignedPool and GLOG.GetUnassignedPool()) or {}
    local suggestions = {}
    if selectedMainName and GLOG.SuggestAltsForMain then
        for _, r in ipairs(GLOG.SuggestAltsForMain(selectedMainName) or {}) do suggestions[r.name] = true end
    end

    -- Build a fast lookup: normalized player name -> original guild note (remark)
    local grs = (GLOG.GetGuildRowsCached and GLOG.GetGuildRowsCached()) or {}
    local noteByNameKey = {}
    for _, gr in ipairs(grs) do
        local key = gr.name_key or (GLOG.NormName and GLOG.NormName(gr.name_amb or gr.name_raw)) or nil
        if key and key ~= "" then
            noteByNameKey[key] = (gr.remark and strtrim(gr.remark)) or ""
        end
    end

    -- Read class info from cache (by normalized name)
    local guildBy = (GLOG._guildCache and GLOG._guildCache.byName) or {}
    if #pool > 0 then
        for _, p in ipairs(pool) do
            local k = GLOG.NormName and GLOG.NormName(p.name)
            local gr = k and guildBy[k] or nil
            -- Use original note text, not normalized key
            local note = (GLOG.GetGuildNoteByName and GLOG.GetGuildNoteByName(p.name)) or (k and noteByNameKey[k]) or ""
            local classTag = (GLOG.GetGuildClassTag and GLOG.GetGuildClassTag(p.name)) or (gr and (gr.classFile or gr.classTag or gr.class) or nil)
            rows[#rows+1] = { name = p.name, note = note, classTag = classTag, suggested = (suggestions[p.name] and true or false) }
        end
    else
        -- Fallback: populate from guild roster cache when DB has no unassigned entries
        local seen = {}
        local targetNk = nil
        if selectedMainName and selectedMainName ~= "" then
            targetNk = (GLOG and GLOG.NormName and GLOG.NormName(selectedMainName)) or string.lower(selectedMainName)
        end
        for _, gr in ipairs(grs) do
            local full = gr.name_amb or gr.name_raw
            if full and full ~= "" then
                local key = gr.name_key or (GLOG.NormName and GLOG.NormName(full)) or full:lower()
                if not seen[key] then
                    seen[key] = true
                    local rec = guildBy[key]
                    -- Use original note from the roster row
                    local note = (GLOG.GetGuildNoteByName and GLOG.GetGuildNoteByName(full)) or (gr.remark and strtrim(gr.remark)) or ""
                    -- Skip if already linked manually (compact mapping)
                    local assigned = (GLOG.HasManualLink and GLOG.HasManualLink(full)) or false
                    if not assigned then
                        local isSug = false
                        if targetNk and note ~= "" then
                            local nkNote = (GLOG and GLOG.NormName and GLOG.NormName(note)) or string.lower(note)
                            isSug = (nkNote == targetNk)
                        end
                        local classTag = rec and (rec.classFile or rec.classTag or rec.class) or nil
                        rows[#rows+1] = { name = full, note = note, classTag = classTag, suggested = isSug or (suggestions[full] and true or false) }
                    end
                end
            end
        end
    end
    -- sort: suggestions first then alpha
    table.sort(rows, function(a,b)
        if a.suggested ~= b.suggested then return a.suggested end
        return (a.name or ""):lower() < (b.name or ""):lower()
    end)
    return rows
end

function buildMainsData()
    local arr = (GLOG.GetConfirmedMains and GLOG.GetConfirmedMains()) or {}
    return arr
end

function buildAltsData()
    if not selectedMainName or selectedMainName == "" then return {} end
    return (GLOG.GetAltsOf and GLOG.GetAltsOf(selectedMainName)) or {}
end

-- ===== BUILD =====
local function Build(container)
    panel, footer, footerH = UI.CreateMainContainer(container, { footer = false })

    leftPane = CreateFrame("Frame", nil, panel)
    midPane  = CreateFrame("Frame", nil, panel)
    rightPane= CreateFrame("Frame", nil, panel)

    UI.SectionHeader(leftPane, Tr("lbl_available_pool") or "Pool disponible")
    lvPool  = UI.ListView(leftPane,  poolCols,  { buildRow = BuildRowPool,  updateRow = UpdateRowPool,  topOffset = UI.SECTION_HEADER_H or 26 })

    UI.SectionHeader(midPane,  Tr("lbl_mains") or "Mains confirmés")
    lvMains = UI.ListView(midPane,  mainsCols, { buildRow = BuildRowMains, updateRow = UpdateRowMains, topOffset = UI.SECTION_HEADER_H or 26 })

    do
        local _, fs = UI.SectionHeader(rightPane, Tr("lbl_associated_alts") or "Alts associés")
        rightPane._sectionHeaderFS = fs
    end
    lvAlts  = UI.ListView(rightPane, altsCols, { buildRow = BuildRowAlts,  updateRow = UpdateRowAlts,  topOffset = UI.SECTION_HEADER_H or 26 })

    -- Initial data
    poolDataCache = buildPoolData(); lvPool:SetData(poolDataCache)
    lvMains:SetData(buildMainsData())
    lvAlts:SetData(buildAltsData())

    -- Ensure initial pane sizing and keep in sync on resize
    if Layout then Layout() end
    if panel and panel.HookScript then
        panel:HookScript("OnSizeChanged", function() if Layout then Layout() end end)
        panel:HookScript("OnShow", function() if Layout then Layout() end end)
    end

    -- React to cache refreshes
    if ns and ns.Events and ns.Events.Register then
        ns.Events.Register("GUILD_ROSTER_UPDATE", lvPool, function()
            poolDataCache = buildPoolData()
            if lvPool and lvPool.SetData then lvPool:SetData(poolDataCache) end
        end)
    end
    -- Internal event (addon bus)
    if GLOG and GLOG.On then
        GLOG.On("mainalt:changed", function()
            poolDataCache = buildPoolData()
            if lvPool and lvPool.SetData then lvPool:SetData(poolDataCache) end
            if lvMains and lvMains.SetData then lvMains:SetData(buildMainsData()) end
            if lvAlts and lvAlts.SetData then lvAlts:SetData(buildAltsData()) end
            if Layout then Layout() end
        end)
    end
end

-- ===== REFRESH =====
local function Refresh()
    poolDataCache = buildPoolData(); if lvPool and lvPool.SetData then lvPool:SetData(poolDataCache) end
    if lvMains and lvMains.SetData then lvMains:SetData(buildMainsData()) end
    if lvAlts and lvAlts.SetData then lvAlts:SetData(buildAltsData()) end
end

-- ===== LAYOUT =====
function Layout()
    if not panel then return end
    local pad = UI.OUTER_PAD or 8
    local W, H = panel:GetWidth(), panel:GetHeight()
    if not W or not H or W <= 0 or H <= 0 then return end

    local footerH = (footer and footer:GetHeight() or 0) + 6
    local availW = math.max(0, W - (pad*2))
    local availH = math.max(0, H - footerH - (pad*2))

    local wLeft = math.floor(availW * 0.40)
    local wMid  = math.floor(availW * 0.35)
    local wRight= availW - wLeft - wMid -- ~25%

    leftPane:ClearAllPoints();
    leftPane:SetPoint("TOPLEFT",  panel, "TOPLEFT",  pad, -pad)
    leftPane:SetSize(wLeft, availH)

    midPane:ClearAllPoints();
    midPane:SetPoint("TOPLEFT",  leftPane, "TOPRIGHT", 6, 0)
    midPane:SetSize(wMid, availH)

    rightPane:ClearAllPoints();
    rightPane:SetPoint("TOPLEFT",  midPane, "TOPRIGHT", 6, 0)
    rightPane:SetPoint("TOPRIGHT", panel,  "TOPRIGHT", -pad, -pad)
    rightPane:SetHeight(availH)

    if lvPool and lvPool.Layout then lvPool:Layout() end
    if lvMains and lvMains.Layout then lvMains:Layout() end
    if lvAlts and lvAlts.Layout then lvAlts:Layout() end

    -- Update dynamic header for alts
    if rightPane._sectionHeaderFS then
        if selectedMainName and selectedMainName ~= "" then
            rightPane._sectionHeaderFS:SetText((Tr("lbl_main_prefix") or "Main: ") .. (selectedMainName or ""))
        else
            rightPane._sectionHeaderFS:SetText(Tr("lbl_associated_alts") or "Alts associés")
        end
    end
end

-- (dynamic SectionHeader FontString captured during Build)

UI.RegisterTab(Tr("tab_main_alt") or "Main/Alt", Build, Refresh, Layout, {
    category = Tr("cat_guild"),
})
