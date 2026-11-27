-- Enemy Tracker: RareScanner-style alerts for detected blacklisted players.
--
-- Targeting: WoW Forever has no addon-callable TargetUnit(), so each alert gets
-- a secure overlay button (SecureActionButtonTemplate, macro "/targetexact
-- Name"). The click itself is the user's hardware action. Secure frames cannot
-- be shown, hidden or reconfigured in combat, so overlays are detached when
-- combat starts and re-attached when it ends; alerts raised in combat show a
-- hint and become clickable after combat.
local _, ET = ...
local L = ET.L

local MAX_TOASTS = 4
local TOAST_W, TOAST_H, GAP = 280, 66, 6
local CLOSE_W = 26
local SOUND_THROTTLE = 2.0
local TEST_KEY = "\001test"

local anchor, mover
local toasts = {}        -- [i] = toast frame (fixed pool, created once)
local overlays = {}      -- [i] = secure button (created lazily out of combat)
local order = {}         -- visible toasts, top to bottom
local queue = {}         -- keys waiting for a free slot
local lastSoundAt = -100

local function settings() return ET.db.settings end

-------------------------------------------------------------------------------
-- Secure overlays
-------------------------------------------------------------------------------
local function getOverlay(i)
    if overlays[i] then return overlays[i] end
    if InCombatLockdown() then return nil end
    local b = CreateFrame("Button", "EnemyTrackerTargetButton" .. i, UIParent, "SecureActionButtonTemplate")
    b:SetFrameStrata("DIALOG")
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type1", "macro")
    b:Hide()
    b:SetScript("OnEnter", function(self)
        local t = toasts[i]
        if not t or not t.name then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(t.name, 1, 0.2, 0.2)
        GameTooltip:AddLine(L.ALERT_CLICK, 1, 1, 1)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:HookScript("PostClick", function(self, button, down)
        if button == "RightButton" and not down then ET:CloseToast(toasts[i]) end
        -- Diagnostics for the in-game targeting check (/et debug).
        ET:Debug("alert click", button, down and "down" or "up", "macro:", tostring(self:GetAttribute("macrotext1")),
            "combat:", tostring(InCombatLockdown()))
    end)
    overlays[i] = b
    return b
end

local function canAttach()
    return not InCombatLockdown() and settings().locked
end

local function attach(t)
    if not canAttach() or not t:IsShown() then return false end
    local b = getOverlay(t.index)
    if not b then return false end
    b:SetAttribute("macrotext1", "/targetexact " .. t.name)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", t, "TOPLEFT", 0, 0)
    b:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -CLOSE_W, 0)
    b:Show()
    t.hint:SetText(L.ALERT_CLICK)
    t.hint:SetTextColor(0.8, 0.8, 0.8)
    return true
end

local function detach(t)
    local b = overlays[t.index]
    if b and not InCombatLockdown() then
        b:Hide()
        b:ClearAllPoints()
    end
end

local function refreshHint(t)
    if overlays[t.index] and overlays[t.index]:IsShown() then return end
    if InCombatLockdown() then
        t.hint:SetText(L.ALERT_COMBAT)
        t.hint:SetTextColor(1, 0.6, 0.2)
    elseif not settings().locked then
        t.hint:SetText(L.UNLOCKED)
        t.hint:SetTextColor(0.6, 1, 0.6)
    else
        t.hint:SetText(L.ALERT_UNTARGETABLE)
        t.hint:SetTextColor(0.7, 0.7, 0.7)
    end
end

-------------------------------------------------------------------------------
-- Toast frames
-------------------------------------------------------------------------------
local function layout()
    for pos, t in ipairs(order) do
        t:ClearAllPoints()
        t:SetPoint("TOP", anchor, "TOP", 0, -((pos - 1) * (TOAST_H + GAP)))
    end
end

local function createToast(i)
    local t = ET.CreateBackdropFrame("Frame", "EnemyTrackerAlert" .. i, anchor)
    t.index = i
    t:SetSize(TOAST_W, TOAST_H)
    t:SetFrameStrata("HIGH")
    if t.SetBackdropColor then
        t:SetBackdropColor(0.08, 0.02, 0.02, 0.92)
        t:SetBackdropBorderColor(0.9, 0.15, 0.15, 1)
    end
    t:EnableMouse(true) -- swallows clicks when no overlay is attached
    t:Hide()

    local icon = t:CreateTexture(nil, "ARTWORK")
    icon:SetSize(44, 44)
    icon:SetPoint("LEFT", 10, 0)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Bone_HumanSkull_01")
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    t.icon = icon

    local title = t:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -1)
    title:SetPoint("RIGHT", t, "RIGHT", -CLOSE_W, 0)
    title:SetJustifyH("LEFT")
    title:SetTextColor(1, 0.25, 0.2)
    title:SetText(L.ALERT_TITLE)

    local name = t:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    name:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    name:SetPoint("RIGHT", t, "RIGHT", -CLOSE_W, 0)
    name:SetJustifyH("LEFT")
    t.nameText = name

    local hint = t:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hint:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
    hint:SetPoint("RIGHT", t, "RIGHT", -CLOSE_W, 0)
    hint:SetJustifyH("LEFT")
    t.hint = hint

    local close = CreateFrame("Button", nil, t, "UIPanelCloseButton")
    close:SetSize(24, 24)
    close:SetPoint("TOPRIGHT", t, "TOPRIGHT", -1, -1)
    close:SetScript("OnClick", function() ET:CloseToast(t) end)

    -- Short pulse when shown / re-detected.
    local ag = t:CreateAnimationGroup()
    local a1 = ag:CreateAnimation("Alpha")
    a1:SetFromAlpha(1); a1:SetToAlpha(0.35); a1:SetDuration(0.25); a1:SetOrder(1)
    local a2 = ag:CreateAnimation("Alpha")
    a2:SetFromAlpha(0.35); a2:SetToAlpha(1); a2:SetDuration(0.25); a2:SetOrder(2)
    ag:SetLoopingType("NONE")
    t.pulse = function()
        ag:Stop()
        ag:Play()
    end

    toasts[i] = t
    return t
