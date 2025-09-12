local ADDON, ns = ...
local Tr  = ns and ns.Tr
local GLOG, UI = ns.GLOG, ns.UI

local PAD = (UI and UI.OUTER_PAD) or 8

local panel, lv, listArea


-- Affichage des membres du groupe : on réutilise la popup roster de l'onglet "Historique des raids" si elle existe
local function ShowGroupMembers(anchor, members)
    members = members or {}
    local title = Tr("group_members") or "Membres du groupe"

    -- 1) Tentatives d'APIs existantes (onglet Historique des raids / UI partagée)
    if UI then
        -- Cas: module interne de l'onglet
        if UI.RaidHistory and type(UI.RaidHistory.ShowRoster) == "function" then
            UI.RaidHistory.ShowRoster(members, { title = title, anchor = anchor })
            return
        end
        -- Cas: popup générique déjà existante
        if type(UI.ShowRosterPopup) == "function" then
            UI.ShowRosterPopup(members, { title = title, anchor = anchor })
            return
        end
        if type(UI.PopupRoster) == "function" then
            UI.PopupRoster(members, { title = title, anchor = anchor })
            return
        end
    end

    -- 2) Fallback: mini popup locale avec ListView (même rendu global)
    local cols = UI.NormalizeColumns({
        { key="idx",  title=Tr("col_hash") or "#",    w=24,  align="CENTER" },
        { key="name", title=Tr("col_name") or "Nom", vsep=true,  min=200, flex=1 },
    })
    local data = {}
    for i, name in ipairs(members) do
        data[#data+1] = { idx = i, name = name }
    end

    -- Construction d'une popup simple avec un ListView interne
    local popup = UI.PopupPanel and UI.PopupPanel(title, 420, 380) or CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    if popup.SetTitle then popup:SetTitle(title) end
    local container = popup.content or popup
    local lvPopup = UI.ListView(container, cols, {
        topOffset = 0,
        buildRow  = function(row)
            local w = {}
            w.idx  = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            w.idx:SetJustifyH("CENTER")
            w.name = UI.CreateNameTag and UI.CreateNameTag(row) or row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            if w.name.SetJustifyH then w.name:SetJustifyH("LEFT") end
            return w
        end,
        updateRow = function(i, row, w, it)
            if w.idx then w.idx:SetText(tostring(it.idx or i)) end
            if w.name then
                if UI.SetNameTagShort then UI.SetNameTagShort(w.name, it.name or "")
                else w.name:SetText(tostring(it.name or "")) end
            end
        end,
    })
    if lvPopup and lvPopup.SetData then lvPopup:SetData(data) end
    if popup.Show then popup:Show() end
end


-- =========================
--    Helpers de cellule
-- =========================
local function BuildRow(row)
    local w = {}

    w.date = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    w.date:SetJustifyH("LEFT")
    
    w.ilvl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    w.ilvl:SetJustifyH("CENTER")

    w.item = UI.CreateItemCell(row, { size = 16, width = 320 })

    -- Qui (ramassé par) + petite icône de type de roll à droite
    w.who = UI.CreateNameTag and UI.CreateNameTag(row) or row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    if w.who.SetJustifyH then w.who:SetJustifyH("LEFT") end

    -- Support icône roll (14px) à droite du nom
    w.rollBtn = CreateFrame("Button", nil, w.who)
    w.rollBtn:SetSize(14, 14)
    w.rollBtn:SetPoint("RIGHT", w.who, "RIGHT", 0, 0)
    w.rollTex = w.rollBtn:CreateTexture(nil, "ARTWORK")
    w.rollTex:SetAllPoints(w.rollBtn)
    w.rollBtn:Hide()

    -- Le texte du name tag s’arrête avant l’icône
    if w.who.text then
        w.who.text:ClearAllPoints()
        local anchorLeft = (w.who.icon or w.who)
        w.who.text:SetPoint("LEFT", anchorLeft, "RIGHT", 3, 0)
        w.who.text:SetPoint("RIGHT", w.rollBtn, "LEFT", -3, 0)
    end

    -- Tooltip
    w.rollBtn:SetScript("OnEnter", function(btn)
        if not btn._rollType or btn._rollType == "" then return end
        GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
        local lbl = (UI.RollLabel and UI.RollLabel(btn._rollType)) or btn._rollType
        if btn._rollVal then
            GameTooltip:AddLine(string.format("%s (%d)", lbl, btn._rollVal))
        else
            GameTooltip:AddLine(lbl)
        end
        GameTooltip:Show()
    end)
    w.rollBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    w.inst = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    w.inst:SetJustifyH("LEFT")

    w.diff = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    w.diff:SetJustifyH("LEFT")

    -- Colonne "Groupe" (bouton avec nombre de membres)
    w.grp = CreateFrame("Frame", nil, row)
    w.grp:SetHeight(UI.ROW_H)

    w.grpBtn = (UI.Button and UI.Button(w.grp, "0", {
        size="xs", variant="secondary", minWidth=28,
        tooltip = Tr("tip_show_group") or "Voir le groupe"
    })) or CreateFrame("Button", nil, w.grp, "UIPanelButtonTemplate")

    if w.grpBtn.SetText then w.grpBtn:SetText("0") end
    w.grpBtn:ClearAllPoints()
    w.grpBtn:SetPoint("CENTER", w.grp, "CENTER", 0, 0)

    -- (Colonne roll supprimée : icône seulement à droite du pseudo)

    -- Colonne supprimer
    w.close = CreateFrame("Frame", nil, row)
    w.close:SetHeight(UI.ROW_H)

    w.del = (UI.Button and UI.Button(w.close, "X", { size="xs", variant="danger", minWidth=24,
        tooltip = Tr("btn_delete") or (Tr("confirm_delete") or "Supprimer")
    })) or CreateFrame("Button", nil, w.close, "UIPanelButtonTemplate")

    -- Assure l'affichage et l'ancrage dans la cellule
    if w.del.SetText then w.del:SetText(Tr("btn_delete_short") or "X") end
    w.del:ClearAllPoints()
    w.del:SetPoint("CENTER", w.close, "CENTER", 0, 0)

    return w
end

local function UpdateRow(i, row, w, it)
    if not it then return end

    -- Date / Heure
    local ts = tonumber(it.ts or 0) or 0
    local dstr = (ts > 0) and (date(Tr("format_date").." "..Tr("format_heure"), ts)) or ""
    if w.date then w.date:SetText(dstr) end

    -- iLvl
    if w.ilvl then
        local iv = tonumber(it.ilvl or 0) or 0
        w.ilvl:SetText(iv > 0 and tostring(iv) or Tr("value_dash") or "-")
    end

    -- Objet (icône, texte + tooltip) coloré selon la rareté
    if w.item then
        local link = it.link or ""
        local itemID = link:match("|Hitem:(%d+):")
        local q, iconTex
        if itemID and type(C_Item) == "table" then
            if C_Item.GetItemQualityByID then
                q = tonumber(C_Item.GetItemQualityByID(tonumber(itemID)))
            end
            if C_Item.GetItemIconByID then
                iconTex = C_Item.GetItemIconByID(tonumber(itemID))
            end
        end

        -- Nom/couleur du lien
        local nameFromLink = link:match("%[(.-)%]") or link
        local colorFromLink = link:match("|c(%x%x%x%x%x%x%x%x)")

        -- Si le lien n'a pas de couleur (ex: lien brut sans |c...|r),
        -- on tente de récupérer la qualité de l'INSTANCE via GetItemInfo(link)
        -- (la qualité par itemID peut être différente/verte pour des objets upgradés)
        local qi = nil
        if not colorFromLink and GetItemInfo then
            local _, _, q2 = GetItemInfo(link)
            qi = tonumber(q2)
        end

        -- Déterminer un préfixe couleur WoW valide ("|cffRRGGBB") pour la rareté
        local function qualityPrefix(qq)
            -- Tableau standard (contient déjà un hex complet avec "|c")
            if ITEM_QUALITY_COLORS and qq and ITEM_QUALITY_COLORS[qq] and ITEM_QUALITY_COLORS[qq].hex then
                return ITEM_QUALITY_COLORS[qq].hex -- ex: "|cffa335ee"
            end
            return nil
        end

        -- Priorité: couleur provenant du lien (plus fiable pour la rareté effective)
        local hex = nil
        if colorFromLink then
            hex = "|c" .. colorFromLink
        else
            -- Essaye d'abord la qualité spécifique à ce lien (qi), sinon fallback ID
            hex = qualityPrefix(qi) or qualityPrefix(q)
        end

        -- Icône: déjà tenté via C_Item.GetItemIconByID; rien à faire si manquante
        if iconTex and w.item.icon then
            w.item.icon:SetTexture(iconTex)
        end

        -- Texte final: nom si connu, sinon nom extrait du lien; couleur = hex (ou blanc si vraiment rien)
        local nameTxt = nameFromLink or ""
        local prefix = (type(hex) == "string" and hex:match("^|c")) and hex or "|cffffffff"
        local suffix = "|r"
        if w.item.text then
            w.item.text:SetText(prefix .. nameTxt .. suffix)
        end
        if w.item.btn then
            w.item.btn._link = link
        end

        -- Si ni couleur ni qualité n'étaient disponibles, programme un recolor léger
        if not colorFromLink and (not qi and not q) and C_Timer and C_Timer.After then
            if lv and not lv._lootRecolorScheduled then
                lv._lootRecolorScheduled = true
                C_Timer.After(0.25, function()
                    if lv and lv.UpdateVisibleRows then lv:UpdateVisibleRows() end
                    lv._lootRecolorScheduled = false
                end)
            end
        end
    end

    -- Qui + icône de roll si connue
    if w.who then UI.SetNameTagShort(w.who, it.looter or "") end
    if w.rollTex and w.rollBtn then
        if it.roll and UI.SetRollIcon then
            UI.SetRollIcon(w.rollTex, it.roll)
            w.rollBtn._rollType = it.roll
            w.rollBtn._rollVal  = tonumber(it.rollV or 0) or nil
            w.rollBtn:Show()
        else
            w.rollBtn._rollType, w.rollBtn._rollVal = nil, nil
            w.rollBtn:Hide()
        end
    end

    -- Instance (depuis instID → nom) ; si diffID==0 → "Extérieur"
    if w.inst then
        local instID = tonumber(it.instID or 0) or 0
        local diffID = tonumber(it.diffID or 0) or 0
        local instName
        if diffID == 0 then
            instName = (Tr and Tr("instance_outdoor")) or "Outdoor"
        else
            instName = (GLOG and GLOG.ResolveInstanceName and GLOG.ResolveInstanceName(instID)) or ""
        end
        w.inst:SetText(instName or "")
    end

    -- Difficulté (+ niveau de clé M+) depuis diffID, avec fallback dynamique
    if w.diff then
        local diffID = tonumber(it.diffID or 0) or 0
        if diffID == 0 then
            -- hors instance : tiret demandé
            w.diff:SetText(Tr("value_dash") or "-")
        else
            local parts = {}
            local diff = (GetDifficultyInfo and GetDifficultyInfo(diffID)) or ""
            if diff and diff ~= "" then parts[#parts+1] = diff end

            local mplus = tonumber(it.mplus or 0) or 0
            if (mplus == 0) and (diffID == 8) and GLOG and GLOG.GetActiveKeystoneLevel then
                local live = tonumber(GLOG.GetActiveKeystoneLevel()) or 0
                if live > 0 then mplus = live end
            end
            -- Ne pas afficher "+X" pour les gouffres (diffID == 208)
            if ((mplus > 0) or (diffID == 8)) and (diffID ~= 208) then
                parts[#parts+1] = (mplus > 0) and ("|cffffa500+"..mplus.."|r") or "+|cffffa500?|r"
            end

            w.diff:SetText(#parts > 0 and table.concat(parts, " ") or Tr("value_dash") or "-")
        end
    end

    -- (Affichage texte roll supprimé, l'icône reste sur le pseudo)

    -- Bouton Groupe -> affiche la liste des membres (et montre le nombre)
    if w.grpBtn and w.grpBtn.SetScript then
        local members = it.group or {}
        local n = #members
        if w.grpBtn.SetText then w.grpBtn:SetText(tostring(n)) end
        if w.grpBtn.SetEnabled then w.grpBtn:SetEnabled(n > 0) end
        if w.grpBtn.SetTooltip then
            w.grpBtn:SetTooltip(((Tr and Tr("tip_show_group")) or "Voir le groupe") .. " ("..n..")")
        end
        w.grpBtn:SetScript("OnClick", function()
            if n > 0 then UI.ShowParticipants2Popup(members) end
        end)
    end

    -- Supprimer
    if w.del and w.del.SetScript then
        w.del:SetScript("OnClick", function()
            UI.PopupConfirm(Tr("lbl_delete_confirm") or (Tr("confirm_delete") or "Supprimer cette ligne ?"), function()
                if GLOG and GLOG.LootTracker_Delete then GLOG.LootTracker_Delete(i) end
            end, nil, { strata = "FULLSCREEN_DIALOG" })
        end)
    end
end

-- =========================
--       Build / Refresh
-- =========================
local function Build(container)
    -- Conteneur standard (footer inutile ici)
    panel = UI.CreateMainContainer(container, { footer = false })

    local y = 0
    y = y + (UI.SectionHeader(panel, Tr("tab_loot_tracker_settings"), { topPad = y }) or (UI.SECTION_HEADER_H or 26)) + 8

        -- === Barre de paramètres de log (session → persistant dans Datas_Char.config) ===
    local function _Cfg()
        GuildLogisticsDatas_Char = GuildLogisticsDatas_Char or {}
        GuildLogisticsDatas_Char.config = GuildLogisticsDatas_Char.config or {}
        local c = GuildLogisticsDatas_Char.config
        -- Défauts alignés avec Core/LootTracker.lua
        local EPIC = (Enum and Enum.ItemQuality and Enum.ItemQuality.Epic) or 4
        if c.lootMinQuality     == nil then c.lootMinQuality     = EPIC end
        if c.lootMinReqLevel    == nil then c.lootMinReqLevel    = 80 end
        if c.lootEquippableOnly == nil then c.lootEquippableOnly = true end
        if c.lootMinItemLevel   == nil then c.lootMinItemLevel   = 0 end
        if c.lootInstanceOnly   == nil then c.lootInstanceOnly   = true end
        return c
    end
    local cfg = _Cfg()

    -- Conteneur de la barre
    local bar = CreateFrame("Frame", nil, panel)
    bar:SetPoint("TOPLEFT",  panel, "TOPLEFT",  UI.OUTER_PAD, -(y))
    bar:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -UI.OUTER_PAD, -(y))
    bar:SetHeight(20)

    -- Libellés utilitaires
    local function label(parent, txt)
        local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        fs:SetText(txt)
        fs:SetJustifyH("LEFT")
        return fs
    end

    -- 1) Dropdown "Rareté minimale"
    local qLbl = label(bar, (Tr and Tr("lbl_min_quality")) or "Rareté minimale")
    qLbl:SetPoint("LEFT", bar, "LEFT", 0, 0)

    local ddName = "GLOG_LootMinQualityDD_" .. tostring(math.random(100000,999999))
    local dd = CreateFrame("Frame", ddName, bar, "UIDropDownMenuTemplate")
    dd:SetPoint("LEFT", qLbl, "RIGHT", 0, -2)
    UIDropDownMenu_SetWidth(dd, 140)

    local qualities = { 0,1,2,3,4,5,6 }
    local function qualityText(q)
        local name = _G["ITEM_QUALITY"..q.."_DESC"] or tostring(q)
        return name
    end
    local function setQuality(q)
        cfg.lootMinQuality = tonumber(q) or cfg.lootMinQuality
        UIDropDownMenu_SetText(dd, qualityText(cfg.lootMinQuality))
    end
    UIDropDownMenu_Initialize(dd, function(self, level)
        for _, q in ipairs(qualities) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = qualityText(q)
            info.checked = (tonumber(cfg.lootMinQuality) == q)
            info.func = function() setQuality(q); CloseDropDownMenus() end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetText(dd, qualityText(cfg.lootMinQuality))
    if UI and UI.AttachDropdownZFix then UI.AttachDropdownZFix(dd, panel) end

       -- 2) Checkbox "Seulement en instance/gouffre" (sur la 1ère ligne, après la rareté)
    local cbInst = CreateFrame("CheckButton", nil, bar, "ChatConfigCheckButtonTemplate")
    cbInst.Text:SetText(Tr("lbl_instance_only") or "Seulement en instance/gouffre")
    cbInst:SetPoint("LEFT", dd, "RIGHT", 18, 2)
    cbInst:SetChecked((cfg.lootInstanceOnly ~= false) and true or false)
    cbInst:SetScript("OnClick", function(self)
        cfg.lootInstanceOnly = self:GetChecked() and true or false
    end)

    -- 3) 2ème ligne : Équippable uniquement > lvl mini > ilvl mini
    --    On déclare en avance pour le rafraîchissement d'état
    local lvLbl, lvBox, ilvlLbl, ilvlBox

    -- Fonction d'état : désactive lvl/ilvl si "Équippable uniquement" est décoché
    local function _RefreshEquipFiltersState()
        local enabled = (cfg.lootEquippableOnly ~= false)

        if lvBox then
            if lvBox.SetEnabled then lvBox:SetEnabled(enabled) end
            lvBox:SetAlpha(enabled and 1 or 0.5)
            if not enabled then lvBox:ClearFocus() end
        end
        if lvLbl and lvLbl.SetAlpha then lvLbl:SetAlpha(enabled and 1 or 0.5) end

        if ilvlBox then
            if ilvlBox.SetEnabled then ilvlBox:SetEnabled(enabled) end
            ilvlBox:SetAlpha(enabled and 1 or 0.5)
            if not enabled then ilvlBox:ClearFocus() end
        end
        if ilvlLbl and ilvlLbl.SetAlpha then ilvlLbl:SetAlpha(enabled and 1 or 0.5) end
    end

    -- 3.1) Checkbox "Équippable uniquement" (début 2ème ligne)
    local cb = CreateFrame("CheckButton", nil, bar, "ChatConfigCheckButtonTemplate")
    cb.Text:SetText(Tr("lbl_equippable_only") or "Équippable uniquement")
    cb:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, -36)
    cb:SetChecked(cfg.lootEquippableOnly and true or false)
    cb:SetScript("OnClick", function(self)
        cfg.lootEquippableOnly = self:GetChecked() and true or false
        _RefreshEquipFiltersState()
    end)

    -- 3.2) Champ "Niveau requis minimal"
    lvLbl = label(bar, (Tr and Tr("lbl_min_req_level")))
    lvLbl:SetPoint("LEFT", cb, "RIGHT", 180, 2)

    lvBox = CreateFrame("EditBox", nil, bar, "InputBoxTemplate")
    lvBox:SetAutoFocus(false)
    lvBox:SetNumeric(true)
    lvBox:SetNumber(tonumber(cfg.lootMinReqLevel or 0) or 0)
    lvBox:SetSize(60, 20)
    lvBox:SetPoint("LEFT", lvLbl, "RIGHT", 8, 0)
    lvBox:SetScript("OnEnterPressed", function(self)
        cfg.lootMinReqLevel = tonumber(self:GetNumber() or 0) or 0
        self:ClearFocus()
    end)
    lvBox:SetScript("OnEditFocusLost", function(self)
        cfg.lootMinReqLevel = tonumber(self:GetNumber() or 0) or 0
    end)

    -- 3.3) Champ "Ilvl minimum"
    ilvlLbl = label(bar, (Tr and Tr("lbl_min_item_level")))
    ilvlLbl:SetPoint("LEFT", lvBox, "RIGHT", 40, 0)

    ilvlBox = CreateFrame("EditBox", nil, bar, "InputBoxTemplate")
    ilvlBox:SetAutoFocus(false)
    ilvlBox:SetNumeric(true)
    ilvlBox:SetNumber(tonumber(cfg.lootMinItemLevel or 0) or 0)
    ilvlBox:SetSize(60, 20)
    ilvlBox:SetPoint("LEFT", ilvlLbl, "RIGHT", 8, 0)
    ilvlBox:SetScript("OnEnterPressed", function(self)
        cfg.lootMinItemLevel = tonumber(self:GetNumber() or 0) or 0
        self:ClearFocus()
    end)
    ilvlBox:SetScript("OnEditFocusLost", function(self)
        cfg.lootMinItemLevel = tonumber(self:GetNumber() or 0) or 0
    end)

    -- État initial (désactive lvl/ilvl si nécessaire)
    _RefreshEquipFiltersState()

    -- Ajuster la hauteur utilisée par la barre (+ marge) - 2 lignes
    y = y + 70 + PAD
    y = y + (UI.SectionHeader(panel, Tr("tab_loot_tracker"), { topPad = y }) or (UI.SECTION_HEADER_H or 26)) + 8


    local cols = UI.NormalizeColumns({
        { key="date",   title=Tr("col_time")       or "Heure",       w=120 },
        { key="ilvl",   title=Tr("col_ilvl")       or "iLvl",        vsep=true,  w=40, justify="CENTER" },
        { key="item",   title=Tr("col_item")       or "Objet",       vsep=true,  min=300, flex=1 },
        { key="who",    title=Tr("col_who")        or "Ramassé par", vsep=true,  w=180 },
        { key="inst",   title=Tr("col_instance")   or "Instance",    vsep=true,  w=220},
        { key="diff",   title=Tr("col_difficulty") or "Difficulté",  vsep=true,  min=125,  justify="CENTER" },
        { key="grp",    title=Tr("col_group")      or "Groupe",      vsep=true,  w=60,  justify="CENTER" },
        { key="close",  title="X", min=30,  vsep=true,justify="CENTER" },
    })

    -- Zone de liste dédiée, ancrée sous la barre de filtres
    listArea = CreateFrame("Frame", nil, panel)
    listArea:SetPoint("TOPLEFT",  panel, "TOPLEFT",  0, -y)
    listArea:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -y)
    listArea:SetPoint("BOTTOMLEFT",  panel, "BOTTOMLEFT",  0, 0)
    listArea:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)

    -- La ListView vit dans listArea → plus de chevauchement
    lv = UI.ListView(listArea, cols, {
        topOffset = 0,
        buildRow  = function(row) return BuildRow(row) end,
        updateRow = function(i, row, w, it) return UpdateRow(i, row, w, it) end,
    })
end

local function Refresh()
    if not lv then return end
    local list = {}
    if GLOG and GLOG.LootTracker_List then
        for _, it in ipairs(GLOG.LootTracker_List()) do 
            list[#list+1] = it
        end
    end
    lv:RefreshData(list)
end

local function Layout() end

UI.RegisterTab(Tr("tab_loot_tracker") or "Loots équipables", Build, Refresh, Layout, {
    category = Tr("cat_tracker") or "Tracker",
})
