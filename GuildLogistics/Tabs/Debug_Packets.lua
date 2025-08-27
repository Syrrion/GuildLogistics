local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI, F = ns.GLOG, ns.UI, ns.Format
local PAD = UI.OUTER_PAD or 16
local U = ns.Util

-- ✏️ ajout gmFS
local panel, lvRecv, lvSend, lvPending, recvArea, sendArea, pendingArea,
      purgeDBBtn, purgeAllBtn, purgeEpuBtn, purgeResBtn, forceSyncBtn,
      footer, debugTicker, verFS


-- Rafraîchit l'étiquette de version DB dans le footer
local function UpdateDBVersionLabel()
    if not verFS then return end
    local rv = (GuildLogisticsDB and GuildLogisticsDB.meta and GuildLogisticsDB.meta.rev) or 0
    verFS:SetText(Tr("lbl_db_version_prefix")..tostring(rv))
end

-- Affiche la version de l'addon dans le footer 
local function UpdateAddonVersionLabel()
    if not gmFS then return end
    -- Version locale de l’addon (via TOC, cf. GLOG.GetAddonVersion déjà fourni dans Core/Comm.lua)
    local ver = (GLOG and GLOG.GetAddonVersion and GLOG.GetAddonVersion()) or (ns and ns.Version) or ""
    ver = tostring(ver or "")
    -- Affichage minimaliste, sans clé de locale (ex.: "v1.2.3")
    gmFS:SetText((ver ~= "" and ("v" .. ver)) or "v ?")
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
    { key="time",  title=Tr("col_time"),       w=110 },
    { key="dir",   title=Tr("col_dir"),        w=70  },
    { key="state", title=Tr("col_state"),        w=160 },
    { key="type",  title=Tr("col_type"),        w=160 },
    { key="rv",    title=Tr("col_version_short"),        w=60  }, 
    { key="size",  title=Tr("col_size"),      w=80  },
    { key="chan",  title=Tr("col_channel"),       w=80  },
    { key="target",title=Tr("col_sender"),    min=200, flex=1 },
    { key="frag",  title=Tr("col_frag"),        w=70  },
    { key="view",  title="",           w=70  },
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
    -- Affiche l'heure réelle : conversion du temps "jeu" (it.ts) en epoch local
    local epoch = (GLOG and GLOG.PreciseToEpoch and GLOG.PreciseToEpoch(it.ts)) or (tonumber(it.ts or 0) or 0)
    if epoch <= 0 then epoch = (time and time()) or 0 end
    f.time:SetText(date("%H:%M:%S", epoch))

    f.dir:SetText(it.dir == "send" and "|cff9ecbff"..Tr("lbl_status_sent").."|r" or "|cff7dff9a"..Tr("lbl_status_recieved").."|r")

    local total = tonumber(it.total or 1) or 1
    local sent  = tonumber(it.sentCount or 0) or 0      -- fragments effectivement transmis (ENVOI)
    local got   = tonumber(it.gotCount  or 0) or 0      -- fragments effectivement reçus  (RECU)

    if it.dir == "send" then
        if sent <= 0 then
            f.state:SetText("|cffffff00"..Tr("lbl_status_waiting").."|r")
        elseif sent < total then
            f.state:SetText("|cffffd200"..Tr("lbl_status_inprogress").."|r")
        else
            f.state:SetText("|cff7dff9a"..Tr("lbl_status_transmitted").."|r")
        end
    else
        -- État côté réception : HELLO => compte à rebours puis élu
        local st = ""
        if it.type == "HELLO" then
            local hid = it.kv and it.kv.helloId
            if hid and ns.GLOG and ns.GLOG._GetHelloElect then
                local info = ns.GLOG._GetHelloElect(hid)
                local nowt = time()
                local started = (info and info.startedAt) or (it.tsFirst or nowt)
                local endsAt  = (info and info.endsAt) or (started + HELLO_WAIT_SEC)
                if nowt < endsAt then
                    st = Tr("lbl_status_discovering") .. tostring(math.max(0, endsAt - nowt)) .. "s"
                elseif info and info.decided then
                    st = Tr("lbl_status_elected") .. (info.winner or "?")
                end
            end
        end

        -- ➕ État générique côté réception si pas un HELLO (ou si HELLO non résolu)
        if st == "" then
            if got <= 0 then
                st = "|cffffff00"..Tr("lbl_status_inprogress").."|r"
            elseif got < total then
                st = ("|cffffd200"..Tr("lbl_status_assembling").."|r %d/%d"):format(got, total)
            else
                st = "|cff7dff9a"..Tr("lbl_status_recieved").."|r"
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
        local title = (it.dir=="send" and Tr("lbl_message_sent") or Tr("lbl_message_received"))

        -- Décodage k=v|k=v avec support payload compressé 'c=z|...'
        local preview = it.fullPayload or ""
        local dec = TryDecompressPayload and TryDecompressPayload(preview)
        if dec and dec ~= "" then preview = dec end
        local kv = {}
        for pair in string.gmatch(preview, "([^|]+)") do
            local k, v = pair:match("^(.-)=(.*)$")
            if k then kv[k] = v end
        end

        local function PrettyVal(v)
            if type(v) ~= "table" then return tostring(v) end
            local out = {}
            local n = #v
            for i = 1, math.min(n, 10) do out[#out+1] = tostring(v[i]) end
            if n > 10 then out[#out+1] = ("…(%d items)"):format(n) end
            return "[" .. table.concat(out, ", ") .. "]"
        end

        local decoded = {}
        for k,v in pairs(kv) do
            decoded[#decoded+1] = k .. " = " .. PrettyVal(v)
        end
        table.sort(decoded)

        local head = ("type=%s  rv=%s  lm=%s  chan=%s  emetteur=%s")
            :format(it.type or "?", tostring(kv.rv or it.rv or "?"), tostring(kv.lm or "?"), it.chan or "", emitter or "")
        local body = (#decoded>0) and table.concat(decoded, "\n") or Tr("lbl_empty_payload")
        local raw  = it.fullRaw or it.fullPayload or Tr("lbl_empty_raw")

        -- Nouveau popup : deux blocs séparés (formaté / brut), plus grand et sélectionnable
        ns.UI.PopupDualText(
            title,
            "Données formatées",
            head.."\n\n"..body,
            "Données brutes",
            raw,
            { width = 900, height = 620 }
        )
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
    -- ➕ Si le débug est désactivé : listes vides et mise en page safe
    if GLOG.IsDebugEnabled and not GLOG.IsDebugEnabled() then
        if lvRecv    then lvRecv:SetData({})    end
        if lvSend    then lvSend:SetData({})    end
        if lvPending then lvPending:SetData({}) end
        if lvRecv and lvRecv.Layout       then lvRecv:Layout()       end
        if lvSend and lvSend.Layout       then lvSend:Layout()       end
        if lvPending and lvPending.Layout then lvPending:Layout()    end
        return
    end

    local selfNorm = _normalize(_selfFullName())
    local recvData, sendData = {}, {}


    -- Split RECU / ENVOI + filtre UI côté RECU (on garde le traitement logique inchangé ailleurs)
    for _, e in ipairs(GLOG.GetDebugLogs()) do
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
    if lvPending and GLOG.GetPendingOutbox then
        local pending = GLOG.GetPendingOutbox() or {}
        lvPending:SetData(pending)
    end

    if lvRecv and lvRecv.Layout then lvRecv:Layout() end
    if lvSend and lvSend.Layout then lvSend:Layout() end
    if lvPending and lvPending.Layout then lvPending:Layout() end
end

local function Build(container)
    -- Création du conteneur
    panel, footer, footerH = UI.CreateMainContainer(container, {footer = true})

    -- Label version DB (bas-gauche)
    verFS = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    verFS:SetPoint("LEFT", footer, "LEFT", UI.OUTER_PAD or 12, 0)
    if UpdateDBVersionLabel then UpdateDBVersionLabel() end
    -- ⚠️ Pas de version d’addon dans le footer (gmFS supprimé)

    -- === Boutons du footer (créés DIRECTEMENT dans le footer) ===
    purgeDBBtn  = UI.Button(footer, Tr("btn_purge_debug"), { size="sm", minWidth=120 })
        :SetOnClick(function() GLOG.ClearDebugLogs(); Refresh() end)

    purgeAllBtn = UI.Button(footer, Tr("btn_purge_full"),  { size="sm", minWidth=120 })
    purgeAllBtn:SetConfirm(Tr("lbl_purge_confirm_all"), function()
        if GLOG.WipeAllSaved then
            GLOG.WipeAllSaved()
        elseif GLOG.WipeAllData then
            GLOG.WipeAllData()
            GuildLogisticsUI = { point="CENTER", relTo=nil, relPoint="CENTER", x=0, y=0, width=1160, height=680 }
        end
        ReloadUI()
    end)

    -- Boutons GM (même logique que Synthese : présents mais masqués si non-GM)
    purgeEpuBtn = UI.Button(footer, Tr("btn_purge_free_items_lots"), { size="sm", minWidth=240 })
    purgeEpuBtn:SetConfirm(Tr("lbl_purge_confirm_lots"), function()
        if GLOG.PurgeLotsAndItemsExhausted then
            local l, it = GLOG.PurgeLotsAndItemsExhausted()
            if UpdateDBVersionLabel then UpdateDBVersionLabel() end
            if ns.RefreshAll then ns.RefreshAll() end
            if UI.Toast then UI.Toast((Tr("lbl_purge_lots_confirm")):format(l or 0, it or 0)) end
        end
    end)

    purgeResBtn = UI.Button(footer, Tr("btn_purge_all_items_lots"), { size="sm", minWidth=180 })
    purgeResBtn:SetConfirm(Tr("lbl_purge_confirm_all_lots"), function()
        if GLOG.PurgeAllResources then
            local l, it = GLOG.PurgeAllResources()
            if UpdateDBVersionLabel then UpdateDBVersionLabel() end
            if ns.RefreshAll then ns.RefreshAll() end
            if UI.Toast then UI.Toast((Tr("lbl_purge_all_lots_confirm")):format(l or 0, it or 0)) end
        end
    end)

    forceSyncBtn = UI.Button(footer, Tr("btn_force_version_gm"), { size="sm", minWidth=200, tooltip = Tr("lbl_diffusing_snapshot") })
    forceSyncBtn:SetConfirm(Tr("lbl_diffusing_snapshot_confirm"), function()
        if GLOG and GLOG._SnapshotExport and GLOG.Comm_Broadcast then
            local newrv = (GLOG.IncRev and GLOG.IncRev()) or nil
            local snap = GLOG._SnapshotExport()
            if newrv then snap.rv = newrv end
            GLOG.Comm_Broadcast("SYNC_FULL", snap)
        end
    end)

    -- Alignement à droite IMMÉDIAT (comme dans Synthese)
    if UI.AttachButtonsFooterRight then
        local isMaster = GLOG.IsMaster and GLOG.IsMaster()
        if isMaster then
            UI.AttachButtonsFooterRight(footer, { forceSyncBtn, purgeEpuBtn, purgeResBtn, purgeDBBtn, purgeAllBtn })
        else
            UI.AttachButtonsFooterRight(footer, { purgeDBBtn, purgeAllBtn })
        end
    end

    -- === Trois zones empilées : REÇU (40%) / ENVOI (40%) / FILE (reste) ===
    recvArea    = CreateFrame("Frame", nil, panel)
    sendArea    = CreateFrame("Frame", nil, panel)
    pendingArea = CreateFrame("Frame", nil, panel)

    UI.SectionHeader(recvArea,    Tr("lbl_incoming_packets"))
    lvRecv    = UI.ListView(recvArea, cols, { buildRow = BuildRow, updateRow = UpdateRow, topOffset = UI.SECTION_HEADER_H or 26 })

    UI.SectionHeader(sendArea,    Tr("lbl_outgoing_packets"))
    lvSend    = UI.ListView(sendArea, cols, { buildRow = BuildRow, updateRow = UpdateRow, topOffset = UI.SECTION_HEADER_H or 26 })

    UI.SectionHeader(pendingArea, Tr("lbl_pending_queue"))
    lvPending = UI.ListView(pendingArea, {
        { key="time", title=Tr("col_time"), w=110 },
        { key="type", title=Tr("col_type"), w=100 },
        { key="info", title=Tr("col_request"), min=240, flex=1 },
    }, {
        buildRow = function(r)
            local f = {}
            f.time = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            f.type = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            f.info = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            return f
        end,
        updateRow = UpdatePendingRow,
        topOffset = UI.SECTION_HEADER_H or 26
    })

    -- Placement type Synthese : zones au-dessus du footer
    local function PositionAreas()
        local pH      = panel:GetHeight() or 600
        local footerH = footer:GetHeight() or (UI.FOOTER_H or 36)
        local topOff  = 10
        local gap     = 10
        local usable  = math.max(0, pH - footerH - topOff)
        local hRecv   = math.floor(usable * 0.40)
        local hSend   = math.floor(usable * 0.40)

        recvArea:ClearAllPoints()
        recvArea:SetPoint("TOPLEFT",  panel, "TOPLEFT",  0, -topOff)
        recvArea:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -topOff)
        recvArea:SetHeight(hRecv)

        sendArea:ClearAllPoints()
        sendArea:SetPoint("TOPLEFT",  panel, "TOPLEFT",  0, -(topOff + hRecv + gap))
        sendArea:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -(topOff + hRecv + gap))
        sendArea:SetHeight(hSend)

        pendingArea:ClearAllPoints()
        pendingArea:SetPoint("TOPLEFT",  panel, "TOPLEFT",  0, -(topOff + hRecv + gap + hSend + gap))
        pendingArea:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -(topOff + hRecv + gap + hSend + gap))
        pendingArea:SetPoint("BOTTOMLEFT",  footer, "TOPLEFT",  0, 0)
        pendingArea:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT", 0, 0)

        if lvRecv and lvRecv.Layout then lvRecv:Layout() end
        if lvSend and lvSend.Layout then lvSend:Layout() end
        if lvPending and lvPending.Layout then lvPending:Layout() end
    end

    PositionAreas()
    if panel and panel.HookScript then
        panel:HookScript("OnSizeChanged", PositionAreas)
    end
end


-- ➕ Layout avec footer et visibilité GM
local function Layout()
    local isMaster = GLOG.IsMaster and GLOG.IsMaster()

    -- Visibilités GM comme dans Synthese
    if forceSyncBtn then forceSyncBtn:SetShown(isMaster) end
    if purgeEpuBtn  then purgeEpuBtn:SetShown(isMaster)  end
    if purgeResBtn  then purgeResBtn:SetShown(isMaster)  end

    -- Ré-attache les boutons à droite du footer (compact)
    if UI.AttachButtonsFooterRight and footer then
        if isMaster then
            UI.AttachButtonsFooterRight(footer, { forceSyncBtn, purgeEpuBtn, purgeResBtn, purgeDBBtn, purgeAllBtn }, 8, nil)
        else
            UI.AttachButtonsFooterRight(footer, { purgeDBBtn, purgeAllBtn }, 8, nil)
        end
    end

    if lvRecv and lvRecv.Layout then lvRecv:Layout() end
    if lvSend and lvSend.Layout then lvSend:Layout() end
    if lvPending and lvPending.Layout then lvPending:Layout() end
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

-- Affichage lisible d’une (sous-)table pour le debug réseau (évite "table: 0x...")
function GLOG.Debug_TinyDump(v, depth)
    depth = depth or 2
    local t = type(v)
    if t ~= "table" then return tostring(v) end
    if depth <= 0 then return "{...}" end
    local out, n = {}, 0
    local isArray = true
    local maxk = 0
    for k,_ in pairs(v) do
        if type(k) ~= "number" then isArray = false break end
        if k > maxk then maxk = k end
    end
    if isArray then
        for i=1, math.min(maxk, 5) do
            out[#out+1] = GLOG.Debug_TinyDump(v[i], depth-1)
        end
        if maxk > 5 then out[#out+1] = ("…(%d items)"):format(maxk) end
        return "["..table.concat(out,", ").."]"
    else
        for k,val in pairs(v) do
            n = n + 1
            if n > 5 then out[#out+1] = "…"; break end
            out[#out+1] = tostring(k)..":"..GLOG.Debug_TinyDump(val, depth-1)
        end
        return "{"..table.concat(out,", ").."}"
    end
end

UI.RegisterTab(Tr("tab_debug"), Build, Refresh, Layout, {
    category = Tr("cat_debug"),
})