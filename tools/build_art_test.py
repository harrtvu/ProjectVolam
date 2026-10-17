#!/usr/bin/env python3
"""Art style test (branch art-test): cuts the free packs into res://assets/art_test/.
Usage: python3 tools/build_art_test.py [/path/to/downloads]   (default /workspace/art_dl)
Expects: <dl>/na/Ninja Adventure - Asset Pack/ (pixel-boy, CC0), <dl>/pvfx/effects/ (nerijs PVFX Foundry, CC0),
<dl>/kenney/PNG/ (Kenney UI Pack RPG Expansion, CC0). Everything 16px is scaled 2x nearest-neighbour to the
game's 32px grid. See CREDITS.md."""
import json, os, sys
from PIL import Image, ImageEnhance

DL = sys.argv[1] if len(sys.argv) > 1 else "/workspace/art_dl"
NA = os.path.join(DL, "na", "Ninja Adventure - Asset Pack")
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "assets", "art_test")
os.makedirs(OUT, exist_ok=True)
X2 = lambda im: im.resize((im.width * 2, im.height * 2), Image.NEAREST)

# ---- player classes: 2 Ninja Adventure characters per element (variant picked by name hash, like the Kenney ones)
CLASSES = {"metal": ["NinjaGray", "Samurai"], "wood": ["NinjaGreen", "NinjaLeaf"], "water": ["NinjaWater", "NinjaBlue"],
           "fire": ["NinjaRed", "NinjaFire"], "earth": ["NinjaYellow", "Monk"]}
def actor_sheet(name):
    """4 cols (down, up, left, right) x 7 rows of 32px: idle, walk x4, attack, item(cast; same in all cols)."""
    d = os.path.join(NA, "Actor", "Character", name, "SeparateAnim")
    sheet = Image.new("RGBA", (64, 112))
    walk = Image.open(os.path.join(d, "Walk.png")).convert("RGBA")
    idle_p = os.path.join(d, "Idle.png")
    idle = Image.open(idle_p).convert("RGBA") if os.path.exists(idle_p) else walk.crop((0, 0, 64, 16))  # fallback: walk frame 1
    sheet.paste(idle.crop((0, 0, 64, 16)), (0, 0))
    sheet.paste(walk, (0, 16))
    sheet.paste(Image.open(os.path.join(d, "Attack.png")).convert("RGBA").crop((0, 0, 64, 16)), (0, 80))
    item = Image.open(os.path.join(d, "Item.png")).convert("RGBA")
    for c in range(4):
        sheet.paste(item, (c * 16, 96))
    return X2(sheet)
for cls, names in CLASSES.items():
    for i, n in enumerate(names):
        actor_sheet(n).save(os.path.join(OUT, "class_%s_%d.png" % (cls, i)))

# ---- Whisperwood monsters (4x4 walk sheets) + boss
MONSTERS = {"rat": "Mouse", "bat": "BlueBat", "spider": "SpiderRed"}
for k, n in MONSTERS.items():
    X2(Image.open(os.path.join(NA, "Actor", "Monster", n, "SpriteSheet.png")).convert("RGBA")).save(os.path.join(OUT, "mon_%s.png" % k))
# boss: TenguRed, 82px frames at 1x: rows idle(6) / walk(10) / attack(15), 15 cols
bd = os.path.join(NA, "Actor", "Boss", "TenguRed")
boss = Image.new("RGBA", (82 * 15, 82 * 3))
for r, f in enumerate(["Idle.png", "Walk.png", "Attack.png"]):
    boss.paste(Image.open(os.path.join(bd, f)).convert("RGBA"), (0, r * 82))
boss.save(os.path.join(OUT, "boss_broodmother.png"))

