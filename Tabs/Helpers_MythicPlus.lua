-- Tabs/Helpers_MythicPlus.lua
local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns.GLOG, ns.UI
local L = ns and ns.L
local U = ns.Util

-- État local
local panel
local currentWeekOffset = 0 -- 0 = semaine actuelle, 1 = suivante, -1 = précédente
local affixFrames = {}
local dungeonFrames = {}

-- Données des donjons saisonniers (ID Challenge -> Texture uniquement)
local SEASONAL_DUNGEONS = {
    [391] = { texture = "Interface\\EncounterJournal\\UI-EJ-LOREBG-TazaveshtheVeiledMarket" },
    [392] = { texture = "Interface\\EncounterJournal\\UI-EJ-LOREBG-TazaveshtheVeiledMarket" },
    [542] = { texture = "Interface\\EncounterJournal\\UI-EJ-LOREBG-EcoDome" },
    [378] = { texture = "Interface\\EncounterJournal\\UI-EJ-LOREBG-HallsofAtonement" },
    [503] = { texture = "Interface\\EncounterJournal\\UI-EJ-LOREBG-AraKaraCityOfEchoes" },
    [525] = { texture = "Interface\\EncounterJournal\\UI-EJ-LOREBG-Waterworks" },
    [499] = { texture = "Interface\\EncounterJournal\\UI-EJ-LOREBG-PrioryOfTheSacredFlames" },
    [505] = { texture = "Interface\\EncounterJournal\\UI-EJ-LOREBG-TheDawnbreaker" }
}

-- Table de ranking des donjons basée sur les combinaisons d'affixes
local DUNGEON_RANKINGS = {
    [10] = {
        [160] = { -- dévorer
            [391] = "S", [392] = "A", [542] = "S", [378] = "B", [503] = "C", [525] = "A", [499] = "A", [505] = "A"
        },
        [148] = { -- sublimation
            [391] = "S", [392] = "S", [542] = "S", [378] = "A", [503] = "C", [525] = "C", [499] = "C", [505] = "B"
        }
     },
     [9] = {
        [162] = { --- pulsar
            [391] = "A", [392] = "A", [542] = "S", [378] = "C", [503] = "C", [525] = "B", [499] = "B", [505] = "B"
        }
     },
    -- Pour l'instant, valeurs par défaut "S" pour tous
    default = "?"
}

-- Fonction pour récupérer le rank d'un donjon selon les affixes actifs
local function GetDungeonRank(dungeonId, affix1Id, affix2Id)
    if not dungeonId or not affix1Id or not affix2Id then 
        return DUNGEON_RANKINGS.default or "S"
    end
    
    -- Vérifier si on a une combinaison spécifique définie
    if DUNGEON_RANKINGS[affix1Id] and DUNGEON_RANKINGS[affix1Id][affix2Id] then
        local rank = DUNGEON_RANKINGS[affix1Id][affix2Id][dungeonId]
        if rank then
            return rank
        end
    end
    
    -- Essayer l'ordre inverse des affixes
    if DUNGEON_RANKINGS[affix2Id] and DUNGEON_RANKINGS[affix2Id][affix1Id] then
        local rank = DUNGEON_RANKINGS[affix2Id][affix1Id][dungeonId]
        if rank then
            return rank
        end
    end
    
    -- Fallback : rank par défaut
    return DUNGEON_RANKINGS.default or "S"
end

-- Fonction pour récupérer le nom d'un donjon via son ID Challenge Mode
local function GetDungeonName(challengeModeID)
    if not challengeModeID then return Tr("unknown_dungeon") or "Donjon inconnu" end
    
    -- Utiliser l'API Challenge Mode pour récupérer le nom
    local name = C_ChallengeMode.GetMapUIInfo(challengeModeID)
    if name and name ~= "" then
        return name
    end
    
    -- Fallback : essayer l'API Map Info
    local mapInfo = C_Map.GetMapInfo(challengeModeID)
    if mapInfo and mapInfo.name and mapInfo.name ~= "" then
        return mapInfo.name
    end
    
    -- Fallback final : nom par défaut
    return Tr("dungeon_id_format"):format(tostring(challengeModeID)) or ("Donjon #" .. tostring(challengeModeID))
end

-- Déclaration forward pour Refresh
local Refresh

