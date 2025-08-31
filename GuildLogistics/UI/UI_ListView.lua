local ADDON, ns = ...
local Tr = ns and ns.Tr
ns.UI = ns.UI or {}
local UI = ns.UI

-- ListView générique
-- cols: { {key,title,w|min,flex,justify,pad}, ... }
-- opts: { topOffset=number, bottomAnchor=Frame, buildRow(row)->fields, updateRow(i,row,fields,item) }
function UI.ListView(parent, cols, opts)
    opts = opts or {}

    local lv = {}
    lv.parent = parent
    lv.cols   = cols or {}
    lv.rows   = {}
    lv.opts   = opts

    -- État/autorisation de la ScrollBar
    lv._scrollbarAllowed = (opts.showSB ~= false)  -- par défaut autorisée
    lv._showScrollbar    = false                   -- invisible tant qu'inutile

    lv.header, lv.hLabels = UI.CreateHeader(parent, lv.cols)
    lv.scroll, lv.list    = UI.CreateScroll(parent)

    -- Réduction de 1 px sur tout le contenu des ListViews (header + lignes)
    if UI and UI.SetFontDeltaForFrame then
        UI.SetFontDeltaForFrame(lv.header, -1, true)
        UI.SetFontDeltaForFrame(lv.list,   -1, true)
    end

    -- Assure l’auto-font sur header + contenu scrollé
    if UI and UI.AttachAutoFont then
        UI.AttachAutoFont(lv.header)
        UI.AttachAutoFont(lv.list)   -- (sécurise même si CreateScroll l’a déjà fait)
    end

    -- Applique immédiatement au texte des entêtes déjà créés
    if UI and UI.ApplyFont and lv.hLabels then
        for _, fs in ipairs(lv.hLabels) do
            if fs then UI.ApplyFont(fs) end
        end
    end

    -- Relie le ScrollFrame à sa ListView pour les callbacks
    lv.scroll._ownerListView = lv

    -- Réaction immédiate quand la plage de scroll change (création/destruction de lignes, resize, etc.)
    lv.scroll:HookScript("OnScrollRangeChanged", function(sf)
        local owner = sf._ownerListView
        if owner and UI and UI.ListView_SyncScrollbar then
            UI.ListView_SyncScrollbar(owner, false) -- déféré pour laisser la range se stabiliser
        end
    end)

    -- Quand le scrollframe apparaît, on resynchronise (au cas où tout a été construit off-screen)
    lv.scroll:HookScript("OnShow", function(sf)
        local owner = sf._ownerListView
        if owner and UI and UI.ListView_SyncScrollbar then
            UI.ListView_SyncScrollbar(owner, false) -- next frame
        end
    end)

    -- Quand géométrie change, on resynchronise au frame suivant
    if lv.scroll.HookScript then
        lv.scroll:HookScript("OnSizeChanged", function(sf)
            local owner = sf._ownerListView
            if owner and UI and UI.ListView_SyncScrollbar then
                UI.ListView_SyncScrollbar(owner, false)
            end
        end)
    end
    if lv.list and lv.list.HookScript then
        lv.list:HookScript("OnSizeChanged", function()
            if UI and UI.ListView_SyncScrollbar then
                UI.ListView_SyncScrollbar(lv, false)
            end
        end)
    end

    -- État initial : pas de barre tant que non nécessaire
    if UI.ListView_SetScrollbarVisible then
        UI.ListView_SetScrollbarVisible(lv, false)
    end

    -- Forçage d’affichage/masquage de l’entête (utilisé pour les listes repliables)
    lv._forceHeaderHidden = false
    function lv:SetHeaderForceHidden(hidden)
        self._forceHeaderHidden = hidden and true or false
        if self.header then
            if self._forceHeaderHidden then self.header:Hide() else self.header:Show() end
        end
    end
    
    -- Overlay d'état vide (grisé + texte centré)
    function lv:_EnsureEmptyOverlay()
        if self._empty then return end
        local ov = CreateFrame("Frame", nil, self.parent)
        ov:SetIgnoreParentAlpha(false)
        ov:EnableMouse(false)
        ov:Hide()

        ov.bg = ov:CreateTexture(nil, "ARTWORK")
        ov.bg:SetAllPoints(ov)
        ov.bg:SetColorTexture(0, 0, 0, 0.12) -- léger grisage

        ov.fs = ov:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
        ov.fs:SetText(Tr(self.opts.emptyText or Tr("lbl_no_data")))
        ov.fs:SetJustifyH("CENTER"); ov.fs:SetJustifyV("MIDDLE")

        ov.fs:SetPoint("CENTER", ov, "CENTER", 0, 0)

        self._empty = ov
    end

    function lv:_SetEmptyShown(show)
        self:_EnsureEmptyOverlay()
        if show then
            -- positionné/level ajustés par Layout()
            self._empty:Show()
        else
            self._empty:Hide()
        end
    end

    -- Z-order : même strata que le parent (popup/panel), niveau au-dessus du scroll
    local pStrata = parent:GetFrameStrata() or "MEDIUM"
    lv.header:SetFrameStrata(pStrata)
    local base = math.max(parent:GetFrameLevel() or 0, lv.scroll:GetFrameLevel() or 0)
    lv.header:SetFrameLevel(base + 10)

    -- Mise en page
    function lv:Layout()
        local top  = tonumber(self.opts.topOffset) or 0
        local pW   = self.parent:GetWidth() or 800

        -- La scrollbar est-elle visible ?
        local showSB = (self._showScrollbar == true)

        -- Largeur effective de la scrollbar (option par-liste > globale > largeur actuelle si dispo)
        local sbW = (self.opts and self.opts.scrollbarWidth) or (UI.SCROLLBAR_W or 6)
        if showSB and UI and UI.GetScrollBar then
            local sb = UI.GetScrollBar(self.scroll)
            if sb and sb.GetWidth then
                local w = sb:GetWidth()
                if w and w > 0 then sbW = w end
            end
        end

        local inset = UI.SCROLLBAR_INSET or 0
        local rOff  = showSB and (sbW + inset) or 0

        -- Largeur des données (empêche toute superposition sous la barre)
        local cW = math.max(0, pW - rOff)


        -- Résolution colonnes (on a déjà retiré l'éventuelle réservation de droite)
        local resolved = UI.ResolveColumns(cW, self.cols)

        -- Élargissement dynamique de la colonne 'act' selon le besoin réel observé
        local actIndex
        for i, c in ipairs(resolved) do if c.key == "act" then actIndex = i break end end
        if actIndex then
            local need = resolved[actIndex].w or resolved[actIndex].min or 120
            for _, r in ipairs(self.rows) do
                if r:IsShown() then
                    local a = r._fields and r._fields.act
                    local n = a and a._actionsNaturalW
                    if n and n > need then need = n end
                end
            end
            local current = resolved[actIndex].w or resolved[actIndex].min or 0
            if need > current then
                local delta = need - current
                local shrinkable, totalCap = {}, 0
                for i, rc in ipairs(resolved) do
                    if i ~= actIndex and (rc.flex and rc.flex > 0) then
                        local w   = rc.w or rc.min or 0
                        local cap = math.max(0, w - (rc.min or 0))
                        if cap > 0 then
                            shrinkable[#shrinkable+1] = { i=i, cap=cap }
                            totalCap = totalCap + cap
                        end
                    end
                end
                if totalCap > 0 then
                    local remain = delta
                    for _, s in ipairs(shrinkable) do
                        local rc = resolved[s.i]
                        local take = math.floor(delta * (s.cap / totalCap) + 0.5)
                        take = math.min(take, s.cap, remain)
                        rc.w = (rc.w or rc.min or 0) - take
                        remain = remain - take
                        if remain <= 0 then break end
                    end
                    local gained = delta - math.max(0, remain)
                    resolved[actIndex].w = current + gained
                end
            end
        end

        -- Header
        self.header:ClearAllPoints()
        self.header:SetPoint("TOPLEFT",  self.parent, "TOPLEFT",   0, -(top))
        self.header:SetPoint("TOPRIGHT", self.parent, "TOPRIGHT", -rOff, -(top))

        UI.LayoutHeader(self.header, resolved, self.hLabels)
        if self._forceHeaderHidden then self.header:Hide() else self.header:Show() end

        -- par sécurité, aucun clipping sur l'entête (pour laisser passer les vseps)
        if self.header and self.header.SetClipsChildren then
            self.header:SetClipsChildren(false)
        end

        -- Scroll area
        self.scroll:ClearAllPoints()
        self.scroll:SetPoint("TOPLEFT", self.header, "BOTTOMLEFT", 0, -4)

        local bottomTarget = self._bottomAnchor or self.parent
        local bottomPoint  = self._bottomAnchor and "TOPRIGHT" or "BOTTOMRIGHT"
        local rightOffset  = rOff
        self.scroll:SetPoint("BOTTOMRIGHT", bottomTarget, bottomPoint, -rightOffset, 0)

        self.list:SetWidth(cW)

        -- Lignes
        local y = 0
        for _, r in ipairs(self.rows) do
            if r:IsShown() then
                r:SetWidth(cW)
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", self.list, "TOPLEFT", 0, -y)
                y = y + r:GetHeight()
                UI.LayoutRow(r, resolved, r._fields or {})
            end
        end
        self.list:SetHeight(y)

        -- Force le recalcul immédiat de la plage de scroll (sinon elle arrive parfois au frame suivant)
        if self.scroll and self.scroll.UpdateScrollChildRect then
            self.scroll:UpdateScrollChildRect()
        end

        -- Réassure l'ordre Z (au cas où)
        if self.scroll:GetFrameLevel() >= self.header:GetFrameLevel() then
            self.header:SetFrameLevel(self.scroll:GetFrameLevel() + 5)
        end

        -- Positionne l'overlay "liste vide" (recouvre la zone scroll, pas le header)
        if self._empty then
            self._empty:ClearAllPoints()
            self._empty:SetPoint("TOPLEFT",     self.scroll, "TOPLEFT",     0, 0)
            self._empty:SetPoint("BOTTOMRIGHT", self.scroll, "BOTTOMRIGHT", 0, 0)
            local base = self.scroll:GetFrameLevel() or 0
            self._empty:SetFrameStrata(self.scroll:GetFrameStrata() or "MEDIUM")
            self._empty:SetFrameLevel(base + 3)
        end

        -- Synchronisation de la barre après pose de la géométrie
        if UI and UI.ListView_SyncScrollbar then
            UI.ListView_SyncScrollbar(self, false) -- next frame pour laisser la range se stabiliser
        end

        -- --- Sync immédiat avec range + fallback géométrique (évite le "n'apparaît pas" aléatoire) ---
        local yr    = (self.scroll.GetVerticalScrollRange and self.scroll:GetVerticalScrollRange()) or 0
        local viewH = self.scroll:GetHeight() or 0
        local need  = (yr > 0) or (y > (viewH + 1))
        if self._scrollbarAllowed == false then need = false end
        local current = (self._showScrollbar == true)
        if current ~= need then
            if UI and UI.ListView_SetScrollbarVisible then
                UI.ListView_SetScrollbarVisible(self, need)
            else
                self._showScrollbar = need and true or false
            end
        end
    end

    -- Données
    -- Wrapper propre qui ne recolorie PLUS le fond : il se contente de décorer les lignes
    do
        local _OrigListView = UI.ListView
        function UI.ListView(...)
            local lv = _OrigListView(...)
            -- Décore les lignes déjà existantes
            if lv and lv.rows then
                for i, row in ipairs(lv.rows) do
                    if not row._bg then UI.DecorateRow(row) end
                end
            end

            -- ➕ Fond englobant (header + contenu)
            if lv and not lv._containerBG then
                local bg = lv.parent:CreateTexture(nil, "BACKGROUND")
                -- couleur pilotée par la skin (modifiable au même endroit que les styles)
                local col = (UI.GetListViewContainerColor and UI.GetListViewContainerColor()) or { r=0, g=0, b=0, a=0.10 }
                bg:SetColorTexture(col.r or 0, col.g or 0, col.b or 0, col.a or 0.10)
                -- couche très en arrière pour ne pas gêner les lignes/hover
                if bg.SetDrawLayer then bg:SetDrawLayer("BACKGROUND", -8) end
                lv._containerBG = bg
            end

            -- Décore toute nouvelle ligne créée + auto-font
            if lv and lv.CreateRow and not lv._decorateCR then
                local _oldCR = lv.CreateRow
                function lv:CreateRow(i)
                    local r = _oldCR(self, i)
                    UI.DecorateRow(r)
                    if UI and UI.AttachAutoFont then UI.AttachAutoFont(r) end
                    if UI and UI.ApplyFontRecursively then UI.ApplyFontRecursively(r) end
                    return r
                end
                lv._decorateCR = true
            end

            -- 🔁 Hook du Layout pour caler le fond sous header+scroll
            if lv and lv.Layout and not lv._bgLayoutHooked then
                local _oldLayout = lv.Layout
                function lv:Layout(...)
                    local res = _oldLayout(self, ...)
                    local bg  = self._containerBG
                    if bg and self.header and self.scroll then
                        bg:ClearAllPoints()
                        -- englobe l’entête…
                        bg:SetPoint("TOPLEFT", self.header, "TOPLEFT", 0, 0)
                        -- …jusqu’au bas de la zone scroll (respecte offsets déjà appliqués)
                        bg:SetPoint("BOTTOMRIGHT", self.scroll, "BOTTOMRIGHT", 0, 0)

                        -- garde la couleur en phase si le thème change dynamiquement
                        if UI.GetListViewContainerColor then
                            local c = UI.GetListViewContainerColor()
                            if c then bg:SetColorTexture(c.r or 0, c.g or 0, c.b or 0, c.a or 0.10) end
                        end
                    end
                    return res
                end
                lv._bgLayoutHooked = true
            end

            return lv
        end
    end
    
    -- Étend le hook de Layout pour quantifier lignes et séparateurs à la fin du layout.
    function UI._AttachListViewPixelSnap(lv)
        if not lv or lv._snapLayoutHooked then return end
        if not lv.Layout then return end

        local _oldLayout = lv.Layout
        function lv:Layout(...)
            local res = _oldLayout(self, ...)
            -- Passe "pixel-perfect"
            if self.rows then
                local px = UI.GetPhysicalPixel()
                for _, row in ipairs(self.rows) do
                    -- Hauteur/points arrondis
                    UI.SnapRegion(row)
                    -- Garde le séparateur à 1 px exact et bien ancré
                    if row._sepTop then
                        UI.SetPixelThickness(row._sepTop, 1)
                        if PixelUtil and PixelUtil.SetPoint then
                            PixelUtil.SetPoint(row._sepTop, "TOPLEFT",  row, "TOPLEFT",  0, 0)
                            PixelUtil.SetPoint(row._sepTop, "TOPRIGHT", row, "TOPRIGHT", 0, 0)
                        else
                            row._sepTop:ClearAllPoints()
                            row._sepTop:SetPoint("TOPLEFT",  row, "TOPLEFT",  0, 0)
                            row._sepTop:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, 0)
                        end
                    end
                end
            end
            return res
        end
        lv._snapLayoutHooked = true
    end
    
    -- SetData ne touche qu'au gradient & séparateurs, JAMAIS au SetColorTexture du fond
    function lv:SetData(data)
        data = data or {}

        -- Hauteur paramétrable (fallback = UI.ROW_H)
        local baseRowH = tonumber(self.opts and self.opts.rowHeight) or (UI.ROW_H or 30)
        if baseRowH < 1 then baseRowH = 1 end
        local baseHWithPad = baseRowH + 2

        -- Crée les lignes manquantes avec la bonne hauteur de base
        for i = #self.rows + 1, #data do
            local r = CreateFrame("Frame", nil, self.list)
            r:SetHeight(baseHWithPad)
            UI.DecorateRow(r)
            r._fields = (self.opts.buildRow and self.opts.buildRow(r)) or {}
            self.rows[i] = r
        end

        -- Première ligne visible (pour masquer son séparateur TOP)
        local firstVisible = nil
        for i = 1, #data do if data[i] then firstVisible = i break end end

        local shown = 0
        for i = 1, #self.rows do
            local r  = self.rows[i]
            local it = data[i]

            if it then
                r:Show()
                shown = shown + 1

                -- Dégradé vertical pair/impair
                if UI.ApplyRowGradient then UI.ApplyRowGradient(r, (i % 2 == 0)) end

                -- Padding supplémentaire pour les lignes 'sep'
                local extraTop = 0
                if it.kind == "sep" then
                    extraTop = (UI.GetSeparatorTopPadding and UI.GetSeparatorTopPadding()) or 0
                    if extraTop < 0 then extraTop = 0 end
                end

                local targetH = baseHWithPad + extraTop
                if r._targetH ~= targetH then
                    r._targetH = targetH
                    r:SetHeight(targetH)
                end

                -- Masquer la barre de séparation du tout premier item si besoin
                if r._sepTop then
                    if firstVisible and i == firstVisible then
                        r._sepTop:Hide()
                    else
                        r._sepTop:Show()
                    end
                end

                -- Mise à jour spécifique à la liste (cellules, textes, etc.)
                if self.opts.updateRow then
                    self.opts.updateRow(i, r, r._fields, it)
                end

                -- Recalage générique des widgets 'sep' pour respecter le padding haut
                if it.kind == "sep" and r._fields then
                    local f   = r._fields
                    local pad = extraTop

                    -- Le fond de section (sepBG) commence sous le padding
                    if f.sepBG then
                        f.sepBG:ClearAllPoints()
                        f.sepBG:SetPoint("TOPLEFT",     r, "TOPLEFT",     0, -pad)
                        f.sepBG:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 2,  0)
                    end

                    -- Le trait supérieur (sepTop) en haut de la zone "fond"
                    if f.sepTop then
                        f.sepTop:ClearAllPoints()
                        if f.sepBG then
                            f.sepTop:SetPoint("TOPLEFT",  f.sepBG, "TOPLEFT",  0, 1)
                            f.sepTop:SetPoint("TOPRIGHT", f.sepBG, "TOPRIGHT", 0, 1)
                        else
                            f.sepTop:SetPoint("TOPLEFT",  r, "TOPLEFT",  0, -pad + 1)
                            f.sepTop:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, -pad + 1)
                        end
                    end

                    -- Couleur du libellé "séparateur"
                    if f.sepLabel then
                        local col = self.opts.sepLabelColor or UI.SEPARATOR_LABEL_COLOR or {1, 1, 1}
                        local cr = col.r or col[1] or 1
                        local cg = col.g or col[2] or 1
                        local cb = col.b or col[3] or 1
                        local ca = col.a or col[4] or 1
                        f.sepLabel:SetTextColor(cr, cg, cb, ca)

                        f.sepLabel:ClearAllPoints()
                        if f.sepBG then
                            f.sepLabel:SetPoint("LEFT", f.sepBG, "LEFT", 8, 0)
                        else
                            f.sepLabel:SetPoint("LEFT", r, "LEFT", 8, -math.floor(pad/2))
                        end
                    end
                end
            else
                r:Hide()
                if r._sepTop then r._sepTop:Hide() end
            end
        end

        self:Layout()
        self:_SetEmptyShown(shown == 0)
    end

    -- Relayout public
    function lv:Refresh()
        self:Layout()
    end

    -- Change dynamiquement l’ancrage bas (ex : si le footer est construit après)
    function lv:SetBottomAnchor(anchor)
        self._bottomAnchor = anchor
        if anchor and anchor.HookScript then
            anchor:HookScript("OnSizeChanged", function()
                if self and self.Layout then self:Layout() end
            end)
        end
        self:Layout()
    end

    -- Relayout sur resize du parent
    if parent and parent.HookScript then
        parent:HookScript("OnSizeChanged", function() if lv and lv.Layout then lv:Layout() end end)
    end

    if lv and UI._AttachListViewPixelSnap then
        UI._AttachListViewPixelSnap(lv)
    end

    return lv
