-- ported from OSM2World Roof.java, HeightfieldRoof.java, RoofWithInnerLines.java, RoofWithRidge.java and
-- SlopedTrianglesTexCoordFunction.java (MIT, Copyright OSM2World contributors)
local req = O2W_REQUIRE or require
local G = req("o2w.geom")
local V, seg, sub, add, mult, dist = G.V, G.seg, G.sub, G.add, G.mult, G.dist
local sqrt, abs, tan, pi, huge, sin, cos = math.sqrt, math.abs, math.tan, math.pi, math.huge, math.sin, math.cos

local B = {}

B.DEFAULT_RIDGE_HEIGHT = 5 -- BuildingPart.DEFAULT_RIDGE_HEIGHT

---------------------------------------------------------------- texture coordinates and output

-- SlopedTrianglesTexCoordFunction over a list of triangles { {x,y,z}, {x,y,z}, {x,y,z} } (z up).
-- Works in OSM2World's own axes (x, y up, z north); returns { u1, v1, u2, v2, u3, v3 } per triangle.
function B.sloped_tex_coords(tris, w, h)
  local res, known = {}, {}
  for ti, t in ipairs(tris) do
    local a, b, c = t[1], t[2], t[3]
    -- getNormal: (v2 - v1) x (v2 - v3) with Java vectors (x, up, north)
    local ux, uy, uz = b[1] - a[1], b[3] - a[3], b[2] - a[2]
    local vx, vy, vz = b[1] - c[1], b[3] - c[3], b[2] - c[2]
    local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
    local l = sqrt(nx * nx + ny * ny + nz * nz)
    nx, nz = nx / l, nz / l
    local down = 0
    if nx ~= 0 or nz ~= 0 then
      down = G.angle(V(nx, nz))
      local similar
      for _, k in ipairs(known) do
        if abs(down - k) < 0.02 then similar = k; break end
      end
      if similar == nil then known[#known + 1] = down else down = similar end
    end
    local s, co = sin(-down), cos(-down)
    local uv = {}
    for k = 1, 3 do
      local p = t[k]
      local x, z = p[1], p[2]
      local bx, bz = s * z + co * x, co * z - s * x
      uv[#uv + 1] = -bx / w
      uv[#uv + 1] = -bz / h
    end
    res[ti] = uv
  end
  return res
end

-- emits triangles (counter-clockwise from outside) with per-triangle light; uv in OSM2World's convention
-- (origin bottom left), stored with v negated like collector:quad does
function B.emit(out, mat, tris, uvs, colour, light)
  colour = colour or { 255, 255, 255 }
  for i, t in ipairs(tris) do
    local a, b, c = t[1], t[2], t[3]
    local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
    local vx, vy, vz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
    local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
    local l = sqrt(nx * nx + ny * ny + nz * nz)
    if l > 0 then nx, ny, nz = nx / l, ny / l, nz / l end
    local f = light and light(nx, ny, nz) or 1
    local col = { colour[1] * f, colour[2] * f, colour[3] * f }
    local uv = uvs[i]
    out:tri(mat, a[1], a[2], a[3], uv[1], -uv[2], b[1], b[2], b[3], uv[3], -uv[4], c[1], c[2], c[3], uv[5], -uv[6], col)
  end
end

function B.mat_size(out, mat)
  local m = out and out.materials and out.materials[mat]
  return (m and m.w) or 1, (m and m.h) or 1
end

---------------------------------------------------------------- Roof

local Roof = {}
Roof.__index = Roof
B.Roof = Roof

function B.class(parent)
  local c = setmetatable({}, { __index = parent })
  c.__index = c
  c.super = parent
  return c
end

function Roof.init(self, poly, tags, material)
  self.original = poly
  self.tags = tags or {}
  self.material = material
end

-- Roof.calculatePreliminaryHeight (roof:angle is not supported by the generic roof)
function Roof:calculate_preliminary_height()
  return G.parse_measure(self.tags["roof:height"])
end

function Roof:roof_height()
  if self._height == nil then self._height = self:calculate_preliminary_height() end
  return self._height or 0
end

function Roof:get_polygon() return self.original end
function Roof:get_inner_segments() return {} end

-- public interface
local function poly_to_flat(P)
  local holes = {}
  for i, h in ipairs(P.holes or {}) do holes[i] = G.ring_to_flat(h) end
  return { outer = G.ring_to_flat(P.outer), holes = holes }
end
function Roof:polygon() return poly_to_flat(self:get_polygon()) end
function Roof:inner_segments()
  local res = {}
  for i, s in ipairs(self:get_inner_segments()) do res[i] = { s.p1.x, s.p1.y, s.p2.x, s.p2.y } end
  return res
end
function Roof:preliminary_height() return self:calculate_preliminary_height() end
function Roof:set_height(h) self._height = h end
function Roof:height()
  if self._height ~= nil then return self._height end
  return self:calculate_preliminary_height()
end
function Roof:height_at(x, y) return self:get_roof_height_at(V(x, y)) end

---------------------------------------------------------------- HeightfieldRoof

local HeightfieldRoof = B.class(Roof)
B.HeightfieldRoof = HeightfieldRoof
B.SNAP_DISTANCE = 0.01

function HeightfieldRoof:get_roof_height_at(v)
  local ele = self:height_at_no_interpolation(v)
  if ele ~= nil then return ele end
  local segs = {}
  for _, s in ipairs(self:get_inner_segments()) do segs[#segs + 1] = s end
  local P = self:get_polygon()
  for _, s in ipairs(G.segments(P.outer)) do segs[#segs + 1] = s end
  for _, h in ipairs(P.holes or {}) do
    for _, s in ipairs(G.segments(h)) do segs[#segs + 1] = s end
  end
  local best, bd = nil, 1.7976931348623157e308
  for _, s in ipairs(segs) do
    local d = G.distance_from_segment(v, s)
    if d < bd then best, bd = s, d end
  end
  local h1, h2 = self:height_at_no_interpolation(best.p1), self:height_at_no_interpolation(best.p2)
  -- OSM2World fails here (NullPointerException, the building is left out), e.g. for pyramidal roofs with holes
  if h1 == nil or h2 == nil then error("no roof height for a point of the roof outline") end
  return G.interpolate_value(v, best.p1, h1, best.p2, h2)
end

-- HeightfieldRoof.getRoofTriangles: list of { {x,y,z}, ... } counter-clockwise
function HeightfieldRoof:roof_triangles(base_ele)
  local P = self:get_polygon()
  local faces = G.split_polygon_into_faces(P.outer, P.holes or {}, self:get_inner_segments())
  local res = {}
  for _, f in ipairs(faces) do
    for _, t in ipairs(G.poly_triangulation(f)) do
      t = G.tri_ccw(t)
      local tri = {}
      for k = 1, 3 do
        local v = t[k]
        tri[k] = { v.x, v.y, base_ele + self:get_roof_height_at(v) }
      end
      res[#res + 1] = tri
    end
  end
  return res
end

function HeightfieldRoof:render(out, base_ele, colour, light)
  local tris = self:roof_triangles(base_ele or 0)
  -- OSM2World throws here (and leaves out the whole building) when nothing is left to draw
  if #tris == 0 then error("empty roof geometry") end
  local w, h = B.mat_size(out, self.material)
  B.emit(out, self.material, tris, B.sloped_tex_coords(tris, w, h), colour, light)
  return tris
end

---------------------------------------------------------------- RoofWithInnerLines

local RoofWithInnerLines = B.class(HeightfieldRoof)
B.RoofWithInnerLines = RoofWithInnerLines

-- InnerLine(segment, extendAtStart, extendAtEnd)
function B.inner_line(s, ext_start, ext_end)
  if ext_end == nil then ext_end = ext_start end
  return { segment = s, ext_start = ext_start or false, ext_end = ext_end or false }
end

local function extended_segment(il)
  local s = il.segment
  if not il.ext_start and not il.ext_end then return s end
  local d = G.seg_dir(s)
  return seg(il.ext_start and add(s.p1, mult(d, -0.05)) or s.p1, il.ext_end and add(s.p2, mult(d, 0.05)) or s.p2)
end

-- calculatePolygonAndInnerSegments (cached: it only depends on the constructor's results)
function RoofWithInnerLines:calculate()
  if self._calc then return self._calc end
  local SNAP = B.SNAP_DISTANCE
  local outer = self.original.outer
  local holes = {}
  for i, h in ipairs(self.original.holes or {}) do holes[i] = h end
  local inner, extra = {}, {}
  for _, il in ipairs(self:get_inner_lines()) do
    local s = extended_segment(il)
    local split = {}
    for _, it in ipairs(G.intersections(outer, s)) do
      outer = G.insert_into_polygon(outer, it.point, SNAP)
      split[#split + 1] = it.point
      extra[G.key(it.point)] = il
    end
    for i = 1, #holes do
      for _, it in ipairs(G.intersections(holes[i], s)) do
        holes[i] = G.insert_into_polygon(holes[i], it.point, SNAP)
        split[#split + 1] = it.point
        extra[G.key(it.point)] = il
      end
    end
    for _, p in ipairs({ s.p1, s.p2 }) do
      local near = false
      for _, sp in ipairs(split) do if dist(sp, p) < SNAP then near = true; break end end
      if not near then split[#split + 1] = p end
    end
    G.stable_sort(split, function(p) return dist(p, s.p1) end)
    for i = 1, #split - 1 do
      local ss = seg(split[i], split[i + 1])
      if G.poly_contains(self.original, G.seg_center(ss)) then inner[#inner + 1] = ss end
    end
  end
  self._calc = { polygon = { outer = outer, holes = holes }, inner = inner, extra = extra }
  return self._calc
end

function RoofWithInnerLines:get_inner_segments() return self:calculate().inner end
function RoofWithInnerLines:get_polygon() return self:calculate().polygon end

---------------------------------------------------------------- Roof.snapDirection, parseRoofAngle

function B.snap_direction(value, segments)
  local deg = G.parse_angle(value)
  if deg == nil then return nil end
  local ang = G.fit_angle(math.rad(deg))
  local best, bd
  for _, s in ipairs(segments) do
    local sa = G.fit_angle(G.angle(G.seg_dir(s)))
    for _, a in ipairs({ sa, G.fit_angle(sa + 0.5 * pi), G.fit_angle(sa + pi), G.fit_angle(sa + 1.5 * pi) }) do
      local d = G.radians_between(a, ang)
      if bd == nil or d < bd then best, bd = a, d end
    end
  end
  value = tostring(value)
  local acceptable
  if value:match("^[NSEW]+$") then acceptable = pi / 4
  elseif not value:find(".", 1, true) then acceptable = pi / 18
  else acceptable = pi / 360 end
  if best ~= nil and bd <= acceptable then return best end
  return ang
end

function B.parse_roof_angle(tags)
  local a = G.parse_osm_decimal(tags["roof:angle"], nil)
  if a ~= nil and a >= 0 and a < 90 then return math.rad(a) end
  return nil
end

---------------------------------------------------------------- RoofWithRidge

local RoofWithRidge = B.class(RoofWithInnerLines)
B.RoofWithRidge = RoofWithRidge

local function ridge_vector_from_roof_orientation(tags, polygon)
  local rect = G.minimum_rotated_bbox(polygon)
  local longest, ll
  for i = 1, 4 do
    local s = seg(rect[i], rect[i % 4 + 1])
    local l = G.seg_length(s)
    if longest == nil or l > ll then longest, ll = s, l end
  end
  local r = G.normalize(sub(longest.p2, longest.p1))
  if tags["roof:orientation"] == "across" then r = G.right_normal(r) end
  return r
end

-- RoofWithRidge.ridgeDirectionFromTags
function B.ridge_direction_from_tags(tags, along, simplified, default_dir)
  local dir
  local a = B.snap_direction(tags["roof:direction"], G.segments(simplified))
  if a ~= nil then
    dir = along and G.from_angle(a) or G.right_normal(G.from_angle(a))
  end
  if dir == nil then
    local a2 = B.snap_direction(tags["roof:ridge:direction"], G.segments(simplified))
    if a2 ~= nil then dir = G.from_angle(a2) end
  end
  if dir == nil then
    if default_dir == nil then
      dir = ridge_vector_from_roof_orientation(tags, simplified)
    elseif tags["roof:orientation"] ~= nil then
      dir = ridge_vector_from_roof_orientation(tags, simplified)
      if G.angle_between(dir, default_dir) > 0.9 * pi then dir = G.invert(dir) end
    else
      dir = default_dir
    end
  end
  return dir
end

-- relative offsets: distance of the ridge ends to the outline relative to the cap length;
-- along: ridge goes along roof:direction; loc: ridge position from front (0) to back (1), default 0.5
function RoofWithRidge.init(self, poly, tags, material, off1, off2, along, loc, default_dir)
  Roof.init(self, poly, tags, material)
  loc = loc or 0.5
  local outer = poly.outer
  local simplified = G.simplified_polygon(outer)
  local dir = B.ridge_direction_from_tags(self.tags, along, simplified, default_dir)
  local bbox = G.rotated_bbox(outer, G.fit_angle(G.angle(dir)))
  local p1 = G.centroid(outer)
  local to_back = seg(bbox[4], bbox[1])
  p1 = add(p1, mult(sub(to_back.p2, to_back.p1), loc - 0.5))
  local diam = G.rect_diameter(bbox)
  local line = seg(add(p1, mult(dir, -diam)), add(p1, mult(dir, diam)))
  local inters = G.intersections(simplified, line)
  if #inters < 2 then error("cannot handle roof geometry") end
  G.stable_sort(inters, function(i) return dist(i.point, line.p1) end)
  local i1, i2 = inters[1], inters[#inters]
  local c1, c2 = i1.point, i2.point
  self.ridge_offset1 = math.min(G.seg_length(i1.segment) * off1, 0.4 * dist(c1, c2))
  self.ridge_offset2 = math.min(G.seg_length(i2.segment) * off2, 0.4 * dist(c1, c2))
  if self.ridge_offset1 == 0 and self.ridge_offset2 == 0 then
    self.ridge = seg(c1, c2)
  else
    self.ridge = seg(add(c1, mult(G.normalize(sub(p1, c1)), self.ridge_offset1)),
      add(c2, mult(G.normalize(sub(p1, c2)), self.ridge_offset2)))
  end
  local r = self.ridge
  self.cap1 = G.is_right_of(i1.segment.p2, r.p1, r.p2) and i1.segment or G.seg_reverse(i1.segment)
  self.cap2 = G.is_right_of(i2.segment.p2, r.p1, r.p2) and i2.segment or G.seg_reverse(i2.segment)
  local m = -huge
  for _, v in ipairs(outer) do m = math.max(m, G.distance_from_segment(v, r)) end
  self.max_distance_to_ridge = m
end

function RoofWithRidge:calculate_preliminary_height()
  local h = G.parse_measure(self.tags["roof:height"])
  if h == nil then
    local a = B.parse_roof_angle(self.tags)
    if a ~= nil then h = tan(a) * self.max_distance_to_ridge end
  end
  return h
end

return B
