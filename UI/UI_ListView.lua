local ADDON, ns = ...
ns.UI = ns.UI or {}
local UI = ns.UI

-- ListView générique
-- cols: { {key,title,w|min,flex,justify,pad}, ... }
-- opts: { topOffset=number, safeRight=true|false, buildRow(row)->fields, updateRow(i,row,fields,item) }
function UI.ListView(parent, cols, opts)
    opts = opts or {}

    local lv = {}
    lv.parent = parent
    lv.cols   = cols or {}
    lv.rows   = {}
    lv.opts   = opts

    lv.header, lv.hLabels = UI.CreateHeader(parent, lv.cols)
    lv.scroll, lv.list    = UI.CreateScroll(parent)

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
        self.header:SetPoint("TOPLEFT",  self.parent, "TOPLEFT",   0,  -(2 + top))
        self.header:SetPoint("TOPRIGHT", self.parent, "TOPRIGHT", -((UI.SCROLLBAR_W or 20) + (UI.SCROLLBAR_INSET or 0)), -(2 + top))
        UI.LayoutHeader(self.header, resolved, self.hLabels)
        self.header:Show()

        self.scroll:ClearAllPoints()
        self.scroll:SetPoint("TOPLEFT", self.header, "BOTTOMLEFT", 0, -4)

        local bottomTarget = self._bottomAnchor or self.parent
        local bottomPoint  = self._bottomAnchor and "TOPRIGHT" or "BOTTOMRIGHT"
        local rightOffset  = self._bottomAnchor and 0 or ((UI.SCROLLBAR_W or 20) + (UI.SCROLLBAR_INSET or 0))
        self.scroll:SetPoint("BOTTOMRIGHT", bottomTarget, bottomPoint, -rightOffset, 0)

        self.list:SetWidth(cW)


        -- Lignes
        local y = 0
        for _, r in ipairs(self.rows) do
            if r:IsShown() then
                r:SetWidth(cW)
                r:ClearAllPoints()
                r:SetPoint("TOPLEFT", self.list, "TOPLEFT", 0, -y)
                y = y + r:GetHeight() + 4
                UI.LayoutRow(r, resolved, r._fields or {})
            end
        end
        self.list:SetHeight(y)

        -- Réassure l'ordre Z (au cas où)
        if self.scroll:GetFrameLevel() >= self.header:GetFrameLevel() then
            self.header:SetFrameLevel(self.scroll:GetFrameLevel() + 5)
        end
    end

    -- Données
    function lv:SetData(data)
        data = data or {}

        -- Crée les lignes manquantes
        for i = #self.rows + 1, #data do
            local r = CreateFrame("Frame", nil, self.list)
            r:SetHeight(UI.ROW_H)
            UI.DecorateRow(r)
            r._fields = (self.opts.buildRow and self.opts.buildRow(r)) or {}
            self.rows[i] = r
        end

        -- Alimente les lignes et cache le surplus
        for i = 1, #self.rows do
            local r  = self.rows[i]
            local it = data[i]
            if it then
                r:Show()
                if self.opts.updateRow then self.opts.updateRow(i, r, r._fields, it) end
            else
                r:Hide()
            end
        end

        self:Layout()
    end

    -- Relayout public
    function lv:Refresh()
        self:Layout()
    end

    -- Relayout sur resize du parent
    if parent and parent.HookScript then
        parent:HookScript("OnSizeChanged", function() if lv and lv.Layout then lv:Layout() end end)
    end

    return lv
end
