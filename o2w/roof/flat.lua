-- ported from OSM2World FlatRoof.java (MIT, Copyright OSM2World contributors)
local req = O2W_REQUIRE or require
local B = req("o2w.roof.base")

local Flat = B.class(B.HeightfieldRoof)
function Flat:calculate_preliminary_height() return 0.0 end
function Flat:height_at_no_interpolation(pos) return 0.0 end

return function(poly, tags, material)
  local r = setmetatable({}, Flat)
  B.Roof.init(r, poly, tags, material)
  return r
end
