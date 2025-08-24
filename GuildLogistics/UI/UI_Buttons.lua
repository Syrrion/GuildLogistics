local ADDON, ns = ...
local Tr = ns and ns.Tr
local UI = ns.UI

local SIZE = { xs=20, sm=24, md=28, lg=32 }

function UI.SizeToText(btn, opts)
    local fs = btn:GetFontString()
    local textW = (fs and fs:GetStringWidth()) or 40
    local padX = (opts and opts.padX) or 18
    local minW = (opts and opts.minWidth) or 80
    btn:SetWidth(math.max(minW, math.ceil(textW + padX)))
end

function UI.SetTooltip(frame, text)
    frame._cdzTooltip = text
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", function(self)
        if not self._cdzTooltip or self._cdzTooltip=="" then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self._cdzTooltip)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

function UI.DebouncedClick(btn, ms, handler)
    btn._cdzDebounce = (ms or 200)/1000
    btn._cdzLast = 0
    btn:SetScript("OnClick", function(self, ...)
        local t = (GetTimePreciseSec and GetTimePreciseSec()) or GetTime()
        if t - (self._cdzLast or 0) < self._cdzDebounce then return end
        self._cdzLast = t
        if handler then handler(self, ...) end
    end)
end

function UI.ConfirmClick(btn, message, handler)
    btn:SetScript("OnClick", function(self)
        UI.PopupConfirm(message or "Confirmer ?", function()
            if handler then handler(self) end
        end)
    end)
end

local function applyVariant(btn, variant)
    local fs = btn:GetFontString()
    if not fs then return end
    if variant == "danger" then
        fs:SetTextColor(1, 0.35, 0.35)
    elseif variant == "ghost" then
        btn:SetAlpha(0.9); fs:SetTextColor(0.9, 0.9, 0.9)
    else
        fs:SetTextColor(1, 0.82, 0)
    end
end

-- UI.Button(parent, "Texte", { size="sm", minWidth=, padX=, variant="primary|danger|ghost", tooltip=, debounce=ms })
function UI.Button(parent, text, opts)
    opts = opts or {}
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetText((Tr and Tr(text or "OK")) or (text or "OK"))
    b:SetHeight(SIZE[opts.size or "sm"] or (opts.height or 24))
    UI.SizeToText(b, opts)
    if opts.tooltip then UI.SetTooltip(b, (Tr and Tr(opts.tooltip)) or opts.tooltip) end
    applyVariant(b, opts.variant)

    local _SetText = b.SetText
    b.SetText = function(self, t) _SetText(self, (Tr and Tr(t)) or t); UI.SizeToText(self, opts) end

    function b:SetConfirm(msg, cb) UI.ConfirmClick(self, msg, cb); return self end
    function b:SetDebounce(ms, cb) UI.DebouncedClick(self, ms, cb); return self end
    function b:SetOnClick(cb)
        if opts.debounce then UI.DebouncedClick(self, opts.debounce, cb)
        else self:SetScript("OnClick", function(btn) if cb then cb(btn) end end) end
        return self
    end

    return b
end

-- Bouton icône simple (texture carrée)
-- UI.IconButton(parent, "Interface\\Icons\\XXX", { size=24, tooltip="..." })
function UI.IconButton(parent, iconPath, opts)
    opts = opts or {}
    local s = tonumber(opts.size) or 24
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(s, s)

    local tex = b:CreateTexture(nil, "ARTWORK")
    tex:SetAllPoints(b)
    tex:SetTexture(iconPath or "Interface\\ICONS\\INV_Misc_QuestionMark")

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetColorTexture(1,1,1,0.12)
    hl:SetAllPoints(b)

    if opts.tooltip then UI.SetTooltip(b, opts.tooltip) end

    function b:SetOnClick(cb)
        b:SetScript("OnClick", function(self) if cb then cb(self) end end)
        return b
    end
    return b
end

