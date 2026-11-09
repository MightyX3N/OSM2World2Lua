-- ported from OSM2World Building.java, BuildingPart.java, BuildingDefaults.java, LevelAndHeightData.java and
-- ExteriorBuildingWall.java (MIT, Copyright OSM2World contributors)
--
-- Buildings: walls, windows and roofs from OSM building outlines and tags.
--
--   building.build(b, out, opts)
--   b.outer, b.holes   the building outline in metres (x east, y north; any winding): { x1, y1, x2, y2, ... }
--   b.tags             the building's OSM tags (building, height, building:levels, roof:shape, ...)
--   b.parts            optional building:part areas: { { outer = ..., holes = ..., tags = ... }, ... }
--   b.base             ground elevation (m) the building stands on (OSM2World: the lowest point of its outline)
--   out                a collector (o2w.collector)
--   opts.light(nx, ny, nz) -> brightness for a surface facing that way (default: sun + sky)
-- Windows are OSM2World's FLAT_TEXTURES windows (the BUILDING_WINDOWS texture, one row per level).
local req = O2W_REQUIRE or require
local tri = req("o2w.triangulate")
local colour_of = req("o2w.colour")
local roofs = req("o2w.roof")
local sqrt, max, min, floor, abs, ceil = math.sqrt, math.max, math.min, math.floor, math.abs, math.ceil

local M = {}
M.DEFAULT_RIDGE_HEIGHT = 5

-- ---- tags ----
local function num(v)
  if v == nil then return nil end
  if type(v) == "number" then return v end
  local s = tostring(v):gsub(",", ".")
  local n, unit = s:match("^%s*(%-?[%d%.]+)%s*(%a*)")
  n = tonumber(n)
  if not n then return nil end
  if unit == "ft" or unit == "feet" then n = n * 0.3048 end
  return n
end
M.num = num

-- inheritTags: the part's tags, completed by its building's
local function inherit(tags, parent)
  local t = {}
  for k, v in pairs(parent or {}) do t[k] = v end
  for k, v in pairs(tags or {}) do t[k] = v end
  return t
end

-- ---- BuildingDefaults ----
function M.defaults(tags)
  local t = tags["building:part"]
  if not t or t == "yes" then t = tags.building end
  t = t or "yes"
  local d = { levels = 3, height_per_level = 2.5, roof_shape = "flat", wall = "BUILDING_DEFAULT", roof = "ROOF_DEFAULT",
    windows = true, walls = true }
  if t == "greenhouse" then d.levels, d.wall, d.roof, d.windows = 1, "GLASS_WALL", "GLASS_ROOF", false
  elseif t == "garage" or t == "garages" then d.levels, d.wall, d.roof, d.windows = 1, "CONCRETE", "CONCRETE", false
  elseif t == "carport" then d.levels, d.wall, d.roof, d.windows, d.walls = 1, "CONCRETE", "CONCRETE", false, false
  elseif t == "hut" or t == "shed" then d.levels = 1
  elseif t == "cabin" then d.levels, d.wall, d.roof = 1, "WOOD_WALL", "WOOD"
  elseif t == "roof" then d.levels, d.windows, d.walls = 1, false, false
  elseif t == "church" or t == "hangar" or t == "industrial" then d.windows = false
  end
  if tags.parking == "multi-storey" then d.levels, d.windows = 5, false end
  if tags.man_made == "chimney" or t == "chimney" then
    d.roof_shape, d.levels, d.height_per_level, d.windows, d.wall, d.roof = "chimney", 1, 10, false, "BRICK", "BRICK"
  end
  if tags["roof:shape"] == "flat" and d.roof == "ROOF_DEFAULT" then d.roof = "CONCRETE" end
  return d
end

