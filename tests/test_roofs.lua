-- usage (from the repo root): luajit tests/test_roofs.lua
package.path = "./?.lua;./?/init.lua;" .. package.path
local o2w = require("o2w")
local R = require("o2w.roof")
local G = require("o2w.geom")
local abs, sqrt, tan, rad = math.abs, math.sqrt, math.tan, math.rad

local fails, checks = 0, 0
local function check(c, msg)
  checks = checks + 1
  if not c then fails = fails + 1; print("FAIL " .. msg) end
end
local function near(a, b, eps) return a ~= nil and b ~= nil and abs(a - b) <= (eps or 1e-6) end
local function f(x) return string.format("%.4f", x or 0 / 0) end

local RECT = { outer = { 0, 0, 10, 0, 10, 6, 0, 6 } }
local L_SHAPE = { outer = { 0, 0, 12, 0, 12, 5, 5, 5, 5, 10, 0, 10 } }
local COURT = { outer = { 0, 0, 20, 0, 20, 12, 0, 12 }, holes = { { 7, 4, 7, 8, 13, 8, 13, 4 } } }
local HEIGHT_FIELD = { "flat", "gabled", "saltbox", "hipped", "side_hipped", "half-hipped", "side_half-hipped",
  "gambrel", "mansard", "sawtooth", "pyramidal", "cone", "skillion", "round" }

-- renders a roof into a fresh collector, returns the triangles { {x,y,z,u,v}, {..}, {..}, colour }
local function render(roof, base, light)
  local out = o2w.collector()
  roof:render(out, base or 0, { 200, 100, 50 }, light or function(nx, ny, nz) return 0.5 + 0.5 * nz end)
  local tris = {}
  for _, g in ipairs(out:groups()) do
    local d = g.d
    for t = 0, g.n / 3 - 1 do
      local tri = { material = g.material }
      for k = 0, 2 do
        local o = t * 24 + k * 8
        tri[k + 1] = { d[o + 1], d[o + 2], d[o + 3], d[o + 4], d[o + 5] }
      end
      tri.colour = { d[t * 24 + 6], d[t * 24 + 7], d[t * 24 + 8] }
      tris[#tris + 1] = tri
    end
  end
  return tris, out
end

local function tri_area2d(t)
  local a, b, c = t[1], t[2], t[3]
  return ((b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1])) / 2
end

local function poly_area(P)
  local a = G.area(G.ring_from_flat(P.outer))
  for _, h in ipairs(P.holes or {}) do a = a - G.area(G.ring_from_flat(h)) end
  return a
end

local function point_in_tri(px, py, t)
  local function cr(a, b) return (b[1] - a[1]) * (py - a[2]) - (b[2] - a[2]) * (px - a[1]) end
  local c1, c2, c3 = cr(t[1], t[2]), cr(t[2], t[3]), cr(t[3], t[1])
  return (c1 >= 0 and c2 >= 0 and c3 >= 0) or (c1 <= 0 and c2 <= 0 and c3 <= 0)
end

-- seen from above, the triangles cover the outline exactly once and none is flipped
local function check_cover(name, tris, P)
  local sum, flipped = 0, 0
  for _, t in ipairs(tris) do
    local a = tri_area2d(t)
    sum = sum + a
    if a < -1e-9 then flipped = flipped + 1 end
  end
  check(flipped == 0, name .. ": " .. flipped .. " flipped triangles")
  check(near(sum, poly_area(P), 1e-6), name .. ": projected area " .. f(sum) .. " ~= " .. f(poly_area(P)))
  -- sample points: inside the outline exactly one triangle, outside (or in a hole) none
  local outer = G.ring_from_flat(P.outer)
  local GP = R.to_poly(P)
  local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
  for _, v in ipairs(outer) do
    x0, y0, x1, y1 = math.min(x0, v.x), math.min(y0, v.y), math.max(x1, v.x), math.max(y1, v.y)
  end
  local bad = 0
  for i = 0, 40 do
    for j = 0, 40 do
      local px = x0 - 1 + (x1 - x0 + 2) * (i + 0.37) / 41
      local py = y0 - 1 + (y1 - y0 + 2) * (j + 0.61) / 41
      local n = 0
      for _, t in ipairs(tris) do if point_in_tri(px, py, t) then n = n + 1 end end
      local want = G.poly_contains(GP, G.V(px, py)) and 1 or 0
      if n ~= want then bad = bad + 1 end
    end
  end
  check(bad == 0, name .. ": " .. bad .. " sample points not covered exactly once")
