extends Node
## Trade market (Trade Broker in Sunny Meadow), server-authoritative.
##
## Asynchronous auction house: sellers list an item for a gold price (paying a
## listing fee); the item moves out of their bag into escrow (the market data).
## Buyers buy out instantly; the seller's gold (minus the sales tax) goes to the
## seller's CLAIM BOX, collected at the broker - so sellers don't need to be online.
## Expired / cancelled listings also go back through the claim box (cancel goes
## straight to the bag when there is room).
##
## Safety:
##  * every request runs on the server's main thread, one after another, so a
##    listing can only be bought once (the second buyer finds it gone);
##  * the market (escrow listings, claim boxes, history) is saved to its own file,
##    user://volam_save/market.json (next to accounts.json; for a custom
##    --save-file X.json it is X_market.json, or --market-file=PATH). Every trade is
##    committed immediately: market.json is written first (temp file + rename)
##    together with a JOURNAL of the post-trade characters involved and a
##    transaction number, then accounts.json (stamped with the same number).
##    If the server dies between the two writes, the next start sees
##    accounts.json behind market.json and replays the journal, so an item is
##    never both in escrow and in a bag (no duplication) and gold is never taken
##    without delivering the item.

const BROKER_RANGE := 100.0

var main: Node
var data := {}             # server: Market.sanitize_data(...)
var path := ""             # server: market.json
var tx := 0                # server: last committed market transaction
var _tick := 0.0

# client side: last results from the server (the panel reads these)
var page: Dictionary = {"rows": [], "total": 0, "page": 0, "pages": 1}
var mine: Dictionary = {"listings": [], "claims": {"gold": 0, "items": [], "stacks": {}}, "history": []}
signal page_changed
signal mine_changed


func _ready() -> void:
	main = get_parent()


func is_server() -> bool:
	return multiplayer.has_multiplayer_peer() and multiplayer.is_server()


func _now() -> int:
	return int(Time.get_unix_time_from_system())


func _log(msg: String) -> void:
	main.log_server("[market] " + msg)


func duration(key := "") -> int:
	if main.market_short != "" and key.begins_with(main.market_short.to_lower()):
		return 15      # (test) these accounts' listings expire after 15 s
	return main.market_duration if main.market_duration > 0 else Market.DURATION


func max_listings() -> int:
	return main.market_max_listings if main.market_max_listings > 0 else Market.MAX_LISTINGS


static func path_for(save_file: String) -> String:
	if save_file == "user://volam_save/accounts.json":
		return "user://volam_save/market.json"
	return save_file.get_basename() + "_market.json"


## Server start: load market.json (validated), replay a half-committed trade.
func load_from(store: AccountStore) -> void:
	path = main.market_file if main.market_file != "" else path_for(store.path)
	var raw: Variant = {}
	if FileAccess.file_exists(path):
		raw = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(raw) != TYPE_DICTIONARY:
			push_warning("market file %s is unreadable - starting an empty market" % path)
			raw = {}
	elif store.data.has("market"):
		raw = store.data["market"]       # (saves from the in-progress build kept the market inside accounts.json)
		_log("migrating the market out of accounts.json")
	store.data.erase("market")
	data = Market.sanitize_data(raw)
	tx = int(raw.get("tx", 0)) if typeof(raw) == TYPE_DICTIONARY else 0
	var acc_tx := int(store.data.get("market_tx", 0))
	if acc_tx < tx and typeof(raw.get("journal")) == TYPE_DICTIONARY:
		# crashed between writing market.json and accounts.json: finish the commit
		var names: Array = []
		for k in raw["journal"]:
			var acc: Dictionary = store.data["accounts"].get(str(k), {})
			if not acc.is_empty() and typeof(raw["journal"][k]) == TYPE_DICTIONARY:
				acc["character"] = raw["journal"][k]
				names.append(str(k))
		store.data["market_tx"] = tx
		store.save_file()
		_log("recovered: accounts.json was at tx %d, market at tx %d - replayed the journal for %s" % [acc_tx, tx, names])
	store.data["market_tx"] = tx
	_log("loaded %s: %d active listing(s), %d claim box(es), next id %d, tx %d" % [path.get_file(), data["listings"].size(), data["claims"].size(), data["next_id"], tx])


func _write_market(journal: Dictionary) -> bool:
	var out := data.duplicate()
	out["version"] = 1
	out["tx"] = tx
	out["journal"] = journal
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Could not write %s" % tmp)
		return false
	f.store_string(JSON.stringify(out, "\t"))
	f.close()
	var dir := DirAccess.open(path.get_base_dir())
	if FileAccess.file_exists(path):
		dir.remove(path.get_file())
	return dir.rename(tmp.get_file(), path.get_file()) == OK


