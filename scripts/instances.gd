extends Node
## Dungeon instances (Path-of-Exile-style maps), server-authoritative.
##
## A run = one private dynamic zone "dun<N>" created when a player opens a Dungeon
## Ticket at the Map Device. Every peer builds the instance's map from the same
## seed (create_instance RPC); the server populates it, and the usual per-zone
## visibility filters keep each run's entities visible only to the players inside.
## Runs are SOLO for now: only the opener may enter (see _may_enter - a party
## system would only have to widen that check).

const EMPTY_TIMEOUT_DEFAULT := 90.0      # an empty run closes after this long
const COMPLETE_TIMEOUT_DEFAULT := 60.0   # a finished run closes this long after the boss dies
const CLOSE_GRACE := 5.0                 # empty + no portals left -> close after this

var main: Node
var runs := {}            # id -> run (server)
var _next := 0
var _tick := 0.0
var _portals_cache: Array = []


func _ready() -> void:
	main = get_parent()


func is_server() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()


func empty_timeout() -> float:
	return main.instance_timeout if main.instance_timeout > 0.0 else EMPTY_TIMEOUT_DEFAULT


func complete_timeout() -> float:
	return main.complete_timeout if main.complete_timeout > 0.0 else COMPLETE_TIMEOUT_DEFAULT


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _log(msg: String) -> void:
	main.log_server("[dungeon] " + msg)


# ================================================================ requests (server)

func handle_request(p: Node, arg: Dictionary) -> void:
	match str(arg.get("op", "")):
		"buy":
			buy_ticket(p, str(arg.get("theme", "")), int(arg.get("tier", 0)))
		"free":
			free_ticket(p, str(arg.get("theme", "")))
		"open":
			open_run(p, int(arg.get("uid", -1)))
		"atlas_alloc":
			atlas_allocate(p, str(arg.get("id", "")))
		"atlas_respec":
			atlas_respec(p)
		"debug_kit":
			if main.debug_atlas_kit and not p.bag_full():
				var kn := str(arg.get("node", "fire:3"))
				if Atlas.node(kn).is_empty():
					_reject(p, "debug_kit", "unknown atlas node %s" % kn)
					return
				if kn != "fire:3":   # e.g. a Guardian ticket: also complete the node before it so it's available
					for a in Atlas.node(kn)["adj"]:
						if a != Atlas.PINNACLE and int(Atlas.node(a)["tier"]) < int(Atlas.node(kn)["tier"]) and not Atlas.is_done(p.atlas, a):
							p.atlas["done"][a] = 1
							main.log_server("[debug] %s: atlas node %s marked completed for the test" % [p.display_name, a])
							break
				var kt := Atlas.make_node_ticket(kn, "normal", main.rng)
				p.bag.append(kt)
				main.log_server("[debug] %s got %s for the atlas test" % [p.display_name, Gear.summary(kt)])
				p.push_inventory()
		"close":
			var r := run_of(p.account_key)
			if r.is_empty():
				_reject(p, "close", "you have no open dungeon")
			elif not r["inside"].is_empty():
				_reject(p, "close", "someone is still inside")
			else:
				_close(str(r["id"]), "closed by its owner")
		_:
			_reject(p, "dungeon", "unknown request")


func _reject(p: Node, what: String, why: String) -> void:
	main.log_server("[%s] %s %s rejected: %s" % [p.zone.zone_id if p.zone else "?", p.display_name, what, why])
	p.notify("Can't do that: " + why, true)


func _ticket_rarity_note(inst: Dictionary) -> String:
	return Gear.summary(inst)


