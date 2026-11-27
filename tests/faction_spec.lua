-- Alerts only for the opposing faction; the blacklist itself stays shared.
local H = require("harness")
local eq, ok, no = H.eq, H.ok, H.no

local function player(full, faction)
    local first, surname = full:match("^(%S+) (%S+)$")
    return { name = first, surname = surname, faction = faction, guid = "Player-" .. full }
end

local ALLIANCE_ME = { name = "Me", surname = "Myself", faction = "Alliance", guid = "Player-1" }
local HORDE_ME = { name = "Me", surname = "Myself", faction = "Horde", guid = "Player-1" }

return {
    { "an Alliance player is alerted about a blacklisted Horde player", function()
        local ET, env = H.boot({ player = ALLIANCE_ME })
        ET:AddEnemy("Gorbash Grimfang")
        H.target(env, player("Gorbash Grimfang", "Horde"))
        ok(env.EnemyTrackerAlert1:IsShown())
        eq(#env._state.sounds, 1)
    end },

    { "a Horde player is alerted about a blacklisted Alliance player", function()
        local ET, env = H.boot({ player = HORDE_ME })
        ET:AddEnemy("Anna Lightway")
        H.target(env, player("Anna Lightway", "Alliance"))
        ok(env.EnemyTrackerAlert1:IsShown())
        eq(#env._state.sounds, 1)
    end },

    { "a blacklisted player of your own faction raises no alert or sound", function()
        local ET, env = H.boot({ player = ALLIANCE_ME })
        ET:AddEnemy("Anna Lightway")
        H.target(env, player("Anna Lightway", "Alliance"))
        no(env.EnemyTrackerAlert1:IsShown(), "no toast")
        eq(#env._state.sounds, 0, "no sound")
        no(H.chatContains(env, ET.L.ALERT_TITLE), "no chat alert")
        H.noErrors(env)
    end },

    { "an ally stays on the list and is still tracked", function()
        local ET, env = H.boot({ player = ALLIANCE_ME })
        ok(ET:AddEnemy("Anna Lightway"), "allies can be added")
        H.target(env, player("Anna Lightway", "Alliance"))
        local e = ET:GetEnemy("Anna Lightway")
        eq(e.stats.detections, 1)
        ok(e.lastSeen > 0, "last seen updated")
        eq(ET:NearbyCount(), 1, "shown in the nearby list")
    end },

    { "remembers a player's faction in their record", function()
        local ET, env = H.boot({ player = ALLIANCE_ME })
        ET:AddEnemy("Gorbash Grimfang")
        H.target(env, player("Gorbash Grimfang", "Horde"))
        eq(ET:GetEnemy("Gorbash Grimfang").faction, "Horde")
        local ET2 = H.reboot(env)
        eq(ET2:GetEnemy("Gorbash Grimfang").faction, "Horde", "persisted")
    end },

    { "alerts when the faction is unknown", function()
        local ET, env = H.boot({ player = ALLIANCE_ME })
        ET:AddEnemy("Gorbash Grimfang")
        H.target(env, player("Gorbash Grimfang", nil))
        ok(env.EnemyTrackerAlert1:IsShown())
    end },

    { "ignores a hidden (secret) faction value", function()
        local ET, env = H.boot({ player = ALLIANCE_ME })
        ET:AddEnemy("Anna Lightway")
        H.target(env, player("Anna Lightway", H.mock.SECRET))
        ok(env.EnemyTrackerAlert1:IsShown(), "treated as unknown")
        no(ET:GetEnemy("Anna Lightway").faction, "not stored")
        H.noErrors(env)
    end },
}
