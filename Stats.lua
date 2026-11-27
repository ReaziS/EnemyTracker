-- Enemy Tracker: PvP kill statistics from the combat log.
--
-- Counted ONLY when the combat log confirms it:
--  * "I killed X":  PARTY_KILL with source = me and destination = blacklisted player.
--  * "X killed me": a damage event from blacklisted player X to me that carries
--                   overkill > 0 (= the killing blow), paired with my death
--                   (PLAYER_DEAD / UNIT_DIED for me) within PAIR_WINDOW seconds.
-- Not counted (ambiguous): kills by pets/totems/guardians, exact-lethal hits
-- reported with overkill 0, deaths without a logged killing blow (e.g. out of
-- combat-log range, fall damage, DoT ticks from unknown sources).
local _, ET = ...
local L = ET.L

local PAIR_WINDOW = 2.0
local PLAYER_FLAG = _G.COMBATLOG_OBJECT_TYPE_PLAYER or 0x00000400
local band = bit.band

local myGUID
local lethal       -- { key = blacklist key or false, t = GetTime() }
local deathAt      -- GetTime() of my last death not yet resolved
local resolvedAt = -100

local function isPlayer(flags) return flags and band(flags, PLAYER_FLAG) ~= 0 end

local function resolveDeath()
    if not (lethal and deathAt) then return end
    if math.abs(deathAt - lethal.t) > PAIR_WINDOW then return end
    if lethal.key then
        local e = ET.db.enemies[lethal.key]
        if e then
            e.killedMe = (e.killedMe or 0) + 1
            ET:Print(string.format(L.KILLED_BY, e.name))
            ET:Fire("BLACKLIST_CHANGED", lethal.key, "stats")
        end
    else
        ET:Debug("death resolved: killer not blacklisted")
    end
    resolvedAt = GetTime()
    lethal, deathAt = nil, nil
end

local function onMyDeath()
    local now = GetTime()
    if now - resolvedAt < 5 then return end -- PLAYER_DEAD and UNIT_DIED both fire
    deathAt = now
    resolveDeath()
end

-- Extracts overkill for damage subevents (nil when not a damage event).
local function overkillOf(sub, ...)
    if sub == "SWING_DAMAGE" then
        return (select(2, ...))                 -- amount, overkill
    elseif sub == "SPELL_DAMAGE" or sub == "RANGE_DAMAGE" or sub == "SPELL_PERIODIC_DAMAGE"
        or sub == "SPELL_BUILDING_DAMAGE" or sub == "DAMAGE_SHIELD" or sub == "DAMAGE_SPLIT" then
        return (select(5, ...))                 -- spellId, name, school, amount, overkill
    end
end

local function onCombatLog()
    local _, sub, _, srcGUID, srcName, srcFlags, _, dstGUID, dstName, dstFlags, _, a12, a13, a14, a15, a16 =
        CombatLogGetCurrentEventInfo()
    if ET.IsSecret(srcGUID) or ET.IsSecret(dstGUID) or ET.IsSecret(srcFlags) or ET.IsSecret(dstFlags) then
        return
    end

    -- Detection source: players acting near us.
    if ET.db.settings.useCombatLog then
        if srcName and isPlayer(srcFlags) and srcGUID ~= myGUID then ET:ObserveName(srcName, "combatlog") end
        if dstName and isPlayer(dstFlags) and dstGUID ~= myGUID then ET:ObserveName(dstName, "combatlog") end
    end

    if sub == "PARTY_KILL" then
        if srcGUID == myGUID and isPlayer(dstFlags) then
            local key = ET.NameKey(dstName)
            local e = key and ET.db.enemies[key]
            if e then
                e.iKilled = (e.iKilled or 0) + 1
                ET:Print(string.format(L.YOU_KILLED, e.name))
                ET:Fire("BLACKLIST_CHANGED", key, "stats")
            end
        end
        return
    end

    if dstGUID == myGUID then
        if sub == "UNIT_DIED" then
            onMyDeath()
            return
        end
        local overkill = overkillOf(sub, a12, a13, a14, a15, a16)
        if overkill and overkill > 0 then
            local key = false
            if isPlayer(srcFlags) and srcName then
                local k = ET.NameKey(srcName)
                if k and ET.db.enemies[k] then key = k end
            end
            lethal = { key = key, t = GetTime() }
            ET:Debug("lethal hit from", tostring(srcName), "blacklisted:", tostring(key))
            resolveDeath()
        end
    end
end

-- The combat log is reportedly unavailable to addons on Forever (Midnight-era
-- restriction). We try once; if the client refuses, kill statistics and the
-- combat-log detection source are switched off and the UI says so. We never
-- try to read the combat log any other way (e.g. parsing the chat tab).
ET.combatLogAvailable = nil -- nil = not checked yet

ET:On("LOGIN", function()
    myGUID = UnitGUID("player")
    ET:RegisterEvent("PLAYER_DEAD", onMyDeath)
    local available = CombatLogGetCurrentEventInfo ~= nil
        and ET:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED", onCombatLog)
    ET.combatLogAvailable = available and true or false
    if not available then ET:Debug("combat log unavailable: kill statistics disabled") end
    ET:Fire("COMBATLOG_STATUS", ET.combatLogAvailable)
end)

-- Exposed for tests.
ET._StatsTest = { onCombatLog = onCombatLog, onMyDeath = onMyDeath,
    setGUID = function(g) myGUID = g end, reset = function() lethal, deathAt, resolvedAt = nil, nil, -100 end }
