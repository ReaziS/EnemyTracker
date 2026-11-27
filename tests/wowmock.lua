-- Minimal mock of the WoW: Forever client API, enough to load and drive the
-- addon outside the game. Each call to new() returns a fresh, isolated global
-- environment; addon chunks are run inside it with setfenv.
--
-- Modelled on what is known about Forever (interface 16001, retail UI code):
--  * UnitName(unit) returns first name and SURNAME (not a realm);
--  * CombatLogGetCurrentEventInfo does not exist (combat log restricted);
--  * issecretvalue exists.
-- It cannot prove rendering, real secure-template behaviour or real payloads.
local M = {}

local function noop() end

-------------------------------------------------------------------------------
-- Widgets
-------------------------------------------------------------------------------
local Widget = {}

-- Unknown method names (Capitalised) are accepted as no-ops; unknown
-- lower-case fields are nil, like plain Lua tables.
local WidgetMT = {
    __index = function(_, k)
        local m = Widget[k]
        if m ~= nil then return m end
        if type(k) == "string" and k:match("^%u") then return noop end
        return nil
    end,
}

local function newWidget(state, kind, name, parent)
    local w = setmetatable({
        _state = state, _kind = kind, _name = name, _parent = parent,
        _shown = true, _scripts = {}, _hooks = {}, _attrs = {}, _points = {},
        _scale = 1, _text = nil, _checked = false, _value = 0, _enabled = true,
        _left = 100, _top = 500, _width = 100, _height = 20,
    }, WidgetMT)
    state.widgets[#state.widgets + 1] = w
    return w
end

function Widget:GetName() return self._name end
function Widget:GetParent() return self._parent end
function Widget:GetObjectType() return self._kind end

function Widget:SetScript(event, fn) self._scripts[event] = fn end
function Widget:GetScript(event) return self._scripts[event] end
function Widget:HookScript(event, fn)
    local list = self._hooks[event] or {}
    list[#list + 1] = fn
    self._hooks[event] = list
end
function Widget:RunScript(event, ...)
    local fn = self._scripts[event]
    if fn then fn(self, ...) end
    for _, h in ipairs(self._hooks[event] or {}) do h(self, ...) end
end

function Widget:Show()
    if self._shown then return end
    self._shown = true
    self:RunScript("OnShow")
end
function Widget:Hide()
    if not self._shown then return end
    self._shown = false
    self:RunScript("OnHide")
end
function Widget:SetShown(v) if v then self:Show() else self:Hide() end end
function Widget:IsShown() return self._shown end
function Widget:IsVisible()
    local w = self
    while w do
        if not w._shown then return false end
        w = w._parent
    end
    return true
end

function Widget:SetText(t) self._text = t end
function Widget:GetText() return self._text end
function Widget:SetFormattedText(fmt, ...) self._text = string.format(fmt, ...) end
function Widget:GetStringWidth() return #(self._text or "") * 7 end

function Widget:SetChecked(v) self._checked = v and true or false end
function Widget:GetChecked() return self._checked end
function Widget:SetValue(v)
    self._value = v
    self:RunScript("OnValueChanged", v)
end
function Widget:GetValue() return self._value end
function Widget:SetEnabled(v) self._enabled = v and true or false end
function Widget:IsEnabled() return self._enabled end
function Widget:Enable() self._enabled = true end
function Widget:Disable() self._enabled = false end

function Widget:SetAttribute(k, v)
    if self._protected and self._state.combat then
        error("ADDON_ACTION_BLOCKED: SetAttribute on protected frame in combat")
    end
    self._attrs[k] = v
end
function Widget:GetAttribute(k) return self._attrs[k] end

function Widget:SetPoint(...) self._points[#self._points + 1] = { ... } end
function Widget:ClearAllPoints() self._points = {} end
function Widget:GetPoint(i)
    local p = self._points[i or 1]
    if p then return unpack(p) end
end
function Widget:GetLeft() return self._left end
function Widget:GetTop() return self._top end
function Widget:GetCenter() return self._left + self._width / 2, self._top - self._height / 2 end
function Widget:SetSize(w, h) self._width, self._height = w, h end
function Widget:SetWidth(w) self._width = w end
function Widget:SetHeight(h) self._height = h end
function Widget:GetWidth() return self._width end
function Widget:GetHeight() return self._height end
function Widget:SetScale(s) self._scale = s end
function Widget:GetScale() return self._scale end
function Widget:GetEffectiveScale()
    local p = self._parent
    return self._scale * (p and p:GetEffectiveScale() or 1)
end
function Widget:GetFrameLevel() return self._level or 1 end
function Widget:SetFrameLevel(l) self._level = l end

function Widget:RegisterEvent(event)
    local s = self._state
    if s.forbiddenEvents[event] then
        error("Attempt to register unknown event \"" .. event .. "\"")
    end
    local list = s.eventFrames[event] or {}
    list[#list + 1] = self
    s.eventFrames[event] = list
end
function Widget:UnregisterEvent(event)
    local list = self._state.eventFrames[event] or {}
    for i = #list, 1, -1 do
        if list[i] == self then table.remove(list, i) end
    end
end

function Widget:CreateTexture() return newWidget(self._state, "Texture", nil, self) end
function Widget:CreateFontString() return newWidget(self._state, "FontString", nil, self) end
function Widget:CreateAnimationGroup() return newWidget(self._state, "AnimationGroup", nil, self) end
function Widget:CreateAnimation() return newWidget(self._state, "Animation", nil, self) end

-------------------------------------------------------------------------------
-- Environment
-------------------------------------------------------------------------------
M.SECRET = "\0secret\0"

function M.new(opts)
    opts = opts or {}
    local s = {
        now = 1000, epoch = 1800000000,
        timers = {}, widgets = {}, eventFrames = {}, forbiddenEvents = {},
        units = {}, plates = {}, chat = {}, sounds = {}, popups = {}, menus = {},
        errors = {}, combat = false, raid = false, groupSize = 0,
        locale = opts.locale or "enUS",
        settingsCategories = {}, openedCategory = nil,
        cvars = { Sound_MasterVolume = "1.0", Sound_SFXVolume = "0.5" },
    }
    for _, e in ipairs(opts.forbiddenEvents or {}) do s.forbiddenEvents[e] = true end

    local env = { _state = s }
    env._G = env
    setmetatable(env, { __index = _G })

    -- Record every error swallowed by the addon's pcall wrappers.
    env.pcall = function(fn, ...)
        local r = { pcall(fn, ...) }
        if not r[1] then s.errors[#s.errors + 1] = tostring(r[2]) end
        return unpack(r, 1, table.maxn(r))
    end

    env.bit = require("bit")
    env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    env.tinsert = table.insert
    env.tremove = table.remove
    env.hooksecurefunc = function(a, b, c)
        local tbl, name, hook = env, a, b
        if type(a) == "table" then tbl, name, hook = a, b, c end
        local orig = tbl[name]
        tbl[name] = function(...)
            local r = { orig(...) }
            hook(...)
            return unpack(r, 1, table.maxn(r))
        end
    end

    env.GetTime = function() return s.now end
    env.time = function(t)
        if t then return os.time(t) end
        return s.epoch + math.floor(s.now)
    end
    env.date = os.date
    env.GetLocale = function() return s.locale end
    env.GetBuildInfo = function() return "1.60.1", "70338", "Nov 1 2026", 16001 end
    env.WOW_PROJECT_CAMELOT = 18
    env.WOW_PROJECT_ID = 18

    -- Secret values
    env.issecretvalue = function(v) return v == M.SECRET end

    -- Frames
    env.CreateFrame = function(kind, name, parent, template)
        local w = newWidget(s, kind, name, parent)
        w._template = template
        if template and template:find("SecureActionButtonTemplate") then w._protected = true end
        -- Templates such as UIPanelCloseButton/UICheckButtonTemplate start shown.
        if name then env[name] = w end
        return w
    end
    env.UIParent = newWidget(s, "Frame", "UIParent")
    env.Minimap = newWidget(s, "Minimap", "Minimap")
    env.Minimap._width = 140
    env.GameTooltip = newWidget(s, "GameTooltip", "GameTooltip")
    env.GameTooltip.AddLine = function(self, text)
        self._lines = self._lines or {}
        self._lines[#self._lines + 1] = text
    end
    env.GameTooltip.SetOwner = function(self) self._lines = {} end
    env.BackdropTemplateMixin = {}
    env.UISpecialFrames = {}
    env.GetCursorPosition = function() return 0, 0 end
    env.InCombatLockdown = function() return s.combat end

    env.DEFAULT_CHAT_FRAME = newWidget(s, "ScrollingMessageFrame", "ChatFrame1")
    env.DEFAULT_CHAT_FRAME.AddMessage = function(_, msg) s.chat[#s.chat + 1] = msg end

    -- Timers (driven by M.advance)
    local function addTimer(delay, fn, interval)
        local t = { at = s.now + delay, fn = fn, interval = interval }
        t.handle = {
            Cancel = function() t.cancelled = true end,
            IsCancelled = function() return t.cancelled == true end,
        }
        s.timers[#s.timers + 1] = t
        return t.handle
    end
    env.C_Timer = {
        After = function(delay, fn) addTimer(delay, fn) end,
        NewTimer = function(delay, fn) return addTimer(delay, fn) end,
        NewTicker = function(interval, fn) return addTimer(interval, fn, interval) end,
    }

    -- Units. s.units[unit] = { name, surname, player, faction, guid, visible, secretName }
    local function U(unit) return s.units[unit] end
    env.UnitExists = function(unit) return U(unit) ~= nil end
    env.UnitIsPlayer = function(unit) local u = U(unit); return u ~= nil and u.player ~= false end
    env.UnitName = function(unit)
        local u = U(unit)
        if not u then return nil end
        if u.secretName then return M.SECRET, M.SECRET end
        return u.name, u.surname
    end
    env.UnitFullName = env.UnitName
    env.UnitNameUnmodified = env.UnitName
    env.GetUnitName = function(unit)
        local u = U(unit)
        if not u then return nil end
        if u.secretName then return M.SECRET end
        if u.surname then return u.name .. " " .. u.surname end
        return u.name
    end
    env.UnitGUID = function(unit) local u = U(unit); return u and u.guid end
    env.UnitFactionGroup = function(unit)
        local u = U(unit)
        if u and u.faction then return u.faction, u.faction end
    end
    env.UnitIsVisible = function(unit) local u = U(unit); return u ~= nil and u.visible ~= false end
    env.UnitIsUnit = function(a, b) return U(a) ~= nil and U(a) == U(b) end
    env.C_PlayerInfo = { ShouldDisplaySurname = function() return true end }
    env.UNKNOWNOBJECT = "Unknown"

    env.C_NamePlate = {
        GetNamePlates = function()
            local list = {}
            for i, unit in ipairs(s.plates) do list[i] = { namePlateUnitToken = unit } end
            return list
        end,
    }
    env.IsInRaid = function() return s.raid end
    env.GetNumGroupMembers = function() return s.groupSize end

    -- Sound
    env.SOUNDKIT = { RAID_WARNING = 8959, READY_CHECK = 8960, TELL_MESSAGE = 3081 }
    env.PlaySound = function(id, channel)
        s.sounds[#s.sounds + 1] = { id = id, channel = channel }
        return true
    end
    env.GetCVar = function(name) return s.cvars[name] end

    -- Dialogs
    env.YES, env.NO = "Yes", "No"
    env.StaticPopupDialogs = {}
    env.StaticPopup_Show = function(which, text1, text2, data)
        s.popups[#s.popups + 1] = { which = which, text = text1, data = data }
    end

    -- Settings panel (retail API, present on Forever)
    env.Settings = {
        RegisterCanvasLayoutCategory = function(panel, name)
            local cat = { panel = panel, name = name, ID = #s.settingsCategories + 1 }
            cat.GetID = function(self) return self.ID end
            return cat
        end,
        RegisterAddOnCategory = function(cat) s.settingsCategories[#s.settingsCategories + 1] = cat end,
        OpenToCategory = function(id) s.openedCategory = id end,
    }

    -- Right-click menus (Menu.ModifyMenu)
    env.Menu = {
        ModifyMenu = function(tag, fn)
            local list = s.menus[tag] or {}
            list[#list + 1] = fn
            s.menus[tag] = list
        end,
    }

    env.SlashCmdList = {}

    -- Chat filters and frames
    s.chatFilters = {}
    env.ChatFrame_AddMessageEventFilter = function(event, fn)
        local list = s.chatFilters[event] or {}
        list[#list + 1] = fn
        s.chatFilters[event] = list
    end
    env.ChatFrame1 = env.DEFAULT_CHAT_FRAME
    env.CHAT_FRAMES = { "ChatFrame1" }
    env.FCF_OpenTemporaryWindow = function() end

    -- Chat channels: joining completes after a short delay, like the client.
    s.channels, s.removedChannels = {}, {}
    env.JoinTemporaryChannel = function(name)
        env.C_Timer.After(0.5, function()
            if s.channels[name] then return end
            local n = 0
            for _ in pairs(s.channels) do n = n + 1 end
            s.channels[name] = n + 5 -- General, Trade... occupy the low numbers
        end)
    end
    env.GetChannelName = function(name)
        local i = s.channels[name]
        if i then return i, name end
        return 0
    end
    env.LeaveChannelByName = function(name) s.channels[name] = nil end
    env.ChatFrame_RemoveChannel = function(frame, name)
        s.removedChannels[#s.removedChannels + 1] = { frame = frame, name = name }
    end

    -- Tooltips (retail TooltipDataProcessor, present on Forever)
    s.tooltipPostCalls = {}
    env.Enum = { TooltipDataType = { Unit = 2 } }
    env.TooltipDataProcessor = {
        AddTooltipPostCall = function(kind, fn)
            local list = s.tooltipPostCalls[kind] or {}
            list[#list + 1] = fn
            s.tooltipPostCalls[kind] = list
        end,
    }
    env.GameTooltip.GetUnit = function() local u = s.tooltipUnit; return u and "x", u end
    env.GameTooltip.HasScript = function() return true end

    return env
end

-------------------------------------------------------------------------------
-- Driving helpers
-------------------------------------------------------------------------------
function M.fire(env, event, ...)
    local list = env._state.eventFrames[event]
    if not list then return end
    for _, f in ipairs(list) do f:RunScript("OnEvent", event, ...) end
end

-- Advances the clock, running due timers in order.
function M.advance(env, dt)
    local s = env._state
    local target = s.now + dt
    while true do
        local best
        for _, t in ipairs(s.timers) do
            if not t.cancelled and t.at <= target and (not best or t.at < best.at) then best = t end
        end
        if not best then break end
        s.now = best.at
        if best.interval then best.at = best.at + best.interval else best.cancelled = true end
        best.fn(best.handle)
    end
    s.now = target
    for i = #s.timers, 1, -1 do
        if s.timers[i].cancelled then table.remove(s.timers, i) end
    end
end

-- Clicks a widget as the user would (OnClick + PostClick hooks).
function M.click(widget, button, down)
    button = button or "LeftButton"
    widget:RunScript("OnClick", button, down)
    widget:RunScript("PostClick", button, down)
end

-- Accepts the most recent StaticPopup.
function M.acceptPopup(env)
    local p = table.remove(env._state.popups)
    assert(p, "no popup shown")
    local dialog = env.StaticPopupDialogs[p.which]
    dialog.OnAccept(nil, p.data)
end

-- Runs a chat event through the registered filters, like ChatFrame does.
-- Returns the message as it would be displayed, or nil if filtered out.
function M.chatMessage(env, event, msg, author, ...)
    local args = { msg, author, ... }
    for _, fn in ipairs(env._state.chatFilters[event] or {}) do
        local r = { fn(env.ChatFrame1, event, unpack(args, 1, table.maxn(args))) }
        if r[1] then return nil end
        if #r > 1 then args = { select(2, unpack(r, 1, table.maxn(r))) } end
    end
    return args[1]
end

-- Hovers a unit: builds GameTooltip for it and returns the added lines.
function M.hoverUnit(env, unit)
    local s = env._state
    s.tooltipUnit = unit
    env.GameTooltip._lines = {}
    for _, fn in ipairs(s.tooltipPostCalls[2] or {}) do fn(env.GameTooltip, {}) end
    return env.GameTooltip._lines
end

-- Presses "No" on the most recent StaticPopup.
function M.declinePopup(env)
    local p = table.remove(env._state.popups)
    assert(p, "no popup shown")
    local dialog = env.StaticPopupDialogs[p.which]
    if dialog.OnCancel then dialog.OnCancel(nil, p.data, "clicked") end
end

-- Opens the right-click menu for a tag and returns the entries added to it.
function M.openMenu(env, tag, contextData)
    local entries = {}
    local root = {
        CreateDivider = function() entries[#entries + 1] = { divider = true } end,
        CreateButton = function(_, label, fn)
            entries[#entries + 1] = { label = label, fn = fn }
        end,
    }
    for _, fn in ipairs(env._state.menus[tag] or {}) do fn(nil, root, contextData) end
    return entries
end

return M
