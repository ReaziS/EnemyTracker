-- Enemy Tracker: "nemeses nearby" counter and the list of players detected now.
-- Counts unique blacklisted players currently reported by any detection
-- source. It is NOT a count of all enemy players in the zone.
--
-- Clicking a name targets that player. Addons cannot target from code, so
-- each row gets a secure overlay button running "/targetexact Name" (the same
-- way as alert toasts). Secure buttons cannot be shown, hidden or changed in
-- combat: they are hidden when combat starts and the list then says that
-- targeting works again after combat.
local _, ET = ...
local L = ET.L
local UI = ET.UI

local W, ROW_H, MAX_ROWS = 260, 34, 8
local HEADER_H, FOOTER_H, MORE_H = 32, 28, 18

local counter, list
local rows, overlays = {}, {}
-- Set from PLAYER_REGEN_DISABLED to _ENABLED. InCombatLockdown() turns true a
-- moment after the event; until then nothing may show an overlay again, or it
-- would stay clickable in combat with a name that no longer matches its row.
local inCombat = false

local function locked() return inCombat or InCombatLockdown() end

local function shouldShow()
    local s = ET.db.settings
    if not s.showCounter then return false end
    return not s.locked or ET:NearbyCount() > 0
end

local function sourceLabel(source)
    return L["SRC_" .. tostring(source)] or tostring(source or "")
end

local function setChevron(open)
    if not counter.chevron then return end
    local a, b = counter.chevron[1], counter.chevron[2]
    -- Closed: "v" (opens downward). Open: "^".
    local r = math.rad(open and 45 or -45)
    a:SetRotation(r)
    b:SetRotation(-r)
end

-------------------------------------------------------------------------------
-- Rows and their secure overlays
-------------------------------------------------------------------------------
local function targetable(i)
    local b = overlays[i]
    return b ~= nil and b:IsShown()
end

local function rowEnter(i, owner)
    local row = rows[i]
    if not row.key then return end
    row.hl:Show()
    local accent = UI.C[targetable(i) and "accent" or "muted"]
    row.cross:SetVertexColor(accent[1], accent[2], accent[3])
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:AddLine(row.name, UI.C.accent[1], UI.C.accent[2], UI.C.accent[3])
    local desc = ET:DescriptionOf(row.key)
    if desc ~= "" then GameTooltip:AddLine(ET.EscapeText(desc), 1, 1, 1, true) end
    local c = UI.C[targetable(i) and "ok" or "warn"]
    GameTooltip:AddLine(targetable(i) and L.NEARBY_HINT or L.NEARBY_COMBAT, c[1], c[2], c[3], true)
    GameTooltip:Show()
end

local function rowLeave(i)
    local row = rows[i]
    row.hl:Hide()
    row.cross:SetVertexColor(UI.C.muted[1], UI.C.muted[2], UI.C.muted[3])
    GameTooltip:Hide()
end

local function getOverlay(i)
    if overlays[i] then return overlays[i] end
    if InCombatLockdown() then return nil end
    local b = CreateFrame("Button", "EnemyTrackerNearbyTarget" .. i, UIParent, "SecureActionButtonTemplate")
    b:SetFrameStrata("HIGH")
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type1", "macro")
    b:SetAllPoints(rows[i])
    b:Hide()
    b:SetScript("OnEnter", function(self) rowEnter(i, self) end)
    b:SetScript("OnLeave", function() rowLeave(i) end)
    b:HookScript("PostClick", function(self, button, down)
        ET:Debug("nearby click", button, down and "down" or "up", "macro:",
            tostring(self:GetAttribute("macrotext1")), "combat:", tostring(InCombatLockdown()))
    end)
    overlays[i] = b
    return b
end

-- Puts an overlay over every visible row (out of combat only).
local function syncOverlays()
    if locked() then return end
    local open = list and list:IsShown() and counter:IsShown()
    for i = 1, MAX_ROWS do
        local name = open and rows[i]:IsShown() and rows[i].name or nil
        local b = name and getOverlay(i) or overlays[i]
        if b then
            if name then
                local macro = "/targetexact " .. name
                if b:GetAttribute("macrotext1") ~= macro then b:SetAttribute("macrotext1", macro) end
                b:SetFrameLevel(list:GetFrameLevel() + 10)
                b:Show()
            else
                b:Hide()
            end
        end
    end
end

local function hideOverlays()
    if InCombatLockdown() then return end
    for _, b in pairs(overlays) do b:Hide() end
end

