local ADDON, ns = ...
local Tr = ns and ns.Tr
ns.UI = ns.UI or {}
local UI = ns.UI

-- ListView générique
-- cols: { {key,title,w|min,flex,justify,pad}, ... }
-- opts: { topOffset=number, safeRight=true|false, bottomAnchor=Frame, buildRow(row)->fields, updateRow(i,row,fields,item) }
function UI.ListView(parent, cols, opts)
    opts = opts or {}

    local lv = {}
    lv.parent = parent
    lv.cols   = cols or {}
    lv.rows   = {}
    lv.opts   = opts

    lv.header, lv.hLabels = UI.CreateHeader(parent, lv.cols)
    lv.scroll, lv.list    = UI.CreateScroll(parent)

    -- Forçage d’affichage/masquage de l’entête (utilisé pour les listes repliables)
    lv._forceHeaderHidden = false
    function lv:SetHeaderForceHidden(hidden)
        self._forceHeaderHidden = hidden and true or false
        if self.header then
            if self._forceHeaderHidden then self.header:Hide() else self.header:Show() end
        end
    end

    -- Ancrage bas optionnel (ex : footer) pour limiter la hauteur de scroll
    lv._bottomAnchor = opts.bottomAnchor
    if lv._bottomAnchor and lv._bottomAnchor.HookScript then
        -- si le footer change de taille, on relayout la liste
        lv._bottomAnchor:HookScript("OnSizeChanged", function()
            if lv and lv.Layout then lv:Layout() end
        end)
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
        local sb   = (UI.SCROLLBAR_W or 20) + (UI.SCROLLBAR_INSET or 0)
        local top  = tonumber(self.opts.topOffset) or 0
        local pW   = self.parent:GetWidth() or 800
        local cW   = pW - sb

        -- Résolution de base (pas de safeRight car on a déjà soustrait la scrollbar)
        local resolved = UI.ResolveColumns(cW, self.cols, { safeRight = false })

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

            -- Si besoin > largeur allouée, on rogne proportionnellement les colonnes flex (sans passer sous min)
            local current = resolved[actIndex].w or resolved[actIndex].min or 0
            if need > current then
                local delta = need - current
                local shrinkable, totalCap = {}, 0
                for i, rc in ipairs(resolved) do
                    if i ~= actIndex and (rc.flex and rc.flex > 0) then
                        local w  = rc.w or rc.min or 0
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
        self.header:SetPoint("TOPLEFT",  self.parent, "TOPLEFT",   0,  -(top))
        self.header:SetPoint("TOPRIGHT", self.parent, "TOPRIGHT", -((UI.SCROLLBAR_W or 20) + (UI.SCROLLBAR_INSET or 0)), -(top))
        UI.LayoutHeader(self.header, resolved, self.hLabels)
        if self._forceHeaderHidden then self.header:Hide() else self.header:Show() end

        self.scroll:ClearAllPoints()
        self.scroll:SetPoint("TOPLEFT", self.header, "BOTTOMLEFT", 0, -4)

        local bottomTarget = self._bottomAnchor or self.parent
        local bottomPoint  = self._bottomAnchor and "TOPRIGHT" or "BOTTOMRIGHT"

        local wantSafeRight = (self.opts.safeRight ~= false)
        local rightOffset   = wantSafeRight and ((UI.SCROLLBAR_W or 20) + (UI.SCROLLBAR_INSET or 0)) or 0

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

        -- Réassure l'ordre Z (au cas où)
        if self.scroll:GetFrameLevel() >= self.header:GetFrameLevel() then
            self.header:SetFrameLevel(self.scroll:GetFrameLevel() + 5)
        end

        -- Positionne l'overlay "liste vide" pour qu'il recouvre la zone scroll (pas le header)
        if self._empty then
            self._empty:ClearAllPoints()
            self._empty:SetPoint("TOPLEFT",     self.scroll, "TOPLEFT",     0, 0)
            self._empty:SetPoint("BOTTOMRIGHT", self.scroll, "BOTTOMRIGHT", 0, 0)
            -- au-dessus des lignes mais sous le header
            local base = self.scroll:GetFrameLevel() or 0
            self._empty:SetFrameStrata(self.scroll:GetFrameStrata() or "MEDIUM")
            self._empty:SetFrameLevel(base + 3)
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

            -- Décore toute nouvelle ligne créée
            if lv and lv.CreateRow and not lv._decorateCR then
                local _oldCR = lv.CreateRow
                function lv:CreateRow(i)
                    local r = _oldCR(self, i)
                    UI.DecorateRow(r)
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
                        -- …jusqu’au bas de la zone scroll (respecte offsets/safeRight déjà appliqués)
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

        -- Crée les lignes manquantes
        for i = #self.rows + 1, #data do
            local r = CreateFrame("Frame", nil, self.list)
            r:SetHeight(UI.ROW_H + 2)
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

                -- Hauteur dynamique : on ajoute un "padding" en haut des lignes 'sep'
                local extraTop = 0
                if it.kind == "sep" then
                    extraTop = (UI.GetSeparatorTopPadding and UI.GetSeparatorTopPadding()) or 0
                    if extraTop < 0 then extraTop = 0 end
                end
                local baseH   = (UI.ROW_H or 30) + 2
                local targetH = baseH + extraTop
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

                    -- Le trait supérieur (sepTop) se place en haut de la zone "fond"
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

                    -- Couleur du libellé "séparateur" : opts > défaut global
                    if f.sepLabel then
                        local col = self.opts.sepLabelColor or UI.SEPARATOR_LABEL_COLOR or {1, 1, 1}
                        local cr = col.r or col[1] or 1
                        local cg = col.g or col[2] or 1
                        local cb = col.b or col[3] or 1
                        local ca = col.a or col[4] or 1
                        f.sepLabel:SetTextColor(cr, cg, cb, ca)

                        -- Ancrage du libellé
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