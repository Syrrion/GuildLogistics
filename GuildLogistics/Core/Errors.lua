local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
ns.Util = ns.Util or {}
ns.Events = ns.Events or {}

local GLOG, U, E = ns.GLOG, ns.Util, ns.Events

-- === Helpers joueur/GM ===
local function playerFullName()
    if U and U.playerFullName then return U.playerFullName() end
    local n, r = UnitName and UnitName("player"), GetNormalizedRealmName and GetNormalizedRealmName()
    if n and r and r ~= "" then return (tostring(n) .. "-" .. tostring(r):gsub("%s+",""):gsub("'","")) end
    return tostring(n or "player")
end

-- Ne garde que les erreurs dont **la ligne fautive** (1ʳᵉ ligne du message)
-- pointe dans notre AddOn. On **ignore la pile d'appel**.
local function _isOurError(msg, _stack)
    local m = tostring(msg or "")
    -- Extraire uniquement la 1ʳᵉ ligne (format standard WoW: "Interface\AddOns\...\file.lua:123: ...")
    local first = m:match("^[^\r\n]+") or ""

    -- Détection stricte sur le chemin de la 1ʳᵉ ligne
    if first:find("[\\/]AddOns[\\/]GuildLogistics[\\/]", 1) then
        return true
    end

    -- Si la 1ʳᵉ ligne n'indique pas un fichier de notre AddOn, on rejette
    return false
end


-- Anti-spam par signature (mémoire session)
local _seen = {}
local function _sig(msg, stack)
    local line1 = tostring(msg or ""):gsub("%s+"," "):sub(1, 160)
    local top   = tostring(stack or ""):match("([^\n\r]+)") or ""
    return line1 .. " | " .. top
end

-- Construction d’un rapport compact
local function _buildReport(msg)
    return {
        ts  = (time and time()) or 0,
        who = playerFullName(),
        ver = (GLOG.GetAddonVersion and GLOG.GetAddonVersion()) or "",
        msg = tostring(msg or ""),
        st  = tostring((debugstack and debugstack(3)) or ""),
    }
end

-- === Emission (même principe que TX_REQ) : direct si GM en ligne, sinon pending ===
function GLOG.Errors_SendOrQueue(rep)
    local gmName = GLOG.GetGuildMasterCached and select(1, GLOG.GetGuildMasterCached())
    local online = (GLOG.IsMasterOnline and GLOG.IsMasterOnline()) or false
    if gmName and online and GLOG.Comm_Whisper then
        GLOG.Comm_Whisper(gmName, "ERR_REPORT", rep)
    else
        if GLOG.Pending_AddERRRPT then
            GLOG.Pending_AddERRRPT(rep)
        end
    end
end

-- === Journal côté GM (réception) ===
local function _ensureJournal()
    GuildLogisticsDB = GuildLogisticsDB or {}
    GuildLogisticsDB.errors = GuildLogisticsDB.errors or { list = {}, nextId = 1 }
end