func buy_ticket(p: Node, theme: String, tier: int) -> void:
	if not p.near_merchant():
		_reject(p, "buy ticket", "you must be at the Ticket Merchant in Sunny Meadow")
		return
	if not Dungeons.is_theme(theme):
		_reject(p, "buy ticket", "unknown dungeon '%s'" % theme)
		return
	if not Atlas.merchant_sells(p.atlas, theme, tier):
		var why := "no atlas node" if not Atlas.has_node("%s:%d" % [theme, tier]) else ("above T%d" % Atlas.MERCHANT_CAP if tier > Atlas.MERCHANT_CAP else "atlas node locked")
		_reject(p, "buy ticket", "the merchant only sells unlocked atlas nodes up to T%d (%s T%d: %s; your best here: T%d)" % [Atlas.MERCHANT_CAP, Dungeons.theme_name(theme), tier, why, Atlas.merchant_max(p.atlas, theme)])
		return
	if p.bag_full():
		_reject(p, "buy ticket", "your bag is full")
		return
	var price := Dungeons.price(tier)
	if p.gold < price:
		_reject(p, "buy ticket", "not enough gold (%d/%d)" % [p.gold, price])
		return
	p.gold -= price
	var t := Atlas.make_node_ticket("%s:%d" % [theme, tier], "normal", main.rng)
	p.bag.append(t)
	main.log_server("[%s] %s bought %s for %d gold (gold left %d)" % [p.zone.zone_id, p.display_name, Gear.summary(t), price, p.gold])
	p.notify("Bought %s" % Gear.display_name(t), true)
	p.push_inventory()


func today() -> String:
	return Time.get_date_string_from_system()


func free_ticket(p: Node, theme: String) -> void:
	if not p.near_merchant():
		_reject(p, "free ticket", "you must be at the Ticket Merchant in Sunny Meadow")
		return
	if p.free_day == today():
		_reject(p, "free ticket", "you already took today's free ticket")
		return
	if p.bag_full():
		_reject(p, "free ticket", "your bag is full")
		return
	if not Dungeons.is_theme(theme):
		theme = Dungeons.ORDER[main.rng.randi() % Dungeons.ORDER.size()]
	# Vo Lam style daily gift: a Magic ticket of your best unlocked merchant tier
	var t := Atlas.make_node_ticket("%s:%d" % [theme, Atlas.merchant_max(p.atlas, theme)], "magic", main.rng)
	t["bound"] = true     # free gifts are account-bound (can't be sold on the market)
	p.free_day = today()
	p.bag.append(t)
	main.log_server("[%s] %s took the daily free ticket: %s" % [p.zone.zone_id, p.display_name, Gear.summary(t)])
	p.notify("Daily gift: %s" % Gear.display_name(t), true)
	p.push_inventory()


func run_of(account_key: String) -> Dictionary:
	for id in runs:
		if runs[id]["owner_key"] == account_key:
			return runs[id]
	return {}


func run_info_for(account_key: String) -> Dictionary:
	var r := run_of(account_key)
	if r.is_empty():
		return {}
	return {"id": r["id"], "name": Zones.info(r["id"])["name"], "portals": r["portals"], "completed": r["completed"],
		"iiq": r["iiq"], "iir": r["iir"], "mods": r["mods"], "inside": r["inside"].size(), "node": r["node"]}


