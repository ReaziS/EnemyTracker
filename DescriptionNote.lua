-- Enemy Tracker: small note with the player's description, shown in a
-- screen corner when a blacklisted player of the opposing faction is
-- detected. Nothing is shown for an empty description.
local _, ET = ...
local L = ET.L

local MAX_NOTES = 3
local NOTE_W, GAP, MARGIN_X, MARGIN_Y = 260, 6, 30, 200

ET.NOTE_CORNERS = { "BOTTOMRIGHT", "BOTTOMLEFT", "TOPRIGHT", "TOPLEFT" }

local anchor
local notes = {}   -- fixed pool, created once
local order = {}   -- visible notes, newest first

local function S() return ET.db.settings end

local function layout()
    local corner = S().noteCorner
    local bottom = corner:find("BOTTOM") ~= nil
    for i, n in ipairs(order) do
        n:ClearAllPoints()
        if i == 1 then
            n:SetPoint(corner, anchor, corner, 0, 0)
        elseif bottom then
            n:SetPoint("BOTTOM", order[i - 1], "TOP", 0, GAP)
        else
            n:SetPoint("TOP", order[i - 1], "BOTTOM", 0, -GAP)
        end
    end
end

local function hideNote(n)
    if not n:IsShown() then return end
    n:Hide()
    n.key = nil
    n.generation = (n.generation or 0) + 1
    for i, o in ipairs(order) do
        if o == n then table.remove(order, i) break end
    end
    layout()
end

local function createNote(i)
    local n = ET.CreateBackdropFrame("Button", "EnemyTrackerNote" .. i, anchor)
    n:SetWidth(NOTE_W)
    n:SetFrameStrata("MEDIUM")
    if n.SetBackdropColor then
        n:SetBackdropColor(0.05, 0.03, 0.03, 0.88)
        n:SetBackdropBorderColor(0.7, 0.2, 0.2, 0.9)
    end
    n.title = n:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    n.title:SetPoint("TOPLEFT", 10, -8)
    n.title:SetPoint("RIGHT", -10, 0)
    n.title:SetJustifyH("LEFT")
    n.title:SetTextColor(1, 0.3, 0.25)
    n.text = n:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    n.text:SetPoint("TOPLEFT", n.title, "BOTTOMLEFT", 0, -4)
    n.text:SetPoint("RIGHT", -10, 0)
    n.text:SetJustifyH("LEFT")
    n.text:SetWordWrap(true)
    n:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    n:SetScript("OnClick", function(self) hideNote(self) end)
    n:Hide()
    notes[i] = n
    return n
end

local function applyAnchor()
    if not anchor then return end
    local corner = S().noteCorner
    local x = corner:find("RIGHT") and -MARGIN_X or MARGIN_X
    local y = corner:find("BOTTOM") and MARGIN_Y or -MARGIN_Y
    anchor:SetScale(S().noteScale or 1)
    anchor:ClearAllPoints()
    anchor:SetPoint(corner, UIParent, corner, x / anchor:GetScale(), y / anchor:GetScale())
    layout()
end

function ET:ShowDescriptionNote(key, name, description)
    if not anchor or description == "" then return false end
    -- Same player already shown: just restart its timer.
    local n
    for _, o in ipairs(order) do if o.key == key then n = o end end
    if not n then
        for i = 1, MAX_NOTES do
            if not notes[i]:IsShown() then n = notes[i] break end
        end
        n = n or order[#order] -- all busy: reuse the oldest
        hideNote(n)
        table.insert(order, 1, n)
    end
    n.key = key
    n.title:SetText(name)
    n.text:SetText(ET.EscapeText(description))
    n:SetHeight(30 + (n.text.GetStringHeight and n.text:GetStringHeight() or 14))
    n:Show()
    layout()
    n.generation = (n.generation or 0) + 1
    local gen, secs = n.generation, S().noteDuration or 10
    if secs > 0 then
        C_Timer.After(secs, function()
            if n.generation == gen then hideNote(n) end
        end)
    end
    return true
end

function ET:HideDescriptionNotes()
    for i = #order, 1, -1 do hideNote(order[i]) end
end

ET:On("LOGIN", function()
    anchor = CreateFrame("Frame", "EnemyTrackerNoteAnchor", UIParent)
    anchor:SetSize(NOTE_W, 1)
    for i = 1, MAX_NOTES do createNote(i) end
    applyAnchor()
end)

ET:On("DB_READY", function()
    local valid = false
    for _, c in ipairs(ET.NOTE_CORNERS) do if S().noteCorner == c then valid = true end end
    if not valid then S().noteCorner = ET.NOTE_CORNERS[1] end
end)

ET:On("ENEMY_DETECTED", function(key, entry)
    if not S().noteEnabled or ET:IsAlly(key) then return end
    local desc = ET:DescriptionOf(key)
    if desc == "" then return end
    local d = ET.nearby[key]
    ET:ShowDescriptionNote(key, d and d.name or entry.name, desc)
end)

ET:On("SETTINGS_CHANGED", function(what)
    if what == "noteCorner" or what == "noteScale" then applyAnchor()
    elseif what == "noteEnabled" and not S().noteEnabled then ET:HideDescriptionNotes() end
end)

ET:On("BLACKLIST_CHANGED", function(key, action)
    if action == "remove" or action == "reject" then
        for _, n in ipairs(order) do
            if n.key == key then hideNote(n) break end
        end
    end
end)

-- Shows a sample note (options "Test" button).
function ET:TestDescriptionNote()
    self:ShowDescriptionNote("\001test", L.TEST_NAME, L.NOTE_TEST_TEXT)
end
