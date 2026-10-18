extends Node
## Parties (server-authoritative). Up to MAX_MEMBERS players; the leader invites by
## name, the invitee accepts. Party members may enter each other's dungeon portals
## (instances.gd _may_enter), so a party clears one shared instance together.
## Commands: /invite <name>, /accept, /decline, /leave, /kick <name>, /party, /p <text>.
## Parties live in memory only: leaving the game leaves the party.

const MAX_MEMBERS := 4
const INVITE_TTL := 60.0

var main: Node
var parties := {}      # party id -> {"id", "leader": account key, "members": [account keys]}
var member_of := {}    # account key -> party id
var invites := {}      # invitee account key -> {"from": account key, "t": seconds}
var _next := 1


func _ready() -> void:
	main = get_parent()


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _log(msg: String) -> void:
	main.log_server("[party] " + msg)


func _player_by_key(k: String) -> Node:
	for p in main.all_players():
		if p.account_key == k:
			return p
	return null


func _name_of(k: String) -> String:
	var p := _player_by_key(k)
	return p.display_name if p else str(main.accounts.get_account(k).get("name", k))


func party_of(key: String) -> Dictionary:
	return parties.get(member_of.get(key, -1), {})


func same_party(a: String, b: String) -> bool:
	return a == b or (member_of.has(a) and member_of.get(a) == member_of.get(b, -2))


func members_of(key: String) -> Array:
	var pt := party_of(key)
	return pt["members"].duplicate() if not pt.is_empty() else [key]


## Server: a chat command ("/invite Bob" ...). Returns true if the text was a party command.
func chat_command(p: Node, text: String) -> bool:
	var parts := text.strip_edges().split(" ", false, 1)
	var cmd := parts[0].to_lower()
	var arg := parts[1].strip_edges() if parts.size() > 1 else ""
	match cmd:
		"/invite":
			invite(p, arg)
		"/accept":
			accept(p)
		"/decline":
			decline(p)
		"/leave":
			leave(p.account_key, "left the party")
		"/kick":
			kick(p, arg)
		"/party":
			var pt := party_of(p.account_key)
			p.notify("You are not in a party. /invite <name> to start one." if pt.is_empty() else "Party: %s" % _names(pt), true)
		"/p":
			var pt2 := party_of(p.account_key)
			if pt2.is_empty():
				p.notify("You are not in a party.", true)
			else:
				for k in pt2["members"]:
					var m := _player_by_key(k)
					if m:
						m.notify("[Party] %s: %s" % [p.display_name, arg.left(200)], true)
		_:
			return false
	return true


func handle_request(p: Node, arg: Dictionary) -> void:
	match str(arg.get("op", "")):
		"invite":
			invite(p, str(arg.get("name", "")))
		"accept":
			accept(p)
		"decline":
			decline(p)
		"leave":
			leave(p.account_key, "left the party")
		"kick":
			kick(p, str(arg.get("name", "")))


func _reject(p: Node, what: String, why: String) -> void:
	_log("%s %s rejected: %s" % [p.display_name, what, why])
	p.notify("Can't do that: " + why, true)


func invite(p: Node, target_name: String) -> void:
	var tk := AccountStore.key_for(target_name)
	var t := _player_by_key(tk)
	var pt := party_of(p.account_key)
	if t == null:
		_reject(p, "invite", "'%s' is not online" % target_name)
	elif tk == p.account_key:
		_reject(p, "invite", "you can't invite yourself")
	elif not pt.is_empty() and pt["leader"] != p.account_key:
		_reject(p, "invite", "only the party leader can invite")
	elif not pt.is_empty() and pt["members"].size() >= MAX_MEMBERS:
		_reject(p, "invite", "the party is full (%d/%d)" % [MAX_MEMBERS, MAX_MEMBERS])
	elif member_of.has(tk):
		_reject(p, "invite", "%s is already in a party" % t.display_name)
	else:
		invites[tk] = {"from": p.account_key, "t": _now()}
		_log("%s invited %s" % [p.display_name, t.display_name])
		p.notify("Invited %s to your party." % t.display_name, true)
		t.notify("%s invites you to a party - type /accept or /decline (or use the party prompt)." % p.display_name, true)
		main.party_invite.rpc_id(t.peer_id, p.display_name)


