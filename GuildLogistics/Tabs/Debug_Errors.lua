local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI, F = ns.GLOG, ns.UI, ns.Format

-- === État local ===
local panel, footer, lv

-- Helpers : récupère la liste des rapports dans l’ordre décroissant
local function _GetErrors()
    local list
    if GLOG and GLOG.Errors_Get then
        list = GLOG.Errors_Get()
    else
        local db = (GuildLogisticsDB and GuildLogisticsDB.errors) or {}
        list = db.list or {}
    end
    local arr = {}
    for i = 1, #list do arr[i] = list[i] end
    table.sort(arr, function(a,b) return (tonumber(a.ts) or 0) > (tonumber(b.ts) or 0) end)
    return arr
end

-- Compte les erreurs non traitées (fallback si Core indispo)
local function _CountOpen()
    if GLOG and GLOG.Errors_CountOpen then return GLOG.Errors_CountOpen() end
    local list = _GetErrors()
    local n = 0
    for i=1,#list do if not (list[i].done == true) then n = n + 1 end end
    return n
end

-- Raccourci : première ligne + tronquage
local function _Preview(s, maxLen)
    s = tostring(s or "")
    local line = s:gsub("\r",""):match("([^\n]+)") or s
    line = line:gsub("%s+"," ")
    maxLen = maxLen or 160
    if #line > maxLen then line = line:sub(1, maxLen-1) .. "…" end
    return line
end

