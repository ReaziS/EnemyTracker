local H = require("harness")
local eq, ok, no = H.eq, H.ok, H.no

local function enemy(name) return { name = name, faction = "Horde", guid = "Player-" .. name } end

return {
    { "targeting a blacklisted player alerts once with one sound", function()
        local ET, env = H.boot()
        ET:AddEnemy("Gorbash")
        H.target(env, enemy("Gorbash"))
        eq(ET:NearbyCount(), 1)
        eq(#env._state.sounds, 1)
        ok(env.EnemyTrackerAlert1:IsShown(), "toast shown")
        eq(env.EnemyTrackerAlert1.nameText:GetText(), "Gorbash")
        H.noErrors(env)
    end },

    { "does not repeat the alert while the player stays visible", function()
        local ET, env = H.boot()
        ET:AddEnemy("Gorbash")
        H.target(env, enemy("Gorbash"))
        H.mock.advance(env, 30)
        eq(#env._state.sounds, 1)
        eq(ET:GetEnemy("Gorbash").detections, 1)
    end },

    { "counts a player once when several sources report them", function()
        local ET, env = H.boot()
        ET:AddEnemy("Gorbash")
        local u = enemy("Gorbash")
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
        ET:AddEnemy("Gorbash")
        H.target(env, enemy("Gorbash"))
        env._state.units.target = nil
        H.mock.advance(env, 12)
        eq(ET:NearbyCount(), 0)
        H.target(env, enemy("Gorbash"))
        eq(ET:NearbyCount(), 1)
        eq(ET:GetEnemy("Gorbash").detections, 2)
        eq(#env._state.sounds, 2)
    end },

    { "ignores players who are not blacklisted and non-player units", function()
        local ET, env = H.boot()
        ET:AddEnemy("Gorbash")
        H.target(env, enemy("Stranger"))
        H.target(env, { name = "Gorbash", player = false })
        eq(ET:NearbyCount(), 0)
    end },

    { "treats secret unit names as no data", function()
        local ET, env = H.boot()
        ET:AddEnemy("Gorbash")
        H.target(env, { name = "Gorbash", secretName = true })
        eq(ET:NearbyCount(), 0)
        H.noErrors(env)
    end },

    { "detects nothing while scanning is off", function()
        local ET, env = H.boot()
        ET:AddEnemy("Gorbash")
        H.slash(env, "off")
        H.target(env, enemy("Gorbash"))
        eq(ET:NearbyCount(), 0)
        H.slash(env, "on")
        eq(ET:NearbyCount(), 1, "rescanned when turned back on")
    end },
}
