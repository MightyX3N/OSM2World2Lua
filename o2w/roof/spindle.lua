-- ported from OSM2World SpindleRoof.java, DomeRoof.java, OnionRoof.java and the parts of ExtrusionGeometry.java
-- they use (MIT, Copyright OSM2World contributors)
local req = O2W_REQUIRE or require
local G = req("o2w.geom")
local B = req("o2w.roof.base")
local sqrt = math.sqrt

local Spindle = B.class(B.Roof)
function Spindle:get_roof_height_at(pos) return 0 end

local function d3(a, b)
  local x, y, z = b[1] - a[1], b[2] - a[2], b[3] - a[3]
  return sqrt(x * x + y * y + z * z)
end

-- ExtrusionGeometry for a closed ring (closing vertex repeated) extruded straight up with scale factors,
-- no caps. ring: vertices relative to centre; returns triangles and raw tex coords
function B.extrude_ring_up(ring, cx, cy, heights, scales)
  local n1 = #ring
  local rings = {}
  for k, z in ipairs(heights) do
    local s, r = scales[k], {}
    for j = 1, n1 do
      local v = ring[j]
      if s == 0 then r[j] = { cx, cy, z } else r[j] = { v.x * s + cx, v.y * s + cy, z } end
    end
    rings[k] = r
  end
  local across = 0
  for j = 1, n1 - 1 do across = across + G.dist(ring[j], ring[j + 1]) end
  local tcs = {}
  for k = 1, #heights do
    local t = {}
    for j = 1, n1 do
      local along = 0
      for i = 1, k - 1 do along = along + d3(rings[i][j], rings[i + 1][j]) end
      t[j] = { along, across / n1 * (j - 1) }
    end
    tcs[k] = t
  end
  local tris, uvs = {}, {}
  local function put(a, b, c, ta, tb, tc)
    tris[#tris + 1] = { a, b, c }
    uvs[#uvs + 1] = { ta[1], ta[2], tb[1], tb[2], tc[1], tc[2] }
  end
  for k = 1, #heights - 1 do
    local sa, sb = scales[k], scales[k + 1]
    local A, Bv, TA, TB = rings[k], rings[k + 1], tcs[k], tcs[k + 1]
    if sa ~= 0 and sb ~= 0 then
      -- triangle strip B1, A1, B2, A2, ...
      local strip, tstrip = {}, {}
      for j = 1, n1 do
        strip[#strip + 1] = Bv[j]; strip[#strip + 1] = A[j]
        tstrip[#tstrip + 1] = TB[j]; tstrip[#tstrip + 1] = TA[j]
      end
      for t = 1, #strip - 2 do
        if t % 2 == 1 then
          put(strip[t], strip[t + 1], strip[t + 2], tstrip[t], tstrip[t + 1], tstrip[t + 2])
        else
          put(strip[t], strip[t + 2], strip[t + 1], tstrip[t], tstrip[t + 2], tstrip[t + 1])
        end
      end
    elseif sa ~= 0 then
      for j = 1, n1 - 1 do
        local m = { (TB[j][1] + TB[j + 1][1]) * 0.5, (TB[j][2] + TB[j + 1][2]) * 0.5 }
        put(A[j], A[j + 1], Bv[1], TA[j], TA[j + 1], m)
      end
    elseif sb ~= 0 then
      for j = 1, n1 - 1 do
        local m = { (TA[j][1] + TA[j + 1][1]) * 0.5, (TA[j][2] + TA[j + 1][2]) * 0.5 }
        put(Bv[j + 1], Bv[j], A[1], TB[j + 1], TB[j], m)
      end
    end
  end
  return tris, uvs
end

function Spindle:render(out, base_ele, colour, light)
  base_ele = base_ele or 0
  local heights, scales = {}, {}
  local h = self:roof_height()
  for i, st in ipairs(self.steps) do
    heights[i] = base_ele + st[1] * h
    scales[i] = st[2]
  end
  local poly = G.make_cw(self.original.outer)
  local center = G.center(poly)
  local shape = {}
  for i, v in ipairs(G.make_ccw(poly)) do shape[i] = G.V(v.x - center.x, v.y - center.y) end
  shape[#shape + 1] = shape[1]
  local tris, raw = B.extrude_ring_up(shape, center.x, center.y, heights, scales)
  local w, th = B.mat_size(out, self.material)
  local uvs = {}
  for i, t in ipairs(raw) do uvs[i] = { t[1] / w, t[2] / th, t[3] / w, t[4] / th, t[5] / w, t[6] / th } end
  B.emit(out, self.material, tris, uvs, colour, light)
  return tris
end

local M = {}

local DOME_STEPS = {}
for ring = 0, 9 do
  local rel = ring / 9
  DOME_STEPS[#DOME_STEPS + 1] = { rel, sqrt(1.0 - rel * rel) }
end
local ONION_STEPS = { { 0.0, 1.0 }, { 0.15, 0.8 }, { 0.52, 1.0 }, { 0.72, 0.7 }, { 0.82, 0.15 }, { 1.00, 0.0 } }

M.dome = function(poly, tags, material)
  local r = setmetatable({}, Spindle); B.Roof.init(r, poly, tags, material); r.steps = DOME_STEPS; return r
end
M.onion = function(poly, tags, material)
  local r = setmetatable({}, Spindle); B.Roof.init(r, poly, tags, material); r.steps = ONION_STEPS; return r
end

return M
