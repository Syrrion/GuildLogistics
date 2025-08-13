local ADDON, ns = ...
ns.UI = ns.UI or {}
local UI = ns.UI

-- Base popup (atlas Neutral)
function UI.CreatePopup(opts)
    opts = opts or {}
    local f = CreateFrame("Frame", "CDZ_Popup_" .. math.random(1e8), UIParent, "BackdropTemplate")
    f:SetSize(opts.width or 460, opts.height or 240)
    f:SetFrameStrata("DIALOG"); f:SetToplevel(true)
    f:SetPoint("CENTER")
    f:SetMovable(true); f:EnableMouse(true)

    -- Permettre le drag partout (incl. header décoratif via HitRectInsets de la skin)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",  function(self) self:StopMovingOrSizing() end)
    if f.SetClampedToScreen then f:SetClampedToScreen(true) end

    -- Habillage Neutral (même look que la fenêtre principale)
    local skin = UI.ApplyNeutralFrameSkin(f, { showRibbon = false, shadow = false })
    local L, R, T, B = skin:GetInsets()

    -- Zone draggable (sur la frise du titre)
    local drag = CreateFrame("Frame", nil, f)
    drag:SetPoint("TOPLEFT",  f, "TOPLEFT",  L-8, -(8))
    drag:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(R-8), -(8))
    drag:SetHeight(64)
    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() f:StartMoving() end)
    drag:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

    -- Titre centré
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetText(opts.title or "Information")
    f.title:SetTextColor(0.98, 0.95, 0.80)
    f.title:SetPoint("CENTER", drag, "CENTER", 0, -2)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() f:Hide() end)

    -- Zones contenu / footer avec gap supplémentaire (popup sans onglets)
    local POP_SIDE  = UI.POPUP_SIDE_PAD        or 6   -- marge G/D
    local POP_TOP   = UI.POPUP_TOP_EXTRA_GAP   or 18  -- espace sous la barre de titre
    local POP_BOT   = UI.POPUP_BOTTOM_LIFT     or 4   -- remonte un peu du bas

    f.content = CreateFrame("Frame", nil, f)
    f.content:SetPoint("TOPLEFT",     f, "TOPLEFT",     L + POP_SIDE, -(T + POP_TOP))
    f.content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(R + POP_SIDE), B + 40 + POP_BOT)

    f.footer = CreateFrame("Frame", nil, f)
    f.footer:SetPoint("BOTTOMLEFT",   f, "BOTTOMLEFT",  L + POP_SIDE, B + POP_BOT)
    f.footer:SetPoint("BOTTOMRIGHT",  f, "BOTTOMRIGHT", -(R + POP_SIDE), B + POP_BOT)
    f.footer:SetHeight(32)


    -- Liseré léger pour séparer le footer (discret pour rester cohérent avec l’atlas)
    local fl = f.footer:CreateTexture(nil, "BORDER")
    fl:SetColorTexture(1, 1, 1, 0.06)
    fl:SetPoint("TOPLEFT", f.footer, "TOPLEFT", 0, 1)
    fl:SetPoint("TOPRIGHT", f.footer, "TOPRIGHT", 0, 1)
    fl:SetHeight(1)

    -- Redimensionnable + relayout ListView embarqué
    f:SetResizable(true)
    if f.SetResizeBounds then f:SetResizeBounds(360, 220) end
    f:SetScript("OnSizeChanged", function(self)
        if self._lv and self._lv.Layout then self._lv:Layout() end
    end)

    -- Raccourcis clavier
    f._defaultBtn = nil
    f:EnableKeyboard(true)
    f:SetScript("OnKeyDown", function(self, key)
        if key == "ENTER" and self._defaultBtn and self._defaultBtn:IsEnabled() then
            self._defaultBtn:Click()
        elseif key == "ESCAPE" then
            self:Hide()
        end
    end)
    if UISpecialFrames then table.insert(UISpecialFrames, f:GetName()) end

    -- Message simple multi-ligne
    function f:SetMessage(text)
        if self.msgFS then self.msgFS:SetText(text or ""); return end
        self.msgFS = self.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        self.msgFS:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, 0)
        self.msgFS:SetPoint("RIGHT",  self.content, "RIGHT", 0, 0)
        self.msgFS:SetJustifyH("LEFT"); self.msgFS:SetJustifyV("TOP")
        self.msgFS:SetText(text or "")
    end

    -- Boutons normalisés (UI.Button) + ancrage à droite
    function f:SetButtons(buttons)
        if self._btns then for _, b in ipairs(self._btns) do b:Hide() end end
        self._btns, self._defaultBtn = {}, nil

        local arr = {}
        for i = 1, #buttons do
            local def = buttons[i]
            local b = UI.Button(self.footer, def.text or "OK", {
                size = "sm",
                minWidth = def.width or 110,
                variant = def.variant,
            })
            b:SetOnClick(function()
                if def.onClick then
                    local ok, err = pcall(def.onClick, b, self)
                    if not ok and geterrorhandler then geterrorhandler()(err) end
                end
                if def.close ~= false then self:Hide() end
            end)
            if def.default then self._defaultBtn = b end
            table.insert(arr, b); table.insert(self._btns, b)
        end

        if UI.AttachButtonsFooterRight then
            UI.AttachButtonsFooterRight(self.footer, arr, 8, 0)
        end
    end

    return f
