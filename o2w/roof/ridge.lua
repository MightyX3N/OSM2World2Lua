-- ported from OSM2World AbstractGabledRoof.java, GabledRoof.java, SaltboxRoof.java, AbstractHippedRoof.java,
-- HippedRoof.java, SideHippedRoof.java, AbstractHalfHippedRoof.java, HalfHippedRoof.java, SideHalfHippedRoof.java,
-- GambrelRoof.java, MansardRoof.java, RoundRoof.java (MIT, Copyright OSM2World contributors)
local req = O2W_REQUIRE or require
local G = req("o2w.geom")
local B = req("o2w.roof.base")
local V, seg = G.V, G.seg
local max, sqrt, floor = math.max, math.sqrt, math.floor
local interp = G.interpolate_between
local RoofWithRidge, inner_line = B.RoofWithRidge, B.inner_line

local M = {}

---------------------------------------------------------------- gabled, saltbox

local AbstractGabled = B.class(RoofWithRidge)
function AbstractGabled.init(self, poly, tags, material, loc)
  RoofWithRidge.init(self, poly, tags, material, 0, 0, false, loc)
end
function AbstractGabled:get_inner_lines() return { inner_line(self.ridge, true) } end
function AbstractGabled:height_at_no_interpolation(pos)
  local rel = G.distance_from_segment(pos, self.ridge) / self.max_distance_to_ridge
  local h = self:roof_height()
  return h - h * rel
end

M.gabled = function(poly, tags, material)
  local r = setmetatable({}, AbstractGabled); AbstractGabled.init(r, poly, tags, material, nil); return r
end
M.saltbox = function(poly, tags, material)
  local r = setmetatable({}, AbstractGabled); AbstractGabled.init(r, poly, tags, material, 0.7); return r
end

---------------------------------------------------------------- hipped, side_hipped

local HIPPED_RIDGE_OFFSET = 1 / 3.0

-- TriangleXYZ.getYAt with (x, north, height) points
local function tri_height_at(v1, v2, v3, pos)
  local a = v1[2] * (v2[3] - v3[3]) + v2[2] * (v3[3] - v1[3]) + v3[2] * (v1[3] - v2[3])
  local b = v1[3] * (v2[1] - v3[1]) + v2[3] * (v3[1] - v1[1]) + v3[3] * (v1[1] - v2[1])
  local c = v1[1] * (v2[2] - v3[2]) + v2[1] * (v3[2] - v1[2]) + v3[1] * (v1[2] - v2[2])
  local d = -a * v1[1] - b * v1[2] - c * v1[3]
  return -a / c * pos.x - b / c * pos.y - d / c
end

local AbstractHipped = B.class(RoofWithRidge)
function AbstractHipped.init(self, poly, tags, material, off1, off2, along, default_dir)
  RoofWithRidge.init(self, poly, tags, material, off1, off2, along, nil, default_dir)
  local m = -math.huge
  for _, v in ipairs(poly.outer) do m = max(m, G.distance_from_line(v, self.ridge.p1, self.ridge.p2)) end
  self.max_orthogonal_distance = m