func open_run(p: Node, uid: int) -> void:
	if not p.near_map_device():
		_reject(p, "open dungeon", "you must be at a Map Device (Sunny Meadow or your hideout)")
		return
	if not run_of(p.account_key).is_empty():
		_reject(p, "open dungeon", "you already have an open dungeon (%s)" % run_of(p.account_key)["id"])
		return
	var bi: int = p.find_bag(uid)
	if bi < 0:
		_reject(p, "open dungeon", "ticket %d is not in your bag" % uid)
		return
	var t: Dictionary = p.bag[bi]
	if not Dungeons.is_ticket(t):
		_reject(p, "open dungeon", "%s is not a Dungeon Ticket" % Gear.display_name(t))
		return
	var nid := Atlas.node_of_ticket(t)
	var unique: bool = t.get("rarity") == "unique"
	if not unique and not Atlas.is_available(p.atlas, nid):
		_reject(p, "open dungeon", "atlas node %s is locked (complete an adjacent node first)" % Atlas.display(nid))
		return
	if runs.size() >= 24:
		_reject(p, "open dungeon", "the server is full of open dungeons, try again later")
		return
	p.bag.remove_at(bi)
	var ri := Dungeons.run_info(t)
	_next += 1
	var id := "dun%d" % _next
	var slot := _free_slot()
	# a node has its own fixed layout seed (unique tickets roll a random one)
	var seed: int = main.rng.randi() if unique else int(Atlas.node(nid)["seed"])
	var theme := Dungeons.theme_of(t)
	var afx := Atlas.run_effects(p.atlas, theme)
	var portals := Dungeons.PORTALS + int(afx["portals"])
	var data := {"theme": theme, "tier": Dungeons.tier_of(t), "seed": seed, "slot": slot, "mods": ri["mods"],
		"owner": p.display_name, "iiq": ri["iiq"], "iir": ri["iir"], "node": "" if unique else nid, "afx": afx,
		"origin": p.zone.zone_id}   # the dungeon's exit portal / death return lead back here (town or hideout)
	create_instance.rpc(id, data)    # (call_local: the server builds it too)
	var z: Node = main.zones[id]
	z.spawn_dungeon()
	runs[id] = {"id": id, "owner_key": p.account_key, "owner": p.display_name, "theme": data["theme"], "tier": data["tier"],
		"portals": portals, "node": data["node"], "rarity": str(t.get("rarity", "normal")), "deaths": 0, "afx": afx,
		"elites_total": int(z.elite_total), "elites_killed": 0, "inside": {}, "completed": false, "completed_at": 0.0, "created": _now(),
		"empty_since": _now(), "iiq": ri["iiq"], "iir": ri["iir"], "mods": ri["mods"], "ticket": Gear.summary(t),
		"pslot": _free_portal_slot(), "closing": false, "origin": p.zone.zone_id}
	_log("%s opened a map from %s (portal there, the exit portal returns there)" % [p.display_name, p.zone.zone_id])
	_log("%s opened %s with %s -> instance %s (seed %d, slot %d): %d portals, iiq +%d%% iir +%d%%, mods %s | atlas node %s, atlas passives %s" % [p.display_name,
		Dungeons.theme_name(data["theme"]), Gear.summary(t), id, seed, slot, portals, roundi(ri["iiq"]), roundi(ri["iir"]), ri["mods"],
		Atlas.display(nid) if not unique else "(unique ticket: any node)", _fx_str(afx)])
	p.notify("A portal to %s opens above the Map Device (%d portals)" % [Zones.info(id)["name"], portals], true)
	_broadcast_portals()
	p.push_inventory()


func _free_slot() -> int:
	var used := {}
	for id in Zones.DYN:
		used[Zones.dyn_slot(id)] = true
	var s := 0
	while used.has(s):
		s += 1
	return s


func _free_portal_slot() -> int:
	var used := {}
	for id in runs:
		used[int(runs[id]["pslot"])] = true
	var s := 0
	while used.has(s):
		s += 1
	return s


## Solo runs: only the opener. (A party system would add its members here.)
func _may_enter(p: Node, r: Dictionary) -> bool:
	return p.account_key == r["owner_key"]


func try_enter(p: Node, id: String) -> void:
	if not is_instance_valid(p) or p.is_queued_for_deletion() or p.dead or not runs.has(id):
		return
	var r: Dictionary = runs[id]
	if r["closing"]:
		return
	if not _may_enter(p, r):
		p.notify("That portal belongs to %s (dungeon runs are solo)" % r["owner"], false)
		main.log_server("[meadow] %s can't enter %s: owned by %s" % [p.display_name, id, r["owner"]])
		return
	if int(r["portals"]) <= 0:
		p.notify("No portals left in this dungeon", true)
		_log("%s can't enter %s: no portals left" % [p.display_name, id])
		return
	r["portals"] = int(r["portals"]) - 1
	r["inside"][p.peer_id] = true
	var d: Dictionary = Zones.info(id)
	_log("%s entered %s (%s) - portals left %d" % [p.display_name, id, d["name"], r["portals"]])
	main.transfer_player(p, id, d["respawn"])
	_broadcast_portals()
	_announce(id, d["name"], "Monster level %s  -  %d portals left" % [d["levels"], r["portals"]])


