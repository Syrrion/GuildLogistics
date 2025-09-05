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
-- === HANDLERS CONSOMMABLES ===
-- =========================

-- MÀJ DATA : appelé quand un consommable est utilisé
local function _onConsumableUsed(sourceName, cat, spellID, spellName)
    if not sourceName or not cat then return end
    
    local full = ""
    if ns.GroupTrackerSession and ns.GroupTrackerSession.NormalizeName then
        full = ns.GroupTrackerSession.NormalizeName(sourceName)
    else
        full = tostring(sourceName or "")
    end
    if full == "" then return end

    -- Compteurs (session live combat)
    local state = ns.GroupTrackerState and ns.GroupTrackerState.GetState() or {}
    state.uses = state.uses or {}
    state.uses[full] = state.uses[full] or { heal=0, util=0, stone=0 }
    state.uses[full][cat] = (state.uses[full][cat] or 0) + 1

    -- Expiration absolue persistante (résiste au /reload)
    local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
    store.expiry = store.expiry or {}
    store.expiry[full] = store.expiry[full] or {}
    
    local cd = 0
    if GLOG and GLOG.GroupTrackerGetCooldown then
        cd = GLOG.GroupTrackerGetCooldown(cat)
    end
    store.expiry[full][cat] = (time and time() or 0) + cd

    -- Historique live combat
    if ns.GroupTrackerSession and ns.GroupTrackerSession.PushEvent then
        ns.GroupTrackerSession.PushEvent(full, cat, spellID, spellName, time and time() or 0)
    end

    -- Rafraîchir l'UI
    local win = state.win
    if win and win._Refresh then win:_Refresh() end
end

-- Compteur pour colonnes personnalisées
local function _onCustomUsed(sourceName, colId, spellID, spellName)
    if not sourceName or not colId then return end
    
    local full = ""
    if ns.GroupTrackerSession and ns.GroupTrackerSession.NormalizeName then
        full = ns.GroupTrackerSession.NormalizeName(sourceName)
    else
        full = tostring(sourceName or "")
    end
    if full == "" then return end

    local state = ns.GroupTrackerState and ns.GroupTrackerState.GetState() or {}
    state.uses = state.uses or {}
    state.uses[full] = state.uses[full] or { heal=0, util=0, stone=0 }
    state.uses[full].custom = state.uses[full].custom or {}
    state.uses[full].custom[tostring(colId)] = (state.uses[full].custom[tostring(colId)] or 0) + 1

    -- Historique live combat (cat = "c:<id>")
    if ns.GroupTrackerSession and ns.GroupTrackerSession.PushEvent then
        ns.GroupTrackerSession.PushEvent(full, "c:"..tostring(colId), spellID, spellName, time and time() or 0)
    end

    -- Rafraîchir l'UI
    local win = state.win
    if win and win._Refresh then win:_Refresh() end
end

-- =========================
-- === API ÉTAT & ACTIVATION ===
-- =========================

function GLOG.GroupTrackerIsEnabled()
    local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
    return store.enabled == true
end

function GLOG.GroupTrackerSetEnabled(on)
    local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
    store.enabled = (on == true)
    
    local state = ns.GroupTrackerState and ns.GroupTrackerState.GetState() or {}
    state.enabled = store.enabled
    
    if on then
        GLOG.GroupTracker_ShowWindow(true)
    else
        GLOG.GroupTracker_ShowWindow(false)
    end
end

-- =========================
-- === API COOLDOWNS ===
-- =========================

function GLOG.GroupTrackerSetCooldown(cat, sec)
    local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
    store.cooldown = store.cooldown or { heal = 300, util = 300, stone = 300 }
    if cat and store.cooldown[cat] ~= nil then
        store.cooldown[cat] = math.max(0, tonumber(sec) or store.cooldown[cat] or 300)
    end
end

function GLOG.GroupTrackerGetCooldown(cat)
    local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
    local cd = (store.cooldown and store.cooldown[cat or ""]) or 300
    return tonumber(cd) or 300
end

-- =========================
-- === API RESET & CLEAR ===
-- =========================