end

function UI._SetRowVisualAlpha(row, a)
    if not row then return end
    a = tonumber(a or 1) or 1
    if a < 0 then a = 0 elseif a > 1 then a = 1 end

    -- 📌 Le gradient du fond utilise un multiplicateur par-ligne
    row._alphaMul = a
    if UI.ApplyRowGradient then
        local even = (row._isEven ~= nil) and row._isEven or false
        UI.ApplyRowGradient(row, even)
    end

    -- 📌 Les séparateurs utilisent alpha_effectif = alpha_base * a
    if row._sepTop and row._sepTop.SetAlpha then
        local base = tonumber(row._sepTopBaseA or row._sepTop:GetAlpha() or 1) or 1
        row._sepTop:SetAlpha(base * a)
    end
    if row._sepBot and row._sepBot.SetAlpha then
        local base = tonumber(row._sepBotBaseA or row._sepBot:GetAlpha() or 1) or 1
        row._sepBot:SetAlpha(base * a)
    end
    -- Séparateurs VERTICAUX : alpha_effectif = alpha_base * a
    if row._vseps then
        for _, t in pairs(row._vseps) do
            if t and t.SetAlpha then
                local base = tonumber(t._baseA or t:GetAlpha() or 1) or 1
                t:SetAlpha(base * a)
            end
        end
    end

    -- Hover conservé (lisibilité)
