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

-- ➕ Déclaration anticipée : la fonction est appelée plus haut (déferrement/poll)
local showPendingInvitesPopup

-- ➕ Déclenchement conditionnel d'affichage (hors combat / hors instance)
local _deferredItems = nil


local function _canShowPopupNow()
    -- Conserver la logique de fin de loading pour éviter le clipping
    if loadingScreenActive then return false end

    -- Pas en combat
    if (InCombatLockdown and InCombatLockdown()) or (UnitAffectingCombat and UnitAffectingCombat("player")) then
        return false
    end

    -- Pas dans une instance
    if IsInInstance then
        local inInstance = IsInInstance()
        if inInstance == true then return false end
        -- (En Retail, IsInInstance() renvoie bool,instanceType)
        local b = select(1, IsInInstance())
        if b == true then return false end
    end

    return true
end

-- ➕ Lecture option (valide par défaut si non paramétrée)
local function _isPopupEnabled(key)
    -- Utilise le même stockage que les autres options UI (onglet Debug > Options)
    local saved = (GLOG.GetSavedWindow and GLOG.GetSavedWindow()) or GuildLogisticsUI or {}
    saved.popups = saved.popups or {}
    local v = saved.popups[key]
    if v == nil then return true end -- ✅ par défaut, on considère cochée
    return v and true or false
end

local function _tryShowOrDefer(items)
    if not items or #items == 0 then return end
    -- ✅ Respecte l’option existante : Notification d'invitation dans le calendrier
    if not _isPopupEnabled("calendarInvite") then return end

    if _canShowPopupNow() then
        showPendingInvitesPopup(items)

        _markSeen(items)
        shownThisSession = true
        pendingCache = nil
        _deferredItems = nil
    else
        -- Mémorise pour un affichage dès que les conditions sont favorables
        _deferredItems = items
    end
end

local function currentCalendarTS()
    local ct = C_DateAndTime and C_DateAndTime.GetCurrentCalendarTime and C_DateAndTime.GetCurrentCalendarTime()
    if ct then
        return time({ year=ct.year, month=ct.month, day=ct.monthDay, hour=ct.hour, min=ct.minute, sec=0 })
    end
    return time()
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
local function _isSystemCalendarEvent(ev, info)
    local calType = (ev and ev.calendarType) or (info and info.calendarType)
    if type(calType) == "string" and calType ~= "PLAYER" then
        return true
    end

    local evType = (ev and ev.eventType) or (info and info.eventType)
    if evType and Enum and Enum.CalendarEventType and evType == Enum.CalendarEventType.Holiday then
        return true
    end

    local isHoliday = (ev and ev.isHoliday) or (info and info.isHoliday)
    if isHoliday then
        return true
    end

    return false
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
    if _isSystemCalendarEvent(nil, info) then
        return false
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
function collectPending(rangeDays)
    local res, needsRetry = {}, false
    if not C_Calendar or not C_Calendar.OpenCalendar then return res, needsRetry end

    local nowTS   = currentCalendarTS()
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

                    -- On ne traite que les INVITED non-système (PLAYER uniquement)
                    if ev and ev.inviteStatus == Enum.CalendarStatus.Invited and not _isSystemCalendarEvent(ev) then
                        local h  = ev.hour   or (ev.startTime and ev.startTime.hour)   or 0
                        local m  = ev.minute or (ev.startTime and ev.startTime.minute) or 0
                        local ts = time({ year = year, month = month, day = day, hour = h, min = m, sec = 0 })

                        if ts and ts >= nowTS and ts <= limitTS then
                            -- Filtre "créé par un membre de la guilde" (avec retry si info pas prête)
                            local ok, fromGuild = pcall(_isEventFromGuildMember, monthOffset, day, i)
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

    table.sort(res, function(a, b) return a.when < b.when end)
    return res, needsRetry
end

-- ⚠️ API publique inchangée (compat) : ne retourne QUE la liste
function M.GetPendingInvites(daysAhead)
    local list = select(1, collectPending(daysAhead or 31))
    return list
end

-- ➕ Utilitaires d'ouverture du calendrier sans le refermer s'il est déjà visible
local function _isCalendarOpen()
    return CalendarFrame and CalendarFrame:IsShown()
end

