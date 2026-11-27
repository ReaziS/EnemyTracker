-- Enemy Tracker: SavedVariables, blacklist storage and per-player statistics.
--
-- Data model (schemaVersion 2). The model is plain data, independent of the
-- UI, so a list can later be exported, shared and merged:
--
--   EnemyTrackerDB = {
--     schemaVersion = 2,
--     enemies = {                      -- keyed by ET.NameKey(name)
--       ["ivan petrov"] = {
--         id = "6578a1b2c3d4e5",       -- stable record id (time + random)
--         name = "Ivan Petrov",        -- full Forever name, client spelling
--         faction = "Horde",           -- "Alliance" / "Horde" / nil (unknown)
--         description = "",            -- the user's note about the player
--         addedAt = 1800000000,        -- time() when added
--         lastSeen = 0,                -- time() of last detection, 0 = never
--         stats = { killedMe = 0, iKilled = 0, detections = 0 },
--         needsSurname = true,         -- only on legacy first-name-only records
--       },
--     },
--     settings = {...}, positions = {...}, minimap = {...},
--   }
--
-- Unknown fields are preserved. Older saves are upgraded by MIGRATIONS.
local _, ET = ...
local L = ET.L

local SCHEMA_VERSION = 2
ET.SCHEMA_VERSION = SCHEMA_VERSION

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

local STAT_FIELDS = { "killedMe", "iKilled", "detections" }
ET.STAT_FIELDS = STAT_FIELDS

local idCounter = 0
function ET.NewId()
    idCounter = (idCounter + 1) % 0x1000
    return string.format("%08x%03x%03x", time() % 0x100000000, math.random(0, 0xFFF), idCounter)
end

-- Migrations: MIGRATIONS[v] upgrades a save from schema v to v + 1.
local MIGRATIONS = {
    -- 1 -> 2: kill/detection counters move into `stats`; the old top-level
    -- `version` field is replaced by `schemaVersion`. New fields (id,
    -- faction, description) are filled in by normalizeRecord.
    [1] = function(db)
        for _, e in pairs(db.enemies) do
            if type(e) == "table" and type(e.stats) ~= "table" then
                e.stats = { killedMe = e.killedMe, iKilled = e.iKilled, detections = e.detections }
                e.killedMe, e.iKilled, e.detections = nil, nil, nil
            end
        end
        db.version = nil
    end,
}

local function schemaOf(db)
    if tonumber(db.schemaVersion) then return tonumber(db.schemaVersion) end
    if tonumber(db.version) then return tonumber(db.version) end
    if type(db.enemies) == "table" then return 1 end
    return SCHEMA_VERSION -- fresh install
end

-- Brings one record to the current schema; returns false if unusable.
local function normalizeRecord(e)
    if type(e) ~= "table" or type(e.name) ~= "string" then return false end
    e.name = ET.NormalizeName(e.name) or e.name
    if type(e.id) ~= "string" or e.id == "" then e.id = ET.NewId() end
    if e.faction ~= "Alliance" and e.faction ~= "Horde" then e.faction = nil end
    if type(e.description) ~= "string" then e.description = "" end
    e.addedAt = tonumber(e.addedAt) or time()
    e.lastSeen = tonumber(e.lastSeen) or 0
    if type(e.stats) ~= "table" then e.stats = {} end
    for _, f in ipairs(STAT_FIELDS) do e.stats[f] = tonumber(e.stats[f]) or 0 end
    -- Version 0.1.1 stored only the first name for targets and menu adds.
    e.needsSurname = e.name:find(" ", 1, true) == nil or nil
    return true
end

local function mergeInto(prev, e)
    for _, f in ipairs(STAT_FIELDS) do prev.stats[f] = prev.stats[f] + e.stats[f] end
    prev.addedAt = math.min(prev.addedAt, e.addedAt)
    prev.lastSeen = math.max(prev.lastSeen, e.lastSeen)
    if prev.description == "" then prev.description = e.description end
    prev.faction = prev.faction or e.faction
end

