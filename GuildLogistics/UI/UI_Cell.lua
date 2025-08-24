local ADDON, ns = ...
local UI = ns and ns.UI
local Tr = ns and ns.Tr

-- ========================================================= --
--   Cellule générique "Classe" : icône + nom colorisé
--   API :
--     local cell = UI.CreateClassCell(parent, opts?)
--     UI.SetClassCell(cell, { classID=..., classTag=... })
--     UI.ClassColor(classID, classTag) -> r,g,b,a,hex
--     UI.WrapTextClassColor("text", classID, classTag) -> "|cAARRGGBBtext|r"
-- ========================================================= --

local CLASS_TEXTURE = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"

local function _ResolveClassInfo(classID, classTag)
    local cid = tonumber(classID)
    if (not cid) and classTag and UI and UI.GetClassIDForToken then
        cid = UI.GetClassIDForToken(classTag)
    end
    local info = (cid and C_CreatureInfo and C_CreatureInfo.GetClassInfo and C_CreatureInfo.GetClassInfo(cid)) or nil
    local classFile = (info and info.classFile) or (classTag and tostring(classTag):upper()) or nil
    local className = (info and (info.className or info.name)) or (UI and UI.ClassName and UI.ClassName(cid, classTag)) or tostring(classTag or "")
    return cid, classFile, className
end

function UI.ClassColor(classID, classTag)
    local _, classFile = _ResolveClassInfo(classID, classTag)
    local col
    if classFile and C_ClassColor and C_ClassColor.GetClassColor then
        col = C_ClassColor.GetClassColor(classFile)
    end
    if not col and RAID_CLASS_COLORS then
        col = RAID_CLASS_COLORS[classFile or ""]
    end
    if col and col.GetRGBA then
        local r, g, b, a = col:GetRGBA()
        return r or 1, g or 1, b or 1, a or 1, (col.colorStr or col:GenerateHexColor())
    elseif col then
        local r,g,b = col.r or 1, col.g or 1, col.b or 1
        local hex = ("ff%02x%02x%02x"):format((r*255+0.5), (g*255+0.5), (b*255+0.5))
        return r, g, b, 1, hex
    end
    return 1,1,1,1,"ffffffff"
end

function UI.WrapTextClassColor(text, classID, classTag)
    local _,_,_,_, hex = UI.ClassColor(classID, classTag)
    return ("|c%s%s|r"):format(hex, tostring(text or ""))
end

local function _SetClassIcon(tex, classFile)
    classFile = tostring(classFile or ""):upper()
    local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
    tex:SetTexture(CLASS_TEXTURE, nil, nil, "TRILINEAR")
    if coords then tex:SetTexCoord(coords[1], coords[2], coords[3], coords[4]) else tex:SetTexCoord(0,1,0,1) end
end

function UI.CreateClassCell(parent, opts)
    opts = opts or {}
    local f = CreateFrame("Frame", nil, parent)
    f:SetSize(opts.width or 160, opts.height or UI and UI.ROW_H or 20)

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(opts.iconSize or 16, opts.iconSize or 16)
    f.icon:SetPoint("LEFT", f, "LEFT", 0, 0)

    f.text = f:CreateFontString(nil, "ARTWORK", opts.font or "GameFontHighlight")
    f.text:SetPoint("LEFT", f.icon, "RIGHT", opts.margin or 6, 0)
    f.text:SetPoint("RIGHT", f, "RIGHT", 0, 0)
    f.text:SetJustifyH("LEFT")

    function f:SetText(s) f.text:SetText(s) end
    return f
end

function UI.SetClassCell(cell, params)
    if not cell then return end
    params = params or {}
    local cid, classFile, className = _ResolveClassInfo(params.classID, params.classTag)
    _SetClassIcon(cell.icon, classFile)
    local r,g,b = UI.ClassColor(cid, classFile)
    cell.text:SetText(className or "")
    cell.text:SetTextColor(r, g, b, 1)
end
