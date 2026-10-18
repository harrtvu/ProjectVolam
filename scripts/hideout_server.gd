extends Node
## Player hideouts (Path of Exile style), server-authoritative.
##
## One private dynamic zone "ho<N>" per account, built on every peer from the
## account's layout (create_hideout RPC) like a dungeon instance; the usual zone
## visibility keeps it private. Solo for now: only the owner may enter
## (_may_enter - a party / "/visit" system only has to widen that check).
## Stations (Map Device, Ticket Merchant, Vendor, Blacksmith + stash) reuse
## the town station code; dungeon portals opened here return here.

const EMPTY_TIMEOUT := 20.0

var main: Node
var by_owner := {}      # account_key -> zone id (server)
var owner_of := {}      # zone id -> account_key (server)
var _empty_since := {}  # zone id -> time it became empty
var _next := 0
var _tick := 0.0


func _ready() -> void:
	main = get_parent()


func is_server() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _log(msg: String) -> void:
	main.log_server("[hideout] " + msg)


func _reject(p: Node, what: String, why: String) -> void:
	_log("%s %s rejected: %s" % [p.display_name, what, why])
	p.notify("Can't do that: " + why, true)


# ================================================================ lifetime

## (server) The owner's hideout zone, created on every peer if needed.
func ensure(account_key: String, owner_name: String, layout: Dictionary) -> String:
	if by_owner.has(account_key) and main.zones.has(by_owner[account_key]):
		return by_owner[account_key]
	_next += 1
	var id := "ho%d" % _next
	var data := {"slot": main.instances._free_slot(), "owner": owner_name, "layout": layout}
	create_hideout.rpc(id, data)
	by_owner[account_key] = id
	owner_of[id] = account_key
	_empty_since[id] = _now()
	_log("created %s for %s (slot %d): %s" % [id, owner_name, int(data["slot"]), Hideouts.summary(layout)])
	return id


func zone_of(p: Node) -> String:
	return str(by_owner.get(p.account_key, ""))


func in_own_hideout(p: Node) -> bool:
	return p.zone != null and p.zone.zone_id == zone_of(p) and zone_of(p) != ""


## Solo: only the owner. (A party / visit system would widen this.)
func _may_enter(p: Node, id: String) -> bool:
	return owner_of.get(id, "") == p.account_key


func enter(p: Node) -> void:
	if p.dead:
		_reject(p, "hideout", "you are dead")
		return
	if p.zone.is_dungeon():
		_reject(p, "hideout", "leave the dungeon first")
		return
	if main.hideout_debug:
		for t in Hideouts.THEME_ORDER:
			if t != "water" and not p.hideout["unlocked"].has(t):   # water stays locked (tests the rejection)
				p.hideout["unlocked"].append(t)
	var id := ensure(p.account_key, p.display_name, p.hideout)
	if p.zone.zone_id == id:
		_reject(p, "hideout", "you are already in your hideout")
		return
	if not _may_enter(p, id):
		_reject(p, "hideout", "that hideout belongs to someone else")
		return
	_log("%s enters %s (from %s)" % [p.display_name, id, p.zone.zone_id])
	main.transfer_player(p, id, Hideouts.ARRIVE)


func _process(delta: float) -> void:
	if not is_server() or owner_of.is_empty():
		return
	_tick += delta
	if _tick < 1.0:
		return
	_tick = 0.0
	for id in owner_of.keys():
		var busy := false
		for pid in main.peer_zone:
			if main.peer_zone[pid] == id:
				busy = true
		for rid in main.instances.runs:
			if str(main.instances.runs[rid].get("origin", "")) == id:
				busy = true   # a dungeon opened here returns here
		if busy:
			_empty_since[id] = _now()
		elif _now() - float(_empty_since[id]) >= EMPTY_TIMEOUT:
			_log("closing %s (owner %s): empty" % [id, owner_of[id]])
			by_owner.erase(owner_of[id])
			owner_of.erase(id)
			_empty_since.erase(id)
			destroy_hideout.rpc(id)


## Late joiners: every hideout zone must exist on their peer.
func sync_peer(pid: int) -> void:
	for id in owner_of:
		var h: Dictionary = Zones.info(id)
		create_hideout.rpc_id(pid, id, {"slot": int(h["slot"]), "owner": str(h["owner"]), "layout": h["hideout"]})


# ================================================================ requests