function GLOG.GroupTracker_Reset()
    if ns.GroupTrackerSession and ns.GroupTrackerSession.ClearLive then
        ns.GroupTrackerSession.ClearLive()
    end
    
    local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
    if store.expiry then wipe(store.expiry) end
    
    local state = ns.GroupTrackerState and ns.GroupTrackerState.GetState() or {}
    local win = state.win
    if win and win._Refresh then win:_Refresh() end
end

function GLOG.GroupTracker_ClearHistory()
    local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
    if store.segments then wipe(store.segments) end
    
    local session = ns.GroupTrackerSession and ns.GroupTrackerSession.GetSession() or {}
    store.viewIndex = session.inCombat and 0 or 1
    
    local state = ns.GroupTrackerState and ns.GroupTrackerState.GetState() or {}
    local win = state.win
    if win and win._Refresh then win:_Refresh() end
end

-- =========================
-- === API FENÊTRE ===
-- =========================

local function _RefreshEventSubscriptions()
    if ns.GroupTrackerState and ns.GroupTrackerState.RecomputeEnabled then
        ns.GroupTrackerState.RecomputeEnabled()
    end
    
    -- Cette fonction sera complétée par le module Events
    if ns.GroupTrackerEvents and ns.GroupTrackerEvents.RefreshSubscriptions then
        ns.GroupTrackerEvents.RefreshSubscriptions()
    end
end

function GLOG.GroupTracker_ShowWindow(show)
    local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
    local state = ns.GroupTrackerState and ns.GroupTrackerState.GetState() or {}
    
    if show then
        state.enabled = true
        
        -- Créer/montrer la fenêtre
        local f = nil
        if ns.GroupTrackerUI and ns.GroupTrackerUI.EnsureWindow then
            f = ns.GroupTrackerUI.EnsureWindow()
        else
            print("GroupTracker: GroupTrackerUI or EnsureWindow not available")
        end
        if not f then 
            print("GroupTracker: Failed to create window")
            return 
        end

        -- Mémoriser l'ouverture et hooker OnShow/OnHide (une seule fois)
        store.winOpen = true
        if not f._openStateHooked then
            f:HookScript("OnShow", function()
                local st = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
                st.winOpen = true
                if _RefreshEventSubscriptions then
                    _RefreshEventSubscriptions()
                end
            end)
            f:HookScript("OnHide", function()
                local st = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
                st.winOpen = false
                if _RefreshEventSubscriptions then
                    _RefreshEventSubscriptions()
                end
            end)
            f._openStateHooked = true
        end

        -- Applique les réglages actuels
        local aWin   = (GLOG.GroupTracker_GetOpacity           and GLOG.GroupTracker_GetOpacity())            or 0.95
        local aText  = (GLOG.GroupTracker_GetTextOpacity       and GLOG.GroupTracker_GetTextOpacity())        or 1.00
        local aTitle = (GLOG.GroupTracker_GetTitleTextOpacity  and GLOG.GroupTracker_GetTitleTextOpacity())   or 1.00
        local aBtnS  = (GLOG.GroupTracker_GetButtonsOpacity    and GLOG.GroupTracker_GetButtonsOpacity())     or 1.00
        local rowH   = (GLOG.GroupTracker_GetRowHeight         and GLOG.GroupTracker_GetRowHeight())          or 22

        if UI and UI.SetFrameVisualOpacity   then UI.SetFrameVisualOpacity(f, aWin)            end
        if UI and UI.SetTextAlpha            then UI.SetTextAlpha(f, aText)                    end
        if UI and UI.SetFrameTitleTextAlpha  then UI.SetFrameTitleTextAlpha(f, aTitle)         end
        if f._lv and UI and UI.ListView_SetVisualOpacity then UI.ListView_SetVisualOpacity(f._lv, aWin) end
        if f._lv and UI and UI.ListView_SetRowHeight     then UI.ListView_SetRowHeight(f._lv, rowH)     end

        -- Respecte le masquage/affichage des colonnes choisi par l'utilisateur
        if ns.GroupTrackerUI and ns.GroupTrackerUI.ApplyColumnsVisibilityToFrame then
            ns.GroupTrackerUI.ApplyColumnsVisibilityToFrame(f)
        end
        -- Adapte la largeur minimale + largeur active en fonction des colonnes visibles
        if ns.GroupTrackerUI and ns.GroupTrackerUI.ApplyMinWidthAndResize then
            ns.GroupTrackerUI.ApplyMinWidthAndResize(f, true)
        end

        -- Applique le lock d'interactions si actif
        if UI and UI.PlainWindow_SetLocked and GLOG and GLOG.GroupTracker_GetLocked then
            UI.PlainWindow_SetLocked(f, GLOG.GroupTracker_GetLocked())
        end

        -- Assure une ancre gauche du titre (sécurité)
        if f.title and f.header then
            f.title:ClearAllPoints()
            f.title:SetPoint("LEFT", f.header, "LEFT", 8, 0)
            if f.title.SetJustifyH then f.title:SetJustifyH("LEFT") end
        end

        -- Le X ferme la fenêtre
        if f.close then
            f.close:SetScript("OnClick", function() f:Hide() end)
        end

        f:Show()
        if f._Refresh then f:_Refresh() end

    else
        -- Masquer la fenêtre et ajuster l'état
        state.enabled = false
        store.winOpen = false

        local win = state.win
        if win and win:IsShown() then
            win:Hide()  -- Déclenchera OnHide et donc _RefreshEventSubscriptions
        end

        -- Par cohérence, masquer aussi la popup d'historique si ouverte
        local popup = state.popup
        if popup and popup:IsShown() then
            popup:Hide()
        end

        -- Si jamais aucun OnHide n'a été hooké (sécurité)
        if _RefreshEventSubscriptions then
            _RefreshEventSubscriptions()
        end
    end
