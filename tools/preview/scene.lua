-- Builds a scene file for the preview renderer: luajit scene.lua <scene lua file> <out.json>
-- A scene file returns { buildings = { { outer = ..., holes = ..., tags = ..., parts = ..., base = ... }, ... },
--   ground = { size = metres, material = "GRASS" } }
package.path = "./?.lua;./?/init.lua;" .. package.path
local o2w = require("o2w")
local scene = dofile(arg[1])
local out = o2w.collector()
for _, b in ipairs(scene.buildings) do
  o2w.building(b, out, { on_error = function(e) io.stderr:write("building failed: " .. tostring(e) .. "\n") end })
end
if scene.ground then
  local s, m = scene.ground.size, scene.ground.material or "GRASS"
  local mat = o2w.materials[m]
  local c = { 200, 200, 200 }
  out:tri(m, -s, -s, 0, -s / mat.w, s / mat.h, s, -s, 0, s / mat.w, s / mat.h, s, s, 0, s / mat.w, -s / mat.h, c)
  out:tri(m, -s, -s, 0, -s / mat.w, s / mat.h, s, s, 0, s / mat.w, -s / mat.h, -s, s, 0, -s / mat.w, -s / mat.h, c)
end
local parts = {}
for _, g in ipairs(out:groups()) do
  local d = {}
  for i = 1, g.n * 8 do d[i] = string.format("%.3f", g.d[i]) end
  local m = o2w.materials[g.material]
  parts[#parts + 1] = string.format('{"tex":"%s","alpha":%s,"d":[%s]}', m and m.tex or "", m and m.alpha and "true" or "false", table.concat(d, ","))
end
local cams = {}
for _, c in ipairs(scene.cameras or { { -30, -40, 25, 0, 0, 5 } }) do cams[#cams + 1] = "[" .. table.concat(c, ",") .. "]" end
local f = assert(io.open(arg[2], "w"))
f:write('{"groups":[' .. table.concat(parts, ",") .. '],"cameras":[' .. table.concat(cams, ",") .. ']}')
f:close()
