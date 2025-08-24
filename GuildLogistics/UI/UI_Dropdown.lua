local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns and ns.GLOG, ns and ns.UI

-- Assure l'existence de l'espace UI de l'addon
UI = UI or {}
if ns then ns.UI = UI end

-- ============================================== --
-- ===        DROPDOWN – OUTILS GÉNÉRIQUES     === --
-- ============================================== --

-- == Fixe le Z-order des DropDownList système pour qu'ils s'affichent au-dessus du frame hôte pendant l'ouverture ==
function UI.AttachDropdownZFix(dd, host)
    -- Si l'un des paramètres est manquant, on quitte immédiatement
    if not dd or not host then return end

    local btn = _G[dd:GetName().."Button"]
    -- Si le bouton associé au dropdown n'existe pas, on ne peut pas hook l'évènement
    if not btn then return end

    btn:HookScript("OnClick", function()
        -- N'exécute que si C_Timer est disponible
        if C_Timer and C_Timer.After then
            C_Timer.After(0, function()
                for i = 1, 2 do
                    local f = _G["DropDownList"..i]
                    -- Si la liste système est visible, on élève sa strata/niveau par rapport au frame hôte
                    if f and f:IsShown() then
                        f:SetFrameStrata(host:GetFrameStrata() or "DIALOG")
                        f:SetFrameLevel((host:GetFrameLevel() or 10) + 100)
                    end
                end
            end)
        end
    end)
end

-- == Construit une fabrique de builder de menu de CLASSE à partir d'une table source indexée par tag de classe ==
-- opts = {
--   dataByClassTag = table,            -- ex: { WARRIOR = {...}, MAGE = {...}, ... }
--   includePlayerFirst = true|false,   -- place la classe du joueur en premier si true (défaut)
--   getCurrent = function() -> tag,    -- retourne le tag de classe actuellement sélectionné
--   onSelect   = function(tag, id) end -- callback obligatoire à l'activation d'une entrée
-- }
function UI.MakeClassMenuBuilder(opts)
    opts = opts or {}
    local data = opts.dataByClassTag or {}
    local includePlayerFirst = (opts.includePlayerFirst ~= false)
    local getCurrent = opts.getCurrent or function() return nil end
    local onSelect   = opts.onSelect   or function() end

    local function ClassName(classID, classTag)
        return (UI.ClassName and UI.ClassName(classID, classTag)) or (classTag or "")
    end
    local function GetClassIDForToken(tag)
        return (UI.GetClassIDForToken and UI.GetClassIDForToken(tag)) or nil
    end
    local function ResolvePlayer()
        return (UI.ResolvePlayerClassSpec and UI.ResolvePlayerClassSpec())
    end

    -- Helper local pour homogénéiser la création d'entries UIDropDown
    local function _info(text, checked, onclick, isTitle)
        local info = UIDropDownMenu_CreateInfo()
        if isTitle then
            info.text, info.isTitle, info.notCheckable = text, true, true
        else
            info.text, info.notCheckable, info.checked, info.func = text, false, not not checked, onclick
        end
        return info
    end

    return function(self, level)
        local entries, seen = {}, {}

        -- Place la classe du joueur en tête si demandé
        if includePlayerFirst then
            local playerID, playerTag = ResolvePlayer()
            -- Si la classe du joueur est connue, on l'ajoute en premier
            if playerTag then
                local up = playerTag:upper()
                local label = ClassName(playerID, up)
                entries[#entries+1] = _info(label, (getCurrent() == up), function() onSelect(up, playerID) end, false)
                seen[up] = true
            end
        end

        -- Construit la liste des autres classes issues de la source
        local scratch = {}
        for tag in pairs(data) do
            local up = tag and tag:upper() or ""
            -- On ignore les tags vides et ceux déjà insérés
            if up ~= "" and not seen[up] then
                local cid   = GetClassIDForToken(up)
                local label = ClassName(cid, up)
                scratch[#scratch+1] = { text = label, tag = up, cid = cid, checked = (getCurrent() == up) }
            end
        end

        -- Trie alphabétique pour un ordre déterministe
        table.sort(scratch, function(a, b) return tostring(a.text) < tostring(b.text) end)

        for _, e in ipairs(scratch) do
            entries[#entries+1] = _info(e.text, e.checked, function() onSelect(e.tag, e.cid) end, false)
        end

        -- Si aucune entrée, affiche un titre "No data"
        if #entries == 0 then
            entries[1] = _info((Tr and Tr("msg_no_data")) or "No data", nil, nil, true)
        end

        return entries
    end
end

-- == Construit une fabrique de builder de menu de SPÉCIALISATION pour la classe actuellement sélectionnée ==
-- opts = {
--   dataByClassTag  = table,                -- data[classTag] = table indexée par specID
--   classTagProvider = function() -> tag,   -- fournit le tag de classe courant
--   classIDProvider  = function() -> id,    -- fournit l'ID de classe courant
--   getCurrentSpecID = function() -> specID,-- fournit la spé sélectionnée
--   onSelect         = function(specID) end -- callback à l'activation d'une entrée
-- }
function UI.MakeSpecMenuBuilder(opts)
    opts = opts or {}
    local data        = opts.dataByClassTag or {}
    local getClassTag = opts.classTagProvider or function() return nil end
    local getClassID  = opts.classIDProvider  or function() return nil end
    local getCurrent  = opts.getCurrentSpecID or function() return nil end
    local onSelect    = opts.onSelect or function() end

    local function SpecName(classID, specID)
        return (UI.SpecName and UI.SpecName(classID, specID)) or tostring(specID or "")
    end

    -- Helper local pour homogénéiser la création d'entries UIDropDown
    local function _info(text, checked, onclick, isTitle)
        local info = UIDropDownMenu_CreateInfo()
        if isTitle then
            info.text, info.isTitle, info.notCheckable = text, true, true
        else
            info.text, info.notCheckable, info.checked, info.func = text, false, not not checked, onclick
        end
        return info
    end

    return function(self, level)
        local entries = {}
        local tag     = getClassTag()
        local classID = getClassID()
        local byClass = tag and data[tag] or nil

        -- Si la table des spés pour la classe courante existe, on la parcourt
        if byClass then
            local scratch = {}
            for specID in pairs(byClass) do
                local label = SpecName(classID, specID)
                scratch[#scratch+1] = { text = label, specID = specID, checked = (getCurrent() == specID) }
            end
            -- Trie alphabétique pour un ordre déterministe
            table.sort(scratch, function(a, b) return tostring(a.text) < tostring(b.text) end)
            for _, e in ipairs(scratch) do
                entries[#entries+1] = _info(e.text, e.checked, function() onSelect(e.specID) end, false)
            end
        end

        -- Si aucune entrée, affiche un titre "No data"
        if #entries == 0 then
            entries[1] = _info((Tr and Tr("msg_no_data")) or "No data", nil, nil, true)
        end

        return entries
    end
end
