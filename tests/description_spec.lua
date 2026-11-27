-- One description per player: who they are and what they did.
local H = require("harness")
local eq, ok, no = H.eq, H.ok, H.no

return {
    { "saves a trimmed description and keeps it across a reload", function()
        local ET, env = H.boot()
        ET:AddEnemy("Ivan Petrov")
        ok(ET:SetDescription("ivan petrov", "  Ganks lowbies   in Westfall  "))
        eq(ET:GetEnemy("Ivan Petrov").description, "Ganks lowbies in Westfall")
        local ET2 = H.reboot(env)
        eq(ET2:GetEnemy("Ivan Petrov").description, "Ganks lowbies in Westfall")
    end },

    { "keeps a single line and caps the length in characters", function()
        local ET = H.boot()
        ET:AddEnemy("Ivan Petrov")
        ET:SetDescription("Ivan Petrov", "line one\nline two")
        eq(ET:GetEnemy("Ivan Petrov").description, "line one line two")
        ET:SetDescription("Ivan Petrov", string.rep("я", 250))
        local d = ET:GetEnemy("Ivan Petrov").description
        eq(#d, 400, "200 Cyrillic characters, none cut in half")
    end },

    { "empty text clears the description", function()
        local ET = H.boot()
        ET:AddEnemy("Ivan Petrov")
        ET:SetDescription("Ivan Petrov", "x")
        ET:SetDescription("Ivan Petrov", "   ")
        eq(ET:GetEnemy("Ivan Petrov").description, "")
    end },

    { "reports an unknown player", function()
        local ET, env = H.boot()
        no(ET:SetDescription("Nobody Here", "text"))
        ok(H.chatContains(env, "Nobody Here"))
    end },

    { "/et note sets and clears a description, in either name form", function()
        local ET, env = H.boot()
        ET:AddEnemy("Ivan Petrov")
        H.slash(env, "note Ivan Petrov Killed me twice at the crossroads")
        eq(ET:GetEnemy("Ivan Petrov").description, "Killed me twice at the crossroads")
        H.slash(env, "note Ivan-Petrov Camps the flight master")
        eq(ET:GetEnemy("Ivan Petrov").description, "Camps the flight master")
        H.slash(env, "note Ivan Petrov")
        eq(ET:GetEnemy("Ivan Petrov").description, "")
        H.noErrors(env)
    end },

    { "the dashboard edits the selected player's description", function()
        local ET, env = H.boot()
        ET:AddEnemy("Ivan Petrov")
        ET:SetDescription("Ivan Petrov", "old")
        ET:ShowDashboard()
        local box = env.EnemyTrackerDashboardDescription
        no(box:IsEnabled(), "disabled with nothing selected")
        H.mock.click(env.EnemyTrackerDashboardRow1)
        ok(box:IsEnabled())
        eq(box:GetText(), "old", "loads the selected player's text")
        box:SetText("new text")
        box:RunScript("OnEnterPressed")
        eq(ET:GetEnemy("Ivan Petrov").description, "new text")
        H.noErrors(env)
    end },

    { "the dashboard does not overwrite text being typed on refresh", function()
        local ET, env = H.boot()
        ET:AddEnemy("Ivan Petrov")
        ET:ShowDashboard()
        H.mock.click(env.EnemyTrackerDashboardRow1)
        local box = env.EnemyTrackerDashboardDescription
        box:SetText("half-typed")
        H.target(env, { name = "Ivan", surname = "Petrov", faction = "Horde", guid = "Player-2" })
        eq(box:GetText(), "half-typed", "a detection refresh keeps the draft")
    end },

    { "escapes UI codes when showing a description", function()
        local ET = H.boot()
        eq(ET.EscapeText("|cffff0000red|r"), "||cffff0000red||r")
    end },
}
