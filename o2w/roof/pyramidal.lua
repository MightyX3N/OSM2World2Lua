-- ported from OSM2World PyramidalRoof.java and ConeRoof.java (MIT, Copyright OSM2World contributors)
local req = O2W_REQUIRE or require
local G = req("o2w.geom")
local B = req("o2w.roof.base")

local Pyramidal = B.class(B.HeightfieldRoof)
function Pyramidal:get_inner_segments() return self.inner end
function Pyramidal:height_at_no_interpolation(pos)
  if G.eq(self.apex, pos) then
    return self:roof_height()
  elseif G.ring_has_vertex(self.original.outer, pos) then
    return 0.0
  end
  return nil
end

-- ConeRoof is a PyramidalRoof with a smooth-shaded material
return function(poly, tags, material)
  local r = setmetatable({}, Pyramidal)
  B.Roof.init(r, poly, tags, material)
  r.apex = G.centroid(poly.outer)
  r.inner = {}
  for _, v in ipairs(poly.outer) do r.inner[#r.inner + 1] = G.seg(v, r.apex) end
  return r
end
