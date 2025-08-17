local ADDON, ns = ...
local CDZ, UI, F = ns.CDZ, ns.UI, ns.Format
local PAD = UI.OUTER_PAD or 16
local U = ns.Util

-- ✏️ ajout gmFS
local panel, lv, lvRecv, lvSend, recvArea, sendArea, purgeDBBtn, purgeAllBtn, forceSyncBtn, footer, debugTicker, verFS, gmFS

-- Rafraîchit l'étiquette de version DB dans le footer
local function UpdateDBVersionLabel()
    if not verFS then return end
    local rv = (ChroniquesDuZephyrDB and ChroniquesDuZephyrDB.meta and ChroniquesDuZephyrDB.meta.rev) or 0
    verFS:SetText("DB v"..tostring(rv))
end

-- ➕ Affiche "GM: Nom-Royaume" (rang 0 du roster)
local function UpdateMasterLabel()
    if not gmFS then return end
    local gmName = CDZ.GetGuildMasterCached and select(1, CDZ.GetGuildMasterCached())
    local txt = "GM: " .. (gmName and Ambiguate(gmName, "none") or "—")
    gmFS:SetText(txt)
end

-- ➕ Affiche "GM: <Name>" basé sur le roster (rang 0)
local function UpdateMasterLabel()
    if not gmFS then return end
    local gmName, gmRow = nil, nil
    if CDZ and CDZ.GetGuildMasterCached then
        gmName, gmRow = CDZ.GetGuildMasterCached()
    end
    local txt = gmName and ("GM: " .. Ambiguate(gmName, "short")) or "GM: —"
    gmFS:SetText(txt)
end

-- Filtrage UI : ne pas montrer côté RECU les messages dont l'émetteur est moi
local _normalize    = U.normalizeStr
local _selfFullName = U.playerFullName
local ShortName     = U.ShortName

-- Tentative locale de décompression d'un payload 'c=z|...' pour l'aperçu Debug
local function TryDecompressPayload(s)
    s = tostring(s or "")
    if not s:find("^c=z|") then return nil end
    local LD
    if type(LibStub) == "table" and LibStub.GetLibrary then
        LD = LibStub:GetLibrary("LibDeflate", true)
    end
    LD = LD or _G.LibDeflate
    if not LD then return nil end
    local decoded = LD:DecodeForWoWAddonChannel(s:sub(5)); if not decoded then return nil end
    return LD:DecompressDeflate(decoded)
end


-- Affichage : constantes & helpers
local HELLO_WAIT_SEC = 5

local cols = UI.NormalizeColumns({
    { key="time",  title="Heure",       w=110 },
    { key="dir",   title="Sens",        w=70  },
    { key="state", title="État",        w=160 },
    { key="type",  title="Type",        w=160 },
    { key="rv",    title="Ver.",        w=60  }, 
    { key="size",  title="Taille",      w=80  },
    { key="chan",  title="Canal",       w=80  },
    { key="target",title="Émetteur",    min=200, flex=1 },
    { key="frag",  title="Frag",        w=70  },
    { key="view",  title=" ",           w=70  },
})

local function BuildRow(r)
    local f = {}
    f.time   = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.dir    = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.state  = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.type   = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.rv     = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.size   = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.chan   = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.target = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.frag   = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.view   = UI.Button(r, "Voir", { size="xs", minWidth=60 })
    return f
end