-------------------------------------------------------------------------------
-- Refresh
-------------------------------------------------------------------------------
local function refreshList()
    if not list or not list:IsShown() then return end
    local data = ET:GetNearbyList()
    local now = GetTime()
    for i = 1, MAX_ROWS do
        local row, d = rows[i], data[i]
        if d then
            row.key, row.name = d.key, d.name
            local e = ET:GetTracked(d.key)
            local c = UI.C[(e and e.shared) and "shared" or "accent"]
            row.dot:SetColorTexture(c[1], c[2], c[3], 1)
            row.nameText:SetText(d.name)
            local ago = math.floor(now - (d.lastSeen or now))
            row.sub:SetText(sourceLabel(d.source) .. "  ·  "
                .. (ago > 1 and string.format(L.NEARBY_AGO, ago) or L.NEARBY_NOW))
            row:Show()
        else
            row.key, row.name = nil, nil
            row:Hide()
        end
    end
    syncOverlays()
    local n = math.min(#data, MAX_ROWS)
    local anyTarget = false
    for i = 1, n do
        rows[i].cross:SetShown(targetable(i))
        anyTarget = anyTarget or targetable(i)
    end
    list.count:SetText(#data > 0 and tostring(#data) or "")
    list.empty:SetShown(#data == 0)
    local more = #data > MAX_ROWS
    list.more:SetShown(more)
    if more then list.more:SetFormattedText(L.NEARBY_MORE, #data - MAX_ROWS) end
    if #data == 0 then
        list.hint:SetText("")
    elseif anyTarget then
        list.hint:SetText(L.NEARBY_HINT)
        list.hint:SetTextColor(UI.C.muted[1], UI.C.muted[2], UI.C.muted[3])
    else
        list.hint:SetText(L.NEARBY_COMBAT)
        list.hint:SetTextColor(UI.C.warn[1], UI.C.warn[2], UI.C.warn[3])
    end
    list:SetHeight(HEADER_H + math.max(1, n) * ROW_H + (more and MORE_H or 0) + FOOTER_H)
end

local function refresh()
    if not counter then return end
    local count = ET:NearbyCount()
    counter.text:SetFormattedText(L.COUNTER, count)
    counter:SetWidth(math.max(120, counter.text:GetStringWidth() + 56))
    local c = UI.C[count > 0 and "accent" or "muted"]
    counter.dot:SetColorTexture(c[1], c[2], c[3], 1)
    counter:SetShown(shouldShow())
    if not counter:IsShown() and list then list:Hide() end
    refreshList()
end

-------------------------------------------------------------------------------
-- Frames
-------------------------------------------------------------------------------
local function createRow(i)
    local row = CreateFrame("Frame", nil, list)
    row:SetSize(W - 2, ROW_H)
    row:SetPoint("TOPLEFT", 1, -HEADER_H - (i - 1) * ROW_H)
    row:EnableMouse(true) -- tooltip in combat, when there is no overlay
    row:SetScript("OnEnter", function(self) rowEnter(i, self) end)
    row:SetScript("OnLeave", function() rowLeave(i) end)

    local hl = row:CreateTexture(nil, "BACKGROUND")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.05)
    hl:Hide()
    row.hl = hl

    local dot = row:CreateTexture(nil, "ARTWORK")
    dot:SetSize(6, 6)
    dot:SetPoint("LEFT", 12, 0)
    row.dot = dot

    row.nameText = UI.Text(row, "GameFontHighlight", "text")
    row.nameText:SetPoint("TOPLEFT", 26, -4)
    row.nameText:SetPoint("RIGHT", -32, 0)
    row.nameText:SetWordWrap(false)

    row.sub = UI.Text(row, "GameFontNormalSmall", "muted")
    row.sub:SetPoint("BOTTOMLEFT", 26, 4)
    row.sub:SetPoint("RIGHT", -32, 0)
    row.sub:SetWordWrap(false)

    -- Crosshair on the right: shown when a click will target.
    local cross = row:CreateTexture(nil, "ARTWORK")
    cross:SetSize(16, 16)
    cross:SetPoint("RIGHT", -12, 0)
    cross:SetTexture("Interface\\Cursor\\Crosshairs")
    cross:SetVertexColor(UI.C.muted[1], UI.C.muted[2], UI.C.muted[3])
    row.cross = cross

    rows[i] = row
end

local function createList()
    list = UI.Frame("Frame", "EnemyTrackerNearbyList", counter)
    list:SetWidth(W)
    list:SetPoint("TOP", counter, "BOTTOM", 0, -4)
    list:SetFrameStrata("HIGH")
    list:SetClampedToScreen(true)
    list:EnableMouse(true)
    UI.Paint(list, UI.C.bg, UI.C.border)

    local title = UI.Text(list, "GameFontNormalSmall", "muted")
    title:SetPoint("TOPLEFT", 12, -10)
    title:SetText(L.NEARBY_TITLE)
    local count = UI.Text(list, "GameFontNormalSmall", "text")
    count:SetPoint("TOPRIGHT", -12, -10)
    count:SetJustifyH("RIGHT")
    list.count = count
    UI.Divider(list, -HEADER_H + 4, 1, 1)

    local empty = UI.Text(list, "GameFontNormalSmall", "muted")
    empty:SetPoint("TOPLEFT", 12, -HEADER_H - 10)
    empty:SetText(L.NEARBY_EMPTY)
    list.empty = empty

    for i = 1, MAX_ROWS do createRow(i) end

    local more = UI.Text(list, "GameFontNormalSmall", "muted")
    more:SetPoint("BOTTOMLEFT", 12, FOOTER_H + 2)
    list.more = more

    local footer = list:CreateTexture(nil, "ARTWORK")
    footer:SetColorTexture(UI.C.border[1], UI.C.border[2], UI.C.border[3], 1)
    footer:SetHeight(1)
    footer:SetPoint("BOTTOMLEFT", 1, FOOTER_H)
    footer:SetPoint("BOTTOMRIGHT", -1, FOOTER_H)
    local hint = UI.Text(list, "GameFontNormalSmall", "muted")
    hint:SetPoint("BOTTOMLEFT", 12, 9)
    hint:SetPoint("BOTTOMRIGHT", -12, 9)
    hint:SetWordWrap(false)
    list.hint = hint

    list:Hide()
    -- Refresh "seconds ago" while the list is open; cheap and only when visible.
    list:SetScript("OnShow", function(self)
        setChevron(true)
        self.ticker = C_Timer.NewTicker(1, refreshList)
    end)
    list:SetScript("OnHide", function(self)
        setChevron(false)
        if self.ticker then self.ticker:Cancel(); self.ticker = nil end
        hideOverlays()
    end)
end

local function create()
    counter = UI.Frame("Button", "EnemyTrackerCounter", UIParent)
    counter:SetSize(140, 26)
    counter:SetFrameStrata("MEDIUM")
    counter:SetMovable(true)
    counter:SetClampedToScreen(true)
    UI.Paint(counter, UI.C.bg, UI.C.border)

    local dot = counter:CreateTexture(nil, "ARTWORK")
    dot:SetSize(8, 8)
    dot:SetPoint("LEFT", 12, 0)
    counter.dot = dot
    counter.text = UI.Text(counter, "GameFontHighlightSmall", "text")
    counter.text:SetPoint("LEFT", dot, "RIGHT", 8, 0)

    -- Chevron from two rotated bars (no glyph or art needed).
    if counter.CreateTexture then
        local bars = {}
        for k = 1, 2 do
            local t = counter:CreateTexture(nil, "ARTWORK")
            t:SetColorTexture(UI.C.muted[1], UI.C.muted[2], UI.C.muted[3], 1)
            t:SetSize(7, 2)
            t:SetPoint("RIGHT", counter, "RIGHT", k == 1 and -16 or -12, 0)
            bars[k] = t
        end
        if bars[1].SetRotation then counter.chevron = bars else
            bars[1]:Hide() bars[2]:Hide()
        end
    end

    counter:RegisterForClicks("LeftButtonUp")
    counter:RegisterForDrag("LeftButton")
    counter:SetScript("OnDragStart", function(self)
        if not ET.db.settings.locked then self:StartMoving() end
    end)
    counter:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        ET.SavePosition(self, ET.db.positions.counter)
        ET.RestorePosition(self, ET.db.positions.counter, "TOP", 0, -100)
    end)
    counter:SetScript("OnClick", function()
        if list:IsShown() then list:Hide() else list:Show(); refreshList() end
    end)
    counter:SetScript("OnEnter", function(self)
        UI.Paint(self, UI.C.bg, { UI.C.border[1] * 1.6, UI.C.border[2] * 1.6, UI.C.border[3] * 1.6, 1 })
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L.COUNTER_TIP, 1, 1, 1, true)
        if not ET.db.settings.locked then GameTooltip:AddLine(L.MOVER_COUNTER, 0.4, 1, 0.4) end
        GameTooltip:Show()
    end)
    counter:SetScript("OnLeave", function(self)
        UI.Paint(self, UI.C.bg, UI.C.border)
        GameTooltip:Hide()
    end)
    ET.RestorePosition(counter, ET.db.positions.counter, "TOP", 0, -100)
    createList()
    setChevron(false)
    -- Secure overlays are created out of combat, ready for the first click.
    if not InCombatLockdown() then
        for i = 1, MAX_ROWS do getOverlay(i) end
    end
end

ET:On("DB_READY", function()
    ET.db.positions.counter = ET.db.positions.counter or {}
end)
ET:On("LOGIN", function() create(); refresh() end)
ET:On("NEARBY_CHANGED", refresh)
ET:On("LOCK_CHANGED", refresh)
ET:On("SETTINGS_CHANGED", refresh)
ET:On("BLACKLIST_CHANGED", refresh)
ET:On("SHARED_CHANGED", refresh)
ET:On("POSITIONS_RESET", function()
    ET.db.positions.counter = {}
    if counter then ET.RestorePosition(counter, ET.db.positions.counter, "TOP", 0, -100) end
end)

-- PLAYER_REGEN_DISABLED fires just before combat lockdown: the last moment
-- secure overlays can be hidden. The list then shows the combat hint.
ET:RegisterEvent("PLAYER_REGEN_DISABLED", function()
    hideOverlays()
    inCombat = true
    C_Timer.After(0, refreshList)
end)
ET:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    inCombat = false
    if counter then
        for i = 1, MAX_ROWS do getOverlay(i) end
    end
    refreshList()
end)
