-- usage (from the repo root): luajit tests/test_basic.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
local o2w = require("o2w")
local fails = 0
local function check(c, msg) if not c then fails = fails + 1; print("FAIL " .. msg) end end

-- a box: 4 walls (2 triangles each), a window layer on each wall, a flat roof (2 triangles)
local out = o2w.collector()
local L = o2w.building({ outer = { 0, 0, 10, 0, 10, 8, 0, 8 }, tags = { building = "yes", height = "12", ["building:levels"] = "4" }, base = 2 }, out)
local by = {}
for _, g in ipairs(out:groups()) do by[g.material] = (by[g.material] or 0) + g.n / 3 end
check(by.BUILDING_DEFAULT == 8, "walls: 8 triangles, got " .. tostring(by.BUILDING_DEFAULT))
check(by.BUILDING_WINDOWS == 8, "windows: 8 triangles, got " .. tostring(by.BUILDING_WINDOWS))
-- an untagged roof shape is flat with OSM2World's ROOF_DEFAULT material (CONCRETE only when roof:shape=flat is tagged)
check(by.ROOF_DEFAULT == 2, "roof: 2 triangles, got " .. tostring(by.ROOF_DEFAULT))
check(L.levels == 4 and math.abs(L.level_height - 3) < 1e-9, "4 levels of 3 m")
-- walls face outwards: the triangle normal points away from the centre
for _, g in ipairs(out:groups()) do
  if g.material == "BUILDING_DEFAULT" then
    local d = g.d
    for t = 0, g.n / 3 - 1 do
      local o = t * 24
      local ux, uy, uz = d[o + 9] - d[o + 1], d[o + 10] - d[o + 2], d[o + 11] - d[o + 3]
      local vx, vy, vz = d[o + 17] - d[o + 1], d[o + 18] - d[o + 2], d[o + 19] - d[o + 3]
      local nx, ny = uy * vz - uz * vy, uz * vx - ux * vz
      local cx, cy = (d[o + 1] + d[o + 9] + d[o + 17]) / 3 - 5, (d[o + 2] + d[o + 10] + d[o + 18]) / 3 - 4
      check(nx * cx + ny * cy > 0, "wall triangle facing in")
    end
  end
end
-- a clockwise outline with a courtyard gives the same counts plus the courtyard walls
local out2 = o2w.collector()
o2w.building({ outer = { 0, 0, 0, 20, 20, 20, 20, 0 }, holes = { { 5, 5, 15, 5, 15, 15, 5, 15 } }, tags = { building = "apartments" } }, out2)
local n = 0
for _, g in ipairs(out2:groups()) do if g.material == "ROOF_DEFAULT" then n = n + g.n / 3 end end
check(n == 8, "roof with a courtyard: 8 triangles, got " .. n)
-- roof area equals outline minus courtyard
local area = 0
for _, g in ipairs(out2:groups()) do
  if g.material == "ROOF_DEFAULT" then
    local d = g.d
    for t = 0, g.n / 3 - 1 do
      local o = t * 24
      area = area + ((d[o + 9] - d[o + 1]) * (d[o + 18] - d[o + 2]) - (d[o + 17] - d[o + 1]) * (d[o + 10] - d[o + 2])) / 2
    end
  end
end
check(math.abs(area - 300) < 1e-6, "roof area 300, got " .. area)
-- colours
check(o2w.colour("#bd8161")[1] == 189 and o2w.colour("firebrick")[1] == 178 and o2w.colour("nope") == nil, "colours")
print(fails == 0 and "OK" or (fails .. " failures"))