func player_died(p: Node) -> void:
	if not is_instance_valid(p) or p.is_queued_for_deletion() or not p.zone.is_dungeon():
		return
	var id: String = p.zone.zone_id
	var left := int(runs[id]["portals"]) if runs.has(id) else 0
	if runs.has(id):
		runs[id]["deaths"] = int(runs[id]["deaths"]) + 1
	_log("%s died in %s - back to %s (portals left %d)" % [p.display_name, id, "the hideout" if Zones.is_hideout(return_of(id)[0]) else "town", left])
	var back := return_of(id)
	p.notify("You died - back %s. Re-entering uses a portal (%d left)." % ["in your hideout" if Zones.is_hideout(back[0]) else "in town", left], true)
	main.transfer_player(p, back[0], back[1])


## Called by Main.transfer_player for every zone change (keeps "who is inside" exact).
func on_transfer(peer_id: int, from: String, to: String) -> void:
	if runs.has(from) and from != to:
		runs[from]["inside"].erase(peer_id)
		if runs[from]["inside"].is_empty():
			runs[from]["empty_since"] = _now()
	if runs.has(to):
		runs[to]["inside"][peer_id] = true


func on_peer_left(peer_id: int) -> void:
	for id in runs:
		if runs[id]["inside"].has(peer_id):
			runs[id]["inside"].erase(peer_id)
			if runs[id]["inside"].is_empty():
				runs[id]["empty_since"] = _now()


# ================================================================ completion

