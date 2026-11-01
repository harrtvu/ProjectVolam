# Project Volam — Item Database

PoEDB-style reference for bases, uniques, currency, affixes, drop rates and crafting.
Numbers come from `scripts/items.gd`, `scripts/gear.gd`, `scripts/monsters.gd`, `scripts/zone.gd`,
`scripts/dungeons.gd` and `scripts/atlas.gd`. The narrative overview lives in the
[README](../README.md#gear-loot--crafting).

| Jump | |
|---|---|
| [Rarity & item level](#rarity--item-level) | [Drop pipeline](#drop-pipeline) |
| [Monster loot tables](#monster-loot-tables) | [Currency](#currency--orbs) |
| [Gear bases](#gear-bases) | [Uniques](#uniques) |
| [Affix pools](#affix-pools) | [Enhancement](#enhancement-huyen-tinh) |
| [Tickets & Atlas](#dungeon-tickets--atlas) | [Vendor prices](#vendor--sell-prices) |

Bag **40** / stash **40**. Slots: weapon, off-hand, helmet, body, gloves, boots, belt, amulet, ring ×2.

---

## Rarity & item level

| Rarity | Colour | Affixes | Base chance (before IIR) |
|---|---|---|---|
| Normal | white | implicit only | remainder |
| Magic | blue | 1–2 (max 1 prefix + 1 suffix) | **32%** |
| Rare | yellow | 3–6 (max 3p + 3s), two-word name | **9%** |
| Unique | orange | fixed mods | **1.2%** (world unique pool for that ilvl) |

```
mult = 1 + item_rarity% / 100
roll unique if rand < 0.012 * mult
else rare  if rand < 0.09  * mult
else magic if rand < 0.32  * mult
else normal
# then raise to min_rarity if the table entry demands it
```

**Item level** = monster level (+**2** if boss). Affix tiers are gated by ilvl. Required level to equip =
`max(base.lvl, floor(highest_affix_tier_min_ilvl × 0.8))`; uniques use their own `lvl`.

Base pick among droppable bases with `lvl ≤ ilvl`: weight `1 + lvl/ilvl` (higher-tier bases slightly favoured).

---

## Drop pipeline

On every kill (`zone.drop_loot` → `Gear.roll_monster_loot`):

1. **Gold** always drops: `randi(level … level×3)` × **12** if boss, then × `(1 + gold_find%/100)`.
2. Build **quantity** / **rarity** from killer gear+passives, plus dungeon ticket IIQ/IIR, Atlas completion IIQ
   (`min(30, completed_nodes)` %), Atlas passives, and **+40% IIQ / +100% IIR** if the monster was elite.
3. Roll the monster's loot table. Every non-summon also rolls **@currency** at **9%** (bosses **300%** → guaranteed
   multi-rolls). Quantity multiplies chances; for `@gear` / `@currency`, chance > 100% becomes extra rolls.
4. Atlas passives may add extra full loot re-rolls and a small chance of a random orb.
5. **Ticket** chance (see [Tickets](#dungeon-tickets--atlas)).

Summoned adds (`xp_mult < 1` and empty loot, e.g. spiderlings) drop nothing.

### IIQ / IIR summary

| Source | Effect |
|---|---|
| Gear affixes / passive web | `item_quantity`, `item_rarity`, `gold_find` on the killer |
| Monster `iiq` / `iir` | Added inside the loot roll (bosses 50–60 / 150–200) |
| Dungeon ticket mods + quality | +IIQ/+IIR per mod tier; +1% IIQ per 1% quality (max 20) |
| Atlas completion | +1% IIQ per completed node (cap 30%) |
| Atlas passives | `iiq`, `iir`, theme `reg_*`, etc. |
| Elite pack monster | +40% quantity, +100% rarity on that kill |

---

## Monster loot tables

Table entries are `[id, chance, count?, min_rarity?]`. `@gear` = random gear at monster ilvl.
`u:<id>` = that unique. Chance is multiplied by quantity; `@gear`/`@currency` can multi-roll.

### Overworld / regular

| Monster | Zone flavour | IIQ / IIR | Loot |
|---|---|---|---|
| Slime | Meadow | — | gel 50%, HP pot 30%, gear 12% |
| Mossling | Meadow | — | gel 40%, HP 30%, gear 12% |
| Hill Boar | Meadow | — | HP 30%, gear 12% |
| Meadow Bandit | Meadow | — | HP 35%, gear 14% |
| Grey Wolf | Meadow / Forest | — | HP 30%, gear 12% |
| Wasp | Meadow | — | HP 25%, gear 8% |
| Treant | Forest | **+10 IIQ** | HP 35%, gear 16% |
| Dire Rat | Forest | — | HP 30%, gear 10% |
| Cave Bat | Forest | — | HP 25%, gear 6% |
| Wood Spider | Forest | — | HP 30%, gear 12% |
| Spiderling | Forest (summon) | — | **none** |
| Skeleton | Crypt | — | HP 30%, greater 10%, gear 12% |
| Wraith | Crypt | — | greater 22%, gear 12% |
| Bone Archer | Crypt | — | HP 30%, greater 15%, gear 12% |
| Ghost | Crypt | — | greater 20%, HP 20%, gear 10% |
| Crypt Crawler | Crypt | **+15 IIR** | greater 15%, gear 14% |
| Snow Slime | Frost | — | gel 45%, HP 30%, gear 10% |
| Frost Bat | Frost | — | greater 20%, HP 30%, gear 8% |
| Ice Wolf | Frost | — | greater 25%, gear 13% |
| Yeti | Frost | — | greater 30%, gear 14% |
| Ice Ogre | Frost | **+20 IIQ / +30 IIR** | greater 30%, gear 20% |

Plus every kill: **9%** currency orb (weighted — see below).

### Zone bosses

| Boss | Zone | IIQ / IIR | Guaranteed / notable loot |
|---|---|---|---|
| **Broodmother** | Whisperwood | 50 / 150 | **Venom Dagger** unique, 3× magic gear, 3× HP pot |
| **The Lich King** | Bone Crypt | 50 / 150 | **Soulbinder**, 3× magic, 50% 1 rare, 3× greater |
| **Yeti King** | Frostpeak | 60 / 200 | **Frostbrand + Ember Staff + Frost Aegis**, 3× magic, 1 rare, 4× greater |

Boss currency roll uses chance **3.0** (multi-orb). Boss gold ×12.

### Dungeon bosses

Den Matriarch, Vault Warden, Crypt Lord, Ember Tyrant, Forge Golem — each **50 / 150** IIQ/IIR with
`3× magic gear + 1 rare + 2× greater`, plus [boss ticket extras](#boss-ticket-extras).

---

## Currency & orbs

Every kill also rolls the currency table (weights total **106**):

| Orb | Weight | ≈ share | Effect |
|---|---|---|---|
| Orb of Transmutation | 30 | 28.3% | Normal → Magic (1–2 affixes) |
| Orb of Alteration | 26 | 24.5% | Reroll Magic affixes |
| Enhancement Stone | 22 | 20.8% | Blacksmith: +1 upgrade (see [Enhancement](#enhancement-huyen-tinh)) |
| Orb of Scouring | 8 | 7.5% | Strip affixes → Normal (keeps `upg`) |
| Regal Orb | 7 | 6.6% | Magic → Rare (+1 affix, ≥3 total) |
| Cartographer's Chisel | 6 | 5.7% | Ticket only: +5% quality (max 20) |
| Chaos Orb | 5 | 4.7% | Reroll Rare (3–6 affixes + new name) |
| Exalted Orb | 2 | 1.9% | +1 affix on Rare (max 6) |

Uniques reject all orbs. Stackables also include **Gold**, **Slime Gel** (sell 1), **Health Potion** (+15 HP, sell 2),
**Greater Potion** (+40 HP, sell 6).

---

## Gear bases

`lvl` = minimum monster ilvl to drop **and** base equip requirement. `drop: false` = unique-only base
(never rolled as Normal/Magic/Rare). Empty classes = any class.

### Weapons

| Id | Name | Lvl | Dmg | Classes | Drop |
|---|---|---|---|---|---|
| `iron_sword` | Iron Sword | 1 | 1 | any | yes |
| `apprentice_staff` | Apprentice Staff | 1 | 1 | wood, water, fire | yes |
| `steel_sword` | Steel Sword | 4 | 2 | any | yes |
| `war_axe` | War Axe | 6 | 4 | metal, earth | yes |
| `venom_dagger` | Venom Dagger | 6 | 5 | metal, wood | **unique only** |
| `great_hammer` | Great Hammer | 10 | 6 | metal, earth | yes |
| `lich_staff` | Lich Staff | 10 | 7 | wood, water, fire | yes |
| `frostbrand` | Frostbrand | 13 | 9 | metal, earth | **unique only** |
| `ember_staff` | Ember Staff | 13 | 9 | wood, water, fire | **unique only** |

### Off-hand & armour

| Id | Name | Slot | Lvl | Def | Implicit | Notes |
|---|---|---|---|---|---|---|
| `wooden_shield` | Wooden Shield | offhand | 1 | 1 | — | |
| `iron_shield` | Iron Shield | offhand | 4 | 2 | — | |
| `bone_shield` | Bone Shield | offhand | 8 | 4 | — | |
| `frost_aegis` | Frost Aegis | offhand | 13 | 6 | — | unique only |
| `leather_cap` | Leather Cap | helmet | 1 | 1 | — | |
| `iron_helm` | Iron Helm | helmet | 6 | 2 | — | |
| `horned_helm` | Horned Helm | helmet | 11 | 3 | +10 life | |
| `cloth_robe` | Cloth Robe | body | 1 | 1 | +10 mana | |
| `leather_vest` | Leather Vest | body | 3 | 2 | — | |
| `chain_mail` | Chain Mail | body | 8 | 4 | — | |
| `plate_armour` | Plate Armour | body | 12 | 6 | — | metal, earth |
| `cloth_wraps` | Cloth Wraps | gloves | 1 | 1 | — | |
| `iron_gauntlets` | Iron Gauntlets | gloves | 7 | 2 | — | |
| `sandals` | Sandals | boots | 1 | 0 | +3% move | |
| `leather_boots` | Leather Boots | boots | 5 | 1 | +4% move | |
| `iron_greaves` | Iron Greaves | boots | 9 | 2 | — | |

### Jewellery

| Id | Name | Slot | Lvl | Implicit |
|---|---|---|---|---|
| `rope_belt` | Rope Belt | belt | 1 | +5 life |
| `leather_belt` | Leather Belt | belt | 6 | +12 life |
| `jade_amulet` | Jade Amulet | amulet | 1 | +3% all res |
| `coral_amulet` | Coral Amulet | amulet | 7 | +15 life |
| `copper_ring` | Copper Ring | ring | 1 | +5 mana |
| `jade_ring` | Jade Ring | ring | 5 | +8% wood res |
| `silver_ring` | Silver Ring | ring | 9 | +1% crit |

### Tickets (not equippable)

| Id | Name | Theme |
|---|---|---|
| `ticket_wood` | Forest Den Ticket | wood |
| `ticket_water` | Frozen Vault Ticket | water |
| `ticket_earth` | Stone Hollow Ticket | earth |
| `ticket_fire` | Ember Caverns Ticket | fire |
| `ticket_metal` | Metal Forge Ticket | metal |

---

## Uniques

### Boss uniques (guaranteed on that boss)

| Id | Name | Base | Lvl | Boss | Mods |
|---|---|---|---|---|---|
| `venom_dagger` | Venom Dagger | venom_dagger | 6 | Broodmother | +10% attack speed, +25 poison, +15% dmg vs earth |
| `lich_staff_u` | Soulbinder (Lich Staff) | lich_staff | 10 | Lich King | 1.5% mana leech, +30 mana, +10% cast speed, −10% metal res |
| `frostbrand` | Frostbrand | frostbrand | 13 | Yeti King | +20% dmg vs fire, +25% water res, +8% attack speed |
| `ember_staff` | Ember Staff | ember_staff | 13 | Yeti King | +12% cast speed, +30 burn, +20% ele dmg, −15% water res |
| `frost_aegis` | Frost Aegis | frost_aegis | 13 | Yeti King | +20% fire res, +30% water res, +30 life |

### World uniques (rare roll when rarity = unique and `lvl ≤ ilvl`)

| Id | Name | Base | Lvl | Mods |
|---|---|---|---|---|
| `gold_seeker` | Gold Seeker's Ring | copper_ring | 3 | +12% IIQ, +25% IIR, +40% gold find, −10% attack |
| `golden_dragon` | Kim Long (Golden Dragon) Amulet | jade_amulet | 5 | +20% dmg vs wood, +4% crit, +30% gold find |
| `thousand_leaf` | Moc Diep (Thousand-Leaf) Treads | leather_boots | 5 | +18% move, +20% metal res, +15% IIR |
| `river_heart` | Thuy Tam (River Heart) Circlet | iron_helm | 6 | +40 mana, +30% mana regen, +25% fire res |
| `mountain_root` | Tho Son (Mountain-Root) Girdle | leather_belt | 6 | +60 life, +4 def, +20% wood res, −5% move |
| `emberfist` | Hoa Quyen (Emberfist) | iron_gauntlets | 7 | +6 flat dmg, +20 burn, +8% attack speed, −10% water res |
| `five_phases` | Ngu Hanh Band (Five Phases) | silver_ring | 9 | +12% all res, +10% ele dmg |

If a unique rarity rolls but no world unique fits the ilvl, the drop falls back to **rare**.

### Unique ticket

| Id | Name | Base | Gate | Mods |
|---|---|---|---|---|
| `wuxing_sanctum` | Sanctum of the Five Phases | ticket_metal | ticket rarity unique **and** tier ≥ 6 (50% → Sanctum, else force rare) | +60% map mon HP, +30% extra ele, +3 elites, −20% player res |

---

## Affix pools

Tiers are `[min_ilvl, low, high]`. `{el}` expands once per element (metal/wood/water/fire/earth).
`{skill}` picks a skill of the killer's class when the item is rolled.

### Prefixes

| Id | Stat | W | Slots | Tiers (ilvl → range) |
|---|---|---|---|---|
| life | life_flat | 10 | armour, belt, jewel | 1:5–10 · 5:11–18 · 10:19–28 · 14:29–40 |
| mana | mana_flat | 8 | weapon, armour, belt, jewel | 1:5–10 · 6:11–20 · 12:21–32 |
| flat_dmg | dmg_flat | 9 | weapon, gloves, ring, amulet | 1:1–2 · 5:3–4 · 9:5–7 · 13:8–10 |
| pct_dmg | atk_pct | 7 | weapon, amulet | 1:5–9 · 6:10–16 · 11:17–25 |
| ele_dmg | ele_dmg_pct | 7 | weapon, amulet, ring | 1:6–10 · 7:11–18 · 12:19–28 |
| armour | def_flat | 8 | armour, belt | 1:1–2 · 6:3–4 · 11:5–7 |
| slay_{el} | dmg_vs:{el} | 3 | weapon, ring, amulet, gloves | 1:6–10 · 8:11–18 · 13:19–26 |
| rarity_p | item_rarity | 5 | helmet, boots, gloves, jewel | 1:4–8 · 6:9–14 · 12:15–22 |
| skill | dmg:{skill} | 5 | weapon, amulet | 3:10–16 · 9:17–26 · 14:27–36 |
| m_hp | map_mon_hp | 10 | ticket | 1:20–30 · 6:31–45 · 12:46–60 |
| m_dmg | map_mon_dmg | 10 | ticket | 1:12–20 · 6:21–30 · 12:31–40 |
| m_ele | map_extra_ele | 8 | ticket | 1:10–15 · 6:16–25 · 12:26–35 |
| m_packs | map_packs | 8 | ticket | 1:20–30 · 8:31–50 |
| m_elites | map_elites | 6 | ticket | 3:1 · 10:2–3 |
| m_speed | map_mon_speed | 7 | ticket | 1:10–15 · 8:16–25 |

### Suffixes

| Id | Stat | W | Slots | Tiers |
|---|---|---|---|---|
| res_{el} | res:{el} | 5 | armour, belt, jewel | 1:6–11 · 5:12–17 · 10:18–24 · 14:25–30 |
| res_all | res_all | 4 | amulet, ring | 8:3–5 · 13:6–9 |
| aspd | attack_speed | 7 | weapon, gloves, ring | 1:3–5 · 7:6–9 · 12:10–13 |
| cspd | cast_speed | 7 | weapon, amulet, ring | same |
| crit | crit | 6 | weapon, amulet, ring, gloves | 1:1–2 · 6:2–3 · 11:3–5 |
| critx | crit_dmg | 5 | weapon, amulet | 5:8–14 · 11:15–24 |
| lleech / mleech | life / mana leech | 4 | weapon, ring, gloves | 4:0.4–0.8 · 10:0.9–1.5 |
| move | speed_pct | 10 | boots | 1:4–7 · 6:8–11 · 11:12–16 |
| quantity | item_quantity | 4 | ring, amulet, belt, boots | 5:3–5 · 11:6–9 |
| gold | gold_find | 6 | ring, amulet, belt, gloves, helmet | 1:5–10 · 6:11–18 · 11:19–28 |
| mregen | mp_regen_pct | 6 | helmet, body, belt, jewel, offhand | 1:8–14 · 7:15–24 |
| m_res | map_less_res | 9 | ticket | 1:8–12 · 6:13–20 · 12:21–30 |
| m_noregen | map_no_regen | 4 | ticket | 4:1 |
| m_mana | map_less_mana_regen | 7 | ticket | 1:20–30 · 8:31–50 |
| m_def | map_mon_def | 7 | ticket | 1:2–3 · 8:4–6 |

Resistances from gear+passives soft-cap at **75%**.

---

## Enhancement (Huyen Tinh)

Blacksmith only. Costs an Enhancement Stone + gold. Item is **never destroyed**.

| Step | Success | Gold `10 × (upg+1)²` |
|---|---|---|
| +0 → +1 | 100% | 10 |
| +1 → +2 | 90% | 40 |
| +2 → +3 | 80% | 90 |
| +3 → +4 | 70% | 160 |
| +4 → +5 | 60% | 250 |
| +5 → +6 | 50% | 360 |
| +6 → +7 | 40% | 490 |
| +7 → +8 | 30% | 640 |
| +8 → +9 | 20% | 810 |
| +9 → +10 | 10% | 1000 |

Fail below +5: no change. Fail at +5 or higher: **50%** chance to lose 1 level, else stay.

Upgrade bonuses:

- Weapons: `base_dmg + upg + floor(base × 0.1 × upg)`
- Armour: `base_def + ceil(upg × 0.5)`
- Jewellery / belts (no dmg/def): **+3 life** per upgrade level

---

## Dungeon tickets & Atlas

### Ticket drop chance

| Context | Base | Formula |
|---|---|---|
| Dungeon normal monster | **3%** | `base × (1 + quantity/100) × (1 + atlas_tq/100)` |
| Dungeon elite | **15%** | same |
| Overworld, monster lvl ≥ 6, not boss | **1%** | `0.01 × (1 + quantity/100)` |

Ticket item level = `2 × tier`. Monster level inside = `4 + 2 × tier`. Affix count follows rarity
(Magic 1–2, Rare **3–6**). Chisel: +5% quality → +5% run IIQ (cap 20%).

### Boss ticket extras

On dungeon boss death (on top of the boss loot table):

1. **Guaranteed** ticket (65% chance adjacent higher-tier Atlas node)
2. Second ticket at `30% × (1 + atlas_boss%/100)`
3. Third ticket at `atlas_boss%/100` (always adjacent if it fires)
4. Pinnacle (Ngũ Hành): +2 random non-ticket uniques at ilvl 40
5. Hideout decoration: **8%** (configurable)

Merchant ticket price: `25 + 35 × tier²`.

### Map mod IIQ / IIR (per rolled mod)

| Mod tier | IIQ | IIR |
|---|---|---|
| T0 / T1 / T2 | +4 / +6 / +9% | +6 / +10 / +15% |
| Unique mod | +8% | +12% |

---

## Vendor & sell prices

### Sell (blacksmith / vendor)

| Kind | Gold |
|---|---|
| Normal gear | `2 + ilvl` |
| Magic | `5 + 2 × ilvl` |
| Rare | `12 + 3 × ilvl` |
| Unique | `40 + 4 × ilvl` |
| + per enhancement | **+10** each |
| Ticket | `3 + 4 × tier + 3 × mods` |
| Slime gel / HP pot / greater | 1 / 2 / 6 |

Vendor **buy** price = sell × **4**. Staples always in stock: HP pot ×20 @10, greater ×10 @30.
Rotating orbs (2 types / rotation, qty 1–3): transmute 40, alteration 60, chisel 80, enhance 120,
scour 150, regal 250. Gear stock: 8 pieces — 35% normal / 45% magic / 20% rare.

---

## Quick farming notes

- **Gold Seeker's Ring** (+12 IIQ / +25 IIR / +40 gold, −10% attack) is the early quantity unique (ilvl 3+).
- Stack **IIR** before hunting world uniques; empty unique pools fall back to rares.
- **Ice Ogres** (+20 IIQ / +30 IIR) and **Treants** (+10 IIQ) are the best regular overworld farmers.
- Zone bosses are the reliable unique farm; Yeti King drops three uniques every kill.
- Dungeon elites are the ticket sustain loop (15% base + quantity + Atlas `tq`).
- For testing without grinding: login as **`gm`** and type `/gm kit` (see [Game Master](../README.md#game-master-testing-cheats)).

---

*Source of truth: the scripts linked above. If this page and the code disagree, trust the code.*
