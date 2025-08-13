local ADDON, ns = ...
ns.UI = ns.UI or {}
local UI = ns.UI
local CDZ = ns.CDZ

-- Thème de cadre (NEUTRAL | ALLIANCE | HORDE)
UI.FRAME_THEME = "ALLIANCE"

-- Constantes (prend celles de UI.lua si déjà définies)
UI.OUTER_PAD       = UI.OUTER_PAD       or 16
UI.SCROLLBAR_W     = UI.SCROLLBAR_W     or 20
UI.SCROLLBAR_INSET = UI.SCROLLBAR_INSET or 10 
UI.GUTTER          = UI.GUTTER          or 8
UI.ROW_H           = UI.ROW_H           or 28
UI.FONT_YELLOW = UI.FONT_YELLOW or {1, 0.82, 0}
UI.WHITE       = UI.WHITE       or {1,1,1}
UI.ACCENT      = UI.ACCENT      or {0.22,0.55,0.95}


-- === Colonnes: w/min/flex
function UI.ResolveColumns(totalWidth, cols, opts)
    opts = opts or {}
    local safeRight = (opts.safeRight ~= false)
    local SAFE = (UI.SCROLLBAR_W or 20) + (UI.SCROLLBAR_INSET or 0)
    local fixed, flexUnits = 0, 0
    local out = {}

    for i, c in ipairs(cols or {}) do
        local min = c.min or c.w or 80
        local w   = c.w
        if w then
            fixed = fixed + w
            out[i] = { key=c.key, w=w, justify=c.justify, pad=c.pad }
        else
            flexUnits = flexUnits + (c.flex or 0)
            out[i] = { key=c.key, w=min, min=min, flex=c.flex or 0, justify=c.justify, pad=c.pad }
            fixed = fixed + min
        end
    end

    local contentW = totalWidth or 800
    if safeRight and #out > 0 then contentW = contentW - SAFE end
    local rem = math.max(0, contentW - fixed)

    if flexUnits > 0 and rem > 0 then
        for _, rc in ipairs(out) do
            if rc.flex and rc.flex > 0 then
                rc.w = rc.min + math.floor(rem * rc.flex / flexUnits + 0.5)
            end
        end
    end

    if safeRight and #out > 0 then
        local last = out[#out]
        last.w = math.max(24, last.w - SAFE)
    end
    return out
end

function UI.MinWidthForColumns(cols)
    local sum = 0
    for _, c in ipairs(cols or {}) do
        sum = sum + (c.w or c.min or 80)
    end
    -- léger slack pour le padding visuel du header
    return sum + 8
end

-- ===== Header =====
function UI.CreateHeader(parent, cols)
    local header = CreateFrame("Frame", nil, parent)
    header:SetHeight(24)
    local labels = {}
    for i, c in ipairs(cols or {}) do
        local fs = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetText(c.title or "")
        fs:SetJustifyH(c.justify or "LEFT")
        labels[i] = fs
    end
    return header, labels
end

function UI.LayoutHeader(header, cols, labels)
    local x = 0
    for i, c in ipairs(cols or {}) do
        local w = c.w or c.min or 80
        local fs = labels[i]
        fs:ClearAllPoints()
        fs:SetPoint("LEFT", header, "LEFT", x + 4, 0)
        fs:SetWidth(w - 8)
        fs:SetHeight(24)
        x = x + w
    end
end

-- ===== Row =====
function UI.LayoutRow(row, cols, fields)
    local x = 0
    for _, c in ipairs(cols or {}) do
        local w = c.w or c.min or 80
        local f = fields[c.key]
        if f then
            f:ClearAllPoints()
            f:SetPoint("LEFT", row, "LEFT", x + 4, 0)
            if f.SetWidth  then f:SetWidth(w - 8) end
            if f.SetHeight then f:SetHeight(UI.ROW_H) end
            if f.SetJustifyH and c.justify then f:SetJustifyH(c.justify) end
            -- Empêche le débordement visuel/interaction hors cellule
            if f.SetClipsChildren then pcall(f.SetClipsChildren, f, true) end
        end

        x = x + w
    end
end

-- ===== Décor & Scroll =====
function UI.DecorateRow(r)
    local bg = r:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(1,1,1,0.03)
    bg:SetAllPoints(r)
    r._bg = bg
end

function UI.CreateScroll(parent)
    local scroll = CreateFrame("ScrollFrame", nil, parent, "UIPanelScrollFrameTemplate")
    local list = CreateFrame("Frame", nil, scroll)
    scroll:SetScrollChild(list)
    list:SetPoint("TOPLEFT")
    list:SetPoint("TOPRIGHT")
    list:SetHeight(1)
    return scroll, list
end

-- Cadre utile pour le contenu : respecte les insets de la skin + safe pads
-- opts: { side = number (def 10), bottom = number (def 6), top = number (def 0) }
function UI.ApplySafeContentBounds(frame, opts)
    opts = opts or {}
    local side  = tonumber(opts.side)   or 10
    local topEx = tonumber(opts.top)    or 0
    local botEx = tonumber(opts.bottom) or 6

    local parent = frame:GetParent()
    local skin   = parent and parent._cdzNeutral
    local L,R,T,B = UI.OUTER_PAD, UI.OUTER_PAD, UI.OUTER_PAD, UI.OUTER_PAD

    if skin and skin.GetInsets then
        L,R,T,B = skin:GetInsets()
    end

    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT",     parent, "TOPLEFT",     L + side, -(T + topEx))
    frame:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -(R + side),  B + botEx)
