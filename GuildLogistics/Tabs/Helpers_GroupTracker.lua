local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns.GLOG, ns.UI
local PAD = (UI and UI.OUTER_PAD) or 16
local ROW_GAP = 12

local panel
local btnOpen, btnClear, slOpacity, cbRecording, cbColHeal, cbColUtil, cbColStone

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
    -- Création du conteneur
    panel, footer, footerH = UI.CreateMainContainer(container, {footer = false})

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
        -- Ne rien faire si le suivi n'est pas activé
        if cbRecording and cbRecording.GetChecked and not cbRecording:GetChecked() then return end

        -- Confirmation via popup UI interne (aucun taint)
        if UI and UI.PopupConfirm then
            UI.PopupConfirm(Tr("confirm_clear_history"), function()
                if GLOG and GLOG.GroupTracker_ClearHistory then
                    GLOG.GroupTracker_ClearHistory()
                end
            end, nil, { strata = "FULLSCREEN_DIALOG" })
        else
            -- Fallback sans popup
            if GLOG and GLOG.GroupTracker_ClearHistory then
                GLOG.GroupTracker_ClearHistory()
            end
        end
    end)

    local rowH = math.max(btnOpen:GetHeight() or 28, btnClear:GetHeight() or 24)
    y = _RowY(y, rowH)

    -- === Nouvelle section : Paramétrage (style identique aux autres SectionHeader) ===
    y = y + (UI.SectionHeader(panel, "Visibilité", { topPad = y }) or 26) + 8

    -- === Cases à cocher pour (dés)afficher les 3 dernières colonnes de la fenêtre flottante ===
    local initHeal  = (GLOG and GLOG.GroupTracker_GetColumnVisible and GLOG.GroupTracker_GetColumnVisible("heal"))  ~= false
    local initUtil  = (GLOG and GLOG.GroupTracker_GetColumnVisible and GLOG.GroupTracker_GetColumnVisible("util"))  ~= false
    local initStone = (GLOG and GLOG.GroupTracker_GetColumnVisible and GLOG.GroupTracker_GetColumnVisible("stone")) ~= false

    if UI and UI.Checkbox then
        cbColHeal = UI.Checkbox(panel, "col_heal_potion",   { checked = initHeal,  minWidth = 240 })
        cbColHeal:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -(y))
        if cbColHeal.SetOnValueChanged then
            cbColHeal:SetOnValueChanged(function(_, checked)
                if GLOG and GLOG.GroupTracker_SetColumnVisible then
                    GLOG.GroupTracker_SetColumnVisible("heal", checked)
                end
            end)
        end
        y = _RowY(y, 20)

        cbColUtil = UI.Checkbox(panel, "col_other_potions", { checked = initUtil,  minWidth = 240 })
        cbColUtil:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -(y))
        if cbColUtil.SetOnValueChanged then
            cbColUtil:SetOnValueChanged(function(_, checked)
                if GLOG and GLOG.GroupTracker_SetColumnVisible then
                    GLOG.GroupTracker_SetColumnVisible("util", checked)
                end
            end)
        end
        y = _RowY(y, 20)

        cbColStone = UI.Checkbox(panel, "col_healthstone",  { checked = initStone, minWidth = 240 })
        cbColStone:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -(y))
        if cbColStone.SetOnValueChanged then
            cbColStone:SetOnValueChanged(function(_, checked)
                if GLOG and GLOG.GroupTracker_SetColumnVisible then
                    GLOG.GroupTracker_SetColumnVisible("stone", checked)
                end
            end)
        end
        y = _RowY(y, 20)
    else
        -- Fallback natif (si UI.Checkbox indisponible)
        cbColHeal = CreateFrame("CheckButton", (ADDON or "GL").."_ChkColHeal", panel, "UICheckButtonTemplate")
        cbColHeal:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -(y))
        cbColHeal:SetChecked(initHeal)
        _G[cbColHeal:GetName().."Text"]:SetText(Tr and Tr("col_heal_potion") or "col_heal_potion")
        cbColHeal:SetScript("OnClick", function(self)
            if GLOG and GLOG.GroupTracker_SetColumnVisible then
                GLOG.GroupTracker_SetColumnVisible("heal", self:GetChecked())
            end
        end)
        y = _RowY(y, 20)

        cbColUtil = CreateFrame("CheckButton", (ADDON or "GL").."_ChkColUtil", panel, "UICheckButtonTemplate")
        cbColUtil:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -(y))
        cbColUtil:SetChecked(initUtil)
        _G[cbColUtil:GetName().."Text"]:SetText(Tr and Tr("col_other_potions") or "col_other_potions")
        cbColUtil:SetScript("OnClick", function(self)
            if GLOG and GLOG.GroupTracker_SetColumnVisible then
                GLOG.GroupTracker_SetColumnVisible("util", self:GetChecked())
            end
        end)
        y = _RowY(y, 20)

        cbColStone = CreateFrame("CheckButton", (ADDON or "GL").."_ChkColStone", panel, "UICheckButtonTemplate")
        cbColStone:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -(y))
        cbColStone:SetChecked(initStone)
        _G[cbColStone:GetName().."Text"]:SetText(Tr and Tr("col_healthstone") or "col_healthstone")
        cbColStone:SetScript("OnClick", function(self)
            if GLOG and GLOG.GroupTracker_SetColumnVisible then
                GLOG.GroupTracker_SetColumnVisible("stone", self:GetChecked())
            end
        end)
        y = _RowY(y, 20)
    end

    -- === Nouvelle section : Paramétrage (style identique aux autres SectionHeader) ===
    y = y + (UI.SectionHeader(panel, "Paramétrage", { topPad = y }) or 26) + 8

    -- 📌 Ligne 3 : slider de transparence (localisé)
    slOpacity = UI.Slider(panel, {
        label  = "group_tracker_opacity_label", -- locales
        min    = 0,
        max    = 100,
        step   = 1,
        value  = math.floor(((GLOG and GLOG.GroupTracker_GetOpacity and GLOG.GroupTracker_GetOpacity()) or 1) * 100),
        width  = 360,
        tooltip= "group_tracker_opacity_tip",   -- locales
        format = function(v) return tostring(v) .. "%" end,
        name   = (ADDON or "GL").."_OpacitySlider"
    })
    slOpacity:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -(y))
    slOpacity:SetOnValueChanged(function(_, v)
        local a = math.max(0.0, math.min(1.0, (tonumber(v) or 100)/100))
        if GLOG and GLOG.GroupTracker_SetOpacity then
            GLOG.GroupTracker_SetOpacity(a)
        end
    end)
    y = _RowY(y, 26)

