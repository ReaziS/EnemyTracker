-- Corner note with the player's description on detection.
local H = require("harness")
local eq, ok, no = H.eq, H.ok, H.no

local function horde(full)
    local first, surname = full:match("^(%S+) (%S+)$")
    return { name = first, surname = surname, faction = "Horde", guid = "Player-" .. full }
end

local function bootWith(desc, opts)
    local ET, env = H.boot(opts)
    ET:AddEnemy("Ivan Petrov", true)
    if desc then ET:SetDescription("Ivan Petrov", desc) end
    return ET, env
end

return {
    { "shows the description of a detected enemy in a corner note", function()
        local _, env = bootWith("Camps the flight master")
        H.target(env, horde("Ivan Petrov"))
        local n = env.EnemyTrackerNote1
        ok(n:IsShown())
        eq(n.title:GetText(), "Ivan Petrov")
        eq(n.text:GetText(), "Camps the flight master")
        H.noErrors(env)
    end },

    { "shows nothing when the description is empty", function()
        local _, env = bootWith(nil)
        H.target(env, horde("Ivan Petrov"))
        no(env.EnemyTrackerNote1:IsShown())
    end },

    { "shows nothing for a player of your own faction", function()
        local _, env = bootWith("Ally note")
        local u = horde("Ivan Petrov"); u.faction = "Alliance"
        H.target(env, u)
        no(env.EnemyTrackerNote1:IsShown())
    end },

    { "can be switched off", function()
        local ET, env = bootWith("text")
        ET.db.settings.noteEnabled = false
        H.target(env, horde("Ivan Petrov"))
        no(env.EnemyTrackerNote1:IsShown())
    end },

    { "hides after the configured time, or stays with 0", function()
        local ET, env = bootWith("text")
        ET.db.settings.noteDuration = 5
        H.target(env, horde("Ivan Petrov"))
        H.mock.advance(env, 4)
        ok(env.EnemyTrackerNote1:IsShown(), "still shown at 4 s")
        H.mock.advance(env, 2)
        no(env.EnemyTrackerNote1:IsShown(), "gone after 5 s")

        local ET2, env2 = bootWith("text")
        ET2.db.settings.noteDuration = 0
        H.target(env2, horde("Ivan Petrov"))
        H.mock.advance(env2, 120)
        ok(env2.EnemyTrackerNote1:IsShown(), "0 = until clicked")
        H.mock.click(env2.EnemyTrackerNote1)
        no(env2.EnemyTrackerNote1:IsShown(), "click closes")
    end },

    { "moves to the chosen corner and resizes at once", function()
        local ET, env = bootWith("text")
        ET.db.settings.noteCorner = "TOPLEFT"
        ET:Fire("SETTINGS_CHANGED", "noteCorner")
        eq((env.EnemyTrackerNoteAnchor:GetPoint(1)), "TOPLEFT")
        ET.db.settings.noteScale = 1.5
        ET:Fire("SETTINGS_CHANGED", "noteScale")
        eq(env.EnemyTrackerNoteAnchor:GetScale(), 1.5)
    end },

    { "repairs an unknown saved corner", function()
        local ET = H.boot({ savedDB = { schemaVersion = 2, enemies = {}, settings = { noteCorner = "MIDDLE" } } })
        eq(ET.db.settings.noteCorner, "BOTTOMRIGHT")
    end },

    { "keeps at most three notes, replacing the oldest", function()
        local ET, env = H.boot()
        local names = { "Aaa Xx", "Bbb Xx", "Ccc Xx", "Ddd Xx" }
        for i, n in ipairs(names) do
            ET:AddEnemy(n, true)
            ET:SetDescription(n, "note " .. i)
            H.setUnit(env, "nameplate" .. i, horde(n))
            H.mock.fire(env, "NAME_PLATE_UNIT_ADDED", "nameplate" .. i)
        end
        local shown = {}
        for i = 1, 3 do
            local n = env["EnemyTrackerNote" .. i]
            ok(n:IsShown())
            shown[n.title:GetText()] = true
        end
        no(shown["Aaa Xx"], "oldest replaced")
        ok(shown["Ddd Xx"], "newest shown")
        no(env.EnemyTrackerNote4, "no fourth frame created")
    end },

    { "shows a sample note for the options test button", function()
        local ET, env = H.boot()
        ET:TestDescriptionNote()
        ok(env.EnemyTrackerNote1:IsShown())
        H.noErrors(env)
    end },
}