func on_monster_died(zone: Node, m: Node, killer: Node) -> void:
	var id: String = zone.zone_id
	if not runs.has(id) or runs[id]["completed"]:
		return
	var r: Dictionary = runs[id]
	if str(m.get("elite")) != "" and m.get("elite") != null:
		r["elites_killed"] = int(r["elites_killed"]) + 1
	if not m.def.get("dungeon", false):
		return
	r["completed"] = true
	r["completed_at"] = _now()
	var tier := int(r["tier"])
	var afx: Dictionary = r["afx"]
	var iir: float = float(r["iir"]) + (killer.tm("item_rarity") if is_instance_valid(killer) else 0.0)
	var nid: String = str(r["node"]) if str(r["node"]) != "" else Atlas.snap(str(r["theme"]), tier)
	# boss: guaranteed ticket that favours an ADJACENT node (sustain loop); 30% (+boss loot) a second one
	var tickets: Array = []
	var adj_p: float = main.debug_next_tier if main.debug_next_tier >= 0.0 else 0.65
	var t_nodes: Array = [Atlas.boss_ticket_node(nid, main.rng, adj_p, main.debug_next_tier >= 0.0)]
	if main.rng.randf() < 0.3 * (1.0 + float(afx.get("boss", 0.0)) / 100.0):
		t_nodes.append(Atlas.boss_ticket_node(nid, main.rng, adj_p))
	if main.rng.randf() < float(afx.get("boss", 0.0)) / 100.0:
		t_nodes.append(Atlas.boss_ticket_node(nid, main.rng, 1.0))
	for tn in t_nodes:
		var tk := Dungeons.roll_ticket(int(Atlas.node(tn)["tier"]), iir, main.rng, str(Atlas.node(tn)["theme"]))
		if tk.get("rarity") != "unique":
			tk["node"] = tn
		tickets.append(tk)
	if nid == Atlas.PINNACLE and str(r["node"]) != "":
		# Ngu Hanh pinnacle: two guaranteed uniques
		var ukeys: Array = Items.UNIQUES.keys().filter(func(k): return not str(Items.UNIQUES[k].get("base", "")).begins_with("ticket_"))
		for k in 2:
			var u := Gear.make_unique(str(ukeys[main.rng.randi() % ukeys.size()]), 40, main.rng)
			tickets.append(u)
	var names: Array = []
	for t in tickets:
		zone.spawn_pickup(str(t["base"]), 1, m.position, t)
		names.append(Gear.summary(t))
	# atlas progress (owner, even if someone else landed the kill): first completion + bonus objective = atlas points
	var bonus_ok := Atlas.bonus_met(nid, r) if str(r["node"]) != "" else false
	var owner := _player_by_key(str(r["owner_key"]))
	var a: Dictionary
	if owner:
		a = owner.atlas
	else:
		var acc: Dictionary = main.accounts.get_account(str(r["owner_key"]))
		a = Dungeons.sanitize_atlas(acc.get("character", {}).get("atlas", {})) if not acc.is_empty() else {}
	var gained: Array = []
	if not a.is_empty() and str(r["node"]) != "":
		if not a["done"].has(nid):
			gained.append("first completion +1")
		a["done"][nid] = int(a["done"].get(nid, 0)) + 1
		if bonus_ok and not a["bonus"].has(nid):
			a["bonus"][nid] = true
			gained.append("bonus objective +1")
		if owner:
			owner.push_atlas()
			main.save_player_now(owner)
		else:
			var acc2: Dictionary = main.accounts.get_account(str(r["owner_key"]))
			acc2["character"]["atlas"] = a
			main.accounts.save_file()
	_log("%s COMPLETED %s T%d (boss %s slain by %s) - tickets dropped: %s | atlas %s: %s (bonus +%d%% iiq, merchant now sells up to T%d)" % [id,
		Dungeons.theme_name(r["theme"]), tier, m.display_name, killer.display_name if is_instance_valid(killer) else "?", ", ".join(names),
		r["owner"], a.get("done", {}), roundi(Dungeons.atlas_iiq(a)), Atlas.merchant_max(a, r["theme"]) if not a.is_empty() else 1])
	if str(r["node"]) != "":
		var tn_txt: Array = []
		for tn in t_nodes:
			tn_txt.append("%s%s" % [tn, " (adjacent)" if Atlas.adjacent(nid).has(tn) else " (same node)"])
		_log("atlas node %s completed by %s: bonus objective '%s' %s (rarity %s, deaths %d, elites %d/%d); points %s -> %d earned, %d free; boss tickets for nodes %s" % [
			nid, r["owner"], Atlas.node(nid)["bonus"], "MET" if bonus_ok else "missed", r["rarity"], int(r["deaths"]), int(r["elites_killed"]), int(r["elites_total"]),
			gained if not gained.is_empty() else "none (already earned)", Atlas.points_earned(a), Atlas.points_free(a), tn_txt])
	# hideout rewards: a Guardian unlocks its element's hideout theme; rare decoration drop
	if owner and main.hideouts:
		if str(r["node"]) != "" and bool(Atlas.node(nid).get("guardian", false)) and Hideouts.THEMES.has(str(r["theme"])):
			main.hideouts.unlock_theme(owner, str(r["theme"]), "slew the %s" % Atlas.node(nid)["name"])
		var dchance: float = main.decor_drop_chance if main.decor_drop_chance >= 0.0 else (1.0 if main.hideout_debug else Hideouts.BOSS_DECOR_CHANCE)
		if main.rng.randf() < dchance:
			var dk: Array = Hideouts.CATALOG.keys()
			main.hideouts.grant_decoration(owner, str(dk[main.rng.randi() % dk.size()]), "dungeon boss drop")
	main.broadcast_system("%s completed %s!" % [r["owner"], Zones.info(id)["name"]])
	_announce(id, "Dungeon Complete!", "%s cleared  -  the instance closes in %ds" % [Zones.info(id)["name"], roundi(complete_timeout())])
	_broadcast_portals()


func _fx_str(afx: Dictionary) -> String:
	var parts: Array = []
	for k in afx:
		if float(afx[k]) != 0.0:
			parts.append("%s %s" % [k, str(snappedf(float(afx[k]), 0.1))])
	return "{" + ", ".join(parts) + "}"


# ================================================================ atlas passive tree (server)

