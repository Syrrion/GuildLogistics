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
    panel = container
    if UI.ApplySafeContentBounds then UI.ApplySafeContentBounds(panel, { side = 10, bottom = 6 }) end

    optionsPane = CreateFrame("Frame", nil, panel)
    
    local RADIO_V_SPACING = 8
    local y = UI.SECTION_HEADER_H
    
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
                GuildLogisticsUI.autoOpen = (key == "YES")
            elseif group == debugRadios then
                GuildLogisticsUI.debugEnabled = (key == "YES")
                if UI.SetDebugEnabled then UI.SetDebugEnabled(GuildLogisticsUI.debugEnabled) end
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

    -- === Section 2 : Ouverture auto ===
    local headerH2 = UI.SectionHeader(optionsPane, Tr("opt_open_on_login"), { topPad = y + 10 }) or (UI.SECTION_HEADER_H or 26)
    y = y + headerH2 + 8
    makeRadioV(autoRadios, "YES", Tr("opt_yes"))
    makeRadioV(autoRadios, "NO",  Tr("opt_no"))

    -- === Section 3 : Affichage des popups ===
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

    -- === Section 4 : Activer le débug ===
    local headerH4 = UI.SectionHeader(optionsPane, Tr("btn_enable_debug"), { topPad = y + 10 }) or (UI.SECTION_HEADER_H or 26)
    y = y + headerH4 + 8
    makeRadioV(debugRadios, "YES", Tr("opt_yes"))
    makeRadioV(debugRadios, "NO",  Tr("opt_no"))

    -- === Section 5 : Afficher les erreurs Lua ===
    local headerH5 = UI.SectionHeader(optionsPane, Tr("opt_script_errors"), { topPad = y + 10 }) or (UI.SECTION_HEADER_H or 26)
    y = y + headerH5 + 8
    makeRadioV(scriptErrRadios, "YES", Tr("opt_yes"))
    makeRadioV(scriptErrRadios, "NO",  Tr("opt_no"))

    -- État initial depuis la sauvegarde
    local saved = (GLOG.GetSavedWindow and GLOG.GetSavedWindow()) or {}
    _SetRadioGroupChecked(themeRadios, (saved.theme) or "AUTO")
    _SetRadioGroupChecked(autoRadios,  (saved.autoOpen) and "YES" or "NO")
    _SetRadioGroupChecked(debugRadios, (saved.debugEnabled) and "YES" or "NO")
    _SetRadioGroupChecked(scriptErrRadios, GLOG.IsScriptErrorsEnabled() and "YES" or "NO")
end

function RefreshOptions()
    local saved = (GLOG.GetSavedWindow and GLOG.GetSavedWindow()) or {}
    _SetRadioGroupChecked(themeRadios, (saved.theme) or "AUTO")
    _SetRadioGroupChecked(autoRadios,  (saved.autoOpen) and "YES" or "NO")
    _SetRadioGroupChecked(debugRadios, (saved.debugEnabled) and "YES" or "NO")
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