local ADDON, ns = ...
local Tr = ns and ns.Tr
ns.UI = ns.UI or {}
local UI = ns.UI

-- Base popup (atlas Neutral)
function UI.CreatePopup(opts)
    opts = opts or {}
    local f = CreateFrame("Frame", "GLOG_Popup_" .. math.random(1e8), UIParent, "BackdropTemplate")
    f:SetSize(opts.width or 460, opts.height or 240)

    -- Strate ajustable (par défaut DIALOG). Ne crée l’overlay que si enforceAction=true.
    local wantedStrata = opts.strata or ((opts.enforceAction and "FULLSCREEN_DIALOG") or "DIALOG")
    f:SetFrameStrata(wantedStrata); f:SetToplevel(true)
    if opts.level and type(opts.level) == "number" then f:SetFrameLevel(opts.level) end

    f:SetPoint("CENTER")
    f:SetMovable(true); f:EnableMouse(true)
    if f.SetClampedToScreen then f:SetClampedToScreen(true) end

    -- Habillage Neutral (même look que la fenêtre principale)
    local skin = UI.ApplyNeutralFrameSkin(f, { showRibbon = false, shadow = false })
    local L, R, T, B = skin:GetInsets()

    -- Zone draggable (sur la frise du titre)
    local drag = CreateFrame("Frame", nil, f)
    if skin.header then
        drag:SetAllPoints(skin.header)   -- exactement la zone du décor
    else
        -- fallback si jamais le skin n’a pas de header
        drag:SetPoint("TOP", f, "TOP", 0, -4)
        drag:SetSize(400, 85) -- largeur raisonnable par défaut
    end

    drag:EnableMouse(true)
    drag:RegisterForDrag("LeftButton")
    drag:SetScript("OnDragStart", function() f:StartMoving() end)
    drag:SetScript("OnDragStop",  function() f:StopMovingOrSizing() end)

    -- Titre centré (ancré dans la zone draggable pour rester au-dessus)
    f.title = drag:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    f.title:SetText(Tr(opts.title or "popup_info_title"))
    f.title:SetTextColor(0.98, 0.95, 0.80)

    if UI.PositionTitle then
        UI.PositionTitle(f.title, drag, -85)
    else
        f.title:SetPoint("CENTER", drag, "CENTER", 0, -85)
    end

    if not opts.enforceAction then
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, 2)
        close:SetScript("OnClick", function() f:Hide() end)
    end

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
    local allowEsc = not opts.enforceAction
    f:EnableKeyboard(true)
    f:SetScript("OnKeyDown", function(self, key)
        if key == "ENTER" and self._defaultBtn and self._defaultBtn:IsEnabled() then
            self._defaultBtn:Click()
        elseif key == "ESCAPE" and allowEsc then
            self:Hide()
        end
    end)
    if UISpecialFrames and allowEsc then table.insert(UISpecialFrames, f:GetName()) end

    -- ➕ Overlay plein écran tant que la popup est active (seulement si enforceAction)
    if opts.enforceAction then
        -- La popup doit être au-dessus de tout
        f:SetFrameStrata("FULLSCREEN_DIALOG")

        -- Overlay qui recouvre tout l'écran et absorbe les clics
        -- ⚠️ Strate volontairement PLUS BASSE que la popup pour garantir l'ordre
        local overlay = CreateFrame("Frame", nil, UIParent)
        overlay:SetAllPoints(UIParent)
        overlay:SetFrameStrata("FULLSCREEN") -- était "FULLSCREEN_DIALOG"
        overlay:SetToplevel(false)
        overlay:SetFrameLevel(1)
        overlay:EnableMouse(true)
        if overlay.SetPropagateKeyboardInput then overlay:SetPropagateKeyboardInput(false) end
        overlay:Show()

        -- Fond semi-transparent
        local tex = overlay:CreateTexture(nil, "BACKGROUND")
        tex:SetAllPoints(overlay)
        tex:SetColorTexture(0, 0, 0, 0.75)
        overlay._bg = tex

        -- Consomme les clics pour empêcher toute interaction derrière
        overlay:SetScript("OnMouseDown", function() end)
        overlay:SetScript("OnMouseUp", function() end)
        overlay:EnableMouseWheel(true)
        overlay:SetScript("OnMouseWheel", function() end)

        -- Garde l’overlay SOUS la popup même si quelque chose modifie les strates/niveaux
        f:HookScript("OnShow", function(self)
            overlay:Show()
            -- On réaffirme les strates correctes à chaque affichage
            overlay:SetFrameStrata("FULLSCREEN")
            self:SetFrameStrata("FULLSCREEN_DIALOG")
            -- Niveau laissé bas par sécurité même si la strate suffit
            overlay:SetFrameLevel(1)
        end)
        f:HookScript("OnHide", function()
            overlay:Hide()
        end)

        f._overlay = overlay
    end

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
            local b = UI.Button(self.footer, def.text or "btn_ok", {
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
        title         = (opts and opts.title) or "Confirmation",
        width         = math.floor(((opts and opts.width)  or 460) * 1.10),
        height        = math.floor(((opts and opts.height) or 180) * 1.20),
        strata        = opts and opts.strata,          -- ➕ passe la strate demandée
        enforceAction = opts and opts.enforceAction,   -- ➕ force un overlay et priorité
    })
    dlg:SetMessage(text)
    dlg:SetButtons({
        { text = Tr("btn_confirm"),   default = true, onClick = function() if onAccept then onAccept() end end },
        { text = Tr("btn_cancel"), variant = "ghost", onClick = function() if onCancel then onCancel() end end },
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
        { text = Tr("btn_confirm"),   default = true, onClick = function()
            local v = (eb.GetNumber and eb:GetNumber()) or (tonumber(eb:GetText()) or 0)
            if onAccept then onAccept(v) end
        end },
        { text = Tr("btn_cancel"), variant = "ghost" },
    })
    dlg:Show()
    return dlg
