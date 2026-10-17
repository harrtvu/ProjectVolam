extends Node2D
## Project Volam - root of the game.
## One scene handles everything: main menu, world, networking, accounts, chat and HUD.
##
## Command-line options (put them after `--`, e.g. `godot --headless -- --server`):
##   --server            run as a dedicated (headless) server
##   --host              start a listen server immediately (host + play)
##   --join=ADDRESS      connect to ADDRESS immediately (e.g. --join=127.0.0.1)
##   --port=7777         port to host on / connect to
##   --name=Harry        account / player name
##   --password=secret   account password
##   --ws                use WebSockets instead of ENet (needed for web clients)
##   --save-file=PATH    server: where accounts are saved (default user://volam_save/accounts.json)
##   --market-file=PATH  server: market save file (default user://volam_save/market.json / X_market.json beside --save-file=X.json)
##   --debug-loot        server: much higher gear drop rates (testing)
##   --debug-start-level=N  server: brand-new accounts start at level N (testing high zones)
##   --fast-respawn      server: monsters/bosses respawn 10x faster (testing)
##   --allow-warp        server: accept --warp requests from clients (testing/screenshots)
##   --warp=ZONE         client: ask the server to teleport you to ZONE after login
##   --warp-cell=X,Y     ... and to that tile of the zone
##   --warp-delay=SECS   wait this long after login before the --warp request (tests)
##   --bot               test bot: hunts monsters, loots, drinks potions, equips gear, chats
##   --bot-passive       test bot that walks into monsters without fighting back
##   --bot-route=a,b,c   bot walks through the portals to zone a, then b, then c ...
##   --bot-dwell=SECS    bot stays this long in each zone of its route (default 12)
##   --bot-hunt=boss     bot goes after the zone boss first
##   --class=NAME        class a bot / headless client picks when asked (metal, wood, water, fire, earth)
##   --bot-no-skills     bot only uses the basic attack
##   --bot-no-gear       bot never equips gear it finds
##   --bot-craft         bot runs the scripted crafting / vendor / stash test at the blacksmith
##   --bot-idle          bot stands still and does nothing (screenshots)
##   --loot-showcase     server: drops one item of each rarity + some currency in the meadow (for screenshots)
##   --debug-gear        server: debug-level accounts get a crafting kit (orbs, 2500 gold, items)
##   --debug-full-bag=P  server: debug-level accounts whose name starts with P get a full bag
##   --gear-selftest     offline gear checks (drop statistics, orbs, enhancement, resistances)
##   --open-smith        open the blacksmith panel when standing next to it (screenshots)
##   --debug-tooltip=N   show the tooltip of the N-th gear item in the bag (screenshots)
##   --open-sheet        open the character sheet (C) on login (screenshots)
##   --quit-after=SECS   quit automatically after SECS seconds (for tests)
##   --screenshot=PATH   save a screenshot after --screenshot-delay=SECS (default 6; needs a display)
##   --open-inventory    open the inventory panel once in game (for screenshots)

const GAME_TITLE := "Project Volam"
const DEFAULT_PORT := 7777
const MAX_PLAYERS := 32
const SAVE_INTERVAL := 30.0
const DEFAULT_SAVE_FILE := "user://volam_save/accounts.json"

const ZoneScript := preload("res://scripts/zone.gd")
const InventoryUIScript := preload("res://scripts/inventory_ui.gd")
const BlacksmithUIScript := preload("res://scripts/blacksmith_ui.gd")
const MapUIScript := preload("res://scripts/map_ui.gd")
const AtlasUIScript := preload("res://scripts/atlas_ui.gd")
const PauseMenuScript := preload("res://scripts/pause_menu.gd")
const MarketUIScript := preload("res://scripts/market_ui.gd")
const HideoutUIScript := preload("res://scripts/hideout_ui.gd")
const ItemTooltipScript := preload("res://scripts/item_tooltip.gd")
const ClassSelectScript := preload("res://scripts/class_select_ui.gd")
const CharacterSheetScript := preload("res://scripts/character_sheet.gd")
const SkillBarScript := preload("res://scripts/skill_bar.gd")
const FxScript := preload("res://scripts/fx.gd")
const TalentUIScript := preload("res://scripts/talent_ui.gd")

var zones := {}             # zone_id -> zone node (every peer builds all of them)
var menu_cam: Camera2D

# UI
var menu_root: Control
var name_edit: LineEdit
var pass_edit: LineEdit
var addr_edit: LineEdit
var host_btn: Button
var join_btn: Button
var status_label: Label
var hud: Control
var chat_log: RichTextLabel
var chat_edit: LineEdit
var info_label: Label
var stats_name: Label
var hp_bar: ProgressBar
var hp_text: Label
var xp_bar: ProgressBar
var xp_text: Label
var stats_line: Label
var dead_label: Label
var zone_label: Label
var banner_label: Label
var _banner_t := 0.0
var _shown_zone := ""
var inventory_ui: PanelContainer
var smith_ui: PanelContainer
var map_ui: PanelContainer
var atlas_ui: PanelContainer
var pause_menu: Control
var menu_test_leave := ""         # --menu-test-leave=menu|quit: finish the menu test with Return to Main Menu / Quit Game
var menu_test := false             # client/host bot: drive the Esc menu (panel priority, pause, resume) and log
var _open_atlas := false
var _open_menu_at := -1.0          # client (screenshots): open the Esc menu after N seconds in game
var _open_atlas_arg := ""          # client (screenshots): "map" | "tree" | "map@<node>" (forced tooltip) | "tree@<passive>"
var item_tip: PanelContainer
var mp_bar: ProgressBar
var mp_text: Label
var class_label: Label
var skill_bar: HBoxContainer
var char_sheet: PanelContainer
var class_select: Control

# State
var chat_active := false
var in_game := false
var is_dedicated := false
var use_ws := false
var bot_mode := false
var instances: Node                # dungeon instance manager (instances.gd), on every peer
var hideout_debug := false         # server (tests): every hideout theme unlocked, boss always drops a decoration
var hideouts: Node                 # player hideouts (hideout_server.gd), on every peer
var market: Node                   # trade market (market_server.gd), on every peer
var market_ui: PanelContainer
var hideout_ui: PanelContainer
var bot_hideout := ""              # client (tests): run the hideout bot ("1" = first session, "2" = after a restart)
var _hideout_shot := ""            # client (screenshots): "decor" | "mode" | "theme"
var market_duration := 0           # server: listing lifetime in seconds (0 = default 48h)
var market_max_listings := 0       # server: active listings per account (0 = default 20)
var _class_from_cli := false       # client: --class=X given -> pick it automatically (screenshots)
var market_file := ""              # server: market save file (default: next to the accounts file)
var market_crash_test := ""        # server (test): kill -9 itself right after writing market.json for this commit ("buy")
var market_short := ""             # server (test): listings of accounts starting with this expire after 15 s
var bot_market := ""               # bot: market test role (seller|buyer|race|pauper|fullbag|expirer|collector)
var _open_market := ""             # client: open the market panel on this tab (screenshots)
var _open_market_at := 7.0
var _bm_done := {}
var market_tip := false            # client (screenshots): show the first result's tooltip
var _bm_ids := {}
var instance_timeout := 0.0        # server: seconds an empty dungeon stays open (0 = default)
var complete_timeout := 0.0        # server: seconds a completed dungeon stays open (0 = default)
var debug_atlas_kit := false      # server: honour the bots' "debug_kit" request (a locked fire:3 ticket)
var debug_next_tier := -1.0        # server: chance a boss ticket is tier+1 (-1 = default 50%)
var bot_dungeon := ""              # bot: "full" | "die" | "enter" - dungeon test scenarios
var bot_dungeon_theme := "wood"
var bot_dungeon_tier := 1
var bot_dungeon_unique := false
var _bd_step := 0
var _bd_t := 0.0
var _bd_ticket := -1
var _bd_done_t := -1.0
var _bd_entries := 0
var bot_atlas := false     # bot (with --bot-dungeon=full): atlas test script (locked node, passives, extra portal, respec)
var _ba := 0
var _ba_t := 0.0
var _open_map_ui := ""
var bot_idle := false     # test/screenshots: bot stands still and does nothing
var bot_passive := false   # test: bot never attacks (so it gets defeated)
var bot_dir := Vector2.ZERO
var bot_class := ""        # --class=fire: class a bot picks when asked
var bot_skills := true     # bots cycle through their skills
var _bot_skill_timer := 0.0
var _bot_skill_slot := 0
var _bot_tried_forbidden := {}
var _open_sheet := false
var _warp_pending := false
var _warp_delay := 0.0   # --warp-delay=SECS: wait before warping (tests)
# targeting / aiming (client)
var preview_slot := -1     # skill whose range / area preview is drawn
var hold_slot := -1        # ground skill key being held (cast on release)
var hover_slot := -1       # skill bar slot under the mouse
var talent_ui: PanelContainer
var target_frame: PanelContainer
var _tf_icon: TextureRect
var _tf_name: Label
var _tf_hp: ProgressBar
var _tf_hp_text: Label
var _tf_status: RichTextLabel
var _open_talents := false
var _debug_preview := -1
var _debug_preview_cell := Vector2i(-1, -1)
# bot testing options
var bot_target_mode := ""   # "far": select the farthest monster in range (not the nearest)
var bot_aim := false        # aim with a "cursor" position instead of a target
var bot_probe := false      # send invalid targets once each (server must reject)
var bot_talents := ""       # "auto:0" / "auto:1": spend points, filling that branch first
var bot_talent_probe := false
var bot_respec_at: Array = []
var _bot_target_t := 0.0
var _bot_aim_point = null
var _bot_next_req := {}
var _bot_probe_step := 0
var _bot_probe_t := 0.0
var _bot_first_zone := ""
var _bot_first_monster := -1
var _bot_talent_t := 0.0
var _bot_talent_probe_done := false
var _bot_respec_pending := false
var _awaiting_class := {}  # server: peer_id -> {"name", "is_new"} logged in, choosing a class
var local_name := ""
var local_password := ""
var rng := RandomNumberGenerator.new()

# Server state
var accounts: AccountStore
var save_file := DEFAULT_SAVE_FILE
var debug_loot := false
var loot_showcase := false         # server: drop a rarity showcase in the meadow (screenshots)
var debug_gear := false            # server: debug accounts get a crafting kit (orbs, gold, items)
var debug_fresh := ""              # server: accounts whose name starts with this skip --debug-start-level (fresh Lv1)
var debug_full_bag := ""           # server: accounts whose name starts with this get a full bag
var bot_craft := false
var bot_no_gear := false           # bot: never equips found gear (keeps skill numbers stable in tests)
var _bot_full_tried := false             # bot: scripted crafting / selling / stash test at the blacksmith
var _gear_selftest_flag := false
var _debug_tooltip := -1           # client: force the item tooltip for bag slot N (screenshots)
var _open_smith := false
var _craft_step := 0
var _craft_t := 0.0
var _craft_ring := -1
var _craft_n := 0
var _bot_hold_dir := Vector2.ZERO
var player_names := {}     # peer_id -> display name (logged-in players)
var peer_accounts := {}    # peer_id -> account key
var _pending_chars := {}   # peer_id -> character dict, consumed by the spawn function
var peer_zone := {}        # peer_id -> zone_id the player is in (drives visibility filters)
var _zone_since := {}      # peer_id -> msec of the last zone change
var respawn_scale := 1.0
var debug_start_level := 0
var allow_warp := false
var _warp_to := ""
var _warp_cell := Vector2i(-1, -1)
var _save_timer := 0.0

var _elapsed := 0.0
var _quit_after := -1.0
var _log_timer := 0.0
var _bot_move_timer := 0.0
var _bot_attack_timer := 0.0
var _bot_misc_timer := 0.0
var _bot_chatted := false
var _bot_last_inv := ""
var bot_route: Array = []
var bot_dwell := 12.0
var bot_hunt_boss := false
var _bot_zone_t := 0.0
var _bot_astar: AStarGrid2D
var _bot_astar_zone := ""
var _bot_path: Array = []
var _bot_path_t := 0.0
var _bot_goal := Vector2i(-1, -1)
var _bot_route_done := false
var _screenshot_path := ""
var _screenshot_delay := 6.0
var _screenshot_when := ""         # "" | "dungeon" (inside an instance) | "boss" (next to a live dungeon boss)
var _shot_since := -1.0
var _open_inventory := false
var _shutting_down := false
var _rejected := false


func _ready() -> void:
	get_tree().paused = false    # (after "Return to Main Menu" the old scene was reloaded while paused)
	rng.randomize()
	_setup_input()
	_build_world()
	_build_ui()
	pause_menu = PauseMenuScript.new()
	pause_menu.main = self
	hud.get_parent().add_child(pause_menu)
	_load_client_settings.call_deferred()
	# Clients never talk to each other directly (everything goes through the
	# authoritative server), so turn off SceneMultiplayer's peer relay. This also
	# avoids the server notifying peers that are in the middle of disconnecting.
	var sm := multiplayer as SceneMultiplayer
	if sm:
		sm.server_relay = false
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_title(GAME_TITLE)
	_parse_args()


# ================================================================ setup

func _setup_input() -> void:
	_add_action("move_up", [KEY_W, KEY_UP])
	_add_action("move_down", [KEY_S, KEY_DOWN])
	_add_action("move_left", [KEY_A, KEY_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT])
	_add_action("attack", [KEY_SPACE])
	_add_action("pickup", [KEY_E])
	_add_action("use_potion", [KEY_Q])
	_add_action("inventory", [KEY_I])
	_add_action("character", [KEY_C])
	_add_action("skill_1", [KEY_1])
	_add_action("skill_2", [KEY_2])
	_add_action("skill_3", [KEY_3])
	_add_action("skill_4", [KEY_4])
	_add_action("talents", [KEY_T])
	_add_action("target_cycle", [KEY_TAB])
	_add_action("atlas", [KEY_M])