end

-- =========================
-- === API LOCK ===
-- =========================

function GLOG.GroupTracker_GetLocked()
    local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
    return store.locked == true
end

function GLOG.GroupTracker_SetLocked(flag)
    local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
    store.locked = (flag == true)
    
    local state = ns.GroupTrackerState and ns.GroupTrackerState.GetState() or {}
    local win = state.win
    if win and UI and UI.PlainWindow_SetLocked then
        UI.PlainWindow_SetLocked(win, store.locked)
        -- Optionnel : ré-applique l'opacité des boutons pour refléter l'état (enabled/disabled)
        if UI.ApplyButtonsOpacity and GLOG.GroupTracker_GetButtonsOpacity then
            UI.ApplyButtonsOpacity(win, GLOG.GroupTracker_GetButtonsOpacity())
        end
    end
end

-- =========================
-- === API OPACITÉS ===
-- =========================

function GLOG.GroupTracker_GetOpacity()
    if ns.Util and ns.Util.GetClampedOption then
        local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
        return ns.Util.GetClampedOption(store, "opacity", 1, 0, 1)
    end
    local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
    local a = tonumber(store.opacity or 0.95) or 0.95
    if a < 0 then a = 0 elseif a > 1 then a = 1 end
    return a
end

function GLOG.GroupTracker_SetOpacity(a)
    local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
    a = tonumber(a or 0.95) or 0.95
    if a < 0 then a = 0 elseif a > 1 then a = 1 end
    store.opacity = a

    local state = ns.GroupTrackerState and ns.GroupTrackerState.GetState() or {}
    -- Fenêtre principale
    local win = state.win
    if win and UI and UI.SetFrameVisualOpacity then
        UI.SetFrameVisualOpacity(win, a)
    end
    -- ListView de la fenêtre principale
    if win and win._lv and UI and UI.ListView_SetVisualOpacity then
        UI.ListView_SetVisualOpacity(win._lv, a)
    end

    -- Popup d'historique + ListView interne
    local popup = state.popup
    if popup then
        if UI and UI.SetFrameVisualOpacity then UI.SetFrameVisualOpacity(popup, a) end
        if popup._lv and UI and UI.ListView_SetVisualOpacity then
            UI.ListView_SetVisualOpacity(popup._lv, a)
        end
    end
end

function GLOG.GroupTracker_GetTextOpacity()
    if ns.Util and ns.Util.GetClampedOption then
        local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
        return ns.Util.GetClampedOption(store, "textOpacity", 1.0, 0.1, 1)
    end
    local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
    local a = tonumber(store.textOpacity or 1.0) or 1.0
    if a < 0.1 then a = 0.1 elseif a > 1 then a = 1 end
    return a
