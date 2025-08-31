local ADDON, ns = ...
local Tr  = ns and ns.Tr
local GLOG, UI = ns.GLOG, ns.UI

local PAD = (UI and UI.OUTER_PAD) or 8

local panel, lv

-- Affichage des membres du groupe : on réutilise la popup roster de l'onglet "Historique des raids" si elle existe
local function ShowGroupMembers(anchor, members)
    members = members or {}
    local title = (Tr and Tr("popup_group_title")) or "Membres du groupe"

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
        { key="idx",  title="#",    w=24,  align="CENTER" },
        { key="name", title=Tr and Tr("col_name") or "Nom", min=200, flex=1 },
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

    -- Qui (ramassé par)
    w.who = UI.CreateNameTag and UI.CreateNameTag(row) or row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    if w.who.SetJustifyH then w.who:SetJustifyH("LEFT") end

    w.inst = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    w.inst:SetJustifyH("LEFT")

    w.diff = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    w.diff:SetJustifyH("LEFT")

    -- Colonne "Groupe" (bouton avec nombre de membres)
    w.grp = CreateFrame("Frame", nil, row)
    w.grp:SetHeight(UI.ROW_H)

    w.grpBtn = (UI.Button and UI.Button(w.grp, "0", {
        size="xs", variant="secondary", minWidth=28,
        tooltip = (Tr and Tr("tip_show_group")) or "Voir le groupe"
    })) or CreateFrame("Button", nil, w.grp, "UIPanelButtonTemplate")

    if w.grpBtn.SetText then w.grpBtn:SetText("0") end
    w.grpBtn:ClearAllPoints()
    w.grpBtn:SetPoint("CENTER", w.grp, "CENTER", 0, 0)

    -- Colonne supprimer
    w.close = CreateFrame("Frame", nil, row)
    w.close:SetHeight(UI.ROW_H)

    w.del = (UI.Button and UI.Button(w.close, "X", { size="xs", variant="danger", minWidth=24,
        tooltip = Tr("btn_delete") or (Tr("confirm_delete") or "Supprimer")
    })) or CreateFrame("Button", nil, w.close, "UIPanelButtonTemplate")

    -- Assure l'affichage et l'ancrage dans la cellule
    if w.del.SetText then w.del:SetText("X") end
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
        w.ilvl:SetText(iv > 0 and tostring(iv) or "-")
    end

    -- Objet (icône, texte + tooltip) coloré selon la rareté (sans stocker la qualité)
    if w.item then
        local link = it.link or ""
        local name, _, quality, _, _, _, _, _, _, iconTex = GetItemInfo(link)
        local q = tonumber(quality)  -- peut être nil si l'item n'est pas en cache

        -- Fallback qualité via itemID si GetItemInfo n'est pas prêt
        if not q and C_Item and C_Item.GetItemQualityByID then
            local itemID = link:match("|Hitem:(%d+):")
            if itemID then
                q = tonumber(C_Item.GetItemQualityByID(tonumber(itemID)))
            end
        end

        -- Déterminer la couleur
        local function qualityHex(qq)
            if C_QualityColors and C_QualityColors.GetQualityColor and qq then
                local c = C_QualityColors.GetQualityColor(qq)
                if c and c.GenerateHexColor then return c:GenerateHexColor() end
            end
            if ITEM_QUALITY_COLORS and qq and ITEM_QUALITY_COLORS[qq] and ITEM_QUALITY_COLORS[qq].hex then
                return ITEM_QUALITY_COLORS[qq].hex
            end
            return nil
        end

        local hex = qualityHex(q)

        -- Si on n'a toujours pas de couleur/qualité, on utilise la couleur directement contenue dans le lien
        -- (ex: |cffa335ee|Hitem:...|h[Nom]|h|r) → a335ee = épique (violet)
        local nameFromLink = link:match("%[(.-)%]") or link
        local colorFromLink = link:match("|c(%x%x%x%x%x%x%x%x)")
        if not hex and colorFromLink then
            hex = "|c" .. colorFromLink
        end

        -- Icône: fallback via itemID si besoin (synchrone)
        if (not iconTex or iconTex == 0) and GetItemIcon then
            local itemID = link:match("|Hitem:(%d+):")
            if itemID then
                iconTex = GetItemIcon(tonumber(itemID))
            end
        end
        if iconTex and w.item.icon then
            w.item.icon:SetTexture(iconTex)
        end

        -- Texte final: nom si connu, sinon nom extrait du lien; couleur = hex (ou blanc si vraiment rien)
        local nameTxt = name or nameFromLink or ""
        local prefix = hex or "|cffffffff"
        local suffix = "|r"
        if w.item.text then
            w.item.text:SetText(prefix .. nameTxt .. suffix)
        end
        if w.item.btn then
            w.item.btn._link = link
        end
    end

    -- Qui
    if w.who then UI.SetNameTagShort(w.who, it.looter or "") end

    -- Instance (depuis instID → nom), avec cast sûr
    if w.inst then
        local instID = tonumber(it.instID or 0) or 0
        local instName = GLOG.ResolveInstanceName(instID)
        w.inst:SetText(instName or "")
    end

    -- Difficulté (+ niveau de clé M+) depuis diffID, avec fallback dynamique
    if w.diff then
        local parts = {}
        local diffID = tonumber(it.diffID or 0) or 0
        local diff = (GetDifficultyInfo and GetDifficultyInfo(diffID)) or ""
        if diff and diff ~= "" then parts[#parts+1] = diff end

        local mplus = tonumber(it.mplus or 0) or 0
        if (mplus == 0) and (diffID == 8) and GLOG and GLOG.GetActiveKeystoneLevel then
            local live = tonumber(GLOG.GetActiveKeystoneLevel()) or 0
            if live > 0 then mplus = live end
        end

        if (mplus > 0) or (diffID == 8) then
            parts[#parts+1] = (mplus > 0) and ("|cffffa500+"..mplus.."|r") or "+|cffffa500?|r"
        end

        w.diff:SetText(#parts > 0 and table.concat(parts, " ") or "")
    end

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
    y = y + (UI.SectionHeader(panel, Tr("tab_loot_tracker") or "Loots épique+ (niv. requis ≥ joueur)", { topPad = y }) or (UI.SECTION_HEADER_H or 26)) + 8

    local cols = UI.NormalizeColumns({
        { key="date",   title=Tr("col_time")       or "Heure",       w=120 },
        { key="ilvl",   title=Tr("col_ilvl")       or "iLvl",        w=40, align="CENTER" },
        { key="item",   title=Tr("col_item")       or "Objet",       min=300, flex=1 },
        { key="who",    title=Tr("col_who")        or "Ramassé par", w=150 },
        { key="inst",   title=Tr("col_instance")   or "Instance",    w=250},
        { key="diff",   title=Tr("col_difficulty") or "Difficulté",  min=125 },
        { key="grp",    title=Tr("col_group")      or "Groupe",      w=60,  align="CENTER" },
        { key="close",  title="", min=30 },
    })

    lv = UI.ListView(panel, cols, {
        topOffset = (UI.SECTION_HEADER_H or 26),
        buildRow  = function(row) return BuildRow(row) end,
        updateRow = function(i, row, w, it) return UpdateRow(i, row, w, it) end,
    })
end

local function Refresh()
    if not lv or not lv.SetData then return end
    local list = {}
    if GLOG and GLOG.LootTracker_List then
        for _, it in ipairs(GLOG.LootTracker_List()) do
            list[#list+1] = it
        end
    end
    lv:SetData(list)
end

local function Layout() end

UI.RegisterTab(Tr("tab_loot_tracker") or "Loots équipables", Build, Refresh, Layout, {
    category = Tr("cat_tracker") or "Tracker",
})
