-- GuildLogistics/UI/UI_TokenList.lua
local ADDON, ns = ...
ns = ns or {}
ns.UI = ns.UI or {}
local UI  = ns.UI
local Tr  = ns.Tr or function(s) return s end

--[[
TokenList (version ListView)
Liste éditable d'éléments avec :
 - icône + libellé (type = "spell" | "item")
 - texte simple (type = "text")

API : local widget = UI.TokenList(parent, opts)
opts = {
  type        = "spell" | "item" | "text",
  title       = "string" (optionnel),
  width       = number (default 560),
  height      = number (default 110),
  placeholder = "string",
}
widget.values      -> table (strings pour "text", numbers pour "spell"/"item")
widget.kind        -> "text"|"spell"|"item"
widget:SetValues(t)
widget:AddValue(v)
widget:RemoveValue(v)
widget:GetValues() -> copie
--]]

function UI.TokenList(parent, opts)
    opts = opts or {}
    local kind        = opts.type or "text"
    local W           = tonumber(opts.width  or 560) or 560
    local H           = tonumber(opts.height or 110) or 110
    local holderText  = tostring(opts.placeholder or "")
    local ROW_H       = UI.ROW_H or 30

    -- Génère un nom unique avec le préfixe GLOG_ pour bénéficier du système de police automatique
    local tokenListId = "GLOG_TokenList_" .. math.random(1e8)
    local f = CreateFrame("Frame", tokenListId, parent, "BackdropTemplate")
    f:SetSize(W, H)

    f.values = {}
    f.kind   = kind

    -- ==== Titre optionnel ====
    local topOffset = 0
    if opts.title and opts.title ~= "" then
        local t = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        t:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 2)
        t:SetText(Tr(opts.title))
        f._title = t
        topOffset = 18
    end

    -- ==== Colonnes ListView ====
    local cols
    if kind == "text" then
        cols = UI.NormalizeColumns({
            { key="name", title=Tr("col_string") or "Chaîne", min=200, flex=1 },
            { key="act",  title="", vsep=true,  w=80 },
        })
    elseif kind == "spell" then
        cols = UI.NormalizeColumns({
            { key="ico",  title="", w=36 },
            { key="name", title=Tr("col_spell_name") or "Nom du sort", min=200, flex=1 },
            { key="act",  title="", vsep=true,  w=80 },
        })
    else
        cols = UI.NormalizeColumns({
            { key="ico",  title="", w=36 },
            { key="name", title=Tr("col_item_name") or "Nom de l'objet", min=200, flex=1 },
            { key="act",  title="", vsep=true,  w=80 },
        })
    end

    -- ==== Helpers résolution nom/icône ====
    local function SpellLabelIcon(id)
        id = tonumber(id)
        if not id then return nil end
        local name, icon
        if C_Spell and C_Spell.GetSpellInfo then
            local info = C_Spell.GetSpellInfo(id)
            if info then name, icon = info.name, info.iconID end
        end
        if not name then name = Tr("spell_id_format"):format(id) or ("Spell #%d"):format(id) end
        return name, icon or 136243
    end

    local function ItemLabelIcon(id)
        id = tonumber(id)
        if not id then return nil end
        local name = C_Item.GetItemInfo(id) or nil
        local icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id))
                  or C_Item.GetItemInfo(id)
                  or 134400
        if not name then name = Tr("item_id_format"):format(id) or ("Item #%d"):format(id) end
        return name, icon or 134400
    end

    local function ParseLinkOrText(txt)
        txt = tostring(txt or "")
        local iid = txt:match("Hitem:(%d+)"); if iid then return "item", tonumber(iid) end
        local sid = txt:match("Hspell:(%d+)"); if sid then return "spell", tonumber(sid) end
        local n = tonumber(txt)
        if n and kind ~= "text" then return kind, n end
        if kind == "text" then
            local s = txt:gsub("^%s+",""):gsub("%s+$","")
            if s ~= "" then return "text", s end
        end
        return nil
    end

    -- ==== ListView ====
    local lv
    local function BuildRow(r)
        local fld = {}
        if kind ~= "text" then
            fld.ico = r:CreateTexture(nil, "ARTWORK")
            fld.ico:SetSize(18,18)
        end
        fld.name = UI.Label(r, { template="GameFontHighlightSmall", justify="LEFT" })

        fld.act = CreateFrame("Frame", nil, r); fld.act:SetHeight(ROW_H); fld.act:SetFrameLevel(r:GetFrameLevel()+1)
        r.btnRemove = UI.Button(fld.act, "×", { size="xs", minWidth=24, variant="danger", tooltip=Tr("btn_remove") or "Supprimer" })
        UI.AttachRowRight(fld.act, { r.btnRemove }, 8, -4, { leftPad=8, align="center" })
        return fld
    end

    local function UpdateRow(i, r, fld, it)
        if kind == "text" then
            if fld.ico then fld.ico:Hide() end
            fld.name:SetText(tostring(it.name or it.value or ""))

            -- Pas de tooltip pour "text"
            if UI and UI.BindItemOrSpellTooltip then
                UI.BindItemOrSpellTooltip(r, 0, 0)
            end
        elseif kind == "spell" then
            local name, icon = SpellLabelIcon(it.value)
            if fld.ico then fld.ico:SetTexture(icon); fld.ico:Show() end
            fld.name:SetText(name or Tr("spell_id_format"):format(tonumber(it.value) or 0) or ("Spell #%d"):format(tonumber(it.value) or 0))

            if UI and UI.BindItemOrSpellTooltip then
                UI.BindItemOrSpellTooltip(r, 0, tonumber(it.value) or 0)
            end
        else -- item
            local name, icon = ItemLabelIcon(it.value)
            if fld.ico then fld.ico:SetTexture(icon); fld.ico:Show() end
            fld.name:SetText(name or Tr("item_id_format"):format(tonumber(it.value) or 0) or ("Item #%d"):format(tonumber(it.value) or 0))

            if UI and UI.BindItemOrSpellTooltip then
                UI.BindItemOrSpellTooltip(r, tonumber(it.value) or 0, 0)
            end
        end

        r.btnRemove:SetOnClick(function()
            f:RemoveValue(it.value)
        end)
    end

    lv = UI.ListView(f, cols, { topOffset = topOffset, buildRow = BuildRow, updateRow = UpdateRow })

    -- ==== Footer (input + bouton Ajouter) ====
    local footer = CreateFrame("Frame", nil, f)
    footer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
    footer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)

    local input = CreateFrame("EditBox", nil, footer, "BackdropTemplate")
    input:SetAutoFocus(false)
    input:SetFontObject("GameFontHighlight")
    input:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    input:SetBackdropColor(0,0,0,0.35)
    input:SetBackdropBorderColor(0,0,0,0.5)
    input:SetTextInsets(6,6,2,2)
    input:SetText("")
    input:SetCursorPosition(0)
    input:SetHeight(24)
    input:SetPoint("BOTTOMLEFT", footer, "BOTTOMLEFT", 0, 0)

    input:SetScript("OnEditFocusGained", function(self)
        if self._placeholder then self:SetText(""); self._placeholder = nil end
    end)

    local function SetPlaceholder()
        if (input:GetText() or "") == "" then
            input._placeholder = true
            input:SetText(holderText)
        end
    end
    if holderText ~= "" then SetPlaceholder() end

    local btnAdd = UI.Button(footer, Tr("btn_add") or "Ajouter", { size="sm", minWidth=88 })
    btnAdd:ClearAllPoints()
    btnAdd:SetPoint("BOTTOMRIGHT", footer, "BOTTOMRIGHT", 0, 0)
    input:SetPoint("RIGHT", btnAdd, "LEFT", -6, 0)

    -- Taille footer (input)
    local footerH = 24 + 18 + 4
    footer:SetHeight(footerH)

    -- Ancre bas de la ListView = le footer
    if lv.SetBottomAnchor then lv:SetBottomAnchor(footer) end

    -- ==== Data <-> ListView ====
    local function RefreshList()
        local rows = {}
        for _, v in ipairs(f.values) do
            if kind == "text" then
                rows[#rows+1] = { value = v, name = tostring(v) }
            elseif kind == "spell" then
                local name, icon = SpellLabelIcon(v)
                rows[#rows+1] = { value = tonumber(v), name = name, icon = icon }
            else
                local name, icon = ItemLabelIcon(v)
                rows[#rows+1] = { value = tonumber(v), name = name, icon = icon }
            end
        end
        lv:SetData(rows)
        lv:Layout()
    end

    function f:SetValues(arr)
        wipe(self.values)
        if type(arr) == "table" then
            for _, v in ipairs(arr) do
                if kind == "text" then
                    local s = tostring(v or ""):gsub("^%s+",""):gsub("%s+$","")
                    if s ~= "" then table.insert(self.values, s) end
                else
                    local n = tonumber(v)
                    if n then table.insert(self.values, n) end
                end
            end
        end
        RefreshList()
    end

    function f:AddValue(v)
        if kind == "text" then
            local s = tostring(v or ""):gsub("^%s+",""):gsub("%s+$","")
            if s == "" then return end
            for _, x in ipairs(self.values) do if x == s then return end end
            table.insert(self.values, s)
        else
            local n = tonumber(v); if not n then return end
            for _, x in ipairs(self.values) do if tonumber(x) == n then return end end
            table.insert(self.values, n)
        end
        RefreshList()
    end

    function f:RemoveValue(v)
        if kind == "text" then
            for i = #self.values, 1, -1 do
                if self.values[i] == v then table.remove(self.values, i) end
            end
        else
            local n = tonumber(v)
            for i = #self.values, 1, -1 do
                if tonumber(self.values[i]) == n then table.remove(self.values, i) end
            end
        end
        RefreshList()
    end

    function f:GetValues()
        local out = {}
        for i, v in ipairs(self.values) do out[i] = v end
        return out
    end

    local function TryAddFromInput()
        local txt = input:GetText() or ""
        if input._placeholder then txt = "" end
        local t, val = ParseLinkOrText(txt)
        if not t then return end
        if kind == "text" and t == "text" then
            f:AddValue(val)
        elseif kind == "spell" and t == "spell" then
            f:AddValue(val)
        elseif kind == "item" and t == "item" then
            f:AddValue(val)
        elseif tonumber(txt) and (kind == "spell" or kind == "item") then
            f:AddValue(tonumber(txt))
        else
            return
        end
        input:SetText("")
        SetPlaceholder()
    end
    btnAdd:SetOnClick(TryAddFromInput)
    input:SetScript("OnEnterPressed", TryAddFromInput)
    input:SetScript("OnEditFocusLost", function() SetPlaceholder() end)

    -- Relayout dynamique
    f:SetScript("OnSizeChanged", function()
        if lv and lv.Layout then lv:Layout() end
    end)
    C_Timer.After(0, function() if lv and lv.Layout then lv:Layout() end end)

    return f
end
