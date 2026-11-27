-- Enemy Tracker: dashboard window (blacklist, statistics, search, management).
-- Uses a virtual list (fixed set of row frames + scroll offset), so it stays
-- fast with hundreds of entries.
local _, ET = ...
local L = ET.L

local W, H = 660, 540
local ROW_H, VISIBLE_ROWS = 20, 15

local frame, rows, slider, searchBox, addBox, totalText, scanCheck
local clearBtn, removeBtn, descBox, descSave, joinBox, joinBtn, createBtn
local descKey           -- record whose description is in descBox
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
    -- Players shared by groups, listed with the player's own.
    for key, e in pairs(ET.sharedView) do
        if filter == "" or key:find(filter, 1, true) then
            data[#data + 1] = { key = key, e = e, shared = true }
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
            local label = e.name
            if e.needsSurname then label = label .. " |cff999999" .. L.NO_SURNAME .. "|r"
            elseif item.shared then label = "|cff6fa8dc" .. label .. "|r" end
            row.cols.name:SetText(label)
            row.cols.killedMe:SetText(e.stats.killedMe)
            row.cols.iKilled:SetText(e.stats.iKilled)
            local seen = ET.nearby[item.key] and ("|cff40ff40" .. L.JUST_NOW .. "|r") or ET.FormatAgo(e.lastSeen)
            row.cols.lastSeen:SetText(seen)
            row.cols.addedAt:SetText(item.shared and ("|cff6fa8dc" .. L.FROM_GROUP .. "|r") or ET.FormatDate(e.addedAt))
            row.cols.detections:SetText(e.stats.detections)
            row.sel:SetShown(item.key == selectedKey)
            row:Show()
        else
            row.key = nil
            row:Hide()
        end
    end
    local shared = 0
    for _ in pairs(ET.sharedView) do shared = shared + 1 end
    totalText:SetFormattedText(L.TOTAL_SHARED, ET:EnemyCount(), shared, #data)
    local hasSel = selectedKey and ET.db.enemies[selectedKey] ~= nil
    local sharedSel = selectedKey and not hasSel and ET.sharedView[selectedKey] ~= nil
    clearBtn:SetEnabled(hasSel and true or false)
    -- For a shared player the button adds them to the player's own list.
    removeBtn:SetText(sharedSel and L.BTN_ADD_TO_MINE or L.BTN_REMOVE)
    removeBtn:SetEnabled((hasSel or sharedSel) and true or false)
    scanCheck:SetChecked(ET.db.settings.scanEnabled)
    local free = ET:GroupCount() < ET.MAX_GROUPS
    joinBtn:SetEnabled(free)
    createBtn:SetEnabled(free)
    -- Load the selected player's description, but never overwrite what the
    -- user is typing for the same player.
    if descKey ~= selectedKey then
        descKey = hasSel and selectedKey or nil
        descBox:SetText(descKey and ET.db.enemies[descKey].description
            or (sharedSel and ET.sharedView[selectedKey].description) or "")
        descBox:ClearFocus()
    end
    descBox:SetEnabled(hasSel and true or false)
    descSave:SetEnabled(hasSel and true or false)
end

local function refresh()
    if not frame or not frame:IsShown() then return end
    if selectedKey and not ET:GetTracked(selectedKey) then selectedKey = nil end
    rebuildData()
    updateRows()
end

local function makeButton(parent, text, w, name)
    local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    b:SetSize(w or 110, 22)
    b:SetText(text)
    return b
end

local function makeEditBox(parent, w, name)
    local e = CreateFrame("EditBox", name, parent, "InputBoxTemplate")
    e:SetSize(w, 20)
    e:SetAutoFocus(false)
    e:SetMaxLetters(48)
    return e
end

local function create()
    frame = ET.CreateBackdropFrame("Frame", "EnemyTrackerDashboard", UIParent)
    frame:SetSize(W, H)
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
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
    addBox = makeEditBox(frame, 130, "EnemyTrackerDashboardAddBox")
    addBox:SetPoint("LEFT", searchBox, "RIGHT", 30, 0)
    local addBtn = makeButton(frame, L.BTN_ADD, 80)
    addBtn:SetPoint("LEFT", addBox, "RIGHT", 6, 0)
    local function doAdd()
        if ET:AddEnemyManual(addBox:GetText()) then addBox:SetText("") end
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
        local row = CreateFrame("Button", "EnemyTrackerDashboardRow" .. i, listFrame)
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
        row:SetScript("OnEnter", function(self)
            local e = self.key and ET:GetTracked(self.key)
            if not e then return end
            local desc = ET:DescriptionOf(self.key)
            if desc == "" and not e.shared then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(e.name, 1, 0.3, 0.3)
            if desc ~= "" then GameTooltip:AddLine(ET.EscapeText(desc), 1, 1, 1, true) end
            if e.shared then
                GameTooltip:AddLine(string.format(L.SHARED_BY, e.by or "?"), 0.44, 0.66, 0.86)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
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

    -- Join a group by ID right here, no chat command needed
    local groupLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    groupLabel:SetPoint("BOTTOMLEFT", 16, 110)
    groupLabel:SetText(L.GROUP_ID_LABEL)
    joinBox = makeEditBox(frame, 170, "EnemyTrackerDashboardJoinBox")
    joinBox:SetMaxLetters(24)
    joinBox:SetPoint("LEFT", groupLabel, "RIGHT", 10, 0)
    joinBtn = makeButton(frame, L.BTN_JOIN, 90, "EnemyTrackerDashboardJoin")
    joinBtn:SetPoint("LEFT", joinBox, "RIGHT", 6, 0)
    local function doJoin()
        if ET:JoinGroup(joinBox:GetText()) then joinBox:SetText("") end
        joinBox:ClearFocus()
    end
    joinBtn:SetScript("OnClick", doJoin)
    joinBox:SetScript("OnEnterPressed", doJoin)
    joinBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    createBtn = makeButton(frame, L.BTN_CREATE_GROUP, 120, "EnemyTrackerDashboardCreate")
    createBtn:SetPoint("LEFT", joinBtn, "RIGHT", 8, 0)
    createBtn:SetScript("OnClick", function() ET:CreateGroup() end)
    local groupsBtn = makeButton(frame, L.BTN_GROUPS, 100)
    groupsBtn:SetPoint("LEFT", createBtn, "RIGHT", 8, 0)
    groupsBtn:SetScript("OnClick", function() ET:ToggleGroupsPanel() end)
    frame.groupsBtn = groupsBtn

    -- Description of the selected player
    local descLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    descLabel:SetPoint("BOTTOMLEFT", 16, 78)
    descLabel:SetText(L.DESCRIPTION)
    descBox = makeEditBox(frame, 440, "EnemyTrackerDashboardDescription")
    descBox:SetMaxLetters(ET.DESCRIPTION_MAX)
    descBox:SetPoint("LEFT", descLabel, "RIGHT", 10, 0)
    descSave = makeButton(frame, L.BTN_SAVE, 90)
    descSave:SetPoint("LEFT", descBox, "RIGHT", 8, 0)
    -- Descriptions reach the whole group; keep them about play.
    local descHint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    descHint:SetPoint("TOPLEFT", descBox, "BOTTOMLEFT", -4, -4)
    descHint:SetText(L.DESC_HINT)
    frame.descHint = descHint
    local function saveDescription()
        local e = descKey and ET.db.enemies[descKey]
        if e and ET:SetDescription(e.name, descBox:GetText()) then
            descBox:SetText(e.description) -- as stored (trimmed)
        end
        descBox:ClearFocus()
    end
    descSave:SetScript("OnClick", saveDescription)
    descBox:SetScript("OnEnterPressed", saveDescription)
    descBox:SetScript("OnEscapePressed", function(self)
        local e = descKey and ET.db.enemies[descKey]
        self:SetText(e and e.description or "")
        self:ClearFocus()
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
        if e then ET:ConfirmRemove(e.name) return end
        local v = selectedKey and ET.sharedView[selectedKey]
        if v and ET:AddEnemy(v.name) then ET.db.enemies[selectedKey].faction = v.faction end
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
ET:On("SHARED_CHANGED", refresh)
ET:On("GROUPS_CHANGED", refresh)
ET:On("SETTINGS_CHANGED", refresh)
ET:On("POSITIONS_RESET", function()
    ET.db.positions.dashboard = {}
    if frame then ET.RestorePosition(frame, ET.db.positions.dashboard, "CENTER", 0, 0) end
end)
