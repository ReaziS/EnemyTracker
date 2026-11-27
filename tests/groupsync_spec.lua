-- Group sync: members' addons exchange lists over the hidden channel.
local H = require("harness")
local mock = H.mock
local eq, ok, no = H.eq, H.ok, H.no

local GID = "7KQMX2PV9HRB"

local function client(name, surname)
    local ET, env = H.boot({ player = { name = name, surname = surname, faction = "Alliance", guid = "Player-" .. name } })
    return { ET = ET, env = env }
end

local function envs(...)
    local t = {}
    for i, c in ipairs({ ... }) do t[i] = c.env end
    return t
end

local function rec(c, key) return c.ET.db.groups[GID] and c.ET.db.groups[GID].records[key] end

-- Joins c as an existing member (as if it had created the group).
local function found(c)
    c.ET:JoinGroup(GID)
    c.ET.db.groups[GID].verified = nil
end

local function sentBodies(env, kind)
    local n = 0
    for _, m in ipairs(env._state.addonOut) do
        if m.text:sub(2, 2) == kind then n = n + 1 end
    end
    return n
end

-- Delivers one raw message to c as if `sender` sent it on the group channel.
local function inject(c, sender, text)
    mock.fire(c.env, "CHAT_MSG_ADDON", "ETG2", text, "CHANNEL", sender, "", 0,
        c.ET.groupRuntime[GID].index, "ET" .. GID)
end

local function record(at, name, desc, del, by)
    return "1R" .. table.concat({ at, del and 1 or 0, "H", by or "Bad-Guy", name, desc or "" }, "^")
end

