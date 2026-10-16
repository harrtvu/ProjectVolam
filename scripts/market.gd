class_name Market
## Trade market (asynchronous auction house) - shared rules, used by the server
## (market_server.gd) and the client panel (market_ui.gd).
##
## A LISTING is {id, seller (account key), seller_name, price, created, expires, item}
## where item is a gear/ticket instance (see gear.gd) or a currency stack
## {"stack": item_id, "n": count}. While listed, the item sits in server escrow
## (the market data), not in anyone's bag.

const FEE_PCT := 2.0            # listing fee (gold sink), min 1 gold
const TAX_PCT := 5.0            # sales tax taken from the seller's proceeds
const MAX_LISTINGS := 20        # active listings per account
const DURATION := 48 * 3600     # seconds (real time) before a listing expires
const MAX_PRICE := 10000000
const PAGE_SIZE := 8
const HISTORY_MAX := 30

const CATEGORIES := ["any", "weapon", "offhand", "helmet", "body", "gloves", "boots", "belt", "amulet", "ring", "ticket", "currency"]
const CAT_NAMES := {"any": "Any category", "weapon": "Weapon", "offhand": "Off-hand", "helmet": "Helmet", "body": "Body Armour",
	"gloves": "Gloves", "boots": "Boots", "belt": "Belt", "amulet": "Amulet", "ring": "Ring", "ticket": "Dungeon Ticket", "currency": "Currency / stack"}
const SORTS := ["price_asc", "price_desc", "newest"]
const SORT_NAMES := {"price_asc": "Price: low to high", "price_desc": "Price: high to low", "newest": "Newest first"}
## Affix stats offered by the search panel (any stat key works on the server).
const FILTER_STATS := ["", "res:fire", "res:water", "res:wood", "res:metal", "res:earth", "res_all", "life_flat", "mana_flat",
	"def_flat", "dmg_flat", "atk_pct", "ele_dmg_pct", "crit", "item_quantity", "item_rarity", "gold_find", "speed_pct",
	"attack_speed", "cast_speed", "map_mon_hp", "map_mon_dmg"]


static func fee(price: int) -> int:
	return maxi(1, ceili(price * FEE_PCT / 100.0))


static func tax(price: int) -> int:
	return maxi(1, floori(price * TAX_PCT / 100.0)) if price > 1 else 0


static func is_stack(item: Dictionary) -> bool:
	return item.has("stack")


## Can this be put on the market at all? "" = yes, else the reason.
static func tradeable_reason(item: Dictionary) -> String:
	if is_stack(item):
		var id := str(item["stack"])
		if not Items.DB.has(id) or id == "gold":
			return "that can't be traded"
		return ""
	if item.is_empty():
		return "no such item"
	if bool(item.get("bound", false)):
		return "%s is account-bound (untradeable)" % Gear.display_name(item)
	return ""


static func item_name(item: Dictionary) -> String:
	if is_stack(item):
		return "%d x %s" % [int(item["n"]), Items.display_name(str(item["stack"]))]
	return Gear.display_name(item)


static func item_summary(item: Dictionary) -> String:
	if is_stack(item):
		return "%d x %s" % [int(item["n"]), str(item["stack"])]
	return Gear.summary(item)


static func category(item: Dictionary) -> String:
	if is_stack(item):
		return "currency"
	return Gear.slot_family(item)


## Sum of a stat on an item (affixes + implicit); res:<el> also counts all-res.
static func stat_value(item: Dictionary, stat: String) -> float:
	if is_stack(item) or stat == "":
		return 0.0
	var v := 0.0
	var imp: Dictionary = Items.BASES.get(str(item.get("base", "")), {}).get("imp", {})
	for k in imp:
		if str(k) == stat or (stat.begins_with("res:") and str(k) == "res_all"):
			v += float(imp[k])
	for e in item.get("mods", []):
		if str(e[1]) == stat or (stat.begins_with("res:") and str(e[1]) == "res_all"):
			v += float(e[2])
	return v


static func sanitize_filters(f: Variant) -> Dictionary:
	var d: Dictionary = f if typeof(f) == TYPE_DICTIONARY else {}
	var out := {
		"text": str(d.get("text", "")).strip_edges().to_lower().left(40),
		"cat": str(d.get("cat", "any")), "rarity": str(d.get("rarity", "any")),
		"max_req": int(d.get("max_req", 0)), "usable": bool(d.get("usable", false)),
		"theme": str(d.get("theme", "any")), "tier_min": int(d.get("tier_min", 0)), "tier_max": int(d.get("tier_max", 0)),
		"stat": str(d.get("stat", "")).left(32), "stat_min": float(d.get("stat_min", 0)),
		"price_min": int(d.get("price_min", 0)), "price_max": int(d.get("price_max", 0)),
		"sort": str(d.get("sort", "price_asc")), "page": maxi(0, int(d.get("page", 0))),
		"mine": bool(d.get("mine", false)),
	}
	if not out["cat"] in CATEGORIES:
		out["cat"] = "any"
	if not out["sort"] in SORTS:
		out["sort"] = "price_asc"
	return out


