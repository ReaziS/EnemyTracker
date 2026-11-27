-- Enemy Tracker: red flag next to blacklisted players, whatever their faction.
--
--  * Chat (say, yell, whispers both ways, party, raid, guild, channels...):
--    the message gets a flag in front, through ChatFrame_AddMessageEventFilter
--    (the standard way addons decorate chat; Blizzard's frames are not
--    modified). The flag is an addon hyperlink: hovering it shows the
--    player's description.
--  * Unit tooltips (mouseover, unit frames, nameplates): a flagged line with
--    the description.
-- Secret (hidden) chat or unit values are left untouched.
local _, ET = ...
local L = ET.L

local FLAG_TEXTURE = "Interface\\AddOns\\EnemyTracker\\Media\\Flag"
ET.FLAG = "|T" .. FLAG_TEXTURE .. ":0|t"
local LINK_PREFIX = "addon:EnemyTracker:"

local CHAT_EVENTS = {
    "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_EMOTE", "CHAT_MSG_TEXT_EMOTE",
    "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_CHANNEL",
}

local function enabled() return ET.db and ET.db.settings.showFlags end

-- Blacklist key for a chat author / unit name, or nil.
local function listedKey(name)
    if ET.IsSecret(name) or type(name) ~= "string" then return nil end
    local key = ET.NameKey(name)
    return key and ET.db.enemies[key] and key or nil
end

function ET.FlagLink(key)
    return "|H" .. LINK_PREFIX .. key .. "|h" .. ET.FLAG .. "|h"
end

-------------------------------------------------------------------------------
-- Chat
-------------------------------------------------------------------------------
local function chatFilter(_, _, msg, author, ...)
    if not enabled() or ET.IsSecret(msg) or type(msg) ~= "string" then return false end
    local key = listedKey(author)
    if not key then return false end
    return false, ET.FlagLink(key) .. " " .. msg, author, ...
end
ET._chatFilter = chatFilter -- for tests

local function showFlagTooltip(owner, key)
    local e = ET.db.enemies[key]
    if not e then return end
    GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
    GameTooltip:AddLine(ET.FLAG .. " " .. e.name, 1, 0.25, 0.25)
    GameTooltip:AddLine(e.description ~= "" and ET.EscapeText(e.description) or L.FLAG_NO_DESCRIPTION,
        1, 1, 1, true)
    GameTooltip:Show()
end

local function onHyperlinkEnter(frame, link)
    if type(link) ~= "string" or link:sub(1, #LINK_PREFIX) ~= LINK_PREFIX then return end
    showFlagTooltip(frame, link:sub(#LINK_PREFIX + 1))
end

local function onHyperlinkLeave() GameTooltip:Hide() end

local hookedFrames = {}
local function hookChatFrames()
    for _, name in ipairs(_G.CHAT_FRAMES or {}) do
        local f = _G[name]
        if f and not hookedFrames[f] then
            hookedFrames[f] = true
            f:HookScript("OnHyperlinkEnter", onHyperlinkEnter)
            f:HookScript("OnHyperlinkLeave", onHyperlinkLeave)
        end
    end
end

-------------------------------------------------------------------------------
-- Unit tooltips
-------------------------------------------------------------------------------
local function onUnitTooltip(tooltip)
    if tooltip ~= GameTooltip or not enabled() then return end
    local _, unit = tooltip:GetUnit()
    if not unit or ET.IsSecret(unit) then return end
    local name = ET.PlayerName(unit)
    local key = name and listedKey(name)
    if not key then return end
    local e = ET.db.enemies[key]
    tooltip:AddLine(ET.FLAG .. " " .. L.FLAG_TOOLTIP, 1, 0.25, 0.25)
    if e.description ~= "" then tooltip:AddLine(ET.EscapeText(e.description), 1, 1, 1, true) end
end
ET._onUnitTooltip = onUnitTooltip -- for tests

-------------------------------------------------------------------------------
-- Setup
-------------------------------------------------------------------------------
ET:On("LOGIN", function()
    if ChatFrame_AddMessageEventFilter then
        for _, event in ipairs(CHAT_EVENTS) do ChatFrame_AddMessageEventFilter(event, chatFilter) end
    else
        ET:Debug("ChatFrame_AddMessageEventFilter missing: no chat flags")
    end
    hookChatFrames()
    if FCF_OpenTemporaryWindow then hooksecurefunc("FCF_OpenTemporaryWindow", hookChatFrames) end

    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, onUnitTooltip)
    elseif GameTooltip:HasScript("OnTooltipSetUnit") then
        GameTooltip:HookScript("OnTooltipSetUnit", onUnitTooltip)
    end
end)
