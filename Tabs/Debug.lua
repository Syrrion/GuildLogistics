local ADDON, ns = ...
local CDZ, UI, F = ns.CDZ, ns.UI, ns.Format
local PAD = UI.OUTER_PAD or 16

local panel, lv, purgeDBBtn, purgeAllBtn, forceSyncBtn, footer


local cols = UI.NormalizeColumns({
    { key="time",  title="Heure",     w=110 },
    { key="dir",   title="Sens",      w=70  },
    { key="state", title="État",      w=100 },
    { key="type",  title="Type",      w=160 },
    { key="rv",    title="Ver.",      w=60  }, 
    { key="size",  title="Taille",    w=80  },
    { key="chan",  title="Canal",     w=80  },
    { key="target",title="Cible",     min=200, flex=1 },
    { key="frag",  title="Frag",      w=70  },
    { key="view",  title=" ",         w=70  },
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
        f.state:SetText("") -- côté réception on laisse vide comme avant
    end

    f.type:SetText(it.type or "")
    f.rv:SetText(it.rv and tostring(it.rv) or "")  -- <= affiche la version
    f.size:SetText(tostring(it.size or 0))
    f.chan:SetText(it.chan or "")
    f.target:SetText(it.target or "")

    local progress = (it.dir == "send") and sent or got
    f.frag:SetText(tostring(progress) .. "/" .. tostring(total))

    f.view:SetOnClick(function()
        if not (ns.UI and ns.UI.PopupText) then return end
        local title = (it.dir=="send" and "Message envoyé" or "Message reçu")

        -- Décodage simple k=v|k=v pour la popup
        local kv = {}
        for pair in string.gmatch(it.fullPayload or "", "([^|]+)") do
            local k, v = pair:match("^(.-)=(.*)$")
            if k then kv[k] = v end
        end

        local decoded = {}
        for k,v in pairs(kv) do
            decoded[#decoded+1] = k.." = "..tostring(v)
        end
        table.sort(decoded)

        local head = ("type=%s  rv=%s  lm=%s  chan=%s  target=%s")
            :format(it.type or "?", tostring(kv.rv or it.rv or "?"), tostring(kv.lm or "?"), it.chan or "", it.target or "")
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

        -- Décodage rv/lm à partir du payload (si présent)
        local kv = {}
        for pair in string.gmatch(g.fullPayload or "", "([^|]+)") do
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

        -- Sens : RECU doit précéder ENVOI (inversion de l'ordre précédent)
        local adir = (a.dir == "send") and 1 or 0
        local bdir = (b.dir == "send") and 1 or 0
        if adir ~= bdir then return adir < bdir end

        -- Dernier repli : horodatage brut pour stabilité
        return (a.ts or 0) > (b.ts or 0)
    end)

    return out
end

local function Refresh()
    local data = {}
    for _, e in ipairs(CDZ.GetDebugLogs()) do data[#data+1] = e end
    local grouped = groupLogs(data)
    lv:SetData(grouped)
    if lv and lv.Layout then lv:Layout() end
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

    -- ➕ Bouton GM : Forcer ma version (incrémente rev + snapshot complet)
    forceSyncBtn = UI.Button(footer, "Forcer ma version (GM)", {size="sm", minWidth=200, tooltip="Incrémente la version et diffuse un snapshot complet" })
    forceSyncBtn:SetConfirm("Diffuser et FORCER la version du GM (incrémenter la version) ?", function()
        if CDZ.GM_ForceVersionBroadcast then
            local rv = CDZ.GM_ForceVersionBroadcast()
            if UIErrorsFrame and rv then
                UIErrorsFrame:AddMessage("|cff40ff40[CDZ]|r Version envoyée (rv="..tostring(rv)..")", 0.4, 1, 0.4)
            end
        end
    end)

    -- ➕ Reparent dans le footer
    purgeDBBtn:SetParent(footer)
    purgeAllBtn:SetParent(footer)

    lv = UI.ListView(panel, cols, { buildRow = BuildRow, updateRow = UpdateRow, topOffset = 38, bottomAnchor = footer })
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
        -- Rafraîchit toujours le tri dès qu'un nouvel élément arrive (si la liste existe)
        if lv then
            Refresh()
        end
    end)
end

UI.RegisterTab("Debug", Build, Refresh, Layout)

