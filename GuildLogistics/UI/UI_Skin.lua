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
    local ov = CreateFrame("Frame", nil, frame) -- parent = frame
    ov:SetClipsChildren(false)
    ov:EnableMouse(false)
    ov:SetAllPoints(frame)

    local function sync()
        ov:SetFrameStrata(frame:GetFrameStrata() or "HIGH")
        ov:SetFrameLevel((frame:GetFrameLevel() or 1) + 1) -- juste au-dessus du cadre, sous le X
    end
    sync()

    frame:HookScript("OnShow", function() ov:Show(); sync() end)
    frame:HookScript("OnHide", function() ov:Hide() end)

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

    -- ➕ on référence aussi les conteneurs des côtés pour pouvoir les nettoyer au reskin
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

    -- ➕ registre weak de toutes les frames skinnées
    UI._NEUTRAL_REG = UI._NEUTRAL_REG or setmetatable({}, { __mode = "k" })
    UI._NEUTRAL_REG[frame] = true

    frame._cdzNeutral = skin
    return skin
end

-- === Nouveau : fond tuilé générique (répétition horizontale/verticale) ===
function UI.ApplyTiledBackground(frame, texturePath, tileW, tileH, alpha)
    if not (frame and texturePath) then return end

    -- Crée/recycle la texture
    local bg = frame._cdzTiledBG
    if not (bg and bg.SetTexture) then
        bg = frame:CreateTexture(nil, "BACKGROUND")
        frame._cdzTiledBG = bg
    end

    -- Couche sûre (au-dessus d'autres BACKGROUND éventuels)
    bg:SetDrawLayer("BACKGROUND", 1)
    bg:ClearAllPoints()
    bg:SetAllPoints(frame)
    bg:SetTexture(texturePath)
    bg:SetAlpha(alpha or 1)

    -- ⚠️ Appels avec ":" (self passé correctement)
    if bg.SetHorizTile then bg:SetHorizTile(true) end
    if bg.SetVertTile  then bg:SetVertTile(true)  end

    -- Taille de tuile (plus “serré” pour éviter l'impression d'étirement)
    local TW = math.max(8, tonumber(tileW) or 256)
    local TH = math.max(8, tonumber(tileH) or 256)

    local function UpdateTexCoord()
        local w = math.max(1, frame:GetWidth()  or 1)
        local h = math.max(1, frame:GetHeight() or 1)
        -- >1 déclenche la répétition quand *Tile(true)
        bg:SetTexCoord(0, w / TW, 0, h / TH)
    end

    -- Réagit aux changements de taille + 1 passe différée
    frame:HookScript("OnSizeChanged", UpdateTexCoord)
    frame:HookScript("OnShow",        UpdateTexCoord)
    UpdateTexCoord()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, UpdateTexCoord)
    end

    return bg
end

-- ➕ Détruit proprement un skin existant (toutes les textures/segments)
function UI.DestroyNeutralSkin(frame)
    if not (frame and frame._cdzNeutral) then return end
    local s = frame._cdzNeutral

    local function hideTex(t)
        if not t then return end
        pcall(function() t:Hide() end)
        if t.SetTexture then pcall(function() t:SetTexture(nil) end) end
        if t.SetAtlas   then pcall(function() t:SetAtlas(nil)   end) end
        pcall(function() t:ClearAllPoints() end)
        pcall(function() t:SetParent(nil)   end)
    end
    local function clearSide(c)
        if not c then return end
        if c._segs then
            for _, tx in ipairs(c._segs) do hideTex(tx) end
        end
        c._segs = nil
        pcall(function() c:Hide() end)
    end

    -- Fond
    hideTex(s.bg)

    -- Coins
    if s.corners then for _,t in pairs(s.corners) do hideTex(t) end end

    -- Bords haut/bas + côtés
    if s.edges then
        hideTex(s.edges.top);  hideTex(s.edges.bottom)
        clearSide(s.edges.left); clearSide(s.edges.right)
    end

    -- Bandeau de titre (gauche/milieu/droite)
    if s.title then for _,t in pairs(s.title) do hideTex(t) end end

    -- Header décoratif + ruban
    hideTex(s.header)
    hideTex(s.ribbon)

    frame._cdzNeutral = nil
end

-- ➕ Re-skin propre d’une frame (détruit puis ré-applique)
function UI.ReskinNeutral(frame, opts)
    if not frame then return end
    UI.DestroyNeutralSkin(frame)
    UI.ApplyNeutralFrameSkin(frame, opts or { showRibbon = false })
end

-- ➕ Re-skin global de toutes les frames enregistrées
function UI.ReskinAllNeutral()
    if not UI._NEUTRAL_REG then return end
    for f in pairs(UI._NEUTRAL_REG) do
        if f and f.GetObjectType then
            UI.ReskinNeutral(f, { showRibbon = false })
        end
    end
    if UI._layout then UI._layout() end -- relance le layout des panneaux visibles
end

-- ➕ API publique : changer de thème et re-skin global immédiatement
function UI.SetTheme(tag)
    UI.FRAME_THEME = tostring(tag or "AUTO"):upper()
    UI.ReskinAllNeutral()
