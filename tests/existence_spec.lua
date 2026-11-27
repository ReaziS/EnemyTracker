-- Manually typed names are checked against players seen this session.
local H = require("harness")
local eq, ok, no = H.eq, H.ok, H.no

return {
    { "adds a typed name at once if the player was seen this session", function()
        local ET, env = H.boot()
        H.setUnit(env, "mouseover", { name = "Raion", surname = "Lyzl", faction = "Horde", guid = "P2" })
        H.mock.fire(env, "UPDATE_MOUSEOVER_UNIT")
        H.slash(env, "add raion lyzl")
        ok(ET:GetEnemy("Raion Lyzl"), "added without a question")
        eq(#env._state.popups, 0)
    end },

    { "counts chat authors as seen", function()
        local ET, env = H.boot()
        H.mock.fire(env, "CHAT_MSG_CHANNEL", "wts stuff", "Raion Lyzl")
        eq(ET:AddEnemyManual("Raion Lyzl"), true)
    end },

    { "asks before adding a name nobody has seen", function()
        local ET, env = H.boot()
        eq(ET:AddEnemyManual("Raoin Lyzl"), "pending")
        no(ET:GetEnemy("Raoin Lyzl"), "not added yet")
        local p = env._state.popups[1]
        eq(p.which, "ENEMYTRACKER_CONFIRM_UNSEEN")
        ok(p.text:find("Raoin Lyzl", 1, true))
        H.mock.acceptPopup(env)
        ok(ET:GetEnemy("Raoin Lyzl"), "added after Yes")
    end },

    { "adds nothing when the user says No", function()
        local ET, env = H.boot()
        ET:AddEnemyManual("Raoin Lyzl")
        H.mock.declinePopup(env)
        eq(ET:EnemyCount(), 0)
    end },

    { "remembers names even while scanning is off", function()
        local ET, env = H.boot()
        H.slash(env, "off")
        H.target(env, { name = "Raion", surname = "Lyzl", guid = "P2" })
        ok(ET:IsKnownName("Raion Lyzl"))
    end },

    { "still rejects invalid names, duplicates and yourself first", function()
        local ET, env = H.boot()
        eq(ET:AddEnemyManual("Raion"), false, "single word")
        eq(ET:AddEnemyManual("Me Myself"), false, "yourself")
        ET:AddEnemy("Raion Lyzl", true)
        eq(ET:AddEnemyManual("Raion Lyzl"), false, "duplicate")
        eq(#env._state.popups, 0, "no question for any of these")
    end },

    { "the dashboard Add button uses the check", function()
        local ET, env = H.boot()
        ET:ShowDashboard()
        local box = env.EnemyTrackerDashboardAddBox
        box:SetText("Raoin Lyzl")
        box:RunScript("OnEnterPressed")
        eq(#env._state.popups, 1, "asked")
        no(ET:GetEnemy("Raoin Lyzl"))
        H.noErrors(env)
    end },

    { "adding the current target needs no question", function()
        local ET, env = H.boot()
        H.setUnit(env, "target", { name = "Raion", surname = "Lyzl", guid = "P2" })
        H.slash(env, "add")
        ok(ET:GetEnemy("Raion Lyzl"))
        eq(#env._state.popups, 0)
    end },
}
