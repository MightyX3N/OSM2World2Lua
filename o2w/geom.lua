-- ported from OSM2World VectorXZ.java, Angle.java, GeometryUtil.java, SimplePolygonXZ.java, SimplePolygonShapeXZ.java,
-- PolygonShapeXZ.java, RectangleXZ.java, FaceDecompositionUtil.java, SimpleLineSegmentIntersectionFinder.java,
-- Earcut4JTriangulationUtil.java (MIT, Copyright OSM2World contributors) and earcut4j Earcut.java 2.2.2 (ISC, after mapbox earcut)
--
-- 2D geometry for the roofs. OSM2World's VectorXZ (x east, z north) maps to our (x, y): same handedness, so angle()
-- (compass bearing, clockwise from north), rightNormal and isRightOf carry over unchanged.
-- Vectors: { x = , y = }. Rings (SimplePolygonXZ): lists of vectors without the repeated last point.
-- Segments: { p1 = v, p2 = v }. Polygons with holes: { outer = ring, holes = { ring, ... } }.
local sqrt, abs, acos, sin, cos, min, max, floor, ceil, huge, pi =
  math.sqrt, math.abs, math.acos, math.sin, math.cos, math.min, math.max, math.floor, math.ceil, math.huge, math.pi
local fmt = string.format

local G = {}

---------------------------------------------------------------- vectors

local function V(x, y) return { x = x, y = y } end
G.V = V
function G.add(a, b) return V(a.x + b.x, a.y + b.y) end
function G.sub(a, b) return V(a.x - b.x, a.y - b.y) end
function G.mult(a, s) return V(a.x * s, a.y * s) end
function G.invert(a) return V(-a.x, -a.y) end
function G.dot(a, b) return a.x * b.x + a.y * b.y end
function G.length(a) return sqrt(a.x * a.x + a.y * a.y) end
function G.length_sq(a) return a.x * a.x + a.y * a.y end
function G.normalize(a) local l = sqrt(a.x * a.x + a.y * a.y); return V(a.x / l, a.y / l) end
function G.right_normal(a) local l = sqrt(a.x * a.x + a.y * a.y); return V(a.y / l, -(a.x / l)) end
function G.dist(a, b) local dx, dy = b.x - a.x, b.y - a.y; return sqrt(dx * dx + dy * dy) end
function G.dist_sq(a, b) local dx, dy = b.x - a.x, b.y - a.y; return dx * dx + dy * dy end
function G.eq(a, b) return a.x == b.x and a.y == b.y end
-- exact key for maps and sets (VectorXZ.equals / hashCode)
function G.key(a) return fmt("%.17g,%.17g", a.x, a.y) end
local add, sub, mult, dot, normalize, dist, eq, key = G.add, G.sub, G.mult, G.dot, G.normalize, G.dist, G.eq, G.key

-- Java's Math.acos is StrictMath.acos (fdlibm e_acos.c); C's acos can differ in the last bit, which can flip
-- ties such as the two equally long sides of a bounding box, so this is fdlibm's algorithm
local acos_fdlibm
do
  local one, PI = 1.0, 3.14159265358979311600e+00
  local pio2_hi, pio2_lo = 1.57079632679489655800e+00, 6.12323399573676603587e-17
  local pS0, pS1, pS2 = 1.66666666666666657415e-01, -3.25565818622400915405e-01, 2.01212532134862925881e-01
  local pS3, pS4, pS5 = -4.00555345006794114027e-02, 7.91534994289814532176e-04, 3.47933107596021167570e-05
  local qS1, qS2 = -2.40339491173441421878e+00, 2.02094576023350569471e+00
  local qS3, qS4 = -6.88283971605453293030e-01, 7.70381505559019352791e-02
  acos_fdlibm = function(x)
    if x ~= x then return x end
    local ax = abs(x)
    if ax >= 1 then
      if ax == 1 then if x > 0 then return 0.0 else return PI + 2.0 * pio2_lo end end
      return 0 / 0
    end
    if ax < 0.5 then
      if ax < 2 ^ -57 * (1 + 2 ^ -20) then return pio2_hi + pio2_lo end
      local z = x * x
      local p = z * (pS0 + z * (pS1 + z * (pS2 + z * (pS3 + z * (pS4 + z * pS5)))))
      local q = one + z * (qS1 + z * (qS2 + z * (qS3 + z * qS4)))
      local r = p / q
      return pio2_hi - (x - (pio2_lo - x * r))
    elseif x < 0 then
      local z = (one + x) * 0.5
      local p = z * (pS0 + z * (pS1 + z * (pS2 + z * (pS3 + z * (pS4 + z * pS5)))))
      local q = one + z * (qS1 + z * (qS2 + z * (qS3 + z * qS4)))
      local s = sqrt(z)
      local r = p / q
      local w = r * s - pio2_lo
      return PI - 2.0 * (s + w)
    else
      local z = (one - x) * 0.5
      local s = sqrt(z)
      -- df = s with the low 32 bits of its significand cleared
      local m, e = math.frexp(s)
      local df = floor(m * 2097152) * 2 ^ (e - 21)
      local c = (z - df * df) / (s + df)
      local p = z * (pS0 + z * (pS1 + z * (pS2 + z * (pS3 + z * (pS4 + z * pS5)))))
      local q = one + z * (qS1 + z * (qS2 + z * (qS3 + z * qS4)))
      local r = p / q
      local w = r * s + c
      return 2.0 * (df + w)
    end
  end
end
G.acos = acos_fdlibm

-- VectorXZ.angle: 0 = north (+y), clockwise, in [0, 2pi)
function G.angle(a)
  if a.x == 0 and a.y == 0 then return 0 end
  local n = normalize(a)
  if a.x >= 0 then return acos_fdlibm(n.y) else return 2 * pi - acos_fdlibm(n.y) end
end
local angle = G.angle
function G.angle_to(a, b) return angle(sub(b, a)) end
function G.from_angle(rad) return V(sin(rad), cos(rad)) end
-- VectorXZ.rotate (clockwise seen from above)
function G.rotate(a, rad)
  local s, c = sin(rad), cos(rad)
  return V(s * a.y + c * a.x, c * a.y - s * a.x)
end
function G.angle_between(v1, v2)
  local raw = abs(angle(v1) - angle(v2))
  if raw < pi then return raw elseif raw == pi then return pi else return pi - (raw % pi) end
end

