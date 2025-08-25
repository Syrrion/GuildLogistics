local ADDON, ns = ...
ns.UI = ns.UI or {}
local Tr = ns and ns.Tr
local UI = ns.UI

-- Fenêtre flottante minimaliste, réutilisable
-- opts = { title=stringKeyOrText, width=, height=, saveKey="UniqueKey", strata="MEDIUM" }
function UI.CreateFloatPanel(opts)
    opts = opts or {}
    local titleText = (Tr and Tr(opts.title or "")) or tostring(opts.title or "")
    local w = tonumber(opts.width or 280)
    local h = tonumber(opts.height or 240)
    local strata = opts.strata or "MEDIUM"
    local saveKey = tostring(opts.saveKey or "Float_"..(titleText or "Window"))

    -- Persistance
    local function _GetStore()
        GuildLogisticsUI_Char = GuildLogisticsUI_Char or {}
        GuildLogisticsUI_Char.floatWins = GuildLogisticsUI_Char.floatWins or {}
        GuildLogisticsUI_Char.floatWins[saveKey] = GuildLogisticsUI_Char.floatWins[saveKey] or {}
        return GuildLogisticsUI_Char.floatWins[saveKey]
    end

    local f = CreateFrame("Frame", "GLOG_Float_"..saveKey, UIParent, "BackdropTemplate")
    f:SetSize(w, h)
    f:SetFrameStrata(strata)
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(160, 120) end

    -- Style minimal : fond sombre léger + bord fin pixel-perfect
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    bg:SetColorTexture(0, 0, 0, 0.55)

    local border = f:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    border:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
    border:SetColorTexture(1, 1, 1, 0.08)

    -- Barre de titre (draggable sur toute la largeur)
    f.header = CreateFrame("Frame", nil, f, "BackdropTemplate")
    f.header:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.header:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    f.header:SetHeight(28)

    local hbg = f.header:CreateTexture(nil, "ARTWORK")
    hbg:SetAllPoints(f.header)
    hbg:SetColorTexture(1, 1, 1, 0.06)

    f.title = f.header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.title:SetPoint("LEFT", f.header, "LEFT", 10, 0)
    f.title:SetJustifyH("LEFT")
    f.title:SetText(titleText)

    -- Close
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() f:Hide() end)

    -- Contenu
    f.content = CreateFrame("Frame", nil, f)
    f.content:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -32)
    f.content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)

    -- Drag
    f.header:EnableMouse(true)
    f.header:RegisterForDrag("LeftButton")
    f.header:SetScript("OnDragStart", function() f:StartMoving() end)
    f.header:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

    -- Persistance position/taille
    local function Save()
        local st = _GetStore()
        local p, rel, rp, x, y = f:GetPoint(1)
        st.point, st.relPoint, st.x, st.y = p, rp, math.floor(x or 0 + 0.5), math.floor(y or 0 + 0.5)
        st.w, st.h = math.floor((f:GetWidth() or w) + 0.5), math.floor((f:GetHeight() or h) + 0.5)
    end
    local function Restore()
        local st = _GetStore()
        local p, rp, x, y = st.point or "CENTER", st.relPoint or "CENTER", tonumber(st.x or 0), tonumber(st.y or 0)
        f:ClearAllPoints()
        f:SetPoint(p, UIParent, rp, x, y)
        f:SetSize(tonumber(st.w or w), tonumber(st.h or h))
    end
    f:SetScript("OnHide", Save)
    f:HookScript("OnSizeChanged", function() Save() end)
    Restore()

    return f
end