func atlas_allocate(p: Node, pid: String) -> void:
	var why := Atlas.can_allocate(p.atlas, pid)
	if why != "":
		_reject(p, "atlas passive %s" % pid, why)
		return
	p.atlas["passives"].append(pid)
	var pd: Dictionary = Atlas.passives()[pid]
	main.log_server("[%s] %s allocated atlas passive %s [%s] (%s) - %d/%d atlas points spent, effects now %s" % [p.zone.zone_id, p.display_name,
		pd["name"], pid, Atlas.fx_text(pd["fx"]).replace("\n", "; "), Atlas.points_spent(p.atlas), Atlas.points_earned(p.atlas), Atlas.effects(p.atlas)])
	p.notify("Atlas passive: %s" % pd["name"], true)
	p.push_atlas()
	main.save_player_now(p)


func atlas_respec(p: Node) -> void:
	var n := Atlas.points_spent(p.atlas)
	if n == 0:
		_reject(p, "atlas respec", "no atlas passives allocated")
		return
	var cost := Atlas.respec_cost(p.atlas)
	if p.gold < cost:
		_reject(p, "atlas respec", "not enough gold (%d/%d)" % [p.gold, cost])
		return
	p.gold -= cost
	p.atlas["passives"] = []
	main.log_server("[%s] %s reset the atlas passive tree: refunded %d points for %d gold (gold left %d, %d free points)" % [p.zone.zone_id, p.display_name,
		n, cost, p.gold, Atlas.points_free(p.atlas)])
	p.notify("Atlas passives reset (%d gold)" % cost, true)
	p.push_atlas()
	p.push_inventory()
	main.save_player_now(p)


func _player_by_key(k: String) -> Node:
	for p in main.all_players():
		if p.account_key == k:
			return p
	return null


func _announce(id: String, title: String, sub: String) -> void:
	if not main.zones.has(id):
		return
	for pid in main.zones[id].peers():
		dungeon_banner.rpc_id(pid, title, sub)


# ================================================================ lifetime / cleanup (server)

func _process(delta: float) -> void:
	if not is_server() or runs.is_empty():
		return
	_tick += delta
	if _tick < 1.0:
		return
	_tick = 0.0
	var now := _now()
	for id in runs.keys():
		var r: Dictionary = runs[id]
		if r["closing"]:
			continue
		# drop peers whose node is gone (disconnects)
		var z: Node = main.zones[id]
		var present := {}
		for p in z.players_root.get_children():
			present[p.peer_id] = true
		for pid in r["inside"].keys():
			if not present.has(pid) and main.peer_zone.get(pid, "") != id:
				r["inside"].erase(pid)
				r["empty_since"] = now
		var empty: bool = r["inside"].is_empty()
		var why := ""
		if r["completed"] and now - float(r["completed_at"]) >= complete_timeout():
			why = "completion timeout"
		elif empty and int(r["portals"]) <= 0 and now - float(r["empty_since"]) >= CLOSE_GRACE:
			why = "no portals left"
		elif empty and now - float(r["empty_since"]) >= empty_timeout():
			why = "empty for %ds" % roundi(empty_timeout())
		if why != "":
			_close(id, why)


func _close(id: String, why: String) -> void:
	var r: Dictionary = runs[id]
	r["closing"] = true
	var z: Node = main.zones[id]
	var kicked := 0
	for p in z.players_root.get_children():
		if not p.is_queued_for_deletion():
			p.notify("The dungeon collapses - back to where you opened it", true)
			var back := return_of(id)
			main.transfer_player(p, back[0], back[1])
			kicked += 1
	_log("closing %s (%s, %s T%d, owner %s): %s, %d player(s) sent to town, %d monsters left" % [id, Zones.info(id)["name"],
		Dungeons.theme_name(r["theme"]), int(r["tier"]), r["owner"], why, kicked, z.monsters_root.get_child_count()])
	runs.erase(id)
	_broadcast_portals()
	var owner := _player_by_key(str(r["owner_key"]))
	if owner:
		owner.push_atlas()
	get_tree().create_timer(1.5).timeout.connect(func():
		destroy_instance.rpc(id)
		_log("instance %s destroyed (open instances: %d, zones: %d)" % [id, runs.size(), main.zones.size()]))


# ================================================================ town portals

