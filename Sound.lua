-- Enemy Tracker: alert sounds.
-- WoW has no per-sound volume control: PlaySound only takes a channel, whose
-- volume is set in the game's own sound options. We offer channel choice
-- instead of a fake volume slider (see README "Sound volume").
local _, ET = ...
local L = ET.L

-- Candidate sound kits; only those the client defines in SOUNDKIT are offered,
-- except RAID_WARNING which has a long-standing numeric ID as fallback.
local CANDIDATES = {
    { key = "RAID_WARNING", fallback = 8959 },
    { key = "READY_CHECK", fallback = 8960 },
    { key = "RAID_BOSS_EMOTE_WARNING" },
    { key = "ALARM_CLOCK_WARNING_3" },
    { key = "PVP_THROUGH_QUEUE" },
    { key = "IG_PLAYER_INVITE" },
    { key = "TELL_MESSAGE" },
}

ET.CHANNELS = { "Master", "SFX", "Dialog", "Ambience", "Music" }

local available
function ET:GetSounds()
    if available then return available end
    available = {}
    local kits = _G.SOUNDKIT or {}
    for _, c in ipairs(CANDIDATES) do
        local id = kits[c.key] or c.fallback
        if id then
            available[#available + 1] = { key = c.key, id = id, label = L["SOUND_" .. c.key] or c.key }
        end
    end
    return available
end

function ET:GetSound(key)
    local list = self:GetSounds()
    for _, s in ipairs(list) do
        if s.key == key then return s end
    end
    return list[1]
end

function ET:PlayAlertSound(force)
    local s = self.db.settings
    if not force and not s.sound then return end
    local snd = self:GetSound(s.soundKey)
    if not snd then return end
    local ok, willPlay = pcall(PlaySound, snd.id, s.soundChannel or "Master")
    if not ok or willPlay == false then
        self:Debug("sound failed", snd.key, ok and "willPlay=false" or willPlay)
        -- Last resort: raid warning on Master.
        pcall(PlaySound, 8959, "Master")
    end
end

-- Current volume (0-100) of the selected channel, read from the game's CVars.
function ET:GetChannelVolume()
    local channel = self.db.settings.soundChannel or "Master"
    local cvar = "Sound_" .. channel .. "Volume"
    local v = tonumber(GetCVar and GetCVar(cvar))
    if not v then return 100 end
    if channel ~= "Master" then
        local master = tonumber(GetCVar("Sound_MasterVolume")) or 1
        v = v * master
    end
    return math.floor(v * 100 + 0.5)
end