end

-- Styles de ListView (dégradé vertical, sans liseré)
function UI.GetListViewStyle()
    return {
        -- Lignes impaires
        oddTop        = { r = 0.20, g = 0.20, b = 0.20, a = 0.50 },
        oddBottom     = { r = 0.20, g = 0.20, b = 0.20, a = 0.10 },
        -- Lignes paires
        evenTop       = oddTop,
        evenBottom    = oddBottom,
        -- Survol & séparateur
        hover      = { r = 1.00, g = 0.82, b = 0.00, a = 0.06 },
        sep        = { r = 1.00, g = 1.00, b = 1.00, a = 0.1 },
        -- ➕ Couleur par défaut du liseré "même groupe"
        accent     = { r = 1.00, g = 0.82, b = 0.00, a = 0.90 }, -- jaune Blizzard
    }
end

function UI.GetListViewContainerColor()
    -- Couleur par défaut du fond englobant (header + contenu) des ListViews
    -- Légèrement opaque, neutre, et cohérent avec les dégradés de lignes.
    -- Ajustable facilement ici si besoin (théming futur).
    return { r = 0.0, g = 0.0, b = 0.0, a = 0.20 }
end


function UI.ApplyTiledBackdrop(frame, bgFile, tileSize, alpha, insets)
    if not (frame and frame.SetBackdrop and bgFile) then return end

    local bd = frame._cdzBD or {}
    bd.bgFile   = bgFile
    bd.edgeFile = nil
    bd.tile     = true
    bd.tileSize = tonumber(tileSize) or 256
    bd.edgeSize = 0
    bd.insets   = insets or bd.insets or { left = 0, right = 0, top = 0, bottom = 0 }

    frame._cdzBD = bd
    frame:SetBackdrop(bd)
    frame:SetBackdropColor(1, 1, 1, alpha or 1) -- alpha facultatif

    return bd
end

-- Applique une "opacité visuelle" à une frame skinnée (fonds/bordures uniquement)
function UI.SetFrameVisualOpacity(frame, a)
    a = tonumber(a or 1) or 1
    if a < 0 then a = 0 elseif a > 1 then a = 1 end
    if not (frame and frame.GetObjectType) then return end

    -- ===============================
    -- 1) Cadres "skinnés" (_cdzNeutral)
    -- ===============================
    if frame._cdzNeutral then
        local s = frame._cdzNeutral
        local function SA(x) if x and x.SetAlpha then x:SetAlpha(a) end end

        -- Fond principal (⚠️ manquait auparavant)
        if s.bg then SA(s.bg) end

        -- Fond global overlay & header atlas (si fourni par le thème)
        if s.overlay then SA(s.overlay) end
        if s.header  then SA(s.header)  end

        -- Arêtes
        if s.edges then
            if s.edges.top    then SA(s.edges.top)    end
            if s.edges.bottom then SA(s.edges.bottom) end
            if s.edges.left   then SA(s.edges.left)   end  -- conteneur ; alpha se propage
            if s.edges.right  then SA(s.edges.right)  end
        end

        -- Coins
        if s.corners then
            for _, t in pairs(s.corners) do SA(t) end
        end

        -- Barre de titre (thème : left/mid/right)
        if s.title then
            SA(s.title.left); SA(s.title.mid); SA(s.title.right)
        end
        -- Compat rétro : si jamais certains thèmes assignent ces champs legacy
        if s.titleLeft  then SA(s.titleLeft)  end
        if s.titleMid   then SA(s.titleMid)   end
        if s.titleRight then SA(s.titleRight) end

        -- Ruban optionnel
        if s.ribbon then SA(s.ribbon) end
        return
    end

    -- ===============================
    -- 2) Fallback cadres "simples"
    -- ===============================
    local applied = false

    -- PlainWindow : fond et header connus
    if frame.bg and frame.bg.SetAlpha then
        frame.bg:SetAlpha(a); applied = true
    end
    if frame.header and frame.header.bg and frame.header.bg.SetAlpha then
        frame.header.bg:SetAlpha(a); applied = true
    end

    -- Conteneur BG utilisé par les listes & composés
    if frame._containerBG and frame._containerBG.SetAlpha then
        frame._containerBG:SetAlpha(a); applied = true
    end

    -- BackdropTemplate
    if frame.SetBackdropColor and frame.GetBackdropColor then
        local r, g, b = frame:GetBackdropColor()
        frame:SetBackdropColor(r or 1, g or 1, b or 1, a)
        applied = true
    end

    -- Dernier recours : textures "bg/background" directes
    if not applied then
        local regions = { frame:GetRegions() }
        for _, r in ipairs(regions) do
            if r and r.GetObjectType and r:GetObjectType() == "Texture" and r.SetAlpha then
                local name = (r.GetName and r:GetName()) or ""
                name = tostring(name):lower()
                if name:find("bg") or name:find("background") then
                    r:SetAlpha(a)
                    applied = true
                end
            end
        end
    end
end