## [zone id, arrive cell] a run's players return to: where it was opened (town or a hideout).
func return_of(id: String) -> Array:
	var o := str(runs[id].get("origin", "meadow")) if runs.has(id) else "meadow"
	if Zones.is_hideout(o) and main.zones.has(o):
		return [o, Hideouts.ARRIVE]
	return ["meadow", Zones.TOWN_ARRIVE]


func _portal_list() -> Array:
	var out: Array = []
	for id in runs:
		var r: Dictionary = runs[id]
		var oz := str(r.get("origin", "meadow"))
		if not main.zones.has(oz):
			oz = "meadow"
		var town: Node = main.zones[oz]
		var base: Vector2i = town.info["map_device"]
		var k := int(r["pslot"])
		var cell: Vector2i
		if Zones.is_hideout(oz):   # one run per account: right below its hideout's device
			cell = base + Vector2i(0, 2)
		else:
			cell = Vector2i(base.x - 4 + (k % 5) * 2, int(town.info["map_portal_row"]) - (k / 5) * 2)
		out.append({"id": id, "zone": oz, "pos": town.map.cell_pos(cell), "owner": r["owner"],
			"text": "%s\n%s - %d portal%s%s" % [Zones.info(id)["name"], r["owner"], r["portals"], "" if int(r["portals"]) == 1 else "s", "  (done)" if r["completed"] else ""]})
	return out


func _broadcast_portals() -> void:
	_portals_cache = _portal_list()
	set_portals.rpc(_portals_cache)


## Late joiners: every open instance (so its zone exists before they could enter) + the portals.
func sync_peer(pid: int) -> void:
	for id in runs:
		var d: Dictionary = Zones.info(id)["dungeon"]
		create_instance.rpc_id(pid, id, {"theme": d["theme"], "tier": d["tier"], "seed": d["seed"], "slot": d["slot"],
			"mods": d["mods"], "owner": d["owner"], "iiq": d["iiq"], "iir": d["iir"], "node": d.get("node", ""), "afx": d.get("afx", {}),
			"origin": str(runs[id].get("origin", "meadow"))})
	set_portals.rpc_id(pid, _portals_cache)


# ================================================================ RPCs (all peers)

@rpc("authority", "call_local", "reliable")
func create_instance(id: String, data: Dictionary) -> void:
	if main.zones.has(id):
		return
	var def := Dungeons.make_def(id, str(data["theme"]), int(data["tier"]), int(data["seed"]), int(data["slot"]), data["mods"], str(data["owner"]))
	def["dungeon"]["iiq"] = float(data["iiq"])
	def["dungeon"]["iir"] = float(data["iir"])
	def["dungeon"]["node"] = str(data.get("node", ""))
	def["dungeon"]["afx"] = data.get("afx", {})
	var origin := str(data.get("origin", "meadow"))
	if Zones.is_hideout(origin):
		def["dungeon"]["origin"] = origin
		def["portals"][0]["to"] = origin
		def["portals"][0]["arrive"] = Hideouts.ARRIVE
	Zones.DYN[id] = def
	var z: Node = main.ZoneScript.new()
	z.setup(id, main)
	z.visible = false
	main.get_node("Zones").add_child(z)
	main.zones[id] = z
	if not is_server():
		main._log("instance %s built locally: %s (seed %d)" % [id, def["name"], int(data["seed"])])


@rpc("authority", "call_local", "reliable")
func destroy_instance(id: String) -> void:
	if not main.zones.has(id):
		return
	var z: Node = main.zones[id]
	main.zones.erase(id)
	Zones.DYN.erase(id)
	z.queue_free()
	if not is_server():
		main._log("instance %s removed locally" % id)


@rpc("authority", "call_local", "reliable")
func set_portals(list: Array) -> void:
	_portals_cache = list
	for zid in main.zones:
		var z: Node = main.zones[zid]
		if z.map_portal_root != null:
			z.set_map_portals(list.filter(func(e): return str(e.get("zone", "meadow")) == zid))


func refresh_portals() -> void:
	if is_server():
		_broadcast_portals()


@rpc("authority", "call_local", "reliable")
func dungeon_banner(title: String, sub: String) -> void:
	main.show_banner(title, sub)