func accept(p: Node) -> void:
	var inv: Dictionary = invites.get(p.account_key, {})
	invites.erase(p.account_key)
	if inv.is_empty() or _now() - float(inv["t"]) > INVITE_TTL:
		_reject(p, "accept", "you have no pending party invite")
		return
	var lk := str(inv["from"])
	if _player_by_key(lk) == null:
		_reject(p, "accept", "the inviter is no longer online")
		return
	if member_of.has(p.account_key):
		leave(p.account_key, "left the party")
	var pt := party_of(lk)
	if pt.is_empty():
		pt = {"id": _next, "leader": lk, "members": [lk]}
		parties[_next] = pt
		member_of[lk] = _next
		_next += 1
	elif pt["members"].size() >= MAX_MEMBERS:
		_reject(p, "accept", "the party is full")
		return
	pt["members"].append(p.account_key)
	member_of[p.account_key] = pt["id"]
	_log("%s joined %s's party #%d: %s" % [p.display_name, _name_of(lk), pt["id"], _names(pt)])
	_tell(pt, "%s joined the party." % p.display_name)
	_push(pt)


func decline(p: Node) -> void:
	var inv: Dictionary = invites.get(p.account_key, {})
	invites.erase(p.account_key)
	if inv.is_empty():
		_reject(p, "decline", "you have no pending party invite")
		return
	_log("%s declined %s's invite" % [p.display_name, _name_of(str(inv["from"]))])
	var l := _player_by_key(str(inv["from"]))
	if l:
		l.notify("%s declined your party invite." % p.display_name, true)


func kick(p: Node, target_name: String) -> void:
	var pt := party_of(p.account_key)
	var tk := AccountStore.key_for(target_name)
	if pt.is_empty() or pt["leader"] != p.account_key:
		_reject(p, "kick", "only the party leader can kick")
	elif tk == p.account_key or not tk in pt["members"]:
		_reject(p, "kick", "'%s' is not in your party" % target_name)
	else:
		leave(tk, "was removed from the party")


## Remove `key` from its party (leaving the game also calls this). Disbands at < 2 members.
func leave(key: String, why: String) -> void:
	invites.erase(key)
	var pt := party_of(key)
	member_of.erase(key)
	if pt.is_empty():
		var p0 := _player_by_key(key)
		if p0 and why == "left the party":
			p0.notify("You are not in a party.", true)
		return
	pt["members"].erase(key)
	_log("%s %s #%d" % [_name_of(key), why, pt["id"]])
	var gone := _player_by_key(key)
	if gone and gone._owner_connected():   # a disconnected peer gets no RPC
		main.party_state.rpc_id(gone.peer_id, [], "")
		gone.notify("You %s." % why.replace("was ", "were "), true)
	_tell(pt, "%s %s." % [_name_of(key), why])
	if pt["members"].size() < 2:
		for k in pt["members"]:
			member_of.erase(k)
			var m := _player_by_key(k)
			if m and m._owner_connected():
				main.party_state.rpc_id(m.peer_id, [], "")
		parties.erase(pt["id"])
		_log("party #%d disbanded" % pt["id"])
		return
	if pt["leader"] == key:
		pt["leader"] = pt["members"][0]
		_tell(pt, "%s is the new party leader." % _name_of(pt["leader"]))
	_push(pt)


func on_peer_left(key: String) -> void:
	if key != "":
		leave(key, "left the game and the party")


func _names(pt: Dictionary) -> String:
	var out: Array = []
	for k in pt["members"]:
		out.append(_name_of(k) + (" (leader)" if k == pt["leader"] else ""))
	return ", ".join(out)


func _tell(pt: Dictionary, text: String) -> void:
	for k in pt["members"]:
		var m := _player_by_key(k)
		if m:
			m.notify("[Party] " + text, true)


## Send the member list (name, class, level, zone) to every online member.
func _push(pt: Dictionary) -> void:
	var list: Array = []
	for k in pt["members"]:
		var m := _player_by_key(k)
		list.append({"name": _name_of(k), "class": m.class_id if m else "", "level": m.level if m else 0,
			"zone": m.zone.zone_id if m and m.zone else ""})
	for k in pt["members"]:
		var m := _player_by_key(k)
		if m and m._owner_connected():
			main.party_state.rpc_id(m.peer_id, list, _name_of(pt["leader"]))