-- ===== Helpers d’alignement robustes (ignorent les nil) =====
local function _sanitizeButtons(buttons)
    local out = {}
    if type(buttons) ~= "table" then return out end
    for i = 1, #buttons do
        local b = buttons[i]
        if b and b.ClearAllPoints and b.SetPoint then
            out[#out+1] = b
        end
    end
    return out
end

-- Aligner des boutons à droite d’un anchor (ex: header)
function UI.AttachButtonsRight(anchor, buttons, gap, dx, dy)
    local arr = _sanitizeButtons(buttons)
    if not anchor or #arr == 0 then return end
    gap = gap or 8; dx = dx or 0; dy = dy or 26
    local prev
    for i = 1, #arr do
        local b = arr[i]
        b:ClearAllPoints()
        if not prev then
            b:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", dx, dy)
        else
            b:SetPoint("RIGHT", prev, "LEFT", -gap, 0)
        end
        prev = b
    end
end

-- Alignement à droite pour un footer (centré verticalement)
function UI.AttachButtonsFooterRight(anchor, buttons, gap, dx)
    local arr = _sanitizeButtons(buttons)
    if not anchor or #arr == 0 then return end
    gap = gap or 8
    local pad = (UI.FOOTER_RIGHT_PAD ~= nil) and UI.FOOTER_RIGHT_PAD or 8
    dx = (dx ~= nil) and dx or -pad
    local prev
    for i = 1, #arr do
        local b = arr[i]
        b:ClearAllPoints()
        if not prev then
            b:SetPoint("RIGHT", anchor, "RIGHT", dx, 0)
        else
            b:SetPoint("RIGHT", prev, "LEFT", -gap, 0)
        end
        prev = b
    end
end

-- Barre d’actions alignée à droite, avec marge interne gauche (leftPad) + largeur "naturelle"
function UI.AttachRowRight(anchor, buttons, gap, dx, opts)
    local arr = _sanitizeButtons(buttons)
    if not anchor or #arr == 0 then return end
    gap = gap or 8; dx = dx or -4; opts = opts or {}
    local minScale = opts.minScale or 0.85
    local minGap   = opts.minGap   or 4
    local leftPad  = opts.leftPad  or 8
    local align    = opts.align    or "right"   -- "right" (défaut) ou "center"

    if anchor.SetClipsChildren then pcall(anchor.SetClipsChildren, anchor, true) end

    -- Hôte interne paddé
    local host = anchor._rowActionsHost
    if not host then
        host = CreateFrame("Frame", nil, anchor)
        anchor._rowActionsHost = host
    end
    host:ClearAllPoints()
    host:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 0, 0)
    host:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", 0, 0)
    host:SetPoint("TOPLEFT", anchor, "TOPLEFT", leftPad, 0)
    if host.SetClipsChildren then pcall(host.SetClipsChildren, host, true) end

    -- Sous-conteneur pour centrage (créé au besoin)
    local pack = anchor._rowActionsPack
    if not pack then
        pack = CreateFrame("Frame", nil, host)
        anchor._rowActionsPack = pack
    end

    -- Ne compter/positionner que les boutons visibles (évite les "trous")
    local function countShown()
        local n = 0
        for i = 1, #arr do if arr[i]:IsShown() then n = n + 1 end end
        return n
    end

    local function measureContentWidth()
        local sum = 0
        for i = 1, #arr do
            local b = arr[i]
            if b:IsShown() then
                if b.SetScale then b:SetScale(1) end
                sum = sum + (b:GetWidth() or 0)
            end
        end
        return sum
    end

    local function measureTotalWidth(g)
        local shown = countShown()
        return measureContentWidth() + math.max(0, shown - 1) * g
    end

    local function layoutWithGapAndScale(g, scale, packW)
        local prev
        if align == "center" then
            pack:ClearAllPoints()
            pack:SetSize(packW or 1, host:GetHeight() or 1)
            pack:SetPoint("CENTER", host, "CENTER", 0, 0)
        end
        for i = 1, #arr do
            local b = arr[i]
            if b:IsShown() then
                b:ClearAllPoints()
                if not prev then
                    if align == "center" then
                        b:SetPoint("RIGHT", pack, "RIGHT", dx, 0)
                    else
                        b:SetPoint("RIGHT", host, "RIGHT", dx, 0)
                    end
                else
                    b:SetPoint("RIGHT", prev, "LEFT", -g, 0)
                end
                if b.SetScale then b:SetScale(scale) end
                prev = b
            end
        end
    end

    local function apply()
        local natural = measureTotalWidth(gap)
        anchor._actionsNaturalW = natural + leftPad + 8

        local aw = host:GetWidth() or 0
        if aw <= 0 then return end

        -- 1) gap normal
        local total = measureTotalWidth(gap)
        if total <= aw then
            local packW = (align=="center") and (measureContentWidth()*1 + math.max(0, countShown()-1)*gap) or nil
            layoutWithGapAndScale(gap, 1, packW)
            return
        end

        -- 2) gap minimal
        total = measureTotalWidth(minGap)
        if total <= aw then
            local packW = (align=="center") and (measureContentWidth()*1 + math.max(0, countShown()-1)*minGap) or nil
            layoutWithGapAndScale(minGap, 1, packW)
            return
        end

        -- 3) scale
        local contentW = measureContentWidth()
        local need = contentW + minGap * math.max(0, countShown()-1)
        local scale = math.max(minScale, math.min(1, (aw / math.max(1, need))))
        local packW = (align=="center") and (contentW*scale + math.max(0, countShown()-1)*minGap) or nil
        layoutWithGapAndScale(minGap, scale, packW)
    end

    apply()
    if host.HookScript then host:HookScript("OnSizeChanged", apply) else host:SetScript("OnSizeChanged", apply) end
    anchor._applyRowActionsLayout = apply
