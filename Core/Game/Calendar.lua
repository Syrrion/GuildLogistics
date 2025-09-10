local ADDON, ns = ...
ns.GLOG = ns.GLOG or {}
ns.UI   = ns.UI   or {}
ns.Util = ns.Util or {}

local GLOG, UI = ns.GLOG, ns.UI
local Tr = ns.Tr or function(s) return s end

-- Module calendrier : détection des invitations "Invited" (sans réponse)
GLOG.Calendar = GLOG.Calendar or {}
local M = GLOG.Calendar

local SECS_PER_DAY = 24 * 60 * 60

-- ➕ Suivi des invitations déjà notifiées (mémoire de session uniquement)
local _seenInvites = {} -- [key] = true

-- ➕ Clé stable pour identifier une invitation (robuste aux variations de champs)
local function _inviteKey(inv)
    local y = (inv.year or (inv.date and inv.date.year)) or 0
    local m = (inv.month or (inv.date and inv.date.month)) or 0
    local d = (inv.day or (inv.date and inv.date.monthDay)) or 0
    local h = inv.hour or inv.h or 0
    local mi = inv.minute or inv.min or 0
    local id = inv.eventUID or inv.eventID or inv.eventIndex or inv.id or 0
    local loc = inv.location or inv.place or ""
    local inviter = inv.inviterName or inv.inviter or inv.creator or ""
    local title = inv.title or inv.name or ""
    return string.format("%s|%04d-%02d-%02d %02d:%02d|%s|%s", tostring(id), y, m, d, h, mi, tostring(loc), tostring(inviter ~= "" and inviter or title))
end

-- ➕ Extrait les invites encore jamais notifiées pendant la session
local function _extractNewInvites(list)
    local new = {}
    if not list then return new end
    for _,it in ipairs(list) do
        local k = _inviteKey(it)
        if not _seenInvites[k] then
            table.insert(new, it)
        end
    end
    return new
end

-- ➕ Marque une liste d’invitations comme "déjà notifiées"
local function _markSeen(list)
    if not list then return end
    for _,it in ipairs(list) do
        _seenInvites[_inviteKey(it)] = true
    end
end

-- ➕ Déclenchement conditionnel d'affichage (hors combat / hors instance)
local _deferredItems = nil

local function _tryShowOrDefer(items)
    if not items or #items == 0 then return end
    -- ✅ Respecte l’option existante : Notification d'invitation dans le calendrier
    if not (GLOG and GLOG.IsPopupEnabled and GLOG.IsPopupEnabled("calendarInvite")) then return end

    if UI and UI.CanOpenModalNow and UI.CanOpenModalNow() then
        if UI.PopupPendingCalendarInvites then
            UI.PopupPendingCalendarInvites(items)
        end
        _markSeen(items)
        shownThisSession = true
        pendingCache = nil
        _deferredItems = nil
    else
        _deferredItems = items
    end
end

-- ➕ Tentative prudente pour déduire un "lieu" sans jamais ouvrir l'évènement
-- (zéro navigation : pas de C_Calendar.OpenEvent)
local function _guessPlaceFromTitle(title)
    if not title or title == "" then return nil end
    local t = tostring(title)

    -- Exemples courants : "Raid - Ulduar", "Soirée @ Orgrimmar", "Amirdrassil (NM)"
    local m = t:match("@%s*(.+)$")          -- après un "@"
           or t:match("%-%s*(.+)$")         -- après un " - "
           or t:match("^(.+)%s*%(")         -- avant la parenthèse
           or t:match("%[(.+)%]")           -- entre crochets
    if m and #m >= 3 then return m end
    return nil
end

-- Filtre "évènement système Blizzard" (non joueur)
-- Renvoie true si l'évènement n’est pas un évènement joueur ("PLAYER"),
-- ou s’il s’agit d’un "Holiday", d’un reset/lockout, etc.
-- ⚠️ DÉPLACÉ vers Guild.lua : _isSystemCalendarEvent()
local function _isSystemCalendarEvent(ev, info)
    -- Déléguer vers Guild.lua (fonction intégrée dans IsCalendarEventFromGuildMember)
    return false -- Désactivé : filtrage fait maintenant dans Guild.lua
end