local function _openCalendarUI()
    -- Ne rien faire si déjà ouvert
    if _isCalendarOpen() then return end

    -- S'assurer que l'addon Blizzard_Calendar est chargé
    if not CalendarFrame then
        if UIParentLoadAddOn then
            UIParentLoadAddOn("Blizzard_Calendar")
        elseif LoadAddOn then
            pcall(LoadAddOn, "Blizzard_Calendar")
        end
    end

    -- Ouvrir explicitement (sans toggle) si possible, sinon fallback
    if CalendarFrame and CalendarFrame.Show then
        CalendarFrame:Show()
    elseif ToggleCalendar then
        ToggleCalendar()
    elseif Calendar_Toggle then
        Calendar_Toggle()
    end
end

-- Affiche la popup avec la liste
function showPendingInvitesPopup(items)
    if not UI or not UI.CreatePopup then return end

    -- Verrouillage natif via UI.CreatePopup(enforceAction = true)
    local dlg = UI.CreatePopup({ title = "pending_invites_title", width = 560, height = 360, enforceAction = true })

    -- Message d’explication (haut du contenu) avec marges
    local msg = dlg.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    msg:SetJustifyH("LEFT"); msg:SetJustifyV("TOP")
    msg:SetPoint("TOPLEFT", dlg.content, "TOPLEFT", 10, -10)
    msg:SetPoint("RIGHT",   dlg.content, "RIGHT",   -10, 0)
    msg:SetText(Tr("pending_invites_message_fmt"):format(#items))

    -- Conteneur liste sous le message (un peu plus d'espace)
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

    local function buildRow(r)
        local f = {}
        f.when  = UI.Label(r)
        f.title = UI.Label(r)
        return f
    end
    local function updateRow(i, r, f, it)
        f.when:SetText(fmtWhen(it))
        f.title:SetText(it.loc or it.title or "?")
    end
    lv.opts.buildRow  = buildRow
    lv.opts.updateRow = updateRow
    lv:SetData(items)

    dlg:SetButtons({
        { text = "btn_open_calendar", default = true, w = 180, onClick = function()
            -- Ouvrir sans refermer si déjà ouvert, et sans naviguer sur l'invitation
            _openCalendarUI()
            -- Fermeture uniquement via cette action
            if dlg.Hide then dlg:Hide() end
        end },
    })
    dlg:Show()
end

-- Au login: ouvrir le calendrier, attendre la mise à jour, puis afficher si besoin.
-- ➕ Anti-clipping d'UI : on n'affiche la popup qu'après la fin du loading screen.
local shownThisSession = false
local loadingScreenActive = true
local pendingCache = nil

-- ➕ Sonde “arrière-plan” pour récupérer les événements sans ouvrir le calendrier
local CAL_POLL_MAX   = 20      -- ↑ fiabilité : 20 x 0.5s ≈ 10s
local CAL_POLL_DELAY = 0.5
local calPollActive  = false
local calPollTries   = 0
local guildReadyOnce = false

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("LOADING_SCREEN_ENABLED")
f:RegisterEvent("LOADING_SCREEN_DISABLED")
f:RegisterEvent("CALENDAR_UPDATE_EVENT_LIST")
f:RegisterEvent("CALENDAR_UPDATE_PENDING_INVITES")
f:RegisterEvent("GUILD_ROSTER_UPDATE") -- ✅ nouveau : relance quand le cache guilde est prêt
f:RegisterEvent("PLAYER_REGEN_ENABLED")
f:RegisterEvent("ZONE_CHANGED_NEW_AREA")

f:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        -- Demande très tôt le chargement des données calendrier (en arrière-plan)
        if C_Calendar and C_Calendar.OpenCalendar then
            C_Calendar.OpenCalendar()
        end
        return

    elseif event == "LOADING_SCREEN_ENABLED" then
        loadingScreenActive = true
        return

    elseif event == "LOADING_SCREEN_DISABLED" then
        loadingScreenActive = false

        -- Sécurise la demande de données juste après la fin du chargement
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
                local items, needsRetry = collectPending(31)

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
        pendingCache, needRetry = collectPending(31)

        if pendingCache and #pendingCache > 0 then
            local newItems = _extractNewInvites(pendingCache)
            if #newItems > 0 then
                _tryShowOrDefer(pendingCache)
            end
        end

        -- 🔁 Si l’auteur n’était pas encore résolu, refait une passe très vite
        if needRetry and C_Timer and C_Timer.After then
            C_Timer.After(0.6, function()
                local again, _need = collectPending(31)
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
            local items, _need = collectPending(31)
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
        if _deferredItems and _canShowPopupNow() then
            _tryShowOrDefer(_deferredItems)  -- tentera d'afficher et videra _deferredItems si succès
        end
        return
    end
end)