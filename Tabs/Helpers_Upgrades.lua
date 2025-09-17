-- Tabs/Helpers_UpgradeTracks.lua
local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns.GLOG, ns.UI

local DATA = ns and ns.Data and ns.Data.UpgradeTracks

-- État local
local panel, lv

local BADGE_DEFAULT_COLOR = {0.5, 0.5, 0.5}

-- Colonnes (structure standard ListView)
local cols = UI.NormalizeColumns({
    { key="ilvl",      title = (DATA and DATA.headers and DATA.headers.itemLevel), min=130, flex=1 , justify="LEFT"  },
    { key="crest",     title = (DATA and DATA.headers and DATA.headers.crests)    ,     vsep=true,  min=140, flex=1},
    { key="aventurier",title = (DATA and DATA.headers and DATA.headers.aventurier),      vsep=true,  w=160, justify="CENTER"  },
    { key="veteran",   title = (DATA and DATA.headers and DATA.headers.veteran)   ,         vsep=true,  w=160, justify="CENTER"  },
    { key="champion",  title = (DATA and DATA.headers and DATA.headers.champion)  ,        vsep=true,  w=160, justify="CENTER"  },
    { key="heros",     title = (DATA and DATA.headers and DATA.headers.heros)     ,           vsep=true,  w=160, justify="CENTER"  },
    { key="mythe",     title = (DATA and DATA.headers and DATA.headers.mythe)     ,           vsep=true,  w=160, justify="CENTER"  },
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
        UI.SetBadgeCellFromPalette(cell, {
            palette = pal,
            key = keyLabel,
            text = labelText,
            defaultColor = BADGE_DEFAULT_COLOR,
        })
    end

    setBadge(f.aventurier, 'aventurier', it.aventurier)
    setBadge(f.veteran,    'veteran',    it.veteran)
    setBadge(f.champion,   'champion',   it.champion)
    setBadge(f.heros,      'heros',      it.heros)
    setBadge(f.mythe,      'mythe',      it.mythe)
end



-- == BUILD (structure standard) ==

local function Build(container)
    -- Création du conteneur
    panel, footer, footerH = UI.CreateMainContainer(container, {footer = false})

    lv = UI.ListView(panel, cols, {
        buildRow = BuildRow,
        updateRow= UpdateRow,
    })

    UI.ListView_SetHeaderBackgrounds(lv, {
        cols = cols,
        palette = (DATA and DATA.palette and DATA.palette.headers) or {},
        paletteMap = { ilvl = 'itemLevel', crest = 'crests' },
        defaultColor = {0.12, 0.12, 0.12},
    })
end

-- == LAYOUT (structure standard) ==
local function Layout()
    if lv then lv:Layout() end
end

local function Refresh()
    UI.RefreshListData(lv, DATA and DATA.rows)
end

-- Enregistrement dans la catégorie "Helpers"
UI.RegisterTab(Tr("tab_upgrade_tracks") or "Paliers d’amélioration (ilvl)", Build, Refresh, Layout, {
    category = Tr("cat_info"),
})