-- Création d'un frame d'affixe avec icône et tooltip
local function CreateAffixFrame(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(64, 64)
    
    -- Arrière-plan pour le cadre
    frame.background = frame:CreateTexture(nil, "BACKGROUND")
    frame.background:SetAllPoints()
    frame.background:SetColorTexture(0.2, 0.2, 0.2, 0.8)
    
    -- Bordure décorative
    frame.border = frame:CreateTexture(nil, "BORDER")
    frame.border:SetAllPoints()
    frame.border:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    frame.border:SetVertexColor(0.8, 0.8, 0.8, 1)
    
    -- Bordure intérieure dorée
    frame.innerBorder = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    frame.innerBorder:SetAllPoints()
    frame.innerBorder:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    frame.innerBorder:SetBackdropBorderColor(1, 0.82, 0, 0.8) -- Couleur dorée
    
    -- Icône
    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetPoint("TOPLEFT", 4, -4)
    frame.icon:SetPoint("BOTTOMRIGHT", -4, 4)
    frame.icon:SetTexCoord(0.1, 0.9, 0.1, 0.9)
    
    -- Texte du nom avec gestion des sauts de ligne (police vraiment réduite)
    frame.nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.nameText:SetPoint("TOP", frame, "BOTTOM", 0, -4)
    frame.nameText:SetTextColor(1, 1, 1)
    frame.nameText:SetWidth(80) -- Largeur fixe pour forcer les sauts de ligne
    frame.nameText:SetWordWrap(true)
    frame.nameText:SetJustifyH("CENTER")
    
    -- Réduire manuellement la taille de la police
    local font, size, flags = frame.nameText:GetFont()
    frame.nameText:SetFont(font, size * 0.85, flags) -- Réduction de 15%
    
    -- Gestion du tooltip
    frame:SetScript("OnEnter", function(self)
        if self.affixId and self.description then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(self.affixName or ("Affixe " .. tostring(self.affixId)), 1, 1, 1)
            if self.description and self.description ~= "" then
                GameTooltip:AddLine(self.description, nil, nil, nil, true)
            end
            GameTooltip:Show()
        end
    end)
    
    frame:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    frame:EnableMouse(true)
    
    return frame
end

-- Création d'un frame de donjon avec texture et badge S
local function CreateDungeonFrame(parent)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(240, 240) -- Augmentation de 30% en hauteur : 160 * 1.3 = 208
    
    -- Arrière-plan de la texture du donjon
    frame.texture = frame:CreateTexture(nil, "BACKGROUND")
    frame.texture:SetAllPoints(frame) -- Occupe absolument tout l'espace du frame (180x140)
    frame.texture:SetTexCoord(0, 1, 0, 1) -- Texture complète sans crop
    
    -- Nom du donjon au-dessus (police plus petite pour prendre moins de place)
    frame.nameText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.nameText:SetPoint("TOP", frame, "TOP", -27, -22)
    frame.nameText:SetTextColor(1, 1, 1)
    frame.nameText:SetWidth(120) -- Ajusté à la nouvelle largeur (200-5px marge)
    frame.nameText:SetWordWrap(true)
    frame.nameText:SetJustifyH("CENTER")
    
    -- Ajuster la taille de la police du nom pour la nouvelle taille
    local font, size, flags = frame.nameText:GetFont()
    frame.nameText:SetFont(font, size * 0.8, flags) -- Légèrement plus grande pour les frames plus larges
    
    -- Badge "S" utilisant UI_Badge dans le coin inférieur droit
    frame.badge = UI.CreateBadgeCell(frame, { centeredGloss = true, textShadow = false, width = 28})
    frame.badge:SetSize(28, 28) -- Taille augmentée proportionnellement
    frame.badge:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -73, 103) -- Repositionné avec plus de marge
    
    return frame
end

-- Mise à jour d'un frame de donjon
local function UpdateDungeonFrame(frame, dungeonId, dungeonData, affix1Id, affix2Id)
    if not frame or not dungeonData then return end
    
    frame.dungeonId = dungeonId
    
    -- Récupérer dynamiquement le nom du donjon
    local dynamicName = GetDungeonName(dungeonId)
    frame.dungeonName = dynamicName
    
    -- Mettre à jour la texture (gardée en dur)
    frame.texture:SetTexture(dungeonData.texture)
    
    -- Mettre à jour le nom (dynamique)
    frame.nameText:SetText(dynamicName)
    
    -- Récupérer le rank basé sur la combinaison d'affixes
    local rank = GetDungeonRank(dungeonId, affix1Id, affix2Id)
    
    -- Mettre à jour le badge avec le rank dynamique
    if frame.badge then
        UI.SetTierBadge(frame.badge, rank, 0, rank) -- Utilise SetTierBadge avec le rank comme base, mod=0, et label
    end
