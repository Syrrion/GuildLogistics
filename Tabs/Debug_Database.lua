local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns.GLOG, ns.UI

-- =========================
-- =====   NAV STATE   =====
-- =========================
local panel, footer
local lv, breadcrumbFS, btnRoot, btnUp, backupInfoFS, ddRoot
local dbgInfoFS
local currentPath = {}  -- tableau de clés (strings ou numbers)
local Build, Refresh, Layout, UpdateRow, updateBackupInfo, refreshDropdown
-- Sélection par défaut: base partagée (GuildLogisticsShared)
local selectedRoot = "DB_SHARED"
local ddRoot

local function _GetRoot()
    -- Les alias de Core.lua (Core.lua) pointent les *\_Char* en runtime
    if selectedRoot == "DB_SHARED" then
        return GuildLogisticsShared or {}
    elseif selectedRoot == "DB_UI" then
        return GuildLogisticsUI_Char or {}
    elseif selectedRoot == "DB_DATAS" then
        return GuildLogisticsDatas_Char or {}
    elseif selectedRoot == "DB_BACKUP" then
        return GuildLogisticsDB_Backup or {}
    elseif selectedRoot == "DB_PREVIOUS" then
        return GuildLogisticsDB_Previous or {}
    end
    return GuildLogisticsDB_Char or GuildLogisticsDB or {}
end

