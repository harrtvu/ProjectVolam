#!/usr/bin/env python3
"""Builds Project Volam's game textures from the Kenney CC0 sheets in assets/kenney/.

Outputs (16px source art upscaled 2x with nearest-neighbour -> 32px):
  assets/tiles.png            tile atlas (one row)
  scripts/tiles.gd            GENERATED constants for every tile (+ which ones are solid)
  assets/chars/char_N.png     player sprites
  assets/monsters/<id>.png    monster sprites
  assets/items/<id>.png       item icons
  assets/tombstone.png
Requires Python 3 + Pillow. Only needed if you want to change the art.
"""
import os, random
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
A = os.path.join(ROOT, "assets")
K = os.path.join(A, "kenney")
def sheet(n): return Image.open(os.path.join(K, n)).convert("RGBA")
TD, TT = sheet("tiny_dungeon_packed.png"), sheet("tiny_town_packed.png")
SKI, BAT = sheet("tiny_ski_packed.png"), sheet("tiny_battle_packed.png")
COLS = {id(TD): 12, id(TT): 12, id(SKI): 12, id(BAT): 18}
S = 2

def tile(sh, i):
    c = COLS[id(sh)]
    x, y = (i % c) * 16, (i // c) * 16
    return sh.crop((x, y, x + 16, y + 16))

def over(bg, fg):
    out = bg.copy(); out.alpha_composite(fg); return out

def tint(img, mul):
    r, g, b, a = img.split()
    r = r.point(lambda v: min(255, int(v * mul[0])))
    g = g.point(lambda v: min(255, int(v * mul[1])))
    b = b.point(lambda v: min(255, int(v * mul[2])))
    return Image.merge("RGBA", (r, g, b, a))

def swap_rb(img):
    r, g, b, a = img.split(); return Image.merge("RGBA", (b, g, r, a))

def dots(img, seed, color, n=5):
    r = random.Random(seed); img = img.copy(); px = img.load()
    for _ in range(n):
        px[r.randrange(1, 15), r.randrange(1, 15)] = color
    return img

def up(img): return img.resize((img.width * S, img.height * S), Image.NEAREST)

def sparkle(img, seed, color):
    r = random.Random(seed); img = img.copy(); px = img.load()
    for row in (3, 8, 13):
        x = r.randrange(0, 10)
        for dx in range(r.randrange(3, 6)):
            px[(x + dx) % 16, row] = color
    return img

FOREST = (0.62, 0.80, 0.70)
ICE = (0.80, 0.92, 1.15)
grass = tile(TT, 0)
fgrass = tint(grass, FOREST)
water = tile(BAT, 37)
snow = tile(SKI, 0)

# (CONSTANT_NAME, image, solid)
TILES = [
    # --- Meadow
    ("GRASS", grass, False),
    ("GRASS2", tile(TT, 1), False),
    ("FLOWER", tile(TT, 2), False),
    ("MUSHROOM", over(grass, tile(TT, 29)), False),
    ("FLOOR", tile(TD, 49), False),
    ("WALL", tile(TT, 126), True),
    ("WATER", water, True),
    ("WATER2", sparkle(water, 2, (170, 215, 250, 255)), True),
    ("TREE", over(grass, tile(TT, 28)), True),
    ("TREE2", over(grass, tile(TT, 16)), True),
]
for n, i in zip(["TL", "T", "TR", "L", "C", "R", "BL", "B", "BR"], (12, 13, 14, 24, 25, 26, 36, 37, 38)):
    TILES.append(("PATH_" + n, tile(TT, i), False))
TILES += [
    # --- Dark Forest (tinted darker / colder)
    ("F_GRASS", fgrass, False),
    ("F_GRASS2", tint(tile(TT, 1), FOREST), False),
    ("F_MUSHROOM", tint(over(grass, tile(TT, 29)), FOREST), False),
    ("F_PINE", tint(over(grass, tile(TT, 4)), FOREST), True),
    ("F_TREE", tint(over(grass, tile(TT, 16)), FOREST), True),
    ("F_OAK", tint(over(grass, tile(TT, 28)), FOREST), True),
    ("F_DEAD", tint(over(grass, tile(TT, 27)), FOREST), True),
    ("F_WATER", tint(water, (0.6, 0.75, 0.8)), True),
    ("F_STUMP", tint(over(grass, tile(TT, 17)), FOREST), False),
]
for n, i in zip(["TL", "T", "TR", "L", "C", "R", "BL", "B", "BR"], (12, 13, 14, 24, 25, 26, 36, 37, 38)):
    TILES.append(("F_PATH_" + n, tint(tile(TT, i), FOREST), False))
TILES += [
    # --- Bone Crypt (Tiny Dungeon)
    ("C_FLOOR", tile(TD, 0), False),
    ("C_FLOOR2", tile(TD, 12), False),
    ("C_RUBBLE", tile(TD, 24), False),
    ("C_WALL", tile(TD, 40), True),
    ("C_WALL_GRATE", tile(TD, 28), True),
    ("C_WALL_BANNER", tile(TD, 29), True),
    ("C_WALL_SKULL", tile(TD, 19), True),
    ("C_PILLAR", over(tile(TD, 0), tile(TD, 58)), True),
    ("C_TOMB", over(tile(TD, 0), tile(TD, 64)), True),
    ("C_GRAVE", over(tile(TD, 0), tile(TD, 65)), True),
    ("C_BARREL", over(tile(TD, 0), tile(TD, 82)), True),
    ("C_ALTAR", over(tile(TD, 0), tile(TD, 32)), True),
    ("C_SAND", tile(TD, 48), False),
    # --- Frostpeak (Tiny Ski + tinted ruins)
    ("S_SNOW", snow, False),
    ("S_SNOW2", dots(snow, 5, (196, 214, 238, 255)), False),
    ("S_SNOW3", dots(tint(snow, (0.95, 0.96, 0.99)), 9, (196, 210, 232, 255), 3), False),
    ("S_PINE", over(snow, tile(SKI, 6)), True),
    ("S_PINE2", over(snow, tile(SKI, 18)), True),
    ("S_DEAD", over(snow, tile(SKI, 7)), True),
    ("S_ROCK", over(snow, tile(SKI, 81)), True),
    ("S_SNOWMAN", over(snow, tile(SKI, 69)), True),
    ("S_ICE", tint(water, (1.25, 1.25, 1.1)), False),
    ("S_WALL", tint(tile(TT, 126), ICE), True),
    ("S_FLOOR", tint(tile(TT, 109), ICE), False),
]

atlas = Image.new("RGBA", (16 * len(TILES), 16))
for n, (_, img, _) in enumerate(TILES):
    atlas.paste(img, (n * 16, 0))
up(atlas).save(os.path.join(A, "tiles.png"))

with open(os.path.join(ROOT, "scripts", "tiles.gd"), "w") as f:
    f.write("class_name Tiles\n## GENERATED by tools/build_assets.py - do not edit by hand.\n")
    f.write("## Atlas coordinates of every tile in res://assets/tiles.png.\n\n")
    for n, (name, _, _) in enumerate(TILES):
        f.write("const %s := Vector2i(%d, 0)\n" % (name, n))
    f.write("\nconst COUNT := %d\n" % len(TILES))
    f.write("const SOLID := [%s]\n" % ", ".join(name for name, _, s in TILES if s))
    f.write("const TREES := [TREE, TREE2, F_PINE, F_TREE, F_OAK, F_DEAD, S_PINE, S_PINE2, S_DEAD]\n")

os.makedirs(os.path.join(A, "chars"), exist_ok=True)
for n, i in enumerate([85, 87, 88, 96, 97, 98, 99, 100, 112, 86]):
    up(tile(TD, i)).save(os.path.join(A, "chars", "char_%d.png" % n))
up(tile(TD, 64)).save(os.path.join(A, "tombstone.png"))
for old in ("slime.png",):
    p = os.path.join(A, old)
    if os.path.exists(p): os.remove(p)

os.makedirs(os.path.join(A, "monsters"), exist_ok=True)
monsters = {
    "slime": tile(TD, 108), "rat": tile(TD, 123), "bat": tile(TD, 120),
    "spider": tile(TD, 122), "archer": tile(TD, 111), "ghost": tile(TD, 121),
    "crawler": tile(TD, 110), "yeti": tile(SKI, 78), "ice_ogre": tint(tile(TD, 109), ICE),
    "broodmother": tint(tile(TD, 122), (1.1, 0.7, 1.2)), "lich": tint(tile(TD, 84), (0.8, 1.1, 0.85)),
    "yeti_king": tile(SKI, 80),
}
for name, img in monsters.items():
    up(img).save(os.path.join(A, "monsters", name + ".png"))

os.makedirs(os.path.join(A, "items"), exist_ok=True)
BONE = (1.25, 1.15, 0.85)
items = {
    "gold": tile(TT, 93), "slime_gel": tile(TD, 114), "health_potion": tile(TD, 115),
    "greater_potion": tile(TD, 127),
    "iron_sword": tile(TD, 104), "steel_sword": tile(TD, 106), "war_axe": tile(TD, 118),
    "venom_dagger": tint(tile(TD, 103), (0.6, 1.3, 0.6)), "great_hammer": tile(TD, 117),
    "lich_staff": tile(TD, 130), "frostbrand": swap_rb(tile(TD, 107)),
    "wooden_shield": tile(TD, 101), "iron_shield": tile(TD, 102),
    "bone_shield": tint(tile(TD, 102), BONE), "frost_aegis": tint(tile(TD, 102), (0.75, 1.0, 1.4)),
}
for name, img in items.items():
    up(img).save(os.path.join(A, "items", name + ".png"))
# ---------------------------------------------------------------- classes (Wu Xing)
from PIL import ImageDraw
ELEM_RGB = {"metal": (232, 214, 140), "wood": (86, 200, 90), "water": (80, 160, 255),
            "fire": (255, 100, 50), "earth": (200, 150, 80)}
os.makedirs(os.path.join(A, "classes"), exist_ok=True)
class_sprites = {
    "metal": [tile(TD, 96), tile(TD, 97)],
    "wood": [tile(TD, 112), tint(tile(TD, 85), (0.8, 1.15, 0.8))],
    "water": [tint(tile(TD, 99), (0.75, 0.9, 1.3)), tint(tile(TD, 98), (0.75, 0.9, 1.3))],
    "fire": [tint(tile(TD, 84), (1.35, 0.7, 0.6)), tint(tile(TD, 88), (1.3, 0.8, 0.7))],
    "earth": [tile(TD, 87), tile(TD, 100)],
}
for cls, imgs in class_sprites.items():
    for n, img in enumerate(imgs):
        up(img).save(os.path.join(A, "classes", "%s_%d.png" % (cls, n)))

def elem_icon(e, size=32):
    im = Image.new("RGBA", (size, size), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    c = ELEM_RGB[e]; dark = tuple(int(v * 0.35) for v in c) + (255,)
    d.ellipse((1, 1, size - 2, size - 2), fill=dark, outline=c + (255,), width=2)
    k = size / 32.0
    P = lambda pts: [(x * k, y * k) for x, y in pts]
    if e == "metal":      # ingot / blade diamond
        d.polygon(P([(16, 6), (25, 16), (16, 26), (7, 16)]), fill=c + (255,))
        d.polygon(P([(16, 9), (21, 16), (16, 23)]), fill=(255, 250, 220, 255))
    elif e == "wood":     # leaf
        d.ellipse(P([(9, 7), (23, 25)]), fill=c + (255,))
        d.line(P([(16, 8), (16, 27)]), fill=(30, 90, 30, 255), width=2)
    elif e == "water":    # drop
        d.polygon(P([(16, 5), (23, 17), (9, 17)]), fill=c + (255,))
        d.ellipse(P([(9, 12), (23, 26)]), fill=c + (255,))
        d.ellipse(P([(12, 16), (15, 19)]), fill=(220, 240, 255, 255))
    elif e == "fire":     # flame
        d.polygon(P([(16, 4), (24, 17), (22, 25), (10, 25), (8, 17), (12, 12), (13, 17)]), fill=c + (255,))
        d.polygon(P([(16, 13), (20, 21), (16, 25), (12, 21)]), fill=(255, 220, 90, 255))
    elif e == "earth":    # mountain
        d.polygon(P([(5, 24), (13, 10), (18, 17), (21, 13), (27, 24)]), fill=c + (255,))
        d.polygon(P([(13, 10), (15, 14), (11, 14)]), fill=(255, 245, 220, 255))
    return im

os.makedirs(os.path.join(A, "elements"), exist_ok=True)
for e in ELEM_RGB:
    elem_icon(e, 32).save(os.path.join(A, "elements", e + ".png"))
    elem_icon(e, 64).save(os.path.join(A, "elements", e + "_big.png"))

# skill icons: element-coloured frame + a Kenney glyph
SKILL_GLYPHS = {
    "whirl": tile(TD, 104), "pierce": tile(TD, 103), "focus": tile(TD, 102), "cuts": tile(TD, 106),
    "thorn": tile(TD, 131), "regrowth": tile(TD, 114), "roots": over(Image.new("RGBA", (16, 16)), tile(TT, 29)), "bloom": tile(TD, 113),
    "ice_shard": tile(TD, 130), "rain": tile(TD, 116), "nova": tile(SKI, 6), "wave": tile(BAT, 37),
    "fireball": tile(TD, 107), "burst": tile(TD, 115), "meteor": tile(TD, 12), "inferno": tile(TD, 29),
    "slam": tile(TD, 117), "stoneskin": tile(TD, 101), "taunt": tile(TD, 19), "quake": tile(TD, 24),
}
SKILL_ELEM = {}
for e, ks in {"metal": ["whirl", "pierce", "focus", "cuts"], "wood": ["thorn", "regrowth", "roots", "bloom"],
              "water": ["ice_shard", "rain", "nova", "wave"], "fire": ["fireball", "burst", "meteor", "inferno"],
              "earth": ["slam", "stoneskin", "taunt", "quake"]}.items():
    for k in ks: SKILL_ELEM[k] = e
os.makedirs(os.path.join(A, "skills"), exist_ok=True)
for k, g in SKILL_GLYPHS.items():
    c = ELEM_RGB[SKILL_ELEM[k]]
    im = Image.new("RGBA", (24, 24), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.rounded_rectangle((0, 0, 23, 23), 4, fill=tuple(int(v * 0.3) for v in c) + (255,), outline=c + (255,), width=2)
    im.alpha_composite(g, (4, 4))
    im.resize((48, 48), Image.NEAREST).save(os.path.join(A, "skills", k + ".png"))

items_extra = {"apprentice_staff": tile(TD, 129), "ember_staff": tint(tile(TD, 129), (1.4, 0.6, 0.4))}
for name, img in items_extra.items():
    up(img).save(os.path.join(A, "items", name + ".png"))
print("class/element/skill art built")
print("assets built: %d tiles" % len(TILES))
