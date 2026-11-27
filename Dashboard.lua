-- Enemy Tracker: dashboard window (blacklist, statistics, search, management).
-- Uses a virtual list (fixed set of row frames + scroll offset), so it stays
-- fast with hundreds of entries.
local _, ET = ...
local L = ET.L
local UI = ET.UI

local W, H = 720, 660
local ROW_H, VISIBLE_ROWS = 22, 15
local PAD = 16

local frame, rows, slider, searchBox, addBox, totalText, scanCheck
local clearBtn, removeBtn, descBox, descSave, joinBox, joinBtn, createBtn
local headers = {}
local descKey           -- record whose description is in descBox
local data = {}         -- filtered + sorted entries { key, entry }
local offset = 0
local selectedKey
local sortKey, sortDesc = "lastSeen", true

local COLUMNS = {
    { id = "name",       label = "COL_NAME",       x = 12,  w = 200, justify = "LEFT" },
    { id = "killedMe",   label = "COL_KILLED_ME",  x = 216, w = 84,  justify = "CENTER" },
    { id = "iKilled",    label = "COL_I_KILLED",   x = 302, w = 84,  justify = "CENTER" },
    { id = "lastSeen",   label = "COL_LAST_SEEN",  x = 388, w = 120, justify = "CENTER" },
    { id = "addedAt",    label = "COL_ADDED",      x = 510, w = 110, justify = "CENTER" },
    { id = "detections", label = "COL_DETECTIONS", x = 622, w = 50,  justify = "CENTER" },
}

local STAT_COLUMN = { killedMe = true, iKilled = true, detections = true }

local function valueOf(e, id)
    if STAT_COLUMN[id] then return e.stats[id] end
    return e[id]
end

-- Zero counters are muted so the numbers that matter stand out.
local function count(n)
    return n == 0 and UI.Color("muted", "0") or tostring(n)
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

local function updateHeaders()
    for id, fs in pairs(headers) do
        local c = UI.C[id == sortKey and "text" or "muted"]
        fs:SetTextColor(c[1], c[2], c[3])
    end
end

local function updateRows()
    if not frame or not frame:IsShown() then return end
    local maxOffset = math.max(0, #data - VISIBLE_ROWS)
    if offset > maxOffset then offset = maxOffset end
    slider:SetMinMaxValues(0, maxOffset)
    slider:SetValue(offset)
    slider:SetShown(maxOffset > 0)
    local mine = ET.UnitFaction("player")
    for i = 1, VISIBLE_ROWS do
        local row = rows[i]
        local item = data[offset + i]
        if item then
            local e = item.e
            row.key = item.key
            local label = e.name
            if e.needsSurname then label = label .. "  " .. UI.Color("muted", L.NO_SURNAME)
            elseif item.shared then label = UI.Color("shared", label) end
            row.cols.name:SetText(label)
            row.cols.killedMe:SetText(count(e.stats.killedMe))
            row.cols.iKilled:SetText(count(e.stats.iKilled))
            -- Own faction: never alerted, so "last seen" means little; show a dash.
            local seen = (mine and e.faction == mine) and UI.Color("muted", "-")
                or ET.nearby[item.key] and UI.Color("ok", L.JUST_NOW)
                or (e.lastSeen or 0) == 0 and UI.Color("muted", L.NEVER)
                or ET.FormatAgo(e.lastSeen)
            row.cols.lastSeen:SetText(seen)
            row.cols.addedAt:SetText(item.shared and UI.Color("shared", L.FROM_GROUP)
                or UI.Color("muted", ET.FormatDate(e.addedAt)))
            row.cols.detections:SetText(count(e.stats.detections))
            local selected = item.key == selectedKey
            row.sel:SetShown(selected)
            row.selBar:SetShown(selected)
            row:Show()
        else
            row.key = nil
            row:Hide()
        end
    end
    updateHeaders()
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

local function createRow(listFrame, i)
    local row = CreateFrame("Button", "EnemyTrackerDashboardRow" .. i, listFrame)
    row:SetSize(W - PAD * 2 - 10, ROW_H)
    row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
    if i % 2 == 0 then
        local bg = row:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 0.025)
    end
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.05)
    local sel = row:CreateTexture(nil, "BORDER")
    sel:SetAllPoints()
    sel:SetColorTexture(UI.C.accent[1], UI.C.accent[2], UI.C.accent[3], 0.13)
    sel:Hide()
    row.sel = sel
    local bar = row:CreateTexture(nil, "ARTWORK")
    bar:SetColorTexture(UI.C.accent[1], UI.C.accent[2], UI.C.accent[3], 1)
    bar:SetWidth(2)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("BOTTOMLEFT")
    bar:Hide()
    row.selBar = bar
    row.cols = {}
    for _, c in ipairs(COLUMNS) do
        local fs = UI.Text(row, "GameFontHighlightSmall", "text")
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
        local mine = ET.UnitFaction("player")
        local own = mine ~= nil and e.faction == mine
        if desc == "" and not e.shared and not own then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(e.name, 1, 0.3, 0.3)
        if own then GameTooltip:AddLine(L.OWN_FACTION, 0.6, 0.6, 0.6, true) end
        if desc ~= "" then GameTooltip:AddLine(ET.EscapeText(desc), 1, 1, 1, true) end
        if e.shared then
            GameTooltip:AddLine(string.format(L.SHARED_BY, e.owner or e.by or "?"), UI.C.shared[1], UI.C.shared[2], UI.C.shared[3])
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return row
end

