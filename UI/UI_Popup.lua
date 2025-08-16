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
    local dlg = UI.CreatePopup({ title = "Participation au raid validée !", width = 560, height = 400 })
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
    -- Header centré + titre agrandi, espacement autour des lignes de montant, puis offset dynamique anti-chevauchement
    local titleFS = dlg.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    titleFS:SetJustifyH("CENTER")
    titleFS:SetPoint("TOPLEFT",  dlg.content, "TOPLEFT",  0, -12)  -- marge haute
    titleFS:SetPoint("TOPRIGHT", dlg.content, "TOPRIGHT", 0, -12)
    titleFS:SetText("Bon raid !")

    -- Lignes séparées pour contrôler précisément les espacements
    local dedFS = dlg.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    dedFS:SetJustifyH("CENTER")
    dedFS:SetPoint("TOPLEFT",  titleFS, "BOTTOMLEFT",  0, -12)     -- espace AU-DESSUS de « Montant déduit »
    dedFS:SetPoint("TOPRIGHT", titleFS, "BOTTOMRIGHT", 0, -12)
    dedFS:SetText( ("|cffffd200Montant déduit :|r %s")
        :format(UI.MoneyText(math.floor(tonumber(deducted) or 0))) )

    local restFS = dlg.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    restFS:SetJustifyH("CENTER")
    restFS:SetPoint("TOPLEFT",  dedFS, "BOTTOMLEFT",  0, -8)       -- espace SOUS « Montant déduit »
    restFS:SetPoint("TOPRIGHT", dedFS, "BOTTOMRIGHT", 0, -8)
    restFS:SetText( ("|cffffd200Solde restant :|r %s")
        :format(UI.MoneyText(math.floor(tonumber(after) or 0))) )

    -- Forcer le wrapping si la largeur est connue
    local cw = dlg.content:GetWidth() or 0
    if cw > 0 then
        if titleFS.SetWidth then titleFS:SetWidth(cw) end
        if dedFS.SetWidth   then dedFS:SetWidth(cw)   end
        if restFS.SetWidth  then restFS:SetWidth(cw)  end
    end

    -- Séparateur après le solde (espace supplémentaire demandé)
    local sep = dlg.content:CreateTexture(nil, "BORDER")
    sep:SetColorTexture(1, 1, 1, 0.06)
    sep:SetPoint("TOPLEFT",  restFS, "BOTTOMLEFT",  0, -12)        -- espace SOUS « Solde restant »
    sep:SetPoint("TOPRIGHT", restFS, "BOTTOMRIGHT", 0, -12)
    sep:SetHeight(1)

    -- (Suppression du label "Lots utilisés (détails) :")

    local L = ctx and (ctx.L or ctx.lots) or nil
    if type(L) == "table" and #L > 0 then
        -- ➖ on ne montre plus la ligne de label ni la liste d'objets

        -- ➕ colonnes : Lot (flex) + Prix (droite)
        local cols = UI.NormalizeColumns({
            { key="lot",   title="Lots utilisés", min=200, flex=1, justify="LEFT"  },
            { key="price", title="Prix",          w=120,              justify="RIGHT" },
        })

        -- ➕ offset dynamique depuis le bas du header texte (pour éviter tout chevauchement)
        local function ComputeLVTopOffset()
            local cTop      = dlg.content:GetTop() or 0
            local anchorBtm = (header and header.GetBottom and header:GetBottom()) or 0
            local gap       = 12
            if cTop > 0 and anchorBtm > 0 then
                return math.max(40, math.floor(cTop - anchorBtm + gap))
            end
            return 64 -- fallback sûr
        end

        local lv = UI.ListView(dlg.content, cols, {
            buildRow = function(r)
                local f = {}
                f.lot   = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                f.price = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
                return f
            end,
            updateRow = function(_, _, f, row)
                f.lot:SetText(row.lot or "")
                f.price:SetText(row.priceText or "")
            end,
            topOffset = ComputeLVTopOffset(),
        })

        -- ➕ Agrégation par lot avec méta (fallback si lot inconnu en local)
        local usedByLot, metaByLot = {}, {}
        for i = 1, #L do
            local li = L[i]
            local id = li and li.id
            local n  = tonumber(li.n or li.k or 1) or 1  -- supporte k/n
            if id then
                usedByLot[id] = (usedByLot[id] or 0) + n
                if not metaByLot[id] then metaByLot[id] = li end -- garde nom + gold côté client
            end
        end

        -- ➕ Construit les lignes (prix = part * nbPartsUtilisées), avec fallback nom/prix depuis ctx.L
        local rows = {}
        for id, usedParts in pairs(usedByLot) do
            local lot = ns and ns.CDZ and ns.CDZ.Lot_GetById and ns.CDZ.Lot_GetById(id)
            local name, perGold
            if lot then
                name    = lot.name or ((metaByLot[id] and metaByLot[id].name) or ("Lot "..tostring(id)))
                perGold = (ns and ns.CDZ and ns.CDZ.Lot_ShareGold and ns.CDZ.Lot_ShareGold(lot)) or 0
            else
                name    = (metaByLot[id] and metaByLot[id].name) or ("Lot "..tostring(id))
                perGold = tonumber(metaByLot[id] and (metaByLot[id].gold or metaByLot[id].g)) or 0
            end

            local gold = math.max(0, (tonumber(perGold) or 0) * (tonumber(usedParts) or 1))
            rows[#rows+1] = { lot = name, price = gold, priceText = UI.MoneyText(gold) }
        end
        table.sort(rows, function(a, b) return (a.lot or ""):lower() < (b.lot or ""):lower() end)

        lv:SetData(rows)
        dlg._lv = lv

        -- ➕ Reflow différé + hooks (échelle UI / resize)
        local function ReflowList()
            if not lv or not lv.Layout then return end
            lv.opts.topOffset = ComputeLVTopOffset()
            lv:Layout()
            if dlg.FitToContent then dlg:FitToContent() end
        end
        ns.Util.After(0, ReflowList)
        if dlg.HookScript then dlg:HookScript("OnShow", ReflowList) end
        if dlg.content and dlg.content.HookScript then dlg.content:HookScript("OnSizeChanged", ReflowList) end
    end

    dlg:SetButtons({ { text = "Fermer", default = true } })
    dlg:Show()
    return dlg
end

-- Prompt texte générique (saisie libre)
function UI.PopupPromptText(title, label, onAccept, opts)
    local dlg = UI.CreatePopup({
        title  = title or "Saisie",
        width  = math.floor(((opts and opts.width)  or 460) * 1.10),
        height = math.floor(((opts and opts.height) or 220) * 1.20),
    })

    local stack = CreateFrame("Frame", nil, dlg.content)
    stack:SetSize(260, 60)
    stack:SetPoint("CENTER")

    local l = stack:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    l:SetText(label or "")
    l:SetPoint("TOP", stack, "TOP", 0, 0)

    local eb = CreateFrame("EditBox", nil, stack, "InputBoxTemplate")
    eb:SetAutoFocus(true); eb:SetSize(260, 28)
    eb:SetPoint("TOP", l, "BOTTOM", 0, -8)

    eb:SetScript("OnEnterPressed", function(self)
        local v = tostring(self:GetText() or "")
        if onAccept then onAccept(v) end
        dlg:Hide()
    end)

    dlg:SetButtons({
        { text = OKAY,   default = true, onClick = function()
            local v = tostring(eb:GetText() or "")
            if onAccept then onAccept(v) end
        end },
        { text = CANCEL, variant = "ghost" },
    })
    dlg:Show()
    return dlg
end

