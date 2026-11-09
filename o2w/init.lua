-- OSM2World2Lua: 3D buildings (and more to come) from OpenStreetMap data, in plain Lua, after OSM2World.
-- No engine code: it produces textured triangle lists that any game turns into its own meshes.
--
--   local o2w = require("o2w")
--   local out = o2w.collector()
--   o2w.building({ outer = { 0,0, 10,0, 10,8, 0,8 }, tags = { building = "yes", height = "12" }, base = 3.5 }, out)
--   for _, g in ipairs(out:groups()) do
--     -- g.material: material name (o2w.materials[g.material].tex is its texture in textures/)
--     -- g.n: vertices; g.d = { x, y, z, u, v, r, g, b, ... } three vertices per triangle, counter-clockwise
--     -- seen from outside; x east, y north, z up, metres; r, g, b 0-255 (colour times light)
--   end
--
-- Loading: plain Lua uses require; a game without require sets O2W_REQUIRE(name) first (name like "o2w.building").
local req = O2W_REQUIRE or require

local M = {}
M.materials = req("o2w.materials")
M.colour = req("o2w.colour")
M.triangulate = req("o2w.triangulate")
local building = req("o2w.building")
M.building_module = building

-- collects triangles by material; opts.max_verts splits groups (e.g. 65535 for engines with 16-bit indices)
function M.collector(opts)
  opts = opts or {}
  local C = { materials = opts.materials or M.materials, max = opts.max_verts or math.huge, list = {}, cur = {} }
  local function group(mat)
    local G = C.cur[mat]
    if not G or G.n + 3 > C.max then
      G = { material = mat, n = 0, d = {} }
      C.cur[mat] = G
      C.list[#C.list + 1] = G
    end
    return G
  end
  local function v(G, x, y, z, u, w, c)
    local d, i = G.d, G.n * 8
    d[i + 1], d[i + 2], d[i + 3], d[i + 4], d[i + 5] = x, y, z, u, w
    d[i + 6], d[i + 7], d[i + 8] = c[1], c[2], c[3]
    G.n = G.n + 1
  end
  function C:tri(mat, x1, y1, z1, u1, v1, x2, y2, z2, u2, v2, x3, y3, z3, u3, v3, c)
    local G = group(mat)
    v(G, x1, y1, z1, u1, v1, c); v(G, x2, y2, z2, u2, v2, c); v(G, x3, y3, z3, u3, v3, c)
  end
  -- an upright quad from (ax, ay) to (bx, by), heights z0..z1, texture u0..u1 along, v0..v1 up
  function C:quad(mat, ax, ay, bx, by, z0, z1, u0, u1, v0, v1, c)
    self:tri(mat, ax, ay, z0, u0, -v0, bx, by, z0, u1, -v0, bx, by, z1, u1, -v1, c)
    self:tri(mat, ax, ay, z0, u0, -v0, bx, by, z1, u1, -v1, ax, ay, z1, u0, -v1, c)
  end
  function C:groups() return self.list end
  return C
end

-- one building (see o2w/building.lua for the fields of b)
function M.building(b, out, opts) return building.build(b, out, opts) end

return M
