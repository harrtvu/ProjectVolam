# Volam Outpost (TD + Roguelike slice)

Browser-playable vertical slice for the Project Volam tower-defense / roguelike direction.
The Godot MMORPG prototype in the repo root stays intact; this folder is the first combat map loop.

## Play

From the repo root:

```bash
python3 -m http.server 8080
```

Open [http://localhost:8080/td/](http://localhost:8080/td/).

Sprites load from `../assets/` (Kenney monsters + skill icons already in the project).

## Slice contents

- One path map with a gate (lives)
- Three towers: Archer (45g), Ember Mage (70g AoE), Frost Totem (60g slow) — place, upgrade to Lv3, sell
- Eight escalating waves
- After each cleared wave: pick 1 of 3 run skills
- Win by clearing all waves; lose when lives hit 0
- Optional auto-demo: open `/td/?bot=1`

## Controls

| Input | Action |
|---|---|
| Click grass tile | Place selected tower |
| Click tower | Select |
| `U` / Upgrade | Upgrade selected tower |
| `1` `2` `3` | Archer / Mage / Frost |
| Space / Start wave | Begin next wave |
| Enter / Esc | Dismiss intro |
| Speed | ×1 / ×2 / ×3 |
