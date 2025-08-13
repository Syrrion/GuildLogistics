local ADDON, ns = ...
local CDZ, UI = ns.CDZ, ns.UI
local PAD = UI.OUTER_PAD

local panel, totalLabel, totalInput, closeBtn, lv, footer, histBtn
local includes = {}

local cols = {
    { key="check", title="",      w=34,  justify="LEFT"  },
    { key="name",  title="Nom",   min=300, flex=1, justify="LEFT" },
    { key="solde", title="Solde", w=160, justify="LEFT"  },
    { key="after", title="Après", w=160, justify="LEFT"  },
}

-- Compte robuste : seulement les joueurs encore présents dans la DB
local function SelectedCount()
    local players = (ChroniquesDuZephyrDB and ChroniquesDuZephyrDB.players) or {}
    local n = 0
    for name in pairs(players) do
        if includes[name] then n = n + 1 end
    end
    return n
end

local function ComputePerHead()
    local total = tonumber(totalInput:GetText() or "0") or 0
    local selected = SelectedCount()
    return (selected > 0) and math.floor(total / selected) or 0
end

-- Au build (ou juste après), on écoute la suppression roster pour purger includes
ns.On("roster:removed", function(name)
    if includes[name] then
        includes[name] = nil
        if lv and lv.Refresh then lv:Refresh() end
    end
end)

local function BuildRow(r)
    local f = {}
    f.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
    f.name  = UI.CreateNameTag(r)
    f.solde = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.after = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    return f
end

local function UpdateRow(i, r, f, d)
    if includes[d.name] == nil then includes[d.name] = true end
    f.check:SetChecked(includes[d.name])
    f.check:SetScript("OnClick", function(self) includes[d.name] = self:GetChecked() and true or false; ns.RefreshAll() end)
    UI.SetNameTag(f.name, d.name or "")
    local solde = (d.credit or 0) - (d.debit or 0)
    f.solde:SetText(UI.MoneyText(solde))
    local per = ComputePerHead()
    local after = includes[d.name] and (solde - per) or solde
    f.after:SetText(UI.MoneyText(after))
end

local function Layout()
    totalLabel:ClearAllPoints()
    totalLabel:SetPoint("LEFT", footer, "LEFT", PAD, 0)
    totalInput:ClearAllPoints()
    totalInput:SetPoint("LEFT", totalLabel, "RIGHT", 8, 0)

    -- Boutons à droite : [Clôturer][Icône Historique]
    if UI.AttachButtonsFooterRight then
        UI.AttachButtonsFooterRight(footer, { closeBtn, histBtn })
    else
        closeBtn:ClearAllPoints()
        closeBtn:SetPoint("RIGHT", footer, "RIGHT", -PAD, 0)
        if histBtn then histBtn:ClearAllPoints(); histBtn:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0) end
    end

    lv:Layout()
end

local function Refresh()
    local players = CDZ.GetPlayersArray()
    lv:SetData(players)
    Layout()
end

local function Build(container)
    panel = container
    if UI.ApplySafeContentBounds then UI.ApplySafeContentBounds(panel, { side = 10, bottom = 6 }) end

    footer = UI.CreateFooter(panel, 36)

    totalLabel = footer:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    totalLabel:SetText("Montant global (po) :")

    totalInput = CreateFrame("EditBox", nil, footer, "InputBoxTemplate")
    totalInput:SetAutoFocus(false); totalInput:SetNumeric(true); totalInput:SetSize(120, 28)
    totalInput:SetScript("OnTextChanged", function() ns.RefreshAll() end)

    -- Icône Historique (ouvre la vue Historique en remplacement du contenu)
    histBtn = UI.IconButton(footer, "Interface\\Icons\\ability_bossmagistrix_timewarp1", { size=24, tooltip="Voir l’historique des répartitions" })
    histBtn:SetOnClick(function() UI.ShowTabByLabel("Historique") end)

    closeBtn = UI.Button(footer, "Clôturer les participations", { size="sm", minWidth=220 })
    closeBtn:SetOnClick(function()
        local total = tonumber(totalInput:GetText() or "0") or 0
        local selected = {}
        for name, v in pairs(includes) do if v then table.insert(selected, name) end end
        table.sort(selected)

        local per = (#selected > 0) and math.floor(total / #selected) or 0
        if #selected == 0 then return end

        local dlg = UI.CreatePopup({ title = "Clôture effectuée", width = 560, height = 220 })
        dlg:SetMessage(("Participants : %d — Débit par joueur : %s.\nQue souhaitez-vous faire ?")
            :format(#selected, UI.MoneyText(per)))

        local function sendBatch(silentFlag)
            local adjusts = {}
            for _, n in ipairs(selected) do
                adjusts[#adjusts+1] = { name = n, delta = -per }
            end
            if CDZ.GM_BroadcastBatch then
                CDZ.GM_BroadcastBatch(adjusts, { reason = "RAID_CLOSE", silent = silentFlag })
            else
                -- Fallback (très vieux clients) : envoi unitaire
                for _, a in ipairs(adjusts) do
                    if CDZ.GM_ApplyAndBroadcastEx then
                        CDZ.GM_ApplyAndBroadcastEx(a.name, a.delta, { reason = "RAID_CLOSE", silent = silentFlag })
                    elseif CDZ.GM_ApplyAndBroadcast then
                        CDZ.GM_ApplyAndBroadcast(a.name, a.delta)
                    end
                end
            end
            CDZ.AddHistorySession(total, per, selected)
            totalInput:SetText("")
            if ns.RefreshAll then ns.RefreshAll() end
        end

        dlg:SetButtons({
            { text = "Notifier les joueurs", default = true, onClick = function() sendBatch(false) end },
            { text = "Valider", onClick = function() sendBatch(true); if UI and UI.ShowTabByLabel then UI.ShowTabByLabel("Historique") end end },
            { text = "Annuler", variant = "ghost" },
        })

        dlg:Show()
    end)

    lv = UI.ListView(panel, cols, { buildRow = BuildRow, updateRow = UpdateRow, topOffset = 0, bottomAnchor = footer })
end


UI.RegisterTab("Raid", Build, Refresh, Layout)
