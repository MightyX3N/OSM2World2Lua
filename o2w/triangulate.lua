-- Triangulates a polygon with holes (ear clipping; holes are joined to the outline first).
--   triangulate(outer, holes) -> xs, ys, tris
--   outer: { x1, y1, x2, y2, ... } any winding; holes: list of rings like outer
--   xs, ys: the points used; tris: { i1, i2, i3, ... } indices into xs / ys, counter-clockwise (x right, y up)
local abs, huge = math.abs, math.huge

local function area2(xs, ys, idx)
  local a = 0
  local n = #idx
  for k = 1, n do
    local i, j = idx[k], idx[k % n + 1]
    a = a + xs[i] * ys[j] - xs[j] * ys[i]
  end
  return a
end

local function cross(ax, ay, bx, by, cx, cy) return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax) end

local function inside_tri(px, py, ax, ay, bx, by, cx, cy)
  return cross(ax, ay, bx, by, px, py) >= 0 and cross(bx, by, cx, cy, px, py) >= 0 and cross(cx, cy, ax, ay, px, py) >= 0
end

local function ring(xs, ys, r, ccw)
  -- add a ring's points (dropping a repeated last point and duplicates), return their indices with the winding asked
  local idx = {}
  local n = #r
  if n >= 4 and r[1] == r[n - 1] and r[2] == r[n] then n = n - 2 end
  for k = 1, n, 2 do
    local x, y = r[k], r[k + 1]
    local last = idx[#idx]
    if not last or xs[last] ~= x or ys[last] ~= y then
      xs[#xs + 1], ys[#ys + 1] = x, y
      idx[#idx + 1] = #xs
    end
  end
  if #idx >= 2 and xs[idx[1]] == xs[idx[#idx]] and ys[idx[1]] == ys[idx[#idx]] then idx[#idx] = nil end
  if (area2(xs, ys, idx) > 0) ~= ccw then
    local rev = {}
    for k = #idx, 1, -1 do rev[#rev + 1] = idx[k] end
    idx = rev
  end
  return idx
end

-- join a hole (clockwise) into the outline (counter-clockwise): from the hole's rightmost point to a visible
-- outline point to its right
local function bridge(xs, ys, outline, hole)
  local hm, hx = 1, -huge
  for k, i in ipairs(hole) do if xs[i] > hx then hm, hx = k, xs[i] end end
  local hy = ys[hole[hm]]
  -- nearest outline edge hit by a ray to the right
  local best, bx, bk = huge, nil, nil
  local n = #outline
  for k = 1, n do
    local i, j = outline[k], outline[k % n + 1]
    local y1, y2 = ys[i], ys[j]
    if (y1 <= hy and y2 >= hy or y2 <= hy and y1 >= hy) and y1 ~= y2 then
      local x = xs[i] + (hy - y1) / (y2 - y1) * (xs[j] - xs[i])
      if x >= hx and x - hx < best then
        best = x - hx
        bk = xs[i] > xs[j] and k or (k % n + 1)
        bx = x
      end
    elseif y1 == hy and y2 == hy then
      local k2 = xs[i] < xs[j] and k or (k % n + 1)
      local x = xs[outline[k2]]
      if x >= hx and x - hx < best then best, bk, bx = x - hx, k2, x end
    end
  end
  if not bk then return outline end
  -- a reflex outline point inside the triangle (hole point, hit, candidate) is a better (visible) choice
  local P = outline[bk]
  local px, py = xs[P], ys[P]
  local bestang = huge
  for k = 1, n do
    local i = outline[k]
    if i ~= P then
      local x, y = xs[i], ys[i]
      if x >= hx and (inside_tri(x, y, hx, hy, bx, hy, px, py) or inside_tri(x, y, hx, hy, px, py, bx, hy)) then
        local a = abs(y - hy) / (x - hx + 1e-12)
        if a < bestang then bestang, bk = a, k end
      end
    end
  end
  local out = {}
  for k = 1, bk do out[#out + 1] = outline[k] end
  for k = 0, #hole do out[#out + 1] = hole[(hm - 1 + k) % #hole + 1] end
  for k = bk, n do out[#out + 1] = outline[k] end
  return out
end

return function(outer, holes)
  local xs, ys = {}, {}
  local poly = ring(xs, ys, outer, true)
  local hs = {}
  for _, h in ipairs(holes or {}) do
    local r = ring(xs, ys, h, false)
    if #r >= 3 then hs[#hs + 1] = r end
  end
  table.sort(hs, function(a, b)
    local ma, mb = -huge, -huge
    for _, i in ipairs(a) do if xs[i] > ma then ma = xs[i] end end
    for _, i in ipairs(b) do if xs[i] > mb then mb = xs[i] end end
    return ma > mb
  end)
  for _, h in ipairs(hs) do poly = bridge(xs, ys, poly, h) end

  -- ear clipping on a linked list
  local tris = {}
  local n = #poly
  if n < 3 then return xs, ys, tris end
  local nxt, prv = {}, {}
  for k = 1, n do nxt[k] = k % n + 1; prv[k] = (k - 2) % n + 1 end
  local left, k, stall = n, 1, 0
  while left > 3 do
    local a, b, c = prv[k], k, nxt[k]
    local ia, ib, ic = poly[a], poly[b], poly[c]
    local ax, ay, bx, by, cx, cy = xs[ia], ys[ia], xs[ib], ys[ib], xs[ic], ys[ic]
    local ear = cross(ax, ay, bx, by, cx, cy) > 0
    if ear then
      local m = nxt[c]
      while m ~= a do
        local im = poly[m]
        if im ~= ia and im ~= ib and im ~= ic and inside_tri(xs[im], ys[im], ax, ay, bx, by, cx, cy) then ear = false; break end
        m = nxt[m]
      end
    end
    -- nothing found in a whole round (bad input): take a convex corner anyway, then any corner
    if not ear and stall > left then ear = cross(ax, ay, bx, by, cx, cy) >= 0 or stall > 2 * left end
    if ear then
      tris[#tris + 1] = ia; tris[#tris + 1] = ib; tris[#tris + 1] = ic
      nxt[a], prv[c] = c, a
      left = left - 1
      k = c
      stall = 0
    else
      k = nxt[k]
      stall = stall + 1
    end
  end
  local a = k
  local b, c = nxt[a], nxt[nxt[a]]
  tris[#tris + 1] = poly[a]; tris[#tris + 1] = poly[b]; tris[#tris + 1] = poly[c]
  return xs, ys, tris
end
