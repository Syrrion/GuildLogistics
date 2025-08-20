local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns.GLOG, ns.UI
local PAD, SBW, GUT = UI.OUTER_PAD, UI.SCROLLBAR_W, UI.GUTTER

local panel, lvActive, lvReserve, activeArea, reserveArea, footer, totalFS

local cols = UI.NormalizeColumns({
    { key="lvl",    title=Tr("col_level_short"),    w=44, justify="CENTER" },
    { key="name",   title=Tr("col_name"),    min=180, flex=1 },
    { key="ilvl",   title=Tr("col_ilvl"),   w=64, justify="CENTER" },
    { key="mkey",   title=Tr("col_mplus_key"),    w=200, justify="LEFT" },
    { key="last",   title=Tr("col_attendance"), w=180 },
    { key="act",    title="", w=200 },
    { key="solde",  title=Tr("col_balance"),  w=80 },
})

-- Helpers
local function money(v)
    v = tonumber(v) or 0
    return (UI and UI.MoneyText) and UI.MoneyText(v) or (tostring(v).." po")
end

local function CanActOn(name)
    local isMaster = GLOG.IsMaster and GLOG.IsMaster()
    if isMaster then return true, true end
    local meFull = ns.Util.playerFullName and ns.Util.playerFullName()
    if (not meFull or meFull == "") and UnitFullName then
        local n, rlm = UnitFullName("player")
        local rn = (GetNormalizedRealmName and GetNormalizedRealmName()) or rlm
        meFull = (n and rn and rn ~= "") and (n.."-"..rn) or (n or UnitName("player"))
    end
    local isSelf = ns.Util.SamePlayer and ns.Util.SamePlayer(name, meFull)
    return isSelf, isMaster
end

local function FindGuildInfo(playerName)
    local guildRows = GLOG.GetGuildRowsCached and GLOG.GetGuildRowsCached() or {}
    for _, gr in ipairs(guildRows) do
        if GLOG.NormName and GLOG.NormName(gr.name_amb or gr.name_raw) == GLOG.NormName(playerName) then
            local info = {
                online = gr.online,
                idx = gr.idx,
                days = gr.daysDerived,
                hours = gr.hoursDerived,
            }
            if GetGuildRosterInfo and gr.idx then
                local _, _, _, level = GetGuildRosterInfo(gr.idx)
                info.level = tonumber(level)
            end
            return info
        end
    end
    return {}
end

local function GetSolde(data)
    if data.solde ~= nil then return tonumber(data.solde) or 0 end
    local cr = tonumber(data.credit) or 0
    local db = tonumber(data.debit) or 0
    return cr - db
end

-- Boutons scripts
local function AttachDepositHandler(btn, name, canAct, isMaster)
    btn:SetScript("OnClick", function()
        if not canAct then return end
        UI.PopupPromptNumber(Tr("prefix_add_gold_to")..(name or ""), Tr("lbl_total_amount_gold_alt"), function(amt)
            amt = math.floor(tonumber(amt) or 0)
            if amt > 0 then
                if isMaster then
                    if GLOG.GM_AdjustAndBroadcast then GLOG.GM_AdjustAndBroadcast(name, amt) end
                else
                    if GLOG.RequestAdjust then GLOG.RequestAdjust(name, amt) end
                end
            end
        end)
    end)
end

local function AttachWithdrawHandler(btn, name, canAct, isMaster)
    btn:SetScript("OnClick", function()
        if not canAct then return end
        UI.PopupPromptNumber(Tr("prefix_remove_gold_from")..(name or ""), Tr("lbl_total_amount_gold_alt"), function(amt)
            amt = math.floor(tonumber(amt) or 0)
            if amt > 0 then
                local delta = -amt
                if isMaster then
                    if GLOG.GM_AdjustAndBroadcast then GLOG.GM_AdjustAndBroadcast(name, delta) end
                else
                    if GLOG.RequestAdjust then GLOG.RequestAdjust(name, delta) end
                end
            end
        end)
    end)
end

local function AttachDeleteHandler(btn, name, isMaster)
    btn:SetScript("OnClick", function()
        if not isMaster then return end
        UI.PopupConfirm(Tr("prefix_delete")..(name or "").." "..Tr("lbl_from_roster_question"), function()
            if GLOG.RemovePlayer then
                GLOG.RemovePlayer(name)
            elseif GLOG.BroadcastRosterRemove then
                local uid = (GLOG.GetUID and GLOG.GetUID(name)) or nil
                GLOG.BroadcastRosterRemove(uid or name)
            end
            if ns.RefreshAll then ns.RefreshAll() end
        end)
    end)
end