end

function UI.ListView_SetVisualOpacity(lv, a)
    -- a ∈ [0..1] : applique l'alpha aux éléments "visuels" (fond/header/sep + gradient des lignes)
    if not lv then return end
    a = tonumber(a or 1) or 1
    if a < 0 then a = 0 elseif a > 1 then a = 1 end

    -- Mémorise pour futures rows (CreateRow/SetData)
    lv._visualAlpha = a

    local function SA(x) if x and x.SetAlpha then x:SetAlpha(a) end end
    local function applyRow(r)
        if not r then return end
        if UI and UI._SetRowVisualAlpha then UI._SetRowVisualAlpha(r, a) end
    end

    -- Fond conteneur éventuel
    if lv._containerBG then SA(lv._containerBG) end

    -- Header (BG + séparateurs du header seulement ; les rows sont traitées à part)
    if lv.header then
        if lv.header._bg        then SA(lv.header._bg)        end
        if lv.header.bg         then SA(lv.header.bg)         end
        if lv.header._sepTop    and lv.header._sepTop.SetAlpha    then
            local base = lv.header._sepTopBaseA or lv.header._sepTop:GetAlpha() or 1
            lv.header._sepTop:SetAlpha(base * a)
        end
        if lv.header._sepBottom and lv.header._sepBottom.SetAlpha then
            local base = lv.header._sepBottomBaseA or lv.header._sepBottom:GetAlpha() or 1
            lv.header._sepBottom:SetAlpha(base * a)
        end
        -- Séparateurs VERTICAUX du header
        if lv.header._vseps then
            for _, t in pairs(lv.header._vseps) do
                if t and t.SetAlpha then
                    local base = t._baseA or t:GetAlpha() or 1
                    t:SetAlpha(base * a)
                end
            end
        end

    end

    -- Rows déjà existantes
    if lv.rows then
        for _, row in ipairs(lv.rows) do
            applyRow(row)
        end
    end

    -- Hook CreateRow : propage l'alpha aux nouvelles lignes
    if lv.CreateRow and not lv._alphaHookCR then
        local _oldCR = lv.CreateRow
        function lv:CreateRow(i)
            local r = _oldCR(self, i)
            if UI and UI._SetRowVisualAlpha and self._visualAlpha then
                UI._SetRowVisualAlpha(r, self._visualAlpha)
            end
            return r
        end
        lv._alphaHookCR = true
    end

    -- Hook SetData : réapplique l'alpha APRÈS le (ré)calcul des gradients
    if lv.SetData and not lv._alphaHookSD then
        local _oldSD = lv.SetData
        function lv:SetData(data)
            _oldSD(self, data)
            local a2 = self._visualAlpha or 1
            if self.rows and UI and UI._SetRowVisualAlpha then
                for _, r in ipairs(self.rows) do
                    UI._SetRowVisualAlpha(r, a2)
                end
            end
        end
        lv._alphaHookSD = true
    end
