-- ported from OSM2World ChimneyRoof.java (MIT, Copyright OSM2World contributors)
local req = O2W_REQUIRE or require
local G = req("o2w.geom")
local B = req("o2w.roof.base")
req("o2w.roof.spindle") -- B.extrude_ring_up

local Chimney = B.class(B.Roof)
function Chimney:calculate_preliminary_height() return 0.0 end
function Chimney:get_roof_height_at(pos) return 0 end

-- GLOBAL_X_Z tex coords
local function global_xz(tris, w, h)
  local uvs = {}
  for i, t in ipairs(tris) do
    uvs[i] = { t[1][1] / w, t[1][2] / h, t[2][1] / w, t[2][2] / h, t[3][1] / w, t[3][2] / h }
  end
  return uvs
end

-- the top of a chimney: a ring around a 3 m deep hole (VOID material at the bottom).
-- returns the smoke emitter position { x, y, z } as the second result
function Chimney:render(out, base_ele, colour, light)
  base_ele = base_ele or 0
  local hole_ele = base_ele - 3.0
  local outer = self.original.outer
  local hole = G.make_ccw(G.scale(outer, 0.8))
  local w, h = B.mat_size(out, self.material)
  -- the area around the hole (earcut's triangles, made counter-clockwise)
  local tris = {}
  for _, t in ipairs(G.triangulate_earcut(outer, { hole })) do
    t = G.tri_ccw(t)
    tris[#tris + 1] = { { t[1].x, t[1].y, base_ele }, { t[2].x, t[2].y, base_ele }, { t[3].x, t[3].y, base_ele } }
  end
  B.emit(out, self.material, tris, global_xz(tris, w, h), colour, light)
  -- the walls of the hole: the reversed hole outline extruded up (TEX_HEIGHT_ALONG_PATH)
  local ring = {}
  local rev = {}
  for i = #hole, 1, -1 do rev[#rev + 1] = hole[i] end
  ring[1] = hole[1]
  for i = 1, #rev do ring[#ring + 1] = rev[i] end
  local wt, raw = B.extrude_ring_up(ring, 0, 0, { hole_ele, base_ele }, { 1, 1 })
  local uvs = {}
  for i, t in ipairs(raw) do uvs[i] = { t[2] / w, t[1] / h, t[4] / w, t[3] / h, t[6] / w, t[5] / h } end
  B.emit(out, self.material, wt, uvs, colour, light)
  -- the bottom of the hole
  local bottom = {}
  for _, t in ipairs(G.ring_triangulation(hole)) do
    bottom[#bottom + 1] = { { t[1].x, t[1].y, hole_ele }, { t[2].x, t[2].y, hole_ele }, { t[3].x, t[3].y, hole_ele } }
  end
  local void = out.materials and out.materials.VOID and "VOID" or self.material
  B.emit(out, void, bottom, global_xz(bottom, 1, 1), { 0, 0, 0 }, nil)
  local c = G.center(hole)
  return tris, { c.x, c.y, hole_ele }
end

return function(poly, tags, material)
  local r = setmetatable({}, Chimney)
  B.Roof.init(r, poly, tags, material)
  return r
end
