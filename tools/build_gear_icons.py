#!/usr/bin/env python3
"""Pixel-art icons for the gear system (armour pieces, jewellery, currency), drawn in code
(16x16, 2x nearest-neighbour upscale like the Kenney art) -> assets/items/<id>.png.
Also the blacksmith anvil / stash chest props from the Kenney Tiny Dungeon sheet (CC0)."""
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "items")
os.makedirs(OUT, exist_ok=True)
OL = (34, 28, 36, 255)

def canvas():
    return Image.new("RGBA", (16, 16), (0, 0, 0, 0))

def outline(img):
    """1px dark outline around opaque pixels."""
    out = img.copy()
    px = img.load(); po = out.load()
    for y in range(16):
        for x in range(16):
            if px[x, y][3] == 0:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < 16 and 0 <= ny < 16 and px[nx, ny][3] > 0:
                        po[x, y] = OL
                        break
    return out

def shade(c, f):
    return tuple(max(0, min(255, int(v * f))) for v in c[:3]) + (255,)

def save(name, img):
    outline(img).resize((32, 32), Image.NEAREST).save(os.path.join(OUT, name + ".png"))

def rect(d, box, c):
    d.rectangle(box, fill=c)

def helmet(c, horns=False, plume=None):
    im = canvas(); d = ImageDraw.Draw(im)
    d.pieslice((3, 3, 12, 14), 180, 360, fill=c)
    rect(d, (3, 8, 12, 11), c)
    rect(d, (5, 9, 10, 10), shade(c, 0.45))      # visor slit
    rect(d, (7, 3, 8, 8), shade(c, 1.25))        # ridge
    if horns:
        d.line((2, 7, 1, 3), fill=(235, 225, 200, 255), width=1); d.line((13, 7, 14, 3), fill=(235, 225, 200, 255), width=1)
    if plume:
        rect(d, (7, 1, 8, 3), plume)
    return im

def body(c, trim):
    im = canvas(); d = ImageDraw.Draw(im)
    d.polygon([(3, 3), (6, 2), (9, 2), (12, 3), (13, 7), (11, 7), (11, 14), (4, 14), (4, 7), (2, 7)], fill=c)
    rect(d, (7, 3, 8, 13), shade(c, 0.8))
    rect(d, (4, 10, 11, 10), trim)
    return im

def gloves(c):
    im = canvas(); d = ImageDraw.Draw(im)
    for ox in (1, 8):
        rect(d, (ox + 1, 6, ox + 5, 12), c)
        for k in range(3):
            rect(d, (ox + 1 + k * 2, 3, ox + 1 + k * 2, 6), c)
        rect(d, (ox, 12, ox + 6, 14), shade(c, 0.7))
    return im

def boots(c):
    im = canvas(); d = ImageDraw.Draw(im)
    for ox in (1, 8):
        rect(d, (ox + 1, 3, ox + 4, 11), c)
        rect(d, (ox + 1, 11, ox + 6, 13), c)
        rect(d, (ox + 1, 13, ox + 6, 13), shade(c, 0.55))
        rect(d, (ox + 1, 4, ox + 4, 4), shade(c, 1.3))
    return im

def belt(c, buckle):
    im = canvas(); d = ImageDraw.Draw(im)
    rect(d, (1, 6, 14, 9), c)
    rect(d, (1, 9, 14, 9), shade(c, 0.6))
    rect(d, (6, 5, 9, 10), buckle)
    rect(d, (7, 7, 8, 8), shade(c, 0.6))
    return im

def amulet(chain, gem):
    im = canvas(); d = ImageDraw.Draw(im)
    d.arc((3, 0, 12, 10), 20, 160, fill=chain, width=1)
    d.line((4, 3, 7, 9), fill=chain); d.line((11, 3, 8, 9), fill=chain)
    d.ellipse((5, 8, 10, 14), fill=gem)
    rect(d, (6, 9, 7, 10), shade(gem, 1.6))
    return im

