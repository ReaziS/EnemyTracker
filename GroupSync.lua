-- Enemy Tracker: list exchange inside a shared group.
--
-- Every member keeps a copy of the group's list in g.records, keyed like the
-- blacklist (NameKey), so one player appears once however many members added
-- them. A record carries only what is shared: name, faction, description,
-- who changed it last and when. Kill statistics stay personal and are never
-- sent.
--
-- Conflicts resolve last-writer-wins on the change time. Removing a player
-- you shared last leaves a tombstone so the removal spreads too; removing one
-- a member shared only stops your own tracking. Tombstones expire after
-- TOMBSTONE_TTL.
--
-- Protocol (addon messages on the group's hidden channel, prefix "ETG2"):
--   Q<digest>                 I just connected; my copy has this digest
--   B<requester>              I am answering <requester>; others stand down
--   R<at>^<del>^<fac>^<by>^<name>^<desc>   one record
--   E<requester>^<digest>     end of my answer; my digest after it
--   W                         anyone here? (sent when joining someone's group)
--   H                         here (answer to W)
-- A body longer than one message is split into "P<id>:<i>:<n>:<chunk>" parts;
-- a body that fits is sent as "1<body>".
--
-- Messages go out with SendAddonMessageLogged when the client has it (Forever
-- does): Blizzard made it for player-written text, so descriptions can be
-- checked by support if someone reports them. Receivers get those as
-- CHAT_MSG_ADDON_LOGGED. Fields are separated by "^" rather than a tab so the
-- text stays printable; "^" and "|" are stripped from descriptions.
--
-- Protection against a member (or anyone who learned the ID) flooding us:
-- a per-sender message budget with a temporary mute, one answered request per
-- sender per minute, strict validation of every field and a cap on the number
-- of records per group.
local _, ET = ...

local PREFIX = "ETG2"
local SEP = "^"
local MAX_MSG = 250                     -- client limit is 255 bytes
local SEND_INTERVAL = 0.25              -- how often the queue is looked at
-- The server allows each prefix a burst of about 10 messages, then one per
-- second; stay just under it so nothing is refused for flooding.
local SEND_BURST, SEND_RATE = 8, 0.9    -- messages, messages per second
local MAX_TRIES = 120                   -- refusals before a message is dropped
local MAX_RECORDS = 2000                -- per group
local FUTURE_SLACK = 3600               -- accepted clock skew, seconds
local TOMBSTONE_TTL = 30 * 86400
local ANSWER_DELAY_MIN, ANSWER_DELAY_MAX = 1, 5
local REQUEST_COOLDOWN = 60
local RESYNC_EVERY = 300                -- seconds between digest checks per group
local BUCKET_SIZE, BUCKET_RATE = 60, 4  -- per sender: burst, messages per second
local MUTE_FOR = 300
local PART_TTL = 30
local PROBE_TIMEOUT = 15                -- seconds to wait for a member when joining
local PING_COOLDOWN = 10
-- AddonMessageThrottle, ChannelThrottle, AddOnMessageLockdown: try again later.
local RETRY_RESULTS = { [3] = true, [8] = true, [11] = true }
local INVALID_MESSAGE = 2                        -- Enum.SendAddonMessageResult.InvalidMessage

-- Counters for /et group debug: what was sent, what came back, what was dropped.
local diag = { sent = {}, received = {}, lastResult = {}, unmatched = nil, blocked = 0, dropped = 0 }
ET.groupDiag = diag

local function succeeded(result)
    return result == nil or result == true or result == 0
end

ET.GROUP_MAX_RECORDS = MAX_RECORDS
ET.GROUP_PREFIX = PREFIX

local runtime = ET.groupRuntime
local queue = {}
local ticker
local tokens, tokensAt = SEND_BURST, nil
local partSeq = 0
local senders = {}      -- sender key -> { tokens, t, mutedUntil, parts = {} }

local FACTION_CODE = { Alliance = "A", Horde = "H" }
local CODE_FACTION = { A = "Alliance", H = "Horde" }

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------
local function myName() return ET.PlayerName("player") or "" end

local function isMe(name)
    local mine = ET.NameKey(myName())
    return mine ~= nil and ET.NameKey(name) == mine
end

-- Who added the player to the group. Records from older versions have no
-- owner field; their author counts as the adder.
local function ownerOf(rec) return rec.owner or rec.by end
-- When the record was first put into the group (older records: their time).
local function firstOf(rec) return rec.first or rec.at end

local function hash(s)
    local h = 5381
    for i = 1, #s do h = (h * 33 + s:byte(i)) % 2147483647 end
    return h
end

function ET:GroupDigest(id)
    local g = self.db.groups[id]
    local n, sum = 0, 0
    for key, r in pairs(g and g.records or {}) do
        n = n + 1
        -- Who owns the record counts too, so copies that agree on the content
        -- but not on the owner still sync.
        sum = (sum + hash(key .. SEP .. r.at .. SEP .. (r.del and 1 or 0) .. SEP .. (r.description or "")
            .. SEP .. (ownerOf(r) or "") .. SEP .. firstOf(r))) % 2147483647
    end
    return n .. ":" .. sum
end

local function cleanDescription(s)
    s = s:gsub("[|%^]", ""):gsub("%c", " "):gsub("%s+", " ")
    return ET.Utf8Truncate(ET.Trim(s), ET.DESCRIPTION_MAX)
end

-- Splits s into pieces of at most n bytes without cutting a UTF-8 character.
local function utf8Chunks(s, n)
    local out, i = {}, 1
    while i <= #s do
        local j = math.min(i + n - 1, #s)
        while j < #s and j > i do
            local b = s:byte(j + 1)
            if b < 0x80 or b >= 0xC0 then break end
            j = j - 1
        end
        out[#out + 1] = s:sub(i, j)
        i = j + 1
    end
    return out
end

-------------------------------------------------------------------------------
-- Store
-------------------------------------------------------------------------------
local function newer(a, b) -- is record a newer than b?
    if not b then return true end
    if a.at ~= b.at then return a.at > b.at end
    if (a.del and true or false) ~= (b.del and true or false) then return a.del and true or false end
    return (a.by or "") > (b.by or "")
end

-- Merges a record into the group's copy. Returns true if it changed.
--
-- The newest change wins the content (name, faction, description, removal).
-- Ownership does not follow it: when two members added the same player
-- independently, whoever added them first stays the owner, decided the same
-- way on every client so all copies agree.
function ET:MergeGroupRecord(id, key, rec)
    local g = self.db.groups[id]
    if not g then return false end
    local cur = g.records[key]
    rec.first = firstOf(rec)
    if cur and not cur.del and not rec.del then
        local cf, rf = firstOf(cur), rec.first
        local older = (cf < rf or (cf == rf and (ownerOf(cur) or "") <= (ownerOf(rec) or ""))) and cur or rec
        if newer(rec, cur) then
            rec.owner, rec.first = ownerOf(older), firstOf(older)
        else
            if older == cur then return false end
            cur.owner, cur.first = ownerOf(rec), rec.first -- only the ownership comes in
            self:Fire("GROUP_RECORDS_CHANGED", id, key)
            return true
        end
    elseif cur and not newer(rec, cur) then
        return false
    end
    if not cur then
        local n = 0
        for _ in pairs(g.records) do n = n + 1 end
        if n >= MAX_RECORDS then
            self:Debug("group", ET.FormatGroupId(id), "is full, dropped", key)
            return false
        end
    end
    g.records[key] = rec
    self:Fire("GROUP_RECORDS_CHANGED", id, key)
    return true
end

-- Time stamp for a change we make now: later than the copy it replaces, even
-- within the same second, so last-writer-wins never drops our own edit.
function ET.ChangeTime(cur)
    local now = time()
    return cur and cur.at >= now and cur.at + 1 or now
end

-- Publishes one of our own blacklist entries into a group. Returns true if
-- the group's copy changed.
--
-- A player the group already has stays with whoever added them (owner): we
-- only send what is new, never taking the record over: our description when
-- we edit it or the group has none, or a faction the record lacks. Only the
-- owner's removal removes a player from the group. Text in the group is
-- cleared only by explicitly clearing the description we wrote ourselves.
--
-- A new player is stamped now when we just added or edited them (isEdit);
-- when re-sharing on login, with when we added them, so a removal made since
-- by the group is not undone.
local function publishOwn(id, key, entry, isEdit, clearing)
    if entry.needsSurname or not ET.IsValidName(entry.name) then return false end
    local cur = ET.db.groups[id].records[key]
    local desc = entry.description or ""
    local faction = FACTION_CODE[entry.faction or ""] and entry.faction or nil
    if cur and not cur.del then
        local theirs = cur.description or ""
        local newDesc
        if desc == "" then
            newDesc = clearing and theirs ~= "" and isMe(cur.by)
        else
            newDesc = desc ~= theirs and (isEdit or theirs == "")
        end
        local newFaction = faction ~= nil and cur.faction == nil
        if not (newDesc or newFaction) then return false end
        return ET:MergeGroupRecord(id, key, {
            name = cur.name, faction = cur.faction or faction,
            description = newDesc and desc or (cur.description or ""),
            at = ET.ChangeTime(cur), by = myName(), owner = ownerOf(cur), first = firstOf(cur),
        })
    end
    return ET:MergeGroupRecord(id, key, {
        name = entry.name, faction = faction, description = desc,
        at = isEdit and ET.ChangeTime(cur) or entry.addedAt or time(), by = myName(), owner = myName(),
    })
end

-------------------------------------------------------------------------------
-- Sending
-------------------------------------------------------------------------------
-- Midnight-era clients (Forever included) block outgoing addon messages in
-- some situations; keep the queue until they are allowed again.
-- Only the lockdown query is a reliable "not now". AreOutgoingAddonChat-
-- MessagesRestricted is not: on Forever it answers true all the time while
-- messages go through, so the send result decides instead.
local function outgoingBlocked()
    local lockdown = C_ChatInfo.InChatMessagingLockdown
    if lockdown then
        local ok, v = pcall(lockdown)
        if ok and v and not ET.IsSecret(v) then return true end
    end
    return false
end

local function takeToken()
    local now = GetTime()
    tokens = math.min(SEND_BURST, tokens + (now - (tokensAt or now)) * SEND_RATE)
    tokensAt = now
    if tokens < 1 then return false end
    tokens = tokens - 1
    return true
end

local function sendNext()
    local item = queue[1]
    if not item then
        if ticker then ticker:Cancel() ticker = nil end
        return
    end
    if outgoingBlocked() then diag.blocked = diag.blocked + 1 return end
    local rt = runtime[item.id]
    if not (rt and rt.ready and ET.db.groups[item.id]) then
        table.remove(queue, 1)
        return
    end
    if not takeToken() then return end
    local result
    local logged = C_ChatInfo.SendAddonMessageLogged
    if logged and not item.plain then
        result = logged(PREFIX, item.text, "CHANNEL", tostring(rt.index))
        if not succeeded(result) and not RETRY_RESULTS[result] then
            -- The logged variant refused this message (the text, or logged
            -- messages on channels at all); send it unlogged instead.
            ET:Debug("logged addon message refused (" .. tostring(result) .. "), sending unlogged")
            diag.lastResult[item.id] = "logged:" .. tostring(result)
            item.plain = true
            return
        end
    else
        result = C_ChatInfo.SendAddonMessage(PREFIX, item.text, "CHANNEL", tostring(rt.index))
    end
    if type(result) == "number" and RETRY_RESULTS[result] and item.tries < MAX_TRIES then
        -- Refused for now: keep it first in line and wait a second.
        item.tries = item.tries + 1
        diag.lastResult[item.id] = (item.plain and "plain:" or "") .. tostring(result)
        tokens = 0
        return
    end
    table.remove(queue, 1)
    diag.lastResult[item.id] = (item.plain and "plain:" or "") .. tostring(result == nil and "ok" or result)
    if succeeded(result) then
        diag.sent[item.id] = (diag.sent[item.id] or 0) + 1
        if item.onSent then item.onSent() end
    else
        diag.dropped = diag.dropped + 1
    end
end

-- bulk: part of a whole-list upload. Everything else (questions, answers,
-- a change just made) goes ahead of queued bulk messages, so a new player
-- reaches the group at once even while a long list is being sent.
local function send(id, body, onSent, bulk)
    local texts
    if #body + 1 <= MAX_MSG then
        texts = { "1" .. body }
    else
        partSeq = (partSeq + 1) % 1000
        local chunks = utf8Chunks(body, MAX_MSG - 12)
        texts = {}
        for i, c in ipairs(chunks) do
            texts[i] = string.format("P%d:%d:%d:%s", partSeq, i, #chunks, c)
        end
    end
    local at = #queue + 1
    if not bulk then
        for i, item in ipairs(queue) do
            -- Never cut in front of a message that is already being retried.
            if item.bulk and i > 1 then at = i break end
        end
    end
    for i, t in ipairs(texts) do
        table.insert(queue, at + i - 1, { id = id, text = t, tries = 0, bulk = bulk,
            onSent = i == #texts and onSent or nil })
    end
    if not ticker then ticker = C_Timer.NewTicker(SEND_INTERVAL, sendNext) end
end

-- "S" records carry who added the player; older versions sent "R" without
-- it (still read, the author counting as the adder). Older versions ignore
-- "S", so every member needs this version for the group to sync.
local function encodeRecord(rec)
    return "S" .. table.concat({
        rec.at, rec.del and 1 or 0, FACTION_CODE[rec.faction or ""] or "-", rec.by or "", ownerOf(rec) or "",
        firstOf(rec), rec.name, rec.del and "" or (rec.description or ""):gsub("[|%^]", ""),
    }, SEP)
end

function ET:BroadcastRecord(id, key)
    local g, rt = self.db.groups[id], runtime[id]
    local rec = g and g.records[key]
    if rec and rt and rt.ready then send(id, encodeRecord(rec)) end
end

local function sendAll(id)
    local g = ET.db.groups[id]
    for _, rec in pairs(g and g.records or {}) do send(id, encodeRecord(rec), nil, true) end
end

-------------------------------------------------------------------------------
-- Receiving
-------------------------------------------------------------------------------
local function decodeRecord(body)
    local at, del, fac, by, owner, first, name, desc
    if body:sub(1, 1) == "S" then
        at, del, fac, by, owner, first, name, desc =
            body:match("^S(%d+)%^([01])%^([AH%-])%^([^%^]*)%^([^%^]*)%^(%d+)%^([^%^]+)%^(.*)$")
    else
        at, del, fac, by, name, desc = body:match("^R(%d+)%^([01])%^([AH%-])%^([^%^]*)%^([^%^]+)%^(.*)$")
    end
    at = tonumber(at)
    if not at or at < 1e9 or at > time() + FUTURE_SLACK then return nil end
    name = ET.NormalizeName(name)
    if not ET.IsValidName(name) then return nil end
    by = ET.NormalizeName(by)
    by = ET.IsValidName(by) and ET.DisplayName(by) or nil
    owner = ET.NormalizeName(owner)
    owner = ET.IsValidName(owner) and ET.DisplayName(owner) or by
    first = tonumber(first)
    if not first or first < 1e9 or first > at then first = at end
    return ET.NameKey(name), {
        name = ET.DisplayName(name), faction = CODE_FACTION[fac], at = at, del = del == "1" or nil,
        by = by, owner = owner, first = first,
        description = del == "1" and "" or cleanDescription(desc),
    }
end

local function answer(id, requester)
    local rt = runtime[id]
    if not (rt and rt.pending and rt.pending[requester]) then return end
    rt.pending[requester] = nil
    send(id, "B" .. requester)
    sendAll(id)
    send(id, "E" .. requester .. SEP .. ET:GroupDigest(id))
end

local handlers = {}

-- Messages that only a member of an existing group sends: hearing one
-- confirms a group we are joining.
local CONFIRMS = { H = true, R = true, S = true, B = true, E = true }

handlers.W = function(id, sender)
    local rt = runtime[id]
    rt.pinged = rt.pinged or {}
    local last = rt.pinged[sender]
    if last and GetTime() - last < PING_COOLDOWN then return end
    rt.pinged[sender] = GetTime()
    C_Timer.After(math.random(), function() send(id, "H") end)
end

handlers.H = function() end

handlers.Q = function(id, sender, body)
    local rt = runtime[id]
    if body:sub(2) == ET:GroupDigest(id) then return end
    -- Our lists differ. Answering only sends what we hold; so also ask back
    -- with our own digest, and whoever holds records we lack sends them, no
    -- matter which side asked first (once a minute per sender, no ping-pong).
    rt.askedBack = rt.askedBack or {}
    local asked = rt.askedBack[sender]
    if not asked or GetTime() - asked >= REQUEST_COOLDOWN then
        rt.askedBack[sender] = GetTime()
        C_Timer.After(math.random(), function()
            if rt.ready and ET.db.groups[id] then send(id, "Q" .. ET:GroupDigest(id)) end
        end)
    end
    if next(ET.db.groups[id].records) == nil then return end
    rt.answered = rt.answered or {}
    local last = rt.answered[sender]
    if last and GetTime() - last < REQUEST_COOLDOWN then return end
    rt.answered[sender] = GetTime()
    rt.pending = rt.pending or {}
    rt.pending[sender] = true
    C_Timer.After(ANSWER_DELAY_MIN + math.random() * (ANSWER_DELAY_MAX - ANSWER_DELAY_MIN),
        function() answer(id, sender) end)
end

handlers.B = function(id, sender, body)
    local rt = runtime[id]
    local requester = ET.NameKey(body:sub(2))
    if rt.pending then
        for k in pairs(rt.pending) do
            if ET.NameKey(k) == requester then rt.pending[k] = nil end
        end
    end
end

handlers.R = function(id, sender, body) -- also "S", see below
    local key, rec = decodeRecord(body)
    if not key then
        ET:Debug("group", ET.FormatGroupId(id), "bad record from", sender)
        return
    end
    ET:MergeGroupRecord(id, key, rec)
end
handlers.S = handlers.R

handlers.E = function(id, sender, body)
    local requester, digest = body:match("^E([^%^]+)%^(.+)$")
    local rt = runtime[id]
    if not requester or ET.NameKey(requester) ~= ET.NameKey(myName()) or rt.synced then return end
    rt.synced = true
    -- The answer gave us their list; if ours still differs we hold records
    -- they lack, so send ours once.
    if ET:GroupDigest(id) ~= digest then sendAll(id) end
end

-- Per-sender message budget; a sender over budget is ignored for a while.
local function allow(sender)
    local now = GetTime()
    local s = senders[sender]
    if not s then
        s = { tokens = BUCKET_SIZE, t = now, parts = {} }
        senders[sender] = s
    end
    if s.mutedUntil and now < s.mutedUntil then return nil end
    s.tokens = math.min(BUCKET_SIZE, s.tokens + (now - s.t) * BUCKET_RATE)
    s.t = now
    if s.tokens < 1 then
        s.mutedUntil = now + MUTE_FOR
        ET:Debug("group sender flooding, muted:", sender)
        return nil
    end
    s.tokens = s.tokens - 1
    return s
end

-- Reassembles split bodies. Returns the full body once complete.
local function collect(s, text)
    if text:sub(1, 1) == "1" then return text:sub(2) end
    local seq, i, n, chunk = text:match("^P(%d+):(%d+):(%d+):(.*)$")
    i, n = tonumber(i), tonumber(n)
    if not seq or i < 1 or n < 2 or n > 8 or i > n then return nil end
    local now = GetTime()
    for k, p in pairs(s.parts) do
        if now - p.t > PART_TTL then s.parts[k] = nil end
    end
    local p = s.parts[seq]
    if not p or p.n ~= n then
        p = { n = n, got = 0, t = now }
        s.parts[seq] = p
    end
    if not p[i] then p[i], p.got = chunk, p.got + 1 end
    if p.got < n then return nil end
    s.parts[seq] = nil
    return table.concat(p, "", 1, n)
end

-- The channel arrives as a name ("ETXXXX" or "6. ETXXXX") or as its local
-- number, depending on the client; accept all of them.
local function groupOf(target, localID, channelName)
    for _, v in ipairs({ channelName, target }) do
        if type(v) == "string" then
            local id = ET:GroupByChannel(v) or ET:GroupByChannel(v:match("^%d+%.%s*(.+)$"))
            if id then return id end
        end
    end
    for _, v in ipairs({ localID, target }) do
        local n = tonumber(v)
        if n then
            for gid, rt in pairs(runtime) do
                if rt.ready and rt.index == n and ET.db.groups[gid] then return gid end
            end
        end
    end
end

function ET:OnGroupMessage(prefix, text, channel, sender, target, _, localID, channelName)
    for _, v in ipairs({ prefix, text, channel, sender, target, localID, channelName }) do
        if ET.IsSecret(v) then return end
    end
    if prefix ~= PREFIX or channel ~= "CHANNEL" or type(text) ~= "string" or type(sender) ~= "string" then return end
    local id = groupOf(target, localID, channelName)
    if not id then
        diag.unmatched = string.format("%s / %s / %s", tostring(target), tostring(localID), tostring(channelName))
        return
    end
    diag.received[id] = (diag.received[id] or 0) + 1
    local senderKey = ET.NameKey(sender)
    if senderKey == ET.NameKey(myName()) then return end
    local s = allow(senderKey)
    if not s then return end
    local body = collect(s, text)
    if not body or body == "" then return end
    local kind = body:sub(1, 1)
    local handler = handlers[kind]
    if not handler then return end
    if CONFIRMS[kind] then ET:ConfirmGroup(id) end
    -- While we are still checking the group, we have nothing to answer with.
    if ET.db.groups[id].verified == false and (kind == "W" or kind == "Q") then return end
    handler(id, ET.NormalizeName(sender), body)
end

-------------------------------------------------------------------------------
-- Wiring
-------------------------------------------------------------------------------
local function shareAll(id)
    local g = ET.db.groups[id]
    if not (g and g.share) then return end
    for key, entry in pairs(ET.db.enemies) do publishOwn(id, key, entry) end
end

C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
ET:RegisterEvent("CHAT_MSG_ADDON", function(_, ...) ET:OnGroupMessage(...) end)
ET:RegisterEvent("CHAT_MSG_ADDON_LOGGED", function(_, ...) ET:OnGroupMessage(...) end)

ET:On("DB_READY", function()
    local now = time()
    for id, g in pairs(ET.db.groups) do
        for key, r in pairs(g.records) do
            if type(r) ~= "table" or type(r.at) ~= "number" or type(r.name) ~= "string"
                or (r.del and now - r.at > TOMBSTONE_TTL) then
                g.records[key] = nil
            end
        end
        shareAll(id)
    end
end)

ET:On("GROUPS_CHANGED", function(id, what)
    if what == "join" then
        shareAll(id)
    elseif what == "leave" then
        for i = #queue, 1, -1 do
            if queue[i].id == id then table.remove(queue, i) end
        end
    end
end)

ET:On("GROUP_READY", function(id)
    local rt = runtime[id]
    rt.synced, rt.pending = false, {}
    if ET.db.groups[id].verified == false then
        -- The wait starts once the question has really left: while messages
        -- are blocked (combat, battlegrounds) nobody could have answered.
        send(id, "W", function()
            C_Timer.After(PROBE_TIMEOUT, function() ET:GroupNotFound(id) end)
        end)
    end
    send(id, "Q" .. ET:GroupDigest(id))
end)

-- Every few minutes each group compares digests once more, so a message
-- lost on the way (or a member who came online meanwhile) is caught up
-- without a reload.
C_Timer.NewTicker(RESYNC_EVERY, function()
    if not ET.db then return end
    for id, g in pairs(ET.db.groups) do
        local rt = runtime[id]
        if rt and rt.ready and g.verified ~= false then send(id, "Q" .. ET:GroupDigest(id)) end
    end
end)

ET:On("BLACKLIST_CHANGED", function(key, what)
    if what ~= "add" and what ~= "description" and what ~= "rename" and what ~= "remove" then return end
    local entry = ET.db.enemies[key]
    for id, g in pairs(ET.db.groups) do
        if g.share then
            local changed
            if what == "remove" then
                -- Only who added the player removes them from the group;
                -- anyone else only removes them from their own list.
                local cur = g.records[key]
                changed = cur and not cur.del and isMe(ownerOf(cur)) and ET:MergeGroupRecord(id, key, {
                    name = cur.name, faction = cur.faction, description = "", at = ET.ChangeTime(cur),
                    del = true, by = myName(), owner = ownerOf(cur), first = firstOf(cur),
                })
            elseif entry then
                changed = publishOwn(id, key, entry, true, what == "description")
            end
            if changed then ET:BroadcastRecord(id, key) end
        end
    end
end)
