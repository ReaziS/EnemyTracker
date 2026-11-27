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

    { "adding from the target or a unit menu remembers the faction", function()
        local ET, env = H.boot()
        H.target(env, { name = "Petr", surname = "Ivanov", faction = "Alliance", guid = "Player-petr" })
        ET:AddTarget()
        eq(ET.db.enemies["petr ivanov"].faction, "Alliance")
        H.target(env, { name = "Vera", surname = "Orlova", faction = "Horde", guid = "Player-vera" })
        local added = false
        for _, e in ipairs(H.mock.openMenu(env, "MENU_UNIT_TARGET", { unit = "target" })) do
            if e.label == ET.L.MENU_ADD then e.fn() added = true end
        end
        ok(added, "menu offers to add")
        eq(ET.db.enemies["vera orlova"].faction, "Horde")
        ET:AddEnemy("Olga Smirnova", true, "Neutral")
        eq(ET.db.enemies["olga smirnova"].faction, nil, "only real factions are kept")
    end },

    { "the dashboard shows a dash in last seen for your own faction", function()
        local ET, env = H.boot()
        ET:AddEnemy("Petr Ivanov", true, "Alliance")
        ET:AddEnemy("Gorbash Grimfang", true, "Horde")
        ET:AddEnemy("Olga Smirnova", true)
        ET:ShowDashboard()
        local seen = {}
        for i = 1, 3 do
            local row = env["EnemyTrackerDashboardRow" .. i]
            seen[row.key] = row.cols.lastSeen:GetText()
        end
        eq(seen["petr ivanov"], "|cff999999-|r")
        eq(seen["gorbash grimfang"], ET.L.NEVER)
        eq(seen["olga smirnova"], ET.L.NEVER, "unknown faction still shows the time")
    end },
}
