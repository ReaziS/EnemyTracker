-- Enemy Tracker: "Groups" window - create a group, join one by ID, leave,
-- and copy a group's ID to give to others.
local _, ET = ...
local L = ET.L
local UI = ET.UI

local W, H = 480, 352
local PAD = 16
local CARD_H, CARD_GAP = 56, 8

local frame, slots, joinBox

local function recordCount(g)
    local n = 0
    for _, r in pairs(g.records) do
        if not r.del then n = n + 1 end
    end
    return n
end

local function sortedIds()
    local ids = {}
    for id in pairs(ET.db.groups) do ids[#ids + 1] = id end
    table.sort(ids, function(a, b)
        local ga, gb = ET.db.groups[a], ET.db.groups[b]
        if (ga.joinedAt or 0) ~= (gb.joinedAt or 0) then return (ga.joinedAt or 0) < (gb.joinedAt or 0) end
        return a < b
    end)
    return ids
end

local function statusOf(g, rt)
    if g.verified == false then return UI.Color("warn", L.GROUP_CHECKING_SHORT) end
    if rt and rt.ready then return UI.Color("ok", L.GROUP_ONLINE) end
    return UI.Color("warn", L.GROUP_CONNECTING)
end

local function refresh()
    if not frame or not frame:IsShown() then return end
    local ids = sortedIds()
    for i, slot in ipairs(slots) do
        local id = ids[i]
        slot.id = id
        if id then
            local g, rt = ET.db.groups[id], ET.groupRuntime[id]
            slot.idBox:SetText(ET.FormatGroupId(id))
            slot.idBox:Show()
            slot.leave:Show()
            slot.dot:Show()
            slot.empty:Hide()
            slot.info:SetText(string.format(L.GROUP_SLOT_INFO, statusOf(g, rt), recordCount(g))
                .. (g.owner and ("  " .. UI.Color("muted", L.GROUP_OWNER)) or ""))
            local c = UI.C[(rt and rt.ready and g.verified ~= false) and "ok" or "warn"]
            slot.dot:SetColorTexture(c[1], c[2], c[3], 1)
        else
            slot.idBox:Hide()
            slot.leave:Hide()
            slot.dot:Hide()
            slot.info:SetText("")
            slot.empty:Show()
        end
    end
    local full = ET:GroupCount() >= ET.MAX_GROUPS
    frame.create:SetEnabled(not full)
    frame.join:SetEnabled(not full)
end

local function createSlot(i, y)
    local slot = {}
    local card = UI.Frame("Frame", nil, frame)
    card:SetPoint("TOPLEFT", PAD, y)
    card:SetPoint("TOPRIGHT", -PAD, y)
    card:SetHeight(CARD_H)
    UI.Paint(card, UI.C.surface, UI.C.border)

    -- Read-only box: the ID can be selected and copied with Ctrl+C.
    local box = UI.EditBox(card, 190, "EnemyTrackerGroupsSlot" .. i .. "Id")
    box:SetPoint("TOPLEFT", 10, -8)
    box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    box:SetScript("OnTextChanged", function(self, userInput)
        if userInput and slot.id then
            self:SetText(ET.FormatGroupId(slot.id))
            self:HighlightText()
        end
    end)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    slot.idBox = box

    local dot = card:CreateTexture(nil, "ARTWORK")
    dot:SetSize(6, 6)
    dot:SetPoint("TOPLEFT", 12, -40)
    slot.dot = dot
    local info = UI.Text(card, "GameFontNormalSmall", "muted")
    info:SetPoint("LEFT", dot, "RIGHT", 6, 0)
    slot.info = info

    local empty = UI.Text(card, "GameFontNormalSmall", "muted")
    empty:SetPoint("CENTER")
    empty:SetText(L.GROUP_SLOT_EMPTY)
    slot.empty = empty

    local leave = UI.Button(card, L.BTN_LEAVE, 90, "EnemyTrackerGroupsSlot" .. i .. "Leave", "danger")
    leave:SetPoint("RIGHT", -10, 0)
    leave:SetScript("OnClick", function() if slot.id then ET:LeaveGroup(slot.id) end end)
    slot.leave = leave
    return slot
end

local function create()
    frame = UI.Window("EnemyTrackerGroups", W, H, L.GROUPS_TITLE)
    frame:SetPoint("CENTER", 0, 60)

    local hint = UI.Text(frame, "GameFontNormalSmall", "muted")
    hint:SetPoint("TOPLEFT", PAD, -UI.HEADER_H - 12)
    hint:SetPoint("TOPRIGHT", -PAD, -UI.HEADER_H - 12)
    hint:SetWordWrap(true)
    hint:SetText(L.GROUPS_HINT)

    slots = {}
    local y = -UI.HEADER_H - 52
    for i = 1, ET.MAX_GROUPS do
        slots[i] = createSlot(i, y)
        y = y - CARD_H - CARD_GAP
    end
    UI.Divider(frame, y - 4, PAD, PAD)

    y = y - 18
    joinBox = UI.EditBox(frame, 190, "EnemyTrackerGroupsJoinBox", "ET-XXXX-XXXX-XXXX")
    joinBox:SetMaxLetters(24)
    joinBox:SetPoint("TOPLEFT", PAD, y)
    local joinBtn = UI.Button(frame, L.BTN_JOIN, 100, "EnemyTrackerGroupsJoin")
    joinBtn:SetPoint("LEFT", joinBox, "RIGHT", 6, 0)
    local function doJoin()
        if ET:JoinGroup(joinBox:GetText()) then joinBox:SetText("") end
        joinBox:ClearFocus()
    end
    joinBtn:SetScript("OnClick", doJoin)
    joinBox:SetScript("OnEnterPressed", doJoin)
    joinBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    frame.join = joinBtn

    local createBtn = UI.Button(frame, L.BTN_CREATE_GROUP, 140, "EnemyTrackerGroupsCreate", "primary")
    createBtn:SetPoint("TOPRIGHT", -PAD, y)
    createBtn:SetScript("OnClick", function() ET:CreateGroup() end)
    frame.create = createBtn

    frame:SetScript("OnShow", function(self)
        self:Raise() -- opened from the dashboard: show it above it
        refresh()
    end)
end

function ET:ToggleGroupsPanel()
    if not frame then create() end
    frame:SetShown(not frame:IsShown())
end

ET:On("GROUPS_CHANGED", refresh)
ET:On("GROUP_READY", refresh)
ET:On("SHARED_CHANGED", refresh)