return {
    { "a member who joins receives the list, without anyone's stats", function()
        math.randomseed(1)
        local a, b = client("Anna", "Kova"), client("Boris", "Lebed")
        a.ET:AddEnemy("Ivan Petrov")
        a.ET:SetDescription("Ivan Petrov", "Ganks lowbies")
        a.ET.db.enemies["ivan petrov"].stats.killedMe = 7
        found(a)
        mock.mesh(envs(a, b), 2)
        b.ET:JoinGroup(GID)
        mock.mesh(envs(a, b), 20)
        local r = rec(b, "ivan petrov")
        ok(r, "B got the record")
        eq(r.name, "Ivan Petrov")
        eq(r.description, "Ganks lowbies")
        eq(r.by, "Anna Kova")
        no(r.stats)
        no(b.ET.db.enemies["ivan petrov"], "shared players do not enter B's own list")
        H.noErrors(a.env) H.noErrors(b.env)
    end },

    { "the lists merge both ways and each player appears once", function()
        math.randomseed(2)
        local a, b = client("Anna", "Kova"), client("Boris", "Lebed")
        a.ET:AddEnemy("Ivan Petrov")
        b.ET:AddEnemy("Olga Smirnova")
        b.ET:AddEnemy("Ivan Petrov")
        found(a)
        mock.mesh(envs(a, b), 2)
        b.ET:JoinGroup(GID)
        mock.mesh(envs(a, b), 30)
        for _, c in ipairs({ a, b }) do
            ok(rec(c, "ivan petrov"))
            ok(rec(c, "olga smirnova"))
            local n = 0
            for _ in pairs(c.ET.db.groups[GID].records) do n = n + 1 end
            eq(n, 2)
        end
        eq(a.ET:GroupDigest(GID), b.ET:GroupDigest(GID), "both copies are identical")
    end },

    { "changes made while connected reach the others at once", function()
        math.randomseed(3)
        local a, b = client("Anna", "Kova"), client("Boris", "Lebed")
        found(a) b.ET:JoinGroup(GID)
        mock.mesh(envs(a, b), 5)
        a.ET:AddEnemy("Olga Smirnova")
        mock.mesh(envs(a, b), 1)
        ok(rec(b, "olga smirnova"))
        a.ET:SetDescription("Olga Smirnova", "Camps the flight master")
        mock.mesh(envs(a, b), 1)
        eq(rec(b, "olga smirnova").description, "Camps the flight master")
        a.ET:RemoveEnemy("Olga Smirnova")
        mock.mesh(envs(a, b), 1)
        ok(rec(b, "olga smirnova").del, "the author's removal spreads")
    end },

    { "adding a described player again keeps the description; only its author removes it", function()
        math.randomseed(4)
        local a, b = client("Anna", "Kova"), client("Boris", "Lebed")
        found(a) b.ET:JoinGroup(GID)
        mock.mesh(envs(a, b), 5)
        a.ET:AddEnemy("Ivan Petrov")
        a.ET:SetDescription("Ivan Petrov", "Ganks lowbies")
        mock.mesh(envs(a, b), 1)
        mock.advance(b.env, 5)
        b.ET:AddEnemy("Ivan Petrov")
        mock.mesh(envs(a, b), 1)
        eq(rec(a, "ivan petrov").description, "Ganks lowbies")
        b.ET:RemoveEnemy("Ivan Petrov")
        mock.mesh(envs(a, b), 1)
        no(rec(a, "ivan petrov").del)
        no(rec(b, "ivan petrov").del)
    end },

    { "a member who was offline gets the list from whoever is online", function()
        math.randomseed(5)
        local a, b, c = client("Anna", "Kova"), client("Boris", "Lebed"), client("Vera", "Orlova")
        a.ET:AddEnemy("Ivan Petrov")
        found(a) b.ET:JoinGroup(GID)
        mock.mesh(envs(a, b), 20)
        c.ET:JoinGroup(GID)
        mock.mesh(envs(b, c), 20) -- Anna logged off
        ok(rec(c, "ivan petrov"))
        eq(rec(c, "ivan petrov").by, "Anna Kova")
    end },

    { "one member answers a request, the others stand down", function()
        math.randomseed(6)
        local a, b, c = client("Anna", "Kova"), client("Boris", "Lebed"), client("Vera", "Orlova")
        a.ET:AddEnemy("Ivan Petrov")
        found(a) b.ET:JoinGroup(GID)
        mock.mesh(envs(a, b), 20)
        local answers = 0
        for _, x in ipairs({ a, b }) do
            local send = x.env.C_ChatInfo.SendAddonMessageLogged
            x.env.C_ChatInfo.SendAddonMessageLogged = function(prefix, text, ...)
                if text:sub(2, 2) == "B" then answers = answers + 1 end
                return send(prefix, text, ...)
            end
        end
        c.ET:JoinGroup(GID)
        mock.mesh(envs(a, b, c), 20)
        eq(answers, 1)
        ok(rec(c, "ivan petrov"))
    end },

    { "lists survive a reload and are re-shared on reconnect", function()
        math.randomseed(7)
        local a, b = client("Anna", "Kova"), client("Boris", "Lebed")
        a.ET:AddEnemy("Ivan Petrov")
        found(a) b.ET:JoinGroup(GID)
        mock.mesh(envs(a, b), 20)
        local ET2, env2 = H.reboot(b.env)
        ok(ET2.db.groups[GID].records["ivan petrov"])
        H.noErrors(env2)
    end },

    { "long Cyrillic descriptions are split into messages and put back together", function()
        math.randomseed(8)
        local a, b = client("Anna", "Kova"), client("Boris", "Lebed")
        found(a) b.ET:JoinGroup(GID)
        mock.mesh(envs(a, b), 5)
        a.ET:AddEnemy("Иван Петров")
        local text = string.rep("Убивает новичков. ", 12)
        a.ET:SetDescription("Иван Петров", text)
        mock.mesh(envs(a, b), 3) -- the mock asserts every message is <= 255 bytes
        eq(rec(b, "иван петров").description, a.ET.db.enemies["иван петров"].description)
        H.noErrors(a.env) H.noErrors(b.env)
    end },

    { "rejects malformed records and strips UI escapes", function()
        local b = client("Boris", "Lebed")
        b.ET:JoinGroup(GID)
        mock.advance(b.env, 2)
        local now = b.env.time()
        inject(b, "Bad-Guy", record(now, "x", "short name"))
        inject(b, "Bad-Guy", record(now, "Ivan Petrov Third", "three words"))
        inject(b, "Bad-Guy", record(now + 86400, "Ivan Petrov", "from the future"))
        inject(b, "Bad-Guy", "1Rnot a record")
        eq(next(b.ET.db.groups[GID].records), nil)
        inject(b, "Bad-Guy", record(now, "Ivan Petrov", "|TInterface\\Icons\\x:0|t |cffff0000red|r\1"))
        local r = rec(b, "ivan petrov")
        ok(r)
        no(r.description:find("|", 1, true))
        eq(r.faction, "Horde")
        H.noErrors(b.env)
    end },

    { "a flooding sender is muted for a while", function()
        local b = client("Boris", "Lebed")
        b.ET:JoinGroup(GID)
        mock.advance(b.env, 2)
        local now = b.env.time()
        for i = 1, 100 do inject(b, "Bad-Guy", record(now, "Ivan Petrov", "spam " .. i)) end
        local desc = rec(b, "ivan petrov").description
        ok(desc ~= "spam 100", "messages over the budget are dropped")
        mock.advance(b.env, 60)
        inject(b, "Bad-Guy", record(b.env.time(), "Olga Smirnova", "still muted"))
        no(rec(b, "olga smirnova"))
        inject(b, "Good-Guy", record(b.env.time(), "Olga Smirnova", "others are not affected"))
        ok(rec(b, "olga smirnova"))
    end },

    { "caps the number of records per group", function()
        local b = client("Boris", "Lebed")
        b.ET:JoinGroup(GID)
        local g = b.ET.db.groups[GID]
        for i = 1, b.ET.GROUP_MAX_RECORDS do g.records["k" .. i] = { name = "X", at = 1 } end
        mock.advance(b.env, 2)
        inject(b, "Good-Guy", record(b.env.time(), "Olga Smirnova", "one too many"))
        no(rec(b, "olga smirnova"))
    end },

    { "waits out messaging lockdown and retries throttled sends", function()
        local a = client("Anna", "Kova")
        found(a)
        mock.advance(a.env, 2)
        a.env._state.addonOut = {}
        a.env._state.lockdown = true
        a.ET:AddEnemy("Ivan Petrov")
        mock.advance(a.env, 3)
        eq(#a.env._state.addonOut, 0, "nothing sent during lockdown")
        a.env._state.lockdown = false
        a.env._state.addonResult = 3 -- AddonMessageThrottle
        mock.advance(a.env, 0.5)
        eq(#a.env._state.addonOut, 0)
        a.env._state.addonResult = nil
        mock.advance(a.env, 1)
        eq(sentBodies(a.env, "R"), 1, "sent once the throttle clears")
    end },

    { "finds the group by channel number when the name is not given", function()
        math.randomseed(9)
        local a, b = client("Anna", "Kova"), client("Boris", "Lebed")
        a.ET:AddEnemy("Ivan Petrov")
        found(a) b.ET:JoinGroup(GID)
        mock.mesh(envs(a, b), 20, { noChannelName = true })
        ok(rec(b, "ivan petrov"))
    end },

    { "ignores other prefixes, other channels and our own echo", function()
        local a = client("Anna", "Kova")
        found(a)
        mock.advance(a.env, 2)
        local now = a.env.time()
        mock.fire(a.env, "CHAT_MSG_ADDON", "OTHER", record(now, "Ivan Petrov"), "CHANNEL", "X-Y", "", 0, 99, "Trade")
        mock.fire(a.env, "CHAT_MSG_ADDON", "ETG2", record(now, "Ivan Petrov"), "CHANNEL", "X-Y", "", 0, 99, "Trade")
        inject(a, "Anna-Kova", record(now, "Ivan Petrov"))
        inject(a, mock.SECRET, record(now, "Ivan Petrov"))
        no(rec(a, "ivan petrov"))
        H.noErrors(a.env)
    end },

    { "joining succeeds when a member answers, even one with an empty list", function()
        math.randomseed(10)
        local a, b = client("Anna", "Kova"), client("Boris", "Lebed")
        found(a)
        mock.mesh(envs(a, b), 2)
        b.ET:JoinGroup(GID)
        mock.mesh(envs(a, b), 30)
        ok(b.ET.db.groups[GID], "group kept")
        eq(b.ET.db.groups[GID].verified, nil)
        ok(H.chatContains(b.env, b.ET.L.GROUP_JOINED:format("ET-7KQM-X2PV-9HRB")))
        H.noErrors(a.env) H.noErrors(b.env)
    end },

    { "two people checking the same unknown ID do not confirm each other", function()
        math.randomseed(11)
        local a, b = client("Anna", "Kova"), client("Boris", "Lebed")
        a.ET:JoinGroup(GID)
        b.ET:JoinGroup(GID)
        mock.mesh(envs(a, b), 30)
        no(a.ET.db.groups[GID])
        no(b.ET.db.groups[GID])
    end },

    { "sends although the client reports addon messages as restricted", function()
        -- On Forever AreOutgoingAddonChatMessagesRestricted() stays true while
        -- messages go through; waiting on it meant never sending anything.
        local a = client("Anna", "Kova")
        found(a)
        mock.advance(a.env, 2)
        a.env._state.addonOut = {}
        a.env._state.addonRestricted = true
        a.ET:AddEnemy("Ivan Petrov")
        mock.advance(a.env, 1)
        eq(sentBodies(a.env, "R"), 1)
        H.noErrors(a.env)
    end },

    { "a message refused by lockdown is kept and sent later", function()
        local a = client("Anna", "Kova")
        found(a)
        mock.advance(a.env, 2)
        a.env._state.addonOut = {}
        a.env._state.addonResult = 11 -- AddOnMessageLockdown
        a.ET:AddEnemy("Ivan Petrov")
        mock.advance(a.env, 30)
        eq(#a.env._state.addonOut, 0)
        a.env._state.addonResult = nil
        mock.advance(a.env, 2)
        eq(sentBodies(a.env, "R"), 1, "not dropped")
    end },

    { "sends with logged addon messages, so reported text can be checked", function()
        math.randomseed(12)
        local a, b = client("Anna", "Kova"), client("Boris", "Lebed")
        found(a)
        b.ET:JoinGroup(GID)
        mock.mesh(envs(a, b), 5)
        local all, logged = 0, 0
        local send = a.env.C_ChatInfo.SendAddonMessageLogged
        a.env.C_ChatInfo.SendAddonMessageLogged = function(...)
            logged = logged + 1
            return send(...)
        end
        local plain = a.env.C_ChatInfo.SendAddonMessage
        a.env.C_ChatInfo.SendAddonMessage = function(...)
            all = all + 1
            return plain(...)
        end
        a.ET:AddEnemy("Ivan Petrov")
        a.ET:SetDescription("Ivan Petrov", "Ganks ^ lowbies | at night")
        mock.mesh(envs(a, b), 2)
        ok(logged >= 2)
        eq(all, 0, "nothing sent unlogged")
        eq(rec(b, "ivan petrov").description, "Ganks lowbies at night", "separator and escapes stripped")
        H.noErrors(a.env) H.noErrors(b.env)
    end },

    { "falls back to plain addon messages when the client lacks the logged one or refuses it", function()
        math.randomseed(13)
        local a, b = client("Anna", "Kova"), client("Boris", "Lebed")
        a.env.C_ChatInfo.SendAddonMessageLogged = nil
        found(a)
        a.ET:AddEnemy("Ivan Petrov")
        b.ET:JoinGroup(GID)
        mock.mesh(envs(a, b), 20)
        ok(rec(b, "ivan petrov"), "no logged API: plain messages")
        local c = client("Vera", "Orlova")
        found(c)
        c.env.C_ChatInfo.SendAddonMessageLogged = function() return 2 end -- InvalidMessage
        mock.advance(c.env, 2)
        c.env._state.addonOut = {}
        c.ET:AddEnemy("Olga Smirnova")
        mock.advance(c.env, 2)
        eq(sentBodies(c.env, "R"), 1, "refused text goes out unlogged")
    end },

    { "falls back to plain messages when logged ones are refused on channels", function()
        math.randomseed(3)
        local a, b = client("Anna", "Kova"), client("Boris", "Lebed")
        a.ET:AddEnemy("Ivan Petrov")
        found(a)
        mock.mesh(envs(a, b), 2)
        a.env._state.loggedResult, b.env._state.loggedResult = 4, 4 -- InvalidChatType
        b.ET:JoinGroup(GID)
        mock.mesh(envs(a, b), 20)
        ok(b.ET.db.groups[GID], "group found")
        ok(rec(b, "ivan petrov"), "list arrived")
    end },

    { "matches the channel when the client reports it as a numbered name", function()
        math.randomseed(4)
        local a, b = client("Anna", "Kova"), client("Boris", "Lebed")
        a.ET:AddEnemy("Ivan Petrov")
        found(a)
        mock.mesh(envs(a, b), 2, { numbered = true })
        b.ET:JoinGroup(GID)
        mock.mesh(envs(a, b), 20, { numbered = true })
        ok(b.ET.db.groups[GID], "group found")
        ok(rec(b, "ivan petrov"), "list arrived")
    end },

    { "the join check waits while messages are blocked", function()
        math.randomseed(5)
        local a, b = client("Anna", "Kova"), client("Boris", "Lebed")
        found(a)
        mock.mesh(envs(a, b), 2)
        b.env._state.lockdown = true
        b.ET:JoinGroup(GID)
        mock.mesh(envs(a, b), 40)
        ok(b.ET.db.groups[GID], "not declared missing while nothing could be asked")
        no(H.chatContains(b.env, b.ET.L.GROUP_NOT_FOUND:format("ET-7KQM-X2PV-9HRB")))
        b.env._state.lockdown = false
        mock.mesh(envs(a, b), 10)
        ok(b.ET.db.groups[GID].verified ~= false, "confirmed once the question went out")
    end },

    { "keeps a group whose channel has players even if nobody answers", function()
        local b = client("Boris", "Lebed")
        b.ET:JoinGroup(GID)
        mock.advance(b.env, 1)
        b.env._state.channelMembers[b.ET.groupRuntime[GID].index] = 3
        mock.mesh({ b.env }, 30)
        ok(b.ET.db.groups[GID], "kept")
        ok(b.ET.db.groups[GID].verified ~= false)
        ok(H.chatContains(b.env, b.ET.L.GROUP_NO_ANSWER:format("ET-7KQM-X2PV-9HRB", 2)))
    end },

    { "/et group debug reports channel, counters and the player's realm", function()
        math.randomseed(6)
        local a, b = client("Anna", "Kova"), client("Boris", "Lebed")
        found(a)
        mock.mesh(envs(a, b), 2)
        b.ET:JoinGroup(GID)
        mock.mesh(envs(a, b), 20)
        H.slash(b.env, "group debug")
        ok(H.chatContains(b.env, "Forever"), "realm")
        ok(H.chatContains(b.env, "channel ET7KQMX2PV9HRB"), "channel name")
        no(H.chatContains(b.env, "received=0"), "answers were counted")
    end },

    { "a long list arrives whole despite the server flood limit", function()
        math.randomseed(7)
        local a, b = client("Anna", "Kova"), client("Boris", "Lebed")
        local first = { "Ivan", "Petr", "Olga", "Anna", "Gleb", "Inna", "Oleg", "Vera" }
        local last = { "Petrov", "Sokol", "Orlov", "Lisin", "Belov", "Popov" }
        local n = 0
        for _, f in ipairs(first) do
            for _, l in ipairs(last) do
                if a.ET:AddEnemy(f .. " " .. l, true) then n = n + 1 end
            end
        end
        eq(n, 48)
        found(a)
        mock.mesh(envs(a, b), 2)
        b.ET:JoinGroup(GID)
        mock.mesh(envs(a, b), 90)
        local got = 0
        for _, r in pairs(b.ET.db.groups[GID].records) do if not r.del then got = got + 1 end end
        eq(got, 48, "every record arrived")
        eq(a.ET.groupDiag.dropped, 0, "nothing dropped")
        eq(a.env._state.throttleRefusals, 0, "paced under the limit")
    end },

    { "a player added during a long upload reaches the group at once", function()
        math.randomseed(8)
        local a, b = client("Anna", "Kova"), client("Boris", "Lebed")
        local first = { "Ivan", "Petr", "Olga", "Anna", "Gleb", "Inna", "Oleg", "Vera" }
        local last = { "Petrov", "Sokol", "Orlov", "Lisin", "Belov", "Popov" }
        for _, f in ipairs(first) do
            for _, l in ipairs(last) do a.ET:AddEnemy(f .. " " .. l, true) end
        end
        found(a)
        mock.mesh(envs(a, b), 2)
        b.ET:JoinGroup(GID)
        mock.mesh(envs(a, b), 15) -- the upload is under way
        a.ET:AddEnemy("Zoya Kuznec", true)
        mock.mesh(envs(a, b), 3)
        ok(rec(b, "zoya kuznec"), "ahead of the rest of the list")
    end },

    { "a newcomer with an empty list gets it when a member comes online later", function()
        -- B joined while nobody else was online; later A (who has the list)
        -- logs in. A asks with its digest; B has nothing to send, but must
        -- ask back so that A sends the list - no reload on B's side.
        math.randomseed(9)
        local a, b = client("Anna", "Kova"), client("Boris", "Lebed")
        a.ET:AddEnemy("Ivan Petrov")
        a.ET:AddEnemy("Olga Smirnova")
        found(b)
        mock.mesh(envs(b), 5)
        found(a)
        mock.mesh(envs(a, b), 30)
        ok(rec(b, "ivan petrov"), "B got A's list")
        ok(rec(b, "olga smirnova"))
    end },

    { "lists that missed each other catch up within minutes, without a reload", function()
        math.randomseed(10)
        local a, b = client("Anna", "Kova"), client("Boris", "Lebed")
        a.ET:AddEnemy("Ivan Petrov")
        b.ET:AddEnemy("Olga Smirnova")
        found(a) found(b)
        mock.mesh(envs(a, b), 30, { dropTo = { [a.env] = true, [b.env] = true } }) -- all lost
        no(rec(b, "ivan petrov"))
        mock.mesh(envs(a, b), 320)
        ok(rec(b, "ivan petrov"), "B caught up")
        ok(rec(a, "olga smirnova"), "A caught up")
    end },

    { "once lists match, members stay quiet", function()
        math.randomseed(11)
        local a, b = client("Anna", "Kova"), client("Boris", "Lebed")
        a.ET:AddEnemy("Ivan Petrov")
        b.ET:AddEnemy("Olga Smirnova")
        found(a)
        mock.mesh(envs(a, b), 2)
        b.ET:JoinGroup(GID)
        mock.mesh(envs(a, b), 60)
        eq(a.ET:GroupDigest(GID), b.ET:GroupDigest(GID), "in sync")
        local sent = 0
        local function count(env)
            local orig = env.C_ChatInfo.SendAddonMessageLogged
            env.C_ChatInfo.SendAddonMessageLogged = function(...) sent = sent + 1 return orig(...) end
        end
        count(a.env) count(b.env)
        mock.mesh(envs(a, b), 600)
        ok(sent <= 4, "only the periodic checks, got " .. sent)
    end },
}
