extends Node2D
const Vendor := preload("res://scripts/vendor.gd")
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
##   --vendor-rotate=SECS  server: vendor stock rotation period (default 2h; stock saved to vendor.json / X_vendor.json beside --save-file=X.json)
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
##   --no-interest       server (benchmarks only): no interest radius, every monster synced + simulated
##   --bench=SECS        client: measure frame time / nodes / physics for SECS seconds, print a BENCH line, quit
##   --bigmap-selftest   offline checks of the big overworld maps (size, reachability, groups, old-save positions)
##   --gear-selftest     offline gear checks (drop statistics, orbs, enhancement, resistances)
##   --open-smith        open the blacksmith panel when standing next to it (screenshots)
##   --debug-tooltip=N   show the tooltip of the N-th gear item in the bag (screenshots)
##   --open-sheet        open the character sheet (C) on login (screenshots)
##   --quit-after=SECS   quit automatically after SECS seconds (for tests)
##   --screenshot=PATH   save a screenshot after --screenshot-delay=SECS (default 6; needs a display)
##   --open-inventory    open the inventory panel once in game (for screenshots)
##   --show-fps          show the F3 FPS overlay from the start (screenshots / reports)
##   --open-zone-map     open the full zone map (N) once in game (for screenshots)

const GAME_TITLE := "Project Volam"
const DEFAULT_PORT := 7777
## Build/protocol version checked on join (handshake.gd). Bump it whenever RPCs or synced data change.
const BUILD_VERSION := "volam-m2.2"
const MAX_PLAYERS := 32
const SAVE_INTERVAL := 30.0
const DEFAULT_SAVE_FILE := "user://volam_save/accounts.json"

const ZoneScript := preload("res://scripts/zone.gd")
const MapPortalVisualScript := preload("res://scripts/map_portal_visual.gd")
const InventoryUIScript := preload("res://scripts/inventory_ui.gd")
const BlacksmithUIScript := preload("res://scripts/blacksmith_ui.gd")
const MapUIScript := preload("res://scripts/map_ui.gd")
const AtlasUIScript := preload("res://scripts/atlas_ui.gd")
const PauseMenuScript := preload("res://scripts/pause_menu.gd")
const VendorUIScript := preload("res://scripts/vendor_ui.gd")
const TutorialUIScript := preload("res://scripts/tutorial_ui.gd")
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
var minimap: Control            # minimap / N zone map (scripts/minimap.gd)
var fps_label: Label            # F3: FPS / frame ms / monsters on this client (off by default)
var _fps_t := 0.0
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
var _show_fps := false
var _open_zone_map := false       # client (screenshots): open the N zone map once in game
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
var craft_seed := -1               # server (tests): --craft-seed=N seeds every player's crafting / enhancement RNG
var ticket_drop_chance := -1.0    # server (tests): --ticket-drop-chance=0..1 overrides the base Dungeon Ticket chance of normal dungeon monsters (3%)
var decor_drop_chance := -1.0     # server (tests): --decor-drop-chance=0..1 overrides the boss decoration drop chance
var bot_guardian := ""           # dungeon bot: --bot-guardian=fire:10 asks for a debug Guardian ticket (server needs --debug-atlas-kit)
var bot_watch_patrol := false     # bot: --bot-watch-patrol stands within activation range of a meadow patrol route (out of aggro range)
var _watch_sent := false
var menu_hideout_test := false    # client: --menu-hideout-test opens the Esc menu and clicks its Hideout button
var _mht_step := 0
var _mht_t := 0.0
var hideout_debug := false         # server (tests): every hideout theme unlocked, boss always drops a decoration
var hideouts: Node                 # player hideouts (hideout_server.gd), on every peer
var vendor: Node                   # NPC vendor (vendor_server.gd), on every peer
var vendor_ui: PanelContainer
var tutorial_ui: PanelContainer
var bot_tutorial := ""             # bot: "full" (do every tutorial step) | "skip"
static var _last_name := ""       # survives the scene reload of Return to Main Menu
var aim_selftest := false         # client (tests): --aim-selftest, skill aim = selected target, else the cursor at the key press
var _test_cursor = null           # aim selftest: stands in for the mouse (headless has none)
var ui_selftest := false          # client (tests): --ui-selftest checks exclusive windows, N-map layer, tutorial placement
var show_tutorial := false         # client: show the tutorial even when headless / a bot (tests, screenshots)
var vendor_rotate := 0             # server (tests): --vendor-rotate=SECS stock rotation period (0 = default 2h)
var bot_vendor := ""               # bot: vendor test role ("1" = buy/sell session, "2" = after a restart)
var _open_vendor := false          # client (screenshots): open the vendor panel
var bot_vendor_role := ""          # bot: "probe" = first try to buy what it can't (no gold / full bag), never sells
var _bv_done := {}
var hideout_ui: PanelContainer
var bot_hideout := ""              # client (tests): run the hideout bot ("1" = first session, "2" = after a restart)
var _hideout_shot := ""            # client (screenshots): "decor" | "mode" | "theme"
var _class_from_cli := false       # client: --class=X given -> pick it automatically (screenshots)
var debug_real_kit := false        # server (tests): --debug-level-for/--debug-start-level characters get the real start kit, not the 5+5 potion test kit
var instance_timeout := 0.0        # server: seconds an empty dungeon stays open (0 = default)
var complete_timeout := 0.0        # server: seconds a completed dungeon stays open (0 = default)
var debug_atlas_kit := false      # server: honour the bots' "debug_kit" request (a locked fire:3 ticket)
var debug_next_tier := -1.0        # server: chance a boss ticket is tier+1 (-1 = default 50%)
var bot_dungeon := ""              # bot: "full" | "die" | "enter" | "first" (free normal ticket, no crafting, fight) - dungeon test scenarios
var bot_dungeon_theme := "wood"
var bot_dungeon_tier := 1
var _bd_walk_t := 0.0
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
var _tf_invite: Button     # target frame: invite the selected player
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
var debug_level_for := {}          # server (tests): --debug-level-for=MetalA:22,... start level per new account (overrides --debug-start-level)
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
var _bot_probe_goal := Vector2.INF   # --bot-probe: walk toward a monster behind a wall until the line-of-sight probe can fire
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
var parties: Node                  # parties (party.gd), server state; party_state RPCs update the HUD
var party_label: Label
var party_members: Array = []      # client: [{name, class, level, zone}] of my party ([] = no party)
var party_leader := ""
var party_panel_pref := 0         # P key: 0 = automatic (shown while in a party), 1 = shown, -1 = hidden
var invite_box: PanelContainer
var _invite_from := ""
var bot_no_potions := false        # bot: never drinks (first-pull trial without potions)
var bot_follow := ""               # bot: walk after this player and never attack (--bot-follow=NAME, party XP-share test)
var bot_party := ""                # bot: "invite:<Name>" (leader) | "accept" (member)
var _bp_t := 0.0
var _bp_probed := false
var _bf_log_t := 0.0
var _bd_safe := 0
var _bd_safe_t := 0.0
var _bd_safe_hp := 0
var _dungeon_complete_seen := false
var handshake: Node                # version handshake (handshake.gd), first RPC exchange on join
var _fake_version := ""            # client (tests): --fake-version=X claims another build
var _skip_handshake := false       # client (tests): behave like an old build (no handshake, straight to login)
var _hs_wait := -1.0               # client: seconds waiting for the server's version answer
var bot_smart := false             # bot (balance trial): --bot-smart casts only ready skills sensibly, ranged classes keep their distance
var no_xp := false                 # server (balance trial): --no-xp keeps every character at its level
var solo_mode := false             # "Play Solo": in-process local server bound to 127.0.0.1, no login, local profile slots
var solo_slot := 1
var solo_port := DEFAULT_PORT       # first port the solo server tries (127.0.0.1 only)
var solo_btn: Button
var solo_slot_pick: OptionButton
const SOLO_SAVE_FILE := "user://volam_save/solo_profile.json"
const SOLO_SLOTS := 3


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
	handshake = preload("res://scripts/handshake.gd").new()
	handshake.version = BUILD_VERSION
	add_child(handshake)
	handshake.accepted.connect(_on_version_accepted)
	handshake.rejected.connect(func(msg: String): _hs_wait = -1.0; login_result(false, msg))
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
	_add_action("party_panel", [KEY_P])
	_add_action("zone_map", [KEY_N])
	_add_action("fps_overlay", [KEY_F3])


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
	parties = preload("res://scripts/party.gd").new()
	parties.name = "Parties"
	add_child(parties)
	vendor = preload("res://scripts/vendor_server.gd").new()
	vendor.name = "Vendor"
	add_child(vendor)
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
	debug_real_kit = opts.has("debug-real-kit")
	complete_timeout = float(opts.get("complete-timeout", "0"))
	debug_next_tier = float(opts.get("debug-next-tier", "-1"))
	bot_dungeon = str(opts.get("bot-dungeon", ""))
	bot_dungeon_theme = str(opts.get("bot-dungeon-theme", "wood"))
	bot_dungeon_tier = int(opts.get("bot-dungeon-tier", "1"))
	bot_dungeon_unique = opts.has("bot-dungeon-unique")
	bot_atlas = opts.has("bot-atlas")
	debug_atlas_kit = opts.has("debug-atlas-kit")
	_open_map_ui = str(opts.get("open-map-ui", ""))
	vendor_rotate = int(opts.get("vendor-rotate", "0"))
	bot_vendor = str(opts.get("bot-vendor", ""))
	bot_vendor_role = str(opts.get("bot-vendor-role", ""))
	bot_tutorial = str(opts.get("bot-tutorial", ""))
	ui_selftest = opts.has("ui-selftest")
	aim_selftest = opts.has("aim-selftest")
	show_tutorial = bot_tutorial != "" or opts.has("show-tutorial") or ui_selftest
	_open_vendor = opts.has("open-vendor")
	bot_party = str(opts.get("bot-party", ""))
	bot_follow = str(opts.get("bot-follow", ""))
	bot_no_potions = opts.has("bot-no-potions")
	no_xp = opts.has("no-xp")
	bot_smart = opts.has("bot-smart")
	_fake_version = str(opts.get("fake-version", ""))
	_skip_handshake = opts.has("skip-handshake")
	_open_atlas = opts.has("open-atlas")
	_open_zone_map = opts.has("open-zone-map")
	_show_fps = opts.has("show-fps")
	if fps_label:
		fps_label.visible = _show_fps
	hideout_debug = opts.has("hideout-debug")
	decor_drop_chance = clampf(float(opts.get("decor-drop-chance", "-1")), -1.0, 1.0)
	craft_seed = int(opts.get("craft-seed", "-1"))
	ticket_drop_chance = clampf(float(opts.get("ticket-drop-chance", "-1")), -1.0, 1.0)
	bot_guardian = str(opts.get("bot-guardian", ""))
	bot_watch_patrol = opts.has("bot-watch-patrol")
	menu_hideout_test = opts.has("menu-hideout-test")
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
	for kv in str(opts.get("debug-level-for", "")).split(",", false):
		var kvp: PackedStringArray = kv.split(":")
		if kvp.size() == 2:
			debug_level_for[kvp[0].to_lower()] = int(kvp[1])
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
	if opts.has("bigmap-selftest"):
		_bigmap_selftest()
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
	_bench_secs = float(opts.get("bench", 0.0))
	if opts.has("no-interest"):
		ZoneScript.interest = false
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
	elif opts.has("solo"):
		start_solo(int(opts.get("solo-slot", "1")), port)
	elif opts.has("click-solo"):
		# test: press the main menu's Play Solo button like a user would (one click)
		_refresh_solo_slots()
		solo_slot_pick.select(clampi(int(opts.get("solo-slot", "1")) - 1, 0, SOLO_SLOTS - 1))
		_log("menu test: clicking Play Solo (%s)" % solo_slot_pick.get_item_text(solo_slot_pick.selected))
		solo_port = port
		solo_btn.pressed.emit()
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
	_last_name = local_name   # (solo too: the name box keeps what you typed after Return to Main Menu)
	local_password = pass_edit.text
	accounts = AccountStore.new(save_file)
	accounts.load_file()
	if vendor_rotate > 0:
		vendor.period = vendor_rotate
	vendor.load_from(accounts)
	if solo_mode:
		local_name = _solo_account()
	elif not dedicated:
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
	elif solo_mode:
		# local only: bound to the loopback, try a few ports in case 7777 is taken by another server
		for p in range(port, port + 10):
			var enet := ENetMultiplayerPeer.new()
			enet.set_bind_ip("127.0.0.1")
			err = enet.create_server(p, 1)
			if err == OK:
				peer = enet
				port = p
				break
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
		"Dedicated" if dedicated else ("Solo (local, in-process)" if solo_mode else "Listen"), port, "WebSocket" if use_ws else "ENet/UDP",
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
		for k in ["blacksmith", "map_device", "merchant", "vendor", "hideout_master", "respawn"]:
			if z.info.has(k) and not z.map.is_reachable(z.info[k]):
				bad.append(k)
		for st in z.map.sites:
			if int(st["spec"]) >= 0 and not z.map.is_reachable(st["cell"]):
				bad.append("site %s" % st["cell"])
		_log("Zone %s ready: %d monsters, %d reachable cells%s" % [id, z.monsters_root.get_child_count(),
			z.map.reachable.size(), "" if bad.is_empty() else " UNREACHABLE: %s" % [bad]])
	if not dedicated:
		_login_ok(1, local_name, local_password)
	return true


func start_client(address: String, port: int) -> bool:
	local_name = _sanitize_name(name_edit.text)
	_last_name = local_name
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
	if multiplayer.is_server() and solo_mode:
		_log("Solo game: refusing peer %d" % id)
		(multiplayer.multiplayer_peer as ENetMultiplayerPeer).disconnect_peer(id)
		return
	if multiplayer.is_server():
		handshake.server_peer_connected(id)
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
	handshake.server_peer_left(id)
	parties.on_peer_left(str(peer_accounts.get(id, "")))
	instances.on_peer_left(id)
	var pname: String = player_names.get(id, "")
	player_names.erase(id)
	peer_accounts.erase(id)
	_log("Peer %d (%s) disconnected" % [id, pname if pname != "" else "not logged in"])
	if pname != "":
		broadcast_system("%s left the world." % pname)


func _on_connected_to_server() -> void:
	if _skip_handshake:
		_log("Connected to server as peer %d, logging in WITHOUT a version handshake (test)" % multiplayer.get_unique_id())
		register_player.rpc_id(1, local_name, local_password)
		return
	var v := _fake_version if _fake_version != "" else BUILD_VERSION
	_log("Connected to server as peer %d, checking the version (%s)" % [multiplayer.get_unique_id(), v])
	_hs_wait = 0.0
	handshake.hello.rpc_id(1, v)


