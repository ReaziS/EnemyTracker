-- Enemy Tracker: shared groups.
--
-- A group is identified by a random ID such as "ET-7KQM-X2PV-9HRT" and lives
-- on a hidden in-game chat channel named after it ("ET7KQMX2PV9HRT"). There is
-- no server: members' addons exchange their lists over that channel (see
-- GroupSync.lua). Knowing the ID is what lets someone in, so the ID is the
-- group's key; share it only with people you trust.
local _, ET = ...
local L = ET.L

local ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ" -- no 0/O, 1/I/L
local ID_LEN = 12                                   -- ~59 bits of randomness
local MAX_GROUPS = 3        -- each group takes one of the client's chat channel slots
local JOIN_DELAY = 10       -- seconds after login, so General/Trade keep /1 and /2
local JOIN_POLL, JOIN_TIMEOUT = 1, 15

ET.MAX_GROUPS = MAX_GROUPS

-------------------------------------------------------------------------------
-- IDs
-------------------------------------------------------------------------------
function ET.NewGroupId()
    local t = {}
    for i = 1, ID_LEN do
        local n = math.random(1, #ALPHABET)
        t[i] = ALPHABET:sub(n, n)
    end
    return table.concat(t)
end

-- Accepts "ET-7KQM-X2PV-9HRT", "et7kqmx2pv9hrt", "7KQM X2PV 9HRT"...
-- Returns the canonical 12-character ID or nil.
function ET.ParseGroupId(input)
    if type(input) ~= "string" or ET.IsSecret(input) then return nil end
    local s = input:upper():gsub("[%s%-]", "")
    if #s == ID_LEN + 2 and s:sub(1, 2) == "ET" then s = s:sub(3) end
    if #s ~= ID_LEN then return nil end
    for i = 1, ID_LEN do
        if not ALPHABET:find(s:sub(i, i), 1, true) then return nil end
    end
    return s
end

function ET.FormatGroupId(id)
    return "ET-" .. id:sub(1, 4) .. "-" .. id:sub(5, 8) .. "-" .. id:sub(9, 12)
end

function ET.GroupChannel(id) return "ET" .. id end

-------------------------------------------------------------------------------
-- Membership
-------------------------------------------------------------------------------
local runtime = {}   -- id -> { ready = bool, index = channel number }
ET.groupRuntime = runtime

function ET:GroupCount()
    local n = 0
    for _ in pairs(self.db.groups) do n = n + 1 end
    return n
end

-- Group whose hidden channel has this name, or nil.
function ET:GroupByChannel(channelName)
    if type(channelName) ~= "string" or ET.IsSecret(channelName) then return nil end
    local id = channelName:upper():match("^ET(%w+)$")
    return id and self.db.groups[id] and id or nil
end

local function hideChannel(name)
    if not ChatFrame_RemoveChannel then return end
    for _, frameName in ipairs(_G.CHAT_FRAMES or {}) do
        local f = _G[frameName]
        if f then pcall(ChatFrame_RemoveChannel, f, name) end
    end
end

-- Joins the hidden channel; GROUP_READY fires once the client confirms it.
function ET:ConnectGroup(id)
    local name = ET.GroupChannel(id)
    local rt = runtime[id] or {}
    runtime[id] = rt
    rt.ready = false
    JoinTemporaryChannel(name)
    local waited = 0
    local function poll()
        if not self.db.groups[id] then return end -- left meanwhile
        local index = GetChannelName(name)
        if type(index) == "number" and index > 0 then
            rt.ready, rt.index = true, index
            hideChannel(name)
            self:Debug("group ready", ET.FormatGroupId(id), "channel", index)
            self:Fire("GROUP_READY", id)
        elseif waited < JOIN_TIMEOUT then
            waited = waited + JOIN_POLL
            C_Timer.After(JOIN_POLL, poll)
        else
            self:Print(string.format(L.GROUP_JOIN_FAILED, ET.FormatGroupId(id)))
        end
    end
    C_Timer.After(JOIN_POLL, poll)
end

function ET:JoinGroup(input, isOwner)
    local id = ET.ParseGroupId(input)
    if not id then
        self:Print(string.format(L.GROUP_BAD_ID, tostring(input)))
        return false
    end
    if self.db.groups[id] then
        self:Print(string.format(L.GROUP_ALREADY, ET.FormatGroupId(id)))
        return false
    end
    if self:GroupCount() >= MAX_GROUPS then
        self:Print(string.format(L.GROUP_LIMIT, MAX_GROUPS))
        return false
    end
    self.db.groups[id] = { id = id, joinedAt = time(), owner = isOwner and true or nil, share = true, records = {} }
    self:ConnectGroup(id)
    if not isOwner then self:Print(string.format(L.GROUP_JOINED, ET.FormatGroupId(id))) end
    self:Fire("GROUPS_CHANGED", id, "join")
    return id
end

function ET:CreateGroup()
    if self:GroupCount() >= MAX_GROUPS then
        self:Print(string.format(L.GROUP_LIMIT, MAX_GROUPS))
        return nil
    end
    local id = ET.NewGroupId()
    while self.db.groups[id] do id = ET.NewGroupId() end
    self:JoinGroup(id, true)
    self:Print(string.format(L.GROUP_CREATED, ET.FormatGroupId(id)))
    return id
end

function ET:LeaveGroup(input)
    local id = ET.ParseGroupId(input)
    if not id or not self.db.groups[id] then
        self:Print(string.format(L.GROUP_NOT_MEMBER, tostring(input)))
        return false
    end
    LeaveChannelByName(ET.GroupChannel(id))
    self.db.groups[id] = nil
    runtime[id] = nil
    self:Print(string.format(L.GROUP_LEFT, ET.FormatGroupId(id)))
    self:Fire("GROUPS_CHANGED", id, "leave")
    return true
end

function ET:PrintGroups()
    if next(self.db.groups) == nil then
        self:Print(L.GROUP_NONE)
        return
    end
    self:Print(L.GROUP_LIST_HEADER)
    for id, g in pairs(self.db.groups) do
        local rt = runtime[id]
        DEFAULT_CHAT_FRAME:AddMessage(string.format("  %s%s - %s", ET.FormatGroupId(id),
            g.owner and (" " .. L.GROUP_OWNER) or "", (rt and rt.ready) and L.GROUP_ONLINE or L.GROUP_CONNECTING))
    end
end

-------------------------------------------------------------------------------
-- Lifecycle
-------------------------------------------------------------------------------
ET:On("DB_READY", function()
    local db = ET.db
    db.groups = type(db.groups) == "table" and db.groups or {}
    for id, g in pairs(db.groups) do
        if type(g) ~= "table" or ET.ParseGroupId(id) ~= id then
            db.groups[id] = nil
        else
            g.id = id
            g.records = type(g.records) == "table" and g.records or {}
            if g.share == nil then g.share = true end
        end
    end
end)

ET:On("LOGIN", function()
    if next(ET.db.groups) == nil then return end
    C_Timer.After(JOIN_DELAY, function()
        for id in pairs(ET.db.groups) do ET:ConnectGroup(id) end
    end)
end)
