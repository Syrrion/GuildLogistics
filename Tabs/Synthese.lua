local ADDON, ns = ...
local CDZ, UI = ns.CDZ, ns.UI
local PAD, SBW, GUT = UI.OUTER_PAD, UI.SCROLLBAR_W, UI.GUTTER

local panel, lvActive, lvReserve, activeArea, reserveArea, footer, totalFS

local cols = UI.NormalizeColumns({
    { key="lvl",    title="Niv",    w=44, justify="CENTER" },
    { key="name",   title="Nom",    min=150, flex=1 },
    { key="ilvl",   title="iLvl",   w=64, justify="CENTER" },
    { key="mkey",   title="Clé",    w=200, justify="LEFT" },
    { key="last",   title="Présence", w=180 },
    { key="act",    title="", w=200 },
    { key="solde",  title="Solde",  w=80 },
})

-- Helpers
local function money(v)
    v = tonumber(v) or 0
    return (UI and UI.MoneyText) and UI.MoneyText(v) or (tostring(v).." po")
end

local function CanActOn(name)
    local isMaster = CDZ.IsMaster and CDZ.IsMaster()
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
    local guildRows = CDZ.GetGuildRowsCached and CDZ.GetGuildRowsCached() or {}
    for _, gr in ipairs(guildRows) do
        if CDZ.NormName and CDZ.NormName(gr.name_amb or gr.name_raw) == CDZ.NormName(playerName) then
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
        UI.PopupPromptNumber("Ajouter de l’or à "..(name or ""), "Montant total (po) :", function(amt)
            amt = math.floor(tonumber(amt) or 0)
            if amt > 0 then
                if isMaster then
                    if CDZ.GM_AdjustAndBroadcast then CDZ.GM_AdjustAndBroadcast(name, amt) end
                else
                    if CDZ.RequestAdjust then CDZ.RequestAdjust(name, amt) end
                end
            end
        end)
    end)
end

local function AttachWithdrawHandler(btn, name, canAct, isMaster)
    btn:SetScript("OnClick", function()
        if not canAct then return end
        UI.PopupPromptNumber("Retirer de l’or à "..(name or ""), "Montant total (po) :", function(amt)
            amt = math.floor(tonumber(amt) or 0)
            if amt > 0 then
                local delta = -amt
                if isMaster then
                    if CDZ.GM_AdjustAndBroadcast then CDZ.GM_AdjustAndBroadcast(name, delta) end
                else
                    if CDZ.RequestAdjust then CDZ.RequestAdjust(name, delta) end
                end
            end
        end)
    end)
end

local function AttachDeleteHandler(btn, name, isMaster)
    btn:SetScript("OnClick", function()
        if not isMaster then return end
        UI.PopupConfirm("Supprimer "..(name or "").." du roster ?", function()
            if CDZ.RemovePlayer then
                CDZ.RemovePlayer(name)
            elseif CDZ.BroadcastRosterRemove then
                local uid = (CDZ.GetUID and CDZ.GetUID(name)) or nil
                CDZ.BroadcastRosterRemove(uid or name)
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

    r.btnDeposit  = UI.Button(f.act, "Dépôt d’or",   { size="sm", minWidth=90 })
    r.btnWithdraw = UI.Button(f.act, "Retrait d’or", { size="sm", variant="ghost", minWidth=90 })
    r.btnDelete   = UI.Button(f.act, "X",            { size="sm", variant="danger", minWidth=28, padX=12 })

    local buttons = { r.btnDeposit, r.btnWithdraw, r.btnDelete }

    if context == "active" then
        r.btnReserve = UI.Button(f.act, "> Réserve", { size="sm", minWidth=120, tooltip="Basculer ce joueur en Réserve" })
        table.insert(buttons, 1, r.btnReserve)
    elseif context == "reserve" then
        r.btnRoster = UI.Button(f.act, "> Roster", { size="sm", minWidth=120, tooltip="Renvoyer ce joueur dans le Roster actif" })
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
            f.last:SetText("|cff40ff40En ligne|r")
        elseif gi.days or gi.hours then
            f.last:SetText(ns.Format.LastSeen(gi.days, gi.hours))
        else
            f.last:SetText("|cffaaaaaa-|r")
        end
    end

    if f.lvl then
        f.lvl:SetText(gi.level and tostring(gi.level) or "")
    end

    if f.mkey then
        local mkeyTxt = (CDZ.GetMKeyText and CDZ.GetMKeyText(data.name)) or ""
        f.mkey:SetText(mkeyTxt or "")
    end

    if f.ilvl then
        local ilvl = (CDZ.GetIlvl and CDZ.GetIlvl(data.name)) or nil
        local txt = ""
        if gi.online then
            txt = (ilvl and ilvl > 0) and tostring(ilvl) or "|cffaaaaaa?|r"
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
    local active  = (CDZ.GetPlayersArrayActive  and CDZ.GetPlayersArrayActive())  or {}
    local reserve = (CDZ.GetPlayersArrayReserve and CDZ.GetPlayersArrayReserve()) or {}

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
        totalFS:SetText("|cffffd200Total soldes :|r " .. txt)
    end
end

-- Footer
local function BuildFooterButtons(footer, isGM)
    local btnAdd   = UI.Button(footer, "Ajouter un joueur", { size="sm", variant="primary", minWidth=120 })
    local btnGuild = UI.Button(footer, isGM and "Ajouter un membre de la guilde" or "Membres de la guilde", { size="sm", minWidth=220 })
    local btnHist  = UI.Button(footer, "Historique des raids", { size="sm", minWidth=160, tooltip="Voir l’historique des raids" })

    btnAdd:SetOnClick(function()
        if not isGM then return end
        UI.PopupPromptText("Ajouter un joueur", "Nom du joueur externe à inclure dans le roster", function(name)
            name = tostring(name or ""):gsub("^%s+",""):gsub("%s+$","")
            if name == "" then return end
            if CDZ.AddPlayer and CDZ.AddPlayer(name) then
                if ns.RefreshAll then ns.RefreshAll() end
            end
        end, { width = 460 })
    end)

    btnGuild:SetOnClick(function()
        if UI.ShowGuildRosterPopup then UI.ShowGuildRosterPopup() end
    end)

    btnHist:SetOnClick(function()
        UI.ShowTabByLabel("Historique")
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

    UI.SectionHeader(activeArea,  "Roster actif",      { topPad = 2 })
    UI.SectionHeader(reserveArea, "Joueurs en réserve",{ topPad = 2 })

    lvActive = UI.ListView(activeArea, cols, {
        buildRow = function(r) return BuildRow(r, "active") end,
        updateRow = function(i, r, f, it)
            UpdateRow(i, r, f, it)
            if r.btnReserve then
                local isMaster = CDZ.IsMaster and CDZ.IsMaster()
                r.btnReserve:SetShown(isMaster)
                if isMaster then
                    r.btnReserve:SetOnClick(function()
                        if CDZ.GM_SetReserved then CDZ.GM_SetReserved(it.name, true) end
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
                local isMaster = CDZ.IsMaster and CDZ.IsMaster()
                r.btnRoster:SetShown(isMaster)
                if isMaster then
                    r.btnRoster:SetOnClick(function()
                        if CDZ.GM_SetReserved then CDZ.GM_SetReserved(data.name, false) end
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

    local isGM = CDZ.IsMaster and CDZ.IsMaster()
    BuildFooterButtons(footer, isGM)
end

UI.RegisterTab("Roster", Build, Refresh, Layout)
