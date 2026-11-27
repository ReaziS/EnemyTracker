-- Enemy Tracker: settings panel in the standard Interface > AddOns options.
-- Every control applies immediately (no /reload) and is saved in SavedVariables.
local _, ET = ...
local L = ET.L

local panel, category
local refreshers = {}

local function S() return ET.db.settings end

local function set(key, value)
    S()[key] = value
    ET:Fire("SETTINGS_CHANGED", key)
end

local function addRefresher(fn) refreshers[#refreshers + 1] = fn end

local function refreshAll()
    for _, fn in ipairs(refreshers) do pcall(fn) end
end

local function checkbox(parent, x, y, label, key, onChange)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetSize(26, 26)
    cb:SetPoint("TOPLEFT", x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    fs:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    fs:SetText(label)
    cb.label = fs
    cb:SetScript("OnClick", function(self)
        local v = self:GetChecked() and true or false
        if onChange then onChange(v) else set(key, v) end
    end)
    addRefresher(function() cb:SetChecked(S()[key]) end)
    return cb
end

local sliderCount = 0
local function slider(parent, x, y, label, key, minV, maxV, step, fmt)
    sliderCount = sliderCount + 1
    local name = "EnemyTrackerOptionSlider" .. sliderCount
    local ok, s = pcall(CreateFrame, "Slider", name, parent, "OptionsSliderTemplate")
    if not ok then
        s = CreateFrame("Slider", name, parent)
        s:SetOrientation("HORIZONTAL")
        s:SetHeight(16)
        s:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
        local bg = s:CreateTexture(nil, "BACKGROUND")
        bg:SetPoint("LEFT"); bg:SetPoint("RIGHT"); bg:SetHeight(6)
        bg:SetColorTexture(1, 1, 1, 0.2)
    end
    for _, suffix in ipairs({ "Low", "High", "Text" }) do
        local r = _G[name .. suffix]
        if r then r:SetText("") end
    end
    s:SetWidth(220)
    s:SetPoint("TOPLEFT", x, y - 18)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("BOTTOMLEFT", s, "TOPLEFT", 0, 4)
    title:SetText(label)
    local valueText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    valueText:SetPoint("LEFT", s, "RIGHT", 10, 0)
    local updating = false
    s:SetScript("OnValueChanged", function(_, v)
        v = math.floor(v / step + 0.5) * step
        valueText:SetText(string.format(fmt, v))
        if not updating and S()[key] ~= v then set(key, v) end
    end)
    addRefresher(function()
        updating = true
        s:SetValue(S()[key])
        valueText:SetText(string.format(fmt, S()[key]))
        updating = false
    end)
    return s
end

local function button(parent, text, w)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w or 140, 22)
    b:SetText(text)
    return b
end

-- "< value >" selector, avoids dropdown APIs that differ between clients.
local function cycler(parent, x, y, label, getItems, key, labelOf)
    local title = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", x, y)
    title:SetText(label)
    local prev = button(parent, "<", 26)
    prev:SetPoint("TOPLEFT", x + 130, y + 4)
    local valueText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    valueText:SetPoint("LEFT", prev, "RIGHT", 8, 0)
    valueText:SetWidth(150)
    local nextB = button(parent, ">", 26)
    nextB:SetPoint("LEFT", valueText, "RIGHT", 8, 0)
    local function step(dir)
        local items = getItems()
        local idx = 1
        for i, v in ipairs(items) do if v == S()[key] then idx = i end end
        idx = (idx - 1 + dir) % #items + 1
        set(key, items[idx])
        valueText:SetText(labelOf(items[idx]))
    end
    prev:SetScript("OnClick", function() step(-1) end)
    nextB:SetScript("OnClick", function() step(1) end)
    addRefresher(function() valueText:SetText(labelOf(S()[key])) end)
end

local function build()
    panel = CreateFrame("Frame", "EnemyTrackerOptionsPanel")
    panel.name = "Enemy Tracker"

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Enemy Tracker " .. ET.version)

    local y = -48
    checkbox(panel, 16, y, L.OPT_SCAN, "scanEnabled", function(v) ET:SetScanning(v) end); y = y - 28
    checkbox(panel, 16, y, L.OPT_VISUAL, "visual"); y = y - 28
    checkbox(panel, 16, y, L.OPT_SOUND, "sound"); y = y - 40

    slider(panel, 20, y, L.OPT_SCALE, "scale", 0.5, 2.0, 0.05, "%.2f"); y = y - 56
    slider(panel, 20, y, L.OPT_AUTOHIDE, "autoHide", 0, 120, 5, "%d"); y = y - 56

    cycler(panel, 20, y, L.OPT_SOUND_CHOICE, function()
        local keys = {}
        for _, s in ipairs(ET:GetSounds()) do keys[#keys + 1] = s.key end
        return keys
    end, "soundKey", function(k) local s = ET:GetSound(k); return s and s.label or tostring(k) end)
    y = y - 32
    cycler(panel, 20, y, L.OPT_CHANNEL, function() return ET.CHANNELS end, "soundChannel",
        function(c) return L["CHANNEL_" .. tostring(c)] or tostring(c) end)
    y = y - 30

    local volumeNote = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    volumeNote:SetPoint("TOPLEFT", 20, y)
    volumeNote:SetWidth(560)
    volumeNote:SetJustifyH("LEFT")
    addRefresher(function() volumeNote:SetText(string.format(L.OPT_VOLUME_NOTE, ET:GetChannelVolume())) end)
    y = y - 34

    local testSound = button(panel, L.OPT_TEST_SOUND, 150)
    testSound:SetPoint("TOPLEFT", 20, y)
    testSound:SetScript("OnClick", function() ET:PlayAlertSound(true) end)
    local testAlert = button(panel, L.OPT_TEST_ALERT, 150)
    testAlert:SetPoint("LEFT", testSound, "RIGHT", 10, 0)
    testAlert:SetScript("OnClick", function() ET:TestAlert() end)
    y = y - 36

    checkbox(panel, 16, y, L.OPT_COUNTER, "showCounter"); y = y - 28
    checkbox(panel, 16, y, L.OPT_MINIMAP, "showMinimap"); y = y - 28
    local clCheck = checkbox(panel, 16, y, L.OPT_COMBATLOG, "useCombatLog"); y = y - 28
    addRefresher(function()
        local off = ET.combatLogAvailable == false
        clCheck:SetEnabled(not off)
        clCheck.label:SetText(L.OPT_COMBATLOG .. (off and (" " .. L.OPT_COMBATLOG_UNAVAILABLE) or ""))
    end)
    checkbox(panel, 16, y, L.OPT_GROUP, "useGroupTargets"); y = y - 28
    checkbox(panel, 16, y, L.OPT_LOCK, "locked", function(v)
        if not ET:SetLocked(v) then refreshAll() end
    end)
    local resetPos = button(panel, L.OPT_RESETPOS, 150)
    resetPos:SetPoint("TOPLEFT", 400, y)
    resetPos:SetScript("OnClick", function() ET:ResetPositions() end)
    y = y - 28
    checkbox(panel, 16, y, L.OPT_DEBUG, "debug"); y = y - 36

    local note = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", 20, y)
    note:SetWidth(560)
    note:SetJustifyH("LEFT")
    note:SetText(L.OPT_DETECTION_NOTE)

    panel:SetScript("OnShow", refreshAll)

    if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
        category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

function ET:OpenOptions()
    if category and Settings and Settings.OpenToCategory then
        local id = category.GetID and category:GetID() or category.ID
        Settings.OpenToCategory(id)
    elseif InterfaceOptionsFrame_OpenToCategory then
        InterfaceOptionsFrame_OpenToCategory(panel)
        InterfaceOptionsFrame_OpenToCategory(panel) -- first call may only open the frame
    end
end

ET:On("DB_READY", build)
ET:On("SETTINGS_CHANGED", function() if panel and panel:IsShown() then refreshAll() end end)
ET:On("LOCK_CHANGED", function() if panel and panel:IsShown() then refreshAll() end end)
