local ADDON, ns = ...
ns.UI = ns.UI or {}
local UI = ns.UI
local Tr = ns.Tr or function(s) return s end

-- DynamicTable: autonomous, spreadsheet-like table widget
-- Visual style aligned with ListView, but does not depend on it.
-- API:
--   local dt = UI.DynamicTable(parent, cols, opts)
--   dt:SetData(rows)                  -- full replace (hierarchical supported via row.children)
--   dt:DiffAndApply(newRows)          -- minimal changes (adds/removes/updates)
--   dt:UpdateCell(rowKey, colKey, v)  -- targeted per-cell update
--   dt:SetSort(colKey, ascending?)    -- sorting on top-level (and optionally per-level)
--   dt:ToggleRow(rowKey, expanded?)   -- accordion expand/collapse
--
-- Column spec (per entry in `cols`):
--   { key="name", title="lbl_name", w|min|flex, justify, vsep=true,
--     buildCell(parent) -> cellFrame or FontString,
--     updateCell(cell, value, row, rowIndex, level),
--     valueOf(row) -> value for sorting, (fallback to row.cells[key])
--     -- Sorting controls
--     sortable=true/false,
--     sortValue = "fieldKey" | function(row) -> any,   -- explicit sort-source
--     sortNumeric = true|false,                         -- force numeric compare
--     -- Special columns
--     treeToggle=true,  -- legacy: +/- inside this column
--     treeCol=true,     -- NEW: dedicated +/- column (no title)
--     leftAccent=true,  -- NEW: dedicated left accent column (no title)
--   }
--
-- Row item shape:
--   { key = stableKey, cells = { [colKey] = value }, children = {...}, expanded=true/false }
--   Optional: row._level (auto-computed), row._parentKey

