-- Enemy Tracker: "Add to / Remove from Enemy Tracker" in player right-click menus.
-- Uses the modern Menu.ModifyMenu API (present in WoW Forever). If the client
-- lacks it we do nothing: hooking the legacy UnitPopup menus taints secure
-- menu entries, and "/et add" (target) remains the fallback.
local _, ET = ...
local L = ET.L

local function resolveName(contextData)
    if not contextData then return nil end
    local name
    if contextData.unit then
        name = ET.PlayerName(contextData.unit)
    else
        name = contextData.name
        -- Chat menus pass the realm field separately; on Forever that slot
        -- may carry the surname, as UnitName's second return does.
        local server = contextData.server
        if type(name) == "string" and not ET.IsSecret(name) and not name:find("[ %-]")
            and type(server) == "string" and not ET.IsSecret(server) and server ~= "" then
            name = name .. " " .. server
        end
    end
    if ET.IsSecret(name) or type(name) ~= "string" or name == "" or ET.IsSelfName(name) then return nil end
    return name
end

local function build(_, rootDescription, contextData)
    local name = resolveName(contextData)
    if not name or not ET.IsValidName(name) then return end
    rootDescription:CreateDivider()
    if ET:GetEnemy(name) then
        rootDescription:CreateButton(L.MENU_REMOVE, function() ET:ConfirmRemove(name) end)
    else
        local faction = contextData.unit and ET.UnitFaction(contextData.unit)
        rootDescription:CreateButton(L.MENU_ADD, function() ET:AddEnemy(name, false, faction) end)
    end
end

ET:On("LOGIN", function()
    if not (Menu and Menu.ModifyMenu) then
        ET:Debug("Menu.ModifyMenu not available; context menu entry disabled")
        return
    end
    local tags = {
        "MENU_UNIT_PLAYER",          -- player portraits / unit frames
        "MENU_UNIT_ENEMY_PLAYER",    -- hostile player target frame
        "MENU_UNIT_TARGET",          -- target frame
        "MENU_UNIT_FOCUS",
        "MENU_UNIT_PARTY",
        "MENU_UNIT_RAID_PLAYER",
        "MENU_UNIT_FRIEND",          -- name clicked in chat
        "MENU_UNIT_FRIEND_OFFLINE",
        "MENU_UNIT_CHAT_ROSTER",
    }
    for _, tag in ipairs(tags) do
        local ok, err = pcall(Menu.ModifyMenu, tag, build)
        if not ok then ET:Debug("ModifyMenu failed for", tag, err) end
    end
end)
