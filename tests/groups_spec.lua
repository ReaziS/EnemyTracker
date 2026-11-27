-- Shared groups: IDs, create / join / leave, hidden channels.
local H = require("harness")
local eq, ok, no = H.eq, H.ok, H.no

local GID = "7KQMX2PV9HRB"

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
        eq(ET.ParseGroupId("ET-7KQM-X2PV-9HRB"), "7KQMX2PV9HRB")
        eq(ET.ParseGroupId("et7kqmx2pv9hrb"), "7KQMX2PV9HRB")
        eq(ET.ParseGroupId("  7KQM X2PV 9HRB "), "7KQMX2PV9HRB")
        eq(ET.FormatGroupId("7KQMX2PV9HRB"), "ET-7KQM-X2PV-9HRB")
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
        H.slash(env, "group join et-7kqm-x2pv-9hrb")
        ok(ET.db.groups["7KQMX2PV9HRB"])
        no(ET.db.groups["7KQMX2PV9HRB"].owner)
        connect(env)
        ok(env._state.channels.ET7KQMX2PV9HRB)
        H.slash(env, "group leave ET-7KQM-X2PV-9HRB")
        no(ET.db.groups["7KQMX2PV9HRB"])
        no(env._state.channels.ET7KQMX2PV9HRB)
        H.noErrors(env)
    end },

    { "rejects bad IDs, duplicates and more than the group limit", function()
        local ET, env = H.boot()
        no(ET:JoinGroup("hello"))
        ok(H.chatContains(env, "hello"))
        ok(ET:JoinGroup("7KQMX2PV9HRB"))
        no(ET:JoinGroup("ET-7KQM-X2PV-9HRB"), "already a member")
        for _ = 2, ET.MAX_GROUPS do ok(ET:CreateGroup()) end
        no(ET:CreateGroup(), "limit reached")
        no(ET:JoinGroup("AAAABBBBCCCG"))
        eq(ET:GroupCount(), ET.MAX_GROUPS)
        no(ET:LeaveGroup("AAAABBBBCCCG"), "not a member")
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
            ["7KQMX2PV9HRB"] = { joinedAt = 1 }, bogus = { }, ["AAAABBBBCCCG"] = "x",
        } } })
        ok(ET.db.groups["7KQMX2PV9HRB"])
        eq(ET:GroupCount(), 1)
        eq(type(ET.db.groups["7KQMX2PV9HRB"].records), "table")
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

    { "a mistyped ID is rejected at once by its check character", function()
        local ET, env = H.boot()
        no(ET.ParseGroupId("ET-7KQM-X2PV-9HRT", true), "wrong last character")
        no(ET.ParseGroupId("ET-7KQM-X2VP-9HRB", true), "swapped characters")
        eq(ET.ParseGroupId("ET-7KQM-X2PV-9HRB", true), "7KQMX2PV9HRB")
        no(ET:JoinGroup("ET-7KQM-X2PV-9HRT"))
        ok(H.chatContains(env, "ET-7KQM-X2PV-9HRT"))
        no(next(ET.db.groups))
        for _ = 1, 200 do
            local id = ET.NewGroupId()
            eq(ET.ParseGroupId(id, true), id, "generated IDs pass the check")
        end
    end },

    { "joining a group nobody is in fails with an error and leaves the channel", function()
        local ET, env = H.boot()
        ok(ET:JoinGroup(GID))
        ok(H.chatContains(env, ET.L.GROUP_CHECKING:format("ET-7KQM-X2PV-9HRB")))
        eq(ET.db.groups[GID].verified, false)
        H.mock.advance(env, 10)
        ok(ET.db.groups[GID], "still waiting for an answer")
        H.mock.advance(env, 10)
        no(ET.db.groups[GID])
        no(env._state.channels.ET7KQMX2PV9HRB, "channel left")
        ok(H.chatContains(env, ET.L.GROUP_NOT_FOUND:format("ET-7KQM-X2PV-9HRB")))
        H.noErrors(env)
    end },

    { "a created group needs no check; an unfinished check is dropped on reload", function()
        local ET, env = H.boot()
        local id = ET:CreateGroup()
        H.mock.advance(env, 30)
        ok(ET.db.groups[id], "own group kept with nobody else in it")
        ET:JoinGroup(GID)
        local ET2 = H.reboot(env)
        ok(ET2.db.groups[id])
        no(ET2.db.groups[GID])
    end },
}