end

local function zrange(tris)
  local lo, hi = math.huge, -math.huge
  for _, t in ipairs(tris) do
    for k = 1, 3 do lo = math.min(lo, t[k][3]); hi = math.max(hi, t[k][3]) end
  end
  return lo, hi
end

local function seg_len(s) return sqrt((s[3] - s[1]) ^ 2 + (s[4] - s[2]) ^ 2) end

---------------------------------------------------------------- every height field shape on the rectangle

for _, shape in ipairs(HEIGHT_FIELD) do
  local roof = R.create(shape, RECT, { ["roof:height"] = "3", ["roof:direction"] = shape == "skillion" and "90" or nil },
    "ROOF_DEFAULT")
  check(roof.shape == shape, shape .. ": created as " .. tostring(roof.shape) .. " " .. tostring(roof.error))
  local tris = render(roof, 10)
  check(#tris > 0, shape .. ": no triangles")
  check_cover(shape, tris, RECT)
  local lo, hi = zrange(tris)
  local want = shape == "flat" and 10 or 13
  check(near(hi, want, 1e-9), shape .. ": max z " .. f(hi) .. " ~= " .. want)
  check(lo >= 10 - 1e-9, shape .. ": min z " .. f(lo) .. " below the roof base")
  for _, t in ipairs(tris) do
    check(t.material == "ROOF_DEFAULT", shape .. ": material " .. tostring(t.material))
    for k = 1, 3 do
      local v = t[k]
      check(near(v[3], 10 + roof:height_at(v[1], v[2]), 1e-9), shape .. ": vertex z not base + height_at")
      check(v[4] == v[4] and v[5] == v[5], shape .. ": NaN texture coordinate")
    end
  end
  -- the polygon still has the outline's corners, inner segments lie inside it
  local P = roof:polygon()
  check(#P.outer >= 8, shape .. ": polygon lost points")
  for _, s in ipairs(roof:inner_segments()) do
    local cx, cy = (s[1] + s[3]) / 2, (s[2] + s[4]) / 2
    check(cx > -1e-9 and cx < 10 + 1e-9 and cy > -1e-9 and cy < 6 + 1e-9, shape .. ": inner segment outside")
  end
end

---------------------------------------------------------------- shape details

do -- gabled: ridge along the long side, ends on the short walls at full height
  local roof = R.create("gabled", RECT, { ["roof:height"] = "3" }, "ROOF_DEFAULT")
  local segs = roof:inner_segments()
  check(#segs == 1, "gabled: one ridge segment, got " .. #segs)
  local s = segs[1]
  check(near(s[2], 3) and near(s[4], 3), "gabled: ridge at y = 3")
  check(near(math.min(s[1], s[3]), 0) and near(math.max(s[1], s[3]), 10), "gabled: ridge from x = 0 to 10")
  check(near(roof:height_at(s[1], s[2]), 3) and near(roof:height_at(s[3], s[4]), 3), "gabled: ridge ends at full height")
  check(near(roof:height_at(5, 0), 0) and near(roof:height_at(5, 6), 0), "gabled: eaves at 0")
  check(near(roof:height_at(5, 1.5), 1.5), "gabled: half way up at y = 1.5")
  -- the ridge end points were inserted into the short walls
  local P = roof:polygon()
  check(#P.outer == 12, "gabled: 2 points inserted into the outline, got " .. (#P.outer / 2))
  -- across: ridge along the short side
  local across = R.create("gabled", RECT, { ["roof:height"] = "3", ["roof:orientation"] = "across" }, "ROOF_DEFAULT")
  local a = across:inner_segments()[1]
  check(near(a[1], 5) and near(a[3], 5) and near(seg_len(a), 6), "gabled across: ridge at x = 5, 6 long")
  -- roof:direction is the slope direction, so the ridge runs across it
  local dir = R.create("gabled", RECT, { ["roof:height"] = "3", ["roof:direction"] = "N" }, "ROOF_DEFAULT")
  local d = dir:inner_segments()[1]
  check(near(d[2], 3) and near(d[4], 3), "gabled roof:direction=N: ridge east-west")
  local dir2 = R.create("gabled", RECT, { ["roof:height"] = "3", ["roof:direction"] = "88" }, "ROOF_DEFAULT")
  local d2 = dir2:inner_segments()[1]
  check(near(d2[1], 5) and near(d2[3], 5), "gabled roof:direction=88 snaps to 90: ridge north-south")
  local rd = R.create("gabled", RECT, { ["roof:height"] = "3", ["roof:ridge:direction"] = "0" }, "ROOF_DEFAULT")
  local r1 = rd:inner_segments()[1]
  check(near(r1[1], 5) and near(r1[3], 5), "gabled roof:ridge:direction=0: ridge north-south")
end

do -- saltbox: ridge moved towards the back (0.7)
  local roof = R.create("saltbox", RECT, { ["roof:height"] = "3" }, "ROOF_DEFAULT")
  local s = roof:inner_segments()[1]
  check(near(s[2], s[4]) and not near(s[2], 3), "saltbox: ridge off centre, y = " .. f(s[2]))
  check(near(abs(s[2] - 3), 6 * 0.2, 1e-9), "saltbox: ridge 0.2 of the depth from the centre")
end

do -- hipped: ridge shorter than the building by 1/3 of the short side at each end
  local roof = R.create("hipped", RECT, { ["roof:height"] = "3" }, "ROOF_DEFAULT")
  local segs = roof:inner_segments()
  check(#segs == 5, "hipped: ridge + 4 hip lines, got " .. #segs)
  local ridge = segs[1]
  check(near(seg_len(ridge), 10 - 2 * 6 / 3), "hipped: ridge length " .. f(seg_len(ridge)))
  check(near(math.min(ridge[1], ridge[3]), 2) and near(math.max(ridge[1], ridge[3]), 8), "hipped: ridge from 2 to 8")
  check(near(roof:height_at(2, 3), 3) and near(roof:height_at(8, 3), 3), "hipped: ridge at full height")
  for _, c in ipairs({ { 0, 0 }, { 10, 0 }, { 10, 6 }, { 0, 6 } }) do
    check(near(roof:height_at(c[1], c[2]), 0), "hipped: corner at 0")
  end
  check(#roof:polygon().outer == 8, "hipped: no points inserted")
  local tris = render(roof, 0)
  check(#tris == 6, "hipped: 6 triangles (2 trapezoids, 2 triangles), got " .. #tris)
end

do -- side_hipped: hip at one end only
  local roof = R.create("side_hipped", RECT, { ["roof:height"] = "3" }, "ROOF_DEFAULT")
  local segs = roof:inner_segments()
  check(#segs == 3, "side_hipped: ridge + 2 hip lines, got " .. #segs)
  check(near(seg_len(segs[1]), 10 - 2), "side_hipped: ridge 8 long, got " .. f(seg_len(segs[1])))
end

do -- half-hipped: small hips that end 1/6 down the gable walls
  local roof = R.create("half-hipped", RECT, { ["roof:height"] = "3" }, "ROOF_DEFAULT")
  local ridge = roof:inner_segments()[1]
  check(near(seg_len(ridge), 10 - 2 * 6 / 6), "half-hipped: ridge length " .. f(seg_len(ridge)))
  check(near(roof:height_at(0, 4), 2) and near(roof:height_at(10, 2), 2), "half-hipped: hip ends at 2/3 height")
end

do -- gambrel and mansard: two slopes, knee at 2/3 height
  local g = R.create("gambrel", RECT, { ["roof:height"] = "3" }, "ROOF_DEFAULT")
  check(near(g:height_at(5, 1), 2) and near(g:height_at(5, 5), 2), "gambrel: knee lines at 2/3 height")
  check(#g:inner_segments() == 3, "gambrel: 3 lines")
  local m = R.create("mansard", RECT, { ["roof:height"] = "3" }, "ROOF_DEFAULT")
  check(#m:inner_segments() == 13, "mansard: 13 lines")
  check(near(m:height_at(10 - 2 / 3, 1), 2), "mansard: edge at 2/3 height")
end

do -- pyramidal: apex at the centroid
  local roof = R.create("pyramidal", RECT, { ["roof:height"] = "4" }, "ROOF_DEFAULT")
  check(near(roof:height_at(5, 3), 4), "pyramidal: apex height")
  local tris = render(roof, 2)
  check(#tris == 4, "pyramidal: 4 triangles")
  local apex = 0
  for _, t in ipairs(tris) do
    for k = 1, 3 do
      if near(t[k][3], 6) then
        apex = apex + 1
        check(near(t[k][1], 5) and near(t[k][2], 3), "pyramidal: apex at the centroid")
      end
    end
  end
  check(apex == 4, "pyramidal: every triangle meets at the apex")
  local tri = R.create("pyramidal", { outer = { 0, 0, 9, 0, 0, 6 } }, { ["roof:height"] = "1" }, "ROOF_DEFAULT")
  check(near(tri:height_at(3, 2), 1), "pyramidal: triangle apex at its centroid (3, 2)")
end

do -- skillion: slopes down towards roof:direction
  local east = R.create("skillion", RECT, { ["roof:height"] = "2", ["roof:direction"] = "90" }, "ROOF_DEFAULT")
  check(near(east:height_at(0, 3), 2) and near(east:height_at(10, 3), 0), "skillion E: high in the west, low in the east")
  check(near(east:height_at(5, 0), 1), "skillion E: half way at x = 5")
  local south = R.create("skillion", RECT, { ["roof:height"] = "2", ["roof:direction"] = "S" }, "ROOF_DEFAULT")
  check(near(south:height_at(5, 6), 2) and near(south:height_at(5, 0), 0), "skillion S: high in the north")
  local angle = R.create("skillion", RECT, { ["roof:angle"] = "30", ["roof:direction"] = "W" }, "ROOF_DEFAULT")
  check(near(angle:preliminary_height(), tan(rad(30)) * 10), "skillion: roof:angle over the 10 m slope")
  check(near(angle:height_at(10, 3), tan(rad(30)) * 10) and near(angle:height_at(0, 3), 0), "skillion W: high in the east")
  local none = R.create("skillion", RECT, { ["roof:height"] = "2" }, "ROOF_DEFAULT")
  check(near(none:height_at(3, 3), 2), "skillion without roof:direction: flat at the roof height")
  -- slope direction diagonal to the outline: the top is a corner
  local diag = R.create("skillion", RECT, { ["roof:height"] = "2", ["roof:direction"] = "45.5" }, "ROOF_DEFAULT")
  check(near(diag:height_at(0, 0), 2), "skillion NE: top at the south-west corner, got " .. f(diag:height_at(0, 0)))
  check_cover("skillion diagonal", render(diag, 0), RECT)
end

do -- sawtooth: teeth from roof:height and roof:angle
  local roof = R.create("sawtooth", { outer = { 0, 0, 20, 0, 20, 12, 0, 12 } }, { ["roof:height"] = "2" }, "ROOF_DEFAULT")
  -- 12 m across, 2 m high at 45 degrees: 6 teeth of 2 m
  check(roof.num_teeth == 6, "sawtooth: 6 teeth, got " .. tostring(roof.num_teeth))
  check(#roof:inner_segments() == 10, "sawtooth: 5 ridges + 5 lower edges, got " .. #roof:inner_segments())
  check_cover("sawtooth 20x12", render(roof, 0), { outer = { 0, 0, 20, 0, 20, 12, 0, 12 } })
end

do -- round: arc through the eaves and the ridge
  local roof = R.create("round", RECT, { ["roof:height"] = "3" }, "ROOF_DEFAULT")
  check(near(roof:height_at(5, 3), 3) and near(roof:height_at(5, 0), 0), "round: ridge 3, eaves 0")
  local h = roof:height_at(5, 1.5)
  check(h > 1.5 and h < 3, "round: convex, " .. f(h) .. " at a quarter")
end

---------------------------------------------------------------- L shape, courtyard

for _, shape in ipairs({ "gabled", "hipped", "flat", "pyramidal", "half-hipped", "mansard", "gambrel", "skillion" }) do
  local roof = R.create(shape, L_SHAPE, { ["roof:height"] = "3", ["roof:direction"] = shape == "skillion" and "0" or nil },
    "ROOF_DEFAULT")
  check(roof.error == nil, "L " .. shape .. ": " .. tostring(roof.error))
  local tris = render(roof, 0)
  check_cover("L " .. shape, tris, L_SHAPE)
  local lo, hi = zrange(tris)
  check(lo >= -1e-9, "L " .. shape .. ": below base " .. f(lo))
  if shape ~= "flat" then check(hi <= 3 + 1e-9 and hi > 1, "L " .. shape .. ": max z " .. f(hi)) end
end
do -- L-shaped gabled: the ridge runs along the long direction of the minimum bounding box, at full height
  local roof = R.create("gabled", L_SHAPE, { ["roof:height"] = "3" }, "ROOF_DEFAULT")
  local _, hi = zrange(render(roof, 0))
  check(near(hi, 3), "L gabled: ridge at full height")
end

for _, shape in ipairs({ "flat", "gabled", "hipped", "skillion", "round" }) do
  local roof = R.create(shape, COURT, { ["roof:height"] = "3", ["roof:direction"] = "90" }, "ROOF_DEFAULT")
  check(roof.error == nil, "courtyard " .. shape .. ": " .. tostring(roof.error))
  local tris = render(roof, 5)
  check_cover("courtyard " .. shape, tris, COURT)
  check(#roof:polygon().holes == 1, "courtyard " .. shape .. ": hole kept")
end
do -- the gabled ridge crosses the courtyard: points are inserted into the hole too
  local roof = R.create("gabled", COURT, { ["roof:height"] = "3" }, "ROOF_DEFAULT")
  check(#roof:polygon().holes[1] == 12, "courtyard gabled: 2 points inserted into the hole")
  check(#roof:inner_segments() == 2, "courtyard gabled: ridge split by the hole into 2")
end

---------------------------------------------------------------- roof:height and roof:angle

do
  local function prelim(shape, tags, poly) return R.create(shape, poly or RECT, tags, "ROOF_DEFAULT"):preliminary_height() end
  check(near(prelim("gabled", { ["roof:height"] = "2.5" }), 2.5), "roof:height 2.5")
  check(near(prelim("gabled", { ["roof:height"] = "2.5 m" }), 2.5), "roof:height '2.5 m'")
  check(near(prelim("gabled", { ["roof:height"] = "3'6\"" }), 0.0253999996930360794 * 42), "roof:height feet and inches")
  check(prelim("gabled", { ["roof:height"] = "-2" }) == nil, "negative roof:height ignored")
  check(prelim("gabled", {}) == nil, "no tags: no preliminary height")
  check(near(prelim("gabled", { ["roof:angle"] = "45" }), 3), "gabled roof:angle 45: 3 m over 3 m")
  check(near(prelim("gabled", { ["roof:angle"] = "30" }), tan(rad(30)) * 3), "gabled roof:angle 30")
  check(near(prelim("gabled", { ["roof:angle"] = "30", ["roof:height"] = "1" }), 1), "roof:height wins over roof:angle")
  check(prelim("gabled", { ["roof:angle"] = "90" }) == nil, "roof:angle 90 ignored")
  -- hipped measures to the (shorter) ridge segment: the corners are sqrt(2^2 + 3^2) away
  check(near(prelim("hipped", { ["roof:angle"] = "45" }), sqrt(13)), "hipped roof:angle uses the corner distance")
  check(prelim("pyramidal", { ["roof:angle"] = "45" }) == nil, "pyramidal: no roof:angle support")
  check(prelim("flat", { ["roof:height"] = "3" }) == 0, "flat: height 0")
  check(prelim("dome", { ["roof:height"] = "3" }) == 3, "dome: roof:height")
  check(prelim("sawtooth", { ["roof:angle"] = "30" }) == nil, "sawtooth: roof:height only")
  -- set_height overrides
  local roof = R.create("gabled", RECT, { ["roof:height"] = "3" }, "ROOF_DEFAULT")
  check(near(roof:height(), 3), "height() is the preliminary height before set_height")
  roof:set_height(5)
  check(roof:height() == 5 and near(roof:height_at(5, 3), 5), "set_height(5)")
  local _, hi = zrange(render(roof, 1))
  check(near(hi, 6), "render uses the set height")
  local noh = R.create("gabled", RECT, {}, "ROOF_DEFAULT")
  check(noh:height() == nil, "height() nil without tags or set_height")
end

---------------------------------------------------------------- non height field roofs

do
  for _, shape in ipairs({ "dome", "onion" }) do
    local roof = R.create(shape, RECT, { ["roof:height"] = "4" }, "ROOF_DEFAULT")
    local tris = render(roof, 10)
    local lo, hi = zrange(tris)
    check(near(lo, 10) and near(hi, 14), shape .. ": z from 10 to 14, got " .. f(lo) .. " " .. f(hi))
    -- every triangle faces away from the vertical axis through the centre (or up)
    local inward = 0
    for _, t in ipairs(tris) do
      local a, b, c = t[1], t[2], t[3]
      local ux, uy, uz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
      local vx, vy, vz = c[1] - a[1], c[2] - a[2], c[3] - a[3]
      local nx, ny, nz = uy * vz - uz * vy, uz * vx - ux * vz, ux * vy - uy * vx
      local cx, cy = (a[1] + b[1] + c[1]) / 3 - 5, (a[2] + b[2] + c[2]) / 3 - 3
      if nx * cx + ny * cy < -1e-9 and nz <= 1e-9 then inward = inward + 1 end
    end
    check(inward == 0, shape .. ": " .. inward .. " triangles facing inwards")
    check(roof:height_at(5, 3) == 0 and #roof:inner_segments() == 0, shape .. ": no height field")
  end
  local dome = R.create("dome", RECT, { ["roof:height"] = "4" }, "ROOF_DEFAULT")
  check(#render(dome, 0) == 8 * 4 * 2 + 4, "dome: 8 rings of quads + a fan of 4, got " .. #render(dome, 0))
  local ch = R.create("chimney", { outer = { 0, 0, 1, 0, 1, 1, 0, 1 } }, {}, "BRICK")
  check(ch:preliminary_height() == 0, "chimney: height 0")
  local out = o2w.collector()
  local _, smoke = ch:render(out, 20, { 255, 255, 255 }, nil)
  local tris = render(ch, 20)
  local top, bottom, area = 0, 0, 0
  for _, t in ipairs(tris) do
    if near(t[1][3], 20) and near(t[2][3], 20) and near(t[3][3], 20) then
      top = top + 1; area = area + tri_area2d(t)
      check(tri_area2d(t) > 0, "chimney: top triangle facing down")
    elseif near(t[1][3], 17) and near(t[2][3], 17) and near(t[3][3], 17) then
      bottom = bottom + 1
    end
  end
  check(near(area, 1 - 0.64), "chimney: ring area " .. f(area))
  check(bottom == 2, "chimney: hole bottom 2 triangles")
  check(#tris == top + bottom + 8, "chimney: 4 inner walls")
  check(near(smoke[1], 0.5) and near(smoke[2], 0.5) and near(smoke[3], 17), "chimney: smoke emitter at the hole bottom")
end

---------------------------------------------------------------- shapes falling back to flat

do
  check(R.create("complex", RECT, {}, "ROOF_DEFAULT").shape == "flat", "complex: flat")
  check(R.create(nil, RECT, {}, "ROOF_DEFAULT").shape == "flat", "nil shape: flat")
  check(R.create("banana", RECT, {}, "ROOF_DEFAULT").shape == "flat", "unknown shape: flat")
end

---------------------------------------------------------------- collector, colour, light, texture coordinates

do
  local out = o2w.collector()
  local roof = R.create("gabled", RECT, { ["roof:height"] = "3" }, "ROOF_DEFAULT")
  roof:render(out, 4, { 100, 200, 50 }, function(nx, ny, nz) return nz end)
  local groups = out:groups()
  check(#groups == 1 and groups[1].material == "ROOF_DEFAULT" and groups[1].n == 12, "collector: one group of 4 triangles")
  local d = groups[1].d
  local nz = 6 / sqrt(36 + 9 * 4) -- slope 3 m over 3 m: normal z = cos(45)
  nz = 1 / sqrt(2)
  check(near(d[6], 100 * nz) and near(d[7], 200 * nz) and near(d[8], 50 * nz), "collector: colour times light(normal)")
  -- SLOPED_TRIANGLES: the texture v runs down the slope, u along it; one copy per 2.4 m (ROOF_DEFAULT)
  local tris = render(roof, 0)
  for _, t in ipairs(tris) do
    local a, b = t[1], t[2]
    -- along the ridge direction (x) v stays constant, u changes by dx / 2.4
    local dxy = sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
    local du, dv = b[4] - a[4], b[5] - a[5]
    check(near(sqrt(du * du + dv * dv) * 2.4, dxy, 1e-9), "sloped tex coords: horizontal distance / 2.4")
  end
  local south = tris[1]
  -- triangles on the same face share one orientation: u changes only with x
  for _, t in ipairs(tris) do
    for k = 2, 3 do
      if near(t[k][2], t[1][2]) then check(near(t[k][5], t[1][5]), "sloped tex coords: v constant along the eaves") end
    end
  end
  local _ = south
end

---------------------------------------------------------------- where OSM2World fails, so does the port

do
  -- pyramidal roofs know no height for the courtyard's corners (OSM2World: NullPointerException)
  local roof = R.create("pyramidal", COURT, { ["roof:height"] = "3" }, "ROOF_DEFAULT")
  check(not pcall(render, roof, 0), "pyramidal with a courtyard: render fails like OSM2World")
  -- create itself never raises (where a roof constructor fails it returns a flat roof with roof.error set)
  for _, shape in ipairs(HEIGHT_FIELD) do
    check(pcall(R.create, shape, { outer = { 0, 0, 1, 0 } }, {}, "ROOF_DEFAULT"), shape .. ": create raised on a degenerate outline")
  end
end

---------------------------------------------------------------- against OSM2World's own output

do
  local function nums(s) local t = {} for x in s:gmatch("%S+") do t[#t + 1] = tonumber(x) end return t end
  local function split(s, sep)
    local t = {}
    for p in (s .. sep):gmatch("(.-)%" .. sep) do t[#t + 1] = p end
    return t
  end
  local function close(a, b, eps)
    if #a ~= #b then return false end
    for i = 1, #a do if abs(a[i] - b[i]) > (eps or 1e-6) then return false end end
    return true
  end
  local cases, cur = {}, nil
  for line in io.lines("tests/data/osm2world_roofs.txt") do
    local kind, rest = line:match("^(%u+) ?(.*)$")
    if kind == "INPUT" then
      cur = { input = rest, OUTER = {}, HOLE = {}, SEG = {}, TRI = {}, VOIDTRI = {}, MODEL = {} }
      cases[#cases + 1] = cur
    elseif kind == "PRELIM" then
      cur.prelim = tonumber(rest)
    elseif kind == "MODEL" then
      cur.MODEL[1] = nums(rest:gsub("[(),]", " "))
    elseif kind and cur and cur[kind] then
      table.insert(cur[kind], nums(rest))
    end
  end
  check(#cases > 50, "OSM2World fixture loaded")
  local identical = 0
  for _, c in ipairs(cases) do
    local f = split(c.input, "|")
    local name = f[1]
    local holes = {}
    if f[4]:match("%S") then for _, h in ipairs(split(f[4], ";")) do holes[#holes + 1] = nums(h) end end
    local tags = {}
    for _, kv in ipairs(split(f[5], ";")) do local k, v = kv:match("^(.-)=(.*)$"); tags[k] = v end
    local roof = R.create(f[2], { outer = nums(f[3]), holes = holes }, tags, "ROOF_DEFAULT")
    check(roof.error == nil, name .. ": " .. tostring(roof.error))
    local ph = roof:preliminary_height()
    check((ph == nil and c.prelim == nil) or (ph ~= ph and c.prelim ~= c.prelim) or near(ph, c.prelim), name .. ": preliminary height " .. tostring(ph) .. " vs " .. tostring(c.prelim))
    local P = roof:polygon()
    check(close(P.outer, c.OUTER[1]), name .. ": polygon differs from OSM2World")
    check(#P.holes == #c.HOLE, name .. ": hole count")
    for i, h in ipairs(c.HOLE) do check(P.holes[i] and close(P.holes[i], h), name .. ": hole differs") end
    local segs = roof:inner_segments()
    local seg_ok = #segs == #c.SEG
    for i, s in ipairs(c.SEG) do seg_ok = seg_ok and close(segs[i], s) end
    check(seg_ok, name .. ": inner segments differ from OSM2World")
    roof:set_height(tonumber(f[6]))
    local out = { materials = { ROOF_DEFAULT = { w = 2.4, h = 2.4 }, VOID = { w = 1, h = 1 } }, t = {}, void = {} }
    function out:tri(m, x1, y1, z1, u1, v1, x2, y2, z2, u2, v2, x3, y3, z3, u3, v3)
      if m == "VOID" then
        table.insert(self.void, { x1, y1, z1, 0, 0, x2, y2, z2, 0, 0, x3, y3, z3, 0, 0 })
      else
        table.insert(self.t, { x1, y1, z1, u1, -v1, x2, y2, z2, u2, -v2, x3, y3, z3, u3, -v3 })
      end
    end
    local _, smoke = roof:render(out, 0, { 255, 255, 255 }, nil)
    local same = #out.t == #c.TRI and #out.void == #c.VOIDTRI
    for i, t in ipairs(c.TRI) do same = same and close(out.t[i], t) end
    for i, t in ipairs(c.VOIDTRI) do same = same and close(out.void[i], t) end
    if c.MODEL[1] then same = same and smoke and close({ smoke[1], smoke[3], smoke[2] }, c.MODEL[1]) end
    check(same, name .. ": triangles differ from OSM2World")
    if same then identical = identical + 1 end
  end
  print(string.format("%d of %d roofs identical to OSM2World (positions, order, texture coordinates)", identical, #cases))
end

print(string.format("%d checks, %d failures", checks, fails))
if fails > 0 then os.exit(1) end
