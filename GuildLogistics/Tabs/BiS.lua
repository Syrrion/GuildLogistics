local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns.GLOG, ns.UI

-- ============================================== --
-- ===           CONSTANTES / COULEURS         === --
-- ============================================== --


-- ============================================== --
-- ===               ETAT LOCAL                === --
-- ============================================== --

local panel, listArea, lv, footer
local classDD, specDD
local selectedClassID, selectedClassTag, selectedSpecID
local specWatcher

-- Pré-déclaration pour références croisées depuis des closures
local _ResolvePlayerDefaults
local _UpdateDropdownTexts
local _Refresh

-- ============================================== --
-- ===        HELPERS : CLASSE / SPECIALIS     === --
-- ============================================== --

-- == Réapplique la classe/spé par défaut du joueur si elles deviennent disponibles == --
local function _EnsurePlayerSpecSelected()
    local pid, ptag, pspec = _ResolvePlayerDefaults()
    -- Explication de la sous-fonction: si aucune classe n'est sélectionnée ou si la sélection correspond à celle du joueur, on applique les valeurs par défaut
    if (not selectedClassID) or (ptag and selectedClassTag == ptag) then
        selectedClassID, selectedClassTag = pid or selectedClassID, ptag or selectedClassTag
        -- Explication de la sous-fonction: si une spécialisation valide est fournie, on l'applique
        if pspec and pspec ~= 0 then selectedSpecID = pspec end
        _UpdateDropdownTexts()
        _Refresh()
    end
end

-- == Calcule la classe/spé par défaut du joueur (robuste même si certaines APIs ne sont pas prêtes) == --
function _ResolvePlayerDefaults()
    -- 1) D’abord, on laisse l’UI résoudre via l’API du jeu (robuste & centralisé)
    local useID, useTag, useSpec = UI.ResolvePlayerClassSpec()

    -- 2) Fallback “domaine BiS” si la classe n’a pas été résolue (ex: API pas prête)
    if not useID then
        for tag in pairs(ns.BIS_TRINKETS or {}) do
            useTag = useTag or tag
            local cid = UI.GetClassIDForToken(tag)
            if cid then
                useID = cid
                break
            end
        end
    end

    -- 3) Fallback final : on choisit une classe valide connue de l’API si possible
    if not useID then
        for cid = 1, 30 do
            local info = UI.GetClassInfoByID(cid)
            if info and info.classFile then
                useID  = cid
                useTag = info.classFile:upper()
                break
            end
        end
    end

    -- 4) Si la spé est inconnue, prendre la 1re spé valide de la classe
    if (not useSpec) and useID and GetNumSpecializationsForClassID and GetSpecializationInfoForClassID then
        local n = GetNumSpecializationsForClassID(useID) or 0
        for i=1,n do
            local id = select(1, GetSpecializationInfoForClassID(useID, i))
            if id and id ~= 0 then useSpec = id; break end
        end
    end

    return useID, useTag, useSpec
end



-- ============================================== --
-- ===         HELPERS : UI / RENDU LIGNES     === --
-- ============================================== --

-- == Analyse une clé de rang (ex: "Aplus","Aminus","S") et renvoie base/mod/label == --
local function _ParseTierKey(key)
    if ns and ns.Util and ns.Util.ParseTierKey then
        return ns.Util.ParseTierKey(key)
    end
    -- Fallback minimal (devrait rarement être utilisé)
    key = type(key) == "string" and key or ""
    local base = key:match("^([A-Z])"); if not base then return nil end
    local lower, mod = key:lower()
    if lower:find("plus", 2, true) or lower:find("%+", 2, true) then mod = "plus"
    elseif lower:find("minus", 2, true) or lower:find("moins", 2, true) or lower:find("%-", 2, true) then mod = "minus" end
    local label = base .. ((mod == "plus" and "+") or (mod == "minus" and "-") or "")
    return base, mod, label
end


-- ============================================== --
-- ===          PREPARATION DES DONNEES        === --
-- ============================================== --