end

function GLOG.GroupTracker_SetTextOpacity(a)
    local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
    a = tonumber(a or 1.0) or 1.0
    if a < 0.1 then a = 0.1 elseif a > 1 then a = 1 end
    store.textOpacity = a
    
    local state = ns.GroupTrackerState and ns.GroupTrackerState.GetState() or {}
    local win = state.win
    if win and UI and UI.ApplyTextAlpha then
        UI.ApplyTextAlpha(win, a)
        -- Ré-applique le titre avec son alpha dédié pour le désolidariser du "texte global"
        if UI.SetFrameTitleTextAlpha and GLOG.GroupTracker_GetTitleTextOpacity then
            UI.SetFrameTitleTextAlpha(win, GLOG.GroupTracker_GetTitleTextOpacity())
        end
    end
end

function GLOG.GroupTracker_GetTitleTextOpacity()
    local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
    local a = tonumber(store.titleTextOpacity or 1.0) or 1.0
    if a < 0 then a = 0 elseif a > 1 then a = 1 end
    return a
end

function GLOG.GroupTracker_SetTitleTextOpacity(a)
    local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
    a = tonumber(a or 1.0) or 1.0
    if a < 0 then a = 0 elseif a > 1 then a = 1 end
    store.titleTextOpacity = a
    
    local state = ns.GroupTrackerState and ns.GroupTrackerState.GetState() or {}
    local win = state.win
    if win and UI and UI.SetFrameTitleTextAlpha then
        UI.SetFrameTitleTextAlpha(win, a)
    end
end

function GLOG.GroupTracker_GetButtonsOpacity()
    if ns.Util and ns.Util.GetClampedOption then
        local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
        return ns.Util.GetClampedOption(store, "btnOpacity", 1.0, 0, 1)
    end
    local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
    local a = tonumber(store.btnOpacity or 1.0) or 1.0
    if a < 0 then a = 0 elseif a > 1 then a = 1 end
    return a
end

function GLOG.GroupTracker_SetButtonsOpacity(a)
    local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
    a = tonumber(a or 1.0) or 1.0
    if a < 0 then a = 0 elseif a > 1 then a = 1 end
    store.btnOpacity = a

    local state = ns.GroupTrackerState and ns.GroupTrackerState.GetState() or {}
    -- Applique immédiatement à la fenêtre principale (si ouverte)
    local win = state.win
    if win and UI and UI.ApplyButtonsOpacity then
        UI.ApplyButtonsOpacity(win, a)
    end
    -- Applique à la popup d'historique (si ouverte)
    local popup = state.popup
    if popup and UI and UI.ApplyButtonsOpacity then
        UI.ApplyButtonsOpacity(popup, a)
    end
end

-- =========================
-- === API COLONNES ===
-- =========================

-- Visibilité des colonnes (fenêtre flottante)
function GLOG.GroupTracker_GetColumnVisible(key)
    local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
    local v = (store.colVis or {})[tostring(key or "")]
    if v == nil then return true end
    return v == true
end

function GLOG.GroupTracker_SetColumnVisible(key, visible)
    key = tostring(key or "")
    if key ~= "heal" and key ~= "util" and key ~= "stone" then return end
    
    local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
    store.colVis = store.colVis or { heal=true, util=true, stone=true }
    store.colVis[key] = (visible == true)

    -- Applique immédiatement si la fenêtre est ouverte
    local state = ns.GroupTrackerState and ns.GroupTrackerState.GetState() or {}
    local win = state.win
    if win and ns.GroupTrackerUI and ns.GroupTrackerUI.ApplyColumnsVisibilityToFrame then
        ns.GroupTrackerUI.ApplyColumnsVisibilityToFrame(win)
    end
    -- Ajuste la largeur minimale et la largeur active (réduction/agrandissement auto)
    if win and ns.GroupTrackerUI and ns.GroupTrackerUI.ApplyMinWidthAndResize then
        ns.GroupTrackerUI.ApplyMinWidthAndResize(win, true)
    end
