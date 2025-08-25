local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns.GLOG, ns.UI
local PAD = (UI and UI.OUTER_PAD) or 16
local ROW_GAP = 12

local panel
local btnOpen, btnClear, slOpacity, cbRecording

local function _RowY(prevY, h)
    return prevY + (h or 0) + ROW_GAP
end

-- Active/désactive proprement un bouton (compatible gabarits différents)
local function _SetButtonEnabled(b, enabled)
    if not b then return end
    if b.SetEnabled then b:SetEnabled(enabled) end
    if enabled then
        if b.Enable then b:Enable() end
    else
        if b.Disable then b:Disable() end
    end
    if b.SetAlpha then b:SetAlpha(enabled and 1 or 0.5) end
end

local function _UpdateButtonsEnabled()
    local checked = false
    if cbRecording then
        if cbRecording.GetChecked then
            checked = cbRecording:GetChecked() and true or false
        elseif cbRecording.GetValue then
            checked = cbRecording:GetValue() and true or false
        end
    else
        checked = (GLOG and GLOG.GroupTracker_GetRecordingEnabled and GLOG.GroupTracker_GetRecordingEnabled()) or false
    end
    _SetButtonEnabled(btnOpen,  checked)
    _SetButtonEnabled(btnClear, checked)
end

local function Build(container)
    panel = container
    if UI.ApplySafeContentBounds then
        UI.ApplySafeContentBounds(panel, { side = 10, bottom = 6 })
    end

    local y = 0
    -- Section header (cohérent avec les autres onglets)
    y = y + (UI.SectionHeader(panel, Tr("tab_group_tracker"), { topPad = y }) or 26) + 8

    -- 📌 Ligne 1 : case à cocher « Activer le suivi »
    local initial = false
    if GLOG and GLOG.GroupTracker_GetRecordingEnabled then
        initial = GLOG.GroupTracker_GetRecordingEnabled()
    end

    if UI.Checkbox then
        cbRecording = UI.Checkbox(panel, "group_tracker_record_label", {
            checked = initial,
            tooltip = "group_tracker_record_tip",
            minWidth = 360,
        })
        cbRecording:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -(y))
        if cbRecording.SetOnValueChanged then
            cbRecording:SetOnValueChanged(function(_, checked)
                if GLOG and GLOG.GroupTracker_SetRecordingEnabled then
                    GLOG.GroupTracker_SetRecordingEnabled(checked)
                end
                _UpdateButtonsEnabled()
            end)
        else
            cbRecording:SetScript("OnClick", function(self)
                local checked = self:GetChecked()
                if GLOG and GLOG.GroupTracker_SetRecordingEnabled then
                    GLOG.GroupTracker_SetRecordingEnabled(checked)
                end
                _UpdateButtonsEnabled()
            end)
        end
    else
        -- Fallback natif
        cbRecording = CreateFrame("CheckButton", (ADDON or "GL").."_RecordCheck", panel, "UICheckButtonTemplate")
        cbRecording:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -(y))
        cbRecording:SetChecked(initial)
        _G[cbRecording:GetName().."Text"]:SetText(Tr and Tr("group_tracker_record_label") or "group_tracker_record_label")
        cbRecording:SetScript("OnClick", function(self)
            if GLOG and GLOG.GroupTracker_SetRecordingEnabled then
                GLOG.GroupTracker_SetRecordingEnabled(self:GetChecked())
            end
            _UpdateButtonsEnabled()
        end)
        if UI.SetTooltip then UI.SetTooltip(cbRecording, Tr("group_tracker_record_tip")) end
    end
    y = _RowY(y, 20)

    -- 📌 Ligne 2 : deux boutons sur la même rangée (seront (dés)activés par _UpdateButtonsEnabled)
    btnOpen = UI.Button(panel, "group_tracker_toggle", { size="md", minWidth=200 })
    btnOpen:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -(y))
    btnOpen:SetOnClick(function()
        -- Garde-fou si jamais l’état visuel n’était pas à jour
        if cbRecording and cbRecording.GetChecked and not cbRecording:GetChecked() then return end
        if GLOG and GLOG.GroupTracker_ShowWindow then
            GLOG.GroupTracker_ShowWindow(true)
        end
    end)

    btnClear = UI.Button(panel, "btn_reset_data", { size="sm", variant="danger", minWidth=220 })
    btnClear:SetPoint("LEFT", btnOpen, "RIGHT", 12, 0)
    btnClear:SetOnClick(function()
        if cbRecording and cbRecording.GetChecked and not cbRecording:GetChecked() then return end
        if StaticPopup_Show then
            StaticPopup_Show("GLOG_CONFIRM_CLEAR_SEGMENTS")
        elseif GLOG and GLOG.GroupTracker_ClearHistory then
            GLOG.GroupTracker_ClearHistory()
        end
    end)

    local rowH = math.max(btnOpen:GetHeight() or 28, btnClear:GetHeight() or 24)
    y = _RowY(y, rowH)

    -- 📌 Ligne 3 : slider de transparence (localisé)
    local percent = math.floor(((GLOG and GLOG.GroupTracker_GetOpacity and GLOG.GroupTracker_GetOpacity()) or 0.95) * 100 + 0.5)
    slOpacity = UI.Slider(panel, {
        label  = "group_tracker_opacity_label", -- locales
        min    = 30,
        max    = 100,
        step   = 5,
        value  = percent,
        width  = 360,
        tooltip= "group_tracker_opacity_tip",   -- locales
        format = function(v) return tostring(v) .. "%" end,
        name   = (ADDON or "GL").."_OpacitySlider"
    })
    slOpacity:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -(y))
    slOpacity:SetOnValueChanged(function(_, v)
        if GLOG and GLOG.GroupTracker_SetOpacity then
            local a = math.max(0.30, math.min(1.0, (tonumber(v) or 100)/100))
            GLOG.GroupTracker_SetOpacity(a)
        end
    end)
    y = _RowY(y, 26)

    

    -- 📌 Ligne 4 : Astuce /glog track
    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -(y))
    hint:SetJustifyH("LEFT")
    hint:SetText((Tr("group_tracker_hint") or ""))

    -- État initial des boutons
    _UpdateButtonsEnabled()
end

local function Refresh()
    if slOpacity and slOpacity.SetValue and GLOG and GLOG.GroupTracker_GetOpacity then
        local p = math.floor((GLOG.GroupTracker_GetOpacity() or 0.95)*100 + 0.5)
        slOpacity:SetValue(p)
    end
    if cbRecording then
        local v = (GLOG and GLOG.GroupTracker_GetRecordingEnabled and GLOG.GroupTracker_GetRecordingEnabled()) or false
        if cbRecording.SetChecked then cbRecording:SetChecked(v) end
        if cbRecording.SetValue then cbRecording:SetValue(v) end
    end
    _UpdateButtonsEnabled()
end

local function Layout() end

UI.RegisterTab(Tr("tab_group_tracker"), Build, Refresh, Layout, {
    category = Tr("cat_info"), -- Helpers
})