-- ---- BuildingPart.buildMaterial ----
local SURFACE = {   -- getSurfaceMaterial: surface=* style values that are also used as building materials
  asphalt = "ASPHALT", concrete = "CONCRETE", ["concrete:plates"] = "CONCRETE", ["concrete:lanes"] = "CONCRETE",
  paving_stones = "PAVING_STONE", sett = "SETT", cobblestone = "SETT", gravel = "GRAVEL", grass = "GRASS",
  sand = "SAND", rock = "ROCK", ground = "EARTH", dirt = "EARTH", earth = "EARTH", wood = "WOOD",
  stone = "STONE", metal = "STEEL", steel = "STEEL", tiles = "TILES", marble = "MARBLE", slate = "SLATE",
  sandstone = "SANDSTONE", plaster = "BUILDING_DEFAULT", roof_tiles = "ROOF_DEFAULT", tile = "ROOF_DEFAULT",
}
local BUILDING_COLOURS = {
  white = { 240, 240, 240 }, black = { 76, 76, 76 }, grey = { 100, 100, 100 }, gray = { 100, 100, 100 },
  red = { 255, 190, 190 }, green = { 190, 255, 190 }, blue = { 190, 190, 255 }, yellow = { 255, 255, 175 },
  pink = { 225, 175, 225 }, orange = { 255, 225, 150 }, brown = { 170, 130, 80 },
}
local ROOF_COLOURS = { red = { 204, 0, 0 }, green = { 150, 200, 130 }, blue = { 100, 50, 200 }, brown = { 120, 110, 110 } }
function M.material(mats, material, colour, default, roof)
  local name = default
  if material then
    if material == "adobe" or material == "clay" or material == "mud" or material == "rammed_earth" then name = "ADOBE"
    elseif material == "brick" then name = "BRICK"
    elseif material == "glass" or material == "mirror" then name = roof and "GLASS_ROOF" or "GLASS_WALL"
    elseif material == "copper" and roof then name = "COPPER_ROOF"
    elseif material == "thatch" or material == "reed" then name = "THATCH_ROOF"
    elseif material == "wood" or material == "bamboo" then name = "WOOD_WALL"
    elseif SURFACE[material] then name = SURFACE[material]
    elseif mats[material:upper()] then name = material:upper()
    end
  end
  if not mats[name] then name = default end
  local m = mats[name] or {}
  local c = m.colour or { 255, 255, 255 }
  -- colourable: no texture, or a colourable texture
  if colour and (m.colourable or not m.tex) then
    local key = tostring(colour):lower()
    c = (roof and ROOF_COLOURS[key]) or BUILDING_COLOURS[key] or colour_of(colour) or c
  end
  return name, c
end

-- ---- LevelAndHeightData (levels above ground; indoor level tags are not used) ----
-- PolygonShapeXZ.getDiameter: the largest distance between two outline points
local function diameter(poly)
  local r, best = poly.outer, 0
  for i = 1, #r, 2 do for j = i + 2, #r, 2 do
    local d = (r[i] - r[j]) ^ 2 + (r[i + 1] - r[j + 1]) ^ 2
    if d > best then best = d end
  end end
  return sqrt(best)
end