func _on_version_accepted() -> void:
	_hs_wait = -1.0
	_log("Version %s accepted by the server, logging in" % BUILD_VERSION)
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
	var is_new: bool = not accounts.has_account(pname) or (solo_mode and accounts.get_account(pname).get("character", {}).is_empty())
	if not accounts.has_account(pname):
		accounts.create_account(pname, password)
		accounts.save_file()
		_log("Created account '%s'" % pname)
	var acc := accounts.get_account(pname)
	var display: String = str(acc.get("name", pname))
	var character: Dictionary = acc.get("character", {})
	if is_new and (debug_start_level > 1 or debug_level_for.has(pname.to_lower())) and not (debug_fresh != "" and pname.to_lower().begins_with(debug_fresh.to_lower())):
		var lv0: int = int(debug_level_for.get(pname.to_lower(), debug_start_level))   # --debug-level-for=name:lv,...
		character = {"level": lv0, "gold": 250, "inventory": {"health_potion": 5, "greater_potion": 5}, "items_v": 2}
		if debug_real_kit:   # --debug-real-kit: only the level; potions/gold exactly like a real new character (class start_items)
			character = {"level": lv0, "gold": 0, "inventory": {}, "items_v": 2}
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
		_log("(debug) new account '%s' starts at level %d" % [pname, lv0])
	player_names[id] = display
	peer_accounts[id] = AccountStore.key_for(pname)
	if not Classes.exists(str(character.get("class", ""))):
		# new account, or a save from before classes existed: pick one first
		_awaiting_class[id] = {"name": pname, "is_new": is_new}
		_log("Account '%s' has no class yet - asking peer %d to choose (%s)" % [display, id, "new account" if is_new else "old save"])
		login_result.rpc_id(id, true, _welcome_text(is_new, display))
		class_select_request.rpc_id(id, is_new)
		return
	_spawn_logged_in(id, pname, is_new)
	login_result.rpc_id(id, true, _welcome_text(is_new, display))
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
	hud.visible = false   # the class cards would overlap chat / help text / skill bar


func _on_class_chosen(cls: String) -> void:
	class_select.visible = false
	hud.visible = true
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
			kit["bound"] = true     # starting gear is account-bound
			eq[Items.slots_for(base)[0]] = kit
		character["equipment"] = eq
		character["items_v"] = 2
		character["tutorial"] = "pending"     # first-time tutorial, shown once
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
		var mv := int(character.get("map_v", 1))
		if Zones.DB.has(zone_id) and mv < Zones.MAP_VERSION:   # saved before the 10x bigger maps
			var moved := Zones.migrate_pos(zone_id, p, mv)
			_log("Login '%s': old-map position %s in %s shifted to %s (map v%d -> v%d)" % [display, p.round(), zone_id, moved.round(), mv, Zones.MAP_VERSION])
			p = moved
		if z.map.is_reachable(z.map.local_to_map(p)) and z.portal_at(p).is_empty():
			pos = p
		else:
			pos = z.map.nearest_reachable_pos(p, z.info["respawn"])
			_log("Login '%s': saved position %s is not a valid spot in %s - relocated to %s" % [display, p.round(), zone_id, pos.round()])
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
		if node.tutorial == "pending":
			_log("[tutorial] %s: starting the tutorial (new character)" % display)
			get_tree().create_timer(0.4).timeout.connect(_send_tutorial.bind(weakref(node)))   # right after spawn, before the first keypress
		_log("Login '%s' (peer %d): %s - class %s, level %d, xp %d, hp %d/%d, mp %d/%d, gold %d, items %s, equip %s, bag %d/%d %s, stash %d %s, zone %s, pos %s, talent points %d/%d %s" % [
			display, id, "NEW account" if is_new else "restored save", node.class_id, node.level, node.xp, node.hp,
			node.max_hp, node.mp, node.max_mp, node.gold, node.inventory, node.equip_summary(), node.bag_used(), Items.BAG_SIZE,
			_inst_list(node.bag), node.stash.size(), _inst_list(node.stash), zone_id, pos.round(),
			Talents.points_spent(node.talents), Talents.points_total(node.level), node.talents])
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
	peer_zone[id] = to_zone
	# despawn the old zone's entities (and the old player node) for this peer NOW, before the
	# new player is spawned: otherwise the client gets its new player first and still holds the
	# old zone's monsters/loot until the next visibility pass (seen as foreign_entities > 0)
	node.zone.hide_from(id)
	node.queue_free()
	_zone_since[id] = Time.get_ticks_msec()
	_pending_chars[id] = c
	var nn: Node = dest.player_spawner.spawn({"id": id, "name": pname, "pos": pos, "class": node.class_id})
	nn.account_key = str(peer_accounts.get(id, ""))
	_push_inventory_later(nn)
	instances.on_transfer(id, from, to_zone)
	parties.on_zone_changed.call_deferred(nn.account_key)   # party panels show where everyone is
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
	if not handshake.is_ok(id):
		_log("Ignored login from peer %d: no accepted version handshake" % id)
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


func _send_tutorial(ref: WeakRef) -> void:
	var node: Node = ref.get_ref()
	if node and not node.is_queued_for_deletion() and node.tutorial == "pending":
		tutorial_start.rpc_id(node.peer_id)


## Client: a short server message over your own head (and optionally in chat). See player.notify().
@rpc("authority", "call_local", "reliable")
func player_notice(text: String, to_chat: bool) -> void:
	var me := _local_player()
	if me:
		NetUtil.popup(me, text, Color(0.8, 0.9, 1.0), -70.0)
	local_notice(text, to_chat)


## Client: "+N XP (kill)" line for the chat log only (no floating text: the kill already shows one).
@rpc("authority", "call_local", "reliable")
func xp_notice(text: String) -> void:
	if bot_mode:
		_log("notice: " + text)
	if chat_log:
		chat_log.append_text("[color=#e8d27a]%s[/color]\n" % _escape(text))


## Client: the server wants this (new) character to see the first-time tutorial.
@rpc("authority", "call_local", "reliable")
func tutorial_start() -> void:
	if (bot_mode or DisplayServer.get_name() == "headless") and not show_tutorial:
		return
	_log("tutorial started")
	tutorial_ui.begin()


## Bot (--bot-tutorial=full|skip): play through or skip the tutorial.
func _bot_tutorial(me: Node, zone: Node, delta: float) -> void:
	_bot_attack_timer -= delta
	bot_dir = Vector2.ZERO
	if bot_tutorial == "skip":
		if _bot_attack_timer < -2.0:
			tutorial_ui.skip_tutorial()
		return
	match tutorial_ui.step:
		0:
			bot_dir = Vector2.RIGHT
		1:
			if _bot_attack_timer <= 0.0:
				_bot_attack_timer = 1.0
				me.request_skill(0)
		2:
			var p: Node2D = _nearest(zone.loot_root, me.position, 600.0)
			if p and me.position.distance_to(p.position) > 20.0:
				bot_dir = me.position.direction_to(p.position)
			elif p and _bot_attack_timer <= 0.0:
				_bot_attack_timer = 0.5
				me.request_pickup()
		3:
			if _bot_attack_timer <= 0.0:
				_bot_attack_timer = 1.0
				for inst in me.bag:
					if inst["base"] == "leather_cap":
						me.request_equip(int(inst["uid"]))
		4:
			if _bot_attack_timer <= 0.0:
				talent_ui.visible = true


## Client: my party changed (members [] = not in a party).
@rpc("authority", "call_local", "reliable")
func party_state(members: Array, leader: String) -> void:
	party_members = members
	party_leader = leader
	if members.size() > 1 and invite_box and invite_box.visible:
		invite_box.visible = false   # in a party now (accepted somewhere): no stale invite popup
		_log("invite popup closed (joined a party)")
	var names: Array = []
	var where: Array = []
	for m in members:
		names.append(str(m["name"]))
		where.append("%s@%s" % [m["name"], m.get("zone", "")])
	_log("party state: %d member(s) [%s], leader %s | zones: %s" % [members.size(), ", ".join(names), leader if leader != "" else "-", " ".join(where)])
	_update_party_label()


## Client: someone invited me to their party.
@rpc("authority", "call_local", "reliable")
func party_invite(from: String) -> void:
	_invite_from = from
	_log("party invite from %s" % from)
	if bot_party == "accept":
		send_chat("/accept")
		return
	if invite_box:
		(invite_box.get_node("V/L") as Label).text = "%s invites you to a party." % from
		invite_box.visible = true
	if bot_party == "accept-chat":   # test: answer like a player typing /accept (popup must close)
		get_tree().create_timer(1.0).timeout.connect(func():
			_log("typing /accept with the invite popup %s" % ("open" if invite_box.visible else "closed"))
			send_chat("/accept")
			await get_tree().create_timer(1.5).timeout
			_log("invite popup after /accept: %s" % ("STILL OPEN" if invite_box.visible else "closed")))


func _answer_invite(yes: bool) -> void:
	invite_box.visible = false
	send_chat("/accept" if yes else "/decline")


func _update_party_label() -> void:
	if party_label == null:
		return
	party_label.visible = party_panel_pref == 1 or (party_panel_pref == 0 and party_members.size() > 1)
	var lines: Array = ["Party  (P hides)"]
	if party_members.size() <= 1:
		lines.append("  Not in a party.")
		lines.append("  /invite NAME, or select a player > Invite")
	for m in party_members:
		var cls := str(m.get("class", ""))
		var zname := str(m.get("zone_name", ""))
		if zname == "" and Zones.exists(str(m.get("zone", ""))):
			zname = str(Zones.info(str(m["zone"]))["name"])
		lines.append("%s%s  Lv%d %s%s" % ["* " if str(m["name"]) == party_leader else "  ", m["name"], int(m.get("level", 0)),
			Classes.info(cls)["name"] if Classes.exists(cls) else "", ("  [%s]" % zname) if zname != "" else ""])
	party_label.text = "\n".join(lines)
	if hud and hud.get_node_or_null("PartyPanel"):
		(hud.get_node("PartyPanel") as Control).reset_size()
	if party_label.visible:
		_log("party panel: %s" % " | ".join(lines.slice(1)))


## P: show / hide the party panel (shown even without a party, with how to start one).
func toggle_party_panel() -> void:
	party_panel_pref = -1 if party_label.visible else 1
	_update_party_label()
	_log("party panel toggled (P): %s (%d member(s))" % ["shown" if party_label.visible else "hidden", party_members.size()])


func show_banner(title: String, sub: String) -> void:
	if title == "Dungeon Complete!":
		_dungeon_complete_seen = true
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
	if node and text.begins_with("/") and parties.chat_command(node, text):
		return
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
	var cmd := text.strip_edges().get_slice(" ", 0).to_lower()
	if invite_box and invite_box.visible and cmd in ["/accept", "/decline"]:
		invite_box.visible = false   # answered by typing: the popup goes too
		_log("invite popup closed (answered with %s in chat)" % cmd)
	submit_chat.rpc_id(1, text)


## Chat line. Typing is handled here in _input, NOT by giving the LineEdit GUI focus: on X11,
## Godot 4.2.1's LineEdit focus turns on the IME (DisplayServerX11::window_set_ime_active maps a
## child "xim" window and moves the X input focus to it, again on every caret blink), and keys
## typed right after Enter could get lost or reach the game (PlayTester: '/invite Bravo' sent as
## 'invite Bravo', '/accept' -> 'ccept' + the 'a' walked). Now Enter opens the chat synchronously
## and every key from then on goes into chat_text in order - no focus hand-off, no IME, nothing
## reaches hotkeys or movement until Enter/Esc. The LineEdit only displays the line.
var chat_open := false
var chat_text := ""
var chat_caret := 0
var _chat_style_open: StyleBoxFlat


func open_chat() -> void:
	if chat_open or chat_edit == null:
		return
	chat_open = true
	chat_active = true
	chat_text = ""
	chat_caret = 0
	Input.action_release("move_left"); Input.action_release("move_right")
	Input.action_release("move_up"); Input.action_release("move_down")
	_chat_refresh()


func close_chat() -> void:
	for act in InputMap.get_actions():   # keys typed into the chat (even ones whose release never came) are not held for the game
		if not str(act).begins_with("ui_"):
			Input.action_release(act)
	chat_open = false
	chat_active = false
	chat_text = ""
	chat_caret = 0
	_chat_refresh()


func _chat_refresh() -> void:
	if chat_edit == null:
		return
	chat_edit.text = chat_text
	chat_edit.caret_column = chat_caret
	chat_edit.caret_force_displayed = chat_open
	chat_edit.placeholder_text = "Type a message, Enter to send, Esc to cancel" if chat_open else "Press Enter to chat, Esc to cancel"
	if chat_open:
		chat_edit.add_theme_stylebox_override("normal", _chat_style_open)
	else:
		chat_edit.remove_theme_stylebox_override("normal")


func _chat_insert(t: String) -> void:
	t = t.replace("\n", " ").replace("\r", "").replace("\t", " ")
	t = t.substr(0, maxi(0, 200 - chat_text.length()))
	chat_text = chat_text.substr(0, chat_caret) + t + chat_text.substr(chat_caret)
	chat_caret += t.length()


## While the chat is open: one key event -> the chat line (always consumed).
func _chat_key(k: InputEventKey) -> void:
	if OS.has_environment("VOLAM_KEYLOG"):
		_log("chat key %s pressed=%s echo=%s unicode=%d" % [OS.get_keycode_string(k.keycode), k.pressed, k.echo, k.unicode])
	if not k.pressed:
		return
	var kc := k.keycode
	var ctrl := k.ctrl_pressed or k.meta_pressed
	if kc == KEY_ENTER or kc == KEY_KP_ENTER:
		var t := chat_text
		close_chat()
		send_chat(t)
		return
	if kc == KEY_ESCAPE:
		close_chat()
		return
	if kc == KEY_BACKSPACE:
		if chat_caret > 0:
			var from := chat_caret - 1
			if ctrl:   # delete the word before the caret
				from = chat_caret
				while from > 0 and chat_text[from - 1] == " ":
					from -= 1
				while from > 0 and chat_text[from - 1] != " ":
					from -= 1
			chat_text = chat_text.substr(0, from) + chat_text.substr(chat_caret)
			chat_caret = from
	elif kc == KEY_DELETE:
		chat_text = chat_text.substr(0, chat_caret) + chat_text.substr(chat_caret + 1)
	elif kc == KEY_LEFT:
		chat_caret = maxi(0, chat_caret - 1)
	elif kc == KEY_RIGHT:
		chat_caret = mini(chat_text.length(), chat_caret + 1)
	elif kc == KEY_HOME:
		chat_caret = 0
	elif kc == KEY_END:
		chat_caret = chat_text.length()
	elif (ctrl and kc == KEY_V) or (k.shift_pressed and kc == KEY_INSERT):
		_chat_insert(DisplayServer.clipboard_get())
	elif not ctrl and not k.alt_pressed and k.unicode >= 32:
		_chat_insert(String.chr(k.unicode))
	elif not ctrl and not k.alt_pressed and k.unicode == 0 and _keycode_char(k) != "":
		_chat_insert(_keycode_char(k))   # input tools that send keycodes without a unicode
	_chat_refresh()


