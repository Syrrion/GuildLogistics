local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns.GLOG, ns.UI

local PAD = (UI and UI.OUTER_PAD) or 16
local panel, lv, btnAdd

-- ===== Helpers =====
local function _Summary(col)
    local s = tonumber(#(col.spellIDs or {})) or 0
    local i = tonumber(#(col.itemIDs  or {})) or 0
    local k = tonumber(#(col.keywords or {})) or 0
    local parts = {}
    table.insert(parts, string.format("%s: %d", Tr("lbl_items") or "Objets", i))
    table.insert(parts, string.format("%s: %d", Tr("lbl_spells") or "Sorts", s))
    table.insert(parts, string.format("%s: %d", Tr("lbl_keywords") or "Clés", k))
    return table.concat(parts, " • ")
end

local function ShowEditColumnPopup(existing)
    local dlg = UI.CreatePopup({ title = Tr("custom_edit_column") or "Éditer la colonne", width = 660, height = 560 })
    local y = 15

    local function addLabel(text, dy)
        local fs = dlg.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetPoint("TOPLEFT", dlg.content, "TOPLEFT", 0, -y)
        fs:SetText(text)
        y = y + (dy or 22)
        return fs
    end
    local function addEditBox(initial, height)
        local box = CreateFrame("EditBox", nil, dlg.content, "BackdropTemplate")
        box:SetMultiLine(false)
        box:SetAutoFocus(false)
        box:SetFontObject("GameFontHighlight")
        box:SetPoint("TOPLEFT", dlg.content, "TOPLEFT", 0, -y)
        box:SetSize(600, height or 24)
        box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
        box:SetBackdropColor(0,0,0,0.35)
        box:SetText(tostring(initial or ""))
        y = y + (height or 24) + 12
        return box
    end
    local function addCheck(initial, label)
        local cb = CreateFrame("CheckButton", nil, dlg.content, "ChatConfigCheckButtonTemplate")
        cb:SetPoint("TOPLEFT", dlg.content, "TOPLEFT", -4, -y)
        cb.Text:SetText(label)
        cb:SetChecked(initial and true or false)
        y = y + 24
        return cb
    end

    -- Libellé
    addLabel(Tr("custom_col_label") or "Libellé")
    local boxLabel = addEditBox(existing and existing.label or "", 24)

    -- Dropdown système (UIDropDownMenu)
    addLabel(Tr("custom_select_type") or "Type d’éléments")
    local ddName = "GLOG_CustomTypeDD_"..tostring(math.random(100000,999999))
    local dd = CreateFrame("Frame", ddName, dlg.content, "UIDropDownMenuTemplate")
    -- Alignement standard: décroche un peu à gauche (template Blizzard)
    dd:SetPoint("TOPLEFT", dlg.content, "TOPLEFT", -16, -y)
    UIDropDownMenu_SetWidth(dd, 220)

    local kinds = {
        { value="item",  text = Tr("type_items") or "Objets" },
        { value="spell", text = Tr("type_spells") or "Sorts" },
        { value="text",  text = Tr("type_keywords") or "Mots-clés" },
    }
    local currentKind = "spell"

    local function LabelFor(kind)
        for _, k in ipairs(kinds) do if k.value == kind then return k.text end end
        return tostring(kind)
    end
    local function SetKind(kind)
        currentKind = kind
        UIDropDownMenu_SetText(dd, LabelFor(kind))
        -- Afficher/masquer la bonne liste
        listSpells:Hide(); listItems:Hide(); listKeys:Hide()
        if     kind == "spell" then listSpells:Show()
        elseif kind == "item"  then listItems:Show()
        else                        listKeys:Show()
        end
    end

    UIDropDownMenu_Initialize(dd, function(self, level)
        for _, k in ipairs(kinds) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = k.text
            info.checked = (currentKind == k.value)
            info.func = function()
                SetKind(k.value)
                CloseDropDownMenus()
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    -- Fix Z-order via outil existant
    if UI and UI.AttachDropdownZFix then UI.AttachDropdownZFix(dd, dlg) end
    y = y + 24 + 10

    -- Zone plein écran pour la liste (une seule visible à la fois)
    local LIST_W, LIST_H = 600, 260

    -- ⚠️ Déclarées ici car SetKind les référence
    listSpells = UI.TokenList(dlg.content, {
        type = "spell", width = LIST_W, height = LIST_H,
        placeholder = Tr("placeholder_spell") or "ID ou lien de sort (Maj+Clic pour coller un lien)",
    })
    listSpells:SetPoint("TOPLEFT", dlg.content, "TOPLEFT", 0, -y)

    listItems = UI.TokenList(dlg.content, {
        type = "item", width = LIST_W, height = LIST_H,
        placeholder = Tr("placeholder_item") or "ID ou lien d'objet (Maj+Clic pour coller un lien)",
    })
    listItems:SetPoint("TOPLEFT", dlg.content, "TOPLEFT", 0, -y)

    listKeys = UI.TokenList(dlg.content, {
        type = "text", width = LIST_W, height = LIST_H,
        placeholder = Tr("placeholder_keyword") or "Mot-clé (puis Entrée)",
    })
    listKeys:SetPoint("TOPLEFT", dlg.content, "TOPLEFT", 0, -y)

    y = y + LIST_H + 12

    -- Pré-remplissage
    if existing then
        listSpells:SetValues(existing.spellIDs or {})
        listItems:SetValues(existing.itemIDs  or {})
        listKeys:SetValues (existing.keywords or {})
    end

    -- Valeur par défaut + affichage initial
    SetKind("spell")

    dlg:SetButtons({
        { text = Tr("btn_confirm") or "Valider", default = true, onClick = function()
            local obj = {
                id          = existing and existing.id or nil,
                label       = boxLabel:GetText() or "",
                spellIDs    = listSpells:GetValues(),
                itemIDs     = listItems:GetValues(),
                keywords    = listKeys:GetValues(),
                -- Pas de contrôle dans la popup : on préserve l’état existant (par défaut: activé)
                enabled     = (existing and existing.enabled == false) and false or true,
                -- 🔒 conserve le mode cooldown invisible si présent (pour les 3 listes par défaut)
                cooldownCat = existing and existing.cooldownCat or nil,
            }

            if obj.label == "" then
                if UI.Toast then UI.Toast("|cffff6060"..(Tr("err_label_required") or "Libellé requis").."|r") end
                return
            end
            if GLOG and GLOG.GroupTracker_Custom_AddOrUpdate then
                GLOG.GroupTracker_Custom_AddOrUpdate(obj)
            end
            dlg:Hide()
            if ns and ns.RefreshAll then ns.RefreshAll() end
        end },
        { text = Tr("btn_cancel") or "Annuler", variant="ghost" },
    })
    dlg:Show()
end



local function Build(container)
    panel = UI.CreateMainContainer(container, { footer = false })

    local y = 0
    y = y + (UI.SectionHeader(panel, Tr("tab_custom_tracker") or "Suivi personnalisé", { topPad = y }) or 26) + 8

    btnAdd = UI.Button(panel, Tr("custom_add_column") or "Ajouter une colonne", { size="md", minWidth=220 })
    btnAdd:SetPoint("TOPLEFT", panel, "TOPLEFT", PAD, -(y))
    btnAdd:SetOnClick(function() ShowEditColumnPopup(nil) end)
    y = y + 28

    local cols = UI.NormalizeColumns({
        { key="label",  title=Tr("custom_col_label") or "Libellé",         min=180, flex=1 },
        { key="rules",  title=Tr("custom_col_mappings") or "Règles",       vsep=true,  min=280, flex=2 },
        { key="active", title=Tr("custom_col_active") or "Actif",          vsep=true,  w=70, justify="CENTER" },
        { key="act",    title="",                                          vsep=true,  w=240, justify="CENTER" },
    })


    lv = UI.ListView(panel, cols, {
        topOffset = y,
        buildRow = function(r)
            local w = {}
            w.label  = UI.Label(r, { justify="LEFT" })
            w.rules  = UI.Label(r, { justify="LEFT" })
            
            -- Hôte de cellule + checkbox centrée
            w.active = CreateFrame("Frame", nil, r)
            w.active.cb = CreateFrame("CheckButton", nil, w.active, "ChatConfigCheckButtonTemplate")
            w.active.cb:SetPoint("CENTER", w.active, "CENTER", 0, 0)
            -- On supprime le texte natif de la checkbox (inutile en cellule)
            if w.active.cb.Text then w.active.cb.Text:SetText("") end
            -- Zone cliquable un peu plus large pour le confort
            if w.active.cb.SetHitRectInsets then w.active.cb:SetHitRectInsets(-6, -6, -6, -6) end

            w.act    = CreateFrame("Frame", nil, r)

            w.btnUp   = UI.Button(w.act, Tr("btn_up") or "Up",       { size="xs", minWidth=26, padX=8, variant="ghost", tooltip = Tr("tooltip_move_up") or (Tr("btn_up") or "Monter") })
            w.btnDown = UI.Button(w.act, Tr("btn_down") or "Down",   { size="xs", minWidth=26, padX=8, variant="ghost", tooltip = Tr("tooltip_move_down") or "Descendre" })
            w.btnEdit = UI.Button(w.act, Tr("btn_edit") or "Éditer", { size="sm", minWidth=68 })
            w.btnDel  = UI.Button(w.act, Tr("btn_delete") or "Supprimer", { size="sm", variant="danger", minWidth=68 })

            if UI.AttachRowRight then
                -- Ordre des actions : ↑ ↓ Éditer Supprimer
                UI.AttachRowRight(w.act, { w.btnUp, w.btnDown, w.btnEdit, w.btnDel }, 10, 0, { align="center" })
            end
            return w
        end,
        updateRow = function(i, r, w, it)
            if not it then return end
            w.label:SetText(tostring(it.label or ""))
            w.rules:SetText(_Summary(it))
            -- État de la case selon la donnée
            local checked = (it.enabled ~= false)
            if w.active and w.active.cb and w.active.cb.SetChecked then
                w.active.cb:SetChecked(checked)
                -- Toggle direct : persiste via l’API existante
                w.active.cb:SetScript("OnClick", function(self)
                    local newObj = {
                        id          = it.id,
                        label       = it.label,
                        spellIDs    = it.spellIDs,
                        itemIDs     = it.itemIDs,
                        keywords    = it.keywords,
                        cooldownCat = it.cooldownCat,
                        enabled     = self:GetChecked() and true or false,
                    }
                    if GLOG and GLOG.GroupTracker_Custom_AddOrUpdate then
                        GLOG.GroupTracker_Custom_AddOrUpdate(newObj)
                    end
                    if ns and ns.RefreshAll then ns.RefreshAll() end
                end)
            end

            if w.btnEdit and w.btnEdit.SetOnClick then
                w.btnEdit:SetOnClick(function() ShowEditColumnPopup(it) end)
            end

            if w.btnDel and w.btnDel.SetOnClick then
                w.btnDel:SetOnClick(function()
                    local msg = string.format(Tr("custom_confirm_delete") or "Supprimer la colonne '%s' ?", tostring(it.label or ""))
                    if UI and UI.PopupConfirm then
                        UI.PopupConfirm(msg, function()
                            if GLOG and GLOG.GroupTracker_Custom_Delete then
                                GLOG.GroupTracker_Custom_Delete(it.id)
                            end
                            if ns and ns.RefreshAll then ns.RefreshAll() end
                        end)
                    end
                end)
            end
            -- ↑ / ↓ : déplacement dans la liste
            if w.btnUp and w.btnUp.SetOnClick then
                w.btnUp:SetOnClick(function()
                    if GLOG and GLOG.GroupTracker_Custom_Move then
                        GLOG.GroupTracker_Custom_Move(it.id, -1)
                    end
                    if ns and ns.RefreshAll then ns.RefreshAll() end
                end)
            end
            if w.btnDown and w.btnDown.SetOnClick then
                w.btnDown:SetOnClick(function()
                    if GLOG and GLOG.GroupTracker_Custom_Move then
                        GLOG.GroupTracker_Custom_Move(it.id, 1)
                    end
                    if ns and ns.RefreshAll then ns.RefreshAll() end
                end)
            end

            -- Désactivation des flèches aux bornes
            local total = 0
            if GLOG and GLOG.GroupTracker_Custom_List then
                for _ in ipairs(GLOG.GroupTracker_Custom_List()) do total = total + 1 end
            end
            if w.btnUp   and w.btnUp.SetEnabled   then w.btnUp:SetEnabled(i > 1) end
            if w.btnDown and w.btnDown.SetEnabled then w.btnDown:SetEnabled(i < total) end

        end,
    })
end

local function Refresh()
    if not lv then return end
    local list = {}
    if GLOG and GLOG.GroupTracker_Custom_List then
        for _, it in ipairs(GLOG.GroupTracker_Custom_List()) do list[#list+1] = it end
    end
    lv:RefreshData(list)
end

local function Layout() end

UI.RegisterTab(Tr("tab_custom_tracker") or "Suivi personnalisé", Build, Refresh, Layout, {
    category = Tr("cat_tracker"),
})
