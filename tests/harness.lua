-- Test helpers: assertions and a loader that boots the addon inside a fresh
-- mock environment, the way the client does (files in TOC order, then
-- SavedVariables, ADDON_LOADED, PLAYER_LOGIN).
local mock = require("wowmock")

local H = { mock = mock }

H.ADDON_DIR = (ROOT_DIR or ".") .. "/"
local ADDON_NAME = "EnemyTracker"

local function tocFiles()
    local files = {}
    for line in io.lines(H.ADDON_DIR .. ADDON_NAME .. ".toc") do
        line = line:gsub("\r", "")
        if line ~= "" and not line:match("^##") and line:match("%.lua$") then
            files[#files + 1] = line
        end
    end
    return files
end

-- Boots the addon. opts:
--   savedDB    table placed in EnemyTrackerDB before ADDON_LOADED
--   player     { name, surname, faction, guid } for the "player" unit
--   locale, forbiddenEvents   passed to the mock
--   noLogin    stop after ADDON_LOADED
-- Returns ET (addon namespace) and env (mock globals).
function H.boot(opts)
    opts = opts or {}
    local env = mock.new(opts)
    env._state.units.player = opts.player or { name = "Me", surname = "Myself", faction = "Alliance", guid = "Player-1" }
    local ET = {}
    for _, file in ipairs(tocFiles()) do
        local chunk = assert(loadfile(H.ADDON_DIR .. file))
        setfenv(chunk, env)
        chunk(ADDON_NAME, ET)
    end
    env.EnemyTrackerDB = opts.savedDB
    mock.fire(env, "ADDON_LOADED", ADDON_NAME)
    if not opts.noLogin then mock.fire(env, "PLAYER_LOGIN") end
    return ET, env
end

-- Simulates /reload or a game restart: boots again with the saved data.
function H.reboot(env, opts)
    opts = opts or {}
    opts.savedDB = env.EnemyTrackerDB
    opts.player = opts.player or env._state.units.player
    return H.boot(opts)
end

-------------------------------------------------------------------------------
-- Driving the client
-------------------------------------------------------------------------------
function H.setUnit(env, unit, data) env._state.units[unit] = data end

function H.target(env, data)
    env._state.units.target = data
    mock.fire(env, "PLAYER_TARGET_CHANGED")
end

function H.slash(env, msg) env.SlashCmdList.ENEMYTRACKER(msg) end

function H.chat(env) return env._state.chat end

function H.lastChat(env)
    local c = env._state.chat
    return c[#c]
end

function H.chatContains(env, text)
    for _, line in ipairs(env._state.chat) do
        if line:find(text, 1, true) then return true end
    end
    return false
end

-------------------------------------------------------------------------------
-- Assertions
-------------------------------------------------------------------------------
local function fmt(v)
    if type(v) == "string" then return string.format("%q", v) end
    return tostring(v)
end

function H.eq(actual, expected, msg)
    if actual ~= expected then
        error((msg and (msg .. ": ") or "") .. "expected " .. fmt(expected) .. ", got " .. fmt(actual), 2)
    end
end

function H.ok(value, msg)
    if not value then error(msg or "expected a true value", 2) end
end

function H.no(value, msg)
    if value then error(msg or ("expected a false value, got " .. fmt(value)), 2) end
end

-- Fails if any error was swallowed by the addon's pcall wrappers.
function H.noErrors(env)
    local errs = env._state.errors
    if #errs > 0 then error("swallowed errors:\n  " .. table.concat(errs, "\n  "), 2) end
end

return H