## Enter presses count even when flagged echo: Godot 4.2.1's X11 backend
## (DisplayServerX11::_handle_key_event) turns a release+press of the same key within 5 ms
## into a dropped release + an "echo" press, and flags a press as echo whenever its Input key
## state still says down from the previous frame's batch. With fast or scripted typing (VNC,
## xdotool, a slow llvmpipe frame) "Enter (send) + Enter (open the next line)" arrives as
## Enter, Enter(echo) - and the old "not event.echo" check left the chat closed, so the next
## line ('/accept') went to the game: 'a' walked, 'c' opened the C panel. Holding Enter only
## toggles an empty line open/closed (empty lines are not sent).
## The character a keycode-only key event stands for (US layout), or "" for non-text keys.
static func _keycode_char(k: InputEventKey) -> String:
	var kc := k.keycode if k.keycode != KEY_NONE else (k.physical_keycode if k.physical_keycode != KEY_NONE else k.key_label)
	var sh := k.shift_pressed
	if kc >= KEY_A and kc <= KEY_Z:
		var c := String.chr(kc)
		return c if sh else c.to_lower()
	if kc >= KEY_0 and kc <= KEY_9:
		return ")!@#$%^&*(".substr(kc - KEY_0, 1) if sh else String.chr(kc)
	if kc >= KEY_KP_0 and kc <= KEY_KP_9:
		return String.chr(KEY_0 + kc - KEY_KP_0)
	var plain := {KEY_SPACE: " ", KEY_SLASH: "/", KEY_PERIOD: ".", KEY_COMMA: ",", KEY_MINUS: "-", KEY_EQUAL: "=", KEY_SEMICOLON: ";",
		KEY_APOSTROPHE: "'", KEY_BRACKETLEFT: "[", KEY_BRACKETRIGHT: "]", KEY_BACKSLASH: "\\", KEY_QUOTELEFT: "`",
		KEY_KP_DIVIDE: "/", KEY_KP_MULTIPLY: "*", KEY_KP_SUBTRACT: "-", KEY_KP_ADD: "+", KEY_KP_PERIOD: "."}
	var shifted := {KEY_SLASH: "?", KEY_PERIOD: ">", KEY_COMMA: "<", KEY_MINUS: "_", KEY_EQUAL: "+", KEY_SEMICOLON: ":",
		KEY_APOSTROPHE: "\"", KEY_BRACKETLEFT: "{", KEY_BRACKETRIGHT: "}", KEY_BACKSLASH: "|", KEY_QUOTELEFT: "~"}
	if sh and shifted.has(kc):
		return shifted[kc]
	if kc >= 32 and kc < 127 and not plain.has(kc):   # printable keycodes that are their own character
		return String.chr(kc)
	return plain.get(kc, "")


## Enter opens chat here, BEFORE the GUI sees the key (a focused button would eat it as
## ui_accept); while it is open every key event is chat text (see open_chat()).
func _input(event: InputEvent) -> void:
	if not in_game or is_dedicated or chat_edit == null:
		return
	if not event is InputEventKey:
		return
	if chat_open:
		if (pause_menu and pause_menu.visible) or class_select.visible:
			close_chat()
			return
		_chat_key(event)
		get_viewport().set_input_as_handled()
		return
	if event.pressed and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER) \
			and not (pause_menu and pause_menu.visible) and not class_select.visible:
		open_chat()
		get_viewport().set_input_as_handled()


