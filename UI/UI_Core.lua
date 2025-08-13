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
    f:SetHeight(height or UI.FOOTER_H or 36)
    f:SetPoint("BOTTOMLEFT",  parent, "BOTTOMLEFT",  0, 0)
    f:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0) -- pleine largeur

    -- Fond sombre (zone d'action)
    local bg = f:CreateTexture(nil, "BACKGROUND")
    local c  = UI.FOOTER_BG or {0, 0, 0, 0.22}
    bg:SetColorTexture(c[1], c[2], c[3], c[4])
    bg:SetAllPoints(f)

    -- Léger dégradé vertical pour du relief
    local grad = f:CreateTexture(nil, "BACKGROUND")
    grad:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    grad:SetAllPoints(f)
    local gt = UI.FOOTER_GRAD_TOP    or {1, 1, 1, 0.05}
    local gb = UI.FOOTER_GRAD_BOTTOM or {0, 0, 0, 0.15}
    if grad.SetGradient then
        grad:SetGradient("VERTICAL", CreateColor(gt[1], gt[2], gt[3], gt[4]), CreateColor(gb[1], gb[2], gb[3], gb[4]))
    elseif grad.SetGradientAlpha then
        grad:SetGradientAlpha("VERTICAL", gt[1], gt[2], gt[3], gt[4], gb[1], gb[2], gb[3], gb[4])
    end

    -- Liseré supérieur (séparation nette)
    local line = f:CreateTexture(nil, "BORDER")
    local lb = UI.FOOTER_BORDER or {1, 1, 1, 0.12}
    line:SetColorTexture(lb[1], lb[2], lb[3], lb[4])
    line:SetPoint("TOPLEFT",  f, "TOPLEFT",  0, 1)
    line:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 1)
    line:SetHeight(1)

    return f
end

-- ➕ Pastille (badge) réutilisable
UI.BADGE_BG       = UI.BADGE_BG       or {0.92, 0.22, 0.22, 1.0}  -- rouge un peu plus saturé
UI.BADGE_TEXT     = UI.BADGE_TEXT     or "GameFontWhiteSmall"
UI.BADGE_INSET_X  = UI.BADGE_INSET_X  or 6
UI.BADGE_OFFSET_X = UI.BADGE_OFFSET_X or -6
UI.BADGE_OFFSET_Y = UI.BADGE_OFFSET_Y or  6
UI.BADGE_MAX      = UI.BADGE_MAX      or 99
UI.BADGE_SHADOW_A = UI.BADGE_SHADOW_A or 0.35                     -- ombre portée pour le contraste

function UI.AttachBadge(frame)
    if frame._badge then return frame._badge end
    local b = CreateFrame("Frame", nil, frame)
    b:SetFrameStrata(frame:GetFrameStrata() or "MEDIUM")
    b:SetFrameLevel((frame:GetFrameLevel() or 0) + 10)
    b:SetPoint("TOPRIGHT", frame, "TOPRIGHT", UI.BADGE_OFFSET_X, UI.BADGE_OFFSET_Y)
    b:Hide()

    -- Ombre circulaire (pour le contraste)
    b.shadow = b:CreateTexture(nil, "BACKGROUND")
    b.shadow:SetColorTexture(0, 0, 0, UI.BADGE_SHADOW_A)

    -- Fond de la pastille
    b.bg = b:CreateTexture(nil, "ARTWORK")
    local c = UI.BADGE_BG
    b.bg:SetColorTexture(c[1], c[2], c[3], c[4])

    -- Masque circulaire commun (même masque pour ombre + fond)
    if b.CreateMaskTexture and b.bg.AddMaskTexture then
        local mask = b:CreateMaskTexture(nil, "BACKGROUND")
        mask:SetTexture("Interface/CHARACTERFRAME/TempPortraitAlphaMask") -- masque rond natif
        mask:SetAllPoints(b)

        b.bg:AddMaskTexture(mask)
        b.shadow:AddMaskTexture(mask)
        b._mask = mask
    end

    -- Texte lisible (blanc + ombre)
    b.txt = b:CreateFontString(nil, "OVERLAY", UI.BADGE_TEXT)
    b.txt:SetPoint("CENTER", b, "CENTER")
    if b.txt.SetTextColor then b.txt:SetTextColor(1,1,1) end
    if b.txt.SetShadowColor then b.txt:SetShadowColor(0,0,0,0.9) end
    if b.txt.SetShadowOffset then b.txt:SetShadowOffset(1, -1) end

    function b:SetCount(n)
        n = tonumber(n) or 0
        if n <= 0 then self:Hide(); return end

        local max = UI.BADGE_MAX
        local s = (n > max) and (tostring(max) .. "+") or tostring(n)
        self.txt:SetText(s)

        local pad = UI.BADGE_INSET_X
        local w = math.ceil(self.txt:GetStringWidth()) + pad * 2
        local h = math.ceil(self.txt:GetStringHeight()) + 2

        -- Pastille parfaitement circulaire : diamètre = max(w,h,16)
        local d = math.max(16, w, h)
        self:SetSize(d, d)

        -- Fond + ombre suivent la taille du cadre (ombre légèrement plus large)
        self.bg:ClearAllPoints()
        self.bg:SetAllPoints(self)

        self.shadow:ClearAllPoints()
        self.shadow:SetPoint("CENTER", self, "CENTER", 0, 0)
        self.shadow:SetSize(d + 3, d + 3)

        self:Show()
    end

    frame._badge = b
    return b
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

