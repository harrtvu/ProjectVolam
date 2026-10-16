#!/usr/bin/env python3
"""Dungeon Ticket icons (a rolled map with an element seal, one per theme), the
Cartographer's Chisel, and the Ticket Merchant sprite (Kenney Tiny Dungeon tile 84, CC0)."""
import os
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "items")
OL = (34, 28, 36, 255)
EL = {"metal": (225, 205, 120), "wood": (90, 190, 80), "water": (80, 150, 235), "fire": (235, 95, 50), "earth": (170, 120, 70)}

def outline(img):
    out = img.copy(); px = img.load(); po = out.load()
    for y in range(16):
        for x in range(16):
            if px[x, y][3] == 0:
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < 16 and 0 <= ny < 16 and px[nx, ny][3] > 0:
                        po[x, y] = OL
                        break
    return out

def save(name, img):
    outline(img).resize((32, 32), Image.NEAREST).save(os.path.join(OUT, name + ".png"))

def ticket(seal):
    im = Image.new("RGBA", (16, 16), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    paper, dark = (236, 214, 160, 255), (190, 160, 105, 255)
    d.rectangle((3, 3, 12, 12), fill=paper)
    d.rectangle((2, 2, 13, 3), fill=dark); d.rectangle((2, 12, 13, 13), fill=dark)   # rolled ends
    for x, y in ((5, 6), (6, 7), (7, 7), (8, 8), (9, 8), (10, 9)):                   # a dotted route
        im.putpixel((x, y), (120, 80, 50, 255))
    im.putpixel((5, 5), (150, 60, 50, 255))
    c = seal + (255,)
    d.ellipse((8, 9, 12, 13), fill=c)
    im.putpixel((10, 10), (255, 255, 255, 200))
    return im

def chisel():
    im = Image.new("RGBA", (16, 16), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.line((4, 12, 10, 6), fill=(140, 95, 60, 255), width=2)          # handle
    d.polygon([(10, 4), (13, 3), (12, 6), (10, 7)], fill=(200, 210, 225, 255))   # blade
    im.putpixel((12, 4), (255, 255, 255, 255))
    return im

for el, col in EL.items():
    save("ticket_" + el, ticket(col))
save("orb_chisel", chisel())
TD = Image.open(os.path.join(ROOT, "assets", "kenney", "tiny_dungeon_packed.png")).convert("RGBA")
i = 84
TD.crop(((i % 12) * 16, (i // 12) * 16, (i % 12) * 16 + 16, (i // 12) * 16 + 16)).resize((32, 32), Image.NEAREST).save(os.path.join(ROOT, "assets", "merchant.png"))
print("dungeon icons written")