-- Angle: radians fitted to [0, 2pi)
function G.fit_angle(rad)
  local a = math.fmod(rad, 2 * pi)
  return math.fmod(a + 2 * pi, 2 * pi)
end
function G.radians_between(a1, a2) return G.angle_between(G.from_angle(a1), G.from_angle(a2)) end

---------------------------------------------------------------- GeometryUtil

local EPSILON = 9.99999974737875163555145263671875e-05 -- Java's 0.0001f
local function approx_zero(f) return f <= EPSILON and f >= -EPSILON end

function G.line_segment_intersection(a1, a2, b1, b2)
  local vx, vz = a2.x - a1.x, a2.y - a1.y
  local qx, qz = b2.x - b1.x, b2.y - b1.y
  local denom = vz * qx - vx * qz
  if approx_zero(denom) then return nil end
  denom = 1 / denom
  local amcx, amcz = b1.x - a1.x, b1.y - a1.y
  local t = (amcz * qx - amcx * qz) * denom
  if t < 0 or t > 1 then return nil end
  local s = (amcz * vx - amcx * vz) * denom
  if s < 0 or s > 1 then return nil end
  return V(a1.x + t * vx, a1.y + t * vz)
end

-- getTrueLineSegmentIntersection: no result for shared end points
function G.true_intersection(a1, a2, b1, b2)
  if eq(a1, b1) or eq(a1, b2) or eq(a2, b1) or eq(a2, b2) then return nil end
  return G.line_segment_intersection(a1, a2, b1, b2)
end
local true_intersection = G.true_intersection

function G.is_right_of(p, l1, l2)
  return 0 > (p.y - l1.y) * (l2.x - l1.x) - (p.x - l1.x) * (l2.y - l1.y)
end
local is_right_of = G.is_right_of

function G.distance_from_line(p, v1, v2)
  local tx, ty = v2.x - v1.x, v2.y - v1.y
  local px, py = p.x - v1.x, p.y - v1.y
  local d = px * tx + py * ty
  local proj = d * d / (tx * tx + ty * ty)
  local l = px * px + py * py - proj
  if l < 0 then l = 0 end
  return sqrt(l)
end

-- JTS Distance.pointToSegment
function G.distance_from_segment(p, s)
  local A, B = s.p1, s.p2
  if A.x == B.x and A.y == B.y then return dist(p, A) end
  local len2 = (B.x - A.x) * (B.x - A.x) + (B.y - A.y) * (B.y - A.y)
  local r = ((p.x - A.x) * (B.x - A.x) + (p.y - A.y) * (B.y - A.y)) / len2
  if r <= 0 then return dist(p, A) end
  if r >= 1 then return dist(p, B) end
  local s2 = ((A.y - p.y) * (B.x - A.x) - (A.x - p.x) * (B.y - A.y)) / len2
  return abs(s2) * sqrt(len2)
end
local distance_from_segment = G.distance_from_segment

function G.interpolate_between(a, b, r)
  return V(a.x * (1 - r) + b.x * r, a.y * (1 - r) + b.y * r)
end

function G.interpolate_value(p, p1, v1, p2, v2)
  local r = dist(p1, p) / (dist(p1, p) + dist(p, p2))
  return v1 * (1 - r) + v2 * r
end

---------------------------------------------------------------- segments

function G.seg(p1, p2) return { p1 = p1, p2 = p2 } end
local seg = G.seg
function G.seg_length(s) return dist(s.p1, s.p2) end
function G.seg_dir(s) return normalize(sub(s.p2, s.p1)) end
function G.seg_reverse(s) return seg(s.p2, s.p1) end
function G.seg_center(s) return V((s.p1.x + s.p2.x) / 2, (s.p1.y + s.p2.y) / 2) end
function G.seg_key(s) return key(s.p1) .. ";" .. key(s.p2) end
-- PolylineShapeXZ.pointAtOffset for a single segment
function G.seg_point_at(s, offset)
  local l = dist(s.p1, s.p2)
  if offset <= l then return G.interpolate_between(s.p1, s.p2, max(0, offset / l)) end
  return s.p2
end

