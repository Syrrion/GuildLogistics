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
-- forward decl for columns/rows builders used by recreation
local _BuildPoolCols, _BuildMainsCols, _BuildAltsCols
local BuildRowPool, UpdateRowPool
local BuildRowMains, UpdateRowMains
local BuildRowAlts,  UpdateRowAlts
local poolDataCache -- incremental cache for left list
local _RecreateListViews -- forward decl

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
        ns.Util.Debounce("Roster_MainAlt.poolRebuild", 0.05, fn)
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
local function _SelfClassTag(name)
    return (GLOG and GLOG.GetGuildClassTag and GLOG.GetGuildClassTag(name)) or nil
end

local function _refreshAll()
    if lvPool and lvPool.Refresh then lvPool:RefreshData(nil) end
    if lvMains and lvMains.Refresh then lvMains:RefreshData(nil) end
    if lvAlts and lvAlts.Refresh then lvAlts:RefreshData(nil) end
end

-- Destroy a ListView instance cleanly (header + scroll) and return nil
local function _DestroyListView(lv)
    if not lv then return nil end
    if lv.header then lv.header:Hide(); lv.header:SetParent(nil) end
    if lv.scroll then lv.scroll:Hide(); lv.scroll:SetParent(nil) end
    return nil
end

-- Full rebuild of the three ListViews to reflect permission-based columns/buttons
_RecreateListViews = function()
    -- Destroy old instances
    lvPool  = _DestroyListView(lvPool)
    lvMains = _DestroyListView(lvMains)
    lvAlts  = _DestroyListView(lvAlts)

    -- Recreate with current columns (depend on CanModifyGuildData/CanGrantEditor)
    lvPool  = UI.ListView(leftPane,  _BuildPoolCols(),  { buildRow = BuildRowPool,  updateRow = UpdateRowPool,  topOffset = UI.SECTION_HEADER_H or 26 })
    lvMains = UI.ListView(midPane,   _BuildMainsCols(), { buildRow = BuildRowMains, updateRow = UpdateRowMains, topOffset = UI.SECTION_HEADER_H or 26 })
    lvAlts  = UI.ListView(rightPane, _BuildAltsCols(),  { buildRow = BuildRowAlts,  updateRow = UpdateRowAlts,  topOffset = UI.SECTION_HEADER_H or 26 })

    -- Re-apply data
    poolDataCache = buildPoolData()
    if lvPool and lvPool.SetData then lvPool:SetData(poolDataCache) end
    if lvMains and lvMains.SetData then lvMains:SetData(buildMainsData()) end
    if lvAlts and lvAlts.SetData then lvAlts:SetData(buildAltsData()) end

    -- Drop stale selected row handle (rows recreated); name selection persists
    selectedMainRow = nil

    -- Layout panel to place new LVs
    if Layout then Layout() end
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
-- Dynamic columns builders (hide actions for non-GM)
local function _BuildPoolCols()
    local cols = {
        { key = "name",  title = Tr("lbl_player") or "Joueur", flex = 1, min = 120 },
        { key = "note",  title = Tr("lbl_guild_note") or "Guild note",   vsep=true,flex = 1, min = 120, justify = "LEFT" },
    }
    if GLOG and GLOG.CanModifyGuildData and GLOG.CanModifyGuildData() then
        cols[#cols+1] = { key = "act", title = Tr("lbl_actions") or "Actions", vsep=true, min = 72 }
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
        r.btnCrown = UI.IconButton(f.act, nil, { skin="panel", atlas=true, atlasName=ICON_MAIN_ATLAS, size=24, fit=true, pad=3, tooltip = Tr("tip_set_main") or "Confirmer en main" })
    -- Chevron = assign as Alt to selected Main (square with classic panel background)
    r.btnAlt   = UI.IconButton(f.act, nil, { skin="panel", atlas=true, atlasName="uitools-icon-chevron-right", size=24, fit=true, pad=3, tooltip=Tr("tip_assign_alt") or "Associer en alt au main sélectionné" })
        UI.AttachRowRight(f.act, { r.btnCrown, r.btnAlt }, 4, -4, { leftPad=4, align="center" })
    end
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
    local gm = GLOG and GLOG.CanModifyGuildData and GLOG.CanModifyGuildData()
        if r.btnCrown then r.btnCrown:SetShown(gm) end
        if r.btnAlt then r.btnAlt:SetShown(gm) end
    if r.btnCrown then
        -- Online restriction removed: keep button active for GMs and show tooltip always
        if UI and UI.SetButtonAlpha then UI.SetButtonAlpha(r.btnCrown, gm and 1 or 0.4) end
        if UI and UI.SetTooltip then
            local base = Tr("tip_set_main") or "Confirmer en main"
            UI.SetTooltip(r.btnCrown, base)
        end
        r.btnCrown:SetOnClick(function()
            if not gm then return end
            GLOG.SetAsMain(data.name)
            if _removeFromPoolByName(data.name) then
                if lvPool and lvPool.SetData then lvPool:SetData(poolDataCache); lvPool:Layout() end
            end
            -- update mains list; alts unaffected
            if lvMains and lvMains.SetData then lvMains:SetData(buildMainsData()); lvMains:Layout() end
        end)
    end

    if r.btnAlt then
        -- If no main selected, keep button soft-disabled (alpha) but still show tooltip
        local can = (selectedMainName and selectedMainName ~= "") and true or false
        if UI and UI.SetButtonAlpha then UI.SetButtonAlpha(r.btnAlt, can and 1 or 0.4) end
        if UI and UI.SetTooltip then
            local base = Tr("tip_assign_alt") or "Associer en alt au main sélectionné"
            if can then UI.SetTooltip(r.btnAlt, base)
            else UI.SetTooltip(r.btnAlt, base .. "\n|cffaaaaaa" .. (Tr("lbl_main_prefix") or "Main: ") .. (Tr("value_empty") or "—") .. "|r") end
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
local function _BuildMainsCols()
    local cols = {
        { key = "name",  title = Tr("lbl_mains") or "Mains", flex = 1, min = 100 },
        { key = "alias", title = Tr("lbl_alias") or "Alias", vsep=true,w = 100, justify = "LEFT" },
        { key = "solde", title = Tr("col_balance") or "Solde", vsep=true,w = 80, justify = "RIGHT" },
    }
    if GLOG and GLOG.CanModifyGuildData and GLOG.CanModifyGuildData() then
        -- Width depends on whether editor toggle is available to this user
        local canGrant = (GLOG.CanGrantEditor and GLOG.CanGrantEditor()) or false
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
    local canGrant = (GLOG and GLOG.CanGrantEditor and GLOG.CanGrantEditor()) or false
    if gm then
        f.act  = CreateFrame("Frame", nil, r); f.act:SetHeight(UI.ROW_H)
        r.btnAlias = UI.IconButton(f.act, nil, { skin="panel", atlas=true, atlasName=ICON_ALIAS_ATLAS, size=24, fit=true, pad=5, tooltip = "Définir un alias" })
        r.btnDel   = UI.IconButton(f.act, nil, { skin="panel", atlas=true, atlasName=ICON_CLOSE_ATLAS, size=24, fit=true, pad=5, tooltip=Tr("tip_remove_main") or "Supprimer" })
        -- Editor toggle: create only if user has grant rights; avoids empty space reservation
        if canGrant then
            r.btnEditorGrant  = UI.IconButton(f.act, nil, { skin="panel", atlas=true, atlasName=ICON_EDITOR_GRANT_TEX, size=24, fit=true, pad=5, tooltip = Tr("tip_grant_editor") or "Accorder droits d'édition" })
            r.btnEditorRevoke = UI.IconButton(f.act, nil, { skin="panel", atlas=true, atlasName=ICON_EDITOR_REVOKE_TEX, size=24, fit=true, pad=5, tooltip = Tr("tip_revoke_editor") or "Retirer droits d'édition" })
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
    if r.btnEditorGrant then r.btnEditorGrant:SetShown(GLOG and GLOG.CanGrantEditor and GLOG.CanGrantEditor()) end
    if r.btnEditorRevoke then r.btnEditorRevoke:SetShown(GLOG and GLOG.CanGrantEditor and GLOG.CanGrantEditor()) end
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
    local canGrant = (GLOG and GLOG.CanGrantEditor and GLOG.CanGrantEditor()) or false
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
            local base = (Tr("tip_grant_editor") or "Accorder droits d'édition")
            local statusCtx = Tr("tip_editor_status_demoted") or "Actuellement rétrogradé"
            if enableGrant then
                UI.SetTooltip(r.btnEditorGrant, base .. "\n|cffaaaaaa" .. statusCtx .. "|r")
            else
                local why = Tr("tip_disabled_offline_group") or "Désactivé : aucun personnage de ce joueur n'est en ligne"
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
            local base = (Tr("tip_revoke_editor") or "Retirer droits d'édition")
            local statusCtx = Tr("tip_editor_status_promoted") or "Actuellement promu"
            if enableRevoke then
                UI.SetTooltip(r.btnEditorRevoke, base .. "\n|cffaaaaaa" .. statusCtx .. "|r")
            else
                local why = Tr("tip_disabled_offline_group") or "Désactivé : aucun personnage de ce joueur n'est en ligne"
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
        -- Online restriction removed for removing a main; always available to authorized users
        if UI and UI.SetButtonAlpha then UI.SetButtonAlpha(r.btnDel, 1) end
        if UI and UI.SetTooltip then
            local base = Tr("tip_remove_main") or "Supprimer"
            UI.SetTooltip(r.btnDel, base)
        end
        r.btnDel:SetOnClick(function()
            if selectedMainName and GLOG.SamePlayer and GLOG.SamePlayer(selectedMainName, data.name) then
                selectedMainName = nil
            end
            GLOG.RemoveMain(data.name)
            _refreshAll()
        end)
    end
    if r.btnAlias then
        r.btnAlias:SetOnClick(function()
            local target = data.name
            if not target or target == "" then return end
            -- Préremplir avec le nom du joueur (sans royaume)
            local base = tostring(target):match("^([^%-]+)") or tostring(target)
            UI.PopupPromptText(Tr("popup_set_alias_title") or "Définir alias", Tr("lbl_alias") or "Alias", function(val)
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
        r.btnPromote = UI.IconButton(f.act, nil, { skin="panel", atlas=true, atlasName=ICON_MAIN_ATLAS, size=24, fit=true, pad=3, tooltip = Tr("tip_set_main") or "Confirmer en main" })
        r.btnAlias   = UI.IconButton(f.act, nil, { skin="panel", atlas=true, atlasName=ICON_ALIAS_ATLAS, size=24, fit=true, pad=5, tooltip = "Définir un alias" })
        r.btnDel     = UI.IconButton(f.act, nil, { skin="panel", atlas=true, atlasName=ICON_CLOSE_ATLAS, size=24, fit=true, pad=5, tooltip=Tr("tip_unassign_alt") or "Dissocier" })
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
        if UI and UI.SetNameTagShortEx then
            UI.SetNameTagShortEx(f.name, data.name or "", cls)
        else
            UI.SetNameTagShort(f.name, data.name or "")
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
            local base = Tr("tip_set_main") or "Confirmer en main"
            UI.SetTooltip(r.btnPromote, base)
        end
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
    if r.btnAlias then
        r.btnAlias:SetOnClick(function()
            local target = data.name
            if not target or target == "" then return end
            -- Alias is stored on the group (main). Editing from an alt edits the main group's alias.
            local base = tostring(target):match("^([^%-]+)") or tostring(target)
            UI.PopupPromptText(Tr("popup_set_alias_title") or "Définir alias", Tr("lbl_alias") or "Alias", function(val)
                if GLOG.GM_SetAlias then GLOG.GM_SetAlias(target, val) end
            end, { default = base, strata = "FULLSCREEN_DIALOG" })
        end)
    end
end

-- ===== Refresh data builders =====
function buildPoolData()
    local rows = {}
    local pool = (GLOG.GetUnassignedPool and GLOG.GetUnassignedPool()) or {}
    -- Build robust suggestions lookup by normalized name
    local suggestions = {}
    if selectedMainName and GLOG.SuggestAltsForMain then
        for _, r in ipairs(GLOG.SuggestAltsForMain(selectedMainName) or {}) do
            local nk = (GLOG and GLOG.NormName and GLOG.NormName(r.name)) or string.lower(r.name or "")
            if nk and nk ~= "" then suggestions[nk] = true end
        end
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

    UI.SectionHeader(leftPane, Tr("lbl_available_pool"))
    lvPool  = UI.ListView(leftPane,  _BuildPoolCols(),  { buildRow = BuildRowPool,  updateRow = UpdateRowPool,  topOffset = UI.SECTION_HEADER_H or 26 })

    UI.SectionHeader(midPane,  Tr("lbl_mains"))
    lvMains = UI.ListView(midPane,  _BuildMainsCols(), { buildRow = BuildRowMains, updateRow = UpdateRowMains, topOffset = UI.SECTION_HEADER_H or 26 })

    do
        local _, fs = UI.SectionHeader(rightPane, Tr("lbl_associated_alts2"))
        rightPane._sectionHeaderFS = fs
    end
    lvAlts  = UI.ListView(rightPane, _BuildAltsCols(), { buildRow = BuildRowAlts,  updateRow = UpdateRowAlts,  topOffset = UI.SECTION_HEADER_H or 26 })

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
            rightPane._sectionHeaderFS:SetText((Tr("lbl_main_prefix") or "Main: ") .. (selectedMainName or ""))
        else
            rightPane._sectionHeaderFS:SetText(Tr("lbl_associated_alts2"))
        end
    end
end

-- (dynamic SectionHeader FontString captured during Build)

UI.RegisterTab(Tr("tab_main_alt") or "Main/Alt", Build, Refresh, Layout, {
    category = Tr("cat_guild"),
})
