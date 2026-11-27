local H = require("harness")
local eq, ok, no = H.eq, H.ok, H.no

local function enemy(full)
    local first, surname = full:match("^(%S+) (%S+)$")
    return { name = first, surname = surname, faction = "Horde", guid = "Player-" .. full }
end

return {
    { "targeting a blacklisted player alerts once with one sound", function()
        local ET, env = H.boot()
        ET:AddEnemy("Gorbash Grimfang")
        H.target(env, enemy("Gorbash Grimfang"))
        eq(ET:NearbyCount(), 1)
        eq(#env._state.sounds, 1)
        ok(env.EnemyTrackerAlert1:IsShown(), "toast shown")
        eq(env.EnemyTrackerAlert1.nameText:GetText(), "Gorbash Grimfang")
        H.noErrors(env)
    end },

    { "does not repeat the alert while the player stays visible", function()
        local ET, env = H.boot()
        ET:AddEnemy("Gorbash Grimfang")
        H.target(env, enemy("Gorbash Grimfang"))
        H.mock.advance(env, 30)
        eq(#env._state.sounds, 1)
        eq(ET:GetEnemy("Gorbash Grimfang").stats.detections, 1)
    end },

    { "counts a player once when several sources report them", function()
        local ET, env = H.boot()
        ET:AddEnemy("Gorbash Grimfang")
        local u = enemy("Gorbash Grimfang")
        H.setUnit(env, "nameplate1", u)
        env._state.plates = { "nameplate1" }
        H.setUnit(env, "mouseover", u)
        H.target(env, u)
        H.mock.fire(env, "UPDATE_MOUSEOVER_UNIT")
        H.mock.advance(env, 1)
        eq(ET:NearbyCount(), 1)
        eq(#env._state.sounds, 1)
    end },

    { "drops a player after 10 s unseen and alerts again when they return", function()
        local ET, env = H.boot()
        ET:AddEnemy("Gorbash Grimfang")
        H.target(env, enemy("Gorbash Grimfang"))
        env._state.units.target = nil
        H.mock.advance(env, 12)
        eq(ET:NearbyCount(), 0)
        H.target(env, enemy("Gorbash Grimfang"))
        eq(ET:NearbyCount(), 1)
        eq(ET:GetEnemy("Gorbash Grimfang").stats.detections, 2)
        eq(#env._state.sounds, 2)
    end },

    { "ignores players who are not blacklisted and non-player units", function()
        local ET, env = H.boot()
        ET:AddEnemy("Gorbash Grimfang")
        H.target(env, enemy("Stranger Danger"))
        H.target(env, { name = "Gorbash", surname = "Grimfang", player = false })
        eq(ET:NearbyCount(), 0)
    end },

    { "treats secret unit names as no data", function()
        local ET, env = H.boot()
        ET:AddEnemy("Gorbash Grimfang")
        H.target(env, { name = "Gorbash", surname = "Grimfang", secretName = true })
        eq(ET:NearbyCount(), 0)
        H.noErrors(env)
    end },

    { "detects nothing while scanning is off", function()
        local ET, env = H.boot()
        ET:AddEnemy("Gorbash Grimfang")
        H.slash(env, "off")
        H.target(env, enemy("Gorbash Grimfang"))
        eq(ET:NearbyCount(), 0)
        H.slash(env, "on")
        eq(ET:NearbyCount(), 1, "rescanned when turned back on")
    end },
}
