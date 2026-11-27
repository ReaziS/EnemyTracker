-- Forever character names: "First Surname", each part 2-12 letters.
local H = require("harness")
local eq, ok, no = H.eq, H.ok, H.no

return {
    { "accepts a full name with one space and stores it as typed", function()
        local ET, env = H.boot()
        ok(ET:AddEnemy("Ivan Petrov"))
        eq(ET:GetEnemy("ivan petrov").name, "Ivan Petrov")
        H.noErrors(env)
    end },

    { "capitalises each part of a name typed in lower case", function()
        local ET = H.boot()
        ET:AddEnemy("ivan petrov")
        eq(ET:GetEnemy("Ivan Petrov").name, "Ivan Petrov", "surname keeps its capital")
    end },

    { "collapses extra spaces and trims the input", function()
        local ET = H.boot()
        ok(ET:AddEnemy("   Ivan    Petrov  "))
        eq(ET:GetEnemy("Ivan Petrov").name, "Ivan Petrov")
        no(ET:AddEnemy("Ivan  Petrov", true), "same player with two spaces is a duplicate")
        eq(ET:EnemyCount(), 1)
    end },

    { "reads the hyphenated First-Surname form as the same player", function()
        local ET = H.boot()
        ok(ET:AddEnemy("Ivan-Petrov"))
        eq(ET:GetEnemy("Ivan Petrov").name, "Ivan Petrov")
        no(ET:AddEnemy("ivan petrov", true), "duplicate")
    end },

    { "rejects a case-insensitive duplicate", function()
        local ET = H.boot()
        ET:AddEnemy("Ivan Petrov")
        no(ET:AddEnemy("IVAN PETROV", true))
        eq(ET:EnemyCount(), 1)
    end },

    { "rejects empty input, a single word and three words", function()
        local ET, env = H.boot()
        no(ET:AddEnemy("", true), "empty")
        no(ET:AddEnemy("   ", true), "blank")
        no(ET:AddEnemy("Ivan", true), "first name only")
        no(ET:AddEnemy("Ivan Petrov Sidorov", true), "three words")
        eq(ET:EnemyCount(), 0)
        ET:AddEnemy("Ivan")
        ok(H.lastChat(env):find("First Surname", 1, true), "error message explains the format")
    end },

    { "rejects digits, punctuation and parts of the wrong length", function()
        local ET = H.boot()
        no(ET:AddEnemy("Ivan Petr0v", true), "digit")
        no(ET:AddEnemy("Ivan Pet'rov", true), "apostrophe")
        no(ET:AddEnemy("Ivan Petrov!", true), "punctuation")
        no(ET:AddEnemy("I Petrov", true), "1-letter first name")
        no(ET:AddEnemy("Ivan Abcdefghijklm", true), "13-letter surname")
        ok(ET:AddEnemy("Ab Abcdefghijkl", true), "2 and 12 letters are fine")
    end },

    { "accepts accented and Cyrillic names and counts letters, not bytes", function()
        local ET = H.boot()
        ok(ET:AddEnemy("Zoë Müller", true), "accented")
        ok(ET:AddEnemy("Иван Константинов", true), "Cyrillic, 12 letters = 24 bytes")
        eq(ET:GetEnemy("ИВАН КОНСТАНТИНОВ").name, "Иван Константинов")
    end },

    { "adds the current target with first name and surname", function()
        local ET, env = H.boot()
        H.setUnit(env, "target", { name = "Raion", surname = "Lyzl", guid = "Player-2" })
        H.slash(env, "add")
        ok(ET:GetEnemy("Raion Lyzl"), "full name stored")
        no(ET:GetEnemy("Raion"), "not the first name alone")
        H.noErrors(env)
    end },

    { "detects by full name and not by first name alone", function()
        local ET, env = H.boot()
        ET:AddEnemy("Raion Lyzl")
        H.target(env, { name = "Raion", surname = "Other", guid = "Player-3" })
        eq(ET:NearbyCount(), 0, "namesake with another surname")
        H.target(env, { name = "Raion", surname = "Lyzl", guid = "Player-2" })
        eq(ET:NearbyCount(), 1)
    end },

    { "keeps the client's spelling of a detected name", function()
        local ET, env = H.boot()
        ET:AddEnemy("mcduff ohara")
        H.target(env, { name = "McDuff", surname = "OHara", guid = "Player-4" })
        eq(ET:GetEnemy("McDuff OHara").name, "McDuff OHara")
    end },

    { "does not let you add yourself by full name", function()
        local ET = H.boot({ player = { name = "Ivan", surname = "Petrov", guid = "Player-1" } })
        no(ET:AddEnemy("Ivan Petrov", true))
        ok(ET:AddEnemy("Ivan Sidorov", true), "a namesake is fine")
    end },

    { "removes a two-part name with /et remove", function()
        local ET, env = H.boot()
        ET:AddEnemy("Ivan Petrov")
        H.slash(env, "remove ivan petrov")
        H.mock.acceptPopup(env)
        eq(ET:EnemyCount(), 0)
    end },

    { "offers the right-click menu entry for a unit with a surname", function()
        local _, env = H.boot()
        H.setUnit(env, "target", { name = "Raion", surname = "Lyzl", guid = "Player-2" })
        local entries = H.mock.openMenu(env, "MENU_UNIT_TARGET", { unit = "target" })
        local add
        for _, e in ipairs(entries) do if e.fn then add = e end end
        ok(add, "menu entry present")
        add.fn()
        H.noErrors(env)
    end },

    { "offers the menu entry for a chat name, joined or split", function()
        local ET, env = H.boot()
        local entries = H.mock.openMenu(env, "MENU_UNIT_FRIEND", { name = "Raion Lyzl" })
        ok(#entries > 0, "full name in one string")
        entries = H.mock.openMenu(env, "MENU_UNIT_FRIEND", { name = "Raion", server = "Lyzl" })
        local add
        for _, e in ipairs(entries) do if e.fn then add = e end end
        ok(add, "first name + surname in the server field")
        add.fn()
        ok(ET:GetEnemy("Raion Lyzl"), "added with surname")
    end },
}