func _on_chat_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		open_chat()   # clicking the chat line opens it too
		chat_edit.accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if not in_game or is_dedicated:
		return
	if chat_open:
		return   # typing: no key is a hotkey
	if OS.has_environment("VOLAM_KEYLOG") and event is InputEventKey and event.pressed:
		_log("hotkey %s echo=%s (C panel %s)" % [OS.get_keycode_string(event.keycode), event.echo, "open" if char_sheet.visible else "closed"])
	if hideout_ui and hideout_ui.handle_world_input(event):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action("inventory"):
			toggle_inventory()
			get_viewport().set_input_as_handled()
		elif event.is_action("character"):
			_open_exclusive(char_sheet, not char_sheet.visible)
			get_viewport().set_input_as_handled()
		elif event.is_action("talents"):
			_open_exclusive(talent_ui, not talent_ui.visible)
			get_viewport().set_input_as_handled()
		elif event.is_action("party_panel"):
			toggle_party_panel()
			get_viewport().set_input_as_handled()
		elif event.is_action("target_cycle"):
			cycle_target()
			get_viewport().set_input_as_handled()
		elif event.is_action("fps_overlay"):
			fps_label.visible = not fps_label.visible
			get_viewport().set_input_as_handled()
		elif event.is_action("zone_map"):
			toggle_zone_map()
			get_viewport().set_input_as_handled()
		elif event.is_action("atlas"):
			_open_exclusive(atlas_ui, not atlas_ui.visible)
			atlas_ui.set_player(_local_player())
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_H:
			toggle_hideout_ui(true)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			handle_escape()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_dbg_clicks += 1
		select_at_mouse(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		# bonus: right-click a monster = select it and attack
		select_at_mouse(event.position)
		var me := _local_player()
		if me and NetUtil.selected != null:
			me.request_attack()
		get_viewport().set_input_as_handled()


# ================================================================ targeting (client)

func _cursor_zone_pos(me: Node) -> Vector2:
	if _test_cursor != null:
		return _test_cursor
	return me.position + me.get_local_mouse_position()


## Left click: select the monster (or player) under the cursor, or clear. `screen_pos` = the
## click's own position (not the mouse "now"); the hit area is generous (moving monsters: the drawn
## position or where the server has it, whichever is closer).
func select_at_mouse(screen_pos = null) -> void:
	var me := _local_player()
	if me == null or me.zone == null:
		return
	var pt := _cursor_zone_pos(me)
	if screen_pos is Vector2:
		pt = me.get_parent().get_global_transform_with_canvas().affine_inverse() * screen_pos
	var best: Node = null
	var best_d := INF
	for m in me.zone.monsters_root.get_children():
		if not m.alive:
			continue
		var sc := float(m.def.get("scale", 1.0))
		var d: float = minf((m.position + Vector2(0, -10.0 * sc)).distance_to(pt), (m.sync_pos + Vector2(0, -10.0 * sc)).distance_to(pt))
		if d <= 22.0 * sc + 10.0 and d < best_d:
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
		_log("selected target %s (click %s, %d px from it)" % [best.display_name, pt.round(), roundi(best_d)])
	elif bot_mode:
		var near := INF
		for m in me.zone.monsters_root.get_children():
			if m.alive:
				near = minf(near, m.position.distance_to(pt))
		_log("click at %s selected nothing (nearest monster %.0f px)" % [pt.round(), near])
	if multiplayer.has_multiplayer_peer() and not multiplayer.is_server():
		report_selection.rpc_id(1, (best.monster_id if best.has_method("take_damage") else best.peer_id) if best else -1,
			"m" if best and best.has_method("take_damage") else "p", best.display_name if best else "")


## Client -> server, log only: what the player selected (so a cast can be matched to it).
@rpc("any_peer", "reliable")
func report_selection(id: int, kind: String, what: String) -> void:
	if not multiplayer.is_server():
		return
	var p := _player_node(multiplayer.get_remote_sender_id())
	if p == null:
		return
	p._srv_log("%s selected target %s" % [p.display_name, ("%s (%s%d)" % [what.left(40), kind, id]) if id >= 0 else "none (cleared)"])


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
	for pn in [["hideout", hideout_ui], ["vendor", vendor_ui], ["map device / merchant", map_ui], ["atlas", atlas_ui], ["blacksmith", smith_ui],
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


func _show_leaving_overlay() -> void:
	var ov := ColorRect.new()
	ov.color = Color(0.03, 0.04, 0.07, 0.85)
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	var l := Label.new()
	l.text = "Returning to menu..."
	l.add_theme_font_size_override("font_size", 24)
	l.set_anchors_preset(Control.PRESET_CENTER)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(-150, -20)
	l.size = Vector2(300, 40)
	ov.add_child(l)
	get_node("UI").add_child(ov)
	_log("leaving: 'Returning to menu...' shown")


## Solo play has no account, so no "Account created" there.
func _welcome_text(is_new: bool, display: String) -> String:
	if solo_mode:
		return "Welcome to Volam, %s!" % display if is_new else "Welcome back, %s!" % display
	return "Account created. Welcome to Volam!" if is_new else "Welcome back, %s!" % display


## Return to Main Menu / Quit Game: save (host), disconnect cleanly, then reload or quit.
func leave_game(to_menu: bool) -> void:
	if not to_menu:
		shutdown()
		return
	if _shutting_down:
		return
	_shutting_down = true
	_show_leaving_overlay()     # instant feedback: saving + reloading takes a couple of seconds
	await get_tree().process_frame
	await get_tree().process_frame
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


## Big windows are exclusive: opening one closes every other one, except its companions
## (vendor / blacksmith / Map Device open the inventory beside them). The N zone map is one of them.
## Screen rects (HUD coordinates) of the town / hideout NPCs and stations on screen, name labels included.
func npc_screen_rects() -> Array:
	var out: Array = []
	var me := _local_player()
	if me == null or me.zone == null:
		return out
	var vp := get_viewport().get_visible_rect()
	for n in get_tree().get_nodes_in_group("npc_visual"):
		if not (n as Node2D).is_visible_in_tree() or not me.zone.is_ancestor_of(n):
			continue
		var o: Vector2 = (n as Node2D).get_global_transform_with_canvas().origin
		var box = n.get("screen_box")
		var r := Rect2(o + box.position, box.size) if box is Rect2 else Rect2(o + Vector2(-55, -34), Vector2(110, 62))
		if vp.intersects(r):
			out.append(r)
	return out


## HUD vs world: fade the top-left stats panel and the help text while an NPC (and its label) is
## under them; hide the corner minimap while a right-side window (inventory, vendor, smith) is open.
func _hud_declutter() -> void:
	var sp := hud.get_node("StatsPanel") as Control
	sp.reset_size()   # shrink back after a long line
	var pp := hud.get_node_or_null("PartyPanel") as Control
	if pp:
		pp.position = Vector2(sp.position.x, sp.get_global_rect().end.y + 6.0)
	var rects := npc_screen_rects()
	for c in [hud.get_node("StatsPanel"), info_label]:
		var under := false
		var cr: Rect2 = (c as Control).get_global_rect()
		for r in rects:
			if cr.intersects(r):
				under = true
		var base := 0.6 if c == info_label else 1.0
		(c as Control).modulate.a = move_toward((c as Control).modulate.a, base * (0.3 if under else 1.0), 0.15)
	minimap.top_y = maxf(106.0, info_label.get_global_rect().end.y + 6.0)
	fps_label.offset_top = minimap.top_y + 120.0
	var cover := false
	var corner := Rect2(Vector2(get_viewport().get_visible_rect().size.x - 190.0, minimap.top_y), Vector2(180, 115))
	for w in [inventory_ui, vendor_ui, smith_ui, map_ui, hideout_ui]:
		if w.visible and w.get_global_rect().intersects(corner):
			cover = true
	minimap.covered = cover


## NPC / station labels: each goes to the first of its spots (above / below the NPC) that keeps
## clear of the HUD corners (help text, minimap, stats) and of my own name tag.
func _place_npc_labels() -> void:
	var me := _local_player()
	if me == null or me.zone == null:
		return
	var avoid := _npc_label_avoid(me)
	for n in get_tree().get_nodes_in_group("npc_visual"):
		if not n.has_method("label_spots") or not (n as Node2D).is_visible_in_tree() or not me.zone.is_ancestor_of(n):
			continue
		var spots: Array = n.label_spots()
		var pick: Array = []
		for sp in spots:
			if not _rect_hits(npc_label_rect(n, sp[1]), avoid):
				pick = sp
				break
		# nowhere clear (the NPC is under a HUD corner, far from me): hide the label until it is
		n.label_node.visible = not pick.is_empty()
		if not pick.is_empty() and n.label_side != pick[0]:
			n.set_label_spot(pick)


func _npc_label_avoid(me: Node) -> Array:
	var xf: Transform2D = me.get_global_transform_with_canvas()
	var pp := hud.get_node("PartyPanel") as Control
	return [info_label.get_global_rect().grow(6), minimap.get_global_rect().grow(8),
		hud.get_node("StatsPanel").get_global_rect().merge(pp.get_global_rect() if pp.visible else hud.get_node("StatsPanel").get_global_rect()).grow(4),
		Rect2(xf * Vector2(-80, -52), Vector2(160, 18) * xf.get_scale()).grow(10)]   # my name tag, with room


## Screen rect of an NPC's label (at local offset `at`, default where it is now); only the text lines.
func npc_label_rect(n: Node, at = null) -> Rect2:
	var l: Label = n.label_node
	var xf: Transform2D = (n as Node2D).get_global_transform_with_canvas()
	var lines := l.text.count("\n") + 1
	var w := 0.0
	for line in l.text.split("\n"):
		w = maxf(w, l.get_theme_font("font").get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, l.get_theme_font_size("font_size")).x)
	var pos: Vector2 = l.position if at == null else at
	return Rect2(xf * (pos + Vector2((l.size.x - w) / 2.0, 0)), Vector2(w, 15.0 * lines) * xf.get_scale())


static func _rect_hits(r: Rect2, rects: Array) -> bool:
	for a in rects:
		if r.intersects(a):
			return true
	return false


func _big_windows() -> Array:
	return [inventory_ui, char_sheet, talent_ui, atlas_ui, map_ui, hideout_ui, smith_ui, vendor_ui]


func close_windows_except(keep: Array) -> void:
	for w in _big_windows():
		if w not in keep and w.visible:
			w.visible = false
	if minimap and minimap.big and minimap not in keep:
		minimap.toggle_big()
	if inventory_ui not in keep:
		item_tip.hide_tip()
		inventory_ui.apply_orb = ""


## Opens `panel` alone (closing every other big window) or closes it.
func _open_exclusive(panel: Control, on: bool) -> void:
	if on:
		close_windows_except([panel])
	panel.visible = on


## N: the full zone map, exclusive with the other big windows and drawn above the HUD.
func toggle_zone_map() -> void:
	if not minimap.big:
		close_windows_except([minimap])
	minimap.toggle_big()


## How many big windows are open (the N map counts) - for the UI self-test / logs.
func open_windows() -> Array:
	var out: Array = []
	for w in _big_windows():
		if w.visible:
			out.append(w.get_script().resource_path.get_file().get_basename())
	if minimap.big:
		out.append("zone_map")
	return out


func toggle_inventory() -> void:
	if not inventory_ui.visible:
		close_windows_except([inventory_ui, vendor_ui, smith_ui, map_ui])   # its companions stay
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
	close_windows_except([map_ui, inventory_ui])
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
	if not hideout_ui.visible:
		close_windows_except([hideout_ui])
	hideout_ui.visible = not hideout_ui.visible
	if not hideout_ui.visible and hideout_ui.deco_mode:
		hideout_ui.toggle_mode()
	hideout_ui.refresh()


## E next to the Vendor: open/close the vendor panel (with the inventory beside it).
func toggle_vendor_ui() -> void:
	var me := _local_player()
	if me == null:
		return
	if vendor_ui.visible:
		vendor_ui.visible = false
		item_tip.hide_tip()
		return
	close_windows_except([vendor_ui, inventory_ui])
	vendor_ui.set_player(me, vendor)
	if not me.inventory_changed.is_connected(vendor_ui.refresh):
		me.inventory_changed.connect(vendor_ui.refresh)
	vendor_ui.visible = true
	me.request_vendor("stock")
	vendor_ui.refresh()
	if not inventory_ui.visible:
		toggle_inventory()
	_log("vendor panel opened")


## E next to the anvil: open/close the blacksmith (with the inventory beside it).
func toggle_smith() -> void:
	var me := _local_player()
	if me == null:
		return
	if not smith_ui.visible and me.near_blacksmith():
		close_windows_except([smith_ui, inventory_ui])
	smith_ui.visible = not smith_ui.visible and me.near_blacksmith()
	if smith_ui.visible:
		smith_ui.set_player(me)
		if not me.inventory_changed.is_connected(smith_ui.refresh):
			me.inventory_changed.connect(smith_ui.refresh)
		smith_ui.refresh()
		if not inventory_ui.visible:
			toggle_inventory()
	item_tip.hide_tip()


# ================================================================ client benchmark (--bench=SECS)

var _bench_secs := 0.0
var _bench_t := -3.0                # warm-up before sampling
var _bench := {}

## Client: samples frame time and the engine monitors while standing in the zone, then prints one
## "BENCH" line and quits (tools/bench_zones.sh compares zones / versions).
func _bench_tick(delta: float) -> void:
	var me := _local_player()
	if me == null or me.zone == null or (_warp_to != "" and me.zone.zone_id != _warp_to):
		return
	_bench_t += delta
	if _bench_t < 0.0:
		return
	var keys := {"frame_ms": delta * 1000.0, "process_ms": Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		"physics_ms": Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"draw_calls": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects_drawn": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		"phys_active": Performance.get_monitor(Performance.PHYSICS_2D_ACTIVE_OBJECTS),
		"phys_pairs": Performance.get_monitor(Performance.PHYSICS_2D_COLLISION_PAIRS)}
	for k in keys:
		_bench[k] = float(_bench.get(k, 0.0)) + float(keys[k])
	_bench["frames"] = int(_bench.get("frames", 0)) + 1
	_bench["worst_ms"] = maxf(float(_bench.get("worst_ms", 0.0)), delta * 1000.0)
	if _bench_t >= _bench_secs:
		var n := float(_bench["frames"])
		var z: Node = me.zone
		var cells := 0
		var animated := 0   # nodes that animate + redraw every frame: decor visuals (all zones) + monsters
		for zid in zones:
			cells += zones[zid].map.get_used_cells(0).size()
			for c in zones[zid].get_children():
				if c is Node2D and c.has_method("_draw") and c.can_process():
					animated += 1
			for m in zones[zid].monsters_root.get_children():
				if not ("_onscreen" in m) or (m._onscreen != null and m._onscreen.is_on_screen()):
					animated += 1
		print("BENCH zone=%s map=%dx%d fps=%.1f frame_ms=%.2f worst_ms=%.1f process_ms=%.2f physics_ms=%.2f nodes=%d draw_calls=%.0f objects_drawn=%.0f phys_active=%.0f phys_pairs=%.0f monsters_here=%d animated_nodes=%d tiles_all_zones=%d frames=%d" % [
			z.zone_id, z.map.get_used_rect().size.x, z.map.get_used_rect().size.y, 1000.0 * n / maxf(1.0, _bench["frame_ms"]), _bench["frame_ms"] / n, _bench["worst_ms"],
			_bench["process_ms"] / n, _bench["physics_ms"] / n, roundi(_bench["nodes"] / n), _bench["draw_calls"] / n, _bench["objects_drawn"] / n,
			_bench["phys_active"] / n, _bench["phys_pairs"] / n, z.monsters_root.get_child_count(), animated, cells, int(n)])
		_bench_secs = 0.0
		get_tree().quit()


# ================================================================ per-frame

func _process(delta: float) -> void:
	if _hs_wait >= 0.0:
		_hs_wait += delta
		if _hs_wait > handshake.TIMEOUT + 1.0:
			_hs_wait = -1.0
			login_result(false, "The server did not answer the version check (it runs a different build of the game).")
	_elapsed += delta
	if _bench_secs > 0.0:
		_bench_tick(delta)
	if _quit_after > 0.0 and _elapsed >= _quit_after:
		_log("quit-after reached, exiting")
		_quit_after = -1.0
		shutdown()
		return
	if fps_label and fps_label.visible:
		_fps_t -= delta
		if _fps_t <= 0.0:
			_fps_t = 0.25
			var me := _local_player()
			var mons: int = me.zone.monsters_root.get_child_count() if me and me.zone else 0
			fps_label.text = "FPS %d  (%.1f ms)\nmonsters on client: %d\nnodes: %d" % [Engine.get_frames_per_second(), 1000.0 / maxf(Engine.get_frames_per_second(), 1.0), mons,
				Performance.get_monitor(Performance.OBJECT_NODE_COUNT)]
	if _open_zone_map and _local_player() != null:
		_open_zone_map = false
		toggle_zone_map()
	if _screenshot_path != "" and _elapsed > _screenshot_delay and _screenshot_ready():
		var img := get_viewport().get_texture().get_image()
		var err := img.save_png(_screenshot_path)
		_log("screenshot saved to %s (err %d)" % [_screenshot_path, err])
		_screenshot_path = ""
	chat_active = chat_open
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
		banner_label.text = "%s\n%s" % [zi["name"], ("Safe haven" if str(zi["levels"]) in ["", "-"] else "Safe haven  -  Lv " + zi["levels"]) if zi.get("safe", false) else "Monsters Lv " + zi["levels"]]
		_banner_t = 3.5
		_log("Entered zone %s (%s)" % [zone_id, zi["name"]])
		if zi.has("dungeon"):
			var d: Dictionary = zi["dungeon"]
			banner_label.text = "%s\nMonsters Lv %s  -  %s" % [zi["name"], zi["levels"], "map iiq +%d%% iir +%d%%" % [roundi(d.get("iiq", 0.0)), roundi(d.get("iir", 0.0))]]


## Client: entities of zones other than `here` this peer still holds (should always be 0).
func _foreign_count(here: String) -> int:
	var n := 0
	for zid in zones:
		if zid != here:
			for root in [zones[zid].players_root, zones[zid].monsters_root, zones[zid].loot_root]:
				for e in root.get_children():
					if not e.is_queued_for_deletion():
						n += 1
	return n


func _update_hud(delta: float) -> void:
	if is_dedicated:
		return
	var me := _local_player()
	if me and me.zone and me.zone.zone_id != _shown_zone:
		if bot_mode and _shown_zone != "" and not multiplayer.is_server():
			# the very frame our player shows up in the new zone: the old zone's entities must already be gone
			_log("zone switch %s -> %s: foreign_entities=%d" % [_shown_zone, me.zone.zone_id, _foreign_count(me.zone.zone_id)])
		if _shown_zone != "" and me.zone.is_dungeon() and Zones.exists(_shown_zone):
			# stepped through a map portal: my own view jumps to the dungeon, so the beam plays where I land
			MapPortalVisualScript.spawn_beam(me.zone, me.position)
			_log("portal fx: teleport beam on arrival in %s at %s" % [me.zone.zone_id, me.position.round()])
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
	info_label.text = "Players here: %d\nWASD move  Space attack  1-4 skills  Q potion\nClick/Tab target  E pick up  Esc menu / help\nI inventory  C character  T passive  N map  P party\nEnter chat   /invite NAME = party" % here
	_hud_declutter()
	_place_npc_labels()
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
	if bot_watch_patrol and not _watch_sent and _elapsed > 3.0 and me.zone.zone_id == "meadow":
		_watch_sent = true
		_watch_patrol(me)
	if menu_hideout_test:
		_menu_hideout_step(me, get_process_delta_time())
	if _warp_pending and _elapsed >= _warp_delay:
		_warp_pending = false
		request_warp.rpc_id(1, _warp_to, _warp_cell)
	var zi := Zones.info(me.zone.zone_id)
	zone_label.text = zi["name"] if str(zi["levels"]) in ["", "-"] else "%s  (Lv %s)" % [zi["name"], zi["levels"]]
	if zi.has("dungeon"):
		var dd: Dictionary = zi["dungeon"]
		var aq: float = Dungeons.atlas_iiq(me.atlas)
		zone_label.text += "\nMap: +%d%% quantity (+%d%% atlas)  +%d%% rarity%s" % [roundi(dd.get("iiq", 0.0)), roundi(aq), roundi(dd.get("iir", 0.0)),
			("  -  %d portals left" % int(me.run_info["portals"])) if not me.run_info.is_empty() else ""]
	if ui_selftest and _elapsed > 4.0:
		ui_selftest = false
		_run_ui_selftest()
	if aim_selftest and _elapsed > 5.0 and _aim_test_monster(me) != null:
		aim_selftest = false
		_run_aim_selftest()
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
	if _open_vendor and _elapsed > 7.0 and me.near_vendor():
		_open_vendor = false
		toggle_vendor_ui()
		for inst in me.bag:
			if not Dungeons.is_ticket(inst) and not inst.get("bound", false):
				vendor_ui.select_uid(int(inst["uid"]))
				break
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
	var in_party := false
	for m in party_members:
		in_party = in_party or str(m["name"]) == str(sel.display_name)
	_tf_invite.visible = not is_monster and sel != me and not in_party
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


## Test bot (outside dungeon runs): --bot-party=invite:A,B invites every listed name until all
## have joined. Returns true while it is still forming the party (the bot waits meanwhile).
func _bot_form_party(delta: float) -> bool:
	var want: Array = Array(bot_party.substr(7).split(",", false))
	var have: Array = []
	for m in party_members:
		have.append(str(m["name"]))
	var missing: Array = want.filter(func(n): return not have.has(n))
	if missing.is_empty():
		return false
	if _elapsed > 40.0:   # give up (someone never came online): play on with whoever joined
		return false
	bot_dir = Vector2.ZERO
	_bp_t -= delta
	if _bp_t <= 0.0:
		_bp_t = 4.0
		for n in missing:
			_log("party bot: inviting %s" % n)
			send_chat("/invite " + str(n))
	return true


## Test bot (--bot-follow=NAME): stays within ~60 px of that player, never attacks.
func _bot_follow(me: Node, zone: Node, delta: float) -> void:
	bot_dir = Vector2.ZERO
	for p in zone.players_root.get_children():
		if str(p.display_name) == bot_follow and p != me:
			if me.position.distance_to(p.position) > 60.0:
				bot_dir = _bot_steer(zone, me.position, p.position, delta)
			_bf_log_t -= delta
			if _bf_log_t <= 0.0:
				_bf_log_t = 5.0
				_log("follow bot: %.0f px from %s, xp %d/%d lv %d" % [me.position.distance_to(p.position), bot_follow, me.xp, me.xp_next, me.level])
			return


## Test bot for dungeon runs (--bot-dungeon=full|die|enter|intrude). Returns true when it drove this frame.
var _bd_layout_logged := false
var _bd_settle := 0.0
var _bd_merch_t := 0.0
var _bd_ticket_tries := 0
var _bd_unused_n := -1   # unused-portal bot: tickets in the bag while its portal was open


func _bot_dungeon(me: Node, zone: Node, delta: float) -> bool:
	if not (_bd_step == 3 and zone.zone_id == "meadow"):
		_bd_walk_t = 0.0
	_bd_t -= delta
	var town: bool = zone.zone_id == "meadow"
	if _elapsed < 3.0:
		bot_dir = Vector2.ZERO
		return true
	if town and bot_atlas and (_ba == 0 or _bd_step == 9) and _ba != 99:
		return _bot_atlas(me, zone, delta)
	if town and bot_party.begins_with("invite:") and party_members.size() < 2:   # party leader: form the party first
		bot_dir = Vector2.ZERO
		_bp_t -= delta
		if _bp_t <= 0.0:
			_bp_t = 4.0
			_log("party bot: inviting %s" % bot_party.substr(7))
			if not _bp_probed:
				_bp_probed = true
				send_chat("/invite Nobody")    # invalid: not online
				send_chat("/accept")           # invalid: no pending invite
			send_chat("/invite " + bot_party.substr(7))
		return true
	if town:
		if _bd_step == 0 and bot_dungeon == "party":   # party member: no ticket, wait for the leader's portal
			_bd_step = 3
			_log("dungeon bot: party member, waiting for %s's portal" % party_leader)
			return true
		if _bd_step in [4, 5]:   # back from a dungeon (left, died or kicked out)
			_bd_step = 3
			_bd_t = 3.0
			_log("dungeon bot: back in town (entries %d), run %s, atlas %s" % [_bd_entries, me.run_info, me.atlas.get("done", {})])
		if _bd_step == 0 and bot_guardian != "":   # Guardian test: a debug ticket for that node, no merchant
			bot_dir = Vector2.ZERO
			_log("dungeon bot: asking for a debug %s ticket, hideout themes %s, owned decorations %s" % [bot_guardian, me.hideout.get("unlocked", []), me.hideout.get("owned", {})])
			me.request_dungeon("debug_kit", {"node": bot_guardian})
			bot_dungeon_theme = Atlas.node(bot_guardian).get("theme", bot_dungeon_theme)
			bot_dungeon_tier = int(Atlas.node(bot_guardian).get("tier", bot_dungeon_tier))
			_bd_step = 1
			_bd_t = 1.5
			return true
		if _bd_step == 0:     # walk to the merchant, take the free ticket, buy one
			_bd_merch_t += delta
			if not me.near_merchant() or (me.position.distance_to(zone.merchant_pos() + Vector2(0, 24)) > 16.0 and _bd_merch_t < 4.0):
				bot_dir = _bot_steer(zone, me.position, zone.merchant_pos() + Vector2(0, 24), delta)
				_bd_settle = 0.6
				return true
			bot_dir = Vector2.ZERO
			_bd_settle -= delta
			if _bd_settle > 0.0:   # stand still until the server has us at the merchant too (slow machines lag)
				return true
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
			if best.is_empty() and _bd_ticket_tries < 3 and bot_guardian == "":
				_bd_ticket_tries += 1
				_log("dungeon bot: no ticket yet (try %d), asking the merchant again" % _bd_ticket_tries)
				_bd_step = 0
				_bd_settle = 1.0
				return true
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
			if bot_dungeon == "unused":   # opened, never entered: wait away from the portal until it closes
				if not me.near_merchant():
					bot_dir = _bot_steer(zone, me.position, zone.merchant_pos() + Vector2(0, 24), delta)
					return true
				bot_dir = Vector2.ZERO
				_bd_walk_t += delta
				if _bd_walk_t > 3.0:
					_bd_walk_t = 0.0
					var nt: int = me.bag.filter(func(i): return Dungeons.is_ticket(i)).size()
					var mine: Array = zone.map_portals.filter(func(mp): return str(mp["owner"]) == me.display_name)
					_log("unused bot: my portals open %d, tickets in bag %d %s" % [mine.size(), nt, _ticket_list(me)])
					if not mine.is_empty():
						_bd_unused_n = nt
					elif _bd_unused_n >= 0:
						_log("unused bot: portal gone, tickets in bag %d -> %d (refund %s)" % [_bd_unused_n, nt, "seen" if nt == _bd_unused_n + 1 else "MISSING"])
						_bd_unused_n = -1
				return true
			if bot_dungeon in ["enter", "safe", "corner"] and _bd_entries >= 1 or bot_dungeon == "die" and _bd_entries >= Dungeons.PORTALS or bot_dungeon in ["full", "party", "first"] and _bd_done_t >= 0.0:
				if _bd_step != 9:
					_log("dungeon bot: finished - back in town, atlas %s, run %s, bag tickets %s" % [me.atlas.get("done", {}), me.run_info, _ticket_list(me)])
				_bd_step = 9
				return true
			for mp_ in zone.map_portals:
				var mine: bool = str(mp_["owner"]) == me.display_name or (bot_dungeon == "party" and party_leader != "" and str(mp_["owner"]) == party_leader)
				if mine != (bot_dungeon == "intrude"):
					var goal: Vector2 = mp_["pos"]
					if bot_dungeon == "corner":   # stand on the drawn gate's lower-right corner (outside the old 24 px radius)
						goal += MapPortalVisualScript.SIZE / 2.0 - Vector2(5, 5)
						if not _bd_layout_logged:
							for v in zone.map_portal_root.get_children():
								if v.has_method("layout_info") and v.owner_name == me.display_name:
									_bd_layout_logged = true
									var li: Dictionary = v.layout_info()
									var gate: Rect2 = li["gate"]
									var trig: Rect2 = MapPortalVisualScript.trigger_rect(mp_["pos"])
									_log("portal layout: gate %s, entry area %s (same %s), label bottom %.0f <= gate top %.0f: %s, z %d, art %s, aiming at %s (%.0f px from the centre)" % [
										gate, trig, gate == trig, li["label_bottom"], gate.position.y, li["label_bottom"] <= gate.position.y, li["z"], li["art"], goal, goal.distance_to(mp_["pos"])])
					if bot_dungeon == "corner" and zone.map.local_to_map(me.position) == zone.map.local_to_map(goal):
						bot_dir = (goal - me.position).limit_length(1.0) if me.position.distance_to(goal) > 2.0 else Vector2.ZERO
					else:
						bot_dir = _bot_steer(zone, me.position, goal, delta)
					_bd_walk_t += delta if me.position.distance_to(mp_["pos"]) > 24.0 else 0.0   # (the intruder waits on the portal on purpose)
					if _bd_walk_t > 15.0:   # diagnostics: a walk to a portal next to the arrival point takes ~3s
						_bd_walk_t = 5.0
						_log("dungeon bot: STILL walking to portal %s at %s (cell %s, walkable %s) from %s (cell %s), dir %s, path %s" % [
							mp_["owner"], mp_["pos"], zone.map.local_to_map(mp_["pos"]), zone.map.is_walkable(zone.map.local_to_map(mp_["pos"])),
							me.position, zone.map.local_to_map(me.position), bot_dir, _bot_path.slice(0, 6)])
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
		_dungeon_complete_seen = false
		_log("dungeon bot: inside %s (entry %d), run %s" % [zone.zone_id, _bd_entries, me.run_info])
	if bot_dungeon == "die":
		bot_dir = Vector2.ZERO      # stand still and let the monsters win
		var hard: Node2D = null   # T1 warm-up pairs barely scratch a Lv1 (1 dmg/hit): go die at a normal pack
		var hard_d := 3000.0
		for mm in zone.monsters_root.get_children():
			if mm.alive and not bool(mm.get("warmup")) and mm.position.distance_to(me.position) < hard_d:
				hard_d = mm.position.distance_to(me.position)
				hard = mm
		if me.dead or me.hp <= 0:
			_bd_step = 5
		elif hard and hard_d > 70.0:
			bot_dir = _bot_steer(zone, me.position, hard.position, delta)
		elif _bd_t < -1.0:   # nothing around yet: walk at the nearest pack
			var n: Node2D = _nearest(zone.monsters_root, me.position, 3000.0)
			if n:
				bot_dir = _bot_steer(zone, me.position, n.position, delta)
			elif _bd_t < -4.0:   # no pack synced to us yet (interest radius): head into the map until one shows up
				var mid: Vector2 = zone.map.nearest_reachable_pos(zone.map.cell_pos(Vector2i(zone.map.w / 2, zone.map.h / 2)), Zones.info(zone.zone_id)["respawn"])
				bot_dir = _bot_steer(zone, me.position, mid, delta)
		return true
	if bot_dungeon == "safe":   # entrance safe area test: idle in it, pull a monster, retreat into it
		var sc: Vector2 = zone.safe_center()
		if _bd_t > -6.0:
			bot_dir = Vector2.ZERO
			return true
		if _bd_safe == 0:
			_bd_safe = 1
			_log("safe bot: idled 6s in the safe area, hp %d/%d, in safe area %s" % [me.hp, me.max_hp, zone.in_safe_area(me.position)])
		if _bd_safe == 1:   # walk at the nearest monster (no attacks) until one hits us
			var n: Node2D = _nearest(zone.monsters_root, me.position, 3000.0)
			if me.hp < me.max_hp or _bd_t < -40.0:
				_bd_safe = 2
				_bd_safe_t = _bd_t
				_log("safe bot: hit (hp %d/%d) - retreating into the safe area" % [me.hp, me.max_hp])
			elif n:
				bot_dir = _bot_steer(zone, me.position, n.position, delta)
			return true
		if _bd_safe == 2:
			if me.position.distance_to(sc) > 40.0:
				bot_dir = _bot_steer(zone, me.position, sc, delta)
			else:
				bot_dir = Vector2.ZERO
				_bd_safe = 3
				_bd_safe_hp = me.hp
				_bd_safe_t = _bd_t
				_log("safe bot: back in the safe area, hp %d/%d" % [me.hp, me.max_hp])
			return true
		bot_dir = Vector2.ZERO
		if _bd_safe == 3 and _bd_safe_t - _bd_t > 8.0:
			_bd_safe = 4
			_log("safe bot: 8s in the safe area after the pull, hp %d -> %d/%d (no damage: %s), nearest monster %.0f px" % [_bd_safe_hp, me.hp, me.max_hp, me.hp >= _bd_safe_hp,
				me.position.distance_to(_nearest(zone.monsters_root, me.position, 5000.0).position) if _nearest(zone.monsters_root, me.position, 5000.0) else -1.0])
		return true
	if bot_dungeon in ["enter", "corner"]:
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
	if (me.run_info.get("completed", false) or _dungeon_complete_seen) and _bd_done_t < 0.0:
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
			1:   # leave through the door, pressing E as soon as it is in reach (before stepping on it)
				if zone.is_hideout() and me.near_hideout_door():
					me._send("door")
					_bh_t = 1.0
				elif zone.is_hideout():
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
			me.request_hideout("station", {"station": "vendor", "x": 31, "y": 26})   # rejected: door
			me.request_hideout("station", {"station": "vendor", "x": 21, "y": 26})
			me.request_hideout("theme", {"id": "fire"})
			me.request_hideout("theme", {"id": "water"})   # rejected: locked
			me.request_hideout("theme", {"id": "nope"})    # rejected
			_bh_step = 6
			_bh_t = 2.0
		6:
			_bh_log(me, "removed one, moved the vendor, theme switched")
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


## Test bot for the NPC vendor (--bot-vendor=1|2): a timed script of vendor requests
## (the server validates / logs everything). "2" = after a server restart: just look at the stock.
func _bot_vendor(me: Node, zone: Node, delta: float) -> void:
	if zone.zone_id != "meadow" or _elapsed < 3.0:
		return
	if not _bv_done.has("far"):
		_bv_done["far"] = true
		for inst in me.bag:
			if not inst.get("bound", false):
				me.request_vendor("sell", {"uid": int(inst["uid"])})     # invalid: not at the vendor
				break
	if not me.near_vendor():
		bot_dir = _bot_steer(zone, me.position, zone.vendor_pos() + Vector2(0, 30), delta)
		return
	bot_dir = Vector2.ZERO
	if not _bv_done.has("t0"):
		_bv_done["t0"] = _elapsed
		_log("vendor bot (%s): at the vendor, gold %d, bag %d/%d" % [bot_vendor, me.gold, me.bag_used(), Items.BAG_SIZE])
		toggle_vendor_ui()
	var t: float = _elapsed - float(_bv_done["t0"])
	var first_gear := func() -> Dictionary:
		for e in vendor.stock:
			if e.has("item"):
				return e
		return {}
	var steps: Array = []
	if bot_vendor == "1":
		steps = [
			[1.0, func():
				if bot_vendor_role != "probe":
					return
				var e: Dictionary = {}
				for x in vendor.stock:
					if x.has("item") and int(x["qty"]) > 0 and int(x["price"]) > me.gold:
						e = x
				if e.is_empty():
					for x in vendor.stock:
						if x.has("item") and int(x["qty"]) > 0:
							e = x
				vendor_ui._buy(int(e.get("id", -1)))],   # clicked in the panel - pauper: "Not enough gold" + server rejects; full bag: bag full
			[1.5, func(): me.request_vendor("buy", {"id": 1, "n": 3})],           # 3 health potions
			[2.0, func():
				var e: Dictionary = first_gear.call()
				_bv_done["gear"] = int(e.get("id", -1))
				_log("vendor bot: buying stock entry #%d %s" % [int(e.get("id", -1)), Vendor.entry_summary(e) if not e.is_empty() else "?"])
				me.request_vendor("buy", {"id": int(e.get("id", -1))})],
			[3.0, func(): me.request_vendor("buy", {"id": int(_bv_done.get("gear", -1))})],   # invalid: sold out
			[3.5, func(): me.request_vendor("buy", {"id": 999})],                              # invalid: not in stock
			[4.0, func():
				if bot_vendor_role == "probe":
					return
				_bv_done["ground"] = _ground_items_near(me, zone)
				for inst in me.bag:
					if not inst.get("bound", false) and not Dungeons.is_ticket(inst):
						me.request_vendor("sell", {"uid": int(inst["uid"])})
						break],
			[4.5, func(): me.request_vendor("sell", {"stack": "slime_gel"} if me.inventory.has("slime_gel") else {"uid": -5})],
			[5.0, func():
				if bot_vendor_role != "probe":
					_log("vendor bot: ground items near me before/after selling: %d -> %d" % [int(_bv_done.get("ground", -1)), _ground_items_near(me, zone)])
					me.request_vendor("sell", {"stack": "health_potion"})],   # consumables sell for a little
			[6.5, func(): _log("vendor bot: done, gold %d, potions %d" % [me.gold, int(me.inventory.get("health_potion", 0))])],
		]
	elif bot_vendor == "ui":   # the real panel path: a click only selects, Sell sells, magic+ asks first, stacks take a quantity
		var slot_of := func(pred: Callable) -> Control:
			for sl in inventory_ui._bag_slots:
				if pred.call(sl):
					return sl
			return null
		var click := func(sl: Control) -> void:
			if sl:
				inventory_ui._on_click(sl, MOUSE_BUTTON_LEFT, false, false)
		steps = [
			[1.0, func():
				var sl: Control = slot_of.call(func(x): return not x.inst.is_empty() and str(x.inst["rarity"]) in ["magic", "rare"] and not Dungeons.is_ticket(x.inst))
				_bv_done["magic"] = int(sl.inst["uid"]) if sl else -1
				_log("vendor ui bot: clicking %s in the bag (bag %d)" % [Gear.summary(sl.inst) if sl else "?", me.bag_used()])
				click.call(sl)
				click.call(sl)            # double-click: still only selected
				vendor_ui._sell()],       # a Sell press in the same instant is ignored
			[1.8, func(): _log("vendor ui bot: after the clicks the item is %s" % ("still in the bag" if _bag_uid(me, int(_bv_done["magic"])).size() > 0 else "GONE"))],
			[2.0, func(): vendor_ui._sell()],          # asks for confirmation
			[2.4, func(): vendor_ui.cancel_sell()],
			[3.0, func():
				_log("vendor ui bot: after cancel the item is %s" % ("still in the bag" if _bag_uid(me, int(_bv_done["magic"])).size() > 0 else "GONE"))
				vendor_ui._sell()],
			[3.4, func(): vendor_ui.confirm_sell()],
			[4.2, func():
				_log("vendor ui bot: after confirming the item is %s" % ("still in the bag" if _bag_uid(me, int(_bv_done["magic"])).size() > 0 else "sold"))
				var sl: Control = slot_of.call(func(x): return x.stack_id == "health_potion")
				_bv_done["pots"] = int(me.inventory.get("health_potion", 0))
				click.call(sl)
				vendor_ui.set_qty(1)],
			[4.8, func(): vendor_ui._sell()],
			[5.6, func(): _log("vendor ui bot: health potions %d -> %d (sold 1)" % [int(_bv_done["pots"]), int(me.inventory.get("health_potion", 0))])],
		]
	else:
		steps = [[2.0, func(): _log("vendor bot: stock after restart seen (%d entries)" % vendor.stock.size())]]
	for i in steps.size():
		if t >= float(steps[i][0]) and not _bv_done.has(i):
			_bv_done[i] = true
			steps[i][1].call()


func _aim_test_monster(me: Node) -> Node:
	var best: Node = null
	for m in me.zone.monsters_root.get_children():
		var d: float = m.position.distance_to(me.position)
		if m.alive and d <= 260.0 and me.zone.map.has_los(me.position + Vector2(0, -6), m.position + Vector2(0, -6)) \
				and (best == null or d < best.position.distance_to(me.position)):
			best = m
	return best


var _dbg_clicks := 0


func _controls_at(n: Node, at: Vector2, out: Array) -> void:
	if n is CanvasItem and not (n as CanvasItem).visible:
		return
	if n is Control and (n as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE and (n as Control).get_global_rect().has_point(at):
		out.append("%s(%s)" % [n.get_path(), n.get_class()])
	for c in n.get_children():
		_controls_at(c, at, out)


## A real left click (press + release) at a screen position, through the engine's input path.
func _feed_click(at: Vector2) -> void:
	for pressed in [true, false]:
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		mb.pressed = pressed
		mb.position = at
		mb.global_position = at
		Input.parse_input_event(mb)
		Input.flush_buffered_events()
		if DisplayServer.get_name() == "headless":
			get_viewport().push_input(mb, true)   # `at` is in viewport (canvas) coordinates, not window pixels
		await get_tree().process_frame


func _first_focusable(n: Node) -> Control:
	for c in n.get_children():
		if c is Control and c.visible and c.focus_mode != Control.FOCUS_NONE:
			return c
		var f := _first_focusable(c)
		if f:
			return f
	return null


## Presses the skill key through Input.parse_input_event like a player (not the bot path).
func _press_skill_key(keycode: int) -> void:
	bot_mode = false
	_os_feed(_os_key(keycode, keycode, true))
	await get_tree().process_frame
	await get_tree().process_frame
	_os_feed(_os_key(keycode, keycode, false))
	await get_tree().process_frame
	bot_mode = true


## --aim-selftest: (1) a target is selected and the mouse is on the other side: the skill goes
## to the target; (2) no target, the mouse rests at A and moves to B just before the key: it goes to B.
func _run_aim_selftest() -> void:
	var me := _local_player()
	bot_idle = true   # the bot walked up to monsters; stand still for the test
	bot_dir = Vector2.ZERO
	var m := _aim_test_monster(me)
	# a real left click (Input.parse_input_event + the window path) a few px off the monster's drawn
	# body while it may be moving: must select it, the server logs the selection
	NetUtil.selected = null
	var click_at: Vector2 = m.get_global_transform_with_canvas() * Vector2(7, -4)
	await _feed_click(click_at)
	# PASS: the clicked monster, or another one standing right there (slimes overlap) that the click is nearer to
	var click_ok: bool = NetUtil.is_selected(m) or (NetUtil.selected != null and is_instance_valid(NetUtil.selected) \
		and NetUtil.selected.has_method("take_damage") and NetUtil.selected.position.distance_to(m.position) < 40.0)
	_log("AIM SELFTEST click: %s (clicked %s px on screen next to %s)" % ["PASS selected " + NetUtil.selected.display_name if click_ok else "FAIL selected %s" % (NetUtil.selected.display_name if NetUtil.selected else "nothing"), click_at.round(), m.display_name])
	if not NetUtil.is_selected(m):
		var under: Array = []
		_controls_at(get_tree().root, click_at, under)
		_log("AIM SELFTEST click diagnostics: unhandled clicks seen %d, controls under the click that take the mouse: [%s]" % [_dbg_clicks, ", ".join(under)])
		NetUtil.selected = m   # (keep testing the aim part)
	_test_cursor = (me.position + (me.position - m.position).normalized() * 150.0).round()
	_log("AIM SELFTEST target: selected %s at %s, cursor on the other side at %s" % [m.display_name, m.position.round(), _test_cursor])
	await _press_skill_key(KEY_1)
	await get_tree().create_timer(3.6).timeout
	NetUtil.selected = null
	var a: Vector2 = (me.position + Vector2(-130, 40)).round()
	_test_cursor = a
	for i in 15:
		await get_tree().process_frame
	var b: Vector2 = (me.position + Vector2(90, -70)).round()
	_test_cursor = b
	_log("AIM SELFTEST cursor: no target, cursor rested at %s, moved to %s at the key press" % [a, b])
	await _press_skill_key(KEY_1)
	_test_cursor = null
	_log("AIM SELFTEST done")
	await _press_skill_key(KEY_P)   # P toggles the party panel (also without a party)
	_log("P KEY TEST after 1st P: party panel visible %s, text '%s'" % [party_label.visible, party_label.text.replace("\n", " | ")])
	await _press_skill_key(KEY_P)
	_log("P KEY TEST after 2nd P: party panel visible %s" % party_label.visible)


## --ui-selftest: the window-management fixes from playtesting, checked on a real client.
func _run_ui_selftest() -> void:
	var fails: Array = []
	# 1. big windows are exclusive (the N map too): I/N alternating used to leave both open
	close_windows_except([])
	for i in 40:
		if i % 2 == 0:
			toggle_inventory()
		else:
			toggle_zone_map()
		await get_tree().process_frame
		var open := open_windows()
		if open.size() > 1:
			fails.append("I/N #%d left %s open" % [i, open])
			break
	for w in [char_sheet, talent_ui, atlas_ui]:
		toggle_inventory() if not inventory_ui.visible else null
		toggle_zone_map() if not minimap.big else null
		_open_exclusive(w, true)
		await get_tree().process_frame
		if open_windows().size() != 1:
			fails.append("opening %s left %s open" % [w.get_script().resource_path.get_file(), open_windows()])
	_log("UI SELFTEST exclusive windows (I/N x40, C/T/atlas): %s" % ("PASS" if fails.is_empty() else "FAIL %s" % [fails]))
	# 2. the N map draws above chat, skill bar, help text and the other HUD
	close_windows_except([])
	toggle_zone_map()
	await get_tree().process_frame
	var layer_ok: bool = minimap.big and minimap.z_index > 0
	for n in [hud.get_node("ChatPanel"), skill_bar, info_label, hud.get_node("StatsPanel")]:
		layer_ok = layer_ok and minimap.get_index() > n.get_index() and minimap.z_index >= n.z_index
	_log("UI SELFTEST N map above the HUD: %s" % ("PASS" if layer_ok else "FAIL (index %d z %d)" % [minimap.get_index(), minimap.z_index]))
	toggle_zone_map()
	# 3. the tutorial box never covers the window its step asks for (step 4 = inventory)
	tutorial_ui.begin()
	tutorial_ui.step = 3
	tutorial_ui._enter_step()
	if not inventory_ui.visible:
		toggle_inventory()
	for f in 3:
		await get_tree().process_frame
	var covered: bool = tutorial_ui.covers_a_window()
	_log("UI SELFTEST tutorial box clear of the inventory: %s (box %s, inventory %s)" % ["FAIL" if covered else "PASS", tutorial_ui.get_global_rect(), inventory_ui.get_global_rect()])
	close_windows_except([])
	# 3b. the tutorial box keeps clear of the chat panel, and the C panel is never drawn under it
	for i in 6:
		chat_log.append_text("A long chat line that runs all the way to the right end of the chat panel %d\n" % i)
	for f in 3:
		await get_tree().process_frame
	var chat_r: Rect2 = hud.get_node("ChatPanel").get_global_rect()
	_log("UI SELFTEST tutorial box clear of the chat panel: %s (box %s, chat %s)" % ["FAIL" if tutorial_ui.get_global_rect().intersects(chat_r) else "PASS", tutorial_ui.get_global_rect(), chat_r])
	_open_exclusive(char_sheet, true)
	for f in 4:
		await get_tree().process_frame
	var c_r: Rect2 = char_sheet.get_global_rect()
	var c_ok: bool = not tutorial_ui.get_global_rect().intersects(c_r) or char_sheet.get_index() > tutorial_ui.get_index()
	_log("UI SELFTEST C panel not covered by the tutorial box: %s (box %s, C panel %s, C above the box %s)" % ["PASS" if c_ok else "FAIL", tutorial_ui.get_global_rect(), c_r, char_sheet.get_index() > tutorial_ui.get_index()])
	# 3b2. a single left click inside the open C panel (text, empty space) keeps it open
	_open_exclusive(char_sheet, true)
	for f in 2:
		await get_tree().process_frame
	var cr: Rect2 = char_sheet.get_global_rect()
	var click_ok := true
	for at in [cr.get_center(), cr.position + Vector2(40, 60), cr.position + cr.size * Vector2(0.8, 0.85)]:
		await _feed_click(at)
		click_ok = click_ok and char_sheet.visible
	_log("UI SELFTEST a click inside the C panel keeps it open: %s" % ("PASS" if click_ok else "FAIL (closed)"))
	# 3c. C and Esc close the open C panel (real key events), also after clicking inside it
	var focusable := _first_focusable(char_sheet)
	if focusable:
		focusable.grab_focus()
	bot_mode = false
	_os_feed(_os_key(KEY_C, 0x63, true))
	_os_feed(_os_key(KEY_C, 0x63, false))
	await get_tree().process_frame
	var c_closed := not char_sheet.visible
	_open_exclusive(char_sheet, true)
	await get_tree().process_frame
	if focusable:
		focusable.grab_focus()
	_os_feed(_os_key(KEY_ESCAPE, 0, true))
	_os_feed(_os_key(KEY_ESCAPE, 0, false))
	await get_tree().process_frame
	var esc_closed := not char_sheet.visible and not pause_menu.visible
	bot_mode = true
	_log("UI SELFTEST C closes the C panel: %s, Esc closes it: %s (focus was on %s)" % ["PASS" if c_closed else "FAIL", "PASS" if esc_closed else "FAIL", focusable.get_class() if focusable else "nothing focusable"])
	if pause_menu.visible:
		pause_menu.close_menu()
	tutorial_ui.visible = false
	close_windows_except([])
	# 4. Enter then fast typing: every key goes into chat, none acts as a hotkey (I, N ...)
	var typed := "/invite Bravo"
	_inject_key(KEY_ENTER, 0)
	for ch in typed:
		var kc: int = OS.find_keycode_from_string(ch.to_upper()) if ch != " " and ch != "/" else (KEY_SPACE if ch == " " else KEY_SLASH)
		_inject_key(kc, ch.unicode_at(0))
	await get_tree().process_frame
	await get_tree().process_frame
	var chat_ok: bool = chat_edit.text == typed and open_windows().is_empty()
	_log("UI SELFTEST fast typing after Enter goes to chat: %s (chat '%s', open %s)" % ["PASS" if chat_ok else "FAIL", chat_edit.text, open_windows()])
	_inject_key(KEY_ESCAPE, 0)
	await get_tree().process_frame
	# 4b. the REAL keyboard path: OS events go through Input.parse_input_event (action state
	#     updated first, then the viewport), one event per frame like a typist, and a burst with
	#     Enter still held while the next keys arrive. Nothing may walk, open, or be lost.
	for mode in ["per-frame", "burst", "x11-merged", "keycode-only", "no-release"]:
		for t in ["/accept wasd", "/invite Bravo"]:
			_rt_mode = mode
			var res: Dictionary = await _real_typing(t, mode in ["burst", "keycode-only", "no-release"], mode == "x11-merged")
			var ok: bool = res["text"] == t and res["moved"] < 0.5 and not res["sent_move"] and res["open"].is_empty()
			_log("UI SELFTEST real keys after Enter (%s) '%s': %s (chat '%s', player moved %.1f px, move input sent %s, open %s)" % [mode, t,
				"PASS" if ok else "FAIL", res["text"], res["moved"], res["sent_move"], res["open"]])
	# 6. HUD/world declutter: the tutorial box keeps clear of NPC labels, help text ends above the
	#    minimap, resistance lines never wrap (inventory + C panel)
	tutorial_ui.begin()
	tutorial_ui.step = 0
	tutorial_ui._enter_step()
	for f in 4:
		await get_tree().process_frame
	var npc_hit := []
	for r in npc_screen_rects():
		if tutorial_ui.get_global_rect().intersects(r):
			npc_hit.append(r)
	var fewest := 999
	var sb: Array = tutorial_ui.spots_and_busy()
	for c in sb[0]:
		var blocked := false
		for bb in sb[1]:
			blocked = blocked or Rect2(c, tutorial_ui.size).intersects(bb)
		if blocked:
			continue   # spots over the chat / HUD / windows are not allowed
		var k := 0
		for r in npc_screen_rects():
			if Rect2(c, tutorial_ui.size).intersects(r):
				k += 1
		fewest = mini(fewest, k)
	if fewest == 999:
		fewest = npc_hit.size()   # no free spot at all: the fallback is judged by the HUD checks
	var hud_hit := []
	for hn in ["StatsPanel", "ChatPanel"]:
		if tutorial_ui.get_global_rect().intersects(hud.get_node(hn).get_global_rect()):
			hud_hit.append(hn)
	if tutorial_ui.get_global_rect().intersects(info_label.get_global_rect()):
		hud_hit.append("help text")
	if tutorial_ui.get_global_rect().intersects(skill_bar.get_global_rect()):
		hud_hit.append("skill bar")
	_log("UI SELFTEST tutorial box clear of the HUD (stats, chat, help text, skill bar): %s (covers [%s])" % ["PASS" if hud_hit.is_empty() else "FAIL", ", ".join(hud_hit)])
	_log("UI SELFTEST tutorial box clear of NPC labels: %s (box %s, %d NPC labels on screen, %d covered, fewest possible %d; %s)" % [
		"PASS" if not npc_screen_rects().is_empty() and npc_hit.size() == fewest else "FAIL",
		tutorial_ui.get_global_rect(), npc_screen_rects().size(), npc_hit.size(), fewest, tutorial_ui.place_info])
	tutorial_ui.visible = false
	var help_bottom: float = info_label.get_global_rect().end.y
	_log("UI SELFTEST help text ends above the minimap: %s (%d lines, bottom %.0f, minimap top %.0f)" % ["PASS" if help_bottom <= minimap.get_global_rect().position.y else "FAIL",
		info_label.get_line_count(), help_bottom, minimap.get_global_rect().position.y])
	toggle_inventory()
	await get_tree().process_frame
	await get_tree().process_frame
	var inv_lines: int = inventory_ui._stats_label.get_line_count()
	var inv_w: float = inventory_ui._stats_label.get_combined_minimum_size().x
	var inv_col: float = inventory_ui._left.size.x
	await get_tree().process_frame
	var mm_hidden: bool = not minimap.visible
	var _mm_dbg := "inv %s vis %s, minimap %s big %s" % [inventory_ui.get_global_rect(), inventory_ui.visible, minimap.get_global_rect(), minimap.big]
	toggle_inventory()
	_open_exclusive(char_sheet, not char_sheet.visible)
	await get_tree().process_frame
	await get_tree().process_frame
	var sheet_ok: bool = char_sheet.get_global_rect().end.y <= get_viewport().get_visible_rect().size.y
	var res_wrapped := false
	for ln in char_sheet._stats.text.split("\n"):
		if ln.begins_with("Metal") and ln.count("%") != 3 or ln.begins_with("Fire") and ln.count("%") != 2:
			res_wrapped = true
	_open_exclusive(char_sheet, not char_sheet.visible)
	_log("UI SELFTEST resistance lines don't wrap: %s (inventory stats %d lines, expected 5, width %.0f of column %.0f)" % ["PASS" if inv_lines == 5 and not res_wrapped and inv_w <= inv_col else "FAIL", inv_lines, inv_w, inv_col])
	_log("UI SELFTEST minimap hidden under the inventory: %s (%s)" % ["PASS" if mm_hidden else "FAIL", _mm_dbg])
	_log("UI SELFTEST C panel fits the window: %s (bottom %.0f of %.0f)" % ["PASS" if sheet_ok else "FAIL", char_sheet.get_global_rect().end.y, get_viewport().get_visible_rect().size.y])
	# 5. mana: casting all four skills back to back runs out of mana (Lv10 Earth: 57 mp < 12+20+taunt+35)
	var me := _local_player()
	for slot in 4:
		me.request_skill(slot)
		await get_tree().create_timer(0.15).timeout
	# 7. NPC labels: standing right under the Vendor, its label keeps off my name tag and no NPC
	#    label (the Blacksmith's ...) sits on the help text / minimap / stats corner
	_ui_walk_goal = me.zone.vendor_pos() + Vector2(0, 44)
	var walk_t := 0.0
	while me.position.distance_to(_ui_walk_goal) > 8.0 and walk_t < 9.0:
		await get_tree().process_frame
		walk_t += get_process_delta_time()
	_ui_walk_goal = null
	for f in 6:
		await get_tree().process_frame
	var avoid := _npc_label_avoid(me)
	var tag: Rect2 = avoid[3]
	var hud_hits: Array = []
	var vendor_tag := "no vendor label"
	var sides: Array = []
	for n in get_tree().get_nodes_in_group("npc_visual"):
		if not n.has_method("label_spots") or not (n as Node2D).is_visible_in_tree() or not me.zone.is_ancestor_of(n):
			continue
		var r := npc_label_rect(n)
		var nm: String = n.label_node.text.get_slice("\n", 0)
		if not get_viewport().get_visible_rect().intersects(r):
			continue
		if not n.label_node.visible:
			sides.append("%s hidden (under the HUD)" % nm)
			continue
		sides.append("%s %s" % [nm, n.label_side])
		if _rect_hits(r, avoid.slice(0, 3)):
			hud_hits.append(nm)
		if nm == "Vendor":
			vendor_tag = "OVERLAP" if r.intersects(tag) else "clear"
	_log("UI SELFTEST NPC labels at the vendor: %s (walked %.1fs, %d px from the spot; HUD overlaps [%s]; vendor label vs my name tag %s; sides: %s)" % [
		"PASS" if hud_hits.is_empty() and vendor_tag == "clear" else "FAIL", walk_t, roundi(me.position.distance_to(me.zone.vendor_pos() + Vector2(0, 44))),
		", ".join(hud_hits), vendor_tag, ", ".join(sides)])


var _ui_walk_goal = null   # UI selftest: walk here (idle bot)
var _rt_mode := ""   # UI selftest typing variant ("keycode-only": unicode 0, "no-release": presses only)


## A key event the way the X11/Windows display server builds it.
func _os_key(keycode: int, unicode: int, pressed: bool) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = keycode
	ev.key_label = keycode
	if _rt_mode == "keycode-only":   # some input tools: keycode (+shift) only, no unicode
		ev.shift_pressed = unicode >= 65 and unicode <= 90
		unicode = 0
	ev.unicode = unicode if pressed else 0
	ev.pressed = pressed
	return ev


static func _keycode_for(ch: String) -> int:
	if ch == " ":
		return KEY_SPACE
	if ch == "/":
		return KEY_SLASH
	return OS.find_keycode_from_string(ch.to_upper())


## One OS key event the way the engine handles it: Input updates the action state (what
## Input.get_vector polls), then the window gets it (Window._window_input -> push_input). The
## headless display server has no window callback, so the second half is done here.
func _os_feed(ev: InputEventKey) -> void:
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	if DisplayServer.get_name() == "headless":
		get_viewport().push_input(ev)


## UI selftest: Enter, then `t`, through Input.parse_input_event; returns what the chat line shows,
## how far the local player moved and whether any movement input went to the server.
func _real_typing(t: String, burst: bool, merged := false) -> Dictionary:
	var me := _local_player()
	var start: Vector2 = me.position if me else Vector2.ZERO
	var sent_move := false
	var was_bot := bot_mode
	bot_mode = false   # read the keyboard like a human client (bots steer via bot_dir)
	var evs: Array = [_os_key(KEY_ENTER, 0, true)]
	if merged:   # what X11 delivers for Enter (open) .. Enter (send an empty line) + Enter (open again) typed fast:
		var echo := _os_key(KEY_ENTER, 0, true)   # the 2nd release is dropped and the 3rd press comes flagged echo
		echo.echo = true
		evs.append_array([_os_key(KEY_ENTER, 0, false), _os_key(KEY_ENTER, 0, true), echo, _os_key(KEY_ENTER, 0, false)])
	if burst:   # rollover: Enter released only after the first characters went down
		for i in t.length():
			evs.append(_os_key(_keycode_for(t[i]), t.unicode_at(i), true))
			if i == 1:
				evs.append(_os_key(KEY_ENTER, 0, false))
			evs.append(_os_key(_keycode_for(t[i]), t.unicode_at(i), false))
		for e in evs:
			if _rt_mode == "no-release" and not e.pressed:
				continue   # some tools send presses only (all in one frame)
			_os_feed(e)
	else:
		evs.append(_os_key(KEY_ENTER, 0, false))
		for i in t.length():
			evs.append(_os_key(_keycode_for(t[i]), t.unicode_at(i), true))
			evs.append(_os_key(_keycode_for(t[i]), t.unicode_at(i), false))
		for e in evs:
			_os_feed(e)
			await get_tree().process_frame
			if me and me._last_sent != Vector2.ZERO:
				sent_move = true
	for f in 6:
		await get_tree().process_frame
		if me and me._last_sent != Vector2.ZERO:
			sent_move = true
	var res := {"text": chat_edit.text, "moved": me.position.distance_to(start) if me else 0.0, "sent_move": sent_move, "open": open_windows()}
	_os_feed(_os_key(KEY_ESCAPE, 0, true))
	_os_feed(_os_key(KEY_ESCAPE, 0, false))
	for f in 3:
		await get_tree().process_frame
	close_windows_except([])
	bot_mode = was_bot
	return res


func _inject_key(keycode: int, unicode: int) -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = keycode
		ev.physical_keycode = keycode
		ev.unicode = unicode if pressed else 0
		ev.pressed = pressed
		get_viewport().push_input(ev)   # synchronous, through GUI focus -> _unhandled_input like a real key


func _ground_items_near(me: Node, zone: Node) -> int:
	var n := 0
	for p in zone.loot_root.get_children():
		if p.position.distance_to(me.position) < 300.0:
			n += 1
	return n


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

	if tutorial_ui.visible and bot_tutorial != "":
		_bot_tutorial(me, zone, delta)
		return
	if bot_hideout != "":
		_bot_hideout(me, zone, delta)
		return
	if bot_craft:
		_bot_craft(me, delta)
		return
	if bot_dungeon == "" and bot_party.begins_with("invite:") and _bot_form_party(delta):
		return
	if bot_follow != "":
		_bot_follow(me, zone, delta)
		return
	if bot_dungeon != "" and _bot_dungeon(me, zone, delta):
		return
	if bot_vendor != "":
		_bot_vendor(me, zone, delta)
		return
	if bot_idle:
		bot_dir = Vector2.ZERO
		if _ui_walk_goal != null and me.position.distance_to(_ui_walk_goal) > 6.0:   # UI selftest walks somewhere
			bot_dir = _bot_steer(zone, me.position, _ui_walk_goal, delta)
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
		if target == null and bot_dungeon == "full" and zone.is_dungeon():   # elites first: the run's elite drop is under test
			var ed := 4000.0
			for m in zone.monsters_root.get_children():
				if m.alive and str(m.elite) != "" and m.position.distance_to(me.position) < ed:
					ed = m.position.distance_to(me.position)
					target = m
		if target == null and bot_hunt_boss:
			for m in zone.monsters_root.get_children():
				if m.is_boss and m.alive:
					target = m
		if target == null:
			target = _nearest(zone.monsters_root, me.position, 2500.0)
		if target:
			goal_pos = target.position
		if bot_probe and _bot_probe_goal != Vector2.INF:
			goal_pos = _bot_probe_goal

	_bot_move_timer -= delta
	if goal_pos == Vector2.INF:
		if _bot_move_timer <= 0.0:
			_bot_move_timer = rng.randf_range(0.6, 1.4)
			bot_dir = Vector2.from_angle(rng.randf() * TAU)
			# never wander back through a portal by accident: on the big maps the arrival
			# spot can have no monster in reach, and a random step west re-entered the old zone
			for p in Zones.info(zone.zone_id).get("portals", []):
				var pc: Vector2 = zone.map.cell_pos(p["rect"].get_center())
				if pc.distance_to(me.position) < 220.0:
					bot_dir = (me.position - pc).normalized().rotated(rng.randf_range(-0.6, 0.6))
	elif bot_smart and Classes.info(me.class_id)["basic"] == "ranged" and _nearest(zone.monsters_root, me.position, 140.0) != null \
			and zone.map.has_los(me.position, goal_pos):
		# ranged class: back off from the nearest monster, keep shooting from ~150-220 px
		var threat: Node2D = _nearest(zone.monsters_root, me.position, 140.0)
		var away: Vector2 = me.position + (me.position - threat.position).normalized() * 120.0
		bot_dir = _bot_steer(zone, me.position, away, delta) if zone.map.is_walkable(zone.map.local_to_map(away)) else Vector2.ZERO
	elif bot_smart and Classes.info(me.class_id)["basic"] == "ranged" and me.position.distance_to(goal_pos) < 220.0 and zone.map.has_los(me.position, goal_pos):
		bot_dir = Vector2.ZERO
	else:
		bot_dir = _bot_steer(zone, me.position, goal_pos, delta)

	_bot_attack_timer -= delta
	if _bot_attack_timer <= 0.0 and not bot_passive:
		_bot_attack_timer = 0.4
		me.request_attack()
	_bot_targeting(me, zone, delta)
	_bot_talent_logic(me, delta)
	_bot_skill_timer -= delta
	if bot_smart and not bot_passive and _bot_skill_timer <= 0.0:
		_bot_skill_timer = 0.3
		_bot_smart_skill(me, zone)
	elif bot_skills and not bot_passive and _bot_skill_timer <= 0.0:
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
		if not bot_passive and not bot_no_potions and me.hp <= me.max_hp - 4 and me.hp * 2 < me.max_hp + 20 and int(me.inventory.get(potion, 0)) > 0:
			_log("drinking a %s at hp %d/%d" % [potion, me.hp, me.max_hp])
			me.request_use(potion)
		_bot_gear(me)
	if not _bot_chatted and _elapsed > 3.0:
		_bot_chatted = true
		send_chat("Hello from %s!" % local_name)


## Balance-trial bot: the skill a sensible player would press now (ready, affordable, unlocked,
## in range; heals only when hurt; buffs / shields / taunts in combat), bigger skills first.
func _bot_smart_skill(me: Node, zone: Node) -> void:
	var tgt: Node2D = _nearest(zone.monsters_root, me.position, 400.0)
	for slot in [3, 2, 1, 0]:
		if me.level < Classes.UNLOCK_LEVELS[slot] or me.cooldown_left(slot) > 0.0:
			continue
		var sk: Dictionary = me.skill_def(Classes.skill_id(me.class_id, slot))
		if me.mp < int(sk["cost"]):
			continue
		var kind := str(sk["kind"])
		var d: float = tgt.position.distance_to(me.position) if tgt else INF
		var use := false
		match kind:
			"hot", "heal_area":
				use = me.hp < me.max_hp * 0.7
			"buff", "shield", "taunt":
				use = d < 200.0
			"aoe_self", "pulses", "ring":
				use = d < float(sk.get("radius", 90.0)) + 10.0
			_:
				use = d < float(sk.get("range", 200.0))
		if use:
			me.request_skill(slot)
			return


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
			if _bot_probe_step >= 3:
				_bot_probe_goal = Vector2.INF
			if req.is_empty() and _bot_probe_step >= 3:
				# no monster behind a wall within reach right now (big maps: often none nearby);
				# head for the nearest one that is out of sight, so the probe gets its chance
				var bd := 1500.0
				for m in zone.monsters_root.get_children():
					var d2: float = m.position.distance_to(me.position)
					if m.alive and d2 < bd and not zone.map.has_los(me.position + Vector2(0, -6), m.position + Vector2(0, -6)):
						bd = d2
						_bot_probe_goal = m.position
				_bot_probe_t = 0.5
				return   # try again shortly
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
func _bigmap_selftest() -> void:
	var ok := true
	var old_area := 64 * 40
	for id in Zones.ORDER:
		var m := ZoneMap.new()
		m.build(id)
		var zi: Dictionary = Zones.info(id)
		var area := m.w * m.h
		var bad: Array = []
		for p in zi["portals"]:
			if not m.is_reachable(p["rect"].position):
				bad.append("portal->" + str(p["to"]))
		for k in ["respawn", "blacksmith", "map_device", "merchant", "vendor", "hideout_master"]:
			if zi.has(k) and not m.is_reachable(zi[k]):
				bad.append(k)
		if not zi["boss"].is_empty() and not m.is_reachable(zi["boss"]["cell"]):
			bad.append("boss lair")
		var kinds := {}
		var depth := {}
		var placed := 0
		for st in m.sites:
			if int(st["spec"]) < 0:
				continue
			placed += 1
			if not m.is_reachable(st["cell"]):
				bad.append("site %s" % st["cell"])
			kinds[st["kind"]] = int(kinds.get(st["kind"], 0)) + 1
			depth[st["kind"]] = float(depth.get(st["kind"], 0.0)) + float(st["depth"])
		var planned := 0
		for g in zi["groups"]:
			if g.get("core", false):
				kinds["pack"] = int(kinds.get("pack", 0)) + int(g["n"])
			elif g["kind"] == "guard":
				kinds["guard"] = int(g["n"])
			else:
				planned += int(g["n"])
		var pack_d := float(depth.get("pack", 0.0)) / maxf(1.0, float(kinds.get("pack", 1)))
		var elite_d := float(depth.get("elite", 0.0)) / maxf(1.0, float(kinds.get("elite", 1)))
		var m2 := ZoneMap.new()
		m2.build(id)
		var same := m2.sites.size() == m.sites.size() and m2.get_used_cells(0).size() == m.get_used_cells(0).size()
		for i in mini(m.sites.size(), m2.sites.size()):
			same = same and m.sites[i]["cell"] == m2.sites[i]["cell"] and m.sites[i]["kind"] == m2.sites[i]["kind"]
		var good: bool = area >= old_area * 9.5 and bad.is_empty() and kinds.size() >= 4 and placed == planned and elite_d > pack_d and same
		ok = ok and good
		print("BIGMAP SELFTEST %-6s size %dx%d (%.1fx the old 64x40 area) | %d reachable cells | %d sites, %d groups placed of %d | group kinds %s | avg depth pack %.2f elite %.2f | deterministic %s | unreachable %s %s" % [
			id, m.w, m.h, float(area) / old_area, m.reachable.size(), m.sites.size(), placed, planned, kinds, pack_d, elite_d, same, bad, "" if good else "<-- FAIL"])
		# old saves: a position on the old 64x40 map lands on the same spot of the core
		var old_cell: Vector2i = zi["respawn"] - Zones.core_of(id)   # the zone entrance on the old 64x40 map
		var old_spawn := Vector2(old_cell * 32) + Vector2(16, 16)
		var moved := Zones.migrate_pos(id, old_spawn, 1)
		var near := m.nearest_reachable_pos(Vector2(99999, -500), zi["respawn"])
		var mig_ok := m.is_reachable(m.local_to_map(moved)) and Zones.migrate_pos(id, moved, Zones.MAP_VERSION) == moved and m.is_reachable(m.local_to_map(near))
		ok = ok and mig_ok
		print("BIGMAP SELFTEST %-6s old-save position %s -> %s (reachable %s), out-of-bounds (99999,-500) -> %s %s" % [id, old_spawn, moved, m.is_reachable(m.local_to_map(moved)), near, "" if mig_ok else "<-- FAIL"])
		var camps: Array = []
		var elites: Array = []
		var packs: Array = []
		for st in m.sites:
			if st["kind"] == "camp":
				camps.append("%d,%d" % [st["cell"].x, st["cell"].y])
			elif st["kind"] == "elite":
				elites.append("%d,%d" % [st["cell"].x, st["cell"].y])
			elif st["kind"] == "pack" and int(st["spec"]) >= 0:
				packs.append("%s@%d,%d" % [str(zi["groups"][int(st["spec"])]["types"][0]), st["cell"].x, st["cell"].y])
		print("BIGMAP SELFTEST %-6s camps at %s elites at %s" % [id, " ".join(camps), " ".join(elites)])
		print("BIGMAP SELFTEST %-6s packs %s" % [id, " ".join(packs)])
		m.free()
		m2.free()
	print("BIGMAP SELFTEST OK" if ok else "BIGMAP SELFTEST FAILED")
	get_tree().quit()


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
	ok = _vendor_selftest(g) and ok
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


## Offline vendor checks: deterministic stock, prices, rotation maths, save sanitizing.
func _vendor_selftest(_g: RandomNumberGenerator) -> bool:
	var fails: Array = []
	var cnt := [0]
	var expect := func(c: bool, what: String) -> void:
		cnt[0] += 1
		if not c:
			fails.append(what)
	var a := Vendor.roll_stock(12345)
	var b := Vendor.roll_stock(12345)
	var c := Vendor.roll_stock(54321)
	expect.call(JSON.stringify(a) == JSON.stringify(b), "same seed -> same stock")
	expect.call(JSON.stringify(a) != JSON.stringify(c), "new rotation -> new stock")
	var gear := a.filter(func(e): return e.has("item"))
	expect.call(gear.size() == Vendor.STOCK_GEAR, "gear count")
	expect.call(a.size() == Vendor.STOCK_GEAR + Vendor.STAPLES.size() + 2, "staples + 2 orbs")
	var ok_price := true
	for e in gear:
		ok_price = ok_price and int(e["price"]) == Vendor.gear_price(e["item"]) and int(e["price"]) > Gear.sell_price(e["item"])
	expect.call(ok_price, "buy price above sell price")
	expect.call(Vendor.rotation_index(7200 * 5 + 10) == 5 and Vendor.rotation_index(7199) == 0, "rotation index")
	var clean := Vendor.sanitize({"rotation": 3, "day": "2026-10-18", "stock": [a[0], {"stack": "bogus"}, {"item": {"base": "nope"}}, gear[0], 5]})
	expect.call(clean["stock"].size() == 2 and clean["rotation"] == 3, "sanitize drops junk")
	if fails.is_empty():
		print("GEAR SELFTEST vendor selftest: all %d checks passed" % cnt[0])
	else:
		print("GEAR SELFTEST vendor selftest: %d/%d FAILED: %s" % [fails.size(), cnt[0], fails])
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
	var foreign := _foreign_count(z.zone_id)
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

	solo_btn = Button.new()
	solo_btn.text = "Play Solo"
	solo_btn.add_theme_font_size_override("font_size", 22)
	solo_btn.custom_minimum_size = Vector2(0, 44)
	solo_btn.tooltip_text = "Start right away with a local server - no login, progress is saved to your local profile."
	solo_btn.pressed.connect(_on_solo_pressed)
	vb.add_child(solo_btn)
	var shb := HBoxContainer.new()
	shb.add_theme_constant_override("separation", 8)
	vb.add_child(shb)
	shb.add_child(_mk_label("Local profile:"))
	solo_slot_pick = OptionButton.new()
	solo_slot_pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shb.add_child(solo_slot_pick)
	_refresh_solo_slots()
	var sep := HSeparator.new()
	vb.add_child(sep)
	vb.add_child(_mk_label("Online play"))
	vb.add_child(_mk_label("Account name"))
	name_edit = LineEdit.new()
	name_edit.text = _last_name if _last_name != "" else "Hero%d" % rng.randi_range(100, 999)   # keep the name after Return to Main Menu
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
	stats_panel.name = "StatsPanel"
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
	zone_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART   # long dungeon lines wrap: the box stays 230 px wide
	svb.add_child(zone_label)
	# the party list is its own box under the stats (it used to grow the stats box, which the HUD
	# declutter then faded whenever an NPC was under the taller box)
	var party_panel := PanelContainer.new()
	party_panel.name = "PartyPanel"
	party_panel.position = Vector2(10, 200)
	party_panel.add_theme_stylebox_override("panel", _panel_style())
	party_panel.visible = false
	hud.add_child(party_panel)
	party_label = Label.new()
	party_label.add_theme_font_size_override("font_size", 13)
	party_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7))
	party_label.visible = false
	party_label.visibility_changed.connect(func():
		party_panel.visible = party_label.visible
		party_panel.reset_size())
	party_panel.add_child(party_label)
	invite_box = PanelContainer.new()
	invite_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	invite_box.position = Vector2(-150, 160)
	invite_box.visible = false
	hud.add_child(invite_box)
	var ivb := VBoxContainer.new()
	ivb.name = "V"
	invite_box.add_child(ivb)
	var il := Label.new()
	il.name = "L"
	ivb.add_child(il)
	var ihb := HBoxContainer.new()
	ivb.add_child(ihb)
	for yes in [true, false]:
		var b := Button.new()
		b.text = "Accept" if yes else "Decline"
		b.pressed.connect(_answer_invite.bind(yes))
		ihb.add_child(b)

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
	info_label.add_theme_font_size_override("font_size", 11)
	info_label.modulate = Color(1, 1, 1, 0.6)   # small + faded: hints, not a wall over monsters
	info_label.add_theme_color_override("font_outline_color", Color.BLACK)
	info_label.add_theme_constant_override("outline_size", 4)
	hud.add_child(info_label)
	fps_label = Label.new()
	fps_label.anchor_left = 1.0
	fps_label.anchor_right = 1.0
	fps_label.offset_left = -300
	fps_label.offset_right = -10
	fps_label.offset_top = 226   # right under the (smaller) minimap
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fps_label.add_theme_font_size_override("font_size", 11)
	fps_label.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	fps_label.add_theme_color_override("font_outline_color", Color.BLACK)
	fps_label.add_theme_constant_override("outline_size", 4)
	fps_label.visible = false
	hud.add_child(fps_label)
	minimap = preload("res://scripts/minimap.gd").new()
	minimap.main = self
	fps_label.visible = _show_fps
	hud.add_child(minimap)

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
	chat_panel.name = "ChatPanel"
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
	chat_edit.focus_mode = Control.FOCUS_NONE   # never takes GUI focus (no X11 IME hand-off), see open_chat()
	chat_edit.context_menu_enabled = false
	chat_edit.gui_input.connect(_on_chat_gui_input)
	_chat_style_open = StyleBoxFlat.new()
	_chat_style_open.bg_color = Color(0.08, 0.1, 0.16, 0.95)
	_chat_style_open.border_color = Color(0.55, 0.75, 1.0)
	_chat_style_open.set_border_width_all(1)
	_chat_style_open.set_content_margin_all(4)
	chat_vb.add_child(chat_edit)

	inventory_ui = InventoryUIScript.new()
	inventory_ui.anchor_left = 1.0
	inventory_ui.anchor_right = 1.0
	inventory_ui.offset_left = -572
	inventory_ui.offset_right = -10
	inventory_ui.offset_top = 80
	inventory_ui.grow_horizontal = Control.GROW_DIRECTION_BEGIN   # wider content grows left, never off-screen
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
	tutorial_ui = TutorialUIScript.new()
	tutorial_ui.main = self
	tutorial_ui.position = Vector2(292, 64)   # tutorial_ui._place() docks it away from open windows
	tutorial_ui.visible = false
	hud.add_child(tutorial_ui)
	vendor_ui = VendorUIScript.new()
	vendor_ui.position = Vector2(10, 70)
	vendor_ui.visible = false
	hud.add_child(vendor_ui)
	item_tip = ItemTooltipScript.new()
	hud.add_child(item_tip)
	vendor_ui.tooltip = item_tip
	inventory_ui.vendor_ui = vendor_ui
	vendor_ui.visibility_changed.connect(func():
		inventory_ui.set_compact(vendor_ui.visible)
		if inventory_ui.player:
			inventory_ui._update_status())
	vendor_ui.ui_log.connect(_log)
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
	_tf_invite = Button.new()
	_tf_invite.text = "Invite to party"
	_tf_invite.focus_mode = Control.FOCUS_NONE
	_tf_invite.add_theme_font_size_override("font_size", 11)
	_tf_invite.visible = false
	_tf_invite.pressed.connect(func():
		var t: Node = NetUtil.selected
		if is_instance_valid(t) and "display_name" in t:
			send_chat("/invite %s" % t.display_name))
	tfh.add_child(_tf_invite)

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
	if OS.has_environment("VOLAM_KEYLOG"):
		char_sheet.visibility_changed.connect(func(): _log("C panel %s" % ("shown" if char_sheet.visible else "hidden")))

	# Draw order: windowed panels sit above the always-on HUD (chat, skill bar, help text,
	# minimap), the tutorial above them, the item tooltip on top of everything.
	# The tutorial sits under the windows: it docks away from them, and when nothing fits (the tall
	# C panel) the window stays readable on top.
	for panel_node in [tutorial_ui, inventory_ui, smith_ui, map_ui, atlas_ui, hideout_ui, vendor_ui, talent_ui, char_sheet, item_tip]:
		hud.move_child(panel_node, -1)

	class_select = ClassSelectScript.new()
	class_select.visible = false
	class_select.chosen.connect(_on_class_chosen)
	ui.add_child(class_select)


