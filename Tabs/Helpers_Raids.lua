-- Tabs/Helpers_Raids.lua
local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns.GLOG, ns.UI

-- Source des données : centralisée dans Data/Upgrades.lua (ns.Data.UpgradeTracks.raids)
local DATA = ns and ns.Data and ns.Data.UpgradeTracks and ns.Data.UpgradeTracks.raids

-- Etat local
local panel, lv
local _notesFS = {}

local BADGE_DEFAULT_COLOR = {0.5, 0.5, 0.5}

-- Colonnes (même moteur ListView/NormalizeColumns)
local cols = UI.NormalizeColumns({
    { key="label",  title = (DATA and DATA.headers and DATA.headers.difficulty) , min=180, flex=2, justify="LEFT"   },
    { key="lfr",    title = (DATA and DATA.headers and DATA.headers.lfr)        ,    vsep=true,  w=225, justify="CENTER" },
    { key="normal", title = (DATA and DATA.headers and DATA.headers.normal)     ,    vsep=true,  w=225, justify="CENTER" },
    { key="heroic", title = (DATA and DATA.headers and DATA.headers.heroic)     ,   vsep=true,   w=225, justify="CENTER" },
    { key="mythic", title = (DATA and DATA.headers and DATA.headers.mythic)     ,   vsep=true,   w=225, justify="CENTER" },
})

-- Rangée : champs UI
local function BuildRow(r)
    local f = {}
    f.label  = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.label:SetJustifyH("LEFT")

    -- 4 cellules “badge” teintées (on réutilise CreateBadgeCell)
    f.lfr    = UI.CreateBadgeCell(r, { centeredGloss = true })
    f.normal = UI.CreateBadgeCell(r, { centeredGloss = true })
    f.heroic = UI.CreateBadgeCell(r, { centeredGloss = true })
    f.mythic = UI.CreateBadgeCell(r, { centeredGloss = true })
    return f
end



-- Rangée : mise à jour des cellules
local function UpdateRow(i, r, f, it)
    if not (f and r) then return end
    f.label:SetText(tostring(it and it.label or ""))

    local pal = (DATA and DATA.palette and DATA.palette.cells) or {}
    local function setBadge(cell, key, value)
        if not cell then return end
        UI.SetBadgeCellFromPalette(cell, {
            palette = pal,
            key = key,
            text = value,
            defaultColor = BADGE_DEFAULT_COLOR,
        })
    end

    setBadge(f.lfr,    'lfr',    it and it.lfr)
    setBadge(f.normal, 'normal', it and it.normal)
    setBadge(f.heroic, 'heroic', it and it.heroic)
    setBadge(f.mythic, 'mythic', it and it.mythic)
end


-- == BUILD ==

local function Build(container)
    -- Création du conteneur
    panel, footer, footerH = UI.CreateMainContainer(container, {footer = false})

    local y = 0
    y = y + (UI.SectionHeader(panel, Tr("tab_raid_loot"), { topPad = 0 }) or 26) + 8

    wipe(_notesFS)
    local texts = (DATA and DATA.text) or {}
    for i, line in ipairs(texts) do
        local fs = UI.Label(panel, { justify = "LEFT" })
        fs:SetText(line or "")
        fs:SetSpacing(1)
        _notesFS[#_notesFS+1] = fs
    end

    lv = UI.ListView(panel, cols, {
        topOffset = y,
        buildRow  = BuildRow,
        updateRow = UpdateRow,
    })

    UI.ListView_SetHeaderBackgrounds(lv, {
        cols = cols,
        palette = (DATA and DATA.palette and DATA.palette.headers) or {},
        paletteMap = { label = 'difficulty' },
        defaultColor = ((DATA and DATA.palette and DATA.palette.headers and DATA.palette.headers.difficulty) or {0.35, 0.23, 0.10}),
    })
end

-- == LAYOUT ==
local function Layout()
    if not panel then return end

    local padL, padR = 10, 10
    local y = (UI.SECTION_HEADER_H or 22) + 8
    local width = math.max(100, (panel:GetWidth() or UI.DEFAULT_W or 800) - padL - padR)
    for _, fs in ipairs(_notesFS) do
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT",  panel, "TOPLEFT",  padL, -y)
        fs:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -padR, -y)
        fs:SetWidth(width)
        local h = math.max(14, fs:GetStringHeight() or 14)
        y = y + h + 6
    end

    if lv then
        lv.opts.topOffset = y
        lv:Layout()
    end
end

local function Refresh()
    if lv then
        lv:RefreshData((DATA and DATA.rows) or {})
    end
end

-- Enregistrement dans la catégorie Helpers
UI.RegisterTab(Tr("tab_raid_ilvls") or "Raids (iLvl par difficulté)", Build, Refresh, Layout, {
    category = Tr("cat_info"),
})
