local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
ns.UI   = ns.UI   or {}
ns.Util = ns.Util or {}
ns.Data = ns.Data or {}

local GLOG, UI, U, Data = ns.GLOG, ns.UI, ns.Util, ns.Data
local Tr = ns.Tr or function(s) return s end

local _G = _G
if setfenv then
    setfenv(1, setmetatable({}, { __index = _G, __newindex = _G }))
end

-- =========================
-- === FORMATAGE & AFFICHAGE ===
-- =========================

local function _fmt(rem)
    rem = math.floor(tonumber(rem) or 0 + 0.5)
    if rem <= 0 then
        local ready = Tr("status_ready") or ""
        return "|cff44ff44"..ready.."|r"
    end
    local m = math.floor(rem / 60); local s = rem % 60
    return (m > 0) and string.format("%d:%02d", m, s) or (s .. "s")
end

-- =========================
-- === CONSTRUCTION DONNÉES ===
-- =========================

local function _rowForLive(full)
    local state = ns.GroupTrackerState and ns.GroupTrackerState.GetState() or {}
    local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
    local e = store.expiry and store.expiry[full] or {}
    local now = (time and time() or 0)
    local u = state.uses and state.uses[full] or { heal=0, util=0, stone=0 }
    return {
        name  = full,
        healR = math.max(0, (tonumber(e.heal or 0)  or 0) - now),
        utilR = math.max(0, (tonumber(e.util or 0)  or 0) - now),
        stoneR= math.max(0, (tonumber(e.stone or 0) or 0) - now),
        healN = u.heal or 0,
        utilN = u.util or 0,
        stoneN= u.stone or 0,
    }
end