function ET:InitDatabase()
    local db = _G.EnemyTrackerDB
    if type(db) ~= "table" then db = {} end
    local version = schemaOf(db)
    db.enemies = type(db.enemies) == "table" and db.enemies or {}
    while version < SCHEMA_VERSION do
        MIGRATIONS[version](db)
        version = version + 1
    end
    db.schemaVersion = math.max(version, SCHEMA_VERSION)
    db.settings = type(db.settings) == "table" and db.settings or {}
    db.positions = type(db.positions) == "table" and db.positions or {}
    db.minimap = type(db.minimap) == "table" and db.minimap or {}
    applyDefaults(db.settings, DEFAULT_SETTINGS)
    if db.minimap.angle == nil then db.minimap.angle = 220 end

    -- Repair entries: re-key with the current normalisation, merge duplicates.
    local fixed = {}
    for key, e in pairs(db.enemies) do
        if normalizeRecord(e) then
            local k = ET.NameKey(e.name) or key
            if fixed[k] then mergeInto(fixed[k], e) else fixed[k] = e end
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
    local input = ET.Trim(type(name) == "string" and name or "")
    name = ET.NormalizeName(input)
    if not ET.IsValidName(name) then
        if not quiet then self:Print(string.format(L.INVALID_NAME, input)) end
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
        id = ET.NewId(),
        name = ET.DisplayName(name),
        description = "",
        addedAt = time(),
        lastSeen = 0,
        stats = { killedMe = 0, iKilled = 0, detections = 0 },
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
    for _, f in ipairs(STAT_FIELDS) do entry.stats[f] = 0 end
    self:Print(string.format(L.STATS_CLEARED, entry.name))
    self:Fire("BLACKLIST_CHANGED", key, "clear")
    return true
end

-------------------------------------------------------------------------------
-- Legacy records without a surname (v0.1.1 stored only the first name).
-- When a player with that first name is seen, the user confirms whether it
-- is the same person; the record then gets the full name and keeps its stats.
-------------------------------------------------------------------------------

-- "Yes, that's them": the legacy record becomes fullName.
function ET:CompleteSurname(legacyKey, fullName)
    local e = self.db.enemies[legacyKey]
    if not (e and e.needsSurname and ET.IsValidName(fullName)) then return false end
    local key = ET.NameKey(fullName)
    self.db.enemies[legacyKey] = nil
    local existing = self.db.enemies[key]
    if existing then
        mergeInto(existing, e)
    else
        e.name = ET.NormalizeName(fullName)
        e.needsSurname, e.notThem = nil, nil
        self.db.enemies[key] = e
    end
    self:Print(string.format(L.SURNAME_COMPLETED, self.db.enemies[key].name))
    self:Fire("BLACKLIST_CHANGED", key, "rename", legacyKey)
    return true
end

-- "No, someone else": never match that full name with the record again.
function ET:RejectSurname(legacyKey, fullName)
    local e = self.db.enemies[legacyKey]
    local key = ET.NameKey(fullName)
    if not (e and e.needsSurname and key) then return false end
    e.notThem = e.notThem or {}
    e.notThem[key] = true
    self:Print(string.format(L.SURNAME_REJECTED, ET.NormalizeName(fullName), e.name))
    self:Fire("BLACKLIST_CHANGED", legacyKey, "reject")
    return true
end

local askedSurname = {} -- "legacyKey|fullKey" -> true, once per session

ET:On("SURNAME_CANDIDATE", function(legacyKey, fullName)
    local id = legacyKey .. "|" .. (ET.NameKey(fullName) or "")
    if askedSurname[id] then return end
    askedSurname[id] = true
    local e = ET.db.enemies[legacyKey]
    StaticPopup_Show("ENEMYTRACKER_CONFIRM_SURNAME", string.format(L.SURNAME_CONFIRM, e.name, fullName), nil,
        { key = legacyKey, name = fullName })
end)

-------------------------------------------------------------------------------
-- Confirmation dialogs (irreversible actions)
-------------------------------------------------------------------------------
StaticPopupDialogs["ENEMYTRACKER_CONFIRM_SURNAME"] = {
    text = "%s",
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, data) ET:CompleteSurname(data.key, data.name) end,
    -- Only an explicit "No" rejects; closing for other reasons asks again later.
    OnCancel = function(_, data, reason)
        if reason == "clicked" then ET:RejectSurname(data.key, data.name) end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

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