-- ➕ Helper : vérifie que l'évènement (mo,day,idx) provient d'un membre de la guilde
-- Déplacé depuis Guild.lua pour meilleure séparation des responsabilités
function GLOG.IsCalendarEventFromGuildMember(monthOffset, day, index)
    if not C_Calendar or not C_Calendar.OpenEvent then return false end

    -- Ouvre les infos de l'évènement (data-only, pas l'UI)
    local ok = pcall(C_Calendar.OpenEvent, monthOffset, day, index)
    if not ok then return nil end

    local info = C_Calendar.GetEventInfo and C_Calendar.GetEventInfo() or nil
    if not info then return nil end

    -- 🛑 Exclure immédiatement les évènements système Blizzard
    -- Certains évènements créés par des joueurs apparaissent avec
    -- calendarType = "GUILD_EVENT" (ou "COMMUNITY_EVENT"). Ne pas les filtrer.
    local calType = (info and info.calendarType) or ""
    if type(calType) == "string" then
        local t = calType -- chaîne déjà en majuscules par l'API
        local isAllowed = (t == "PLAYER" or t == "GUILD_EVENT" or t == "COMMUNITY_EVENT" or t == "GUILD_ANNOUNCEMENT")
        if not isAllowed then
            return false
        end
    end

    local evType = (info and info.eventType)
    if evType and Enum and Enum.CalendarEventType and evType == Enum.CalendarEventType.Holiday then
        return false
    end

    local isHoliday = (info and info.isHoliday)
    if isHoliday then
        return false
    end

    -- Tant que le cache de guilde n'est pas prêt, on reporte la décision
    if not GLOG.IsGuildCacheReady() then
        return nil
    end

    -- Auteur de l'évènement (selon le type, le champ diffère)
    local by = info.invitedBy or info.inviter or info.creator or info.organizer or info.owner or ""
    by = tostring(by or "")
    if by == "" then
        -- Pas d'auteur joueur → ce n'est pas un évènement de guilde
        return false
    end

    -- Normalisation & test appartenance guilde
    local full = (GLOG.ResolveFullName and GLOG.ResolveFullName(by)) or by
    local inG  = GLOG.IsGuildCharacter(full)
    if inG == nil then return nil end
    return inG and true or false
end

-- ➕ Helper : vérifie que l'évènement (mo,day,idx) provient d'un membre de la guilde
local function _isEventFromGuildMember(monthOffset, day, index)
    if not C_Calendar or not C_Calendar.OpenEvent then return false end

    -- Ouvre les infos de l'évènement (data-only, pas l’UI)
    local ok = pcall(C_Calendar.OpenEvent, monthOffset, day, index)
    if not ok then return nil end

    local info = C_Calendar.GetEventInfo and C_Calendar.GetEventInfo() or nil
    if not info then return nil end

    -- 🛑 Exclure immédiatement les évènements système Blizzard
    -- (même logique que ci-dessus; on conserve cette fonction par compat)
    local calType = (info and info.calendarType) or ""
    if type(calType) == "string" then
        local t = calType
        local isAllowed = (t == "PLAYER" or t == "GUILD_EVENT" or t == "COMMUNITY_EVENT" or t == "GUILD_ANNOUNCEMENT")
        if not isAllowed then
            return false
        end
    end

    -- Tant que le cache de guilde n’est pas prêt, on reporte la décision
    if GLOG and GLOG.IsGuildCacheReady and not GLOG.IsGuildCacheReady() then
        return nil
    end

    -- Auteur de l’évènement (selon le type, le champ diffère)
    local by = info.invitedBy or info.inviter or info.creator or info.organizer or info.owner or ""
    by = tostring(by or "")
    if by == "" then
        -- Pas d’auteur joueur → ce n’est pas un évènement de guilde
        return false
    end

    -- Normalisation & test appartenance guilde
    local full = (GLOG.ResolveFullName and GLOG.ResolveFullName(by)) or by
    local inG  = (GLOG.IsGuildCharacter and GLOG.IsGuildCharacter(full))
    if inG == nil then return nil end
    return inG and true or false
end

