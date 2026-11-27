-- Versioned data model and migration of older saves.
local H = require("harness")
local eq, ok, no = H.eq, H.ok, H.no

-- A save written by v0.1.1 (schema 1).
local function v1Save()
    return {
        version = 1,
        enemies = {
            ["ivan petrov"] = { name = "Ivan Petrov", killedMe = 4, iKilled = 2, detections = 7,
                addedAt = 1700000000, lastSeen = 1700000500, custom = "kept" },
            ["raion"] = { name = "Raion", killedMe = 1, iKilled = 0, detections = 3,
                addedAt = 1700000100, lastSeen = 0 },
        },
        settings = { sound = false, scale = 1.5 },
        positions = { alerts = { x = 10, y = 20 } },
        minimap = { angle = 90 },
    }
end

return {
    { "a fresh install starts at the current schema version", function()
        local ET = H.boot()
        eq(ET.db.schemaVersion, ET.SCHEMA_VERSION)
        eq(ET.db.schemaVersion, 2)
        no(ET.db.version, "old version field not written")
    end },

    { "new records follow the schema", function()
        local ET = H.boot()
        ET:AddEnemy("Ivan Petrov")
        local e = ET:GetEnemy("Ivan Petrov")
        ok(type(e.id) == "string" and #e.id > 0, "id")
        eq(e.description, "")
        eq(e.stats.killedMe, 0); eq(e.stats.iKilled, 0); eq(e.stats.detections, 0)
        eq(e.lastSeen, 0)
        ok(e.addedAt > 0)
        no(e.needsSurname)
    end },

    { "migrates a v0.1.1 save without losing data", function()
        local ET, env = H.boot({ savedDB = v1Save() })
        H.noErrors(env)
        eq(ET.db.schemaVersion, 2)
        no(ET.db.version, "old version field removed")
        local e = ET:GetEnemy("Ivan Petrov")
        eq(e.stats.killedMe, 4); eq(e.stats.iKilled, 2); eq(e.stats.detections, 7)
        no(e.killedMe, "top-level counters moved")
        eq(e.addedAt, 1700000000); eq(e.lastSeen, 1700000500)
        eq(e.description, "")
        ok(e.id, "id assigned")
        eq(e.custom, "kept", "unknown fields preserved")
        eq(ET.db.settings.sound, false, "settings kept")
        eq(ET.db.settings.scale, 1.5)
        eq(ET.db.positions.alerts.x, 10, "positions kept")
        eq(ET.db.minimap.angle, 90)
    end },

    { "flags legacy first-name-only records", function()
        local ET = H.boot({ savedDB = v1Save() })
        ok(ET:GetEnemy("Raion").needsSurname, "single word flagged")
        no(ET:GetEnemy("Ivan Petrov").needsSurname)
    end },

    { "keeps ids stable and does not migrate twice across reloads", function()
        local ET, env = H.boot({ savedDB = v1Save() })
        local id = ET:GetEnemy("Ivan Petrov").id
        local ET2 = H.reboot(env)
        local e = ET2:GetEnemy("Ivan Petrov")
        eq(e.id, id)
        eq(e.stats.killedMe, 4, "counters not doubled")
    end },

    { "gives every record a different id", function()
        local ET = H.boot()
        local seen = {}
        local letters = "abcdefghijklmnopqrstuvwxyz"
        for i = 1, 50 do
            local a, b = i % 26 + 1, math.floor(i / 26) + 1
            ok(ET:AddEnemy("Name Xx" .. letters:sub(a, a) .. letters:sub(b, b), true), "added " .. i)
        end
        local n = 0
        for _, e in pairs(ET.db.enemies) do
            no(seen[e.id], "duplicate id " .. e.id)
            seen[e.id] = true
            n = n + 1
        end
        ok(n > 1)
    end },

    { "keeps a known faction and drops an invalid one", function()
        local ET = H.boot({ savedDB = { schemaVersion = 2, enemies = {
            a = { name = "Ivan Petrov", faction = "Horde" },
            b = { name = "Petr Ivanov", faction = "Murlocs" },
        } } })
        eq(ET:GetEnemy("Ivan Petrov").faction, "Horde")
        no(ET:GetEnemy("Petr Ivanov").faction)
        eq(ET:GetEnemy("Petr Ivanov").stats.detections, 0, "missing stats filled")
    end },

    { "the dashboard renders migrated records", function()
        local ET, env = H.boot({ savedDB = v1Save() })
        ET:ShowDashboard()
        H.noErrors(env)
        ok(env.EnemyTrackerDashboard:IsShown())
    end },
}