end

-- Confirm standard
function UI.PopupConfirm(text, onAccept, onCancel, opts)
    local dlg = UI.CreatePopup({
        title  = (opts and opts.title) or "Confirmation",
        width  = (opts and opts.width)  or 460,
        height = (opts and opts.height) or 180,
    })
    dlg:SetMessage(text)
    dlg:SetButtons({
        { text = OKAY,   default = true, onClick = function() if onAccept then onAccept() end end },
        { text = CANCEL, variant = "ghost", onClick = function() if onCancel then onCancel() end end },
    })
    dlg:Show()
    return dlg
end

-- Prompt numérique
function UI.PopupPromptNumber(title, label, onAccept, opts)
    local dlg = UI.CreatePopup({
        title  = title or "Saisie",
        width  = (opts and opts.width)  or 460,
        height = (opts and opts.height) or 220,
    })

    local l = dlg.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    l:SetPoint("TOPLEFT", dlg.content, "TOPLEFT", 0, 0)
    l:SetText(label or "")

    local eb = CreateFrame("EditBox", nil, dlg.content, "InputBoxTemplate")
    eb:SetAutoFocus(true); eb:SetNumeric(true); eb:SetSize(180, 28)
    eb:SetPoint("TOPLEFT", l, "BOTTOMLEFT", 0, -8)
    eb:SetScript("OnEnterPressed", function(self)
        local v = (self.GetNumber and self:GetNumber()) or (tonumber(self:GetText()) or 0)
        if onAccept then onAccept(v) end
        dlg:Hide()
    end)

    dlg:SetButtons({
        { text = OKAY,   default = true, onClick = function()
            local v = (eb.GetNumber and eb:GetNumber()) or (tonumber(eb:GetText()) or 0)
            if onAccept then onAccept(v) end
        end },
        { text = CANCEL, variant = "ghost" },
    })
    dlg:Show()
    return dlg
end

-- Demande de transaction entrante (GM)
function UI.PopupRequest(playerName, delta, onApprove, onRefuse)
    local title = "Demande de transaction"
    local dlg = UI.CreatePopup({ title = title, width = 520, height = 220 })
    local op = (tonumber(delta) or 0) >= 0 and "|cff40ff40+|r" or "|cffff6060-|r"
    local amt = UI.MoneyText(math.abs(tonumber(delta) or 0))

    dlg:SetMessage(("|cffffd200Demandeur:|r %s\n|cffffd200Opération:|r %s %s\n\nApprouver ?")
        :format(playerName or "?", op, amt))

    dlg:SetButtons({
        { text = "Approuver", default = true, onClick = function() if onApprove then onApprove() end end },
        { text = "Refuser", variant = "ghost", onClick = function() if onRefuse then onRefuse() end end },
    })
    dlg:Show()
    return dlg
end

-- Popup liste des participants (inchangée côté logique, Look&Feel hérité)
function UI.ShowParticipantsPopup(names)
    local dlg = UI.CreatePopup({ title = "Participants", width = 540, height = 440 })
    local cols = {
        { key="name",   title="Nom",    min=300, justify="LEFT" },
        { key="status", title="Statut", w=180,  justify="LEFT"  },
    }
    local lv = UI.ListView(dlg.content, cols, {
        buildRow = function(r)
            local f = {}
            f.name   = UI.CreateNameTag(r)
            f.status = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            return f
        end,
        updateRow = function(i, r, f, item)
            UI.SetNameTag(f.name, item.name or "")
            f.status:SetText(item.exists and "|cff40ff40Présent|r" or "|cffff7070Supprimé|r")
        end,
    })
    dlg._lv = lv

    local pdb = (ChroniquesDuZephyrDB and ChroniquesDuZephyrDB.players) or {}
    local arr = {}
    for _, n in ipairs(names or {}) do arr[#arr+1] = n end
    table.sort(arr, function(a,b) return (a or ""):lower() < (b or ""):lower() end)
    local data = {}
    for _, n in ipairs(arr) do data[#data+1] = { name = n, exists = (pdb[n] ~= nil) } end

    lv:SetData(data)
    dlg:SetButtons({ { text = CLOSE, default = true } })
    dlg:Show()
end

function UI.PopupText(title, text)
    local dlg = UI.CreatePopup({ title = title or "Message", width = 700, height = 420 })
    dlg:SetMessage(text or "")
    dlg:SetButtons({ { text = "Fermer", default = true } })
    dlg:Show()
    return dlg
end