func handle_request(p: Node, arg: Dictionary) -> void:
	var op := str(arg.get("op", ""))
	if op == "enter":
		enter(p)
		return
	if op == "debug_gold" and main.hideout_debug:
		p.gold += 100000
		p.push_inventory()
		_log("(debug) %s +100000 gold" % p.display_name)
		return
	if op == "buy":
		buy(p, str(arg.get("id", "")), int(arg.get("count", 1)))
		return
	if not in_own_hideout(p):
		_reject(p, "hideout %s" % op, "you must be in your hideout")
		return
	var h: Dictionary = p.hideout
	var dec: Array = h["decor"]
	var idx := int(arg.get("index", -1))
	var cell := Vector2i(int(arg.get("x", -1)), int(arg.get("y", -1)))
	var why := ""
	var what := ""
	match op:
		"place":
			var did := str(arg.get("id", ""))
			if not Hideouts.CATALOG.has(did):
				why = "unknown decoration '%s'" % did
			elif dec.size() >= Hideouts.MAX_DECOR:
				why = "the hideout is full (%d/%d decorations)" % [dec.size(), Hideouts.MAX_DECOR]
			elif Hideouts.placed_count(h, did) >= int(h["owned"].get(did, 0)):
				why = "you have no unplaced %s (owned %d, placed %d)" % [Hideouts.CATALOG[did]["name"], int(h["owned"].get(did, 0)), Hideouts.placed_count(h, did)]
			else:
				why = Hideouts.blocked_reason(h, cell)
			if why == "":
				dec.append({"id": did, "x": cell.x, "y": cell.y, "rot": clampi(int(arg.get("rot", 0)), 0, 3), "flip": bool(arg.get("flip", false))})
				what = "placed %s at (%d, %d)" % [Hideouts.CATALOG[did]["name"], cell.x, cell.y]
		"move", "remove", "rotate", "flip":
			if idx < 0 or idx >= dec.size():
				why = "no decoration #%d" % idx
			elif op == "move":
				why = Hideouts.blocked_reason(h, cell, idx)
				if why == "":
					what = "moved %s #%d (%d, %d) -> (%d, %d)" % [Hideouts.CATALOG[dec[idx]["id"]]["name"], idx, int(dec[idx]["x"]), int(dec[idx]["y"]), cell.x, cell.y]
					dec[idx]["x"] = cell.x
					dec[idx]["y"] = cell.y
			elif op == "remove":
				what = "removed %s #%d (back to the decoration inventory)" % [Hideouts.CATALOG[dec[idx]["id"]]["name"], idx]
				dec.remove_at(idx)
			elif op == "rotate":
				dec[idx]["rot"] = (int(dec[idx]["rot"]) + 1) % 4
				what = "rotated %s #%d to %d deg" % [Hideouts.CATALOG[dec[idx]["id"]]["name"], idx, int(dec[idx]["rot"]) * 90]
			else:
				dec[idx]["flip"] = not bool(dec[idx]["flip"])
				what = "flipped %s #%d (flip %s)" % [Hideouts.CATALOG[dec[idx]["id"]]["name"], idx, dec[idx]["flip"]]
		"station":
			var st := str(arg.get("station", ""))
			why = Hideouts.station_reason(h, st, cell)
			if why == "":
				what = "moved the %s to (%d, %d)" % [Hideouts.STATION_NAMES[st], cell.x, cell.y]
				h["stations"][st] = [cell.x, cell.y]
		"theme":
			var t := str(arg.get("id", ""))
			if not Hideouts.THEMES.has(t):
				why = "unknown hideout theme '%s'" % t
			elif not h["unlocked"].has(t):
				why = "%s is locked (defeat the %s Guardian on the Atlas)" % [Hideouts.THEMES[t]["name"], Classes.ELEMENT_INFO.get(Hideouts.THEMES[t]["element"], {"name": "?"})["name"]]
			elif h["theme"] == t:
				why = "%s is already your theme" % Hideouts.THEMES[t]["name"]
			else:
				var kept := Hideouts.sanitize(_with_theme(h, t))
				var lost: int = dec.size() - kept["decor"].size()
				h["theme"] = t
				h["decor"] = kept["decor"]
				what = "switched the theme to %s (kept %d decorations, %d invalid removed)" % [Hideouts.THEMES[t]["name"], kept["decor"].size(), lost]
		_:
			why = "unknown request '%s'" % op
	if why != "":
		_reject(p, "hideout %s" % op, why)
		return
	_log("%s %s - %d/%d decorations" % [p.display_name, what, h["decor"].size(), Hideouts.MAX_DECOR])
	_changed(p)


