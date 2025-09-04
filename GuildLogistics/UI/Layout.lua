local ADDON, ns = ...
ns.UI = ns.UI or {}
local UI = ns.UI

-- Affiche/masque tous les séparateurs verticaux attachés à 'region' (via region._vseps).
function UI.SetVSepsVisible(region, visible)
    if not region or not region._vseps then return end
    for _, t in pairs(region._vseps) do
        if t then
            if visible == false then
                if t.Hide then t:Hide() end
            else
                if t.Show then t:Show() end
            end
        end
    end
end
