-- Shared groups: IDs, create / join / leave, hidden channels.
local H = require("harness")
local eq, ok, no = H.eq, H.ok, H.no

local function connect(env) H.mock.advance(env, 2) end

return {
    { "generates well-formed, distinct group IDs", function()
        local ET = H.boot()
        local seen = {}
        for _ = 1, 500 do
            local id = ET.NewGroupId()
            eq(#id, 12)
            eq(ET.ParseGroupId(id), id, "a new ID parses back to itself")
            no(seen[id], "IDs repeat")
            seen[id] = true
        end
    end },

    { "parses the ID in any of the forms a player would type", function()
        local ET = H.boot()
        eq(ET.ParseGroupId("ET-7KQM-X2PV-9HRT"), "7KQMX2PV9HRT")
        eq(ET.ParseGroupId("et7kqmx2pv9hrt"), "7KQMX2PV9HRT")
        eq(ET.ParseGroupId("  7KQM X2PV 9HRT "), "7KQMX2PV9HRT")
        eq(ET.FormatGroupId("7KQMX2PV9HRT"), "ET-7KQM-X2PV-9HRT")
        no(ET.ParseGroupId("ET-7KQM-X2PV"), "too short")
        no(ET.ParseGroupId("ET-7KQM-X2PV-9HR0"), "0 is not in the alphabet")
        no(ET.ParseGroupId(H.mock.SECRET))
        no(ET.ParseGroupId(nil))
    end },

    { "creating a group joins its hidden channel and hides it from chat", function()
        local ET, env = H.boot()
        local id = ET:CreateGroup()
        ok(id)
        ok(H.chatContains(env, ET.FormatGroupId(id)), "the ID is printed so it can be shared")
        ok(ET.db.groups[id].owner)
        no(ET.groupRuntime[id].ready, "not ready before the client confirms")
        connect(env)
        ok(ET.groupRuntime[id].ready)
        ok(env._state.channels["ET" .. id])
        eq(env._state.removedChannels[1].name, "ET" .. id)
        H.noErrors(env)
    end },

    { "/et group join and leave", function()
        local ET, env = H.boot()
        H.slash(env, "group join et-7kqm-x2pv-9hrt")
        ok(ET.db.groups["7KQMX2PV9HRT"])
        no(ET.db.groups["7KQMX2PV9HRT"].owner)
        connect(env)
        ok(env._state.channels.ET7KQMX2PV9HRT)
        H.slash(env, "group leave ET-7KQM-X2PV-9HRT")
        no(ET.db.groups["7KQMX2PV9HRT"])
        no(env._state.channels.ET7KQMX2PV9HRT)
        H.noErrors(env)
    end },

    { "rejects bad IDs, duplicates and more than the group limit", function()
        local ET, env = H.boot()
        no(ET:JoinGroup("hello"))
        ok(H.chatContains(env, "hello"))
        ok(ET:JoinGroup("7KQMX2PV9HRT"))
        no(ET:JoinGroup("ET-7KQM-X2PV-9HRT"), "already a member")
        for _ = 2, ET.MAX_GROUPS do ok(ET:CreateGroup()) end
        no(ET:CreateGroup(), "limit reached")
        no(ET:JoinGroup("AAAABBBBCCCC"))
        eq(ET:GroupCount(), ET.MAX_GROUPS)
        no(ET:LeaveGroup("AAAABBBBCCCC"), "not a member")
    end },

    { "rejoins saved groups after login, a few seconds later", function()
        local ET, env = H.boot()
        local id = ET:CreateGroup()
        local ET2, env2 = H.reboot(env)
        ok(ET2.db.groups[id])
        H.mock.advance(env2, 5)
        no(env2._state.channels["ET" .. id], "waits so General and Trade keep /1 and /2")
        H.mock.advance(env2, 10)
        ok(ET2.groupRuntime[id].ready)
        H.noErrors(env2)
    end },

    { "drops corrupt saved groups", function()
        local ET = H.boot({ savedDB = { schemaVersion = 2, enemies = {}, groups = {
            ["7KQMX2PV9HRT"] = { joinedAt = 1 }, bogus = { }, ["AAAABBBBCCCC"] = "x",
        } } })
        ok(ET.db.groups["7KQMX2PV9HRT"])
        eq(ET:GroupCount(), 1)
        eq(type(ET.db.groups["7KQMX2PV9HRT"].records), "table")
    end },

    { "lists groups with /et group list", function()
        local ET, env = H.boot()
        H.slash(env, "group list")
        ok(H.chatContains(env, "/et group create"))
        local id = ET:CreateGroup()
        H.slash(env, "group list")
        ok(H.lastChat(env):find(ET.FormatGroupId(id), 1, true))
        H.noErrors(env)
    end },
}
