local H = require("harness")
local eq, ok, no = H.eq, H.ok, H.no

return {
    { "adds a player with /et add and rejects a case-insensitive duplicate", function()
        local ET, env = H.boot()
        H.slash(env, "add Gorbash Grimfang")
        H.mock.acceptPopup(env) -- not seen this session: confirm
        ok(ET:GetEnemy("gorbash grimfang"), "added")
        H.slash(env, "add GORBASH GRIMFANG")
        eq(ET:EnemyCount(), 1)
        ok(H.chatContains(env, "already"), "duplicate reported")
        H.noErrors(env)
    end },

    { "keys Cyrillic names case-insensitively", function()
        local ET, env = H.boot()
        ok(ET:AddEnemy("Злыдень Мрачный"))
        ok(ET:GetEnemy("ЗЛЫДЕНЬ МРАЧНЫЙ"), "upper-case lookup")
        no(ET:AddEnemy("злыдень мрачный", true), "duplicate in lower case")
        H.noErrors(env)
    end },

    { "refuses to add yourself", function()
        local ET = H.boot({ player = { name = "Selfie", surname = "Selfsson", guid = "Player-1" } })
        no(ET:AddEnemy("Selfie Selfsson", true))
    end },

    { "removes a player and their statistics only after confirmation", function()
        local ET, env = H.boot()
        ET:AddEnemy("Gorbash Grimfang")
        H.slash(env, "remove Gorbash Grimfang")
        ok(ET:GetEnemy("Gorbash Grimfang"), "still there before confirming")
        H.mock.acceptPopup(env)
        no(ET:GetEnemy("Gorbash Grimfang"), "removed after confirming")
    end },

    { "clear stats resets counters but keeps the entry, last seen and date added", function()
        local ET, env = H.boot()
        ET:AddEnemy("Gorbash Grimfang")
        local e = ET:GetEnemy("Gorbash Grimfang")
        e.stats.killedMe, e.stats.iKilled, e.stats.detections, e.lastSeen = 3, 2, 5, 12345
        local added = e.addedAt
        H.slash(env, "clear Gorbash Grimfang")
        H.mock.acceptPopup(env)
        eq(e.stats.killedMe, 0); eq(e.stats.iKilled, 0); eq(e.stats.detections, 0)
        eq(e.lastSeen, 12345)
        eq(e.addedAt, added)
        ok(ET:GetEnemy("Gorbash Grimfang"), "still listed")
    end },

    { "keeps the blacklist across a reload", function()
        local ET, env = H.boot()
        ET:AddEnemy("Gorbash Grimfang")
        local ET2, env2 = H.reboot(env)
        ok(ET2:GetEnemy("Gorbash Grimfang"), "persisted")
        H.noErrors(env2)
    end },

    { "merges duplicate entries found in old saved data", function()
        local ET = H.boot({ savedDB = { enemies = {
            a = { name = "Gorbash Grimfang", killedMe = 1, iKilled = 0, addedAt = 50, lastSeen = 10 },
            b = { name = "GORBASH GRIMFANG", killedMe = 2, iKilled = 1, addedAt = 40, lastSeen = 90 },
        } } })
        eq(ET:EnemyCount(), 1)
        local e = ET:GetEnemy("gorbash grimfang")
        eq(e.stats.killedMe, 3); eq(e.stats.iKilled, 1); eq(e.addedAt, 40); eq(e.lastSeen, 90)
    end },
}
