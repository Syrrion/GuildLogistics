local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns.GLOG, ns.UI

-- =========================
-- =====   NAV STATE   =====
-- =========================
local panel, footer
local lv, breadcrumbFS, btnRoot, btnUp
local currentPath = {}  -- tableau de clés (strings ou numbers)
local Build, Refresh, Layout, UpdateRow

local function _GetRoot()
    -- Les alias de Core.lua font pointer GuildLogisticsDB sur la base « par personnage »
    return GuildLogisticsDB_Char or GuildLogisticsDB or {}
end

local function _PathToText(path)
    local parts = {"GuildLogisticsDB_Char"}
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
    { key="type",  title=Tr("col_type") or "Type",      w=100 },
    { key="prev",  title=Tr("col_preview") or "Aperçu", min=220, flex=1.2 },
    { key="act",   title="",                             w=160 },
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
            local newV, err = (GLOG.DeserializeLua and GLOG.DeserializeLua(txt))
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

UpdateRow = function(i, r, f, it)
    -- Libellés
    f.key:SetText(tostring(it.key))
    f.type:SetText(tostring(it.type))
    f.prev:SetText(_Preview(it.value))

    -- État des actions
    local isTbl = (type(it.value) == "table")
    r.btnOpen:SetShown(isTbl)       -- Naviguer dans une table
    r.btnEdit:SetShown(not isTbl)   -- ❌ Interdit d'éditer une table
    r.btnDel:SetShown(true)

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
    panel, footer = UI.CreateMainContainer(container, { footer = false })

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

    -- Assure un rafraîchissement quand on revient sur l’onglet
    if panel and panel.SetScript then
        panel:SetScript("OnShow", function() Refresh() end)
    end
end

Refresh = function()
    if breadcrumbFS then breadcrumbFS:SetText(_PathToText(currentPath)) end
    if not lv or not lv.SetData then return end
    lv:SetData(_BuildItems())
end

Layout = function()
    -- rien de spécifique (CreateMainContainer s'occupe du sizing)
end

UI.RegisterTab(Tr("tab_debug_db") or "Base de donnée", Build, Refresh, Layout, {
    category = Tr("cat_debug"),
})
