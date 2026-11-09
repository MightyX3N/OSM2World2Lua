-- ported from OSM2World Roof.java (createRoofForShape) (MIT, Copyright OSM2World contributors)
--
--   local roof = req("o2w.roof").create(shape, poly, tags, material[, opts])
--   shape: roof:shape value; poly: { outer = { x1, y1, ... } (counter-clockwise), holes = { { ... clockwise }, ... } }
--   tags: OSM tags (roof:height, roof:angle, roof:direction, roof:ridge:direction, roof:orientation)
--   material: material name for all roof triangles, e.g. "ROOF_DEFAULT"
--   opts.default_direction = { x, y }: for side_hipped / side_half-hipped, the direction OSM2World derives from
--     the outline segments shared with other building parts (pointing away from them)
-- Methods: roof:polygon(), roof:inner_segments(), roof:preliminary_height(), roof:set_height(h), roof:height(),
--   roof:height_at(x, y), roof:render(out, base_ele, colour, light). See tests/test_roofs.lua for use.
local req = O2W_REQUIRE or require
local G = req("o2w.geom")
local B = req("o2w.roof.base")
local flat = req("o2w.roof.flat")
local ridge = req("o2w.roof.ridge")
local pyramidal = req("o2w.roof.pyramidal")
local skillion = req("o2w.roof.skillion")
local sawtooth = req("o2w.roof.sawtooth")
local spindle = req("o2w.roof.spindle")
local chimney = req("o2w.roof.chimney")

local M = {}
M.DEFAULT_RIDGE_HEIGHT = B.DEFAULT_RIDGE_HEIGHT

local SHAPES = {
  pyramidal = pyramidal,
  onion = spindle.onion,
  skillion = skillion,
  saltbox = ridge.saltbox,
  gabled = ridge.gabled,
  hipped = ridge.hipped,
  side_hipped = ridge.side_hipped,
  ["half-hipped"] = ridge["half-hipped"],
  ["side_half-hipped"] = ridge["side_half-hipped"],
  gambrel = ridge.gambrel,
  mansard = ridge.mansard,
  sawtooth = sawtooth,
  dome = spindle.dome,
  round = ridge.round,
  cone = pyramidal,
  chimney = chimney,
  -- complex needs mapped roof:ridge / roof:edge ways, which this interface has no way to pass: flat
}
M.SHAPES = SHAPES

local function to_poly(poly)
  local holes = {}
  for i, h in ipairs(poly.holes or {}) do holes[i] = G.ring_from_flat(h) end
  return { outer = G.ring_from_flat(poly.outer), holes = holes }
end
M.to_poly = to_poly

-- Roof.createRoofForShape; unknown shapes are flat. Where OSM2World's constructor fails (it then skips the
-- building part) this returns a flat roof with roof.error set instead.
function M.create(shape, poly, tags, material, opts)
  local P = to_poly(poly)
  tags = tags or {}
  local make = SHAPES[shape] or flat
  local ok, r = pcall(make, P, tags, material, opts)
  if ok then
    r.shape = SHAPES[shape] and shape or "flat"
    return r
  end
  local f = flat(P, tags, material)
  f.shape = "flat"
  f.error = r
  return f
end

return M
