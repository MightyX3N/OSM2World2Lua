-- A small made-up street for the preview pictures: houses with different roofs, a corner block, a church.
local function rect(x, y, w, d)
  return { x, y, x + w, y, x + w, y + d, x, y + d }
end
return {
  ground = { size = 80, material = "GRASS" },
  buildings = {
    { outer = rect(0, 0, 9, 12), tags = { building = "house", ["building:levels"] = "2", ["roof:shape"] = "gabled", ["roof:colour"] = "red" } },
    { outer = rect(10, 0, 8, 11), tags = { building = "house", ["building:levels"] = "2", ["roof:shape"] = "hipped", ["building:colour"] = "white", ["roof:colour"] = "brown" } },
    { outer = rect(19, 0, 10, 10), tags = { building = "house", ["building:levels"] = "3", ["building:material"] = "brick", ["roof:shape"] = "gabled", ["roof:orientation"] = "across" } },
    { outer = rect(30, 0, 8, 8), tags = { building = "house", ["building:levels"] = "2", ["roof:shape"] = "pyramidal", ["building:colour"] = "#e8d8b0" } },
    { outer = rect(39, 0, 9, 9), tags = { building = "house", ["building:levels"] = "1", ["roof:shape"] = "skillion", ["roof:direction"] = "N", ["building:colour"] = "lightblue" } },
    { outer = { -2, 16, 22, 16, 22, 26, 10, 26, 10, 36, -2, 36 }, tags = { building = "apartments", ["building:levels"] = "5", ["roof:shape"] = "hipped", ["building:colour"] = "#d9c6a5" } },
    { outer = rect(26, 16, 14, 24), tags = { building = "church", ["building:material"] = "stone", height = "16", ["roof:shape"] = "gabled", ["roof:height"] = "7" },
      parts = { { outer = rect(29, 37, 8, 8), tags = { ["building:part"] = "yes", height = "38", ["roof:shape"] = "pyramidal", ["roof:height"] = "12", ["roof:material"] = "copper" } },
                { outer = rect(26, 16, 14, 22), tags = { ["building:part"] = "yes", height = "16", ["roof:shape"] = "gabled", ["roof:height"] = "7" } } } },
    { outer = rect(44, 16, 12, 12), tags = { building = "yes", ["building:levels"] = "4", ["roof:shape"] = "dome", ["building:colour"] = "white" } },
  },
  cameras = { { -25, -35, 22, 22, 15, 6 }, { 60, -40, 30, 25, 20, 8 }, { 20, -12, 2, 20, 10, 6 } },
}
