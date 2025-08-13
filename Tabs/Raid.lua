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

local function ComputePerHead()
    local total = tonumber(totalInput:GetText() or "0") or 0
    local count = 0
    for _, v in pairs(includes) do if v then count = count + 1 end end
    if count == 0 then return 0 end
    return math.floor(total / count)
end

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
        for _, n in ipairs(selected) do CDZ.Debit(n, per) end
        if #selected > 0 then CDZ.AddHistorySession(total, per, selected) end

        totalInput:SetText("")
        if ns.RefreshAll then ns.RefreshAll() end

        -- Popup de confirmation
        if #selected > 0 then
            local dlg = UI.CreatePopup({ title = "Clôture effectuée", width = 560, height = 220 })
            local moneyText = (UI and UI.MoneyText) and UI.MoneyText or function(v) return tostring(v).." po" end
            dlg:SetMessage(("La clôture a été enregistrée.\nParticipants : %d — Débit par joueur : %s.\n\nSouhaitez-vous notifier les joueurs ?")
                :format(#selected, moneyText(per)))

            dlg:SetButtons({
                {
                    text = "Notifier les joueurs", default = true,
                    onClick = function()
                        if not (CDZ.IsMaster and CDZ.IsMaster()) then
                            UIErrorsFrame:AddMessage("|cffff6060[CDZ]|r Notification réservée au GM.", 1, 0.4, 0.4)
                            return
                        end
                        for _, n in ipairs(selected) do
                            if CDZ.GM_ApplyAndBroadcastEx then
                                CDZ.GM_ApplyAndBroadcastEx(n, -per, { reason = "RAID_CLOSE" })
                            elseif CDZ.GM_ApplyAndBroadcast then
                                -- fallback sans étiquette (ne déclenchera pas le 'Bon raid !')
                                CDZ.GM_ApplyAndBroadcast(n, -per)
                            end
                        end
                    end,
                },
                {
                    text = "Fermer", variant = "ghost",
                    onClick = function()
                        if UI and UI.ShowTabByLabel then UI.ShowTabByLabel("Historique") end
                    end,
                },
            })

            dlg:Show()
        else
            if UI and UI.ShowTabByLabel then UI.ShowTabByLabel("Historique") end
        end
    end)

    lv = UI.ListView(panel, cols, { buildRow = BuildRow, updateRow = UpdateRow, topOffset = 0, bottomAnchor = footer })
end


UI.RegisterTab("Raid", Build, Refresh, Layout)
