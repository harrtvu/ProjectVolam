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

## Art style test (branch `art-test` only, enabled with `--art-test`)
Downloaded 17 Oct 2026 from the official pages below (free downloads, nothing bought, no sign-up).
`tools/build_art_test.py` cuts them into `assets/art_test/` (16 px art scaled 2x nearest-neighbour; the
TenguRed boss and Ninja Adventure 2x2 trees are kept at 1x; the wood panel is darkened).

* **Ninja Adventure - Asset Pack** by **pixel-boy** (upload of 29 Mar 2026).
  https://pixel-boy.itch.io/ninja-adventure-asset-pack. License: **CC0 1.0** (LICENSE.txt in the pack).
  Used: player characters NinjaGray, Samurai, NinjaGreen, NinjaLeaf, NinjaWater, NinjaBlue, NinjaRed,
  NinjaFire, NinjaYellow, Monk (Idle / Walk / Attack / Item); monsters Mouse, BlueBat, SpiderRed; boss TenguRed;
  TilesetFloor, TilesetNature and TilesetWater cells for Whisperwood ground, paths, trees, stumps, water;
  UI Theme Wood `nine_path_panel`.
  AI disclosure: the itch.io page says **"No generative AI was used"**.
* **UI Pack: RPG Expansion** by **Kenney** (www.kenney.nl). https://kenney.nl/assets/ui-pack-rpg-expansion.
  License: **CC0 1.0** (license.txt in the pack). Used: `barBack/barRed/barBlue/barYellow_horizontal*` (HP, mana, XP bars).
  AI disclosure: **not stated** on the page.
* **PVFX Foundry** (v0.10.0) by **nerijs**. https://nerijs.itch.io/pvfx-foundry.
  License: **CC0 1.0** for the sprite sheets, manifests and docs in the release (see the pack's LICENSE.txt; it does
  not cover the Pixel VFX Studio software or names/marks). Used: electric-impact (Metal), leaf-gust (Wood),
  frost-nova (Water), warm-explosion (Fire), earth-rupture (Earth).
  AI disclosure: the author's itch.io page marks it **"AI Assisted: Code, Text"**, i.e. AI helped with the
  pack's code and text only, not the effects; the sheets are rendered by the creator's own VFX tool.

Not used in the test (no credit needed): **Medieval Chinese Buildings tileset, VectoRaith, free demo**
(https://vectoraith.itch.io/medieval-chinese-buildings-tileset-pack; free and commercial projects OK, but **no
redistribution**; page says "No generative AI was used"). It was downloaded locally only and is not committed,
because this repository is public and committing the tiles would redistribute them.

No CC-BY assets are used, so none of the attribution-log credit lines (Martial Arts Fighter / Rancic,
Samurai Nights / Majadroid, Taiko drums / jobro, JC Sounds Fantasy SFX) are needed yet.
AI disclosure of the existing Kenney packs above (Tiny Town / Dungeon / Ski / Battle): **not stated**.

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
