local ADDON, ns = ...
local Tr = ns and ns.Tr
ns.UI = ns.UI or {}
local UI = ns.UI

-- ListView générique
-- cols: { {key,title,w|min,flex,justify,pad}, ... }
-- opts: { topOffset=number, bottomAnchor=Frame, buildRow(row)->fields, updateRow(i,row,fields,item) }
---@diagnostic disable-next-line: duplicate-set-field
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

    -- Virtual window mode (only render visible rows)
    lv._windowed = (opts.virtualWindow == true)
    lv._shownFirst, lv._shownLast = nil, nil
    lv._baseRowHWithPad = nil

    -- Hook CreateFontString sur la liste pour capturer toutes les créations
    if lv.list and lv.list.CreateFontString then
        local originalCreateFontString = lv.list.CreateFontString
        lv.list.CreateFontString = function(self, ...)
            local fs = originalCreateFontString(self, ...)
            if UI.GLOBAL_FONT_ENABLED and UI and UI.ApplyFont and fs then
                UI.ApplyFont(fs)
            end
            return fs
        end
    end

    -- Réduction de 1 px sur tout le contenu des ListViews (header + lignes)
    if UI and UI.SetFontDeltaForFrame then
        UI.SetFontDeltaForFrame(lv.header, -1, true)
        UI.SetFontDeltaForFrame(lv.list,   -1, true)
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
                if owner._windowed and owner._UpdateVisibleWindow then owner:_UpdateVisibleWindow() end
            end
        end)
    end
    if lv.list and lv.list.HookScript then
        lv.list:HookScript("OnSizeChanged", function()
            if UI and UI.ListView_SyncScrollbar then
                UI.ListView_SyncScrollbar(lv, false)
                if lv._windowed and lv._UpdateVisibleWindow then lv:_UpdateVisibleWindow() end
            end
        end)
    end

    -- Suivi du scroll vertical pour mettre à jour la fenêtre visible
    if lv.scroll and lv.scroll.SetScript then
        local prev = lv.scroll:GetScript("OnVerticalScroll")
        lv.scroll:SetScript("OnVerticalScroll", function(sf, offset)
            if prev then pcall(prev, sf, offset) end
            local owner = sf._ownerListView
            if owner and owner._windowed and owner._UpdateVisibleWindow then owner:_UpdateVisibleWindow() end
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
    ov.fs:SetText(Tr(self.opts.emptyText or "lbl_no_data"))
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
        -- Empêche les boucles Layout <-> SyncScrollbar / OnSizeChanged
        if self._inLayout then return end
        self._inLayout = true

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
            -- Cache le besoin max si déjà calculé et pas marqué comme sale
            if not self._actWidthDirty and self._cachedActWidth and self._cachedActWidth > need then
                need = self._cachedActWidth
            else
                local maxW = need
                for i = 1, #self.rows do
                    local r = self.rows[i]
                    if r and r.IsShown and r:IsShown() then
                        local a = r._fields and r._fields.act
                        local n = a and a._actionsNaturalW
                        if n and n > maxW then maxW = n end
                    end
                end
                self._cachedActWidth = maxW
                self._actWidthDirty = false
                need = maxW
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

        -- 🔒 Signature de layout pour éviter de relayout inutilement les cellules/v-seps
        local sigParts = { tostring(cW), tostring(#resolved) }
        for i = 1, #resolved do
            local c = resolved[i]
            sigParts[#sigParts+1] = tostring(c.w or c.min or 0)
        end
        local _layoutSig = table.concat(sigParts, "|")

        if not self._windowed then
            for _, r in ipairs(self.rows) do
                if r:IsShown() then
                    r:SetWidth(cW)
                    r:ClearAllPoints()
                    r:SetPoint("TOPLEFT", self.list, "TOPLEFT", 0, -y)
                    y = y + r:GetHeight()

                    -- Ne réaligne les champs + v-seps que si la géométrie des colonnes a changé
                    if r._layoutSig ~= _layoutSig then
                        UI.LayoutRow(r, resolved, r._fields or {})
                        r._layoutSig = _layoutSig
                    end
                end
            end
            self.list:SetHeight(y)
        else
            -- Windowed: positionne uniquement les lignes visibles et fixe une hauteur totale logique
            local first = tonumber(self._shownFirst) or 1
            local last  = tonumber(self._shownLast) or 0
            local rowH  = tonumber(self._baseRowHWithPad or (UI.ROW_H or 30) + 2) or 1
            if last < first then last = first - 1 end
            for i = first, last do
                local r = self.rows[i]
                if r and r:IsShown() then
                    r:SetWidth(cW)
                    r:ClearAllPoints()
                    r:SetPoint("TOPLEFT", self.list, "TOPLEFT", 0, -((i-1) * rowH))
                    -- Ne réaligne que si nécessaire
                    if r._layoutSig ~= _layoutSig then
                        UI.LayoutRow(r, resolved, r._fields or {})
                        r._layoutSig = _layoutSig
                    end
                end
            end
            -- Hauteur totale = nb lignes * hauteur de base (approximation uniforme)
            local totalH = math.max(0, (self._data and #self._data or 0) * rowH)
            self.list:SetHeight(totalH)
        end


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
        self._inLayout = nil
    end

    -- Refresh standard : SetData + Layout
    function lv:RefreshData(rows)
        if rows ~= nil and self.SetData then
            self:SetData(rows)
        end
        if self.Layout then
            self:Layout()
        end
    end

    -- Données
    -- Wrapper propre qui ne recolorie PLUS le fond : il se contente de décorer les lignes
    do
        local _OrigListView = UI.ListView
        ---@diagnostic disable-next-line: duplicate-set-field
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

            -- 🔧 Recalage automatique quand l’échelle UI change
            if ns and ns.Events and ns.Events.Register then
                ns.Events.Register("UI_SCALE_CHANGED", lv, function()
                    if lv and lv.Layout then lv:Layout() end
                end)
                ns.Events.Register("DISPLAY_SIZE_CHANGED", lv, function()
                    if lv and lv.Layout then lv:Layout() end
                end)
                ns.Events.Register("CVAR_UPDATE", lv, function(_, cvar)
                    if cvar == "uiScale" or cvar == "useUIScale" then
                        if lv and lv.Layout then lv:Layout() end
                    end
                end)
            end

            return lv
        end

            -- (This return above is part of original function chain; code below will not execute)
    end

        -- Inject incremental append capability for list views (called after wrappers redefine UI.ListView)
        do
            local _Old = UI.ListView
            ---@diagnostic disable-next-line: duplicate-set-field
            UI.ListView = function(...)
                local lv = _Old(...)
                if lv and not lv.AppendData then
                    function lv:AppendData(batch)
                        if not batch or #batch == 0 then return end
                        self._data = self._data or {}
                        local startIndex = #self._data
                        for i = 1, #batch do
                            self._data[startIndex + i] = batch[i]
                        end
                        local baseRowH = tonumber(self.opts and self.opts.rowHeight) or (UI.ROW_H or 30)
                        if baseRowH < 1 then baseRowH = 1 end
                        local baseHWithPad = baseRowH + 2
                        -- Create only missing rows
                        local have = #self.rows
                        local need = #self._data
                        for i = have + 1, need do
                            local r = CreateFrame("Frame", nil, self.list)
                            r:SetHeight(baseHWithPad)
                            UI.DecorateRow(r)
                            r._fields = (self.opts.buildRow and self.opts.buildRow(r)) or {}
                            self.rows[i] = r
                            r._lastItemRef = nil
                            if self._windowed and r.Hide then r:Hide() end
                            if UI and UI.ApplyFontRecursively then UI.ApplyFontRecursively(r) end
                        end
                        -- If windowed, just update window; else update only newly added rows
                        if self._windowed then
                            if self.list and self.list.SetHeight then
                                local totalH = math.max(0, (#self._data) * baseHWithPad)
                                self.list:SetHeight(totalH)
                            end
                            if self._UpdateVisibleWindow then self:_UpdateVisibleWindow() end
                        else
                            local firstVisible
                            for i = 1, #self._data do if self._data[i] then firstVisible = i break end end
                            for i = startIndex + 1, #self._data do
                                local r  = self.rows[i]
                                local it = self._data[i]
                                if r and it then
                                    r:Show()
                                    if UI.ApplyRowGradient then UI.ApplyRowGradient(r, (i % 2 == 0)) end
                                    local extraTop = 0
                                    if it.kind == "sep" and not it.extraTop then
                                        extraTop = (UI.GetSeparatorTopPadding and UI.GetSeparatorTopPadding()) or 0
                                        if extraTop < 0 then extraTop = 0 end
                                    end
                                    r._isSep = (it.kind == "sep")
                                    local targetH = baseHWithPad + extraTop
                                    if r._targetH ~= targetH then r._targetH = targetH; r:SetHeight(targetH) end
                                    if r._sepTop then
                                        if firstVisible and i == firstVisible then r._sepTop:Hide() else r._sepTop:Show() end
                                    end
                                    if self.opts.updateRow and r._lastItemRef ~= it then
                                        self.opts.updateRow(i, r, r._fields, it)
                                        r._lastItemRef = it
                                    end
                                end
                            end
                            if self.Layout then self:Layout() end
                            if self._SetEmptyShown then self:_SetEmptyShown(#self._data == 0) end
                        end
                    end
                end
                return lv
            end
        end
    
    -- Étend le hook de Layout pour quantifier lignes et séparateurs à la fin du layout.
-- UI/UI_ListView.lua
function UI._AttachListViewPixelSnap(lv)
    if not lv or lv._snapLayoutHooked then return end
    if not lv.Layout then return end

    local _oldLayout = lv.Layout
    function lv:Layout(...)
        -- ✋ évite les boucles Layout <-> SetPoint : si on re-rentre pendant un snap, on sort de suite
        if self._snapInProgress then
            return _oldLayout(self, ...)
        end

        self._snapInProgress = true
        local res = _oldLayout(self, ...)

        -- Passe "pixel-perfect" (idempotente : change seulement si nécessaire)
        if self.rows then
            for _, row in ipairs(self.rows) do
                UI.SnapRegion(row)

                -- Barre de séparation supérieure (1px) : re-anchorer seulement si ça change
                if row._sepTop then
                    UI.SetPixelThickness(row._sepTop, 1)
                    UI.SetPoints2IfChanged(
                        row._sepTop,
                        {"TOPLEFT",  row, "TOPLEFT",  0, 0},
                        {"TOPRIGHT", row, "TOPRIGHT", 0, 0}
                    )
                end

                -- Séparateurs verticaux : seulement si pad change
                if row and row.IsShown and row:IsShown() and row._vseps then
                    local pad = tonumber(row._sepPadTop) or 0
                    for _, t in pairs(row._vseps) do
                        if t and t.GetPoint then
                            if t._lastPad ~= pad then
                                local _, _, _, xOfs = t:GetPoint(1)
                                xOfs = tonumber(xOfs) or 0
                                if UI.SetPoints2IfChanged then
                                    UI.SetPoints2IfChanged(
                                        t,
                                        {"TOPLEFT",    row, "TOPLEFT",    xOfs, -pad},
                                        {"BOTTOMLEFT", row, "BOTTOMLEFT", xOfs,  0}
                                    )
                                else
                                    t:ClearAllPoints()
                                    if PixelUtil and PixelUtil.SetPoint then
                                        PixelUtil.SetPoint(t, "TOPLEFT",    row, "TOPLEFT",    xOfs, -pad)
                                        PixelUtil.SetPoint(t, "BOTTOMLEFT", row, "BOTTOMLEFT", xOfs,  0)
                                    else
                                        t:SetPoint("TOPLEFT",    row, "TOPLEFT",    xOfs, -pad)
                                        t:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", xOfs,  0)
                                    end
                                end
                                t._lastPad = pad
                            end
                        end
                    end
                end
            end
        end

        -- 🔧 Resnap différé (frame suivante) pour éviter tout rebond immédiat pendant Layout
        if not self._resnapQueued then
            self._resnapQueued = true
            UI.NextFrame(function()
                self._resnapQueued = nil
                if UI and UI.ListView_ResnapVSeps then
                    UI.ListView_ResnapVSeps(self)
                end
            end)
        end

        self._snapInProgress = nil
        return res
    end
    lv._snapLayoutHooked = true
end
    
    -- Resnap ciblé des séparateurs verticaux (header + rows)
    function UI.ListView_ResnapVSeps(lv)
        if not lv then return end

        -- Header
        local H = lv.header
        if H and H._vseps then
            for _, t in pairs(H._vseps) do
                if t and t.IsShown and t:IsShown() then
                    if UI.SetPixelWidth then UI.SetPixelWidth(t, 1) end
                    -- ❌ plus de SnapRegion ici non plus
                end
            end
        end

        -- Rows
        if lv.rows then
            for _, r in ipairs(lv.rows) do
                if r and r._vseps then
                    for _, t in pairs(r._vseps) do
                        if t and t.IsShown and t:IsShown() then
                            if UI.SetPixelWidth then UI.SetPixelWidth(t, 1) end
                            -- ❌ plus de SnapRegion ici non plus
                        end
                    end
                end
            end
        end
    end

    -- SetData ne touche qu'au gradient & séparateurs, JAMAIS au SetColorTexture du fond
    function lv:SetData(data)
        data = data or {}
        -- 🔍 Diff rapide: si la signature du dataset n'a pas changé, on évite tout le travail
        if ns and ns.Util and ns.Util.FastSigArray then
            local sigParts = {}
            local maxPreview = math.min(#data, 32) -- on inclut un échantillon de tête pour réduire collisions sur tailles similaires
            for i = 1, maxPreview do
                local it = data[i]
                if type(it) == 'table' then
                    -- Incorporer quelques champs stables (kind, id, name, uid) si présents
                    local k = it.kind or it.id or it.name or it.uid or i
                    sigParts[#sigParts+1] = tostring(k)
                else
                    sigParts[#sigParts+1] = tostring(it)
                end
            end
            sigParts[#sigParts+1] = tostring(#data)
            local sig = table.concat(sigParts, '|')
            if self._lastDataSig == sig then
                -- Dataset identique -> on ne refait pas la construction des lignes; on peut toutefois invalider layout si nécessaire
                return
            end
            self._lastDataSig = sig
        end
        -- Conserve une référence aux données courantes pour MAJ ciblées
        self._data = data
        -- Marque la largeur d'actions comme potentiellement à recalculer sur nouveau dataset
        self._actWidthDirty = true; self._cachedActWidth = nil

        -- Hauteur paramétrable (fallback = UI.ROW_H)
        local baseRowH = tonumber(self.opts and self.opts.rowHeight) or (UI.ROW_H or 30)
        if baseRowH < 1 then baseRowH = 1 end
        local baseHWithPad = baseRowH + 2

        -- Crée les lignes manquantes avec la bonne hauteur de base
        -- Optionnel: création par lots pour éviter les freezes sur de grosses listes
        local have = #self.rows
        local need = #data
        local step = tonumber(self.opts and self.opts.maxCreatePerFrame) or 0
        -- Valeur par défaut intelligente pour éviter les freezes sur de grandes listes
        if (not step or step == 0) and need >= 250 then
            step = 150 -- crée 150 lignes par frame pour limiter le travail
        end
        local createUntil = need
        if step > 0 and have < need then
            createUntil = math.min(need, have + step)
        end
        for i = have + 1, createUntil do
            local r = CreateFrame("Frame", nil, self.list)
            r:SetHeight(baseHWithPad)
            UI.DecorateRow(r)
            r._fields = (self.opts.buildRow and self.opts.buildRow(r)) or {}
            self.rows[i] = r
            r._lastItemRef = nil -- forcera updateRow
            if self._windowed and r.Hide then r:Hide() end

            -- Applique immédiatement la police aux nouvelles lignes
            if UI and UI.ApplyFontRecursively then
                UI.ApplyFontRecursively(r)
            end
        end
        -- Si tout n'est pas créé, planifie la suite au frame suivant et évite les doublons
        if step > 0 and createUntil < need and not self._batchPending then
            self._batchPending = true
            UI.NextFrame(function()
                if not self then return end
                self._batchPending = nil
                if self.SetData then self:SetData(self._data or data) end
            end)
        end

        -- Première ligne visible (pour masquer son séparateur TOP)
        local firstVisible = nil
        for i = 1, #data do if data[i] then firstVisible = i break end end

        local shown = 0
        if not self._windowed then
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
                    if not it.extraTop then
                        extraTop = (UI.GetSeparatorTopPadding and UI.GetSeparatorTopPadding()) or 0
                        if extraTop < 0 then extraTop = 0 end
                    end
                end
                
                -- Flag interne pour que LayoutRow sache masquer les v-seps
                r._isSep = (it.kind == "sep")

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
                    -- Évite les mises à jour redondantes: n'update que si l'item a changé
                    if r._lastItemRef ~= it then
                        self.opts.updateRow(i, r, r._fields, it)
                        r._lastItemRef = it
                    end
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

                    -- Les séparateurs verticaux ne doivent pas envahir la zone de padding
                    if r._vseps then
                        for _, t in pairs(r._vseps) do
                            if t and t.GetPoint then
                                local _, _, _, x = t:GetPoint(1)
                                x = tonumber(x) or 0
                                if PixelUtil and PixelUtil.SetPoint then
                                    PixelUtil.SetPoint(t, "TOPLEFT",    r, "TOPLEFT",    UI.RoundToPixel and UI.RoundToPixel(x) or x, -pad)
                                    PixelUtil.SetPoint(t, "BOTTOMLEFT", r, "BOTTOMLEFT", UI.RoundToPixel and UI.RoundToPixel(x) or x, 0)
                                else
                                    t:ClearAllPoints()
                                    t:SetPoint("TOPLEFT",    r, "TOPLEFT",    x, -pad)
                                    t:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", x, 0)
                                end
                                if UI.SetPixelWidth then UI.SetPixelWidth(t, 1) end
                                if UI.SnapRegion   then UI.SnapRegion(t)   end
                            end
                        end
                    end

                    -- Synchronise l'affichage des v-seps selon le type de ligne
                    local isSep = it and it.kind == "sep"
                    if UI.SetVSepsVisible then
                        UI.SetVSepsVisible(r, not isSep)
                    elseif r._vseps then
                        for _, t in pairs(r._vseps) do
                            if t then
                                if isSep then
                                    if t.Hide then t:Hide() end
                                else
                                    if t.Show then t:Show() end
                                end
                            end
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
                    -- ➕ Ajuste les séparateurs verticaux pour ignorer la zone de padding (extraTop)
                    -- et mémorise le pad pour les futurs Layouts.
                    r._sepPadTop = pad
                    if r._vseps then
                        for _, t in pairs(r._vseps) do
                            if t and t.GetPoint then
                                local _, _, _, xOfs = t:GetPoint(1)  -- conserve l’offset X existant
                                xOfs = tonumber(xOfs) or 0
                                t:ClearAllPoints()
                                if PixelUtil and PixelUtil.SetPoint then
                                    PixelUtil.SetPoint(t, "TOPLEFT",    r, "TOPLEFT",    xOfs, -pad)
                                    PixelUtil.SetPoint(t, "BOTTOMLEFT", r, "BOTTOMLEFT", xOfs,  0)
                                else
                                    t:SetPoint("TOPLEFT",    r, "TOPLEFT",    xOfs, -pad)
                                    t:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", xOfs,  0)
                                end
                                if UI.SetPixelWidth then UI.SetPixelWidth(t, 1) end
                            end
                        end
                    end

                end
                else
                    r:Hide()
                    r._isSep = false
                    if r._sepTop then r._sepTop:Hide() end
                end
            end
            self:Layout()
            self:_SetEmptyShown(shown == 0)
        else
            -- Windowed: ne montre pas toutes les lignes; fixe la hauteur de base et ouvre une fenêtre visible
            self._baseRowHWithPad = baseHWithPad
            -- Ajuste la hauteur totale immédiatement pour des scrollbars correctes
            local totalH = math.max(0, (#data) * baseHWithPad)
            if self.list and self.list.SetHeight then self.list:SetHeight(totalH) end
            self:_UpdateVisibleWindow()
            self:_SetEmptyShown(#data == 0)
        end
    end

    -- Mise à jour légère: ré-appelle updateRow uniquement pour les lignes visibles avec les données courantes
    function lv:UpdateVisibleRows()
        if not (self and self.rows and self.opts and self.opts.updateRow and self._data) then return end
        if not self._windowed then
            local n = math.min(#self.rows, #self._data)
            for i = 1, n do
                local r = self.rows[i]
                local it = self._data[i]
                if r and r.IsShown and r:IsShown() and it then
                    -- Update léger uniquement si contenu changé
                    if r._lastItemRef ~= it then
                        self.opts.updateRow(i, r, r._fields, it)
                        r._lastItemRef = it
                    end
                end
            end
        else
            local first = tonumber(self._shownFirst) or 1
            local last  = math.min(#self._data, tonumber(self._shownLast) or 0)
            for i = first, last do
                local r = self.rows[i]
                local it = self._data[i]
                if r and r.IsShown and r:IsShown() and it then
                    if r._lastItemRef ~= it then
                        self.opts.updateRow(i, r, r._fields, it)
                        r._lastItemRef = it
                    end
                end
            end
        end
    end

    -- Invalidation ciblée du cache d'items pour forcer updateRow au prochain rafraîchissement
    function lv:InvalidateVisibleRowsCache()
        if not (self and self.rows) then return end
        if not self._windowed then
            for i = 1, #self.rows do
                local r = self.rows[i]
                if r and r.IsShown and r:IsShown() then r._lastItemRef = nil end
            end
        else
            local first = tonumber(self._shownFirst) or 1
            local last  = tonumber(self._shownLast) or 0
            for i = first, last do
                local r = self.rows[i]
                if r then r._lastItemRef = nil end
            end
        end
    end

    function lv:InvalidateAllRowsCache()
        if not (self and self.rows) then return end
        for i = 1, #self.rows do
            local r = self.rows[i]
            if r then r._lastItemRef = nil end
        end
    end

    -- Calcule et applique la fenêtre visible (indices de lignes à afficher)
    function lv:_UpdateVisibleWindow()
        if not (self and self._windowed and self._data and self.scroll and self.list) then return end
        local rowH = tonumber(self._baseRowHWithPad or (UI.ROW_H or 30) + 2) or 1
        if rowH < 1 then rowH = 1 end
        local total = #self._data
        local viewH = (self.scroll.GetHeight and self.scroll:GetHeight()) or 0
        local offset = (self.scroll.GetVerticalScroll and self.scroll:GetVerticalScroll()) or 0
        local buffer = 4
        local first = math.max(1, math.floor(offset / rowH) + 1 - buffer)
        local visibleCount = math.ceil(viewH / rowH) + (buffer * 2)
        local last  = math.min(total, first + visibleCount - 1)

        if self._shownFirst == first and self._shownLast == last then
            return -- rien à faire
        end

        -- Cache l'ancien intervalle
        if self._shownFirst and self._shownLast then
            for i = self._shownFirst, self._shownLast do
                local r = self.rows[i]
                if r and r.Hide then r:Hide() end
            end
        end
        -- Montre le nouveau
        for i = first, last do
            local r = self.rows[i]
            if r and r.Show then r:Show() end
        end
        self._shownFirst, self._shownLast = first, last
        -- Met à jour uniquement les lignes visibles
        if self.UpdateVisibleRows then self:UpdateVisibleRows() end
        -- Relayout léger pour placer les lignes visibles
        if self.Layout then self:Layout() end
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

    if prev ~= lv._showScrollbar then
        if ns and ns.Util and ns.Util.Debounce and lv.Layout then
            ns.Util.Debounce("ListView.Layout." .. tostring(lv), 0, function()
                if lv and lv.Layout then lv:Layout() end
            end)
        elseif lv and lv.Layout then
            UI.NextFrame(function() if lv and lv.Layout then lv:Layout() end end)
        end
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
-- UI/UI_ListView.lua
function UI.ListView_SyncScrollbar(lv, immediate)
    if not (lv and lv.scroll) then return end

    -- ⏸️ Pause globale : n'agir que si l'UI est ouverte ou si la liste appartient à une zone always-on (tracker)
    if UI and UI.ShouldProcess and not UI.ShouldProcess(lv.parent or lv.scroll or lv.list) then
        return
    end

    local function computeNeed()
        local yr = (lv.scroll.GetVerticalScrollRange and lv.scroll:GetVerticalScrollRange()) or 0
        local need = (yr > 0)
        if not need then
            local listH = (lv.list and lv.list.GetHeight and lv.list:GetHeight()) or 0
            local viewH = (lv.scroll and lv.scroll.GetHeight and lv.scroll:GetHeight()) or 0
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
        lv._sbSyncTicket = (lv._sbSyncTicket or 0) + 1
        local ticket = lv._sbSyncTicket
        local function pass2()
            if not (lv and lv.scroll) then return end
            if ticket ~= lv._sbSyncTicket then return end
            doSync()
        end
        UI.NextFrame(function()
            if not (lv and lv.scroll) then return end
            if ticket ~= lv._sbSyncTicket then return end
            doSync()
            UI.NextFrame(pass2)
        end)
    end
end

-- === Registre des ListViews + utilitaires de (re)layout/snap ===
UI.__allListViews = UI.__allListViews or setmetatable({}, { __mode = "k" })

-- Inscription automatique à la création (hook de l’enveloppe existante)
do
    local _Old = UI.ListView
    ---@diagnostic disable-next-line: duplicate-set-field
    UI.ListView = function(...)
        local lv = _Old(...)
        if lv then
            UI.__allListViews[lv] = true
            if lv.Layout and not lv._gatedLayout then
                local _orig = lv.Layout
                function lv:Layout(...)
                    -- ⏸️ Ne layout que si l'UI est active ou si la liste est dans une zone always-on (tracker)
                    if UI and UI.ShouldProcess and not UI.ShouldProcess(self.parent or self.list or self.scroll) then
                        return
                    end
                    return _orig(self, ...)
                end
                lv._gatedLayout = true
            end
        end
        return lv
    end
end


-- Resnap ciblé des séparateurs verticaux (header + rows)
function UI.ListView_ResnapVSeps(lv)
    if not lv then return end
    local function resnapBucket(b)
        if not b then return end
        for _, t in pairs(b) do
            if t and t.IsShown and t:IsShown() then
                if UI.SetPixelWidth then UI.SetPixelWidth(t, 1) end
                if UI.SnapRegion   then UI.SnapRegion(t)   end
            end
        end
    end
    if lv.header and lv.header._vseps then resnapBucket(lv.header._vseps) end
    if lv.rows then
        for _, r in ipairs(lv.rows) do
            if r and r.IsShown and r:IsShown() and r._vseps then
                resnapBucket(r._vseps)
            end
        end
    end
end

-- Relayout + resnap de TOUTES les ListViews (appelé quand l’échelle change)
-- UI/UI_ListView.lua
function UI.ListView_RelayoutAll()
    if not UI.__allListViews then return end
    local uiOpen = (UI and UI.IsOpen and UI.IsOpen()) or (UI and UI.Main and UI.Main.IsShown and UI.Main:IsShown()) or false
    for lv in pairs(UI.__allListViews) do
        if lv and lv.Layout then
            local owner = lv.parent or lv.list or lv.scroll
            if uiOpen or (UI and UI.ShouldProcess and UI.ShouldProcess(owner)) then
                -- Met à jour le contenu des lignes visibles (gating droits, icônes d'action, textes)
                if lv.UpdateVisibleRows then pcall(lv.UpdateVisibleRows, lv) end
                -- Puis relayout complet (scrollbars, colonnes dynamiques, snap)
                lv:Layout()
                if UI.ListView_ResnapVSeps then UI.ListView_ResnapVSeps(lv) end
            end
        end
    end
end


-- Suivre les changements d’échelle globaux (fallback si slider non utilisé)
if ns and ns.Events and ns.Events.Register then
    ns.Events.Register("UI_SCALE_CHANGED",     UI, function() if UI.ListView_RelayoutAll then UI.ListView_RelayoutAll() end end)
    ns.Events.Register("DISPLAY_SIZE_CHANGED", UI, function() if UI.ListView_RelayoutAll then UI.ListView_RelayoutAll() end end)
    ns.Events.Register("CVAR_UPDATE",          UI, function(_, cvar) if cvar=="uiScale" or cvar=="useUIScale" then if UI.ListView_RelayoutAll then UI.ListView_RelayoutAll() end end end)
end


-- === Shared header background helpers ===
local function _GL_CopyTableShallow(src)
    if type(src) ~= 'table' then return nil end
    local out = {}
    for k, v in pairs(src) do out[k] = v end
    return out
end

local function _GL_NormalizeColor(color, fallback)
    fallback = fallback or {0.12, 0.12, 0.12, 1}
    local fr = fallback.r or fallback[1] or 0.12
    local fg = fallback.g or fallback[2] or 0.12
    local fb = fallback.b or fallback[3] or 0.12
    local fa = fallback.a or fallback[4] or 1
    if type(color) == 'table' then
        local r = color.r or color[1]
        local g = color.g or color[2]
        local b = color.b or color[3]
        local a = color.a or color[4]
        if r or g or b then
            return r or fr, g or fg, b or fb, a or fa
        end
    end
    return fr, fg, fb, fa
end

function UI.ListView_EnsureHeaderBackgrounds(lv, opts)
    if not (lv and lv.header) then return nil end
    local cols = (opts and opts.cols) or lv.cols or {}
    if #cols == 0 then return nil end

    lv._headerBGs = lv._headerBGs or {}
    local parent   = (opts and opts.parent) or lv.header
    local layer    = (opts and opts.layer) or 'BACKGROUND'
    local subLayer = opts and opts.subLayer

    for i = 1, #cols do
        local tex = lv._headerBGs[i]
        if not tex or tex:GetParent() ~= parent then
            tex = parent:CreateTexture(nil, layer)
            tex:SetTexture('Interface\\Buttons\\WHITE8x8')
            lv._headerBGs[i] = tex
        end
        if tex.SetDrawLayer and subLayer then
            tex:SetDrawLayer(layer, subLayer)
        end
        tex:Show()
    end

    if #lv._headerBGs > #cols then
        for i = #cols + 1, #lv._headerBGs do
            local tex = lv._headerBGs[i]
            if tex then tex:Hide() end
        end
    end

    return lv._headerBGs
end

function UI.ListView_LayoutHeaderBackgrounds(lv, opts)
    if not (lv and lv.header) then return end
    opts = opts or lv._headerBGOptions or {}
    local cols = opts.cols or lv.cols or {}
    if #cols == 0 then return end

    local textures = UI.ListView_EnsureHeaderBackgrounds(lv, {
        cols = cols,
        parent = opts.parent,
        layer = opts.layer,
        subLayer = opts.subLayer,
    })
    if not textures then return end

    local defaultColor = opts.defaultColor
    if type(defaultColor) ~= 'table' then
        defaultColor = {0.12, 0.12, 0.12, 1}
    else
        defaultColor = {
            defaultColor.r or defaultColor[1] or 0.12,
            defaultColor.g or defaultColor[2] or 0.12,
            defaultColor.b or defaultColor[3] or 0.12,
            defaultColor.a or defaultColor[4] or 1,
        }
    end

    local palette     = opts.palette
    local paletteMap  = opts.paletteMap
    local paletteKeyResolver = opts.paletteKeyResolver
    local aliases     = opts.paletteAliases
    local custom      = opts.colors
    local colorFn     = opts.colorForColumn
    local overrideAlpha = opts.alpha

    local x = 0
    for idx, col in ipairs(cols) do
        local tex = textures[idx]
        if tex then
            tex:ClearAllPoints()
            tex:SetPoint('TOPLEFT', lv.header, 'TOPLEFT', x, 0)
            tex:SetPoint('BOTTOMLEFT', lv.header, 'BOTTOMLEFT', x, 0)
            local width = col.w or col.min or 80
            tex:SetWidth(width)

            local color
            local key = col.key or idx
            if type(colorFn) == 'function' then
                color = colorFn(col, idx, opts)
            elseif custom and custom[key] then
                color = custom[key]
            elseif palette then
                local palKey = key
                if paletteKeyResolver then
                    palKey = paletteKeyResolver(col, idx, opts)
                elseif paletteMap and paletteMap[palKey] then
                    palKey = paletteMap[palKey]
                end
                if aliases and palKey and not palette[palKey] and aliases[palKey] then
                    palKey = aliases[palKey]
                end
                if palKey and palette[palKey] then
                    color = palette[palKey]
                end
            end

            local r, g, b, a = _GL_NormalizeColor(color, defaultColor)
            if overrideAlpha ~= nil then a = overrideAlpha end
            if tex.SetColorTexture then
                tex:SetColorTexture(r, g, b, a)
            else
                tex:SetVertexColor(r, g, b, a)
            end
            tex:Show()
        end
        x = x + (col.w or col.min or 80)
    end
end

function UI.ListView_SetHeaderBackgrounds(lv, opts)
    if not lv then return end
    lv._headerBGOptions = opts and _GL_CopyTableShallow(opts) or nil
    if lv.Layout and not lv._headerBGLayoutHooked then
        local _orig = lv.Layout
        function lv:Layout(...)
            local res = _orig(self, ...)
            UI.ListView_LayoutHeaderBackgrounds(self)
            return res
        end
        lv._headerBGLayoutHooked = true
    end
    UI.ListView_LayoutHeaderBackgrounds(lv, lv._headerBGOptions)
end