end

-- Mise à jour d'un frame d'affixe
local function UpdateAffixFrame(frame, affixId)
    if not frame then return end
    
    frame.affixId = affixId
    local name, iconId, description = U.GetAffixInfo(affixId)
    
    frame.affixName = name
    frame.description = description
    
    if iconId and iconId ~= 0 then
        frame.icon:SetTexture(iconId)
        frame.icon:Show()
    else
        -- Fallback : utiliser une texture par défaut
        frame.icon:SetTexture("Interface\\Icons\\Achievement_Dungeon_Heroic_GloryoftheHero")
        frame.icon:Show()
    end
    
    -- Gestion intelligente du texte (raccourcissement ou saut de ligne)
    local displayName = name
    if string.len(name) > 20 then
        -- Pour les noms très longs, essayer de couper intelligemment
        local words = {}
        for word in string.gmatch(name, "%S+") do
            table.insert(words, word)
        end
        
        if #words > 1 then
            -- Si plusieurs mots, utiliser le saut de ligne
            if #words == 2 then
                displayName = words[1] .. "\n" .. words[2]
            elseif #words >= 3 then
                -- Pour 3 mots ou plus, regrouper intelligemment
                local firstLine = words[1]
                local secondLine = ""
                for i = 2, #words do
                    if i == 2 then
                        secondLine = words[i]
                    else
                        secondLine = secondLine .. " " .. words[i]
                    end
                end
                displayName = firstLine .. "\n" .. secondLine
            end
        else
            -- Un seul mot très long, le raccourcir
            displayName = string.sub(name, 1, 18) .. "..."
        end
    end
    
    frame.nameText:SetText(displayName)
end

-- Création des boutons de navigation
local function CreateNavigationButton(parent, direction)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(32, 32)
    
    -- Texture du bouton
    button:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
    button:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down")
    button:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Disabled")
    button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    
    if direction == "prev" then
        -- Rotation pour le bouton précédent
        button:GetNormalTexture():SetRotation(math.pi)
        button:GetPushedTexture():SetRotation(math.pi)
        button:GetDisabledTexture():SetRotation(math.pi)
        button:GetHighlightTexture():SetRotation(math.pi)
    end
    
    button:SetScript("OnClick", function()
        local newOffset
        if direction == "next" then
            newOffset = currentWeekOffset + 1
        else
            newOffset = currentWeekOffset - 1
        end
        
        -- Vérifier si la nouvelle semaine est valide (pas avant le début de saison)
        local currentWeek = GLOG.Time.GetWeekNumberFromTimestamp(time())
        local targetWeek = currentWeek + newOffset
        
        if targetWeek >= 1 then -- La semaine 1 est le début de la saison
            currentWeekOffset = newOffset
            if Refresh then
                Refresh()
            end
        end
    end)
    
    return button
end

