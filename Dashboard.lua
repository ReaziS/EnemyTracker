-- Enemy Tracker: dashboard window (blacklist, statistics, search, management).
-- Uses a virtual list (fixed set of row frames + scroll offset), so it stays
-- fast with hundreds of entries.
local _, ET = ...
local L = ET.L

local W, H = 660, 470
local ROW_H, VISIBLE_ROWS = 20, 15

local frame, rows, slider, searchBox, addBox, totalText, scanCheck
local clearBtn, removeBtn
local data = {}         -- filtered + sorted entries { key, entry }
local offset = 0
local selectedKey
local sortKey, sortDesc = "lastSeen", true

local COLUMNS = {
    { id = "name",       label = "COL_NAME",       x = 8,   w = 160, justify = "LEFT" },
    { id = "killedMe",   label = "COL_KILLED_ME",  x = 170, w = 80,  justify = "CENTER" },
    { id = "iKilled",    label = "COL_I_KILLED",   x = 252, w = 80,  justify = "CENTER" },
    { id = "lastSeen",   label = "COL_LAST_SEEN",  x = 334, w = 120, justify = "CENTER" },
    { id = "addedAt",    label = "COL_ADDED",      x = 456, w = 110, justify = "CENTER" },
    { id = "detections", label = "COL_DETECTIONS", x = 568, w = 50,  justify = "CENTER" },
}

local STAT_COLUMN = { killedMe = true, iKilled = true, detections = true }

local function valueOf(e, id)
    if STAT_COLUMN[id] then return e.stats[id] end
    return e[id]
end

