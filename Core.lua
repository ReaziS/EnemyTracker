-- Enemy Tracker: core namespace, event dispatch, internal callbacks, utilities.
local ADDON_NAME, ET = ...
_G.EnemyTracker = ET -- exposed for debugging (/dump EnemyTracker)

ET.name = ADDON_NAME
ET.version = "0.1.1"

-------------------------------------------------------------------------------
-- Game events
-------------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
local eventHandlers = {} -- event -> { fn, fn, ... }

-- Returns true on success. Some events may be forbidden to addons on the
-- client (e.g. the combat log on Forever); that returns false instead of erroring.
function ET:RegisterEvent(event, fn)
    local list = eventHandlers[event]
    if not list then
        local ok, err = pcall(eventFrame.RegisterEvent, eventFrame, event)
        if not ok then
            ET:Debug("cannot register", event, err)
            return false
        end
        list = {}
        eventHandlers[event] = list
    end
    list[#list + 1] = fn
    return true
end

-- Midnight-era clients (which Forever reportedly follows) can return "secret"
-- values that addons may not compare, index with, or branch on. We never use
-- them; anything secret is treated as "no data".
local issecretvalue = _G.issecretvalue
function ET.IsSecret(v)
    return issecretvalue ~= nil and issecretvalue(v) and true or false
end

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = eventHandlers[event]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], event, ...)
        if not ok then ET:Debug("error in", event, err) end
    end
end)

-------------------------------------------------------------------------------
-- Internal messages (module-to-module notifications)
-------------------------------------------------------------------------------
local messageHandlers = {}

function ET:On(message, fn)
    local list = messageHandlers[message]
    if not list then
        list = {}
        messageHandlers[message] = list
    end
    list[#list + 1] = fn
end

function ET:Fire(message, ...)
    local list = messageHandlers[message]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], ...)
        if not ok then ET:Debug("error in message", message, err) end
    end
end

-------------------------------------------------------------------------------
-- Output
-------------------------------------------------------------------------------
local PREFIX = "|cffff3030Enemy Tracker|r: "

function ET:Print(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. table.concat(parts, " "))
end

function ET:Debug(...)
    if not (self.db and self.db.settings and self.db.settings.debug) then return end
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    DEFAULT_CHAT_FRAME:AddMessage("|cff888888[ET debug]|r " .. table.concat(parts, " "))
end

-------------------------------------------------------------------------------
-- UTF-8 aware case mapping (Latin, Latin-1 Supplement, Cyrillic).
-- string.lower() only handles ASCII, which would break Cyrillic names.
-------------------------------------------------------------------------------
local function lowerCp(cp)
    if cp >= 0x41 and cp <= 0x5A then return cp + 32 end                       -- A-Z
    if cp >= 0xC0 and cp <= 0xDE and cp ~= 0xD7 then return cp + 32 end        -- À-Þ
    if cp >= 0x410 and cp <= 0x42F then return cp + 32 end                      -- А-Я
    if cp >= 0x400 and cp <= 0x40F then return cp + 80 end                      -- Ѐ-Џ (Ё)
    return cp
end

local function upperCp(cp)
    if cp >= 0x61 and cp <= 0x7A then return cp - 32 end
    if cp >= 0xE0 and cp <= 0xFE and cp ~= 0xF7 then return cp - 32 end
    if cp >= 0x430 and cp <= 0x44F then return cp - 32 end
    if cp >= 0x450 and cp <= 0x45F then return cp - 80 end
    return cp
end

