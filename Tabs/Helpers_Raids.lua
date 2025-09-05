-- Tabs/Helpers_Raids.lua
local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns.GLOG, ns.UI

-- Source des données : centralisée dans Data/Upgrades.lua (ns.Data.UpgradeTracks.raids)
local DATA = ns and ns.Data and ns.Data.UpgradeTracks and ns.Data.UpgradeTracks.raids

-- Etat local
local panel, lv
local _headerBGs
local _notesFS = {}

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

-- ==== Header background helpers ====
local function _CreateHeaderBGs()
    if not lv or not lv.header then return end
    _headerBGs = _headerBGs or {}
    for i = 1, #cols do
        if not _headerBGs[i] then
            local t = lv.header:CreateTexture(nil, "BACKGROUND", nil, -8)
            t:SetColorTexture(0.12, 0.12, 0.12, 1)
            _headerBGs[i] = t
        end
    end
end

-- Rangée : MAJ
local function UpdateRow(i, r, f, it)
    -- Texte de la colonne 1
    f.label:SetText(tostring(it.label or ""))

    -- Palette (données)
    local pal = (DATA and DATA.palette and DATA.palette.cells) or {}
    local function setBadge(cell, palKey, text)
        if not cell then return end
        if text and text ~= "" then
            local c = pal[palKey] or {0.5,0.5,0.5,0.25}
            UI.SetBadgeCell(cell, { c[1], c[2], c[3] }, text)
            cell:Show()
        else
            cell:Hide()
        end
    end

    setBadge(f.lfr,    "lfr",    it.lfr)
    setBadge(f.normal, "normal", it.normal)
    setBadge(f.heroic, "heroic", it.heroic)
    setBadge(f.mythic, "mythic", it.mythic)
end

-- Header coloré par colonne (comme Helpers_Upgrades)
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

    local x = 0
    local pal = (DATA and DATA.palette and DATA.palette.headers) or {}
    -- même couleur pour tous les headers = couleur de la 1ʳᵉ colonne ("difficulty")
    local col = pal.difficulty or {0.35, 0.23, 0.10} -- fallback discret si palette absente

    for i, c in ipairs(cols) do
        local w = c.w or c.min or 80
        local t = _headerBGs[i]
        if t then
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT",     lv.header, "TOPLEFT",  x, 0)
            t:SetPoint("BOTTOMLEFT",  lv.header, "BOTTOMLEFT", x, 0)
            t:SetWidth(w)
            t:SetColorTexture(col[1], col[2], col[3], 1)
        end
        x = x + w
    end
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

    _LayoutHeaderBGs()
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

    _LayoutHeaderBGs()
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