do
    -- small, allocation-free signature helper for primitive/table-ish values
    local function Sig(v)
        local t = type(v)
        if t == 'string' or t == 'number' or t == 'boolean' then
            return tostring(v)
        elseif t == 'table' then
            -- prefer explicit fields if provided
            if v.sig then return tostring(v.sig) end
            if v.id  then return tostring(v.id) end
            if v.key then return tostring(v.key) end
            -- shallow sample (avoid recursion)
            local a = v[1]; if a ~= nil then return "#"..tostring(a) end
            local name = rawget(v, 'name') or rawget(v, 'label') or rawget(v, 'text')
            if name then return tostring(name) end
            return tostring(v)
        else
            return tostring(v)
        end
    end

    local function NormalizeColumns(cols)
        local out = {}
        for i, c in ipairs(cols or {}) do
            local cc = {}
            for k, v in pairs(c) do cc[k] = v end
            cc.key      = tostring(cc.key or ("col"..i))
            -- Special columns default to no title
            if cc.treeCol or cc.leftAccent then
                cc.title = cc.title or ""
            else
                cc.title    = cc.title or cc.key
            end
            cc.min      = cc.min or cc.w or 80
            cc.justify  = cc.justify or "LEFT"
            cc.vsep     = (cc.vsep ~= false) -- show v-seps by default
            cc.sortable = (cc.sortable ~= false)
            -- Dedicated columns are not sortable by default
            if cc.treeCol or cc.leftAccent then
                cc.sortable = false
                -- No vertical separator for structural columns
                cc.vsep = false
            end
            out[i] = cc
        end
        return out
    end

    local function CreateHeader(parent, cols, owner)
        local header, labels = UI.CreateHeader(parent, cols)
        -- clickable headers for sort
        owner._sort = owner._sort or { key = nil, asc = true }
        for i, fs in ipairs(labels) do
            local col = cols[i]
            if fs and col and col.sortable ~= false then
                local btn = CreateFrame("Button", nil, header)
                btn:SetAllPoints(fs)
                btn:SetScript("OnClick", function()
                    local key = col.key
                    local s = owner._sort
                    if s.key == key then s.asc = not s.asc else s.key, s.asc = key, true end
                    owner:SetSort(s.key, s.asc)
                end)
                btn:EnableMouse(true)
            end
        end
        return header, labels
    end

    -- cell default builders
    local function DefaultBuildCell(parent)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetJustifyH("LEFT")
        if UI and UI.ApplyFont then UI.ApplyFont(fs) end
        return fs
    end
    local function DefaultUpdateCell(cell, value)
        if cell and cell.SetText then cell:SetText(value == nil and "" or tostring(value)) end
    end

    function UI.DynamicTable(parent, cols, opts)
        opts = opts or {}
        local dt = {}
        dt.parent = parent
        dt.cols   = NormalizeColumns(cols or {})
        dt.opts   = opts

        -- visual scaffolding (autonomous)
        dt.header, dt._hLabels = CreateHeader(parent, dt.cols, dt)
        dt.scroll, dt.list     = UI.CreateScroll(parent)

        -- Column roles
        dt._treeColIndex = nil
        dt._leftAccentIndex = nil
        dt._leftAccentW = 0
        for i, c in ipairs(dt.cols) do
            if not dt._treeColIndex and c.treeCol then dt._treeColIndex = i end
            if not dt._leftAccentIndex and c.leftAccent then
                dt._leftAccentIndex = i
                dt._leftAccentW = tonumber(c.w or c.min or 3) or 3
            end
        end

        -- container background (header + scroll)
        do
            local bg = parent:CreateTexture(nil, "BACKGROUND")
            if bg.SetDrawLayer then bg:SetDrawLayer("BACKGROUND", -8) end
            dt._containerBG = bg
        end

        -- header background strips per column (self-managed, no ListView dependency)
        dt._headerBGs = {}
        dt._headerBottom = nil
        function dt:_EnsureHeaderBGs(n)
            for i=1,n do
                if not self._headerBGs[i] then
                    local t = self.header:CreateTexture(nil, "BACKGROUND")
                    -- nicer look: keep as texture but we'll apply a soft gradient tint later
                    t:SetTexture('Interface\\Buttons\\WHITE8x8')
                    self._headerBGs[i] = t
                end
                self._headerBGs[i]:Show()
            end
            for i=n+1, #self._headerBGs do
                if self._headerBGs[i] then self._headerBGs[i]:Hide() end
            end
            -- ensure header bottom divider once
            if not self._headerBottom then
                local b = self.header:CreateTexture(nil, "BORDER")
                b:SetTexture('Interface\\Buttons\\WHITE8x8')
                b:SetVertexColor(1,1,1,0.10)
                self._headerBottom = b
            end
        end
        function dt:_LayoutHeaderBGs(resolved)
            local default = self.opts.headerBGColor or {0.12,0.12,0.12,1}
            local palette = self.opts.headerColors
            local colorFn = self.opts.headerColorForColumn
            -- Desired opacity for header backgrounds (default 40%)
            local desiredAlpha = (self.opts and (self.opts.headerAlpha or self.opts.headerOpacity)) or 0.40
            self:_EnsureHeaderBGs(#resolved)
            local x = 0
            for idx, c in ipairs(resolved) do
                local t = self._headerBGs[idx]
                t:ClearAllPoints()
                t:SetPoint('TOPLEFT', self.header, 'TOPLEFT', x, 0)
                t:SetPoint('BOTTOMLEFT', self.header, 'BOTTOMLEFT', x, 0)
                local w = c.w or c.min or 80
                t:SetWidth(w)
                local col = default
                if type(colorFn) == 'function' then
                    local cc = colorFn(c, idx, self) ; if type(cc)=='table' then col = cc end
                elseif palette and c.key and palette[c.key] then
                    col = palette[c.key]
                end
                local r = col.r or col[1] or default[1]
                local g = col.g or col[2] or default[2]
                local b = col.b or col[3] or default[3]
                local a = desiredAlpha
                -- Soft vertical gradient for header cells (darker at top)
                if t.SetGradient then
                    t:SetColorTexture(1,1,1,1)
                    t:SetGradient("VERTICAL", CreateColor(r*0.85, g*0.85, b*0.85, a), CreateColor(r*1.05, g*1.05, b*1.05, a))
                else
                    if t.SetColorTexture then t:SetColorTexture(r,g,b,a) else t:SetVertexColor(r,g,b,a) end
                end
                x = x + w
            end
            -- bottom divider line under header
            if self._headerBottom then
                local b = self._headerBottom
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", self.header, "BOTTOMLEFT", 0, 0)
                b:SetPoint("TOPRIGHT", self.header, "BOTTOMRIGHT", 0, 0)
                if UI.SetPixelThickness then UI.SetPixelThickness(b, 1) else b:SetHeight(1) end
                b:Show()
            end
        end

        -- thin outer border (pixel perfect) around header+list
        dt._border = { }
        local function ensureBorder()
            local function mk()
                local t = parent:CreateTexture(nil, "BORDER")
                t:SetTexture('Interface\\Buttons\\WHITE8x8')
                t:SetVertexColor(1,1,1,0.12)
                return t
            end
            dt._border.top    = dt._border.top    or mk()
            dt._border.bottom = dt._border.bottom or mk()
            dt._border.left   = dt._border.left   or mk()
            dt._border.right  = dt._border.right  or mk()
        end
        ensureBorder()

        -- state
        dt._rows     = {}          -- array of row frames in order
        dt._rowByKey = {}          -- key -> frame
        dt._dataMap  = {}          -- key -> row data (flat, display order)
        dt._flatData = {}
        dt._rowH     = math.max(1, tonumber(opts.rowHeight) or (UI.ROW_H or 30))
        dt._rowHWithPad = dt._rowH + 2
    dt._showScrollbar = false -- visible state (auto)
    dt._colLines = {}

        -- Empty overlay (like ListView)
        local function EnsureEmpty()
            if dt._empty then return end
            local ov = CreateFrame("Frame", nil, parent)
            ov:Hide()
            ov.bg = ov:CreateTexture(nil, "ARTWORK")
            ov.bg:SetAllPoints(ov); ov.bg:SetColorTexture(0,0,0,0.12)
            ov.fs = ov:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
            ov.fs:SetText(Tr(opts.emptyText or "lbl_no_data"))
            if UI.ApplyFont then UI.ApplyFont(ov.fs) end
            ov.fs:SetJustifyH("CENTER"); ov.fs:SetJustifyV("MIDDLE")
            ov.fs:SetPoint("CENTER")
            dt._empty = ov
        end

        -- compute/resolve columns widths
        function dt:_ResolveCols(totalW)
            return UI.ResolveColumns(totalW, self.cols)
        end

        -- layout positions/sizes
        function dt:Layout()
            if self._inLayout then return end
            self._inLayout = true

            local top  = tonumber(self.opts.topOffset) or 0
            local pW   = self.parent:GetWidth() or 800

            -- Scrollbar geometry (centered gutter); reserve gutter even when hidden to avoid content shift
            local sb = UI.GetScrollBar and UI.GetScrollBar(self.scroll)
            local sbW = (self.opts and self.opts.scrollbarWidth) or (UI.SCROLLBAR_W or 12)
            local inset = (UI.SCROLLBAR_INSET or 0)
            -- Option: reserve the scrollbar gutter even when the bar is hidden (default: true)
            local reserve = self.opts and self.opts.reserveScrollbarGutter
            if reserve == nil then reserve = true end
            -- For a visually centered scrollbar, reserve a gutter = sbW + 2*inset
            local rOff = reserve and (sbW + (inset * 2)) or 0

            -- Header geometry
            self.header:ClearAllPoints()
            self.header:SetPoint("TOPLEFT",  self.parent, "TOPLEFT",  0, -top)
            self.header:SetPoint("TOPRIGHT", self.parent, "TOPRIGHT", -rOff, -top)

            local cW = math.max(0, (pW - rOff))
            local resolved = self:_ResolveCols(cW)
            UI.LayoutHeader(self.header, resolved, self._hLabels)
            -- no clipping to keep vseps visible
            if self.header.SetClipsChildren then self.header:SetClipsChildren(false) end

            -- Column-wide separators over the scroll viewport (more performant than per-row)
            do
                self._colLines = self._colLines or {}
                local used = {}
                local x = 0
                local baseA = tonumber(UI.VCOL_SEP_ALPHA or 0.15) or 0.15
                for i, c in ipairs(resolved) do
                    local w = c.w or c.min or 80
                    if c.vsep then
                        local t = self._colLines[i]
                        if not t then
                            t = self.scroll:CreateTexture(nil, "OVERLAY", nil, 7)
                            self._colLines[i] = t
                        end
                        t:SetColorTexture(1,1,1,1)
                        if UI.SetPixelWidth then UI.SetPixelWidth(t, 1) else t:SetWidth(1) end
                        t:ClearAllPoints()
                        local px = (UI.RoundToPixelOn and UI.RoundToPixelOn(self.scroll, x))
                                or (UI.RoundToPixel and UI.RoundToPixel(x)) or x
                        t:SetPoint("TOPLEFT",    self.scroll, "TOPLEFT",    px, 0)
                        t:SetPoint("BOTTOMLEFT", self.scroll, "BOTTOMLEFT", px, 0)
                        if t._baseA ~= baseA then t:SetAlpha(baseA); t._baseA = baseA end
                        if UI.SnapTexture then UI.SnapTexture(t) end
                        t:Show()
                        used[i] = true
                    end
                    x = x + w
                end
                -- Hide unused/semi-stale lines
                for i, t in pairs(self._colLines) do
                    if not used[i] and t.Hide then t:Hide() end
                end
            end

            -- Scroll area
            self.scroll:ClearAllPoints()
            self.scroll:SetPoint("TOPLEFT",  self.header, "BOTTOMLEFT", 0, -4)
            self.scroll:SetPoint("BOTTOMRIGHT", self.parent, "BOTTOMRIGHT", -rOff, 0)
            self.list:SetWidth(cW)

            -- place rows
            local y = 0
            local layoutSigParts = { tostring(pW), tostring(#resolved) }
            for i=1,#resolved do layoutSigParts[#layoutSigParts+1] = tostring(resolved[i].w or resolved[i].min or 0) end
            local layoutSig = table.concat(layoutSigParts, "|")

            -- Prepare a resolved variant without vseps for row layout (performance)
            local resolvedNoVsep = {}
            for i = 1, #resolved do
                local c = resolved[i]
                resolvedNoVsep[i] = { key=c.key, w=c.w, min=c.min, flex=c.flex, justify=c.justify, pad=c.pad, vsep=false }
            end

            for i = 1, #self._rows do
                local r = self._rows[i]
                if r and r:IsShown() then
                    r:SetWidth(cW)
                    r:ClearAllPoints()
                    r:SetPoint("TOPLEFT", self.list, "TOPLEFT", 0, -y)
                    y = y + r:GetHeight()
                    if r._layoutSig ~= layoutSig then
                        UI.LayoutRow(r, resolvedNoVsep, r._cells or {})
                        r._layoutSig = layoutSig
                    end
                end
            end
            self.list:SetHeight(y)

            if self.scroll.UpdateScrollChildRect then self.scroll:UpdateScrollChildRect() end

            -- Determine if scrollbar is needed and show/hide + place it in centered gutter
            local needSB = false
            do
                local yr    = (self.scroll.GetVerticalScrollRange and self.scroll:GetVerticalScrollRange()) or 0
                local viewH = self.scroll:GetHeight() or 0
                needSB = (yr > 0) or (y > (viewH + 1))
            end

            if sb then
                if needSB then
                    if sb.Show then sb:Show() end
                    if sb.EnableMouse then sb:EnableMouse(true) end
                    if sb.SetAlpha and UI.SCROLLBAR_ALPHA then sb:SetAlpha(UI.SCROLLBAR_ALPHA) end
                    if sb.SetWidth then sb:SetWidth(sbW) end
                    if sb.ClearAllPoints then
                        sb:ClearAllPoints()
                        -- Centered in gutter: left margin = inset, right margin = inset
                        sb:SetPoint("TOPLEFT",    self.scroll, "TOPRIGHT",  inset, 0)
                        sb:SetPoint("BOTTOMLEFT", self.scroll, "BOTTOMRIGHT", inset, 0)
                    end
                    if UI.UpdateScrollThumb then UI.UpdateScrollThumb(sb) end
                else
                    if sb.Hide then sb:Hide() end
                    if sb.EnableMouse then sb:EnableMouse(false) end
                end
            end

            -- If visibility changed, re-layout next frame (no visual shift when reserving gutter)
            if (self._showScrollbar == true) ~= (needSB and true or false) then
                self._showScrollbar = (needSB and true) or false
                if UI and UI.NextFrame then UI.NextFrame(function() if dt and dt.Layout then dt:Layout() end end) end
            end

            -- container bg spans header + scroll + color from theme if available
            if self._containerBG then
                self._containerBG:ClearAllPoints()
                self._containerBG:SetPoint("TOPLEFT", self.header, "TOPLEFT", 0, 0)
                -- include the gutter to the right so the scrollbar sits on the same background
                self._containerBG:SetPoint("BOTTOMRIGHT", self.parent, "BOTTOMRIGHT", 0, 0)
                local col = (UI.GetListViewContainerColor and UI.GetListViewContainerColor()) or { r=0, g=0, b=0, a=0.10 }
                self._containerBG:SetColorTexture(col.r or 0, col.g or 0, col.b or 0, col.a or 0.10)
            end

            -- empty overlay positioning
            EnsureEmpty(); local ov = self._empty
            if ov then
                ov:ClearAllPoints()
                ov:SetPoint("TOPLEFT", self.scroll, "TOPLEFT", 0, 0)
                ov:SetPoint("BOTTOMRIGHT", self.scroll, "BOTTOMRIGHT", 0, 0)
                ov:SetFrameStrata(self.scroll:GetFrameStrata() or "MEDIUM")
                ov:SetFrameLevel((self.scroll:GetFrameLevel() or 0) + 3)
            end

            -- header backgrounds (self-managed)
            self:_LayoutHeaderBGs(resolved)

            -- outer border
            do
                local b = self._border
                -- top
                b.top:ClearAllPoints()
                b.top:SetPoint("TOPLEFT", self.header, "TOPLEFT", 0, 0)
                -- span full width including gutter
                b.top:SetPoint("TOPRIGHT", self.parent, "TOPRIGHT", 0, 0)
                UI.SetPixelThickness(b.top, 1)
                -- bottom
                b.bottom:ClearAllPoints()
                b.bottom:SetPoint("BOTTOMLEFT", self.scroll, "BOTTOMLEFT", 0, 0)
                b.bottom:SetPoint("BOTTOMRIGHT", self.parent, "BOTTOMRIGHT", 0, 0)
                UI.SetPixelThickness(b.bottom, 1)
                -- left
                b.left:ClearAllPoints()
                -- Hide left border to avoid double bar with accent or style
                if b.left.Hide then b.left:Hide() end
                -- right: do not render a vertical border (avoid grey bar on the right)
                if b.right.Hide then b.right:Hide() end
            end

            self._inLayout = nil
        end

        -- row creation (pooling)
        local function CreateRow()
            local r = CreateFrame("Frame", nil, dt.list)
            r:SetHeight(dt._rowHWithPad)
            UI.DecorateRow(r)
            r._cells = {}
            r._cellSig = {}
            r._indent = 0
            r._isCategory = false
            -- build cells using column builders once
            for i, col in ipairs(dt.cols) do
                -- Skip building an in-cell widget for dedicated structural columns
                if col.treeCol then
                    -- Will place the toggle button into this column at render time
                elseif col.leftAccent then
                    -- reserved width; handled by r._accentLeft texture sizing/color
                else
                    local cell = (col.buildCell and col.buildCell(r)) or DefaultBuildCell(r)
                    r._cells[col.key] = cell
                end
            end
            -- row-level tree toggle button (for legacy or dedicated treeCol)
            do
                local btn = CreateFrame("Button", nil, r)
                btn:SetSize(16, 16)
                btn.icon = btn:CreateTexture(nil, "OVERLAY")
                btn.icon:SetAllPoints(btn)
                btn.icon:SetTexture("Interface\\Buttons\\UI-PlusMinus-Buttons")
                btn.icon:SetTexCoord(0, 0.5, 0, 0.5)
                btn:SetScript("OnClick", function()
                    if r._rowKey then dt:ToggleRow(r._rowKey) end
                end)
                btn:Hide()
                r._treeBtn = btn
            end

            -- Category row visuals (full-width background + label and optional count)
            do
                local bg = r:CreateTexture(nil, "OVERLAY")
                if bg.SetDrawLayer then bg:SetDrawLayer("OVERLAY", 7) end -- on top
                -- Choose atlas/texture for category background in this priority:
                -- 1) opts.categoryAtlasName (atlas)
                -- 2) theme-aware atlases (Alliance/Horde/Neutral) CardParchment / BackgroundTile
                -- 3) opts.categoryTexture (file path)
                -- 4) gradient dark strip
                local function atlasExists(name)
                    return name and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name)
                end
                local applied = false
                local alpha = (dt.opts and dt.opts.categoryAlpha) or 0.75
                local desiredAtlas = dt.opts and dt.opts.categoryAtlasName
                if atlasExists(desiredAtlas) then
                    bg:SetAtlas(desiredAtlas, true)
                    bg:SetAlpha(alpha)
                    applied = true
                else
                    local faction = UnitFactionGroup and UnitFactionGroup("player") or "Neutral"
                    local theme = (faction == "Alliance" and "Alliance") or (faction == "Horde" and "Horde") or "Neutral"
                    local candidates = {
                        "UI-Frame-"..theme.."-CardParchment",
                        "UI-Frame-"..theme.."-BackgroundTile",
                        "UI-Frame-Neutral-CardParchment",
                        "UI-Frame-Neutral-BackgroundTile",
                    }
                    for i=1,#candidates do
                        if atlasExists(candidates[i]) then
                            bg:SetAtlas(candidates[i], true)
                            bg:SetAlpha(alpha)
                            applied = true
                            break
                        end
                    end
                end
                if (not applied) and dt.opts and dt.opts.categoryTexture then
                    bg:SetTexture(dt.opts.categoryTexture)
                    bg:SetAlpha(alpha)
                    applied = true
                end
                if not applied then
                    bg:SetColorTexture(0.18, 0.18, 0.18, 0.95)
                    if bg.SetGradient then
                        bg:SetGradient("VERTICAL", CreateColor(0.14,0.14,0.14,0.95), CreateColor(0.20,0.20,0.20,0.95))
                    end
                end
                bg:Hide()
                r._catBG = bg

                -- No blocker: categories must remain fully transparent behind their own textures

                -- TWW scenario barframe triple-slice (left/mid tiled/right)
                r._catLeftTex = r:CreateTexture(nil, "ARTWORK")
                r._catRightTex = r:CreateTexture(nil, "ARTWORK")
                -- Draw caps above mid tiles to cover any seams
                if r._catLeftTex.SetDrawLayer then r._catLeftTex:SetDrawLayer("ARTWORK", 2) end
                if r._catRightTex.SetDrawLayer then r._catRightTex:SetDrawLayer("ARTWORK", 3) end
                r._catMidSegs = {}
                r._catLeftTex:Hide(); r._catRightTex:Hide()

                local label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                if UI and UI.ApplyFont then UI.ApplyFont(label) end
                if label.SetFontObject then pcall(function() label:SetFontObject("GameFontHighlightLarge") end) end
                label:SetJustifyH("LEFT")
                label:SetJustifyV("MIDDLE")
                label:Hide()
                r._catText = label

                local count = r:CreateFontString(nil, "OVERLAY", "GameFontDisable")
                if UI and UI.ApplyFont then UI.ApplyFont(count) end
                count:SetJustifyH("RIGHT")
                count:SetJustifyV("MIDDLE")
                count:Hide()
                r._catCount = count

                -- Category arrow icon (visual only); uses PageUp/Down Mouseover atlases
                local icon = r:CreateTexture(nil, "OVERLAY")
                icon:SetSize(16,16)
                icon:Hide()
                r._catIcon = icon

                -- Full-row click area for category rows (toggles expand/collapse)
                local click = CreateFrame("Button", nil, r)
                click:Hide()
                click:SetScript("OnClick", function()
                    if r._rowKey then dt:ToggleRow(r._rowKey) end
                end)
                r._catClick = click

                -- Thin top/bottom edges to separate categories from rows
                local top = r:CreateTexture(nil, "OVERLAY")
                top:SetTexture('Interface\\Buttons\\WHITE8x8')
                top:SetVertexColor(1,1,1,0.10)
                local bot = r:CreateTexture(nil, "OVERLAY")
                bot:SetTexture('Interface\\Buttons\\WHITE8x8')
                bot:SetVertexColor(0,0,0,0.35)
                r._catEdgeTop = top; r._catEdgeBottom = bot
                top:Hide(); bot:Hide()
            end
            return r
        end

        function dt:_EnsureRows(n)
            local have = #self._rows
            if have >= n then return end
            for i = have + 1, n do
                local r = CreateRow()
                self._rows[i] = r
            end
        end

        function dt:_HideExtraRows(fromIndex)
            for i = fromIndex, #self._rows do
                local r = self._rows[i]
                if r then r:Hide(); r._rowKey = nil end
            end
        end

        -- flatten hierarchical data according to expanded flags
        local function Flatten(input)
            local out = {}
            local function addRow(row, level, parentKey)
                row._level = level or 0
                row._parentKey = parentKey
                out[#out+1] = row
                if row.expanded and row.children and #row.children > 0 then
                    for _, ch in ipairs(row.children) do addRow(ch, (level or 0) + 1, row.key) end
                end
            end
            for _, r in ipairs(input or {}) do addRow(r, 0, nil) end
            return out
        end

        local function DefaultComparator(col, asc)
            local mult = asc and 1 or -1
            local function extract(row)
                -- Explicit sort source has priority
                local sv = col and col.sortValue
                local tsv = type(sv)
                if tsv == 'function' then
                    local ok, v = pcall(sv, row)
                    if ok then return v end
                elseif tsv == 'string' and sv ~= '' then
                    local cells = row.cells or {}
                    if cells[sv] ~= nil then return cells[sv] end
                    if row[sv] ~= nil then return row[sv] end
                end
                -- Backward compat
                if col and col.valueOf then
                    local ok, v = pcall(col.valueOf, row)
                    if ok then return v end
                end
                return (row.cells and row.cells[col.key])
            end
            local function toNum(v)
                if type(v) == 'number' then return v end
                if type(v) == 'table' then
                    if v.n then return tonumber(v.n) or 0 end
                    if v.value then return tonumber(v.value) or 0 end
                    if v.amount then return tonumber(v.amount) or 0 end
                end
                if type(v) == 'string' then
                    local s = v:match("[-%d%.]+")
                    return tonumber(s) or 0
                end
                return tonumber(v) or 0
            end
            return function(a, b)
                local va = extract(a)
                local vb = extract(b)
                if col and col.sortNumeric then
                    local na, nb = toNum(va), toNum(vb)
                    if na ~= nb then return (na - nb) * mult < 0 end
                    return tostring(a.key) < tostring(b.key)
                else
                    -- If both are numbers, numeric compare by default
                    if type(va) == 'number' and type(vb) == 'number' then
                        if va ~= vb then return (va - vb) * mult < 0 end
                        return tostring(a.key) < tostring(b.key)
                    end
                    local sa, sb = tostring(va or ""), tostring(vb or "")
                    if sa == sb then return (tostring(a.key) < tostring(b.key)) end
                    if asc then return sa < sb else return sa > sb end
                end
            end
        end

        function dt:_SortInPlace(arr)
            local s = self._sort or { key=nil }
            if not s.key then return end
            local col
            for _, c in ipairs(self.cols) do if c.key == s.key then col = c; break end end
            if not col then return end
            local cmp = (col.comparator and col.comparator(s.asc)) or DefaultComparator(col, s.asc ~= false)
            table.sort(arr, cmp)
        end

        -- render apply flat data -> frames with minimal per-cell updates
        function dt:_RenderFlat(flat)
            self._flatData = flat or {}
            -- keep map for targeted updates
            local map = self._dataMap
            for k in pairs(map) do map[k] = nil end
            for i = 1, #flat do map[ flat[i].key ] = flat[i] end

            self:_EnsureRows(#flat)

            local shown = 0
            for i = 1, #flat do
                local data = flat[i]
                local r = self._rows[i]
                r:Show()
                shown = shown + 1
                r._rowKey = data.key
                r._indent = tonumber(data._level or 0) or 0
                -- height (uniform per row)
                local baseH = self._rowHWithPad
                if r._targetH ~= baseH then r._targetH = baseH; r:SetHeight(baseH) end

                -- Reset pooled UI elements that can leak between row types
                if r._treeBtn and r._treeBtn.Hide then r._treeBtn:Hide() end
                if r._catIcon and r._catIcon.Hide then r._catIcon:Hide() end
                if r._catClick and r._catClick.Hide then r._catClick:Hide() end

                -- Detect category row
                local isCat = (data.isCategory or data.categoryRow or data.category) and true or false
                r._isCategory = isCat

                -- Category layout/visuals
                if isCat then
                    -- Hide default row gradient for category rows (no background on the category line)
                    if r._bg and r._bg.Hide then r._bg:Hide() end
                    -- Show background spanning full row width and place text/count
                    local usedTitle = false
                    local usedScenario = false
                    do
                        local function atlasInfo(name)
                            if not (C_Texture and C_Texture.GetAtlasInfo) then return nil end
                            return name and C_Texture.GetAtlasInfo(name) or nil
                        end
                        -- Prefer The War Within Title atlases
                        local candidatesL = {"ui-frame-thewarwithin-titleleft", "UI-Frame-TheWarWithin-TitleLeft"}
                        local candidatesM = {"_ui-frame-thewarwithin-titlemiddle", "ui-frame-thewarwithin-titlemiddle", "_UI-Frame-TheWarWithin-TitleMiddle", "UI-Frame-TheWarWithin-TitleMiddle"}
                        local candidatesR = {"ui-frame-thewarwithin-titleright", "UI-Frame-TheWarWithin-TitleRight"}
                        local ATL_TL, ATL_TM, ATL_TR
                        for _,nm in ipairs(candidatesL) do if atlasInfo(nm) then ATL_TL = nm; break end end
                        for _,nm in ipairs(candidatesM) do if atlasInfo(nm) then ATL_TM = nm; break end end
                        for _,nm in ipairs(candidatesR) do if atlasInfo(nm) then ATL_TR = nm; break end end
                            usedTitle = true
                            r._catStyle = "title"; r._catAtlas = {L=ATL_TL, M=ATL_TM, R=ATL_TR}
                            local aiL, aiM, aiR = atlasInfo(ATL_TL), atlasInfo(ATL_TM), atlasInfo(ATL_TR)
                            local h = math.max(1, r:GetHeight() or 1)
                            -- Left (native atlas width scaled to row height, rounded to integer px)
                            r._catLeftTex:SetAtlas(ATL_TL, true)
                            local wL = math.max(1, math.floor(((aiL and aiL.width or 1) * (h / ((aiL and aiL.height) or h))) + 0.5))
                            r._catWLeft = wL
                            r._catLeftTex:ClearAllPoints()
                            r._catLeftTex:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
                            r._catLeftTex:SetSize(wL, h)
                            r._catLeftTex:Show()
                            if UI and UI.SnapTexture then UI.SnapTexture(r._catLeftTex) end
                            -- Right
                            r._catRightTex:SetAtlas(ATL_TR, true)
                            local wR = math.max(1, math.floor(((aiR and aiR.width or 1) * (h / ((aiR and aiR.height) or h))) + 0.5))
                            r._catWRight = wR
                            r._catRightTex:ClearAllPoints()
                            r._catRightTex:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, 0)
                            r._catRightTex:SetSize(wR, h)
                            r._catRightTex:Show()
                            if UI and UI.SnapTexture then UI.SnapTexture(r._catRightTex) end
                            -- Middle tiled segments
                            local totalW = math.max(1, math.floor(((r:GetWidth() or (self.list and self.list:GetWidth()) or 1)) + 0.5))
                            local midArea = math.max(1, totalW - wL - wR)
                            local segW0  = math.max(1, (aiM and aiM.width) or 1)
                            local segH0  = math.max(1, (aiM and aiM.height) or 1)
                            local segW   = math.max(1, math.floor((segW0 * (h / segH0)) + 0.5))
                            local need   = math.max(1, math.floor(midArea / segW))
                            r._catMidSegs = r._catMidSegs or {}
                            for i=1, need do
                                if not r._catMidSegs[i] then r._catMidSegs[i] = r:CreateTexture(nil, "ARTWORK") end
                                local t = r._catMidSegs[i]
                                t:SetAtlas(ATL_TM, true)
                                t:ClearAllPoints()
                                local x = wL + (i-1) * segW
                                t:SetPoint("TOPLEFT", r, "TOPLEFT", x, 0)
                                t:SetSize(segW, h)
                                t:Show()
                                if t.SetDrawLayer then t:SetDrawLayer("ARTWORK", 1) end
                                if UI and UI.SnapTexture then UI.SnapTexture(t) end
                            end
                            for i=need+1, #(r._catMidSegs) do if r._catMidSegs[i] then r._catMidSegs[i]:Hide() end end
                            local last = r._catMidSegs[need]
                            if last then
                                local usedW = (need-1) * segW
                                local rem = math.max(0, midArea - usedW)
                                last:ClearAllPoints()
                                local xLast = wL + (need-1) * segW
                                last:SetPoint("TOPLEFT", r, "TOPLEFT", xLast, 0)
                                local lastW = (rem > 0) and rem or segW
                                last:SetSize(lastW, h)
                                if UI and UI.SnapTexture then UI.SnapTexture(last) end
                                if rem > 0 and rem < segW then
                                    local uL,uR,vT,vB = last:GetTexCoord(); if not uL then uL,uR,vT,vB = 0,1,0,1 end
                                    local frac = rem / segW
                                    local eps = 0.0015
                                    last:SetTexCoord(uL, (uL + (uR-uL)*frac) - eps, vT, vB)
                                else
                                    last:SetTexCoord(0,1,0,1)
                                end
                            end
                        
                    end
                    -- No row background for categories: always hide the simple bg
                    if r._catBG and r._catBG.Hide then r._catBG:Hide() end
                    -- If no triple-slice available we simply keep the row transparent (no background)
                    if not (usedTitle or usedScenario) then
                        if r._catLeftTex then r._catLeftTex:Hide() end
                        if r._catRightTex then r._catRightTex:Hide() end
                        if r._catMidSegs then for _,t in ipairs(r._catMidSegs) do if t.Hide then t:Hide() end end end
                        r._catWLeft, r._catWRight = 0, 0
                    else
                        -- Keep fully transparent behind triple-slice as requested (no blocker)
                    end
                    -- Hook one-time resize relayout for category triple-slice
                    if (usedTitle or usedScenario) and not r._catHooked then
                        r._catHooked = true
                        r:HookScript("OnSizeChanged", function(self)
                            if not (self._catStyle and self._catAtlas and self._isCategory) then return end
                            local L, M, R = self._catAtlas.L, self._catAtlas.M, self._catAtlas.R
                            local aiL = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(L)
                            local aiM = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(M)
                            local aiR = C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(R)
                            if not (aiL and aiM and aiR) then return end
                            local h = math.max(1, self:GetHeight() or 1)
                            -- Left (native atlas width scaled to row height, rounded)
                            local wL = math.max(1, math.floor(((aiL and aiL.width or 1) * (h / ((aiL and aiL.height) or h))) + 0.5))
                            self._catLeftTex:ClearAllPoints(); self._catLeftTex:SetPoint("TOPLEFT", self, "TOPLEFT", 0, 0)
                            self._catLeftTex:SetSize(wL, h)
                            if UI and UI.SnapTexture then UI.SnapTexture(self._catLeftTex) end
                            -- Right
                            local wR = math.max(1, math.floor(((aiR and aiR.width or 1) * (h / ((aiR and aiR.height) or h))) + 0.5))
                            self._catRightTex:ClearAllPoints(); self._catRightTex:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, 0)
                            self._catRightTex:SetSize(wR, h)
                            if UI and UI.SnapTexture then UI.SnapTexture(self._catRightTex) end
                            -- Mid
                            local totalW = math.max(1, math.floor((self:GetWidth() or 1) + 0.5))
                            local midArea = math.max(1, totalW - wL - wR)
                            local segW0  = math.max(1, (aiM and aiM.width) or 1)
                            local segH0  = math.max(1, (aiM and aiM.height) or 1)
                            local segW   = math.max(1, math.floor((segW0 * (h / segH0)) + 0.5))
                            local need   = math.max(1, math.floor(midArea / segW))
                            self._catMidSegs = self._catMidSegs or {}
                            for i=1, need do
                                if not self._catMidSegs[i] then self._catMidSegs[i] = self:CreateTexture(nil, "ARTWORK") end
                                local t = self._catMidSegs[i]
                                t:SetAtlas(M, true)
                                t:ClearAllPoints(); t:SetPoint("TOPLEFT", self, "TOPLEFT", wL + (i-1) * segW, 0)
                                t:SetSize(segW, h); t:Show()
                                if t.SetDrawLayer then t:SetDrawLayer("ARTWORK", 1) end
                                if UI and UI.SnapTexture then UI.SnapTexture(t) end
                            end
                            for i=need+1, #(self._catMidSegs) do if self._catMidSegs[i] then self._catMidSegs[i]:Hide() end end
                            local last = self._catMidSegs[need]
                            if last then
                                local usedW = (need-1) * segW
                                local rem = math.max(0, midArea - usedW)
                                last:ClearAllPoints()
                                local xLast = wL + (need-1) * segW
                                last:SetPoint("TOPLEFT", self, "TOPLEFT", xLast, 0)
                                local lastW = (rem > 0) and rem or segW
                                last:SetSize(lastW, h)
                                if UI and UI.SnapTexture then UI.SnapTexture(last) end
                                if rem > 0 and rem < segW then
                                    local uL,uR,vT,vB = last:GetTexCoord(); if not uL then uL,uR,vT,vB = 0,1,0,1 end
                                    local frac = rem / segW
                                    local eps = 0.0015
                                    last:SetTexCoord(uL, (uL + (uR-uL)*frac) - eps, vT, vB)
                                else
                                    last:SetTexCoord(0,1,0,1)
                                end
                            end
                            -- Reposition toggle/text/count inside the middle zone on resize
                            self._catWLeft, self._catWRight = wL, wR
                            local baseLeftPad = (self._catWLeft or 0) + 8
                            local leftPadIcon = math.max(0, baseLeftPad - 25) -- only arrows shift left by 25px
                            local rightPad = (self._catWRight or 0) + 8
                            if self._catIcon then
                                self._catIcon:ClearAllPoints()
                                self._catIcon:SetPoint("LEFT", self, "LEFT", leftPadIcon, 0)
                            end
                            if self._treeBtn then
                                self._treeBtn:ClearAllPoints()
                                -- tree toggle keeps original placement (no extra shift)
                                self._treeBtn:SetPoint("LEFT", self, "LEFT", baseLeftPad, 0)
                            end
                            if self._catCount then
                                self._catCount:ClearAllPoints()
                                local adjRight = math.max(0, rightPad - 20)
                                self._catCount:SetPoint("RIGHT", self, "RIGHT", -adjRight, 0)
                            end
                            if self._catText then
                                self._catText:ClearAllPoints()
                                if self._treeBtn and self._treeBtn:IsShown() then
                                    -- shift text 20px to the right (from -14 to +6)
                                    self._catText:SetPoint("LEFT", self._treeBtn, "RIGHT", 6, 0)
                                else
                                    -- shift text 20px to the right (from baseLeftPad-20 to baseLeftPad)
                                    local adjLeft = math.max(0, baseLeftPad)
                                    self._catText:SetPoint("LEFT", self, "LEFT", adjLeft, 0)
                                end
                                if self._catCount and self._catCount:IsShown() then
                                    self._catText:SetPoint("RIGHT", self._catCount, "LEFT", -8, 0)
                                else
                                    local adjRight2 = math.max(0, rightPad - 20)
                                    self._catText:SetPoint("RIGHT", self, "RIGHT", -adjRight2, 0)
                                end
                            end
                        end)
                    end
                    if r._catEdgeTop and r._catEdgeBottom then
                        r._catEdgeTop:ClearAllPoints()
                        r._catEdgeTop:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
                        r._catEdgeTop:SetPoint("TOPRIGHT", r, "TOPRIGHT", 0, 0)
                        if UI.SetPixelThickness then UI.SetPixelThickness(r._catEdgeTop, 1) else r._catEdgeTop:SetHeight(1) end
                        r._catEdgeTop:Show()
                        r._catEdgeBottom:ClearAllPoints()
                        r._catEdgeBottom:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", 0, 0)
                        r._catEdgeBottom:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
                        if UI.SetPixelThickness then UI.SetPixelThickness(r._catEdgeBottom, 1) else r._catEdgeBottom:SetHeight(1) end
                        r._catEdgeBottom:Show()
                    end
                    local title = data.title or data.categoryTitle or (data.cells and (data.cells.title or data.cells.label)) or ""
                    -- Category arrow icon state + placement
                    do
                        -- Only arrow shifts 25px left; others keep original padding
                        local baseLeftPad = (r._catWLeft or 0) + 8
                        local leftPad = math.max(0, baseLeftPad - 25) -- match OnSizeChanged logic
                        if r._catIcon then
                            r._catIcon:ClearAllPoints()
                            r._catIcon:SetPoint("LEFT", r, "LEFT", leftPad, 0)
                            -- Choose atlas based on expanded state
                            local atl = data.expanded and "UI-HUD-ActionBar-PageDownArrow-Mouseover" or "UI-HUD-ActionBar-PageUpArrow-Mouseover"
                            if C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atl) then
                                r._catIcon:SetAtlas(atl, true)
                            else
                                -- Fallback to plus/minus spritesheet roughly
                                r._catIcon:SetTexture("Interface\\Buttons\\UI-PlusMinus-Buttons")
                                if data.expanded then r._catIcon:SetTexCoord(0.5,1,0,0.5) else r._catIcon:SetTexCoord(0,0.5,0,0.5) end
                            end
                            r._catIcon:Show()
                        end
                    end
                    if r._catText then
                        r._catText:ClearAllPoints()
                        local baseLeftPad = (r._catWLeft or 0) + 8
                        local rightPad = (r._catWRight or 0) + 8
                        -- Match OnSizeChanged: prefer tree toggle if shown; otherwise use base left pad, shifted +20px
                        if r._treeBtn and r._treeBtn:IsShown() then
                            r._catText:SetPoint("LEFT", r._treeBtn, "RIGHT", 6, 0)
                        else
                            local adjLeft = math.max(0, baseLeftPad)
                            r._catText:SetPoint("LEFT", r, "LEFT", adjLeft, 0)
                        end
                        if r._catCount and r._catCount:IsShown() then
                            r._catText:SetPoint("RIGHT", r._catCount, "LEFT", -8, 0)
                        else
                            local adjRight = math.max(0, rightPad - 20)
                            r._catText:SetPoint("RIGHT", r, "RIGHT", -adjRight, 0)
                        end
                        r._catText:SetText(tostring(title or ""))
                        r._catText:Show()
                    end
                    local count = data.count
                    if count == nil and type(data.children) == 'table' then count = #data.children end
                    if r._catCount then
                        r._catCount:ClearAllPoints()
                        local rightPad = (r._catWRight or 0) + 8
                        local adjRight = math.max(0, rightPad - 20)
                        r._catCount:SetPoint("RIGHT", r, "RIGHT", -adjRight, 0)
                        if count ~= nil then r._catCount:SetText("("..tostring(count)..")") else r._catCount:SetText("") end
                        r._catCount:Show()
                    end
                    -- Hide +/- button on category rows to avoid duplicate visuals; use the full-row click area instead
                    if r._treeBtn and r._treeBtn.Hide then r._treeBtn:Hide() end
                    if r._catClick then
                        r._catClick:ClearAllPoints()
                        r._catClick:SetPoint("TOPLEFT", r, "TOPLEFT", 0, 0)
                        r._catClick:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", 0, 0)
                        r._catClick:Show()
                    end
                    -- Hide all standard cells and structural accents for category rows
                    for _, col in ipairs(self.cols) do
                        local cell = r._cells[col.key]
                        if cell and cell.Hide then cell:Hide() end
                    end
                    if r._accentLeft and r._accentLeft.Hide then r._accentLeft:Hide() end
                else
                    -- Restore default row gradient for non-category rows
                    if r._bg and r._bg.Show then r._bg:Show() end
                    -- Non-category: ensure category visuals are hidden
                    if r._catIcon and r._catIcon.Hide then r._catIcon:Hide() end
                    if r._catClick and r._catClick.Hide then r._catClick:Hide() end
                    -- Do NOT force-show the pooled tree button; let the tree logic toggle it based on children
                    if r._treeBtn and r._treeBtn.Hide then r._treeBtn:Hide() end
                    if r._catBG and r._catBG.Hide then r._catBG:Hide() end
                    if r._catLeftTex and r._catLeftTex.Hide then r._catLeftTex:Hide() end
                    if r._catRightTex and r._catRightTex.Hide then r._catRightTex:Hide() end
                    if r._catMidSegs then for _,t in ipairs(r._catMidSegs) do if t.Hide then t:Hide() end end end
                    if r._catEdgeTop and r._catEdgeTop.Hide then r._catEdgeTop:Hide() end
                    if r._catEdgeBottom and r._catEdgeBottom.Hide then r._catEdgeBottom:Hide() end
                    if r._catText and r._catText.Hide then r._catText:Hide() end
                    if r._catCount and r._catCount.Hide then r._catCount:Hide() end
                    -- Ensure standard cells are shown (they may have been hidden by a previous category use of this pooled frame)
                    for _, col in ipairs(self.cols) do
                        local cell = r._cells[col.key]
                        if cell and cell.Show then cell:Show() end
                    end
                end

                -- For category rows, skip the rest of the standard row updates
                if not isCat then
                -- per-row special columns (leftAccent, tree toggle column)
                -- Left accent as dedicated column: show/hide and set thickness/color without overlapping content
                if self._leftAccentIndex and r._accentLeft then
                    local show, colr
                    local colSpec = self.cols[self._leftAccentIndex]
                    if colSpec and type(colSpec.accentOf) == 'function' then
                        local ok, res = pcall(colSpec.accentOf, data, i)
                        if ok then
                            if type(res) == 'table' then show, colr = true, res else show = (res and true) or false end
                        end
                    else
                        -- Fallback: truthy value in the accent column key or row.accent
                        local key = colSpec and colSpec.key
                        local v = (key and data.cells and data.cells[key]) or data.accent
                        show = not not v
                    end
                    if show then
                        local acc = r._accentLeft
                        if acc then
                            if colr and type(colr) == 'table' then
                                local cr = { colr.r or colr[1] or 1, colr.g or colr[2] or .82, colr.b or colr[3] or 0, colr.a or colr[4] or .9 }
                                acc:SetVertexColor(cr[1], cr[2], cr[3], cr[4])
                            end
                            if UI.SetPixelThickness then UI.SetPixelThickness(acc, math.max(1, self._leftAccentW)) end
                            acc:Show()
                        end
                    else
                        if r._accentLeft and r._accentLeft.Hide then r._accentLeft:Hide() end
                    end
                else
                    -- hide any default accent if not using dedicated column
                    if r._accentLeft and r._accentLeft.Hide then r._accentLeft:Hide() end
                end

                -- Position dedicated tree column button if requested
                if self._treeColIndex and r._treeBtn then
                    local colSpec = self.cols[self._treeColIndex]
                    local hostX = 0
                    -- place the button at the left of the tree column cell region
                    -- We don't have the field object for treeCol; approximate offset using layout of resolved columns
                    -- Fallback: anchor to row's left + accumulated width before tree column
                    local x = 0
                    local resolved = self:_ResolveCols(self.parent:GetWidth() or 0)
                    for idx = 1, (self._treeColIndex - 1) do
                        local c = resolved[idx]
                        x = x + (c and (c.w or c.min or 0) or 0)
                    end
                    r._treeBtn:ClearAllPoints()
                    r._treeBtn:SetPoint("LEFT", r, "LEFT", x + 4 + (r._indent * 14), 0)
                    local hasChildren = data.children and #data.children > 0
                    r._treeBtn:SetShown(hasChildren)
                    if hasChildren then
                        if data.expanded then
                            r._treeBtn.icon:SetTexCoord(0.5, 1.0, 0, 0.5)
                        else
                            r._treeBtn.icon:SetTexCoord(0, 0.5, 0, 0.5)
                        end
                    end
                end

                -- per-cell update using signatures
                for _, col in ipairs(self.cols) do
                    local cell = r._cells[col.key]
                    local value = data.cells and data.cells[col.key]
                    -- tree toggle inside a cell (legacy) only when no dedicated tree column
                    if (not self._treeColIndex) and col.treeToggle and r._treeBtn then
                        -- indent host
                        if cell and cell.SetPoint then
                            cell:ClearAllPoints()
                            cell:SetPoint("LEFT", r, "LEFT", 4 + (r._indent * 14), 0)
                        end
                        -- toggle visibility
                        local hasChildren = data.children and #data.children > 0
                        r._treeBtn:SetShown(hasChildren)
                        if hasChildren then
                            if data.expanded then
                                -- minus
                                r._treeBtn.icon:SetTexCoord(0.5, 1.0, 0, 0.5)
                            else
                                -- plus
                                r._treeBtn.icon:SetTexCoord(0, 0.5, 0, 0.5)
                            end
                            -- place button before text/icon within the host
                            r._treeBtn:ClearAllPoints()
                            r._treeBtn:SetPoint("LEFT", cell, "LEFT", 0, 0)
                        end
                    elseif type(cell) == 'table' and cell.SetPoint then
                        -- first column indent if it has no treeToggle
                        if (not self._treeColIndex) and col == self.cols[1] then
                            cell:ClearAllPoints()
                            cell:SetPoint("LEFT", r, "LEFT", 4 + (r._indent * 14), 0)
                        end
                    end

                    local sig = Sig(value)
                    local must = (col and col.forceUpdate) and true or false
                    if must or r._cellSig[col.key] ~= sig then
                        -- expose row metadata for advanced cell updaters without expanding call signature
                        if type(cell) == 'table' then
                            cell._rowData  = data
                            cell._rowIndex = i
                            cell._level    = r._indent
                        end
                        local update = col.updateCell or DefaultUpdateCell
                        update(cell, value)
                        r._cellSig[col.key] = sig
                    end
                end
                end -- not category
            end

            self:_HideExtraRows(#flat + 1)
            self:Layout()
            EnsureEmpty(); dt._empty:SetShown(shown == 0)
        end

        function dt:_PrepareData(data)
            local arr = data or {}
            -- If top-level contains category rows, we sort within each category independently.
            local hasCategory = false
            for i = 1, #arr do if arr[i] and (arr[i].isCategory or arr[i].categoryRow or arr[i].category) then hasCategory = true; break end end

            local function sortArray(a)
                -- shallow copy to avoid mutating caller list during sort
                local copy = {}
                for i = 1, #a do copy[i] = a[i] end
                self:_SortInPlace(copy)
                return copy
            end

            local prepared
            if hasCategory then
                -- Optionally sort top-level categories (off by default to preserve user order)
                local top = {}
                for i = 1, #arr do top[i] = arr[i] end
                if self.opts and self.opts.sortCategories then
                    local s = self._sort or { key=nil }
                    if s.key then self:_SortInPlace(top) end
                end
                -- Sort each category's children independently using current column
                for i = 1, #top do
                    local cat = top[i]
                    if cat and type(cat.children) == 'table' and #cat.children > 0 then
                        cat.children = sortArray(cat.children)
                    end
                end
                prepared = top
            else
                prepared = sortArray(arr)
            end
            return Flatten(prepared)
        end

        -- Public API
        function dt:SetData(rows)
            self._rawData = rows or {}
            local flat = self:_PrepareData(self._rawData)
            self:_RenderFlat(flat)
        end

        -- Minimal diff-applier: recompute flat and update only cells whose signatures changed.
        function dt:DiffAndApply(newRows)
            self._rawData = newRows or {}
            local flat = self:_PrepareData(self._rawData)
            self:_RenderFlat(flat)
        end

        function dt:UpdateCell(rowKey, colKey, value)
            if not rowKey or not colKey then return end
            local data = self._dataMap[rowKey]
            if not data then return end
            data.cells = data.cells or {}
            data.cells[colKey] = value
            local frame = self._rowByKey[rowKey]
            -- in current design we map by index; build a quick reverse map here (cheap)
            if not frame then
                for i = 1, #self._rows do local r = self._rows[i]; if r and r._rowKey == rowKey then frame = r; break end end
                self._rowByKey[rowKey] = frame
            end
            if frame then
                local col
                for _, c in ipairs(self.cols) do if c.key == colKey then col = c; break end end
                if col then
                    local cell = frame._cells[colKey]
                    local sig = Sig(value)
                    if frame._cellSig[colKey] ~= sig then
                        if type(cell) == 'table' then
                            cell._rowData  = data
                            cell._rowIndex = nil
                            cell._level    = frame._indent
                        end
                        local update = col.updateCell or DefaultUpdateCell
                        update(cell, value)
                        frame._cellSig[colKey] = sig
                    end
                end
            end
        end

        function dt:SetSort(colKey, asc)
            self._sort = { key = colKey, asc = (asc ~= false) }
            if self._rawData then self:SetData(self._rawData) end
        end

        function dt:ToggleRow(rowKey, expanded)
            local data = self._dataMap[rowKey]
            if not data then return end
            if expanded == nil then
                data.expanded = not data.expanded
            else
                data.expanded = (expanded and true) or false
            end
            -- Propagate to rawData entry too (same object if not copied by caller)
            self:_RenderFlat(self:_PrepareData(self._rawData))
        end

        function dt:ExpandAll()
            local function setAll(rows)
                for _, r in ipairs(rows or {}) do r.expanded = true; setAll(r.children) end
            end
            setAll(self._rawData or {})
            self:SetData(self._rawData)
        end

        function dt:CollapseAll()
            local function setAll(rows)
                for _, r in ipairs(rows or {}) do r.expanded = false; setAll(r.children) end
            end
            setAll(self._rawData or {})
            self:SetData(self._rawData)
        end

        -- Layout on size changes
        if parent and parent.HookScript then
            parent:HookScript("OnSizeChanged", function() if dt and dt.Layout then dt:Layout() end end)
        end
        if dt.scroll and dt.scroll.HookScript then
            dt.scroll:HookScript("OnSizeChanged", function() if dt and dt.Layout then dt:Layout() end end)
        end

        -- public getter for rows count
        function dt:Count()
            return #self._flatData
        end

        -- initial layout
        dt:Layout()
        return dt
    end
end