-- Collecte les invitations "Invited" à venir, filtrées "auteur ∈ guilde".
-- 🔁 Retourne: list, needsRetry (bool) → needsRetry=true si certains auteurs étaient encore "indisponibles".
function CollectPending(rangeDays)
    local res, needsRetry = {}, false
    if not C_Calendar or not C_Calendar.OpenCalendar then return res, needsRetry end

    local nowTS   = (GLOG and GLOG.GetCurrentCalendarEpoch and GLOG.GetCurrentCalendarEpoch()) or time()
    local limitTS = nowTS + (tonumber(rangeDays) or 31) * SECS_PER_DAY

    C_Calendar.OpenCalendar()

    for monthOffset = 0, 1 do
        local mi = C_Calendar.GetMonthInfo and C_Calendar.GetMonthInfo(monthOffset)
        local year, month, numDays = mi and mi.year, mi and mi.month, (mi and mi.numDays) or 31
        if year and month then
            for day = 1, numDays do
                local num = (C_Calendar.GetNumDayEvents and C_Calendar.GetNumDayEvents(monthOffset, day)) or 0
                for i = 1, num do
                    local ev = C_Calendar.GetDayEvent and C_Calendar.GetDayEvent(monthOffset, day, i)

                    -- On ne traite que les INVITED et uniquement les types joueur/guilde/communauté
                    if ev and ev.inviteStatus == Enum.CalendarStatus.Invited then
                        local ct = ev and ev.calendarType
                        if type(ct) == "string" then
                            local allowed = (ct == "PLAYER" or ct == "GUILD_EVENT" or ct == "COMMUNITY_EVENT" or ct == "GUILD_ANNOUNCEMENT")
                            if not allowed then
                                -- skip system/holiday/lockout
                                -- move to next event
                            else
                        local h  = ev.hour   or (ev.startTime and ev.startTime.hour)   or 0
                        local m  = ev.minute or (ev.startTime and ev.startTime.minute) or 0
                        local ts = time({ year = year, month = month, day = day, hour = h, min = m, sec = 0 })

                        if ts and ts >= nowTS and ts <= limitTS and (not ct or ct == "PLAYER" or ct == "GUILD_EVENT" or ct == "COMMUNITY_EVENT" or ct == "GUILD_ANNOUNCEMENT") then
                            -- Filtre "créé par un membre de la guilde" (avec retry si info pas prête)
                            local ok, fromGuild = pcall(GLOG.IsCalendarEventFromGuildMember, monthOffset, day, i)
                            if not ok then
                                needsRetry = true
                            else
                                if fromGuild == nil then
                                    needsRetry = true
                                elseif fromGuild == true then
                                    local location = _guessPlaceFromTitle(ev.title)
                                    table.insert(res, {
                                        when = ts, year = year, month = month, day = day,
                                        hour = h, minute = m,
                                        title = ev.title or "?", loc = location,
                                    })
                                end
                                -- fromGuild == false → ignoré
                            end
                        end
                            end
                        end
                    end
                end
            end
        end
    end

    table.sort(res, function(a, b) return a.when < b.when end)
    return res, needsRetry
end

-- ⚠️ API publique inchangée (compat) : ne retourne QUE la liste
function M.GetPendingInvites(daysAhead)
    local list = select(1, CollectPending(daysAhead or 31))
    return list
end

-- Au login: ouvrir le calendrier, attendre la mise à jour, puis afficher si besoin.
-- ➕ Anti-clipping d'UI : on n'affiche la popup qu'après la fin du loading screen.
local shownThisSession = false
local pendingCache = nil

-- ➕ Sonde “arrière-plan” pour récupérer les événements sans ouvrir le calendrier
local CAL_POLL_MAX   = 20      -- ↑ fiabilité : 20 x 0.5s ≈ 10s
local CAL_POLL_DELAY = 0.5
local calPollActive  = false
local calPollTries   = 0
local guildReadyOnce = false

