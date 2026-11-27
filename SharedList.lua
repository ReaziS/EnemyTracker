-- Enemy Tracker: players shared by your groups, merged with your own list.
--
-- ET.sharedView[key] holds every live group record whose player is not in
-- your own blacklist: one entry per player across all groups, the most
-- recently changed record winning. Detection, alerts and flags look players
-- up through ET:GetTracked(), so shared players are treated like your own.
-- Their statistics start at zero and live only in memory: kills and deaths
-- count only in your own list.
local _, ET = ...

ET.sharedView = {}

function ET:RebuildShared()
    local old, view = self.sharedView, {}
    for id, g in pairs(self.db.groups) do
        for key, r in pairs(g.records) do
            if not r.del and not self.db.enemies[key] then
                local v = view[key]
                if not v then
                    -- Keep the same table, so "last seen" survives a rebuild.
                    v = old[key] or { stats = { killedMe = 0, iKilled = 0, detections = 0 }, lastSeen = 0 }
                    v.at, v.groups = -1, {}
                    view[key] = v
                end
                v.groups[#v.groups + 1] = id
                if r.at > v.at then
                    v.at, v.name, v.faction, v.description, v.by = r.at, r.name, r.faction, r.description or "", r.by
                end
            end
        end
    end
    for _, v in pairs(view) do
        v.shared = true
        table.sort(v.groups)
    end
    self.sharedView = view
    local added = false
    for key in pairs(view) do
        if not old[key] then added = true break end
    end
    self:Fire("SHARED_CHANGED")
    if added and self.ScanAll then self:ScanAll() end
end

-- The newest non-empty description a group holds for this player.
function ET:SharedDescription(key)
    local best
    for _, g in pairs(self.db.groups) do
        local r = g.records[key]
        if r and not r.del and (r.description or "") ~= "" and (not best or r.at > best.at) then best = r end
    end
    return best and best.description or ""
end

-- Rebuilding is cheap but a full sync delivers records one by one; coalesce.
local pending = false
local function scheduleRebuild()
    if pending then return end
    pending = true
    C_Timer.After(0.5, function()
        pending = false
        ET:RebuildShared()
    end)
end

ET:On("DB_READY", function() ET:RebuildShared() end)
ET:On("GROUP_RECORDS_CHANGED", scheduleRebuild)
ET:On("GROUPS_CHANGED", function() ET:RebuildShared() end)
ET:On("BLACKLIST_CHANGED", function(_, what)
    if what == "add" or what == "remove" or what == "rename" then ET:RebuildShared() end
end)