## Main menu: label each local profile slot with the saved hero (class + level) or "empty".
func _refresh_solo_slots() -> void:
	var store := AccountStore.new(save_file if save_file != DEFAULT_SAVE_FILE else SOLO_SAVE_FILE)
	store.load_file()
	solo_slot_pick.clear()
	for i in range(1, SOLO_SLOTS + 1):
		var acc := store.get_account("slot%d" % i)
		var ch: Dictionary = acc.get("character", {})
		var txt := "Slot %d - empty (new hero)" % i
		if not acc.is_empty():
			txt = "Slot %d - %s, %s Lv%d" % [i, acc.get("name", "?"), Classes.info(str(ch["class"]))["name"] if Classes.exists(str(ch.get("class", ""))) else "no class", int(ch.get("level", 1))]
		solo_slot_pick.add_item(txt, i)
	solo_slot_pick.select(clampi(solo_slot - 1, 0, SOLO_SLOTS - 1))


func _on_solo_pressed() -> void:
	start_solo(solo_slot_pick.get_selected_id() if solo_slot_pick.selected >= 0 else 1, solo_port)


## "Play Solo": one click. Runs the normal authoritative server in-process (ENet bound to
## 127.0.0.1, nobody else can join) and logs the local profile slot in without a password.
func start_solo(slot: int, port := DEFAULT_PORT) -> bool:
	solo_mode = true
	solo_slot = clampi(slot, 1, SOLO_SLOTS)
	if save_file == DEFAULT_SAVE_FILE:
		save_file = SOLO_SAVE_FILE
	_log("Play Solo: local profile slot %d (%s)" % [solo_slot, ProjectSettings.globalize_path(save_file)])
	return start_server(port, false)


