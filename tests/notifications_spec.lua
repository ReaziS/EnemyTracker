local H = require("harness")
local eq, ok, no = H.eq, H.ok, H.no

local function enemy(name) return { name = name, faction = "Horde", guid = "Player-" .. name } end

return {
    { "the toast's secure overlay targets the player by exact name", function()
        local ET, env = H.boot()
        ET:AddEnemy("Gorbash")
        H.target(env, enemy("Gorbash"))
        local b = env.EnemyTrackerTargetButton1
        ok(b:IsShown(), "overlay attached")
        eq(b:GetAttribute("type1"), "macro")
        eq(b:GetAttribute("macrotext1"), "/targetexact Gorbash")
    end },

    { "alerts raised in combat are not clickable until combat ends", function()
        local ET, env = H.boot()
        ET:AddEnemy("Gorbash")
        H.mock.fire(env, "PLAYER_REGEN_DISABLED")
        env._state.combat = true
        H.mock.advance(env, 0)
        H.target(env, enemy("Gorbash"))
        local t = env.EnemyTrackerAlert1
        ok(t:IsShown(), "toast still shown in combat")
        no(env.EnemyTrackerTargetButton1:IsShown(), "overlay not attached in combat")
        eq(t.hint:GetText(), ET.L.ALERT_COMBAT)
        env._state.combat = false
        H.mock.fire(env, "PLAYER_REGEN_ENABLED")
        ok(env.EnemyTrackerTargetButton1:IsShown(), "overlay attached after combat")
        H.noErrors(env)
    end },

    { "close button hides the toast", function()
        local ET, env = H.boot()
        ET:AddEnemy("Gorbash")
        H.target(env, enemy("Gorbash"))
        ET:CloseToast(env.EnemyTrackerAlert1)
        no(env.EnemyTrackerAlert1:IsShown())
    end },

    { "shows four toasts at most and queues the rest", function()
        local ET, env = H.boot()
        local names = { "Aaa", "Bbb", "Ccc", "Ddd", "Eee" }
        for _, n in ipairs(names) do ET:AddEnemy(n, true) end
        for i, n in ipairs(names) do
            H.setUnit(env, "nameplate" .. i, enemy(n))
            H.mock.fire(env, "NAME_PLATE_UNIT_ADDED", "nameplate" .. i)
        end
        eq(ET:NearbyCount(), 5)
        for i = 1, 4 do ok(env["EnemyTrackerAlert" .. i]:IsShown(), "toast " .. i) end
        ET:CloseToast(env.EnemyTrackerAlert1)
        ok(env.EnemyTrackerAlert1:IsShown(), "queued alert takes the freed slot")
        eq(env.EnemyTrackerAlert1.nameText:GetText(), "Eee")
    end },

    { "sound and visual alerts can be switched off independently", function()
        local ET, env = H.boot()
        ET:AddEnemy("Gorbash")
        ET.db.settings.sound = false
        H.target(env, enemy("Gorbash"))
        eq(#env._state.sounds, 0, "no sound")
        ok(env.EnemyTrackerAlert1:IsShown(), "visual still shown")

        local ET2, env2 = H.boot()
        ET2:AddEnemy("Gorbash")
        ET2.db.settings.visual = false
        H.target(env2, enemy("Gorbash"))
        eq(#env2._state.sounds, 1, "sound still played")
        no(env2.EnemyTrackerAlert1:IsShown(), "no visual")
    end },
}