---------------------------------------------------------------- sorting (Java's List.sort is stable)

function G.stable_sort(list, keyfn)
  local n = #list
  local keys = {}
  for i = 1, n do keys[i] = keyfn(list[i]) end
  local idx = {}
  for i = 1, n do idx[i] = i end
  table.sort(idx, function(a, b)
    if keys[a] ~= keys[b] then return keys[a] < keys[b] end
    return a < b
  end)
  local out = {}
  for i = 1, n do out[i] = list[idx[i]] end
  for i = 1, n do list[i] = out[i] end
  return list
end

---------------------------------------------------------------- rings (SimplePolygonXZ)

function G.ring_from_flat(t)
  local r = {}
  local n = #t
  if n >= 4 and t[1] == t[n - 1] and t[2] == t[n] then n = n - 2 end
  for i = 1, n, 2 do r[#r + 1] = V(t[i], t[i + 1]) end
  return r
end
function G.ring_to_flat(r)
  local t = {}
  for _, v in ipairs(r) do t[#t + 1] = v.x; t[#t + 1] = v.y end
  return t
end

function G.signed_area(r)
  local s, n = 0, #r
  for i = 1, n do
    local a, b = r[i], r[i % n + 1]
    s = s + a.x * b.y
    s = s - b.x * a.y
  end
  return s / 2
end
function G.area(r) return abs(G.signed_area(r)) end
function G.is_clockwise(r) return G.signed_area(r) < 0 end
function G.reverse(r)
  local o = {}
  for i = #r, 1, -1 do o[#o + 1] = r[i] end
  -- Java reverses the closed loop, so the first vertex stays first
  if #o > 0 then table.insert(o, 1, table.remove(o)) end
  return o
end
function G.make_ccw(r) if G.is_clockwise(r) then return G.reverse(r) end return r end
function G.make_cw(r) if not G.is_clockwise(r) then return G.reverse(r) end return r end

function G.segments(r)
  local s, n = {}, #r
  for i = 1, n do s[i] = seg(r[i], r[i % n + 1]) end
  return s
end

function G.centroid(r)
  local sa = G.signed_area(r)
  local xs, ys, n = 0, 0, #r
  for i = 1, n do
    local a, b = r[i], r[i % n + 1]
    local f = a.x * b.y - b.x * a.y
    xs = xs + (a.x + b.x) * f
    ys = ys + (a.y + b.y) * f
  end
  local af = 1 / (6 * sa)
  return V(af * xs, af * ys)
end

-- SimplePolygonXZ.getCenter: vertex average
function G.center(r)
  local x, y, n = 0, 0, #r
  for _, v in ipairs(r) do x = x + v.x / n; y = y + v.y / n end
  return V(x, y)
end

-- SimplePolygonShapeXZ.getDiameter
function G.diameter(r)
  local m = 0
  for i = 2, #r do
    for j = 1, i - 1 do
      local d = dist(r[i], r[j])
      if d > m then m = d end
    end
  end
  return m
end

-- pnpoly (SimplePolygonShapeXZ.contains)
function G.ring_contains(r, p)
  local c = false
  local n = #r
  local j = n
  for i = 1, n do
    local vi, vj = r[i], r[j]
    if ((vi.y > p.y) ~= (vj.y > p.y)) and (p.x < (vj.x - vi.x) / (vj.y - vi.y) * (p.y - vi.y) + vi.x) then
      c = not c
    end
    j = i
  end
  return c
end

function G.ring_has_vertex(r, p)
  for _, v in ipairs(r) do if v.x == p.x and v.y == p.y then return true end end
  return false
end

-- ShapeXZ.intersections: list of { point, segment }
function G.intersections(r, s)
  local res = {}
  for _, rs in ipairs(G.segments(r)) do
    local p = true_intersection(s.p1, s.p2, rs.p1, rs.p2)
    if p then res[#res + 1] = { point = p, segment = rs } end
  end
  return res
end

function G.intersection_segments(r, s)
  local res = {}
  for _, rs in ipairs(G.segments(r)) do
    if true_intersection(s.p1, s.p2, rs.p1, rs.p2) then res[#res + 1] = rs end
  end
  return res
end

function G.ring_intersects(r, a, b)
  local n = #r
  for i = 1, n do
    if true_intersection(a, b, r[i], r[i % n + 1]) then return true end
  end
  return false
end

function G.closest_segment(r, p)
  local best, bd = nil, huge
  for _, s in ipairs(G.segments(r)) do
    local d = distance_from_segment(p, s)
    if d < bd then best, bd = s, d end
  end
  return best
end

-- GeometryUtil.insertIntoPolygon
function G.insert_into_polygon(r, p, snap)
  local s = G.closest_segment(r, p)
  local n = #r
  for i = 1, n do
    if eq(r[i], s.p1) and eq(r[i % n + 1], s.p2) then
      if dist(r[i], p) <= snap or dist(r[i % n + 1], p) <= snap then return r end
      local o = {}
      for k = 1, i do o[k] = r[k] end
      o[i + 1] = p
      for k = i + 1, n do o[k + 1] = r[k] end
      return o
    end
  end
  error("segment was not found in polygon")
end

-- the checks of the SimplePolygonXZ constructor; false if Java would throw
function G.valid_ring(r)
  local n = #r
  if n < 3 then return false end
  for i = 1, n do if G.dist_sq(r[i % n + 1], r[i]) == 0 then return false end end
  for i = 1, n do
    local a1, a2 = r[i], r[i % n + 1]
    for j = i + 1, n do
      if true_intersection(a1, a2, r[j], r[j % n + 1]) then return false end
    end
  end
  local a = G.area(r)
  if a == 0 or a < 1e-6 then return false end
  return true
end

local function simplified(r, max_dot)
  local n = #r
  local del, count = {}, 0
  for i = 1, n do
    local before = sub(r[i], r[(i - 2) % n + 1])
    local after = sub(r[i % n + 1], r[i])
    local d = dot(normalize(before), normalize(after))
    if abs(d - 1) < max_dot then del[i] = true; count = count + 1 end
  end
  if count == 0 or count > n - 3 then return r end
  local o = {}
  for i = 1, n do if not del[i] then o[#o + 1] = r[i] end end
  if not G.valid_ring(o) then return nil end
  return o
end

-- SimplePolygonXZ.getSimplifiedPolygon
function G.simplified_polygon(r)
  local res = simplified(r, 0.05)
  if res == nil or abs(G.area(res) - G.area(r)) / G.area(r) > 0.1 then
    res = simplified(r, 0.001)
  end
  return res or r
end

-- AxisAlignedRectangleXZ corners: bottomLeft, bottomRight, topRight, topLeft
local function bbox_corners(vs)
  local x0, y0, x1, y1 = huge, huge, -huge, -huge
  for _, v in ipairs(vs) do
    x0 = min(x0, v.x); y0 = min(y0, v.y); x1 = max(x1, v.x); y1 = max(y1, v.y)
  end
  return { V(x0, y0), V(x1, y0), V(x1, y1), V(x0, y1) }, (x1 - x0) * (y1 - y0)
end

-- a RectangleXZ is a list of 4 vectors; rect segments are (v1,v2), (v2,v3), (v3,v4), (v4,v1)
function G.minimum_rotated_bbox(r)
  local min_box, min_area, min_angle
  local n = #r
  for i = 1, n do
    local a = G.angle_to(r[i], r[i % n + 1])
    local rot = {}
    for k, v in ipairs(r) do rot[k] = G.rotate(v, -a) end
    rot[#rot + 1] = rot[1]
    local box, ar = bbox_corners(rot)
    if min_box == nil or ar < min_area then min_box, min_area, min_angle = box, ar, a end
  end
  local o = {}
  for k = 1, 4 do o[k] = G.rotate(min_box[k], min_angle) end
  return o
end

function G.rotated_bbox(r, ang)
  local rot = {}
  for k, v in ipairs(r) do rot[k] = G.rotate(v, -ang) end
  local box = bbox_corners(rot)
  local rect = {}
  for k = 1, 4 do rect[k] = G.rotate(box[k], ang) end
  local start
  for i = 1, 4 do
    local side = G.angle_to(rect[i], rect[i % 4 + 1])
    if G.radians_between(G.fit_angle(side), ang) < 0.1 then start = i; break end
  end
  if not start then error("No side of the bbox matches the given angle") end
  local o = {}
  for k = 0, 3 do o[k + 1] = rect[(start - 1 + k) % 4 + 1] end
  return o
end
function G.rect_diameter(rect) return dist(rect[1], rect[3]) end

-- SimpleClosedShapeXZ.scale(factor) around the centroid
function G.scale(r, f)
  if f == 1 then return r end
  local c = G.centroid(r)
  local o = {}
  for k, v in ipairs(r) do o[k] = V((v.x - c.x) * f + c.x, (v.y - c.y) * f + c.y) end
  return o
end

---------------------------------------------------------------- polygons with holes

function G.poly_contains(P, p)
  if not G.ring_contains(P.outer, p) then return false end
  for _, h in ipairs(P.holes or {}) do
    if G.ring_contains(h, p) then return false end
  end
  return true
end

---------------------------------------------------------------- earcut (earcut4j 2.2.2)

local bit = rawget(_G, "bit")
if not bit then local ok, b = pcall(require, "bit"); if ok then bit = b end end

local function java_int(v)
  if v ~= v then return 0 end
  if v >= 2147483647 then return 2147483647 end
  if v <= -2147483648 then return -2147483648 end
  return v >= 0 and floor(v) or ceil(v)
end

local function z_order(x, y, minx, miny, inv)
  local lx = java_int(32767 * (x - minx) * inv)
  local ly = java_int(32767 * (y - miny) * inv)
  if bit then
    local bor, band, lsh = bit.bor, bit.band, bit.lshift
    lx = band(bor(lx, lsh(lx, 8)), 0x00FF00FF)
    lx = band(bor(lx, lsh(lx, 4)), 0x0F0F0F0F)
    lx = band(bor(lx, lsh(lx, 2)), 0x33333333)
    lx = band(bor(lx, lsh(lx, 1)), 0x55555555)
    ly = band(bor(ly, lsh(ly, 8)), 0x00FF00FF)
    ly = band(bor(ly, lsh(ly, 4)), 0x0F0F0F0F)
    ly = band(bor(ly, lsh(ly, 2)), 0x33333333)
    ly = band(bor(ly, lsh(ly, 1)), 0x55555555)
    return bor(lx, lsh(ly, 1))
  end
  -- plain Lua: interleave the low 16 bits (values are 0..32767 for points inside the outline)
  local r, b = 0, 1
  for _ = 0, 15 do
    r = r + (lx % 2) * b + (ly % 2) * b * 2
    lx, ly, b = floor(lx / 2), floor(ly / 2), b * 4
  end
  return r
end

local function node(i, x, y) return { i = i, x = x, y = y } end
local function e_area(p, q, r) return (q.y - p.y) * (r.x - q.x) - (q.x - p.x) * (r.y - q.y) end
local function e_equals(a, b) return a.x == b.x and a.y == b.y end
local function remove_node(p)
  p.next.prev = p.prev
  p.prev.next = p.next
  if p.prevZ then p.prevZ.nextZ = p.nextZ end
  if p.nextZ then p.nextZ.prevZ = p.prevZ end
end
local function insert_node(i, x, y, last)
  local p = node(i, x, y)
  if not last then p.prev = p; p.next = p
  else
    p.next = last.next; p.prev = last
    last.next.prev = p; last.next = p
  end
  return p
end
local function e_signed_area(data, s, e)
  local sum, j = 0, e - 2
  for i = s, e - 1, 2 do
    sum = sum + (data[j + 1] - data[i + 1]) * (data[i + 2] + data[j + 2])
    j = i
  end
  return sum
end
-- data is 1-based storage of 0-based offsets: x of offset i is data[i + 1]
local function linked_list(data, s, e, clockwise)
  local last
  if clockwise == (e_signed_area(data, s, e) > 0) then
    for i = s, e - 1, 2 do last = insert_node(i, data[i + 1], data[i + 2], last) end
  else
    for i = e - 2, s, -2 do last = insert_node(i, data[i + 1], data[i + 2], last) end
  end
  if last and e_equals(last, last.next) then
    remove_node(last)
    last = last.next
  end
  return last
end
local function filter_points(start, e)
  if not start then return start end
  if not e then e = start end
  local p = start
  local again
  repeat
    again = false
    if (not p.steiner and e_equals(p, p.next)) or e_area(p.prev, p, p.next) == 0 then
      remove_node(p)
      p = p.prev; e = p
      if p == p.next then break end
      again = true
    else
      p = p.next
    end
  until not (again or p ~= e)
  return e
end
local function point_in_triangle(ax, ay, bx, by, cx, cy, px, py)
  return (cx - px) * (ay - py) - (ax - px) * (cy - py) >= 0 and (ax - px) * (by - py) - (bx - px) * (ay - py) >= 0
    and (bx - px) * (cy - py) - (cx - px) * (by - py) >= 0
end
local function is_ear(ear)
  local a, b, c = ear.prev, ear, ear.next
  if e_area(a, b, c) >= 0 then return false end
  local p = ear.next.next
  while p ~= ear.prev do
    if point_in_triangle(a.x, a.y, b.x, b.y, c.x, c.y, p.x, p.y) and e_area(p.prev, p, p.next) >= 0 then return false end
    p = p.next
  end
  return true
end
local function is_ear_hashed(ear, minx, miny, inv)
  local a, b, c = ear.prev, ear, ear.next
  if e_area(a, b, c) >= 0 then return false end
  local mintx = a.x < b.x and (a.x < c.x and a.x or c.x) or (b.x < c.x and b.x or c.x)
  local minty = a.y < b.y and (a.y < c.y and a.y or c.y) or (b.y < c.y and b.y or c.y)
  local maxtx = a.x > b.x and (a.x > c.x and a.x or c.x) or (b.x > c.x and b.x or c.x)
  local maxty = a.y > b.y and (a.y > c.y and a.y or c.y) or (b.y > c.y and b.y or c.y)
  local minz = z_order(mintx, minty, minx, miny, inv)
  local maxz = z_order(maxtx, maxty, minx, miny, inv)
  local p, n = ear.prevZ, ear.nextZ
  while p and p.z >= minz and n and n.z <= maxz do
    if p ~= ear.prev and p ~= ear.next and point_in_triangle(a.x, a.y, b.x, b.y, c.x, c.y, p.x, p.y) and e_area(p.prev, p, p.next) >= 0 then return false end
    p = p.prevZ
    if n ~= ear.prev and n ~= ear.next and point_in_triangle(a.x, a.y, b.x, b.y, c.x, c.y, n.x, n.y) and e_area(n.prev, n, n.next) >= 0 then return false end
    n = n.nextZ
  end
  while p and p.z >= minz do
    if p ~= ear.prev and p ~= ear.next and point_in_triangle(a.x, a.y, b.x, b.y, c.x, c.y, p.x, p.y) and e_area(p.prev, p, p.next) >= 0 then return false end
    p = p.prevZ
  end
  while n and n.z <= maxz do
    if n ~= ear.prev and n ~= ear.next and point_in_triangle(a.x, a.y, b.x, b.y, c.x, c.y, n.x, n.y) and e_area(n.prev, n, n.next) >= 0 then return false end
    n = n.nextZ
  end
  return true
end
local function sign(v) return v > 0 and 1 or (v < 0 and -1 or 0) end
local function on_segment(p, q, r)
  return q.x <= max(p.x, r.x) and q.x >= min(p.x, r.x) and q.y <= max(p.y, r.y) and q.y >= min(p.y, r.y)
end
local function e_intersects(p1, q1, p2, q2)
  if (e_equals(p1, p2) and e_equals(q1, q2)) or (e_equals(p1, q2) and e_equals(p2, q1)) then return true end
  local o1, o2 = sign(e_area(p1, q1, p2)), sign(e_area(p1, q1, q2))
  local o3, o4 = sign(e_area(p2, q2, p1)), sign(e_area(p2, q2, q1))
  if o1 ~= o2 and o3 ~= o4 then return true end
  if o1 == 0 and on_segment(p1, p2, q1) then return true end
  if o2 == 0 and on_segment(p1, q2, q1) then return true end
  if o3 == 0 and on_segment(p2, p1, q2) then return true end
  if o4 == 0 and on_segment(p2, q1, q2) then return true end
  return false
end
local function locally_inside(a, b)
  if e_area(a.prev, a, a.next) < 0 then
    return e_area(a, b, a.next) >= 0 and e_area(a, a.prev, b) >= 0
  end
  return e_area(a, b, a.prev) < 0 or e_area(a, a.next, b) < 0
end
local function intersects_polygon(a, b)
  local p = a
  repeat
    if p.i ~= a.i and p.next.i ~= a.i and p.i ~= b.i and p.next.i ~= b.i and e_intersects(p, p.next, a, b) then return true end
    p = p.next
  until p == a
  return false
end
local function middle_inside(a, b)
  local p, inside = a, false
  local px, py = (a.x + b.x) / 2, (a.y + b.y) / 2
  repeat
    if ((p.y > py) ~= (p.next.y > py)) and (px < (p.next.x - p.x) * (py - p.y) / (p.next.y - p.y) + p.x) then
      inside = not inside
    end
    p = p.next
  until p == a
  return inside
end
local function is_valid_diagonal(a, b)
  return a.next.i ~= b.i and a.prev.i ~= b.i and not intersects_polygon(a, b) and
    ((locally_inside(a, b) and locally_inside(b, a) and middle_inside(a, b) and
      (e_area(a.prev, a, b.prev) ~= 0 or e_area(a, b.prev, b) ~= 0)) or
     (e_equals(a, b) and e_area(a.prev, a, a.next) > 0 and e_area(b.prev, b, b.next) > 0))
end
local function split_polygon(a, b)
  local a2, b2 = node(a.i, a.x, a.y), node(b.i, b.x, b.y)
  local an, bp = a.next, b.prev
  a.next = b; b.prev = a
  a2.next = an; an.prev = a2
  b2.next = a2; a2.prev = b2
  bp.next = b2; b2.prev = bp
  return b2
end
local function cure_local_intersections(start, tris)
  local p = start
  repeat
    local a, b = p.prev, p.next.next
    if not e_equals(a, b) and e_intersects(a, p, p.next, b) and locally_inside(a, b) and locally_inside(b, a) then
      tris[#tris + 1] = a.i / 2; tris[#tris + 1] = p.i / 2; tris[#tris + 1] = b.i / 2
      remove_node(p); remove_node(p.next)
      p = b; start = b
    end
    p = p.next
  until p == start
  return filter_points(p, nil)
end
local function sort_linked(list)
  local in_size = 1
  local num_merges
  repeat
    local p = list
    list = nil
    local tail
    num_merges = 0
    while p do
      num_merges = num_merges + 1
      local q = p
      local psize = 0
      for _ = 1, in_size do
        psize = psize + 1
        q = q.nextZ
        if not q then break end
      end
      local qsize = in_size
      while psize > 0 or (qsize > 0 and q) do
        local e
        if psize == 0 then e = q; q = q.nextZ; qsize = qsize - 1
        elseif qsize == 0 or not q then e = p; p = p.nextZ; psize = psize - 1
        elseif p.z <= q.z then e = p; p = p.nextZ; psize = psize - 1
        else e = q; q = q.nextZ; qsize = qsize - 1 end
        if tail then tail.nextZ = e else list = e end
        e.prevZ = tail
        tail = e
      end
      p = q
    end
    tail.nextZ = nil
    in_size = in_size * 2
  until num_merges <= 1
  return list
end
local function index_curve(start, minx, miny, inv)
  local p = start
  repeat
    if p.z == nil then p.z = z_order(p.x, p.y, minx, miny, inv) end
    p.prevZ = p.prev
    p.nextZ = p.next
    p = p.next
  until p == start
  p.prevZ.nextZ = nil
  p.prevZ = nil
  sort_linked(p)
end

local earcut_linked
local function split_earcut(start, tris, minx, miny, inv, hashed)
  local a = start
  repeat
    local b = a.next.next
    while b ~= a.prev do
      if a.i ~= b.i and is_valid_diagonal(a, b) then
        local c = split_polygon(a, b)
        a = filter_points(a, a.next)
        c = filter_points(c, c.next)
        earcut_linked(a, tris, minx, miny, inv, hashed, 0)
        earcut_linked(c, tris, minx, miny, inv, hashed, 0)
        return
      end
      b = b.next
    end
    a = a.next
  until a == start
end
earcut_linked = function(ear, tris, minx, miny, inv, hashed, pass)
  if not ear then return end
  if pass == 0 and hashed then index_curve(ear, minx, miny, inv) end
  local stop = ear
  while ear.prev ~= ear.next do
    local prev, nxt = ear.prev, ear.next
    if (hashed and is_ear_hashed(ear, minx, miny, inv)) or (not hashed and is_ear(ear)) then
      tris[#tris + 1] = prev.i / 2; tris[#tris + 1] = ear.i / 2; tris[#tris + 1] = nxt.i / 2
      remove_node(ear)
      ear = nxt.next
      stop = nxt.next
    else
      ear = nxt
      if ear == stop then
        if pass == 0 then
          earcut_linked(filter_points(ear, nil), tris, minx, miny, inv, hashed, 1)
        elseif pass == 1 then
          ear = cure_local_intersections(filter_points(ear, nil), tris)
          earcut_linked(ear, tris, minx, miny, inv, hashed, 2)
        elseif pass == 2 then
          split_earcut(ear, tris, minx, miny, inv, hashed)
        end
        break
      end
    end
  end
end
local function get_leftmost(start)
  local p, l = start, start
  repeat
    if p.x < l.x or (p.x == l.x and p.y < l.y) then l = p end
    p = p.next
  until p == start
  return l
end
local function find_hole_bridge(hole, outer)
  local p = outer
  local hx, hy = hole.x, hole.y
  local qx = -1.7976931348623157e308
  local m
  repeat
    if hy <= p.y and hy >= p.next.y then
      local x = p.x + (hy - p.y) * (p.next.x - p.x) / (p.next.y - p.y)
      if x <= hx and x > qx then
        qx = x
        if x == hx then
          if hy == p.y then return p end
          if hy == p.next.y then return p.next end
        end
        m = p.x < p.next.x and p or p.next
      end
    end
    p = p.next
  until p == outer
  if not m then return nil end
  -- earcut4j 2.2.2 starts its refinement loop with p == stop, so the loop body never runs
  return m
end
local function eliminate_hole(hole, outer)
  outer = find_hole_bridge(hole, outer)
  if outer then
    local b = split_polygon(outer, hole)
    filter_points(outer, outer.next)
    filter_points(b, b.next)
  end
end

-- earcut(data, hole_starts) -> list of 0-based vertex indices (3 per triangle)
function G.earcut(data, holes)
  local has_holes = holes and #holes > 0
  local outer_len = has_holes and holes[1] * 2 or #data
  local outer = linked_list(data, 0, outer_len, true)
  local tris = {}
  if not outer or outer.next == outer.prev then return tris end
  local minx, miny, maxx, maxy, inv = 0, 0, 0, 0, nil
  if has_holes then
    local queue = {}
    for i = 1, #holes do
      local s = holes[i] * 2
      local e = i < #holes and holes[i + 1] * 2 or #data
      local list = linked_list(data, s, e, false)
      if list == list.next then list.steiner = true end
      queue[#queue + 1] = get_leftmost(list)
    end
    G.stable_sort(queue, function(n) return n.x end)
    for _, n in ipairs(queue) do
      eliminate_hole(n, outer)
      outer = filter_points(outer, outer.next)
    end
  end
  if #data > 80 * 2 then
    minx, miny = data[1], data[2]; maxx, maxy = minx, miny
    for i = 2, outer_len - 1, 2 do
      local x, y = data[i + 1], data[i + 2]
      if x < minx then minx = x end
      if y < miny then miny = y end
      if x > maxx then maxx = x end
      if y > maxy then maxy = y end
    end
    inv = max(maxx - minx, maxy - miny)
    inv = inv ~= 0 and 1 / inv or 0
  end
  earcut_linked(outer, tris, minx, miny, inv or 0, inv ~= nil, 0)
  return tris
end

---------------------------------------------------------------- triangulation (Earcut4JTriangulationUtil, TriangleXZ)

-- triangles: { a, b, c } of vectors
function G.tri_area(t)
  local a, b, c = t[1], t[2], t[3]
  return abs((a.x * b.y - b.x * a.y + b.x * c.y - c.x * b.y + c.x * a.y - a.x * c.y) / 2)
end
function G.tri_is_clockwise(t) return is_right_of(t[3], t[1], t[2]) end
function G.tri_ccw(t) if G.tri_is_clockwise(t) then return { t[3], t[2], t[1] } end return t end
function G.tri_cw(t) if not G.tri_is_clockwise(t) then return { t[3], t[2], t[1] } end return t end

function G.triangulate_earcut(outer, holes)
  local data, hi = {}, {}
  local verts = {}
  for _, v in ipairs(outer) do data[#data + 1] = v.x; data[#data + 1] = v.y; verts[#verts + 1] = v end
  for _, h in ipairs(holes or {}) do
    hi[#hi + 1] = #verts
    for _, v in ipairs(h) do data[#data + 1] = v.x; data[#data + 1] = v.y; verts[#verts + 1] = v end
  end
  local raw = G.earcut(data, hi)
  local res = {}
  for i = 1, #raw, 3 do
    local t = { verts[raw[i] + 1], verts[raw[i + 1] + 1], verts[raw[i + 2] + 1] }
    if not eq(t[1], t[2]) and not eq(t[2], t[3]) and not eq(t[3], t[1]) then
      if not (G.tri_area(t) < 1e-5) then res[#res + 1] = t end
    end
  end
  return res
end

-- SimplePolygonXZ.getTriangulation
function G.ring_triangulation(r)
  if #r == 3 then return { { r[1], r[2], r[3] } } end
  local res = G.triangulate_earcut(r, nil)
  local cw = G.is_clockwise(r)
  for i, t in ipairs(res) do res[i] = cw and G.tri_cw(t) or G.tri_ccw(t) end
  return res
end

-- PolygonWithHolesXZ.getTriangulation
function G.poly_triangulation(P)
  if not P.holes or #P.holes == 0 then return G.ring_triangulation(P.outer) end
  return G.triangulate_earcut(P.outer, P.holes)
end

-- PolygonShapeXZ.getPointInside
function G.point_inside(P)
  local c = G.centroid(P.outer)
  if G.poly_contains(P, c) then return c end
  local t = G.poly_triangulation(P)[1]
  return V((t[1].x + t[2].x + t[3].x) / 3, (t[1].y + t[2].y + t[3].y) / 3)
end

---------------------------------------------------------------- Java HashMap / HashSet iteration order
-- FaceDecompositionUtil walks HashSets; their iteration order decides where each face's vertex loop starts and
-- so earcut's triangles. This reproduces it: VectorXZ / LineSegmentXZ hashCode, HashMap.hash and table sizes.

local TWO32, TWO31 = 4294967296, 2147483648
local function to_i32(v) v = v % TWO32; if v >= TWO31 then v = v - TWO32 end return v end
local xor32
if bit then
  xor32 = function(a, b) return bit.bxor(to_i32(a), to_i32(b)) end
else
  xor32 = function(a, b)
    a, b = a % TWO32, b % TWO32
    local r, p = 0, 1
    for _ = 1, 32 do
      local x, y = a % 2, b % 2
      if x ~= y then r = r + p end
      a, b, p = (a - x) / 2, (b - y) / 2, p * 2
    end
    return to_i32(r)
  end
end

-- Double.doubleToLongBits as two unsigned 32-bit halves
local function double_bits(x)
  if x ~= x then return 0x7ff80000, 0 end
  if x == 0 then return (1 / x < 0) and TWO31 or 0, 0 end
  local sign = x < 0 and TWO31 or 0
  local a = abs(x)
  local hi_e, mant
  if a == huge then hi_e, mant = 2047, 0
  else
    local m, e = math.frexp(a)
    local biased = e - 1 + 1023
    if biased <= 0 then hi_e, mant = 0, a * 2 ^ 1000 * 2 ^ 74
    else hi_e, mant = biased, (m * 2 - 1) * 2 ^ 52 end
  end
  return sign + hi_e * 1048576 + floor(mant / TWO32), mant % TWO32
end

local function double_hash(x)
  local hi, lo = double_bits(x)
  return xor32(hi, lo)
end
function G.vector_hash(v)
  local r = 1
  r = to_i32(31 * r + double_hash(v.x))
  r = to_i32(31 * r + double_hash(v.y))
  return r
end
function G.segment_hash(s)
  local r = 1
  r = to_i32(31 * r + G.vector_hash(s.p1))
  r = to_i32(31 * r + G.vector_hash(s.p2))
  return r
end
local function bucket(h, cap)
  local spread = xor32(h, floor((h % TWO32) / 65536))
  return (spread % TWO32) % cap
end

-- table size of new HashSet<>(collection of n) (JDK 19+: HashMap.newHashMap(max(n, 12)))
local function copy_capacity(n)
  local want = ceil(max(n, 12) / 0.75)
  local cap = 1
  while cap < want do cap = cap * 2 end
  return cap
end

-- reorders a list (in insertion order) into the iteration order of a java.util.HashMap starting with the given
-- table size: buckets in order, insertion order within a bucket; grows when full, and (like treeifyBin) when a
-- bucket passes 8 entries in a table smaller than 64. Tree bins in larger tables are not modelled.
local function hash_order(list, hashes, cap)
  local buckets, size = {}, 0
  local function rehash(newcap)
    local nb = {}
    for b = 0, cap - 1 do
      local bin = buckets[b]
      if bin then
        for _, i in ipairs(bin) do
          local k = bucket(hashes[i], newcap)
          local t = nb[k]
          if not t then t = {}; nb[k] = t end
          t[#t + 1] = i
        end
      end
    end
    buckets, cap = nb, newcap
  end
  for i = 1, #list do
    local k = bucket(hashes[i], cap)
    local bin = buckets[k]
    if not bin then bin = {}; buckets[k] = bin end
    bin[#bin + 1] = i
    if #bin >= 9 and cap < 64 then rehash(cap * 2) end
    size = size + 1
    if size > cap * 0.75 then rehash(cap * 2) end
  end
  local out = {}
  for b = 0, cap - 1 do
    local bin = buckets[b]
    if bin then for _, i in ipairs(bin) do out[#out + 1] = list[i] end end
  end
  return out
end

---------------------------------------------------------------- FaceDecompositionUtil

-- PolygonShapeXZ.contains(PolygonShapeXZ) for rings
local function ring_contains_ring(r, o)
  for _, v in ipairs(o) do
    if not G.ring_has_vertex(r, v) and not G.ring_contains(r, v) then return false end
  end
  return true
end

local function faces_from_fully_noded_graph(nodes, edges)
  local directed = {}
  for _, e in ipairs(edges) do
    directed[#directed + 1] = e
    directed[#directed + 1] = seg(e.p2, e.p1)
  end
  local out_edges = {}
  for _, e in ipairs(directed) do e.k = G.seg_key(e) end
  for _, nd in ipairs(nodes) do
    local list = {}
    for _, e in ipairs(directed) do if eq(e.p1, nd) then list[#list + 1] = e end end
    G.stable_sort(list, function(e) return angle(G.seg_dir(e)) end)
    out_edges[key(nd)] = list
  end
  local remaining, rem_count = {}, #directed
  for _, e in ipairs(directed) do remaining[e.k] = true end
  local hashes = {}
  for i, e in ipairs(directed) do hashes[i] = G.segment_hash(e) end
  local iter = hash_order(directed, hashes, copy_capacity(#directed))
  local faces = {}
  local di = 1
  while rem_count > 0 do
    while not remaining[iter[di].k] do di = di + 1 end
    local path = { iter[di] }
    local broken = false
    while path[1].k ~= path[#path].k or #path == 1 do
      local cur = path[#path]
      local list = out_edges[key(cur.p2)]
      local rk = key(cur.p2) .. ";" .. key(cur.p1)
      local inc
      for i, e in ipairs(list) do if e.k == rk then inc = i; break end end
      path[#path + 1] = list[inc % #list + 1]
      if #path > 10000 then broken = true; break end
    end
    if broken then break end
    for _, e in ipairs(path) do
      if remaining[e.k] then remaining[e.k] = nil; rem_count = rem_count - 1 end
    end
    local loop = {}
    for i = 1, #path - 1 do loop[i] = path[i].p1 end
    if G.valid_ring(loop) then faces[#faces + 1] = loop end
  end
  local outers, inners = {}, {}
  for _, f in ipairs(faces) do
    if G.is_clockwise(f) then inners[#inners + 1] = f else outers[#outers + 1] = f end
  end
  -- buildPolygonsFromRings
  local result = {}
  while #outers > 0 do
    local o = table.remove(outers)
    local holes = {}
    local oa = G.area(o)
    for _, ir in ipairs(inners) do
      local ia = G.area(ir)
      if oa > ia + 1e-7 and ring_contains_ring(o, ir) then
        local in_smaller = false
        for _, o2 in ipairs(outers) do
          if ring_contains_ring(o2, ir) and G.area(o2) > ia + 1e-7 and ring_contains_ring(o, o2) then in_smaller = true; break end
        end
        if not in_smaller then holes[#holes + 1] = ir end
      end
    end
    result[#result + 1] = { outer = o, holes = holes }
    local used = {}
    for _, h in ipairs(holes) do used[h] = true end
    local rest = {}
    for _, ir in ipairs(inners) do if not used[ir] then rest[#rest + 1] = ir end end
    inners = rest
  end
  return result
end

function G.faces_from_graph(segments)
  local SNAP = 1e-5
  -- all true intersections
  local inters = {}
  for i = 1, #segments do
    for j = i + 1, #segments do
      local a, b = segments[i], segments[j]
      local p = true_intersection(a.p1, a.p2, b.p1, b.p2)
      if p then inters[#inters + 1] = { pos = p, a = a, b = b } end
    end
  end
  -- snap intersection points to nearby segment end points
  local known, kseen = {}, {}
  for _, s in ipairs(segments) do
    for _, p in ipairs({ s.p1, s.p2 }) do
      local k = key(p)
      if not kseen[k] then kseen[k] = true; known[#known + 1] = p end
    end
  end
  local kept, snapped = {}, {}
  for _, it in ipairs(inters) do
    local best, bd = nil, huge
    for _, p in ipairs(known) do
      local d = dist(it.pos, p)
      if d < bd then best, bd = p, d end
    end
    if dist(best, it.pos) < SNAP then
      snapped[#snapped + 1] = { pos = best, a = it.a, b = it.b }
    else
      kept[#kept + 1] = it
    end
  end
  for _, it in ipairs(snapped) do kept[#kept + 1] = it end
  -- points per segment (deduplicated segments and points)
  local per, order = {}, {}
  local function put(s, p)
    local sk = G.seg_key(s)
    local e = per[sk]
    if not e then e = { s = s, pts = {}, seen = {} }; per[sk] = e; order[#order + 1] = sk end
    local pk = key(p)
    if not e.seen[pk] then e.seen[pk] = true; e.pts[#e.pts + 1] = p end
  end
  for _, it in ipairs(kept) do put(it.a, it.pos); put(it.b, it.pos) end
  for _, s in ipairs(segments) do put(s, s.p1); put(s, s.p2) end
  -- HashMultimap key order
  do
    local hs = {}
    for i, sk in ipairs(order) do hs[i] = G.segment_hash(per[sk].s) end
    order = hash_order(order, hs, 16)
  end
  local edges, eseen = {}, {}
  for _, sk in ipairs(order) do
    local e = per[sk]
    local s = e.s
    local start = s.p1
    if s.p2.x < s.p1.x or (s.p2.x == s.p1.x and s.p2.y < s.p1.y) then start = s.p2 end
    local pts = e.pts
    G.stable_sort(pts, function(p) return dist(p, start) end)
    for i = 1, #pts - 1 do
      local ed = seg(pts[i], pts[i + 1])
      local k = G.seg_key(ed)
      if not eseen[k] then eseen[k] = true; edges[#edges + 1] = ed end
    end
  end
  -- HashSet<LineSegmentXZ> edges order
  do
    local hs = {}
    for i, ed in ipairs(edges) do hs[i] = G.segment_hash(ed) end
    edges = hash_order(edges, hs, 16)
  end
  local nodes, nseen = {}, {}
  for _, ed in ipairs(edges) do
    for _, p in ipairs({ ed.p1, ed.p2 }) do
      local k = key(p)
      if not nseen[k] then nseen[k] = true; nodes[#nodes + 1] = p end
    end
  end
  return faces_from_fully_noded_graph(nodes, edges)
end

-- FaceDecompositionUtil.splitPolygonIntoFaces(outer ring, hole rings, other segments)
function G.split_polygon_into_faces(outer, holes, others)
  local segs = {}
  for _, s in ipairs(G.segments(outer)) do segs[#segs + 1] = s end
  for _, h in ipairs(holes) do for _, s in ipairs(G.segments(h)) do segs[#segs + 1] = s end end
  for _, s in ipairs(others) do segs[#segs + 1] = s end
  local faces = G.faces_from_graph(segs)
  local res = {}
  for _, f in ipairs(faces) do
    local p = G.point_inside(f)
    local keep = G.ring_contains(outer, p)
    if keep then
      for _, h in ipairs(holes) do if G.ring_contains(h, p) then keep = false; break end end
    end
    if keep then res[#res + 1] = f end
  end
  return res
end

---------------------------------------------------------------- tag values (ValueParseUtil)

local function java_parse_int(s)
  if type(s) ~= "string" or not s:match("^[+-]?%d+$") then return nil end
  local v = tonumber(s:sub(1, 1) == "+" and s:sub(2) or s)
  if not v or v > 2147483647 or v < -2147483648 then return nil end
  return v
end

function G.parse_osm_decimal(value, constraint)
  if value == nil then return nil end
  value = tostring(value)
  local r = java_parse_int(value)
  if r and (not constraint or constraint(r)) then return r end
  local before, after = value:match("^(%-?%d+)%.(%d+)$")
  if before then
    local b, a = java_parse_int(before), java_parse_int(after)
    if b and a then
      local neg = before:sub(1, 1) == "-"
      local res = abs(b) + 10 ^ (-#after) * a
      if neg then res = -res end
      if not constraint or constraint(res) then return res end
    end
  end
  return nil
end
local function positive(v) return v > 0 end
local function nonnegative(v) return v >= 0 end

function G.parse_measure(value)
  if value == nil then return nil end
  value = tostring(value)
  local m = G.parse_osm_decimal(value, positive)
  if m then return m end
  local s = value:match("^([%d%.]+)%s*m$")
  if s then return G.parse_osm_decimal(s, positive) end
  s = value:match("^([%d%.]+)%s*km$")
  if s then local v = G.parse_osm_decimal(s, positive); return v and 1000 * v end
  s = value:match("^([%d%.]+)%s*mi$")
  if s then local v = G.parse_osm_decimal(s, positive); return v and 1609.344 * v end
  local f, i = value:match("^(%d+)'%s*(%d+)\"$")
  if f then
    f, i = java_parse_int(f), java_parse_int(i)
    if f and i and f >= 0 and i >= 0 and i < 12 then return 0.0253999996930360794 * (12 * f + i) end
  end
  return nil
end

local CARDINAL = { N = 0, NNE = 22.5, NE = 45, ENE = 67.5, E = 90, ESE = 112.5, SE = 135, SSE = 157.5, S = 180,
  SSW = 202.5, SW = 225, WSW = 247.5, W = 270, WNW = 292.5, NW = 315, NNW = 337.5 }
function G.parse_angle(value)
  if value == nil then return nil end
  value = tostring(value)
  local m = G.parse_osm_decimal(value, nonnegative)
  if m then return math.fmod(m, 360) end
  return CARDINAL[value]
end

return G