func _add_action(action: String, keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _build_world() -> void:
	var root := Node2D.new()
	root.name = "Zones"
	add_child(root)
	for id in Zones.ORDER:
		var z := ZoneScript.new()
		z.setup(id, self)
		root.add_child(z)
		zones[id] = z
	instances = preload("res://scripts/instances.gd").new()
	instances.name = "Instances"
	add_child(instances)
	hideouts = preload("res://scripts/hideout_server.gd").new()
	hideouts.name = "Hideouts"
	add_child(hideouts)
	market = preload("res://scripts/market_server.gd").new()
	market.name = "Market"
	add_child(market)
	# Menu / spectator camera (the local player's own camera takes over in game).
	menu_cam = Camera2D.new()
	menu_cam.name = "MenuCamera"
	menu_cam.position = zones["meadow"].map.cell_pos(Zones.info("meadow")["respawn"])
	add_child(menu_cam)
	menu_cam.make_current()
	_show_zone("meadow", false)


## Server: character data waiting for the player's spawn function.
func take_pending_character(id: int) -> Dictionary:
	var c: Dictionary = _pending_chars.get(id, {})
	_pending_chars.erase(id)
	return c


func _player_node(id: int) -> Node:
	for z in zones.values():
		var n: Node = z.players_root.get_node_or_null(str(id))
		if n and not n.is_queued_for_deletion():
			return n
	return null


func all_players() -> Array:
	var out: Array = []
	for z in zones.values():
		for p in z.players_root.get_children():
			if not p.is_queued_for_deletion():
				out.append(p)
	return out














func _parse_args() -> void:
	if PauseMenuScript.returned_to_menu:
		# came back via the Esc menu's "Return to Main Menu": show the title screen, don't auto-join again
		PauseMenuScript.returned_to_menu = false
		_log("main menu shown after Return to Main Menu (peer %s)" % ("none" if not multiplayer.has_multiplayer_peer() or multiplayer.multiplayer_peer is OfflineMultiplayerPeer else "still set!"))
		if DisplayServer.get_name() == "headless":
			get_tree().create_timer(0.5).timeout.connect(func(): get_tree().quit())
		return
	var opts := {}
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv: PackedStringArray = a.substr(2).split("=", true, 1)
			opts[kv[0]] = kv[1] if kv.size() > 1 else "true"
	# Web builds can't take command-line args, so accept URL query params:
	# index.html?join=127.0.0.1&name=Harry&password=x  (same option names as above)
	if OS.has_feature("web"):
		var q = JavaScriptBridge.eval("window.location.search", true)
		if typeof(q) == TYPE_STRING and q.length() > 1:
			for pair in q.substr(1).split("&", false):
				var kv: PackedStringArray = pair.split("=", true, 1)
				opts[kv[0].uri_decode()] = kv[1].uri_decode() if kv.size() > 1 else "true"
	var port := int(opts.get("port", str(DEFAULT_PORT)))
	use_ws = opts.has("ws") or OS.has_feature("web")
	bot_mode = opts.has("bot") or opts.has("bot-passive")
	bot_passive = opts.has("bot-passive") or opts.has("bot-idle")
	bot_idle = opts.has("bot-idle")
	instance_timeout = float(opts.get("instance-timeout", "0"))
	complete_timeout = float(opts.get("complete-timeout", "0"))
	debug_next_tier = float(opts.get("debug-next-tier", "-1"))
	bot_dungeon = str(opts.get("bot-dungeon", ""))
	bot_dungeon_theme = str(opts.get("bot-dungeon-theme", "wood"))
	bot_dungeon_tier = int(opts.get("bot-dungeon-tier", "1"))
	bot_dungeon_unique = opts.has("bot-dungeon-unique")
	bot_atlas = opts.has("bot-atlas")
	debug_atlas_kit = opts.has("debug-atlas-kit")
	_open_map_ui = str(opts.get("open-map-ui", ""))
	market_duration = int(opts.get("market-duration", "0"))
	market_max_listings = int(opts.get("market-max-listings", "0"))
	market_short = str(opts.get("market-short", ""))
	market_file = str(opts.get("market-file", ""))
	market_crash_test = str(opts.get("market-crash-test", ""))
	bot_market = str(opts.get("bot-market", ""))
	_open_market = str(opts.get("open-market", ""))
	_open_market_at = float(opts.get("open-market-at", "7"))
	if opts.has("market-tip"):
		market_tip = true
	_open_atlas = opts.has("open-atlas")
	hideout_debug = opts.has("hideout-debug")
	bot_hideout = str(opts.get("bot-hideout", ""))
	_hideout_shot = str(opts.get("hideout-shot", ""))
	menu_test = opts.has("menu-test")
	menu_test_leave = str(opts.get("menu-test-leave", ""))
	if opts.has("settings-file"):
		PauseMenuScript.settings_path = str(opts["settings-file"])
	if opts.has("settings-test"):
		_settings_test.call_deferred()
	_open_menu_at = float(opts.get("open-menu", "-1"))
	_open_atlas_arg = str(opts.get("open-atlas", ""))
	debug_loot = opts.has("debug-loot")
	debug_gear = opts.has("debug-gear")
	loot_showcase = opts.has("loot-showcase")
	debug_full_bag = str(opts.get("debug-full-bag", ""))
	debug_fresh = str(opts.get("debug-fresh", ""))
	bot_craft = opts.has("bot-craft")
	_gear_selftest_flag = opts.has("gear-selftest")
	if opts.has("debug-tooltip"):
		_debug_tooltip = int(opts["debug-tooltip"])
	_open_smith = opts.has("open-smith")
	debug_start_level = clampi(int(opts.get("debug-start-level", "0")), 0, 50)
	respawn_scale = 0.1 if opts.has("fast-respawn") else 1.0
	allow_warp = opts.has("allow-warp")
	if opts.has("warp") and Zones.exists(str(opts["warp"])):
		_warp_to = str(opts["warp"])
	_warp_delay = float(opts.get("warp-delay", "0"))
	if opts.has("warp-cell"):
		var xy: PackedStringArray = str(opts["warp-cell"]).split(",")
		if xy.size() == 2:
			_warp_cell = Vector2i(int(xy[0]), int(xy[1]))
	if opts.has("bot-route"):
		for z in str(opts["bot-route"]).split(",", false):
			if Zones.exists(z):
				bot_route.append(z)
	if opts.has("bot-dwell"):
		bot_dwell = float(opts["bot-dwell"])
	bot_hunt_boss = str(opts.get("bot-hunt", "")) == "boss"
	_open_inventory = opts.has("open-inventory")
	_open_sheet = opts.has("open-sheet")
	_open_talents = opts.has("open-talents")
	if opts.has("debug-preview"):
		var dp: PackedStringArray = str(opts["debug-preview"]).split(",")
		_debug_preview = int(dp[0]) - 1
		if dp.size() == 3:
			_debug_preview_cell = Vector2i(int(dp[1]), int(dp[2]))
	bot_target_mode = str(opts.get("bot-target", ""))
	bot_aim = opts.has("bot-aim")
	bot_probe = opts.has("bot-probe")
	bot_talents = str(opts.get("bot-talents", ""))
	bot_talent_probe = opts.has("bot-talent-probe")
	if opts.has("bot-respec-at"):
		for t in str(opts["bot-respec-at"]).split(",", false):
			bot_respec_at.append(float(t))
	if opts.has("talent-selftest"):
		_talent_selftest()
		return
	if _gear_selftest_flag:
		_gear_selftest()
		return
	if opts.has("class") and Classes.exists(str(opts["class"])):
		bot_class = str(opts["class"])
		_class_from_cli = true
	bot_skills = not opts.has("bot-no-skills")
	bot_no_gear = opts.has("bot-no-gear")
	if opts.has("save-file"):
		save_file = str(opts["save-file"])
	if opts.has("quit-after"):
		_quit_after = float(opts["quit-after"])
	if opts.has("screenshot"):
		_screenshot_path = str(opts["screenshot"])
	_screenshot_when = str(opts.get("screenshot-when", ""))
	if opts.has("screenshot-delay"):
		_screenshot_delay = float(opts["screenshot-delay"])
	if opts.has("name"):
		name_edit.text = str(opts["name"])
	if opts.has("password"):
		pass_edit.text = str(opts["password"])
	if opts.has("join") and opts["join"] != "true":
		addr_edit.text = str(opts["join"])

	if opts.has("server") or OS.has_feature("dedicated_server"):
		is_dedicated = true
		start_server(port, true)
	elif opts.has("host"):
		start_server(port, false)
	elif opts.has("join"):
		var parsed := _parse_address(addr_edit.text, port)
		start_client(parsed[0], parsed[1])
	if OS.has_feature("web"):
		host_btn.disabled = true
		host_btn.tooltip_text = "Browsers cannot host; join a server started with --ws."


# ================================================================ networking

## Screenshot helper: one item of each rarity and some currency around the meadow spawn.
func _drop_showcase() -> void:
	var z: Node = zones["meadow"]
	var c: Vector2 = z.map.cell_pos(z.info["respawn"])
	var drops := [Gear.make("steel_sword", "normal", 6, rng), Gear.make("leather_boots", "magic", 8, rng),
		Gear.make("chain_mail", "rare", 12, rng), Gear.make_unique("five_phases", 12, rng), Gear.make("silver_ring", "rare", 12, rng)]
	var offs := [Vector2(-110, -70), Vector2(-200, 40), Vector2(-120, 60), Vector2(110, 70), Vector2(0, -120)]
	for i in drops.size():
		z.spawn_pickup(str(drops[i]["base"]), 1, c + offs[i], drops[i])
	z.spawn_pickup("orb_chaos", 1, c + Vector2(-20, 120))
	z.spawn_pickup("enhance_stone", 1, c + Vector2(60, 125))
	_log("(debug) loot showcase dropped in the meadow")


func start_server(port: int, dedicated: bool) -> bool:
	local_name = _sanitize_name(name_edit.text)
	local_password = pass_edit.text
	accounts = AccountStore.new(save_file)
	accounts.load_file()
	market.load_from(accounts)
	if not dedicated:
		# the host logs in to its own server like everyone else
		var why := _check_login(local_name, local_password, 1)
		if why != "":
			_log("Host login rejected: " + why)
			status_label.text = "Login failed: " + why
			if bot_mode:
				get_tree().quit(3)
			return false
	var peer: MultiplayerPeer
	var err: int
	if use_ws:
		var ws := WebSocketMultiplayerPeer.new()
		err = ws.create_server(port)
		peer = ws
	else:
		var enet := ENetMultiplayerPeer.new()
		err = enet.create_server(port, MAX_PLAYERS)
		peer = enet
	if err != OK:
		_log("Failed to start server on port %d (error %d)" % [port, err])
		status_label.text = "Could not host on port %d (in use?)" % port
		return false
	multiplayer.multiplayer_peer = peer
	_log("%s server listening on port %d (%s). Saves: %s (%d accounts)" % [
		"Dedicated" if dedicated else "Listen", port, "WebSocket" if use_ws else "ENet/UDP",
		ProjectSettings.globalize_path(save_file), accounts.data["accounts"].size()])
	_enter_game()
	for id in Zones.ORDER:
		var z: Node = zones[id]
		z.spawn_initial_monsters()
		var bad: Array = []
		for p in z.info["portals"]:
			if not z.map.is_reachable(p["rect"].position) or not zones[p["to"]].map.is_walkable(p["arrive"]):
				bad.append(p["to"])
		var boss: Dictionary = z.info["boss"]
		if not boss.is_empty() and not z.map.is_reachable(boss["cell"]):
			bad.append("boss")
		_log("Zone %s ready: %d monsters, %d reachable cells%s" % [id, z.monsters_root.get_child_count(),
			z.map.reachable.size(), "" if bad.is_empty() else " UNREACHABLE: %s" % [bad]])
	if not dedicated:
		_login_ok(1, local_name, local_password)
	return true


func start_client(address: String, port: int) -> bool:
	local_name = _sanitize_name(name_edit.text)
	local_password = pass_edit.text
	if local_password.is_empty():
		status_label.text = "Please enter a password (it creates your account on first join)."
		if bot_mode:
			get_tree().quit(2)
		return false
	var peer: MultiplayerPeer
	var err: int
	if use_ws:
		var ws := WebSocketMultiplayerPeer.new()
		err = ws.create_client("ws://%s:%d" % [address, port])
		peer = ws
	else:
		var enet := ENetMultiplayerPeer.new()
		err = enet.create_client(address, port)
		peer = enet
	if err != OK:
		_log("Failed to create client (error %d)" % err)
		status_label.text = "Could not connect (error %d)" % err
		return false
	_rejected = false
	multiplayer.multiplayer_peer = peer
	status_label.text = "Connecting to %s:%d ..." % [address, port]
	_log("Connecting to %s:%d as '%s' ..." % [address, port, local_name])
	host_btn.disabled = true
	join_btn.disabled = true
	return true





func _on_peer_connected(id: int) -> void:
	if multiplayer.is_server():
		_log("Peer %d connected, waiting for login" % id)
		if pause_menu:
			pause_menu.on_peer_joined()


func _on_peer_disconnected(id: int) -> void:
	if not multiplayer.is_server():
		return
	# Handle it after the network poll finishes: if several clients drop in the
	# same instant, sending to one whose disconnect is still queued logs ENet errors.
	_handle_peer_left.call_deferred(id)


func _handle_peer_left(id: int) -> void:
	if not multiplayer.has_multiplayer_peer():
		return
	var node := _player_node(id)
	if node:
		_save_player(node)
		accounts.save_file()
		node.queue_free()  # the spawner despawns it on all clients that can see it
	peer_zone.erase(id)
	_zone_since.erase(id)
	_awaiting_class.erase(id)
	instances.on_peer_left(id)
	var pname: String = player_names.get(id, "")
	player_names.erase(id)
	peer_accounts.erase(id)
	_log("Peer %d (%s) disconnected" % [id, pname if pname != "" else "not logged in"])
	if pname != "":
		broadcast_system("%s left the world." % pname)


func _on_connected_to_server() -> void:
	_log("Connected to server as peer %d, logging in" % multiplayer.get_unique_id())
	register_player.rpc_id(1, local_name, local_password)


func _on_connection_failed() -> void:
	_log("Connection failed")
	multiplayer.multiplayer_peer = null
	status_label.text = "Connection failed. Is the server running?"
	_reset_menu_buttons()
	if bot_mode:
		get_tree().quit(1)


func _on_server_disconnected() -> void:
	if _shutting_down or _rejected:
		return
	get_tree().paused = true  # the peer is dead now; stop entities from using it
	_log("Disconnected from server")
	if bot_mode or DisplayServer.get_name() == "headless":
		get_tree().quit()
		return
	_return_to_menu.call_deferred()


func _return_to_menu() -> void:
	class_select.visible = false
	multiplayer.multiplayer_peer = null
	get_tree().paused = false
	get_tree().reload_current_scene()


func _reset_menu_buttons() -> void:
	host_btn.disabled = OS.has_feature("web")
	join_btn.disabled = false


# ================================================================ accounts / login (server)

## Returns "" if the login is allowed, otherwise the reason it is rejected.
func _check_login(pname: String, password: String, peer_id: int) -> String:
	if password.is_empty():
		return "A password is required."
	if password.length() > 64:
		return "Password too long."
	var key := AccountStore.key_for(pname)
	for pid in peer_accounts:
		if peer_accounts[pid] == key and pid != peer_id:
			return "Account '%s' is already logged in." % pname
	if accounts.has_account(pname) and not accounts.check_password(pname, password):
		return "Wrong password for account '%s'." % pname
	return ""


func _login_ok(id: int, pname: String, password: String) -> void:
	var is_new := not accounts.has_account(pname)
	if is_new:
		accounts.create_account(pname, password)
		accounts.save_file()
		_log("Created account '%s'" % pname)
	var acc := accounts.get_account(pname)
	var display: String = str(acc.get("name", pname))
	var character: Dictionary = acc.get("character", {})
	if is_new and debug_start_level > 1 and not (debug_fresh != "" and pname.to_lower().begins_with(debug_fresh.to_lower())):
		character = {"level": debug_start_level, "gold": 250, "inventory": {"health_potion": 5, "greater_potion": 5}, "items_v": 2}
		if debug_gear:   # crafting test kit
			character["gold"] = 2500
			for orb in Items.ORBS:
				character["inventory"][orb] = 30 if orb == "enhance_stone" else 12
			character["bag"] = [Gear.make("copper_ring", "normal", 12, rng), Gear.make("iron_sword", "normal", 12, rng),
				Gear.make("leather_cap", "normal", 12, rng), Gear.make("sandals", "normal", 3, rng), Gear.make("cloth_wraps", "normal", 3, rng),
				Gear.make_unique("gold_seeker", 12, rng), Gear.make_unique("frost_aegis", 13, rng), Gear.make("chain_mail", "rare", 12, rng),
				Gear.make("lich_staff", "rare", 13, rng), Gear.make("horned_helm", "magic", 13, rng), Gear.make("leather_boots", "rare", 13, rng),
				Dungeons.make_unique_ticket("wuxing_sanctum", rng), Dungeons.make_ticket("water", 3, "rare", rng)]
		if debug_full_bag != "" and pname.to_lower().begins_with(debug_full_bag.to_lower()):
			var junk: Array = []
			for i in Items.BAG_SIZE - character["inventory"].size():     # + the stacks = exactly a full bag
				junk.append(Gear.make("rope_belt", "normal", 1, rng))
			character["bag"] = junk
		acc["character"] = character
		_log("(debug) new account '%s' starts at level %d" % [pname, debug_start_level])
	player_names[id] = display
	peer_accounts[id] = AccountStore.key_for(pname)
	if not Classes.exists(str(character.get("class", ""))):
		# new account, or a save from before classes existed: pick one first
		_awaiting_class[id] = {"name": pname, "is_new": is_new}
		_log("Account '%s' has no class yet - asking peer %d to choose (%s)" % [display, id, "new account" if is_new else "old save"])
		login_result.rpc_id(id, true, "Account created. Welcome to Volam!" if is_new else "Welcome back, %s!" % display)
		class_select_request.rpc_id(id, is_new)
		return
	_spawn_logged_in(id, pname, is_new)
	login_result.rpc_id(id, true, "Account created. Welcome to Volam!" if is_new else "Welcome back, %s!" % display)
	broadcast_system("%s joined the world." % display)


## Client: the server wants us to pick a class (shown once per character).
@rpc("authority", "call_local", "reliable")
func class_select_request(is_new: bool) -> void:
	_log("Class selection requested (%s)" % ("new account" if is_new else "existing account without a class"))
	if bot_mode or _class_from_cli or DisplayServer.get_name() == "headless":
		var cls := bot_class
		if cls == "":
			cls = Classes.ELEMENTS[absi(local_name.to_lower().hash()) % 5]
		_log("bot chooses class %s" % cls)
		choose_class.rpc_id(1, cls)
		return
	class_select.set_subtitle("Choose your element - Ngũ Hành" if is_new else "Your hero needs an element - choose once")
	class_select.visible = true


func _on_class_chosen(cls: String) -> void:
	class_select.visible = false
	choose_class.rpc_id(1, cls)


## Server: a logged-in player without a class picked one.
@rpc("any_peer", "call_local", "reliable")
func choose_class(cls: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if id == 0:
		id = 1
	if not _awaiting_class.has(id) or not Classes.exists(cls):
		return
	var w: Dictionary = _awaiting_class[id]
	_awaiting_class.erase(id)
	var acc := accounts.get_account(str(w["name"]))
	var character: Dictionary = acc.get("character", {})
	character["class"] = cls
	var d := Classes.info(cls)
	if w["is_new"] or not character.has("level"):
		# class-appropriate starting kit for brand new characters
		var eq: Dictionary = character.get("equipment", {})
		for slot in d["start_gear"]:
			var base := str(d["start_gear"][slot])
			var kit := Gear.make(base, "normal", 1, rng)
			kit["bound"] = true     # starting gear is account-bound (can't be sold on the market)
			eq[Items.slots_for(base)[0]] = kit
		character["equipment"] = eq
		character["items_v"] = 2
		var inv: Dictionary = character.get("inventory", {})
		for item in d["start_items"]:
			inv[item] = int(inv.get(item, 0)) + int(d["start_items"][item])
		character["inventory"] = inv
	acc["character"] = character
	accounts.save_file()
	_log("%s chose class %s (%s, %s)" % [acc.get("name", "?"), cls, d["name"], Classes.element_name(d["element"])])
	_spawn_logged_in(id, str(w["name"]), bool(w["is_new"]))
	broadcast_system("%s the %s joined the world." % [player_names.get(id, "?"), d["name"]])


func _spawn_logged_in(id: int, pname: String, is_new: bool) -> void:
	var acc := accounts.get_account(pname)
	var display: String = str(acc.get("name", pname))
	var character: Dictionary = acc.get("character", {})
	var zone_id := str(character.get("zone", "meadow"))
	instances.sync_peer(id)   # open dungeon zones must exist on this peer before anyone could see them
	hideouts.sync_peer(id)
	if zone_id == "hideout":   # logged out in the hideout: reopen it and restore there
		zone_id = hideouts.ensure(peer_accounts[id], display, Hideouts.sanitize(character.get("hideout", {})))
		_log("Login '%s': restoring into the hideout %s" % [display, zone_id])
	elif not Zones.exists(zone_id) or Zones.is_dungeon(zone_id) or Zones.is_hideout(zone_id):   # never log back in inside an instance
		zone_id = "meadow"
	var z: Node = zones[zone_id]
	var pos: Vector2 = z.map.spot_near(z.info["respawn"], rng)
	var saved_pos = character.get("pos", null)
	if typeof(saved_pos) == TYPE_ARRAY and saved_pos.size() == 2:
		var p := Vector2(float(saved_pos[0]), float(saved_pos[1]))
		if z.map.is_walkable_pos(p) and z.portal_at(p).is_empty():
			pos = p
	if acc.has("stash"):   # account-wide shared stash (older saves kept it on the character)
		character = character.duplicate()
		character["stash"] = acc["stash"]
	_pending_chars[id] = character
	if loot_showcase:   # (debug) drop it once the first player is in, so they see it spawn
		loot_showcase = false
		get_tree().create_timer(2.0).timeout.connect(_drop_showcase)
	peer_zone[id] = zone_id
	_zone_since[id] = Time.get_ticks_msec()
	var node: Node = z.player_spawner.spawn({"id": id, "name": display, "pos": pos, "class": str(character["class"])})
	if node:
		node.account_key = peer_accounts[id]
		_push_inventory_later(node)
		_log("Login '%s' (peer %d): %s - class %s, level %d, xp %d, hp %d/%d, mp %d/%d, gold %d, items %s, equip %s, bag %d/%d %s, stash %d %s, zone %s, pos %s, talent points %d/%d %s" % [
			display, id, "NEW account" if is_new else "restored save", node.class_id, node.level, node.xp, node.hp,
			node.max_hp, node.mp, node.max_mp, node.gold, node.inventory, node.equip_summary(), node.bag_used(), Items.BAG_SIZE,
			_inst_list(node.bag), node.stash.size(), _inst_list(node.stash), zone_id, pos.round(),
			Talents.points_spent(node.talents), Talents.points_total(node.level), node.talents])
		market.on_login(node)
		_log("Login atlas '%s': %s (completed nodes %d, dungeon iiq +%d%%, free ticket %s) | bonus %s, atlas points %d earned / %d spent, passives %s" % [display, node.atlas.get("done", {}),
			Dungeons.completed_nodes(node.atlas), roundi(Dungeons.atlas_iiq(node.atlas)), "taken " + node.free_day if node.free_day != "" else "available",
			node.atlas.get("bonus", {}).keys(), Atlas.points_earned(node.atlas), Atlas.points_spent(node.atlas), node.atlas.get("passives", [])])


static func _inst_list(a: Array) -> String:
	var parts: Array = []
	for inst in a:
		parts.append("%s(%s%s)" % [inst["base"], inst["rarity"], (" +%d" % int(inst["upg"])) if int(inst.get("upg", 0)) > 0 else ""])
	return "[%s]" % ", ".join(parts)


func _push_inventory_later(node: Node) -> void:
	# after the spawn packet has gone out, so the owner already has the node
	var ref: WeakRef = weakref(node)
	get_tree().create_timer(0.2).timeout.connect(func():
		var n = ref.get_ref()
		if n and not n.is_queued_for_deletion():
			n.push_inventory())


## Server: move a player through a portal into another zone. The old node is
## despawned and a fresh one (same character data) is spawned in the target
## zone; visibility filters then hand the client the new zone's entities.
func transfer_player(node: Node, to_zone: String, arrive: Vector2i) -> void:
	if not multiplayer.is_server() or not is_instance_valid(node) or node.is_queued_for_deletion():
		return
	if not Zones.exists(to_zone):
		return
	var id: int = node.peer_id
	var from: String = node.zone.zone_id
	if from == to_zone:   # (only warps can do this) just move the player
		node.position = node.zone.map.spot_near(arrive, rng, 20.0)
		node.sync_pos = node.position
		return
	var c: Dictionary = node.to_character()
	c["hp"] = node.hp
	c["_cd"] = node._cooldowns.duplicate()
	var dest: Node = zones[to_zone]
	var pos: Vector2 = dest.map.spot_near(arrive, rng, 20.0)
	c["zone"] = to_zone
	c["pos"] = [pos.x, pos.y]
	var pname: String = node.display_name
	node.queue_free()
	peer_zone[id] = to_zone
	_zone_since[id] = Time.get_ticks_msec()
	_pending_chars[id] = c
	var nn: Node = dest.player_spawner.spawn({"id": id, "name": pname, "pos": pos, "class": node.class_id})
	nn.account_key = str(peer_accounts.get(id, ""))
	_push_inventory_later(nn)
	instances.on_transfer(id, from, to_zone)
	_log("Zone transfer: %s %s -> %s at %s" % [pname, from, to_zone, pos.round()])
	_save_player(nn)
	accounts.save_file()


## Server: call an RPC on `node` only for the peers that can see it (same zone).
## Cosmetic only, so peers whose view of the zone is still being set up (just
## arrived, or the node itself was just spawned) are skipped.
func zone_rpc(node: Node, method: String, args: Array = []) -> void:
	var now := Time.get_ticks_msec()
	if now - int(node.get("_born_ms")) < 600:
		return
	for pid in node.zone.peers():
		if pid == multiplayer.get_unique_id() or now - int(_zone_since.get(pid, 0)) > 600:
			node.callv("rpc_id", [pid, method] + args)


func log_server(msg: String) -> void:
	_log(msg)


## Server: show a skill visual effect to everyone in `zone` (cosmetic).
func zone_fx(zone: Node, kind: String, pos: Vector2, radius: float, color: Color, extra: Vector2) -> void:
	var now := Time.get_ticks_msec()
	for pid in zone.peers():
		if pid == multiplayer.get_unique_id():
			fx(zone.zone_id, kind, pos, radius, color, extra)
		elif now - int(_zone_since.get(pid, 0)) > 600:
			fx.rpc_id(pid, zone.zone_id, kind, pos, radius, color, extra)


@rpc("authority", "unreliable")
func fx(zone_id: String, kind: String, pos: Vector2, radius: float, color: Color, extra: Vector2) -> void:
	if is_dedicated or DisplayServer.get_name() == "headless" or not zones.has(zone_id):
		return
	var f := FxScript.new()
	f.setup(kind, pos, radius, color, extra)
	zones[zone_id].entities.add_child(f)


## Client: a notice from the server (skill unlocked, rejected cast, ...).
func local_notice(text: String, to_chat: bool) -> void:
	if bot_mode:
		_log("notice: " + text)
	if chat_log and to_chat:
		chat_log.append_text("[color=#a0c8ff]%s[/color]\n" % _escape(text))


## Owner -> server: movement input / attack / pickup / use / equip requests.
@rpc("any_peer", "call_local", "reliable")
func player_request(action: String, arg: Variant) -> void:
	if not multiplayer.is_server():
		return
	var node := _player_node(multiplayer.get_remote_sender_id())
	if node:
		node.handle_request(action, arg)


@rpc("any_peer", "reliable")
func request_warp(zone_id: String, cell: Vector2i) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if not allow_warp:
		_log("Warp request from peer %d ignored (server not started with --allow-warp)" % id)
		return
	var node := _player_node(id)
	if node and Zones.exists(zone_id):
		if not zones[zone_id].map.is_walkable(cell):
			cell = Zones.info(zone_id)["respawn"]
		transfer_player(node, zone_id, cell)


@rpc("any_peer", "reliable")
func register_player(pname: String, password: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if player_names.has(id):
		return
	pname = _sanitize_name(pname)
	var why := _check_login(pname, password, id)
	if why != "":
		_log("Rejected login '%s' from peer %d: %s" % [pname, id, why])
		login_result.rpc_id(id, false, why)
		# give the message a moment to arrive, then kick
		get_tree().create_timer(0.5).timeout.connect(func():
			if multiplayer.multiplayer_peer and multiplayer.get_peers().has(id):
				multiplayer.multiplayer_peer.disconnect_peer(id))
		return
	_login_ok(id, pname, password)


@rpc("authority", "call_local", "reliable")
func login_result(ok: bool, message: String) -> void:
	if ok:
		_log("Login OK: %s" % message)
		_enter_game()
		_warp_pending = _warp_to != ""   # sent once our character exists (after class selection)
		if message != "":
			chat_log.append_text("[color=#a0ffa0]%s[/color]\n" % _escape(message))
		return
	_log("Login rejected: %s" % message)
	_rejected = true
	if bot_mode or DisplayServer.get_name() == "headless":
		shutdown(3)
		return
	multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	status_label.text = "Login failed: " + message
	_reset_menu_buttons()


func save_player_now(node: Node) -> void:
	_save_player(node)
	accounts.save_file()


func show_banner(title: String, sub: String) -> void:
	if banner_label:
		banner_label.text = "%s\n%s" % [title, sub]
		_banner_t = 4.5
	_log("banner: %s - %s" % [title, sub])


func _save_player(node: Node) -> void:
	if node.account_key != "" and accounts:
		accounts.set_character(node.account_key, node.to_character())


func save_all(reason: String) -> void:
	if not multiplayer.is_server() or accounts == null:
		return
	var ps := all_players()
	for p in ps:
		_save_player(p)
	var ok := accounts.save_file()
	_log("Saved %d online player(s) to %s (%s)%s" % [ps.size(),
		ProjectSettings.globalize_path(save_file), reason, "" if ok else " FAILED"])


# ================================================================ chat

@rpc("any_peer", "call_local", "reliable")
func submit_chat(text: String) -> void:
	if not multiplayer.is_server():
		return
	var id := multiplayer.get_remote_sender_id()
	if not player_names.has(id):
		return
	text = text.strip_edges().left(200)
	if text.is_empty():
		return
	var node := _player_node(id)
	if node and text.to_lower() == "/hideout":
		hideouts.enter(node)
		return
	if node and text.to_lower().begins_with("/visit"):
		node.notify("Visiting other hideouts isn't available yet (hideouts are private for now).", true)
		return
	var tag: String = Zones.info(node.zone.zone_id)["short"] if node else "?"
	receive_chat.rpc("[%s] %s" % [tag, player_names[id]], text)


@rpc("authority", "call_local", "reliable")
func receive_chat(sender: String, text: String) -> void:
	if sender.is_empty():
		_log("[chat] * %s" % text)
		chat_log.append_text("[color=#f0d070]* %s[/color]\n" % _escape(text))
	else:
		_log("[chat] %s: %s" % [sender, text])
		chat_log.append_text("[color=#80c8ff]%s:[/color] %s\n" % [_escape(sender), _escape(text)])


## Server only: system message to everyone.
func broadcast_system(text: String) -> void:
	if multiplayer.is_server():
		receive_chat.rpc("", text)


func send_chat(text: String) -> void:
	if text.strip_edges().is_empty():
		return
	submit_chat.rpc_id(1, text)


func _on_chat_submitted(text: String) -> void:
	send_chat(text)
	chat_edit.clear()
	chat_edit.release_focus()


func _on_chat_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		chat_edit.clear()
		chat_edit.release_focus()
		chat_edit.accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if not in_game or is_dedicated:
		return
	if hideout_ui and hideout_ui.handle_world_input(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER) and not chat_edit.has_focus():
			chat_edit.grab_focus()
			get_viewport().set_input_as_handled()
		elif event.is_action("inventory") and not chat_edit.has_focus():
			toggle_inventory()
			get_viewport().set_input_as_handled()
		elif event.is_action("character") and not chat_edit.has_focus():
			char_sheet.visible = not char_sheet.visible
			get_viewport().set_input_as_handled()
		elif event.is_action("talents") and not chat_edit.has_focus():
			talent_ui.visible = not talent_ui.visible
			get_viewport().set_input_as_handled()
		elif event.is_action("target_cycle") and not chat_edit.has_focus():
			cycle_target()
			get_viewport().set_input_as_handled()
		elif event.is_action("atlas") and not chat_edit.has_focus():
			atlas_ui.visible = not atlas_ui.visible
			atlas_ui.set_player(_local_player())
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_H and not chat_edit.has_focus():
			toggle_hideout_ui(true)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE and not chat_edit.has_focus():
			handle_escape()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		select_at_mouse()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		# bonus: right-click a monster = select it and attack
		select_at_mouse()
		var me := _local_player()
		if me and NetUtil.selected != null:
			me.request_attack()
		get_viewport().set_input_as_handled()


# ================================================================ targeting (client)

func _cursor_zone_pos(me: Node) -> Vector2:
	return me.position + me.get_local_mouse_position()


## Left click: select the monster (or player) under the cursor, or clear.
func select_at_mouse() -> void:
	var me := _local_player()
	if me == null or me.zone == null:
		return
	var pt := _cursor_zone_pos(me)
	var best: Node = null
	var best_d := INF
	for m in me.zone.monsters_root.get_children():
		if not m.alive:
			continue
		var sc := float(m.def.get("scale", 1.0))
		var d: float = (m.position + Vector2(0, -10.0 * sc)).distance_to(pt)
		if d <= 18.0 * sc + 4.0 and d < best_d:
			best_d = d
			best = m
	if best == null:
		for p in me.zone.players_root.get_children():
			var d: float = (p.position + Vector2(0, -10)).distance_to(pt)
			if d <= 18.0 and d < best_d:
				best_d = d
				best = p
	NetUtil.selected = best
	if best:
		_log("selected target %s" % best.display_name)


## Tab: cycle through living monsters near you, nearest first.
func cycle_target() -> void:
	var me := _local_player()
	if me == null or me.zone == null:
		return
	var list: Array = []
	for m in me.zone.monsters_root.get_children():
		if m.alive and m.position.distance_to(me.position) <= 450.0:
			list.append(m)
	if list.is_empty():
		NetUtil.selected = null
		return
	list.sort_custom(func(a, b): return a.position.distance_to(me.position) < b.position.distance_to(me.position))
	var i := list.find(NetUtil.selected) if NetUtil.is_selected(NetUtil.selected) else -1
	NetUtil.selected = list[(i + 1) % list.size()]


## What the client attaches to attack / skill requests: selected target + cursor.
## Bots without targeting options send nothing (server picks the nearest monster).
func target_request(me: Node) -> Dictionary:
	if not _bot_next_req.is_empty():
		var r := _bot_next_req
		_bot_next_req = {}
		return r
	var req := {}
	var sel = NetUtil.selected
	if NetUtil.is_selected(sel) and sel.zone == me.zone:
		if sel.has_method("take_damage"):
			req = {"t": sel.monster_id, "k": "m"}
		else:
			req = {"t": sel.peer_id, "k": "p"}
	if bot_mode:
		if bot_aim and _bot_aim_point != null:
			req["aim"] = _bot_aim_point
			if not req.has("t"):
				req["t"] = -1
		return req
	if not req.has("t"):
		req["t"] = -1
	req["aim"] = _cursor_zone_pos(me)
	return req


## Esc (chat input handles its own Esc): close the topmost open panel, else toggle the menu.
## (Clearing the target is done by clicking empty ground.)
func handle_escape() -> void:
	if pause_menu.visible:
		pause_menu.close_menu()
		return
	for pn in [["hideout", hideout_ui], ["market", market_ui], ["map device / merchant", map_ui], ["atlas", atlas_ui], ["blacksmith", smith_ui],
			["passive web", talent_ui], ["character sheet", char_sheet], ["inventory", inventory_ui]]:
		if pn[1].visible:
			pn[1].visible = false
			item_tip.hide_tip()
			if menu_test:
				_log("Esc closed the %s panel" % pn[0])
			return
	hold_slot = -1
	pause_menu.open_menu()


## True while the Esc menu is open: the local player sends no movement / skill input.
func menu_open() -> bool:
	return pause_menu != null and pause_menu.visible


## Return to Main Menu / Quit Game: save (host), disconnect cleanly, then reload or quit.
func leave_game(to_menu: bool) -> void:
	if not to_menu:
		shutdown()
		return
	if _shutting_down:
		return
	_shutting_down = true
	var is_srv := multiplayer.has_multiplayer_peer() and multiplayer.is_server() and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if is_srv:
		if in_game:
			save_all("return to menu")
		for z in zones.values():
			for root in [z.players_root, z.monsters_root, z.loot_root, z.proj_root]:
				for n in root.get_children():
					n.queue_free()
		await get_tree().process_frame
	elif multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		get_tree().paused = true
		multiplayer.multiplayer_peer.disconnect_peer(1)
		await get_tree().create_timer(0.3).timeout
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	_log("left the game, back to the main menu")
	PauseMenuScript.returned_to_menu = true
	# reload while still paused (no entity may touch the closed peer); the new Main unpauses
	get_tree().paused = true
	class_select.visible = false
	multiplayer.multiplayer_peer = null
	get_tree().reload_current_scene()


func _load_client_settings() -> void:
	if not is_dedicated:
		PauseMenuScript.load_settings()


func _settings_test() -> void:
	var M = PauseMenuScript
	M.master_volume = 0.35
	M.fullscreen = false
	M.show_damage_numbers = false
	var err: int = M.save_settings()
	M.master_volume = 1.0
	M.show_damage_numbers = true
	M.load_settings()
	var ok: bool = err == OK and absf(M.master_volume - 0.35) < 0.001 and not M.show_damage_numbers and not M.fullscreen \
		and not NetUtil.show_popups and absf(AudioServer.get_bus_volume_db(0) - linear_to_db(0.35)) < 0.01
	print("SETTINGS TEST %s: saved to %s (err %d), reloaded volume %.2f, damage numbers %s, fullscreen %s, bus 0 %.1f dB" % ["OK" if ok else "FAILED",
		ProjectSettings.globalize_path(M.settings_path), err, M.master_volume, M.show_damage_numbers, M.fullscreen, AudioServer.get_bus_volume_db(0)])
	get_tree().quit(0 if ok else 1)


func toggle_inventory() -> void:
	inventory_ui.visible = not inventory_ui.visible
	inventory_ui.set_player(_local_player())
	inventory_ui.refresh()
	if not inventory_ui.visible:
		item_tip.hide_tip()
		inventory_ui.apply_orb = ""
		smith_ui.visible = false


## E next to the Map Device / Ticket Merchant: open/close the dungeon panel.
func toggle_map_ui(mode: String) -> void:
	var me := _local_player()
	if me == null:
		return
	if map_ui.visible and map_ui.mode == mode:
		map_ui.visible = false
		return
	map_ui.set_player(me)
	if not me.inventory_changed.is_connected(map_ui.refresh):
		me.inventory_changed.connect(map_ui.refresh)
	map_ui.open(mode)
	map_ui.visible = true
	if mode == "device" and not inventory_ui.visible:
		toggle_inventory()


## E at the Hideout Master / H: open/close the hideout panel; H in your hideout also toggles decoration mode.
func toggle_hideout_ui(from_key := false) -> void:
	var me := _local_player()
	if me == null:
		return
	hideout_ui.set_player(me, self)
	if not me.inventory_changed.is_connected(hideout_ui.refresh):
		me.inventory_changed.connect(hideout_ui.refresh)
	if from_key and hideout_ui.in_hideout():
		if not hideout_ui.visible:
			hideout_ui.visible = true
		hideout_ui.toggle_mode()
		if not hideout_ui.deco_mode:
			hideout_ui.visible = false
		return
	if from_key and not hideout_ui.visible:
		return   # H does nothing outside your hideout (the Hideout Master opens the panel there)
	hideout_ui.visible = not hideout_ui.visible
	if not hideout_ui.visible and hideout_ui.deco_mode:
		hideout_ui.toggle_mode()
	hideout_ui.refresh()


## E next to the Trade Broker: open/close the market panel (with the inventory beside it).
func toggle_market_ui(tab := "") -> void:
	var me := _local_player()
	if me == null:
		return
	if market_ui.visible and tab == "":
		market_ui.visible = false
		item_tip.hide_tip()
		return
	market_ui.set_player(me, market)
	if not me.inventory_changed.is_connected(market_ui.refresh):
		me.inventory_changed.connect(market_ui.refresh)
	market_ui.visible = true
	market_ui.show_tab(tab if tab != "" else market_ui.tab)
	market_ui.refresh()
	if not inventory_ui.visible:
		toggle_inventory()


## E next to the anvil: open/close the blacksmith (with the inventory beside it).
func toggle_smith() -> void:
	var me := _local_player()
	if me == null:
		return
	smith_ui.visible = not smith_ui.visible and me.near_blacksmith()
	if smith_ui.visible:
		smith_ui.set_player(me)
		if not me.inventory_changed.is_connected(smith_ui.refresh):
			me.inventory_changed.connect(smith_ui.refresh)
		smith_ui.refresh()
		if not inventory_ui.visible:
			toggle_inventory()
	item_tip.hide_tip()


# ================================================================ per-frame

func _process(delta: float) -> void:
	_elapsed += delta
	if _quit_after > 0.0 and _elapsed >= _quit_after:
		_log("quit-after reached, exiting")
		_quit_after = -1.0
		shutdown()
		return
	if _screenshot_path != "" and _elapsed > _screenshot_delay and _screenshot_ready():
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png(_screenshot_path)
		_log("screenshot saved to %s (err %d)" % [_screenshot_path, err])
		_screenshot_path = ""
	chat_active = chat_edit != null and chat_edit.has_focus()
	if not in_game:
		return
	if multiplayer.is_server():
		_save_timer += delta
		if _save_timer >= SAVE_INTERVAL:
			_save_timer = 0.0
			save_all("periodic")
	if bot_mode:
		_bot_update(delta)
	_log_timer += delta
	if _log_timer >= 3.0:
		_log_timer = 0.0
		_log_status()
	_update_hud(delta)


## Shows only `zone_id`'s map + entities on this peer (and the entry banner).
func _show_zone(zone_id: String, announce := true) -> void:
	_shown_zone = zone_id
	for id in zones:
		zones[id].visible = id == zone_id
	if announce and banner_label:
		var zi := Zones.info(zone_id)
		banner_label.text = "%s\n%s" % [zi["name"], "Safe haven  -  Lv " + zi["levels"] if zi.get("safe", false) else "Monsters Lv " + zi["levels"]]
		_banner_t = 3.5
		_log("Entered zone %s (%s)" % [zone_id, zi["name"]])
		if zi.has("dungeon"):
			var d: Dictionary = zi["dungeon"]
			banner_label.text = "%s\nMonsters Lv %s  -  %s" % [zi["name"], zi["levels"], "map iiq +%d%% iir +%d%%" % [roundi(d.get("iiq", 0.0)), roundi(d.get("iir", 0.0))]]


func _update_hud(delta: float) -> void:
	if is_dedicated:
		return
	var me := _local_player()
	if me and me.zone and me.zone.zone_id != _shown_zone:
		_show_zone(me.zone.zone_id)
	if _banner_t > 0.0:
		_banner_t -= delta
		banner_label.visible = true
		banner_label.modulate.a = clampf(_banner_t, 0.0, 1.0)
	else:
		banner_label.visible = false
	var here := 0
	if zones.has(_shown_zone):
		here = zones[_shown_zone].players_root.get_child_count()
	info_label.text = "Players here: %d\nWASD move  Space attack  1-4 skills\nClick/Tab target  Esc menu  E pick up\nQ potion  I inventory  C character\nT passive web  Enter chat" % here
	if me == null:
		target_frame.visible = false
		return
	_update_target_frame(me)
	preview_slot = hold_slot if hold_slot >= 0 else hover_slot
	if _debug_preview >= 0 and _elapsed > 3.0:
		preview_slot = _debug_preview
		var off := Vector2(_debug_preview_cell) if _debug_preview_cell != Vector2i(-1, -1) else Vector2(120, -40)
		Input.warp_mouse(me.get_global_transform_with_canvas().origin + off)
	if _open_talents:
		_open_talents = false
		talent_ui.visible = true
	talent_ui.set_player(me)
	if _warp_pending and _elapsed >= _warp_delay:
		_warp_pending = false
		request_warp.rpc_id(1, _warp_to, _warp_cell)
	var zi := Zones.info(me.zone.zone_id)
	zone_label.text = "%s  (Lv %s)" % [zi["name"], zi["levels"]]
	if zi.has("dungeon"):
		var dd: Dictionary = zi["dungeon"]
		var aq: float = Dungeons.atlas_iiq(me.atlas)
		zone_label.text += "   Map: +%d%% quantity (+%d%% atlas)  +%d%% rarity%s" % [roundi(dd.get("iiq", 0.0)), roundi(aq), roundi(dd.get("iir", 0.0)),
			("  -  %d portals left" % int(me.run_info["portals"])) if not me.run_info.is_empty() else ""]
	if _open_inventory:
		_open_inventory = false
		toggle_inventory()
	if _open_map_ui != "" and _elapsed > 6.0 and (me.near_map_device() if _open_map_ui == "device" else me.near_merchant()):
		toggle_map_ui(_open_map_ui)
		_open_map_ui = ""
		for inst in me.bag:
			if Dungeons.is_ticket(inst) and (inst["rarity"] == "rare" or map_ui.selected_uid < 0):
				map_ui.select(inst)
		_log("map panel opened (%s), selected %s" % [map_ui.mode, map_ui.selected_uid])
	if _open_market != "" and _elapsed > _open_market_at and me.near_broker():
		var parts := _open_market.split(":")
		market_ui.show_first_tip = market_tip
		toggle_market_ui(parts[0])
		if parts[0] == "browse" and parts.size() > 1:
			var f := {}
			for kv in parts[1].split(","):
				f[kv.get_slice("=", 0)] = kv.get_slice("=", 1)
			if f.has("usable"):
				f["usable"] = true
			market_ui.set_filters(f)
			market_ui.search(0)
		elif parts[0] == "sell":
			for inst in me.bag:
				if inst["rarity"] == "rare" and not Dungeons.is_ticket(inst):
					market_ui.select_uid(int(inst["uid"]))
					market_ui._price.value = 450
					break
		_log("market panel opened on %s" % _open_market)
		_open_market = ""
	if _open_menu_at >= 0.0 and _elapsed > _open_menu_at:
		_open_menu_at = -1.0
		pause_menu.open_menu()
	if _hideout_shot != "" and _elapsed > 5.0 and me.zone and me.zone.has_method("is_hideout") and me.zone.is_hideout():
		var shot := _hideout_shot
		_hideout_shot = ""
		if shot == "mode":
			toggle_hideout_ui(true)
			hideout_ui.selected = "pine"
			hideout_ui.refresh()
		_log("hideout screenshot setup: %s (theme %s, %d decorations)" % [shot, me.zone.info["hideout"]["theme"], me.zone.info["hideout"]["decor"].size()])
	if _open_atlas and _elapsed > 5.0:
		_open_atlas = false
		atlas_ui.visible = true
		atlas_ui.set_player(me)
		var arg := _open_atlas_arg.split("@")
		atlas_ui.set_tab("tree" if arg[0] == "tree" else "map")
		if arg.size() > 1:
			atlas_ui.force_hover = arg[1]
			if arg[0] != "tree":
				atlas_ui.select_node(arg[1])
		_log("atlas panel opened: %s | %d nodes: %s" % [me.atlas, Atlas.nodes().size(), _atlas_states(me.atlas)])
	if _open_smith and _elapsed > 6.0 and me.near_blacksmith() and not me.bag.is_empty():
		_open_smith = false
		toggle_smith()
		for inst in me.bag:
			if inst["rarity"] == "rare":
				smith_ui.select(inst)
				_log("blacksmith panel opened with %s selected" % Gear.summary(inst))
				break
	if _debug_tooltip >= 0 and inventory_ui.visible and _elapsed > 5.0:
		var entries: Array = inventory_ui.bag_entries()
		var gear_i := 0
		for i in entries.size():
			if entries[i].has("inst"):
				if gear_i == _debug_tooltip:
					inventory_ui.show_tooltip_for(inventory_ui._bag_slots[i])
					_log("showing tooltip for %s" % Gear.summary(entries[i]["inst"]))
					_debug_tooltip = -2
					break
				gear_i += 1
	if _open_sheet:
		_open_sheet = false
		char_sheet.visible = true
	inventory_ui.set_player(me)
	char_sheet.set_player(me)
	skill_bar.player = me
	stats_name.text = "%s   Level %d" % [me.display_name, me.level]
	class_label.text = "%s  -  %s" % [Classes.info(me.class_id)["name"], Classes.element_name(me.element)]
	class_label.add_theme_color_override("font_color", Classes.color(me.element))
	mp_bar.max_value = me.max_mp
	mp_bar.value = me.mp
	mp_text.text = "MP %d / %d" % [me.mp, me.max_mp]
	hp_bar.max_value = me.max_hp
	hp_bar.value = me.hp
	hp_text.text = "HP %d / %d" % [me.hp, me.max_hp]
	xp_bar.max_value = me.xp_next
	xp_bar.value = me.xp
	xp_text.text = "XP %d / %d" % [me.xp, me.xp_next]
	stats_line.text = "ATK %d   DEF %d   Gold %d" % [me.attack, me.defense, me.gold]
	dead_label.visible = me.dead


func _update_target_frame(me: Node) -> void:
	var sel = NetUtil.selected
	if sel != null and (not is_instance_valid(sel) or sel.is_queued_for_deletion() or sel.zone != me.zone):
		NetUtil.selected = null
		sel = null
	if sel != null and "alive" in sel and not sel.alive:
		NetUtil.selected = null    # it died
		sel = null
	target_frame.visible = sel != null
	if sel == null:
		return
	var is_monster: bool = sel.has_method("take_damage")
	var el: String = sel.element
	_tf_icon.texture = Classes.element_icon(el) if el != "" else null
	if is_monster:
		_tf_name.text = "%s%s  Lv %d   %s" % ["★ " if sel.is_boss else "", sel.display_name, sel.level, Classes.element_name(el)]
	else:
		_tf_name.text = "%s  Lv %d   %s (ally)" % [sel.display_name, sel.level, Classes.info(sel.class_id)["name"]]
	_tf_name.add_theme_color_override("font_color", Classes.color(el).lerp(Color.WHITE, 0.4))
	_tf_hp.max_value = sel.max_hp
	_tf_hp.value = sel.hp
	var d: float = me.position.distance_to(sel.position)
	_tf_hp_text.text = "HP %d / %d     %d px away" % [sel.hp, sel.max_hp, roundi(d)]
	var st: Array = []
	var f: int = sel.status_flags
	if is_monster:
		if f & 1: st.append("[color=#70ff70]Poisoned[/color]")
		if f & 2: st.append("[color=#ff9040]Burning[/color]")
		if f & 4: st.append("[color=#80c0ff]Slowed[/color]")
		if f & 8: st.append("[color=#ffee60]Stunned[/color]")
		var mine := Classes.multiplier(me.element, el)
		if mine > 1.0: st.append("[color=#ffd070]weak to you (x1.25)[/color]")
		elif mine < 1.0: st.append("[color=#a0a0a0]resists you (x0.80)[/color]")
	else:
		if f & 1: st.append("[color=#d0a060]Shield[/color]")
		if f & 2: st.append("[color=#ffe070]Blade Focus[/color]")
		if f & 4: st.append("[color=#70ff70]Regrowth[/color]")
		if f & 8: st.append("[color=#c09060]Fortified[/color]")
		if sel.dead: st.append("[color=#ff6060]Defeated[/color]")
	_tf_status.text = "  ".join(st) if not st.is_empty() else "[color=#808080]no effects[/color]"


## Clean shutdown: save, despawn networked nodes and close the connection
## before quitting (avoids noisy engine teardown messages in exported builds).
func shutdown(exit_code := 0) -> void:
	if _shutting_down:
		return
	_shutting_down = true
	set_process(false)
	var is_srv := multiplayer.has_multiplayer_peer() and multiplayer.is_server() \
		and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer)
	if is_srv:
		if in_game:
			save_all("shutdown")
		# only the server owns replicated nodes; free them so clients get despawns
		for z in zones.values():
			for root in [z.players_root, z.monsters_root, z.loot_root, z.proj_root]:
				for n in root.get_children():
					n.queue_free()
		await get_tree().process_frame
	if multiplayer.multiplayer_peer and not is_srv and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		# client: polite disconnect, give the server a moment to process it
		get_tree().paused = true  # stop entity scripts from using the closing peer
		multiplayer.multiplayer_peer.disconnect_peer(1)
		await get_tree().create_timer(0.3).timeout
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	await get_tree().process_frame
	get_tree().quit(exit_code)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		get_tree().auto_accept_quit = false
		shutdown()


func _local_player() -> Node:
	if not multiplayer.has_multiplayer_peer() or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return null
	return _player_node(multiplayer.get_unique_id())


## Bot: equip better gear (simple score), try a forbidden item once to exercise the server check.
func _bot_gear(me: Node) -> void:
	if me.bag_full() and not _bot_full_tried:
		for sl in Items.SLOTS:
			if not me.equipment.get(sl, {}).is_empty():
				_bot_full_tried = true
				_log("bag is full (%d/%d) - trying to unequip %s anyway" % [me.bag_used(), Items.BAG_SIZE, sl])
				me.request_unequip(sl)
				break
	if bot_no_gear:
		return
	for inst in me.bag:
		var base := str(inst["base"])
		if not Items.can_use(base, me.class_id):
			if not _bot_tried_forbidden.has(base):   # once, to exercise the server-side check
				_bot_tried_forbidden[base] = true
				_log("trying to equip %s (not allowed for %s)" % [base, me.class_id])
				me.request_equip(int(inst["uid"]))
			continue
		if me.level < Gear.req_level(inst):
			continue
		var best_slot := ""
		var best_gain := 0.0
		for sl in Items.slots_for(base):
			var gain := Gear.score(inst) - Gear.score(me.equipment.get(sl, {}))
			if gain > best_gain + 0.01:
				best_gain = gain
				best_slot = sl
		if best_slot != "":
			_log("equipping %s in %s" % [Gear.summary(inst), best_slot])
			me.request_equip(int(inst["uid"]), best_slot)
			return


## Test bot for dungeon runs (--bot-dungeon=full|die|enter|intrude). Returns true when it drove this frame.
func _bot_dungeon(me: Node, zone: Node, delta: float) -> bool:
	_bd_t -= delta
	var town: bool = zone.zone_id == "meadow"
	if _elapsed < 3.0:
		bot_dir = Vector2.ZERO
		return true
	if town and bot_atlas and (_ba == 0 or _bd_step == 9) and _ba != 99:
		return _bot_atlas(me, zone, delta)
	if town:
		if _bd_step in [4, 5]:   # back from a dungeon (left, died or kicked out)
			_bd_step = 3
			_bd_t = 3.0
			_log("dungeon bot: back in town (entries %d), run %s, atlas %s" % [_bd_entries, me.run_info, me.atlas.get("done", {})])
		if _bd_step == 0:     # walk to the merchant, take the free ticket, buy one
			if not me.near_merchant():
				bot_dir = _bot_steer(zone, me.position, zone.merchant_pos() + Vector2(0, 24), delta)
				return true
			bot_dir = Vector2.ZERO
			_log("dungeon bot: at the merchant, gold %d, atlas %s, free ticket %s" % [me.gold, me.atlas.get("done", {}), "taken" if me.free_day != "" else "available"])
			me.request_dungeon("free", {"theme": bot_dungeon_theme})
			me.request_dungeon("free", {"theme": bot_dungeon_theme})                        # invalid: once a day
			me.request_dungeon("buy", {"theme": bot_dungeon_theme, "tier": bot_dungeon_tier})
			me.request_dungeon("buy", {"theme": bot_dungeon_theme, "tier": 9})               # invalid: not unlocked (T1-T3 + atlas)
			_bd_step = 1
			_bd_t = 1.5
			return true
		if _bd_step == 1:     # craft the bought ticket
			bot_dir = Vector2.ZERO
			if _bd_t > 0.0:
				return true
			var best := {}
			for inst in me.bag:
				if Dungeons.is_ticket(inst) and Dungeons.theme_of(inst) == bot_dungeon_theme and Dungeons.tier_of(inst) == bot_dungeon_tier and inst["rarity"] == "normal":
					best = inst
			if bot_dungeon_unique:
				best = {}
				for inst in me.bag:
					if Dungeons.is_ticket(inst) and inst["rarity"] == "unique":
						best = inst
			if best.is_empty():
				for inst in me.bag:
					if Dungeons.is_ticket(inst):
						best = inst
			if best.is_empty():
				_log("dungeon bot: no ticket in the bag!")
				_bd_step = 9
				return true
			_bd_ticket = int(best["uid"])
			_log("dungeon bot: crafting %s" % Gear.summary(best))
			if bot_dungeon in ["full", "enter"]:
				me.request_craft("orb_chisel", _bd_ticket)
				me.request_craft("orb_chisel", _bd_ticket)
				me.request_craft("orb_transmute", _bd_ticket)
				me.request_craft("orb_regal", _bd_ticket)
				me.request_craft("enhance_stone", _bd_ticket)     # invalid: tickets can't be enhanced
			_bd_step = 3 if bot_dungeon == "intrude" else 2
			_bd_t = 2.0
			return true
		if _bd_step == 2:     # open it at the map device
			if _bd_t > 0.0:
				bot_dir = Vector2.ZERO
				return true
			if not me.near_map_device():
				bot_dir = _bot_steer(zone, me.position, zone.map_device_pos() + Vector2(0, 28), delta)
				return true
			bot_dir = Vector2.ZERO
			var t := _bag_uid(me, _bd_ticket)
			_log("dungeon bot: opening %s - %s" % [Gear.summary(t), Dungeons.run_info(t) if not t.is_empty() else {}])
			me.request_dungeon("open", {"uid": _bd_ticket})
			_bd_step = 3
			_bd_t = 2.0
			return true
		if _bd_step == 3:     # walk into my portal (or, as the intruder, someone else's)
			if _bd_t > 0.0 or me.dead:
				bot_dir = Vector2.ZERO
				return true
			if bot_dungeon == "enter" and _bd_entries >= 1 or bot_dungeon == "die" and _bd_entries >= Dungeons.PORTALS or bot_dungeon == "full" and _bd_done_t >= 0.0:
				if _bd_step != 9:
					_log("dungeon bot: finished - back in town, atlas %s, run %s, bag tickets %s" % [me.atlas.get("done", {}), me.run_info, _ticket_list(me)])
				_bd_step = 9
				return true
			for mp_ in zone.map_portals:
				var mine: bool = str(mp_["owner"]) == me.display_name
				if mine != (bot_dungeon == "intrude"):
					bot_dir = _bot_steer(zone, me.position, mp_["pos"], delta)
					return true
			bot_dir = Vector2.ZERO
			return true
		bot_dir = Vector2.ZERO
		return true
	# ---- inside a dungeon
	if _bd_step == 3:
		_bd_step = 4
		_bd_entries += 1
		_bd_t = 0.0
		_log("dungeon bot: inside %s (entry %d), run %s" % [zone.zone_id, _bd_entries, me.run_info])
	if bot_dungeon == "die":
		bot_dir = Vector2.ZERO      # stand still and let the monsters win
		if me.dead or me.hp <= 0:
			_bd_step = 5
		elif _bd_t < -1.0:   # nothing around yet: walk at the nearest pack
			var n: Node2D = _nearest(zone.monsters_root, me.position, 3000.0)
			if n:
				bot_dir = _bot_steer(zone, me.position, n.position, delta)
		return true
	if bot_dungeon == "enter":
		bot_dir = Vector2.ZERO
		if _bd_t < -10.0:   # leave through the exit portal after a while
			bot_dir = _bot_steer(zone, me.position, zone.map.cell_pos(Zones.info(zone.zone_id)["portals"][0]["rect"].get_center()), delta)
			if _bd_step == 4:
				_bd_step = 5
				_log("dungeon bot: leaving %s" % zone.zone_id)
		return true
	# full: fight (normal bot AI) until the run is complete, loot, then leave
	if me.dead:
		_bd_step = 5
		return false
	if me.run_info.get("completed", false) and _bd_done_t < 0.0:
		_bd_done_t = _elapsed
		_log("dungeon bot: run completed, looting")
	if _bd_done_t >= 0.0 and _elapsed - _bd_done_t > 10.0:
		bot_dir = _bot_steer(zone, me.position, zone.map.cell_pos(Zones.info(zone.zone_id)["portals"][0]["rect"].get_center()), delta)
		me.request_pickup()
		_bd_step = 5
		return true
	return false


## Atlas test script around a normal "full" dungeon run (see run_local_test.sh phase 8).
func _bot_atlas(me: Node, zone: Node, delta: float) -> bool:
	_ba_t -= delta
	if _ba_t > 0.0:
		bot_dir = Vector2.ZERO
		return true
	var at_device := func() -> bool:
		if me.near_map_device():
			bot_dir = Vector2.ZERO
			return true
		bot_dir = _bot_steer(zone, me.position, zone.map_device_pos() + Vector2(0, 28), delta)
		return false
	var at_merchant := func() -> bool:
		if me.near_merchant():
			bot_dir = Vector2.ZERO
			return true
		bot_dir = _bot_steer(zone, me.position, zone.merchant_pos() + Vector2(0, 24), delta)
		return false
	match _ba:
		0:   # before the first run: no points yet, and a ticket for a locked node
			if not at_device.call():
				return true
			if not _bd_ticket_has(me, "fire:3"):
				me.request_dungeon("debug_kit")
				me.request_dungeon("atlas_alloc", {"id": "a_ring_water"})     # invalid: no atlas points yet
				_ba_t = 1.5
				return true
			for inst in me.bag:
				if Dungeons.is_ticket(inst) and Atlas.node_of_ticket(inst) == "fire:3":
					_log("atlas bot: trying the locked node %s with %s" % [Atlas.display("fire:3"), Gear.summary(inst)])
					me.request_dungeon("open", {"uid": int(inst["uid"])})   # invalid: fire:3 is locked
			_ba = 1
			_ba_t = 1.5
			return true
		1:
			_ba = 2
			return false   # continue with the normal "full" run
		2:   # first run done: wait for the atlas update to reach this (new) player node
			_ba = 21
			_ba_t = 3.0
		21:   # spend the points
			_log("atlas bot: back from the run, atlas %s, points %d free" % [me.atlas, Atlas.points_free(me.atlas)])
			me.request_dungeon("atlas_alloc", {"id": "a_metal_5"})      # invalid: not connected
			me.request_dungeon("atlas_alloc", {"id": "a_ring_water"})
			me.request_dungeon("atlas_alloc", {"id": "a_water_1"})      # +1 portal
			me.request_dungeon("atlas_alloc", {"id": "a_fire_1"})       # invalid: no points left (2 earned)
			_ba = 3
			_ba_t = 2.0
		3:   # the neighbour fire:2 is now unlocked at the merchant, fire:3 still isn't
			if not at_merchant.call():
				return true
			var freed := 0
			for inst in me.bag:     # make room (the debug kit fills the bag with gear)
				if not Dungeons.is_ticket(inst) and freed < 3:
					me.request_destroy(int(inst["uid"]))
					freed += 1
			me.request_dungeon("buy", {"theme": "fire", "tier": 2})
			me.request_dungeon("buy", {"theme": "fire", "tier": 3})    # invalid: locked
			_ba = 4
			_ba_t = 1.5
		4:   # open fire:2: 7 portals with the passive
			if not at_device.call():
				return true
			for inst in me.bag:
				if Dungeons.is_ticket(inst) and Atlas.node_of_ticket(inst) == "fire:2" and inst.get("rarity") != "unique":
					_log("atlas bot: opening the newly unlocked %s" % Atlas.display("fire:2"))
					me.request_dungeon("open", {"uid": int(inst["uid"])})
					break
			_ba = 5
			_ba_t = 2.0
		5:   # respec for gold, again (nothing to refund), re-allocate one passive
			_log("atlas bot: run %s" % me.run_info)
			me.request_dungeon("atlas_respec")
			me.request_dungeon("atlas_respec")     # invalid: nothing allocated
			me.request_dungeon("atlas_alloc", {"id": "a_ring_fire"})
			_ba = 6
			_ba_t = 2.0
		6:
			_log("atlas bot: done, atlas %s, points %d/%d spent" % [me.atlas, Atlas.points_spent(me.atlas), Atlas.points_earned(me.atlas)])
			_ba = 99
	bot_dir = Vector2.ZERO
	return true


func _bd_ticket_has(me: Node, nid: String) -> bool:
	for inst in me.bag:
		if Dungeons.is_ticket(inst) and Atlas.node_of_ticket(inst) == nid:
			return true
	return false


func _ticket_list(me: Node) -> String:
	var out: Array = []
	for inst in me.bag:
		if Dungeons.is_ticket(inst):
			out.append(Gear.summary(inst))
	return "[%s]" % ", ".join(out)


var _bh_step := 0
var _bh_t := 0.0
var _bh_ticket := -1


func _bh_log(me: Node, what: String) -> void:
	_log("hideout bot: %s | zone %s, %s" % [what, me.zone.zone_id, Hideouts.summary(me.hideout)])


## Test bot for hideouts (--bot-hideout=1: first session, 2: after a server restart).
func _bot_hideout(me: Node, zone: Node, delta: float) -> void:
	bot_dir = Vector2.ZERO
	_bh_t -= delta
	if _elapsed < 3.0 or _bh_t > 0.0:
		return
	var hu: Node = hideout_ui
	hu.set_player(me, self)
	if bot_hideout == "2":
		match _bh_step:
			0:
				_bh_log(me, "logged back in (restart)")
				_bh_step = 1
			1:   # leave through the door
				if zone.is_hideout():
					bot_dir = _bot_steer(zone, me.position, zone.map.cell_pos(Hideouts.DOOR.get_center()) + Vector2(0, 8), delta)
				else:
					_bh_log(me, "left the hideout through the door")
					_bh_step = 2
			2:
				me.request_hideout("theme", {"id": "earth"})   # rejected: not in the hideout
				send_chat("/hideout")
				_bh_step = 3
				_bh_t = 3.0
			3:
				_bh_log(me, "back via /hideout")
				_bh_step = 99
		return
	match _bh_step:
		0:   # walk to the Hideout Master
			if not me.near_hideout_master():
				bot_dir = _bot_steer(zone, me.position, zone.hideout_master_pos() + Vector2(0, 28), delta)
				return
			toggle_hideout_ui()
			_bh_log(me, "at the Hideout Master, panel %s" % ("open" if hideout_ui.visible else "closed"))
			me.request_hideout("place", {"id": "flowers", "x": 22, "y": 13})   # rejected: not in the hideout
			me.request_hideout("buy", {"id": "pond", "count": 50})              # rejected: not enough gold (13000)
			me.request_hideout("debug_gold")
			_bh_step = 1
			_bh_t = 1.5
		1:
			me.request_hideout("buy", {"id": "pine", "count": 2})
			me.request_hideout("buy", {"id": "statue"})
			me.request_hideout("buy", {"id": "pond"})
			me.request_hideout("buy", {"id": "bogus"})            # rejected
			_bh_step = 2
			_bh_t = 1.5
		2:
			_bh_log(me, "bought decorations")
			toggle_hideout_ui()
			send_chat("/hideout")
			_bh_step = 3
			_bh_t = 3.0
		3:
			if not zone.is_hideout():
				_bh_log(me, "NOT in the hideout yet")
				_bh_t = 2.0
				return
			_bh_log(me, "entered my hideout via /hideout")
			send_chat("/hideout")     # rejected: already there
			toggle_hideout_ui(true)   # H: panel + decoration mode
			hu.selected = "pine"
			hu.click(Vector2i(19, 13))
			hu.click(Vector2i(20, 13))
			hu.selected = "statue"
			hu.click(Vector2i(28, 14))
			hu.selected = "pond"
			hu.click(Vector2i(31, 27))      # rejected: door lane
			hu.click(Vector2i(5, 5))        # rejected: outside
			me.request_hideout("place", {"id": "pond", "x": 24, "y": 16})   # rejected: next to the map device
			hu.click(Vector2i(36, 20))
			me.request_hideout("place", {"id": "snowman", "x": 37, "y": 20})   # rejected: not owned
			me.request_hideout("place", {"id": "pine", "x": 38, "y": 20})      # rejected: both pines placed
			_bh_step = 4
			_bh_t = 1.5
		4:
			_bh_log(me, "placed decorations")
			var i: int = hu._decor_at(Vector2i(28, 14))
			hu.click(Vector2i(28, 14))        # pick the statue up...
			hu.click(Vector2i(27, 13))        # ...and move it
			me.request_hideout("move", {"index": i, "x": 32, "y": 26})   # rejected: door lane
			me.request_hideout("rotate", {"index": 0})
			me.request_hideout("flip", {"index": 0})
			me.request_hideout("remove", {"index": 99})                  # rejected
			_bh_step = 5
			_bh_t = 1.5
		5:
			_bh_log(me, "moved / rotated / flipped")
			hu.click(Vector2i(20, 13), true)  # right click: remove the second pine
			me.request_hideout("station", {"station": "broker", "x": 31, "y": 26})   # rejected: door
			me.request_hideout("station", {"station": "broker", "x": 21, "y": 26})
			me.request_hideout("theme", {"id": "fire"})
			me.request_hideout("theme", {"id": "water"})   # rejected: locked
			me.request_hideout("theme", {"id": "nope"})    # rejected
			_bh_step = 6
			_bh_t = 2.0
		6:
			_bh_log(me, "removed one, moved the broker, theme switched")
			_log("hideout bot: client zone theme %s, %d decoration sprites" % [zone.info["hideout"]["theme"],
				zone.get_node("HideoutDeco").get_children().filter(func(n): return n is Sprite2D).size() if zone.has_node("HideoutDeco") else -1])
			# limit: own plenty of rocks, then fill the room past 200
			me.request_hideout("buy", {"id": "rock", "count": 50})
			me.request_hideout("buy", {"id": "rock", "count": 50})
			me.request_hideout("buy", {"id": "rock", "count": 50})
			me.request_hideout("buy", {"id": "rock", "count": 50})
			me.request_hideout("buy", {"id": "rock", "count": 10})
			_bh_step = 7
			_bh_t = 2.0
		7:
			var n := 0
			for y in range(Hideouts.ROOM.position.y, Hideouts.ROOM.end.y):
				for x in range(Hideouts.ROOM.position.x, Hideouts.ROOM.end.x):
					if Hideouts.blocked_reason(me.hideout, Vector2i(x, y)) == "" and n < 205:
						me.request_hideout("place", {"id": "rock", "x": x, "y": y})
						n += 1
			_log("hideout bot: sent %d rock placements" % n)
			_bh_step = 8
			_bh_t = 4.0
		8:
			_bh_log(me, "after filling")
			# clear the rocks again (keep the room usable): remove from the end
			var idx: Array = []
			for i in me.hideout["decor"].size():
				if me.hideout["decor"][i]["id"] == "rock":
					idx.append(i)
			idx.reverse()
			for i in idx:
				me.request_hideout("remove", {"index": i})
			_bh_step = 9
			_bh_t = 4.0
		9:
			_bh_log(me, "rocks removed")
			hu.toggle_mode()
			me.request_dungeon("free", {"theme": "wood"})   # the hideout's Ticket Merchant (must be near it)
			_bh_step = 10
		10:   # Ticket Merchant in the hideout
			if not me.near_merchant():
				bot_dir = _bot_steer(zone, me.position, zone.merchant_pos() + Vector2(24, 0), delta)
				return
			me.request_dungeon("free", {"theme": "wood"})
			_bh_step = 11
			_bh_t = 2.0
		11:   # Map Device in the hideout
			for inst in me.bag:
				if Dungeons.is_ticket(inst):
					_bh_ticket = int(inst["uid"])
			if not me.near_map_device():
				bot_dir = _bot_steer(zone, me.position, zone.map_device_pos() + Vector2(28, 0), delta)
				return
			_bh_log(me, "opening ticket %d at the hideout Map Device" % _bh_ticket)
			me.request_dungeon("open", {"uid": _bh_ticket})
			_bh_step = 12
			_bh_t = 2.0
		12:   # walk into the portal below the device
			if zone.is_dungeon():
				_log("hideout bot: inside the dungeon opened from the hideout (zone %s, exit portal -> %s)" % [zone.zone_id, zone.info["portals"][0]["to"]])
				_bh_step = 13
				_bh_t = 2.0
				return
			if zone.map_portals.is_empty():
				return
			bot_dir = _bot_steer(zone, me.position, zone.map_portals[0]["pos"], delta)
		13:   # take the exit portal back
			if zone.is_hideout():
				_log("hideout bot: the dungeon exit portal returned me to the hideout (zone %s)" % zone.zone_id)
				_bh_step = 14
				_bh_t = 1.5
				return
			var pr: Dictionary = zone.info["portals"][0]
			bot_dir = _bot_steer(zone, me.position, zone.map.cell_pos(pr["rect"].get_center()), delta)
		14:
			_bh_log(me, "done - staying in the hideout until logout")
			_bh_step = 99


## Test bot for the trade market (--bot-market=ROLE): walks to the Trade Broker, then
## runs a timed script of market requests (the server validates / logs everything).
func _bot_market(me: Node, zone: Node, delta: float) -> void:
	if zone.zone_id != "meadow" or _elapsed < 3.0:
		bot_dir = Vector2.ZERO
		return
	if bot_market == "expirer" and not _bm_done.has("gift"):
		# first fetch the (account-bound) daily free ticket from the Ticket Merchant
		if not me.near_merchant():
			bot_dir = _bot_steer(zone, me.position, zone.merchant_pos() + Vector2(0, 30), delta)
			return
		bot_dir = Vector2.ZERO
		me.request_dungeon("free", {"theme": "fire"})
		_bm_done["gift"] = _elapsed
		return
	if not me.near_broker():
		bot_dir = _bot_steer(zone, me.position, zone.broker_pos() + Vector2(0, 30), delta)
		return
	bot_dir = Vector2.ZERO
	if not _bm_done.has("arrived"):
		_bm_done["arrived"] = _elapsed
		_log("market bot (%s): at the broker, gold %d, bag %d/%d" % [bot_market, me.gold, me.bag_used(), Items.BAG_SIZE])
	var t: float = _elapsed - float(_bm_done["arrived"])
	var steps: Array = []
	match bot_market:
		"seller":
			steps = [
				[1.0, func():
					me.request_market("list", {"uid": int(_bag_find(me, "chain_mail", "rare").get("uid", -1)), "price": 300})
					me.request_market("list", {"uid": int(_bag_find(me, "copper_ring").get("uid", -1)), "price": 50})
					me.request_market("list", {"stack": "orb_chaos", "n": 5, "price": 120})
					me.request_market("list", {"uid": int(_bag_find(me, "frost_aegis").get("uid", -1)), "price": 900})],
				[2.0, func(): me.request_market("list", {"uid": int(_bag_find(me, "horned_helm").get("uid", -1)), "price": 10})],   # over the max
				[3.0, func():
					me.request_market("list", {"uid": int(_bag_find(me, "leather_boots").get("uid", -1)), "price": 0})               # bad price
					_bm_ids["weapon"] = int(me.equipment["weapon"].get("uid", -1))
					me.request_unequip("weapon")],
				[4.5, func(): me.request_market("list", {"uid": int(_bm_ids["weapon"]), "price": 25})],                          # bound starter gear
				[5.0, func(): me.request_market("mine")],
				[6.0, func():
					var ls: Array = market.mine["listings"]
					_log("market bot: my listings %s" % [ls.map(func(l): return "#%d %s @%d" % [l["id"], Market.item_summary(l["item"]), l["price"]])])
					if not ls.is_empty():
						me.request_market("buy", {"id": int(ls[0]["id"]), "price": int(ls[0]["price"])})],                      # self-buy
			]
		"buyer":
			steps = [
				[9.0, func(): me.request_market("browse", {"filters": {"cat": "body", "rarity": "rare"}})],
				[9.5, func(): me.request_market("browse", {"filters": {"stat": "res:water", "stat_min": 25}})],
				[10.0, func(): me.request_market("browse", {"filters": {"text": "ring"}})],
				[10.5, func(): me.request_market("browse", {"filters": {"cat": "currency"}})],
				[11.0, func(): me.request_market("browse", {"filters": {"price_max": 100, "sort": "price_desc"}})],
				[11.5, func(): me.request_market("browse", {"filters": {"max_req": 5, "cat": "ring"}})],
				[12.0, func(): me.request_market("browse", {"filters": {"theme": "water", "tier_min": 3}})],
				[12.5, func(): me.request_market("browse", {"filters": {"sort": "newest"}})],
				[13.0, func(): me.request_market("browse", {"filters": {"usable": true, "cat": "offhand"}})],
				[16.0, func(): me.request_market("browse", {"filters": {"cat": "body", "rarity": "rare"}})],
				[17.0, func():
					var rows: Array = market.page["rows"]
					if not rows.is_empty():
						me.request_market("buy", {"id": int(rows[0]["id"]), "price": int(rows[0]["price"])})],
				[32.0, func(): me.request_market("browse", {"filters": {"cat": "currency"}})],
				[33.0, func():
					var rows: Array = market.page["rows"]
					if not rows.is_empty():
						me.request_market("buy", {"id": int(rows[0]["id"]), "price": int(rows[0]["price"])})],
			]
		"race":
			steps = [
				[18.0, func(): me.request_market("browse", {"filters": {"text": "copper"}})],
				[19.0, func():
					_log("race bot: page %s" % [market.page["rows"].map(func(l): return l["id"])])
					if not market.page["rows"].is_empty():
						_bm_ids["race"] = int(market.page["rows"][0]["id"])],
				[20.0, func():   # both racers fire in the same second (the server serializes them)
					if _bm_ids.has("race"):
						me.request_market("buy", {"id": _bm_ids["race"], "price": 50})],
			]
		"pauper":
			steps = [
				[9.0, func(): me.request_market("list", {"stack": "health_potion", "n": 1, "price": 500})],    # can't pay the fee
				[10.0, func(): me.request_market("browse", {"filters": {"rarity": "unique"}})],
				[11.0, func():
					if not market.page["rows"].is_empty():
						me.request_market("buy", {"id": int(market.page["rows"][0]["id"]), "price": -1})],
			]
		"fullbag":
			steps = [
				[10.0, func(): me.request_market("browse", {"filters": {"rarity": "unique"}})],
				[11.0, func():
					if not market.page["rows"].is_empty():
						me.request_market("buy", {"id": int(market.page["rows"][0]["id"]), "price": -1})],
			]
		"expirer":
			steps = [
				[1.0, func():
					me.request_market("list", {"uid": int(_bag_find(me, "ticket_water").get("uid", -1)), "price": 200})
					me.request_market("list", {"uid": int(_bag_find(me, "leather_cap").get("uid", -1)), "price": 40})],
				[2.0, func():
					var gift: Dictionary = {}
					for i in me.bag:
						if Dungeons.is_ticket(i) and bool(i.get("bound", false)):
							gift = i
					_log("expirer bot: free ticket in bag: %s" % (Gear.summary(gift) if not gift.is_empty() else "none"))
					me.request_market("list", {"uid": int(gift.get("uid", -1)), "price": 80})],                                  # bound daily gift
				[3.0, func():
					for l in market.mine["listings"]:
						if not Market.is_stack(l["item"]) and l["item"]["base"] == "leather_cap":
							me.request_market("cancel", {"id": int(l["id"])})],
				[30.0, func(): me.request_market("claim")],
				[31.0, func(): _log("expirer bot: bag tickets %s" % [me.bag.filter(func(i): return Dungeons.is_ticket(i)).map(func(i): return Gear.summary(i))])],
			]
		"stocker":    # screenshots: put a bit of everything on the market
			steps = [
				[1.0, func():
					var prices := {"normal": 35, "magic": 120, "rare": 380, "unique": 950}
					var n := 0
					for inst in me.bag.duplicate():
						if n >= 7 or bool(inst.get("bound", false)):
							continue
						var pr: int = int(prices.get(str(inst["rarity"]), 50)) + (me.peer_id % 40) + n * 7
						if Dungeons.is_ticket(inst):
							pr = 160 + 40 * Dungeons.tier_of(inst)
						me.request_market("list", {"uid": int(inst["uid"]), "price": pr})
						n += 1
					me.request_market("list", {"stack": "orb_chaos", "n": 3, "price": 75})
					me.request_market("list", {"stack": "orb_regal", "n": 2, "price": 40})],
			]
		"onebuyer":   # screenshots: buy two of Mira's listings
			steps = [
				[8.0, func(): me.request_market("browse", {"filters": {"cat": "currency"}})],
				[9.0, func(): _bm_ids["n"] = 0],
			]
			if _bm_done.has(1) and int(_bm_ids.get("n", 0)) < 2 and not _bm_done.has("b%d" % int(_bm_ids.get("n", 0))):
				for l in market.page["rows"]:
					if l["seller_name"] == "Mira" and not _bm_done.has("id%d" % int(l["id"])):
						_bm_done["id%d" % int(l["id"])] = true
						_bm_done["b%d" % int(_bm_ids["n"])] = true
						_bm_ids["n"] = int(_bm_ids["n"]) + 1
						me.request_market("buy", {"id": int(l["id"]), "price": int(l["price"])})
						break
		"qbuyer":     # crash test: buy whatever is listed, quickly
			steps = [
				[3.0, func(): me.request_market("browse", {"filters": {"sort": "newest"}})],
				[4.0, func():
					for l in market.page["rows"]:
						me.request_market("buy", {"id": int(l["id"]), "price": int(l["price"])})],
			]
		"collector":
			steps = [
				[1.0, func(): me.request_market("mine")],
				[2.0, func(): me.request_market("claim")],
				[3.0, func(): me.request_market("claim")],      # nothing left
				[4.0, func(): me.request_market("browse", {"filters": {}})],
			]
	for i in steps.size():
		if t >= float(steps[i][0]) and not _bm_done.has(i):
			_bm_done[i] = true
			steps[i][1].call()


func _bag_find(me: Node, base: String, rarity := "") -> Dictionary:
	for inst in me.bag:
		if inst["base"] == base and (rarity == "" or inst["rarity"] == rarity):
			return inst
	return {}


func _bag_uid(me: Node, uid: int) -> Dictionary:
	for inst in me.bag:
		if int(inst["uid"]) == uid:
			return inst
	for sl in me.equipment:
		if not me.equipment[sl].is_empty() and int(me.equipment[sl]["uid"]) == uid:
			return me.equipment[sl]
	return {}


## Scripted crafting test (bot standing at the blacksmith with the --debug-gear kit).
## Every request goes to the server, which does the rolls and validates; this only drives it.
func _bot_craft(me: Node, delta: float) -> void:
	bot_dir = _bot_hold_dir
	_craft_t -= delta
	if _craft_t > 0.0 or _elapsed < 4.0:
		return
	_craft_t = 0.6
	var ring := _bag_uid(me, _craft_ring)
	var step := _craft_step
	_craft_step += 1
	match step:
		0:
			var r := _bag_find(me, "copper_ring", "normal")
			if r.is_empty():
				_craft_step = 0
				return
			_craft_ring = int(r["uid"])
			_log("craft bot: starting at the blacksmith, gold %d, bag %d, near smith %s" % [me.gold, me.bag.size(), me.near_blacksmith()])
			me.request_craft("orb_transmute", _craft_ring)
		1: me.request_craft("orb_transmute", _craft_ring)    # invalid: already magic
		2: me.request_craft("orb_alteration", _craft_ring)
		3: me.request_craft("orb_alteration", _craft_ring)
		4: me.request_craft("orb_chaos", _craft_ring)        # invalid: magic
		5: me.request_craft("orb_exalt", _craft_ring)        # invalid: magic
		6: me.request_craft("orb_regal", _craft_ring)
		7: me.request_craft("orb_regal", _craft_ring)        # invalid: rare
		8: me.request_craft("orb_alteration", _craft_ring)   # invalid: rare
		9, 10, 11, 12:
			if ring.get("mods", []).size() < 6:
				me.request_craft("orb_exalt", _craft_ring)
		13: me.request_craft("orb_exalt", _craft_ring)       # invalid once full (6 affixes)
		14: me.request_craft("orb_chaos", _craft_ring)
		15: me.request_craft("orb_scour", _craft_ring)
		16: me.request_craft("orb_scour", _craft_ring)       # invalid: normal
		17: me.request_craft("orb_chaos", int(_bag_find(me, "copper_ring", "unique").get("uid", -1)))  # invalid: unique
		18: me.request_craft("gold", _craft_ring)            # invalid: not currency
		19: me.request_craft("orb_transmute", 123)           # invalid: no such item
		20: # equip a unique that changes resistances, then a rare body armour
			me.request_equip(int(_bag_find(me, "frost_aegis").get("uid", -1)))
		21: me.request_equip(int(_bag_find(me, "chain_mail").get("uid", -1)))
		22: me.request_equip(_craft_ring)
		23: me.request_craft("orb_transmute", _craft_ring)   # crafting an EQUIPPED item updates stats
		24: me.request_unequip("ring1")
		25: me.request_equip(_craft_ring)
		26: # sell / stash / drop / destroy
			me.request_sell(int(_bag_find(me, "leather_cap").get("uid", -1)))
		27: me.request_stash("put", int(_bag_find(me, "copper_ring", "unique").get("uid", -1)))
		28: me.request_drop(int(_bag_find(me, "sandals").get("uid", -1)))
		29: me.request_destroy(int(_bag_find(me, "cloth_wraps").get("uid", -1)))
		30: me.request_sell_stack("slime_gel")                # invalid (none) or sells gel
		31:
			_craft_n = 0
			_log("craft bot: enhancing iron sword, gold %d" % me.gold)
		32:
			var sw := _bag_find(me, "iron_sword")
			if sw.is_empty():
				return
			_craft_n += 1
			if _craft_n < 40 and int(sw["upg"]) < 10 and me.gold >= Gear.enhance_gold(int(sw["upg"])) and int(me.inventory.get("enhance_stone", 0)) > 0:
				me.request_craft("enhance_stone", int(sw["uid"]))
				_craft_step = 32
			else:
				_log("craft bot: enhancement finished at +%d after %d attempts, gold %d" % [int(sw["upg"]), _craft_n - 1, me.gold])
				me.request_craft("enhance_stone", int(sw["uid"]))   # one more: rejected (max level or not enough gold)
		33:
			_log("craft bot: walking away from the blacksmith")
			_craft_t = 2.5
			bot_dir = Vector2.LEFT
		34:
			bot_dir = Vector2.ZERO
			var sw := _bag_find(me, "iron_sword")
			me.request_sell(int(sw.get("uid", -1)))           # invalid: not at the blacksmith
		35:
			me.request_craft("enhance_stone", int(_bag_find(me, "iron_sword").get("uid", -1)))  # invalid: away from smith
			me.request_craft("orb_transmute", int(_bag_find(me, "iron_sword").get("uid", -1)))  # orbs work anywhere
		36:
			_log("craft bot finished: gold %d, bag %d, stash %d, equip %s" % [me.gold, me.bag.size(), me.stash.size(), me.equip_summary()])
		_:
			bot_dir = Vector2.ZERO
	if step == 33:
		_bot_hold_dir = Vector2.LEFT
	elif step >= 34:
		_bot_hold_dir = Vector2.ZERO
	bot_dir = _bot_hold_dir


func _bot_update(delta: float) -> void:
	var me := _local_player()
	if me == null or me.zone == null:
		return
	var zone: Node = me.zone
	# log inventory changes so tests can see loot / equip / potion use
	var inv_str := "gold=%d inv=%s bag=%d equip=%s" % [me.gold, me.inventory, me.bag.size(), me.equip_summary()]
	if inv_str != _bot_last_inv:
		_bot_last_inv = inv_str
		_log("inventory: " + inv_str)
	if me.dead:
		bot_dir = Vector2.ZERO
		_bot_path.clear()
		return
	if _bot_astar_zone != zone.zone_id:
		_bot_astar_zone = zone.zone_id
		_bot_astar = zone.map.make_astar()
		_bot_path.clear()
		_bot_zone_t = 0.0
		if not bot_route.is_empty() and bot_route[0] == zone.zone_id:
			bot_route.pop_front()
			if bot_route.is_empty():
				_log("bot route finished in %s" % zone.zone_id)
	_bot_zone_t += delta

	if bot_hideout != "":
		_bot_hideout(me, zone, delta)
		return
	if bot_craft:
		_bot_craft(me, delta)
		return
	if bot_dungeon != "" and _bot_dungeon(me, zone, delta):
		return
	if bot_market != "":
		_bot_market(me, zone, delta)
		return
	if bot_idle:
		bot_dir = Vector2.ZERO
		return
	# --- decide where to go
	var goal_pos := Vector2.INF
	var travelling := not bot_route.is_empty() and _bot_zone_t >= bot_dwell
	if travelling:
		var portal := _portal_towards(zone.zone_id, bot_route[0])
		if not portal.is_empty():
			goal_pos = zone.map.cell_pos(portal["rect"].get_center())
	else:
		var target: Node2D = null
		var best_d := 350.0
		for p in zone.loot_root.get_children():   # skip loot that won't fit in the bag
			var d: float = p.position.distance_to(me.position)
			if d < best_d and me.can_take_pickup(p):
				best_d = d
				target = p
		if target == null and bot_hunt_boss:
			for m in zone.monsters_root.get_children():
				if m.is_boss and m.alive:
					target = m
		if target == null:
			target = _nearest(zone.monsters_root, me.position, 2500.0)
		if target:
			goal_pos = target.position

	_bot_move_timer -= delta
	if goal_pos == Vector2.INF:
		if _bot_move_timer <= 0.0:
			_bot_move_timer = rng.randf_range(0.6, 1.4)
			bot_dir = Vector2.from_angle(rng.randf() * TAU)
	else:
		bot_dir = _bot_steer(zone, me.position, goal_pos, delta)

	_bot_attack_timer -= delta
	if _bot_attack_timer <= 0.0 and not bot_passive:
		_bot_attack_timer = 0.4
		me.request_attack()
	_bot_targeting(me, zone, delta)
	_bot_talent_logic(me, delta)
	_bot_skill_timer -= delta
	if bot_skills and not bot_passive and _bot_skill_timer <= 0.0:
		_bot_skill_timer = 0.8
		# cycle through all 4 slots without checking cooldown / mana / level
		# locally, so the server's rejections get exercised too
		var near: Node2D = _nearest(zone.monsters_root, me.position, 240.0)
		var self_skill: bool = Classes.SKILLS[Classes.skill_id(me.class_id, _bot_skill_slot)]["kind"] in ["buff", "hot", "heal_area", "shield"]
		if near or (self_skill and me.hp < me.max_hp):
			me.request_skill(_bot_skill_slot)
			_bot_skill_slot = (_bot_skill_slot + 1) % 4
	_bot_misc_timer -= delta
	if _bot_misc_timer <= 0.0:
		_bot_misc_timer = 1.0
		me.request_pickup()
		var potion: String = me.best_potion()
		if not bot_passive and me.hp <= me.max_hp - 4 and me.hp * 2 < me.max_hp + 20 and int(me.inventory.get(potion, 0)) > 0:
			_log("drinking a %s at hp %d/%d" % [potion, me.hp, me.max_hp])
			me.request_use(potion)
		_bot_gear(me)
	if not _bot_chatted and _elapsed > 3.0:
		_bot_chatted = true
		send_chat("Hello from %s!" % local_name)


## Test bot: mouse-targeting stand-ins (select far targets, aim points, invalid probes).
func _bot_targeting(me: Node, zone: Node, delta: float) -> void:
	if _bot_first_zone == "":
		_bot_first_zone = zone.zone_id
	if zone.zone_id == _bot_first_zone and _bot_first_monster < 0 and zone.monsters_root.get_child_count() > 0:
		_bot_first_monster = zone.monsters_root.get_child(0).monster_id
	_bot_target_t -= delta
	if _bot_target_t <= 0.0:
		_bot_target_t = 0.5
		if bot_target_mode == "near" and not (NetUtil.is_selected(NetUtil.selected) and NetUtil.selected.alive):
			# like pressing Tab: keep the nearest monster selected (screenshots of the target frame)
			NetUtil.selected = _nearest(zone.monsters_root, me.position, 500.0)
		if bot_target_mode == "far":
			# select the FARTHEST visible monster within reach (so a nearer one exists)
			var cands: Array = []
			for m in zone.monsters_root.get_children():
				var d: float = m.position.distance_to(me.position)
				if m.alive and d <= 230.0 and zone.map.has_los(me.position + Vector2(0, -6), m.position + Vector2(0, -6)):
					cands.append([d, m])
			cands.sort_custom(func(a, b): return a[0] > b[0])
			var keep: bool = NetUtil.is_selected(NetUtil.selected) and NetUtil.selected.alive \
				and NetUtil.selected.position.distance_to(me.position) <= 230.0
			if not keep:
				NetUtil.selected = cands[0][1] if cands.size() >= 2 else null
				if NetUtil.selected:
					_log("bot selects far target %s (%d px; %d monsters in reach)" % [NetUtil.selected.display_name, roundi(cands[0][0]), cands.size()])
		if bot_aim:
			var n: Node2D = _nearest(zone.monsters_root, me.position, 320.0)
			if n and rng.randf() < 0.7:
				_bot_aim_point = n.position + Vector2(rng.randf_range(-8, 8), rng.randf_range(-8, 8))
			else:
				_bot_aim_point = me.position + Vector2.from_angle(rng.randf() * TAU) * 600.0
	if bot_probe and zone.zone_id != _bot_first_zone and _elapsed > 6.0:
		_bot_probe_t -= delta
		if _bot_probe_t <= 0.0 and _bot_probe_step < 12:   # the line-of-sight probe is tried up to 9 times (targets die fast)
			_bot_probe_t = 1.5
			var req := {}
			match _bot_probe_step:
				0:
					req = {"t": 999999, "k": "m"}
				1:
					# entity ids are global; the meadow is built first, so id 1 is a meadow slime
					req = {"t": _bot_first_monster if _bot_first_monster > 0 else 1, "k": "m"}
				2:
					for m in zone.monsters_root.get_children():
						if m.alive and m.position.distance_to(me.position) > 600.0:
							req = {"t": m.monster_id, "k": "m"}
							break
				_:
					for m in zone.monsters_root.get_children():
						var d: float = m.position.distance_to(me.position)
						if m.alive and d < 250.0 and not zone.map.has_los(me.position + Vector2(0, -6), m.position + Vector2(0, -6)):
							req = {"t": m.monster_id, "k": "m"}
							break
			if req.is_empty() and _bot_probe_step >= 3:
				return   # no monster behind a wall right now; try again later
			_bot_probe_step += 1
			if not req.is_empty():
				# basic attack (short cooldown): hold the bot's own attacks so it's ready
				_bot_attack_timer = 1.0
				_bot_skill_timer = maxf(_bot_skill_timer, 1.0)   # and its skills, so the probed monster survives
				var probe := req
				var step := _bot_probe_step
				get_tree().create_timer(0.6).timeout.connect(func():
					var me2 := _local_player()
					if me2:
						_log("probe %d: basic attack with invalid target %s" % [step, probe])
						_bot_next_req = probe
						me2.request_attack())


## Test bot: spend passive points along the web, probe the rules, refund, respec.
##   --bot-talents=auto:B  path to the class keystone of cluster B (0/1), then the other one
##   --bot-talents=farm    path to the centre "Treasure Hunter's Oath" and "Blood Pact" keystones first
##   --bot-talents=goals:a,b,...  path to these node ids first
func _bot_goals(cls: String) -> Array:
	var goals: Array = []
	var first := 0
	if bot_talents.begins_with("goals:"):
		goals.append_array(bot_talents.trim_prefix("goals:").split(",", false))
	elif ":" in bot_talents:
		first = int(bot_talents.get_slice(":", 1))
	if bot_talents == "farm":
		goals.append_array(["k_greed", "k_blood"])
	for b in [first, 1 - first]:
		for t in Talents.TREES[cls][b]["talents"]:
			if int(t["tier"]) == 4:
				goals.append(t["id"])
	goals.append("k_greed")
	return goals


func _bot_talent_logic(me: Node, delta: float) -> void:
	if bot_talents == "" and not bot_talent_probe and bot_respec_at.is_empty():
		return
	if not bot_respec_at.is_empty() and _elapsed >= float(bot_respec_at[0]):
		bot_respec_at.pop_front()
		_log("requesting passive web reset (cost %d, gold %d)" % [Talents.respec_cost(me.level), me.gold])
		me.request_respec()
		_bot_talent_t = 1.5
		return
	_bot_talent_t -= delta
	if _bot_talent_t > 0.0:
		return
	_bot_talent_t = 0.6
	var cls: String = me.class_id
	var tl: Dictionary = me.talents
	var avail := Talents.points_total(me.level) - Talents.points_spent(tl)
	var goals := _bot_goals(cls)
	if bot_talent_probe and not _bot_talent_probe_done and tl.is_empty():
		_bot_talent_probe_done = true
		_log("passive probe: unknown node, unconnected keystone, own start")
		me.request_talent("not_a_node")
		me.request_talent(str(goals[0]))
		me.request_talent(Talents.start_of(cls))
		return
	if avail <= 0:
		if bot_talent_probe and _bot_talent_probe_done and not tl.is_empty():
			bot_talent_probe = false
			var nxt := ""
			for g in goals:
				var path := Talents.path_to(cls, tl, g)
				if not path.is_empty():
					nxt = path[0]
					break
			if nxt != "":
				_log("passive probe: allocate with no points left (%s)" % nxt)
				me.request_talent(nxt)
			# refund a node in the middle (would disconnect) and then a leaf (allowed, costs gold)
			var leaf := ""
			var middle := ""
			for id in tl:
				if Talents.can_refund(cls, tl, id) == "":
					leaf = id
				elif middle == "":
					middle = id
			if middle != "":
				_log("passive probe: refund a connecting node (%s)" % middle)
				me.request_refund(middle)
			if leaf != "":
				_log("passive probe: refund a leaf node (%s)" % leaf)
				me.request_refund(leaf)
		return
	if not (bot_talents.begins_with("auto") or bot_talents.begins_with("goals:") or bot_talents == "farm"):
		return
	for g in goals:
		var path := Talents.path_to(cls, tl, g)
		if not path.is_empty():
			me.request_talent(str(path[0]))
			return
	# every goal reached: take any connected notable, else any connected node
	var best := ""
	for id in Talents.all_nodes():
		if Talents.can_learn(cls, me.level, tl, id) == "":
			if best == "" or Talents.node(id)["type"] == "notable":
				best = id
	if best != "":
		me.request_talent(best)


## Offline check of the passive web (no network): graph rules, then stats and skill numbers
## before/after pathing to each class keystone (and the centre keystones) for every class, then quits.
## Offline gear checks (no network): rarity / item-level gating / IIQ+IIR statistics,
## every orb + invalid uses, enhancement rules, equip -> Stats.gather -> damage taken, migration.
func _gear_selftest() -> void:
	var g := RandomNumberGenerator.new()
	g.seed = 12345
	var ok := true
	var stats_runs: Array = []
	# ---- rarity distribution + IIQ/IIR
	for setup in [["no bonus", 0.0, 0.0], ["+100% IIQ +200% IIR", 100.0, 200.0]]:
		var counts := {"normal": 0, "magic": 0, "rare": 0, "unique": 0, "currency": 0}
		var kills := 4000
		for i in kills:
			for drop in Gear.roll_monster_loot(Monsters.info("yeti"), 14, setup[1], setup[2], g):
				if not drop[2].is_empty():
					counts[drop[2]["rarity"]] += 1
				elif Items.type_of(drop[0]) == "orb":
					counts["currency"] += 1
		var gear: int = counts["normal"] + counts["magic"] + counts["rare"] + counts["unique"]
		print("GEAR SELFTEST drops (%s, %d yeti kills lv14): gear %d %s | rare+unique share %.1f%%" % [setup[0], kills, gear, counts,
			100.0 * (counts["rare"] + counts["unique"]) / maxf(1.0, gear)])
		stats_runs.append([gear, counts])
	var a: Array = stats_runs[0]
	var b: Array = stats_runs[1]
	var share_a: float = float(a[1]["rare"] + a[1]["unique"]) / a[0]
	var share_b: float = float(b[1]["rare"] + b[1]["unique"]) / b[0]
	var iiq_ok: bool = b[0] > a[0] * 1.6 and b[1]["currency"] > a[1]["currency"] * 1.6
	var iir_ok: bool = share_b > share_a * 2.0
	print("GEAR SELFTEST IIQ effect: %d -> %d gear drops (x%.2f) %s | IIR effect: rare+unique share x%.2f %s" % [a[0], b[0], float(b[0]) / a[0],
		"OK" if iiq_ok else "BAD", share_b / share_a, "OK" if iir_ok else "BAD"])
	ok = ok and iiq_ok and iir_ok and a[1]["unique"] > 0 and a[1]["normal"] > 0 and a[1]["magic"] > 0 and a[1]["rare"] > 0
	# ---- item level gating
	var worst_low := 0
	var best_high := 0
	var bases_low := {}
	for i in 3000:
		var lo := Gear.roll_drop(2, g, 300.0)
		bases_low[lo["base"]] = true
		worst_low = maxi(worst_low, Items.stat(lo["base"], "lvl"))
		for e in lo["mods"]:
			if e[4] != "u":
				worst_low = maxi(worst_low, Gear._tier_min(str(e[0]), int(e[3])))
		var hi := Gear.roll_drop(15, g, 300.0)
		for e in hi["mods"]:
			if e[4] != "u":
				best_high = maxi(best_high, Gear._tier_min(str(e[0]), int(e[3])))
	var gate_ok := worst_low <= 2 and best_high >= 13
	print("GEAR SELFTEST item level gating: ilvl 2 drops use bases/affix tiers up to level %d (bases %s) | ilvl 15 drops reach affix tier level %d %s" % [
		worst_low, bases_low.keys(), best_high, "OK" if gate_ok else "BAD"])
	ok = ok and gate_ok
	# ---- every orb, valid + invalid
	var it := Gear.make("silver_ring", "normal", 15, g)
	var log_orb := func(orb: String, expect_ok: bool) -> bool:
		var before: String = Gear.summary(it)
		var why := Gear.apply_orb(it, orb, g, "water")
		var good := (why == "") == expect_ok
		print("GEAR SELFTEST %-15s %s -> %s %s%s" % [orb, before, Gear.summary(it) if why == "" else "REJECTED: " + why, "" if good else "  <-- UNEXPECTED", ""])
		return good
	for step in [["orb_transmute", true], ["orb_transmute", false], ["orb_alteration", true], ["orb_chaos", false], ["orb_exalt", false],
			["orb_regal", true], ["orb_regal", false], ["orb_alteration", false], ["orb_exalt", true], ["orb_chaos", true], ["orb_scour", true],
			["orb_scour", false], ["orb_alteration", false], ["orb_regal", false]]:
		ok = log_orb.call(step[0], step[1]) and ok
	it = Gear.make("silver_ring", "rare", 15, g)
	while it["mods"].size() < 6:
		Gear.apply_orb(it, "orb_exalt", g, "")
	ok = log_orb.call("orb_exalt", false) and ok   # full rare
	var counts_ok := true
	for i in 300:
		var m := Gear.make(Gear.roll_base(15, g), "magic", 15, g)
		var r := Gear.make(Gear.roll_base(15, g), "rare", 15, g)
		var rg := Gear.make(Gear.roll_base(15, g), "magic", 15, g)
		Gear.apply_orb(rg, "orb_regal", g, "")
		if rg["mods"].size() < 3 or m["mods"].size() < 1 or m["mods"].size() > 2 or r["mods"].size() < 3 or r["mods"].size() > 6 or not r.has("name"):
			counts_ok = false
	print("GEAR SELFTEST affix counts (magic 1-2, rare 3-6 with a generated name): %s" % ("OK" if counts_ok else "BAD"))
	ok = ok and counts_ok
	it = Gear.make_unique("frostbrand", 13, g)
	ok = log_orb.call("orb_chaos", false) and log_orb.call("orb_scour", false) and ok
	# ---- enhancement rules (many trials)
	var trials := {}
	var destroyed := 0
	var bad_down := 0
	for i in 20000:
		var e := {"base": "iron_sword", "upg": g.randi_range(0, 9)}
		var res := Gear.enhance(e, g)
		var key := int(res["from"])
		if not trials.has(key):
			trials[key] = {"n": 0, "success": 0, "fail": 0, "downgrade": 0}
		trials[key]["n"] += 1
		trials[key][res["result"]] += 1
		if not e.has("base") or int(e["upg"]) < 0:
			destroyed += 1
		if res["result"] == "downgrade" and key < 5:
			bad_down += 1
	var lines: Array = []
	var rate_ok := true
	for k in range(10):
		var t: Dictionary = trials[k]
		var sr: float = float(t["success"]) / float(t["n"])
		rate_ok = rate_ok and absf(sr - Gear.ENHANCE_CHANCE[k]) < 0.05
		lines.append("+%d->+%d %d%% (exp %d%%, down %d, gold %d)" % [k, k + 1, roundi(sr * 100.0), roundi(Gear.ENHANCE_CHANCE[k] * 100.0), t["downgrade"], Gear.enhance_gold(k)])
	var max_res := Gear.enhance({"base": "iron_sword", "upg": 10}, g)
	print("GEAR SELFTEST enhancement: %s" % " | ".join(lines))
	print("GEAR SELFTEST enhancement rules: destroyed %d, downgrades below +5 %d, at +10 -> %s, damage +0/+5/+10 = %d/%d/%d" % [destroyed, bad_down,
		max_res.get("err", "?"), Gear.damage({"base": "great_hammer", "upg": 0}), Gear.damage({"base": "great_hammer", "upg": 5}), Gear.damage({"base": "great_hammer", "upg": 10})])
	ok = ok and rate_ok and destroyed == 0 and bad_down == 0 and int(trials[7]["downgrade"]) > 0 and str(max_res.get("err", "")).contains("max")
	# ---- equip -> Stats.gather -> stats & incoming damage
	var PS := load("res://scripts/player.gd")
	var p: Node = PS.new()
	p.class_id = "fire"
	p.element = "fire"
	p.level = 15
	p.equipment = {}
	for sl in Items.SLOTS:
		p.equipment[sl] = {}
	p.recalc_stats()
	var before := [p.max_hp, p.attack, p.defense, p.resistance("water"), p.incoming_damage(40, "water"), p.incoming_damage(40, "metal")]
	var helm := Gear.make_unique("river_heart", 15, g)     # +25% fire res etc.
	var aegis := Gear.make_unique("frost_aegis", 15, g)    # +30% water res, +30 life
	var staff := Gear.make("lich_staff", "normal", 15, g)
	staff["upg"] = 6
	var belt := {"uid": 1, "base": "leather_belt", "rarity": "rare", "ilvl": 15, "upg": 0, "name": "Test Coil",
		"mods": [["res_water", "res:water", 30.0, 3, "s"], ["life", "life_flat", 40.0, 3, "p"], ["res_all", "res_all", 9.0, 1, "s"]]}
	p.equipment["helmet"] = helm
	p.equipment["offhand"] = aegis
	p.equipment["weapon"] = staff
	p.equipment["belt"] = belt
	p.equipment["ring1"] = Gear.make_unique("five_phases", 15, g)   # +12% all res
	p.recalc_stats()
	var after := [p.max_hp, p.attack, p.defense, p.resistance("water"), p.incoming_damage(40, "water"), p.incoming_damage(40, "metal")]
	print("GEAR SELFTEST equip (Fire L15: River Heart + Frost Aegis + Lich Staff +6 + rare belt + Five Phases ring): max hp %d->%d, attack %d->%d, defense %d->%d, water res %d%%->%d%% (raw %d, cap %d), 40 water damage taken %d->%d, 40 metal damage taken %d->%d" % [
		before[0], after[0], before[1], after[1], before[2], after[2], roundi(before[3]), roundi(after[3]), roundi(p.tm("res:water") + p.tm("res_all")), roundi(Gear.RES_CAP),
		before[4], after[4], before[5], after[5]])
	ok = ok and after[0] > before[0] and after[1] > before[1] and after[2] > before[2] and after[3] == Gear.RES_CAP and after[4] < before[4]
	for sl in Items.SLOTS:
		p.equipment[sl] = {}
	p.recalc_stats()
	print("GEAR SELFTEST unequip all: max hp %d, attack %d, water damage taken %d (back to %d/%d/%d)" % [p.max_hp, p.attack, p.incoming_damage(40, "water"), before[0], before[1], before[4]])
	ok = ok and p.max_hp == before[0] and p.attack == before[1] and p.incoming_damage(40, "water") == before[4]
	p.free()
	# ---- legacy migration
	var leg: Array = []
	for id in ["iron_sword", "lich_staff", "wooden_shield", "frostbrand"]:
		leg.append(Gear.summary(Gear.from_legacy(id, g)))
	print("GEAR SELFTEST legacy ids -> instances: %s" % ", ".join(leg))
	ok = ok and leg[1].contains("[unique]") and leg[0].contains("[normal]")
	# ---- describe / tooltip / compare sanity
	var tip := Gear.tooltip(Gear.make("great_hammer", "rare", 15, g), "metal", 15)
	var cmp := Gear.compare(Gear.make("great_hammer", "rare", 15, g), Gear.make("iron_sword", "magic", 3, g))
	print("GEAR SELFTEST tooltip %d lines, compare %d lines: %s" % [tip.size(), cmp.size(), str(cmp.map(func(x): return x[0]))])
	ok = _dungeon_selftest(g) and ok
	ok = _market_selftest(g) and ok
	ok = _atlas_selftest(g) and ok
	print("GEAR SELFTEST RESULT: %s" % ("PASS" if ok else "FAIL"))
	get_tree().quit()


## Offline dungeon checks: tickets, crafting, IIQ/IIR, atlas math, deterministic + connected layouts.
func _dungeon_selftest(g: RandomNumberGenerator) -> bool:
	var fails: Array = []
	var cnt: Array = [0]
	var expect := func(cond: bool, what: String):
		cnt[0] += 1
		if not cond:
			fails.append(what)
	for th in Dungeons.ORDER:
		var t := Dungeons.make_ticket(th, 3, "normal", g)
		expect.call(Dungeons.is_ticket(t) and Dungeons.theme_of(t) == th and Dungeons.tier_of(t) == 3, "make_ticket " + th)
		expect.call(Dungeons.run_info(t)["iiq"] == 0.0, "normal ticket has no iiq " + th)
		expect.call(Gear.apply_orb(t, "orb_transmute", g, "") == "" and t["rarity"] == "magic", "transmute ticket " + th)
		expect.call(Dungeons.run_info(t)["iiq"] > 0.0 and Dungeons.run_info(t)["iir"] > 0.0, "magic ticket gives iiq/iir " + th)
		expect.call(Gear.apply_orb(t, "orb_regal", g, "") == "" and t["rarity"] == "rare", "regal ticket " + th)
		var iiq0: float = Dungeons.run_info(t)["iiq"]
		for k in 5:
			Gear.apply_orb(t, "orb_chisel", g, "")
		expect.call(int(t["q"]) == Dungeons.MAX_QUALITY and Dungeons.run_info(t)["iiq"] == iiq0 + Dungeons.MAX_QUALITY, "chisel quality cap " + th)
		for m in t["mods"]:
			expect.call(str(m[1]).begins_with("map_"), "only map mods on tickets " + th)
		var back := Gear.sanitize(JSON.parse_string(JSON.stringify(t)))
		expect.call(Gear.summary(back) == Gear.summary(t), "ticket survives save/load " + th)
		expect.call(Dungeons.tooltip(t, {}).size() >= 5, "ticket tooltip " + th)
		# same seed -> same map, boss reachable from the entrance
		var seed := 1000 + Dungeons.ORDER.find(th)
		var maps: Array = []
		for k in 2:
			var id := "dun_test%d" % k
			Zones.DYN[id] = Dungeons.make_def(id, th, 3, seed, 7 + k, {}, "test")
			var zm := ZoneMap.new()
			zm.build(id)
			var d: Dictionary = Zones.DYN[id]["dungeon"]
			expect.call(zm.reachable.has(d["boss_cell"]), "boss reachable " + th)
			expect.call(zm.is_walkable(Zones.DYN[id]["respawn"]), "entrance walkable " + th)
			maps.append(zm.get_used_cells(0).size())
			maps.append(zm.reachable.size())
			zm.free()
			Zones.DYN.erase(id)
		expect.call(maps[0] == maps[2] and maps[1] == maps[3], "deterministic layout " + th)
	var u := Dungeons.make_unique_ticket("wuxing_sanctum", g)
	expect.call(Gear.apply_orb(u, "orb_chaos", g, "") != "", "unique ticket rejects orbs")
	expect.call(Gear.apply_orb(Gear.make("iron_sword", "normal", 5, g), "orb_chisel", g, "") != "", "chisel only on tickets")
	var atlas := {"done": {"fire:1": 2, "fire:2": 1, "fire:3": 1, "wood:1": 1}}
	expect.call(Dungeons.completed_nodes(atlas) == 4 and Dungeons.atlas_iiq(atlas) == 4.0, "atlas bonus")
	expect.call(Dungeons.merchant_max(atlas, "fire") == 5 and Dungeons.merchant_max(atlas, "metal") == 2 and Dungeons.merchant_max(atlas, "water") == 1 and Dungeons.merchant_max(atlas, "wood") == 2, "merchant sells unlocked atlas nodes")
	expect.call(Dungeons.merchant_max(Atlas.sanitize({"done": {"fire:9": 1}}), "fire") == Atlas.MERCHANT_CAP, "merchant cap T5")
	expect.call(Dungeons.tier_of(Dungeons.make_ticket("fire", 15, "normal", g)) == 10 and Dungeons.MAX_TIER == 10, "tickets capped at T10")
	expect.call(Dungeons.sanitize_atlas({"done": {"bogus:3": 1, "fire:99": 1, "water:2": "x"}})["done"].keys() == ["water:2"], "atlas sanitize")
	var up := 0
	for k in 400:
		if Dungeons.tier_of(Dungeons.roll_ticket(4, 0.0, g)) == 4:
			up += 1
	expect.call(up == 400, "roll_ticket keeps the tier")
	if fails.is_empty():
		print("GEAR SELFTEST dungeon selftest: all %d checks passed" % cnt[0])
	else:
		print("GEAR SELFTEST dungeon selftest: %d/%d FAILED: %s" % [fails.size(), cnt[0], fails])
	return fails.is_empty()


func _atlas_states(a: Dictionary) -> String:
	var c := {"completed": [], "available": [], "locked": []}
	for k in Atlas.nodes():
		c[Atlas.state(a, k)].append(k)
	return "completed %s, available %s, locked %d" % [c["completed"], c["available"], c["locked"].size()]


## Offline atlas checks: map graph, unlock rules, points, migration, passive tree, measured effects.
func _atlas_selftest(g: RandomNumberGenerator) -> bool:
	var fails: Array = []
	var cnt: Array = [0]
	var expect := func(cond: bool, what: String):
		cnt[0] += 1
		if not cond:
			fails.append(what)
			print("ATLAS SELFTEST fail: " + what)
	var N: Dictionary = Atlas.nodes()
	expect.call(N.size() == 31, "31 atlas nodes (30 region + pinnacle)")
	# every node reachable from any T1 through paths
	var seen := {"fire:1": true}
	var q: Array = ["fire:1"]
	while not q.is_empty():
		for a in Atlas.adjacent(q.pop_back()):
			if not seen.has(a):
				seen[a] = true
				q.append(a)
	expect.call(seen.size() == N.size(), "atlas graph connected")
	var empty := Atlas.sanitize({})
	var open0: Array = N.keys().filter(func(k): return Atlas.is_available(empty, k))
	expect.call(open0.size() == 5 and open0.all(func(k): return int(N[k]["tier"]) == 1), "fresh atlas: exactly the five T1 nodes are open")
	expect.call(Atlas.state(empty, "fire:2") == "locked" and Atlas.state(empty, "fire:1") == "available", "states locked/available")
	var a1 := Atlas.sanitize({"v": 2, "done": {"fire:1": 1}})
	expect.call(Atlas.is_available(a1, "fire:2") and not Atlas.is_available(a1, "fire:3") and not Atlas.is_available(a1, "metal:2"), "completing fire:1 unlocks only its neighbour fire:2")
	var a2 := Atlas.sanitize({"v": 2, "done": {"fire:1": 1, "fire:2": 1}})
	expect.call(Atlas.is_available(a2, "fire:3") and Atlas.is_available(a2, "earth:2") and Atlas.is_available(a2, "metal:2"), "fire:2 unlocks fire:3 + ring neighbours earth:2/metal:2")
	expect.call(Atlas.state(a2, "fire:2") == "completed", "state completed")
	var g4 := {"v": 2, "done": {}}
	for th in Dungeons.ORDER:
		if th != "metal":
			g4["done"]["%s:10" % th] = 1
	expect.call(not Atlas.is_available(Atlas.sanitize(g4), Atlas.PINNACLE), "pinnacle locked with 4/5 guardians")
	g4["done"]["metal:10"] = 1
	expect.call(Atlas.is_available(Atlas.sanitize(g4), Atlas.PINNACLE), "pinnacle opens with all 5 guardians")
	expect.call(Atlas.node_of_ticket(Dungeons.make_ticket("water", 4, "normal", g)) == "water:3" and Atlas.node_of_ticket(Atlas.make_node_ticket("earth:5", "normal", g)) == "earth:5", "ticket -> node mapping")
	expect.call(Atlas.merchant_sells(a2, "fire", 3) and not Atlas.merchant_sells(a2, "fire", 5) and not Atlas.merchant_sells(a2, "fire", 4), "merchant: unlocked nodes only")
	# points + bonus objectives
	expect.call(Atlas.points_earned(Atlas.sanitize({"v": 2, "done": {"fire:1": 3, "wood:1": 1}, "bonus": {"fire:1": true, "water:1": true}})) == 3, "points = first completions + bonus (bonus needs completion)")
	expect.call(Atlas.bonus_met("fire:1", {"rarity": "rare"}) and not Atlas.bonus_met("fire:1", {"rarity": "magic"}), "bonus: rare ticket")
	expect.call(Atlas.bonus_met("fire:3", {"elites_total": 2, "elites_killed": 2}) and not Atlas.bonus_met("fire:3", {"elites_total": 3, "elites_killed": 2}), "bonus: all elites")
	expect.call(Atlas.bonus_met("fire:2", {"deaths": 0}) and not Atlas.bonus_met("fire:2", {"deaths": 1}), "bonus: deathless")
	# migration of the old 5x10 grid
	var old := {"done": {"fire:1": 2, "fire:4": 1, "fire:3": 1, "water:9": 1, "bogus:2": 1}}
	var mig := Atlas.sanitize(old)
	expect.call(Atlas.is_legacy(old) and not Atlas.is_legacy(mig), "legacy detection")
	expect.call(mig["done"] == {"fire:1": 2, "fire:3": 2, "water:7": 1} and Atlas.points_earned(mig) == 3, "legacy grid migrates (T4->T3, T9->T7) with points")
	expect.call(Atlas.is_available(mig, "fire:5") and Atlas.is_available(mig, "water:10"), "migrated progress unlocks neighbours")
	var rt := Atlas.sanitize(JSON.parse_string(JSON.stringify(mig)))
	expect.call(rt["done"] == mig["done"] and rt["migrated"] == mig["migrated"], "atlas survives save/load")
	# passive tree
	var P: Dictionary = Atlas.passives()
	expect.call(P.size() == 36, "36 atlas passives (incl. root)")
	var pa := Atlas.sanitize({"v": 2, "done": {"fire:1": 1, "fire:2": 1}, "bonus": {"fire:1": true}})
	expect.call(Atlas.can_allocate(pa, "a_water_1").contains("not connected"), "passive adjacency enforced")
	expect.call(Atlas.can_allocate(pa, "nope").contains("no atlas passive"), "unknown passive rejected")
	pa["passives"] = ["a_ring_water", "a_water_1", "a_ring_wood"]
	expect.call(Atlas.can_allocate(pa, "a_wood_1").contains("no atlas points"), "no points left rejected")
	expect.call(Atlas.can_allocate(pa, "a_ring_wood").contains("already"), "already allocated rejected")
	var bad := Atlas.sanitize({"v": 2, "done": {"fire:1": 1}, "passives": ["a_water_5", "a_ring_fire", "a_ring_wood"]})
	expect.call(bad["passives"] == ["a_ring_fire"], "save sanitizing drops unconnected / unpaid passives")
	expect.call(Atlas.respec_cost(pa) == 3 * Atlas.RESPEC_GOLD_PER_POINT, "respec cost")
	# measured effects (Monte Carlo, fixed seeds)
	var full := {"v": 2, "done": {}, "bonus": {}, "passives": []}
	for k in N:
		full["done"][k] = 1
		full["bonus"][k] = true
	full = Atlas.sanitize(full)
	for pid in ["a_ring_water", "a_water_1", "a_water_2", "a_water_3", "a_water_5", "a_ring_metal", "a_metal_1", "a_metal_2", "a_metal_3", "a_metal_5",
			"a_ring_fire", "a_fire_1", "a_fire_3", "a_fire_4", "a_fire_5", "a_ring_wood", "a_wood_1", "a_wood_3", "a_wood_5", "a_ring_earth", "a_earth_1", "a_earth_3", "a_earth_5"]:
		var why := Atlas.can_allocate(full, pid)
		expect.call(why == "", "allocate %s (%s)" % [pid, why])
		if why == "":
			full["passives"].append(pid)
	var fx0 := Atlas.run_effects(empty, "fire")
	var fx1 := Atlas.run_effects(full, "fire")
	expect.call(int(fx1["portals"]) == 2 and Dungeons.PORTALS + int(fx1["portals"]) == 8, "extra portals: 6 -> 8")
	expect.call(int(fx1["elites"]) == 2, "more elites: +2 packs")
	expect.call(fx1["reg"] == 37.0 and Atlas.run_effects(full, "water")["reg"] == 12.0, "fire region boost applies only to fire dungeons")
	var r := RandomNumberGenerator.new()
	var drops := [0, 0]
	var ups := [0, 0]
	var orbs := [0, 0]
	var rolls := [0, 0]
	var boss_rolls := [0, 0]
	var K := 20000
	for i in 2:
		var fx: Dictionary = fx0 if i == 0 else fx1
		r.seed = 4242
		for k in K:
			if r.randf() < Atlas.ticket_chance(0.03, 0.0, fx):
				drops[i] += 1
			if int(Atlas.node(Atlas.roll_drop_node("fire:3", r, float(fx["tt"])))["tier"]) > 3:
				ups[i] += 1
			var ex := Atlas.roll_extras(fx, false, r)
			orbs[i] += ex["orbs"].size()
			rolls[i] += int(ex["loot_rolls"])
			boss_rolls[i] += int(Atlas.roll_extras(fx, true, r)["loot_rolls"])
	print("ATLAS SELFTEST effects over %d kills (no passives -> full fire build %s): ticket drops %d -> %d, higher-tier tickets %d -> %d, bonus currency %d -> %d, extra loot rolls %d -> %d, extra boss loot rolls %d -> %d, portals %d -> %d, elite packs +%d" % [
		K, Atlas._fx_short(fx1), drops[0], drops[1], ups[0], ups[1], orbs[0], orbs[1], rolls[0], rolls[1], boss_rolls[0], boss_rolls[1], Dungeons.PORTALS, Dungeons.PORTALS + int(fx1["portals"]), int(fx1["elites"])])
	expect.call(drops[1] > drops[0] * 1.25, "ticket drop passives measurably raise ticket drops")
	expect.call(ups[0] == 0 and ups[1] > K * 0.2, "tier passives measurably raise higher-tier tickets")
	expect.call(orbs[0] == 0 and orbs[1] > K * 0.02, "currency passives measurably add currency")
	expect.call(rolls[0] == 0 and rolls[1] > K * 0.3, "region passives add loot rolls")
	expect.call(boss_rolls[0] == 0 and boss_rolls[1] >= K / 2, "boss passives add boss loot")
	# boss tickets favour adjacent nodes
	var adj := 0
	r.seed = 99
	for k in 2000:
		if Atlas.adjacent("fire:3").has(Atlas.boss_ticket_node("fire:3", r, 0.65)):
			adj += 1
	print("ATLAS SELFTEST boss tickets: %d/2000 for adjacent nodes" % adj)
	expect.call(adj > 1150 and adj < 1450, "boss tickets favour adjacent nodes (~65%)")
	if fails.is_empty():
		print("GEAR SELFTEST atlas selftest: all %d checks passed" % cnt[0])
	else:
		print("GEAR SELFTEST atlas selftest: %d/%d FAILED: %s" % [fails.size(), cnt[0], fails])
	return fails.is_empty()


## Offline market checks: fee/tax math, tradeability, filters, sorting/paging, save sanitizing.
func _market_selftest(g: RandomNumberGenerator) -> bool:
	var fails: Array = []
	var cnt: Array = [0]
	var expect := func(cond: bool, what: String):
		cnt[0] += 1
		if not cond:
			fails.append(what)
	expect.call(Market.fee(10) == 1 and Market.fee(1000) == 20 and Market.fee(1) == 1, "fee 2% min 1")
	expect.call(Market.tax(1000) == 50 and Market.tax(10) == 1 and Market.tax(1) == 0, "tax 5%")
	var bound := Gear.make("iron_sword", "normal", 1, g)
	bound["bound"] = true
	expect.call(Market.tradeable_reason(bound) != "", "bound gear untradeable")
	expect.call(Gear.sanitize(bound).get("bound", false) == true, "bound flag survives saves")
	expect.call(Gear.tooltip(bound).back()[0].contains("bound"), "tooltip shows bound")
	expect.call(Market.tradeable_reason({"stack": "gold", "n": 5}) != "" and Market.tradeable_reason({"stack": "orb_chaos", "n": 2}) == "", "gold not listable, orbs are")
	var aegis := Gear.make_unique("frost_aegis", 13, g)
	var ls: Array = [
		{"id": 1, "seller": "a", "seller_name": "A", "price": 300, "item": Gear.make("chain_mail", "rare", 12, g)},
		{"id": 2, "seller": "a", "seller_name": "A", "price": 50, "item": Gear.make("copper_ring", "normal", 3, g)},
		{"id": 3, "seller": "b", "seller_name": "B", "price": 900, "item": aegis},
		{"id": 4, "seller": "b", "seller_name": "B", "price": 120, "item": {"stack": "orb_chaos", "n": 5}},
		{"id": 5, "seller": "c", "seller_name": "C", "price": 200, "item": Dungeons.make_ticket("water", 4, "rare", g)},
		{"id": 6, "seller": "c", "seller_name": "C", "price": 75, "item": Gear.make("great_hammer", "normal", 10, g)},
	]
	var q := func(f: Dictionary, cls := "water") -> Array:
		return Market.search(ls, Market.sanitize_filters(f), cls)["rows"].map(func(l): return int(l["id"]))
	expect.call(q.call({}) == [2, 6, 4, 5, 1, 3], "default sort: price asc")
	expect.call(q.call({"sort": "price_desc"})[0] == 3 and q.call({"sort": "newest"})[0] == 6, "sort desc / newest")
	expect.call(q.call({"cat": "body"}) == [1], "category filter")
	expect.call(q.call({"rarity": "unique"}) == [3], "rarity filter")
	expect.call(q.call({"text": "COPPER"}) == [2], "text filter (case-insensitive)")
	expect.call(q.call({"stat": "res:water", "stat_min": 25}) == [3], "affix filter res:water >= 25")
	expect.call(q.call({"price_min": 60, "price_max": 250}) == [6, 4, 5], "price range")
	expect.call(q.call({"cat": "currency"}) == [4], "currency category")
	expect.call(q.call({"theme": "water", "tier_min": 4, "tier_max": 4}) == [5] and q.call({"theme": "fire"}) == [], "ticket theme / tier")
	expect.call(not 6 in q.call({"usable": true}, "water") and 6 in q.call({"usable": true}, "metal"), "usable by class")
	expect.call(not 3 in q.call({"max_req": 10}) and 2 in q.call({"max_req": 10}), "required level filter")
	var many: Array = []
	for i in 19:
		many.append({"id": i + 1, "seller": "a", "seller_name": "A", "price": i + 1, "item": {"stack": "orb_chaos", "n": 1}})
	var p2 := Market.search(many, Market.sanitize_filters({"page": 2}), "")
	expect.call(p2["pages"] == 3 and p2["rows"].size() == 3 and int(p2["rows"][0]["price"]) == 17, "paging")
	var dirty := {"next_id": 2, "listings": [{"id": 7, "seller": "x", "price": -5, "item": {"base": "nope"}},
		{"id": 9, "seller": "x", "price": 99999999999, "item": {"stack": "orb_regal", "n": 2}}],
		"claims": {"x": {"gold": -3, "items": [{"base": "iron_sword", "uid": 4}], "stacks": {"bogus": 2}}}}
	var clean := Market.sanitize_data(dirty)
	expect.call(clean["listings"].size() == 1 and int(clean["listings"][0]["price"]) == Market.MAX_PRICE and clean["next_id"] == 10, "sanitize listings")
	expect.call(clean["claims"]["x"]["gold"] == 0 and clean["claims"]["x"]["items"].size() == 1 and clean["claims"]["x"]["stacks"].is_empty(), "sanitize claims")
	if fails.is_empty():
		print("GEAR SELFTEST market selftest: all %d checks passed" % cnt[0])
	else:
		print("GEAR SELFTEST market selftest: %d/%d FAILED: %s" % [fails.size(), cnt[0], fails])
	return fails.is_empty()


func _talent_selftest() -> void:
	var PS := load("res://scripts/player.gd")
	var all_ok := true
	var nodes := Talents.all_nodes()
	var count := {}
	for id in nodes:
		var n: Dictionary = nodes[id]
		count[n["type"]] = int(count.get(n["type"], 0)) + 1
		for l in n["links"]:
			if not nodes.has(l) or not nodes[l]["links"].has(id):
				print("WEB SELFTEST bad link %s-%s" % [id, l]); all_ok = false
	# every node reachable from every start
	for cls in Classes.ELEMENTS:
		var everything := {}
		for id in nodes:
			if id != Talents.start_of(cls):
				everything[id] = 1
		if Talents._reachable(cls, everything, "").size() != nodes.size():
			print("WEB SELFTEST %s: not every node is reachable" % cls); all_ok = false
	# no two nodes on top of each other
	var ids := nodes.keys()
	var min_d := 99999.0
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			min_d = minf(min_d, (nodes[ids[i]]["pos"] as Vector2).distance_to(nodes[ids[j]]["pos"]))
	print("WEB SELFTEST %d nodes: %s, closest pair %.0f px" % [nodes.size(), count, min_d])
	all_ok = all_ok and min_d >= 20.0 and int(count.get("keystone", 0)) == 15 and int(count.get("start", 0)) == 5
	# rules
	var r1 := Talents.can_learn("metal", 20, {}, "m_bladestorm")
	var r2 := Talents.can_learn("metal", 1, {}, "m_honed_1")
	var r3 := Talents.can_refund("metal", {"m_honed_1": 1, "m_honed_2": 1}, "m_honed_1")
	var r4 := Talents.can_refund("metal", {"m_honed_1": 1, "m_honed_2": 1}, "m_honed_2")
	var r5 := Talents.sanitize("metal", 20, {"m_honed": 3, "m_honed_2": 1})
	print("WEB SELFTEST rules: unconnected '%s' | no points '%s' | refund middle '%s' | refund leaf '%s' | old/disconnected save -> %s" % [r1, r2, r3, r4, r5])
	all_ok = all_ok and r1.contains("not connected") and r2.contains("no passive points") and r3.contains("disconnect") and r4 == "" and r5.is_empty()
	for cls in Classes.ELEMENTS:
		for b in 2:
			var p: Node = PS.new()
			p.class_id = cls
			p.element = Classes.element_of(cls)
			p.level = 40
			p.recalc_stats()
			var before: String = p._stat_line()
			var tl := {}
			var ks := ""
			for t in Talents.TREES[cls][b]["talents"]:
				if int(t["tier"]) == 4:
					ks = t["id"]
			var path := Talents.path_to(cls, tl, ks)
			for id in path:
				all_ok = all_ok and Talents.can_learn(cls, 40, tl, id) == ""
				tl[id] = 1
			var to_ks := path.size()
			for id in Talents.path_to(cls, tl, "k_greed"):
				tl[id] = 1
			p.talents = tl
			p.recalc_stats()
			var parts: Array = []
			for sid in Classes.info(cls)["skills"]:
				var a: Dictionary = Classes.SKILLS[sid]
				var c: Dictionary = p.skill_def(sid)
				var diff: Array = []
				for k in ["mult", "cd", "cost", "radius", "range", "stun", "count", "hits", "pulses", "duration", "amount", "heal", "instant", "poison", "burn", "slow", "pierce", "execute"]:
					if c.has(k) and str(c[k]) != str(a.get(k, "-")):
						diff.append("%s %s->%s" % [k, _fmt(a.get(k, "-")), _fmt(c[k])])
				if not diff.is_empty():
					parts.append("%s{%s}" % [sid, ", ".join(diff)])
			var changed: bool = before != p._stat_line() and not parts.is_empty()
			all_ok = all_ok and changed and to_ks == 10
			print("TALENT SELFTEST %s/%s (%d points to %s, %d with centre keystone): %s -> %s | %s | bonuses: %s" % [cls, Talents.TREES[cls][b]["name"],
				to_ks, Talents.node(ks)["name"], tl.size(), before, p._stat_line(), "; ".join(parts), ", ".join(Stats.describe(p.tmods))])
			p.free()
	print("TALENT SELFTEST %s" % ("OK" if all_ok else "FAILED"))
	get_tree().quit(0 if all_ok else 1)


func _fmt(v: Variant) -> String:
	if typeof(v) == TYPE_FLOAT:
		return "%.2f" % v
	if typeof(v) == TYPE_ARRAY:
		var o: Array = []
		for x in v:
			o.append(_fmt(x))
		return "[" + ",".join(o) + "]"
	return str(v)


## The portal in `from` that leads (directly or eventually) to `to`.
## Zones form a chain in Zones.ORDER, so step one zone toward the target.
func _portal_towards(from: String, to: String) -> Dictionary:
	if Zones.is_dungeon(from) or Zones.is_dungeon(to):   # instances only have the exit portal to town
		return Zones.info(from)["portals"][0] if Zones.is_dungeon(from) else {}
	var a := Zones.index_of(from)
	var b := Zones.index_of(to)
	if a == b:
		return {}
	var next: String = Zones.ORDER[a + (1 if b > a else -1)]
	for p in Zones.info(from)["portals"]:
		if p["to"] == next:
			return p
	return {}


## Bot movement: A* over the zone's tile grid, re-planned every second.
func _bot_steer(zone: Node, from: Vector2, goal: Vector2, delta: float) -> Vector2:
	var gcell: Vector2i = zone.map.local_to_map(goal)
	var fcell: Vector2i = zone.map.local_to_map(from)
	_bot_path_t -= delta
	if _bot_path.is_empty() or _bot_path_t <= 0.0 or Vector2(gcell).distance_to(Vector2(_bot_goal)) > 1.5:
		_bot_path_t = 1.0
		_bot_goal = gcell
		_bot_path.clear()
		if _bot_astar.is_in_boundsv(fcell) and _bot_astar.is_in_boundsv(gcell) \
				and not _bot_astar.is_point_solid(gcell) and not _bot_astar.is_point_solid(fcell):
			for c in _bot_astar.get_id_path(fcell, gcell):
				_bot_path.append(zone.map.cell_pos(c))
	while _bot_path.size() > 1 and from.distance_to(_bot_path[0]) < 10.0:
		_bot_path.pop_front()
	if _bot_path.size() <= 1:
		return from.direction_to(goal) if from.distance_to(goal) > 20.0 else Vector2.ZERO
	return from.direction_to(_bot_path[0])


func _nearest(root: Node, from: Vector2, max_d: float) -> Node2D:
	var best: Node2D = null
	var best_d := max_d
	for n in root.get_children():
		if "alive" in n and not n.alive:
			continue
		var d: float = n.position.distance_to(from)
		if d < best_d:
			best_d = d
			best = n
	return best


## Screenshot trigger (--screenshot-when): wait until the scene is worth a picture.
func _screenshot_ready() -> bool:
	if _screenshot_when == "":
		return true
	var me := _local_player()
	if me == null or me.zone == null or not me.zone.is_dungeon():
		_shot_since = -1.0
		return false
	var ok := true
	if _screenshot_when == "boss":
		ok = false
		for m in me.zone.monsters_root.get_children():
			if m.is_boss and m.alive and m.position.distance_to(me.position) < 170.0 and m.hp < m.max_hp:
				ok = true
	if not ok:
		_shot_since = -1.0
		return false
	if _shot_since < 0.0:
		_shot_since = _elapsed
	return _elapsed - _shot_since > (0.6 if _screenshot_when == "boss" else 6.0)


func _log_status() -> void:
	if multiplayer.is_server() and is_dedicated:
		var parts: Array = []
		for id in Zones.ORDER:
			var z: Node = zones[id]
			var alive := 0
			for m in z.monsters_root.get_children():
				if m.alive:
					alive += 1
			var names: Array = []
			for p in z.players_root.get_children():
				names.append("%s(Lv%d %d/%dhp %d/%dmp %s%s)" % [p.display_name, p.level, p.hp, p.max_hp, p.mp, p.max_mp, p.class_id, " DEAD" if p.dead else ""])
			parts.append("%s: players=%s monsters=%d/%d loot=%d" % [id, names, alive, z.monsters_root.get_child_count(), z.loot_root.get_child_count()])
		var dl: Array = []
		for id in instances.runs:
			var r: Dictionary = instances.runs[id]
			var zz: Node = zones[id]
			var al := 0
			for m in zz.monsters_root.get_children():
				if m.alive:
					al += 1
			dl.append("%s(%s T%d owner=%s players=%d monsters=%d/%d portals=%d%s)" % [id, r["theme"], r["tier"], r["owner"],
				zz.players_root.get_child_count(), al, zz.monsters_root.get_child_count(), r["portals"], " DONE" if r["completed"] else ""])
		if not dl.is_empty():
			parts.append("instances: " + ", ".join(dl))
		_log("status: " + " | ".join(parts))
		return
	var me := _local_player()
	if me == null:
		return
	var z: Node = me.zone
	var ps: Array = []
	for p in z.players_root.get_children():
		ps.append("%s(Lv%d %d/%dhp%s)@%s" % [p.display_name, p.level, p.hp, p.max_hp, " DEAD" if p.dead else "", p.position.round()])
	var counts := {}
	for m in z.monsters_root.get_children():
		var k: String = m.type
		if not counts.has(k):
			counts[k] = [0, 0]
		counts[k][1] += 1
		if m.alive:
			counts[k][0] += 1
	var mons: Array = []
	for k in counts:
		mons.append("%s %d/%d" % [k, counts[k][0], counts[k][1]])
	# entities of OTHER zones this client received (should always be 0)
	var foreign := 0
	for zid in zones:
		if zid != z.zone_id:
			for root in [zones[zid].players_root, zones[zid].monsters_root, zones[zid].loot_root]:
				foreign += root.get_child_count()
	_log("status: zone=%s players=%d %s | monsters: %s | loot=%d | foreign_entities=%d" % [
		z.zone_id, ps.size(), ", ".join(ps), ", ".join(mons), z.loot_root.get_child_count(), foreign])


# ================================================================ UI

func _enter_game() -> void:
	in_game = true
	menu_root.visible = false
	hud.visible = not is_dedicated
	get_viewport().gui_release_focus()


func _build_ui() -> void:
	var ui := CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)

	# ---- main menu
	menu_root = Control.new()
	menu_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui.add_child(menu_root)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.07, 0.12, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_root.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_root.add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(360, 0)
	vb.add_theme_constant_override("separation", 6)
	margin.add_child(vb)

	var title := Label.new()
	title.text = GAME_TITLE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
	vb.add_child(title)
	var sub := Label.new()
	sub.text = "a tiny multiplayer RPG prototype"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(1, 1, 1, 0.7)
	vb.add_child(sub)

	vb.add_child(_mk_label("Account name"))
	name_edit = LineEdit.new()
	name_edit.text = "Hero%d" % rng.randi_range(100, 999)
	name_edit.max_length = 16
	vb.add_child(name_edit)
	vb.add_child(_mk_label("Password (first join creates the account)"))
	pass_edit = LineEdit.new()
	pass_edit.secret = true
	pass_edit.max_length = 64
	pass_edit.placeholder_text = "password"
	vb.add_child(pass_edit)
	vb.add_child(_mk_label("Server address (host or host:port)"))
	addr_edit = LineEdit.new()
	addr_edit.text = "127.0.0.1"
	vb.add_child(addr_edit)

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	vb.add_child(hb)
	host_btn = Button.new()
	host_btn.text = "Host (listen server)"
	host_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_btn.pressed.connect(_on_host_pressed)
	hb.add_child(host_btn)
	join_btn = Button.new()
	join_btn.text = "Join"
	join_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	join_btn.pressed.connect(_on_join_pressed)
	hb.add_child(join_btn)
	status_label = Label.new()
	status_label.text = "Port %d (UDP). Host to play locally, or Join a server." % DEFAULT_PORT
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(360, 0)
	status_label.modulate = Color(1, 1, 1, 0.75)
	vb.add_child(status_label)

	# ---- in-game HUD
	hud = Control.new()
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.visible = false
	ui.add_child(hud)

	var stats_panel := PanelContainer.new()
	stats_panel.position = Vector2(10, 10)
	stats_panel.add_theme_stylebox_override("panel", _panel_style())
	hud.add_child(stats_panel)
	var svb := VBoxContainer.new()
	svb.custom_minimum_size = Vector2(230, 0)
	stats_panel.add_child(svb)
	stats_name = Label.new()
	stats_name.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	svb.add_child(stats_name)
	class_label = Label.new()
	class_label.add_theme_font_size_override("font_size", 12)
	svb.add_child(class_label)
	var hp_pair := _mk_bar(Color(0.85, 0.2, 0.2))
	hp_bar = hp_pair[0]
	hp_text = hp_pair[1]
	svb.add_child(hp_bar)
	var mp_pair := _mk_bar(Color(0.25, 0.45, 1.0))
	mp_bar = mp_pair[0]
	mp_text = mp_pair[1]
	svb.add_child(mp_bar)
	var xp_pair := _mk_bar(Color(0.75, 0.6, 0.2))
	xp_bar = xp_pair[0]
	xp_text = xp_pair[1]
	svb.add_child(xp_bar)
	stats_line = Label.new()
	stats_line.add_theme_font_size_override("font_size", 13)
	svb.add_child(stats_line)
	zone_label = Label.new()
	zone_label.add_theme_font_size_override("font_size", 13)
	zone_label.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	svb.add_child(zone_label)

	banner_label = Label.new()
	banner_label.anchor_left = 0.0
	banner_label.anchor_right = 1.0
	banner_label.offset_top = 70
	banner_label.offset_bottom = 150
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner_label.add_theme_font_size_override("font_size", 34)
	banner_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.5))
	banner_label.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.0))
	banner_label.add_theme_constant_override("outline_size", 8)
	banner_label.visible = false
	hud.add_child(banner_label)

	info_label = Label.new()
	info_label.anchor_left = 1.0
	info_label.anchor_right = 1.0
	info_label.offset_left = -300
	info_label.offset_right = -10
	info_label.offset_top = 8
	info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	info_label.add_theme_font_size_override("font_size", 13)
	info_label.add_theme_color_override("font_outline_color", Color.BLACK)
	info_label.add_theme_constant_override("outline_size", 4)
	hud.add_child(info_label)

	dead_label = Label.new()
	dead_label.text = "You were defeated...\nrespawning at the zone entrance"
	dead_label.set_anchors_preset(Control.PRESET_CENTER)
	dead_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dead_label.add_theme_font_size_override("font_size", 28)
	dead_label.add_theme_color_override("font_color", Color(1, 0.4, 0.4))
	dead_label.add_theme_color_override("font_outline_color", Color.BLACK)
	dead_label.add_theme_constant_override("outline_size", 6)
	dead_label.position = Vector2(-200, -120)
	dead_label.size = Vector2(400, 80)
	dead_label.visible = false
	hud.add_child(dead_label)

	var chat_panel := PanelContainer.new()
	chat_panel.anchor_top = 1.0
	chat_panel.anchor_bottom = 1.0
	chat_panel.offset_left = 10
	chat_panel.offset_right = 450
	chat_panel.offset_top = -200
	chat_panel.offset_bottom = -10
	chat_panel.add_theme_stylebox_override("panel", _panel_style())
	hud.add_child(chat_panel)
	var chat_vb := VBoxContainer.new()
	chat_panel.add_child(chat_vb)
	chat_log = RichTextLabel.new()
	chat_log.bbcode_enabled = true
	chat_log.scroll_following = true
	chat_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	chat_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chat_log.add_theme_font_size_override("normal_font_size", 13)
	chat_vb.add_child(chat_log)
	chat_edit = LineEdit.new()
	chat_edit.placeholder_text = "Press Enter to chat, Esc to cancel"
	chat_edit.max_length = 200
	chat_edit.text_submitted.connect(_on_chat_submitted)
	chat_edit.gui_input.connect(_on_chat_gui_input)
	chat_vb.add_child(chat_edit)

	inventory_ui = InventoryUIScript.new()
	inventory_ui.anchor_left = 1.0
	inventory_ui.anchor_right = 1.0
	inventory_ui.offset_left = -572
	inventory_ui.offset_right = -10
	inventory_ui.offset_top = 80
	inventory_ui.visible = false
	hud.add_child(inventory_ui)
	smith_ui = BlacksmithUIScript.new()
	smith_ui.position = Vector2(10, 80)
	smith_ui.visible = false
	hud.add_child(smith_ui)
	map_ui = MapUIScript.new()
	map_ui.position = Vector2(10, 80)
	map_ui.visible = false
	hud.add_child(map_ui)
	atlas_ui = AtlasUIScript.new()
	atlas_ui.position = Vector2(50, 22)
	atlas_ui.visible = false
	hud.add_child(atlas_ui)
	hideout_ui = HideoutUIScript.new()
	hideout_ui.position = Vector2(10, 70)
	hideout_ui.visible = false
	hud.add_child(hideout_ui)
	market_ui = MarketUIScript.new()
	market_ui.position = Vector2(10, 70)
	market_ui.visible = false
	hud.add_child(market_ui)
	item_tip = ItemTooltipScript.new()
	hud.add_child(item_tip)
	market_ui.tooltip = item_tip
	inventory_ui.market_ui = market_ui
	market_ui.visibility_changed.connect(func(): inventory_ui.set_compact(market_ui.visible))
	inventory_ui.map_ui = map_ui
	inventory_ui.tooltip = item_tip
	inventory_ui.smith = smith_ui
	smith_ui.tooltip = item_tip
	smith_ui.inventory = inventory_ui

	skill_bar = SkillBarScript.new()
	skill_bar.anchor_left = 0.5
	skill_bar.anchor_right = 0.5
	skill_bar.anchor_top = 1.0
	skill_bar.anchor_bottom = 1.0
	skill_bar.offset_left = -118
	skill_bar.offset_right = 118
	skill_bar.offset_top = -66
	skill_bar.offset_bottom = -10
	hud.add_child(skill_bar)

	target_frame = PanelContainer.new()
	target_frame.add_theme_stylebox_override("panel", _panel_style())
	target_frame.anchor_left = 0.5
	target_frame.anchor_right = 0.5
	target_frame.offset_left = -170
	target_frame.offset_right = 170
	target_frame.offset_top = 8
	target_frame.visible = false
	hud.add_child(target_frame)
	var tfh := HBoxContainer.new()
	target_frame.add_child(tfh)
	_tf_icon = TextureRect.new()
	_tf_icon.custom_minimum_size = Vector2(32, 32)
	_tf_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_tf_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tfh.add_child(_tf_icon)
	var tfv := VBoxContainer.new()
	tfv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tfh.add_child(tfv)
	_tf_name = Label.new()
	_tf_name.add_theme_font_size_override("font_size", 13)
	tfv.add_child(_tf_name)
	var tf_pair := _mk_bar(Color(0.85, 0.2, 0.2))
	_tf_hp = tf_pair[0]
	_tf_hp_text = tf_pair[1]
	tfv.add_child(_tf_hp)
	var tfs := RichTextLabel.new()
	tfs.bbcode_enabled = true
	tfs.fit_content = true
	tfs.scroll_active = false
	tfs.custom_minimum_size = Vector2(290, 18)
	tfs.add_theme_font_size_override("normal_font_size", 12)
	tfs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tfv.add_child(tfs)
	_tf_status = tfs

	talent_ui = TalentUIScript.new()
	talent_ui.anchor_left = 0.5
	talent_ui.anchor_right = 0.5
	talent_ui.offset_left = -470
	talent_ui.offset_top = 50
	talent_ui.visible = false
	hud.add_child(talent_ui)

	char_sheet = CharacterSheetScript.new()
	char_sheet.anchor_left = 0.5
	char_sheet.anchor_right = 0.5
	char_sheet.offset_left = -275
	char_sheet.offset_top = 70
	char_sheet.visible = false
	hud.add_child(char_sheet)

	class_select = ClassSelectScript.new()
	class_select.visible = false
	class_select.chosen.connect(_on_class_chosen)
	ui.add_child(class_select)


