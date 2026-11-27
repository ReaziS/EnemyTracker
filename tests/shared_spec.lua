-- Players shared by groups are watched for like the player's own.
local H = require("harness")
local mock = H.mock
local eq, ok, no = H.eq, H.ok, H.no

local GID, GID2 = "7KQMX2PV9HRB", "AAAABBBBCCCG"

local function unit(full, faction)
    local first, surname = full:match("^(%S+) (%S+)$")
    return { name = first, surname = surname, faction = faction or "Horde", guid = "Player-" .. full }
end

-- Boots a client in GID whose copy holds Ivan Petrov, shared by Anna.
local function withShared(desc, faction, gid)
    local ET, env = H.boot()
    ET:JoinGroup(gid or GID)
    ET:MergeGroupRecord(gid or GID, "ivan petrov", { name = "Ivan Petrov", faction = faction or "Horde",
        description = desc or "", at = env.time(), by = "Anna Kova" })
    mock.advance(env, 1)
    return ET, env
end

return {
    { "a shared player raises an alert, a flag and the corner note", function()
        local ET, env = withShared("Ganks lowbies")
        local v = ET:GetTracked("ivan petrov")
        ok(v and v.shared)
        H.target(env, unit("Ivan Petrov"))
        ok(env.EnemyTrackerAlert1:IsShown(), "alert")
        eq(env.EnemyTrackerNote1.text:GetText(), "Ganks lowbies")
        local _, msg = ET._chatFilter(nil, "CHAT_MSG_SAY", "hi", "Ivan Petrov")
        ok(msg:find("Flag", 1, true), "flag in chat")
        no(ET.db.enemies["ivan petrov"], "not copied into the player's own list")
        H.noErrors(env)
    end },

    { "no alert for a shared player of the player's own faction", function()
        local ET, env = withShared("x", "Alliance")
        H.target(env, unit("Ivan Petrov", "Alliance"))
        no(env.EnemyTrackerAlert1:IsShown())
    end },

    { "the player's own entry wins; an empty own description shows the group's", function()
        local ET, env = withShared("Ganks lowbies")
        ET:AddEnemy("Ivan Petrov")
        no(ET.sharedView["ivan petrov"], "own list takes over")
        eq(ET:GetTracked("ivan petrov"), ET.db.enemies["ivan petrov"])
        eq(ET:DescriptionOf("ivan petrov"), "Ganks lowbies")
        ET:RemoveEnemy("Ivan Petrov")
        ok(ET.sharedView["ivan petrov"], "still shared by the group after removing it from the own list")
        ET:AddEnemy("Ivan Petrov")
        ET:SetDescription("Ivan Petrov", "Mine")
        eq(ET:DescriptionOf("ivan petrov"), "Mine")
    end },

    { "one entry per player across groups, newest record wins", function()
        local ET, env = withShared("old text")
        ET:JoinGroup(GID2)
        ET:MergeGroupRecord(GID2, "ivan petrov", { name = "Ivan Petrov", faction = "Horde",
            description = "new text", at = env.time() + 5, by = "Boris Lebed" })
        mock.advance(env, 1)
        local v = ET.sharedView["ivan petrov"]
        eq(v.description, "new text")
        eq(v.by, "Boris Lebed")
        eq(#v.groups, 2)
        local n = 0
        for _ in pairs(ET.sharedView) do n = n + 1 end
        eq(n, 1)
    end },

    { "removed records and left groups stop being watched", function()
        local ET, env = withShared("x")
        ET:MergeGroupRecord(GID, "ivan petrov", { name = "Ivan Petrov", description = "", del = true,
            at = env.time() + 1, by = "Anna Kova" })
        mock.advance(env, 1)
        no(ET:GetTracked("ivan petrov"))
        local ET2, env2 = withShared("x")
        ET2:LeaveGroup(GID)
        no(ET2:GetTracked("ivan petrov"))
        H.target(env2, unit("Ivan Petrov"))
        no(env2.EnemyTrackerAlert1:IsShown())
    end },

    { "a shared player already in view is detected when the record arrives", function()
        local ET, env = H.boot()
        ET:JoinGroup(GID)
        H.target(env, unit("Ivan Petrov"))
        no(env.EnemyTrackerAlert1:IsShown())
        ET:MergeGroupRecord(GID, "ivan petrov", { name = "Ivan Petrov", faction = "Horde",
            description = "", at = env.time(), by = "Anna Kova" })
        mock.advance(env, 1)
        ok(env.EnemyTrackerAlert1:IsShown())
        eq(ET.db.enemies["ivan petrov"], nil)
        H.noErrors(env)
    end },
}
