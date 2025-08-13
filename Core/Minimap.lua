-- Core/Minimap.lua
local ADDON, ns = ...
local CDZ, UI = ns.CDZ, ns.UI

-- Valeurs par défaut minimap (sauvegardées dans ChroniquesDuZephyrUI.minimap)
local function EnsureUI()
    ChroniquesDuZephyrUI = ChroniquesDuZephyrUI or {}
    ChroniquesDuZephyrUI.minimap = ChroniquesDuZephyrUI.minimap or { hide=false, angle=215 }
    if ChroniquesDuZephyrUI.minimap.angle == nil then
        ChroniquesDuZephyrUI.minimap.angle = 215
    end
end

local function SetButtonPosition(btn, angleDeg)
    local r = (Minimap:GetWidth() / 2) - 5
    local rad = math.rad(angleDeg or 215)
    btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * r, math.sin(rad) * r)
end

local function BeginDrag(btn)
    btn:SetScript("OnUpdate", function(self)
        local mx, my = Minimap:GetCenter()
        local scale = Minimap:GetEffectiveScale()
        local cx, cy = GetCursorPosition()
        local dx, dy = (cx/scale - mx), (cy/scale - my)
        local angle = math.deg(math.atan2(dy, dx))  -- [-180;180]
        if angle < 0 then angle = angle + 360 end
        ChroniquesDuZephyrUI.minimap.angle = angle
        SetButtonPosition(self, angle)
    end)
end

local function EndDrag(btn)
    btn:SetScript("OnUpdate", nil)
end

function CDZ.Minimap_Init()
    EnsureUI()
    if ChroniquesDuZephyrUI.minimap.hide then return end

    if _G.CDZ_MinimapButton then
        -- déjà créé (reload)
        SetButtonPosition(_G.CDZ_MinimapButton, ChroniquesDuZephyrUI.minimap.angle or 215)
        return
    end

    local b = CreateFrame("Button", "CDZ_MinimapButton", Minimap)
    b:SetSize(32, 32)
    b:SetFrameStrata("MEDIUM")
    b:SetMovable(true)
    b:RegisterForDrag("LeftButton")
    b:RegisterForClicks("AnyUp")

    -- Bordure standard du bouton minimap
    local border = b:CreateTexture(nil, "BACKGROUND")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(56, 56)
    border:SetPoint("TOPLEFT", b, "TOPLEFT", -7, 6)

    -- Icône (tu pourras la remplacer par un fichier du dossier de l’addon si tu veux)
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\ICONS\\INV_Misc_QuestionMark")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", b, "CENTER", 0, 0)

    -- Highlight
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    hl:SetBlendMode("ADD")
    hl:SetAllPoints(b)

    -- Tooltip
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Chroniques du Zéphyr")
        GameTooltip:AddLine("Clic gauche : Ouvrir / fermer la fenêtre", 1,1,1)
        GameTooltip:AddLine("Glisser : déplacer l’icône autour de la minimap", 1,1,1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Drag (déplacement)
    b:SetScript("OnDragStart", function(self) BeginDrag(self) end)
    b:SetScript("OnDragStop",  function(self) EndDrag(self) end)

    -- Clic : toggle UI
    b:SetScript("OnClick", function(self, button)
        if ns.ToggleUI then ns.ToggleUI() end
    end)

    -- Position initiale
    SetButtonPosition(b, ChroniquesDuZephyrUI.minimap.angle or 215)
end
