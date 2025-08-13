local ADDON, ns = ...
ns.UI = ns.UI or {}
local UI = ns.UI

-- Insets par défaut (zone de contenu interne)
UI.NEUTRAL_INSETS = UI.NEUTRAL_INSETS or { left=24, right=24, top=72, bottom=24 }

-- ---------- Génération dynamique des atlas par thème ----------
local _THEME_CACHE = {}

local function ucfirst(s) return s:sub(1,1):upper()..s:sub(2):lower() end
local function atlasExists(name)
    if not name then return false end
    return C_Texture and C_Texture.GetAtlasInfo and (C_Texture.GetAtlasInfo(name) ~= nil)
end

local function normalizeTag(tag)
    local t = tostring(tag or "NEUTRAL")
    if t:upper() == "AUTO" then
        local f = UnitFactionGroup and UnitFactionGroup("player")
        if f == "Alliance" then return "ALLIANCE" end
        if f == "Horde"    then return "HORDE" end
        return "NEUTRAL"
    end
    return t:upper()
end

local function buildTheme(tagU)
    local cap = ucfirst(tagU:lower()) -- "NEUTRAL" -> "Neutral"
    local T = {
        corner     = cap.."-NineSlice-Corner",
        edgeTop    = "_"..cap.."-NineSlice-EdgeTop",
        edgeBottom = "_"..cap.."-NineSlice-EdgeBottom",
        titleLeft  = "UI-Frame-"..cap.."-TitleLeft",
        titleRight = "UI-Frame-"..cap.."-TitleRight",
        titleMid   = "_UI-Frame-"..cap.."-TitleMiddle",
        ribbon     = "UI-Frame-"..cap.."-Ribbon",
        header     = "UI-Frame-"..cap.."-Header",
        bgTile     = "UI-Frame-"..cap.."-BackgroundTile",
        parchment  = "UI-Frame-"..cap.."-CardParchment",
    }

    for k,v in pairs(T) do if not atlasExists(v) then T[k] = nil end end
    if not T.parchment then
        T.parchment = atlasExists("UI-Frame-Neutral-CardParchment") and "UI-Frame-Neutral-CardParchment" or nil
    end
    return T
end

local function getTheme()
    local tagU = normalizeTag(UI.FRAME_THEME or "NEUTRAL")
    if not _THEME_CACHE[tagU] then _THEME_CACHE[tagU] = buildTheme(tagU) end
    return _THEME_CACHE[tagU]
end

local function fallback(atlas, neutral)
    return atlas or neutral
end

-- Stratas utilitaires (version locale)
local _STRATA_ORDER = { "BACKGROUND","LOW","MEDIUM","HIGH","DIALOG","FULLSCREEN","FULLSCREEN_DIALOG","TOOLTIP" }
local _STRATA_INDEX = {}; for i,n in ipairs(_STRATA_ORDER) do _STRATA_INDEX[n]=i end
local function PrevStrata(name)
    local idx = _STRATA_INDEX[name or "HIGH"] or _STRATA_INDEX.HIGH
    return _STRATA_ORDER[ math.max(idx-1, 1) ]
