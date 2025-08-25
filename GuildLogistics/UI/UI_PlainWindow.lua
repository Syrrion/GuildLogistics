local ADDON, ns = ...
ns.UI = ns.UI or {}
local UI = ns.UI
local Tr = ns.Tr or function(s) return s end

-- Fenêtre épurée : header noir 50%, fond global 25%, redimensionnable coin BR.
-- opts = {
--   title, width, height, strata, level, saveKey, headerHeight,
--   -- Position par défaut si aucune position sauvegardée n’existe :
--   defaultPoint="CENTER", defaultRelPoint="CENTER", defaultX=0, defaultY=0,
--   -- Padding interne du contenu :
--   contentPad = 8,
-- }
function UI.CreatePlainWindow(opts)
    opts = opts or {}
    local titleText = Tr(opts.title or "")
    local w       = tonumber(opts.width or 560)
    local h       = tonumber(opts.height or 360)
    local strata  = opts.strata or "FULLSCREEN_DIALOG"
    local level   = tonumber(opts.level or 220)
    local headerH = tonumber(opts.headerHeight or 24)
    local saveKey = tostring(opts.saveKey or ("Plain_"..(titleText or "Window")))
    local pad     = tonumber(opts.contentPad or (UI and UI.GUTTER) or 8)

    -- Persistance (position/taille)
    local function _GetStore()
        GuildLogisticsUI_Char = GuildLogisticsUI_Char or {}
        GuildLogisticsUI_Char.plainWins = GuildLogisticsUI_Char.plainWins or {}
        GuildLogisticsUI_Char.plainWins[saveKey] = GuildLogisticsUI_Char.plainWins[saveKey] or {}
        return GuildLogisticsUI_Char.plainWins[saveKey]
    end

    -- Frame principale
    local f = CreateFrame("Frame", "GLOG_Plain_"..saveKey, UIParent)
    f:SetSize(w, h)
    f:SetFrameStrata(strata)
    f:SetFrameLevel(level)
    f:SetToplevel(true)
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(400, 200) end

    -- Fond global 25%
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints(f)
    f.bg:SetColorTexture(0, 0, 0, 0.5)

    -- Header (draggable) + fond NOIR 50%
    f.header = CreateFrame("Frame", nil, f)
    f.header:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
    f.header:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
    f.header:SetHeight(headerH)
    f.header:EnableMouse(true)
    f.header:RegisterForDrag("LeftButton")
    f.header:SetScript("OnDragStart", function() f:StartMoving() end)
    f.header:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)
    f.header:SetFrameLevel(f:GetFrameLevel() + 1)

    f.header.bg = f.header:CreateTexture(nil, "ARTWORK")
    f.header.bg:SetAllPoints(f.header)
    f.header.bg:SetColorTexture(0, 0, 0, 0.50) -- noir 50%

    -- Titre à gauche
    f.title = f.header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("LEFT", f.header, "LEFT", 8, 0)
    f.title:SetText(titleText)

    -- Bouton fermer (croix) à droite
    f.close = CreateFrame("Button", nil, f.header, "UIPanelCloseButton")
    f.close:SetPoint("RIGHT", f.header, "RIGHT", -2, 0)
    f.close:SetSize(22, 22)

    -- 🔹 Conteneur de contenu standard (pour y attacher ListView, etc.)
    f.content = CreateFrame("Frame", nil, f)
    f.content:SetPoint("TOPLEFT",     f, "TOPLEFT",     pad, -(headerH + pad))
    f.content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -pad, -pad)

    -- Redimensionnement coin bas-droit
    f.resize = CreateFrame("Button", nil, f)
    f.resize:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2, 2)
    f.resize:SetSize(16, 16)
    local tex = f.resize:CreateTexture(nil, "OVERLAY")
    tex:SetAllPoints()
    tex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    tex:SetAlpha(0.7)
    f.resize:SetScript("OnMouseDown", function() f:StartSizing("BOTTOMRIGHT") end)
    f.resize:SetScript("OnMouseUp",   function() f:StopMovingOrSizing() end)

    -- Persistance pos/size
    local function Save()
        local st = _GetStore()
        local p, _, rp, x, y = f:GetPoint(1)
        st.point, st.relPoint, st.x, st.y = p, rp, math.floor((x or 0) + 0.5), math.floor((y or 0) + 0.5)
        st.w, st.h = math.floor((f:GetWidth() or w) + 0.5), math.floor((f:GetHeight() or h) + 0.5)
    end
    local function Restore()
        local st = _GetStore()
        local p  = st.point    or (opts.defaultPoint    or "CENTER")
        local rp = st.relPoint or (opts.defaultRelPoint or "CENTER")
        local x  = st.x; if x == nil then x = tonumber(opts.defaultX or 0) end
        local y  = st.y; if y == nil then y = tonumber(opts.defaultY or 0) end
        f:ClearAllPoints()
        f:SetPoint(p, UIParent, rp, tonumber(x or 0), tonumber(y or 0))
        f:SetSize(tonumber(st.w or w), tonumber(st.h or h))
    end
    f:SetScript("OnHide", Save)
    f:HookScript("OnSizeChanged", Save)
    Restore()

    return f
end