end


function UI.ListView_SetRowGradientOpacity(lv, a)
    -- a ∈ [0..1] : multiplicateur appliqué AU DÉGRADÉ des lignes (row._alphaMul)
    if not lv or not lv.rows then
        if lv then lv._rowGradAlpha = tonumber(a or 1) or 1 end
        return
    end
    a = tonumber(a or 1) or 1
    if a < 0 then a = 0 elseif a > 1 then a = 1 end

    lv._rowGradAlpha = a

    -- Applique immédiatement aux lignes existantes (sans toucher aux séparateurs ici)
    for i, r in ipairs(lv.rows) do
        if r then
            r._alphaMul = a
            if UI.ApplyRowGradient then
                UI.ApplyRowGradient(r, r._isEven ~= nil and r._isEven or (i % 2 == 0))
            end
        end
    end

    -- Les nouvelles lignes hériteront du multiplicateur
    if lv.CreateRow and not lv._rowGradAlphaHook then
        local _oldCR = lv.CreateRow
        function lv:CreateRow(i)
            local r = _oldCR(self, i)
            if r then
                if r._alphaMul == nil then r._alphaMul = 1 end
                r._alphaMul = self._rowGradAlpha or r._alphaMul
                if UI.ApplyRowGradient then
                    local isEven = (i % 2 == 0)
                    r._isEven = isEven
                    UI.ApplyRowGradient(r, isEven)
                end
            end
            return r
        end
        lv._rowGradAlphaHook = true
    end
