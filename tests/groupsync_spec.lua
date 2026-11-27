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
    mock.fire(c.env, "CHAT_MSG_ADDON", "ETG1", text, "CHANNEL", sender, "", 0,
        c.ET.groupRuntime[GID].index, "ET" .. GID)
end

local function record(at, name, desc, del, by)
    return "1R" .. table.concat({ at, del and 1 or 0, "H", by or "Bad-Guy", name, desc or "" }, "\t")
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
            local send = x.env.C_ChatInfo.SendAddonMessage
            x.env.C_ChatInfo.SendAddonMessage = function(prefix, text, ...)
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
        mock.fire(a.env, "CHAT_MSG_ADDON", "ETG1", record(now, "Ivan Petrov"), "CHANNEL", "X-Y", "", 0, 99, "Trade")
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
}