## Solo: the account key of the local profile slot, created on first use (display name from the name box).
func _solo_account() -> String:
	var key := "slot%d" % solo_slot
	if not accounts.has_account(key):
		var acc := accounts.create_account(key, Crypto.new().generate_random_bytes(16).hex_encode())
		var nm := _sanitize_name(name_edit.text)
		acc["name"] = nm if nm != "" else "Hero"
		acc["solo"] = true
		accounts.save_file()
		_log("Created local profile slot %d for '%s'" % [solo_slot, acc["name"]])
	return key


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


## --bot-watch-patrol: pick a meadow patrol site, work out its route (the site + the 2 nearest other sites, as the
## server does) and warp to a walkable cell that keeps every waypoint within monster activation range but stays well
## outside aggro range of the whole route; then just stand there (the patrol test in run_local_test.sh phase 12).
func _watch_patrol(me: Node) -> void:
	var map = me.zone.map
	var aggro_px := 300.0
	for st in map.sites:
		if st["kind"] != "patrol":
			continue
		var c: Vector2i = st["cell"]
		var others: Array = []
		for o in map.sites:
			if o["cell"] != c:
				others.append(o["cell"])
		others.sort_custom(func(a, b): return Vector2(a).distance_squared_to(Vector2(c)) < Vector2(b).distance_squared_to(Vector2(c)))
		var route: Array = [c, others[0], others[1]]
		var pts: Array = route.map(func(x): return map.cell_pos(x))
		var mean: Vector2 = (pts[1] + pts[2]) * 0.5
		var away: Vector2 = (pts[0] - mean).normalized()
		for ang in [0.0, 0.4, -0.4, 0.8, -0.8, 1.2, -1.2, 1.6, -1.6]:
			for d in range(10, 22):
				var pos: Vector2 = pts[0] + away.rotated(ang) * d * 32.0
				var cell: Vector2i = map.local_to_map(pos)
				if not map.is_walkable(cell) or not map.is_reachable(cell):
					continue
				var ok := true
				for i in 3:
					var a: Vector2 = pts[i]
					var b: Vector2 = pts[(i + 1) % 3]
					if a.distance_to(map.cell_pos(cell)) > me.zone.ACTIVE_RADIUS - 150.0 \
							or Geometry2D.get_closest_point_to_segment(map.cell_pos(cell), a, b).distance_to(map.cell_pos(cell)) < aggro_px:
						ok = false
						break
				if ok:
					_log("patrol watch: standing at cell %s, %.0f px from patrol site %s, route %s (max waypoint distance %.0f px)" % [
						cell, map.cell_pos(cell).distance_to(pts[0]), c, route,
						maxf(maxf(pts[0].distance_to(map.cell_pos(cell)), pts[1].distance_to(map.cell_pos(cell))), pts[2].distance_to(map.cell_pos(cell)))])
					request_warp.rpc_id(1, "meadow", cell)
					return
	_log("patrol watch: no suitable spot found near any patrol route")