end
function AbstractHipped:get_inner_lines()
  local r, c1, c2 = self.ridge, self.cap1, self.cap2
  local l = { inner_line(r, self.ridge_offset1 == 0, self.ridge_offset2 == 0) }
  if self.ridge_offset1 > 0 then
    l[#l + 1] = inner_line(seg(r.p1, c1.p1))
    l[#l + 1] = inner_line(seg(r.p1, c1.p2))
  end
  if self.ridge_offset2 > 0 then
    l[#l + 1] = inner_line(seg(r.p2, c2.p1))
    l[#l + 1] = inner_line(seg(r.p2, c2.p2))
  end
  return l
end
function AbstractHipped:height_at_no_interpolation(pos)
  local h = self:roof_height()
  local r, c1, c2 = self.ridge, self.cap1, self.cap2
  local mo = self.max_orthogonal_distance
  local function from_ridge(p)
    local rel = G.distance_from_line(p, r.p1, r.p2) / mo
    return { p.x, p.y, h - h * rel }
  end
  local rr = G.is_right_of
  if self.ridge_offset1 > 0 and rr(pos, r.p1, c1.p2) and not rr(pos, r.p1, c1.p1) then
    return tri_height_at({ r.p1.x, r.p1.y, h }, from_ridge(c1.p1), from_ridge(c1.p2), pos)
  elseif self.ridge_offset1 > 0 and rr(pos, r.p2, c2.p1) and not rr(pos, r.p2, c2.p2) then
    -- as in OSM2World: this branch tests ridgeOffset1 and uses ridge.p1
    return tri_height_at({ r.p1.x, r.p1.y, h }, from_ridge(c2.p1), from_ridge(c2.p2), pos)
  end
  return from_ridge(pos)[3]
end

M.hipped = function(poly, tags, material)
  local r = setmetatable({}, AbstractHipped)
  AbstractHipped.init(r, poly, tags, material, HIPPED_RIDGE_OFFSET, HIPPED_RIDGE_OFFSET, false, nil)
  return r
end
-- default_dir: SideHippedRoof.determineDefaultDirection (needs neighbouring building parts; opts.default_direction)
M.side_hipped = function(poly, tags, material, opts)
  local r = setmetatable({}, AbstractHipped)
  AbstractHipped.init(r, poly, tags, material, 0, HIPPED_RIDGE_OFFSET, true, opts and opts.default_direction)
  return r
end

---------------------------------------------------------------- half-hipped, side_half-hipped

local HALF_HIPPED_RIDGE_OFFSET = 1 / 6.0

local AbstractHalfHipped = B.class(RoofWithRidge)
function AbstractHalfHipped.init(self, poly, tags, material, off1, off2, along, default_dir)
  RoofWithRidge.init(self, poly, tags, material, off1, off2, along, nil, default_dir)
  local c1, c2 = self.cap1, self.cap2
  local l1 = G.seg_length(c1)
  self.cap1part = seg(interp(c1.p1, c1.p2, 0.5 - self.ridge_offset1 / l1), interp(c1.p1, c1.p2, 0.5 + self.ridge_offset1 / l1))
  -- as in OSM2World: cap2part also divides by cap1's length
  self.cap2part = seg(interp(c2.p1, c2.p2, 0.5 - self.ridge_offset2 / l1), interp(c2.p1, c2.p2, 0.5 + self.ridge_offset2 / l1))
end
function AbstractHalfHipped:get_inner_lines()
  local r = self.ridge
  local l = { inner_line(r, self.ridge_offset1 == 0, self.ridge_offset2 == 0) }
  if self.ridge_offset1 > 0 then
    l[#l + 1] = inner_line(seg(r.p1, self.cap1part.p1), false, true)
    l[#l + 1] = inner_line(seg(r.p1, self.cap1part.p2), false, true)
  end
  if self.ridge_offset2 > 0 then
    l[#l + 1] = inner_line(seg(r.p2, self.cap2part.p1), false, true)
    l[#l + 1] = inner_line(seg(r.p2, self.cap2part.p2), false, true)
  end
  return l
end
function AbstractHalfHipped:height_at_no_interpolation(pos)
  local h = self:roof_height()
  local r, c1, c2 = self.ridge, self.cap1, self.cap2
  if G.eq(r.p1, pos) or G.eq(r.p2, pos) then
    return h
  elseif G.distance_from_segment(pos, self.cap1part) < 0.05 then
    return h - h * self.ridge_offset1 / (G.seg_length(c1) / 2)
  elseif G.distance_from_segment(pos, self.cap2part) < 0.05 then
    return h - h * self.ridge_offset2 / (G.seg_length(c2) / 2)
  elseif G.distance_from_segment(pos, c1) < 0.05 then
    local rel = G.distance_from_line(pos, r.p1, r.p2) / (G.seg_length(c1) / 2)
    return max(h * (1 - rel), 0.0)
  elseif G.distance_from_segment(pos, c2) < 0.05 then
    local rel = G.distance_from_line(pos, r.p1, r.p2) / (G.seg_length(c2) / 2)
    return max(h * (1 - rel), 0.0)
  elseif G.ring_has_vertex(self:get_polygon().outer, pos) then
    return 0.0
  end
  return nil
end

M["half-hipped"] = function(poly, tags, material)
  local r = setmetatable({}, AbstractHalfHipped)
  AbstractHalfHipped.init(r, poly, tags, material, HALF_HIPPED_RIDGE_OFFSET, HALF_HIPPED_RIDGE_OFFSET, false, nil)
  return r
end
M["side_half-hipped"] = function(poly, tags, material, opts)
  local r = setmetatable({}, AbstractHalfHipped)
  AbstractHalfHipped.init(r, poly, tags, material, 0, HALF_HIPPED_RIDGE_OFFSET, true, opts and opts.default_direction)
  return r
end

---------------------------------------------------------------- gambrel

local Gambrel = B.class(RoofWithRidge)
function Gambrel.init(self, poly, tags, material)
  RoofWithRidge.init(self, poly, tags, material, 0, 0, false, nil)
  local c1, c2 = self.cap1, self.cap2
  self.cap1part = seg(interp(c1.p1, c1.p2, 1 / 6.0), interp(c1.p1, c1.p2, 5 / 6.0))
  self.cap2part = seg(interp(c2.p1, c2.p2, 1 / 6.0), interp(c2.p1, c2.p2, 5 / 6.0))
end
function Gambrel:get_inner_lines()
  return {
    inner_line(self.ridge, true),
    inner_line(seg(self.cap1part.p1, self.cap2part.p1), true),
    inner_line(seg(self.cap1part.p2, self.cap2part.p2), true),
  }
end
function Gambrel:height_at_no_interpolation(pos)
  local h = self:roof_height()
  local rel = G.distance_from_segment(pos, self.ridge) / self.max_distance_to_ridge
  if rel < 2 / 3.0 then
    return h - 1 / 2.0 * h * rel
  else
    return h - 1 / 3.0 * h - 2 * h * (rel - 2 / 3.0)
  end
end
M.gambrel = function(poly, tags, material)
  local r = setmetatable({}, Gambrel); Gambrel.init(r, poly, tags, material); return r
end

---------------------------------------------------------------- mansard

local Mansard = B.class(RoofWithRidge)
function Mansard.init(self, poly, tags, material)
  RoofWithRidge.init(self, poly, tags, material, 1 / 3.0, 1 / 3.0, false, nil)
  local r, c1, c2 = self.ridge, self.cap1, self.cap2
  self.edge1 = seg(interp(c1.p1, r.p1, 1 / 3.0), interp(c2.p1, r.p2, 1 / 3.0))
  self.edge2 = seg(interp(c1.p2, r.p1, 1 / 3.0), interp(c2.p2, r.p2, 1 / 3.0))
end
function Mansard:get_inner_lines()
  local r, c1, c2, e1, e2 = self.ridge, self.cap1, self.cap2, self.edge1, self.edge2
  local segs = { r, e1, e2,
    seg(r.p1, e1.p1), seg(r.p1, e2.p1), seg(r.p2, e1.p2), seg(r.p2, e2.p2),
    seg(c1.p1, e1.p1), seg(c2.p1, e1.p2), seg(c1.p2, e2.p1), seg(c2.p2, e2.p2),
    seg(e1.p1, e2.p1), seg(e1.p2, e2.p2) }
  local l = {}
  for i, s in ipairs(segs) do l[i] = inner_line(s) end
  return l
end
function Mansard:height_at_no_interpolation(pos)
  local r, e1, e2 = self.ridge, self.edge1, self.edge2
  local eq = G.eq
  if eq(r.p1, pos) or eq(r.p2, pos) then
    return self:roof_height()
  elseif G.ring_has_vertex(self:get_polygon().outer, pos) then
    return 0.0
  elseif eq(e1.p1, pos) or eq(e1.p2, pos) or eq(e2.p1, pos) or eq(e2.p2, pos) then
    return self:roof_height() - 1 / 3.0 * self:roof_height()
  end
  return nil
end
M.mansard = function(poly, tags, material)
  local r = setmetatable({}, Mansard); Mansard.init(r, poly, tags, material); return r
end

---------------------------------------------------------------- round

-- rounds to the nearest float32 (Java float arithmetic)
local function f32(x)
  if x == 0 or x ~= x then return x end
  local m, e = math.frexp(x)
  local s = m * 16777216
  local fl = floor(s)
  local d = s - fl
  if d > 0.5 or (d == 0.5 and fl % 2 == 1) then fl = fl + 1 end
  return math.ldexp(fl, e - 24)
end

local Round = B.class(RoofWithRidge)
function Round.init(self, poly, tags, material)
  RoofWithRidge.init(self, poly, tags, material, 0, 0, false, nil)
  local height = RoofWithRidge.calculate_preliminary_height(self) or B.DEFAULT_RIDGE_HEIGHT
  local rings = max(3, height / 1)
  rings = rings >= 0 and floor(rings) or math.ceil(rings)
  self.rings = rings
  local bbox = G.rotated_bbox(poly.outer, G.fit_angle(G.angle(G.seg_dir(self.ridge))))
  local cap1 = seg(bbox[4], bbox[1])
  local cap2 = seg(bbox[2], bbox[3])
  local parts = {}
  local step = f32(0.5 / (rings + 1))
  for i = 1, rings do
    local t = f32(i * step)
    local t2 = f32(1 - t)
    parts[#parts + 1] = seg(interp(cap1.p1, cap1.p2, t), interp(cap1.p1, cap1.p2, t2))
    parts[#parts + 1] = seg(interp(cap2.p1, cap2.p2, t), interp(cap2.p1, cap2.p2, t2))
  end
  self.cap_parts = parts
end
function Round:get_inner_lines()
  local segs = { self.ridge }
  for i = 1, self.rings * 2, 2 do
    local a, b = self.cap_parts[i], self.cap_parts[i + 1]
    segs[#segs + 1] = seg(a.p1, b.p2)
    segs[#segs + 1] = seg(a.p2, b.p1)
  end
  local l = {}
  for i, s in ipairs(segs) do l[i] = inner_line(s, true) end
  return l
end
function Round:height_at_no_interpolation(pos)
  local h = self:roof_height()
  local md = self.max_distance_to_ridge
  local radius
  if h < md then
    local center_y = (md * md - h * h) / (2 * h)
    radius = sqrt(md * md + center_y * center_y)
  else
    radius = 0
  end
  local d = G.distance_from_segment(pos, self.ridge)
  local res
  if radius > 0 then
    local rel = d / radius
    res = h - radius + sqrt(1.0 - rel * rel) * radius
  else
    local rel = d / md
    res = (1 - rel ^ 2.5) * h
  end
  return max(res, 0.0)
end
M.round = function(poly, tags, material)
  local r = setmetatable({}, Round); Round.init(r, poly, tags, material); return r
end

return M
