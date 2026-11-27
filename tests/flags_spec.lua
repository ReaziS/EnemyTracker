-- Red flag next to blacklisted players in chat and unit tooltips.
local H = require("harness")
local eq, ok, no = H.eq, H.ok, H.no

local function bootListed()
    local ET, env = H.boot()
    ET:AddEnemy("Raion Lyzl", true)
    ET:SetDescription("Raion Lyzl", "Ganks at the docks")
    return ET, env
end

return {
    { "flags a chat message from a blacklisted player", function()
        local ET, env = bootListed()
        local out = H.mock.chatMessage(env, "CHAT_MSG_SAY", "hello", "Raion Lyzl")
        ok(out:find(ET.FLAG, 1, true), "flag icon added")
        ok(out:find("hello$"), "original text kept")
        ok(out:find("|Haddon:EnemyTracker:raion lyzl|h", 1, true), "hoverable link")
        H.noErrors(env)
    end },

    { "flags whispers both ways and group chat", function()
        local ET, env = bootListed()
        for _, event in ipairs({ "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_PARTY",
            "CHAT_MSG_RAID", "CHAT_MSG_GUILD", "CHAT_MSG_CHANNEL" }) do
            local out = H.mock.chatMessage(env, event, "hi", "Raion Lyzl")
            ok(out:find(ET.FLAG, 1, true), event)
        end
    end },

    { "recognises the hyphenated and realm-suffixed author forms", function()
        local ET, env = bootListed()
        ok(H.mock.chatMessage(env, "CHAT_MSG_SAY", "a", "Raion-Lyzl"):find(ET.FLAG, 1, true))
        ok(H.mock.chatMessage(env, "CHAT_MSG_SAY", "a", "Raion Lyzl-Realm"):find(ET.FLAG, 1, true))
    end },

    { "flags players of either faction", function()
        local ET, env = H.boot({ player = { name = "Me", surname = "Myself", faction = "Alliance", guid = "P1" } })
        ET:AddEnemy("Anna Lightway", true)
        H.setUnit(env, "mouseover", { name = "Anna", surname = "Lightway", faction = "Alliance", guid = "P2" })
        local lines = H.mock.hoverUnit(env, "mouseover")
        ok(lines[1] and lines[1]:find(ET.L.FLAG_TOOLTIP, 1, true), "ally flagged in tooltip")
        ok(H.mock.chatMessage(env, "CHAT_MSG_SAY", "a", "Anna Lightway"):find(ET.FLAG, 1, true), "and in chat")
    end },

    { "leaves other players' messages untouched", function()
        local _, env = bootListed()
        eq(H.mock.chatMessage(env, "CHAT_MSG_SAY", "hello", "Someone Else"), "hello")
    end },

    { "leaves secret chat values untouched", function()
        local _, env = bootListed()
        eq(H.mock.chatMessage(env, "CHAT_MSG_SAY", H.mock.SECRET, "Raion Lyzl"), H.mock.SECRET)
        eq(H.mock.chatMessage(env, "CHAT_MSG_SAY", "hello", H.mock.SECRET), "hello")
        H.noErrors(env)
    end },

    { "shows the description in the unit tooltip", function()
        local ET, env = bootListed()
        H.setUnit(env, "mouseover", { name = "Raion", surname = "Lyzl", faction = "Horde", guid = "P3" })
        local lines = H.mock.hoverUnit(env, "mouseover")
        ok(lines[1]:find(ET.FLAG, 1, true))
        eq(lines[2], "Ganks at the docks")
    end },

    { "hovering the chat flag shows the description", function()
        local _, env = bootListed()
        env.ChatFrame1:RunScript("OnHyperlinkEnter", "addon:EnemyTracker:raion lyzl", "x")
        local lines = env.GameTooltip._lines
        ok(lines[1]:find("Raion Lyzl", 1, true))
        eq(lines[2], "Ganks at the docks")
        H.noErrors(env)
    end },

    { "ignores other addons' links", function()
        local _, env = bootListed()
        env.GameTooltip._lines = nil
        env.ChatFrame1:RunScript("OnHyperlinkEnter", "item:1234", "x")
        no(env.GameTooltip._lines, "no tooltip")
    end },

    { "can be switched off", function()
        local ET, env = bootListed()
        ET.db.settings.showFlags = false
        eq(H.mock.chatMessage(env, "CHAT_MSG_SAY", "hello", "Raion Lyzl"), "hello")
        H.setUnit(env, "mouseover", { name = "Raion", surname = "Lyzl", guid = "P3" })
        eq(#H.mock.hoverUnit(env, "mouseover"), 0)
    end },

    { "ships the flag texture", function()
        local f = io.open(H.ADDON_DIR .. "Media/Flag.tga", "rb")
        ok(f, "Media/Flag.tga exists")
        local data = f:read("*a")
        f:close()
        eq(data:byte(3), 2, "uncompressed true-colour TGA")
        eq(data:byte(17), 32, "32 bits per pixel")
        eq(#data, 18 + 32 * 32 * 4)
    end },
}
