local ADDON, ns = ...
local Tr = ns and ns.Tr
local UI = ns and ns.UI
local GLOG = ns and ns.GLOG

-- DynamicTable-powered Roster (Active + Reserve categories)
local panel, footer, dt
local totalFS, resourceFS, sepFS, bothFS, bankLeftFS, bankSepFS, bankRightFS

-- Helpers
local function _HasGuild()
    return (IsInGuild and IsInGuild()) and true or false
end

local function FindGuildInfo(playerName)
    return (GLOG and GLOG.GetMainAggregatedInfo and GLOG.GetMainAggregatedInfo(playerName or "")) or {}
end

local function CanActOn(name)
    local isMaster = (GLOG and GLOG.CanModifyGuildData and GLOG.CanModifyGuildData()) or false
    if isMaster then return true, true end
    local meFull = ns and ns.Util and ns.Util.playerFullName and ns.Util.playerFullName()
    local isSelf = ns and ns.Util and ns.Util.SamePlayer and ns.Util.SamePlayer(name, meFull)
    return isSelf, isMaster
end

-- Build a full name (Name-Realm) for roster operations
local function EnsureFullName(name)
    local m = tostring(name or "")
    if m == "" then return m end
    if m:find("-", 1, true) then
        return (ns and ns.Util and ns.Util.CleanFullName and ns.Util.CleanFullName(m)) or m
    end
    if ns and ns.GLOG and ns.GLOG.ResolveFullNameStrict then
        local full = ns.GLOG.ResolveFullNameStrict(m)
        if full then return full end
    end
    return m
end

-- Lazy guild membership set to detect out-of-guild players
local _guildSet, _guildSetTs
local function _RebuildGuildSet()
    _guildSet = {}
    local rows = (GLOG and GLOG.GetGuildRowsCached and GLOG.GetGuildRowsCached()) or {}
    for _, r in ipairs(rows) do
        local amb = r.name_amb or r.name_raw
        local k = amb and (GLOG.NormName and GLOG.NormName(amb)) or nil
        if k and k ~= "" then _guildSet[k] = true end
    end
    _guildSetTs = GetTime and GetTime() or (time and time()) or 0
end
local function _IsOutOfGuild(name)
    if not _guildSet or not _guildSetTs or ((_guildSetTs + 30) < ((GetTime and GetTime()) or (time and time()) or 0)) then
        _RebuildGuildSet()
    end
    local k = name and (GLOG and GLOG.NormName and GLOG.NormName(name)) or nil
    if not k or k == "" then return false end
    return not (_guildSet[k] == true)
end

local function _money(v)
    v = tonumber(v) or 0
    return (UI and UI.MoneyText) and UI.MoneyText(v) or tostring(v)
end

-- Online-first then alpha
local function _SortOnlineFirst(arr)
    if not arr or #arr == 0 then return end
    table.sort(arr, function(a, b)
        local na = (a.name or ""):lower()
        local nb = (b.name or ""):lower()
        local giA = FindGuildInfo(a.name) or {}
        local giB = FindGuildInfo(b.name) or {}
        local oa  = giA.online and 1 or 0
        local ob  = giB.online and 1 or 0
        if oa ~= ob then return oa > ob end
        return na < nb
    end)
end

-- Actions wiring
local function AttachDepositHandler(btn, name, canAct, isMaster)
    if not btn then return end
    btn:SetOnClick(function()
        if not canAct then return end
        if not (UI and UI.PopupPromptNumber) then return end
        UI.PopupPromptNumber(Tr("prefix_add_gold_to")..(name or ""), Tr("lbl_total_amount_gold_alt"), function(amt)
            amt = math.floor(tonumber(amt) or 0)
            if amt > 0 then
                if isMaster and GLOG and GLOG.GM_AdjustAndBroadcast then GLOG.GM_AdjustAndBroadcast(name, amt)
                elseif GLOG and GLOG.RequestAdjust then GLOG.RequestAdjust(name, amt) end
            end
        end)
    end)