## Commit a market change: market.json (+ journal of the players involved), then
## accounts.json - see the header comment.
func _commit(players: Array, why: String) -> void:
	tx += 1
	var journal := {}
	for p in players:
		if p and is_instance_valid(p) and p.account_key != "":
			main._save_player(p)
			journal[p.account_key] = main.accounts.get_account(p.account_key)["character"]
	var ok_m := _write_market(journal)
	if main.market_crash_test != "" and why.begins_with(main.market_crash_test):
		_log("CRASH TEST: dying between market.json (tx %d) and accounts.json" % tx)
		OS.kill(OS.get_process_id())
		return
	main.accounts.data["market_tx"] = tx
	var ok_a: bool = main.accounts.save_file()
	_log("committed tx %d (%s)%s" % [tx, why, "" if ok_m and ok_a else " SAVE FAILED"])


func _claims(key: String) -> Dictionary:
	if not data["claims"].has(key):
		data["claims"][key] = {"gold": 0, "items": [], "stacks": {}}
	return data["claims"][key]


func _history(key: String, entry: Dictionary) -> void:
	if not data["history"].has(key):
		data["history"][key] = []
	entry["t"] = _now()
	data["history"][key].append(entry)
	if data["history"][key].size() > Market.HISTORY_MAX:
		data["history"][key] = data["history"][key].slice(-Market.HISTORY_MAX)


func _player_by_key(k: String) -> Node:
	for p in main.all_players():
		if p.account_key == k:
			return p
	return null


func _find(id: int) -> int:
	for i in data["listings"].size():
		if int(data["listings"][i]["id"]) == id:
			return i
	return -1


func count_listings(key: String) -> int:
	var n := 0
	for l in data["listings"]:
		if l["seller"] == key:
			n += 1
	return n


func _reject(p: Node, what: String, why: String) -> void:
	main.log_server("[%s] %s %s rejected: %s" % [p.zone.zone_id if p.zone else "?", p.display_name, what, why])
	p.notify("Can't do that: " + why, true)


# ================================================================ requests (server)

func handle_request(p: Node, arg: Dictionary) -> void:
	var op := str(arg.get("op", ""))
	if op != "browse" and op != "mine" and not p.near_broker():
		_reject(p, "market " + op, "you must be at the Trade Broker in Sunny Meadow")
		return
	match op:
		"browse":
			browse(p, arg.get("filters", {}))
		"mine":
			push_mine(p)
		"list":
			list_item(p, arg)
		"cancel":
			cancel(p, int(arg.get("id", -1)))
		"buy":
			buy(p, int(arg.get("id", -1)), int(arg.get("price", -1)))
		"claim":
			claim(p)
		_:
			_reject(p, "market", "unknown request")


func browse(p: Node, filters: Variant) -> void:
	var f := Market.sanitize_filters(filters)
	var res := Market.search(data["listings"], f, p.class_id, p.account_key)
	main.log_server("[market] %s searched %s -> %d hit(s): %s" % [p.display_name, _filter_text(f), res["total"],
		", ".join(res["rows"].map(func(l): return "#%d %s @%d" % [l["id"], Market.item_summary(l["item"]), l["price"]]))])
	if p._owner_connected():
		client_page.rpc_id(p.peer_id, res)


func _filter_text(f: Dictionary) -> String:
	var parts: Array = []
	var dflt := Market.sanitize_filters({})
	for k in f:
		if f[k] != dflt[k]:
			parts.append("%s=%s" % [k, f[k]])
	return "{%s}" % " ".join(parts)


func list_item(p: Node, arg: Dictionary) -> void:
	var price := int(arg.get("price", 0))
	if price < 1 or price > Market.MAX_PRICE:
		_reject(p, "list", "price must be 1-%d gold" % Market.MAX_PRICE)
		return
	var item := {}
	var bag_i := -1
	if arg.has("stack"):
		var id := str(arg["stack"])
		var n := int(arg.get("n", 0))
		var have := int(p.inventory.get(id, 0))
		if n < 1 or have < n:
			_reject(p, "list", "you don't have %d x %s" % [n, id])
			return
		item = {"stack": id, "n": n}
	else:
		bag_i = p.find_bag(int(arg.get("uid", -1)))
		if bag_i < 0:
			_reject(p, "list", "item not in your bag (unequip it first)")
			return
		item = p.bag[bag_i]
	var why := Market.tradeable_reason(item)
	if why != "":
		_reject(p, "list", why)
		return
	if count_listings(p.account_key) >= max_listings():
		_reject(p, "list", "you already have %d active listings (max %d)" % [count_listings(p.account_key), max_listings()])
		return
	var f := Market.fee(price)
	if p.gold < f:
		_reject(p, "list", "the listing fee is %d gold (you have %d)" % [f, p.gold])
		return
	# take it out of the bag into escrow
	p.gold -= f
	if Market.is_stack(item):
		var left: int = int(p.inventory[item["stack"]]) - int(item["n"])
		if left <= 0:
			p.inventory.erase(item["stack"])
		else:
			p.inventory[item["stack"]] = left
	else:
		p.bag.remove_at(bag_i)
	var now := _now()
	var l := {"id": int(data["next_id"]), "seller": p.account_key, "seller_name": p.display_name, "price": price,
		"created": now, "expires": now + duration(p.account_key), "item": item}
	data["next_id"] = int(data["next_id"]) + 1
	data["listings"].append(l)
	_commit([p], "list #%d" % l["id"])
	_log("%s listed #%d %s for %d gold (fee %d, gold left %d, active listings %d/%d, expires in %ds)" % [p.display_name, l["id"],
		Market.item_summary(item), price, f, p.gold, count_listings(p.account_key), max_listings(), duration(p.account_key)])
	p.notify("Listed %s for %d gold (fee %d)" % [Market.item_name(item), price, f], true)
	p.push_inventory()
	push_mine(p)