-- Popup détail + copie
local function ShowErrorPopup(item)
    local dlg = UI.CreatePopup({
        title  = Tr("tab_debug_errors"),
        width  = 780,
        height = 440,
    })

    local scroll = CreateFrame("ScrollFrame", nil, dlg.content, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", dlg.content, "TOPLEFT", 8, -8)
    scroll:SetPoint("BOTTOMRIGHT", dlg.content, "BOTTOMRIGHT", -8, 8)
    if UI.SkinScrollBar then UI.SkinScrollBar(scroll) end
    if UI.StripScrollButtons then UI.StripScrollButtons(scroll) end

    local eb = CreateFrame("EditBox", nil, scroll)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(true)
    eb:SetFontObject(ChatFontNormal)
    eb:EnableMouse(true)
    eb:SetWidth(scroll:GetWidth())
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    scroll:SetScrollChild(eb)

    local title = (GLOG and GLOG.GetAddonVersion and ("GuildLogistics v"..(GLOG.GetAddonVersion() or ""))) or "GuildLogistics"
    local body = {}
    body[#body+1] = ("[%s]  %s"):format(Tr("col_player"), tostring(item.who or "?"))
    body[#body+1] = ("[%s]  %s"):format(Tr("col_date"),   F.DateTime(item.ts, "%d/%m/%Y %H:%M:%S"))
    body[#body+1] = ("[%s]  %s"):format(Tr("col_version"), tostring(item.ver or ""))
    body[#body+1] = ("[%s]  %s"):format(Tr("col_done"), (item.done and Tr("lbl_yes")) or Tr("lbl_no"))
    body[#body+1] = ""
    body[#body+1] = ("== %s =="):format(Tr("lbl_error"))
    body[#body+1] = tostring(item.msg or "")
    body[#body+1] = ""
    body[#body+1] = ("== %s =="):format(Tr("lbl_stacktrace"))
    body[#body+1] = tostring(item.st or "")

    local text = title .. "\n" .. table.concat(body, "\n")
    eb:SetText(text)
    eb:HighlightText(0, text:len())

    dlg:SetButtons({
        { text = Tr("btn_copy"), onClick = function()
            eb:SetFocus()
            eb:HighlightText(0, eb:GetNumLetters() or 0)
        end, close = false },
        { text = Tr("btn_close"), variant = "ghost" },
    })

    dlg:Show()
end

-- ➕ Pastille (badge) = nb d'erreurs non traitées
local function UpdateBadges()
    if not UI or not UI.SetTabBadge then return end
    local count = _CountOpen()
    UI.SetTabBadge(Tr("tab_debug_errors"), count) -- cascade automatique sur la catégorie
end

-- Colonnes (ajout de la colonne "Traité" avant les actions)
local function _Columns()
    local cols = {
        { key="date",    title=Tr("col_date"),     w=160 },
        { key="player",  title=Tr("col_player"),   vsep=true, min=160 },
        { key="ver",     title=Tr("col_version"),  vsep=true, w=90, justify="CENTER" },
        { key="message", title=Tr("col_message"),  vsep=true, min=360, flex=1 },
        { key="done",    title=Tr("col_done"),     vsep=true, w=36, justify="CENTER" }, -- ✅ checkbox
        { key="act",     title="",                 vsep=true, w=120 },
    }
    return UI.NormalizeColumns(cols)
end

-- Construction d’une ligne
local function BuildRow(r)
    local f = {}
    f.date    = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.player  = UI.CreateNameTag(r)
    f.ver     = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.message = UI.Label(r, { justify="LEFT" })
    f.done    = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate") -- ✅ sans libellé

    f.act = CreateFrame("Frame", nil, r); f.act:SetHeight(UI.ROW_H); f.act:SetFrameLevel(r:GetFrameLevel()+1)
    r.btnView = UI.Button(f.act, Tr("btn_view"), { size="sm", minWidth=100 })
    UI.AttachRowRight(f.act, { r.btnView }, 8, -4, { leftPad=8, align="center" })
    return f
end

local function UpdateRow(i, r, f, it)
    f.date:SetText(F.DateTime(it.ts))
    UI.SetNameTag(f.player, it.who or "?")
    f.ver:SetText(tostring(it.ver or ""))
    f.message:SetText(_Preview(it.msg or "", 200))

    -- Checkbox "Traité"
    local isGM = (GLOG and GLOG.IsMaster and GLOG.IsMaster()) or false
    local checked = (it.done == true)
    f.done:SetChecked(checked)
    f.done:SetEnabled(isGM)
    if isGM then
        f.done:SetScript("OnClick", function(self)
            if GLOG and GLOG.Errors_SetDone then
                GLOG.Errors_SetDone(it.id, self:GetChecked() and true or false)
            else
                -- Fallback: set direct si module Core absent
                local db = GuildLogisticsDB and GuildLogisticsDB.errors
                if db and db.list then
                    for k=1,#db.list do
                        local e = db.list[k]
                        if tonumber(e.id or 0) == tonumber(it.id or -1) then
                            e.done = self:GetChecked() and true or false
                            break
                        end
                    end
                    if ns.Emit then ns.Emit("errors:changed") end
                end
            end
            UpdateBadges()
        end)
    else
        f.done:SetScript("OnClick", nil)
    end

    r.btnView:SetOnClick(function() ShowErrorPopup(it) end)
end

-- Build/Refresh/Layout du panneau
local function Build(container)
    panel, footer = UI.CreateMainContainer(container, { footer = true })

    lv = UI.ListView(panel, _Columns(), {
        buildRow  = BuildRow,
        updateRow = UpdateRow,
        topOffset = 0,
        emptyText = Tr("tab_debug_errors"),
    })

    -- Bouton footer : vider le journal
    local bClear = UI.Button(footer, Tr("btn_clear"), { size="sm", variant="ghost", minWidth=120 })
    bClear:SetOnClick(function()
        if GLOG and GLOG.Errors_Clear then GLOG.Errors_Clear()
        elseif GuildLogisticsDB and GuildLogisticsDB.errors then
            GuildLogisticsDB.errors.list, GuildLogisticsDB.errors.nextId = {}, 1
        end
        if lv and lv.SetData then lv:SetData({}) end
        UpdateBadges()
    end)
    UI.AttachButtonsFooterRight(footer, { bClear }, 8, 0)

    -- Refresh auto quand le panneau s’ouvre
    if panel and panel.SetScript then
        panel:SetScript("OnShow", function()
            if lv then lv:SetData(_GetErrors()) end
            UpdateBadges()
        end)
    end

    -- Abonnement aux changements (émis par Core/Errors.lua)
    if ns and ns.On then
        ns.On("errors:changed", function()
            if lv and lv.SetData then
                lv:SetData(_GetErrors())
            end
            UpdateBadges()
        end)
    end

    -- Premier calcul de badge au build (au cas où)
    UpdateBadges()
end

local function Refresh()
    if lv then
        lv:RefreshData(_GetErrors())
        UpdateBadges()
    end
end


local function Layout()
    if lv and lv.Layout then lv:Layout() end
end

UI.RegisterTab(Tr("tab_debug_errors"), Build, Refresh, Layout, {
    category = Tr("cat_debug"),
})
