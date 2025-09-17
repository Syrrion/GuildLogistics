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

-- Perf: suppression window to avoid heavy pool rebuilds right after local lightweight updates
local _poolSuppressUntil = 0
local function _Now()
    if GetTime then return GetTime() end
    return (ns and ns.Time and ns.Time.Now and ns.Time.Now()) or 0
end
local function _ShouldSuppressPoolRebuild()
    return _Now() < (_poolSuppressUntil or 0)
end

-- Perf: cache for suggestions per selected main, invalidated on guild cache ts change
local _suggCache = { key=nil, ts=0, set=nil }
local function _GetSuggestionsForSelectedMain()
    local key = nil
    if selectedMainName and selectedMainName ~= "" then
        key = (GLOG and GLOG.NormName and GLOG.NormName(selectedMainName)) or string.lower(selectedMainName)
    end
    local ts  = (GLOG and GLOG.GetGuildCacheTimestamp and GLOG.GetGuildCacheTimestamp()) or 0
    if key and _suggCache.key == key and _suggCache.ts == ts and _suggCache.set then
        return _suggCache.set
    end
    local set = {}
    if key and GLOG and GLOG.SuggestAltsForMain then
        local list = GLOG.SuggestAltsForMain(selectedMainName) or {}
        for i = 1, #list do
            local r = list[i]
            local nk = (GLOG and GLOG.NormName and GLOG.NormName(r.name)) or string.lower(r.name or "")
            if nk and nk ~= "" then set[nk] = true end
        end
    end
    _suggCache.key = key; _suggCache.ts = ts; _suggCache.set = set
    return set
end
-- forward decl for columns/rows builders used by recreation
local poolDataCache -- incremental cache for left list

