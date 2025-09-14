-- ===================================================
-- Core/Debug/ErrorJournal.lua - Journal des erreurs côté GM
-- ===================================================
-- Stockage, gestion et opérations CRUD sur le journal des erreurs

local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
ns.Util = ns.Util or {}

local GLOG, U = ns.GLOG, ns.Util

-- =========================
-- === Initialisation DB ===
-- =========================

local function ensureJournal()
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.errors = GuildLogisticsDB.errors or { list = {}, nextId = 1 }
end

-- =========================
-- === Gestion des entrées ===
-- =========================

-- Ajoute un rapport d'erreur au journal (sans filtrage de version)
function GLOG.ErrorJournal_AddReport(kv, sender)

    ensureJournal()
    local t = GuildLogisticsDB.errors
    t.list   = t.list   or {}
    t.nextId = tonumber(t.nextId or 1) or 1
    local id = t.nextId
    
    -- Créer l'entrée
    t.list[#t.list+1] = {
        id  = id,
        ts  = tonumber(kv.ts or (time and time()) or 0) or 0,
        who = kv.who or sender or "?",
        ver = kv.ver or "",
        msg = kv.msg or "",
        st  = kv.st  or "",
        done = false, 
    }

    t.nextId = id + 1

    -- Borne mémoire (max 200 entrées)
    local MAX = 200
    if #t.list > MAX then
        while #t.list > MAX do 
            table.remove(t.list, 1) 
        end
    end

    -- Afficher toast si mode debug activé
    local function showErrorToast(kv, sender)
        local debugOn = (GuildLogisticsUI and GuildLogisticsUI.debugEnabled) == true
        if not debugOn or not ns.UI or not ns.UI.ToastError then 
            return 
        end

        local preview = tostring(kv.msg or ""):gsub("\r",""):match("([^\n]+)") or (kv.msg or "")
        if #preview > 140 then 
            preview = preview:sub(1,139) .. "…" 
        end

        local sticky = (GuildLogisticsUI and GuildLogisticsUI.debugStickyErrorToasts) == true

        ns.UI.ToastError(preview, {
            title = (ns.Tr and ns.Tr("toast_error_title")) or "Erreur Lua",
            actionText = (ns.Tr and ns.Tr("btn_view")) or "Voir",
            onAction = function()
                local label = (ns.Tr and ns.Tr("tab_debug_errors")) or "Lua Errors"
                if ns.UI and ns.UI.OpenAndShowTab then
                    ns.UI.OpenAndShowTab(label)
                else
                    -- Fallback robuste : n'appelle ToggleUI que si fermé
                    local main = (ns.UI and ns.UI.Main) or (_G and _G["GLOG_Main"])
                    local shown = main and main.IsShown and main:IsShown()
                    if not shown then
                        if ns and ns.ToggleUI then 
                            ns.ToggleUI()
                        elseif main and main.Show then 
                            main:Show() 
                        end
                    end
                    if ns.UI and ns.UI.ShowTabByLabel then
                        ns.UI.ShowTabByLabel(label)
                    end
                end
            end,
            key = "ERR_TOAST_"..tostring(sender or kv.who or "?"),
            duration = 30,
            sticky   = false,
        })
    end
    
    showErrorToast(kv, sender)

    -- Émettre événement de changement
    if ns.Emit then ns.Emit("errors:changed") end
end

-- =========================
-- === API de consultation ===
-- =========================

-- Récupère la liste complète des erreurs
function GLOG.ErrorJournal_Get()
    ensureJournal()
    return (GuildLogisticsDB.errors and GuildLogisticsDB.errors.list) or {}
end

-- Vide complètement le journal
function GLOG.ErrorJournal_Clear()
    ensureJournal()
    GuildLogisticsDB.errors.list   = {}
    GuildLogisticsDB.errors.nextId = 1
    if ns.Emit then ns.Emit("errors:changed") end
end

-- Marque une entrée comme traitée ou non traitée
function GLOG.ErrorJournal_SetDone(id, done)
    GuildLogisticsDB = GuildLogisticsDB or {}
    local t = GuildLogisticsDB.errors
    if not t or not t.list then return false end
    
    local target = tonumber(id or 0)
    for i = 1, #t.list do
        local it = t.list[i]
        if tonumber(it.id or -1) == target then
            it.done = (done and true) or false
            if ns.Emit then ns.Emit("errors:changed") end
            return true
        end
    end
    return false
end

-- Compte les erreurs non traitées
function GLOG.ErrorJournal_CountOpen()
    GuildLogisticsDB = GuildLogisticsDB or {}
    local list = (GuildLogisticsDB.errors and GuildLogisticsDB.errors.list) or {}
    local n = 0
    for i = 1, #list do 
        if not (list[i].done == true) then 
            n = n + 1 
        end 
    end
    return n
end

-- Supprime une entrée spécifique par ID
function GLOG.ErrorJournal_Remove(id)
    GuildLogisticsDB = GuildLogisticsDB or {}
    local t = GuildLogisticsDB.errors
    if not t or not t.list then return false end
    
    local target = tonumber(id or 0)
    for i = #t.list, 1, -1 do
        local it = t.list[i]
        if tonumber(it.id or -1) == target then
            table.remove(t.list, i)
            if ns.Emit then ns.Emit("errors:changed") end
            return true
        end
    end
    return false
end

-- Supprime toutes les entrées traitées
function GLOG.ErrorJournal_RemoveDone()
    GuildLogisticsDB = GuildLogisticsDB or {}
    local t = GuildLogisticsDB.errors
    if not t or not t.list then return 0 end
    
    local removed = 0
    for i = #t.list, 1, -1 do
        local it = t.list[i]
        if it.done == true then
            table.remove(t.list, i)
            removed = removed + 1
        end
    end
    
    if removed > 0 and ns.Emit then 
        ns.Emit("errors:changed") 
    end
    return removed
end

-- =========================
-- === Rétro-compatibilité ===
-- =========================

-- Aliases pour compatibilité avec l'ancien système
function GLOG.Errors_Get()
    return GLOG.ErrorJournal_Get()
end

function GLOG.Errors_Clear()
    return GLOG.ErrorJournal_Clear()
end

function GLOG.Errors_SetDone(id, done)
    return GLOG.ErrorJournal_SetDone(id, done)
end

function GLOG.Errors_CountOpen()
    return GLOG.ErrorJournal_CountOpen()
end

function GLOG.Errors_AddIncomingReport(kv, sender)
    return GLOG.ErrorJournal_AddReport(kv, sender)
end
