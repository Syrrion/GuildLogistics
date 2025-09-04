local ADDON, ns = ...
ns.UI = ns.UI or {}
local UI = ns.UI

-- Tick/throttle par frame pour éviter les resnaps multiples.
if not UI._tickFrame then
    UI._tick = 0
    UI._tickFrame = CreateFrame("Frame")
    UI._tickFrame:SetScript("OnUpdate", function()
        UI._tick = (UI._tick + 1) % 1000000000
    end)
end

-- Calcule la taille d'un pixel physique selon la résolution et l'échelle effective (UIParent).
function UI.GetPhysicalPixel()
    local _, ph = GetPhysicalScreenSize()
    local scale = (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale()) or 1
    if not ph or ph <= 0 then ph = 768 end
    if not scale or scale <= 0 then scale = 1 end
    return 768 / ph / scale
end

-- Arrondit 'v' à l'incrément d'un pixel physique (référence UIParent).
function UI.RoundToPixel(v)
    local p = UI.GetPhysicalPixel()
    return math.floor((v / p) + 0.5) * p
end

-- Retourne la taille d'un pixel physique à l'échelle effective d'une région donnée.
function UI.GetPhysicalPixelFor(region)
    local _, ph = GetPhysicalScreenSize()
    local eff = (region and region.GetEffectiveScale and region:GetEffectiveScale())
             or (UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale())
             or 1
    if not ph or ph <= 0 then ph = 768 end
    if not eff or eff <= 0 then eff = 1 end
    return 768 / ph / eff
end

-- Arrondit 'v' au pixel pour la région spécifiée (évite les sous-pixels lorsque scalée).
function UI.RoundToPixelOn(region, v)
    local p = UI.GetPhysicalPixelFor(region)
    return math.floor((v / p) + 0.5) * p
end

-- Active l'accroche "pixel-perfect" sur une texture et neutralise le bias.
function UI.SnapTexture(tex)
    if tex and tex.SetSnapToPixelGrid then
        tex:SetSnapToPixelGrid(true)
        tex:SetTexelSnappingBias(0)
    end
    return tex
end

-- Aligne une région au pixel (taille + points d'ancrage), throttle 1x/frame par région.
function UI.SnapRegion(region)
    if not region then return end
    if region.IsVisible and not region:IsVisible() then return end

    UI._tick = UI._tick or 0
    if region._lastSnapTick and region._lastSnapTick == UI._tick then
        return
    end
    region._lastSnapTick = UI._tick

    local function Q(v)
        if UI.RoundToPixelOn then return UI.RoundToPixelOn(region, v) end
        return UI.RoundToPixel(v)
    end

    local w, h = region:GetSize()
    if w and w > 0 then
        local qw = Q(w)
        if PixelUtil and PixelUtil.SetWidth then PixelUtil.SetWidth(region, qw) else region:SetWidth(qw) end
    end
    if h and h > 0 then
        local qh = Q(h)
        if PixelUtil and PixelUtil.SetHeight then PixelUtil.SetHeight(region, qh) else region:SetHeight(qh) end
    end

    local n = region:GetNumPoints()
    if n and n > 0 then
        for i = 1, n do
            local p, rel, rp, x, y = region:GetPoint(i)
            if p then
                local nx, ny = Q(x or 0), Q(y or 0)
                if (not x) or (not y)
                   or math.abs((x or 0) - nx) > 1e-3
                   or math.abs((y or 0) - ny) > 1e-3 then
                    if PixelUtil and PixelUtil.SetPoint then
                        PixelUtil.SetPoint(region, p, rel, rp, nx, ny)
                    else
                        region:SetPoint(p, rel, rp, nx, ny)
                    end
                end
            end
        end
    end
end

-- Fixe l'épaisseur verticale d'une ligne à 'n' pixels physiques exacts.
function UI.SetPixelThickness(tex, n)
    n = n or 1
    local h = (UI.GetPhysicalPixelFor and UI.GetPhysicalPixelFor(tex) or UI.GetPhysicalPixel()) * n
    if PixelUtil and PixelUtil.SetHeight then PixelUtil.SetHeight(tex, h) else tex:SetHeight(h) end
end

-- Fixe la largeur horizontale d'une ligne à 'n' pixels physiques exacts.
function UI.SetPixelWidth(tex, n)
    n = n or 1
    local w = (UI.GetPhysicalPixelFor and UI.GetPhysicalPixelFor(tex) or UI.GetPhysicalPixel()) * n
    if PixelUtil and PixelUtil.SetWidth then PixelUtil.SetWidth(tex, w) else tex:SetWidth(w) end
end

-- Met le point uniquement si différent du point actuel (évite un relayout inutile)
function UI.SetPointIfChanged(f, point, relativeTo, relativePoint, xOfs, yOfs)
    if not (f and f.GetPoint) then return false end
    local p1, rel, p2, x, y = f:GetPoint(1)
    local same =
        (p1 == point)
        and (rel == relativeTo)
        and (p2 == relativePoint)
        and (math.floor(tonumber(x) or 0) == math.floor(tonumber(xOfs) or 0))
        and (math.floor(tonumber(y) or 0) == math.floor(tonumber(yOfs) or 0))
    if same then
        return false
    end
    f:ClearAllPoints()
    if PixelUtil and PixelUtil.SetPoint then
        PixelUtil.SetPoint(f, point, relativeTo, relativePoint, xOfs, yOfs)
    else
        f:SetPoint(point, relativeTo, relativePoint, xOfs, yOfs)
    end
    return true
end

-- Variante pratique : applique 2 points (TOPLEFT/RIGHT, TOPLEFT/BOTTOMLEFT, etc.) uniquement si changement
function UI.SetPoints2IfChanged(f, p1, p2)
    if not (f and f.GetPoint and p1 and p2) then return false end
    local c1 = { f:GetPoint(1) }
    local c2 = { f:GetPoint(2) }

    local function same(a, b)
        if not a or not b then return false end
        return (a[1] == b[1]) and (a[2] == b[2]) and (a[3] == b[3])
           and (math.floor(tonumber(a[4]) or 0) == math.floor(tonumber(b[4]) or 0))
           and (math.floor(tonumber(a[5]) or 0) == math.floor(tonumber(b[5]) or 0))
    end

    local unchanged = same(c1, p1) and same(c2, p2)
    if unchanged then return false end

    f:ClearAllPoints()
    if PixelUtil and PixelUtil.SetPoint then
        PixelUtil.SetPoint(f, p1[1], p1[2], p1[3], p1[4], p1[5])
        PixelUtil.SetPoint(f, p2[1], p2[2], p2[3], p2[4], p2[5])
    else
        f:SetPoint(p1[1], p1[2], p1[3], p1[4], p1[5])
        f:SetPoint(p2[1], p2[2], p2[3], p2[4], p2[5])
    end
    return true
end