end

function UI.ListView_SetScrollbarVisible(lv, show)
    if not (lv and lv.scroll) then return end
    if show == nil then show = true end

    -- Respecte l'autorisation globale
    if lv._scrollbarAllowed == false then show = false end

    local prev = (lv._showScrollbar == true)
    lv._showScrollbar = (show and true) or false

    -- ScrollBar du ScrollFrame
    local sb = (UI.GetScrollBar and UI.GetScrollBar(lv.scroll)) or lv.scroll.ScrollBar or lv.scroll.scrollbar
    if not sb then return end

    -- Sécurité : supprimer flèches et appliquer skin fin si dispo
    if UI.StripScrollButtons then UI.StripScrollButtons(sb) end
    if UI.SkinScrollBar     then UI.SkinScrollBar(sb)     end

    if lv._showScrollbar then
        if sb.Show        then sb:Show() end
        if sb.EnableMouse then sb:EnableMouse(true) end
        if sb.SetAlpha    then sb:SetAlpha(UI.SCROLLBAR_ALPHA) end 
        if sb.SetWidth and UI.SCROLLBAR_W then sb:SetWidth(UI.SCROLLBAR_W) end

        -- ✅ Place la ScrollBar *en dehors* de la zone scroll (dans le gutter réservé par Layout)
        -- Le gutter vaut: sbW (largeur réelle) + inset ; on ancre la barre dès le bord droit du ScrollFrame.
        do
            local gap = UI.SCROLLBAR_INSET or 0
            if sb.ClearAllPoints then
                sb:ClearAllPoints()
                -- Le coin gauche de la barre colle au bord droit de la zone scroll + gap
                sb:SetPoint("TOPLEFT",     lv.scroll, "TOPRIGHT",     gap, 0)
                sb:SetPoint("BOTTOMLEFT",  lv.scroll, "BOTTOMRIGHT",  gap, 0)
            end
        end

        -- Recalage du pouce (proportionnel + min)
        if UI.UpdateScrollThumb then
            if lv.scroll and lv.scroll.UpdateScrollChildRect then
                lv.scroll:UpdateScrollChildRect()
            end
            UI.UpdateScrollThumb(sb)
        end

    else
        if sb.Hide        then sb:Hide() end
        if sb.EnableMouse then sb:EnableMouse(false) end
        if sb.SetAlpha    then sb:SetAlpha(0) end
    end

    if prev ~= lv._showScrollbar and lv.Layout then
        lv:Layout()
    end
