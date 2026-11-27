-- Enemy Tracker: SavedVariables, blacklist storage and per-player statistics.
local _, ET = ...
local L = ET.L

local DB_VERSION = 1

local DEFAULT_SETTINGS = {
    scanEnabled = true,
    visual = true,
    sound = true,
    soundKey = "RAID_WARNING",
    soundChannel = "Master",
    scale = 1.0,
    autoHide = 30,          -- seconds, 0 = alert stays until closed
    showCounter = true,
    showMinimap = true,
    useCombatLog = true,
    useGroupTargets = true,
    locked = true,
    debug = false,
}

local function applyDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if target[k] == nil then target[k] = v end
    end
end

function ET:InitDatabase()
    local db = _G.EnemyTrackerDB
    if type(db) ~= "table" then db = {} end
    db.version = db.version or DB_VERSION
    db.enemies = type(db.enemies) == "table" and db.enemies or {}
    db.settings = type(db.settings) == "table" and db.settings or {}
    db.positions = type(db.positions) == "table" and db.positions or {}
    db.minimap = type(db.minimap) == "table" and db.minimap or {}
    applyDefaults(db.settings, DEFAULT_SETTINGS)
    if db.minimap.angle == nil then db.minimap.angle = 220 end

    -- Repair entries: re-key with the current normalisation, merge duplicates.
    local fixed = {}
    for key, e in pairs(db.enemies) do
        if type(e) == "table" and type(e.name) == "string" then
            local k = ET.NameKey(e.name) or key
            e.name = ET.DisplayName(e.name)
            e.killedMe = tonumber(e.killedMe) or 0
            e.iKilled = tonumber(e.iKilled) or 0
            e.detections = tonumber(e.detections) or 0
            e.addedAt = tonumber(e.addedAt) or time()
            e.lastSeen = tonumber(e.lastSeen) or 0
            local prev = fixed[k]
            if prev then
                prev.killedMe = prev.killedMe + e.killedMe
                prev.iKilled = prev.iKilled + e.iKilled
                prev.detections = prev.detections + e.detections
                prev.addedAt = math.min(prev.addedAt, e.addedAt)
                prev.lastSeen = math.max(prev.lastSeen, e.lastSeen)
            else
                fixed[k] = e
            end
        end
    end
    db.enemies = fixed

    _G.EnemyTrackerDB = db
    self.db = db
end

ET.DEFAULT_SETTINGS = DEFAULT_SETTINGS

-------------------------------------------------------------------------------
-- Blacklist API
-------------------------------------------------------------------------------

-- Returns the enemy entry for a name (any case) or nil. O(1) hash lookup.
function ET:GetEnemy(name)
    local key = ET.NameKey(name)
    return key and self.db.enemies[key], key
end

function ET:GetEnemyByKey(key)
    return self.db.enemies[key]
end

function ET:EnemyCount()
    local n = 0
    for _ in pairs(self.db.enemies) do n = n + 1 end
    return n
end

-- Adds a player. Returns true on success; prints feedback unless quiet.
function ET:AddEnemy(name, quiet)
    name = ET.Trim(name or ""):gsub("%-.*$", "")
    if not ET.IsValidName(name) then
        if not quiet then self:Print(string.format(L.INVALID_NAME, name)) end
        return false
    end
    local key = ET.NameKey(name)
    if ET.IsSelfName(name) then
        if not quiet then self:Print(L.CANT_ADD_SELF) end
        return false
    end
    if self.db.enemies[key] then
        if not quiet then self:Print(string.format(L.ALREADY, self.db.enemies[key].name)) end
        return false
    end
    local entry = {
        name = ET.DisplayName(name),
        addedAt = time(),
        killedMe = 0,
        iKilled = 0,
        detections = 0,
        lastSeen = 0,
    }
    self.db.enemies[key] = entry
    if not quiet then self:Print(string.format(L.ADDED, entry.name)) end
    self:Debug("added", key)
    self:Fire("BLACKLIST_CHANGED", key, "add")
    return true
end

-- Adds the current target. Returns true on success.
function ET:AddTarget()
    local exists = UnitExists("target")
    if ET.IsSecret(exists) or not exists then
        self:Print(L.NO_TARGET)
        return false
    end
    local name = ET.PlayerName("target")
    if not name then
        self:Print(L.TARGET_NOT_PLAYER)
        return false
    end
    return self:AddEnemy(name)
end

function ET:RemoveEnemy(name)
    local entry, key = self:GetEnemy(name)
    if not entry then
        self:Print(string.format(L.NOT_FOUND, tostring(name)))
        return false
    end
    self.db.enemies[key] = nil
    self:Print(string.format(L.REMOVED, entry.name))
    self:Fire("BLACKLIST_CHANGED", key, "remove")
    return true
end

-- Resets kill counters and detection count. "Last seen" and "added" are kept.
function ET:ClearStats(name)
    local entry, key = self:GetEnemy(name)
    if not entry then
        self:Print(string.format(L.NOT_FOUND, tostring(name)))
        return false
    end
    entry.killedMe = 0
    entry.iKilled = 0
    entry.detections = 0
    self:Print(string.format(L.STATS_CLEARED, entry.name))
    self:Fire("BLACKLIST_CHANGED", key, "clear")
    return true
end

-------------------------------------------------------------------------------
-- Confirmation dialogs (irreversible actions)
-------------------------------------------------------------------------------
StaticPopupDialogs["ENEMYTRACKER_CONFIRM_REMOVE"] = {
    text = "%s",
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, data) ET:RemoveEnemy(data) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["ENEMYTRACKER_CONFIRM_CLEAR"] = {
    text = "%s",
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, data) ET:ClearStats(data) end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

function ET:ConfirmRemove(name)
    local entry = self:GetEnemy(name)
    if not entry then
        self:Print(string.format(L.NOT_FOUND, tostring(name)))
        return
    end
    StaticPopup_Show("ENEMYTRACKER_CONFIRM_REMOVE", string.format(L.CONFIRM_REMOVE, entry.name), nil, entry.name)
end

function ET:ConfirmClear(name)
    local entry = self:GetEnemy(name)
    if not entry then
        self:Print(string.format(L.NOT_FOUND, tostring(name)))
        return
    end
    StaticPopup_Show("ENEMYTRACKER_CONFIRM_CLEAR", string.format(L.CONFIRM_CLEAR, entry.name), nil, entry.name)
end
