-- Test runner. Usage (from the repository root):  luajit tests/run_tests.lua [filter]
-- Runs every tests/*_spec.lua. Each spec file returns a list of
-- { "test name", function() ... end }. Exit code 1 on any failure.
local scriptDir = (arg and arg[0] or ""):match("^(.*)[/\\]") or "."
ROOT_DIR = scriptDir .. "/.."
package.path = scriptDir .. "/?.lua;" .. package.path

local filter = arg and arg[1]

local function listSpecs()
    local cmd = package.config:sub(1, 1) == "\\"
        and ('dir /b "' .. scriptDir:gsub("/", "\\") .. '"')
        or ('ls "' .. scriptDir .. '"')
    local files = {}
    local p = assert(io.popen(cmd))
    for name in p:lines() do
        if name:match("_spec%.lua$") then files[#files + 1] = name end
    end
    p:close()
    table.sort(files)
    return files
end

local passed, failed = 0, {}
for _, file in ipairs(listSpecs()) do
    local tests = dofile(scriptDir .. "/" .. file)
    for _, t in ipairs(tests) do
        local name = file:gsub("_spec%.lua$", "") .. ": " .. t[1]
        if not filter or name:find(filter, 1, true) then
            local ok, err = xpcall(t[2], debug.traceback)
            if ok then
                passed = passed + 1
            else
                failed[#failed + 1] = name .. "\n    " .. tostring(err):gsub("\n", "\n    ")
            end
        end
    end
end

for _, f in ipairs(failed) do print("FAIL " .. f) end
print(string.format("%d passed, %d failed", passed, #failed))
os.exit(#failed == 0 and 0 or 1)
