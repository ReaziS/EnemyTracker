local H = require("harness")
local eq, ok, no = H.eq, H.ok, H.no

return {
    { "boots without errors and registers the slash command", function()
        local ET, env = H.boot()
        H.noErrors(env)
        ok(env.SlashCmdList.ENEMYTRACKER, "slash handler")
        eq(env.SLASH_ENEMYTRACKER1, "/et")
        ok(ET.db, "database ready")
    end },

    { "registers the options panel in Interface > AddOns", function()
        local _, env = H.boot()
        eq(#env._state.settingsCategories, 1)
        eq(env._state.settingsCategories[1].name, "Enemy Tracker")
    end },

    { "fills default settings on an empty SavedVariables", function()
        local ET = H.boot()
        ok(ET.db.settings.scanEnabled, "scanning on by default")
        ok(ET.db.settings.visual)
        ok(ET.db.settings.sound)
        eq(ET:EnemyCount(), 0)
    end },

    { "switches kill statistics off when the client has no combat log API", function()
        local ET, env = H.boot()
        eq(ET.combatLogAvailable, false)
        no(env._state.eventFrames.COMBAT_LOG_EVENT_UNFILTERED, "CLEU not registered")
        H.noErrors(env)
    end },
}