-- 📌 (NOUVEAU) Ligne 3b : Transparence du texte (indépendante du fond)
    if slTextOpacity and slTextOpacity.Hide then slTextOpacity:Hide() end -- au cas où on reconstruit
    slTextOpacity = UI.Slider(panel, {
        label   = Tr("group_tracker_text_opacity_label") or "Transparence du texte",
        min     = 1,
        max     = 100,
        step   = 1,
        value  = math.floor(((GLOG and GLOG.GroupTracker_GetTextOpacity and GLOG.GroupTracker_GetTextOpacity()) or 1) * 100),
        width  = 360,
        tooltip = Tr("group_tracker_text_opacity_tip"),
                format = function(v) return tostring(v) .. "%" end,
        name   = (ADDON or "GL").."_OpacitySlider2"
    })
    slTextOpacity:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -(y))
    slTextOpacity:SetOnValueChanged(function(_, v)
        local a = math.max(0.0, math.min(1.0, (tonumber(v) or 100)/100))
        if GLOG and GLOG.GroupTracker_SetTextOpacity then
            GLOG.GroupTracker_SetTextOpacity(a)
        end
    end)
    y = _RowY(y, 26)

        -- 📌 (NOUVEAU) Ligne 3c : Transparence des boutons (Fermer, <, >, Vider)
    if slBtnOpacity and slBtnOpacity.Hide then slBtnOpacity:Hide() end
    slBtnOpacity = UI.Slider(panel, {
        label   = Tr("group_tracker_btn_opacity_label") or "Transparence des boutons",
        min     = 0,      -- autorise 0% (boutons invisibles mais cliquables)
        max     = 100,
        step    = 1,
        tooltip = Tr("group_tracker_btn_opacity_tip") or "Contrôle l'opacité des boutons sans affecter les fonds ni le texte.",
        width   = 360,
        format  = function(v) return tostring(v) .. "%" end,
        name    = (ADDON or "GL").."_BtnOpacitySlider",
    })
    slBtnOpacity:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -(y))
    slBtnOpacity:SetOnValueChanged(function(_, v)
        local a = math.max(0.0, math.min(1.0, (tonumber(v) or 100)/100))
        if GLOG and GLOG.GroupTracker_SetButtonsOpacity then
            GLOG.GroupTracker_SetButtonsOpacity(a)
        end
    end)
    y = _RowY(y, 26)

    -- Crée le slider "Hauteur des lignes" s'il n'existe pas encore
    if slRowHeight and slRowHeight.Hide then slRowHeight:Hide() end
    slRowHeight = UI.Slider(panel, {
        label   = Tr("group_tracker_row_height_label"),
        min     = 10,
        max     = 64,
        step    = 1,
        value   = (GLOG and GLOG.GroupTracker_GetRowHeight and GLOG.GroupTracker_GetRowHeight()) or 22,
        width   = 360,
        tooltip = Tr("group_tracker_row_height_tip"),
        format  = function(v) return tostring(v) .. " px" end,
        name    = (ADDON or "GL").."_RowHeightSlider",
    })

    slRowHeight:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -(y))
    slRowHeight:SetOnValueChanged(function(_, v)
        local h = math.floor(tonumber(v) or 22)
        if GLOG and GLOG.GroupTracker_SetRowHeight then
            GLOG.GroupTracker_SetRowHeight(h)
        end
    end)

    -- Sync valeur slider hauteur si déjà présent
    if slRowHeight and slRowHeight.SetValue and GLOG and GLOG.GroupTracker_GetRowHeight then
        slRowHeight:SetValue((GLOG.GroupTracker_GetRowHeight() or 22))
    end
    
    -- init depuis le store
    if slBtnOpacity and slBtnOpacity.SetValue and GLOG and GLOG.GroupTracker_GetButtonsOpacity then
        local p = math.floor(((GLOG.GroupTracker_GetButtonsOpacity() or 1.0) * 100))
        if p < 0 then p = 0 elseif p > 100 then p = 100 end
        slBtnOpacity:SetValue(p)
    end
    y = _RowY(y, 26)


    -- 📌 Ligne 5 : Astuce /glog track
    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -(y))
    hint:SetJustifyH("LEFT")
    hint:SetText((Tr("group_tracker_hint") or ""))

    -- État initial des boutons
    _UpdateButtonsEnabled()
