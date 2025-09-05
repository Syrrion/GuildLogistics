local ADDON, ns = ...
ns.UI = ns.UI or {}
local UI = ns.UI

-- Helper pour retrouver la ScrollBar d’un ScrollFrame “UIPanelScrollFrameTemplate”
function UI.GetScrollBar(scroll)
    if not scroll then return nil end
    local sb = scroll.ScrollBar or scroll.scrollbar
    if (not sb) and scroll.GetName then
        local n = scroll:GetName()
        if n then sb = _G[n .. "ScrollBar"] end
    end
    return sb
end

-- Skin “fine” de la ScrollBar (rail + pouce), avec comportements hover/drag
function UI.SkinScrollBar(scrollOrBar, opts)
    opts = opts or {}
    local sb = scrollOrBar
    if sb and sb.GetObjectType and sb:GetObjectType() == "ScrollFrame" then
        sb = UI.GetScrollBar(sb)
    end
    if not sb then return end

    local W   = tonumber(opts.width or UI.SCROLLBAR_W or 12) or 12
    local trk = opts.trackColor or UI.SCROLLBAR_TRACK or {0,0,0,0.30}
    local thn = opts.thumbColor or UI.SCROLLBAR_THUMB or {1,1,1,0.55}
    local hov = opts.thumbHover or UI.SCROLLBAR_THUMB_HOVER or {1,1,1,0.85}

    if sb.SetWidth then sb:SetWidth(W) end

    -- Cache l’UI par défaut (textures et boutons up/down)
    local regions = { sb:GetRegions() }
    for _, r in ipairs(regions) do
        if r and r.GetObjectType and r:GetObjectType() == "Texture" then
            r:SetTexture(nil)
        end
    end
    if sb.ScrollUpButton   then sb.ScrollUpButton:Hide()   end
    if sb.ScrollDownButton then sb.ScrollDownButton:Hide() end

    -- Rail (track) simple
    if not sb._gl_track then
        local t = sb:CreateTexture(nil, "BACKGROUND", nil, -7)
        t:SetColorTexture(trk[1], trk[2], trk[3], trk[4])
        t:SetPoint("TOP",    sb, "TOP",    0, 0)
        t:SetPoint("BOTTOM", sb, "BOTTOM", 0, 0)
        t:SetWidth(W)
        sb._gl_track = t
    else
        sb._gl_track:SetColorTexture(trk[1], trk[2], trk[3], trk[4])
        sb._gl_track:SetWidth(W)
    end

    -- Pouce (thumb)
    local thumb = (sb.GetThumbTexture and sb:GetThumbTexture()) or sb.ThumbTexture
    if thumb then
        thumb:SetTexture("Interface\\Buttons\\WHITE8x8")
        thumb:SetVertexColor(thn[1], thn[2], thn[3], thn[4])
        thumb:SetDrawLayer("ARTWORK", 1)
        -- largeur cohérente avec W, hauteur pilotée par Blizzard, on force juste une base mini
        local h = math.max(24, (thumb.GetHeight and thumb:GetHeight()) or 24)
        if thumb.SetSize then thumb:SetSize(W, h) end

        if not sb._gl_thumbHook then
            sb:EnableMouse(true)
            sb:HookScript("OnEnter", function()
                local t = (sb.GetThumbTexture and sb:GetThumbTexture()) or sb.ThumbTexture
                if t then t:SetVertexColor(hov[1], hov[2], hov[3], hov[4]) end
            end)
            sb:HookScript("OnLeave", function()
                local t = (sb.GetThumbTexture and sb:GetThumbTexture()) or sb.ThumbTexture
                if t then t:SetVertexColor(thn[1], thn[2], thn[3], thn[4]) end
            end)
            sb._gl_thumbHook = true
        end
    end

    -- Auto-thumb (hauteur proportionnelle au contenu)
    if UI.EnableAutoThumb then
        UI.EnableAutoThumb(sb, opts and opts.minThumbH)
    end

    sb._gl_skinned = true
