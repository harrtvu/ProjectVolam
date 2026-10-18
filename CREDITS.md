# Credits & Licenses

## Art
* **Tiny Town** (1.1) by **Kenney** (www.kenney.nl): grass, flowers, mushrooms, dirt paths,
  trees, stone wall, gold coin. License: **CC0 1.0** (public domain).
  https://kenney.nl/assets/tiny-town
* **Tiny Dungeon** (1.0) by **Kenney** (www.kenney.nl): player characters, slime, rat, bat,
  spider, ghost, hooded archer, crawler, ogre, wizard (Lich King), tombstone, crypt floors/walls/
  pillars/graves/barrels/altar, swords, axe, hammer, staff, shields, potions.
  License: **CC0 1.0** (public domain). https://kenney.nl/assets/tiny-dungeon
* **Tiny Ski** (1.0) by **Kenney** (www.kenney.nl): snow ground, snowy pines, bare trees, rocks,
  snowman, yetis (Yeti / Yeti King). License: **CC0 1.0** (public domain).
  https://kenney.nl/assets/tiny-ski
* **Tiny Battle** (1.0) by **Kenney** (www.kenney.nl): water tile (also used, tinted, for forest
  ponds and frozen lakes). License: **CC0 1.0** (public domain). https://kenney.nl/assets/tiny-battle

The original sheets and Kenney's license files are in `assets/kenney/`.
`tools/build_assets.py` cuts them into the textures the game uses (`assets/tiles.png`,
`assets/chars/`, `assets/items/`, ...), scaled 2× with nearest-neighbour filtering.
Some sprites and tiles are **tinted / recoloured** by the script (dark forest tiles, icy walls,
Ice Ogre, Frost Bat, Broodmother, Lich King, a few item icons), and a sparkle/speckle variant of
the water and snow tiles is drawn procedurally. Those derived images are part of this project.

CC0 doesn't require credit, but thank you, Kenney!

## Engine
Made with **Godot Engine 4.2.1** (MIT license), https://godotengine.org/license

## Code
All GDScript in `scripts/` was written for Project Volam.

## Class art (Project Volam additions)

* Class sprites (`assets/classes/`) are Kenney "Tiny Dungeon" characters (CC0); the Water and Fire
  variants and one Wood variant are colour-tinted by `tools/build_assets.py`.
* Skill icons (`assets/skills/`) are Kenney Tiny Dungeon / Tiny Town / Tiny Ski / Tiny Battle tiles (CC0)
  on an element-coloured frame drawn by `tools/build_assets.py`.
* Element icons (`assets/elements/`) are drawn procedurally by `tools/build_assets.py` (no external art; CC0 like the rest).

## Portal effects (SpritePilot, CC0)

* `assets/fx/portal/portal-16px_strip8.png` - "Portal" (violet vortex, 8 frames, 10 fps, loops), the map portal gate in town / hideouts.
* `assets/fx/portal/teleport-16px_strip12.png` - "Teleport" (light beam, 12 frames, 15 fps, one-shot), played when someone steps through.

From SpritePilot "Free Pixel Art Spell & Projectile Effects", https://spritepilot.com/free-game-assets/magic -
released under **CC0 1.0** (any use, no credit required; credited anyway, thank you SpritePilot!).
Unmodified 16 px strips; drawn x3 with nearest filtering by `scripts/map_portal_visual.gd` (swappable: replace the PNG).