-- (Frame supprimé — on passe par ns.Events dans Core/Events.lua)
do
    local function _dispatch(_, ev, ...) M.OnEvent(ev, ...) end
    ns.Events.Register("PLAYER_LOGIN",                      _dispatch)
    ns.Events.Register("PLAYER_ENTERING_WORLD",             _dispatch)
    ns.Events.Register("LOADING_SCREEN_ENABLED",            _dispatch)
    ns.Events.Register("LOADING_SCREEN_DISABLED",           _dispatch)
    ns.Events.Register("CALENDAR_UPDATE_EVENT_LIST",        _dispatch)
    ns.Events.Register("CALENDAR_UPDATE_PENDING_INVITES",   _dispatch)
    ns.Events.Register("GUILD_ROSTER_UPDATE",               _dispatch)
    ns.Events.Register("PLAYER_REGEN_ENABLED",              _dispatch)
    ns.Events.Register("ZONE_CHANGED_NEW_AREA",             _dispatch)
end

function M.OnEvent(event, ...)
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        -- Demande très tôt le chargement des données calendrier (en arrière-plan)
        if C_Calendar and C_Calendar.OpenCalendar then
            C_Calendar.OpenCalendar()
        end
        return

    elseif event == "LOADING_SCREEN_ENABLED" then
        return

    elseif event == "LOADING_SCREEN_DISABLED" then
        if C_Calendar and C_Calendar.OpenCalendar then
            C_Calendar.OpenCalendar()
        end

        -- Si on a déjà reçu des données pendant le loading, on notifie (en respectant combat/instance)
        if pendingCache and #pendingCache > 0 then
            local newItems = _extractNewInvites(pendingCache)
            if #newItems > 0 then
                _tryShowOrDefer(pendingCache)
                return
            end
        end

        -- Sonde en arrière-plan pour récupérer les données sans ouvrir le calendrier
        if not calPollActive then
            calPollActive = true
            calPollTries  = 0

            local function step()
                calPollTries = calPollTries + 1
                local items, needsRetry = CollectPending(31)

                if items and #items > 0 then
                    local newItems = _extractNewInvites(items)
                    if #newItems > 0 then
                        _tryShowOrDefer(items)
                        pendingCache  = nil
                        calPollActive = false
                        return
                    end
                end

                -- 🕒 On retente tant que l’auteur n’était pas encore dispo (limité par CAL_POLL_MAX)
                if (needsRetry and calPollTries < (CAL_POLL_MAX or 20)) and C_Timer and C_Timer.After then
                    C_Timer.After(CAL_POLL_DELAY or 0.5, step)
                    return
                end

                if calPollTries < (CAL_POLL_MAX or 20) and C_Timer and C_Timer.After then
                    C_Timer.After(CAL_POLL_DELAY or 0.5, step)
                else
                    calPollActive = false
                end
            end

            step()
        end
        return

    elseif event == "CALENDAR_UPDATE_EVENT_LIST" or event == "CALENDAR_UPDATE_PENDING_INVITES" then
        local needRetry
        pendingCache, needRetry = CollectPending(31)

        if pendingCache and #pendingCache > 0 then
            local newItems = _extractNewInvites(pendingCache)
            if #newItems > 0 then
                _tryShowOrDefer(pendingCache)
            end
        end

        -- 🔁 Si l’auteur n’était pas encore résolu, refait une passe très vite
        if needRetry and C_Timer and C_Timer.After then
            C_Timer.After(0.6, function()
                local again, _need = CollectPending(31)
                if again and #again > 0 then
                    local newItems2 = _extractNewInvites(again)
                    if #newItems2 > 0 then
                        _tryShowOrDefer(again)
                    end
                end
            end)
        end
        return

    elseif event == "GUILD_ROSTER_UPDATE" then
        -- ✅ Nouveau : relance une collecte dès que le cache guilde devient prêt
        if (not guildReadyOnce) and GLOG and GLOG.IsGuildCacheReady and GLOG.IsGuildCacheReady() then
            guildReadyOnce = true
            local items, _need = CollectPending(31)
            if items and #items > 0 then
                local newItems = _extractNewInvites(items)
                if #newItems > 0 then
                    _tryShowOrDefer(items)
                end
            end
        end
        return
    end

    -- Reprise d'un affichage différé quand on sort de combat / change de zone
    if event == "PLAYER_REGEN_ENABLED" or event == "ZONE_CHANGED_NEW_AREA" then
        if _deferredItems and UI and UI.CanOpenModalNow and UI.CanOpenModalNow() then
            _tryShowOrDefer(_deferredItems)
        end
        return
    end
end