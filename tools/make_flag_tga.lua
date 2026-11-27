-- Generates Media/Flag.tga: the 32x32 red flag shown next to blacklisted
-- players. Usage (from the repository root): luajit tools/make_flag_tga.lua
local SIZE = 32
local OUT = (arg and arg[1]) or "Media/Flag.tga"

local function px(r, g, b, a) return { r, g, b, a } end
local CLEAR = px(0, 0, 0, 0)
local POLE, POLE_EDGE = px(225, 225, 225, 255), px(60, 60, 60, 255)
local CLOTH, CLOTH_EDGE = px(225, 30, 30, 255), px(120, 0, 0, 255)

-- Image in top-left coordinates: img[y][x], 0-based.
local img = {}
for y = 0, SIZE - 1 do
    img[y] = {}
    for x = 0, SIZE - 1 do img[y][x] = CLEAR end
end

-- Swallow-tailed cloth: rows 4..17, from the pole to x = 27 minus a notch.
local function clothEnd(y) return 27 - math.max(0, 4 - math.abs(y - 10.5)) end
local function inCloth(x, y) return y >= 4 and y <= 17 and x >= 9 and x <= clothEnd(y) end

for y = 0, SIZE - 1 do
    for x = 0, SIZE - 1 do
        if inCloth(x, y) then
            local edge = not (inCloth(x - 1, y) and inCloth(x + 1, y) and inCloth(x, y - 1) and inCloth(x, y + 1))
            img[y][x] = edge and CLOTH_EDGE or CLOTH
        end
    end
end
for y = 3, 29 do
    img[y][5], img[y][6], img[y][7], img[y][8] = POLE_EDGE, POLE, POLE, POLE_EDGE
end
img[2][6], img[2][7] = POLE_EDGE, POLE_EDGE
img[30][6], img[30][7] = POLE_EDGE, POLE_EDGE

-- Uncompressed true-colour TGA, 32 bpp BGRA, bottom-left origin.
local header = string.char(
    0, 0, 2,                     -- no id, no colour map, uncompressed true-colour
    0, 0, 0, 0, 0,               -- colour map spec
    0, 0, 0, 0,                  -- x/y origin
    SIZE % 256, math.floor(SIZE / 256), SIZE % 256, math.floor(SIZE / 256),
    32, 8)                       -- 32 bpp, 8 alpha bits, bottom-left origin
local parts = { header }
for y = SIZE - 1, 0, -1 do
    for x = 0, SIZE - 1 do
        local p = img[y][x]
        parts[#parts + 1] = string.char(p[3], p[2], p[1], p[4])
    end
end
local f = assert(io.open(OUT, "wb"))
f:write(table.concat(parts))
f:close()
print("wrote " .. OUT)
