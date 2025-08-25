local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns.GLOG, ns.UI
local PAD = (UI and UI.OUTER_PAD) or 16

local panel, chk
local lblHeal, inHeal
local lblUtil, inUtil
local lblStone, inStone
local resetBtn

local function Build(container)
    panel = container

    if UI.ApplySafeContentBounds then
        UI.ApplySafeContentBounds(panel, { side = 10, bottom = 6 })
    end

    local y = 0
    y = y + (UI.SectionHeader(panel, Tr("tab_group_tracker"), { topPad = y }) or 26) + 8

    -- Toggle fenêtre
    chk = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    chk:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -(y))
    chk.text = chk:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    chk.text:SetPoint("LEFT", chk, "RIGHT", 6, 0)
    chk.text:SetText(Tr("group_tracker_toggle"))
    chk:SetScript("OnClick", function(self)
        local on = self:GetChecked() and true or false
        if GLOG and GLOG.GroupTrackerSetEnabled then GLOG.GroupTrackerSetEnabled(on) end
    end)
    y = y + (chk:GetHeight() or 24) + 12

    -- Cooldowns par catégorie
    lblHeal = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lblHeal:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -(y))
    lblHeal:SetText(Tr("group_tracker_cooldown_heal"))
    inHeal = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    inHeal:SetSize(64, 28); inHeal:SetAutoFocus(false); inHeal:SetNumeric(true)
    inHeal:SetPoint("LEFT", lblHeal, "RIGHT", 8, 0)
    inHeal:SetScript("OnTextChanged", function(self)
        if GLOG and GLOG.GroupTrackerSetCooldown then
            local v = tonumber(self:GetText() or "") or 0
            GLOG.GroupTrackerSetCooldown("heal", v)
        end
    end)

    lblUtil = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lblUtil:SetPoint("LEFT", inHeal, "RIGHT", 24, 0)
    lblUtil:SetText(Tr("group_tracker_cooldown_util"))
    inUtil = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    inUtil:SetSize(64, 28); inUtil:SetAutoFocus(false); inUtil:SetNumeric(true)
    inUtil:SetPoint("LEFT", lblUtil, "RIGHT", 8, 0)
    inUtil:SetScript("OnTextChanged", function(self)
        if GLOG and GLOG.GroupTrackerSetCooldown then
            local v = tonumber(self:GetText() or "") or 0
            GLOG.GroupTrackerSetCooldown("util", v)
        end
    end)

    lblStone = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lblStone:SetPoint("LEFT", inUtil, "RIGHT", 24, 0)
    lblStone:SetText(Tr("group_tracker_cooldown_stone"))
    inStone = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    inStone:SetSize(64, 28); inStone:SetAutoFocus(false); inStone:SetNumeric(true)
    inStone:SetPoint("LEFT", lblStone, "RIGHT", 8, 0)
    inStone:SetScript("OnTextChanged", function(self)
        if GLOG and GLOG.GroupTrackerSetCooldown then
            local v = tonumber(self:GetText() or "") or 0
            GLOG.GroupTrackerSetCooldown("stone", v)
        end
    end)

    -- Reset session
    resetBtn = UI.Button(panel, Tr("btn_reset_counters"), { size="sm", minWidth=140 })
    resetBtn:ClearAllPoints()
    resetBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -(y + 40))
    resetBtn:SetScript("OnClick", function()
        if GLOG and GLOG.GroupTracker_Reset then GLOG.GroupTracker_Reset() end
    end)

    -- Aide
    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -(y + 76))
    hint:SetJustifyH("LEFT")
    hint:SetText(Tr("group_tracker_hint"))
end


local function Refresh()
    if not panel then return end
    if chk and chk.SetChecked then chk:SetChecked((GLOG and GLOG.GroupTrackerIsEnabled and GLOG.GroupTrackerIsEnabled()) or false) end

    if GLOG and GLOG.GroupTrackerGetCooldown then
        if inHeal  and inHeal.SetText  then inHeal:SetText( tostring(GLOG.GroupTrackerGetCooldown("heal")  or 0) ) end
        if inUtil  and inUtil.SetText  then inUtil:SetText( tostring(GLOG.GroupTrackerGetCooldown("util")  or 0) ) end
        if inStone and inStone.SetText then inStone:SetText(tostring(GLOG.GroupTrackerGetCooldown("stone") or 0) ) end
    end
end

local function Layout() end

UI.RegisterTab(Tr("tab_group_tracker"), Build, Refresh, Layout, {
    category = Tr("cat_info"), -- Helpers
})
