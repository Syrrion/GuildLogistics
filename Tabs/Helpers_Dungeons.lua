-- Tabs/Helpers_Dungeons.lua
local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns.GLOG, ns.UI

-- Dataset
local DATA = ns and ns.Data and ns.Data.Dungeons
local UPG  = ns and ns.Data and ns.Data.UpgradeTracks  -- palette des paliers (tinte des cellules Loot/Vault)

-- État local
local panel, lv
local _notesFS = {}

-- Colonnes
local cols = UI.NormalizeColumns({
    { key="label",   title = ""   , w=180, flex=1, justify="LEFT" },
    { key="loot",    title = (DATA and DATA.headers and DATA.headers.dungeonLoot), vsep=true,  w=300, justify="CENTER" },
    { key="vault",   title = (DATA and DATA.headers and DATA.headers.vault)      , vsep=true,  w=300, justify="CENTER" },
    { key="crests",  title = (DATA and DATA.headers and DATA.headers.crests)     , vsep=true,  w=300, justify="CENTER" },
})



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
    if not (r and f) then return end

    f.label:SetText(item and item.label or "")

    local palCells = (UPG and UPG.palette and UPG.palette.cells) or {}
    local crestPal = (DATA and DATA.palette and DATA.palette.crests) or {}

    local lootKey  = _DetectTrackKey(item and item.loot)
    local vaultKey = _DetectTrackKey(item and item.vault)

    local crestCount, crestKey
    if item and type(item.crest) == "table" then
        crestCount = tonumber(item.crest.count or 0) or 0
        crestKey   = tostring(item.crest.key or "")
    else
        local s = tostring(item and (item.crests or item.crest) or "")
        crestCount = tonumber(string.match(s, "(%d+)") or 0) or 0
        crestKey   = _DetectCrestKey(s)
    end

    if crestKey then
        crestKey = string.lower(tostring(crestKey))
    end

    local crestLabelByKey = {
        valor  = (ns.L and ns.L["crest_valor"])  or "Valor",
        worn   = (ns.L and ns.L["crest_worn"])   or "Worn",
        carved = (ns.L and ns.L["crest_carved"]) or "Carved",
        runic  = (ns.L and ns.L["crest_runic"])  or "Runic",
        golden = (ns.L and ns.L["crest_golden"]) or "Golden",
    }

    local crestText
    if crestKey and crestCount and crestCount > 0 then
        crestText = string.format("%d x %s", crestCount, crestLabelByKey[crestKey] or crestKey)
    end

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

            if lootKey then
                UI.SetBadgeCellFromPalette(f.lootBadge, {
                    palette = palCells,
                    key = lootKey,
                    text = item and item.loot,
                    requireColor = true,
                    hideWhenEmpty = true,
                })
            else
                if f.lootBadge.Hide then f.lootBadge:Hide() end
                if f.lootBadge.txt then f.lootBadge.txt:SetText("") end
            end

        elseif c.key == "vault" then
            f.vaultBadge:ClearAllPoints()
            f.vaultBadge:SetPoint("CENTER", r, "LEFT", x + w/2, 0)
            f.vaultBadge:SetWidth(w - 20)

            if vaultKey then
                UI.SetBadgeCellFromPalette(f.vaultBadge, {
                    palette = palCells,
                    key = vaultKey,
                    text = item and item.vault,
                    requireColor = true,
                    hideWhenEmpty = true,
                })
            else
                if f.vaultBadge.Hide then f.vaultBadge:Hide() end
                if f.vaultBadge.txt then f.vaultBadge.txt:SetText("") end
            end

        elseif c.key == "crests" then
            f.crestBadge:ClearAllPoints()
            f.crestBadge:SetPoint("CENTER", r, "LEFT", x + w/2, 0)
            f.crestBadge:SetWidth(w - 20)

            if crestKey and crestText then
                UI.SetBadgeCellFromPalette(f.crestBadge, {
                    palette = crestPal,
                    key = crestKey,
                    text = crestText,
                    requireColor = true,
                    hideWhenEmpty = true,
                })
            else
                if f.crestBadge.Hide then f.crestBadge:Hide() end
                if f.crestBadge.txt then f.crestBadge.txt:SetText("") end
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

    UI.ListView_SetHeaderBackgrounds(lv, {
        cols = cols,
        colors = {
            label = ((DATA and DATA.palette and DATA.palette.headers and DATA.palette.headers.activity) or {0.12, 0.12, 0.12}),
            loot  = ((DATA and DATA.palette and DATA.palette.headers and DATA.palette.headers.activity) or {0.12, 0.12, 0.12}),
            vault = ((DATA and DATA.palette and DATA.palette.headers and DATA.palette.headers.activity) or {0.12, 0.12, 0.12}),
            crests= ((DATA and DATA.palette and DATA.palette.headers and DATA.palette.headers.activity) or {0.12, 0.12, 0.12}),
        },
        defaultColor = ((DATA and DATA.palette and DATA.palette.headers and DATA.palette.headers.activity) or {0.12, 0.12, 0.12}),
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

UI.RegisterTab(Tr("tab_dungeons_loot") or "Donjons (paliers)", Build, Refresh, Layout, {
    category = Tr("cat_info"),
})
