# Art style test (branch `art-test`, never merged)

Zone reskinned: **Whisperwood Forest** (it has the boss lair; Sunny Meadow has no boss).
Run with `--art-test` on a client (or `VOLAM_ART_TEST=1`); `--art-test-nomood` keeps the reskin but drops the dark pass.
Without the flag the game is unchanged. The server never needs the flag (tile layout and collision are identical).

* Assets: `python3 tools/build_art_test.py /workspace/art_dl` -> `assets/art_test/` (see CREDITS.md).
* Captures: `xvfb-run -a -s "-screen 0 1280x720x24" tools/art_test_screenshots.sh [views|combat|all]`
  (`VIEWS="boss"` limits the views; `SEQ`, `INTERVAL`, `LV` tune the combat run).
* Smoke tests: `tools/art_test_smoke.sh` (phases 1, 3 and 11 of run_local_test.sh plus their checks, then phase 11 with `--art-test` clients).

## What's reskinned (only with --art-test)
* Players: Ninja Adventure characters, 2 per element (Metal NinjaGray/Samurai, Wood NinjaGreen/NinjaLeaf,
  Water NinjaWater/NinjaBlue, Fire NinjaRed/NinjaFire, Earth NinjaYellow/Monk). 4-direction idle, 4-frame walk,
  attack pose on swings, `Item` pose as a temporary cast (shown to the caster's own client only).
* Monsters: Dire Rat -> Mouse, Cave Bat -> BlueBat, Wood Spider -> SpiderRed (4-dir walk). Boss Broodmother -> TenguRed
  (82 px idle / walk / attack frames; attack row plays while it telegraphs).
* Whisperwood tiles (F_* cells of the same atlas): grass x2, clover, 4 tree types, stump, water, 3x3 dirt path; forest camp ground.
* UI: HP / mana / XP bars from Kenney UI Pack RPG Expansion, stats panel from Ninja Adventure's wood theme (darkened).
* VFX: one PVFX Foundry effect per element over the existing skill effects (Metal electric-impact, Wood leaf-gust,
  Water frost-nova, Fire warm-explosion, Earth earth-rupture).
* Mood pass (all zones): CanvasModulate (0.50, 0.50, 0.62), full-screen colour grade shader (35% desaturate, contrast,
  cool shadows / warm highlights, vignette) under the HUD, PointLight2D on your own hero and on every monster camp fire.

## Proof
* `before_*.png` / `after_*.png`: town, wilds (forest entrance 12,22), monster group (forest camp), boss lair. Same cells, same 1152x648 window.
* `combat/combat_01..10.png`: a fight at a forest camp, one bot per element, frames 0.25 s apart
  (01 water nova + wood gust, 04 fire explosion, 07 wood, 08 earth rupture, 09-10 metal electric impact).
* `combat.mp4`: 60 frames at 5 fps (12 s) of the same fight.

## 16x16 issues found
1. **Scale**: the game grid is 32 px; every 16 px Ninja Adventure tile and actor is drawn 2x nearest. That works, but
   the 2x2-tile Ninja Adventure trees are kept at 1x to fit one 32 px tile, so trees have **half the pixel size** of
   everything else (mixed texel density). The proper fix is 2x2-tile trees (map generator change) or a 16 px grid with camera zoom 2.
2. **Collision**: unchanged, because the atlas layout is kept. Trees are solid squares, but the NA trees are round, so you
   bump into transparent corners. Player and monster circles (9-10 px) still suit 32 px actors.
3. **Boss**: TenguRed is 82 px frames at 1x, about 2.5 tiles; the old boss was 32 px x2.2 scale. The name label had to move up
   (y -100) to clear it. Other NA bosses mix 50 and 82 px frames, so each one needs its own offset.
4. **Outlines**: NA sprites have a dark 1 px outline (2 px after scaling). Kenney town tiles and props (barrels on an opaque
   dark square, the blacksmith, NPCs, the map device) have none, so **mixing the packs is obvious** in town and at the camps.
   The town and Kenney props are not reskinned in this test.
5. **Readability**: name labels and HP bars stay readable on the darker ground thanks to the black outline. In packs they
   overlap badly (they did before too). Player light plus vignette leave screen edges dark, which hurts minimap-free scouting.
6. **Animation frames**: NA actors are 16x16 with 4 walk frames and a single attack, item or dead frame per direction.
   This pack version (29 Mar 2026) **does** include a 4-direction `Idle.png`, so the "walk frame 1 as idle" fallback is only
   used if Idle.png is missing. Monsters only have walk frames: no attack, hit or death frames. Effects are 96 px (PVFX)
   versus 16 px actors, so they are scaled by skill radius and look higher-resolution and smoother than the sprites.
7. **Colour**: NA's saturated pastel palette needs the grade pass to read as wuxia. Without it, it is as cute as Kenney.