end

-- Demande de transaction entrante (GM)
function UI.PopupRequest(playerName, delta, onApprove, onRefuse)
    local title = "popup_tx_request"
    local dlg = UI.CreatePopup({
        title  = title,
        width  = math.floor(520 * 1.10),
        height = math.floor(220 * 1.20),
    })
    local op = (tonumber(delta) or 0) >= 0 and "|cff40ff40+|r" or "|cffff6060-|r"
    local amt = UI.MoneyText(math.abs(tonumber(delta) or 0))

    dlg:SetMessage(Tr("popup_tx_request_message")
        :format(playerName or "?", op, amt))

    dlg:SetButtons({
        { text = "btn_approve", default = true, onClick = function()
            if onApprove then onApprove() end
            if UI and UI.UpdateRequestsBadge then UI.UpdateRequestsBadge() end
            if ns and ns.RefreshAll then ns.RefreshAll() end
        end },
         { text = "btn_refuse", variant = "ghost", onClick = function()
            if onRefuse then onRefuse() end
            if UI and UI.UpdateRequestsBadge then UI.UpdateRequestsBadge() end
            if ns and ns.RefreshAll then ns.RefreshAll() end
        end },
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
            f.status:SetText(item.exists and Tr("lbl_status_present_colored") or Tr("lbl_status_deleted_colored"))

        end,
    })
    dlg._lv = lv

    local pdb = (GuildLogisticsDB and GuildLogisticsDB.players) or {}
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
    local dlg = UI.CreatePopup({ title = (Tr and Tr(title or "popup_info_title")) or (title or "Information") })
    dlg:SetMessage((Tr and Tr(text)) or text)
    dlg:SetButtons({ { text = Tr("btn_close"), default = true } })
    dlg:Show()
    return dlg
end

-- ✅ Nouveau : popup large avec deux zones de texte sélectionnables (formaté / brut)
function UI.PopupDualText(title, topLabel, topText, bottomLabel, bottomText, opts)
    opts = opts or {}
    local dlg = UI.CreatePopup({
        title  = (Tr and Tr(title or "popup_info_title")) or (title or "Information"),
        width  = opts.width or 820,
        height = opts.height or 560,
    })
    local content = dlg.content

    -- Label supérieur
    local lblTop = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lblTop:SetText((Tr and Tr(topLabel or "")) or (topLabel or ""))
    lblTop:SetPoint("TOPLEFT", content, "TOPLEFT", 12, -8)

    -- Zone supérieure (scroll + EditBox sélectionnable)
    local sfTop = CreateFrame("ScrollFrame", nil, content, "UIPanelScrollFrameTemplate")
    sfTop:SetPoint("TOPLEFT", lblTop, "BOTTOMLEFT", 0, -4)
    sfTop:SetPoint("RIGHT", content, "RIGHT", -12, 0)
    sfTop:SetPoint("BOTTOM", content, "CENTER", 0, -8)

    local ebTop = CreateFrame("EditBox", nil, sfTop)
    ebTop:SetMultiLine(true); ebTop:SetAutoFocus(false)
    ebTop:SetFontObject("ChatFontNormal")
    ebTop:SetJustifyH("LEFT"); ebTop:SetJustifyV("TOP")
    ebTop:SetText(topText or ""); ebTop:ClearFocus(); ebTop:SetCursorPosition(0)
    sfTop:SetScrollChild(ebTop)

    -- Label inférieur
    local lblBottom = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    lblBottom:SetText((Tr and Tr(bottomLabel or "")) or (bottomLabel or ""))
    lblBottom:SetPoint("TOPLEFT", sfTop, "BOTTOMLEFT", 0, -10)

    -- Zone inférieure (scroll + EditBox sélectionnable)
    local sfBottom = CreateFrame("ScrollFrame", nil, content, "UIPanelScrollFrameTemplate")
    sfBottom:SetPoint("TOPLEFT",  lblBottom, "BOTTOMLEFT", 0, -4)
    sfBottom:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -12, 12)

    local ebBottom = CreateFrame("EditBox", nil, sfBottom)
    ebBottom:SetMultiLine(true); ebBottom:SetAutoFocus(false)
    ebBottom:SetFontObject("ChatFontNormal")
    ebBottom:SetJustifyH("LEFT"); ebBottom:SetJustifyV("TOP")
    ebBottom:SetText(bottomText or ""); ebBottom:ClearFocus(); ebBottom:SetCursorPosition(0)
    sfBottom:SetScrollChild(ebBottom)

    -- Ajuste la largeur des EditBox quand la fenêtre change de taille
    local function syncWidth(scroll, edit)
        local function apply() edit:SetWidth(scroll:GetWidth() - 8) end
        scroll:HookScript("OnSizeChanged", apply)
        dlg:HookScript("OnShow", apply)
        apply()
    end
    syncWidth(sfTop, ebTop)
    syncWidth(sfBottom, ebBottom)

    dlg:SetButtons({ { text = Tr("btn_close"), default = true } })
    dlg:Show()
    return dlg
