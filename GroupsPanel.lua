-- Enemy Tracker: "Groups" window - create a group, join one by ID, leave,
-- and copy a group's ID to give to others.
local _, ET = ...
local L = ET.L

local W, H = 460, 250
local SLOT_H = 34

local frame, slots, joinBox

local function makeButton(parent, text, w, name)
    local b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    return b
end

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
            local status = (rt and rt.ready) and ("|cff40ff40" .. L.GROUP_ONLINE .. "|r")
                or ("|cffffd200" .. L.GROUP_CONNECTING .. "|r")
            slot.info:SetText(string.format(L.GROUP_SLOT_INFO, status, recordCount(g))
                .. (g.owner and ("  |cff999999" .. L.GROUP_OWNER .. "|r") or ""))
        else
            slot.idBox:Hide()
            slot.leave:Hide()
            slot.info:SetText("|cff666666" .. L.GROUP_SLOT_EMPTY .. "|r")
        end
    end
    local full = ET:GroupCount() >= ET.MAX_GROUPS
    frame.create:SetEnabled(not full)
    frame.join:SetEnabled(not full)
end

local function create()
    frame = ET.CreateBackdropFrame("Frame", "EnemyTrackerGroups", UIParent)
    frame:SetSize(W, H)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    if frame.SetBackdropColor then frame:SetBackdropColor(0.05, 0.05, 0.05, 0.95) end
    frame:SetPoint("CENTER", 0, 60)
    frame:Hide()
    tinsert(UISpecialFrames, "EnemyTrackerGroups")

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    title:SetText(L.GROUPS_TITLE)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("TOPLEFT", 16, -38)
    hint:SetPoint("TOPRIGHT", -16, -38)
    hint:SetJustifyH("LEFT")
    hint:SetText(L.GROUPS_HINT)

    slots = {}
    for i = 1, ET.MAX_GROUPS do
        local slot = {}
        local y = -66 - (i - 1) * SLOT_H
        -- Read-only box: the ID can be selected and copied with Ctrl+C.
        local box = CreateFrame("EditBox", "EnemyTrackerGroupsSlot" .. i .. "Id", frame, "InputBoxTemplate")
        box:SetSize(150, 20)
        box:SetAutoFocus(false)
        box:SetPoint("TOPLEFT", 22, y)
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

        local info = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        info:SetPoint("TOPLEFT", 182, y - 4)
        info:SetWidth(170)
        info:SetJustifyH("LEFT")
        slot.info = info

        local leave = makeButton(frame, L.BTN_LEAVE, 80, "EnemyTrackerGroupsSlot" .. i .. "Leave")
        leave:SetPoint("TOPRIGHT", -16, y)
        leave:SetScript("OnClick", function() if slot.id then ET:LeaveGroup(slot.id) end end)
        slot.leave = leave
        slots[i] = slot
    end

    local createBtn = makeButton(frame, L.BTN_CREATE_GROUP, 140, "EnemyTrackerGroupsCreate")
    createBtn:SetPoint("BOTTOMLEFT", 16, 18)
    createBtn:SetScript("OnClick", function() ET:CreateGroup() end)
    frame.create = createBtn

    joinBox = CreateFrame("EditBox", "EnemyTrackerGroupsJoinBox", frame, "InputBoxTemplate")
    joinBox:SetSize(150, 20)
    joinBox:SetAutoFocus(false)
    joinBox:SetMaxLetters(24)
    joinBox:SetPoint("LEFT", createBtn, "RIGHT", 30, 0)
    local joinBtn = makeButton(frame, L.BTN_JOIN, 80, "EnemyTrackerGroupsJoin")
    joinBtn:SetPoint("LEFT", joinBox, "RIGHT", 6, 0)
    local function doJoin()
        if ET:JoinGroup(joinBox:GetText()) then joinBox:SetText("") end
        joinBox:ClearFocus()
    end
    joinBtn:SetScript("OnClick", doJoin)
    joinBox:SetScript("OnEnterPressed", doJoin)
    joinBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    frame.join = joinBtn

    frame:SetScript("OnShow", refresh)
end

function ET:ToggleGroupsPanel()
    if not frame then create() end
    frame:SetShown(not frame:IsShown())
end

ET:On("GROUPS_CHANGED", refresh)
ET:On("GROUP_READY", refresh)
ET:On("SHARED_CHANGED", refresh)
