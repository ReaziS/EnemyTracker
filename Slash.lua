-- Enemy Tracker: slash commands (/et, /enemytracker).
local _, ET = ...
local L = ET.L

local function printHelp()
    ET:Print("v" .. ET.version)
    for _, line in ipairs(L.HELP) do DEFAULT_CHAT_FRAME:AddMessage("  " .. line) end
end

local function printList()
    local names = {}
    for _, e in pairs(ET.db.enemies) do
        names[#names + 1] = string.format("%s (%d/%d, %s)", e.name, e.stats.killedMe, e.stats.iKilled,
            ET.FormatAgo(e.lastSeen))
    end
    if #names == 0 then ET:Print(L.LIST_EMPTY) return end
    table.sort(names)
    ET:Print(string.format(L.LIST_HEADER, #names))
    for _, line in ipairs(names) do DEFAULT_CHAT_FRAME:AddMessage("  " .. line) end
end

function ET:HandleSlash(msg)
    msg = ET.Trim(msg or "")
    local cmd, rest = msg:match("^(%S+)%s*(.*)$")
    cmd = cmd and cmd:lower() or ""
    rest = ET.Trim(rest or "")

    if cmd == "add" or cmd == "a" then
        if rest == "" then self:AddTarget() else self:AddEnemyManual(rest) end
    elseif cmd == "addtarget" or cmd == "at" then
        self:AddTarget()
    elseif cmd == "remove" or cmd == "rm" or cmd == "del" then
        if rest == "" then
            rest = ET.PlayerName("target") or ""
        end
        if rest ~= "" then self:ConfirmRemove(rest) else printHelp() end
    elseif cmd == "note" or cmd == "desc" then
        -- /et note First Surname [text]; no text clears the description.
        local first, second, text = rest:match("^(%S+)%s*(%S*)%s*(.*)$")
        local name
        if first and first:find("-", 1, true) then -- "First-Surname text"
            name, text = first, ET.Trim(second .. " " .. text)
        elseif first and second ~= "" then
            name = first .. " " .. second
        end
        if name then self:SetDescription(name, text) else printHelp() end
    elseif cmd == "group" or cmd == "g" then
        local sub, arg = rest:match("^(%S*)%s*(.*)$")
        sub = (sub or ""):lower()
        if sub == "create" or sub == "new" then
            self:CreateGroup()
        elseif sub == "join" and arg ~= "" then
            self:JoinGroup(arg)
        elseif sub == "leave" and arg ~= "" then
            self:LeaveGroup(arg)
        elseif sub == "list" then
            self:PrintGroups()
        else
            self:ToggleGroupsPanel()
        end
    elseif cmd == "lang" or cmd == "language" then
        local codes = { auto = "auto", en = "enUS", enus = "enUS", ru = "ruRU", ruru = "ruRU" }
        local code = codes[rest:lower()]
        if code then self:SetLanguage(code) else self:Print(L.LANG_USAGE) end
    elseif cmd == "clear" then
        if rest ~= "" then self:ConfirmClear(rest) else printHelp() end
    elseif cmd == "list" or cmd == "ls" then
        printList()
    elseif cmd == "show" or cmd == "dashboard" or cmd == "ui" then
        self:ToggleDashboard()
    elseif cmd == "on" then
        self:SetScanning(true)
    elseif cmd == "off" then
        self:SetScanning(false)
    elseif cmd == "toggle" then
        self:SetScanning(not self.db.settings.scanEnabled)
    elseif cmd == "unlock" or cmd == "move" then
        self:SetLocked(false)
    elseif cmd == "lock" then
        self:SetLocked(true)
    elseif cmd == "resetpos" then
        self:ResetPositions()
    elseif cmd == "test" then
        self:TestAlert()
    elseif cmd == "options" or cmd == "config" or cmd == "opt" then
        self:OpenOptions()
    elseif cmd == "debug" then
        self.db.settings.debug = not self.db.settings.debug
        self:Print(self.db.settings.debug and L.DEBUG_ON or L.DEBUG_OFF)
        self:Fire("SETTINGS_CHANGED", "debug")
    else
        printHelp()
    end
end

SLASH_ENEMYTRACKER1 = "/et"
SLASH_ENEMYTRACKER2 = "/enemytracker"
SlashCmdList["ENEMYTRACKER"] = function(msg) ET:HandleSlash(msg) end