def ring(band, gem):
    im = canvas(); d = ImageDraw.Draw(im)
    d.ellipse((3, 5, 12, 14), outline=band, width=2)
    d.ellipse((6, 2, 9, 6), fill=gem)
    rect(d, (6, 3, 6, 3), shade(gem, 1.7))
    return im

def orb(c, mark=None):
    im = canvas(); d = ImageDraw.Draw(im)
    d.ellipse((2, 2, 13, 13), fill=c)
    d.ellipse((4, 4, 8, 8), fill=shade(c, 1.45))
    d.ellipse((9, 9, 12, 12), fill=shade(c, 0.7))
    if mark:
        rect(d, (7, 6, 8, 9), mark); rect(d, (6, 7, 9, 8), mark)
    return im

def stone(c):
    im = canvas(); d = ImageDraw.Draw(im)
    d.polygon([(8, 1), (13, 6), (11, 14), (5, 14), (3, 6)], fill=c)
    d.polygon([(8, 1), (8, 14), (5, 14), (3, 6)], fill=shade(c, 1.3))
    d.line((3, 6, 13, 6), fill=shade(c, 0.7))
    return im

IRON, STEEL, BRONZE, BONE = (150, 160, 175), (190, 200, 215), (190, 130, 70), (225, 215, 180)
LEATHER, CLOTH, GOLD = (140, 90, 50), (90, 110, 170), (235, 195, 70)
JADE, RUBY, SAPPH, AMBER = (70, 200, 120), (220, 50, 60), (70, 120, 240), (240, 160, 40)

save("leather_cap", helmet(LEATHER))
save("iron_helm", helmet(IRON, plume=RUBY))
save("horned_helm", helmet(STEEL, horns=True))
save("cloth_robe", body(CLOTH, GOLD))
save("leather_vest", body(LEATHER, BRONZE))
save("chain_mail", body(IRON, STEEL))
save("plate_armour", body(STEEL, GOLD))
save("cloth_wraps", gloves((200, 190, 160)))
save("iron_gauntlets", gloves(IRON))
save("sandals", boots((170, 120, 70)))
save("leather_boots", boots(LEATHER))
save("iron_greaves", boots(IRON))
save("rope_belt", belt((180, 150, 100), BRONZE))
save("leather_belt", belt(LEATHER, GOLD))
save("jade_amulet", amulet(GOLD, JADE))
save("coral_amulet", amulet(STEEL, RUBY))
save("copper_ring", ring(BRONZE, AMBER))
save("jade_ring", ring(GOLD, JADE))
save("silver_ring", ring(STEEL, SAPPH))
# currency (PoE-style orbs + Vo Lam enhancement stone)
save("orb_transmute", orb((90, 140, 230)))
save("orb_alteration", orb((120, 200, 230), (255, 255, 255, 255)))
save("orb_regal", orb((235, 195, 70), (120, 40, 140, 255)))
save("orb_chaos", orb((200, 70, 200), (40, 255, 120, 255)))
save("orb_exalt", orb((250, 240, 200), (230, 170, 40, 255)))
save("orb_scour", orb((160, 160, 160), (60, 60, 60, 255)))
save("enhance_stone", stone((110, 220, 255)))

# blacksmith station props (Kenney Tiny Dungeon, CC0): anvil 74, chest 89
TD = Image.open(os.path.join(ROOT, "assets", "kenney", "tiny_dungeon_packed.png")).convert("RGBA")
def td(i):
    x, y = (i % 12) * 16, (i // 12) * 16
    return TD.crop((x, y, x + 16, y + 16)).resize((32, 32), Image.NEAREST)
td(74).save(os.path.join(ROOT, "assets", "anvil.png"))
td(89).save(os.path.join(ROOT, "assets", "chest.png"))
td(86).save(os.path.join(ROOT, "assets", "blacksmith.png"))
print("gear icons written")
