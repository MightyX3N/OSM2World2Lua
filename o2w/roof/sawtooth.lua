-- ported from OSM2World SawtoothRoof.java (MIT, Copyright OSM2World contributors)
local req = O2W_REQUIRE or require
local G = req("o2w.geom")
local B = req("o2w.roof.base")
local seg = G.seg
local floor, max, min = math.floor, math.max, math.min

local UPSLOPE_PROPORTION = 0.05

local Sawtooth = B.class(B.RoofWithInnerLines)

function Sawtooth:calculate_preliminary_height() return G.parse_measure(self.tags["roof:height"]) end

function Sawtooth:get_inner_lines()
  local l = {}
  for i = 2, #self.ridges do l[#l + 1] = B.inner_line(self.ridges[i], true) end
  for _, e in ipairs(self.lower_edges) do l[#l + 1] = B.inner_line(e, true) end
  return l
end

function Sawtooth:height_at_no_interpolation(pos)
  local r0 = self.ridges[1]
  local n, tl = self.num_teeth, self.tooth_length
  local d = G.distance_from_line(pos, r0.p1, r0.p2)
  local on = min(n - 1, floor(d / tl))
  local last = on == n - 1
  local rel = (d - on * tl) / tl
  local down = last and 1.0 or 1 - UPSLOPE_PROPORTION
  local h = self:roof_height()
  if rel < down then
    return h * max(last and 0 or 0.05, 1 - rel / down)
  else
    return h * max(last and 0 or 0.05, (rel - down) / UPSLOPE_PROPORTION)
  end
end

return function(poly, tags, material)
  local r = setmetatable({}, Sawtooth)
  B.Roof.init(r, poly, tags, material)
  local simplified = G.simplified_polygon(poly.outer)
  local dir = B.ridge_direction_from_tags(r.tags, false, simplified, nil)
  local bbox = G.rotated_bbox(poly.outer, G.fit_angle(G.angle(dir)))
  local left = seg(bbox[1], bbox[4])
  local right = seg(bbox[2], bbox[3])
  local length = G.seg_length(left)
  local height = r:calculate_preliminary_height() or B.DEFAULT_RIDGE_HEIGHT
  local ang = B.parse_roof_angle(r.tags) or math.rad(45)
  local calc_len = height / math.tan(ang)
  r.num_teeth = max(2, floor(length / calc_len + 0.5))
  r.tooth_length = length / r.num_teeth
  r.ridges, r.lower_edges = {}, {}
  for i = 0, r.num_teeth - 1 do
    r.ridges[#r.ridges + 1] = seg(G.seg_point_at(left, i * r.tooth_length), G.seg_point_at(right, i * r.tooth_length))
    if i > 0 then
      local o = (i - UPSLOPE_PROPORTION) * r.tooth_length
      r.lower_edges[#r.lower_edges + 1] = seg(G.seg_point_at(left, o), G.seg_point_at(right, o))
    end
  end
  return r
end