end

function UI.PopupRaidDebit(name, deducted, after, ctx)
    -- Hauteur augmentée pour accueillir le détail des composants
    local dlg = UI.CreatePopup({ title = (Tr and Tr("popup_raid_ok")) or "Participation au raid validée !", width = 660, height = 400 })
    local lines = {}
    lines[#lines+1] = Tr("msg_good_raid") .. "\n"

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
    titleFS:SetText(Tr("msg_good_raid"))

    -- Lignes séparées pour contrôler précisément les espacements
    local dedFS = dlg.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    dedFS:SetJustifyH("CENTER")
    dedFS:SetPoint("TOPLEFT",  titleFS, "BOTTOMLEFT",  0, -12)     -- espace AU-DESSUS de « Montant déduit »
    dedFS:SetPoint("TOPRIGHT", titleFS, "BOTTOMRIGHT", 0, -12)
    dedFS:SetText( Tr("popup_deducted_amount_fmt"):format(
        UI.MoneyText(math.floor(tonumber(deducted) or 0))
    ) )

    local restFS = dlg.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    restFS:SetJustifyH("CENTER")
    restFS:SetPoint("TOPLEFT",  dedFS, "BOTTOMLEFT",  0, -8)       -- espace SOUS « Montant déduit »
    restFS:SetPoint("TOPRIGHT", dedFS, "BOTTOMRIGHT", 0, -8)
    restFS:SetText( Tr("popup_remaining_balance_fmt"):format(
        UI.MoneyText(math.floor(tonumber(after) or 0))
    ) )

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
            { key="lot",   title=Tr("lbl_used_bundles"), min=200, flex=1, justify="LEFT"  },
            { key="price", title=Tr("col_price"),        w=120,              justify="RIGHT" },
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
            local lot = ns and ns.GLOG and ns.GLOG.Lot_GetById and ns.GLOG.Lot_GetById(id)
            local name, perGold
            if lot then
                name    = lot.name or ((metaByLot[id] and metaByLot[id].name) or (Tr("lbl_lot")..tostring(id)))
                perGold = (ns and ns.GLOG and ns.GLOG.Lot_ShareGold and ns.GLOG.Lot_ShareGold(lot)) or 0
            else
                name    = (metaByLot[id] and metaByLot[id].name) or (Tr("lbl_lot")..tostring(id))
                perGold = tonumber(metaByLot[id] and (metaByLot[id].gold or metaByLot[id].g)) or 0
            end

            local gold = math.max(0, (tonumber(perGold) or 0) * (tonumber(usedParts) or 1))
            rows[#rows+1] = { lot = name, price = gold, priceText = UI.MoneyText(gold) }
        end
        table.sort(rows, function(a, b) return (a.lot or ""):lower() < (b.lot or ""):lower() end)

        lv:SetData(rows)
        dlg._lv = lv

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

    dlg:SetButtons({ { text = Tr("btn_close"), default = true } })
    dlg:Show()
    return dlg
end

-- Prompt texte générique (saisie libre)
function UI.PopupPromptText(title, label, onAccept, opts)
    opts = opts or {}
    local dlg = UI.CreatePopup({
        title  = title or "Saisie",
        width  = math.floor((opts.width  or 460) * 1.10),
        height = math.floor((opts.height or 220) * 1.20),
        strata = "FULLSCREEN_DIALOG",  -- au-dessus de la popup des membres
        -- level optionnel si besoin: level = 1000,
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
        { text = Tr("btn_confirm"), default = true, onClick = function()
            local v = tostring(eb:GetText() or "")
            if onAccept then onAccept(v) end
        end },
        { text = Tr("btn_cancel"), variant = "ghost" },
    })
    dlg:Show()
    return dlg
end

-- ➕ Popup spécialisée : invitations calendrier en attente
function UI.PopupPendingCalendarInvites(items)
    local dlg = UI.CreatePopup({
        title  = "pending_invites_title",
        width  = 560,
        height = 360,
    })

    local Tr = ns and ns.Tr or function(s) return s end

    -- Marges autour du texte
    local msg = dlg.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    msg:SetJustifyH("LEFT"); msg:SetJustifyV("TOP")
    msg:SetPoint("TOPLEFT", dlg.content, "TOPLEFT", 10, -10)
    msg:SetPoint("RIGHT",   dlg.content, "RIGHT",   -10, 0)
    msg:SetText(Tr("pending_invites_message_fmt"):format(#(items or {})))

    local listHost = CreateFrame("Frame", nil, dlg.content)
    listHost:SetPoint("TOPLEFT",  dlg.content, "TOPLEFT",  10, -70)
    listHost:SetPoint("BOTTOMRIGHT", dlg.content, "BOTTOMRIGHT", -10, -10)

    local cols = UI.NormalizeColumns({
        { key="when",  title=Tr("col_when"),  w=180 },
        { key="title", title=Tr("col_event"), flex=1, min=200 },
    })
    local lv = UI.ListView(listHost, cols, { emptyText = "lbl_no_data" })
    dlg._lv = lv

    local function weekdayName(ts)
        local w = tonumber(date("%w", ts))
        if w == 0 then return Tr("weekday_sun")
        elseif w == 1 then return Tr("weekday_mon")
        elseif w == 2 then return Tr("weekday_tue")
        elseif w == 3 then return Tr("weekday_wed")
        elseif w == 4 then return Tr("weekday_thu")
        elseif w == 5 then return Tr("weekday_fri")
        else return Tr("weekday_sat") end
    end
    local function fmtWhen(it)
        return string.format("%s %02d/%02d %02d:%02d",
            weekdayName(it.when), it.day or 0, it.month or 0, it.hour or 0, it.minute or 0)
    end

    local function buildRow(r) local f = {}; f.when = UI.Label(r); f.title = UI.Label(r); return f end
    local function updateRow(i, r, f, it)
        f.when:SetText(fmtWhen(it))
        f.title:SetText(it.loc or it.title or "?")
    end

    lv.opts.buildRow  = buildRow
    lv.opts.updateRow = updateRow
    lv:SetData(items or {})

    dlg:SetButtons({
        { text = "btn_open_calendar", default = true, w = 180, onClick = function()
            if ToggleCalendar then ToggleCalendar() elseif Calendar_Toggle then Calendar_Toggle() end
            if dlg.Hide then dlg:Hide() end -- ✏️ fermeture via action
        end },
    })
    dlg:Show()
    return dlg
end

-- ➕ Popup : addon obsolète
function UI.ShowOutdatedAddonPopup(currentVer, latestVer, fromPlayer)
    -- Évite de cumuler plusieurs instances à l’écran
    if UI._obsoleteDlg and UI._obsoleteDlg:IsShown() then return end

    local dlg = UI.CreatePopup({
        title = Tr("popup_outdated_title"),
        width = 520, height = 240, enforceAction = false
    })

    -- Texte informatif
    local content = dlg.content
    local msg = content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    local l1 = string.format(Tr("msg_outdated_line1"), tostring(currentVer or "?"))
    local l2 = string.format(Tr("msg_outdated_line2"), tostring(latestVer or "?"))
    local l3 = Tr("msg_outdated_hint")
    if fromPlayer and fromPlayer ~= "" then
        l3 = l3 .. "\n" .. string.format(Tr("msg_outdated_from"), tostring(fromPlayer))
    end
    msg:SetText(l1.."\n"..l2.."\n\n"..l3)
    msg:SetJustifyH("LEFT"); msg:SetJustifyV("TOP")
    msg:SetPoint("TOPLEFT", content, "TOPLEFT", 12, -12)
    msg:SetPoint("RIGHT", content, "RIGHT", -12, 0)

    dlg:SetButtons({
        { text = Tr("btn_confirm"), default = true },
    })
    dlg:Show()
    UI._obsoleteDlg = dlg
    return dlg
end
