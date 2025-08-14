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
    -- laisse la marge latérale du contenu, mais réserve la hauteur du footer + gap
    f.content:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(R + POP_SIDE), B + ( (UI.FOOTER_H or 36) + 8 + POP_BOT))

    -- Footer pleine largeur (au sein des insets du skin) + style centralisé
    f.footer = UI.CreateFooter(f, UI.FOOTER_H or 36)
    f.footer:ClearAllPoints()
    f.footer:SetPoint("BOTTOMLEFT",   f, "BOTTOMLEFT",  L,  B + POP_BOT)
    f.footer:SetPoint("BOTTOMRIGHT",  f, "BOTTOMRIGHT", -R, B + POP_BOT)

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
        if not self.msgFS then
            self.msgFS = self.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            -- plein cadre + centrage
            self.msgFS:SetPoint("TOPLEFT",     self.content, "TOPLEFT",  0, 0)
            self.msgFS:SetPoint("BOTTOMRIGHT", self.content, "BOTTOMRIGHT", 0, 0)
            self.msgFS:SetJustifyH("CENTER")
            self.msgFS:SetJustifyV("MIDDLE")
        end
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
        width  = math.floor(((opts and opts.width)  or 460) * 1.10),
        height = math.floor(((opts and opts.height) or 180) * 1.20),
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
        width  = math.floor(((opts and opts.width)  or 460) * 1.10),
        height = math.floor(((opts and opts.height) or 220) * 1.20),
    })

    -- Conteneur centré pour (label + input)
    local stack = CreateFrame("Frame", nil, dlg.content)
    stack:SetSize(260, 60)       -- assez large/haut pour le label + champ
    stack:SetPoint("CENTER")     -- centre le groupe dans la popup

    local l = stack:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    l:SetText(label or "")
    l:SetPoint("TOP", stack, "TOP", 0, 0)

    local eb = CreateFrame("EditBox", nil, stack, "InputBoxTemplate")
    eb:SetAutoFocus(true); eb:SetNumeric(true); eb:SetSize(220, 28)
    eb:SetPoint("TOP", l, "BOTTOM", 0, -8)

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
    local dlg = UI.CreatePopup({
        title  = title,
        width  = math.floor(520 * 1.10),
        height = math.floor(220 * 1.20),
    })
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

function UI.PopupRaidDebit(name, deducted, after, ctx)
    -- Hauteur augmentée pour accueillir le détail des composants
    local dlg = UI.CreatePopup({ title = "Participation clôturée", width = 560, height = 400 })
    local lines = {}
    lines[#lines+1] = "Bon raid !\n"

    -- Petit utilitaire local pour nom d'objet
    local function _itemName(it)
        if not it then return "" end
        if it.itemLink and it.itemLink ~= "" then
            local bracket = it.itemLink:match("%[(.-)%]")
            if bracket and bracket ~= "" then return bracket end
        end
        return it.itemName or ""
    end

    -- On construit du contenu interactif (icônes + tooltips), plus de SetMessage ici
    -- Header "Bon raid" + montants
    local header = dlg.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    header:SetJustifyH("LEFT")
    header:SetPoint("TOPLEFT", dlg.content, "TOPLEFT", 0, 0)
    header:SetText(("Bon raid !\n\n|cffffd200Montant déduit :|r %s\n|cffffd200Solde restant :|r %s")
        :format(UI.MoneyText(math.floor(tonumber(deducted) or 0)),
                UI.MoneyText(math.floor(tonumber(after) or 0))))

    local L = ctx and (ctx.L or ctx.lots) or nil
    if type(L) == "table" and #L > 0 then
        local label = dlg.content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -10)
        label:SetText("|cffffd200Lots utilisés (détails) :|r")

        local cols = UI.NormalizeColumns({
            { key="lot",  title="Lot",   min=160, flex=1 },
            { key="qty",  title="Qté",   w=60, justify="RIGHT" },
            { key="item", title="Objet", min=280, flex=1 },
        })
        local lv = UI.ListView(dlg.content, cols, {
            buildRow = function(r)
                local f = {}
                f.lot = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                f.qty = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")

                f.itemFrame = CreateFrame("Frame", nil, r); f.itemFrame:SetHeight(UI.ROW_H)
                f.icon  = f.itemFrame:CreateTexture(nil, "ARTWORK"); f.icon:SetSize(20,20); f.icon:SetPoint("LEFT", f.itemFrame, "LEFT", 0, 0)
                f.btn   = CreateFrame("Button", nil, f.itemFrame); f.btn:SetPoint("LEFT", f.icon, "RIGHT", 6, 0); f.btn:SetSize(260, UI.ROW_H)
                f.text  = f.btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                f.text:SetJustifyH("LEFT"); f.text:SetPoint("LEFT", f.btn, "LEFT", 0, 0)

                f.btn:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT")
                    if self._itemID and self._itemID > 0 then
                        GameTooltip:SetItemByID(self._itemID)
                    elseif self._link and self._link ~= "" then
                        GameTooltip:SetHyperlink(self._link)
                    else
                        GameTooltip:Hide()
                    end
                end)
                f.btn:SetScript("OnLeave", function() GameTooltip:Hide() end)
                f.item = f.itemFrame
                return f
            end,
            updateRow = function(_, _, f, row)
                f.lot:SetText(row.lot or "")
                f.qty:SetText(tostring(row.qty or 1))
                f.text:SetText(row.name or "Objet inconnu")
                f.icon:SetTexture(row.icon or "Interface\\ICONS\\INV_Misc_QuestionMark")
                f.btn._itemID = row.itemID
                f.btn._link   = row.link
            end,
            topOffset = 52,
        })

        local rows = {}
        for i=1,#L do
            local li = L[i]
            local lot = ns and ns.CDZ and ns.CDZ.Lot_GetById and ns.CDZ.Lot_GetById(li.id)
            local nm  = li.name or li.n or (lot and lot.name) or ("Lot "..tostring(li.id or i))
            local N   = tonumber(li.N or 1) or 1
            if lot and ns.CDZ and ns.CDZ.GetExpenseById then
                for _, eid in ipairs(lot.itemIds or {}) do
                    local _, it = ns.CDZ.GetExpenseById(eid)
                    if it then
                        local itemID = tonumber(it.itemID or 0) or 0
                        local link   = (itemID > 0) and (select(2, GetItemInfo(itemID))) or it.itemLink
                        local name   = (link and link:match("%[(.-)%]")) or (GetItemInfo(itemID)) or it.itemName or "Objet inconnu"
                        local icon   = (itemID > 0) and (select(5, GetItemInfoInstant(itemID))) or "Interface\\ICONS\\INV_Misc_QuestionMark"
                        local qty    = tonumber(it.qty or 1) or 1
                        if N > 1 and qty % N == 0 then qty = qty / N end
                        rows[#rows+1] = { lot = nm, qty = qty, itemID = itemID, link = link, name = name, icon = icon }
                    end
                end
            end
        end
        lv:SetData(rows)
        dlg._lv = lv  -- déclenche le relayout automatique de la popup
        lv:Layout()   -- calcule immédiatement la mise en page initiale

    end

    dlg:SetButtons({ { text = "Fermer", default = true } })
    dlg:Show()
    return dlg
end
