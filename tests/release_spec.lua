-- Release metadata stays consistent: the .toc version, the in-game version
-- and the changelog agree, and every file the .toc loads exists.
local H = require("harness")
local eq, ok = H.eq, H.ok

local function read(path)
    local f = assert(io.open(H.ADDON_DIR .. path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

local function tocField(name)
    return read("EnemyTracker.toc"):match("## " .. name .. ": *([^\r\n]+)")
end

return {
    { "the .toc version matches the in-game version", function()
        local ET = H.boot()
        eq(tocField("Version"), ET.version)
    end },

    { "the changelog has a section for this version", function()
        local v = tocField("Version")
        ok(read("CHANGELOG.md"):find("\n## " .. v:gsub("%.", "%%.") .. "\r?\n"), "## " .. v)
    end },

    { "every file the .toc loads exists", function()
        for line in read("EnemyTracker.toc"):gmatch("[^\r\n]+") do
            if not line:match("^%s*#") and line:match("%S") then
                ok(io.open(H.ADDON_DIR .. line, "rb"), "missing " .. line)
            end
        end
    end },

}
