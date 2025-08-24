local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns.GLOG, ns.UI

-- ============================================== --
-- ===           CONSTANTES / COULEURS         === --
-- ============================================== --

-- == Ordre des rangs de BiS utilisé pour le tri == --
local TIER_ORDER = { "S","A","B","C","D","E","F" }

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

-- == Récupère les informations d'une classe par son ID via l'API sécurisé par pcall == --
local function _GetClassInfoByID(cid)
    -- Explication de la sous-fonction: ignore les entrées non numériques
    if not cid or type(cid) ~= "number" then return nil end
    -- Explication de la sous-fonction: utilise l'API de WoW si disponible
    if C_CreatureInfo and C_CreatureInfo.GetClassInfo then
        local ok, info = pcall(C_CreatureInfo.GetClassInfo, cid)
        -- Explication de la sous-fonction: ne renvoie des données que si l'appel s'est bien passé
        if ok then return info end
    end
    return nil
end

-- == Retourne l'ID de classe (numérique) à partir d'un token de classe (ex: "WARRIOR") == --
local function _GetClassIDForToken(token)
    token = token and token:upper()
    -- Explication de la sous-fonction: abandonne si aucun token n'est fourni
    if not token then return nil end
    for cid = 1, 30 do
        local info = _GetClassInfoByID(cid)
        -- Explication de la sous-fonction: compare le classFile uppercased au token ciblé
        if info and info.classFile and info.classFile:upper() == token then
            return cid
        end
    end
    return nil
end

-- == Renvoie un nom lisible pour une spécialisation donnée (évite "0") == --
local function _SpecName(classID, specID)
    -- Explication de la sous-fonction: si specID absent/0, retourne un libellé générique
    if not specID or specID == 0 then
        return Tr("lbl_spec") or "Specialization"
    end
    -- Explication de la sous-fonction: tente d'abord par classe (liste des spécialisations disponibles pour cette classe)
    if classID and GetNumSpecializationsForClassID and GetSpecializationInfoForClassID then
        local n = GetNumSpecializationsForClassID(classID) or 0
        for i = 1, n do
            local id, name = GetSpecializationInfoForClassID(classID, i)
            -- Explication de la sous-fonction: si l'ID correspond, renvoie le nom
            if id == specID and name then
                return name
            end
        end
    end
    -- Explication de la sous-fonction: sinon, tente d'utiliser la spécialisation active du joueur
    if GetSpecialization and GetSpecializationInfo then
        local idx = GetSpecialization()
        if idx then
            local id, name = GetSpecializationInfo(idx)
            -- Explication de la sous-fonction: vérifie la correspondance avec specID ciblé
            if id == specID and name then
                return name
            end
        end
    end
    return Tr("lbl_spec") or "Specialization"
end

-- == Renvoie un nom lisible pour une classe depuis son ID, sinon le tag fourni == --
local function _ClassName(classID, classTag)
    -- Explication de la sous-fonction: privilégie les infos issues de l'API si l'ID est fourni
    if classID then
        local info = _GetClassInfoByID(classID)
        if info then return (info.className or info.name or info.classFile) end
    end
    return classTag or ""
end

-- == Renvoie le texte coloré Oui/Non selon la possession de l'objet == --
local function _OwnedText(owned)
    local yes = (Tr and Tr("opt_yes")) or "Yes"
    local no  = (Tr and Tr("opt_no"))  or "No"
    -- Explication de la sous-fonction: choisit la couleur verte pour oui et rouge pour non
    if owned then return "|cff33ff33"..yes.."|r" else return "|cffff4040"..no.."|r" end
end

-- == Calcule la classe/spé par défaut du joueur (robuste même si certaines APIs ne sont pas prêtes) == --
function _ResolvePlayerDefaults()
    local useTag, useID, useSpec

    -- Explication de la sous-fonction: récupère le token et l'ID de classe du joueur si possible
    if UnitClass then
        local _, token, classID = UnitClass("player")
        useTag = token and token:upper() or nil
        useID  = (type(classID) == "number") and classID or _GetClassIDForToken(useTag)
    end

    -- Explication de la sous-fonction: récupère la spécialisation active du joueur si disponible
    if GetSpecialization and GetSpecializationInfo then
        local specIndex = GetSpecialization()
        useSpec = specIndex and select(1, GetSpecializationInfo(specIndex)) or nil
    end
    -- Explication de la sous-fonction: évite un specID = 0 (non valide)
    if useSpec == 0 then useSpec = nil end

    -- Explication de la sous-fonction: si la classe n'est pas déterminée, tente via les clés du tableau BIS_TRINKETS
    if not useID then
        for tag in pairs(ns.BIS_TRINKETS or {}) do
            useTag = useTag or tag
            useID  = _GetClassIDForToken(tag) or useID
            -- Explication de la sous-fonction: s'arrête dès qu'un ID valide est trouvé
            if useID then break end
        end
    end
    -- Explication de la sous-fonction: fallback final via itération des classes connues de l'API
    if not useID then
        for cid = 1, 30 do
            local info = _GetClassInfoByID(cid)
            if info then
                useID  = cid
                useTag = info.classFile and info.classFile:upper() or useTag
                break
            end
        end
    end

    -- Explication de la sous-fonction: si la spécialisation est encore inconnue, choisit la première valide de la classe
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
    if type(key) ~= "string" then return nil end
    local base = key:match("^([A-Z])")
    -- Explication de la sous-fonction: invalide si aucun préfixe de rang trouvé
    if not base then return nil end
    local lower = key:lower()
    local mod
    -- Explication de la sous-fonction: détecte la variante "plus"
    if lower:find("plus", 2, true) then
        mod = "plus"
    -- Explication de la sous-fonction: détecte la variante "minus"/"moins"
    elseif lower:find("minus", 2, true) or lower:find("moins", 2, true) then
        mod = "minus"
    end
    local label = base
    -- Explication de la sous-fonction: ajoute le suffixe visuel +/-
    if mod == "plus" then
        label = base .. "+"
    elseif mod == "minus" then
        label = base .. "-"
    end
    return base, mod, label
