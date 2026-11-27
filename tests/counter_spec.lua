-- Nearby counter and its list: clicking a name targets the player.
local H = require("harness")
local mock = H.mock
local eq, ok, no = H.eq, H.ok, H.no

local function enemy(full)
    local first, surname = full:match("^(%S+) (%S+)$")
    return { name = first, surname = surname, faction = "Horde", guid = "Player-" .. full }
end

-- A nameplate of `full` appears as unit nameplate<i>.
local function plate(env, i, full)
    H.setUnit(env, "nameplate" .. i, enemy(full))
    mock.fire(env, "NAME_PLATE_UNIT_ADDED", "nameplate" .. i)
end

-- Detects `full` through the target and opens the list.
local function detectAndOpen(ET, env, full)
    ET:AddEnemy(full, true)
    H.target(env, enemy(full))
    mock.click(env.EnemyTrackerCounter)
    ok(env.EnemyTrackerNearbyList:IsShown(), "list open")
end

local function enterCombat(env)
    mock.fire(env, "PLAYER_REGEN_DISABLED")
    env._state.combat = true
    mock.advance(env, 0)
end

local function leaveCombat(env)
    env._state.combat = false
    mock.fire(env, "PLAYER_REGEN_ENABLED")
end

return {
    { "clicking a name in the list targets that player", function()
        local ET, env = H.boot()
        detectAndOpen(ET, env, "Gorbash Grimfang")
        local b = env.EnemyTrackerNearbyTarget1
        ok(b and b:IsShown(), "secure button over the first row")
        eq(b:GetAttribute("type1"), "macro")
        eq(b:GetAttribute("macrotext1"), "/targetexact Gorbash Grimfang", "full name incl. surname")
        no(env.EnemyTrackerNearbyTarget2:IsShown(), "no button over empty rows")
        eq(env.EnemyTrackerNearbyList.hint:GetText(), ET.L.NEARBY_HINT)
        H.noErrors(env)
    end },

    { "each row targets its own player and follows list changes", function()
        local ET, env = H.boot()
        ET:AddEnemy("Bbb Xx", true)
        ET:AddEnemy("Aaa Xx", true)
        plate(env, 1, "Bbb Xx")
        plate(env, 2, "Aaa Xx")
        mock.click(env.EnemyTrackerCounter)
        eq(env.EnemyTrackerNearbyTarget1:GetAttribute("macrotext1"), "/targetexact Aaa Xx", "sorted by name")
        eq(env.EnemyTrackerNearbyTarget2:GetAttribute("macrotext1"), "/targetexact Bbb Xx")
        ET:ClearNearby()
        no(env.EnemyTrackerNearbyTarget1:IsShown(), "nobody nearby: no buttons")
        H.noErrors(env)
    end },

    { "closing the list removes the buttons", function()
        local ET, env = H.boot()
        detectAndOpen(ET, env, "Gorbash Grimfang")
        mock.click(env.EnemyTrackerCounter)
        no(env.EnemyTrackerNearbyList:IsShown())
        no(env.EnemyTrackerNearbyTarget1:IsShown(), "no invisible clickable area left behind")
    end },

    { "in combat the buttons are hidden without errors and come back after", function()
        local ET, env = H.boot()
        detectAndOpen(ET, env, "Gorbash Grimfang")
        enterCombat(env)
        no(env.EnemyTrackerNearbyTarget1:IsShown(), "hidden before lockdown")
        eq(env.EnemyTrackerNearbyList.hint:GetText(), ET.L.NEARBY_COMBAT)
        -- The list keeps working in combat: changes, closing, reopening.
        ET:AddEnemy("Olga Smirnova", true)
        plate(env, 1, "Olga Smirnova")
        mock.advance(env, 2)
        mock.click(env.EnemyTrackerCounter)
        mock.click(env.EnemyTrackerCounter)
        no(env.EnemyTrackerNearbyTarget1:IsShown())
        H.noErrors(env) -- the mock raises ADDON_ACTION_BLOCKED like the client
        leaveCombat(env)
        ok(env.EnemyTrackerNearbyTarget1:IsShown())
        eq(env.EnemyTrackerNearbyTarget2:GetAttribute("macrotext1"), "/targetexact Olga Smirnova",
            "names set after combat match the rows")
        eq(env.EnemyTrackerNearbyList.hint:GetText(), ET.L.NEARBY_HINT)
    end },

    { "no button reappears between the combat event and the lockdown", function()
        local ET, env = H.boot()
        detectAndOpen(ET, env, "Gorbash Grimfang")
        mock.fire(env, "PLAYER_REGEN_DISABLED") -- lockdown not on yet
        mock.advance(env, 1)                     -- the list refreshes meanwhile
        no(env.EnemyTrackerNearbyTarget1:IsShown())
    end },

    { "rows say where and when the player was seen, in the addon language", function()
        local ET, env = H.boot({ locale = "ruRU" })
        eq(ET.language, "ruRU")
        detectAndOpen(ET, env, "Gorbash Grimfang")
        local row
        for _, w in ipairs(env._state.widgets) do
            local t = w._kind == "FontString" and w:GetText()
            if type(t) == "string" and t:find(ET.L.SRC_target, 1, true) then row = t end
        end
        ok(row, "source shown")
        ok(row:find(ET.L.NEARBY_NOW, 1, true), "just seen")
        no(row:find("target", 1, true), "no English source name")
    end },

    { "more players than rows are summed up", function()
        local ET, env = H.boot()
        local names = { "Aaa Xx", "Bbb Xx", "Ccc Xx", "Ddd Xx", "Eee Xx", "Fff Xx", "Ggg Xx", "Hhh Xx", "Iii Xx", "Jjj Xx" }
        for i, n in ipairs(names) do
            ET:AddEnemy(n, true)
            plate(env, i, n)
        end
        mock.click(env.EnemyTrackerCounter)
        local list = env.EnemyTrackerNearbyList
        ok(list.more:IsShown())
        eq(list.more:GetText(), ET.L.NEARBY_MORE:format(2))
        H.noErrors(env)
    end },
}