# ---- forest tiles: same atlas layout as assets/tiles.png, only the F_* cells replaced (collision unchanged)
atlas = Image.open(os.path.join(ROOT, "assets", "tiles.png")).convert("RGBA")
TS = os.path.join(NA, "Backgrounds", "Tilesets")
floor = Image.open(os.path.join(TS, "TilesetFloor.png")).convert("RGBA")
nature = Image.open(os.path.join(TS, "TilesetNature.png")).convert("RGBA")
water = Image.open(os.path.join(TS, "TilesetWater.png")).convert("RGBA")
cell16 = lambda im, x, y: im.crop((x * 16, y * 16, x * 16 + 16, y * 16 + 16))
cell32 = lambda im, x, y: im.crop((x * 16, y * 16, x * 16 + 32, y * 16 + 32))   # a 2x2 NA object at 1x (half pixel density!)
grass = X2(cell16(floor, 11, 12))
def on_grass(obj, big=False):
    base = grass.copy()
    base.alpha_composite(obj if big else X2(obj))
    return base
T = {19: grass, 20: X2(cell16(floor, 12, 12)), 21: on_grass(cell16(nature, 2, 11)),
     22: on_grass(cell32(nature, 2, 0), True), 23: on_grass(cell32(nature, 0, 0), True), 24: on_grass(cell32(nature, 16, 0), True),
     25: on_grass(cell32(nature, 4, 0), True), 26: X2(cell16(water, 1, 1)), 27: on_grass(cell16(nature, 4, 8))}
for i, (x, y) in enumerate([(11, 7), (12, 7), (13, 7), (11, 8), (12, 8), (13, 8), (11, 9), (12, 9), (13, 9)]):
    T[28 + i] = X2(cell16(floor, x, y))
T[49] = X2(cell16(floor, 12, 8))   # C_SAND (forest camp ground) -> Ninja Adventure dirt
for idx, im in T.items():
    atlas.paste(im, (idx * 32, 0))
atlas.save(os.path.join(OUT, "tiles.png"))

# ---- UI: Kenney RPG Expansion bars (9-slice in Godot) + Ninja Adventure wood panel
K = os.path.join(DL, "kenney", "PNG")
for col, name in [("Back", "back"), ("Red", "red"), ("Blue", "blue"), ("Yellow", "yellow")]:
    l = Image.open(os.path.join(K, "bar%s_horizontalLeft.png" % col)).convert("RGBA")
    mid_name = "bar%s_horizontalMid.png" % col
    if not os.path.exists(os.path.join(K, mid_name)):
        mid_name = "barBlue_horizontalBlue.png"
    m = Image.open(os.path.join(K, mid_name)).convert("RGBA")
    r = Image.open(os.path.join(K, "bar%s_horizontalRight.png" % col)).convert("RGBA")
    bar = Image.new("RGBA", (l.width + m.width + r.width, 18))
    bar.paste(l, (0, 0)); bar.paste(m, (l.width, 0)); bar.paste(r, (l.width + m.width, 0))
    bar.save(os.path.join(OUT, "ui_bar_%s.png" % name))
p = X2(Image.open(os.path.join(NA, "Ui", "Theme", "Theme Wood", "nine_path_panel.png")).convert("RGBA"))
ImageEnhance.Brightness(p).enhance(0.55).save(os.path.join(OUT, "ui_panel.png"))

# ---- elemental skill VFX (PVFX Foundry grid sheets: 5 cols x N rows of 96px, 20 fps)
VFX = {"metal": "electric-impact", "wood": "leaf-gust", "water": "frost-nova", "fire": "warm-explosion", "earth": "earth-rupture"}
meta = {}
for el, e in VFX.items():
    d = os.path.join(DL, "pvfx", "effects", e, "grid")
    Image.open(os.path.join(d, "sprite-sheet.png")).save(os.path.join(OUT, "vfx_%s.png" % el))
    m = json.load(open(os.path.join(d, "manifest.json")))
    meta[el] = {"frames": len(m["frames"]), "pivot": m["pivot"], "effect": e}
json.dump(meta, open(os.path.join(OUT, "vfx.json"), "w"), indent=1)
print("art_test assets written to", OUT)
