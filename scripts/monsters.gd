class_name Monsters
## Monster type database. Stats scale with level:
##   max_hp = hp[0] + hp[1] * level,  damage = dmg[0] + dmg[1] * level
## behaviour:
##   melee   - wander, chase, bite in range
##   pack    - melee; when one member is attacked/aggroed the whole pack joins in
##   lunge   - melee + quick dash at its target
##   erratic - flying (ignores walls/water), jittery movement
##   phase   - flying, drifts through walls, semi-transparent
##   ranged  - keeps its distance and shoots projectiles
## special (bosses): summon / volley / quake

const DB := {
	"slime": {"element": "water", "name": "Slime", "sprite": "slime", "hp": [4, 2], "dmg": [3, 1.0], "def": 0,
		"speed": 38, "chase": 62, "aggro": 130, "range": 24, "cd": 1.2, "behavior": "melee",
		"respawn": 6.0, "loot": [["slime_gel", 0.5], ["health_potion", 0.3], ["@gear", 0.12]]},
	"rat": {"element": "earth", "name": "Dire Rat", "sprite": "rat", "hp": [6, 4], "dmg": [2, 1.2], "def": 0,
		"speed": 50, "chase": 118, "aggro": 170, "range": 22, "cd": 0.9, "behavior": "pack",
		"respawn": 10.0, "loot": [["health_potion", 0.3], ["@gear", 0.1]]},
	"bat": {"element": "fire", "name": "Cave Bat", "sprite": "bat", "hp": [4, 3], "dmg": [2, 1.0], "def": 0,
		"speed": 70, "chase": 105, "aggro": 160, "range": 22, "cd": 1.0, "behavior": "erratic",
		"flying": true, "respawn": 8.0, "loot": [["health_potion", 0.25], ["@gear", 0.06]]},
	"frost_bat": {"element": "metal", "name": "Frost Bat", "sprite": "bat", "tint": [0.6, 0.85, 1.3], "hp": [4, 3], "dmg": [2, 1.2],
		"def": 1, "speed": 70, "chase": 110, "aggro": 160, "range": 22, "cd": 1.0, "behavior": "erratic",
		"flying": true, "respawn": 8.0, "loot": [["greater_potion", 0.2], ["health_potion", 0.3], ["@gear", 0.08]]},
	"spider": {"element": "wood", "name": "Wood Spider", "sprite": "spider", "hp": [8, 4], "dmg": [3, 1.4], "def": 1,
		"speed": 40, "chase": 72, "aggro": 140, "range": 24, "cd": 1.1, "behavior": "lunge",
		"respawn": 10.0, "loot": [["health_potion", 0.3], ["@gear", 0.12]]},
	"spiderling": {"element": "wood", "name": "Spiderling", "sprite": "spider", "scale": 0.7, "tint": [1.1, 0.8, 1.2], "hp": [4, 2],
		"dmg": [2, 1.0], "def": 0, "speed": 60, "chase": 95, "aggro": 300, "range": 20, "cd": 1.0,
		"behavior": "lunge", "respawn": 0.0, "xp_mult": 0.3, "loot": []},
	"archer": {"element": "metal", "name": "Crypt Archer", "sprite": "archer", "hp": [8, 4], "dmg": [3, 1.4], "def": 1,
		"speed": 40, "chase": 60, "aggro": 230, "range": 230, "cd": 1.8, "behavior": "ranged", "keep": 150,
		"projectile": "arrow", "respawn": 12.0, "loot": [["health_potion", 0.3], ["greater_potion", 0.15], ["@gear", 0.12]]},
	"ghost": {"element": "water", "name": "Restless Ghost", "sprite": "ghost", "alpha": 0.75, "hp": [10, 5], "dmg": [4, 1.5], "def": 2,
		"speed": 28, "chase": 62, "aggro": 170, "range": 24, "cd": 1.3, "behavior": "phase", "flying": true,
		"respawn": 12.0, "loot": [["greater_potion", 0.2], ["health_potion", 0.2], ["@gear", 0.1]]},
	"crawler": {"element": "fire", "name": "Grave Crawler", "sprite": "crawler", "hp": [14, 6], "dmg": [5, 1.8], "def": 3,
		"speed": 35, "chase": 58, "aggro": 140, "range": 26, "cd": 1.4, "behavior": "melee",
		"respawn": 12.0, "iir": 15, "loot": [["greater_potion", 0.15], ["@gear", 0.14]]},
	"yeti": {"element": "water", "name": "Yeti", "sprite": "yeti", "hp": [20, 7], "dmg": [6, 1.6], "def": 4,
		"speed": 40, "chase": 72, "aggro": 160, "range": 26, "cd": 1.3, "behavior": "melee",
		"respawn": 14.0, "loot": [["greater_potion", 0.3], ["@gear", 0.14]]},
	"ice_ogre": {"element": "earth", "name": "Ice Ogre", "sprite": "ice_ogre", "scale": 1.3, "hp": [30, 8], "dmg": [8, 2.0], "def": 6,
		"speed": 30, "chase": 52, "aggro": 150, "range": 30, "cd": 1.7, "behavior": "melee",
		"respawn": 16.0, "iiq": 20, "iir": 30, "loot": [["greater_potion", 0.3], ["@gear", 0.2]]},
	# ---- bosses
	"broodmother": {"element": "wood", "name": "Broodmother", "sprite": "broodmother", "boss": true, "scale": 2.2,
		"hp": [300, 20], "dmg": [8, 2.0], "def": 3, "speed": 30, "chase": 78, "aggro": 220, "range": 36,
		"cd": 1.2, "behavior": "lunge", "special": "summon", "special_cd": 10.0, "respawn": 180.0,
		"iiq": 50, "iir": 150, "loot": [["u:venom_dagger", 1.0], ["@gear", 1.0, 3, "magic"], ["health_potion", 1.0, 3]]},
	"lich": {"element": "metal", "name": "The Lich King", "sprite": "lich", "boss": true, "scale": 1.9,
		"hp": [500, 30], "dmg": [8, 1.5], "def": 4, "speed": 25, "chase": 55, "aggro": 260, "range": 260,
		"cd": 1.5, "behavior": "ranged", "keep": 120, "projectile": "bolt", "special": "volley",
		"special_cd": 5.0, "respawn": 180.0,
		"iiq": 50, "iir": 150, "loot": [["u:lich_staff_u", 1.0], ["@gear", 1.0, 3, "magic"], ["@gear", 0.5, 1, "rare"], ["greater_potion", 1.0, 3]]},
	"yeti_king": {"element": "water", "name": "Yeti King", "sprite": "yeti_king", "boss": true, "scale": 2.4,
		"hp": [800, 40], "dmg": [12, 1.6], "def": 7, "speed": 30, "chase": 70, "aggro": 220, "range": 40,
		"cd": 1.5, "behavior": "melee", "special": "quake", "special_cd": 7.0, "respawn": 180.0,
		"iiq": 60, "iir": 200, "loot": [["u:frostbrand", 1.0], ["u:ember_staff", 1.0], ["u:frost_aegis", 1.0], ["@gear", 1.0, 3, "magic"], ["@gear", 1.0, 1, "rare"], ["greater_potion", 1.0, 4]]},
	# ---- dungeon bosses (endgame instances; never respawn, loot handled by the instance too)
	"den_matriarch": {"element": "wood", "name": "Den Matriarch", "sprite": "broodmother", "boss": true, "dungeon": true, "scale": 2.4,
		"tint": [0.75, 1.15, 0.7], "hp": [200, 32], "dmg": [6, 1.6], "def": 3, "speed": 32, "chase": 80, "aggro": 260, "range": 36,
		"cd": 1.2, "behavior": "lunge", "special": "summon", "special_cd": 9.0, "respawn": 0.0,
		"iiq": 50, "iir": 150, "loot": [["@gear", 1.0, 3, "magic"], ["@gear", 1.0, 1, "rare"], ["greater_potion", 1.0, 2]]},
	"vault_warden": {"element": "water", "name": "Vault Warden", "sprite": "yeti_king", "boss": true, "dungeon": true, "scale": 2.4,
		"tint": [0.7, 0.9, 1.3], "hp": [260, 36], "dmg": [7, 1.6], "def": 5, "speed": 30, "chase": 70, "aggro": 260, "range": 40,
		"cd": 1.5, "behavior": "melee", "special": "quake", "special_cd": 7.0, "respawn": 0.0,
		"iiq": 50, "iir": 150, "loot": [["@gear", 1.0, 3, "magic"], ["@gear", 1.0, 1, "rare"], ["greater_potion", 1.0, 2]]},
	"crypt_lord": {"element": "earth", "name": "Crypt Lord", "sprite": "lich", "boss": true, "dungeon": true, "scale": 2.0,
		"tint": [1.15, 0.95, 0.7], "hp": [190, 30], "dmg": [6, 1.4], "def": 4, "speed": 25, "chase": 55, "aggro": 280, "range": 250,
		"cd": 1.5, "behavior": "ranged", "keep": 120, "projectile": "bolt", "special": "volley", "special_cd": 5.0, "respawn": 0.0,
		"iiq": 50, "iir": 150, "loot": [["@gear", 1.0, 3, "magic"], ["@gear", 1.0, 1, "rare"], ["greater_potion", 1.0, 2]]},
	"ember_tyrant": {"element": "fire", "name": "Ember Tyrant", "sprite": "ice_ogre", "boss": true, "dungeon": true, "scale": 2.3,
		"tint": [1.5, 0.6, 0.35], "hp": [230, 34], "dmg": [8, 1.8], "def": 4, "speed": 30, "chase": 66, "aggro": 260, "range": 40,
		"cd": 1.5, "behavior": "melee", "special": "quake", "special_cd": 6.0, "respawn": 0.0,
		"iiq": 50, "iir": 150, "loot": [["@gear", 1.0, 3, "magic"], ["@gear", 1.0, 1, "rare"], ["greater_potion", 1.0, 2]]},
	"forge_golem": {"element": "metal", "name": "Forge Golem", "sprite": "ice_ogre", "boss": true, "dungeon": true, "scale": 2.3,
		"tint": [0.85, 0.9, 1.0], "hp": [280, 38], "dmg": [7, 1.6], "def": 7, "speed": 26, "chase": 60, "aggro": 260, "range": 40,
		"cd": 1.6, "behavior": "melee", "special": "volley", "projectile": "bolt", "special_cd": 6.0, "respawn": 0.0,
		"iiq": 50, "iir": 150, "loot": [["@gear", 1.0, 3, "magic"], ["@gear", 1.0, 1, "rare"], ["greater_potion", 1.0, 2]]},
}

## Loot entries: [id, chance, count?, min_rarity?] - see Gear.roll_monster_loot().
## "iiq"/"iir": the monster's own item quantity / rarity bonus (bosses and elites).

static func element_of(type: String) -> String:
	return str(info(type).get("element", ""))


static func info(type: String) -> Dictionary:
	return DB.get(type, DB["slime"])


static func max_hp(type: String, level: int) -> int:
	var d := info(type)
	return int(d["hp"][0] + d["hp"][1] * level)


static func damage(type: String, level: int) -> int:
	var d := info(type)
	return int(d["dmg"][0] + d["dmg"][1] * level)


static func xp_reward(type: String, level: int) -> int:
	var d := info(type)
	if d.get("boss", false):
		return 100 + 20 * level
	return maxi(1, int((6 + 4 * level) * float(d.get("xp_mult", 1.0))))