end
local function AttachWithdrawHandler(btn, name, canAct, isMaster)
    if not btn then return end
    btn:SetOnClick(function()
        if not canAct then return end
        if not (UI and UI.PopupPromptNumber) then return end
        UI.PopupPromptNumber(Tr("prefix_remove_gold_from")..(name or ""), Tr("lbl_total_amount_gold_alt"), function(amt)
            amt = math.floor(tonumber(amt) or 0)
            if amt > 0 then
                local delta = -amt
                if isMaster and GLOG and GLOG.GM_AdjustAndBroadcast then GLOG.GM_AdjustAndBroadcast(name, delta)
                elseif GLOG and GLOG.RequestAdjust then GLOG.RequestAdjust(name, delta) end
            end
        end)
    end)
end

-- Columns
local function BuildColumns()
    return UI.NormalizeColumns({
        { key = "alias",  title = Tr("col_alias"),       w = 90,  justify = "LEFT",   vsep = true,  sortValue = "alias" },
        { key = "lvl",    title = Tr("col_level_short"), w = 44,  justify = "CENTER", vsep = true,  sortNumeric = true, sortValue = "lvl" },
        { key = "name",   title = Tr("col_name"),        flex = 1, min = 160, justify = "LEFT",  vsep = true,
          buildCell = function(parent) return UI.CreateNameTag(parent) end,
          updateCell = function(cell, v)
              local full = type(v) == 'table' and v.text or v
              if UI and UI.SetNameTagShort then UI.SetNameTagShort(cell, full or "") else if cell and cell.SetText then cell:SetText(full or "") end end
              local altShort = type(v) == 'table' and v.alt or nil
              if altShort and altShort ~= "" and cell and cell.text and cell.text.GetText then
                  local baseText = cell.text:GetText() or ""
                  local altPart = (" |cffaaaaaa( %s )|r"):format(altShort)
                  cell.text:SetText(baseText .. altPart)
              end
          end
        },
        { key = "act",    title = "",                   w = 240, justify = "CENTER", vsep = true, sortable = false,
          buildCell = function(parent)
              local host = CreateFrame("Frame", nil, parent)
              host:SetHeight(UI.ROW_H)
              host.btnDeposit  = UI.Button(host, Tr("btn_deposit_gold"),  { size="sm", minWidth=60 })
              host.btnWithdraw = UI.Button(host, Tr("btn_withdraw_gold"), { size="sm", variant="ghost", minWidth=60 })
              host.btnRoster   = UI.Button(host, Tr("btn_add_to_roster"), { size="sm", variant="ghost", minWidth=110 })
              host.btnDelete   = UI.Button(host, Tr("btn_delete"), { size="xs", variant="danger", minWidth=60 })
              if UI.AttachRowRight then UI.AttachRowRight(host, { host.btnDeposit, host.btnWithdraw, host.btnRoster, host.btnDelete }, 8, -4, { leftPad = 8, align = "center" }) end
              return host
          end,
          updateCell = function(cell, v, row)
              -- Special action row at end of Out-of-Guild category: show a single "Add player" button
              local rowKey = (row and row.key) or (cell and cell._rowData and cell._rowData.key) or nil
              if rowKey == "__add_external__" then
                  -- Hide deposit/withdraw and repurpose the roster button as "Add player"
                  if cell.btnDeposit then cell.btnDeposit:Hide() end
                  if cell.btnWithdraw then cell.btnWithdraw:Hide() end
                  if cell.btnDelete then cell.btnDelete:Hide() end
                  local btn = cell.btnRoster
                  if btn then
                      local isGM = (GLOG and GLOG.CanModifyGuildData and GLOG.CanModifyGuildData()) or false
                      btn:SetText(Tr("btn_add_player"))
                      if btn.SetVariant then btn:SetVariant("primary") end
                      btn:SetShown(isGM)
                      if isGM then
                          btn:SetOnClick(function()
                              UI.PopupPromptText(Tr("btn_add_player"), Tr("prompt_external_player_name"), function(name)
                                  name = tostring(name or ""):gsub("^%s+"," "):gsub("%s+$","")
                                  if name == "" then return end
                                  -- Add localized external realm suffix if not provided
                                  if not string.find(name, "-", 1, true) then
                                      local ext = (Tr and Tr("realm_external")) or "External"
                                      name = name .. "-" .. tostring(ext or "External")
                                  end
                                  if GLOG and GLOG.AddPlayer and GLOG.AddPlayer(name) then
                                      if ns and ns.RefreshActive then ns.RefreshActive() elseif ns and ns.RefreshAll then ns.RefreshAll() end
                                  end
                              end, { width = 460 })
                          end)
                      end
                      if cell._applyRowActionsLayout then cell._applyRowActionsLayout() end
                  end
                  return
              end
              -- row.key is full name
              local name = row and row.key or (type(v) == 'string' and v) or nil
              if not name then return end
              local isSelf, isMaster = CanActOn(name)
              local canAct = isMaster or isSelf
              if cell.btnDeposit then cell.btnDeposit:SetShown(canAct); AttachDepositHandler(cell.btnDeposit, name, canAct, isMaster) end
              if cell.btnWithdraw then cell.btnWithdraw:SetShown(canAct); AttachWithdrawHandler(cell.btnWithdraw, name, canAct, isMaster) end

              -- GM-only roster toggle (moved from Gestion → Roster)
              local btn = cell.btnRoster
              if btn then
                  local canGM = isMaster and true or false
                  -- Hide toggle for out-of-guild entries (same rule as Gestion)
                  local outGuild = _IsOutOfGuild(name)
                  if not canGM or outGuild then
                      btn:Hide()
                  else
                      btn:Show()
                      local fullName = EnsureFullName(name)
                      local isReserved = (GLOG and GLOG.IsReserved and (GLOG.IsReserved(fullName) or GLOG.IsReserved(name))) or false
                      local inRoster  = ((GLOG and GLOG.HasPlayer and (GLOG.HasPlayer(fullName) or GLOG.HasPlayer(name))) and not isReserved) or false
                      if not inRoster then
                          btn:SetText(Tr("btn_add_to_roster"))
                          btn:SetOnClick(function()
                              if GLOG and GLOG.GM_SetReserved then GLOG.GM_SetReserved(fullName, false)
                              elseif GLOG and GLOG.SetReserve then GLOG.SetReserve(fullName, false) end
                              if ns and ns.RefreshActive then ns.RefreshActive() elseif ns and ns.RefreshAll then ns.RefreshAll() end
                          end)
                      else
                          btn:SetText(Tr("btn_remove_from_roster"))
                          btn:SetOnClick(function()
                              if GLOG and GLOG.GM_SetReserved then GLOG.GM_SetReserved(fullName, true)
                              elseif GLOG and GLOG.SetReserve then GLOG.SetReserve(fullName, true) end
                              if ns and ns.RefreshActive then ns.RefreshActive() elseif ns and ns.RefreshAll then ns.RefreshAll() end
                          end)
                      end
                  end
              end

              -- Delete button for out-of-guild players (GM only)
              if cell.btnDelete then
                  local fullName = EnsureFullName(name)
                  local outGuild = _IsOutOfGuild(name)
                  local showDel = outGuild and ((GLOG and GLOG.CanModifyGuildData and GLOG.CanModifyGuildData()) or false)
                  cell.btnDelete:SetShown(showDel)
                  if showDel then
                      cell.btnDelete:SetText(Tr("btn_delete") or "Supprimer")
                      cell.btnDelete:SetOnClick(function()
                          UI.PopupConfirm(Tr("confirm_delete") or "Supprimer ?", function()
                              if GLOG then
                                  -- Mapping-aware deletion:
                                  -- 1) If this is an ALT, unlink it from its main first
                                  if GLOG.IsAlt and GLOG.IsAlt(fullName) then
                                      if GLOG.UnassignAlt then GLOG.UnassignAlt(fullName) end
                                  else
                                      -- 2) If this is a MAIN with a manual link, remove the MAIN mapping first
                                      local hasLink = GLOG.HasManualLink and GLOG.HasManualLink(fullName)
                                      local mainOf  = GLOG.GetMainOf and GLOG.GetMainOf(fullName) or fullName
                                      local isMain  = (type(mainOf) == "string" and (GLOG.SamePlayer and GLOG.SamePlayer(mainOf, fullName))) or (mainOf == fullName)
                                      if hasLink and isMain and GLOG.RemoveMain then
                                          GLOG.RemoveMain(fullName)
                                      end
                                  end
                                  if GLOG.RemovePlayer then GLOG.RemovePlayer(fullName) end
                              end
                              if ns and ns.RefreshActive then ns.RefreshActive() elseif ns and ns.RefreshAll then ns.RefreshAll() end
                          end, nil, { strata = "FULLSCREEN_DIALOG", enforceAction = true })
                      end)
                  end
              end
              if cell._applyRowActionsLayout then cell._applyRowActionsLayout() end
          end
        },
        { key = "solde",  title = Tr("col_balance"),    w = 100, justify = "RIGHT",  vsep = true,  sortNumeric = true,
          sortValue = function(row)
              local v = row and row.cells and row.cells.solde
              return tonumber(v or 0) or 0
          end,
          buildCell = function(parent)
              local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
              if fs.SetJustifyH then fs:SetJustifyH("RIGHT") end
              return fs
          end,
          updateCell = function(cell, v)
              cell:SetText(_money(v))
          end
        },
    })