end

-- Dropdown générique (basé sur UIDropDownMenu) pour unifier l'UI des menus déroulants.
-- UI.Dropdown(parent, { width=, placeholder=, tooltip= })
--    :SetBuilder(function(self, level) return { info, info, ... } end) -- items au format UIDropDownMenu_CreateInfo()
--    :SetSelected(value, label)  -- texte affiché + valeur courante
--    :GetSelected() -> value
function UI.Dropdown(parent, opts)
    opts = opts or {}
    local name = "GL_Dropdown_" .. math.random(1e8)
    local dd = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")

    dd:SetClipsChildren(false)
    dd:SetFrameStrata("DIALOG") -- s'affiche au-dessus des bordures décoratives

    local width = opts.width or 180
    if UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(dd, width) end
    if UIDropDownMenu_JustifyText then UIDropDownMenu_JustifyText(dd, "LEFT") end
    if opts.placeholder and UIDropDownMenu_SetText then
        UIDropDownMenu_SetText(dd, (Tr and Tr(opts.placeholder)) or opts.placeholder)
    end
    if opts.tooltip and UI.SetTooltip then UI.SetTooltip(dd, (Tr and Tr(opts.tooltip)) or opts.tooltip) end

    dd._builder = nil
    dd._selectedValue = nil

    function dd:SetBuilder(fn)
        self._builder = fn
        if UIDropDownMenu_Initialize then
            UIDropDownMenu_Initialize(self, function(frame, level, menuList)
                if not self._builder then return end
                local items = self:_builder(level or 1, menuList)
                if type(items) ~= "table" then return end
                for i = 1, #items do
                    UIDropDownMenu_AddButton(items[i], level)
                end
            end)
        end
        return self
    end

    function dd:SetSelected(value, label)
        self._selectedValue = value
        if UIDropDownMenu_SetText then
            UIDropDownMenu_SetText(self, label or tostring(value or ""))
        end
        return self
    end

    function dd:GetSelected()
        return self._selectedValue
    end

    function dd:SetWidth(px)
        if UIDropDownMenu_SetWidth then UIDropDownMenu_SetWidth(self, tonumber(px) or width) end
        return self
    end

    -- S'assure que les listes système DropDownListN passent au-dessus des cadres décoratifs
    dd:SetScript("OnShow", function()
        for i = 1, 3 do
            local f = _G["DropDownList"..i]
            if f then
                f:SetFrameStrata("TOOLTIP")
                f:SetFrameLevel(1000)
            end
        end
    end)

    return dd
end