end

local function findToast(key)
    for _, t in ipairs(order) do
        if t.key == key then return t end
    end
end

local function freeToast()
    for i = 1, MAX_TOASTS do
        if not toasts[i]:IsShown() then return toasts[i] end
    end
end

local function scheduleAutoHide(t)
    t.generation = (t.generation or 0) + 1
    local gen = t.generation
    local secs = settings().autoHide or 0
    if secs > 0 then
        C_Timer.After(secs, function()
            if t.generation == gen and t:IsShown() then ET:CloseToast(t) end
        end)
    end
end

local function showToast(key, name)
    local t = freeToast()
    if not t then return false end
    t.key, t.name = key, name
    t.nameText:SetText(name)
    t:SetAlpha(1)
    t:Show()
    order[#order + 1] = t
    layout()
    if not attach(t) then refreshHint(t) end
    t.pulse()
    scheduleAutoHide(t)
    return true
end

local function queued(key)
    for _, k in ipairs(queue) do if k == key then return true end end
end

function ET:CloseToast(t)
    if not t or not t:IsShown() then return end
    detach(t)
    t:Hide()
    t.key, t.name = nil, nil
    t.generation = (t.generation or 0) + 1
    for i, o in ipairs(order) do
        if o == t then table.remove(order, i) break end
    end
    layout()
    -- Show the next queued alert, skipping players removed meanwhile.
    while #queue > 0 do
        local key = table.remove(queue, 1)
        local e = key == TEST_KEY and { name = L.TEST_NAME } or self:GetTracked(key)
        if e and not findToast(key) then
            showToast(key, e.name)
            break
        end
    end
end

-------------------------------------------------------------------------------
-- Public
-------------------------------------------------------------------------------
function ET:Notify(key, name)
    local s = settings()
    self:Print("|cffff4040" .. L.ALERT_TITLE .. "|r " .. name)
    local now = GetTime()
    if s.sound and now - lastSoundAt >= SOUND_THROTTLE then
        lastSoundAt = now
        self:PlayAlertSound()
    end
    if not s.visual then return end
    local existing = findToast(key)
    if existing then
        existing.pulse()
        scheduleAutoHide(existing)
        return
    end
    if not showToast(key, name) and not queued(key) then
        queue[#queue + 1] = key
    end
end

function ET:TestAlert()
    self:Notify(TEST_KEY, L.TEST_NAME)
end

function ET:HideAllAlerts()
    wipe(queue)
    for i = #order, 1, -1 do self:CloseToast(order[i]) end
end

function ET:ApplyAlertScale()
    if not anchor then return end
    anchor:SetScale(settings().scale or 1)
    ET.RestorePosition(anchor, ET.db.positions.alerts, "TOP", 0, -140)
end

-- Unlock mode: show drag handles; overlays are detached so they don't eat drags.
function ET:SetLocked(locked)
    if InCombatLockdown() then
        self:Print(L.COMBAT_BLOCKED)
        return false
    end
    settings().locked = locked and true or false
    if mover then mover:SetShown(not locked) end
    for _, t in ipairs(order) do
        if locked then
            if not attach(t) then refreshHint(t) end
        else
            detach(t)
            refreshHint(t)
        end
    end
    self:Fire("LOCK_CHANGED", locked)
    self:Print(locked and L.LOCKED or L.UNLOCKED)
    return true
end

function ET:ResetPositions()
    wipe(ET.db.positions)
    self:ApplyAlertScale()
    self:Fire("POSITIONS_RESET")
    self:Print(L.POS_RESET)
end

-------------------------------------------------------------------------------
-- Setup
-------------------------------------------------------------------------------
local function createAnchor()
    anchor = CreateFrame("Frame", "EnemyTrackerAlertAnchor", UIParent)
    anchor:SetSize(TOAST_W, TOAST_H)
    anchor:SetMovable(true)
    anchor:SetClampedToScreen(true)
    anchor:SetFrameStrata("HIGH")

    mover = ET.CreateBackdropFrame("Frame", nil, anchor)
    mover:SetAllPoints(anchor)
    mover:SetFrameLevel(anchor:GetFrameLevel() + 20)
    if mover.SetBackdropColor then
        mover:SetBackdropColor(0.1, 0.6, 0.1, 0.5)
        mover:SetBackdropBorderColor(0.2, 1, 0.2, 1)
    end
    local label = mover:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("CENTER")
    label:SetText(L.MOVER_ALERTS)
    mover:EnableMouse(true)
    mover:RegisterForDrag("LeftButton")
    mover:SetScript("OnDragStart", function() anchor:StartMoving() end)
    mover:SetScript("OnDragStop", function()
        anchor:StopMovingOrSizing()
        ET.SavePosition(anchor, ET.db.positions.alerts)
        ET.RestorePosition(anchor, ET.db.positions.alerts, "TOP", 0, -140)
    end)
    mover:Hide()

    for i = 1, MAX_TOASTS do createToast(i) end
end

ET:On("DB_READY", function()
    ET.db.positions.alerts = ET.db.positions.alerts or {}
end)

ET:On("LOGIN", function()
    createAnchor()
    ET:ApplyAlertScale()
    if not settings().locked then mover:Show() end
    -- Pre-create secure overlays while out of combat (login / reload).
    if not InCombatLockdown() then
        for i = 1, MAX_TOASTS do getOverlay(i) end
    end
end)

ET:On("POSITIONS_RESET", function()
    ET.db.positions.alerts = {}
    ET:ApplyAlertScale()
end)

ET:On("ENEMY_DETECTED", function(key, entry)
    -- Players of your own faction stay on the list and are still tracked
    -- (last seen, detections), but raise no alert or sound.
    if ET:IsAlly(key) then
        ET:Debug("ally detected, no alert:", entry.name)
        return
    end
    local d = ET.nearby[key]
    ET:Notify(key, d and d.name or entry.name)
end)

ET:On("BLACKLIST_CHANGED", function(key, action, oldKey)
    if action == "remove" or action == "reject" then
        local t = findToast(key)
        if t then ET:CloseToast(t) end
    elseif action == "rename" then
        local t = findToast(oldKey)
        if t then
            t.key, t.name = key, ET.db.enemies[key].name
            t.nameText:SetText(t.name)
            if not attach(t) then refreshHint(t) end
        end
    end
end)

ET:On("SETTINGS_CHANGED", function(what)
    if what == "scale" then ET:ApplyAlertScale()
    elseif what == "visual" and not settings().visual then ET:HideAllAlerts() end
end)

-- PLAYER_REGEN_DISABLED fires just before combat lockdown, so secure frames
-- can still be hidden here.
ET:RegisterEvent("PLAYER_REGEN_DISABLED", function()
    for _, t in ipairs(order) do
        detach(t)
    end
    C_Timer.After(0, function()
        for _, t in ipairs(order) do refreshHint(t) end
    end)
end)

ET:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    for i = 1, MAX_TOASTS do getOverlay(i) end
    for _, t in ipairs(order) do
        if not attach(t) then refreshHint(t) end
    end
end)