end

-- Calcule et applique la hauteur du pouce en fonction de la part visible du contenu.
-- Accepte un ScrollFrame OU directement sa ScrollBar.
function UI.UpdateScrollThumb(scrollOrBar, minH)
    local sb = scrollOrBar
    local scroll = nil

    if sb and sb.GetObjectType and sb:GetObjectType() == "ScrollFrame" then
        scroll = sb
        sb = UI.GetScrollBar and UI.GetScrollBar(scroll) or nil
    else
        -- sb est la ScrollBar → son parent est le ScrollFrame
        if sb and sb.GetObjectType and sb:GetObjectType() == "Slider" then
            scroll = sb:GetParent()
        end
    end
    if not (sb and scroll and sb.GetHeight and scroll.GetHeight) then return end

    local trackH  = sb:GetHeight() or 0
    local viewH   = scroll:GetHeight() or 0
    local yr      = (scroll.GetVerticalScrollRange and scroll:GetVerticalScrollRange()) or 0
    local content = viewH + (yr or 0)
    if trackH <= 0 or viewH <= 0 or content <= 0 then
        -- si la géométrie n'est pas prête, re-essaie au frame suivant
        if C_Timer then C_Timer.After(0, function()
            if sb and sb:IsShown() then UI.UpdateScrollThumb(scrollOrBar, minH) end
        end) end
        return
    end

    local ratio = viewH / content -- part visible
    if ratio > 1 then ratio = 1 elseif ratio < 0 then ratio = 0 end

    local thumbH = math.floor((trackH * ratio) + 0.5)
    thumbH = math.max(tonumber(minH) or UI.SCROLLBAR_THUMB_MIN_H or 10, thumbH)

    local thumb = (sb.GetThumbTexture and sb:GetThumbTexture()) or sb.ThumbTexture
    if thumb then
        local W = (sb.GetWidth and sb:GetWidth()) or (UI.SCROLLBAR_W or 12)
        if thumb.SetSize then
            thumb:SetSize(W, thumbH)
        elseif thumb.SetHeight then
            thumb:SetHeight(thumbH)
        end
    end
end

-- Active la mise à jour automatique de la hauteur du pouce
function UI.EnableAutoThumb(scrollOrBar, minH)
    local sb = scrollOrBar
    local scroll = nil

    if sb and sb.GetObjectType and sb:GetObjectType() == "ScrollFrame" then
        scroll = sb
        sb = UI.GetScrollBar and UI.GetScrollBar(scroll) or nil
    else
        if sb and sb.GetObjectType and sb:GetObjectType() == "Slider" then
            scroll = sb:GetParent()
        end
    end
    if not (sb and scroll) then return end
    if sb._gl_autoThumb then return end
    sb._gl_autoThumb = true

    local function updateDeferred()
        if not (sb and scroll and sb:IsShown()) then return end
        -- On laisse la range/rect se mettre à jour
        C_Timer.After(0, function()
            if sb and scroll and sb:IsShown() then
                if scroll.UpdateScrollChildRect then scroll:UpdateScrollChildRect() end
                UI.UpdateScrollThumb(sb, minH)
            end
        end)
    end

    -- Événements pertinents
    scroll:HookScript("OnScrollRangeChanged", function() updateDeferred() end)
    scroll:HookScript("OnShow",                function() updateDeferred() end)
    if scroll.HookScript then
        scroll:HookScript("OnSizeChanged",     function() updateDeferred() end)
    end
    -- Quand le slider lui-même change de taille (rare, mais sûr)
    if sb.HookScript then
        sb:HookScript("OnSizeChanged",         function() updateDeferred() end)
        sb:HookScript("OnShow",                function() updateDeferred() end)
    end

    -- Premier calcul immédiat (déféré d’un frame pour sécurité)
    updateDeferred()
end