local function rebuildData()
    wipe(data)
    local filter = searchBox and ET.Utf8Lower(ET.Trim(searchBox:GetText() or "")) or ""
    for key, e in pairs(ET.db.enemies) do
        if filter == "" or key:find(filter, 1, true) then
            data[#data + 1] = { key = key, e = e }
        end
    end
    table.sort(data, function(a, b)
        local va, vb = valueOf(a.e, sortKey), valueOf(b.e, sortKey)
        if sortKey == "name" then va, vb = a.key, b.key end
        va, vb = va or 0, vb or 0
        if va == vb then return a.key < b.key end
        if sortDesc then return va > vb end
        return va < vb
    end)
end

local function updateRows()
    if not frame or not frame:IsShown() then return end
    local maxOffset = math.max(0, #data - VISIBLE_ROWS)
    if offset > maxOffset then offset = maxOffset end
    slider:SetMinMaxValues(0, maxOffset)
    slider:SetValue(offset)
    slider:SetShown(maxOffset > 0)
    for i = 1, VISIBLE_ROWS do
        local row = rows[i]
        local item = data[offset + i]
        if item then
            local e = item.e
            row.key = item.key
            row.cols.name:SetText(e.needsSurname and (e.name .. " |cff999999" .. L.NO_SURNAME .. "|r") or e.name)
            row.cols.killedMe:SetText(e.stats.killedMe)
            row.cols.iKilled:SetText(e.stats.iKilled)
            local seen = ET.nearby[item.key] and ("|cff40ff40" .. L.JUST_NOW .. "|r") or ET.FormatAgo(e.lastSeen)
            row.cols.lastSeen:SetText(seen)
            row.cols.addedAt:SetText(ET.FormatDate(e.addedAt))
            row.cols.detections:SetText(e.stats.detections)
            row.sel:SetShown(item.key == selectedKey)
            row:Show()
        else
            row.key = nil
            row:Hide()
        end
    end
    totalText:SetFormattedText(L.TOTAL, ET:EnemyCount(), #data)
    local hasSel = selectedKey and ET.db.enemies[selectedKey] ~= nil
    clearBtn:SetEnabled(hasSel and true or false)
    removeBtn:SetEnabled(hasSel and true or false)
    scanCheck:SetChecked(ET.db.settings.scanEnabled)
end

local function refresh()
    if not frame or not frame:IsShown() then return end
    if selectedKey and not ET.db.enemies[selectedKey] then selectedKey = nil end
    rebuildData()
    updateRows()
end

local function makeButton(parent, text, w)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w or 110, 22)
    b:SetText(text)
    return b
end

local function makeEditBox(parent, w)
    local e = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    e:SetSize(w, 20)
    e:SetAutoFocus(false)
    e:SetMaxLetters(48)
    return e
end

local function create()
    frame = ET.CreateBackdropFrame("Frame", "EnemyTrackerDashboard", UIParent)
    frame:SetSize(W, H)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        ET.SavePosition(self, ET.db.positions.dashboard)
    end)
    if frame.SetBackdropColor then frame:SetBackdropColor(0.05, 0.05, 0.05, 0.95) end
    frame:Hide()
    tinsert(UISpecialFrames, "EnemyTrackerDashboard") -- close with Escape

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText(L.DASH_TITLE)

    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    -- Search
    local searchLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    searchLabel:SetPoint("TOPLEFT", 16, -44)
    searchLabel:SetText(L.SEARCH)
    searchBox = makeEditBox(frame, 160)
    searchBox:SetPoint("LEFT", searchLabel, "RIGHT", 10, 0)
    searchBox:SetScript("OnTextChanged", function() offset = 0; refresh() end)
    searchBox:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)

    -- Add
    addBox = makeEditBox(frame, 130)
    addBox:SetPoint("LEFT", searchBox, "RIGHT", 30, 0)
    local addBtn = makeButton(frame, L.BTN_ADD, 80)
    addBtn:SetPoint("LEFT", addBox, "RIGHT", 6, 0)
    local function doAdd()
        if ET:AddEnemy(addBox:GetText()) then addBox:SetText("") end
        addBox:ClearFocus()
    end
    addBtn:SetScript("OnClick", doAdd)
    addBox:SetScript("OnEnterPressed", doAdd)
    addBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    local addTarget = makeButton(frame, L.BTN_ADD_TARGET, 120)
    addTarget:SetPoint("LEFT", addBtn, "RIGHT", 6, 0)
    addTarget:SetScript("OnClick", function() ET:AddTarget() end)

    -- Column headers (click to sort)
    local listTop = -76
    for _, c in ipairs(COLUMNS) do
        local h = CreateFrame("Button", nil, frame)
        h:SetSize(c.w, 18)
        h:SetPoint("TOPLEFT", 12 + c.x, listTop)
        local fs = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetAllPoints()
        fs:SetJustifyH(c.justify)
        fs:SetText(L[c.label])
        h:SetScript("OnClick", function()
            if sortKey == c.id then sortDesc = not sortDesc
            else sortKey, sortDesc = c.id, c.id ~= "name" end
            refresh()
        end)
        h:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    end

    -- Rows
    local listFrame = CreateFrame("Frame", nil, frame)
    listFrame:SetPoint("TOPLEFT", 12, listTop - 20)
    listFrame:SetSize(W - 44, ROW_H * VISIBLE_ROWS)
    listFrame:EnableMouseWheel(true)
    listFrame:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, math.min(offset - delta * 3, math.max(0, #data - VISIBLE_ROWS)))
        updateRows()
    end)
    rows = {}
    for i = 1, VISIBLE_ROWS do
        local row = CreateFrame("Button", nil, listFrame)
        row:SetSize(W - 44, ROW_H)
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, (i % 2 == 0) and 0.04 or 0)
        local sel = row:CreateTexture(nil, "BORDER")
        sel:SetAllPoints()
        sel:SetColorTexture(0.9, 0.2, 0.2, 0.3)
        sel:Hide()
        row.sel = sel
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        row.cols = {}
        for _, c in ipairs(COLUMNS) do
            local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("LEFT", c.x, 0)
            fs:SetWidth(c.w)
            fs:SetJustifyH(c.justify)
            fs:SetWordWrap(false)
            row.cols[c.id] = fs
        end
        row:SetScript("OnClick", function(self)
            selectedKey = (selectedKey == self.key) and nil or self.key
            updateRows()
        end)
        rows[i] = row
    end

    slider = CreateFrame("Slider", nil, frame)
    slider:SetOrientation("VERTICAL")
    slider:SetPoint("TOPLEFT", listFrame, "TOPRIGHT", 6, 0)
    slider:SetPoint("BOTTOMLEFT", listFrame, "BOTTOMRIGHT", 6, 0)
    slider:SetWidth(14)
    slider:SetValueStep(1)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    slider:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    track:SetColorTexture(1, 1, 1, 0.08)
    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value + 0.5)
        if value ~= offset then offset = value; updateRows() end
    end)

    -- Bottom bar
    clearBtn = makeButton(frame, L.BTN_CLEAR, 130)
    clearBtn:SetPoint("BOTTOMLEFT", 16, 40)
    clearBtn:SetScript("OnClick", function()
        local e = selectedKey and ET.db.enemies[selectedKey]
        if e then ET:ConfirmClear(e.name) end
    end)
    removeBtn = makeButton(frame, L.BTN_REMOVE, 110)
    removeBtn:SetPoint("LEFT", clearBtn, "RIGHT", 8, 0)
    removeBtn:SetScript("OnClick", function()
        local e = selectedKey and ET.db.enemies[selectedKey]
        if e then ET:ConfirmRemove(e.name) end
    end)

    scanCheck = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    scanCheck:SetSize(24, 24)
    scanCheck:SetPoint("LEFT", removeBtn, "RIGHT", 20, 0)
    local scanLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    scanLabel:SetPoint("LEFT", scanCheck, "RIGHT", 2, 0)
    scanLabel:SetText(L.SCANNING)
    scanCheck:SetScript("OnClick", function(self) ET:SetScanning(self:GetChecked()) end)

    totalText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    totalText:SetPoint("BOTTOMRIGHT", -18, 46)

    local note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("BOTTOMLEFT", 16, 16)
    note:SetPoint("BOTTOMRIGHT", -16, 16)
    note:SetJustifyH("LEFT")
    frame.note = note

    frame:SetScript("OnShow", function()
        note:SetText(ET.combatLogAvailable == false and L.STATS_UNAVAILABLE or L.STATS_NOTE)
        refresh()
    end)
    ET.RestorePosition(frame, ET.db.positions.dashboard, "CENTER", 0, 0)
end

function ET:ToggleDashboard()
    if not frame then create() end
    frame:SetShown(not frame:IsShown())
end

function ET:ShowDashboard()
    if not frame then create() end
    frame:Show()
end

ET:On("DB_READY", function()
    ET.db.positions.dashboard = ET.db.positions.dashboard or {}
end)
ET:On("BLACKLIST_CHANGED", refresh)
ET:On("NEARBY_CHANGED", refresh)
ET:On("SETTINGS_CHANGED", refresh)
ET:On("POSITIONS_RESET", function()
    ET.db.positions.dashboard = {}
    if frame then ET.RestorePosition(frame, ET.db.positions.dashboard, "CENTER", 0, 0) end
end)