end

local function BuildRows()
    local active  = (GLOG and GLOG.GetPlayersArrayActive  and GLOG.GetPlayersArrayActive())  or {}
    local reserve = (GLOG and GLOG.GetPlayersArrayReserve and GLOG.GetPlayersArrayReserve({ showHidden = true, cutoffDays = 30 })) or {}
    _SortOnlineFirst(active); _SortOnlineFirst(reserve)

    local total = 0
    local function rowOf(it)
        local gi = FindGuildInfo(it.name)
        local lvl = tonumber(gi and gi.level or 0) or 0
        local alias = (GLOG and GLOG.GetAliasFor and GLOG.GetAliasFor(it.name)) or ""
        if not alias or alias == "" then alias = (tostring(it.name):match("^([^%-]+)") or tostring(it.name) or "") end
        local altShort
        if gi and gi.onlineAltBase then
            altShort = (ns and ns.Util and ns.Util.ShortenFullName and ns.Util.ShortenFullName(gi.onlineAltFull or gi.onlineAltBase)) or gi.onlineAltBase
        end
        local bal = tonumber(it.solde) or (GLOG and GLOG.GetSolde and GLOG.GetSolde(it.name)) or 0
        total = total + (tonumber(bal) or 0)
        return {
            key = it.name,
            cells = {
                alias = alias,
                lvl   = lvl,
                name  = { text = it.name, alt = altShort, sig = tostring(it.name or "") .. "|" .. tostring(altShort or "") },
                act   = it.name,
                solde = tonumber(bal) or 0,
            },
        }
    end

    -- Build Active/Reserve with only guild members
    local catA = { key = "__cat_active",  isCategory = true, expanded = true,  title = Tr and Tr("lbl_active_roster")    or "Active roster",   children = {}, count = 0 }
    local catR = { key = "__cat_reserve", isCategory = true, expanded = true,  title = Tr and Tr("lbl_reserved_players") or "Reserved players", children = {}, count = 0 }
    for i = 1, #active do
        local it = active[i]
        if not _IsOutOfGuild(it.name) then catA.children[#catA.children+1] = rowOf(it) end
    end
    catA.count = #catA.children
    for i = 1, #reserve do
        local it = reserve[i]
        if not _IsOutOfGuild(it.name) then catR.children[#catR.children+1] = rowOf(it) end
    end
    catR.count = #catR.children

    -- Out-of-guild category: any player in DB not present in guild
    local seen = {}
    for i = 1, #catA.children do seen[catA.children[i].key] = true end
    for i = 1, #catR.children do seen[catR.children[i].key] = true end

    local outs = {}
    do
        local arr = (GLOG and GLOG.GetPlayersArray and GLOG.GetPlayersArray()) or {}
        for _, rec in ipairs(arr) do
            local n = rec.name
            if n and _IsOutOfGuild(n) and not seen[n] then
                outs[#outs+1] = rec
            end
        end
        table.sort(outs, function(a,b) return tostring(a.name):lower() < tostring(b.name):lower() end)
    end

    local catO = { key = "__cat_outguild", isCategory = true, expanded = true,
        title = (Tr and (Tr("lbl_out_of_guild_short") or Tr("lbl_out_of_guild"))) or "Out of guild",
        children = {}, count = 0 }
    for i = 1, #outs do catO.children[#catO.children+1] = rowOf(outs[i]) end
    -- Append special action row with Add Player button (no impact on totals)
    catO.children[#catO.children+1] = {
        key = "__add_external__",
        cells = {
            alias = "",
            lvl   = "",
            name  = { text = "", sig = "__add_external__" },
            act   = "__add_external__",
            solde = 0,
        },
    }
    catO.count = #catO.children

    return { catA, catR, catO }, total
end

local function _applyTotals(total, rcopper)
    if totalFS then totalFS:SetText("|cffffd200"..(Tr and Tr("lbl_total_balance") or "Total").." :|r " .. _money(total)) end
    rcopper = rcopper or (GLOG and GLOG.Resources_TotalAvailableCopper and (GLOG.Resources_TotalAvailableCopper() or 0)) or 0
    if resourceFS then resourceFS:SetText("|cffffd200"..(Tr and Tr("lbl_total_resources") or "Resources").." :|r " .. _money(rcopper/10000)) end
    if bothFS then
        local combinedGold = (tonumber(total) or 0) - (rcopper / 10000)
        bothFS:SetText("|cffffd200"..(Tr and Tr("lbl_total_both") or "Remaining").." :|r " .. _money(combinedGold))
    end
    if bankRightFS and bankLeftFS then
        local bankCopper = GLOG and GLOG.GetGuildBankBalanceCopper and GLOG.GetGuildBankBalanceCopper() or nil
        local combinedGold = (tonumber(total) or 0) - (rcopper / 10000)
        local xTxt, yTxt
        if bankCopper == nil then
            local nd = "|cffaaaaaa"..((Tr and Tr("no_data")) or "No data").."|r"
            xTxt, yTxt = nd, nd
        else
            local bankGold   = bankCopper / 10000
            local equilibrium = (bankGold or 0) - (combinedGold or 0)
            xTxt = (UI and UI.MoneyText and UI.MoneyText(bankGold)) or tostring(math.floor(bankGold + 0.5)).." po"
            local base = (UI and UI.MoneyText) and UI.MoneyText(equilibrium) or (tostring(math.floor(equilibrium + 0.5)).." po")
            if equilibrium and equilibrium > 0 then yTxt = "|cff40ff40"..base.."|r" else yTxt = base end
        end
        local orange, reset = "|cffffd200", "|r"
        bankLeftFS:SetText(orange..((Tr and Tr("lbl_bank_balance")) or "Bank balance").." :"..reset.." "..xTxt)
        if (bankCopper == nil) and UI and UI.SetTooltip then
            local hint = (Tr and Tr("hint_open_gbank_to_update")) or "Open the guild bank to update this value"
            UI.SetTooltip(bankLeftFS, hint); UI.SetTooltip(bankRightFS, hint)
        else
            if bankLeftFS.SetScript then bankLeftFS:SetScript("OnEnter", nil); bankLeftFS:SetScript("OnLeave", nil) end
            if bankRightFS.SetScript then bankRightFS:SetScript("OnEnter", nil); bankRightFS:SetScript("OnLeave", nil) end
        end
        bankRightFS:SetText(orange..((Tr and Tr("lbl_equilibrium")) or "Equilibrium").." :"..reset.." "..yTxt)
    end
end

local function _DoRefresh()
    if not dt then return end
    if not _HasGuild() then
        -- When out of guild, this tab is hidden by gating; keep data empty silently
        if dt.SetData then dt:SetData({}) end
        _applyTotals(0, 0)
        return
    end
    local rows, total = BuildRows()
    if dt.DiffAndApply then dt:DiffAndApply(rows) else dt:SetData(rows) end
    _applyTotals(total)
end

local function Refresh()
    if ns and ns.Util and ns.Util.Debounce then
        ns.Util.Debounce("roster:dyntable", 0.12, _DoRefresh)
    else
        _DoRefresh()
    end
end

local function Build(container)
    panel, footer = UI.CreateMainContainer(container, { footer = true })

    local cols = BuildColumns()
    dt = UI.DynamicTable(panel, cols, { reserveScrollbarGutter = true, headerBGColor = {0.10, 0.10, 0.10, 1.0} })

    -- Attach to LiveCellUpdater for targeted solde/reserve updates
    if ns and ns.LiveCellUpdater and ns.LiveCellUpdater.AttachInstance then
        ns.LiveCellUpdater.AttachInstance("roster", dt)
    end

    -- Footer counters
    totalFS = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); totalFS:SetPoint("LEFT", footer, "LEFT", UI.OUTER_PAD, 0)
    resourceFS = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); resourceFS:SetPoint("LEFT", totalFS, "RIGHT", 24, 0)
    sepFS = footer:CreateFontString(nil, "OVERLAY", "GameFontDisable"); sepFS:SetPoint("LEFT", resourceFS, "RIGHT", 16, 0); sepFS:SetText("|")
    bothFS = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); bothFS:SetPoint("LEFT", sepFS, "RIGHT", 16, 0)
    bankRightFS = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); bankRightFS:SetPoint("RIGHT", footer, "RIGHT", - (UI.FOOTER_RIGHT_PAD or 8), 0); bankRightFS:SetJustifyH("RIGHT")
    bankSepFS = footer:CreateFontString(nil, "OVERLAY", "GameFontDisable"); bankSepFS:SetPoint("RIGHT", bankRightFS, "LEFT", -16, 0); bankSepFS:SetText("|")
    bankLeftFS = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlight"); bankLeftFS:SetPoint("RIGHT", bankSepFS, "LEFT", -16, 0); bankLeftFS:SetJustifyH("RIGHT")

    -- No-guild message removed from Raids; message is handled in Guild tab

    Refresh()

    -- Events: roster/group changes → refresh; reserve toggle → refresh; bank updates → footer refresh
    local function _throttled()
        if UI and UI.ShouldRefreshUI and not UI.ShouldRefreshUI() then return end
        if panel and panel.IsShown and (not panel:IsShown()) then return end
        Refresh()
    end
    ns.Events.Register("GUILD_ROSTER_UPDATE", "roster-dyntable", _throttled)
    ns.Events.Register("GROUP_ROSTER_UPDATE",  "roster-dyntable", _throttled)
    -- React to Main/Alt mapping changes (assign/unassign/promote/remove): refresh roster view
    if ns and ns.On then
        ns.On("mainalt:changed", function()
            _throttled()
        end)
    end
    if GLOG and GLOG.On then
        GLOG.On("mainalt:changed", function()
            _throttled()
        end)
    end
    if ns and ns.On then
        ns.On("roster:reserve", function()
            -- If LiveCellUpdater is wired, it already relocates rows; avoid full rebuild
            if ns and ns.LiveCellUpdater and ns.LiveCellUpdater.AttachInstance then
                return
            end
            _throttled()
        end)
    end
    -- Lightweight footer-only refresh when only totals changed
    local function _refreshTotalsOnly()
        if UI and UI.ShouldRefreshUI and not UI.ShouldRefreshUI() then return end
        if not dt or not dt._rawData then return end
        -- Recompute totals based on current rows to avoid full rebuild
        local total = 0
        local function addFrom(cat)
            if not cat or not cat.children then return end
            for i = 1, #cat.children do
                local r = cat.children[i]
                if r and r.key then
                    -- Use authoritative balance for accuracy
                    local bal = (GLOG and GLOG.GetSolde and GLOG.GetSolde(r.key)) or 0
                    total = total + (tonumber(bal) or 0)
                end
            end
        end
        local raw = dt._rawData or {}
        if #raw > 0 and raw[1] and raw[1].isCategory then
            for i = 1, #raw do addFrom(raw[i]) end
        else
            for i = 1, #raw do
                local r = raw[i]
                if r and r.key then
                    local bal = (GLOG and GLOG.GetSolde and GLOG.GetSolde(r.key)) or 0
                    total = total + (tonumber(bal) or 0)
                end
            end
        end
        _applyTotals(total)
    end
    if GLOG and GLOG.On then
        GLOG.On("guildbank:updated", function() _refreshTotalsOnly() end)
    end
    if ns and ns.On then
        ns.On("roster:balance", function() _refreshTotalsOnly() end)
    end
end

local function Layout() end

UI.RegisterTab(Tr("tab_roster"), Build, Refresh, Layout, { category = Tr("cat_raids") })
