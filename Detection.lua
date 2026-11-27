-- Enemy Tracker: detection of blacklisted players through client-provided units.
-- Sources: nameplates, target, mouseover, focus, target-of-target, group
-- members' targets and nearby combat log events. No hidden data, no world scan.
local _, ET = ...

local LOST_AFTER = 10      -- seconds without any source before "no longer detected"
local TICK = 1.0           -- periodic re-check interval (no OnUpdate scanning)
local MAX_PLATES = 40

local nearby = {}          -- key -> { key, name, firstSeen, lastSeen, source }
ET.nearby = nearby

local GetTime = GetTime

-- Pre-built unit token lists so the ticker allocates nothing.
local plateUnits, partyTargets, raidTargets = {}, {}, {}
for i = 1, MAX_PLATES do plateUnits[i] = "nameplate" .. i end
for i = 1, 4 do partyTargets[i] = "party" .. i .. "target" end
for i = 1, 40 do raidTargets[i] = "raid" .. i .. "target" end

local function scanning()
    return ET.db and ET.db.settings.scanEnabled
end

-- Records that a blacklisted player (by key) is visible right now.
function ET:MarkSeen(key, seenName, source)
    local entry = self.db.enemies[key]
    if not entry then return end
    local now = GetTime()
    local d = nearby[key]
    local isNew = false
    if not d then
        d = { key = key, firstSeen = now }
        nearby[key] = d
        isNew = true
    end
    d.lastSeen = now
    d.source = source
    -- Prefer the client's own spelling/case of the name.
    if seenName and seenName ~= entry.name and ET.NameKey(seenName) == key then
        entry.name = ET.DisplayName(seenName)
    end
    d.name = entry.name
    entry.lastSeen = time()
    if isNew then
        entry.detections = (entry.detections or 0) + 1
        self:Debug("detected", entry.name, "via", source)
        self:Fire("ENEMY_DETECTED", key, entry, source)
        self:Fire("NEARBY_CHANGED")
    end
end

-- Checks a unit token; cheap when it is not a blacklisted player.
function ET:ObserveUnit(unit, source)
    if not scanning() then return end
    local name = ET.PlayerName(unit)
    if not name then return end
    local key = ET.NameKey(name)
    if key and self.db.enemies[key] then
        self:MarkSeen(key, name, source)
    end
end

-- Called from the combat log handler for player-type sources/destinations.
function ET:ObserveName(name, source)
    if not scanning() or not name then return end
    local key = ET.NameKey(name)
    if key and self.db.enemies[key] then
        self:MarkSeen(key, name, source)
    end
end

function ET:ScanAll()
    if not scanning() then return end
    -- Nameplates
    if C_NamePlate and C_NamePlate.GetNamePlates then
        local plates = C_NamePlate.GetNamePlates()
        for i = 1, #plates do
            local unit = plates[i].namePlateUnitToken
            if unit then self:ObserveUnit(unit, "nameplate") end
        end
    else
        for i = 1, MAX_PLATES do self:ObserveUnit(plateUnits[i], "nameplate") end
    end
    self:ObserveUnit("target", "target")
    self:ObserveUnit("mouseover", "mouseover")
    self:ObserveUnit("focus", "focus")
    self:ObserveUnit("targettarget", "target")
    -- Group members' targets, only if the client can actually see that unit.
    if self.db.settings.useGroupTargets then
        local list, n
        if IsInRaid and IsInRaid() then list, n = raidTargets, GetNumGroupMembers()
        elseif GetNumGroupMembers and GetNumGroupMembers() > 0 then list, n = partyTargets, 4 end
        if list then
            for i = 1, math.min(n, #list) do
                local u = list[i]
                local visible = UnitIsVisible(u)
                if not ET.IsSecret(visible) and visible then self:ObserveUnit(u, "group") end
            end
        end
    end
end

-- Drops players not seen by any source for LOST_AFTER seconds.
function ET:ExpireNearby()
    local now = GetTime()
    local changed = false
    for key, d in pairs(nearby) do
        if now - d.lastSeen > LOST_AFTER or not self.db.enemies[key] then
            nearby[key] = nil
            changed = true
            self:Debug("lost", d.name)
            self:Fire("ENEMY_LOST", key)
        end
    end
    if changed then self:Fire("NEARBY_CHANGED") end
end

function ET:ClearNearby()
    local had = next(nearby) ~= nil
    for key in pairs(nearby) do
        nearby[key] = nil
        self:Fire("ENEMY_LOST", key)
    end
    if had then self:Fire("NEARBY_CHANGED") end
end

function ET:NearbyCount()
    local n = 0
    for _ in pairs(nearby) do n = n + 1 end
    return n
end

-- Sorted array of nearby entries (for the counter list).
function ET:GetNearbyList()
    local list = {}
    for _, d in pairs(nearby) do list[#list + 1] = d end
    table.sort(list, function(a, b) return a.name < b.name end)
    return list
end

function ET:SetScanning(enabled)
    self.db.settings.scanEnabled = enabled and true or false
    if not enabled then self:ClearNearby() else self:ScanAll() end
    self:Print(enabled and ET.L.SCAN_ON or ET.L.SCAN_OFF)
    self:Fire("SETTINGS_CHANGED", "scanEnabled")
end

-------------------------------------------------------------------------------
-- Events + timer
-------------------------------------------------------------------------------
ET:RegisterEvent("NAME_PLATE_UNIT_ADDED", function(_, unit) ET:ObserveUnit(unit, "nameplate") end)
ET:RegisterEvent("PLAYER_TARGET_CHANGED", function() ET:ObserveUnit("target", "target") end)
ET:RegisterEvent("UPDATE_MOUSEOVER_UNIT", function() ET:ObserveUnit("mouseover", "mouseover") end)

ET:On("LOGIN", function()
    -- Errors are caught so an unexpected client value can never cause an
    -- error popup every second; they are reported once via debug logging.
    local reported = false
    C_Timer.NewTicker(TICK, function()
        local ok, err = pcall(ET.ScanAll, ET)
        if ok then ok, err = pcall(ET.ExpireNearby, ET) end
        if not ok and not reported then
            reported = true
            ET:Debug("scan error (further ones suppressed):", err)
        end
    end)
end)

ET:On("BLACKLIST_CHANGED", function(key, action)
    if action == "remove" and nearby[key] then
        nearby[key] = nil
        ET:Fire("ENEMY_LOST", key)
        ET:Fire("NEARBY_CHANGED")
    elseif action == "add" then
        ET:ScanAll()
    end
end)