func _with_theme(h: Dictionary, t: String) -> Dictionary:
	var c := h.duplicate(true)
	c["theme"] = t
	return c


func buy(p: Node, did: String, count: int) -> void:
	var at_master: bool = p.zone != null and p.zone.has_method("hideout_master_pos") and p.zone.hideout_master_pos() != Vector2.INF \
		and p.position.distance_to(p.zone.hideout_master_pos()) <= p.BLACKSMITH_RANGE
	if not at_master and not in_own_hideout(p):
		_reject(p, "buy decoration", "talk to the Hideout Master in Sunny Meadow (or shop from your hideout)")
		return
	if not Hideouts.CATALOG.has(did):
		_reject(p, "buy decoration", "unknown decoration '%s'" % did)
		return
	count = clampi(count, 1, 50)
	var cost: int = int(Hideouts.CATALOG[did]["price"]) * count
	if p.gold < cost:
		_reject(p, "buy decoration", "not enough gold (%d/%d)" % [p.gold, cost])
		return
	p.gold -= cost
	p.hideout["owned"][did] = int(p.hideout["owned"].get(did, 0)) + count
	_log("%s bought %d x %s for %d gold (gold left %d, owned %d)" % [p.display_name, count, Hideouts.CATALOG[did]["name"], cost, p.gold, p.hideout["owned"][did]])
	p.push_inventory()
	_changed(p)


## A rare decoration drop / a Guardian kill unlocking a theme (called by the dungeon code).
func grant_decoration(p: Node, did: String, why: String) -> void:
	p.hideout["owned"][did] = int(p.hideout["owned"].get(did, 0)) + 1
	_log("%s found a decoration: %s (%s) - owned %d" % [p.display_name, Hideouts.CATALOG[did]["name"], why, p.hideout["owned"][did]])
	p.notify("Hideout decoration found: %s" % Hideouts.CATALOG[did]["name"], true)
	_changed(p)


func unlock_theme(p: Node, t: String, why: String) -> void:
	if t == "" or p.hideout["unlocked"].has(t):
		return
	p.hideout["unlocked"].append(t)
	_log("%s unlocked the hideout theme %s (%s)" % [p.display_name, Hideouts.THEMES[t]["name"], why])
	p.notify("New hideout theme: %s" % Hideouts.THEMES[t]["name"], true)
	_changed(p)


func _changed(p: Node) -> void:
	var id := zone_of(p)
	if id != "":
		update_hideout.rpc(id, p.hideout)
		main.instances.refresh_portals()
	p.push_hideout()
	main.save_player_now(p)


# ================================================================ RPCs (all peers)

@rpc("authority", "call_local", "reliable")
func create_hideout(id: String, data: Dictionary) -> void:
	if main.zones.has(id):
		return
	var layout: Dictionary = data["layout"].duplicate(true)
	var def := {"name": "%s's Hideout" % str(data["owner"]), "short": "Hideout", "levels": "-", "safe": true,
		"respawn": Hideouts.ARRIVE, "slot": int(data["slot"]), "owner": str(data["owner"]), "hideout": layout,
		"portals": [{"rect": Hideouts.DOOR, "to": "meadow", "arrive": Hideouts.TOWN_ARRIVE}],
		"monsters": [], "boss": {}, "map_portal_row": 0}
	for s in Hideouts.STATIONS:
		def[s] = Hideouts.cell_of(layout["stations"][s])
	Zones.DYN[id] = def
	var z: Node = main.ZoneScript.new()
	z.setup(id, main)
	z.visible = false
	main.get_node("Zones").add_child(z)
	main.zones[id] = z
	main.instances.set_portals(main.instances._portals_cache)
	if not is_server():
		main._log("hideout %s built locally: %s" % [id, def["name"]])


@rpc("authority", "call_local", "reliable")
func update_hideout(id: String, layout: Dictionary) -> void:
	if main.zones.has(id):
		main.zones[id].apply_hideout(layout.duplicate(true))


@rpc("authority", "call_local", "reliable")
func destroy_hideout(id: String) -> void:
	if not main.zones.has(id):
		return
	var z: Node = main.zones[id]
	main.zones.erase(id)
	Zones.DYN.erase(id)
	z.queue_free()
