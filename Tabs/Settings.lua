local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns.GLOG, ns.UI

-- État local des contrôles (permet un refresh simple)
local optPanel
local themeRadios, autoRadios, debugRadios, scriptErrRadios = {}, {}, {}, {}

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