## --menu-hideout-test: open the Esc menu and click its "Hideout" button with real mouse events, then confirm the
## client ends up in its hideout (and the menu closed).
func _menu_hideout_step(me: Node, delta: float) -> void:
	_mht_t -= delta
	if _mht_t > 0.0:
		return
	match _mht_step:
		0:
			if _elapsed < 4.0:
				return
			pause_menu.open_menu()
			_mht_step = 1
			_mht_t = 0.5
		1:
			var btn: Button = null
			for b in pause_menu.find_children("*", "Button", true, false):
				if b.text == "Hideout" and b.is_visible_in_tree():
					btn = b
			if btn == null:
				_log("menu hideout test: FAILED - no visible Hideout button in the Esc menu")
				_mht_step = 9
				return
			var at := btn.get_global_rect().get_center()
			_log("menu hideout test: clicking the Esc menu's Hideout button at %s (zone %s)" % [at, me.zone.zone_id])
			var mv := InputEventMouseMotion.new()
			mv.position = at
			mv.global_position = at
			get_viewport().push_input(mv, true)
			for pressed in [true, false]:
				var ev := InputEventMouseButton.new()
				ev.button_index = MOUSE_BUTTON_LEFT
				ev.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
				ev.pressed = pressed
				ev.position = at
				ev.global_position = at
				get_viewport().push_input(ev, true)
			_mht_step = 2
			_mht_t = 6.0
		2:
			_log("menu hideout test: %s - zone %s, Esc menu %s" % ["ENTERED the hideout" if Zones.is_hideout(me.zone.zone_id) else "still outside", me.zone.zone_id, "open" if pause_menu.visible else "closed"])
			_mht_step = 9