end

-- =========================
-- === API HAUTEUR LIGNE ===
-- =========================

-- Hauteur de ligne de la listview (fenêtre minimaliste)
function GLOG.GroupTracker_GetRowHeight()
    local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
    local h = tonumber(store.rowHeight or 22) or 22
    if h < 12 then h = 12 elseif h > 48 then h = 48 end
    return h
end

function GLOG.GroupTracker_SetRowHeight(px)
    local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
    local v = tonumber(px)
    if not v then return end
    if v < 12 then v = 12 elseif v > 48 then v = 48 end
    store.rowHeight = v

    -- Si la fenêtre est ouverte, applique immédiatement
    local state = ns.GroupTrackerState and ns.GroupTrackerState.GetState() or {}
    local win = state.win
    if win and win._lv and UI and UI.ListView_SetRowHeight then
        UI.ListView_SetRowHeight(win._lv, v)
        if win._Refresh then win:_Refresh() end
    end
end

-- =========================
-- === API SUIVI PERSONNALISÉ ===
-- =========================

-- API Suivi personnalisé (CRUD colonnes)
function GLOG.GroupTracker_Custom_List()
    local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
    return (store.custom and store.custom.columns) or {}
end

function GLOG.GroupTracker_Custom_AddOrUpdate(obj)
    if type(obj) ~= "table" then return nil end
    
    local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
    store.custom = store.custom or {}
    store.custom.columns = store.custom.columns or {}
    store.custom.nextId = tonumber(store.custom.nextId or 1) or 1

    local function normList(t)
        local out = {}
        if type(t) == "table" then
            for _, v in ipairs(t) do
                local n = tonumber(v)
                if n then table.insert(out, n) end
            end
        end
        return out
    end
    
    obj.spellIDs = normList(obj.spellIDs)
    obj.itemIDs  = normList(obj.itemIDs)
    
    local kws = {}
    if type(obj.keywords) == "table" then
        for _, k in ipairs(obj.keywords) do
            local s = tostring(k or ""):gsub("^%s+",""):gsub("%s+$","")
            if s ~= "" then table.insert(kws, s) end
        end
    end
    obj.keywords = kws

    local id = tostring(obj.id or "")
    if id == "" then
        id = "C" .. tostring(store.custom.nextId)
        store.custom.nextId = store.custom.nextId + 1
        obj.id = id
        table.insert(store.custom.columns, obj)
    else
        local found = false
        for i, c in ipairs(store.custom.columns) do
            if tostring(c.id) == id then
                store.custom.columns[i] = obj
                found = true
                break
            end
        end
        if not found then table.insert(store.custom.columns, obj) end
    end

    if ns.GroupTrackerConsumables and ns.GroupTrackerConsumables.RebuildCustomLookup then
        ns.GroupTrackerConsumables.RebuildCustomLookup()
    end
    if GLOG and GLOG.GroupTracker_RecreateWindow then 
        GLOG.GroupTracker_RecreateWindow() 
    end
    return id
end

function GLOG.GroupTracker_Custom_Delete(id)
    local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
    local cols = (store.custom and store.custom.columns) or {}
    for i = #cols, 1, -1 do
        if tostring(cols[i].id) == tostring(id) then table.remove(cols, i) end
    end
    if ns.GroupTrackerConsumables and ns.GroupTrackerConsumables.RebuildCustomLookup then
        ns.GroupTrackerConsumables.RebuildCustomLookup()
    end
    if GLOG and GLOG.GroupTracker_RecreateWindow then 
        GLOG.GroupTracker_RecreateWindow() 
    end
end

-- Déplace une colonne identifiée par 'id' de 'delta' positions (+1 = descendre, -1 = monter)
function GLOG.GroupTracker_Custom_Move(id, delta)
    delta = tonumber(delta) or 0
    if delta == 0 then return end
    
    local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
    local cols = (store.custom and store.custom.columns) or {}
    local n = #cols
    if n <= 1 then return end

    local idx = nil
    for i = 1, n do
        if tostring(cols[i].id) == tostring(id) then idx = i; break end
    end
    if not idx then return end

    local newIdx = math.max(1, math.min(n, idx + delta))
    if newIdx == idx then return end

    local entry = table.remove(cols, idx)
    table.insert(cols, newIdx, entry)

    if ns.GroupTrackerConsumables and ns.GroupTrackerConsumables.RebuildCustomLookup then
        ns.GroupTrackerConsumables.RebuildCustomLookup()
    end
    if GLOG and GLOG.GroupTracker_RecreateWindow then 
        GLOG.GroupTracker_RecreateWindow() 
    end
