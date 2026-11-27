-- Groups window and shared players in the dashboard.
local H = require("harness")
local mock = H.mock
local eq, ok, no = H.eq, H.ok, H.no

local GID = "7KQMX2PV9HRB"

local function shareIvan(ET, env, desc)
    ET:MergeGroupRecord(GID, "ivan petrov", { name = "Ivan Petrov", faction = "Horde",
        description = desc or "", at = env.time(), by = "Anna Kova" })
    mock.advance(env, 1)
end

return {
    { "/et group opens the window; create, join and leave from it", function()
        local ET, env = H.boot()
        H.slash(env, "group")
        ok(env.EnemyTrackerGroups:IsShown())
        eq(env.EnemyTrackerGroupsSlot1Id:IsShown(), false, "no groups yet")
        mock.click(env.EnemyTrackerGroupsCreate)
        local id = next(ET.db.groups)
        ok(id)
        eq(env.EnemyTrackerGroupsSlot1Id:GetText(), ET.FormatGroupId(id), "ID shown for copying")
        mock.advance(env, 1) -- slots are ordered by join time
        env.EnemyTrackerGroupsJoinBox:SetText("ET-7KQM-X2PV-9HRB")
        mock.click(env.EnemyTrackerGroupsJoin)
        ok(ET.db.groups[GID])
        eq(env.EnemyTrackerGroupsJoinBox:GetText(), "")
        mock.click(env.EnemyTrackerGroupsSlot1Leave)
        no(ET.db.groups[id])
        eq(env.EnemyTrackerGroupsSlot1Id:GetText(), ET.FormatGroupId(GID), "remaining group moves up")
        H.noErrors(env)
    end },

    { "the ID box cannot be edited", function()
        local ET, env = H.boot()
        H.slash(env, "group")
        ET:JoinGroup(GID)
        local box = env.EnemyTrackerGroupsSlot1Id
        box:SetText("ET-XXXX")
        box:RunScript("OnTextChanged", true)
        eq(box:GetText(), "ET-7KQM-X2PV-9HRB")
    end },

    { "create and join are disabled when all slots are used", function()
        local ET, env = H.boot()
        H.slash(env, "group")
        for _ = 1, ET.MAX_GROUPS do ET:CreateGroup() end
        no(env.EnemyTrackerGroupsCreate:IsEnabled())
        no(env.EnemyTrackerGroupsJoin:IsEnabled())
    end },

    { "shows the connection state and how many players a group has", function()
        local ET, env = H.boot()
        H.slash(env, "group")
        ET:JoinGroup(GID)
        mock.advance(env, 2)
        local function infoText()
            for _, w in ipairs(env._state.widgets) do
                local t = w._kind == "FontString" and w:GetText()
                if type(t) == "string" and t:find(ET.L.GROUP_CHECKING_SHORT, 1, true) then return t end
            end
        end
        ok(infoText(), "an unconfirmed group says it is being checked")
        ET:ConfirmGroup(GID)
        shareIvan(ET, env)
        local info
        for _, w in ipairs(env._state.widgets) do
            local t = w._kind == "FontString" and w:GetText()
            if type(t) == "string" and t:find(ET.L.GROUP_ONLINE, 1, true) then info = t end
        end
        ok(info, "status line")
        ok(info:find("1", 1, true), "player count")
    end },

    { "the dashboard lists shared players and can adopt one", function()
        local ET, env = H.boot()
        ET:AddEnemy("Olga Smirnova")
        ET:JoinGroup(GID)
        shareIvan(ET, env, "Ganks lowbies")
        ET:ShowDashboard()
        local names = {}
        for i = 1, 3 do
            local row = env["EnemyTrackerDashboardRow" .. i]
            if row:IsShown() then names[#names + 1] = row.cols.name:GetText() end
        end
        eq(#names, 2)
        local ivanRow
        for i = 1, 2 do
            if env["EnemyTrackerDashboardRow" .. i].key == "ivan petrov" then
                ivanRow = env["EnemyTrackerDashboardRow" .. i]
            end
        end
        ok(ivanRow)
        mock.click(ivanRow)
        eq(env.EnemyTrackerDashboardDescription:GetText(), "Ganks lowbies")
        local frame = env.EnemyTrackerDashboard
        local adopt
        for _, w in ipairs(env._state.widgets) do
            if w._kind == "Button" and w:GetText() == ET.L.BTN_ADD_TO_MINE then adopt = w end
        end
        ok(adopt and adopt:IsEnabled(), "button offers to add the shared player")
        mock.click(adopt)
        ok(ET.db.enemies["ivan petrov"])
        eq(ET.db.enemies["ivan petrov"].faction, "Horde")
        eq(ET:DescriptionOf("ivan petrov"), "Ganks lowbies")
        no(ET.sharedView["ivan petrov"])
        ok(frame.groupsBtn)
        H.noErrors(env)
    end },

    { "the dashboard joins and creates groups without chat commands", function()
        local ET, env = H.boot()
        ET:ShowDashboard()
        env.EnemyTrackerDashboardJoinBox:SetText("et-7kqm-x2pv-9hrb")
        mock.click(env.EnemyTrackerDashboardJoin)
        ok(ET.db.groups[GID])
        eq(env.EnemyTrackerDashboardJoinBox:GetText(), "")
        env.EnemyTrackerDashboardJoinBox:SetText("ET-7KQM-X2PV-9HRT")
        mock.click(env.EnemyTrackerDashboardJoin)
        eq(env.EnemyTrackerDashboardJoinBox:GetText(), "ET-7KQM-X2PV-9HRT", "kept for fixing a typo")
        ok(H.chatContains(env, "ET-7KQM-X2PV-9HRT"))
        mock.click(env.EnemyTrackerDashboardCreate)
        eq(ET:GroupCount(), 2)
        ET:CreateGroup()
        no(env.EnemyTrackerDashboardJoin:IsEnabled(), "all slots used")
        no(env.EnemyTrackerDashboardCreate:IsEnabled())
        H.noErrors(env)
    end },

    { "the description field reminds what belongs in it", function()
        local ET, env = H.boot()
        ET:ShowDashboard()
        eq(env.EnemyTrackerDashboard.descHint:GetText(), ET.L.DESC_HINT)
        ok(ET.L.DESC_HINT:find("personal", 1, true))
    end },

    { "the groups window opens above the dashboard", function()
        local ET, env = H.boot()
        ET:ShowDashboard()
        H.slash(env, "group")
        local g = env.EnemyTrackerGroups
        H.slash(env, "group") -- close
        local raised = false
        g.Raise = function() raised = true end
        mock.click(env.EnemyTrackerDashboard.groupsBtn)
        ok(g:IsShown())
        ok(raised, "raised on open")
    end },
}