end

function Refresh()
    -- Opacité fonds
    if slOpacity and slOpacity.SetValue and GLOG and GLOG.GroupTracker_GetOpacity then
        local p = math.floor((GLOG.GroupTracker_GetOpacity() or 0.95)*100 + 0.5)
        slOpacity:SetValue(p)
    end

    -- Rafraîchit l’état des cases de colonnes
    if GLOG and GLOG.GroupTracker_GetColumnVisible then
        local vHeal  = GLOG.GroupTracker_GetColumnVisible("heal")
        local vUtil  = GLOG.GroupTracker_GetColumnVisible("util")
        local vStone = GLOG.GroupTracker_GetColumnVisible("stone")
        if cbColHeal and cbColHeal.SetChecked then cbColHeal:SetChecked(vHeal ~= false) end
        if cbColUtil and cbColUtil.SetChecked then cbColUtil:SetChecked(vUtil ~= false) end
        if cbColStone and cbColStone.SetChecked then cbColStone:SetChecked(vStone ~= false) end
        if cbColHeal and cbColHeal.SetValue   then cbColHeal:SetValue(vHeal ~= false)   end
        if cbColUtil and cbColUtil.SetValue   then cbColUtil:SetValue(vUtil ~= false)   end
        if cbColStone and cbColStone.SetValue then cbColStone:SetValue(vStone ~= false) end
    end

    _UpdateButtonsEnabled()
end


local function Layout() end

UI.RegisterTab(Tr("tab_group_tracker"), Build, Refresh, Layout, {
    category = Tr("cat_tracker"), -- Helpers
})