local function encode(cp)
    if cp < 0x80 then return string.char(cp) end
    if cp < 0x800 then
        return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
    end
    if cp < 0x10000 then
        return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
    end
    return string.char(0xF0 + math.floor(cp / 0x40000), 0x80 + math.floor(cp / 0x1000) % 0x40,
        0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
end

-- Iterates UTF-8 characters; returns list of codepoints (invalid bytes kept as-is).
local function codepoints(s)
    local cps, i, n = {}, 1, #s
    while i <= n do
        local c = s:byte(i)
        local len, cp
        if c < 0x80 then len, cp = 1, c
        elseif c >= 0xC2 and c <= 0xDF then len, cp = 2, c - 0xC0
        elseif c >= 0xE0 and c <= 0xEF then len, cp = 3, c - 0xE0
        elseif c >= 0xF0 and c <= 0xF4 then len, cp = 4, c - 0xF0
        else len, cp = 1, c end
        if len > 1 then
            for j = 1, len - 1 do
                local b = s:byte(i + j)
                if not b or b < 0x80 or b > 0xBF then len, cp = 1, c; break end
                cp = cp * 0x40 + (b - 0x80)
            end
        end
        cps[#cps + 1] = cp
        i = i + len
    end
    return cps
end

local function mapString(s, firstFn, restFn)
    local cps = codepoints(s)
    local out = {}
    for i = 1, #cps do
        local fn = (i == 1) and firstFn or restFn
        out[i] = encode(fn(cps[i]))
    end
    return table.concat(out)
end

function ET.Utf8Lower(s) return mapString(s, lowerCp, lowerCp) end

-------------------------------------------------------------------------------
-- Player names. On WoW Forever every character has a first name and a
-- surname ("Ivan Petrov"); there are no realms. UnitName(unit) returns the
-- two parts as separate values, some UI text joins them with a hyphen
-- ("Ivan-Petrov"). Internally a name is always "First Surname".
-------------------------------------------------------------------------------
local function trim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
ET.Trim = trim

local NAME_PART_MIN, NAME_PART_MAX = 2, 12 -- characters per part (Forever rule)

-- Canonical spelling of user input or client text: single spaces,
-- "First-Surname" turned into "First Surname", any "-Realm" suffix dropped.
-- Case is left untouched. Returns nil for secret or non-string values.
function ET.NormalizeName(name)
    if ET.IsSecret(name) or type(name) ~= "string" then return nil end
    name = trim(name):gsub("%s+", " ")
    if not name:find(" ", 1, true) then
        name = name:gsub("%-", " ", 1)
    end
    name = name:gsub("%-.*$", "")
    return trim(name)
end

-- Returns lookup key (case-insensitive) or nil if the name is not usable.
local keyCache, keyCacheSize = {}, 0
function ET.NameKey(name)
    if ET.IsSecret(name) or type(name) ~= "string" or name == "" then return nil end
    local key = keyCache[name]
    if key then return key end
    key = ET.Utf8Lower(ET.NormalizeName(name))
    if key == "" then return nil end
    if keyCacheSize > 1000 then wipe(keyCache); keyCacheSize = 0 end
    keyCache[name] = key
    keyCacheSize = keyCacheSize + 1
    return key
end

local function usable(v)
    return v ~= nil and not ET.IsSecret(v) and type(v) == "string" and v ~= ""
end

-- Full name ("First Surname") of a unit if it exists, is a player, and the
-- client exposes the data as normal (non-secret) values; otherwise nil.
function ET.PlayerName(unit)
    local exists = UnitExists(unit)
    if ET.IsSecret(exists) or not exists then return nil end
    local isPlayer = UnitIsPlayer(unit)
    if ET.IsSecret(isPlayer) or not isPlayer then return nil end
    local name, surname = UnitName(unit)
    if not usable(name) or name == (_G.UNKNOWNOBJECT or "Unknown") then
        return nil
    end
    if usable(surname) then name = name .. " " .. surname end
    return name
end

function ET.IsSelfName(name)
    local me = ET.PlayerName("player")
    return me ~= nil and ET.NameKey(me) == ET.NameKey(name)
end

-- Display form: each part capitalised, rest lower case (Forever naming rule).
function ET.DisplayName(name)
    name = ET.NormalizeName(name) or ""
    local parts = {}
    for part in name:gmatch("%S+") do
        parts[#parts + 1] = mapString(part, upperCp, lowerCp)
    end
    return table.concat(parts, " ")
end

local function charCount(s) return #(s:gsub("[\128-\191]", "")) end

-- One name part: 2-12 letters. Non-ASCII characters are accepted as letters
-- (accented and Cyrillic names); ASCII digits, spaces and punctuation are not.
local function isValidPart(part)
    local n = charCount(part)
    if n < NAME_PART_MIN or n > NAME_PART_MAX then return false end
    return part:gsub("[\128-\255]", ""):find("^%a*$") ~= nil
end

-- A character name is exactly two parts: "First Surname".
function ET.IsValidName(name)
    name = ET.NormalizeName(name)
    if not name then return false end
    local first, surname = name:match("^(%S+) (%S+)$")
    return first ~= nil and isValidPart(first) and isValidPart(surname)
end

-------------------------------------------------------------------------------
-- Time formatting
-------------------------------------------------------------------------------
function ET.FormatDate(ts)
    if not ts or ts == 0 then return ET.L.NEVER end
    return date("%d.%m.%Y %H:%M", ts)
end

function ET.FormatAgo(ts)
    if not ts or ts == 0 then return ET.L.NEVER end
    local diff = time() - ts
    if diff < 60 then return ET.L.JUST_NOW end
    if diff < 3600 then return string.format(ET.L.MIN_AGO, math.floor(diff / 60)) end
    if diff < 86400 then return string.format(ET.L.HOURS_AGO, math.floor(diff / 3600)) end
    return ET.FormatDate(ts)
end

-------------------------------------------------------------------------------
-- Small UI helpers shared by modules
-------------------------------------------------------------------------------
ET.BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

-- Creates a frame with a backdrop on both old and new (BackdropTemplate) clients.
function ET.CreateBackdropFrame(frameType, name, parent, template)
    local tpl = template
    if BackdropTemplateMixin then
        tpl = tpl and (tpl .. ",BackdropTemplate") or "BackdropTemplate"
    end
    local f = CreateFrame(frameType, name, parent, tpl)
    if f.SetBackdrop then f:SetBackdrop(ET.BACKDROP) end
    return f
end

-- Positions are stored as the frame's top-left corner in UIParent units, so
-- they survive changes of the frame's own scale and of the UI scale.
function ET.SavePosition(frame, store)
    local left, top = frame:GetLeft(), frame:GetTop()
    if not left or not top then return end
    local ratio = frame:GetEffectiveScale() / UIParent:GetEffectiveScale()
    store.x, store.y = left * ratio, top * ratio
end

function ET.RestorePosition(frame, store, defPoint, defX, defY)
    frame:ClearAllPoints()
    if store and store.x and store.y then
        local ratio = UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", store.x * ratio, store.y * ratio)
    else
        frame:SetPoint(defPoint, UIParent, defPoint, defX or 0, defY or 0)
    end
end

-------------------------------------------------------------------------------
-- Lifecycle
-------------------------------------------------------------------------------
ET:RegisterEvent("ADDON_LOADED", function(_, name)
    if name ~= ADDON_NAME then return end
    ET:InitDatabase()
    ET:Fire("DB_READY")
end)

ET:RegisterEvent("PLAYER_LOGIN", function()
    ET:Fire("LOGIN")
end)