function UI.RaiseCloseButton(btn, owner)
    local f = owner or btn:GetParent()
    btn:SetFrameStrata("TOOLTIP")
    btn:SetFrameLevel((f and f:GetFrameLevel() or 1) + 10)
end

-- Affichage d'or (valeur en or entiers)
function UI.MoneyText(gold)
    local n = math.floor(tonumber(gold) or 0)
    if BreakUpLargeNumbers then
        return BreakUpLargeNumbers(n).." po"
    end
    local s = tostring(n)
    local left, num, right = s:match("^([^%d]*%d)(%d*)(.-)$")
    return (left..(num:reverse():gsub("(%d%d%d)","%1 "):reverse())..right):gsub("^%s+",""):gsub("%s+$","").." po"
end

-- Affichage détaillé depuis des pièces de cuivre
function UI.MoneyFromCopper(copper)
    local c = math.floor(tonumber(copper) or 0)
    local g = math.floor(c / 10000)
    local s = math.floor((c % 10000) / 100)
    local cp = c % 100
    local out = {}
    if g > 0 then table.insert(out, UI.MoneyText(g)) end
    if s > 0 then table.insert(out, s.." pa") end
    if cp > 0 or #out == 0 then table.insert(out, cp.." pc") end
    return table.concat(out, " ")
end

-- ========== UTIL: Format (ex-Format.lua) ==========
ns.Format = ns.Format or {}
do
    local F = ns.Format

    function F.DateTime(ts, fmt)
        local n = tonumber(ts) or 0
        if n > 0 then return date(fmt or "le %H:%M à %d/%m/%Y", n) end
        return tostring(ts or "")
    end

    function F.Date(ts, fmt)
        local n = tonumber(ts) or 0
        if n > 0 then return date(fmt or "le %d/%m/%Y", n) end
        return tostring(ts or "")
    end

    function F.RelativeFromSeconds(sec)
        local n = tonumber(sec); if not n then return "" end
        local s = math.abs(n)
        local d = math.floor(s/86400); s = s%86400
        local h = math.floor(s/3600);  s = s%3600
        local m = math.floor(s/60)
        if d > 0 then return (d.."j "..h.."h") end
        if h > 0 then return (h.."h "..m.."m") end
        return (m.."m")
    end

    function F.LastSeen(days, hours)
        local d = tonumber(days)
        local h = tonumber(hours)

        if d and d <= 0 then
            if h and h > 0 then return h .. " h" else return "≤ 1 h" end
        end

        d = d or 9999
        if d < 1 then
            if h and h > 0 then return h .. " h" else return "≤ 1 h" end
        elseif d < 30 then
            return d .. " j"
        elseif d < 365 then
            return (math.floor(d/30)) .. " mois"
        else
            return (math.floor(d/365)) .. " ans"
        end
    end
end
-- (Fin ex-Format.lua)  :contentReference[oaicite:4]{index=4}

-- ========== MINIMAP (ex-Minimap.lua) ==========
function CDZ.Minimap_Init()
    if CDZ._EnsureDB then CDZ._EnsureDB() end
    ChroniquesDuZephyrUI = ChroniquesDuZephyrUI or {}
    ChroniquesDuZephyrUI.minimap = ChroniquesDuZephyrUI.minimap or { hide=false, angle=215 }
    if ChroniquesDuZephyrUI.minimap.angle == nil then
        ChroniquesDuZephyrUI.minimap.angle = 215
    end
    if ChroniquesDuZephyrUI.minimap.hide then return end

    if _G.CDZ_MinimapButton then
        local r = (Minimap:GetWidth() / 2) - 5
        local rad = math.rad(ChroniquesDuZephyrUI.minimap.angle or 215)
        _G.CDZ_MinimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * r, math.sin(rad) * r)
        return
    end

    local b = CreateFrame("Button", "CDZ_MinimapButton", Minimap)
    b:SetSize(32, 32)
    b:SetFrameStrata("MEDIUM")
    b:SetMovable(true)
    b:RegisterForDrag("LeftButton")
    b:RegisterForClicks("AnyUp")

    local border = b:CreateTexture(nil, "BACKGROUND")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(56, 56)
    border:SetPoint("TOPLEFT", b, "TOPLEFT", -7, 6)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\ICONS\\INV_Misc_QuestionMark")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetSize(20, 20)
    icon:SetPoint("CENTER", b, "CENTER", 0, 0)

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
    b:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function(btn)
            local mx, my = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            local dx, dy = (cx/scale - mx), (cy/scale - my)
            local angle = math.deg(math.atan2(dy, dx))
            if angle < 0 then angle = angle + 360 end
            ChroniquesDuZephyrUI.minimap.angle = angle
            local r = (Minimap:GetWidth() / 2) - 5
            local rad = math.rad(angle or 215)
            btn:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * r, math.sin(rad) * r)
        end)
    end)
    b:SetScript("OnDragStop",  function(self) self:SetScript("OnUpdate", nil) end)

    -- Clic : toggle UI
    b:SetScript("OnClick", function() if ns.ToggleUI then ns.ToggleUI() end end)

    local r = (Minimap:GetWidth() / 2) - 5
    local rad = math.rad(ChroniquesDuZephyrUI.minimap.angle or 215)
    b:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * r, math.sin(rad) * r)
end
-- (Fin ex-Minimap.lua)  :contentReference[oaicite:5]{index=5}
