local ADDON, ns = ...
ns.UI = ns.UI or {}
local UI = ns.UI

-- =========================
--   Configuration police
-- =========================
UI.GLOBAL_FONT_ENABLED = true
-- Laisse UI.GLOBAL_FONT_PATH nil pour auto-détection.
UI.GLOBAL_FONT_PATH    = "Interface\\AddOns\\GuildLogistics\\Ressources\\Fonts\\vixar.ttf" or nil
UI.GLOBAL_FONT_SCALE   = UI.GLOBAL_FONT_SCALE or 1.00
UI.GLOBAL_FONT_FLAGS   = UI.GLOBAL_FONT_FLAGS or nil   -- ex: "OUTLINE"

-- Tentatives de chemins possibles (ordre de préférence)
local _CANDIDATES = {
    "Interface\\AddOns\\GuildLogistics\\Ressources\\Fonts\\vixar.ttf", -- arborescence actuelle du projet
}

local _resolvedPath  -- cache

-- Applique la police au FontString (conserve taille/flags avec SCALE)
-- Somme le delta posé sur le FS et ses parents
local function _accumDelta(fs)
    local sum = 0
    if fs and fs.__glog_fontDelta then sum = sum + (tonumber(fs.__glog_fontDelta) or 0) end
    local p = (fs and fs.GetParent) and fs:GetParent() or nil
    while p do
        if p.__glog_fontDelta then sum = sum + (tonumber(p.__glog_fontDelta) or 0) end
        p = (p.GetParent and p:GetParent()) or nil
    end
    return sum
end

-- Capture la taille de base (une seule fois) pour éviter le cumul aux réapplies
local function _ensureBase(fs)
    if not fs or fs.__glog_baseCaptured then return end
    local file, size, flags = fs:GetFont()
    fs.__glog_baseFontFile  = file
    fs.__glog_baseFontSize  = tonumber(size) or 12
    fs.__glog_baseFontFlags = flags
    fs.__glog_baseCaptured  = true
end

local function _apply(fs)
    if not (fs and fs.SetFont) then return end
    _ensureBase(fs)

    local baseSize = fs.__glog_baseFontSize or select(2, fs:GetFont())
    local flags    = UI.GLOBAL_FONT_FLAGS or fs.__glog_baseFontFlags
    local path     = UI.GLOBAL_FONT_PATH

    local scaled = math.floor(baseSize * (UI.GLOBAL_FONT_SCALE or 1.0) + 0.5)
    local final  = scaled + _accumDelta(fs)
    if final < 6 then final = 6 end -- garde-fou

    fs:SetFont(path, final, flags)
end

-- API publique
function UI.ApplyFont(fs)
    if UI.GLOBAL_FONT_ENABLED then _apply(fs) end
    return fs
end

function UI.ApplyFontRecursively(frame)
    if not (UI.GLOBAL_FONT_ENABLED and frame and frame.GetRegions) then return end
    for _, r in ipairs({ frame:GetRegions() }) do
        if r and r.GetObjectType and r:GetObjectType() == "FontString" then
            _apply(r)
        end
    end
    if frame.GetChildren then
        for _, child in ipairs({ frame:GetChildren() }) do
            UI.ApplyFontRecursively(child)
        end
    end
end

-- Pose un delta de police sur un frame ; tous les FontString descendants l'héritent
function UI.SetFontDeltaForFrame(frame, delta, applyNow)
    if not frame then return end
    frame.__glog_fontDelta = tonumber(delta) or 0
    if applyNow and UI.ApplyFontRecursively then
        UI.ApplyFontRecursively(frame)
    end
end

-- Hook par frame: auto-apply quand CreateFontString est utilisé
function UI.AttachAutoFont(frame)
    if not frame or frame.__glog_autoFontAttached then return end
    local orig = frame.CreateFontString
    frame.CreateFontString = function(self, ...)
        local fs = orig(self, ...)
        if UI.GLOBAL_FONT_ENABLED then _apply(fs) end
        return fs
    end
    frame.__glog_autoFontAttached = true
end

-- =========================================================================
-- Application globale : parcourt tous les frames "GLOG_*" déjà créés
-- (utile si la police est chargée après la construction d’une partie de l’UI)
-- =========================================================================
local function _applyAllGLOGFrames()
    if not (UI and UI.ApplyFontRecursively) then return end
    if not EnumerateFrames then return end
    local f = EnumerateFrames()
    while f do
        local n = (f.GetName and f:GetName()) or nil
        if n and n:find("^GLOG_") then
            UI.ApplyFontRecursively(f)
        end
        f = EnumerateFrames(f)
    end
end

-- Applique maintenant + retente en différé pour couvrir les créations tardives
local function _applyNow(debugPrint)
    if debugPrint and DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffd200GuildLogistics|r: Application police sur frames GLOG_*")
    end
    _applyAllGLOGFrames()
    if C_Timer and C_Timer.After then
        C_Timer.After(0.10, _applyAllGLOGFrames)
        C_Timer.After(0.50, _applyAllGLOGFrames)
    end
end

-- API publique si besoin ailleurs
UI.ApplyFontNow = _applyNow

-- Événements : applique à l’init + à l’entrée monde
local _evt = CreateFrame("Frame")
_evt:RegisterEvent("ADDON_LOADED")
_evt:RegisterEvent("PLAYER_LOGIN")
_evt:RegisterEvent("PLAYER_ENTERING_WORLD")
_evt:SetScript("OnEvent", function(_, evt, arg1)
    -- On applique à ADDON_LOADED uniquement pour notre addon
    if evt == "ADDON_LOADED" then
        if tostring(arg1) ~= tostring(ADDON) then return end
        _applyNow(false)
    else
        _applyNow(false)
    end
end)