## Does a listing match the search? cls = the searching player's class (for "usable").
static func matches(l: Dictionary, f: Dictionary, cls: String) -> bool:
	var item: Dictionary = l["item"]
	var price := int(l["price"])
	if f["price_min"] > 0 and price < f["price_min"]:
		return false
	if f["price_max"] > 0 and price > f["price_max"]:
		return false
	if f["cat"] != "any" and category(item) != f["cat"]:
		return false
	if f["text"] != "":
		var hay := (item_name(item) + " " + (str(item["stack"]) if is_stack(item) else str(item.get("base", "")))).to_lower()
		if not hay.contains(f["text"]):
			return false
	if is_stack(item):
		# gear-only filters exclude stacks
		return f["rarity"] == "any" and f["max_req"] <= 0 and f["stat"] == "" and f["theme"] == "any" and f["tier_min"] <= 0 and f["tier_max"] <= 0
	if f["rarity"] != "any" and str(item.get("rarity", "")) != f["rarity"]:
		return false
	var ticket := Dungeons.is_ticket(item)
	if f["max_req"] > 0 and not ticket and Gear.req_level(item) > f["max_req"]:
		return false
	if f["usable"] and not ticket and not Items.can_use(str(item["base"]), cls):
		return false
	if f["theme"] != "any" and (not ticket or Dungeons.theme_of(item) != f["theme"]):
		return false
	if (f["tier_min"] > 0 or f["tier_max"] > 0) and not ticket:
		return false
	if f["tier_min"] > 0 and Dungeons.tier_of(item) < f["tier_min"]:
		return false
	if f["tier_max"] > 0 and Dungeons.tier_of(item) > f["tier_max"]:
		return false
	if f["stat"] != "" and stat_value(item, f["stat"]) < maxf(f["stat_min"], 0.0001):
		return false
	return true


## Filter + sort + page. Returns {rows: [listing...], total, page, pages}.
static func search(listings: Array, f: Dictionary, cls: String, me := "") -> Dictionary:
	var hits: Array = []
	for l in listings:
		if f.get("mine", false) and str(l["seller"]) != me:
			continue
		if matches(l, f, cls):
			hits.append(l)
	match f["sort"]:
		"price_desc":
			hits.sort_custom(func(a, b): return int(a["price"]) > int(b["price"]) or (int(a["price"]) == int(b["price"]) and int(a["id"]) < int(b["id"])))
		"newest":
			hits.sort_custom(func(a, b): return int(a["id"]) > int(b["id"]))
		_:
			hits.sort_custom(func(a, b): return int(a["price"]) < int(b["price"]) or (int(a["price"]) == int(b["price"]) and int(a["id"]) < int(b["id"])))
	var pages := maxi(1, ceili(hits.size() / float(PAGE_SIZE)))
	var page := clampi(int(f["page"]), 0, pages - 1)
	return {"rows": hits.slice(page * PAGE_SIZE, (page + 1) * PAGE_SIZE), "total": hits.size(), "page": page, "pages": pages}


static func sanitize_item(v: Variant) -> Dictionary:
	if typeof(v) != TYPE_DICTIONARY:
		return {}
	if v.has("stack"):
		var id := str(v["stack"])
		if Items.DB.has(id) and id != "gold" and int(v.get("n", 0)) > 0:
			return {"stack": id, "n": int(v["n"])}
		return {}
	return Gear.sanitize(v)


## Validates market data loaded from the save file.
static func sanitize_data(v: Variant) -> Dictionary:
	var out := {"next_id": 1, "listings": [], "claims": {}, "history": {}}
	if typeof(v) != TYPE_DICTIONARY:
		return out
	out["next_id"] = maxi(1, int(v.get("next_id", 1)))
	for l in v.get("listings", []):
		if typeof(l) != TYPE_DICTIONARY:
			continue
		var item := sanitize_item(l.get("item"))
		if item.is_empty() or str(l.get("seller", "")) == "":
			continue
		out["listings"].append({"id": int(l.get("id", 0)), "seller": str(l["seller"]), "seller_name": str(l.get("seller_name", l["seller"])),
			"price": clampi(int(l.get("price", 1)), 1, MAX_PRICE), "created": int(l.get("created", 0)), "expires": int(l.get("expires", 0)), "item": item})
		out["next_id"] = maxi(out["next_id"], int(l.get("id", 0)) + 1)
	var claims = v.get("claims", {})
	if typeof(claims) == TYPE_DICTIONARY:
		for k in claims:
			var c = claims[k]
			if typeof(c) != TYPE_DICTIONARY:
				continue
			var cc := {"gold": maxi(0, int(c.get("gold", 0))), "items": [], "stacks": {}}
			for it in c.get("items", []):
				var s := Gear.sanitize(it)
				if not s.is_empty():
					cc["items"].append(s)
			var st = c.get("stacks", {})
			if typeof(st) == TYPE_DICTIONARY:
				for id in st:
					if Items.DB.has(str(id)) and int(st[id]) > 0:
						cc["stacks"][str(id)] = int(st[id])
			out["claims"][str(k)] = cc
	var hist = v.get("history", {})
	if typeof(hist) == TYPE_DICTIONARY:
		for k in hist:
			if typeof(hist[k]) == TYPE_ARRAY:
				out["history"][str(k)] = (hist[k] as Array).slice(-HISTORY_MAX)
	return out


## Tooltip lines for a listing: the item's own tooltip + seller / price.
static func tooltip(l: Dictionary, cls := "", level := 99) -> Array:
	var item: Dictionary = l["item"]
	var out: Array = []
	if is_stack(item):
		var info := Items.info(str(item["stack"]))
		out.append(["%d x %s" % [int(item["n"]), info["name"]], Color(0.75, 0.95, 1.0)])
		out.append([str(info.get("desc", "")), Color(0.8, 0.8, 0.8)])
	else:
		out = Gear.tooltip(item, cls, level)
	out.append(["Price: %d gold  -  seller %s" % [int(l["price"]), str(l.get("seller_name", "?"))], Color(1, 0.85, 0.3)])
	return out