-- Reorder pool so that suggested entries appear first, then others (both alpha within groups)
local function _ResortPoolForCurrentSelection()
    if not (poolDataCache and lvPool) then return end
    local suggSet = _GetSuggestionsForSelectedMain() or {}
    if not suggSet or (next(suggSet) == nil) then return end

    local suggested, others = {}, {}
    for i = 1, #poolDataCache do
        local it = poolDataCache[i]
        local nk = (GLOG and GLOG.NormName and GLOG.NormName(it.name)) or string.lower(it.name or "")
        if nk ~= "" and suggSet[nk] then
            suggested[#suggested+1] = it
        else
            others[#others+1] = it
        end
    end
    if #suggested == 0 then return end

    local function alpha(a,b) return (a.name or ""):lower() < (b.name or ""):lower() end
    table.sort(suggested, alpha)
    table.sort(others, alpha)

    local new = {}
    for i=1,#suggested do new[#new+1] = suggested[i] end
    for i=1,#others do new[#new+1] = others[i] end
    poolDataCache = new
    lvPool._data = poolDataCache
end

-- Scroll pool to top only if there are suggestions for the current selection
local function _ScrollPoolToTopIfSuggestions()
    if not (lvPool and lvPool.scroll) then return end
    local suggSet = _GetSuggestionsForSelectedMain() or {}
    if next(suggSet) == nil then return end -- no suggestions: keep current position
    local off = (lvPool.scroll.GetVerticalScroll and lvPool.scroll:GetVerticalScroll()) or 0
    if off and off > 0 then
        if lvPool.scroll.SetVerticalScroll then lvPool.scroll:SetVerticalScroll(0) end
        if lvPool._UpdateVisibleWindow then lvPool:_UpdateVisibleWindow() end
        if lvPool.Layout then lvPool:Layout() end
        if UI and UI.ListView_SyncScrollbar then UI.ListView_SyncScrollbar(lvPool, false) end
    end
end

-- ===== Online helpers (strict full-name + guild cache) =====
local function _ResolveFull(name)
    return (GLOG and ((GLOG.ResolveFullNameStrict and GLOG.ResolveFullNameStrict(name)) or (GLOG.ResolveFullName and GLOG.ResolveFullName(name)))) or name
end

local function _NormKey(name)
    return (GLOG and GLOG.NormName and GLOG.NormName(name)) or (name and string.lower(name)) or nil
end

-- Returns true if the provided full or ambiguous name appears online in the guild cache
local function _IsOnlineName(name)
    if not name or name == "" then return false end
    -- Prefer explicit API if addon exposes it
    if GLOG and GLOG.IsPlayerOnline then
        local ok = GLOG.IsPlayerOnline(name)
        if ok ~= nil then return ok and true or false end
    end
    local full = _ResolveFull(name)
    local nk   = _NormKey(full)
    local by   = (GLOG and GLOG._guildCache and GLOG._guildCache.byName) or nil
    local gr   = (nk and by) and by[nk] or nil
    if gr and gr.online ~= nil then return gr.online and true or false end
    -- Fallback: scan cached guild rows
    local grs = (GLOG and GLOG.GetGuildRowsCached and GLOG.GetGuildRowsCached()) or nil
    if type(grs) == "table" then
        for _, row in ipairs(grs) do
            local key = row.name_key or _NormKey(row.name_amb or row.name_raw)
            if key and nk and key == nk then
                if row.online ~= nil then return row.online and true or false end
                break
            end
        end
    end
    return false
end

-- Returns true if the main or any of its alts are currently online
local function _IsAnyGroupOnline(mainName)
    if not mainName or mainName == "" then return false end
    local fullMain = _ResolveFull(mainName)
    if _IsOnlineName(fullMain) then return true end
    local alts = (GLOG and GLOG.GetAltsOf and GLOG.GetAltsOf(fullMain)) or {}
    for _, alt in ipairs(alts) do
        local nm = (type(alt) == "table" and (alt.name or alt.full or alt.n)) or alt
        if nm and _IsOnlineName(nm) then return true end
    end
    return false
end

-- Tint UIPanelButtonTemplate background to grey (offline) or reset (online)
local function _SetPanelButtonGrey(btn, grey)
    if not btn then return end
    local r,g,b = 1,1,1
    if grey then
        local C = (UI and UI.GRAY_OFFLINE) or { 0.30, 0.30, 0.30 }
        r,g,b = C[1] or 0.30, C[2] or 0.30, C[3] or 0.30
    end
    local function tint(tex)
        if not tex then return end
        if tex.SetDesaturated then pcall(tex.SetDesaturated, tex, grey and true or false) end
        if tex.SetVertexColor then pcall(tex.SetVertexColor, tex, r, g, b) end
    end
    -- Try direct normal/pushed/disabled if available
    if btn.GetNormalTexture   then tint(btn:GetNormalTexture())   end
    if btn.GetPushedTexture   then tint(btn:GetPushedTexture())   end
    if btn.GetDisabledTexture then tint(btn:GetDisabledTexture()) end
    -- Fallback: UIPanelButtonTemplate often uses multiple slice textures; scan all regions
    local regs = { btn:GetRegions() }
    for _, reg in ipairs(regs) do
        if reg and reg.GetObjectType and reg:GetObjectType() == "Texture" then
            local layer = (reg.GetDrawLayer and select(1, reg:GetDrawLayer())) or ""
            if layer ~= "HIGHLIGHT" then tint(reg) end
        end
    end
end

local function _schedulePoolRebuild()
    local fn = function()
        poolDataCache = buildPoolData()
        if lvPool and lvPool.SetData then lvPool:SetData(poolDataCache) end
    end
    if ns and ns.Util and ns.Util.Debounce then
        -- Si on est dans une fenêtre de suppression, attendre sa fin avant de reconstruire
        if _ShouldSuppressPoolRebuild() then
            local delay = math.max(0.02, (_poolSuppressUntil - _Now()))
            ns.Util.Debounce("Roster_MainAlt.poolRebuild.wait", delay, fn)
        else
            -- Légèrement augmenté pour mieux regrouper des actions en rafale
            ns.Util.Debounce("Roster_MainAlt.poolRebuild", 0.08, fn)
        end
    else
        if UI and UI.NextFrame then UI.NextFrame(fn) else fn() end
    end
end

-- Use requested atlases for icons
local ICON_MAIN_ATLAS = "GO-icon-Header-Assist-Applied"
local ICON_ALT_ATLAS  = "GO-icon-Assist-Available"
local ICON_ALIAS_ATLAS = "Professions_Icon_FirstTimeCraft"
local ICON_CLOSE_ATLAS = "uitools-icon-close"
local ICON_EDITOR_GRANT_TEX = "auctionhouse-icon-favorite-off"
local ICON_EDITOR_REVOKE_TEX = "auctionhouse-icon-favorite"

-- Helper: get the character's own class tag from guild cache (ignores main's class)
-- Resolve a class tag for a character with progressive fallbacks.
-- 1) Fast guild cache lookup (cheap, no iteration)
-- 2) Derived name class (may look at main mapping)
-- 3) Last resort: style helper (returns class plus color) – we only use the class token
local function _SelfClassTag(name)
    if not name or name == "" then return nil end
    local cls = (GLOG and GLOG.GetGuildClassTag and GLOG.GetGuildClassTag(name)) or nil
    if (not cls or cls == "") and GLOG and GLOG.GetNameClass then
        cls = GLOG.GetNameClass(name)
    end
    if (not cls or cls == "") and GLOG and GLOG.GetNameStyle then
        local s = select(1, GLOG.GetNameStyle(name))
        if s and s ~= "" then cls = s end
    end
    return cls
end

local function _refreshAll()
    if lvPool and lvPool.Refresh then lvPool:RefreshData(nil) end
    if lvMains and lvMains.Refresh then lvMains:RefreshData(nil) end
    if lvAlts and lvAlts.Refresh then lvAlts:RefreshData(nil) end
end