local function create()
    frame = UI.Window("EnemyTrackerDashboard", W, H, "Enemy Tracker", L.DASH_TITLE)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        ET.SavePosition(self, ET.db.positions.dashboard)
    end)

    local groupsBtn = UI.Button(frame, L.BTN_GROUPS, 90, nil, "ghost")
    groupsBtn:SetPoint("RIGHT", frame.close, "LEFT", -8, 0)
    groupsBtn:SetScript("OnClick", function() ET:ToggleGroupsPanel() end)
    frame.groupsBtn = groupsBtn

    -- Toolbar: search on the left, add on the right.
    local y = -UI.HEADER_H - 14
    searchBox = UI.EditBox(frame, 220, nil, L.SEARCH)
    searchBox:SetPoint("TOPLEFT", PAD, y)
    searchBox:SetScript("OnTextChanged", function() offset = 0; refresh() end)
    searchBox:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)

    local addTarget = UI.Button(frame, L.BTN_ADD_TARGET, 120)
    addTarget:SetPoint("TOPRIGHT", -PAD, y)
    addTarget:SetScript("OnClick", function() ET:AddTarget() end)
    local addBtn = UI.Button(frame, L.BTN_ADD, 90, nil, "primary")
    addBtn:SetPoint("RIGHT", addTarget, "LEFT", -6, 0)
    addBox = UI.EditBox(frame, 170, "EnemyTrackerDashboardAddBox", L.PH_NAME)
    addBox:SetPoint("RIGHT", addBtn, "LEFT", -6, 0)
    local function doAdd()
        if ET:AddEnemyManual(addBox:GetText()) then addBox:SetText("") end
        addBox:ClearFocus()
    end
    addBtn:SetScript("OnClick", doAdd)
    addBox:SetScript("OnEnterPressed", doAdd)
    addBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    -- Column headers (click to sort)
    y = y - 38
    for _, c in ipairs(COLUMNS) do
        local h = CreateFrame("Button", nil, frame)
        h:SetSize(c.w, 16)
        h:SetPoint("TOPLEFT", PAD + c.x, y)
        local fs = UI.Text(h, "GameFontNormalSmall", "muted")
        fs:SetAllPoints()
        fs:SetJustifyH(c.justify)
        fs:SetText(L[c.label])
        headers[c.id] = fs
        h:SetScript("OnClick", function()
            if sortKey == c.id then sortDesc = not sortDesc
            else sortKey, sortDesc = c.id, c.id ~= "name" end
            refresh()
        end)
    end
    y = y - 20
    UI.Divider(frame, y, PAD, PAD)

    -- Rows
    local listFrame = CreateFrame("Frame", nil, frame)
    listFrame:SetPoint("TOPLEFT", PAD, y - 2)
    listFrame:SetSize(W - PAD * 2 - 10, ROW_H * VISIBLE_ROWS)
    listFrame:EnableMouseWheel(true)
    listFrame:SetScript("OnMouseWheel", function(_, delta)
        offset = math.max(0, math.min(offset - delta * 3, math.max(0, #data - VISIBLE_ROWS)))
        updateRows()
    end)
    rows = {}
    for i = 1, VISIBLE_ROWS do rows[i] = createRow(listFrame, i) end

    slider = UI.Scrollbar(frame)
    slider:SetPoint("TOPRIGHT", -PAD, y - 2)
    slider:SetHeight(ROW_H * VISIBLE_ROWS)
    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value + 0.5)
        if value ~= offset then offset = value; updateRows() end
    end)
    y = y - 4 - ROW_H * VISIBLE_ROWS
    UI.Divider(frame, y, PAD, PAD)

    -- Description of the selected player
    y = y - 12
    local descLabel = UI.Section(frame, L.DESCRIPTION)
    descLabel:SetPoint("TOPLEFT", PAD, y)
    y = y - 16
    descSave = UI.Button(frame, L.BTN_SAVE, 100)
    descSave:SetPoint("TOPRIGHT", -PAD, y)
    descBox = UI.EditBox(frame, W - PAD * 2 - 108, "EnemyTrackerDashboardDescription", L.PH_DESCRIPTION)
    descBox:SetMaxLetters(ET.DESCRIPTION_MAX)
    descBox:SetPoint("TOPLEFT", PAD, y)
    -- Descriptions reach the whole group; keep them about play.
    local descHint = UI.Text(frame, "GameFontNormalSmall", "muted")
    descHint:SetPoint("TOPLEFT", descBox, "BOTTOMLEFT", 0, -5)
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

    -- Join or create a group right here, no chat command needed
    y = y - 50
    local groupLabel = UI.Section(frame, L.GROUP_ID_LABEL)
    groupLabel:SetPoint("TOPLEFT", PAD, y)
    y = y - 16
    joinBox = UI.EditBox(frame, 200, "EnemyTrackerDashboardJoinBox", "ET-XXXX-XXXX-XXXX")
    joinBox:SetMaxLetters(24)
    joinBox:SetPoint("TOPLEFT", PAD, y)
    joinBtn = UI.Button(frame, L.BTN_JOIN, 100, "EnemyTrackerDashboardJoin")
    joinBtn:SetPoint("LEFT", joinBox, "RIGHT", 6, 0)
    local function doJoin()
        if ET:JoinGroup(joinBox:GetText()) then joinBox:SetText("") end
        joinBox:ClearFocus()
    end
    joinBtn:SetScript("OnClick", doJoin)
    joinBox:SetScript("OnEnterPressed", doJoin)
    joinBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    createBtn = UI.Button(frame, L.BTN_CREATE_GROUP, 140, "EnemyTrackerDashboardCreate", "ghost")
    createBtn:SetPoint("LEFT", joinBtn, "RIGHT", 6, 0)
    createBtn:SetScript("OnClick", function() ET:CreateGroup() end)
    y = y - 36
    UI.Divider(frame, y, PAD, PAD)

    -- Footer: actions on the selection, scanning, totals
    y = y - 12
    removeBtn = UI.Button(frame, L.BTN_REMOVE, 130, nil, "danger")
    removeBtn:SetPoint("TOPLEFT", PAD, y)
    removeBtn:SetScript("OnClick", function()
        local e = selectedKey and ET.db.enemies[selectedKey]
        if e then ET:ConfirmRemove(e.name) return end
        local v = selectedKey and ET.sharedView[selectedKey]
        if v and ET:AddEnemy(v.name) then ET.db.enemies[selectedKey].faction = v.faction end
    end)
    clearBtn = UI.Button(frame, L.BTN_CLEAR, 130)
    clearBtn:SetPoint("LEFT", removeBtn, "RIGHT", 6, 0)
    clearBtn:SetScript("OnClick", function()
        local e = selectedKey and ET.db.enemies[selectedKey]
        if e then ET:ConfirmClear(e.name) end
    end)

    scanCheck = UI.Check(frame, L.SCANNING)
    scanCheck:SetPoint("LEFT", clearBtn, "RIGHT", 18, 0)
    scanCheck:SetScript("OnClick", function(self) ET:SetScanning(self:GetChecked()) end)

    totalText = UI.Text(frame, "GameFontNormalSmall", "muted")
    totalText:SetPoint("TOPRIGHT", -PAD, y - 6)
    totalText:SetJustifyH("RIGHT")

    local note = UI.Text(frame, "GameFontNormalSmall", "muted")
    note:SetPoint("BOTTOMLEFT", PAD, 12)
    note:SetPoint("BOTTOMRIGHT", -PAD, 12)
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
