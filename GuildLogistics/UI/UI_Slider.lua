local ADDON, ns = ...
ns.UI = ns.UI or {}
local UI = ns.UI
local Tr = ns.Tr or function(s) return s end

-- UI.Slider(parent, { label="Transparence", min=0, max=100, step=1, value=50, width=220, tooltip=..., format=function(v)return v.."% end, name="OptionalGlobalName" })
-- Retourne un frame "wrap" avec :
--   wrap.slider  -> l'objet Slider
--   wrap.label   -> FontString du libellé
--   wrap.valueFS -> FontString de la valeur formatée
-- Méthodes utilitaires :
--   wrap:SetOnValueChanged(fn) -- fn(self, value)
--   wrap:SetValue(v) / wrap:GetValue()
--   wrap:SetFormat(func)       -- func(number)->string d’affichage à droite
function UI.Slider(parent, opts)
    opts = opts or {}
    local wrap = CreateFrame("Frame", nil, parent)

    local width   = tonumber(opts.width or 240)
    -- ⬇️ Hauteur augmentée car le slider passe sous le libellé
    local height  = tonumber(opts.height) or 42

    local minV    = tonumber(opts.min or 0) or 0
    local maxV    = tonumber(opts.max or 100) or 100
    local step    = tonumber(opts.step or 1) or 1
    local value   = tonumber(opts.value or minV) or minV
    local label   = tostring(opts.label or "")
    local formatF = opts.format or function(v) return tostring(v) end

    wrap:SetSize(width, height)

    -- Libellé (ligne du haut, à gauche)
    local fs = wrap:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("TOPLEFT", wrap, "TOPLEFT", 0, 0)
    fs:SetJustifyH("LEFT")
    fs:SetText((Tr and Tr(label)) or label)
    wrap.label = fs

    -- Valeur formatée (ligne du haut, à droite)
    local vfs = wrap:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    vfs:SetPoint("TOPRIGHT", wrap, "TOPRIGHT", 0, 0)
    vfs:SetJustifyH("RIGHT")
    wrap.valueFS = vfs

    -- Le libellé prend la place disponible à gauche de la valeur
    fs:SetPoint("RIGHT", vfs, "LEFT", -8, 0)

    -- 🔹 Génère un nom unique si absent, nécessaire pour OptionsSliderTemplate
    UI.__slider_uid = (UI.__slider_uid or 0) + 1
    local sliderName = opts.name or (tostring(ADDON or "GL") .. "_Slider" .. UI.__slider_uid)

    -- Slider (en dessous du libellé/valeur)
    local s = CreateFrame("Slider", sliderName, wrap, "OptionsSliderTemplate")
    s:SetHeight(16)
    local gapY = 6
    s:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -gapY)
    s:SetPoint("TOPRIGHT", vfs, "BOTTOMRIGHT", 0, -gapY)

    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s:EnableMouseWheel(true)
    s:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetValue()
        local nv = cur + (delta > 0 and step or -step)
        nv = math.max(minV, math.min(maxV, nv))
        self:SetValue(nv)
        if wrap._onChange then wrap._onChange(wrap, nv) end
    end)

    -- 🔹 Masquer les textes Low/High/Text du template (compat nom + fallback champs)
    local name = s:GetName()
    if name then
        local low  = _G[name .. "Low"]
        local high = _G[name .. "High"]
        local text = _G[name .. "Text"]
        if low  and low.SetText  then low:SetText("") end
        if high and high.SetText then high:SetText("") end
        if text and text.SetText then text:SetText("") end
    else
        if s.Low  and s.Low.SetText  then s.Low:SetText("") end
        if s.High and s.High.SetText then s.High:SetText("") end
        if s.Text and s.Text.SetText then s.Text:SetText("") end
    end

    local function _apply(v)
        vfs:SetText(formatF(v))
    end

    s:SetScript("OnValueChanged", function(self, v)
        v = math.floor((tonumber(v) or minV) / step + 0.5) * step
        _apply(v)
        wrap._pendingValue = v
        -- Commit live seulement si on ne veut pas le différer
        if not opts.applyOnRelease and wrap._onChange then
            wrap._onChange(wrap, v)
        end
    end)

    -- Application différée : commit au relâchement de la souris
    s:HookScript("OnMouseUp", function(self)
        if opts.applyOnRelease and wrap._onChange then
            local v = wrap._pendingValue or self:GetValue()
            wrap._onChange(wrap, v)
        end
    end)

    s:SetValue(value)
    _apply(value)

    wrap.slider = s

    if opts.tooltip and UI.SetTooltip then
        UI.SetTooltip(wrap, (Tr and Tr(opts.tooltip)) or tostring(opts.tooltip))
    end

    function wrap:SetOnValueChanged(fn) self._onChange = fn; return self end
    function wrap:SetValue(v) self.slider:SetValue(tonumber(v) or minV); return self end
    function wrap:GetValue() return self.slider:GetValue() end
    function wrap:SetFormat(f) formatF = f or formatF; _apply(self:GetValue()); return self end

    return wrap
end

