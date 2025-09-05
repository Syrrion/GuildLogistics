local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI = ns.GLOG, ns.UI

-- =========================
--      État / Locaux
-- =========================
local panel, footer, lv, ticker, btnPause, btnClear
local isPaused = true -- ⬅️ démarre en pause

-- Utilise le dumper compact existant si dispo, sinon fallback
local function TinyDump(v, depth)
    if GLOG and GLOG.Debug_TinyDump then
        return GLOG.Debug_TinyDump(v, depth or 1)
    end
    depth = (depth or 1)
    local t = type(v)
    if t == "string" then
        local s = v:gsub("\r","\\r"):gsub("\n","\\n")
        if #s > 120 then s = s:sub(1,117) .. "..." end
        return '"'..s..'"'
    elseif t == "number" or t == "boolean" or t == "nil" then
        return tostring(v)
    elseif t == "table" then
        if depth <= 0 then return "{...}" end
        local out, n = {}, 0
        for k,val in pairs(v) do
            n = n + 1
            if n > 4 then out[#out+1] = "…"; break end
            out[#out+1] = tostring(k)..":"..TinyDump(val, depth-1)
        end
        return "{"..table.concat(out, ", ").."}"
    end
    return tostring(v)
end

-- =========================
--        ListView
-- =========================
local cols = UI.NormalizeColumns({
    { key="time",  title=Tr("col_time"),  w=90 },
    { key="event", title=Tr("col_event"), vsep=true, w=220 },
    { key="args",  title=Tr("col_content"), min=300, flex=1 },
})

local function BuildRow(r)
    local f = {}
    f.time  = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.event = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.args  = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.args:SetJustifyH("LEFT")
    return f
end

local function UpdateRow(i, r, f, it)
    -- Conversion d’un timestamp "précis" → epoch local (même logique que Debug_Packets)
    local epoch = (GLOG and GLOG.PreciseToEpoch and GLOG.PreciseToEpoch(it.ts)) or (tonumber(it.ts or 0) or 0)
    if epoch <= 0 then epoch = (time and time()) or 0 end
    f.time:SetText(date("%H:%M:%S", epoch))

    f.event:SetText(it.event or "")

    local parts = {}
    if type(it.args) == "table" then
        for a = 1, math.min(#it.args, 6) do
            parts[#parts+1] = TinyDump(it.args[a], 1)
        end
        if #it.args > 6 then parts[#parts+1] = "…(" .. tostring(#it.args - 6) .. ")" end
    end
    f.args:SetText(table.concat(parts, "  |  "))
end

-- Construit la data en inversant (dernier en haut), comme les autres vues debug
local MAX_ROWS = 200
local function _BuildDataFromLog()
    local log = (ns.Events and ns.Events.GetDebugLog and ns.Events.GetDebugLog()) or {}
    local out = {}
    local from = math.max(1, #log - (MAX_ROWS - 1))
    for i = #log, from, -1 do
        local e = log[i]
        out[#out+1] = { ts = e.ts, event = e.event, args = e.args }
    end
    return out
end


-- =========================
--     Build / Refresh / Layout
-- =========================
local function Build(container)
    -- Conteneur standard avec footer (pattern Debug_Packets / Debug_Database)
    panel, footer = UI.CreateMainContainer(container, { footer = true })

    -- En-tête de section
    local y = 0
    y = y + (UI.SectionHeader(panel, Tr("tab_debug_events") or "Historique des évènements", { topPad = y }) or (UI.SECTION_HEADER_H or 26)) + 8

    -- ListView
    lv = UI.ListView(panel, cols, { buildRow = BuildRow, updateRow = UpdateRow, topOffset = y })

        -- Bouton Vider
    btnClear = UI.Button and UI.Button(footer, (Tr and Tr("btn_clear")) or "Vider", { size="sm", minWidth=110 }) or btnClear
    if btnClear and btnClear.SetOnClick then
        btnClear:SetOnClick(function()
            if ns.Events and ns.Events.ClearDebugLog then ns.Events.ClearDebugLog() end
            if lv and lv.SetData then lv:SetData({}) end
        end)
    elseif btnClear and btnClear.SetScript then
        btnClear:SetScript("OnClick", function()
            if ns.Events and ns.Events.ClearDebugLog then ns.Events.ClearDebugLog() end
            if lv and lv.SetData then lv:SetData({}) end
        end)
    end

    -- Bouton Pause/Reprendre
    btnPause = UI.Button and UI.Button(footer, (Tr and Tr("btn_pause")) or "Pause", { size="sm", minWidth=110 }) or btnPause
    if btnPause and btnPause.SetOnClick then
        btnPause:SetOnClick(function()
            isPaused = not isPaused
            if ns.Events and ns.Events.SetDebugLogging then
                ns.Events.SetDebugLogging(not isPaused)
            end
            if btnPause.SetText then
                btnPause:SetText(isPaused and ((Tr and Tr("btn_resume")) or "Reprendre") or ((Tr and Tr("btn_pause")) or "Pause"))
            end
        end)
    elseif btnPause and btnPause.SetScript then
        btnPause:SetScript("OnClick", function()
            isPaused = not isPaused
            if ns.Events and ns.Events.SetDebugLogging then
                ns.Events.SetDebugLogging(not isPaused)
            end
            if btnPause.SetText then
                btnPause:SetText(isPaused and ((Tr and Tr("btn_resume")) or "Reprendre") or ((Tr and Tr("btn_pause")) or "Pause"))
            end
        end)
    end

    if UI.AttachButtonsFooterRight and footer and btnPause and btnClear then
        UI.AttachButtonsFooterRight(footer, { btnPause, btnClear }, 8, nil)
    end

    -- Init visuelle selon l'état réel du hub (par défaut: PAUSE)
    if ns.Events and ns.Events.IsDebugLoggingEnabled then
        isPaused = not ns.Events.IsDebugLoggingEnabled()
    end
    if btnPause and btnPause.SetText then
        btnPause:SetText(isPaused and ((Tr and Tr("btn_resume")) or "Reprendre") or ((Tr and Tr("btn_pause")) or "Pause"))
    end



    if UI.AttachButtonsFooterRight and footer then
        UI.AttachButtonsFooterRight(footer, { btnPause, btnClear }, 8, nil)
    end

    -- Ticker throttle : 1.0s + refresh seulement si révision change
    local lastRev = -1
    if C_Timer and C_Timer.NewTicker then
        if ticker and ticker.Cancel then ticker:Cancel() end
        ticker = C_Timer.NewTicker(1.5, function()
            if not panel or not panel:IsShown() then return end
            if isPaused then return end
            if not (ns.Events and ns.Events.GetDebugLogRev and ns.Events.GetDebugLog) then return end
            local rev = ns.Events.GetDebugLogRev()
            if rev == lastRev then return end
            lastRev = rev
            if lv and lv.SetData then
                lv:SetData(_BuildDataFromLog())
            end
        end)
    end
end

local function Refresh()
    if not panel or not panel:IsShown() then return end
    if not (ns.Events and ns.Events.GetDebugLogRev and ns.Events.GetDebugLog) then return end
    local rev = ns.Events.GetDebugLogRev()
    if lv and lv.SetData then
        lastRev = rev -- évite un SetData immédiat par le ticker
        lv:SetData(_BuildDataFromLog())
    end
end


local function Layout()
    if lv and lv.Layout then lv:Layout() end
end

-- Enregistre l’onglet dans la catégorie Débug (identique aux autres)
UI.RegisterTab(Tr("tab_debug_events") or "Historique des évènements", Build, Refresh, Layout, {
    category = Tr("cat_debug"),
})
