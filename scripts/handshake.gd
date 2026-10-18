extends Node
## Build/protocol version handshake, the first thing a client does after connecting.
## Lives on its own node ("Main/Handshake") with a tiny, frozen RPC set, so its RPC
## checksum matches across builds even when Main's RPCs changed: an old/new client gets
## a readable "Version mismatch" instead of "rpc node checksum failed" errors.
## The server ignores every other request from a peer until its version was accepted,
## and disconnects peers that don't complete the handshake in time (older builds).
## DO NOT add/rename RPCs here - bump BUILD_VERSION in main.gd instead.

signal accepted
signal rejected(message: String)

const TIMEOUT := 4.0

var version := ""          # this build's version (set by Main)
var ok_peers := {}         # server: peer id -> true once the versions matched
var _pending := {}         # server: peer id -> seconds since connect


func _ready() -> void:
	name = "Handshake"


func server_peer_connected(id: int) -> void:
	_pending[id] = 0.0


func server_peer_left(id: int) -> void:
	_pending.erase(id)
	ok_peers.erase(id)


func is_ok(id: int) -> bool:
	return id == 1 or ok_peers.has(id)


func _process(delta: float) -> void:
	if _pending.is_empty() or not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	for id in _pending.keys():
		_pending[id] += delta
		if _pending[id] > TIMEOUT:
			_pending.erase(id)
			get_parent()._log("Peer %d sent no version handshake in %.0fs (older build?) - disconnected" % [id, TIMEOUT])
			if multiplayer.get_peers().has(id):
				multiplayer.multiplayer_peer.disconnect_peer(id)


## Client -> server: my build version.
@rpc("any_peer", "reliable")
func hello(client_version: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	_pending.erase(id)
	if client_version != version:
		var msg := "Version mismatch: server %s, you %s. Please update to the same build." % [version, client_version]
		get_parent()._log("Peer %d refused: %s" % [id, msg])
		answer.rpc_id(id, false, msg)
		get_tree().create_timer(0.5).timeout.connect(func():
			if multiplayer.multiplayer_peer and multiplayer.get_peers().has(id):
				multiplayer.multiplayer_peer.disconnect_peer(id))
		return
	ok_peers[id] = true
	get_parent()._log("Peer %d version %s accepted" % [id, client_version])
	answer.rpc_id(id, true, version)


## Server -> client: accepted (message = server version) or refused (message = reason).
@rpc("authority", "reliable")
func answer(ok: bool, message: String) -> void:
	if ok:
		accepted.emit()
	else:
		rejected.emit(message)