function M.levels(btags, tags, roof, shape, poly)
  local d = M.defaults(tags)
  local min_level = floor(num(tags["building:min_level"]) or 0)
  local underground = floor(num(tags["building:levels:underground"]) or 0)
  local min_level_ug = min_level > 0 and min_level or min(min_level, -underground)
  local parsed = num(tags["building:levels"])
  local levels
  if parsed then
    levels = max(0, ceil(parsed))
  else
    local h = num(tags.height)
    local rh = num(tags["roof:height"])
    local without = (h or 0) - (rh or 0)
    if h and rh and h <= rh then levels = 0
    elseif rh and without > 0 then levels = max(min_level_ug + 1, max(1, floor(without / d.height_per_level)))
    elseif min_level_ug > 0 then levels = min_level_ug + 1
    else levels = d.levels end
  end
  local roof_levels = floor(num(tags["roof:levels"]) or 1)
  local roof_h = roof:preliminary_height()
  -- (a flat roof's preliminary height is 0)
  if not roof_h and levels == 0 and (num(tags.height) or 0) > 0 then roof_h = num(tags.height) end
  if not roof_h and tags["roof:levels"] and num(tags["roof:levels"]) then roof_h = d.height_per_level * num(tags["roof:levels"]) end
  if not roof_h then
    if shape == "dome" then roof_h = diameter(poly) / 2
    elseif levels == 1 then roof_h = 1
    else roof_h = M.DEFAULT_RIDGE_HEIGHT end
  end
  if roof_h == 0 then roof_levels = 0 end
  local height = num(tags.height) or (levels * d.height_per_level + roof_h)
  height = max(height, 0.01)
  local without = floor((height - roof_h) * 1e4 + 0.5) / 1e4
  local min_h = num(tags.min_height)
  if not min_h then
    if min_level > 0 then min_h = (without / max(levels, 1)) * min_level
    elseif not d.walls then min_h = without - 0.3
    else min_h = 0 end
  end
  if min_h > without then min_h = without - 0.1 end
  local above = max(0, levels - min_level)
  return { height = height, without_roof = without, roof_height = height - without, min_height = min_h,
    levels = above, level_height = above > 0 and (without - min_h) / above or 0, defaults = d }
end

M.SUN = { -0.45, -0.35, 0.82 }
do local s = M.SUN; local l = sqrt(s[1] ^ 2 + s[2] ^ 2 + s[3] ^ 2); M.SUN = { s[1] / l, s[2] / l, s[3] / l } end
function M.default_light(nx, ny, nz)
  local d = nx * M.SUN[1] + ny * M.SUN[2] + nz * M.SUN[3]
  return 0.62 + 0.45 * max(0, d)
end

-- ---- rings ----
local function ring_points(r)
  local pts, n = {}, #r
  if n >= 4 and r[1] == r[n - 1] and r[2] == r[n] then n = n - 2 end
  for k = 1, n, 2 do
    local p = pts[#pts]
    if not p or p[1] ~= r[k] or p[2] ~= r[k + 1] then pts[#pts + 1] = { r[k], r[k + 1] } end
  end
  if #pts > 1 and pts[1][1] == pts[#pts][1] and pts[1][2] == pts[#pts][2] then pts[#pts] = nil end
  return pts
end
local function signed_area(pts)
  local a = 0
  for i = 1, #pts do
    local p, q = pts[i], pts[i % #pts + 1]
    a = a + p[1] * q[2] - q[1] * p[2]
  end
  return a / 2
end
local function flat(pts) local r = {} for _, p in ipairs(pts) do r[#r + 1] = p[1]; r[#r + 1] = p[2] end return r end
local function reverse(pts) local r = {} for i = #pts, 1, -1 do r[#r + 1] = pts[i] end return r end
local function area_of(poly) return abs(signed_area(ring_points(poly.outer))) end

-- SimplePolygonXZ.getSimplifiedPolygon: drops points where the outline goes (almost) straight on
local function is_corner(pts, i)
  local n = #pts
  local a, b, c = pts[(i - 2) % n + 1], pts[i], pts[i % n + 1]
  local ux, uy, vx, vy = b[1] - a[1], b[2] - a[2], c[1] - b[1], c[2] - b[2]
  local lu, lv = sqrt(ux * ux + uy * uy), sqrt(vx * vx + vy * vy)
  if lu == 0 or lv == 0 then return false end
  local cross = (ux * vy - uy * vx) / (lu * lv)
  local dot = (ux * vx + uy * vy) / (lu * lv)
  return not (dot > 0 and abs(cross) < 0.01)
end

-- ---- one building part ----
local function render_part(part, building_tags, base, out, light, mats)
  local tags = inherit(part.tags, building_tags)
  local d = M.defaults(tags)
  local outer = ring_points(part.outer)
  if #outer < 3 then return end
  if signed_area(outer) < 0 then outer = reverse(outer) end
  local holes = {}
  for _, h in ipairs(part.holes or {}) do
    local hp = ring_points(h)
    if #hp >= 3 then
      if signed_area(hp) > 0 then hp = reverse(hp) end
      holes[#holes + 1] = hp
    end
  end
  local poly = { outer = flat(outer), holes = {} }
  for _, h in ipairs(holes) do poly.holes[#poly.holes + 1] = flat(h) end

  -- roof shape (roof:shape, building:roof:shape, the default)
  local shape = tags["roof:shape"] or tags["building:roof:shape"] or d.roof_shape
  local roof_name, roof_col = M.material(mats, tags["roof:material"], tags["roof:colour"], d.roof, true)
  local roof = roofs.create(shape, poly, tags, roof_name)
  local L = M.levels(building_tags, tags, roof, shape, poly)
  roof:set_height(L.height - L.without_roof)

  local wall_name, wall_col = M.material(mats, tags["building:material"], tags["building:colour"], d.wall, false)
  local wall = mats[wall_name] or { w = 1, h = 1 }
  local floor_h = L.min_height
  local floor_ele = base + floor_h
  local top_ele = base + L.without_roof
  local windows = d.windows
  if tags.window then windows = tags.window ~= "no" end
  if tags["building:material"] == "glass" or tags["building:material"] == "mirror" then windows = false end
  local win = mats.BUILDING_WINDOWS

  -- walls (ExteriorBuildingWall), split at the corners; the top follows the roof outline
  local rp = roof:polygon()
  local roof_rings = { ring_points(rp.outer) }
  for _, h in ipairs(rp.holes or {}) do roof_rings[#roof_rings + 1] = ring_points(h) end
  local function top_points(a, b)
    for _, R in ipairs(roof_rings) do
      local ia, ib
      for i, p in ipairs(R) do
        if abs(p[1] - a[1]) < 1e-6 and abs(p[2] - a[2]) < 1e-6 then ia = i end
        if abs(p[1] - b[1]) < 1e-6 and abs(p[2] - b[2]) < 1e-6 then ib = i end
      end
      if ia and ib then
        -- walk the ring in whichever direction goes from a to b along this wall
        local n = #R
        local fwd, bwd = {}, {}
        local i = ia
        repeat fwd[#fwd + 1] = R[i]; if i == ib then break end; i = i % n + 1 until #fwd > n
        i = ia
        repeat bwd[#bwd + 1] = R[i]; if i == ib then break end; i = (i - 2) % n + 1 until #bwd > n
        return (#fwd <= #bwd) and fwd or bwd
      end
    end
    return { a, b }
  end

  if d.walls then
    for ri, R in ipairs({ outer, unpack(holes) }) do
      -- the outside to the right (as OSM2World's wall nodes): the outline counter-clockwise, holes clockwise
      local pts = R
      local n = #pts
      local corners = {}
      for i = 1, n do if is_corner(pts, i) then corners[#corners + 1] = i end end
      if #corners == 0 then corners = { 1 } end
      for c = 1, #corners do
        local i0, i1 = corners[c], corners[c % #corners + 1]
        local wpts = { pts[i0] }
        local i = i0
        repeat i = i % n + 1; wpts[#wpts + 1] = pts[i] until i == i1
        -- along-the-wall positions
        local s = { 0 }
        for k = 2, #wpts do s[k] = s[k - 1] + sqrt((wpts[k][1] - wpts[k - 1][1]) ^ 2 + (wpts[k][2] - wpts[k - 1][2]) ^ 2) end
        local len = s[#s]
        if len > 0.01 then
          local tp = top_points(wpts[1], wpts[#wpts])
          local tops, ts = {}, { 0 }
          for k, p in ipairs(tp) do
            tops[k] = top_ele + roof:height_at(p[1], p[2])
            if k > 1 then ts[k] = ts[k - 1] + sqrt((p[1] - tp[k - 1][1]) ^ 2 + (p[2] - tp[k - 1][2]) ^ 2) end
          end
          local tlen = ts[#ts] > 0 and ts[#ts] or 1
          local min_top = math.huge
          for _, z in ipairs(tops) do if z < min_top then min_top = z end end
          local roof_bottom = min(top_ele, min_top)
          -- straight segments of the wall below the roof
          for k = 1, #wpts - 1 do
            local ax, ay, bx, by = wpts[k][1], wpts[k][2], wpts[k + 1][1], wpts[k + 1][2]
            local sl = s[k + 1] - s[k]
            if sl > 0.001 then
              -- outward normal: the outside is to the right
              local nx, ny = (by - ay) / sl, -(bx - ax) / sl
              local c = light(nx, ny, 0)
              local col = { wall_col[1] * c, wall_col[2] * c, wall_col[3] * c }
              if roof_bottom > floor_ele then
                out:quad(wall_name, ax, ay, bx, by, floor_ele, roof_bottom, s[k] / wall.w, s[k + 1] / wall.w,
                  (floor_ele - base) / wall.h, (roof_bottom - base) / wall.h, col)
              end
            end
          end
          -- windows: rows per level, one window per BUILDING_WINDOWS.per_w metres of the whole wall
          if windows and win and L.levels > 0 and len >= 2 and roof_bottom > floor_ele + 0.5 then
            local cols = max(1, floor(len / (win.per_w or 2.5) + 0.5))
            local rows = L.levels * (roof_bottom - floor_ele) / max(0.01, top_ele - floor_ele)
            for k = 1, #wpts - 1 do
              local ax, ay, bx, by = wpts[k][1], wpts[k][2], wpts[k + 1][1], wpts[k + 1][2]
              local sl = s[k + 1] - s[k]
              if sl > 0.001 then
                local nx, ny = (by - ay) / sl, -(bx - ax) / sl
                local c = light(nx, ny, 0)
                local o = 0.03
                out:quad("BUILDING_WINDOWS", ax + nx * o, ay + ny * o, bx + nx * o, by + ny * o, floor_ele, roof_bottom,
                  s[k] / len * cols, s[k + 1] / len * cols, 0, rows, { 255 * c, 255 * c, 255 * c })
              end
            end
          end
          -- the part of the wall in the roof (gable ends): between the roof bottom line and the roof outline
          local up = false
          for _, z in ipairs(tops) do if z > roof_bottom + 0.01 then up = true end end
          if up then
            -- polygon in wall coordinates (along, height): bottom line left to right, then the top back
            local ring = { 0, roof_bottom, tlen, roof_bottom }
            for k = #tp, 1, -1 do ring[#ring + 1] = ts[k]; ring[#ring + 1] = tops[k] end
            local xs, ys, T = tri(ring, nil)
            local ax, ay, bx, by = tp[1][1], tp[1][2], tp[#tp][1], tp[#tp][2]
            local dx, dy = (bx - ax) / tlen, (by - ay) / tlen
            local c = light(dy, -dx, 0)
            local col = { wall_col[1] * c, wall_col[2] * c, wall_col[3] * c }
            for k = 1, #T, 3 do
              local P = {}
              -- counter-clockwise in (along, up) seen from outside (outside is to the right of travel)
              for _, j in ipairs({ T[k], T[k + 1], T[k + 2] }) do
                P[#P + 1] = { ax + dx * xs[j], ay + dy * xs[j], ys[j], xs[j] / wall.w, -(ys[j] - base) / wall.h }
              end
              out:tri(wall_name, P[1][1], P[1][2], P[1][3], P[1][4], P[1][5], P[2][1], P[2][2], P[2][3], P[2][4], P[2][5],
                P[3][1], P[3][2], P[3][3], P[3][4], P[3][5], col)
            end
          end
        end
      end
    end
  end

  -- roof
  roof:render(out, top_ele, roof_col, light)

  -- bottom when the part does not reach the ground (BuildingBottom)
  if floor_h > 0 then
    local xs, ys, T = tri(poly.outer, poly.holes)
    local c = light(0, 0, -1)
    local col = { wall_col[1] * c, wall_col[2] * c, wall_col[3] * c }
    for k = 1, #T, 3 do
      local i, j, l = T[k], T[k + 2], T[k + 1]
      out:tri(wall_name, xs[i], ys[i], floor_ele, xs[i] / wall.w, ys[i] / wall.h, xs[j], ys[j], floor_ele, xs[j] / wall.w,
        ys[j] / wall.h, xs[l], ys[l], floor_ele, xs[l] / wall.w, ys[l] / wall.h, col)
    end
  end
  return L
end

-- ---- Building: its parts, or the building itself when it has none (or they cover too little of it) ----
function M.build(b, out, opts)
  opts = opts or {}
  local light = opts.light or M.default_light
  local mats = out.materials
  local tags = b.tags or {}
  local parts = {}
  for _, p in ipairs(b.parts or {}) do parts[#parts + 1] = p end
  local use_self = #parts == 0
  local bp = tags["building:part"]
  if bp and bp ~= "no" then use_self = true end
  if not use_self then
    local sum = 0
    for _, p in ipairs(parts) do sum = sum + area_of(p) end
    local a = area_of(b)
    if sum < 0.9 * a and a - sum > 0.1 * a then use_self = true end
  end
  if use_self then parts[#parts + 1] = { outer = b.outer, holes = b.holes, tags = {} } end
  local base = b.base or 0
  local last
  for _, p in ipairs(parts) do
    local ok, L = pcall(render_part, p, tags, base, out, light, mats)
    if ok then last = L elseif opts.on_error then opts.on_error(L) end
  end
  return last
end

return M