end

-- ============================================== --
-- ===          PREPARATION DES DONNEES        === --
-- ============================================== --

-- == Construit les données affichables à partir de ns.BIS_TRINKETS et de la classe/spé choisie == --
local function _BuildData()
    local out = {}
    local db = ns.BIS_TRINKETS or {}
    local byClass = (selectedClassTag and db[selectedClassTag]) or nil
    local bySpec  = byClass and byClass[selectedSpecID] or nil
    -- Explication de la sous-fonction: si aucune donnée pour la spé, retourne une liste vide
    if not bySpec then return out end

    local baseOrder = {}
    for i, t in ipairs(TIER_ORDER) do baseOrder[t] = i end

    local tiers = {}
    for key, ids in pairs(bySpec) do
        -- Explication de la sous-fonction: ne retient que les listes d'items valides
        if type(ids) == "table" then
            local base, mod, label = _ParseTierKey(key)
            -- Explication de la sous-fonction: si la clé correspond à un rang valide, la prépare pour tri/affichage
            if base then
                local bidx = baseOrder[base] or 99
                local midx = (mod == "plus") and -1 or (mod == "minus") and 1 or 0
                tiers[#tiers+1] = { key = key, ids = ids, base = base, mod = mod, label = label, bidx = bidx, midx = midx }
            end
        end
    end

    table.sort(tiers, function(a,b)
        -- Explication de la sous-fonction: tri principal par rang de base
        if a.bidx ~= b.bidx then return a.bidx < b.bidx end
        -- Explication de la sous-fonction: variantes + avant, - après
        if a.midx ~= b.midx then return a.midx < b.midx end
        -- Explication de la sous-fonction: tri alpha sur le label en dernier recours
        return tostring(a.label) < tostring(b.label)
    end)

    for _, t in ipairs(tiers) do
        for _, itemID in ipairs(t.ids) do
            local owned = (GetItemCount and (GetItemCount(itemID, true) or 0) or 0) > 0
            out[#out+1] = {
                tier       = t.base,
                mod        = t.mod,
                tierLabel  = t.label,
                itemID     = itemID,
                owned      = owned,
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
        classDD:SetSelected(selectedClassTag, _ClassName(selectedClassID, selectedClassTag))
    end
    if specDD then
        local specLabel = _SpecName(selectedClassID, selectedSpecID)
        -- Explication de la sous-fonction: fallback sur libellé générique si vide
        if (not specLabel) or specLabel == "" then
            specLabel = Tr("lbl_spec") or "Specialization"
        end
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
local function UpdateRow(i, r, f, d)
    UI.SetTierBadge(f.tier, d.tier, d.mod, d.tierLabel, UI.Colors and UI.Colors.BIS_TIER_COLORS)
    UI.SetItemCell(f.item, { itemID = d.itemID })
    f.owned:SetText(_OwnedText(d.owned))
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

-- == Crée un petit footer local (texte bas-gauche gris) == --
local function _CreateFooter(parent, text)
    local f = CreateFrame("Frame", nil, parent)
    f:SetHeight(16)
    local lbl = UI.Label(f, { template = "GameFontDisableSmall" })
    lbl:SetText(text or "")
    lbl:ClearAllPoints()
    lbl:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    f.label = lbl
    return f
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
    introFS:SetText(Tr("bis_intro") or "Cette page liste les bijoux (trinkets) BiS par classe et spécialisation. Les rangs S à F indiquent la priorité (S étant le meilleur). Utilisez les listes déroulantes pour changer la classe et la spécialisation.")
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
    lblClass:SetText(Tr("lbl_class") or "Class")
    lblClass:SetPoint("LEFT", filtersArea, "LEFT", 0, 0)
    lblClass:SetPoint("TOP",  filtersArea, "TOP",  0, -2)

    classDD = UI.Dropdown(filtersArea, { width = 200, placeholder = Tr("lbl_class") or "Class" })
    classDD:SetPoint("LEFT", lblClass, "RIGHT", 8, -2)
    classDD:SetBuilder(_ClassMenuBuilder)
    _AttachDropdownZFix(classDD, panel)

    local lblSpec = UI.Label(filtersArea, { template="GameFontNormal" })
    lblSpec:SetText(Tr("lbl_spec") or "Specialization")
    lblSpec:SetPoint("LEFT", classDD, "RIGHT", 24, 2)

    specDD = UI.Dropdown(filtersArea, { width = 220, placeholder = Tr("lbl_spec") or "Specialization" })
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
    sourceFS:SetText(Tr("footer_source_wowhead") or "Source : wowhead.com")

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