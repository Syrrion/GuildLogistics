local ADDON, ns = ...
local CDZ, UI, F = ns.CDZ, ns.UI, ns.Format
local PAD = UI.OUTER_PAD or 16

local panel, lv, purgeDBBtn, purgeAllBtn

local cols = UI.NormalizeColumns({
    { key="time",  title="Heure",     w=110 },
    { key="dir",   title="Sens",      w=70  },
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
        f.type:SetText(it.type or "")
    f.rv:SetText(it.rv and tostring(it.rv) or "")  -- <== affiche la version
    f.size:SetText(tostring(it.size or 0))
    f.chan:SetText(it.chan or "")
    f.target:SetText(it.target or "")
    f.frag:SetText((it.lastPart or 1).."/"..(it.total or 1))

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

local function Layout()
    if UI.AttachButtonsRight then
        UI.AttachButtonsRight(panel, { purgeDBBtn, purgeAllBtn }, 8, -PAD, -12)
    else
        purgeAllBtn:ClearAllPoints(); purgeAllBtn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -PAD, -12)
        purgeDBBtn:ClearAllPoints();  purgeDBBtn:SetPoint("RIGHT", purgeAllBtn, "LEFT", -8, 0)
    end
    if lv and lv.Layout then lv:Layout() end
end

-- Regroupe les fragments et décode rv/lm
local function groupLogs(raw)
    local map = {}
    for _, e in ipairs(raw) do
        local key = table.concat({ e.dir or "?", e.type or "?", e.chan or "?", e.target or "?", tostring(e.seq or 0) }, "|")
        local g = map[key]
        if not g then
            g = {
                ts = e.ts or 0,
                dir = e.dir, type = e.type, chan = e.chan, target = e.target,
                seq = e.seq or 0, total = e.total or 1, lastPart = e.part or 1, size = 0,
                parts = {},
            }
            map[key] = g
        end
        g.ts = math.max(g.ts or 0, e.ts or 0)
        g.size = (g.size or 0) + (tonumber(e.size) or 0)
        g.total = e.total or g.total
        g.lastPart = math.max(g.lastPart or 1, e.part or 1)
        g.parts[e.part or 1] = e.raw
    end

    local out = {}
    for _, g in pairs(map) do
        local payloads, raws = {}, {}
        for i = 1, (g.total or 1) do
            local raw = g.parts[i]
            if raw then
                raws[#raws+1] = raw
                payloads[#payloads+1] = raw:match("|n=%d+|(.*)$") or ""
            end
        end
        g.fullPayload = table.concat(payloads, "")
        g.fullRaw = table.concat(raws, "\n")
        -- Décoder pour extraire rv/lm si présents
        local decode = ns.CDZ and ns.CDZ._decodeForDebug or nil
        local kv = decode and decode(g.fullPayload) or nil
        if not kv and ns.CDZ and ns.CDZ._unsafeDecode then kv = ns.CDZ._unsafeDecode(g.fullPayload) end
        if not kv then
            -- mini-décodage local (k=v|k=v) pour debug
            kv = {}
            for pair in string.gmatch(g.fullPayload or "", "([^|]+)") do
                local k, v = pair:match("^(.-)=(.*)$")
                if k then kv[k] = v end
            end
        end
        g.kv = kv
        g.rv = tonumber(kv.rv or "") or nil
        g.lm = tonumber(kv.lm or "") or nil
        out[#out+1] = g
    end
    table.sort(out, function(a, b)
        -- priorité à lm si présent, sinon fallback ts
        local ad = tonumber(a.lm) or tonumber(a.ts) or 0
        local bd = tonumber(b.lm) or tonumber(b.ts) or 0
        if ad ~= bd then return ad > bd end
        local arv = tonumber(a.rv) or -math.huge
        local brv = tonumber(b.rv) or -math.huge
        if arv ~= brv then return arv > brv end
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
    if UI.ApplySafeContentBounds then UI.ApplySafeContentBounds(panel, { side = 10, bottom = 6 }) end

    purgeDBBtn = UI.Button(panel, "Purger DB", { size="sm", variant="danger", minWidth=140 })
    purgeDBBtn:SetConfirm("Supprimer TOUTES les données (Joueurs, Historique, Dépenses) ?", function()
        if CDZ.WipeAllData then CDZ.WipeAllData() end
        if ns and ns.RefreshAll then ns.RefreshAll() end
    end)

    purgeAllBtn = UI.Button(panel, "Purge totale (DB+UI)", { size="sm", variant="danger", minWidth=180 })
    purgeAllBtn:SetConfirm("Purger la DB + réinitialiser l’UI puis recharger ?", function()
        if CDZ.WipeAllSaved then
            CDZ.WipeAllSaved()
        elseif CDZ.WipeAllData then
            CDZ.WipeAllData()
            ChroniquesDuZephyrUI = { point="CENTER", relTo=nil, relPoint="CENTER", x=0, y=0, width=1160, height=680 }
        end
        ReloadUI()
    end)

    lv = UI.ListView(panel, cols, { buildRow = BuildRow, updateRow = UpdateRow, topOffset = 38 })
end

UI.RegisterTab("Debug", Build, Refresh, function() if lv and lv.Layout then lv:Layout() end end)
