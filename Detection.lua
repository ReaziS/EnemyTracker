-- Enemy Tracker: detection of blacklisted players through client-provided units.
-- Sources: nameplates, target, mouseover, focus, target-of-target,
-- focus-target, group members and their targets, and nearby combat log
-- events. No hidden data, no world scan.
local _, ET = ...

local LOST_AFTER = 10      -- seconds without any source before "no longer detected"
local TICK = 1.0           -- periodic re-check interval (no OnUpdate scanning)
local MAX_PLATES = 40
local PLATE_RECHECK = 0.3  -- NAME_PLATE_UNIT_ADDED can fire before the unit is filled in

local nearby = {}          -- key -> { key, name, firstSeen, lastSeen, source }
ET.nearby = nearby

local GetTime = GetTime

-- Pre-built unit token lists so the ticker allocates nothing.
local plateUnits = {}
local partyUnits, partyTargets, raidUnits, raidTargets = {}, {}, {}, {}
local targetOf = {}        -- "party1" -> "party1target", for UNIT_TARGET
for i = 1, MAX_PLATES do plateUnits[i] = "nameplate" .. i end
for i = 1, 4 do
    partyUnits[i], partyTargets[i] = "party" .. i, "party" .. i .. "target"
    targetOf[partyUnits[i]] = partyTargets[i]
end
for i = 1, 40 do
    raidUnits[i], raidTargets[i] = "raid" .. i, "raid" .. i .. "target"
    targetOf[raidUnits[i]] = raidTargets[i]
end

local function scanning()
    return ET.db and ET.db.settings.scanEnabled
end

-- Legacy record (first name only, from v0.1.1) that a seen full name may
-- belong to: same first name, and the user has not said "not them".
function ET:LegacyKeyFor(fullKey)
    local first = fullKey:match("^(%S+) ")
    local e = first and self.db.enemies[first]
    if e and e.needsSurname and not (e.notThem and e.notThem[fullKey]) then return first end
end

-- Records that a blacklisted player (by key) is visible right now.
local FACTIONS = { Alliance = true, Horde = true }

-- Faction of a unit ("Alliance"/"Horde") or nil if unknown or hidden.
function ET.UnitFaction(unit)
    if not unit then return nil end
    local f = UnitFactionGroup(unit)
    if ET.IsSecret(f) or not FACTIONS[f] then return nil end
    return f
end

-- Same faction as the player? Unknown factions count as hostile, so a
-- player we know nothing about still raises an alert.
function ET:IsAlly(key)
    local mine = ET.UnitFaction("player")
    local d, e = nearby[key], self.db.enemies[key]
    local theirs = (d and d.faction) or (e and not e.needsSurname and e.faction)
    return mine ~= nil and theirs == mine
end

function ET:MarkSeen(key, seenName, source, faction)
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
    if faction then
        d.faction = faction
        -- A legacy record may match a namesake, so it learns nothing.
        if not entry.needsSurname then entry.faction = faction end
    end
    -- Prefer the client's own spelling/case of the name.
    local spelled = ET.NormalizeName(seenName)
    if spelled and spelled ~= entry.name and ET.NameKey(spelled) == key then
        entry.name = spelled
    end
    -- A legacy record shows (and targets) the full name actually seen.
    d.name = entry.needsSurname and spelled or entry.name
    entry.lastSeen = time()
    if isNew then
        entry.stats.detections = entry.stats.detections + 1
        self:Debug("detected", entry.name, "via", source)
        self:Fire("ENEMY_DETECTED", key, entry, source)
        self:Fire("NEARBY_CHANGED")
    end
end

-- Matches a seen full name against the blacklist; cheap when not listed.
function ET:ObserveName(name, source, faction)
    if not scanning() or not name then return end
    local key = ET.NameKey(name)
    if not key then return end
    if self.db.enemies[key] then
        self:MarkSeen(key, name, source, faction)
        return
    end
    local legacyKey = self:LegacyKeyFor(key)
    if legacyKey then
        self:MarkSeen(legacyKey, name, source, faction)
        self:Fire("SURNAME_CANDIDATE", legacyKey, ET.NormalizeName(name))
    end
end

-------------------------------------------------------------------------------
-- Names seen this session (any player, listed or not). Used to confirm that a
-- manually typed name really exists before adding it. Bounded in size.
-------------------------------------------------------------------------------
local seenNames, seenCount = {}, 0
local SEEN_MAX = 3000

function ET:RememberName(name)
    local key = ET.NameKey(name)
    if not key or seenNames[key] then return end
    if seenCount >= SEEN_MAX then wipe(seenNames); seenCount = 0 end
    seenNames[key] = true
    seenCount = seenCount + 1
end

function ET:IsKnownName(name)
    local key = ET.NameKey(name)
    return key ~= nil and seenNames[key] == true
end

-- Checks a unit token.
function ET:ObserveUnit(unit, source)
    local name = ET.PlayerName(unit)
    if not name then return end
    self:RememberName(name)
    if scanning() then self:ObserveName(name, source, ET.UnitFaction(unit)) end
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
    self:ObserveUnit("focustarget", "focus")
    -- Group members and their targets, only if the client can actually see
    -- that unit (a raid member across the zone is not "nearby").
    if self.db.settings.useGroupTargets then
        local members, targets, n
        if IsInRaid and IsInRaid() then
            members, targets, n = raidUnits, raidTargets, GetNumGroupMembers()
        elseif GetNumGroupMembers and GetNumGroupMembers() > 0 then
            members, targets, n = partyUnits, partyTargets, 4
        end
        if members then
            for i = 1, math.min(n, #members) do
                self:ObserveVisibleUnit(members[i], "group")
                self:ObserveVisibleUnit(targets[i], "group")
            end
        end
    end
end

function ET:ObserveVisibleUnit(unit, source)
    local visible = UnitIsVisible(unit)
    if not ET.IsSecret(visible) and visible then self:ObserveUnit(unit, source) end
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
ET:RegisterEvent("NAME_PLATE_UNIT_ADDED", function(_, unit)
    ET:ObserveUnit(unit, "nameplate")
    C_Timer.After(PLATE_RECHECK, function() ET:ObserveUnit(unit, "nameplate") end)
end)
-- Chat authors count as "seen" for the existence check (not for detection:
-- a whisper or a channel message says nothing about distance).
local function rememberAuthor(_, _, author)
    if not ET.IsSecret(author) and type(author) == "string" then ET:RememberName(author) end
end
for _, event in ipairs({ "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_WHISPER", "CHAT_MSG_PARTY",
    "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_GUILD",
    "CHAT_MSG_CHANNEL", "CHAT_MSG_EMOTE" }) do
    ET:RegisterEvent(event, rememberAuthor)
end

-- A group member changed target: check it now instead of on the next tick.
ET:RegisterEvent("UNIT_TARGET", function(_, unit)
    local t = targetOf[unit]
    if t and ET.db and ET.db.settings.useGroupTargets then ET:ObserveVisibleUnit(t, "group") end
end)
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

ET:On("BLACKLIST_CHANGED", function(key, action, oldKey)
    if (action == "remove" or action == "reject") and nearby[key] then
        nearby[key] = nil
        ET:Fire("ENEMY_LOST", key)
        ET:Fire("NEARBY_CHANGED")
    elseif action == "rename" then
        local d = nearby[oldKey]
        if d then
            nearby[oldKey] = nil
            if not nearby[key] then
                d.key, d.name = key, ET.db.enemies[key].name
                nearby[key] = d
            end
            ET:Fire("NEARBY_CHANGED")
        end
    elseif action == "add" then
        ET:ScanAll()
    end
end)
