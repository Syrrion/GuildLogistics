-- Tabs/Helpers_Dungeons.lua
local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns.GLOG, ns.UI

-- Dataset
local DATA = ns and ns.Data and ns.Data.Dungeons
local UPG  = ns and ns.Data and ns.Data.UpgradeTracks  -- palette des paliers (tinte des cellules Loot/Vault)

-- État local
local panel, lv
local _headerBGs
local _notesFS = {}

-- Colonnes
local cols = UI.NormalizeColumns({
    { key="label",   title = ""   , w=180, flex=1, justify="LEFT" },
    { key="loot",    title = (DATA and DATA.headers and DATA.headers.dungeonLoot), w=300, justify="CENTER" },
    { key="vault",   title = (DATA and DATA.headers and DATA.headers.vault)      , w=300, justify="CENTER" },
    { key="crests",  title = (DATA and DATA.headers and DATA.headers.crests)     , w=300, justify="CENTER" },
})

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

local function _LayoutHeaderBGs()
    if not lv or not lv.header or not _headerBGs then return end
    local x = 0
    -- Utilise uniquement la couleur de la 1ère colonne (activity) pour toutes les colonnes
    local base = (DATA and DATA.palette and DATA.palette.headers and DATA.palette.headers.activity) or {0.12, 0.12, 0.12}
    for i, c in ipairs(cols) do
        local w = c.w or c.min or 80
        local t = _headerBGs[i]
        if t then
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT",    lv.header, "TOPLEFT",  x, 0)
            t:SetPoint("BOTTOMLEFT", lv.header, "BOTTOMLEFT", x, 0)
            t:SetWidth(w)
            t:SetColorTexture(base[1], base[2], base[3], 1) -- même couleur partout
        end
        x = x + w
    end
end

-- ==== Détection du palier ====
local function _DetectTrackKey(text)
    if not text or text == "" then return nil end
    local L = ns and ns.L or {}
    local map = {
        aventurier = L["upgrade_track_adventurer"] or "Adventurer",
        veteran    = L["upgrade_track_veteran"]    or "Veteran",
        champion   = L["upgrade_track_champion"]   or "Champion",
        heros      = L["upgrade_track_hero"]       or "Hero",
        mythe      = L["upgrade_track_myth"]       or "Myth",
    }
    local lower = string.lower(text)
    for k, v in pairs(map) do
        if v and v ~= "" then
            local needle = string.lower(v)
            if string.find(lower, needle, 1, true) then
                return k
            end
        end
    end
    return nil
end

-- ==== Détection du type d’écus ====
local function _DetectCrestKey(label)
    if not label or label == "" then return nil end
    local L = ns and ns.L or {}
    local lower = string.lower(label)
    local map = {
        valor  = string.lower(L["crest_valor"]  or "Valor"),
        worn   = string.lower(L["crest_worn"]   or "Worn"),
        carved = string.lower(L["crest_carved"] or "Carved"),
        runic  = string.lower(L["crest_runic"]  or "Runic"),
        golden = string.lower(L["crest_golden"] or "Golden"),
    }
    for key, needle in pairs(map) do
        if string.find(lower, needle, 1, true) then
            return key
        end
    end
    return nil
end

-- ==== buildRow / updateRow ====
local function buildRow(r)
    local f = {}

    f.label  = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")

    -- Colonnes loot / vault = badge uniquement
    f.lootBadge  = UI.CreateBadgeCell(r, { centeredGloss = true, textShadow = false })
    f.vaultBadge = UI.CreateBadgeCell(r, { centeredGloss = true, textShadow = false })

    -- Colonne écus : badge intégrant nombre + type
    f.crestBadge = UI.CreateBadgeCell(r, { centeredGloss = true, textShadow = false })
    return f
end