function GLOG.Errors_AddIncomingReport(kv, sender)
    -- Filtrage version : n'accepter que si ver(emetteur) >= ver(GM)
    local myVer  = (GLOG.GetAddonVersion and GLOG.GetAddonVersion()) or ""
    local hisVer = tostring(kv and kv.ver or "")
    if hisVer == "" then
        return -- version inconnue côté émetteur -> on ignore
    end
    if U and U.CompareVersions and U.CompareVersions(hisVer, myVer) < 0 then
        return -- émetteur plus ancien que le GM -> on ignore
    end

    _ensureJournal()
    local t = GuildLogisticsDB.errors
    t.list   = t.list   or {}
    t.nextId = tonumber(t.nextId or 1) or 1
    local id = t.nextId
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

    -- borne mémoire
    local MAX = 200
    if #t.list > MAX then
        while #t.list > MAX do table.remove(t.list, 1) end
    end

    -- 🔔 Toast côté GM quand une erreur est reçue (ou ajoutée localement)
    -- 👉 Afficher UNIQUEMENT si le mode Débug est activé
    local debugOn = (GuildLogisticsUI and GuildLogisticsUI.debugEnabled) == true
    if debugOn and ns.UI and ns.UI.ToastError then
        local preview = tostring(kv.msg or ""):gsub("\r",""):match("([^\n]+)") or (kv.msg or "")
        if #preview > 140 then preview = preview:sub(1,139) .. "…" end

        local sticky = (GuildLogisticsUI and GuildLogisticsUI.debugStickyErrorToasts) == true

        ns.UI.ToastError(preview, {
            title = (ns.Tr and ns.Tr("toast_error_title")) or "Erreur Lua",
            actionText = (ns.Tr and ns.Tr("btn_view")) or "Voir",
            onAction = function()
                local label = (ns.Tr and ns.Tr("tab_debug_errors")) or "Lua Errors"
                if ns.UI and ns.UI.OpenAndShowTab then
                    ns.UI.OpenAndShowTab(label)
                else
                    -- Fallback robuste : n'appele ToggleUI que si fermé
                    local main = (ns.UI and ns.UI.Main) or (_G and _G["GLOG_Main"])
                    local shown = main and main.IsShown and main:IsShown()
                    if not shown then
                        if ns and ns.ToggleUI then ns.ToggleUI()
                        elseif main and main.Show then main:Show() end
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

    if ns.Emit then ns.Emit("errors:changed") end

end

function GLOG.Errors_Get()
    _ensureJournal()
    return (GuildLogisticsDB.errors and GuildLogisticsDB.errors.list) or {}
end

function GLOG.Errors_Clear()
    _ensureJournal()
    GuildLogisticsDB.errors.list   = {}
    GuildLogisticsDB.errors.nextId = 1
    if ns.Emit then ns.Emit("errors:changed") end
end

-- === Hook global error handler (chainé, sûr) ===
do
    local prev = geterrorhandler and geterrorhandler() or nil
    local function handler(msg)
        local ok = pcall(function()
            local stack = (debugstack and debugstack(3)) or ""
            if not _isOurError(msg, stack) then return end

            -- anti-spam 60s par signature
            local key = _sig(msg, stack)
            local now = (time and time()) or 0
            if _seen[key] and (now - _seen[key]) < 60 then return end
            _seen[key] = now

            local rep = _buildReport(msg)

            -- Si le joueur est le GM : journal local direct (pas d'envoi réseau / pas de pending)
            if GLOG and GLOG.IsMaster and GLOG.IsMaster() then
                if GLOG.Errors_AddIncomingReport then
                    GLOG.Errors_AddIncomingReport(rep, rep.who)
                else
                    -- Fallback direct DB (au cas où le module n’est pas encore chargé)
                    GuildLogisticsDB = GuildLogisticsDB or {}
                    GuildLogisticsDB.errors = GuildLogisticsDB.errors or { list = {}, nextId = 1 }
                    local t = GuildLogisticsDB.errors
                    local id = tonumber(t.nextId or 1) or 1
                    rep.id   = id
                    rep.done = false
                    t.list[#t.list+1] = rep
                    t.nextId = id + 1
                    if ns.Emit then ns.Emit("errors:changed") end
                end
            else
                -- Joueur non-GM : même flux que TX_REQ (direct si GM en ligne, sinon pending)
                GLOG.Errors_SendOrQueue(rep)
            end

        end)
        if prev then prev(msg) end
    end
    if seterrorhandler then seterrorhandler(handler) end
end

-- Marque une entrée comme traitée / non traitée
function GLOG.Errors_SetDone(id, done)
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
function GLOG.Errors_CountOpen()
    GuildLogisticsDB = GuildLogisticsDB or {}
    local list = (GuildLogisticsDB.errors and GuildLogisticsDB.errors.list) or {}
    local n = 0
    for i = 1, #list do if not (list[i].done == true) then n = n + 1 end end
    return n
end