local function _buildRows()
    local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
    local session = ns.GroupTrackerSession and ns.GroupTrackerSession.GetSession() or {}
    local view = tonumber(store.viewIndex or 1) or 1
    local rows = {}

    if session.inCombat and view == 0 then
        -- Vue live combat
        if ns.GroupTrackerSession and ns.GroupTrackerSession.PurgeStale then
            ns.GroupTrackerSession.PurgeStale()
        end
        
        local roster = {}
        if ns.GroupTrackerSession and ns.GroupTrackerSession.BuildRosterSet then
            roster = ns.GroupTrackerSession.BuildRosterSet()
        end
        
        -- Ajouter le joueur
        do
            local n, r = UnitName("player")
            if n and ns.GroupTrackerSession and ns.GroupTrackerSession.NormalizeName then
                local normalized = ns.GroupTrackerSession.NormalizeName((r and r~="" and (n.."-"..r)) or n)
                roster[normalized] = true
            end
        end
        
        for full in pairs(roster) do
            rows[#rows+1] = _rowForLive(full)
        end
        table.sort(rows, function(a,b)
            local ma = math.max(a.healR or 0, a.utilR or 0, a.stoneR or 0)
            local mb = math.max(b.healR or 0, b.utilR or 0, b.stoneR or 0)
            if ma ~= mb then return ma > mb end
            return (a.name or "") < (b.name or "")
        end)
    else
        -- Vue segment (historique) : on affiche les CD restants actuels si présents
        if (not session.inCombat) and view == 0 then view = 1 end
        local seg = store.segments and store.segments[view]
        if seg then
            local names = {}
            if seg.roster and #seg.roster > 0 then
                for i=1,#seg.roster do names[#names+1] = seg.roster[i] end
            end
            if #names == 0 and seg.data then
                for full in pairs(seg.data) do names[#names+1] = full end
            end
            table.sort(names)
            local now = time and time() or 0
            for _, full in ipairs(names) do
                local evs = (seg.data and seg.data[full] and seg.data[full].events) or {}
                local cnt = { heal=0, util=0, stone=0 }
                for i=1,#evs do
                    local cat = evs[i].cat
                    if cat and cnt[cat] ~= nil then cnt[cat] = cnt[cat] + 1 end
                end
                local e = store.expiry and store.expiry[full] or {}
                local healR = math.max(0, (tonumber(e.heal or 0)  or 0) - now)
                local utilR = math.max(0, (tonumber(e.util or 0)  or 0) - now)
                local stoneR= math.max(0, (tonumber(e.stone or 0) or 0) - now)
                rows[#rows+1] = {
                    name  = full,
                    healR = healR, utilR = utilR, stoneR = stoneR,
                    healN = cnt.heal, utilN = cnt.util, stoneN = cnt.stone,
                }
            end
        end
    end

    return rows
end

-- =========================
-- === POPUP HISTORIQUE ===
-- =========================

-- Popup standard d'historique pour un joueur (segment courant affiché ou live combat)
local function _ShowHistoryPopup(full)
    local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
    local session = ns.GroupTrackerSession and ns.GroupTrackerSession.GetSession() or {}
    local view = tonumber(store.viewIndex or 1) or 1
    local arr

    if session.inCombat and view == 0 then
        local hist = ns.GroupTrackerSession and ns.GroupTrackerSession.GetHist() or {}
        arr = hist[full] or {}
    else
        if (not session.inCombat) and view == 0 then view = 1 end
        local seg = store.segments and store.segments[view]
        arr = (seg and seg.data[full] and seg.data[full].events) or {}
    end

    -- Fusionne les événements d'un même cast (même seconde + même spellID)
    -- et agrège leurs catégories (évite les doublons visuels).
    -- ➕ Applique les exclusions globales (ID/nom) comme le moteur principal.
    local combined, rows = {}, {}
    for i = 1, #arr do
        local ev = arr[i]
        local isExcluded = false
        if ns.GroupTrackerConsumables and ns.GroupTrackerConsumables.IsExcluded then
            isExcluded = ns.GroupTrackerConsumables.IsExcluded(ev.spellID, ev.spellName)
        end
        
        if not isExcluded then
            local key = tostring(ev.t or 0) .. ":" .. tostring(ev.spellID or 0)
            local slot = combined[key]
            local cat  = tostring(ev.cat or "")
            if slot then
                if cat ~= "" then
                    slot._tagset = slot._tagset or {}
                    if not slot._tagset[cat] then
                        slot._tagset[cat] = true
                        slot.tags = slot.tags or {}
                        table.insert(slot.tags, cat)
                    end
                end
            else
                combined[key] = {
                    t = ev.t,
                    spellID = ev.spellID,
                    spellName = ev.spellName,
                    cat  = cat, -- premier tag (fallback affichage)
                    tags = (cat ~= "" and { cat } or {}),
                    _tagset = (cat ~= "" and { [cat] = true } or {}),
                }
            end
        end
    end
    for _, v in pairs(combined) do
        v._tagset = nil -- nettoyage
        table.insert(rows, v)
    end
    table.sort(rows, function(a,b) return (a.t or 0) > (b.t or 0) end)

    -- Libellés (segment courant / live)
    local label, posStr
    if session.inCombat and store.viewIndex == 0 then
        label  = session.label or (Tr("history_combat") or "Combat")
        posStr = "[Live]"
    else
        local view2 = (store.viewIndex == 0) and 1 or store.viewIndex
        local seg   = store.segments and store.segments[view2]
        label  = (seg and seg.label) or (Tr("history_combat") or "Combat")
        posStr = (seg and seg.posStr) or string.format("[%d/%d]", view2, store.segments and #store.segments or 0)
    end

    -- Popup
    local p = UI.CreatePopup and UI.CreatePopup({
        title  = string.format("%s\n%s",
                  Tr("group_tracker_title"),
                  (GLOG and GLOG.ExtractNameOnly and GLOG.ExtractNameOnly(full)) or full or ""),
        width  = 520,
        height = 360,
        strata = "LOW",  -- ✅ Couche basse mais pas la plus basse
        enforceAction = false,
    }) or nil
    if not p then return end

    -- Zone : on libère le footer et on étire la zone de contenu
    do
        local L, R, T, B = 8, 8, 70, 8
        local POP_SIDE, POP_TOP, POP_BOT = (UI.POPUP_SIDE_PAD or 6), (UI.POPUP_TOP_EXTRA_GAP or 18), (UI.POPUP_BOTTOM_LIFT or 4)
        if p.content then
            p.content:ClearAllPoints()
            p.content:SetPoint("TOPLEFT",     p, "TOPLEFT",     L + POP_SIDE, -(T + POP_TOP))
            p.content:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -(R + POP_SIDE), B + POP_BOT)
        end
        if p.footer and p.footer.Hide then p.footer:Hide() end
    end

    -- Liste : rowHeight honoré + scrollbar optionnelle masquée
    local cols = UI.NormalizeColumns({
        { key="time",  title=Tr("col_time"),     w=120,  justify="CENTER" },
        { key="cat",   title=Tr("col_category"), vsep=true,  w=120,  justify="CENTER" },
        { key="icon",  title="",                 vsep=true,  w=38,   justify="CENTER" }, -- 🔸 icône sort/objet
        { key="spell", title=Tr("col_spell"),    min=200, flex=1, justify="LEFT" },
    })

    local lv = UI.ListView(p.content, cols, {
        topOffset = 0,
        buildRow = function(r)
            local w = {}
            w.time  = UI.Label(r, { justify = "CENTER" })
            w.cat   = UI.Label(r, { justify = "CENTER" })
            -- 🔸 petite texture pour l'icône (dimension ajustée à la hauteur de ligne)
            local icon = r:CreateTexture(nil, "ARTWORK")
            icon:SetSize(20, 20) -- sera repositionné/contraint par LayoutRow
            w.icon  = icon
            w.spell = UI.Label(r, { justify = "LEFT" })
            return w
        end,
        updateRow = function(i, r, w, it)
            if not it then return end
            local hhmm = date and date("%H:%M:%S", tonumber(it.t or 0)) or tostring(it.t or "")
            w.time:SetText(hhmm)
            local catText
            if it.tags and #it.tags > 1 then
                local parts = {}
                for _, tag in ipairs(it.tags) do
                    local label = ""
                    if ns.GroupTrackerConsumables and ns.GroupTrackerConsumables.GetCategoryLabel then
                        label = ns.GroupTrackerConsumables.GetCategoryLabel(tag)
                    end
                    table.insert(parts, label)
                end
                catText = table.concat(parts, ", ")
            else
                if ns.GroupTrackerConsumables and ns.GroupTrackerConsumables.GetCategoryLabel then
                    catText = ns.GroupTrackerConsumables.GetCategoryLabel(it.cat)
                end
            end
            w.cat:SetText(catText or "")

            w.spell:SetText(it.spellName or "")
            -- 🔸 choisit l'icône d'item si le sort provient d'un objet, sinon icône du sort
            if w.icon and w.icon.SetTexture then
                local iconTex = "Interface/Icons/INV_Misc_QuestionMark"
                if ns.GroupTrackerConsumables and ns.GroupTrackerConsumables.GetSpellOrItemIcon then
                    iconTex = ns.GroupTrackerConsumables.GetSpellOrItemIcon(it.spellID)
                end
                w.icon:SetTexture(iconTex)
            end
            -- 🔸 Tooltip au survol (objet prioritaire si connu, sinon sort)
            local sid = tonumber(it.spellID or 0) or 0
            local iid = 0
            if ns.GroupTrackerConsumables and ns.GroupTrackerConsumables.GetItemBySpellID then
                local itemBySpellID = ns.GroupTrackerConsumables.GetItemBySpellID()
                iid = (sid > 0 and itemBySpellID and itemBySpellID[sid]) or 0
            end
            if UI and UI.BindItemOrSpellTooltip then
                UI.BindItemOrSpellTooltip(r, iid, sid)
            end
        end,
    })

    -- Applique le masquage de la scrollbar + supprime l'espace à droite
    if UI and UI.ListView_SetScrollbarVisible then
        UI.ListView_SetScrollbarVisible(lv, false)
    end

    -- ➕ Transparence
    if ns.GroupTrackerState then
        ns.GroupTrackerState.SetPopup(p)
    end
    if p then p._lv = lv end
    do
        local a = 1
        if GLOG and GLOG.GroupTracker_GetOpacity then
            a = GLOG.GroupTracker_GetOpacity()
        end
        if UI and UI.ListView_SetRowGradientOpacity then 
            UI.ListView_SetRowGradientOpacity(lv, a) 
        end
    end

    -- Données
    if lv and lv.SetData then lv:SetData(rows) end

    -- Nettoyage
    if ns.GroupTrackerState then
        ns.GroupTrackerState.SetLastPopup(p)
    end
    if p.SetScript then
        p:SetScript("OnHide", function()
            if ns.GroupTrackerState then
                local lastPopup = ns.GroupTrackerState.GetLastPopup()
                local popup = ns.GroupTrackerState.GetPopup()
                if lastPopup == p then ns.GroupTrackerState.SetLastPopup(nil) end
                if popup == p then ns.GroupTrackerState.SetPopup(nil) end
            end
        end)
    end
    
    -- Applique le skin spécialisé pour popup (sans header draggable séparé)
    if UI and UI.ApplyNeutralPopupSkin then
        UI.ApplyNeutralPopupSkin(p)
    end
end

-- =========================
-- === NAVIGATION SEGMENTS ===
-- =========================

-- === Vue & navigation ===
local function _setViewIndex(idx)
    local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
    local session = ns.GroupTrackerSession and ns.GroupTrackerSession.GetSession() or {}
    local max = store.segments and #store.segments or 0
    idx = tonumber(idx) or 0
    local minIdx = (session.inCombat and 0) or 1
    if idx < minIdx then idx = minIdx end
    if idx > max then idx = max end
    store.viewIndex = idx
    
    local state = ns.GroupTrackerState and ns.GroupTrackerState.GetState() or {}
    local win = state.win
    if win and win._Refresh then win:_Refresh() end
end

-- =========================
-- === GESTION COLONNES ===
-- =========================

-- Applique la visibilité des colonnes (heal/util/stone) à un frame contenant la ListView
local function _ApplyColumnsVisibilityToFrame(f)
    if not (f and f._lv) then return end
    local lv = f._lv
    local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
    local vis = store.colVis or { heal=true, util=true, stone=true }

    local base = f._baseCols or lv.cols or {}
    local cols = {}

    -- lookup : idCustom → "heal"|"util"|"stone" (pour colonnes en mode cooldown)
    local cooldownById = {}
    if ns.GroupTrackerConsumables and ns.GroupTrackerConsumables.GetCustomCooldownById then
        cooldownById = ns.GroupTrackerConsumables.GetCustomCooldownById()
    end

    for _, c in ipairs(base) do
        local cc = {}
        for k, v in pairs(c) do cc[k] = v end
        local key = tostring(cc.key or "")
        local show = true

        -- Colonnes personnalisées « cust:ID » : respectent la visibilité de leur catégorie cooldown
        if key:find("^cust:") then
            local id  = key:match("^cust:(.+)$")
            local cat = id and cooldownById[id]
            if cat and (vis[cat] == false) then
                show = false
            end
        end

        if not show then
            cc.w, cc.min, cc.flex = 0, 0, 0
        end
        cols[#cols+1] = cc
    end

    lv.cols = cols
    if lv.header and UI and UI.LayoutHeader then
        UI.LayoutHeader(lv.header, lv.cols, lv.hLabels)
    end
    if lv.Refresh then lv:Refresh() elseif lv.Layout then lv:Layout() end
end

-- Calcule la largeur minimale requise par la ListView + bordures
local function _ComputeMinWindowWidth(f)
    if not (f and f._lv) then
        return math.max(200, (f and f:GetWidth() or 200))
    end
    local lv = f._lv
    local cols = lv.cols or {}

    local sum, visible = 0, 0
    for _, c in ipairs(cols) do
        -- On prend la meilleure estimation "minimale" : max(w, min)
        local w   = tonumber(c and c.w)   or 0
        local wmn = tonumber(c and c.min) or 0
        local ww  = math.max(w, wmn, 0)

        if ww > 0 then
            sum = sum + ww
            visible = visible + 1
        end
    end

    local colSpacing = 0
    local spacing    = (visible > 0) and (colSpacing * (visible - 1)) or 0
    local scrollW    = (lv.scroll and 16) or 16 -- largeur scroll barre verticale
    local padX       = (lv.padX or 12) * 2      -- padding interne ListView
    local frameEdge  = 28                       -- marges/bordures de la fenêtre

    local minW = sum + spacing + scrollW + padX + frameEdge
    -- On borne pour éviter une fenêtre trop petite
    return math.max(50, math.floor(minW + 0.5))
end

-- Applique la largeur minimale ET ajuste la largeur active (snap)
local function _ApplyMinWidthAndResize(f, snapToMin)
    if not f then return end
    local minW = _ComputeMinWindowWidth(f)
    local minH = 160

    if f.SetResizeBounds then
        f:SetResizeBounds(minW, minH)
    elseif f.SetMinResize then
        f:SetMinResize(minW, minH)
    end

    -- Adaptation automatique de la largeur active :
    -- - Si on ajoute une colonne => élargit à minW
    -- - Si on retire une colonne => réduit à minW
    if snapToMin ~= false then
        f:SetWidth(minW)
    else
        -- Variante "non agressive" (on n'utilise pas ici) : seulement si trop petit
        local cur = f:GetWidth() or minW
        if cur < minW then f:SetWidth(minW) end
    end
end

-- =========================
-- === FENÊTRE PRINCIPALE ===
-- =========================

-- Fenêtre principale (épurée via UI.CreatePlainWindow)
local function _ensureWindow()
    local state = ns.GroupTrackerState and ns.GroupTrackerState.GetState() or {}
    local win = state.win
    
    -- Réutiliser la fenêtre existante si elle existe (même si elle est cachée)
    if win then return win end
    if not (UI and UI.CreatePlainWindow and UI.ListView and UI.NormalizeColumns) then 
        return nil 
    end

    local f = UI.CreatePlainWindow({
        title   = "group_tracker_title",
        height  = 160,
        headerHeight = 25,
        strata  = "LOW",  -- ✅ Couche basse mais pas la plus basse (pour éviter les problèmes d'événements)
        level   = 220,
        saveKey = "GroupTrackerWindow",
        defaultPoint    = "LEFT",
        defaultRelPoint = "LEFT",
        defaultX        = 24,
        defaultY        = 0,
        contentPadBottomExtra = -30,
    })
    
    if ns.GroupTrackerState then
        ns.GroupTrackerState.SetWindow(f)
    end

    -- Autorise cette fenêtre à continuer de se rafraîchir même si l'UI principale est fermée
    if UI and UI.MarkAlwaysOn then
        UI.MarkAlwaysOn(f, true)
    end

    -- Conteneur stable pour les boutons de navigation + reset
    if f.hctrl and f.hctrl.Hide then f.hctrl:Hide() end
    f.hctrl = CreateFrame("Frame", nil, f.header)
    -- Laisse 28 px pour le bouton de fermeture (22 + marge 6)
    f.hctrl:ClearAllPoints()
    f.hctrl:SetPoint("RIGHT", f.header, "RIGHT", -28, 0)
    f.hctrl:SetSize(92, 22) -- largeur suffisante pour 3x20 + espacements
    f.hctrl:SetFrameLevel(f.header:GetFrameLevel() + 3)

    -- '>' (plus récent / vers Live)
    if not f.nextBtn then
        f.nextBtn = CreateFrame("Button", nil, f.hctrl)
        f.nextBtn:SetSize(20, 20)
        local txN = f.nextBtn:CreateTexture(nil, "OVERLAY"); txN:SetAllPoints()
        txN:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up")
        f.nextBtn:SetScript("OnClick", function()
            local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
            _setViewIndex((store.viewIndex or 1) - 1) -- vers plus récent / Live
        end)
    else
        f.nextBtn:SetParent(f.hctrl)
        f.nextBtn:SetSize(20, 20)
    end
    f.nextBtn:ClearAllPoints()
    f.nextBtn:SetPoint("RIGHT", f.hctrl, "RIGHT", 0, 0)
    f.nextBtn:SetFrameLevel(f.hctrl:GetFrameLevel() + 1)

    -- '<' (plus ancien)
    if not f.prevBtn then
        f.prevBtn = CreateFrame("Button", nil, f.hctrl)
        f.prevBtn:SetSize(20, 20)
        local txP = f.prevBtn:CreateTexture(nil, "OVERLAY"); txP:SetAllPoints()
        txP:SetTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
        f.prevBtn:SetScript("OnClick", function()
            local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
            _setViewIndex((store.viewIndex or 1) + 1) -- vers plus ancien
        end)
    else
        f.prevBtn:SetParent(f.hctrl)
        f.prevBtn:SetSize(20, 20)
    end
    f.prevBtn:ClearAllPoints()
    f.prevBtn:SetPoint("RIGHT", f.nextBtn, "LEFT", -4, 0)
    f.prevBtn:SetFrameLevel(f.hctrl:GetFrameLevel() + 1)

    -- Corbeille (vider l'historique)
    if f.clearBtn and f.clearBtn.Hide then f.clearBtn:Hide() end
    if not f.clearBtn then
        f.clearBtn = CreateFrame("Button", nil, f.hctrl)
        f.clearBtn:SetSize(20, 20)
        local texPath = "Interface\\PaperDollInfoFrame\\UI-GearManager-LeaveItem-Transparent"
        f.clearBtn:SetNormalTexture(texPath)
        f.clearBtn:SetPushedTexture(texPath)
        f.clearBtn:SetDisabledTexture(texPath)
        f.clearBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        local nrm = f.clearBtn:GetNormalTexture();   if nrm then nrm:SetVertexColor(1, 0.25, 0.25, 1) end
        local psh = f.clearBtn:GetPushedTexture();   if psh then psh:SetVertexColor(1, 0.25, 0.25, 1) end
        local dis = f.clearBtn:GetDisabledTexture(); if dis then dis:SetVertexColor(1, 0.25, 0.25, 0.45); dis:SetDesaturated(true) end
        local hl  = f.clearBtn:GetHighlightTexture(); if hl then hl:SetAlpha(0.22) end
        f.clearBtn:SetScript("OnClick", function()
            if UI and UI.PopupConfirm then
                UI.PopupConfirm(Tr("confirm_clear_history"), function()
                    if GLOG and GLOG.GroupTracker_ClearHistory then
                        GLOG.GroupTracker_ClearHistory()
                    end
                end, nil, { strata = "LOW" })  -- ✅ Couche basse mais pas la plus basse
            else
                if GLOG and GLOG.GroupTracker_ClearHistory then
                    GLOG.GroupTracker_ClearHistory()
                end
            end
        end)
        -- Tooltip
        f.clearBtn:HookScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(Tr("btn_reset_data"))
            GameTooltip:Show()
        end)
        f.clearBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    else
        f.clearBtn:SetParent(f.hctrl)
        f.clearBtn:SetSize(20, 20)
    end
    f.clearBtn:ClearAllPoints()
    f.clearBtn:SetPoint("RIGHT", f.prevBtn, "LEFT", -6, 0)
    f.clearBtn:SetFrameLevel(f.hctrl:GetFrameLevel() + 2)

    -- Recalage automatique si la fenêtre est redimensionnée
    f:HookScript("OnSizeChanged", function()
        if not f.hctrl then return end
        f.hctrl:ClearAllPoints()
        f.hctrl:SetPoint("RIGHT", f.header, "RIGHT", -28, 0)
    end)

    -- Colonnes
    local cols = UI.NormalizeColumns({
        { key="name", title=Tr("col_name"), min=50, flex=1, justify="LEFT" },
    })

    -- ➕ Colonnes personnalisées actives
    local _customCols = {}
    if ns.GroupTrackerConsumables and ns.GroupTrackerConsumables.GetEnabledCustomColumnsOrdered then
        _customCols = ns.GroupTrackerConsumables.GetEnabledCustomColumnsOrdered()
    end
    
    for _, c in ipairs(_customCols) do
        table.insert(cols, { key = "cust:"..tostring(c.id), title = tostring(c.label), w = 54, justify = "CENTER" })
    end

    -- Table de correspondance "colonne custom" → catégorie cooldown ('heal'|'util'|'stone')
    local _cooldownById = {}
    if ns.GroupTrackerConsumables and ns.GroupTrackerConsumables.GetCustomCooldownById then
        _cooldownById = ns.GroupTrackerConsumables.GetCustomCooldownById()
    end

    local lv = UI.ListView(f.content, cols, {
        topOffset = 0,
        rowHeight = 22,
        buildRow = function(r)
            r:EnableMouse(true)
            r:SetScript("OnMouseUp", function(self, button)
                if button == "LeftButton" and self._full then
                    _ShowHistoryPopup(self._full)
                end
            end)
            local w = {}
            w.name = UI.CreateNameTag(r)
            -- Champs dynamiques pour toutes les colonnes personnalisées
            if _customCols then
                for _, c in ipairs(_customCols) do
                    w["cust:"..tostring(c.id)] = UI.Label(r, { justify = "CENTER" })
                end
            end
            return w
        end,
        updateRow = function(i, r, w, it)
            if not it then return end
            r._full = it.name

            -- ✅ Affichage sans serveur, tout en conservant le style
            if UI and UI.SetNameTagShort and w.name then
                UI.SetNameTagShort(w.name, it.name or "")
            elseif UI and UI.SetNameTag and w.name then
                local short = it.name or ""
                if ns and ns.Util and ns.Util.ShortenFullName then
                    short = ns.Util.ShortenFullName(it.name)
                end
                w.name.text:SetText(short)
                UI.SetNameTag(w.name, it.name or "")
            end

            local function cell(rem, n)
                rem = tonumber(rem or 0) or 0
                local base
                if rem <= 0 then
                    local ready = Tr("status_ready") or ""
                    base = "|cff44ff44"..ready.."|r"
                else
                    local m = math.floor(rem / 60); local s = rem % 60
                    base = (m > 0) and string.format("%d:%02d", m, s) or (s .. "s")
                end
                if (n or 0) > 0 then
                    base = base .. " |cffa0a0a0("..tostring(n)..")|r"
                end
                return base
            end

            local function timerFor(cat)
                if cat == "heal"  then return (it.healR  or 0),  (it.healN  or 0) end
                if cat == "util"  then return (it.utilR  or 0),  (it.utilN  or 0) end
                if cat == "stone" then return (it.stoneR or 0),  (it.stoneN or 0) end
                return 0, 0
            end

            -- Colonnes personnalisées : certaines en cooldown (timer), les autres en compteur
            if _customCols then
                local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
                local session = ns.GroupTrackerSession and ns.GroupTrackerSession.GetSession() or {}
                local view = tonumber(store.viewIndex or 1) or 1
                
                local function customCount(full, colId)
                    if session.inCombat and view == 0 then
                        local state = ns.GroupTrackerState and ns.GroupTrackerState.GetState() or {}
                        local cu = state.uses and state.uses[full] and state.uses[full].custom or {}
                        return tonumber(cu[tostring(colId)] or 0) or 0
                    else
                        if (not session.inCombat) and view == 0 then view = 1 end
                        local seg = store.segments and store.segments[view]
                        if not seg then return 0 end
                        local evs = (seg.data and seg.data[full] and seg.data[full].events) or {}
                        local key = "c:"..tostring(colId)
                        local n = 0
                        for i=1,#evs do if evs[i].cat == key then n = n + 1 end end
                        return n
                    end
                end

                for _, c in ipairs(_customCols) do
                    local field = w["cust:"..tostring(c.id)]
                    if field and field.SetText then
                        local cat = _cooldownById[tostring(c.id)]
                        if cat == "heal" or cat == "util" or cat == "stone" then
                            local rem, n = timerFor(cat)
                            field:SetText(cell(rem, n))
                        else
                            local n = customCount(it.name, c.id)
                            field:SetText((n > 0) and tostring(n) or "|cffaaaaaa—|r")
                        end
                    end
                end
            end
        end,
    })
    
    -- ➕ Référence pour appliquer la transparence aux éléments de la ListView
    f._lv = lv
    do
        local a = 1
        if GLOG and GLOG.GroupTracker_GetOpacity then
            a = GLOG.GroupTracker_GetOpacity()
        end
        if UI and UI.ListView_SetVisualOpacity then 
            UI.ListView_SetVisualOpacity(lv, a) 
        end
    end

    -- Mémorise le modèle de colonnes pour les recalculs (show/hide)
    f._baseCols = cols
    -- Applique la visibilité des colonnes selon les préférences
    _ApplyColumnsVisibilityToFrame(f)
    -- Ajuste la largeur minimale ET la largeur active selon les colonnes visibles
    _ApplyMinWidthAndResize(f, true)

    -- Libérer totalement l'espace réservé à la scrollbar (popup light)
    do
        -- API de la ListView si disponible
        if lv and lv.HideScrollbar       then lv:HideScrollbar(true) end
        if lv and lv.SetReserveScrollbar then lv:SetReserveScrollbar(false) end
        if lv and lv.SetRightPadding     then lv:SetRightPadding(30) end

        -- Masquer la barre existante
        local sb = lv and (lv.ScrollBar or (lv.scroll and (lv.scroll.ScrollBar or lv.scrollbar)))
        if sb and sb.Hide then
            sb:Hide()
            if sb.SetWidth    then sb:SetWidth(1) end
            if sb.EnableMouse then sb:EnableMouse(false) end
        end

        -- ✅ Re-ancrer le ScrollFrame sur le conteneur principal (évite la boucle de dépendance)
        if lv and lv.scroll and f and f.content and lv.scroll.ClearAllPoints and lv.scroll.SetPoint then
            lv.scroll:ClearAllPoints()
            lv.scroll:SetPoint("TOPLEFT",     f.content, "TOPLEFT",     0, 0)
            lv.scroll:SetPoint("BOTTOMRIGHT", f.content, "BOTTOMRIGHT", 0, 0)
        end
    end

    local function _updateHeaderTitle()
        local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
        local session = ns.GroupTrackerSession and ns.GroupTrackerSession.GetSession() or {}
        local state = ns.GroupTrackerState and ns.GroupTrackerState.GetState() or {}
        local f = state.win
        if not f then return end

        -- Garde-fous pour éviter les comparaisons nil
        local segCount = (store.segments and #store.segments) or 0
        local view     = tonumber(store.viewIndex)
        if view == nil then view = (segCount > 0) and 1 or 0 end
        if view < 0 then view = 0 end
        if view > segCount then view = segCount end

        -- Calcul du libellé et de la position
        local label, posStr
        if view == 0 then
            -- session "live" (en combat)
            local inCombat = (session.inCombat == true)
            if not inCombat then
                -- si pas en combat, on retombe sur un segment valide si possible
                if segCount > 0 then
                    view = math.min(tonumber(store.viewIndex or 1) or 1, segCount)
                else
                    view = 1
                end
            end

            label  = session.label or Tr("history_combat")
            posStr = "[Live]"

        else
            if (not store.segments or not store.segments[view]) and segCount > 0 then
                -- garde-fou si view est hors bornes
                view = math.min(math.max(view, 1), segCount)
            end
            label  = (store.segments and store.segments[view] and store.segments[view].label) or Tr("history_combat")
            posStr = string.format("[%d/%d]", view, segCount)
        end

        -- Titre de la fenêtre principale
        if f.title and f.title.SetText then
            f.title:SetText(string.format("%s %s\n%s",
                Tr("group_tracker_title"), posStr or "", label or ""))
        elseif f.header and f.header.title and f.header.title.SetText then
            f.header.title:SetText(string.format("%s - %s %s",
                Tr("group_tracker_title"), label or "", posStr or ""))
        end

        -- États/alpha des boutons
        local canNext  = (view > 1)
        local canPrev  = (view < segCount)
        local canClear = (segCount > 0)

        if f.nextBtn  then f.nextBtn:SetEnabled(canNext)  end
        if f.prevBtn  then f.prevBtn:SetEnabled(canPrev)  end
        if f.clearBtn then f.clearBtn:SetEnabled(canClear) end

        local sA = 1
        if GLOG and GLOG.GroupTracker_GetButtonsOpacity then
            sA = GLOG.GroupTracker_GetButtonsOpacity()
        end
        
        if UI and UI.SetButtonAlphaScaled then
            if f.nextBtn  then UI.SetButtonAlphaScaled(f.nextBtn,  canNext  and 1 or 0.35, sA) end
            if f.prevBtn  then UI.SetButtonAlphaScaled(f.prevBtn,  canPrev  and 1 or 0.35, sA) end
            if f.clearBtn then UI.SetButtonAlphaScaled(f.clearBtn, canClear and 1 or 0.35, sA) end
            if f.close    then UI.SetButtonAlphaScaled(f.close,    1.00,          sA) end
        else
            if f.nextBtn  then f.nextBtn:SetAlpha(canNext  and 1 or 0.35) end
            if f.prevBtn  then f.prevBtn:SetAlpha(canPrev  and 1 or 0.35) end
            if f.clearBtn then f.clearBtn:SetAlpha(canClear and 1 or 0.35) end
        end
    end

    function f:_Refresh()
        local rows = _buildRows()
        if lv and lv.SetData then lv:SetData(rows) end
        if _updateHeaderTitle then _updateHeaderTitle() end
    end

    -- Ticker : mise à jour intelligente quand visible (réduit de 1s à 3s pour les performances)
    local state2 = ns.GroupTrackerState and ns.GroupTrackerState.GetState() or {}
    if state2.tick and state2.tick.Cancel then state2.tick:Cancel() end
    if C_Timer and C_Timer.NewTicker then
        local lastRefreshTime = 0
        local tick = C_Timer.NewTicker(3, function()  -- Réduit de 1s à 3s
            if f:IsShown() then 
                -- ⏸️ Pause globale : ne rafraîchir que si autorisé (tracker est une zone always-on)
                if UI and UI.ShouldRefreshUI and not UI.ShouldRefreshUI(f) then return end
                local now = GetTime()
                -- Ne rafraîchit que si assez de temps s'est écoulé depuis la dernière mise à jour manuelle
                if (now - lastRefreshTime) >= 2.5 then
                    f:_Refresh() 
                    lastRefreshTime = now
                end
            end
        end)
        if ns.GroupTrackerState then
            ns.GroupTrackerState.SetTicker(tick)
        end
        
        -- Fonction de rafraîchissement manuel qui met à jour le timestamp
        local originalRefresh = f._Refresh
        f._Refresh = function(...)
            lastRefreshTime = GetTime()
            return originalRefresh(...)
        end
    end

    f:Show()
    f:_Refresh()
    return f
end

-- =========================
-- ===   API PUBLIQUE    ===
-- =========================

ns.GroupTrackerUI = {
    -- Fenêtre principale
    EnsureWindow = function() return _ensureWindow() end,
    
    -- Navigation
    SetViewIndex = function(idx) return _setViewIndex(idx) end,
    
    -- Popup historique
    ShowHistoryPopup = function(full) return _ShowHistoryPopup(full) end,
    
    -- Gestion des colonnes
    ApplyColumnsVisibilityToFrame = function(f) return _ApplyColumnsVisibilityToFrame(f) end,
    ApplyMinWidthAndResize = function(f, snapToMin) return _ApplyMinWidthAndResize(f, snapToMin) end,
    ComputeMinWindowWidth = function(f) return _ComputeMinWindowWidth(f) end,
    
    -- Construction des données d'affichage
    BuildRows = function() return _buildRows() end,
    FormatTime = function(rem) return _fmt(rem) end,
}

-- Export vers le namespace global pour compatibilité
ns.GLOG.GroupTrackerUI = ns.GroupTrackerUI
