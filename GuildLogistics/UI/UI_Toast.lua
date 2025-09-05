local ADDON, ns = ...
ns.UI = ns.UI or {}
local UI = ns.UI
local Tr = ns.Tr

-- ==============================
--  UI.Toast : toasts génériques
-- ==============================
-- API :
--   UI.Toast({
--     title = "Titre",
--     text  = "Contenu du toast",
--     icon  = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew",
--     variant = "info" | "success" | "warning" | "error",
--     duration = 6,                         -- secondes ; <=0/false = illimitée
--     sticky = true,                        -- alias : durée illimitée
--     onClick  = function(frame) end,       -- clic sur le toast (ferme par défaut)
--     actionText = "Voir",                  -- (optionnel) bouton d'action
--     onAction   = function(frame) end,     -- callback bouton d'action
--     sound = SOUNDKIT.RAID_WARNING,        -- (optionnel)
--     key = "dedupe-key-optional",          -- dédoublonnage souple
--   })
--
--   UI.ToastError("Message", opts) -- raccourci variant="error"
--
-- Implementation : pile de toasts en haut-droite, auto-hide, clickable.
-- ==============================

local anchor
local active = {}
local dedupe = {}

local function _EnsureAnchor()
    if anchor then return anchor end
    anchor = CreateFrame("Frame", ADDON.."ToastAnchor", UIParent)
    anchor:SetSize(1,1)
    anchor:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -28, -120)
    anchor.toasts = {}
    return anchor
end

local function _VariantColors(variant)
    if variant == "success" then
        return { bg={0,0.35,0.15,0.92}, border={0.2,0.9,0.4,1} }
    elseif variant == "warning" then
        return { bg={0.35,0.25,0,0.92}, border={1,0.7,0.2,1} }
    elseif variant == "error" then
        return { bg={0.35,0,0,0.92}, border={1,0.25,0.25,1} }
    else -- info / default
        return { bg={0,0,0,0.85}, border={0.35,0.6,1,1} }
    end
end

local function _Reflow()
    local y = 0
    for i=1,#active do
        local f = active[i]
        f:ClearAllPoints()
        f:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", 0, -y)
        y = y + f:GetHeight() + 8
    end
end

local function _Remove(f)
    for i=1,#active do
        if active[i] == f then
            table.remove(active, i)
            break
        end
    end
    _Reflow()
    f:Hide()
    f:SetScript("OnUpdate", nil)
end

local function _CreateToast(opts)
    local f = CreateFrame("Button", nil, _EnsureAnchor(), "BackdropTemplate")
    f:SetSize(360, 64)
    f:SetFrameStrata("TOOLTIP")
    f:SetClampedToScreen(true)
    f:SetMovable(false)
    f:SetAlpha(0.999) -- évite un clignotement

    local colors = _VariantColors(opts.variant)

    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile   = "Interface\\Buttons\\WHITE8x8",
            edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1,
        })
        f:SetBackdropColor(unpack(colors.bg))
        f:SetBackdropBorderColor(unpack(colors.border))
    end

    -- Icone
    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(24,24)
    f.icon:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -10)
    f.icon:SetTexture(opts.icon or "Interface\\FriendsFrame\\InformationIcon")

    -- Titre
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    f.title:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 8, -2)
    f.title:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    f.title:SetJustifyH("LEFT")
    f.title:SetText(opts.title or "Notification")
    
    -- Applique la police au titre
    if UI and UI.ApplyFont and f.title then
        UI.ApplyFont(f.title)
    end

    -- Texte
    f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.text:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -4)
    f.text:SetPoint("RIGHT", f, "RIGHT", -10, 0)
    f.text:SetJustifyH("LEFT")
    f.text:SetSpacing(2)
    f.text:SetText(opts.text or "")
    
    -- Applique la police au texte
    if UI and UI.ApplyFont and f.text then
        UI.ApplyFont(f.text)
    end

    -- Bouton action (optionnel)
    if opts.actionText and opts.onAction then
        f.action = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        f.action:SetText(opts.actionText)
        f.action:SetSize(80, 20)
        f.action:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -10, 8)
        f.action:SetScript("OnClick", function()
            pcall(opts.onAction, f)
            _Remove(f)
        end)
    end

    -- Taille verticale selon contenu
    f:SetHeight( math.max(64, 18 + f.title:GetStringHeight() + 6 + f.text:GetStringHeight() + (f.action and 24 or 0)) )

    -- Interactions
    f:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(1,1,1,1)
    end)
    f:SetScript("OnLeave", function(self)
        local c = _VariantColors(opts.variant).border
        self:SetBackdropBorderColor(c[1], c[2], c[3], c[4])
    end)
    f:SetScript("OnClick", function(self)
        if opts.onClick then pcall(opts.onClick, self) end
        _Remove(self)
    end)

    -- Auto-hide (durée illimitée si sticky=true, ou duration<=0 / false / nil)
    local sticky = (opts.sticky == true)
                   or (opts.duration == false)
                   or (type(opts.duration) == "number" and opts.duration <= 0)
    if not sticky then
        local t0, dur = GetTime(), tonumber(opts.duration or 6)
        f:SetScript("OnUpdate", function(self)
            if (GetTime() - t0) >= dur then _Remove(self) end
        end)
    else
        f:SetScript("OnUpdate", nil) -- pas d'auto-hide, clic pour fermer
    end


    -- Son
    if opts.sound then
        pcall(PlaySound, opts.sound)
    end

    return f
end

function UI.Toast(opts)
    opts = type(opts)=="table" and opts or { text = tostring(opts or "") }
    -- Dédoublonnage souple court (3s) par clé
    if opts.key and dedupe[opts.key] then
        if (GetTime() - dedupe[opts.key]) < 3 then return end
    end
    if opts.key then dedupe[opts.key] = GetTime() end

    local f = _CreateToast(opts)
    table.insert(active, 1, f)
    _Reflow()
    f:Show()
    return f
end

function UI.ToastError(text, opts)
    opts = opts or {}
    opts.text    = text
    opts.variant = "error"
    opts.icon    = opts.icon or "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew"
    opts.title   = opts.title or (Tr and Tr("toast_error_title")) or "Lua Error"
    opts.sound   = false--(opts.sound ~= false) and (SOUNDKIT and SOUNDKIT.RAID_WARNING) or nil
    return UI.Toast(opts)
end
