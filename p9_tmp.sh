#!/usr/bin/env bash
# Headless end-to-end test of Project Volam (dedicated server + bot clients).
#   Phase 1: fresh save. Bot1/Bot2 level up on meadow slimes; Bot1 walks
#            meadow -> forest -> meadow through the portals, Bot2 walks to the forest
#            and stays there (zone + position saved on logout).
#   Phase 2: server restarted on the same save: restore (incl. zone), wrong password,
#            duplicate login, passive bot gets defeated and respawns.
#   Classes: every new account picks a class (bots via --class); between phases 1
#            and 2 an "old" pre-class account is injected into the save to check the
#            one-time class prompt. Bots cycle through all 4 skill slots without local
#            checks, so the server's unlock / cooldown / mana rejections are exercised.
#   Phase 3: separate save, high-level debug characters: a Walker crosses every portal
#            in both directions (meadow->forest->crypt->frost->...->meadow) and hunter
#            squads warp to each zone and kill its boss (fast respawn so bosses return).
# Usage: GODOT=/path/to/Godot_v4.2.1-stable_linux.x86_64 ./run_local_test.sh
set -u
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")"
L=test-logs; mkdir -p $L; 
SAVE="$(pwd)/$L/accounts.json"; rm -f "$SAVE"
SAVE3="$(pwd)/$L/accounts_p3.json"; rm -f "$SAVE3"
rm -f $L/*_market.json $L/*.tmp
run() { "$GODOT" --headless --path . -- "$@"; }

echo "Phase 9 (~95s): Esc menu, pause, settings..."
SAVE9="$(pwd)/$L/accounts_p9.json"; rm -f "$SAVE9" $L/settings_test.cfg
# 9a: solo host (listen server, nobody else online): the menu really pauses the world, then quits cleanly
"$GODOT" --headless --path . -- --host --name=Solo --password=s --class=fire --bot-idle --menu-test --menu-test-leave=quit --save-file="$SAVE9" --quit-after=40 > $L/p9_host.log 2>&1
# 9b: client of a dedicated server: the game continues online, input stops; then Return to Main Menu
run --server --save-file="$SAVE9" --debug-start-level=5 --quit-after=30 > $L/p9b_server.log 2>&1 &
sleep 2
run --join=127.0.0.1 --name=Online --password=o --class=water --bot --menu-test --menu-test-leave=menu --quit-after=26 > $L/p9b_client.log 2>&1 &
wait
# 9c: a player joins a host whose menu is open -> the host unpauses
"$GODOT" --headless --path . -- --host --name=Solo --password=s --bot-idle --open-menu=4 --save-file="$SAVE9" --quit-after=22 > $L/p9c_host.log 2>&1 &
sleep 9
run --join=127.0.0.1 --name=Joiner --password=j --class=earth --bot-idle --quit-after=8 > $L/p9c_joiner.log 2>&1 &
wait
"$GODOT" --headless --path . -- --settings-test --settings-file="$(pwd)/$L/settings_test.cfg" > $L/settings_test.log 2>&1

check() { if grep -qE "$2" $L/$3; then echo "PASS  $1"; else echo "FAIL  $1"; fi; }
echo; echo "== Esc menu & pause"
check "Esc closes an open panel first (not the menu)"  "Esc closed the inventory panel"                         p9_host.log
check "Esc with nothing open opens the menu"           "menu opened \(solo host: world paused\)"              p9_host.log
check "solo host: tree paused, peer still connected"   "menu test: menu open true, tree paused true, solo host true, [1-9][0-9]* monsters tracked, peer connected true" p9_host.log
check "solo host pause freezes monsters"               "while the menu was open for 4s, monsters moved 0.0 px in total \(tree paused true\)" p9_host.log
check "Esc again resumes"                              "menu test: menu open false, tree paused false, peer connected true" p9_host.log
check "monsters move again after resume"               "after resuming, monsters moved [1-9][0-9.]* px"         p9_host.log
check "Quit Game saves and exits cleanly"              "Saved .*shutdown"                                       p9_host.log
check "online client: game continues, input stopped"  "menu opened \(online: game continues, input stopped\)" p9b_client.log
check "online client: world keeps running while menu open" "while the menu was open for 4s, monsters moved [1-9][0-9.]* px in total \(tree paused false\); local input dir \(0, 0\)" p9b_client.log
check "online client: still connected after the menu" "menu test: menu open false, tree paused false, peer connected true" p9b_client.log
check "Return to Main Menu: clean disconnect"          "left the game, back to the main menu"                   p9b_client.log
check "Return to Main Menu: title screen shown"        "main menu shown after Return to Main Menu \(peer none\)" p9b_client.log
check "server saw the clean disconnect + saved"        "Peer [0-9]+ \(Online\) disconnected"                  p9b_server.log
check "player joining a paused host unpauses it"       "menu: a player joined, world unpaused"                  p9c_host.log
check "joiner logged in while host menu open"          "Login 'Joiner'"                                         p9c_host.log
check "settings persist (user://settings.cfg)"         "SETTINGS TEST OK"                                       settings_test.log
echo; echo "== Errors/warnings (should be none):"
grep -iE "SCRIPT ERROR|^ERROR|^WARNING" $L/*.log | sort | uniq -c | head -40 || true
grep -qiE "SCRIPT ERROR|^ERROR|^WARNING" $L/*.log || echo "none"
