-- Enemy Tracker: shared groups.
--
-- A group is identified by a random ID such as "ET-7KQM-X2PV-9HRT" and lives
-- on a hidden in-game chat channel named after it ("ET7KQMX2PV9HRT"). There is
-- no server: members' addons exchange their lists over that channel (see
-- GroupSync.lua). Knowing the ID is what lets someone in, so the ID is the
-- group's key; share it only with people you trust.
--
-- The last character of an ID is a check character, so a mistyped ID is
-- rejected at once. Without a server a group "exists" only while someone is
-- in its channel: joining someone else's group asks the channel who is there
-- and leaves again with an error if no member answers.
local _, ET = ...
local L = ET.L

local ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ" -- no 0/O, 1/I/L
local ID_LEN = 12                                   -- 11 random (~54 bits) + check
local MAX_GROUPS = 3        -- each group takes one of the client's chat channel slots
local JOIN_DELAY = 10       -- seconds after login, so General/Trade keep /1 and /2
local JOIN_POLL, JOIN_TIMEOUT = 1, 15

ET.MAX_GROUPS = MAX_GROUPS

-------------------------------------------------------------------------------
-- IDs
-------------------------------------------------------------------------------
local function checkChar(body)
    local sum = 0
    for i = 1, #body do sum = sum + ALPHABET:find(body:sub(i, i), 1, true) * (i + 1) end
    local n = sum % #ALPHABET + 1
    return ALPHABET:sub(n, n)
end

function ET.NewGroupId()
    local t = {}
    for i = 1, ID_LEN - 1 do
        local n = math.random(1, #ALPHABET)
        t[i] = ALPHABET:sub(n, n)
    end
    local body = table.concat(t)
    return body .. checkChar(body)
end

-- Accepts "ET-7KQM-X2PV-9HRT", "et7kqmx2pv9hrt", "7KQM X2PV 9HRT"...
-- Returns the canonical 12-character ID or nil. With strict, the check
-- character must match too (typed IDs); saved IDs are checked by format only.
function ET.ParseGroupId(input, strict)
    if type(input) ~= "string" or ET.IsSecret(input) then return nil end
    local s = input:upper():gsub("[%s%-]", "")
    if #s == ID_LEN + 2 and s:sub(1, 2) == "ET" then s = s:sub(3) end
    if #s ~= ID_LEN then return nil end
    for i = 1, ID_LEN do
        if not ALPHABET:find(s:sub(i, i), 1, true) then return nil end
    end
    if strict and checkChar(s:sub(1, ID_LEN - 1)) ~= s:sub(ID_LEN) then return nil end
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
    local id = ET.ParseGroupId(input, true)
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
    -- verified = false until a member answers (see GroupSync).
    self.db.groups[id] = { id = id, joinedAt = time(), owner = isOwner and true or nil, share = true,
        records = {} }
    if not isOwner then self.db.groups[id].verified = false end
    self:ConnectGroup(id)
    if not isOwner then self:Print(string.format(L.GROUP_CHECKING, ET.FormatGroupId(id))) end
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

-- A member answered: the group exists.
function ET:ConfirmGroup(id)
    local g = self.db.groups[id]
    if not g or g.verified ~= false then return end
    g.verified = nil
    self:Print(string.format(L.GROUP_JOINED, ET.FormatGroupId(id)))
    self:Fire("GROUPS_CHANGED", id, "verified")
end

-- Nobody answered: drop the group again with an error.
function ET:GroupNotFound(id)
    local g = self.db.groups[id]
    if not g or g.verified ~= false then return end
    -- Others are in the channel but do not answer: the group exists, they
    -- just lack the addon (or run an old version). Keep it.
    local others = self:GroupChannelMembers(id) - 1
    if others > 0 then
        self:Print(string.format(L.GROUP_NO_ANSWER, ET.FormatGroupId(id), others))
        self:ConfirmGroup(id)
        return
    end
    self:Print(string.format(L.GROUP_NOT_FOUND, ET.FormatGroupId(id)))
    self:LeaveGroup(id, true)
end

-- How many players are in the group's channel (0 when unknown).
function ET:GroupChannelMembers(id)
    local rt = runtime[id]
    if not (rt and rt.index and GetNumChannelMembers) then return 0 end
    local ok, n = pcall(GetNumChannelMembers, rt.index)
    return (ok and type(n) == "number" and not ET.IsSecret(n)) and n or 0
end

-- /et group debug: everything needed to tell where messages get lost.
function ET:PrintGroupDebug()
    local d = ET.groupDiag or { sent = {}, received = {}, lastResult = {} }
    self:Print(string.format("%s, %s-%s, %s", ET.version or "?", tostring(ET.PlayerName("player")),
        tostring(GetRealmName and GetRealmName()), tostring(ET.UnitFaction("player"))))
    local any = false
    for id, g in pairs(self.db.groups) do
        any = true
        local rt = runtime[id] or {}
        local name = ET.GroupChannel(id)
        local index = GetChannelName(name)
        self:Print(string.format("%s: channel %s #%s ready=%s verified=%s members=%d sent=%d received=%d last=%s",
            ET.FormatGroupId(id), name, tostring(index), tostring(rt.ready), tostring(g.verified ~= false),
            self:GroupChannelMembers(id), d.sent[id] or 0, d.received[id] or 0, tostring(d.lastResult[id])))
    end
    if not any then self:Print(L.GROUP_NONE) end
    local blocked = C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
    self:Print(string.format("blocked=%s waits=%d dropped=%d unmatched=%s", tostring(blocked), d.blocked or 0,
        d.dropped or 0, tostring(d.unmatched)))
end

function ET:LeaveGroup(input, quiet)
    local id = ET.ParseGroupId(input)
    if not id or not self.db.groups[id] then
        self:Print(string.format(L.GROUP_NOT_MEMBER, tostring(input)))
        return false
    end
    LeaveChannelByName(ET.GroupChannel(id))
    self.db.groups[id] = nil
    runtime[id] = nil
    if not quiet then self:Print(string.format(L.GROUP_LEFT, ET.FormatGroupId(id))) end
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
        local state = g.verified == false and L.GROUP_CHECKING_SHORT
            or (rt and rt.ready) and L.GROUP_ONLINE or L.GROUP_CONNECTING
        DEFAULT_CHAT_FRAME:AddMessage(string.format("  %s%s - %s", ET.FormatGroupId(id),
            g.owner and (" " .. L.GROUP_OWNER) or "", state))
    end
end

-------------------------------------------------------------------------------
-- Lifecycle
-------------------------------------------------------------------------------
ET:On("DB_READY", function()
    local db = ET.db
    db.groups = type(db.groups) == "table" and db.groups or {}
    for id, g in pairs(db.groups) do
        -- verified == false: the check never finished (reload while joining).
        if type(g) ~= "table" or ET.ParseGroupId(id) ~= id or g.verified == false then
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