local function updateRow(i, r, f, item)
    -- Activité
    f.label:SetText(item.label or "")

    -- Couleurs loot/vault
    local palCells = (UPG and UPG.palette and UPG.palette.cells) or {}
    local lootKey  = _DetectTrackKey(item.loot)
    local vaultKey = _DetectTrackKey(item.vault)
    local colLoot  = lootKey  and palCells[lootKey]
    local colVault = vaultKey and palCells[vaultKey]

    -- Écus
    local crestCount, crestKey
    if type(item.crest) == "table" then
        crestCount = tonumber(item.crest.count or 0) or 0
        crestKey   = tostring(item.crest.key or "")
    else
        local s = tostring(item.crests or item.crest or "")
        crestCount = tonumber(string.match(s, "(%d+)") or 0) or 0
        crestKey   = _DetectCrestKey(s)
    end
    local crestPal = (DATA and DATA.palette and DATA.palette.crests) or {}
    local crestRGB = crestKey and crestPal[crestKey]
    local crestLabelByKey = {
        valor  = (ns.L and ns.L["crest_valor"])  or "Valor",
        worn   = (ns.L and ns.L["crest_worn"])   or "Worn",
        carved = (ns.L and ns.L["crest_carved"]) or "Carved",
        runic  = (ns.L and ns.L["crest_runic"])  or "Runic",
        golden = (ns.L and ns.L["crest_golden"]) or "Golden",
    }

    local resolved = UI.ResolveColumns(r:GetWidth() or (UI.SumWidths(cols)), cols)
    local x = 0
    for _, c in ipairs(resolved) do
        local w = c.w or c.min or 80

        if c.key == "label" then
            f.label:ClearAllPoints()
            f.label:SetJustifyH(c.justify or "LEFT")
            f.label:SetPoint("LEFT", r, "LEFT", x + 8, 0)
            f.label:SetWidth(w - 16)

        elseif c.key == "loot" then
            f.lootBadge:ClearAllPoints()
            f.lootBadge:SetPoint("CENTER", r, "LEFT", x + w/2, 0)
            f.lootBadge:SetWidth(w - 20)

            if lootKey and colLoot then
                UI.SetBadgeCell(f.lootBadge, colLoot, item.loot or "")
                f.lootBadge:Show()
            else
                f.lootBadge:Hide()
            end

        elseif c.key == "vault" then
            f.vaultBadge:ClearAllPoints()
            f.vaultBadge:SetPoint("CENTER", r, "LEFT", x + w/2, 0)
            f.vaultBadge:SetWidth(w - 20)

            if vaultKey and colVault then
                UI.SetBadgeCell(f.vaultBadge, colVault, item.vault or "")
                f.vaultBadge:Show()
            else
                f.vaultBadge:Hide()
            end

        elseif c.key == "crests" then
            f.crestBadge:ClearAllPoints()
            f.crestBadge:SetPoint("CENTER", r, "LEFT", x + w/2, 0)
            f.crestBadge:SetWidth(w - 20)

            if crestKey and crestRGB and crestCount and crestCount > 0 then
                local label = string.format("%d x %s", crestCount, crestLabelByKey[crestKey] or crestKey)
                UI.SetBadgeCell(f.crestBadge, crestRGB, label)
                f.crestBadge:Show()
            else
                f.crestBadge:Hide()
            end
        end

        x = x + w
    end
end

-- == BUILD ==
local function Build(container)
    -- Création du conteneur
    panel, footer, footerH = UI.CreateMainContainer(container, {footer = false})

    local y = 0
    y = y + (UI.SectionHeader(panel, Tr("tab_dungeons_loot"), { topPad = 0 }) or 26) + 8

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
        buildRow  = buildRow,
        updateRow = updateRow,
    })

    _CreateHeaderBGs()
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

-- == REFRESH ==
local function Refresh()
    if not lv then return end
    local rows = (DATA and DATA.rows) or {}
    lv:SetData(rows)
    Layout()
end

UI.RegisterTab(Tr("tab_dungeons_loot") or "Donjons (paliers)", Build, Refresh, Layout, {
    category = Tr("cat_info"),
})