end


function UI.ListView_SetRowHeight(lv, h)
    if not lv then return end
    local v = tonumber(h)
    if not v or v < 1 then return end
    lv.opts = lv.opts or {}
    lv.opts.rowHeight = v
    -- Forcer une ré-application de la hauteur sur les lignes existantes
    if lv.SetData then
        -- Re-pousse les mêmes données pour recalculer les hauteurs
        local data = {}
        if lv.rows and #lv.rows > 0 and lv.list and lv.list.GetChildren then
            -- si tu as un buffer de données côté appelant, passe-le directement
        end
        -- On suppose que l'appelant rappellera SetData après ce setter dans la plupart des cas.
        -- À défaut, on provoque au moins un Layout.
        if lv.Layout then lv:Layout() end
    end
end

-- Synchronise l'état d'affichage de la ScrollBar avec la plage réelle du ScrollFrame.
-- immediate=true => calcule maintenant ; sinon programme au frame suivant (évite les races de sizing).
function UI.ListView_SyncScrollbar(lv, immediate)
    if not (lv and lv.scroll) then return end

    local function computeNeed()
        local yr = (lv.scroll.GetVerticalScrollRange and lv.scroll:GetVerticalScrollRange()) or 0
        local need = (yr > 0)
        if not need then
            -- Fallback si la plage n'est pas encore à jour : compare contenu vs viewport
            local listH   = (lv.list and lv.list.GetHeight and lv.list:GetHeight()) or 0
            local viewH   = (lv.scroll and lv.scroll.GetHeight and lv.scroll:GetHeight()) or 0
            need = (listH > (viewH + 1))
        end
        if lv._scrollbarAllowed == false then need = false end
        return need
    end

    local function doSync()
        local need = computeNeed()
        if (lv._showScrollbar == true) ~= need then
            if UI and UI.ListView_SetScrollbarVisible then
                UI.ListView_SetScrollbarVisible(lv, need)
            else
                lv._showScrollbar = need and true or false
            end
        end
    end

    if immediate then
        doSync()
    else
        -- Deux passes déférées pour laisser UpdateScrollChildRect() et la range se stabiliser
        lv._sbSyncTicket = (lv._sbSyncTicket or 0) + 1
        local ticket = lv._sbSyncTicket

        local function pass2()
            if not (lv and lv.scroll) then return end
            -- si un nouveau ticket est arrivé entre temps, on laisse la prochaine passe gérer
            if lv._sbSyncTicket ~= ticket then return end
            doSync()
        end

        C_Timer.After(0, function()
            if not (lv and lv.scroll) then return end
            doSync()
            C_Timer.After(0, pass2)
        end)
    end
end