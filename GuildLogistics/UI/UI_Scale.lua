local ADDON, ns = ...
ns.UI = ns.UI or {}
local UI = ns.UI

UI.Scale = UI.Scale or {}
local Scale = UI.Scale

-- =========================
--   Configuration
-- =========================
-- Active/désactive la protection d’échelle
Scale.LOCK_ENABLED       = (Scale.LOCK_ENABLED ~= false)  -- true par défaut
-- Échelle effective visée pour nos fenêtres (1.0 = taille “réelle” pixel)
Scale.TARGET_EFF_SCALE   = 0.75

-- 📦 Pré-initialisation : utilise la valeur sauvegardée SI disponible dès le chargement
do
    local sv = rawget(_G, "GuildLogisticsUI_Char") or rawget(_G, "GuildLogisticsUI")
    local v  = sv and tonumber(sv.uiScale)
    if v and v >= 0.5 and v <= 1.25 then
        Scale.TARGET_EFF_SCALE = v
    end
end

-- Calcule et applique l'échelle locale pour atteindre l’échelle effective cible
local function _applyFixedScale(frame, targetEffScale)
    if not (frame and frame.SetScale) then return end
    local parent = frame:GetParent() or UIParent
    local parentEff = (parent.GetEffectiveScale and parent:GetEffectiveScale()) or 1
    local target   = targetEffScale or Scale.TARGET_EFF_SCALE or 1
    local localScale = target / parentEff
    frame:SetScale(localScale)
    frame.__glog_fixedScaleTarget = target
end

-- Registre des frames protégées
-- Hub local minimal (table) au lieu d’un frame dédié
local _evt = { frames = setmetatable({}, { __mode = "k" }) }

function Scale.Register(frame, targetEffScale)
    if not (Scale.LOCK_ENABLED and frame) then return end
    _evt.frames[frame] = targetEffScale or Scale.TARGET_EFF_SCALE or 1
    _applyFixedScale(frame, _evt.frames[frame])
end

local function _OnScaleEvent(_, evt, cvar)
    if evt == "CVAR_UPDATE" and (cvar ~= "uiScale" and cvar ~= "useUIScale") then return end
    for f, target in pairs(_evt.frames) do
        if f and f.SetScale then
            _applyFixedScale(f, target)
        else
            _evt.frames[f] = nil
        end
    end
end

ns.Events.Register("UI_SCALE_CHANGED",      _OnScaleEvent)
ns.Events.Register("DISPLAY_SIZE_CHANGED",  _OnScaleEvent)
ns.Events.Register("CVAR_UPDATE",           _OnScaleEvent)


-- Utilitaire public si besoin ponctuel
function Scale.ApplyNow(frame, targetEffScale)
    _applyFixedScale(frame, targetEffScale)
end

-- Applique le scale cible à TOUTES les frames enregistrées (une seule passe)
function Scale.ApplyAll(targetEffScale)
    if targetEffScale then Scale.TARGET_EFF_SCALE = targetEffScale end
    for f, _ in pairs(_evt.frames) do
        if f and f.SetScale then
            _applyFixedScale(f, Scale.TARGET_EFF_SCALE)
        else
            _evt.frames[f] = nil
        end
    end
end

-- Debug: /glogscale -> affiche les scales
SLASH_GLOGSCALE1 = "/glogscale"
SlashCmdList.GLOGSCALE = function()
    local p = UIParent:GetEffectiveScale()
    DEFAULT_CHAT_FRAME:AddMessage(("|cffffd200GuildLogistics|r: UIParent eff=|cffffff00%.3f|r  target=|cffffff00%.3f|r")
        :format(p, Scale.TARGET_EFF_SCALE or 1))
end
