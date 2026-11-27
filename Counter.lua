-- Enemy Tracker: "nemeses nearby" counter and the list of players detected now.
-- Counts unique blacklisted players currently reported by any detection
-- source. It is NOT a count of all enemy players in the zone.
local _, ET = ...
local L = ET.L

local counter, list, rows = nil, nil, {}
local ROW_H, MAX_ROWS = 16, 20

local SOURCE_LABEL = {
    nameplate = "nameplate", target = "target", mouseover = "mouseover",
    focus = "focus", group = "group", combatlog = "combat log",
}

local function shouldShow()
    local s = ET.db.settings
    if not s.showCounter then return false end
    return not s.locked or ET:NearbyCount() > 0
end

local function refreshList()
    if not list or not list:IsShown() then return end
    local data = ET:GetNearbyList()
    local now = GetTime()
    for i = 1, MAX_ROWS do
        local row = rows[i]
        local d = data[i]
        if d then
            local ago = math.floor(now - d.lastSeen)
            row.left:SetText(d.name)
            row.right:SetText((SOURCE_LABEL[d.source] or d.source or "") .. (ago > 1 and (" (" .. ago .. "s)") or ""))
            row:Show()
        else
            row:Hide()
        end
    end
    list.empty:SetShown(#data == 0)
    local shown = math.max(1, math.min(#data, MAX_ROWS))
    list:SetHeight(34 + shown * ROW_H)
end

local function refresh()
    if not counter then return end
    counter.text:SetFormattedText(L.COUNTER, ET:NearbyCount())
    counter:SetWidth(math.max(120, counter.text:GetStringWidth() + 20))
    counter:SetShown(shouldShow())
    if not counter:IsShown() and list then list:Hide() end
    refreshList()
end

local function createList()
    local UI = ET.UI
    list = UI.Frame("Frame", "EnemyTrackerNearbyList", counter)
    list:SetWidth(240)
    list:SetPoint("TOP", counter, "BOTTOM", 0, -4)
    list:SetFrameStrata("HIGH")
    list:SetClampedToScreen(true)
    UI.Paint(list, UI.C.bg, UI.C.border)
    local title = UI.Text(list, "GameFontNormalSmall", "muted")
    title:SetPoint("TOPLEFT", 10, -8)
    title:SetText(L.NEARBY_TITLE)
    local empty = UI.Text(list, "GameFontNormalSmall", "muted")
    empty:SetPoint("TOPLEFT", 10, -26)
    empty:SetText(L.NEARBY_EMPTY)
    list.empty = empty
    for i = 1, MAX_ROWS do
        local row = CreateFrame("Frame", nil, list)
        row:SetSize(220, ROW_H)
        row:SetPoint("TOPLEFT", 10, -26 - (i - 1) * ROW_H)
        row.left = UI.Text(row, "GameFontHighlightSmall", "text")
        row.left:SetPoint("LEFT")
        row.right = UI.Text(row, "GameFontNormalSmall", "muted")
        row.right:SetPoint("RIGHT")
        rows[i] = row
    end
    list:Hide()
end

local function create()
    local UI = ET.UI
    counter = UI.Frame("Button", "EnemyTrackerCounter", UIParent)
    counter:SetSize(140, 24)
    counter:SetFrameStrata("MEDIUM")
    counter:SetMovable(true)
    counter:SetClampedToScreen(true)
    UI.Card(counter)
    counter.text = UI.Text(counter, "GameFontHighlightSmall", "text")
    counter.text:SetPoint("CENTER", 2, 0)
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
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
        GameTooltip:AddLine(L.COUNTER_TIP, 1, 1, 1, true)
        if not ET.db.settings.locked then GameTooltip:AddLine(L.MOVER_COUNTER, 0.4, 1, 0.4) end
        GameTooltip:Show()
    end)
    counter:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ET.RestorePosition(counter, ET.db.positions.counter, "TOP", 0, -100)
    createList()
    -- Refresh "seconds ago" while the list is open; cheap and only when visible.
    list:SetScript("OnShow", function(self)
        self.ticker = C_Timer.NewTicker(1, refreshList)
    end)
    list:SetScript("OnHide", function(self)
        if self.ticker then self.ticker:Cancel(); self.ticker = nil end
    end)
end

ET:On("DB_READY", function()
    ET.db.positions.counter = ET.db.positions.counter or {}
end)
ET:On("LOGIN", function() create(); refresh() end)
ET:On("NEARBY_CHANGED", refresh)
ET:On("LOCK_CHANGED", refresh)
ET:On("SETTINGS_CHANGED", refresh)
ET:On("BLACKLIST_CHANGED", refresh)
ET:On("POSITIONS_RESET", function()
    ET.db.positions.counter = {}
    if counter then ET.RestorePosition(counter, ET.db.positions.counter, "TOP", 0, -100) end
end)
