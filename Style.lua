-- Enemy Tracker: visual style shared by every window.
--
-- Flat dark surfaces, 1-pixel borders, one red accent, muted secondary text.
-- Everything is built from a plain white texture tinted per element, so it
-- needs no art assets and looks the same on every client.
local _, ET = ...

local UI = {}
ET.UI = UI

local WHITE = "Interface\\Buttons\\WHITE8X8"

local C = {
    bg        = { 0.067, 0.071, 0.086, 0.96 },
    surface   = { 0.110, 0.118, 0.141, 1 },
    hover     = { 0.150, 0.160, 0.190, 1 },
    border    = { 0.210, 0.224, 0.260, 1 },
    text      = { 0.93, 0.93, 0.95 },
    muted     = { 0.56, 0.58, 0.64 },
    accent    = { 0.92, 0.33, 0.33 },
    shared    = { 0.45, 0.67, 0.88 },
    ok        = { 0.38, 0.82, 0.52 },
    warn      = { 1.00, 0.80, 0.30 },
}
UI.C = C

local function hex(c)
    return string.format("|cff%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255)
end

-- "|cffRRGGBB" for a palette colour, for inline text colouring.
function UI.Hex(name) return hex(C[name]) end
function UI.Color(name, text) return hex(C[name]) .. text .. "|r" end

local FLAT = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 }

local function paint(f, bg, border)
    if not f.SetBackdrop then return end
    f:SetBackdrop(FLAT)
    f:SetBackdropColor(bg[1], bg[2], bg[3], bg[4] or 1)
    f:SetBackdropBorderColor(border[1], border[2], border[3], border[4] or 1)
end
UI.Paint = paint

-- CreateFrame with BackdropTemplate where the client needs it.
function UI.Frame(frameType, name, parent, template)
    local tpl = template
    if BackdropTemplateMixin then
        tpl = tpl and (tpl .. ",BackdropTemplate") or "BackdropTemplate"
    end
    return CreateFrame(frameType, name, parent, tpl)
end