-- Incremental add to pool by name (immediate feedback), with later coalesced resort
local function _addToPoolByName(name)
    if not name or name == "" then return end
    local full = (GLOG and GLOG.ResolveFullName and GLOG.ResolveFullName(name)) or name
    local note = (GLOG and GLOG.GetGuildNoteByName and GLOG.GetGuildNoteByName(full)) or ""
    local classTag = (GLOG and GLOG.GetGuildClassTag and GLOG.GetGuildClassTag(full)) or nil
    local suggSet = _GetSuggestionsForSelectedMain() or {}
    local fnk = (GLOG and GLOG.NormName and GLOG.NormName(full)) or string.lower(full)
    local suggested = (fnk and fnk ~= "" and suggSet[fnk]) and true or false
    local row = { name = full, note = note, classTag = classTag, suggested = suggested }
    poolDataCache = poolDataCache or {}
    -- Heuristic insert: top if suggested, else append
    if suggested then
        table.insert(poolDataCache, 1, row)
    else
        poolDataCache[#poolDataCache+1] = row
    end
    -- Inject compacted data without heavy SetData
    if lvPool then
        lvPool._data = poolDataCache
        -- Invalidate cache refs near the insertion zone
        local start = suggested and 1 or math.max(1, #poolDataCache - 2)
        if lvPool.rows then
            for i = start, math.min(#lvPool.rows, #poolDataCache) do
                local rowf = lvPool.rows[i]
                if rowf then rowf._lastItemRef = nil end
            end
        end
        if lvPool._windowed and lvPool._UpdateVisibleWindow then
            lvPool:_UpdateVisibleWindow()
        else
            if lvPool.UpdateVisibleRows then lvPool:UpdateVisibleRows() end
            if lvPool.Layout then lvPool:Layout() end
        end
    end
    -- Plan a proper rebuild (sorting) slightly later
    if _schedulePoolRebuild then _schedulePoolRebuild() end
end

-- Incremental removal from pool cache by name
local function _removeFromPoolByName(name)
    if not (poolDataCache and name and name ~= "") then return false end
    local nk = (GLOG and GLOG.NormName and GLOG.NormName(name)) or string.lower(name)
    for idx = #poolDataCache, 1, -1 do
        local it = poolDataCache[idx]
        local nk2 = (GLOG and GLOG.NormName and GLOG.NormName(it.name)) or string.lower(it.name or "")
        if nk == nk2 then
            -- Compacte immédiatement le dataset pour éviter une ligne vide
            table.remove(poolDataCache, idx)
            if lvPool then
                -- Met à jour la data du ListView sans SetData lourd
                lvPool._data = poolDataCache
                -- Invalide les refs pour forcer updateRow sur la zone impactée
                if lvPool.rows then
                    for i = idx, math.min(#lvPool.rows, #poolDataCache + 1) do
                        local row = lvPool.rows[i]
                        if row then row._lastItemRef = nil end
                    end
                end
                -- Met à jour la fenêtre visible (mode virtual) ou fait un refresh léger
                if lvPool._windowed and lvPool._UpdateVisibleWindow then
                    lvPool:_UpdateVisibleWindow()
                else
                    if lvPool.UpdateVisibleRows then lvPool:UpdateVisibleRows() end
                    if lvPool.Layout then lvPool:Layout() end
                end
            end
            -- Fenêtre d’anti-rebuild pour coalescer les bursts
            _poolSuppressUntil = _Now() + 0.30
            return true
        end
    end
    return false
end

-- ===== Pool (50%) =====
-- Dynamic columns builders (hide actions for non-GM)
local function _BuildPoolCols()
    local cols = {
        { key = "name",  title = Tr("lbl_player"), flex = 1, min = 120 },
        { key = "note",  title = Tr("lbl_guild_note"),   vsep=true,flex = 1, min = 120, justify = "LEFT" },
    }
    if GLOG and GLOG.CanModifyGuildData and GLOG.CanModifyGuildData() then
        cols[#cols+1] = { key = "act", title = Tr("lbl_actions"), vsep=true, min = 72 }
    end
    return cols
end

local function BuildRowPool(r)
    local f = {}
    f.name = UI.CreateNameTag(r)
    -- Note column (guild note / remark)
    f.note = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.note:SetJustifyH("LEFT")

    -- Actions container (GM only)
    local gm = GLOG and GLOG.CanModifyGuildData and GLOG.CanModifyGuildData()
    if gm then
        f.act  = CreateFrame("Frame", nil, r); f.act:SetHeight(UI.ROW_H)
        -- Crown = set as Main (square icon with classic panel background)
        r.btnCrown = UI.IconButton(f.act, nil, { skin="panel", atlas=true, atlasName=ICON_MAIN_ATLAS, size=24, fit=true, pad=3, tooltip = Tr("tip_set_main") })
    -- Chevron = assign as Alt to selected Main (square with classic panel background)
    r.btnAlt   = UI.IconButton(f.act, nil, { skin="panel", atlas=true, atlasName="uitools-icon-chevron-right", size=24, fit=true, pad=3, tooltip=Tr("tip_assign_alt") })
        UI.AttachRowRight(f.act, { r.btnCrown, r.btnAlt }, 4, -4, { leftPad=4, align="center" })
    end
    return f
end

local function UpdateRowPool(i, r, f, it)
    local data = it.data or it
    do
        local cls = data.classTag or _SelfClassTag(data.name)
        local suggSet = _GetSuggestionsForSelectedMain() or {}
        local nk = (GLOG and GLOG.NormName and GLOG.NormName(data.name)) or string.lower(data.name or "")
        local isSuggested = (nk ~= "" and suggSet[nk]) and true or false
        if UI and UI.UpdateNameTagCached then
            UI.UpdateNameTagCached(f.name, data.name or "", cls, isSuggested and Tr("lbl_suggested") or nil, {0,1,0})
        else
            if UI and UI.SetNameTagShortEx then UI.SetNameTagShortEx(f.name, data.name or "", cls) else UI.SetNameTagShort(f.name, data.name or "") end
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
    local gm = GLOG and GLOG.CanModifyGuildData and GLOG.CanModifyGuildData()
        if r.btnCrown then r.btnCrown:SetShown(gm) end
        if r.btnAlt then r.btnAlt:SetShown(gm) end
    if r.btnCrown then
        -- Online restriction removed: keep button active for GMs and show tooltip always
        if UI and UI.SetButtonAlpha then UI.SetButtonAlpha(r.btnCrown, gm and 1 or 0.4) end
        if UI and UI.SetTooltip then
            local base = Tr("tip_set_main")
            UI.SetTooltip(r.btnCrown, base)
        end
        r.btnCrown:SetOnClick(function()
            if not gm then return end
            GLOG.SetAsMain(data.name)
            -- Remove from pool lazily: hide row + light layout, no SetData here
            if _removeFromPoolByName(data.name) then end
            -- update mains list; alts unaffected
            if lvMains and lvMains.SetData then lvMains:SetData(buildMainsData()) end
        end)
    end

    if r.btnAlt then
        -- If no main selected, keep button soft-disabled (alpha) but still show tooltip
        local can = (selectedMainName and selectedMainName ~= "") and true or false
        if UI and UI.SetButtonAlpha then UI.SetButtonAlpha(r.btnAlt, can and 1 or 0.4) end
        if UI and UI.SetTooltip then
            local base = Tr("tip_assign_alt")
            if can then UI.SetTooltip(r.btnAlt, base)
            else UI.SetTooltip(r.btnAlt, base .. "\n|cffaaaaaa" .. Tr("lbl_main_prefix") .. Tr("value_empty") .. "|r") end
        end
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
                -- Remove from pool lazily: hide row + light layout, no SetData here
                if _removeFromPoolByName(altFull) then end
                -- update current main's alts incrementally
                if lvAlts and lvAlts.SetData then lvAlts:SetData(buildAltsData()) end
            end

            if altBal ~= 0 and UI and UI.PopupConfirm then
                local amt = (UI.MoneyText and UI.MoneyText(altBal)) or tostring(altBal)
                local body = Tr("msg_merge_balance_body")
                body = string.format(body, amt, altFull, fullMain, altFull)
                UI.PopupConfirm(body, function()
                    doAssignWithOptionalMerge()
                end, nil, { title = Tr("msg_merge_balance_title") })
            else
                doAssignWithOptionalMerge()
            end
        end)
    end
end

-- ===== Mains (25%) =====
local function _BuildMainsCols()
    local cols = {
        { key = "name",  title = Tr("lbl_mains"), flex = 1, min = 100 },
        { key = "alias", title = Tr("lbl_alias"), vsep=true,w = 100, justify = "LEFT" },
        { key = "solde", title = Tr("col_balance"), vsep=true,w = 80, justify = "RIGHT" },
    }
    if GLOG and GLOG.CanModifyGuildData and GLOG.CanModifyGuildData() then
        -- Width depends on whether editor toggle is available to this user
        local isStandalone = (GLOG and GLOG.IsStandaloneMode and GLOG.IsStandaloneMode()) or false
        local canGrant = (GLOG.CanGrantEditor and GLOG.CanGrantEditor()) or false
        if isStandalone then canGrant = false end
        -- Aliases + Delete only (~2 icons) ≈ 76px; with editor toggle (~4 icons) ≈ 110px
        local minW = canGrant and 110 or 76
        cols[#cols+1] = { key = "act", title = "", vsep=true, min = minW }
    end
    return cols
end

local function BuildRowMains(r)
    local f = {}
    -- Enable mouse to catch clicks for selection
    if r.EnableMouse then r:EnableMouse(true) end
    f.name = UI.CreateNameTag(r)
    f.alias = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.solde = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    local gm = GLOG and GLOG.CanModifyGuildData and GLOG.CanModifyGuildData()
    local isStandalone = (GLOG and GLOG.IsStandaloneMode and GLOG.IsStandaloneMode()) or false
    local canGrant = (GLOG and GLOG.CanGrantEditor and GLOG.CanGrantEditor()) or false
    if isStandalone then canGrant = false end
    if gm then
        f.act  = CreateFrame("Frame", nil, r); f.act:SetHeight(UI.ROW_H)
        r.btnAlias = UI.IconButton(f.act, nil, { skin="panel", atlas=true, atlasName=ICON_ALIAS_ATLAS, size=24, fit=true, pad=5, tooltip = Tr("btn_set_alias") })
        r.btnDel   = UI.IconButton(f.act, nil, { skin="panel", atlas=true, atlasName=ICON_CLOSE_ATLAS, size=24, fit=true, pad=5, tooltip=Tr("tip_remove_main") })
        -- Editor toggle: create only if user has grant rights; avoids empty space reservation
        if canGrant then
            r.btnEditorGrant  = UI.IconButton(f.act, nil, { skin="panel", atlas=true, atlasName=ICON_EDITOR_GRANT_TEX, size=24, fit=true, pad=5, tooltip = Tr("tip_grant_editor") })
            r.btnEditorRevoke = UI.IconButton(f.act, nil, { skin="panel", atlas=true, atlasName=ICON_EDITOR_REVOKE_TEX, size=24, fit=true, pad=5, tooltip = Tr("tip_revoke_editor") })
            UI.AttachRowRight(f.act, { r.btnDel, r.btnAlias, r.btnEditorRevoke, r.btnEditorGrant }, 4, -4, { leftPad=4, align="center" })
        else
            -- Pack without editor toggle
            UI.AttachRowRight(f.act, { r.btnDel, r.btnAlias }, 4, -4, { leftPad=4, align="center" })
        end
    end
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
    if r.btnDel then r.btnDel:SetShown(GLOG and GLOG.CanModifyGuildData and GLOG.CanModifyGuildData()) end
    if r.btnAlias then r.btnAlias:SetShown(GLOG and GLOG.CanModifyGuildData and GLOG.CanModifyGuildData()) end
    if r.btnEditorGrant then r.btnEditorGrant:SetShown((GLOG and GLOG.CanGrantEditor and GLOG.CanGrantEditor()) and not ((GLOG and GLOG.IsStandaloneMode and GLOG.IsStandaloneMode()) or false)) end
    if r.btnEditorRevoke then r.btnEditorRevoke:SetShown((GLOG and GLOG.CanGrantEditor and GLOG.CanGrantEditor()) and not ((GLOG and GLOG.IsStandaloneMode and GLOG.IsStandaloneMode()) or false)) end
    return f
end

local function UpdateRowMains(i, r, f, it)
    local data = it.data or it
    do
        local cls = _SelfClassTag(data.name)
        if UI and UI.UpdateNameTagCached then
            UI.UpdateNameTagCached(f.name, data.name or "", cls)
        else
            if UI and UI.SetNameTagShortEx then UI.SetNameTagShortEx(f.name, data.name or "", cls) else UI.SetNameTagShort(f.name, data.name or "") end
        end
    end
    -- Alias text (group-level)
    if f.alias then
        local a = (GLOG and GLOG.GetAliasFor and GLOG.GetAliasFor(data.name)) or ""
        f.alias:SetText(a or "")
        f.alias:SetJustifyH("LEFT")
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
    if r.btnDel then r.btnDel:SetShown(GLOG and GLOG.CanModifyGuildData and GLOG.CanModifyGuildData()) end
    if r.btnAlias then r.btnAlias:SetShown(GLOG and GLOG.CanModifyGuildData and GLOG.CanModifyGuildData()) end

    -- Editor toggle: compute current editor status for this main (by main UID)
    local isStandalone = (GLOG and GLOG.IsStandaloneMode and GLOG.IsStandaloneMode()) or false
    local canGrant = (GLOG and GLOG.CanGrantEditor and GLOG.CanGrantEditor()) or false
    if isStandalone then canGrant = false end
    local editors = (GLOG and GLOG.GetEditors and GLOG.GetEditors()) or {}
    -- Resolve the main UID for this entry (works for mains and alts); avoid non-existent GetUID/FindUIDByName
    local mainName = (GLOG and GLOG.GetMainOf and GLOG.GetMainOf(data.name)) or data.name
    -- Hide editor controls for the actual Guild Master (always has rights)
    local targetIsGM = (GLOG and GLOG.IsNameGuildMaster and GLOG.IsNameGuildMaster(mainName)) or false
    local mu = (GLOG and GLOG.GetOrAssignUID and GLOG.GetOrAssignUID(mainName)) or nil
    local isEditor = (mu and editors and editors[mu]) and true or false
    if r.btnEditorGrant then r.btnEditorGrant:SetShown(canGrant and not isEditor and not targetIsGM) end
    if r.btnEditorRevoke then r.btnEditorRevoke:SetShown(canGrant and isEditor and not targetIsGM) end

    -- Online gating: apply ONLY to editor promotion/demotion buttons
    local isOnline = _IsAnyGroupOnline(data.name)
    if r.btnEditorGrant and not targetIsGM then
        local enableGrant = canGrant and (not isEditor) and isOnline
        -- Soft-disable: keep tooltip visible even when grayed out
        if UI and UI.SetButtonAlpha then UI.SetButtonAlpha(r.btnEditorGrant, enableGrant and 1 or 0.4) end
        -- Grey background when offline (visual cue on the panel skin)
        _SetPanelButtonGrey(r.btnEditorGrant, not isOnline)
        -- Tooltip reason when disabled
        if UI and UI.SetTooltip then
            local base = Tr("tip_grant_editor")
            local statusCtx = Tr("tip_editor_status_demoted")
            if enableGrant then
                UI.SetTooltip(r.btnEditorGrant, base .. "\n|cffaaaaaa" .. statusCtx .. "|r")
            else
                local why = Tr("tip_disabled_offline_group")
                UI.SetTooltip(r.btnEditorGrant, base .. "\n|cffaaaaaa" .. statusCtx .. "|r" .. "\n|cffaaaaaa" .. why .. "|r")
            end
        end
    end
    if r.btnEditorRevoke and not targetIsGM then
        local enableRevoke = canGrant and isEditor and isOnline
        -- Soft-disable: keep tooltip visible even when grayed out
        if UI and UI.SetButtonAlpha then UI.SetButtonAlpha(r.btnEditorRevoke, enableRevoke and 1 or 0.4) end
        -- Grey background when offline
        _SetPanelButtonGrey(r.btnEditorRevoke, not isOnline)
        if UI and UI.SetTooltip then
            local base = Tr("tip_revoke_editor")
            local statusCtx = Tr("tip_editor_status_promoted")
            if enableRevoke then
                UI.SetTooltip(r.btnEditorRevoke, base .. "\n|cffaaaaaa" .. statusCtx .. "|r")
            else
                local why = Tr("tip_disabled_offline_group")
                UI.SetTooltip(r.btnEditorRevoke, base .. "\n|cffaaaaaa" .. statusCtx .. "|r" .. "\n|cffaaaaaa" .. why .. "|r")
            end
        end
    end
    -- Re-apply row action layout after visibility changes, otherwise the newly shown button may not reflow
    if f and f.act and f.act._applyRowActionsLayout then f.act._applyRowActionsLayout() end

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
            rightPane._sectionHeaderFS:SetText(Tr("lbl_main_prefix") .. (selectedMainName or ""))
        end
        -- Suggestions depend on selected main; reorder pool to put suggestions on top, then refresh lightly
        if lvPool then
            _ResortPoolForCurrentSelection()
            _ScrollPoolToTopIfSuggestions()
            if lvPool.InvalidateAllRowsCache and lvPool.UpdateVisibleRows then
                lvPool:InvalidateAllRowsCache()
                lvPool:UpdateVisibleRows()
                if lvPool.Layout then lvPool:Layout() end
            elseif lvPool.SetData then
                -- Fallback: full SetData
                poolDataCache = buildPoolData(); lvPool:SetData(poolDataCache)
            end
        elseif _schedulePoolRebuild then
            _schedulePoolRebuild()
        end
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
        -- Online restriction removed for removing a main; always available to authorized users
        if UI and UI.SetButtonAlpha then UI.SetButtonAlpha(r.btnDel, 1) end
        if UI and UI.SetTooltip then
            UI.SetTooltip(r.btnDel, Tr("tip_remove_main"))
        end
        r.btnDel:SetOnClick(function()
            local bal = (GLOG and GLOG.GetSolde and tonumber(GLOG.GetSolde(data.name))) or 0
            local function doRemove()
                if selectedMainName and GLOG.SamePlayer and GLOG.SamePlayer(selectedMainName, data.name) then
                    selectedMainName = nil
                end
                GLOG.RemoveMain(data.name)
                _refreshAll()
            end
            if bal ~= 0 and UI and UI.PopupConfirm then
                local amt = (UI and UI.MoneyText and UI.MoneyText(bal)) or tostring(bal)
                local body = (Tr("msg_remove_main_balance_body")):format(amt)
                UI.PopupConfirm(body, function()
                    doRemove()
                end, nil, { title = Tr("msg_remove_main_balance_title") or "Remove main with balance?", height = 260 })
            else
                doRemove()
            end
        end)
    end
    if r.btnAlias then
        r.btnAlias:SetOnClick(function()
            local target = data.name
            if not target or target == "" then return end
            -- Préremplir avec le nom du joueur (sans royaume)
            local base = tostring(target):match("^([^%-]+)") or tostring(target)
            UI.PopupPromptText(Tr("popup_set_alias_title"), Tr("lbl_alias"), function(val)
                if GLOG.GM_SetAlias then GLOG.GM_SetAlias(target, val) end
            end, { default = base, strata = "FULLSCREEN_DIALOG" })
        end)
    end
    if r.btnEditorGrant then
        r.btnEditorGrant:SetOnClick(function()
            if not (GLOG and GLOG.GM_GrantEditor) then return end
            -- Enforce online requirement at click time as well
            if not _IsAnyGroupOnline(data.name) then return end
            GLOG.GM_GrantEditor(data.name)
            -- Swap icons locally for immediate feedback (GM view only)
            if r.btnEditorGrant and r.btnEditorRevoke then
                r.btnEditorGrant:Hide()
                r.btnEditorRevoke:Show()
                -- Reflow action pack if layout helper exists
                if f and f.act and f.act._applyRowActionsLayout then f.act._applyRowActionsLayout() end
            end
        end)
    end
    if r.btnEditorRevoke then
        r.btnEditorRevoke:SetOnClick(function()
            if not (GLOG and GLOG.GM_RevokeEditor) then return end
            if not _IsAnyGroupOnline(data.name) then return end
            GLOG.GM_RevokeEditor(data.name)
            -- Swap icons locally for immediate feedback (GM view only)
            if r.btnEditorGrant and r.btnEditorRevoke then
                r.btnEditorRevoke:Hide()
                r.btnEditorGrant:Show()
                if f and f.act and f.act._applyRowActionsLayout then f.act._applyRowActionsLayout() end
            end
        end)
    end
end

-- ===== Alts (25%) =====
local function _BuildAltsCols()
    local cols = {
        { key = "name",  title = Tr("lbl_associated_alts"), flex = 1, min = 120 },
    }
    if GLOG and GLOG.CanModifyGuildData and GLOG.CanModifyGuildData() then
        cols[#cols+1] = { key = "act", title = "", vsep=true, min = 90 }
    end
    return cols
end

local function BuildRowAlts(r)
    local f = {}
    f.name = UI.CreateNameTag(r)
    local gm = GLOG and GLOG.CanModifyGuildData and GLOG.CanModifyGuildData()
    if gm then
        f.act  = CreateFrame("Frame", nil, r); f.act:SetHeight(UI.ROW_H)
        r.btnPromote = UI.IconButton(f.act, nil, { skin="panel", atlas=true, atlasName=ICON_MAIN_ATLAS, size=24, fit=true, pad=3, tooltip = Tr("tip_set_main") })
        r.btnAlias   = UI.IconButton(f.act, nil, { skin="panel", atlas=true, atlasName=ICON_ALIAS_ATLAS, size=24, fit=true, pad=5, tooltip = Tr("btn_set_alias") })
        r.btnDel     = UI.IconButton(f.act, nil, { skin="panel", atlas=true, atlasName=ICON_CLOSE_ATLAS, size=24, fit=true, pad=5, tooltip=Tr("tip_unassign_alt") })
        UI.AttachRowRight(f.act, { r.btnDel, r.btnAlias, r.btnPromote }, 4, -4, { leftPad=4, align="center" })
    end

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
        if UI and UI.UpdateNameTagCached then
            UI.UpdateNameTagCached(f.name, data.name or "", cls)
        else
            if UI and UI.SetNameTagShortEx then UI.SetNameTagShortEx(f.name, data.name or "", cls) else UI.SetNameTagShort(f.name, data.name or "") end
        end
    end
    -- Base gradient for zebra effect
    if UI.ApplyRowGradient then UI.ApplyRowGradient(r, (i % 2 == 0)) end
    -- Ensure GM-only visibility reflects current status (no-op if buttons weren't created)
    local gm = GLOG and GLOG.CanModifyGuildData and GLOG.CanModifyGuildData()
    if r.btnPromote then r.btnPromote:SetShown(gm) end
    if r.btnAlias then r.btnAlias:SetShown(gm) end
    if r.btnDel then r.btnDel:SetShown(gm) end
    if r.btnPromote then
        -- Online restriction removed here; promotion to main available to GMs regardless of online state
        if UI and UI.SetButtonAlpha then UI.SetButtonAlpha(r.btnPromote, gm and 1 or 0.4) end
        if UI and UI.SetTooltip then
            local base = Tr("tip_set_main")
            UI.SetTooltip(r.btnPromote, base)
        end
        r.btnPromote:SetOnClick(function()
            if not selectedMainName or selectedMainName == "" then return end
            local fullMain = (GLOG and GLOG.ResolveFullName and GLOG.ResolveFullName(selectedMainName)) or selectedMainName
            GLOG.PromoteAltToMain(data.name, fullMain)
            -- Keep selection on the new main (the promoted alt)
            selectedMainName = data.name
            -- Refresh lists: mains changed (swap), alts for new main changed, pool likely unchanged
            if lvMains and lvMains.SetData then lvMains:SetData(buildMainsData()) end
            if lvAlts and lvAlts.SetData then lvAlts:SetData(buildAltsData()) end
        end)
    end
    if r.btnDel then
        r.btnDel:SetOnClick(function()
            GLOG.UnassignAlt(data.name)
            -- Immediately reinsert into pool for instant feedback, and refresh current alts list
            _addToPoolByName(data.name)
            if lvAlts and lvAlts.SetData then lvAlts:SetData(buildAltsData()) end
        end)
    end
    if r.btnAlias then
        r.btnAlias:SetOnClick(function()
            local target = data.name
            if not target or target == "" then return end
            -- Alias is stored on the group (main). Editing from an alt edits the main group's alias.
            local base = tostring(target):match("^([^%-]+)") or tostring(target)
            UI.PopupPromptText(Tr("popup_set_alias_title"), Tr("lbl_alias"), function(val)
                if GLOG.GM_SetAlias then GLOG.GM_SetAlias(target, val) end
            end, { default = base, strata = "FULLSCREEN_DIALOG" })
        end)
    end
end

-- ===== Refresh data builders =====
function buildPoolData()
    local rows = {}
    local pool = (GLOG.GetUnassignedPool and GLOG.GetUnassignedPool()) or {}
    -- Suggestions en cache pour le main sélectionné
    local suggestions = _GetSuggestionsForSelectedMain() or {}

    -- Évite un scan coûteux du roster: privilégie les accès directs

    -- Read class info from cache (by normalized name)
    local guildBy = (GLOG._guildCache and GLOG._guildCache.byName) or {}
    if #pool > 0 then
        for _, p in ipairs(pool) do
            local k = GLOG.NormName and GLOG.NormName(p.name)
            local gr = k and guildBy[k] or nil
            -- Use original note text, not normalized key
            local note = (GLOG.GetGuildNoteByName and GLOG.GetGuildNoteByName(p.name)) or ""
            local classTag = (GLOG.GetGuildClassTag and GLOG.GetGuildClassTag(p.name)) or (gr and (gr.classFile or gr.classTag or gr.class) or nil)
            local pnk = (GLOG and GLOG.NormName and GLOG.NormName(p.name)) or string.lower(p.name or "")
            rows[#rows+1] = { name = p.name, note = note, classTag = classTag, suggested = (pnk ~= "" and suggestions[pnk] or false) and true or false }
        end
    else
        -- Fallback: populate from guild roster cache when DB has no unassigned entries
        local seen = {}
        local targetNk = nil
        if selectedMainName and selectedMainName ~= "" then
            targetNk = (GLOG and GLOG.NormName and GLOG.NormName(selectedMainName)) or string.lower(selectedMainName)
        end
        local grs = (GLOG.GetGuildRowsCached and GLOG.GetGuildRowsCached()) or {}
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
                        local fnk = (GLOG and GLOG.NormName and GLOG.NormName(full)) or string.lower(full or "")
                        rows[#rows+1] = { name = full, note = note, classTag = classTag, suggested = isSug or ((fnk ~= "" and suggestions[fnk]) and true or false) }
                    end
                end
            end
        end
    end
    -- sort: suggestions first then alpha
    -- Skip tri si dataset déjà trié (signature simple)
    local needsSort = true
    do
        local prevSug, prevNameLower = true, ""
        for i=1,#rows do
            local r = rows[i]
            local sug = r.suggested and true or false
            local nm = (r.name or ""):lower()
            -- Ordre souhaité: suggested d'abord (true), puis alpha
            if i == 1 then
                prevSug, prevNameLower = sug, nm
            else
                if (not prevSug and sug) then
                    needsSort = true; break
                end
                if (prevSug == sug) and (prevNameLower > nm) then
                    needsSort = true; break
                end
                needsSort = false
                prevSug, prevNameLower = sug, nm
            end
        end
    end
    if needsSort then
        table.sort(rows, function(a,b)
            if a.suggested ~= b.suggested then return a.suggested end
            return (a.name or ""):lower() < (b.name or ""):lower()
        end)
    end
    return rows
end

function buildMainsData()
    local arr = (GLOG.GetConfirmedMains and GLOG.GetConfirmedMains()) or {}
    -- Défensif: dataset déjà trié par GetConfirmedMains; pas de tri supplémentaire ici.
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

    UI.SectionHeader(leftPane, Tr("lbl_available_pool"))
    lvPool  = UI.ListView(leftPane,  _BuildPoolCols(),  { buildRow = BuildRowPool,  updateRow = UpdateRowPool, rowHeight = UI.ROW_H_SMALL, topOffset = UI.SECTION_HEADER_H or 26, maxCreatePerFrame = 60, virtualWindow = true })

    UI.SectionHeader(midPane,  Tr("lbl_mains"))
    lvMains = UI.ListView(midPane,  _BuildMainsCols(), { buildRow = BuildRowMains, updateRow = UpdateRowMains, rowHeight = UI.ROW_H_SMALL, topOffset = UI.SECTION_HEADER_H or 26, maxCreatePerFrame = 60 })

    do
        local _, fs = UI.SectionHeader(rightPane, Tr("lbl_associated_alts2"))
        rightPane._sectionHeaderFS = fs
    end
    lvAlts  = UI.ListView(rightPane, _BuildAltsCols(), { buildRow = BuildRowAlts,  updateRow = UpdateRowAlts, rowHeight = UI.ROW_H_SMALL, topOffset = UI.SECTION_HEADER_H or 26, maxCreatePerFrame = 60 })

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
            -- Évite les rebuilds lourds immédiats; planifie une MAJ compacte
            if _schedulePoolRebuild then _schedulePoolRebuild() end
        end)
        -- When the roster cache refreshes we may have gained class info: just invalidate and redraw mains/alts.
        ns.Events.Register("GUILD_ROSTER_UPDATE", lvMains, function()
            if lvMains then
                if lvMains.InvalidateAllRowsCache then lvMains:InvalidateAllRowsCache() end
                if lvMains.UpdateVisibleRows then lvMains:UpdateVisibleRows() end
            end
            if lvAlts then
                if lvAlts.InvalidateAllRowsCache then lvAlts:InvalidateAllRowsCache() end
                if lvAlts.UpdateVisibleRows then lvAlts:UpdateVisibleRows() end
            end
        end)
    end
    -- Internal event (addon bus)
    if GLOG and GLOG.On then
        GLOG.On("mainalt:changed", function()
            -- Coalesce les changements provenant du bus interne
            local function apply()
                -- Mains/Alts sont des petites listes: MAJ directe
                if lvMains and lvMains.SetData then lvMains:SetData(buildMainsData()) end
                if lvAlts and lvAlts.SetData then lvAlts:SetData(buildAltsData()) end
                -- Le pool est volumineux: planifie une MAJ compacte
                if _schedulePoolRebuild then _schedulePoolRebuild() end
                if Layout then Layout() end
            end
            if ns and ns.Util and ns.Util.Debounce then
                ns.Util.Debounce("Roster_MainAlt.changed", 0.08, apply)
            else
                apply()
            end
        end)
        -- Dropped dynamic UI rebuilds on rights changes per new UX: show a popup and let user /reload manually
        -- Keep the tab stable until a reload, avoiding column structure churn at runtime.
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

    -- Widths: Pool 38%, Mains 38%, Alts ~24% (remainder)
    local wLeft = math.floor(availW * 0.38)
    local wMid  = math.floor(availW * 0.38)
    local wRight= availW - wLeft - wMid -- ~24%

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
            rightPane._sectionHeaderFS:SetText(Tr("lbl_main_prefix") .. (selectedMainName or ""))
        else
            rightPane._sectionHeaderFS:SetText(Tr("lbl_associated_alts2"))
        end
    end
end

-- (dynamic SectionHeader FontString captured during Build)

UI.RegisterTab(Tr("tab_main_alt"), Build, Refresh, Layout, {
    category = Tr("cat_guild"),
})