-- BuildRow
local function BuildRow(r, context)
    local f = {}
    f.lvl   = UI.Label(r, { justify = "CENTER" })
    f.name  = UI.CreateNameTag(r)
    f.ilvl  = UI.Label(r, { justify = "CENTER" })
    f.mkey  = UI.Label(r, { justify = "LEFT" })
    f.last  = UI.Label(r, { justify = "CENTER" })
    f.solde = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")

    f.act = CreateFrame("Frame", nil, r)
    f.act:SetHeight(UI.ROW_H)
    f.act:SetFrameLevel(r:GetFrameLevel()+1)

    r.btnDeposit  = UI.Button(f.act, Tr("btn_deposit_gold"),   { size="sm", minWidth=90 })
    r.btnWithdraw = UI.Button(f.act, Tr("btn_withdraw_gold"), { size="sm", variant="ghost", minWidth=90 })
    r.btnDelete   = UI.Button(f.act, Tr("btn_delete_short"), { size="sm", variant="danger", minWidth=28, padX=12 })

    local buttons = { r.btnDeposit, r.btnWithdraw, r.btnDelete }

    if context == "active" then
        r.btnReserve = UI.Button(f.act, Tr("btn_to_reserve"), { size="sm", minWidth=120, tooltip=Tr("lbl_move_to_reserve")})
        table.insert(buttons, 1, r.btnReserve)
    elseif context == "reserve" then
        r.btnRoster = UI.Button(f.act, Tr("btn_to_roster"), { size="sm", minWidth=120, tooltip=Tr("lbl_move_to_roster") })
        table.insert(buttons, 1, r.btnRoster)
    end

    UI.AttachRowRight(f.act, buttons, 8, -4, { leftPad = 8, align = "center" })
    return f
end

-- UpdateRow
local function UpdateRow(i, r, f, data)
    UI.SetNameTag(f.name, data.name or "")

    local gi = FindGuildInfo(data.name)

    if f.last then
        if gi.online then
            f.last:SetText("|cff40ff40"..Tr("status_online").."|r")
        elseif gi.days or gi.hours then
            f.last:SetText(ns.Format.LastSeen(gi.days, gi.hours))
        else
            f.last:SetText("|cffaaaaaa"..Tr("status_empty").."|r")
        end
    end

    if f.lvl then
        f.lvl:SetText(gi.level and tostring(gi.level) or "")
    end

    if f.mkey then
        local mkeyTxt = (GLOG.GetMKeyText and GLOG.GetMKeyText(data.name)) or ""
        if gi.online then
            f.mkey:SetText(mkeyTxt or "")
        else
            f.mkey:SetText("|cffaaaaaa"..Tr("status_empty").."|r")
        end
    end

    if f.ilvl then
        local ilvl = (GLOG.GetIlvl and GLOG.GetIlvl(data.name)) or nil
        local txt = ""
        if gi.online then
            txt = (ilvl and ilvl > 0) and tostring(ilvl) or "|cffaaaaaa"..Tr("status_unknown").."|r"
        else
            txt = "|cffaaaaaa"..Tr("status_empty").."|r"
        end
        f.ilvl:SetText(txt)
    end

    f.solde:SetText(money(GetSolde(data)))

    local canAct, isMaster = CanActOn(data.name)

    if r.btnDeposit then
        r.btnDeposit:SetEnabled(canAct)
        r.btnDeposit:SetAlpha(canAct and 1 or 0.5)
        AttachDepositHandler(r.btnDeposit, data.name, canAct, isMaster)
    end
    if r.btnWithdraw then
        r.btnWithdraw:SetEnabled(canAct)
        r.btnWithdraw:SetAlpha(canAct and 1 or 0.5)
        AttachWithdrawHandler(r.btnWithdraw, data.name, canAct, isMaster)
    end
    if r.btnDelete then
        r.btnDelete:SetShown(isMaster)
        AttachDeleteHandler(r.btnDelete, data.name, isMaster)
    end
end

-- Layout
local function Layout()
    if not (activeArea and reserveArea) then return end
    local panelH = panel:GetHeight()
    local footerH = (UI.FOOTER_H or 36)
    local gap = 10

    local usableH = panelH - footerH - (gap * 3)
    local hTop = math.floor(usableH * 0.60)

    activeArea:ClearAllPoints()
    activeArea:SetPoint("TOPLEFT",  panel, "TOPLEFT",  UI.OUTER_PAD, -(UI.OUTER_PAD))
    activeArea:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -UI.OUTER_PAD, -(UI.OUTER_PAD))
    activeArea:SetHeight(hTop)

    reserveArea:ClearAllPoints()
    reserveArea:SetPoint("TOPLEFT",  activeArea, "BOTTOMLEFT", 0, -gap)
    reserveArea:SetPoint("TOPRIGHT", activeArea, "BOTTOMRIGHT", 0, -gap)
    reserveArea:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", UI.OUTER_PAD, (UI.FOOTER_H or 36) + gap)
    reserveArea:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -UI.OUTER_PAD, (UI.FOOTER_H or 36) + gap)

    if lvActive  and lvActive.Layout  then lvActive:Layout()  end
    if lvReserve and lvReserve.Layout then lvReserve:Layout() end
