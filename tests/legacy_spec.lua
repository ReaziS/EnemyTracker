-- Records saved by v0.1.1 with the first name only get their surname
-- confirmed by the user on the first encounter.
local H = require("harness")
local eq, ok, no = H.eq, H.ok, H.no

local function legacySave(extra)
    local enemies = {
        raion = { name = "Raion", killedMe = 2, iKilled = 1, detections = 5, addedAt = 1700000000, lastSeen = 0 },
    }
    for k, v in pairs(extra or {}) do enemies[k] = v end
    return { version = 1, enemies = enemies }
end

local RAION_LYZL = { name = "Raion", surname = "Lyzl", guid = "Player-2" }

return {
    { "a first-name-only record alerts for a player with that first name", function()
        local ET, env = H.boot({ savedDB = legacySave() })
        H.target(env, RAION_LYZL)
        eq(ET:NearbyCount(), 1)
        eq(env.EnemyTrackerAlert1.nameText:GetText(), "Raion Lyzl", "toast shows the full name seen")
        eq(env.EnemyTrackerTargetButton1:GetAttribute("macrotext1"), "/targetexact Raion Lyzl")
        H.noErrors(env)
    end },

    { "asks once whether the seen player is the one in the record", function()
        local _, env = H.boot({ savedDB = legacySave() })
        H.target(env, RAION_LYZL)
        local popups = env._state.popups
        eq(#popups, 1)
        eq(popups[1].which, "ENEMYTRACKER_CONFIRM_SURNAME")
        ok(popups[1].text:find("Raion Lyzl", 1, true), "question names the full name")
        env._state.units.target = nil
        H.mock.advance(env, 15)
        H.target(env, RAION_LYZL)
        eq(#popups, 1, "not asked again in the same session")
    end },

    { "Yes gives the record the surname and keeps its statistics", function()
        local ET, env = H.boot({ savedDB = legacySave() })
        H.target(env, RAION_LYZL)
        H.mock.acceptPopup(env)
        no(ET:GetEnemy("Raion"), "old key gone")
        local e = ET:GetEnemy("Raion Lyzl")
        ok(e, "renamed")
        no(e.needsSurname)
        eq(e.stats.killedMe, 2); eq(e.stats.iKilled, 1)
        eq(e.stats.detections, 6, "old detections + this one")
        eq(ET:NearbyCount(), 1, "still counted once")
        ok(ET.nearby["raion lyzl"], "nearby entry moved to the new key")
        eq(env.EnemyTrackerAlert1.nameText:GetText(), "Raion Lyzl")
        H.noErrors(env)
    end },

    { "No stops matching that player and drops the alert", function()
        local ET, env = H.boot({ savedDB = legacySave() })
        H.target(env, RAION_LYZL)
        H.mock.declinePopup(env)
        eq(ET:NearbyCount(), 0)
        no(env.EnemyTrackerAlert1:IsShown(), "toast closed")
        ok(ET:GetEnemy("Raion").needsSurname, "record kept")
        H.mock.advance(env, 15)
        H.target(env, RAION_LYZL)
        eq(ET:NearbyCount(), 0, "rejected namesake ignored")
        H.target(env, { name = "Raion", surname = "Other", guid = "Player-9" })
        eq(ET:NearbyCount(), 1, "another namesake still matches")
        eq(#env._state.popups, 1, "and is asked about")
    end },

    { "remembers a No across a reload", function()
        local ET, env = H.boot({ savedDB = legacySave() })
        H.target(env, RAION_LYZL)
        H.mock.declinePopup(env)
        local ET2, env2 = H.reboot(env)
        H.target(env2, RAION_LYZL)
        eq(ET2:NearbyCount(), 0)
    end },

    { "an exact full-name record wins over the legacy one", function()
        local ET, env = H.boot({ savedDB = legacySave({
            ["raion lyzl"] = { name = "Raion Lyzl", killedMe = 0, iKilled = 0, detections = 0 },
        }) })
        H.target(env, RAION_LYZL)
        ok(ET.nearby["raion lyzl"])
        no(ET.nearby["raion"])
        eq(#env._state.popups, 0, "no question")
    end },

    { "Yes merges into an existing full-name record", function()
        local ET, env = H.boot({ savedDB = legacySave() })
        H.target(env, RAION_LYZL)
        ET:AddEnemy("Raion Lyzl", true)
        H.mock.acceptPopup(env)
        eq(ET:EnemyCount(), 1)
        eq(ET:GetEnemy("Raion Lyzl").stats.killedMe, 2, "legacy stats merged")
    end },

    { "the dashboard marks records without a surname", function()
        local ET, env = H.boot({ savedDB = legacySave() })
        ET:ShowDashboard()
        local found = false
        for _, w in ipairs(env._state.widgets) do
            local t = w._text
            if type(t) == "string" and t:find("Raion", 1, true) and t:find(ET.L.NO_SURNAME, 1, true) then
                found = true
            end
        end
        ok(found, "row text carries the marker")
    end },
}
