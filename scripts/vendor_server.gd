extends Node
const Vendor := preload("res://scripts/vendor.gd")
## NPC vendor (Sunny Meadow + every hideout), server-authoritative. See vendor.gd.
## The stock of the current rotation is saved to its own file next to accounts.json
## (user://volam_save/vendor.json, or X_vendor.json for --save-file=X.json) together
## with the rotation index and the day, so stock, prices and sold-out entries survive
## a restart. A purchase saves the buyer (accounts.json) first, then vendor.json: if the
## server dies in between, the worst case is that one sold-out entry is back in stock -
## the player never loses gold or an item.

var main: Node
var data := {"rotation": -1, "day": "", "stock": []}   # server: Vendor.sanitize(...)
var path := ""
var period := Vendor.ROTATE_SECONDS          # --vendor-rotate=SECS (tests)
var _tick := 0.0
var stock: Array = []           # client: last stock received (the panel reads it)
var next_rotation := 0          # client: unix time of the next rotation
signal stock_changed


func _ready() -> void:
	main = get_parent()


func is_server() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()


func _now() -> int:
	return int(Time.get_unix_time_from_system())


func _log(msg: String) -> void:
	main.log_server("[vendor] " + msg)


static func path_for(save_file: String) -> String:
	if save_file == "user://volam_save/accounts.json":
		return "user://volam_save/vendor.json"
	return save_file.get_basename() + "_vendor.json"


func load_from(store: AccountStore) -> void:
	path = path_for(store.path)
	var raw: Variant = {}
	if FileAccess.file_exists(path):
		raw = JSON.parse_string(FileAccess.get_file_as_string(path))
	data = Vendor.sanitize(raw)
	var left := 0
	for e in data["stock"]:
		left += int(e["qty"])
	_log("loaded %s: rotation %d (%s), %d entries, %d items left in stock" % [path.get_file(), data["rotation"], data["day"], data["stock"].size(), left])
	_check_rotation()


func _save() -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
	var dir := DirAccess.open(path.get_base_dir())
	if FileAccess.file_exists(path):
		dir.remove(path.get_file())
	return dir.rename(tmp.get_file(), path.get_file()) == OK


## New rotation when the timer index or the UTC day changed.
func _check_rotation() -> void:
	var now := _now()
	var rot := Vendor.rotation_index(now, period)
	var day := Vendor.day_of(now)
	if rot == int(data["rotation"]) and day == str(data["day"]) and not data["stock"].is_empty():
		return
	var why := "first stock" if int(data["rotation"]) < 0 else ("new day" if day != str(data["day"]) else "timer")
	data = {"rotation": rot, "day": day, "stock": Vendor.roll_stock(hash("%s:%d" % [day, rot]))}
	_save()
	var parts: Array = []
	for e in data["stock"]:
		parts.append("%s x%d @%d" % [Vendor.entry_summary(e) if e.has("stack") else Gear.display_name(e["item"]), int(e["qty"]), int(e["price"])])
	_log("stock rotated (%s): rotation %d, day %s, %d entries: %s" % [why, rot, day, data["stock"].size(), ", ".join(parts)])
	for p in main.all_players():
		if p.near_vendor():
			push_stock(p)


func next_rotation_at() -> int:
	return (int(data["rotation"]) + 1) * period


func _reject(p: Node, what: String, why: String) -> void:
	_log("%s %s rejected: %s" % [p.display_name, what, why])
	p.notify("Can't do that: " + why, true)


func handle_request(p: Node, arg: Dictionary) -> void:
	match str(arg.get("op", "")):
		"stock":
			push_stock(p)
		"buy":
			buy(p, int(arg.get("id", -1)), int(arg.get("n", 1)))
		"sell":
			if not p.near_vendor():
				_reject(p, "sell", "you must be at the vendor")
				return
			p.server_sell(arg)
		_:
			_reject(p, "vendor", "unknown request")


func _find(id: int) -> Dictionary:
	for e in data["stock"]:
		if int(e["id"]) == id:
			return e
	return {}


func buy(p: Node, id: int, n: int) -> void:
	_check_rotation()
	if not p.near_vendor():
		_reject(p, "buy", "you must be at the vendor")
		return
	var e := _find(id)
	if e.is_empty():
		_reject(p, "buy", "that item is not in stock (the stock may have rotated)")
		return
	n = 1 if e.has("item") else clampi(n, 1, 99)
	if int(e["qty"]) < n:
		_reject(p, "buy", "%s is sold out" % Vendor.entry_name(e) if int(e["qty"]) == 0 else "only %d left" % int(e["qty"]))
		return
	var cost := int(e["price"]) * n
	if p.gold < cost:
		_reject(p, "buy", "not enough gold (%d/%d)" % [p.gold, cost])
		return
	if e.has("item"):
		if p.bag_full():
			_reject(p, "buy", "your bag is full")
			return
		var inst: Dictionary = e["item"].duplicate(true)
		inst["uid"] = Gear.new_uid(main.rng)      # a fresh instance (the stock entry keeps its template)
		p.bag.append(inst)
	else:
		var sid := str(e["stack"])
		if not p.inventory.has(sid) and p.bag_full():
			_reject(p, "buy", "your bag is full")
			return
		p.inventory[sid] = int(p.inventory.get(sid, 0)) + n
	p.gold -= cost
	e["qty"] = int(e["qty"]) - n
	main.save_player_now(p)
	_save()
	_log("%s bought %s%s for %d gold (gold left %d, %d left in stock)" % [p.display_name, "%d x " % n if e.has("stack") else "",
		Vendor.entry_summary(e), cost, p.gold, int(e["qty"])])
	p.notify("Bought %s for %d gold" % [Vendor.entry_name(e), cost], true)
	p.push_inventory()
	push_stock(p)


func push_stock(p: Node) -> void:
	if p._owner_connected():
		client_stock.rpc_id(p.peer_id, data["stock"], next_rotation_at())


func _process(delta: float) -> void:
	if not is_server() or path == "":
		return
	_tick += delta
	if _tick >= 1.0:
		_tick = 0.0
		_check_rotation()


@rpc("authority", "call_local", "reliable")
func client_stock(s: Array, next_at: int) -> void:
	stock = s
	next_rotation = next_at
	if main.bot_mode:
		main._log("vendor stock: %d entries, next rotation in %ds: %s" % [s.size(), next_at - _now(),
			" | ".join(s.map(func(e): return "#%d %s x%d @%d" % [e["id"], Vendor.entry_summary(e), e["qty"], e["price"]]))])
	stock_changed.emit()
