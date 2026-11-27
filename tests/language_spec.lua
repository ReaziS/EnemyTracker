-- Localisation: complete English and Russian, switchable in the addon.
local H = require("harness")
local mock = H.mock
local eq, ok, no = H.eq, H.ok, H.no

-- Every text shown by a widget.
local function widgetTexts(env)
    local out = {}
    for _, w in ipairs(env._state.widgets) do
        local t = w._text
        if type(t) == "string" and t ~= "" then out[#out + 1] = t end
    end
    return out
end

-- Opens every window the addon has.
local function openEverything(ET, env)
    ET:AddEnemy("Ivan Petrov", true)
    ET:SetDescription("Ivan Petrov", "x")
    ET:ShowDashboard()
    ET:ToggleGroupsPanel()
    ET:TestAlert()
    ET:TestDescriptionNote()
    env.EnemyTrackerOptionsPanel:RunScript("OnShow")
    H.target(env, { name = "Ivan", surname = "Petrov", faction = "Horde", guid = "Player-ivan" })
end

return {
    { "every English string has a Russian translation and vice versa", function()
        local ET = H.boot()
        local EN, RU = ET._locales.enUS, ET._locales.ruRU
        local missing, extra = {}, {}
        for k in pairs(EN) do
            if RU[k] == nil and k ~= "LANG_enUS" and k ~= "LANG_ruRU" then missing[#missing + 1] = k end
        end
        for k in pairs(RU) do
            if EN[k] == nil then extra[#extra + 1] = k end
        end
        table.sort(missing) table.sort(extra)
        eq(table.concat(missing, ", "), "", "untranslated")
        eq(table.concat(extra, ", "), "", "Russian keys without English")
        eq(#RU.HELP, #EN.HELP, "same number of help lines")
    end },

    { "follows the game client by default", function()
        local ET = H.boot({ locale = "ruRU" })
        eq(ET.language, "ruRU")
        eq(ET.L.ALERT_TITLE, ET._locales.ruRU.ALERT_TITLE)
        local ET2 = H.boot({ locale = "deDE" })
        eq(ET2.language, "enUS", "unsupported client languages fall back to English")
    end },

    { "a Russian setting on an English client leaves no English text on screen", function()
        local _, env = H.boot()
        env.EnemyTrackerDB.settings.language = "ruRU"
        local ET, env2 = H.reboot(env)
        eq(ET.language, "ruRU")
        openEverything(ET, env2)
        local EN, RU = ET._locales.enUS, ET._locales.ruRU
        local english = {}
        for k, v in pairs(EN) do
            if type(v) == "string" and RU[k] ~= nil and RU[k] ~= v and #v > 3 then english[v] = k end
        end
        for _, t in ipairs(widgetTexts(env2)) do
            no(english[t], "English text on screen: " .. t)
        end
        H.noErrors(env2)
    end },

    { "an English setting on a Russian client leaves no Russian text on screen", function()
        local _, env = H.boot({ locale = "ruRU" })
        env.EnemyTrackerDB.settings.language = "enUS"
        local ET, env2 = H.reboot(env, { locale = "ruRU" })
        openEverything(ET, env2)
        for _, t in ipairs(widgetTexts(env2)) do
            no(t:find("[\208\209]"), "Cyrillic text on screen: " .. t)
        end
        H.noErrors(env2)
    end },

    { "/et lang switches messages at once and offers a reload", function()
        local ET, env = H.boot()
        H.slash(env, "lang ru")
        eq(ET.db.settings.language, "ruRU")
        eq(ET.L.ALERT_TITLE, ET._locales.ruRU.ALERT_TITLE)
        ok(H.chatContains(env, "Русский"))
        local p = env._state.popups[#env._state.popups]
        eq(p.which, "ENEMYTRACKER_RELOAD")
        eq(p.button1, ET._locales.ruRU.BTN_RELOAD)
        mock.acceptPopup(env)
        ok(env._state.reloaded)
        H.slash(env, "lang auto")
        eq(ET.language, "enUS")
        H.slash(env, "lang xx")
        ok(H.lastChat(env):find("/et lang", 1, true))
        local ET2 = H.reboot(env)
        eq(ET2.db.settings.language, "auto", "saved")
        H.noErrors(env)
    end },

    { "the options panel cycles the language", function()
        local ET, env = H.boot()
        env.EnemyTrackerOptionsPanel:RunScript("OnShow")
        eq(env.EnemyTrackerOptionsPanel.langText:GetText(), "Auto (game)")
        mock.click(env.EnemyTrackerOptionsPanel.langNext)
        eq(ET.db.settings.language, "enUS")
        mock.click(env.EnemyTrackerOptionsPanel.langNext)
        eq(ET.db.settings.language, "ruRU")
        eq(env.EnemyTrackerOptionsPanel.langText:GetText(), "Русский")
    end },

    { "confirmation buttons follow the addon language, not the client's", function()
        local _, env = H.boot()
        env.EnemyTrackerDB.settings.language = "ruRU"
        local ET, env2 = H.reboot(env)
        ET:AddEnemy("Ivan Petrov", true)
        ET:ConfirmRemove("Ivan Petrov")
        local p = env2._state.popups[#env2._state.popups]
        eq(p.button1, "Да")
        eq(p.button2, "Нет")
    end },
}