function UI.Text(parent, font, color, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY", font or "GameFontHighlightSmall")
    local c = C[color or "text"]
    fs:SetTextColor(c[1], c[2], c[3])
    fs:SetJustifyH("LEFT")
    return fs
end

-- 1-pixel horizontal line from x1 to the right edge minus x2, at y.
function UI.Divider(parent, y, x1, x2)
    local t = parent:CreateTexture(nil, "ARTWORK")
    t:SetColorTexture(C.border[1], C.border[2], C.border[3], 1)
    t:SetHeight(1)
    t:SetPoint("TOPLEFT", x1 or 0, y)
    t:SetPoint("TOPRIGHT", -(x2 or 0), y)
    return t
end

-- Small muted caption above a section.
function UI.Section(parent, text)
    local fs = UI.Text(parent, "GameFontNormalSmall", "muted")
    fs:SetText(text)
    return fs
end

-------------------------------------------------------------------------------
-- Buttons. kind: nil (default), "primary" (accent fill), "danger" (accent
-- text), "ghost" (no background until hovered).
-------------------------------------------------------------------------------
local KINDS = {
    default = { bg = C.surface, hover = C.hover, border = C.border, text = C.text },
    primary = { bg = { C.accent[1] * 0.75, C.accent[2] * 0.75, C.accent[3] * 0.75, 1 },
                hover = { C.accent[1], C.accent[2], C.accent[3], 1 },
                border = { C.accent[1], C.accent[2], C.accent[3], 1 }, text = { 1, 1, 1 } },
    danger  = { bg = C.surface, hover = { 0.24, 0.12, 0.13, 1 }, border = { 0.42, 0.20, 0.21, 1 }, text = C.accent },
    ghost   = { bg = { 0, 0, 0, 0 }, hover = C.hover, border = { 0, 0, 0, 0 }, text = C.muted },
}

local function restyle(b)
    local k = b.etKind
    local enabled = b:IsEnabled()
    local bg = (b.etHover and enabled) and k.hover or k.bg
    paint(b, bg, k.border)
    local c = enabled and k.text or C.muted
    if b.etLabel then b.etLabel:SetTextColor(c[1], c[2], c[3]) end
    b:SetAlpha(enabled and 1 or 0.5)
end

function UI.Button(parent, text, w, name, kind)
    local b = UI.Frame("Button", name, parent)
    b:SetSize(w or 100, 24)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", 8, 0)
    fs:SetPoint("RIGHT", -8, 0)
    fs:SetJustifyH("CENTER")
    fs:SetWordWrap(false)
    b:SetFontString(fs)
    b.etLabel = fs
    b.etKind = KINDS[kind or "default"]
    b:SetText(text)
    b:HookScript("OnEnter", function(self) self.etHover = true restyle(self) end)
    b:HookScript("OnLeave", function(self) self.etHover = false restyle(self) end)
    for _, m in ipairs({ "SetEnabled", "Enable", "Disable" }) do
        hooksecurefunc(b, m, restyle)
    end
    restyle(b)
    return b
end

-- "×" close button for window and card corners.
function UI.CloseButton(parent, onClick)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(22, 22)
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    fs:SetPoint("CENTER", 0, 1)
    fs:SetText("×")
    fs:SetTextColor(C.muted[1], C.muted[2], C.muted[3])
    b:SetScript("OnEnter", function() fs:SetTextColor(C.accent[1], C.accent[2], C.accent[3]) end)
    b:SetScript("OnLeave", function() fs:SetTextColor(C.muted[1], C.muted[2], C.muted[3]) end)
    b:SetScript("OnClick", onClick or function() parent:Hide() end)
    return b
end

-------------------------------------------------------------------------------
-- Text input with a placeholder and an accent border while focused.
-------------------------------------------------------------------------------
function UI.EditBox(parent, w, name, placeholder)
    local e = UI.Frame("EditBox", name, parent)
    e:SetSize(w, 24)
    e:SetAutoFocus(false)
    e:SetFontObject("ChatFontNormal")
    e:SetTextInsets(8, 8, 0, 0)
    e:SetMaxLetters(48)
    paint(e, C.surface, C.border)
    local ph = e:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ph:SetPoint("LEFT", 9, 0)
    ph:SetPoint("RIGHT", -8, 0)
    ph:SetJustifyH("LEFT")
    ph:SetWordWrap(false)
    ph:SetText(placeholder or "")
    e.placeholder = ph
    local function update()
        ph:SetShown((e:GetText() or "") == "" and not e:HasFocus())
    end
    e:HookScript("OnEditFocusGained", function(self)
        paint(self, C.surface, C.accent)
        update()
    end)
    e:HookScript("OnEditFocusLost", function(self)
        paint(self, C.surface, C.border)
        update()
    end)
    e:HookScript("OnTextChanged", update)
    hooksecurefunc(e, "SetText", update)
    for _, m in ipairs({ "SetEnabled", "Enable", "Disable" }) do
        hooksecurefunc(e, m, function(self) self:SetAlpha(self:IsEnabled() and 1 or 0.5) end)
    end
    update()
    return e
end

-------------------------------------------------------------------------------
-- Square toggle with a label; a CheckButton, so GetChecked/OnClick work.
-------------------------------------------------------------------------------
function UI.Check(parent, label, name)
    local c = UI.Frame("CheckButton", name, parent)
    c:SetSize(16, 16)
    paint(c, C.surface, C.border)
    local mark = c:CreateTexture(nil, "ARTWORK")
    mark:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    mark:SetPoint("TOPLEFT", 3, -3)
    mark:SetPoint("BOTTOMRIGHT", -3, 3)
    c:SetCheckedTexture(mark)
    local fs = UI.Text(c, "GameFontHighlightSmall", "text")
    fs:SetPoint("LEFT", c, "RIGHT", 8, 0)
    fs:SetText(label)
    c.label = fs
    c:SetHitRectInsets(0, -(fs:GetStringWidth() + 10), 0, 0) -- the label is clickable too
    return c
end

-------------------------------------------------------------------------------
-- Thin vertical scrollbar (a Slider with a flat thumb).
-------------------------------------------------------------------------------
function UI.Scrollbar(parent)
    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("VERTICAL")
    s:EnableMouse(true)
    s:SetWidth(6)
    s:SetValueStep(1)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    local track = s:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(1, 1, 1, 0.04)
    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetColorTexture(C.border[1] * 1.6, C.border[2] * 1.6, C.border[3] * 1.6, 1)
    thumb:SetSize(6, 36)
    s:SetThumbTexture(thumb)
    return s
end

-------------------------------------------------------------------------------
-- Window: flat panel, accent line on top, title + subtitle, close button,
-- draggable by the header, closes with Escape.
-------------------------------------------------------------------------------
UI.HEADER_H = 44

function UI.Window(name, w, h, title, subtitle)
    local f = UI.Frame("Frame", name, UIParent)
    f:SetSize(w, h)
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    paint(f, C.bg, C.border)
    f:Hide()
    tinsert(UISpecialFrames, name)

    local bar = f:CreateTexture(nil, "ARTWORK")
    bar:SetColorTexture(C.accent[1], C.accent[2], C.accent[3], 1)
    bar:SetHeight(2)
    bar:SetPoint("TOPLEFT", 1, -1)
    bar:SetPoint("TOPRIGHT", -1, -1)

    local t = UI.Text(f, "GameFontNormalLarge", "text")
    t:SetPoint("TOPLEFT", 16, -14)
    t:SetText(title)
    f.title = t
    if subtitle then
        local s = UI.Text(f, "GameFontNormalSmall", "muted")
        s:SetPoint("LEFT", t, "RIGHT", 10, -1)
        s:SetText(subtitle)
        f.subtitle = s
    end
    local close = UI.CloseButton(f)
    close:SetPoint("TOPRIGHT", -8, -10)
    f.close = close
    UI.Divider(f, -UI.HEADER_H, 1, 1)
    return f
end

-------------------------------------------------------------------------------
-- Card: small floating panel (alerts, notes) with an accent strip on the left.
-------------------------------------------------------------------------------
function UI.Card(f, accent)
    paint(f, { 0.067, 0.071, 0.086, 0.94 }, C.border)
    local strip = f:CreateTexture(nil, "ARTWORK")
    local c = accent or C.accent
    strip:SetColorTexture(c[1], c[2], c[3], 1)
    strip:SetWidth(3)
    strip:SetPoint("TOPLEFT", 1, -1)
    strip:SetPoint("BOTTOMLEFT", 1, 1)
    f.strip = strip
    return f
end