-- == Construit les données affichables à partir de ns.BIS_TRINKETS et de la classe/spé choisie == --
local function _BuildData()
    local out = {}

    local db      = ns.BIS_TRINKETS or {}
    local byClass = (selectedClassTag and db[selectedClassTag]) or nil
    local bySpec  = byClass and byClass[selectedSpecID] or nil
    if not bySpec then return out end

    -- Ordre des tiers centralisé
    local ORDER = (ns and ns.Util and ns.Util.TIER_ORDER) or { "S","A","B","C","D","E","F" }
    local baseOrder = {}
    for i, t in ipairs(ORDER) do baseOrder[t] = i end

    local tiers = {}
    for key, ids in pairs(bySpec) do
        if type(ids) == "table" then
            local base, mod, label = _ParseTierKey(key)
            if base then
                tiers[#tiers+1] = { base = base, mod = mod, label = label, ids = ids }
            end
        end
    end

    table.sort(tiers, function(a, b)
        local ai = baseOrder[a.base] or math.huge
        local bi = baseOrder[b.base] or math.huge
        if ai ~= bi then return ai < bi end
        if a.mod ~= b.mod then
            -- plus > (nil) > minus
            local order = { plus = 1, ["nil"] = 2, minus = 3 }
            return (order[a.mod or "nil"] or 99) < (order[b.mod or "nil"] or 99)
        end
        return tostring(a.label) < tostring(b.label)
    end)

    for _, t in ipairs(tiers) do
        for _, itemID in ipairs(t.ids) do
            local owned = (GetItemCount and (GetItemCount(itemID, true) or 0) or 0) > 0
            out[#out+1] = {
                tier      = t.base,
                mod       = t.mod,
                tierLabel = t.label,
                itemID    = itemID,
                owned     = owned,
            }
        end
    end

    return out
end


-- == Recharge la liste à partir des données recalculées == --
function _Refresh()
    if not lv then return end
    lv:SetData(_BuildData())
end

-- == Met à jour les libellés des dropdowns selon l'état sélectionné == --
function _UpdateDropdownTexts()
    if classDD then
        classDD:SetSelected(
            selectedClassTag,
            UI.ClassName(selectedClassID, selectedClassTag)
        )
    end
    if specDD then
        local specLabel = UI.SpecName(selectedClassID, selectedSpecID)
            or (Tr and Tr("lbl_spec"))
            or "Specialization"
        specDD:SetSelected(selectedSpecID or "", specLabel)
    end
end


-- ============================================== --
-- ===        BUILDERS DE MENUS (DROPDOWN)     === --
-- ============================================== --

-- == Construit le menu de sélection de classe à l'aide du builder générique UI == --
local function _ClassMenuBuilder(self, level)
    local builder = UI.MakeClassMenuBuilder({
        dataByClassTag     = ns.BIS_TRINKETS or {},
        includePlayerFirst = true,
        getCurrent         = function() return selectedClassTag end,
        onSelect           = function(tag, cid)
            selectedClassTag, selectedClassID = tag, cid
            local ok = false
            -- Explication de la sous-fonction: vérifie si la spé actuelle existe pour la nouvelle classe
            if selectedClassID and selectedSpecID and GetNumSpecializationsForClassID and GetSpecializationInfoForClassID then
                local n = GetNumSpecializationsForClassID(selectedClassID) or 0
                for i=1,n do
                    local id = select(1, GetSpecializationInfoForClassID(selectedClassID, i))
                    if id == selectedSpecID then ok = true; break end
                end
            end
            -- Explication de la sous-fonction: si la spé courante est invalide, prend la première spé valide de la classe
            if not ok then
                local n = (GetNumSpecializationsForClassID and GetNumSpecializationsForClassID(selectedClassID)) or 0
                for i=1,n do
                    local id = select(1, GetSpecializationInfoForClassID(selectedClassID, i))
                    if id then selectedSpecID = id; break end
                end
            end
            _UpdateDropdownTexts()
            _Refresh()
        end,
    })
    return builder(self, level)
end

-- == Construit le menu de sélection de spécialisation à l'aide du builder générique UI == --
local function _SpecMenuBuilder(self, level)
    local builder = UI.MakeSpecMenuBuilder({
        dataByClassTag   = ns.BIS_TRINKETS or {},
        classTagProvider = function() return selectedClassTag end,
        classIDProvider  = function() return selectedClassID end,
        getCurrentSpecID = function() return selectedSpecID end,
        onSelect         = function(specID)
            selectedSpecID = specID
            _UpdateDropdownTexts()
            _Refresh()
        end,
    })
    return builder(self, level)
end

-- ============================================== --
-- ===     LISTVIEW : COLONNES / RENDU LIGNE   === --
-- ============================================== --

-- == Définition normalisée des colonnes de la liste == --
local cols = UI.NormalizeColumns({
    { key="tier",  title=Tr("col_tier")  or "Tier",    w=40, justify="CENTER" },
    { key="item",  title=Tr("col_item")  or "Item",    min=320, flex=1 },
    { key="owned", title=Tr("col_owned") or "Owned",   w=110, justify="CENTER" },
})

-- == Construit les widgets d'une ligne (cellules tier/item/owned) == --
local function BuildRow(r)
    local f = {}
    f.tier  = UI.CreateBadgeCell(r, { width = 36, centeredGloss = true, textShadow = false })
    f.item  = UI.CreateItemCell(r, { size = 18, width = 360 })
    f.owned = UI.Label(r, { justify = "CENTER" })
    return f
end


-- == Met à jour une ligne avec les données (rang, item, possession) == --
function UpdateRow(i, r, f, d)
    UI.SetTierBadge(f.tier, d.tier, d.mod, d.tierLabel, UI.Colors and UI.Colors.BIS_TIER_COLORS)
    UI.SetItemCell(f.item, { itemID = d.itemID })
    f.owned:SetText(UI.YesNoText(d.owned))
end

-- ============================================== --
-- ===          DIVERS HELPERS D'INTEGRA       === --
-- ============================================== --

-- == Force la popup des dropdowns système au-dessus d'un hôte donné (délègue à UI) == --
local function _AttachDropdownZFix(dd, host)
    if UI.AttachDropdownZFix then
        UI.AttachDropdownZFix(dd, host)
    end
end

-- ============================================== --
-- ===          CONSTRUCTION DE L'ONGLET       === --
-- ============================================== --

-- == Construit l'interface de l'onglet BiS (intro, filtres, liste, footer) == --
local function Build(p)
    panel = p
    local content = UI.PaddedBox(panel)

    local INSET   = 12
    local PAD     = UI.OUTER_PAD or 10
    local PAD_LEFT, PAD_RIGHT = 10, 10
    local PAD_TOP, PAD_BOTTOM = 6, 0

    local introArea = CreateFrame("Frame", nil, content)
    introArea:SetPoint("TOPLEFT",  content, "TOPLEFT",  INSET, -INSET)
    introArea:SetPoint("TOPRIGHT", content, "TOPRIGHT", -INSET, -INSET)
    introArea:SetFrameLevel((content:GetFrameLevel() or 0) + 1)

    local introFS = introArea:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    introFS:SetPoint("TOPLEFT",  introArea, "TOPLEFT",  PAD_LEFT, -PAD_TOP)
    introFS:SetPoint("TOPRIGHT", introArea, "TOPRIGHT", -PAD_RIGHT, -PAD_TOP)
    introFS:SetJustifyH("LEFT"); introFS:SetJustifyV("TOP")
    if introFS.SetWordWrap then introFS:SetWordWrap(true) end
    if introFS.SetNonSpaceWrap then introFS:SetNonSpaceWrap(true) end
    introFS:SetText(Tr("bis_intro"))
    do
        local fontPath, fontSize, fontFlags = introFS:GetFont()
        if fontPath and fontSize then
            introFS:SetFont(fontPath, (fontSize + 2), fontFlags)
        end
        introFS:SetTextColor(1, 1, 1)
        if introFS.SetShadowOffset then introFS:SetShadowOffset(1, -1) end
    end
    introArea:SetHeight(math.max(24, (introFS:GetStringHeight() or 16) + PAD_TOP + PAD_BOTTOM))

    local headerArea = CreateFrame("Frame", nil, content)
    headerArea:SetPoint("TOPLEFT",  introArea, "BOTTOMLEFT",  0, -6)
    headerArea:SetPoint("TOPRIGHT", introArea, "BOTTOMRIGHT", 0, -6)
    local headerH = UI.SectionHeader(headerArea, Tr("lbl_bis_filters") or "Filters", { topPad = 0 }) or (UI.SECTION_HEADER_H or 26)
    headerArea:SetHeight(headerH)

    local filtersArea = CreateFrame("Frame", nil, content)
    filtersArea:SetPoint("TOPLEFT",  headerArea, "BOTTOMLEFT",  0, -8)
    filtersArea:SetPoint("TOPRIGHT", headerArea, "BOTTOMRIGHT", 0, -8)
    filtersArea:SetHeight(34)
    filtersArea:SetFrameLevel((content:GetFrameLevel() or 0) + 1)

    local lblClass = UI.Label(filtersArea, { template="GameFontNormal" })
    lblClass:SetText(Tr("lbl_class"))
    lblClass:SetPoint("LEFT", filtersArea, "LEFT", 0, 0)
    lblClass:SetPoint("TOP",  filtersArea, "TOP",  0, -2)

    classDD = UI.Dropdown(filtersArea, { width = 200, placeholder = Tr("lbl_class")})
    classDD:SetPoint("LEFT", lblClass, "RIGHT", 8, -2)
    classDD:SetBuilder(_ClassMenuBuilder)
    _AttachDropdownZFix(classDD, panel)

    local lblSpec = UI.Label(filtersArea, { template="GameFontNormal" })
    lblSpec:SetText(Tr("lbl_spec"))
    lblSpec:SetPoint("LEFT", classDD, "RIGHT", 24, 2)

    specDD = UI.Dropdown(filtersArea, { width = 220, placeholder = Tr("lbl_spec") })
    specDD:SetPoint("LEFT", lblSpec, "RIGHT", 8, -2)
    specDD:SetBuilder(_SpecMenuBuilder)
    _AttachDropdownZFix(specDD, panel)

    footer = UI.CreateFooter(content, 22)
    footer:ClearAllPoints()
    footer:SetPoint("BOTTOMLEFT",  content, "BOTTOMLEFT",  INSET, INSET)
    footer:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -INSET, INSET)

    local sourceFS = footer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sourceFS:SetPoint("LEFT", footer, "LEFT", PAD, 0)
    sourceFS:SetJustifyH("LEFT"); sourceFS:SetJustifyV("MIDDLE")
    sourceFS:SetText(Tr("footer_source_wowhead"))

    listArea = CreateFrame("Frame", nil, content)
    listArea:SetPoint("TOPLEFT",     filtersArea, "BOTTOMLEFT",  0, -8)
    listArea:SetPoint("TOPRIGHT",    filtersArea, "BOTTOMRIGHT", 0, -8)
    listArea:SetPoint("BOTTOMLEFT",  footer,      "TOPLEFT",     0,  8)
    listArea:SetPoint("BOTTOMRIGHT", footer,      "TOPRIGHT",    0,  8)
    listArea:SetFrameLevel((content:GetFrameLevel() or 0) + 1)

    lv = UI.ListView(listArea, cols, {
        safeRight    = true,
        buildRow     = BuildRow,
        updateRow    = UpdateRow,
        bottomAnchor = footer,
    })

    selectedClassID, selectedClassTag, selectedSpecID = _ResolvePlayerDefaults()
    _UpdateDropdownTexts()
    _Refresh()

    if not specWatcher then
        specWatcher = CreateFrame("Frame", nil, panel)
        specWatcher:RegisterEvent("PLAYER_ENTERING_WORLD")
        specWatcher:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
        specWatcher:SetScript("OnEvent", function() _EnsurePlayerSpecSelected() end)
    end
end

-- == Déclenche un rafraîchissement manuel de la liste == --
local function Refresh()
    _Refresh()
end

-- == Point d'extension future : l'agencement est géré par ancres == --
local function Layout()
    -- (volontairement vide)
end

UI.RegisterTab(Tr("tab_bis") or "BiS", Build, Refresh, Layout)