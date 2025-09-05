-- Tabs/Helpers_Delves.lua
local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns.GLOG, ns.UI
local L = ns and ns.L

local DATA = ns and ns.Data and ns.Data.Delves

-- État local
local panel, lv
local intro -- bloc titre + puces
local _headerBGs -- textures de fond colorées par colonne (header)
local _notesFS = {}

-- Colonnes (structure standard ListView)
local cols = UI.NormalizeColumns({
    { key="level", title = (DATA and DATA.headers and DATA.headers.level),  w=180, justify="LEFT"   },
    { key="chest", title = (DATA and DATA.headers and DATA.headers.chest),  vsep=true,  w=300, justify="CENTER" },
    { key="map",   title = (DATA and DATA.headers and DATA.headers.map),    vsep=true,  w=300, justify="CENTER" },
    { key="vault", title = (DATA and DATA.headers and DATA.headers.vault),  vsep=true,  w=300, justify="CENTER" },
})

-- == Rangée : création des cellules ==
local function BuildRow(r)
    local f = {}
    -- Texte simple (niveau)
    f.level  = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.level:SetJustifyH("LEFT")

    -- Cellules « badge » teintées (réutilisables)
    f.chest  = UI.CreateBadgeCell(r, { centeredGloss = true })
    f.map    = UI.CreateBadgeCell(r, { centeredGloss = true })
    f.vault  = UI.CreateBadgeCell(r, { centeredGloss = true })
    return f
end

-- == Rangée : mise à jour des cellules ==
local function UpdateRow(i, r, f, it)
    -- Colonne Niveau
    local lvlTxt = it.level or ""
    if lvlTxt ~= "" then
        local prefix = (DATA and DATA.fmt and DATA.fmt.level) or "Niveau %s"
        f.level:SetText(string.format(prefix, tostring(lvlTxt)))
    else
        f.level:SetText("")
    end

    -- Palette des couleurs (tiers)
    local pal = (DATA and DATA.palette and DATA.palette.cells) or {}

    local function setBadge(cell, entry)
        if not cell then return end
        if type(entry) == "table" and entry.text and entry.text ~= "" then
            local k = entry.tier or "adventurer"
            -- Alias FR/EN pour correspondre à la palette existante
            local alias = { aventurier="adventurer", heros="hero", mythe="myth",
                            adventurer="adventurer", hero="hero", myth="myth" }
            k = alias[k] or k
            -- Si la palette est en FR, on re-bascule
            if not pal[k] then
                local rev = { adventurer="aventurier", hero="heros", myth="mythe" }
                k = rev[k] or k
            end
            local c = pal[k] or {0.5,0.5,0.5,0.25}
            UI.SetBadgeCell(cell, { c[1], c[2], c[3] }, entry.text)
            cell:Show()
        else
            cell:Hide()
        end
    end

    setBadge(f.chest, it.chest)
    setBadge(f.map,   it.map)
    setBadge(f.vault, it.vault)
end

local function _LayoutIntro()
    if not (intro and DATA) then return end
    local padYTitle  = 2
    local gapTitle   = 6
    local gapRows    = 2
    local leftTextPad= 14

    -- Titre
    intro.title:SetText((DATA.intro and DATA.intro.title) or "")
    local y = padYTitle

    -- Lignes/puces
    local bullets = (DATA.intro and DATA.intro.bullets) or {}
    local palH    = DATA.palette and DATA.palette.headers or {}

    for i=1, #intro.rows do
        local row   = intro.rows[i]
        local spec  = bullets[i]
        row:ClearAllPoints()
        if i == 1 then
            row:SetPoint("TOPLEFT", intro.title, "BOTTOMLEFT", 0, -gapTitle)
            row:SetPoint("TOPRIGHT", intro.title, "BOTTOMRIGHT", 0, -gapTitle)
        else
            row:SetPoint("TOPLEFT", intro.rows[i-1], "BOTTOMLEFT", 0, -gapRows)
            row:SetPoint("TOPRIGHT", intro.rows[i-1], "BOTTOMRIGHT", 0, -gapRows)
        end

        local key = spec and spec.key or nil
        local fmt = spec and spec.fmt or ""
        local label = key and (DATA.headers and DATA.headers[key]) or ""
        local col = (key and palH[key]) or {0.7,0.7,0.7}
        local colored = (UI.Colorize and UI.Colorize(label, col[1], col[2], col[3])) or label

        local txt = fmt and fmt:find("%%s") and string.format(fmt, colored) or (tostring(fmt or "") .. " " .. tostring(colored or ""))
        row.text:SetText(txt)
        -- Ajuste la hauteur de la rangée sur la hauteur réelle du texte
        row:SetHeight((row.text:GetStringHeight() or 0) + 2)

        -- pastille à gauche (couleur = couleur d’entête de la colonne)
        if row.icon and row.icon.dot and row.icon.dot.SetColorTexture then
            row.icon.dot:SetColorTexture(col[1], col[2], col[3], 1)
        end
        if row.icon and row.icon.SetOn then row.icon:SetOn(true) end
        if row.icon and row.icon.AnchorTo then
            row.icon:AnchorTo(row.text, "RIGHT", "LEFT", -6, 0)
        end
    end

    -- Calcul hauteur dynamique
    intro:SetHeight(
        padYTitle
        + (intro.title:GetStringHeight() or 0)
        + gapTitle
        + (intro.rows[1].text:GetStringHeight() or 0)
        + gapRows
        + (intro.rows[2].text:GetStringHeight() or 0)
        + gapRows
        + (intro.rows[3].text:GetStringHeight() or 0)
        + 6
    )
end

-- == Header : teinte colorée par colonne ==
local function _EnsureHeaderBGs()
    if _headerBGs then return end
    _headerBGs = {}
    for i=1, #cols do
        local t = panel:CreateTexture(nil, "BACKGROUND")
        t:SetTexture("Interface\\Buttons\\WHITE8x8")
        _headerBGs[i] = t
    end
end

local function _LayoutHeaderBGs()
    if not panel or not lv or not lv.header then return end
    _EnsureHeaderBGs()
    local x = 0
    for i, c in ipairs(cols) do
        local w = c.w or c.min or 80
        local t = _headerBGs[i]
        if t then
            t:ClearAllPoints()
            t:SetPoint("TOPLEFT",     lv.header, "TOPLEFT",  x, 0)
            t:SetPoint("BOTTOMLEFT",  lv.header, "BOTTOMLEFT", x, 0)
            t:SetWidth(w)
            t:SetColorTexture(0.35, 0.23, 0.1, 1)
        end
        x = x + w
    end
end

-- == BUILD ==
local function Build(container)
    -- Création du conteneur
    panel, footer, footerH = UI.CreateMainContainer(container, {footer = false})

    local y = 0
    y = y + (UI.SectionHeader(panel, Tr("delves_intro_title"), { topPad = 0 }) or 26) + 8

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
        buildRow = BuildRow,
        updateRow= UpdateRow,
    })
end

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
    if lv then
        lv:RefreshData((DATA and DATA.rows) or {})
    end
end


-- Enregistrement dans la catégorie "Helpers"
UI.RegisterTab(Tr("tab_delves") or "Delves (rewards)", Build, Refresh, Layout, {
    category = Tr("cat_info"),
})
