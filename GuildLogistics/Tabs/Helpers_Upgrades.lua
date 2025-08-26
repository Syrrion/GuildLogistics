-- Tabs/Helpers_UpgradeTracks.lua
local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns.GLOG, ns.UI

local DATA = ns and ns.Data and ns.Data.UpgradeTracks

-- État local
local panel, lv
local _headerBGs -- textures de fond colorées par colonne (header)

-- Colonnes (structure standard ListView)
local cols = UI.NormalizeColumns({
    { key="ilvl",      title = (DATA and DATA.headers and DATA.headers.itemLevel), min=140, flex=1 , justify="LEFT"  },
    { key="crest",     title = (DATA and DATA.headers and DATA.headers.crests)    ,     min=140, flex=1},
    { key="aventurier",title = (DATA and DATA.headers and DATA.headers.aventurier),      w=160, justify="CENTER"  },
    { key="veteran",   title = (DATA and DATA.headers and DATA.headers.veteran)   ,         w=160, justify="CENTER"  },
    { key="champion",  title = (DATA and DATA.headers and DATA.headers.champion)  ,        w=160, justify="CENTER"  },
    { key="heros",     title = (DATA and DATA.headers and DATA.headers.heros)     ,           w=160, justify="CENTER"  },
    { key="mythe",     title = (DATA and DATA.headers and DATA.headers.mythe)     ,           w=160, justify="CENTER"  },
})

-- == Rangée : création des cellules ==
local function BuildRow(r)
    local f = {}
    -- Texte simple
    f.ilvl  = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.ilvl:SetJustifyH("LEFT")

    f.crest = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.crest:SetJustifyH("LEFT")

    -- Badges colorés réutilisables (UI.CreateBadgeCell)
    f.aventurier = UI.CreateBadgeCell(r, { centeredGloss = true })
    f.veteran    = UI.CreateBadgeCell(r, { centeredGloss = true })
    f.champion   = UI.CreateBadgeCell(r, { centeredGloss = true })
    f.heros      = UI.CreateBadgeCell(r, { centeredGloss = true })
    f.mythe      = UI.CreateBadgeCell(r, { centeredGloss = true })
    return f
end

-- == Rangée : mise à jour d’une cellule ==
local function UpdateRow(i, r, f, it)
    local now  = tonumber(it.ilvl or 0) or 0
    f.ilvl:SetText(string.format("%d", now))

    -- Colonne écus
    f.crest:SetText(tostring(it.crest or ""))

    -- Petites aides
    local pal = (DATA and DATA.palette and DATA.palette.cells) or {}
    local function setBadge(cell, keyLabel, labelText)
        if not cell then return end
        if labelText and labelText ~= "" then
            local c = pal[keyLabel] or {0.5,0.5,0.5,0.25}
            -- UI.SetBadgeCell attend {r,g,b} sans alpha
            UI.SetBadgeCell(cell, { c[1], c[2], c[3] }, labelText)
            cell:Show()
        else
            cell:Hide()
        end
    end
    setBadge(f.aventurier, "aventurier", it.aventurier)
    setBadge(f.veteran,    "veteran",    it.veteran)
    setBadge(f.champion,   "champion",   it.champion)
    setBadge(f.heros,      "heros",      it.heros)
    setBadge(f.mythe,      "mythe",      it.mythe)
end

-- == Header : teinte colorée par colonne (resté local à l’onglet) ==
local function _EnsureHeaderBGs()
    if _headerBGs then return end
    _headerBGs = {}
    if not (lv and lv.header) then return end
    for i = 1, #cols do
        local t = lv.header:CreateTexture(nil, "BACKGROUND")
        t:SetTexture("Interface\\Buttons\\WHITE8x8")
        _headerBGs[i] = t
    end
end

local function _LayoutHeaderBGs()
    if not (lv and lv.header and cols) then return end
    _EnsureHeaderBGs()

    -- Positionnement identique au header standard
    local x = 0
    local pal = (DATA and DATA.palette and DATA.palette.headers) or {}
    for i, c in ipairs(cols) do
        local w = c.w or c.min or 80
        local t = _headerBGs[i]
        if t then
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT",     lv.header, "TOPLEFT",  x, 0)
            t:SetPoint("BOTTOMLEFT",  lv.header, "BOTTOMLEFT", x, 0)
            t:SetWidth(w)

            local palKey =
                (c.key == "ilvl" and "itemLevel")
                or (c.key == "crest" and "crests")
                or c.key
            local col = pal[palKey] or {0.12,0.12,0.12}
            t:SetColorTexture(col[1], col[2], col[3], 1)
        end
        x = x + w
    end
end

-- == BUILD (structure standard) ==
local function Build(container)
    panel = container
    if UI.ApplySafeContentBounds then
        UI.ApplySafeContentBounds(panel, { side = 10, bottom = 6 })
    end

    lv = UI.ListView(panel, cols, {
        buildRow = BuildRow,
        updateRow= UpdateRow,
    })
end

-- == LAYOUT (structure standard) ==
local function Layout()
    if lv then lv:Layout() end
    _LayoutHeaderBGs()
end

-- == REFRESH (structure standard) ==
local function Refresh()
    local rows = (DATA and DATA.rows) or {}
    if lv then
        lv:SetData(rows)
        lv:Layout()
        _LayoutHeaderBGs()
    end
end

-- Enregistrement dans la catégorie "Helpers"
UI.RegisterTab(Tr("tab_upgrade_tracks") or "Paliers d’amélioration (ilvl)", Build, Refresh, Layout, {
    category = Tr("cat_info"),
})