-- Construction de l'interface
local function Build(container)
    -- Création du conteneur principal
    panel = UI.CreateMainContainer(container, {footer = false})
    
    -- Titre de section
    local y = UI.SectionHeader(panel, Tr("mythicplus_title") or "Rotation des Affixes Mythique+", { topPad = 0 }) or 26
    y = y + 20
    
    -- Container pour la navigation et les affixes
    local navContainer = CreateFrame("Frame", nil, panel)
    navContainer:SetPoint("TOP", panel, "TOP", 0, -y + 25)
    navContainer:SetSize(600, 160) -- Hauteur augmentée pour le texte multi-ligne
    
    -- Cadre esthétique avec opacité et bords arrondis
    navContainer.headerFrame = CreateFrame("Frame", nil, navContainer, "BackdropTemplate")
    navContainer.headerFrame:SetPoint("LEFT", navContainer, "LEFT", 36, 0) -- Commence après la moitié des flèches (20 + 16)
    navContainer.headerFrame:SetPoint("RIGHT", navContainer, "RIGHT", -36, 0) -- S'arrête avant la moitié des flèches (-20 - 16)
    navContainer.headerFrame:SetPoint("TOP", navContainer, "TOP", 0, -5)
    navContainer.headerFrame:SetPoint("BOTTOM", navContainer, "BOTTOM", 0, 0) -- Encore plus bas (de 45 à 10)
    navContainer.headerFrame:SetFrameLevel(navContainer:GetFrameLevel() - 1) -- Derrière les autres éléments
    
    -- Configuration du backdrop avec bords arrondis
    navContainer.headerFrame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false,
        tileSize = 0,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    
    -- Couleur de fond noire avec opacité légère
    navContainer.headerFrame:SetBackdropColor(0, 0, 0, 0.7) -- Noir avec 70% d'opacité
    
    -- Bordure dorée subtile
    navContainer.headerFrame:SetBackdropBorderColor(1, 0.82, 0, 0.4) -- Doré avec 40% d'opacité
    
    -- Effet de lueur intérieure
    navContainer.headerGlow = navContainer.headerFrame:CreateTexture(nil, "BACKGROUND")
    navContainer.headerGlow:SetPoint("TOPLEFT", navContainer.headerFrame, "TOPLEFT", 3, -3)
    navContainer.headerGlow:SetPoint("BOTTOMRIGHT", navContainer.headerFrame, "BOTTOMRIGHT", -3, 3)
    navContainer.headerGlow:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
    navContainer.headerGlow:SetVertexColor(0.1, 0.1, 0.1, 0.3) -- Lueur noire subtile
    navContainer.headerGlow:SetBlendMode("ADD")
    
    -- Titre de semaine (dates) - au-dessus du cadre
    navContainer.weekTitle = navContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    navContainer.weekTitle:SetPoint("TOP", navContainer, "TOP", 0, -15)
    navContainer.weekTitle:SetTextColor(1, 0.82, 0)
    
    -- Sous-titre de statut (Semaine actuelle, etc.) - au-dessus du cadre
    navContainer.weekStatus = navContainer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    navContainer.weekStatus:SetPoint("TOP", navContainer.weekTitle, "BOTTOM", 0, -5)
    navContainer.weekStatus:SetTextColor(0.7, 0.7, 0.7)
    
    -- Bouton précédent (rapproché, moitié dehors du cadre)
    navContainer.prevButton = CreateNavigationButton(navContainer, "prev")
    navContainer.prevButton:SetPoint("LEFT", navContainer, "LEFT", 20, 0) -- Position pour être à moitié sur le cadre
    
    -- Bouton suivant (rapproché, moitié dehors du cadre)
    navContainer.nextButton = CreateNavigationButton(navContainer, "next")
    navContainer.nextButton:SetPoint("RIGHT", navContainer, "RIGHT", -20, 0) -- Position pour être à moitié sur le cadre
    
    -- Conteneur pour les affixes (ajusté pour le nouveau sous-titre et cadre esthétique)
    navContainer.affixContainer = CreateFrame("Frame", nil, navContainer)
    navContainer.affixContainer:SetPoint("CENTER", navContainer, "CENTER", 0, -10) -- Ajusté pour le cadre
    navContainer.affixContainer:SetSize(400, 120) -- Largeur augmentée pour l'espacement doublé (de 300 à 400px)
    
    -- === SECTION DONJONS SAISONNIERS ===
    -- Titre pour les donjons saisonniers (espace réduit)
    local dungeonY = y + 130 -- Réduit de 200 à 185 pour rapprocher les sections
    
    -- Container pour les donjons (toute la largeur disponible)
    local dungeonContainer = CreateFrame("Frame", nil, panel)
    dungeonContainer:SetPoint("TOP", panel, "TOP", 0, -dungeonY)
    dungeonContainer:SetSize(900, 450) -- Container encore plus grand pour les frames plus hautes (208*2 + marges)
    
    -- Cadre esthétique pour les donjons
    dungeonContainer.frame = CreateFrame("Frame", nil, dungeonContainer, "BackdropTemplate")
    dungeonContainer.frame:SetAllPoints(dungeonContainer)
    dungeonContainer.frame:SetFrameLevel(dungeonContainer:GetFrameLevel() - 1)
    
    dungeonContainer.frame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false,
        tileSize = 0,
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    
    dungeonContainer.frame:SetBackdropColor(0, 0, 0, 0)
    dungeonContainer.frame:SetBackdropBorderColor(1, 0.82, 0, 0)
    
    -- Création des frames de donjons
    dungeonContainer.dungeonFrames = {}
    for i = 1, 8 do
        local frame = CreateDungeonFrame(dungeonContainer)
        dungeonContainer.dungeonFrames[i] = frame
        
        -- Disposition en grille 4x2 répartie sur toute la largeur
        local col = ((i - 1) % 4) + 1
        local row = math.ceil(i / 4)
        
        -- Calcul pour répartir équitablement sur toute la largeur (900px)
        -- Marge: 20px de chaque côté, donc 860px utilisables
        -- 4 frames de 200px = 800px, reste 60px pour espacement = 20px entre frames
        local totalWidth = 860 -- Largeur utilisable (900 - 40 marges)
        local frameWidth = 200 -- Nouvelle largeur des frames
        local spacingWidth = (totalWidth - (4 * frameWidth)) / 3 -- Espacement entre les 4 frames
        
        local xOffset = 20 + (col - 1) * (frameWidth + spacingWidth) -- Commence à 20px du bord
        local yOffset = -15 - (row - 1) * 165  -- Espacement vertical ajusté pour les frames encore plus hautes (208 + 12px marge)
        
        frame:SetPoint("TOPLEFT", dungeonContainer, "TOPLEFT", xOffset, yOffset)
    end
    
    -- Stockage des références
    panel.navContainer = navContainer
    panel.dungeonContainer = dungeonContainer