func buy(p: Node, id: int, expect_price: int) -> void:
	var i := _find(id)
	if i < 0:
		_reject(p, "buy #%d" % id, "that listing is gone (sold, cancelled or expired)")
		return
	var l: Dictionary = data["listings"][i]
	if l["seller"] == p.account_key:
		_reject(p, "buy #%d" % id, "you can't buy your own listing (cancel it instead)")
		return
	var price := int(l["price"])
	if expect_price >= 0 and expect_price != price:
		_reject(p, "buy #%d" % id, "the price changed")
		return
	if p.gold < price:
		_reject(p, "buy #%d" % id, "not enough gold (%d/%d)" % [p.gold, price])
		return
	var item: Dictionary = l["item"]
	var stack_fits: bool = Market.is_stack(item) and p.inventory.has(item["stack"])
	if not stack_fits and p.bag_full():
		_reject(p, "buy #%d" % id, "your bag is full")
		return
	# --- the trade (no awaits in here: nothing else can run in between)
	data["listings"].remove_at(i)
	p.gold -= price
	if Market.is_stack(item):
		p.inventory[item["stack"]] = int(p.inventory.get(item["stack"], 0)) + int(item["n"])
	else:
		while p.find_bag(int(item["uid"])) >= 0 or p.find_equipped(int(item["uid"])) != "":
			item["uid"] = Gear.new_uid(main.rng)      # (30-bit random uids: just in case)
		p.bag.append(item)
	var t := Market.tax(price)
	var net := price - t
	var c := _claims(l["seller"])
	c["gold"] = int(c["gold"]) + net
	_history(l["seller"], {"kind": "sold", "what": Market.item_name(item), "price": price, "net": net, "buyer": p.display_name})
	_history(p.account_key, {"kind": "bought", "what": Market.item_name(item), "price": price, "seller": l["seller_name"]})
	var seller := _player_by_key(l["seller"])
	_log("%s bought #%d %s from %s for %d gold (tax %d, seller gets %d into the claim box; buyer gold left %d; seller %s)" % [
		p.display_name, id, Market.item_summary(item), l["seller_name"], price, t, net, p.gold, "online" if seller else "offline"])
	_commit([p, seller], "buy #%d" % id)
	p.notify("Bought %s for %d gold" % [Market.item_name(item), price], true)
	p.push_inventory()
	push_mine(p)
	if seller:
		seller.notify("[Market] Your %s sold to %s for %d gold (%d after %d%% tax) - collect it at the Trade Broker" % [
			Market.item_name(item), p.display_name, price, net, roundi(Market.TAX_PCT)], true)
		push_mine(seller)


func cancel(p: Node, id: int) -> void:
	var i := _find(id)
	if i < 0 or data["listings"][i]["seller"] != p.account_key:
		_reject(p, "cancel #%d" % id, "no such listing of yours")
		return
	var l: Dictionary = data["listings"][i]
	data["listings"].remove_at(i)
	var item: Dictionary = l["item"]
	var where := _give_or_claim(p, item)
	_history(p.account_key, {"kind": "cancelled", "what": Market.item_name(item), "price": int(l["price"])})
	_commit([p], "cancel #%d" % id)
	_log("%s cancelled #%d %s -> %s" % [p.display_name, id, Market.item_summary(item), where])
	p.notify("Listing cancelled: %s returned to your %s" % [Market.item_name(item), where], true)
	p.push_inventory()
	push_mine(p)


## Into the bag if there is room, else into the claim box.
func _give_or_claim(p: Node, item: Dictionary) -> String:
	if Market.is_stack(item):
		if p.inventory.has(item["stack"]) or not p.bag_full():
			p.inventory[item["stack"]] = int(p.inventory.get(item["stack"], 0)) + int(item["n"])
			return "bag"
	elif not p.bag_full():
		p.bag.append(item)
		return "bag"
	_to_claims(p.account_key, item)
	return "claim box"


