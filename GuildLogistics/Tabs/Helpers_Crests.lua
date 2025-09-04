-- Tabs/Helpers_Crests.lua
local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns.GLOG, ns.UI

local DATA = ns and ns.Data and ns.Data.Crests

-- État
local panel, lv
local _headerBGs

-- Colonnes (structure ListView standard)
local cols = UI.NormalizeColumns({
    { key="crest",   title=(DATA and DATA.headers and DATA.headers.crest)   , min=180, flex=1,  justify="CENTER"   },
    { key="chasms",  title=(DATA and DATA.headers and DATA.headers.chasms)  , vsep=true,  w=225, justify="CENTER" },
    { key="dungeons",title=(DATA and DATA.headers and DATA.headers.dungeons), vsep=true,  w=225, justify="CENTER" },
    { key="raids",   title=(DATA and DATA.headers and DATA.headers.raids)   , vsep=true,  w=225, justify="CENTER" },
    { key="outdoor", title=(DATA and DATA.headers and DATA.headers.outdoor) , vsep=true,  w=225, justify="CENTER" },
})

-- Helpers de rendu texte (localisation & couleur)
local function Y(txt)
    local c = UI.FONT_YELLOW or {1,0.82,0}
    return UI.Colorize(txt, c[1], c[2], c[3])
end

local function fmtLevel(n)  return string.format(Tr("label_level")   or "Niveau %d", n) end
local function fmtCrests(n) return string.format(Tr("label_crests_n") or "%d écus", n) end
local function fmtPerBoss(n, noFinal)
    local base = string.format(Tr("label_per_boss") or "%d écus par boss", n)
    if noFinal then return base .. " " .. (Tr("label_except_last_boss") or "(hors boss final)") end
    return base
end
local function fmtPerCache(n)
    return string.format(Tr("label_per_cache") or "%d écus par cache", n)
end

local TITLES = {
    classic             = function() return Tr("gouffre_classic")           or "Gouffre classique" end,
    abundant            = function() return Tr("gouffre_abundant")          or "Gouffre abondant" end,
    archaeologist_loot  = function() return Tr("archaeologist_loot")        or "Butin de l'archéologue" end,
    heroic              = function() return Tr("heroic")                     or "Héroïque" end,
    normal              = function() return Tr("normal")                     or "Normal" end,
    lfr                 = function() return Tr("lfr")                        or "Outils raids" end,
    mythic              = function() return Tr("mythic")                     or "Mythique" end,
    m0                  = function() return Tr("mythic0")                    or "Mythique 0" end,
    mplus               = function() return Tr("mplus_key")                  or "Clé mythique" end,
    weekly_event        = function() return Tr("weekly_event")               or "Événement hebdomadaire" end,
    treasures_quests    = function() return Tr("treasures_quests")           or "Trésors/Quêtes" end,
    na                  = function() return Tr("label_na")                   or "N/A" end,
}

local function joinBlocks(blocks)
    local parts = {}
    for _, b in ipairs(blocks or {}) do
        local head = b.kind and TITLES[b.kind] and TITLES[b.kind]() or ""
        local lines = {}

        if b.levels then
            for _, pair in ipairs(b.levels) do
                local lvl, amt = pair[1], pair[2]
                table.insert(lines, string.format("%s: %s", fmtLevel(lvl), fmtCrests(amt)))
            end
        end
        if b.perBoss then
            table.insert(lines, fmtPerBoss(b.perBoss, b.noFinal))
        end
        if b.perCache then
            table.insert(lines, fmtPerCache(b.perCache))
        end
        if b.range then
            local a, b2 = b.range[1], b.range[2]
            table.insert(lines, string.format("%d à %d écus", a or 0, b2 or 0))
        end
        if b.kind == "na" then
            table.insert(lines, TITLES.na())
        end

        local txt = ""
        if head ~= "" then
            txt = Y(head)
            if #lines > 0 then txt = txt .. "\n" .. table.concat(lines, "\n") end
        else
            txt = table.concat(lines, "\n")
        end
        table.insert(parts, txt)
    end
    return table.concat(parts, "\n\n")
end

-- Lignes
local function BuildRow(r)
    local f = {}

    -- Colonne Écus 
    f.crest = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.crest:SetJustifyH("LEFT")

    -- Colonnes texte multilignes
    local function mkFS()
        local fs = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP")
        fs:SetWordWrap(true); if fs.SetMaxLines then fs:SetMaxLines(10) end
        fs._noTruncation = true
        return fs
    end

    f.chasms   = mkFS()
    f.dungeons = mkFS()
    f.raids    = mkFS()
    f.outdoor  = mkFS()

    return f
end

-- Signature alignée sur UI_ListView : updateRow(i, rowFrame, fields, item)
local function UpdateRow(i, r, f, item)
    if not (f and item) then return end

    -- Badge d’écus : "Nom (min à max)"
    local min  = tonumber(item.crest and item.crest.min)
    local max  = tonumber(item.crest and item.crest.max)
    local name = item.crest and item.crest.name or ""
    local label = (item.crest)
        and string.format(Tr("crest_range"), tostring(name), min or 0, max or 0)
        or ""

        -- Colonnes
    f.crest:SetText(label)
    f.chasms:SetText(   joinBlocks(item.chasms)   )
    f.dungeons:SetText( joinBlocks(item.dungeons) )
    f.raids:SetText(    joinBlocks(item.raids)    )
    f.outdoor:SetText(  joinBlocks(item.outdoor)  )
end

-- Fond coloré sous chaque entête (comme Helpers_Upgrades)
local function _EnsureHeaderBGs()
    _headerBGs = _headerBGs or {}
    for i = 1, #cols do
        if not _headerBGs[i] and lv and lv.header then
            local t = lv.header:CreateTexture(nil, "BACKGROUND")
            t:SetDrawLayer("BACKGROUND", 0)
            t:SetColorTexture(0,0,0,1)
            t:Show()
            _headerBGs[i] = t
        end
    end
end

local function _LayoutHeaderBGs()
    if not (lv and lv.header) then return end
    _EnsureHeaderBGs()
    local pal = (DATA and DATA.palette and DATA.palette.headers) or {}
    local baseCol = pal.crest or {0.12, 0.12, 0.12}
    local x = 0
    for i, c in ipairs(cols) do
        local w = c.w or c.min or 80
        local t = _headerBGs[i]
        if t then
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT",    lv.header, "TOPLEFT",  x, 0)
            t:SetPoint("BOTTOMLEFT", lv.header, "BOTTOMLEFT", x, 0)
            t:SetWidth(w)

            local col = baseCol
            t:SetColorTexture(col[1], col[2], col[3], 1)
        end
        x = x + w
    end
end

-- == BUILD ==
local function Build(container)
    -- Création du conteneur
    panel, footer, footerH = UI.CreateMainContainer(container, {footer = false})

    -- Hauteur de ligne augmentée pour le multi-ligne
    lv = UI.ListView(panel, cols, {
        buildRow  = BuildRow,
        updateRow = UpdateRow,
        rowHeight = 88,
    })
end

-- == LAYOUT ==
local function Layout()
    if lv then lv:Layout() end
    _LayoutHeaderBGs()
end

local function Refresh()
    if not lv then return end
    lv:RefreshData((DATA and DATA.rows) or {})
    _LayoutHeaderBGs()
end

-- Enregistrement (catégorie Helpers)
UI.RegisterTab(Tr("tab_crests") or "Écus (sources)", Build, Refresh, Layout, {
    category = Tr("cat_info"),
})