end

function GLOG.GroupTracker_RecreateWindow()
    local state = ns.GroupTrackerState and ns.GroupTrackerState.GetState() or {}
    local win = state.win
    if win then
        local wasOpen = win:IsShown()
        
        -- Forcer la sauvegarde de la position avant de détruire la fenêtre
        if win.SetScript then
            -- Déclencher manuellement l'event OnHide pour sauvegarder
            local onHideScript = win:GetScript("OnHide")
            if onHideScript then
                onHideScript(win)
            end
        end
        
        win:Hide()
        if ns.GroupTrackerState then
            ns.GroupTrackerState.SetWindow(nil)
        end
        if wasOpen and GLOG and GLOG.GroupTracker_ShowWindow then
            GLOG.GroupTracker_ShowWindow(true)
        end
    end
end

-- =========================
-- === API SEED DÉFAUT ===
-- =========================

-- Seed des listes par défaut (Potions, Prépot, Pierre de soins)
function GLOG.GroupTracker_EnsureDefaultCustomLists(force)
    if ns.GroupTrackerConsumables and ns.GroupTrackerConsumables.EnsureDefaultCustomLists then
        ns.GroupTrackerConsumables.EnsureDefaultCustomLists(force == true)
    end
end

function GLOG.GroupTracker_RebuildCustomMapping()
    if ns.GroupTrackerConsumables and ns.GroupTrackerConsumables.RebuildCustomLookup then
        ns.GroupTrackerConsumables.RebuildCustomLookup()
    end
end

-- =========================
-- === API ENREGISTREMENT ===
-- =========================

function GLOG.GroupTracker_GetRecordingEnabled()
    local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
    return store.recording == true
end

function GLOG.GroupTracker_SetRecordingEnabled(enabled)
    local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
    store.recording = (enabled == true)

    if store.recording then
        -- Suivi actif : (ré)abonne les événements
        _RefreshEventSubscriptions()
    else
        -- Suivi inactif : on masque si besoin puis on coupe les événements
        local state = ns.GroupTrackerState and ns.GroupTrackerState.GetState() or {}
        local win = state.win
        if win and win:IsShown() then
            GLOG.GroupTracker_ShowWindow(false) -- OnHide fera aussi _RefreshEventSubscriptions()
        end
        _RefreshEventSubscriptions()
    end
end

-- =========================
-- === API POPUP ===
-- =========================

function GLOG.GroupTracker_IsPopupTitleHidden()
    local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
    return store.popupTitleTextHidden == true
end

function GLOG.GroupTracker_SetPopupTitleHidden(hidden)
    local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
    store.popupTitleTextHidden = (hidden == true)
    
    local state = ns.GroupTrackerState and ns.GroupTrackerState.GetState() or {}
    local popup = state.popup
    if popup and UI and UI.SetFrameTitleVisibility then
        UI.SetFrameTitleVisibility(popup, not store.popupTitleTextHidden)
    end
end

function GLOG.GroupTracker_TogglePopupTitleHidden()
    local store = ns.GroupTrackerState and ns.GroupTrackerState.GetStore() or {}
    GLOG.GroupTracker_SetPopupTitleHidden(not (store.popupTitleTextHidden == true))
end

-- =========================
-- === HANDLERS EXPORTS ===
-- =========================

-- Export des handlers pour utilisation par le module Events
ns.GroupTrackerAPI = {
    OnConsumableUsed = _onConsumableUsed,
    OnCustomUsed = _onCustomUsed,
    RefreshEventSubscriptions = _RefreshEventSubscriptions,
}

-- Export vers le namespace global pour compatibilité
ns.GLOG.GroupTrackerAPI = ns.GroupTrackerAPI