end

-- Refresh
local function Refresh()
    local active  = (GLOG.GetPlayersArrayActive  and GLOG.GetPlayersArrayActive())  or {}
    local reserve = (GLOG.GetPlayersArrayReserve and GLOG.GetPlayersArrayReserve()) or {}

    if lvActive  then lvActive:SetData(active) end
    if lvReserve then
        local wrapped = {}
        for i, it in ipairs(reserve) do wrapped[i] = { data = it, fromReserve = true } end
        lvReserve:SetData(wrapped)
    end

    local total = 0
    for _, it in ipairs(active)  do total = total + (tonumber(it.solde) or 0) end
    for _, it in ipairs(reserve) do total = total + (tonumber(it.solde) or 0) end
    if totalFS then
        local txt = (UI and UI.MoneyText) and UI.MoneyText(total) or (tostring(total).." po")
        totalFS:SetText("|cffffd200"..Tr("lbl_total_balance").." :|r " .. txt)
    end
end

-- Footer
local function BuildFooterButtons(footer, isGM)
    local btnAdd   = UI.Button(footer, Tr("btn_add_player"), { size="sm", variant="primary", minWidth=120 })
    local btnGuild = UI.Button(footer, isGM and Tr("add_guild_member") or Tr("guild_members"), { size="sm", minWidth=220 })
    local btnHist  = UI.Button(footer, Tr("btn_raids_history"), { size="sm", minWidth=160})

    btnAdd:SetOnClick(function()
        if not isGM then return end
        UI.PopupPromptText(Tr("btn_add_player"), Tr("prompt_external_player_name"), function(name)
            name = tostring(name or ""):gsub("^%s+",""):gsub("%s+$","")
            if name == "" then return end
            if GLOG.AddPlayer and GLOG.AddPlayer(name) then
                if ns.RefreshAll then ns.RefreshAll() end
            end
        end, { width = 460 })
    end)

    btnGuild:SetOnClick(function()
        if UI.ShowGuildRosterPopup then UI.ShowGuildRosterPopup() end
    end)

    btnHist:SetOnClick(function()
        UI.ShowTabByLabel(Tr("tab_history"))
    end)

    if UI.AttachButtonsFooterRight then
        UI.AttachButtonsFooterRight(footer, { btnHist, btnGuild, btnAdd })
    end

    if not isGM then btnAdd:Hide() end
    return btnAdd, btnGuild, btnHist
end

-- Build panel
local function Build(container)
    panel = container
    if UI.ApplySafeContentBounds then UI.ApplySafeContentBounds(panel) end

    activeArea  = CreateFrame("Frame", nil, panel)
    reserveArea = CreateFrame("Frame", nil, panel)

    UI.SectionHeader(activeArea,  Tr("lbl_active_roster"),      { topPad = 2 })
    UI.SectionHeader(reserveArea, Tr("lbl_reserved_players"),{ topPad = 2 })

    lvActive = UI.ListView(activeArea, cols, {
        buildRow = function(r) return BuildRow(r, "active") end,
        updateRow = function(i, r, f, it)
            UpdateRow(i, r, f, it)
            if r.btnReserve then
                local isMaster = GLOG.IsMaster and GLOG.IsMaster()
                r.btnReserve:SetShown(isMaster)
                if isMaster then
                    r.btnReserve:SetOnClick(function()
                        if GLOG.GM_SetReserved then GLOG.GM_SetReserved(it.name, true) end
                    end)
                end
            end
        end,
        topOffset = UI.SECTION_HEADER_H or 26
    })

    lvReserve = UI.ListView(reserveArea, cols, {
        buildRow = function(r) return BuildRow(r, "reserve") end,
        updateRow = function(i, r, f, it)
            local data = it.data or it
            UpdateRow(i, r, f, data)
            if r.btnRoster then
                local isMaster = GLOG.IsMaster and GLOG.IsMaster()
                r.btnRoster:SetShown(isMaster)
                if isMaster then
                    r.btnRoster:SetOnClick(function()
                        if GLOG.GM_SetReserved then GLOG.GM_SetReserved(data.name, false) end
                    end)
                end
            end
        end,
        topOffset = UI.SECTION_HEADER_H or 26,
        bottomAnchor = footer
    })

    footer = UI.CreateFooter(panel, 36)
    totalFS = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    totalFS:SetPoint("LEFT", footer, "LEFT", PAD, 0)

    local isGM = GLOG.IsMaster and GLOG.IsMaster()
    BuildFooterButtons(footer, isGM)
end

UI.RegisterTab(Tr("tab_roster"), Build, Refresh, Layout)
