"""Imports OSM2World's default style (https://github.com/tordanik/OSM2World-default-style) into OSM2World2Lua:
materials (texture, size in metres, colour) as o2w/materials.lua and the colour textures, scaled down for games,
into textures/.

usage: python3 tools/import_style.py <OSM2World-default-style dir> [texture size, default 512]

The style's configuration and its own textures are public domain (CC0); most textures come from ambientCG (CC0)
and the OSM Wiki Texture Library (public domain). See textures/SOURCES.md, written by this tool.
"""
import os, re, sys
from PIL import Image

STYLE = sys.argv[1]
SIZE = int(sys.argv[2]) if len(sys.argv) > 2 else 512
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT_TEX = os.path.join(ROOT, "textures")

# the materials OSM2World2Lua uses (buildings, roads, ground)
WANT = """TERRAIN_DEFAULT ASPHALT BRICK BUILDING_DEFAULT BUILDING_WINDOWS CONCRETE EARTH GLASS_WALL GRASS GRASS_PAVER
GRAVEL PAVING_STONE ROOF_DEFAULT SAND SETT SLATE STONE WATER WOOD_WALL WOOD ROCK SCRUB SNOW CORRUGATED_STEEL
RAIL_BALLAST TILES COPPER_ROOF GLASS_ROOF THATCH_ROOF UNHEWN_COBBLESTONE HEDGE SANDSTONE PEBBLESTONE SCREE
ICE WOODCHIPS MARBLE ADOBE STEEL""".split()

props = {}
for line in open(os.path.join(STYLE, "standard.properties"), encoding="utf-8"):
    line = line.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    k, v = line.split("=", 1)
    props[k.strip()] = v.strip()

def num(v, d=None):
    try:
        return float(v)
    except (TypeError, ValueError):
        return d

def colour(v):
    if not v:
        return None
    m = re.match(r"#?([0-9a-fA-F]{6})", v)
    if not m:
        return None
    h = m.group(1)
    return [int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)]

os.makedirs(OUT_TEX, exist_ok=True)
lua = ["-- Materials from OSM2World's default style (public domain / CC0), imported by tools/import_style.py.",
       "-- tex: file in textures/; w, h: metres one copy of the texture covers; colour: tint (multiplied with the",
       "-- texture) when the material is colourable or has a set colour; alpha: the texture has see-through parts;",
       "-- per_w, per_h: metres per repeated item (windows: one window per per_w along a wall and per level).",
       "return {"]
sources = []
for name in WANT:
    p = "material_" + name + "_"
    d = props.get(p + "texture0_dir")
    f = props.get(p + "texture0_file")
    src = None
    if d:
        d = os.path.join(STYLE, d)
        cands = [x for x in os.listdir(d) if re.search(r"_?Colou?r\.(png|jpe?g)$", x, re.I)] if os.path.isdir(d) else []
        if cands:
            src = os.path.join(d, sorted(cands)[0])
    elif f:
        src = os.path.join(STYLE, f)
    if not src or not os.path.exists(src):
        print("skipped (no texture):", name)
        continue
    im = Image.open(src)
    alpha = im.mode in ("RGBA", "LA") or "transparency" in im.info
    im = im.convert("RGBA" if alpha else "RGB")
    if alpha:
        a = im.getchannel("A")
        hist = a.histogram()
        alpha = sum(hist[:128]) > 0.01 * im.width * im.height      # a few stray pixels do not count
        if not alpha:
            im = im.convert("RGB")
    im = im.resize((SIZE, SIZE), Image.LANCZOS)
    fname = name.lower() + ".png"
    im.save(os.path.join(OUT_TEX, fname), optimize=True)
    w = num(props.get(p + "texture0_width"), 1)
    h = num(props.get(p + "texture0_height"), 1)
    col = colour(props.get(p + "color"))
    colourable = props.get(p + "texture0_colorable") == "true"
    fields = ['tex = "%s"' % fname, "w = %g" % w, "h = %g" % h]
    if col:
        fields.append("colour = { %d, %d, %d }" % tuple(col))
    if colourable:
        fields.append("colourable = true")
    if alpha:
        fields.append("alpha = true")
    pw, ph = num(props.get(p + "texture0_widthPerEntity")), num(props.get(p + "texture0_heightPerEntity"))
    if pw:
        fields.append("per_w = %g" % pw)
    if ph:
        fields.append("per_h = %g" % ph)
    if props.get(p + "texture0_coord_function") == "GLOBAL_X_Z":
        fields.append("ground = true")
    lua.append("  %s = { %s }," % (name, ", ".join(fields)))
    sources.append("| %s | `%s` | %s |" % (fname, os.path.relpath(src, STYLE), "ambientCG (CC0)" if "cc0textures" in src
                   else ("OSM2World default style (CC0)" if "/custom/" in src else "OSM Wiki Texture Library (public domain)")))
lua.append("}")
os.makedirs(os.path.join(ROOT, "o2w"), exist_ok=True)
open(os.path.join(ROOT, "o2w", "materials.lua"), "w").write("\n".join(lua) + "\n")
open(os.path.join(OUT_TEX, "SOURCES.md"), "w").write(
    "# Texture sources\n\nScaled-down colour maps from [OSM2World-default-style](https://github.com/tordanik/OSM2World-default-style). "
    "Its configuration and own textures are public domain (CC0); most textures come from [ambientCG](https://ambientcg.com/) (CC0) "
    "and the [OSM Wiki Texture Library](https://wiki.openstreetmap.org/wiki/Texture_Library) (public domain).\n\n"
    "| File | Original | Source |\n|---|---|---|\n" + "\n".join(sources) + "\n")
print(len(sources), "materials imported")