local function _PathToText(path)
    local rootName
    
    if selectedRoot == "DB_SHARED" then
        rootName = "GuildLogisticsShared"
    elseif selectedRoot == "DB_UI" then
        rootName = "GuildLogisticsUI_Char"
    elseif selectedRoot == "DB_DATAS" then
        rootName = "GuildLogisticsDatas_Char"
    elseif selectedRoot == "DB_BACKUP" then
        rootName = "GuildLogisticsDB_Backup"
    elseif selectedRoot == "DB_PREVIOUS" then
        rootName = "GuildLogisticsDB_Previous"
    else
        rootName = "GuildLogisticsDB_Char"
    end
    local parts = { rootName }
    for i = 1, #path do
        parts[#parts+1] = tostring(path[i])
    end
    return table.concat(parts, ".")
end

-- Résout un chemin et retourne parent, key, value
local function _Resolve(path)
    local root = _GetRoot()
    if #path == 0 then return nil, nil, root end
    local parent = root
    for i = 1, #path - 1 do
        parent = (type(parent) == "table") and parent[path[i]] or nil
        if parent == nil then return nil, nil, nil end
    end
    local k = path[#path]
    local val = (type(parent) == "table") and parent[k] or nil
    return parent, k, val
end

local function _SortedKeys(t)
    if type(t) ~= "table" then return {} end
    local isArray, n = (GLOG.IsArrayTable and GLOG.IsArrayTable(t)) or false, 0
    if isArray then
        local out = {}
        for i = 1, #t do out[i] = i end
        return out
    end
    local keys = {}
    for k in pairs(t) do keys[#keys+1] = k end
    table.sort(keys, function(a,b) return tostring(a) < tostring(b) end)
    return keys
end

-- =========================
-- =====   LISTVIEW    =====
-- =========================
local cols = UI.NormalizeColumns({
    { key="key",   title=Tr("col_key") or "Clé",        min=120, flex=0.5 },
    { key="type",  title=Tr("col_type") or "Type",      vsep=true,  w=100 },
    { key="prev",  title=Tr("col_preview") or "Aperçu", vsep=true,  min=220, flex=1.2 },
    { key="act",   title="",                             vsep=true,  w=160 },
})

local function BuildRow(r)
    local f = {}
    f.key  = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.type = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.prev = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.act  = CreateFrame("Frame", nil, r); f.act:SetHeight(UI.ROW_H)
    r.btnOpen  = UI.Button(f.act, Tr("btn_open") or "Ouvrir", { size="sm", minWidth=70 })
    r.btnEdit  = UI.Button(f.act, Tr("btn_edit") or "Éditer", { size="sm", minWidth=70 })
    r.btnDel   = UI.Button(f.act, Tr("btn_delete") or "Supprimer", { size="sm", variant="ghost", minWidth=90 })
    UI.AttachRowRight(f.act, { r.btnOpen, r.btnEdit, r.btnDel }, 6, -4, { leftPad=8, align="center" })
    return f
end

-- Petit helper d'aperçu
local function _Preview(val)
    local t = type(val)
    if t == "table" then
        local count = (GLOG.TableKeyCount and GLOG.TableKeyCount(val)) or 0
        return "{...} ("..count..")"
    elseif t == "string" then
        local s = val:gsub("\n"," "):gsub("\r","")
        if #s > 60 then s = s:sub(1,57) .. "..." end
        return string.format("%q", s)
    else
        return tostring(val)
    end
end

-- Popup d'édition pour scalaires + littéraux Lua
local function ShowEditPopup(parent, key, value, onSave)
    local dlg = UI.CreatePopup({ title = Tr("popup_edit_value") or "Éditer la valeur", width=560, height=340 })
    local lab = dlg.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lab:SetPoint("TOPLEFT", dlg.content, "TOPLEFT", 0, 0)
    lab:SetText((Tr("lbl_edit_path") or "Chemin : ") .. _PathToText(currentPath) .. (key and ("."..tostring(key)) or ""))

    local box = CreateFrame("EditBox", nil, dlg.content, "BackdropTemplate")
    box:SetMultiLine(true); box:SetAutoFocus(true)
    box:SetFontObject("GameFontHighlight")
    box:SetPoint("TOPLEFT",  dlg.content, "TOPLEFT", 0, -18)
    box:SetPoint("BOTTOMRIGHT", dlg.content, "BOTTOMRIGHT", 0, 40)
    box:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    box:SetBackdropColor(0,0,0,0.35)
    box:SetText((GLOG.SerializeLua and GLOG.SerializeLua(value)) or tostring(value))

    local hint = dlg.content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", dlg.content, "BOTTOMLEFT", 0, 0)
    hint:SetText(Tr("lbl_lua_hint") or "Entrez un littéral Lua : 123, true, \"text\", { a = 1 }")

    dlg:SetButtons({
        { text = Tr("btn_confirm"), default = true, onClick = function()
            local txt = box:GetText() or ""
            local okV, newV, err
            if GLOG.DeserializeLua then
                newV, err = GLOG.DeserializeLua(txt)
            else
                okV, newV = true, txt
            end
            if err then
                if UI.Toast then UI.Toast("|cffff6060Erreur :|r "..tostring(err)) end
                return
            end
            if onSave then onSave(newV) end
            dlg:Hide()  -- ferme la popup après sauvegarde
        end },
        { text = Tr("btn_cancel"), variant = "ghost" },
    })
    dlg:Show()
    return dlg
end

-- Popup d'ajout de champ (clé + valeur) sur le nœud courant
local function ShowAddFieldPopup()
    local dlg = UI.CreatePopup({ title = Tr("popup_add_field") or "Ajouter un champ", width = 560, height = 400 })

    local pathFS = dlg.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pathFS:SetPoint("TOPLEFT", dlg.content, "TOPLEFT", 0, 0)
    pathFS:SetText((Tr("lbl_edit_path") or "Chemin : ") .. _PathToText(currentPath))

    -- Libellés
    local labKey = dlg.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labKey:SetPoint("TOPLEFT", dlg.content, "TOPLEFT", 0, -20)
    labKey:SetText(Tr("lbl_key") or "Clé")

    local labVal = dlg.content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    labVal:SetPoint("TOPLEFT", dlg.content, "TOPLEFT", 0, -72)
    labVal:SetText(Tr("lbl_value") or "Valeur (littéral Lua)")

    -- Champ clé (une ligne)
    local keyBox = CreateFrame("EditBox", nil, dlg.content, "BackdropTemplate")
    keyBox:SetAutoFocus(true)
    keyBox:SetMultiLine(false)
    keyBox:SetFontObject("GameFontHighlight")
    keyBox:SetPoint("TOPLEFT",  dlg.content, "TOPLEFT", 0, -36)
    keyBox:SetPoint("RIGHT", dlg.content, "RIGHT", 0, 0)
    keyBox:SetHeight(24)
    keyBox:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    keyBox:SetBackdropColor(0,0,0,0.35)
    keyBox:SetText("")

    -- Champ valeur (multi-ligne, littéral Lua)
    local valBox = CreateFrame("EditBox", nil, dlg.content, "BackdropTemplate")
    valBox:SetMultiLine(true); valBox:SetAutoFocus(false)
    valBox:SetFontObject("GameFontHighlight")
    valBox:SetPoint("TOPLEFT",  dlg.content, "TOPLEFT", 0, -90)
    valBox:SetPoint("BOTTOMRIGHT", dlg.content, "BOTTOMRIGHT", 0, 40)
    valBox:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8" })
    valBox:SetBackdropColor(0,0,0,0.35)
    valBox:SetText("")

    local hint = dlg.content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", dlg.content, "BOTTOMLEFT", 0, 0)
    hint:SetText(Tr("lbl_lua_hint") or "Entrez un littéral Lua : 123, true, \"text\", { a = 1 }")

    dlg:SetButtons({
        { text = Tr("btn_confirm"), default = true, onClick = function()
            -- Récupère le nœud courant
            local node = select(3, _Resolve(currentPath))
            if type(node) ~= "table" then
                if UI.Toast then UI.Toast("|cffff6060"..(Tr("err_not_table") or "Le nœud courant n'est pas une table").."|r") end
                return
            end

            local keyTxt = (keyBox:GetText() or ""):gsub("^%s+",""):gsub("%s+$","")
            local valTxt = valBox:GetText() or ""

            -- Parse la valeur via littéral Lua
            local newVal, errV
            if GLOG.DeserializeLua then newVal, errV = GLOG.DeserializeLua(valTxt) else newVal = valTxt end
            if errV then
                if UI.Toast then UI.Toast("|cffff6060Erreur valeur :|r "..tostring(errV)) end
                return
            end

            local isArray = GLOG.IsArrayTable and select(1, GLOG.IsArrayTable(node))

            if isArray then
                -- Tableau : clé optionnelle numérique → insertion à l'index, sinon append
                local idx = tonumber(keyTxt)
                if idx and idx >= 1 and idx <= (#node + 1) then
                    table.insert(node, idx, newVal)
                else
                    node[#node+1] = newVal
                end
            else
                -- Table de hachage : clé requise (on accepte littéral Lua string/number, sinon brut)
                if keyTxt == "" then
                    if UI.Toast then UI.Toast("|cffff6060"..(Tr("err_need_key") or "Clé requise pour une table de hachage").."|r") end
                    return
                end
                local kParsed, errK
                if GLOG.DeserializeLua then kParsed, errK = GLOG.DeserializeLua(keyTxt) end
                local kFinal = (not errK and (type(kParsed)=="string" or type(kParsed)=="number")) and kParsed or keyTxt
                node[kFinal] = newVal
            end

            if UI.Toast then UI.Toast(Tr("lbl_saved") or "Enregistré") end
            dlg:Hide()
            if Refresh then Refresh() end
        end },
        { text = Tr("btn_cancel"), variant = "ghost" },
    })
    dlg:Show()
    return dlg
end


UpdateRow = function(i, r, f, it)
    -- Libellés
    f.key:SetText(tostring(it.key))
    f.type:SetText(tostring(it.type))
    f.prev:SetText(_Preview(it.value))

    -- État des actions + restrictions GM
    local isTbl = (type(it.value) == "table")
    local isGM  = (GLOG.IsGM and GLOG.IsGM()) or false

    r.btnOpen:SetShown(isTbl)                  -- visible seulement si table
    r.btnEdit:SetShown(isGM and not isTbl)              -- édition scalaire uniquement (inchangé)

    --r.btnDel:SetShown(isGM)

    -- Reflow (les shows/hides impactent le layout)
    if UI.AttachRowRight and f.act then
        UI.AttachRowRight(f.act, { r.btnOpen, r.btnEdit, r.btnDel }, 6, -4, { leftPad=8, align="center" })
    end

    -- Copie locale de la clé (les lignes sont recyclées)
    local k = it.key

    r.btnOpen:SetOnClick(function()
        if not isTbl then return end
        currentPath[#currentPath+1] = k
        if breadcrumbFS then breadcrumbFS:SetText(_PathToText(currentPath)) end
        Refresh()
    end)

    r.btnEdit:SetOnClick(function()
        if isTbl then return end
        -- ⚠️ On cible le NŒUD COURANT (3e valeur de _Resolve)
        local node = select(3, _Resolve(currentPath))
        if type(node) ~= "table" then return end
        local curVal = node[k]
        local dlg = ShowEditPopup(panel, k, curVal, function(newV)
            node[k] = newV
            if UI.Toast then UI.Toast(Tr("lbl_saved") or "Enregistré") end
            Refresh()
        end)
    end)

    r.btnDel:SetOnClick(function()
        UI.PopupConfirm(Tr("lbl_delete_confirm") or "Supprimer cet élément ?", function()
            -- ⚠️ On supprime dans le NŒUD COURANT (et pas dans son parent)
            local node = select(3, _Resolve(currentPath))
            if type(node) ~= "table" then return end
            local isArray = GLOG.IsArrayTable and select(1, GLOG.IsArrayTable(node))
            if isArray and type(k) == "number" then
                table.remove(node, k)
            else
                node[k] = nil
            end
            Refresh()
        end)
    end)
end

-- Datasource pour la LV : éléments immédiats du noeud courant
local function _BuildItems()
    local _, _, node = _Resolve(currentPath)
    if node == nil then return {} end

    if type(node) ~= "table" then
        return {
            { key = "(value)", type = type(node), value = node }
        }
    end

    local items = {}
    for _, k in ipairs(_SortedKeys(node)) do
        local v = node[k]
        local t = type(v)
        local ty
        if t == "table" then
            local cnt = (GLOG.TableKeyCount and GLOG.TableKeyCount(v)) or 0
            ty = "table("..cnt..")"
        else
            ty = t
        end
        table.insert(items, { key=k, type=ty, value=v })
    end
    return items
end

-- =========================
-- =====   BUILD/UI   ======
-- =========================
Build = function(container)
    panel, footer = UI.CreateMainContainer(container, { footer = true })

    -- Barre navigation (haut)
    local nav = CreateFrame("Frame", nil, panel)
    nav:SetHeight(26)
    nav:SetPoint("TOPLEFT",  panel, "TOPLEFT",  0, 6)
    nav:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 6)

    btnRoot = UI.Button(nav, Tr("btn_root") or "Racine", { size="sm", minWidth=80 })
    btnUp   = UI.Button(nav, Tr("btn_up") or "Remonter", { size="sm", variant="ghost", minWidth=100 })
    btnRoot:SetPoint("LEFT", nav, "LEFT", 0, 0); btnUp:SetPoint("LEFT", btnRoot, "RIGHT", 6, 0)

    breadcrumbFS = nav:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    breadcrumbFS:SetPoint("LEFT", btnUp, "RIGHT", 12, 0)
    breadcrumbFS:SetText(_PathToText(currentPath))

    -- Sélecteur de base (DB / DB_UI)
    ddRoot = UI.Dropdown(nav, { width = 160, placeholder = (Tr("lbl_db_select") or "Base : DB") })
        :SetBuilder(function(self, level)
            local entries = {}
            local function info(text, checked, onClick, isTitle)
                local i = UIDropDownMenu_CreateInfo()
                i.text = text
                i.checked = checked
                i.func = onClick
                i.isTitle = isTitle
                i.notCheckable = isTitle
                return i
            end



            entries[#entries+1] = info(Tr("lbl_db_data"), selectedRoot == "DB_SHARED", function()
                selectedRoot = "DB_SHARED"
                ddRoot:SetSelected("DB_SHARED", "DB_SHARED")
                breadcrumbFS:SetText(_PathToText(currentPath))
                Refresh()
            end)

            entries[#entries+1] = info(Tr("lbl_db_ui"), selectedRoot == "DB_UI", function()
                selectedRoot = "DB_UI"
                ddRoot:SetSelected("DB_UI", "DB_UI")
                breadcrumbFS:SetText(_PathToText(currentPath))
                Refresh()
            end)

            entries[#entries+1] = info(Tr("lbl_db_datas"), selectedRoot == "DB_DATAS", function()
                selectedRoot = "DB_DATAS"
                ddRoot:SetSelected("DB_DATAS", "DB_DATAS")
                breadcrumbFS:SetText(_PathToText(currentPath))
                Refresh()
            end)

            entries[#entries+1] = info(Tr("lbl_db_backup"), selectedRoot == "DB_BACKUP", function()
                selectedRoot = "DB_BACKUP"
                ddRoot:SetSelected("DB_BACKUP", "DB_BACKUP")
                breadcrumbFS:SetText(_PathToText(currentPath))
                Refresh()
            end)

            entries[#entries+1] = info(Tr("lbl_db_previous"), selectedRoot == "DB_PREVIOUS", function()
                selectedRoot = "DB_PREVIOUS"
                ddRoot:SetSelected("DB_PREVIOUS", "DB_PREVIOUS")
                breadcrumbFS:SetText(_PathToText(currentPath))
                Refresh()
            end)

            return entries
        end)

    ddRoot:SetPoint("RIGHT", nav, "RIGHT", 0, 0)
    UI.AttachDropdownZFix(ddRoot, nav)
    -- Valeur initiale affichée
    ddRoot:SetSelected(selectedRoot, selectedRoot)

    -- ===== AFFICHAGE INFO BACKUP =====
    backupInfoFS = nav:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    backupInfoFS:SetPoint("RIGHT", ddRoot, "LEFT", -12, 0)
    backupInfoFS:SetJustifyH("RIGHT")

    -- Petit affichage debug (clé active + UID) pour QA
    dbgInfoFS = nav:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    dbgInfoFS:SetPoint("LEFT", breadcrumbFS, "RIGHT", 12, 0)
    local function _updateDbg()
        local key = (GLOG and GLOG.GetActiveGuildBucketKey and GLOG.GetActiveGuildBucketKey())
        if not key then
            -- Fallback: try to recompute like DatabaseManager
            if GLOG and GLOG.GetMode then
                local gname = (GetGuildInfo and GetGuildInfo("player")) or nil
                local base = (not gname or gname == "") and "__noguild__" or tostring(gname):gsub("%s+",""):gsub("'",""):lower()
                local mode = GLOG.GetMode()
                key = (base == "__noguild__") and base or ((mode == "standalone") and ("standalone_"..base) or base)
            end
        end
        local uid = (UnitGUID and UnitGUID("player")) or ""
        dbgInfoFS:SetText("|cff808080["..tostring(key or "?").."]("..(uid ~= "" and uid:sub(-6) or "no GUID")..")|r")
    end
    _updateDbg()
    
    updateBackupInfo = function()
        if GLOG.GetBackupInfo then
            local info = GLOG.GetBackupInfo()
            if info then
                local text = string.format("|cff7dff9a%s|r (%s)", 
                    Tr("lbl_backup_info") or "Backup", 
                    info.date or (Tr("unknown_date") or "date inconnue")
                )
                backupInfoFS:SetText(text)
            else
                backupInfoFS:SetText("|cff808080" .. (Tr("lbl_no_backup_available") or "Aucun backup") .. "|r")
            end
        else
            backupInfoFS:SetText("")
        end
    end
    updateBackupInfo() -- Affichage initial

    -- Fonction pour rafraîchir le dropdown après création/suppression de backup
    refreshDropdown = function()
        if ddRoot then            
            -- Méthode alternative : forcer la réinitialisation du dropdown
            if UIDropDownMenu_Initialize and ddRoot._builder then
                UIDropDownMenu_Initialize(ddRoot, function(frame, level, menuList)
                    if not ddRoot._builder then return end
                    local items = ddRoot:_builder(level or 1, menuList)
                    if type(items) ~= "table" then return end
                    for i = 1, #items do
                        UIDropDownMenu_AddButton(items[i], level)
                    end
                end)
            end
            
            -- Forcer la mise à jour de l'affichage
            if UIDropDownMenu_RefreshAll then
                UIDropDownMenu_RefreshAll(ddRoot)
            end
        end
    end

    btnRoot:SetOnClick(function()
        wipe(currentPath)
        breadcrumbFS:SetText(_PathToText(currentPath))
        Refresh()
    end)
    btnUp:SetOnClick(function()
        if #currentPath > 0 then table.remove(currentPath) end
        breadcrumbFS:SetText(_PathToText(currentPath))
        Refresh()
    end)

    -- Liste
    lv = UI.ListView(panel, cols, {
        buildRow = BuildRow,
        updateRow = UpdateRow,
        topOffset = 34,
    })

    -- Bouton footer
    if footer then
        local btnAdd = UI.Button(footer, Tr("btn_add_field") or "Ajouter un champ", { size="sm", minWidth=160, tooltip=Tr("tip_add_field") or "Ajouter une clé/valeur dans l'élément courant" })
        btnAdd:SetOnClick(function()
            ShowAddFieldPopup()
        end)
        btnAdd:SetShown((GLOG.IsGM and GLOG.IsGM()) or false)

        -- ===== NOUVEAUX BOUTONS BACKUP/RESTORE =====
        local btnBackup = UI.Button(footer, Tr("btn_create_backup") or "Créer un backup", { 
            size="sm", 
            minWidth=140, 
            tooltip=Tr("tooltip_create_backup") or "Créer une sauvegarde complète de la base de données" 
        })
        
        local btnRestore = UI.Button(footer, Tr("btn_restore_backup") or "Restaurer le backup", { 
            size="sm", 
            minWidth=140, 
            variant="ghost",
            tooltip=Tr("tooltip_restore_backup") or "Restaurer la base de données depuis le dernier backup" 
        })

        -- Actions des boutons backup
        btnBackup:SetOnClick(function()
            UI.PopupConfirm(Tr("confirm_create_backup") or "Créer un backup de la base de données ?", function()
                if GLOG.CreateDatabaseBackup then
                    local success, message = GLOG.CreateDatabaseBackup()
                    if success then
                        if UI.Toast then UI.Toast("|cff7dff9a" .. message .. "|r") end
                        -- Rafraîchir l'état du bouton restore et l'affichage
                        btnRestore:SetEnabled(GLOG.HasValidBackup and GLOG.HasValidBackup() or false)
                        if updateBackupInfo then updateBackupInfo() end
                        -- Délai pour s'assurer que les données sont à jour
                        C_Timer.After(0.1, function()
                            if refreshDropdown then 
                                refreshDropdown() 
                            end
                        end)
                    else
                        if UI.Toast then UI.Toast("|cffff6060Erreur : " .. message .. "|r") end
                    end
                else
                    if UI.Toast then UI.Toast("|cffff6060Fonction de backup non disponible|r") end
                end
            end, nil, { strata = "FULLSCREEN_DIALOG" })
        end)

        btnRestore:SetOnClick(function()
            if not (GLOG.HasValidBackup and GLOG.HasValidBackup()) then
                if UI.Toast then UI.Toast("|cffff6060" .. (Tr("err_no_backup") or "Aucun backup trouvé") .. "|r") end
                return
            end

            -- Afficher les infos du backup dans la confirmation
            local backupInfo = GLOG.GetBackupInfo and GLOG.GetBackupInfo()
            local confirmText = Tr("confirm_restore_backup") or "Restaurer la base de données depuis le backup ?\n\nCela remplacera toutes les données actuelles.\nLa base actuelle sera sauvegardée comme 'previous'."
            
            if backupInfo and backupInfo.date then
                confirmText = confirmText .. "\n\n" .. string.format(Tr("lbl_backup_date") or "Date : %s", backupInfo.date)
                if backupInfo.size then
                    confirmText = confirmText .. "\n" .. string.format(Tr("lbl_backup_size") or "Taille : %d éléments", backupInfo.size)
                end
            end

            UI.PopupConfirm(confirmText, function()
                if GLOG.RestoreDatabaseFromBackup then
                    local success, message = GLOG.RestoreDatabaseFromBackup()
                    if success then
                        if UI.Toast then UI.Toast("|cff7dff9a" .. message .. "|r") end
                        -- Rafraîchir l'affichage après restore
                        if Refresh then Refresh() end
                        if updateBackupInfo then updateBackupInfo() end
                        -- Délai pour s'assurer que les données sont à jour
                        C_Timer.After(0.1, function()
                            if refreshDropdown then 
                                refreshDropdown() 
                            end
                        end)
                    else
                        if UI.Toast then UI.Toast("|cffff6060Erreur : " .. message .. "|r") end
                    end
                else
                    if UI.Toast then UI.Toast("|cffff6060Fonction de restore non disponible|r") end
                end
            end, nil, { strata = "FULLSCREEN_DIALOG" })
        end)

        -- État initial du bouton restore (actif seulement si backup existe)
        btnRestore:SetEnabled(GLOG.HasValidBackup and GLOG.HasValidBackup() or false)
        
        -- Les boutons backup ne s'affichent que si on a une DB principale
        local hasMainDB = GuildLogisticsDB_Char and type(GuildLogisticsDB_Char) == "table"
        btnBackup:SetShown(hasMainDB)
        btnRestore:SetShown(hasMainDB)

        if UI.AttachButtonsFooterRight then
            local buttons = { btnAdd }
            if hasMainDB then
                table.insert(buttons, btnBackup)
                table.insert(buttons, btnRestore)
            end
            UI.AttachButtonsFooterRight(footer, buttons, 8, 0)
        end
    end

    -- Assure un rafraîchissement quand on revient sur l’onglet
    if panel and panel.SetScript then
        panel:SetScript("OnShow", function() Refresh() end)
    end
end

Refresh = function()
    if breadcrumbFS then breadcrumbFS:SetText(_PathToText(currentPath)) end
    if dbgInfoFS and dbgInfoFS.SetText then
        -- refresh debug info (active key + UID)
        local key = (GLOG and GLOG.GetActiveGuildBucketKey and GLOG.GetActiveGuildBucketKey())
        if not key then
            if GLOG and GLOG.GetMode then
                local gname = (GetGuildInfo and GetGuildInfo("player")) or nil
                local base = (not gname or gname == "") and "__noguild__" or tostring(gname):gsub("%s+",""):gsub("'",""):lower()
                local mode = GLOG.GetMode()
                key = (base == "__noguild__") and base or ((mode == "standalone") and ("standalone_"..base) or base)
            end
        end
        local uid = (UnitGUID and UnitGUID("player")) or ""
        dbgInfoFS:SetText("|cff808080["..tostring(key or "?").."]("..(uid ~= "" and uid:sub(-6) or "no GUID")..")|r")
    end
    if not lv or not lv.SetData then return end
    lv:SetData(_BuildItems())
    
    -- Mettre à jour l'affichage des infos de backup
    if updateBackupInfo then updateBackupInfo() end
    -- Délai pour s'assurer que les données sont à jour
    C_Timer.After(0.05, function()
        if refreshDropdown then 
            refreshDropdown() 
        end
    end)
end

Layout = function()
    -- rien de spécifique (CreateMainContainer s'occupe du sizing)
end

UI.RegisterTab(Tr("tab_debug_db") or "Base de donnée", Build, Refresh, Layout, {
    category = Tr("cat_debug"),
})
