-- Tabs/Demandes.lua
local ADDON, ns = ...
local Tr = ns and ns.Tr
local GLOG, UI, F = ns.GLOG, ns.UI, ns.Format
local PAD = UI.OUTER_PAD

local panel, lv

local cols = UI.NormalizeColumns({
    { key="date",  title=Tr("col_date"),   w=160 },
    { key="name",  title=Tr("col_player"), min=240, flex=1 },
    { key="op",    title=Tr("col_operation"), w=160 },
    { key="act",   title="", w=220 },
})

local function BuildRow(r)
    local f = {}
    f.date = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.name = UI.CreateNameTag(r)
    f.op   = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")

    f.act = CreateFrame("Frame", nil, r); f.act:SetHeight(UI.ROW_H); f.act:SetFrameLevel(r:GetFrameLevel()+1)
    r.btnApprove = UI.Button(f.act, Tr("btn_approve"), { size="sm", minWidth=120 })
    r.btnRefuse  = UI.Button(f.act, Tr("btn_refuse"),   { size="sm", variant="ghost", minWidth=100 })
    UI.AttachRowRight(f.act, { r.btnApprove, r.btnRefuse }, 8, -4, { leftPad=8, align="center" })
    return f
end

local function UpdateRow(i, r, f, it)
    f.date:SetText(F.DateTime(it.ts))
    UI.SetNameTag(f.name, it.name or "?")
    local op = (it.delta or 0) >= 0 and ("|cff40ff40+|r "..UI.MoneyText(it.delta)) or ("|cffff6060-|r "..UI.MoneyText(math.abs(it.delta or 0)))
    f.op:SetText(op)

    r.btnApprove:SetOnClick(function()
        if not GLOG.IsMaster or not GLOG.IsMaster() then return end
        -- Anti double-clic : masquer la ligne tout de suite
        if r and r.Hide then r:Hide() end
        if lv and lv.Layout then lv:Layout() end

        -- Traitement : appliquer et retirer de la file
        local who = it.who or it.name or "?"
        if GLOG.GM_ApplyAndBroadcastEx then
            GLOG.GM_ApplyAndBroadcastEx(who, tonumber(it.delta) or 0, {
                reason = "PLAYER_REQUEST",
                requester = who,
                uid = it.uid, -- info annexe pour traçabilité
            })
        elseif GLOG.GM_ApplyAndBroadcast then
            GLOG.GM_ApplyAndBroadcast(who, tonumber(it.delta) or 0)
        elseif GLOG.GM_ApplyAndBroadcastByUID then
            -- Fallback si les APIs ci-dessus n’existent pas
            GLOG.GM_ApplyAndBroadcastByUID(it.uid, tonumber(it.delta) or 0, {
                reason = "PLAYER_REQUEST", requester = who
            })
        end

        if GLOG.ResolveRequest then GLOG.ResolveRequest(it.id, true, Tr("badge_approved_list")) end

        -- Rafraîchit la liste et met à jour le badge/onglet
        if Refresh then Refresh() end
        if UI and UI.UpdateRequestsBadge then UI.UpdateRequestsBadge() end
    end)

    r.btnRefuse:SetOnClick(function()
        -- Anti double-clic : désactiver + masquer la ligne tout de suite
        if r.btnApprove.SetEnabled then r.btnApprove:SetEnabled(false) end
        if r.btnRefuse.SetEnabled  then r.btnRefuse:SetEnabled(false)  end
        if r and r.Hide then r:Hide() end
        if lv and lv.Layout then lv:Layout() end

        -- Traitement : retirer de la file
        if GLOG.ResolveRequest then GLOG.ResolveRequest(it.id, false, Tr("badge_refused_list")) end

        -- Rafraîchit la liste et met à jour le badge/onglet
        if Refresh then Refresh() end
        if UI and UI.UpdateRequestsBadge then UI.UpdateRequestsBadge() end

    end)

end

local function Layout()
    lv:Layout()
end

local function Refresh()
    local rows = {}
    if not GLOG.IsMaster or not GLOG.IsMaster() then
        lv:SetData({})
        if UI and UI.UpdateRequestsBadge then UI.UpdateRequestsBadge() end
        return
    end
    for _, r in ipairs(GLOG.GetRequests()) do
        -- Affichage : préférer le nom « who » transmis par le joueur ; sinon mapping UID → nom
        local display = r.who or (GLOG.GetNameByUID and GLOG.GetNameByUID(r.uid)) or "?"
        rows[#rows+1] = {
            id = r.id, ts = r.ts, uid = r.uid,
            who = r.who,           -- conserve le demandeur pour l'action d'approbation
            name = display, delta = r.delta
        }
    end
    lv:SetData(rows)
    if UI and UI.UpdateRequestsBadge then UI.UpdateRequestsBadge() end
    lv:Layout()
end


local function Build(container)
    panel = container
    if UI.ApplySafeContentBounds then UI.ApplySafeContentBounds(panel, { side = 10, bottom = 6 }) end
    lv = UI.ListView(panel, cols, { buildRow = BuildRow, updateRow = UpdateRow })
end

UI.RegisterTab(Tr("tab_requests"), Build, Refresh, Layout, { hidden = false })
