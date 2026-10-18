## (no class_name: users preload this script as `const Vendor := preload("res://scripts/vendor.gd")`
## so a stale .godot class cache after `git pull` can never break loading)
## NPC vendor (replaces the old player trade market): static rules shared by the
## server (vendor_server.gd) and the panel (vendor_ui.gd).
##   * players SELL loot for gold (Gear.sell_price / Items "sell"),
##   * and BUY from a rotating stock: STOCK_GEAR gear pieces + potions + a few orbs,
##     regenerated every ROTATE_SECONDS (and at each new UTC day). The stock of a
##     rotation is rolled from (day, rotation index), and the server saves it, so stock,
##     prices and what is already sold out survive a restart.

const ROTATE_SECONDS := 2 * 3600
const STOCK_GEAR := 8
const RANGE := 100.0
const BUY_MULT := 4            # buy price = sell price x this (the vendor's margin)
## always in stock: [item id, price each, stock per rotation]
const STAPLES := [["health_potion", 10, 20], ["greater_potion", 30, 10]]
## a couple of these orbs per rotation: [orb id, price]
const ORB_STOCK := [["orb_transmute", 40], ["orb_alteration", 60], ["orb_chisel", 80], ["enhance_stone", 120], ["orb_regal", 250], ["orb_scour", 150]]


static func rotation_index(unix: int, period := ROTATE_SECONDS) -> int:
	return int(floor(float(unix) / float(maxi(period, 1))))


static func day_of(unix: int) -> String:
	return Time.get_date_string_from_unix_time(unix)


static func gear_price(inst: Dictionary) -> int:
	return maxi(5, Gear.sell_price(inst) * BUY_MULT)


## Roll the stock of one rotation. Gear item levels spread over 1..max_ilvl so
## both new and levelled characters find something.
static func roll_stock(seed_val: int, max_ilvl := 20) -> Array:
	var g := RandomNumberGenerator.new()
	g.seed = seed_val
	var out: Array = []
	var next := 1
	for s in STAPLES:
		out.append({"id": next, "stack": s[0], "price": int(s[1]), "qty": int(s[2])})
		next += 1
	var orbs: Array = ORB_STOCK.duplicate()
	for k in 2:
		var o: Array = orbs.pop_at(g.randi() % orbs.size())
		out.append({"id": next, "stack": o[0], "price": int(o[1]), "qty": 1 + g.randi() % 3})
		next += 1
	for k in STOCK_GEAR:
		var il := 1 + int(round(float(max_ilvl - 1) * float(k) / float(STOCK_GEAR - 1)))
		var base := Gear.roll_base(il, g)
		var r := g.randf()
		var rarity := "rare" if r < 0.2 else ("magic" if r < 0.65 else "normal")
		var inst := Gear.make(base, rarity, il, g)
		out.append({"id": next, "item": inst, "price": gear_price(inst), "qty": 1})
		next += 1
	return out


static func entry_name(e: Dictionary) -> String:
	if e.has("item"):
		return Gear.display_name(e["item"])
	return Items.display_name(str(e.get("stack", "")))


static func entry_summary(e: Dictionary) -> String:
	if e.has("item"):
		return Gear.summary(e["item"])
	return "%s" % e.get("stack", "")


## Validate saved vendor data (vendor.json). Unknown junk is dropped.
static func sanitize(v: Variant) -> Dictionary:
	var out := {"rotation": -1, "day": "", "stock": []}
	if typeof(v) != TYPE_DICTIONARY:
		return out
	out["rotation"] = int(v.get("rotation", -1))
	out["day"] = str(v.get("day", ""))
	if typeof(v.get("stock")) == TYPE_ARRAY:
		for e in v["stock"]:
			if typeof(e) != TYPE_DICTIONARY:
				continue
			var c := {"id": int(e.get("id", 0)), "price": maxi(1, int(e.get("price", 1))), "qty": maxi(0, int(e.get("qty", 0)))}
			if e.has("item"):
				var inst := Gear.sanitize(e["item"])
				if inst.is_empty():
					continue
				c["item"] = inst
			elif Items.exists(str(e.get("stack", ""))):
				c["stack"] = str(e["stack"])
			else:
				continue
			out["stock"].append(c)
	return out
