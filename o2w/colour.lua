-- OSM colour values (building:colour, roof:colour): "#rrggbb", "#rgb" or a CSS colour name -> { r, g, b } or nil
local NAMES = {
  black = "000000", white = "ffffff", gray = "808080", grey = "808080", silver = "c0c0c0", lightgray = "d3d3d3",
  lightgrey = "d3d3d3", darkgray = "a9a9a9", darkgrey = "a9a9a9", dimgray = "696969", dimgrey = "696969",
  gainsboro = "dcdcdc", whitesmoke = "f5f5f5", red = "ff0000", darkred = "8b0000", maroon = "800000",
  firebrick = "b22222", brown = "a52a2a", sienna = "a0522d", saddlebrown = "8b4513", chocolate = "d2691e",
  peru = "cd853f", tan = "d2b48c", burlywood = "deb887", wheat = "f5deb3", beige = "f5f5dc", ivory = "fffff0",
  linen = "faf0e6", antiquewhite = "faebd7", bisque = "ffe4c4", blanchedalmond = "ffebcd", cornsilk = "fff8dc",
  navajowhite = "ffdead", moccasin = "ffe4b5", papayawhip = "ffefd5", oldlace = "fdf5e6", seashell = "fff5ee",
  snow = "fffafa", orange = "ffa500", darkorange = "ff8c00", coral = "ff7f50", tomato = "ff6347",
  orangered = "ff4500", salmon = "fa8072", lightsalmon = "ffa07a", darksalmon = "e9967a", indianred = "cd5c5c",
  rosybrown = "bc8f8f", pink = "ffc0cb", lightpink = "ffb6c1", hotpink = "ff69b4", yellow = "ffff00",
  lightyellow = "ffffe0", lemonchiffon = "fffacd", khaki = "f0e68c", darkkhaki = "bdb76b", gold = "ffd700",
  goldenrod = "daa520", darkgoldenrod = "b8860b", palegoldenrod = "eee8aa", green = "008000", darkgreen = "006400",
  lime = "00ff00", olive = "808000", olivedrab = "6b8e23", darkolivegreen = "556b2f", forestgreen = "228b22",
  seagreen = "2e8b57", lightgreen = "90ee90", palegreen = "98fb98", yellowgreen = "9acd32", teal = "008080",
  cyan = "00ffff", aqua = "00ffff", turquoise = "40e0d0", blue = "0000ff", navy = "000080", darkblue = "00008b",
  royalblue = "4169e1", steelblue = "4682b4", lightblue = "add8e6", skyblue = "87ceeb", lightsteelblue = "b0c4de",
  slategray = "708090", slategrey = "708090", lightslategray = "778899", darkslategray = "2f4f4f",
  cadetblue = "5f9ea0", purple = "800080", violet = "ee82ee", plum = "dda0dd", lavender = "e6e6fa",
  mintcream = "f5fffa", honeydew = "f0fff0", azure = "f0ffff", aliceblue = "f0f8ff", ghostwhite = "f8f8ff",
  floralwhite = "fffaf0", mistyrose = "ffe4e1", lavenderblush = "fff0f5", sandybrown = "f4a460",
}

return function(v)
  if not v then return nil end
  v = tostring(v):lower():gsub("[%s_%-]", "")
  local h = v:match("^#?(%x%x%x%x%x%x)$")
  if not h then
    local s = v:match("^#(%x%x%x)$")
    if s then h = s:sub(1, 1):rep(2) .. s:sub(2, 2):rep(2) .. s:sub(3, 3):rep(2) end
  end
  h = h or NAMES[v]
  if not h then return nil end
  return { tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16) }
end