func _on_host_pressed() -> void:
	start_server(_parse_address(addr_edit.text, DEFAULT_PORT)[1], false)


func _on_join_pressed() -> void:
	var a := _parse_address(addr_edit.text, DEFAULT_PORT)
	start_client(a[0], a[1])


func _panel_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.5)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(8)
	return sb


func _mk_bar(color: Color) -> Array:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(230, 18)
	bar.show_percentage = false
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.1, 0.1, 0.9)
	bg.set_corner_radius_all(3)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bg)
	bar.add_theme_stylebox_override("fill", fill)
	var l := Label.new()
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 3)
	bar.add_child(l)
	return [bar, l]


func _mk_label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l


# ================================================================ helpers

func _parse_address(text: String, default_port: int) -> Array:
	var t := text.strip_edges()
	if t.is_empty():
		t = "127.0.0.1"
	var port := default_port
	var idx := t.rfind(":")
	if idx > 0 and t.count(":") == 1:
		port = int(t.substr(idx + 1))
		t = t.substr(0, idx)
	return [t, port]


func _sanitize_name(n: String) -> String:
	var s := n.strip_edges().replace("[", "").replace("]", "").left(16)
	if s.is_empty():
		s = "Hero%d" % rng.randi_range(100, 999)
	return s


func _escape(t: String) -> String:
	return t.replace("[", "[lb]")


func _log(msg: String) -> void:
	var role := "CLIENT %s" % local_name
	if not multiplayer.has_multiplayer_peer() or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		role = "MENU"
	elif multiplayer.multiplayer_peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		role = "CLIENT %s" % local_name
	elif multiplayer.is_server():
		role = "SERVER"
	print("[%s] [%s] %s" % [Time.get_time_string_from_system(), role, msg])
