-- ported from OSM2World SkillionRoof.java (MIT, Copyright OSM2World contributors)
local req = O2W_REQUIRE or require
local G = req("o2w.geom")
local B = req("o2w.roof.base")
local V, seg, add, sub, mult = G.V, G.seg, G.add, G.sub, G.mult

local Skillion = B.class(B.HeightfieldRoof)

function Skillion:calculate_preliminary_height()
  local h = G.parse_measure(self.tags["roof:height"])
  if h == nil then
    local a = G.parse_angle(self.tags["roof:angle"])
    if a ~= nil and a >= 0 and a < 90.0 then h = math.tan(math.rad(a)) * self.roof_length end
  end
  return h
end

function Skillion:height_at_no_interpolation(pos)
  local h = self:roof_height()
  if self.ridge == nil then return h end
  local d = G.distance_from_line(pos, self.ridge.p1, self.ridge.p2)
  return h - d / self.roof_length * h
end

return function(poly, tags, material)
  local r = setmetatable({}, Skillion)
  B.Roof.init(r, poly, tags, material)
  local simplified = G.simplified_polygon(poly.outer)
  local ang = B.snap_direction(r.tags["roof:direction"], G.segments(simplified))
  if ang ~= nil then
    local slope = G.from_angle(ang)
    -- the upper segment: outermost intersection of a line from far up the slope to the centre
    local center = G.centroid(simplified)
    local segs = G.intersection_segments(simplified, seg(add(center, mult(slope, -1000)), center))
    local upper, ud
    for _, s in ipairs(segs) do
      local d = G.distance_from_segment(center, s)
      if upper == nil or d > ud then upper, ud = s, d end
    end
    if G.angle_between(G.seg_dir(upper), slope) < math.pi / 180 then
      r.ridge = upper
    else
      local offset = mult(G.right_normal(slope), G.diameter(simplified))
      local cl = seg(sub(center, offset), add(center, offset))
      local top, td
      for _, p in ipairs({ upper.p1, upper.p2 }) do
        local d = G.distance_from_line(p, cl.p1, cl.p2)
        if top == nil or d > td then top, td = p, d end
      end
      r.ridge = seg(sub(top, offset), add(top, offset))
    end
    local m = -math.huge
    for _, v in ipairs(poly.outer) do m = math.max(m, G.distance_from_line(v, r.ridge.p1, r.ridge.p2)) end
    r.roof_length = m
  else
    r.roof_length = 0 / 0
  end
  return r
end