local function UpdateRow(i, r, f, it)
    f.time:SetText(date("%H:%M:%S", it.ts or time()))
    f.dir:SetText(it.dir == "send" and "|cff9ecbffENVOI|r" or "|cff7dff9aRECU|r")

    local total = tonumber(it.total or 1) or 1
    local sent  = tonumber(it.sentCount or 0) or 0      -- fragments effectivement transmis (ENVOI)
    local got   = tonumber(it.gotCount  or 0) or 0      -- fragments effectivement reçus  (RECU)

    if it.dir == "send" then
        if sent <= 0 then
            f.state:SetText("|cffffff00En attente|r")
        elseif sent < total then
            f.state:SetText("|cffffd200En cours|r")
        else
            f.state:SetText("|cff7dff9aTransmis|r")
        end
    else
        -- État côté réception : HELLO => compte à rebours puis élu
        local st = ""
        if it.type == "HELLO" then
            local hid = it.kv and it.kv.helloId
            if hid and ns.CDZ and ns.CDZ._GetHelloElect then
                local info = ns.CDZ._GetHelloElect(hid)
                local nowt = time()
                local started = (info and info.startedAt) or (it.tsFirst or nowt)
                local endsAt  = (info and info.endsAt) or (started + HELLO_WAIT_SEC)
                if nowt < endsAt then
                    st = "Découverte… " .. tostring(math.max(0, endsAt - nowt)) .. "s"
                elseif info and info.decided then
                    st = "Élu : " .. (info.winner or "?")
                end
            end
        end

        -- ➕ État générique côté réception si pas un HELLO (ou si HELLO non résolu)
        if st == "" then
            if got <= 0 then
                st = "|cffffff00En attente|r"
            elseif got < total then
                st = ("|cffffd200Assemblage|r %d/%d"):format(got, total)
            else
                st = "|cff7dff9aReçu|r"
            end
        end

        f.state:SetText(st)
    end

    f.type:SetText(it.type or "")
    f.rv:SetText(it.rv and tostring(it.rv) or "")  -- <= affiche la révision
    f.size:SetText(tostring(it.size or 0))
    f.chan:SetText(it.chan or "")

    -- Colonne "Émetteur" : côté RECU = sender (sans royaume), côté ENVOI = moi (sans royaume)
    -- Côté affichage : on conserve toujours le nom complet
    local emitter = (it.dir == "recv") and (it.target or "") or _selfFullName()
    f.target:SetText(emitter or "")

    local progress = (it.dir == "send") and sent or got
    f.frag:SetText(tostring(progress) .. "/" .. tostring(total))

    f.view:SetOnClick(function()
        if not (ns.UI and ns.UI.PopupText) then return end
        local title = (it.dir=="send" and "Message envoyé" or "Message reçu")

        -- Décodage k=v|k=v avec support payload compressé 'c=z|...'
        local preview = it.fullPayload or ""
        local dec = TryDecompressPayload and TryDecompressPayload(preview)
        if dec and dec ~= "" then preview = dec end
        local kv = {}
        for pair in string.gmatch(preview, "([^|]+)") do
            local k, v = pair:match("^(.-)=(.*)$")
            if k then kv[k] = v end
        end

        local decoded = {}
        for k,v in pairs(kv) do
            decoded[#decoded+1] = k.." = "..tostring(v)
        end
        table.sort(decoded)

        local head = ("type=%s  rv=%s  lm=%s  chan=%s  emetteur=%s")
            :format(it.type or "?", tostring(kv.rv or it.rv or "?"), tostring(kv.lm or "?"), it.chan or "", emitter or "")
        local body = (#decoded>0) and table.concat(decoded, "\n") or "(payload vide)"
        local raw  = it.fullRaw or it.fullPayload or "(brut indisponible)"
        ns.UI.PopupText(title, head.."\n\n"..body.."\n\n— BRUT —\n"..raw)
    end)
end

-- Regroupe les fragments et décode rv/lm
local function groupLogs(raw)
    local map = {}
    for _, e in ipairs(raw) do
        local key = table.concat({ e.dir or "?", e.type or "?", e.chan or "?", e.target or "?", tostring(e.seq or 0) }, "|")
        local g = map[key]
        if not g then
            g = {
                ts = e.ts or 0,               -- affichage (sera fixé au 1er fragment)
                tsFirst = e.ts or 0,          -- 1er fragment (heure stable)
                tsLast  = e.ts or 0,          -- dernier fragment (info interne)
                dir = e.dir, type = e.type, chan = e.chan, target = e.target,
                seq = e.seq or 0, total = e.total or 1, lastPart = e.part or 1, size = 0,
                state = nil,
                sentCount = 0,                -- nb fragments effectivement envoyés (ENVOI)
                parts = {},
            }
            map[key] = g
        end
        g.tsFirst = math.min(g.tsFirst or (e.ts or 0), e.ts or 0)
        g.tsLast  = math.max(g.tsLast  or 0, e.ts or 0)
        g.size    = (g.size or 0) + (tonumber(e.size) or 0)
        g.total   = e.total or g.total
        g.lastPart= math.max(g.lastPart or 1, e.part or 1)
        g.parts[e.part or 1] = e.raw

        -- Comptage précis des fragments TRANSMIS (sans compter les "pending")
        if e.state == "sent" then
            g._sent = g._sent or {}
            local p = e.part or 1
            if not g._sent[p] then
                g._sent[p] = true
                g.sentCount = (g.sentCount or 0) + 1
            end
        end
    end

    local out = {}
    for _, g in pairs(map) do
        -- Horodatage affiché = fixé au 1er fragment
        g.ts = g.tsFirst or g.ts

        -- Compte des fragments réellement présents (utile côté RECU)
        local got = 0
        for i = 1, (g.total or 1) do if g.parts[i] then got = got + 1 end end
        g.gotCount = got

        local payloads, raws = {}, {}
        for i = 1, (g.total or 1) do
            local raw = g.parts[i]
            if raw then
                raws[#raws+1] = raw
                payloads[#payloads+1] = raw:match("|n=%d+|(.*)$") or ""
            end
        end
        g.fullPayload = table.concat(payloads, "")
        g.fullRaw     = table.concat(raws, "\n")

        -- Décodage rv/lm (supporte payload compressé 'c=z|...')
        local preview = g.fullPayload or ""
        local dec = TryDecompressPayload and TryDecompressPayload(preview)
        if dec and dec ~= "" then preview = dec end
        local kv = {}
        for pair in string.gmatch(preview, "([^|]+)") do
            local k, v = pair:match("^(.-)=(.*)$")
            if k then kv[k] = v end
        end
        g.kv = kv
        g.rv = tonumber(kv.rv or "") or nil
        g.lm = tonumber(kv.lm or "") or nil
        out[#out+1] = g

    end

    -- Tri : par Heure (décroissant), puis par Version (décroissant), puis par Sens (RECU avant ENVOI)
    table.sort(out, function(a, b)
        local ad = tonumber(a.lm) or tonumber(a.ts) or 0
        local bd = tonumber(b.lm) or tonumber(b.ts) or 0
        if ad ~= bd then return ad > bd end

        local arv = tonumber(a.rv) or -math.huge
        local brv = tonumber(b.rv) or -math.huge
        if arv ~= brv then return arv > brv end

        -- Sens : RECU doit précéder ENVOI
        local adir = (a.dir == "send") and 1 or 0
        local bdir = (b.dir == "send") and 1 or 0
        if adir ~= bdir then return adir < bdir end

        -- Dernier repli : horodatage brut pour stabilité
        return (a.ts or 0) > (b.ts or 0)
    end)

    return out
end

function Refresh()
    local selfNorm = _normalize(_selfFullName())
    local recvData, sendData = {}, {}

    -- Split RECU / ENVOI + filtre UI côté RECU (on garde le traitement logique inchangé ailleurs)
    for _, e in ipairs(CDZ.GetDebugLogs()) do
        if e.dir == "recv" then
            if not (_normalize(e.target) == selfNorm) then
                recvData[#recvData+1] = e
            end
        elseif e.dir == "send" then
            sendData[#sendData+1] = e
        else
            -- sécurité : si dir inconnu, on place en haut
            recvData[#recvData+1] = e
        end
    end

    local groupedRecv = groupLogs(recvData)
    local groupedSend = groupLogs(sendData)

    if lvRecv then lvRecv:SetData(groupedRecv) end
    if lvSend then lvSend:SetData(groupedSend) end

    -- ➕ Alimente la file d'attente (pending TX_REQ)
    if lvPending and CDZ.GetPendingOutbox then
        local pending = CDZ.GetPendingOutbox() or {}
        lvPending:SetData(pending)
    end

    if lvRecv and lvRecv.Layout then lvRecv:Layout() end
    if lvSend and lvSend.Layout then lvSend:Layout() end
    if lvPending and lvPending.Layout then lvPending:Layout() end
end

local function Build(container)
    panel = container
    if UI.ApplySafeContentBounds then UI.ApplySafeContentBounds(panel) end

    purgeDBBtn = UI.Button(panel, "Purger Debug", { size="sm", minWidth=120 })
    purgeDBBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -12)
    purgeDBBtn:SetOnClick(function() CDZ.ClearDebugLogs(); Refresh() end)

    purgeAllBtn = UI.Button(panel, "Purge totale", { size="sm", minWidth=120, tooltip="Wipe DB + reset UI + Reload" })
    purgeAllBtn:SetPoint("RIGHT", purgeDBBtn, "LEFT", -8, 0)
    purgeAllBtn:SetConfirm("Purger la DB + réinitialiser l’UI puis recharger ?", function()
        if CDZ.WipeAllSaved then
            CDZ.WipeAllSaved()
        elseif CDZ.WipeAllData then
            CDZ.WipeAllData()
            ChroniquesDuZephyrUI = { point="CENTER", relTo=nil, relPoint="CENTER", x=0, y=0, width=1160, height=680 }
        end
        ReloadUI()
    end)

    -- ➕ Footer actions
    footer = UI.CreateFooter(panel, 36)

    -- ➕ Affichage version DB (bas gauche)
    verFS = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    verFS:SetPoint("LEFT", footer, "LEFT", 12, 0)
    if UpdateDBVersionLabel then UpdateDBVersionLabel() end

    -- ➕ Affichage GM (à droite de la version)
    gmFS = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    gmFS:SetPoint("LEFT", verFS, "RIGHT", 16, 0)
    if UpdateMasterLabel then UpdateMasterLabel() end

    -- ➕ Bouton GM : Forcer ma version (envoi direct d’un SYNC_FULL)
    forceSyncBtn = UI.Button(footer, "Forcer ma version (GM)", { size="sm", minWidth=200,
        tooltip = "Diffuse immédiatement un snapshot complet (SYNC_FULL)" })
    forceSyncBtn:SetConfirm("Diffuser et FORCER la version du GM (SYNC_FULL) ?", function()
        if CDZ and CDZ._SnapshotExport and CDZ.Comm_Broadcast then
            -- Option: on garde le comportement 'force' en incrémentant la révision locale si disponible
            local newrv = (CDZ.IncRev and CDZ.IncRev()) or nil
            local snap = CDZ._SnapshotExport()
            if newrv then snap.rv = newrv end
            CDZ.Comm_Broadcast("SYNC_FULL", snap)
            if UIErrorsFrame then
                UIErrorsFrame:AddMessage("|cff40ff40[CDZ]|r SYNC_FULL envoyé (rv="..tostring(snap.rv)..")", 0.4, 1, 0.4)
            end
        end
    end)

    -- ➕ Reparent dans le footer
    purgeDBBtn:SetParent(footer)
    purgeAllBtn:SetParent(footer)

    -- === Trois zones empilées : RECU (40%) / ENVOI (40%) / FILE (20%) ===
    recvArea    = CreateFrame("Frame", nil, panel)
    sendArea    = CreateFrame("Frame", nil, panel)
    pendingArea = CreateFrame("Frame", nil, panel)

    -- Titre + trait pour chaque zone
    UI.SectionHeader(recvArea,    "Liste des paquets entrants")
    lvRecv    = UI.ListView(recvArea,    cols,         { buildRow = BuildRow, updateRow = UpdateRow, topOffset = UI.SECTION_HEADER_H or 26 })

    UI.SectionHeader(sendArea,    "Liste des paquets sortants")
    lvSend    = UI.ListView(sendArea,    cols,         { buildRow = BuildRow, updateRow = UpdateRow, topOffset = UI.SECTION_HEADER_H or 26 })

    UI.SectionHeader(pendingArea, "Liste des paquets en file d'attente")
    lvPending = UI.ListView(pendingArea, pendingCols,  { buildRow = BuildPendingRow, updateRow = UpdatePendingRow, topOffset = UI.SECTION_HEADER_H or 26, bottomAnchor = footer })

    -- Colonnes simplifiées pour la file d'attente (heure / type / info)
    local colsQueue = UI.NormalizeColumns({
        { key="time", title="Heure", w=110 },
        { key="type", title="Type",  w=100 },
        { key="info", title="Demande", min=240, flex=1 },
    })
    local function BuildRowQueue(r)
        local f = {}
        f.time = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.type = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        f.info = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        return f
    end
    local function UpdateRowQueue(i, r, f, it)
        local d = it.data or it
        local dt = date and date("%H:%M:%S", tonumber(d.ts or 0)) or tostring(d.ts or "")
        f.time:SetText(dt)
        f.type:SetText(d.type or "")
        f.info:SetText(d.info or ("ID " .. tostring(d.id or "")))
    end

    -- Positionnement responsive (40/40/20 de la hauteur utile)
    local function PositionAreas()
        local pH      = panel:GetHeight() or 600
        local footerH = footer:GetHeight() or 36
        local topOff  = 38
        local gap     = 8
        local usable  = math.max(0, pH - footerH - topOff)
        local hRecv   = math.floor((usable) * 0.40)
        local hSend   = math.floor((usable) * 0.40)
        local hPend   = math.max(0, usable - hRecv - hSend - (gap*2))

        -- RECU
        recvArea:ClearAllPoints()
        recvArea:SetPoint("TOPLEFT",  panel, "TOPLEFT",  0, -topOff)
        recvArea:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -topOff)
        recvArea:SetHeight(hRecv)

        -- ENVOI
        sendArea:ClearAllPoints()
        sendArea:SetPoint("TOPLEFT",  panel, "TOPLEFT",  0, -(topOff + hRecv + gap))
        sendArea:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -(topOff + hRecv + gap))
        sendArea:SetHeight(hSend)

        -- FILE d'attente
        pendingArea:ClearAllPoints()
        pendingArea:SetPoint("TOPLEFT",  panel, "TOPLEFT",  0, -(topOff + hRecv + gap + hSend + gap))
        pendingArea:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -(topOff + hRecv + gap + hSend + gap))
        pendingArea:SetPoint("BOTTOMLEFT", footer, "TOPLEFT",  0, 0)
        pendingArea:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", 0, 0)

        if lvRecv and lvRecv.Layout then lvRecv:Layout() end
        if lvSend and lvSend.Layout then lvSend:Layout() end
        if lvPending and lvPending.Layout then lvPending:Layout() end
    end


    -- Calcul initial + relayout sur resize du panneau
    PositionAreas()
    if panel and panel.HookScript then
        panel:HookScript("OnSizeChanged", PositionAreas)
    end
end

-- ➕ Layout avec footer et visibilité GM
local function Layout()
    local isMaster = CDZ.IsMaster and CDZ.IsMaster()
    if forceSyncBtn then forceSyncBtn:SetShown(isMaster) end
    if UI.AttachButtonsFooterRight then
        local buttons = { purgeDBBtn, purgeAllBtn }
        if isMaster and forceSyncBtn then table.insert(buttons, 1, forceSyncBtn) end
        UI.AttachButtonsFooterRight(footer, buttons, 8, nil)
    end
    if lv and lv.Layout then lv:Layout() end
end

-- ➕ Rafraîchissement temps réel lorsque des logs arrivent / changent d'état
if ns and ns.On then
    ns.On("debug:changed", function()
        if lvRecv or lvSend then
            Refresh()
        end
        -- Met à jour bas-gauche
        if UpdateDBVersionLabel then UpdateDBVersionLabel() end
        if UpdateMasterLabel   then UpdateMasterLabel()   end
    end)

    -- Quand la guilde change ou la méta bouge, on rafraîchit aussi le GM
    if ns.On then
        ns.On("roster:upsert", function() if UpdateMasterLabel then UpdateMasterLabel() end end)
        ns.On("roster:removed", function() if UpdateMasterLabel then UpdateMasterLabel() end end)
        ns.On("meta:changed",  function() if UpdateMasterLabel then UpdateMasterLabel() end end)
    end
end


-- =================== Onglet OPTIONS ===================
local optPanel
local themeRadios, autoRadios = {}, {}

local function _SetRadioGroupChecked(group, key)
    for k, b in pairs(group) do b:SetChecked(k == key) end
end

local function BuildOptions(panel)
    optPanel = panel
    local PAD = UI.OUTER_PAD or 16
    local RADIO_V_SPACING = 8

    -- ✅ Cadre englobant avec padding augmenté
    local OUTER_PAD = PAD + 8      -- +8 px autour de la boîte
    local INNER_PAD = 16           -- padding interne plus confortable
    local box, content = UI.PaddedBox(panel, { outerPad = OUTER_PAD, pad = INNER_PAD })

    -- === Section 1 : Thème de l'interface ===
    local y = 0
    local headerH = UI.SectionHeader(content, "Thème de l'interface", { topPad = y }) or (UI.SECTION_HEADER_H or 26)
    y = y + headerH + 8

    local function makeRadioV(group, key, text)
        local b = CreateFrame("CheckButton", nil, content, "UIRadioButtonTemplate")
        b:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)

        local label = b.Text
        if not label then
            label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            label:SetPoint("LEFT", b, "RIGHT", 6, 0)
            b.Text = label
        end
        label:SetText(text)

        b:SetScript("OnClick", function(self)
            _SetRadioGroupChecked(group, key)
            ChroniquesDuZephyrUI = ChroniquesDuZephyrUI or {}
            if group == themeRadios then
                ChroniquesDuZephyrUI.theme = key
                if UI.SetTheme then UI.SetTheme(key) end
            else
                ChroniquesDuZephyrUI.autoOpen = (key == "YES")
            end
        end)

        group[key] = b
        y = y + (b:GetHeight() or 24) + RADIO_V_SPACING
        return b
    end

    -- Ordre demandé : Automatique, Alliance, Horde, Neutre
    makeRadioV(themeRadios, "AUTO",     "Automatique")
    makeRadioV(themeRadios, "ALLIANCE", "Alliance")
    makeRadioV(themeRadios, "HORDE",    "Horde")
    makeRadioV(themeRadios, "NEUTRAL",  "Neutre")

    -- === Section 2 : Ouverture auto ===
    local headerH2 = UI.SectionHeader(content, "Ouvrir automatiquement à l'ouverture du jeu", { topPad = y + 10 }) or (UI.SECTION_HEADER_H or 26)
    y = y + headerH2 + 8

    makeRadioV(autoRadios, "YES", "Oui")
    makeRadioV(autoRadios, "NO",  "Non")

    -- Valeurs initiales
    local saved = CDZ.GetSavedWindow and CDZ.GetSavedWindow() or {}
    local theme = (saved and saved.theme) or "AUTO"
    local auto  = (saved and saved.autoOpen) and "YES" or "NO"
    _SetRadioGroupChecked(themeRadios, theme)
    _SetRadioGroupChecked(autoRadios, auto)
end

UI.RegisterTab("Options", BuildOptions, RefreshOptions)
UI.RegisterTab("Debug", Build, Refresh, Layout)