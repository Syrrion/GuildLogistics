local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns.GLOG, ns.UI

-- État local des contrôles (permet un refresh simple)
local optPanel
local themeRadios, autoRadios, debugRadios, scriptErrRadios = {}, {}, {}, {}
-- Editors UI state
local editorsLV, editorsInput, editorsGrantBtn

local function _EditorsCanModify()
    return (GLOG and GLOG.CanGrantEditor and GLOG.CanGrantEditor()) and true or false
end

local function _SetRadioGroupChecked(group, key)
    for k, b in pairs(group) do
        if b and b.SetChecked then b:SetChecked(k == key) end
    end
end

function Build(container)
    -- Création du conteneur
    panel, footer, footerH = UI.CreateMainContainer(container, {footer = false})

    optionsPane = CreateFrame("Frame", nil, panel)
    
    local RADIO_V_SPACING = 8
    local y = 8
    
    -- === Section 1 : Thème de l'interface ===
    local headerH1 = UI.SectionHeader(optionsPane, Tr("opt_ui_theme"), { topPad = y })
    y = y + headerH1 + 8

    local function makeRadioV(group, key, text)
        local b = CreateFrame("CheckButton", nil, optionsPane, "UIRadioButtonTemplate")
        b:SetPoint("TOPLEFT", optionsPane, "TOPLEFT", 0, -y)

        local label = b.Text or b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        if not b.Text then label:SetPoint("LEFT", b, "RIGHT", 6, 0); b.Text = label end
        label:SetText(text)

        b:SetScript("OnClick", function()
            _SetRadioGroupChecked(group, key)
            local saved = (GLOG.GetSavedWindow and GLOG.GetSavedWindow()) or {}
            if group == themeRadios then
                saved.theme = key
                if UI.SetTheme then UI.SetTheme(key) end
            elseif group == autoRadios then
                saved.autoOpen = (key == "YES")
            elseif group == debugRadios then
                saved.debugEnabled = (key == "YES")
                if UI.SetDebugEnabled then UI.SetDebugEnabled(saved.debugEnabled) end
            elseif group == scriptErrRadios then
                local on = (key == "YES")
                if GLOG.SetScriptErrorsEnabled then
                    GLOG.SetScriptErrorsEnabled(on)
                else
                    if SetCVar then pcall(SetCVar, "scriptErrors", on and "1" or "0") end
                end
            end
        end)

        group[key] = b
        y = y + (b:GetHeight() or 24) + RADIO_V_SPACING
        return b
    end

    makeRadioV(themeRadios, "AUTO",     Tr("opt_auto"))
    makeRadioV(themeRadios, "ALLIANCE", Tr("opt_alliance"))
    makeRadioV(themeRadios, "HORDE",    Tr("opt_horde"))
    makeRadioV(themeRadios, "NEUTRAL",  Tr("opt_neutral"))

    -- Radios "Oui/Non" sur UNE seule ligne (retourne les 2 boutons)
    local function makeYesNoInline(group, onClickYes, onClickNo)
        local bYes = CreateFrame("CheckButton", nil, optionsPane, "UIRadioButtonTemplate")
        bYes:SetPoint("TOPLEFT", optionsPane, "TOPLEFT", 0, -y)
        local lYes = bYes.Text or bYes:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        if not bYes.Text then lYes:SetPoint("LEFT", bYes, "RIGHT", 6, 0); bYes.Text = lYes end
        lYes:SetText(Tr("opt_yes"))

        local bNo  = CreateFrame("CheckButton", nil, optionsPane, "UIRadioButtonTemplate")
        bNo:SetPoint("LEFT", bYes, "RIGHT", 120, 0)
        local lNo  = bNo.Text or bNo:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        if not bNo.Text then lNo:SetPoint("LEFT", bNo, "RIGHT", 6, 0); bNo.Text = lNo end
        lNo:SetText(Tr("opt_no"))

        bYes:SetScript("OnClick", function()
            _SetRadioGroupChecked(group, "YES")
            if type(onClickYes) == "function" then onClickYes() end
        end)
        bNo:SetScript("OnClick", function()
            _SetRadioGroupChecked(group, "NO")
            if type(onClickNo) == "function" then onClickNo() end
        end)

        group["YES"], group["NO"] = bYes, bNo
        y = y + (bYes:GetHeight() or 24) + RADIO_V_SPACING
        return bYes, bNo
    end
    y = y + 8

    -- === Section 1 : Echelle de l'interface ===
    local headerH2 = UI.SectionHeader(optionsPane, Tr("opt_ui_scale_long"), { topPad = y })
    y = y + headerH2 + 8

    -- Slider d'échelle (0.5 → 1.0), défaut 0.75
    local savedForScale = (GLOG.GetSavedWindow and GLOG.GetSavedWindow()) or {}
    local curScale = tonumber(savedForScale.uiScale or 0.75) or 0.75
    if curScale < 0.5 then curScale = 0.5 elseif curScale > 1.0 then curScale = 1.0 end

    local slScale = UI.Slider(optionsPane, {
        label   = Tr("opt_ui_scale"),
        min     = 0.5,
        max     = 1.0,
        step    = 0.05,
        value   = curScale,
        width   = 360,
        tooltip = "Ajuste l’échelle propre à l’addon (indépendante de l’UI globale).",
        format  = function(v) return string.format("%d%%", math.floor((tonumber(v) or 0.7)*100 + 0.5)) end,
        applyOnRelease = true, -- ✅ commit seulement au relâchement
        name    = (ADDON or "GL").."_UIScaleSlider",
    })


    slScale:SetPoint("TOPLEFT", optionsPane, "TOPLEFT", 0, -(y))
    slScale:SetOnValueChanged(function(_, v)
        v = tonumber(v) or 0.7
        if v < 0.5 then v = 0.5 elseif v > 1.0 then v = 1.0 end

        -- Sauvegarde
        local sv = (GLOG.GetSavedWindow and GLOG.GetSavedWindow()) or {}
        sv.uiScale = v

        -- Application UNIFORME (commit au release grâce à applyOnRelease=true)
        if UI.Scale and UI.Scale.ApplyAll then
            UI.Scale.ApplyAll(v)
        else
            -- Fallback : enumerates toutes les frames GLOG_
            if EnumerateFrames and UI.Scale and UI.Scale.ApplyNow then
                local f = EnumerateFrames()
                while f do
                    local n = f.GetName and f:GetName() or nil
                    if n and n:find("^GLOG_") then
                        UI.Scale.ApplyNow(f, v)
                    end
                    f = EnumerateFrames(f)
                end
            end
        end

        -- Relayout + resnap de toutes les ListViews pour un rendu pixel-perfect
        if UI and UI.ListView_RelayoutAll then
            UI.ListView_RelayoutAll()
        end
    end)

    y = y + (slScale:GetHeight() or 26) + RADIO_V_SPACING

    -- (Section Détection main/alt par notes supprimée – le système repose sur les liens manuels, la note ne sert qu'aux suggestions)

    -- === Section 3 : Ouverture auto ===
    local headerH2 = UI.SectionHeader(optionsPane, Tr("opt_open_on_login"), { topPad = y + 10 }) or (UI.SECTION_HEADER_H or 26)
    y = y + headerH2 + 8
    makeYesNoInline(autoRadios,
        function() 
            local saved = (GLOG.GetSavedWindow and GLOG.GetSavedWindow()) or {}
            saved.autoOpen = true 
        end,
        function() 
            local saved = (GLOG.GetSavedWindow and GLOG.GetSavedWindow()) or {}
            saved.autoOpen = false 
        end
    )
    -- === Section 4 : Affichage des popups ===
    local headerH3 = UI.SectionHeader(optionsPane, Tr("options_notifications_title"), { topPad = y + 10 }) or (UI.SECTION_HEADER_H or 26)
    y = y + headerH3 + 8

    local savedForPop = (GLOG.GetSavedWindow and GLOG.GetSavedWindow()) or {}
    savedForPop.popups = savedForPop.popups or {}

    local function makeCheck(key, labelKey)
        local cb = CreateFrame("CheckButton", nil, optionsPane, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", optionsPane, "TOPLEFT", 0, -y)

        local lbl = cb.Text or cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        if not cb.Text then lbl:SetPoint("LEFT", cb, "RIGHT", 6, 0); cb.Text = lbl end
        lbl:SetText(Tr(labelKey))

        local v = savedForPop.popups[key]
        if v == nil then v = true end -- par défaut cochée
        cb:SetChecked(v)

        cb:SetScript("OnClick", function(btn)
            savedForPop.popups[key] = btn:GetChecked() and true or false
        end)

        y = y + (cb:GetHeight() or 24) -8
        return cb
    end

    -- Cases à cocher : calendrier / participation raid
    makeCheck("calendarInvite",    "opt_popup_calendar_invite")
    makeCheck("raidParticipation", "opt_popup_raid_participation")

    -- === Section 5 : Activer le débug ===
    local headerH4 = UI.SectionHeader(optionsPane, Tr("btn_enable_debug"), { topPad = y + 10 }) or (UI.SECTION_HEADER_H or 26)
    y = y + headerH4 + 8
    makeYesNoInline(debugRadios,
        function()
            GuildLogisticsUI.debugEnabled = true
            if UI.SetDebugEnabled then UI.SetDebugEnabled(true) end
        end,
        function()
            GuildLogisticsUI.debugEnabled = false
            if UI.SetDebugEnabled then UI.SetDebugEnabled(false) end
        end
    )

    -- === Section 6 : Afficher les erreurs Lua ===
    local headerH5 = UI.SectionHeader(optionsPane, Tr("opt_script_errors"), { topPad = y + 10 }) or (UI.SECTION_HEADER_H or 26)
    y = y + headerH5 + 8
    makeYesNoInline(scriptErrRadios,
        function()
            if GLOG.SetScriptErrorsEnabled then
                GLOG.SetScriptErrorsEnabled(true)
            elseif SetCVar then pcall(SetCVar, "scriptErrors", "1") end
        end,
        function()
            if GLOG.SetScriptErrorsEnabled then
                GLOG.SetScriptErrorsEnabled(false)
            elseif SetCVar then pcall(SetCVar, "scriptErrors", "0") end
        end
    )

    -- === Section 7 : Droits d'édition (Editors allowlist) ===
    local headerH6 = UI.SectionHeader(optionsPane, Tr("opt_editors_title") or "Droits d\'édition", { topPad = y + 10 }) or (UI.SECTION_HEADER_H or 26)
    y = y + headerH6 + 8

    -- Inline input + Grant button (GM-only)
    do
        local canGrant = _EditorsCanModify()

        local lbl = optionsPane:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        lbl:SetPoint("TOPLEFT", optionsPane, "TOPLEFT", 0, -y)
        lbl:SetText(Tr("opt_editors_grant_label") or "Ajouter un éditeur (main ou alt) :")

        editorsInput = CreateFrame("EditBox", nil, optionsPane, "InputBoxTemplate")
        editorsInput:SetAutoFocus(false)
        editorsInput:SetSize(260, 28)
        editorsInput:SetPoint("LEFT", lbl, "RIGHT", 8, 0)
        editorsInput:SetEnabled(canGrant)
        editorsInput:SetAlpha(canGrant and 1 or 0.35)

        editorsGrantBtn = UI.Button(optionsPane, Tr("btn_grant") or "Accorder", { size = "sm", minWidth = 100 })
        editorsGrantBtn:ClearAllPoints()
        editorsGrantBtn:SetPoint("LEFT", editorsInput, "RIGHT", 8, 0)
        editorsGrantBtn:SetEnabled(canGrant)
        if not canGrant then editorsGrantBtn:SetAlpha(0.35) end

        local function TryGrant()
            if not _EditorsCanModify() then return end
            local txt = (editorsInput and editorsInput:GetText()) or ""
            txt = tostring(txt or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if txt == "" then return end
            local full = (GLOG and GLOG.ResolveFullNameStrict and GLOG.ResolveFullNameStrict(txt)) or txt
            if GLOG and GLOG.GM_GrantEditor then
                local ok = GLOG.GM_GrantEditor(full)
                if ok then
                    editorsInput:SetText("")
                end
            end
        end
        editorsGrantBtn:SetOnClick(TryGrant)
        editorsInput:SetScript("OnEnterPressed", TryGrant)

        y = y + 28 + 8
    end

    -- Editors list (read-only for non-GM, revoke buttons for GM)
    do
        local cols = UI.NormalizeColumns({
            { key = "name", title = Tr("col_player") or "Joueur", min = 200, flex = 1 },
            { key = "act",  title = "", vsep = true,  w = 90 },
        })

        local function BuildRow(r)
            local fld = {}
            fld.name = UI.Label(r, { template = "GameFontHighlightSmall", justify = "LEFT" })
            fld.act  = CreateFrame("Frame", nil, r); fld.act:SetHeight(24); fld.act:SetFrameLevel(r:GetFrameLevel()+1)
            r.btnRevoke = UI.Button(fld.act, Tr("btn_revoke") or "Retirer", { size = "xs", minWidth = 60, variant = "danger" })
            UI.AttachRowRight(fld.act, { r.btnRevoke }, 8, -4, { leftPad = 8, align = "center" })
            return fld
        end

        local function UpdateRow(i, r, fld, it)
            fld.name:SetText(tostring(it.display or it.name or "?"))
            local canGrant = _EditorsCanModify()
            if r.btnRevoke and r.btnRevoke.SetShown then r.btnRevoke:SetShown(canGrant) end
            if r.btnRevoke then
                r.btnRevoke:SetOnClick(function()
                    if not _EditorsCanModify() then return end
                    if GLOG and GLOG.GM_RevokeEditor then
                        GLOG.GM_RevokeEditor(it.uid or it.name)
                    end
                end)
            end
        end

        -- Container frame to give the list a fixed height within options
        local listFrame = CreateFrame("Frame", nil, optionsPane)
        listFrame:SetPoint("TOPLEFT", optionsPane, "TOPLEFT", 0, -y)
        listFrame:SetPoint("TOPRIGHT", optionsPane, "TOPRIGHT", 0, -y)
        listFrame:SetHeight(160)

        editorsLV = UI.ListView(listFrame, cols, { topOffset = 0, buildRow = BuildRow, updateRow = UpdateRow })

        local function RefreshEditors()
            local rows = {}
            if GLOG and GLOG.GetEditors then
                local t = GLOG.GetEditors() or {}
                for mu, v in pairs(t) do
                    if v then
                        local nm = (GLOG.GetNameByUID and GLOG.GetNameByUID(mu)) or tostring(mu)
                        rows[#rows+1] = { name = nm, display = nm, uid = mu }
                    end
                end
            end
            table.sort(rows, function(a,b) return (tostring(a.display or a.name or ""):lower()) < (tostring(b.display or b.name or ""):lower()) end)
            if editorsLV and editorsLV.RefreshData then editorsLV:RefreshData(rows) end
        end

        -- Initial populate
        RefreshEditors()

        -- Live updates on changes
        if GLOG and GLOG.On then
            GLOG.On("editors:changed", function()
                RefreshEditors()
                -- Update grant controls state if GM status changed elsewhere
                local can = _EditorsCanModify()
                if editorsInput and editorsInput.SetEnabled then editorsInput:SetEnabled(can); editorsInput:SetAlpha(can and 1 or 0.35) end
                if editorsGrantBtn and editorsGrantBtn.SetEnabled then editorsGrantBtn:SetEnabled(can); editorsGrantBtn:SetAlpha(can and 1 or 0.35) end
            end)
            GLOG.On("gm:changed", function()
                local can = _EditorsCanModify()
                if editorsInput and editorsInput.SetEnabled then editorsInput:SetEnabled(can); editorsInput:SetAlpha(can and 1 or 0.35) end
                if editorsGrantBtn and editorsGrantBtn.SetEnabled then editorsGrantBtn:SetEnabled(can); editorsGrantBtn:SetAlpha(can and 1 or 0.35) end
                if editorsLV and editorsLV.UpdateVisibleRows then editorsLV:UpdateVisibleRows() end
            end)
        end

        y = y + 160 + 8
    end

    -- État initial depuis la sauvegarde
    local saved = (GLOG.GetSavedWindow and GLOG.GetSavedWindow()) or {}
    _SetRadioGroupChecked(themeRadios, (saved.theme) or "AUTO")
    _SetRadioGroupChecked(autoRadios,  (saved.autoOpen) and "YES" or "NO")
    _SetRadioGroupChecked(debugRadios, (saved.debugEnabled) and "YES" or "NO")
    _SetRadioGroupChecked(scriptErrRadios, GLOG.IsScriptErrorsEnabled() and "YES" or "NO")
    -- plus de radio pour auto-détection main/alt
end

function RefreshOptions()
    local saved = (GLOG.GetSavedWindow and GLOG.GetSavedWindow()) or {}
    _SetRadioGroupChecked(themeRadios, (saved.theme) or "AUTO")
    
    -- Compatibilité : lire depuis saved.autoOpen ou GuildLogisticsUI.autoOpen (migration douce)
    local autoOpen = saved.autoOpen
    if autoOpen == nil then autoOpen = (GuildLogisticsUI and GuildLogisticsUI.autoOpen) end
    if autoOpen == nil then autoOpen = true end -- défaut: true
    _SetRadioGroupChecked(autoRadios, autoOpen and "YES" or "NO")
    
    -- Compatibilité : lire depuis saved.debugEnabled ou GuildLogisticsUI.debugEnabled  
    local debugEnabled = saved.debugEnabled
    if debugEnabled == nil then debugEnabled = (GuildLogisticsUI and GuildLogisticsUI.debugEnabled) end
    if debugEnabled == nil then debugEnabled = false end -- défaut: false
    _SetRadioGroupChecked(debugRadios, debugEnabled and "YES" or "NO")
    
    _SetRadioGroupChecked(scriptErrRadios, GLOG.IsScriptErrorsEnabled() and "YES" or "NO")
    -- Refresh editors list if present and re-evaluate controls state
    if editorsLV and editorsLV.Refresh then editorsLV:Refresh() end
    local can = _EditorsCanModify()
    if editorsInput and editorsInput.SetEnabled then editorsInput:SetEnabled(can); editorsInput:SetAlpha(can and 1 or 0.35) end
    if editorsGrantBtn and editorsGrantBtn.SetEnabled then editorsGrantBtn:SetEnabled(can); editorsGrantBtn:SetAlpha(can and 1 or 0.35) end
end


-- == Point d'extension future : l'agencement est géré par ancres == --
local function Layout()
    if not panel or not panel.GetWidth then return end
    local W = panel:GetWidth() or 0
    local H = panel:GetHeight() or 0
    -- Si le panneau n'est pas encore dimensionné, on sort (évite les W/H=0 et les ancrages foireux)
    if W <= 0 or H <= 0 then return end

    local footerH = (footer and footer:GetHeight() or 0) + 6
    local availH = math.max(0, H - footerH - (UI.OUTER_PAD*2))
    local topH   = math.floor(availH * 0.60)

    -- Zone joueurs (haut) : bornée entre le haut du panel et le haut de lotsPane
    optionsPane:ClearAllPoints()
    optionsPane:SetPoint("TOPLEFT",  panel,   "TOPLEFT",  UI.OUTER_PAD, -UI.OUTER_PAD)
    optionsPane:SetPoint("TOPRIGHT", panel,   "TOPRIGHT", -UI.OUTER_PAD, -UI.OUTER_PAD)
    optionsPane:SetPoint("BOTTOMLEFT", panel, "TOPLEFT",  0,  6)
    optionsPane:SetPoint("BOTTOMRIGHT", panel, "TOPRIGHT", 0,  6)
end

-- == Déclenche un rafraîchissement manuel de la liste == --
local function Refresh()
    Layout()
end

UI.RegisterTab(Tr("tab_settings"), Build, Refresh, Layout, {
    category = Tr("cat_settings"),
})