func _to_claims(key: String, item: Dictionary) -> void:
	var c := _claims(key)
	if Market.is_stack(item):
		c["stacks"][item["stack"]] = int(c["stacks"].get(item["stack"], 0)) + int(item["n"])
	else:
		c["items"].append(item)


func claim(p: Node) -> void:
	if not data["claims"].has(p.account_key):
		_reject(p, "claim", "your claim box is empty")
		return
	var c: Dictionary = data["claims"][p.account_key]
	var g := int(c["gold"])
	p.gold += g
	c["gold"] = 0
	var got: Array = []
	var keep: Array = []
	for it in c["items"]:
		if p.bag_full():
			keep.append(it)
		else:
			p.bag.append(it)
			got.append(Gear.summary(it))
	c["items"] = keep
	for id in c["stacks"].keys():
		if p.inventory.has(id) or not p.bag_full():
			p.inventory[id] = int(p.inventory.get(id, 0)) + int(c["stacks"][id])
			got.append("%d x %s" % [c["stacks"][id], id])
			c["stacks"].erase(id)
	var left: int = keep.size() + c["stacks"].size()
	if left == 0:
		data["claims"].erase(p.account_key)
	if g == 0 and got.is_empty():
		_reject(p, "claim", "your bag is full")
		return
	_commit([p], "claim")
	_log("%s claimed %d gold and %d item(s) [%s] from the claim box (gold now %d, %d item(s) left in the box)" % [p.display_name, g, got.size(),
		", ".join(got), p.gold, left])
	p.notify("Collected %d gold and %d item(s) from the Trade Broker%s" % [g, got.size(), "" if left == 0 else " (bag full: %d left)" % left], true)
	p.push_inventory()
	push_mine(p)


func push_mine(p: Node) -> void:
	if not p._owner_connected():
		return
	var ls: Array = []
	for l in data["listings"]:
		if l["seller"] == p.account_key:
			ls.append(l)
	client_mine.rpc_id(p.peer_id, {"listings": ls, "claims": data["claims"].get(p.account_key, {"gold": 0, "items": [], "stacks": {}}),
		"history": data["history"].get(p.account_key, []), "max": max_listings(), "now": _now()})


## Login: tell the player about sales / returned items waiting for them.
func on_login(p: Node) -> void:
	var c: Dictionary = data["claims"].get(p.account_key, {})
	_log("Login market '%s': %d active listing(s), claim box gold %d, items %d, stacks %s" % [p.display_name, count_listings(p.account_key),
		int(c.get("gold", 0)), c.get("items", []).size(), c.get("stacks", {})])
	if not c.is_empty():
		var msg := "[Market] While you were away: %d gold and %d item(s) are waiting at the Trade Broker" % [int(c["gold"]), c["items"].size() + c["stacks"].size()]
		get_tree().create_timer(1.0).timeout.connect(func():
			if is_instance_valid(p):
				p.notify(msg, true))


func _process(delta: float) -> void:
	if not is_server() or data.is_empty():
		return
	_tick += delta
	if _tick < 1.0:
		return
	_tick = 0.0
	var now := _now()
	var expired: Array = []
	for l in data["listings"]:
		if int(l["expires"]) <= now:
			expired.append(l)
	if expired.is_empty():
		return
	var touched: Array = []
	for l in expired:
		data["listings"].erase(l)
		_to_claims(l["seller"], l["item"])
		_history(l["seller"], {"kind": "expired", "what": Market.item_name(l["item"]), "price": int(l["price"])})
		_log("listing #%d (%s by %s) expired -> returned to the seller's claim box" % [l["id"], Market.item_summary(l["item"]), l["seller_name"]])
		var s := _player_by_key(l["seller"])
		if s:
			s.notify("[Market] Your listing %s expired - collect it at the Trade Broker" % Market.item_name(l["item"]), true)
			touched.append(s)
	_commit(touched, "expiry")
	for s in touched:
		push_mine(s)


# ================================================================ RPCs (server -> owner client)

@rpc("authority", "call_local", "reliable")
func client_page(res: Dictionary) -> void:
	page = res
	if not is_server() or main.bot_mode:
		main._log("market page: %d hit(s), page %d/%d: %s" % [int(res["total"]), int(res["page"]) + 1, int(res["pages"]),
			", ".join(res["rows"].map(func(l): return "#%d %s @%d" % [l["id"], Market.item_summary(l["item"]), l["price"]]))])
	page_changed.emit()


@rpc("authority", "call_local", "reliable")
func client_mine(m: Dictionary) -> void:
	mine = m
	mine_changed.emit()