end

-- Mise à jour des données
function Refresh()
    if not panel or not panel.navContainer then return end
    
    local navContainer = panel.navContainer
    local affixes, weekNumber = U.GetWeekAffixes(currentWeekOffset)
    
    -- Mise à jour du titre avec les dates de début et fin de semaine
    local weekDateRange = GLOG.Time.GetWeekDateRange(weekNumber)
    navContainer.weekTitle:SetText(weekDateRange)
    
    -- Mise à jour du statut de semaine avec colorisation
    local statusText, statusColor
    if currentWeekOffset == 0 then
        statusText = "Semaine actuelle"
        statusColor = {0.2, 1, 0.2} -- Vert
    elseif currentWeekOffset == 1 then
        statusText = "Semaine prochaine"
        statusColor = {0.7, 0.7, 0.7} -- Gris
    elseif currentWeekOffset == -1 then
        statusText = "Semaine dernière"
        statusColor = {0.7, 0.7, 0.7} -- Gris
    else
        local offsetText = currentWeekOffset > 0 and ("Dans " .. currentWeekOffset .. " semaines") or ("Il y a " .. math.abs(currentWeekOffset) .. " semaines")
        statusText = offsetText
        statusColor = {0.7, 0.7, 0.7} -- Gris
    end
    
    navContainer.weekStatus:SetText(statusText)
    navContainer.weekStatus:SetTextColor(statusColor[1], statusColor[2], statusColor[3])
    
    -- Nettoyage des anciens frames d'affixes
    for _, frame in ipairs(affixFrames) do
        frame:Hide()
    end
    
    -- Création/mise à jour des frames d'affixes
    for i, affixId in ipairs(affixes) do
        if not affixFrames[i] then
            affixFrames[i] = CreateAffixFrame(navContainer.affixContainer)
        end
        
        local frame = affixFrames[i]
        UpdateAffixFrame(frame, affixId)
        frame:Show()
        
        -- Positionnement
        if i == 1 then
            frame:SetPoint("CENTER", navContainer.affixContainer, "CENTER", -60, 0) -- Ajusté pour l'espacement doublé
        else
            frame:SetPoint("LEFT", affixFrames[i-1], "RIGHT", 40, 0) -- Espacement doublé (de 20 à 40px)
        end
    end
    
    -- === MISE À JOUR DES DONJONS SAISONNIERS ===
    if panel.dungeonContainer and panel.dungeonContainer.dungeonFrames then
        -- Récupérer les deux premiers affixes pour le ranking (en ignorant les affixes saisonniers)
        local affix1Id, affix2Id = nil, nil
        if affixes and #affixes >= 2 then
            affix1Id = affixes[1]
            affix2Id = affixes[2]
        end
        
        local dungeonIndex = 1
        for dungeonId, dungeonData in pairs(SEASONAL_DUNGEONS) do
            if dungeonIndex <= 8 and panel.dungeonContainer.dungeonFrames[dungeonIndex] then
                UpdateDungeonFrame(panel.dungeonContainer.dungeonFrames[dungeonIndex], dungeonId, dungeonData, affix1Id, affix2Id)
                panel.dungeonContainer.dungeonFrames[dungeonIndex]:Show()
                dungeonIndex = dungeonIndex + 1
            end
        end
        
        -- Masquer les frames non utilisés
        for i = dungeonIndex, 8 do
            if panel.dungeonContainer.dungeonFrames[i] then
                panel.dungeonContainer.dungeonFrames[i]:Hide()
            end
        end
    end
end

-- Mise en page
local function Layout()
    if not panel then return end
    -- La mise en page est gérée par les points d'ancrage fixes pour l'instant
end

-- Enregistrement de l'onglet
UI.RegisterTab(Tr("tab_mythic_plus") or "Rotation Mythique+", Build, Refresh, Layout, {
    category = Tr("cat_info") or "Helpers",
})
