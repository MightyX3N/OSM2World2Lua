# OSM2World2Lua

3D buildings from OpenStreetMap data in plain Lua, ported from [OSM2World](https://osm2world.org/).

Give it a building's outline and its OSM tags (`height`, `building:levels`, `roof:shape`, colours, materials,
`building:part` areas) and it returns textured triangle lists: walls, windows and roofs. There is no engine code in
it, so it works in LÖVE, Garry's Mod, Roblox or anything else that runs Lua 5.1 / LuaJIT.

Site: https://mightyx3n.github.io/OSM2World2Lua/

```lua
local o2w = require("o2w")
local out = o2w.collector({ max_verts = 65535 })
o2w.building({
  outer = { 0, 0, 10, 0, 10, 8, 0, 8 },             -- metres, x east, y north
  tags = { building = "house", ["building:levels"] = "2", ["roof:shape"] = "gabled" },
  base = 3.5,                                       -- ground elevation
}, out)
for _, g in ipairs(out:groups()) do
  -- g.material (o2w.materials[g.material].tex is its texture), g.d = { x, y, z, u, v, r, g, b, ... }
end
```

## Layout

- `o2w/` the library (`init.lua` is the entry point)
- `textures/` textures from OSM2World's default style (public domain / CC0, see `textures/SOURCES.md`)
- `tools/import_style.py` re-imports the materials and textures from OSM2World-default-style
- `tools/preview/` renders example scenes to pictures (used for the site)
- `examples/` example scenes, `tests/` tests (`luajit tests/test_basic.lua` from the repo root)
- `docs/` the site

## Licence

MIT. This is a port of OSM2World (MIT, © OSM2World contributors); it is not made by the OSM2World team.