end

-- Normalisation légère des colonnes (justif/tailles par type)
function UI.NormalizeColumns(cols)
    local out = {}
    for i, c in ipairs(cols or {}) do
        local cc = {}
        for k,v in pairs(c) do cc[k]=v end
        local key  = tostring(cc.key or "")
        local tit  = cc.title or cc.key or ""
        cc.min = cc.min or cc.w or 80

        if key=="act" then
            cc.justify = cc.justify or "CENTER"
            cc.w = cc.w or 200
        elseif key=="qty" or key=="count" then
            cc.justify = cc.justify or "CENTER"
        elseif key=="amount" or key=="total" or key=="per" or key=="solde" then
            cc.justify = cc.justify or "RIGHT"
        else
            cc.justify = cc.justify or "LEFT"
        end
        cc.title = tit
        out[i] = cc
    end
    return out
end

-- Footer générique attaché au bas d’un panel
function UI.CreateFooter(parent, height)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(height or 36)
    f:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
    f:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -((UI.SCROLLBAR_W or 20) + (UI.SCROLLBAR_INSET or 0)), 0)

    -- Fond distinct
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetColorTexture(1, 1, 1, 0.05)
    bg:SetAllPoints(f)

    -- Liseré haut
    local line = f:CreateTexture(nil, "BORDER")
    line:SetColorTexture(1, 1, 1, 0.08)
    line:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 1)
    line:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 1)
    line:SetHeight(1)

    return f
end

-- Nom + icône de classe
function UI.CreateNameTag(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(16,16)
    f.icon:SetPoint("LEFT", f, "LEFT", 0, 0)
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.text:SetJustifyH("LEFT")
    f.text:SetPoint("LEFT", f.icon, "RIGHT", 3, 0) -- padding réduit
    f.text:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    return f
end


function UI.SetNameTag(tag, name)
    if not tag then return end
    local class, r, g, b, coords = nil, 1,1,1,nil
    if CDZ and CDZ.GetNameStyle then class, r, g, b, coords = CDZ.GetNameStyle(name) end
    if tag.text then tag.text:SetText(name or "") tag.text:SetTextColor(r or 1, g or 1, b or 1) end
    if tag.icon and coords then
        tag.icon:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CharacterCreate-Classes")
        tag.icon:SetTexCoord(coords[1], coords[2], coords[3], coords[4])
        tag.icon:Show()
    elseif tag.icon then
        tag.icon:SetTexture(nil)
        tag.icon:Hide()
    end
end

function UI.ClassIconMarkup(classTag, size)
    if not classTag or not CLASS_ICON_TCOORDS or not CLASS_ICON_TCOORDS[classTag] then return "" end
    local c = CLASS_ICON_TCOORDS[classTag]
    local l, r, t, b = math.floor(c[1]*256), math.floor(c[2]*256), math.floor(c[3]*256), math.floor(c[4]*256)
    local s = tonumber(size) or 14
    return string.format("|TInterface\\GLUES\\CHARACTERCREATE\\UI-CharacterCreate-Classes:%d:%d:0:0:256:256:%d:%d:%d:%d|t", s, s, l, r, t, b)
end