end
local function NextStrata(name)  -- AJOUT
    local idx = _STRATA_INDEX[name or "HIGH"] or _STRATA_INDEX.HIGH
    return _STRATA_ORDER[ math.min(idx+1, #_STRATA_ORDER) ]
end


-- Frame underlay: sibling toujours SOUS le frame (utile pour les ombres hors clip)
local function EnsureUnderlay(frame)
    if frame._cdzUnderlay then return frame._cdzUnderlay end
    local uv = CreateFrame("Frame", nil, UIParent)
    uv:SetClipsChildren(false)
    uv:SetPoint("TOPLEFT",     frame, "TOPLEFT")
    uv:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")
    local function sync()
        local fs = frame:GetFrameStrata() or "HIGH"
        uv:SetFrameStrata( PrevStrata(fs) )                  -- une strata en dessous
        uv:SetFrameLevel( math.max((frame:GetFrameLevel() or 1) - 1, 1) )
    end
    sync()
    frame:HookScript("OnShow", function() uv:Show(); sync() end)
    frame:HookScript("OnHide", function() uv:Hide() end)
    frame:HookScript("OnUpdate", sync)
    frame._cdzUnderlay = uv
    return uv
end

-- Helper gradient (compat 10.x/11.x)
local function SetSoftGradient(tex, orientation, aOuter, aInner)
    tex:SetColorTexture(0,0,0,1)
    if tex.SetGradient then
        tex:SetGradient(orientation, CreateColor(0,0,0,aOuter), CreateColor(0,0,0,aInner))
    else
        tex:SetGradientAlpha(orientation, 0,0,0,aOuter, 0,0,0,aInner)
    end
end

-- Masque circulaire pour coins arrondis (quarter-circle)
local CORNER_MASK_TEX = "Interface/CHARACTERFRAME/TempPortraitAlphaMask"
local function MakeMaskedCorner(parent)
    local t = parent:CreateTexture(nil, "BACKGROUND")
    if parent.CreateMaskTexture and t.AddMaskTexture then
        local m = parent:CreateMaskTexture(nil, "BACKGROUND") -- corrige: créé par le parent, pas par la texture
        m:SetTexture(CORNER_MASK_TEX)
        m:SetAllPoints(t)
        t:AddMaskTexture(m)
        t._cdzMask = m -- on garde une référence pour régler le quadrant
    end
    return t
end

-- Définir le quadrant du masque (TL/TR/BL/BR)
local function SetCornerMaskQuad(tex, corner)
    local m = tex and tex._cdzMask
    if not (m and m.SetTexCoord) then return end
    if corner == "TOPLEFT" then
        m:SetTexCoord(0, 0.5, 0, 0.5)
    elseif corner == "TOPRIGHT" then
        m:SetTexCoord(0.5, 1, 0, 0.5)
    elseif corner == "BOTTOMLEFT" then
        m:SetTexCoord(0, 0.5, 0.5, 1)
    else -- "BOTTOMRIGHT"
        m:SetTexCoord(0.5, 1, 0.5, 1)
    end
end


-- Overlay sibling commun, ancré au frame et toujours au-dessus de lui
local function EnsureOverlay(frame)
    if frame._cdzOverlay then return frame._cdzOverlay end
    local ov = CreateFrame("Frame", nil, UIParent)
    ov:SetClipsChildren(false)
    ov:SetPoint("TOPLEFT",     frame, "TOPLEFT")
    ov:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT")
    local function sync()
        local fs = frame:GetFrameStrata() or "HIGH"
        ov:SetFrameStrata( NextStrata(fs) )                -- une strata au-dessus du frame
        ov:SetFrameLevel( (frame:GetFrameLevel() or 1) )   -- level suffisant (strata > prime)
    end
    sync()
    frame:HookScript("OnShow", function() ov:Show(); sync() end)
    frame:HookScript("OnHide", function() ov:Hide() end)
    frame:HookScript("OnUpdate", sync)
    frame._cdzOverlay = ov
    return ov
end

-- Rognage en pixels d'un atlas, sans étirer (conserve le ratio via targetH)
local function CropAtlasPx(tex, atlas, cropLeft, cropRight, targetH)
    cropLeft, cropRight = cropLeft or 0, cropRight or 0
    tex:SetAtlas(atlas, true)
    local ai = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
    if not ai then return end
    local u0, u1 = ai.leftTexCoord, ai.rightTexCoord
    local v0, v1 = ai.topTexCoord,  ai.bottomTexCoord
    local du     = (u1 - u0) / (ai.width or 1)
    local uL     = u0 + du * cropLeft
    local uR     = u1 - du * cropRight
    tex:SetTexCoord(uL, uR, v0, v1)
    local srcW   = (ai.width or 0)  - cropLeft - cropRight
    local srcH   = (ai.height or 1)
    if targetH and targetH > 0 then
        local scale = targetH / srcH
        tex:SetSize(math.max(1, math.floor(srcW * scale + 0.5)), math.floor(targetH + 0.5))
    else
        tex:SetSize(math.max(1, srcW), srcH)
    end
end


-- ---------- Skin principal (thème-aware) ----------
-- opts: { insets?=table, showRibbon?=bool, titleMidExtend?=number }
function UI.ApplyNeutralFrameSkin(frame, opts)
    opts = opts or {}
    if frame._cdzNeutral then return frame._cdzNeutral end

    local T = getTheme()
    local INS = {
        left   = (opts.insets and opts.insets.left)   or UI.NEUTRAL_INSETS.left,
        right  = (opts.insets and opts.insets.right)  or UI.NEUTRAL_INSETS.right,
        top    = (opts.insets and opts.insets.top)    or UI.NEUTRAL_INSETS.top,
        bottom = (opts.insets and opts.insets.bottom) or UI.NEUTRAL_INSETS.bottom,
    }

    local EDGE_H, TITLE_H, CORNER_S = 30, 85, 28
    local layerBG, layerEdge, layerTitle = "BACKGROUND", "BORDER", "ARTWORK"
    local skin = {}
    frame:SetClipsChildren(true)

    -- Fond (tile si possible, sinon parchemin, sinon couleur)
    local bg = frame:CreateTexture(nil, layerBG)
    bg:SetPoint("TOPLEFT",     frame, "TOPLEFT",     INS.left,  -INS.top)
    bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -INS.right,  INS.bottom)
    if T.bgTile then
        bg:SetAtlas(T.bgTile, true)
        bg:SetHorizTile(true); bg:SetVertTile(true)
    elseif T.parchment then
        bg:SetAtlas(T.parchment, true)
        bg:SetHorizTile(false); bg:SetVertTile(false)
    else
        bg:SetColorTexture(0,0,0,0.30)
    end
    skin.bg = bg

    -- Coins
    local overlay = EnsureOverlay(frame)

    local tl = overlay:CreateTexture(nil, "OVERLAY"); tl:SetSize(CORNER_S, CORNER_S)
    tl:SetDrawLayer("OVERLAY", 2)
    tl:SetPoint("TOPLEFT", overlay, "TOPLEFT")
    tl:SetAtlas(fallback(T.corner, "Neutral-NineSlice-Corner"), true)

    local tr = overlay:CreateTexture(nil, "OVERLAY"); tr:SetSize(CORNER_S, CORNER_S)
    tr:SetDrawLayer("OVERLAY", 2)
    tr:SetPoint("TOPRIGHT", overlay, "TOPRIGHT")
    tr:SetAtlas(fallback(T.corner, "Neutral-NineSlice-Corner"), true)
    tr:SetRotation(math.rad(-90))

    local bl = overlay:CreateTexture(nil, "OVERLAY"); bl:SetSize(CORNER_S, CORNER_S)
    bl:SetDrawLayer("OVERLAY", 2)
    bl:SetPoint("BOTTOMLEFT", overlay, "BOTTOMLEFT")
    bl:SetAtlas(fallback(T.corner, "Neutral-NineSlice-Corner"), true)
    bl:SetRotation(math.rad(90))

    local br = overlay:CreateTexture(nil, "OVERLAY"); br:SetSize(CORNER_S, CORNER_S)
    br:SetDrawLayer("OVERLAY", 2)
    br:SetPoint("BOTTOMRIGHT", overlay, "BOTTOMRIGHT")
    br:SetAtlas(fallback(T.corner, "Neutral-NineSlice-Corner"), true)
    br:SetRotation(math.rad(180))

    skin.corners = {tl=tl,tr=tr,bl=bl,br=br}


    -- Arête haute (au-dessus de tout le titre, même si TitleMid passe en sublevel élevé)
    local top = frame:CreateTexture(nil, "ARTWORK")
    top:SetDrawLayer("ARTWORK", 3)
    top:SetPoint("TOPLEFT",  tl, "TOPRIGHT", 0, 0)
    top:SetPoint("TOPRIGHT", tr, "TOPLEFT",  0, 0)
    top:SetHeight(EDGE_H)
    top:SetAtlas(fallback(T.edgeTop, "_Neutral-NineSlice-EdgeTop"), true)
    top:SetHorizTile(true)
    top:Show()


    local bottom = frame:CreateTexture(nil, layerEdge)
    bottom:SetPoint("BOTTOMLEFT",  bl, "BOTTOMRIGHT", 0, 0)
    bottom:SetPoint("BOTTOMRIGHT", br, "TOPLEFT",     0, 0)
    bottom:SetHeight(EDGE_H)
    bottom:SetAtlas(fallback(T.edgeBottom, "_Neutral-NineSlice-EdgeBottom"), true)
    bottom:SetHorizTile(true)

    -- Côtés (reconstruction via fichier du bas)
    local edgeAtlas = fallback(T.edgeBottom, "_Neutral-NineSlice-EdgeBottom")
    local info = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(edgeAtlas)
    local file = (info and info.file) or "Interface/FrameGeneral/UIFrameNeutral"
    local u0 = (info and info.leftTexCoord)   or 0.0
    local u1 = (info and info.rightTexCoord)  or 0.25
    local v0 = (info and info.topTexCoord)    or 0.117188
    local v1 = (info and info.bottomTexCoord) or 0.146484
    local sideW   = (info and info.height) or EDGE_H
    local tileLen = (info and info.width)  or 256

    skin.edges = { top=top, bottom=bottom }

    local function BuildSideContainer(anchor)
        local c = CreateFrame("Frame", nil, frame)
        c:SetClipsChildren(true)
        if anchor == "LEFT" then
            c:SetPoint("TOPLEFT",    tl, "BOTTOMLEFT",  0, 0)
            c:SetPoint("BOTTOMLEFT", bl, "TOPLEFT",     0, 0)
        else
            c:SetPoint("TOPRIGHT",   tr, "BOTTOMRIGHT", 0, 0)
            c:SetPoint("BOTTOMRIGHT",br, "TOPRIGHT",    0, 0)
        end
        c:SetWidth(sideW)
        return c
    end

    local function LayoutSide(container, isLeft)
        container._segs = container._segs or {}
        for _, t in ipairs(container._segs) do t:Hide() end
        local H = container:GetHeight()
        local count = math.ceil(H / tileLen)
        local y = 0
        local function seg(i)
            local t = container._segs[i]
            if not t then
                t = container:CreateTexture(nil, layerEdge)
                container._segs[i] = t
            end
            t:Show()
            t:SetTexture(file)
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT", container, "TOPLEFT", 0, -y)
            t:SetSize(sideW, tileLen)
            if isLeft then
                t:SetTexCoord(u0, v1,  u1, v1,  u0, v0,  u1, v0)
            else
                t:SetTexCoord(u1, v0,  u0, v0,  u1, v1,  u0, v1)
            end
            y = y + tileLen
            return t
        end
        for i=1, count do seg(i) end
    end

    local leftC  = BuildSideContainer("LEFT")
    local rightC = BuildSideContainer("RIGHT")
    LayoutSide(leftC,  true)
    LayoutSide(rightC, false)
    leftC:HookScript("OnSizeChanged",  function(self) LayoutSide(self,  true) end)
    rightC:HookScript("OnSizeChanged", function(self) LayoutSide(self, false) end)
    skin.edges.left  = leftC
    skin.edges.right = rightC

     -- Barre de titre
    local extend  = (opts.titleMidExtend ~= nil) and opts.titleMidExtend or 100
    local CROP_PX_LEFT = 70
    local CROP_PX_RIGHT = 65

    -- LEFT
    local tLeft  = frame:CreateTexture(nil, layerTitle)
    do
        local atlas = fallback(T.titleLeft, "UI-Frame-Neutral-TitleLeft")
        local ai = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
        if ai then
            local u0,u1,v0,v1 = ai.leftTexCoord, ai.rightTexCoord, ai.topTexCoord, ai.bottomTexCoord
            local du = (u1 - u0) / (ai.width or 1)
            tLeft:SetTexture(ai.file)
            tLeft:SetTexCoord(u0, u1 - du * (CROP_PX_LEFT), v0, v1) -- coupe à DROITE, pas d'inversion
            local scale = TITLE_H / (ai.height or TITLE_H)
            local croppedW = ((ai.width or 0) - CROP_PX_LEFT) * scale
            tLeft:SetSize(math.max(1, math.floor(croppedW + 0.5)), TITLE_H)
        else
            tLeft:SetAtlas(atlas, true)
            tLeft:SetHeight(TITLE_H)
        end
    end
    tLeft:SetDrawLayer(layerTitle, 2) -- au-dessus du centre
    tLeft:SetIgnoreParentAlpha(true)
    tLeft:SetPoint("TOPLEFT", frame, "TOPLEFT", INS.left-6, -8)

    -- RIGHT
    local tRight = frame:CreateTexture(nil, layerTitle)
    do
        local atlas = fallback(T.titleRight, "UI-Frame-Neutral-TitleRight")
        local ai = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas)
        if ai then
            local u0,u1,v0,v1 = ai.leftTexCoord, ai.rightTexCoord, ai.topTexCoord, ai.bottomTexCoord
            local du = (u1 - u0) / (ai.width or 1)
            tRight:SetTexture(ai.file)
            tRight:SetTexCoord(u0 + du * CROP_PX_RIGHT, u1, v0, v1) -- coupe à GAUCHE, pas d'inversion
            local scale = TITLE_H / (ai.height or TITLE_H)
            local croppedW = ((ai.width or 0) - CROP_PX_RIGHT) * scale
            tRight:SetSize(math.max(1, math.floor(croppedW + 0.5)), TITLE_H)
        else
            tRight:SetAtlas(atlas, true)
            tRight:SetHeight(TITLE_H)
        end
    end
    tRight:SetDrawLayer(layerTitle, 2) -- au-dessus du centre
    tRight:SetIgnoreParentAlpha(true)
    tRight:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(INS.right-6), -8)

    -- MID: sous les côtés, tuilé (aucune étire)
    local tMid = frame:CreateTexture(nil, layerTitle)
    tMid:SetAtlas(fallback(T.titleMid, "_UI-Frame-Neutral-TitleMiddle"), true)
    tMid:SetHorizTile(true)
    tMid:SetDrawLayer(layerTitle, 1) -- sous les côtés
    tMid:SetIgnoreParentAlpha(true)
    tMid:ClearAllPoints()
    tMid:SetPoint("TOPLEFT",  tLeft,  "TOPRIGHT", -extend, 0)
    tMid:SetPoint("TOPRIGHT", tRight, "TOPLEFT",   extend, 0)
    tMid:SetHeight(TITLE_H)

    -- Ombre portée autour du cadre (underlay sibling pour ne pas être clippée)
    do
        local under = EnsureUnderlay(frame)
        local size   = (opts.shadowSize  ~= nil) and opts.shadowSize  or 28  -- épaisseur
        local alpha  = (opts.shadowAlpha ~= nil) and opts.shadowAlpha or 0.35
        local inset2 = 2  -- rapproche de 2 px

        if not skin.shadow then
            skin.shadow = {
                left   = under:CreateTexture(nil, "BACKGROUND"),
                right  = under:CreateTexture(nil, "BACKGROUND"),
                top    = under:CreateTexture(nil, "BACKGROUND"),
                bottom = under:CreateTexture(nil, "BACKGROUND"),
                -- coins arrondis (2 couches par coin : H + V pour simuler un “radial” doux)
                tlH = MakeMaskedCorner(under), tlV = MakeMaskedCorner(under),
                trH = MakeMaskedCorner(under), trV = MakeMaskedCorner(under),
                blH = MakeMaskedCorner(under), blV = MakeMaskedCorner(under),
                brH = MakeMaskedCorner(under), brV = MakeMaskedCorner(under),
            }
        end
        local sh = skin.shadow

        local function LayoutShadow()
            -- LATERAUX (rapprochés de 2 px)
            sh.left:ClearAllPoints()
            sh.left:SetPoint("TOPLEFT",    under, "TOPLEFT",    -(size - inset2),  inset2)
            sh.left:SetPoint("BOTTOMLEFT", under, "BOTTOMLEFT", -(size - inset2), -inset2)
            sh.left:SetWidth(size)
            SetSoftGradient(sh.left, "HORIZONTAL", 0.0, alpha)    -- extérieur -> bord

            sh.right:ClearAllPoints()
            sh.right:SetPoint("TOPRIGHT",    under, "TOPRIGHT",    (size - inset2),  inset2)
            sh.right:SetPoint("BOTTOMRIGHT", under, "BOTTOMRIGHT", (size - inset2), -inset2)
            sh.right:SetWidth(size)
            SetSoftGradient(sh.right, "HORIZONTAL", alpha, 0.0)    -- bord -> extérieur

            -- HAUT / BAS : dégradé inversé demandé
            sh.top:ClearAllPoints()
            sh.top:SetPoint("TOPLEFT",  under, "TOPLEFT",   inset2,  (size - inset2))
            sh.top:SetPoint("TOPRIGHT", under, "TOPRIGHT", -inset2,  (size - inset2))
            sh.top:SetHeight(size)
            SetSoftGradient(sh.top, "VERTICAL", alpha, 0.0)        -- (inversé) extérieur -> plus clair vers l'extérieur

            sh.bottom:ClearAllPoints()
            sh.bottom:SetPoint("BOTTOMLEFT",  under, "BOTTOMLEFT",  inset2, -(size - inset2))
            sh.bottom:SetPoint("BOTTOMRIGHT", under, "BOTTOMRIGHT", -inset2, -(size - inset2))
            sh.bottom:SetHeight(size)
            SetSoftGradient(sh.bottom, "VERTICAL", 0.0, alpha)     -- (inversé) plus clair extérieur, plus dense vers le bord

            -- COINS ARRONDIS (quarter-circles), 2 couches (H+V) par coin
            local function Corner(tH, tV, point, xOff, yOff, horizOuterToInner, vertOuterToInner)
                -- taille carrée
                tH:ClearAllPoints(); tH:SetPoint(point, under, point, xOff, yOff); tH:SetSize(size, size)
                tV:ClearAllPoints(); tV:SetPoint(point, under, point, xOff, yOff); tV:SetSize(size, size)

                -- Appliquer le quadrant de masque selon le coin
                SetCornerMaskQuad(tH, point)
                SetCornerMaskQuad(tV, point)

                -- HORIZONTAL
                if horizOuterToInner then
                    SetSoftGradient(tH, "HORIZONTAL", 0.0, alpha)  -- extérieur -> bord
                else
                    SetSoftGradient(tH, "HORIZONTAL", alpha, 0.0)  -- bord -> extérieur
                end
                -- VERTICAL (inversé en haut/bas)
                if vertOuterToInner then
                    SetSoftGradient(tV, "VERTICAL", 0.0, alpha)    -- extérieur -> bord
                else
                    SetSoftGradient(tV, "VERTICAL", alpha, 0.0)    -- bord -> extérieur
                end
            end


            -- Offsets des coins (rapprochés de 2 px sur les deux axes)
            local xN, xP = -(size - inset2),  (size - inset2)
            local yN, yP = -(size - inset2),  (size - inset2)

            -- TL : extérieur = gauche/haut
            Corner(sh.tlH, sh.tlV, "TOPLEFT",  xN,  yP, true,  false)  -- H: ext->bord ; V: (haut) inversé
            -- TR : extérieur = droite/haut
            Corner(sh.trH, sh.trV, "TOPRIGHT", xP,  yP, false, false)  -- H: bord->ext ; V: (haut) inversé
            -- BL : extérieur = gauche/bas
            Corner(sh.blH, sh.blV, "BOTTOMLEFT",  xN,  yN, true,  true) -- H: ext->bord ; V: (bas)  inversé
            -- BR : extérieur = droite/bas
            Corner(sh.brH, sh.brV, "BOTTOMRIGHT", xP,  yN, false, true) -- H: bord->ext ; V: (bas)  inversé
        end

        LayoutShadow()
        frame:HookScript("OnSizeChanged", LayoutShadow)
    end

    skin.title = {left=tLeft, mid=tMid, right=tRight}

   -- Header décoratif (dans l’overlay, toujours au-dessus, inclus dans la zone de drag)
    if T.header and atlasExists(T.header) then
        local overlay = EnsureOverlay(frame)

        local hdr = overlay:CreateTexture(nil, "OVERLAY")
        hdr:SetDrawLayer("OVERLAY", 1) -- sous les coins (coins = OVERLAY,2)
        hdr:SetAtlas(T.header, true)
        hdr:ClearAllPoints()

        -- Offset selon le thème
        local HEADER_YOFF = { ALLIANCE = -30, HORDE = -35, NEUTRAL = 6 }
        local themeTag = normalizeTag(UI.FRAME_THEME or "NEUTRAL")
        local yOff = HEADER_YOFF[themeTag] or 6

        hdr:SetPoint("BOTTOM", overlay, "TOP", 0, yOff)
        skin.header = hdr

        -- Étendre la zone cliquable/drag pour inclure le header
        local headerH = 48
        local ai = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(T.header)
        if ai and ai.height then headerH = ai.height end
        if frame.SetHitRectInsets then
            local l, r, _, b = 0, 0, 0, 0
            frame:SetHitRectInsets(l, r, -(headerH + math.abs(yOff)), b)
        end
    end

    -- Ruban optionnel
    if opts.showRibbon and T.ribbon then
        local rib = frame:CreateTexture(nil, "OVERLAY")
        rib:SetAtlas(T.ribbon, true)
        rib:SetPoint("TOP", frame, "TOP", 0, -(INS.top - 6))
        skin.ribbon = rib
    end

    function skin:GetInsets() return INS.left, INS.right, INS.top, INS.bottom end

    frame._cdzNeutral = skin
    return skin
end
