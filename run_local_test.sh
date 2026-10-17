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
L=test-logs; mkdir -p $L; rm -f $L/*.log
SAVE="$(pwd)/$L/accounts.json"; rm -f "$SAVE"
SAVE3="$(pwd)/$L/accounts_p3.json"; rm -f "$SAVE3"
rm -f $L/*_market.json $L/*.tmp
run() { "$GODOT" --headless --path . -- "$@"; }

echo "Phase 1 (~86s)..."
run --server --debug-loot --save-file="$SAVE" --quit-after=86 > $L/p1_server.log 2>&1 &
sleep 2
run --join=127.0.0.1 --name=Bot1 --password=pw1 --class=metal --bot --bot-route=forest,meadow --bot-dwell=15 --quit-after=80 > $L/p1_bot1.log 2>&1 &
run --join=127.0.0.1 --name=Bot2 --password=pw2 --class=water --bot --bot-route=forest --bot-dwell=20 --quit-after=80 > $L/p1_bot2.log 2>&1 &
wait

# an account saved by the pre-class version of the game (password "old", no "class",
# wearing a staff an Earth character can't use)
python3 - "$SAVE" <<'PY'
import hashlib, json, sys
p = sys.argv[1]; d = json.load(open(p)); salt = "0123456789abcdef"
d["accounts"]["oldie"] = {"name": "Oldie", "salt": salt, "hash": hashlib.sha256((salt + "old").encode()).hexdigest(),
  "created": "2026-10-11T12:00:00", "character": {"level": 4, "xp": 5, "hp": 40, "gold": 12, "zone": "meadow",
  "inventory": {"health_potion": 2, "steel_sword": 1}, "equipment": {"weapon": "lich_staff", "armor": "wooden_shield"}}}
# saved before the 10x bigger maps (no "map_v"): standing next to the old town blacksmith (cell 35,18 of the 64x40 meadow)
d["accounts"]["oldtown"] = {"name": "Oldtown", "salt": salt, "hash": hashlib.sha256((salt + "old").encode()).hexdigest(),
  "created": "2026-10-12T12:00:00", "class": "metal", "character": {"class": "metal", "level": 3, "xp": 0, "hp": 40, "gold": 5,
  "zone": "meadow", "pos": [35 * 32 + 16, 18 * 32 + 16]}}
# a position that is outside the map / inside a wall: must be relocated to the nearest valid spot
d["accounts"]["lost"] = {"name": "Lost", "salt": salt, "hash": hashlib.sha256((salt + "old").encode()).hexdigest(),
  "created": "2026-10-12T12:00:00", "class": "fire", "character": {"class": "fire", "level": 8, "xp": 0, "hp": 60, "gold": 5,
  "zone": "crypt", "pos": [99999.0, -320.0], "map_v": 2}}
json.dump(d, open(p, "w"), indent="\t")
PY

echo "Phase 2 (~45s)..."
run --server --save-file="$SAVE" --quit-after=46 > $L/p2_server.log 2>&1 &
sleep 2
run --join=127.0.0.1 --name=Bot1 --password=pw1 --bot --quit-after=40 > $L/p2_bot1_restore.log 2>&1 &
run --join=127.0.0.1 --name=Bot2 --password=pw2 --bot --quit-after=10 > $L/p2_bot2_restore.log 2>&1 &
run --join=127.0.0.1 --name=Oldie --password=old --class=earth --bot --quit-after=30 > $L/p2_oldie.log 2>&1 &
run --join=127.0.0.1 --name=Oldtown --password=old --bot-idle --quit-after=12 > $L/p2_oldtown.log 2>&1 &
run --join=127.0.0.1 --name=Lost --password=old --bot-idle --quit-after=12 > $L/p2_lost.log 2>&1 &
run --join=127.0.0.1 --name=Victim --password=v --class=fire --bot-passive --bot-route=forest --bot-dwell=0 --quit-after=40 > $L/p2_victim.log 2>&1 &
sleep 3
run --join=127.0.0.1 --name=BOT1 --password=pw1 --bot --quit-after=10 > $L/p2_bot1_duplicate.log 2>&1 &
sleep 10   # Bot2 has logged out again by now
run --join=127.0.0.1 --name=bot2 --password=WRONG --bot --quit-after=10 > $L/p2_bot2_wrongpw.log 2>&1 &
wait

echo "Phase 3 (~130s)..."
run --server --save-file="$SAVE3" --debug-start-level=20 --fast-respawn --allow-warp --quit-after=130 > $L/p3_server.log 2>&1 &
sleep 2
run --join=127.0.0.1 --name=Walker --password=w --class=wood --bot --bot-route=forest,crypt,frost,crypt,forest,meadow --bot-dwell=4 --quit-after=124 > $L/p3_walker.log 2>&1 &
declare -A LAIR=([forest]=180,110 [crypt]=26,18 [frost]=186,26)   # inside each boss lair (big maps)
declare -A HC=([forest1]=metal [forest2]=wood [forest3]=water [crypt1]=fire [crypt2]=earth [crypt3]=water
               [frost1]=earth [frost2]=fire [frost3]=metal)
for z in forest crypt frost; do
  for n in 1 2 3; do
    run --join=127.0.0.1 --name=${z}Hunter$n --password=h --class=${HC[$z$n]} --bot --bot-hunt=boss --warp=$z --warp-cell=${LAIR[$z]} --quit-after=124 > $L/p3_${z}_hunter$n.log 2>&1 &
  done
done
wait

echo "Phase 4 (~75s): targeting + talents..."
SAVE4="$(pwd)/$L/accounts_p4.json"; rm -f "$SAVE4"
run --server --save-file="$SAVE4" --debug-start-level=20 --debug-loot --fast-respawn --allow-warp --quit-after=76 > $L/p4_server.log 2>&1 &
sleep 2
b4() { n=$1; shift; run --join=127.0.0.1 --name=$n --password=t --bot --bot-no-gear "$@" --quit-after=70 > $L/p4_$n.log 2>&1 & }
b4 MetalA --class=metal --bot-talents=goals:m_bloodthirst,m_bladestorm --bot-target=far --warp=crypt
b4 MetalB --class=metal --bot-talents=auto:1 --warp=forest
b4 WoodA  --class=wood  --bot-talents=auto:0 --bot-aim --warp=forest
b4 WoodB  --class=wood  --bot-talents=auto:1 --warp=crypt
b4 WaterA --class=water --bot-talents=goals:a_siphon,a_zero --bot-aim --warp=frost
b4 WaterB --class=water --bot-talents=auto:1 --bot-probe --warp=forest
b4 FireA  --class=fire  --bot-talents=goals:f_quicken,f_shower --bot-aim --warp=crypt
b4 FireB  --class=fire  --bot-talents=auto:1 --bot-target=far --bot-respec-at=28,31,34,37,40,43,46 --warp=frost
b4 EarthA --class=earth --bot-talents=auto:0 --bot-talent-probe --warp=crypt
b4 EarthB --class=earth --bot-talents=auto:1 --warp=frost
b4 Farmer --class=metal --bot-talents=farm --warp=forest
run --join=127.0.0.1 --name=Phoenix --password=t --bot-passive --class=fire --bot-talents=goals:f_phoenix --warp=frost --warp-cell=50,64 --warp-delay=12 --quit-after=70 > $L/p4_Phoenix.log 2>&1 &
wait
echo "Phase 4b (~14s): talents restored after restart..."
run --server --save-file="$SAVE4" --quit-after=14 > $L/p4b_server.log 2>&1 &
sleep 2
run --join=127.0.0.1 --name=MetalA --password=t --bot --quit-after=8 > $L/p4b_metal.log 2>&1 &
run --join=127.0.0.1 --name=FireB --password=t --bot --quit-after=8 > $L/p4b_fire.log 2>&1 &
wait
"$GODOT" --headless --path . -- --talent-selftest > $L/talent_selftest.log 2>&1
"$GODOT" --headless --path . -- --bigmap-selftest > $L/bigmap_selftest.log 2>&1

echo "Phase 5 (~70s): gear, crafting, blacksmith..."
SAVE5="$(pwd)/$L/accounts_p5.json"; rm -f "$SAVE5"
run --server --save-file="$SAVE5" --debug-start-level=13 --debug-gear --debug-full-bag=Full --debug-loot --allow-warp --quit-after=70 > $L/p5_server.log 2>&1 &
sleep 2
run --join=127.0.0.1 --name=Smith --password=s --class=water --bot --bot-craft --warp=meadow --warp-cell=173,62 --quit-after=64 > $L/p5_smith.log 2>&1 &
run --join=127.0.0.1 --name=Warden --password=s --class=metal --bot --quit-after=64 > $L/p5_warden.log 2>&1 &
run --join=127.0.0.1 --name=FullBag --password=s --class=earth --bot --bot-no-gear --quit-after=64 > $L/p5_fullbag.log 2>&1 &
wait
echo "Phase 5b (~14s): gear restored after restart..."
run --server --save-file="$SAVE5" --quit-after=14 > $L/p5b_server.log 2>&1 &
sleep 2
run --join=127.0.0.1 --name=Smith --password=s --bot-passive --quit-after=8 > $L/p5b_smith.log 2>&1 &
wait
"$GODOT" --headless --path . -- --gear-selftest > $L/gear_selftest.log 2>&1

echo "Phase 6 (~180s): dungeon tickets, map device, instances, atlas..."
SAVE6="$(pwd)/$L/accounts_p6.json"; rm -f "$SAVE6"
run --server --save-file="$SAVE6" --debug-start-level=20 --debug-gear --debug-fresh=Diver --fast-respawn --instance-timeout=15 --complete-timeout=15 --debug-next-tier=1 --quit-after=180 > $L/p6_server.log 2>&1 &
sleep 2
b6() { n=$1; shift; run --join=127.0.0.1 --name=$n --password=d "$@" --quit-after=174 > $L/p6_$n.log 2>&1 & }
b6 MapperA --class=fire  --bot --bot-no-gear --bot-dungeon=full --bot-dungeon-theme=fire
b6 MapperB --class=water --bot --bot-no-gear --bot-dungeon=full --bot-dungeon-theme=wood
b6 Diver   --class=earth --bot --bot-dungeon=die --bot-dungeon-theme=earth
b6 Idler   --class=metal --bot --bot-dungeon=enter --bot-dungeon-unique
sleep 25
b6 Intruder --class=wood --bot --bot-dungeon=intrude
wait
echo "Phase 6b (~14s): atlas restored after restart..."
run --server --save-file="$SAVE6" --quit-after=14 > $L/p6b_server.log 2>&1 &
sleep 2
run --join=127.0.0.1 --name=MapperA --password=d --bot-idle --open-atlas --quit-after=8 > $L/p6b_mappera.log 2>&1 &
wait

echo "Phase 7 (~55s): trade market (list, search, buy, race, expiry, claim box)..."
SAVE7="$(pwd)/$L/accounts_p7.json"; rm -f "$SAVE7"
run --server --save-file="$SAVE7" --debug-start-level=20 --debug-gear --debug-full-bag=Full --debug-fresh=Pauper --market-max-listings=4 --market-short=Exp --quit-after=52 > $L/p7_server.log 2>&1 &
sleep 2
b7() { n=$1; q=$2; shift 2; run --join=127.0.0.1 --name=$n --password=m --bot "$@" --quit-after=$q > $L/p7_$n.log 2>&1 & }
b7 Sella 34 --class=metal --bot-market=seller
b7 Buyer 48 --class=water --bot-market=buyer
b7 RaceA 46 --class=fire --bot-market=race
b7 RaceB 46 --class=earth --bot-market=race
b7 Pauper 46 --class=wood --bot-market=pauper
b7 FullBag 46 --class=metal --bot-market=fullbag
b7 Expo 46 --class=water --bot-market=expirer
wait
echo "Phase 7b (~16s): market restored after restart, offline seller collects..."
run --server --save-file="$SAVE7" --quit-after=16 > $L/p7b_server.log 2>&1 &
sleep 2
run --join=127.0.0.1 --name=Sella --password=m --bot --bot-market=collector --quit-after=12 > $L/p7b_Sella.log 2>&1 &
run --join=127.0.0.1 --name=Buyer --password=m --bot-idle --quit-after=8 > $L/p7b_Buyer.log 2>&1 &
wait
python3 tools/market_audit.py "$SAVE7" $L/p7_server.log $L/p7b_server.log > $L/p7_audit.log 2>&1
echo "Phase 7c (~30s): server killed (-9) right after a trade, then restarted..."
SAVE7C="$(pwd)/$L/accounts_p7c.json"; rm -f "$SAVE7C"
"$GODOT" --headless --path . -- --server --save-file="$SAVE7C" --debug-start-level=20 --debug-gear > $L/p7c_server.log 2>&1 &
SPID=$!   # (the Godot process itself, not a subshell, so kill -9 really kills the server)
sleep 2
run --join=127.0.0.1 --name=Crasher --password=m --class=metal --bot --bot-market=seller --quit-after=14 > $L/p7c_seller.log 2>&1 &
run --join=127.0.0.1 --name=Snatcher --password=m --class=fire --bot --bot-market=qbuyer --quit-after=14 > $L/p7c_buyer.log 2>&1 &
sleep 13
kill -9 $SPID 2>/dev/null
wait
run --server --save-file="$SAVE7C" --quit-after=12 > $L/p7d_server.log 2>&1 &
sleep 2
run --join=127.0.0.1 --name=Crasher --password=m --bot --bot-market=collector --quit-after=8 > $L/p7d_seller.log 2>&1 &
wait
python3 tools/market_audit.py "$SAVE7C" $L/p7c_server.log $L/p7d_server.log > $L/p7c_audit.log 2>&1
echo "Phase 7e (~30s): server dies BETWEEN writing market.json and accounts.json, then restarted..."
SAVE7E="$(pwd)/$L/accounts_p7e.json"; rm -f "$SAVE7E"
run --server --save-file="$SAVE7E" --debug-start-level=20 --debug-gear --market-crash-test=buy --quit-after=20 > $L/p7e_server.log 2>&1 &
sleep 2
run --join=127.0.0.1 --name=Crasher --password=m --class=metal --bot --bot-market=seller --quit-after=14 > $L/p7e_seller.log 2>&1 &
run --join=127.0.0.1 --name=Snatcher --password=m --class=fire --bot --bot-market=qbuyer --quit-after=14 > $L/p7e_buyer.log 2>&1 &
wait
cp "$SAVE7E" $L/p7e_accounts_before_restart.json
run --server --save-file="$SAVE7E" --quit-after=12 > $L/p7f_server.log 2>&1 &
sleep 2
run --join=127.0.0.1 --name=Snatcher --password=m --bot-idle --quit-after=8 > $L/p7f_buyer.log 2>&1 &
run --join=127.0.0.1 --name=Crasher --password=m --bot --bot-market=collector --quit-after=8 > $L/p7f_seller.log 2>&1 &
wait
python3 tools/market_audit.py "$SAVE7E" $L/p7e_server.log $L/p7f_server.log > $L/p7e_audit.log 2>&1

echo "Phase 8 (~230s): PoE-style atlas (locked node, points, passives, extra portal, respec)..."
SAVE8="$(pwd)/$L/accounts_p8.json"; rm -f "$SAVE8"
run --server --save-file="$SAVE8" --debug-start-level=20 --debug-gear --fast-respawn --instance-timeout=15 --complete-timeout=12 --debug-atlas-kit --debug-next-tier=1 --quit-after=230 > $L/p8_server.log 2>&1 &
sleep 2
run --join=127.0.0.1 --name=Atlasa --password=a --class=fire --bot --bot-no-gear --bot-dungeon=full --bot-dungeon-theme=fire --bot-atlas --quit-after=224 > $L/p8_Atlasa.log 2>&1 &
wait
# an account saved by the OLD atlas (5x10 theme/tier grid, incl. tiers that are no longer map nodes)
python3 - "$SAVE8" <<'PY'
import hashlib, json, sys
p = sys.argv[1]; d = json.load(open(p)); salt = "0123456789abcdef"
d["accounts"]["oldmapper"] = {"name": "Oldmapper", "salt": salt, "hash": hashlib.sha256((salt + "old").encode()).hexdigest(),
  "created": "2026-10-13T12:00:00", "class": "water", "character": {"level": 20, "xp": 0, "hp": 100, "gold": 500, "zone": "meadow",
  "class": "water", "atlas": {"done": {"water:1": 3, "water:2": 1, "water:4": 2, "fire:1": 1, "metal:9": 1}}}}
json.dump(d, open(p, "w"), indent="\t")
PY
echo "Phase 8b (~16s): atlas restored after restart + old atlas migrated..."
run --server --save-file="$SAVE8" --quit-after=16 > $L/p8b_server.log 2>&1 &
sleep 2
run --join=127.0.0.1 --name=Atlasa --password=a --bot-idle --open-atlas --quit-after=10 > $L/p8b_Atlasa.log 2>&1 &
run --join=127.0.0.1 --name=Oldmapper --password=old --bot-idle --open-atlas --quit-after=10 > $L/p8b_Oldmapper.log 2>&1 &
wait
"$GODOT" --headless --path . -- --gear-selftest > $L/atlas_selftest.log 2>&1

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

echo "Phase 10 (~110s): hideout (enter/leave, decorations, limits, themes, stations, restart)..."
SAVE10="$(pwd)/$L/accounts_p10.json"; rm -f "$SAVE10"
run --server --hideout-debug --debug-start-level=20 --save-file="$SAVE10" --quit-after=66 > $L/p10_server.log 2>&1 &
sleep 2
run --join=127.0.0.1 --name=Decor --password=d --class=wood --bot --bot-hideout=1 --quit-after=58 > $L/p10_bot.log 2>&1 &
wait
run --server --save-file="$SAVE10" --quit-after=30 > $L/p10b_server.log 2>&1 &
sleep 2
run --join=127.0.0.1 --name=Decor --password=d --bot --bot-hideout=2 --quit-after=24 > $L/p10b_bot.log 2>&1 &
wait

check() { if grep -qE "$2" $L/$3; then echo "PASS  $1"; else echo "FAIL  $1"; fi; }
echo; echo "== Core features"
check "accounts created"            "Created account 'Bot1'"                 p1_server.log
check "slime damages player"        "took [0-9]+ damage from Slime"          p1_server.log
check "kill gives XP"               "gained [0-9]+ XP"                       p1_server.log
check "level up + chat message"     "\[chat\] \* Bot[12] reached level"      p1_bot1.log
check "loot dropped"                "dropped: gold"                          p1_server.log
check "loot picked up"              "picked up"                              p1_server.log
check "gear equipped"               "equipped"                               p1_server.log
check "periodic save"               "Saved .*periodic"                       p1_server.log
check "shutdown save"               "Saved .*shutdown"                       p1_server.log
check "save restored after restart" "Login 'Bot1'.*restored save"            p2_server.log
check "wrong password rejected"     "Login rejected: Wrong password"         p2_bot2_wrongpw.log
check "duplicate login rejected"    "Login rejected: .*already logged in"    p2_bot1_duplicate.log
check "player death"                "Victim died"                            p2_server.log
check "respawn at zone entrance"    "Victim respawned at spawn point"        p2_server.log
if grep -qhE "used (health|greater)_potion" $L/*server.log; then echo "PASS  potion used"; else echo "FAIL  potion used"; fi
echo; echo "== Zones"
check "meadow -> forest (Bot1)"     "Zone transfer: Bot1 meadow -> forest"   p1_server.log
check "forest -> meadow (Bot1)"     "Zone transfer: Bot1 forest -> meadow"   p1_server.log
check "client sees zone banner"     "Entered zone forest"                    p1_bot1.log
check "zone saved + restored"       "Login 'Bot2'.*restored save.*zone forest" p2_server.log
for t in "meadow -> forest" "forest -> crypt" "crypt -> frost" "frost -> crypt" "crypt -> forest" "forest -> meadow"; do
  check "walker $t"                 "Zone transfer: Walker $t"               p3_server.log
done
if grep -qhE "foreign_entities=[1-9]" $(ls $L/*.log | grep -v "_host.log"); then echo "FAIL  visibility isolation (client received other-zone entities)"; else echo "PASS  visibility isolation (no client ever received another zone's entities)"; fi
check "Bot1 back in meadow sees only itself" "zone=meadow players=1 Bot1\(" p1_bot1.log
check "Bot2 in forest sees only itself"      "zone=forest players=1 Bot2\(" p1_bot2.log
echo; echo "== Big maps & monster groups"
check "offline big-map self-test passes"   "BIGMAP SELFTEST OK"                                bigmap_selftest.log
for z in meadow forest crypt frost; do
  check "$z is ~10x bigger (200x128 vs 64x40)" "BIGMAP SELFTEST $z +size 200x128 \(10.0x the old 64x40 area\)" bigmap_selftest.log
  l=$(grep -hE "\[$z\] [0-9]+ monster groups" $L/p3_server.log | head -1)
  k=0; for kind in pack camp elite patrol guard; do echo "$l" | grep -q "\"$kind\"" && k=$((k+1)); done
  if [ "$k" -ge 4 ]; then echo "PASS  $z has $k distinct group types ($(echo "$l" | sed -E 's/.*map: //'))"; else echo "FAIL  $z distinct group types ($l)"; fi
done
if grep -hE "Zone [a-z]+ ready" $L/p3_server.log | grep -q UNREACHABLE; then echo "FAIL  portals, NPCs, boss lairs and monster sites reachable"; else echo "PASS  portals, NPCs, boss lairs and monster sites reachable"; fi
check "bosses wait in their lairs deep in the zone" "boss Yeti King spawned in its lair"          p3_server.log
if grep -qhE "group aggro: .* pulled by .* - [1-9][0-9]* groupmates join" $L/*server.log; then echo "PASS  group aggro (pull one, the group comes): $(cat $L/*server.log | grep -cE "group aggro:") pulls"; else echo "FAIL  group aggro"; fi
for kind in camp elite; do
  if grep -qhE "group aggro: .*\(group #[0-9]+ $kind of" $L/*server.log; then echo "PASS  a $kind group aggroed together"; else echo "FAIL  a $kind group aggroed together"; fi
done
if grep -qhE "group #[0-9]+ [a-z]+ of .* respawned at .*: [2-9][0-9]* members" $L/*server.log; then echo "PASS  groups respawn together ($(cat $L/*server.log | grep -cE "group #[0-9]+ .* respawned at") group respawns)"; else echo "FAIL  groups respawn together"; fi
check "elite group leader in the overworld"  "◆ |(Hasted|Armoured|Brutal|Regenerating) [A-Za-z ]+\(Lv[0-9]+\) was slain"   p3_server.log
check "old save: position shifted into the big map" "Login 'Oldtown': old-map position \(1136, 592\) in meadow shifted to \(5488, 2000\)" p2_server.log
check "old save: restored at the shifted spot"      "Login 'Oldtown' .*zone meadow, pos \(5488, 2000\)"                               p2_server.log
check "invalid saved position relocated"            "Login 'Lost': saved position \(99999, -320\) is not a valid spot in crypt - relocated" p2_server.log
if grep -hE "\] perf: " $L/p3_server.log $L/p4_server.log | awk '{for(i=1;i<=NF;i++){if($i=="monsters,"){t=$(i-1)} if($i=="awake"){a=$(i-1)}} if(a<t) ok=1} END{exit !ok}'; then echo "PASS  interest management: far monsters sleep ($(grep -hE "\] perf: " $L/p3_server.log | tail -1 | sed -E 's/.*perf: //'))"; else echo "FAIL  interest management"; fi
echo; echo "== Monsters (attack / die / respawn)"
for m in "Slime" "Dire Rat" "Cave Bat" "Wood Spider" "Crypt Archer" "Restless Ghost" "Grave Crawler" "Yeti" "Ice Ogre" "Frost Bat"; do
  a=$(cat $L/*server.log | grep -c "damage from $m")
  d=$(cat $L/*server.log | grep -c "] $m(Lv[0-9]*) was slain")
  r=$(cat $L/*server.log | grep -c "] $m(Lv[0-9]*) respawned")
  if [ "$a" -gt 0 ] && [ "$d" -gt 0 ] && [ "$r" -gt 0 ]; then s=PASS; else s=FAIL; fi
  printf "%s  %-15s attacks=%-4s kills=%-4s respawns=%s\n" $s "$m" $a $d $r
done
echo; echo "== Bosses"
for b in "Broodmother" "The Lich King" "Yeti King"; do
  check "$b killed"                 "$b\(Lv[0-9]+\) was slain"               p3_server.log
  check "$b loot dropped"           "$b dropped: gold"                       p3_server.log
  check "$b kill announced in chat" "\[chat\] \* .* defeated $b"             p3_server.log
  check "$b respawned"              "$b has returned"                        p3_server.log
done
check "Broodmother summons"         "summons spiderlings"                    p3_server.log
check "Lich volley"                 "casts Bone Volley"                      p3_server.log
check "Yeti King quake"             "QUAKE hits"                             p3_server.log
check "boss loot picked up"         "picked up \[unique\] .*(venom_dagger|lich_staff|frostbrand|ember_staff|frost_aegis)" p3_server.log
echo; echo "== Classes & character creation"
for c in metal wood water fire earth; do
  if grep -qhE "chose class $c " $L/*server.log; then echo "PASS  a character chose class $c"; else echo "FAIL  a character chose class $c"; fi
done
check "new account asked to pick a class"   "Class selection requested \(new account\)"           p1_bot1.log
check "starting gear: Metal gets a sword"   "Login 'Bot1'.*NEW account - class metal.*iron_sword"  p1_server.log
check "starting gear: Water gets a staff"   "Login 'Bot2'.*NEW account - class water.*apprentice_staff" p1_server.log
check "old account prompted (server)"       "Account 'Oldie' has no class yet.*old save"           p2_server.log
check "old account prompted (client)"       "Class selection requested \(existing account without a class\)" p2_oldie.log
check "old account keeps its progress"      "Login 'Oldie'.*restored save - class earth, level 4"  p2_server.log
check "class persists (Bot1 metal)"         "Login 'Bot1'.*restored save - class metal"           p2_server.log
check "class persists (Bot2 water)"         "Login 'Bot2'.*restored save - class water"           p2_server.log
check "restored players not re-prompted"    "Login 'Bot1'"                                         p2_server.log
if grep -q "Account 'Bot1' has no class" $L/p2_server.log; then echo "FAIL  Bot1 was prompted again"; else echo "PASS  Bot1 not prompted again"; fi
check "class-restricted weapon refused"     "Oldie can't equip lich_staff"                        p2_server.log
echo; echo "== Skills (server-authoritative)"
for sk in "Whirling Blade" "Piercing Strike" "Blade Focus" "Thousand Cuts" \
          "Poison Thorn" "Regrowth" "Entangling Roots" "Plague Bloom" \
          "Ice Shard" "Healing Rain" "Frost Nova" "Tidal Wave" \
          "Fireball" "Flame Burst" "Meteor" "Inferno" \
          "Ground Slam" "Stone Skin" "Mountain's Challenge" "Earthquake"; do
  n=$(cat $L/*server.log | grep -c "cast $sk (")
  h=$(cat $L/*server.log | grep -c "with $sk")
  if [ "$n" -gt 0 ]; then s=PASS; else s=FAIL; fi
  printf "%s  %-22s casts=%-4s hits=%s\n" $s "$sk" $n $h
done
check "locked skill rejected (level)"       "skill [234] rejected: .* unlocks at level"  p1_server.log
check "skill unlocked on level-up"          "Bot[12] unlocked skill 2: .* \(level 3\)"   p1_server.log
if grep -qhE "rejected: .* is on cooldown" $L/*server.log; then echo "PASS  cooldown enforced"; else echo "FAIL  cooldown enforced"; fi
if grep -qhE "rejected: not enough mana" $L/*server.log; then echo "PASS  mana cost enforced"; else echo "FAIL  mana cost enforced"; fi
# mana regen: Bot1's mana goes up between two server status lines at some point
if grep -ohE "Bot1\(Lv[0-9]+ [0-9]+/[0-9]+hp [0-9]+/" $L/p1_server.log | sed -E 's/.*hp ([0-9]+)\//\1/' | awk 'NR>1 && $1>p {up=1} {p=$1} END {exit !up}'; then echo "PASS  mana regenerates"; else echo "FAIL  mana regenerates"; fi
check "ranged basic attack (Water)"         "Bot2 hit .* with Frost Bolt"               p1_server.log
if grep -qh "with Fire Bolt" $L/*server.log; then echo "PASS  ranged basic attack (Fire)"; else echo "FAIL  ranged basic attack (Fire)"; fi
echo; echo "== Status effects & element cycle"
for st in "is poisoned" "is burning" "is slowed" "is stunned" "Stone Skin shield absorbs" "is taunted by" "gains Blade Focus"; do
  if grep -qh "$st" $L/*server.log; then echo "PASS  $st"; else echo "FAIL  $st"; fi
done
if grep -qhP "\] (\S+) healed (?!\1 )\S+ for" $L/*server.log; then echo "PASS  Healing Rain heals an ally"; else echo "FAIL  Healing Rain heals an ally"; fi
if grep -qhE "hit .*\[[A-Za-z]+>[A-Za-z]+ x1.25\]" $L/*server.log; then echo "PASS  +25% vs overcome element (player -> monster)"; else echo "FAIL  +25% vs overcome element"; fi
if grep -qhE "hit .*\[[A-Za-z]+<[A-Za-z]+ x0.80\]" $L/*server.log; then echo "PASS  -20% vs overcoming element (player -> monster)"; else echo "FAIL  -20% vs overcoming element"; fi
if grep -qhE "took [0-9]+ damage .*\[[A-Za-z]+>[A-Za-z]+ x1.25\]" $L/*server.log; then echo "PASS  element bonus applies to monster -> player"; else echo "FAIL  element bonus monster -> player"; fi
echo; echo "== Mouse targeting (server-validated)"
checkp() { if grep -qhP "$2" $L/$3; then echo "PASS  $1"; else echo "FAIL  $1"; fi; }
check "skills use selected target over nearer"   "uses selected target .* over nearer"      p4_server.log
check "projectile aimed at cursor (Ice Shard)"   "aims Ice Shard at the cursor"             p4_server.log
check "basic bolt aimed at cursor"               "aims basic bolt at the cursor"            p4_server.log
check "ground AoE at cursor (Entangling Roots)"  "casts Entangling Roots at the cursor"     p4_server.log
check "ground AoE at cursor (Meteor)"            "casts Meteor at the cursor"               p4_server.log
check "cursor clamped to max range"              "at the cursor .*clamped to range"         p4_server.log
check "invalid target id rejected"               "target rejected: .*does not exist"        p4_server.log
check "target in another zone rejected"          "target rejected: .*in another zone"       p4_server.log
check "out-of-range target rejected"             "target rejected: .*out of range"          p4_server.log
check "no line of sight rejected"                "target rejected: .*no line of sight"      p4_server.log
echo; echo "== Passive web"
check "offline web self-test (graph + maths)"  "TALENT SELFTEST OK"                       talent_selftest.log
check "web: every node reachable, 15 keystones" "WEB SELFTEST 1[0-9][0-9] nodes: .*\"keystone\": 15" talent_selftest.log
check "refund that would disconnect rejected"   "refund [a-z_0-9]+ rejected: refunding .* would disconnect" p4_server.log
check "single node refunded for gold"           "refunded passive .* for [0-9]+ gold"       p4_server.log
check "centre keystone allocated (Farmer)"      "Farmer allocated passive Treasure Hunter's Oath \[keystone\]" p4_server.log
check "points granted (level 20 = 19 points)"    "allocated passive .*\(19/19 points spent\)"  p4_server.log
check "adjacency enforced (unconnected node)"    "passive [a-z_]+ rejected: .* is not connected to your allocated nodes" p4_server.log
check "unknown node rejected"                    "rejected: there is no passive node .not_a_node." p4_server.log
check "already-allocated node rejected"          "rejected: .* is already allocated"         p4_server.log
check "no points left rejected"                  "rejected: no passive points left"          p4_server.log
check "full reset with gold cost"                "FireB reset passive web: refunded [0-9]+ points for [0-9]+ gold" p4_server.log
check "respec without enough gold rejected"      "FireB respec rejected: not enough gold"   p4_server.log
check "passives persist across restart (MetalA)"  "Login 'MetalA'.*restored save.*talent points [1-9][0-9]*/[0-9]+ \{ \"[a-z]" p4b_server.log
check "passives persist across restart (FireB)"   "Login 'FireB'.*restored save.*talent points [1-9][0-9]*/[0-9]+ \{ \"[a-z]" p4b_server.log
check "retroactive points (old save Oldie, Lv4)" "Login 'Oldie'.*talent points 0/3"         p2_server.log
check "retroactive points (pre-talent Bot1)"     "Login 'Bot1'.*restored save.*talent points 0/[1-9]" p2_server.log
checkp "stat talent: Honed Edge raises attack"   "passive Honed Edge I .*atk (\d+) .*-> .*atk (?!\1 )"  p4_server.log
checkp "stat talent: Steel Body raises max life" "passive Steel Body I .*\| hp (\d+) .*-> hp (?!\1 )"   p4_server.log
checkp "stat talent: Keen Eye raises crit"       "passive Keen Eye I .*crit (\S+) .*-> .*crit (?!\1 )"  p4_server.log
checkp "stat talent: Mana Font raises mana"      "passive Mana Font I .*mp (\d+) .*-> .*mp (?!\1 )"     p4_server.log
checkp "stat talent: Granite raises defense"     "passive Granite I .*def (\d+) .*-> .*def (?!\1 )"     p4_server.log
checkp "stat talent: Fleet Foot raises speed"    "passive Fleet Foot I .*speed (\d+) .*-> .*speed (?!\1$)" p4_server.log
for pair in "MetalA:Whirling Blade.*cd 2.4s, x2.32" "MetalB:Piercing Strike.*cd 4.9s" "WoodA:Plague Bloom.*cd 12.8s" \
            "WoodB:Regrowth.*cd 8.4s" "WaterA:Ice Shard.*cd 1.0s, x1.90" "WaterB:Healing Rain.*cd 7.6s" \
            "FireA:Meteor.*cd 10.0s" "FireB:Fireball.*cd 2.1s, x2.61" "EarthA:Mountain's Challenge.*cd 8.4s" "EarthB:Ground Slam.*cd 3.0s, x1.63"; do
  who=${pair%%:*}; pat=${pair#*:}
  check "passives change $who's ${pat%%.\**}" "\] $who cast $pat" p4_server.log
done
check "keystone Blade Storm (Metal)"          "Blade Storm spins again"                  p4_server.log
check "keystone Death Mark (Metal)"           "Death Mark executes"                      p4_server.log
check "keystone Pandemic (Wood)"              "Pandemic: .* poison jumps"                p4_server.log
check "keystone Heart of the Forest (Wood)"   "Heart of the Forest: Regrowth also heals" p4_server.log
check "keystone Absolute Zero (Water)"        "WaterA cast Ice Shard.*cd 1.0s"           p4_server.log
check "keystone Wellspring (Water)"           "Wellspring shields"                       p4_server.log
check "keystone Meteor Shower (Fire)"         "Meteor Shower calls 2 more meteors"       p4_server.log
check "keystone Phoenix Heart (Fire)"         "Phoenix Heart triggers"                   p4_server.log
check "keystone Unbreakable (Earth)"          "Unbreakable shield erupts"                p4_server.log
check "keystone Tectonic Fury (Earth)"        "Tectonic Fury: Earthquake tremors stun"   p4_server.log
check "farming stats boost loot (quantity/rarity/gold)" "dropped: .*\(killer .*% quantity" p4_server.log
check "life leech"                            "leeches [0-9]+ life"                      p4_server.log
check "mana leech"                            "leeches [0-9]+ mana"                      p4_server.log
check "Shatter: bonus vs slowed"              "Shatter: \+"                              p4_server.log
echo; echo "== Gear, rarity & loot"
checkp "offline gear self-test passes"            "GEAR SELFTEST RESULT: PASS"                         gear_selftest.log
check "IIQ: more drops (offline, 4000 kills)"     "IIQ effect: .* OK"                                  gear_selftest.log
check "IIR: rarer drops (offline, 4000 kills)"    "IIR effect: .* OK"                                  gear_selftest.log
check "item level gates bases + affix tiers"      "item level gating: ilvl 2 drops use bases/affix tiers up to level [12] .* OK" gear_selftest.log
check "magic 1-2 / rare 3-6 affixes + rare names" "affix counts .*: OK"                                gear_selftest.log
for r in normal magic rare unique; do
  if grep -qhE "dropped: .*\[$r\]" $L/*server.log; then echo "PASS  live drop of a $r item"; else echo "FAIL  live drop of a $r item"; fi
done
check "bosses drop their uniques"                 "Yeti King dropped: .*\[unique\] Frostbrand.*\[unique\] Ember Staff.*\[unique\] Frost Aegis" p3_server.log
check "boss drop table: magic+ guaranteed, monster IIQ/IIR" "Broodmother dropped: .*\[(magic|rare|unique)\].*monster iiq 50% iir 150%" p3_server.log
check "item level from monster level"             "dropped: .*\| monster lv ([0-9]+) -> ilvl [0-9]+"  p5_server.log
if grep -qhE "dropped: .*(orb_[a-z]+|enhance_stone) x" $L/*server.log; then echo "PASS  monsters drop crafting currency"; else echo "FAIL  monsters drop crafting currency"; fi
if grep -qhE "picked up 1 x (orb_[a-z]+|enhance_stone)" $L/*server.log && grep -qhE "inventory: .*\"(orb_[a-z]+|enhance_stone)\": ([2-9]|[1-9][0-9])" $L/p4_*.log; then echo "PASS  currency stacks in the bag"; else echo "FAIL  currency stacks in the bag"; fi
check "old saved items migrated to instances"     "Oldie: migrated 3 old item\(s\) to gear instances: steel_sword, lich_staff, wooden_shield" p2_server.log
echo; echo "== Crafting currency & enhancement (server-validated)"
check "Transmutation: normal -> magic"            "Smith used Orb of Transmutation on \[normal\].* -> \[magic\]"    p5_server.log
check "Transmutation on magic rejected"           "craft rejected: Orb of Transmutation on .*needs a Normal item"   p5_server.log
check "Alteration rerolls magic"                  "Smith used Orb of Alteration on \[magic\].* -> \[magic\]"        p5_server.log
check "Alteration on rare rejected"               "craft rejected: Orb of Alteration on .*needs a Magic item"       p5_server.log
check "Regal: magic -> rare"                      "Smith used Regal Orb on \[magic\].* -> \[rare\]"                 p5_server.log
check "Regal on rare rejected"                    "craft rejected: Regal Orb on .*needs a Magic item"               p5_server.log
check "Exalted adds an affix"                     "Smith used Exalted Orb on \[rare\].* -> \[rare\]"               p5_server.log
check "Exalted on a full rare rejected"           "craft rejected: Exalted Orb on .*already has 6 affixes"          p5_server.log
check "Chaos rerolls rare"                        "Smith used Chaos Orb on \[rare\].* -> \[rare\]"                 p5_server.log
check "Chaos on magic rejected"                   "craft rejected: Chaos Orb on .*needs a Rare item"                p5_server.log
check "Scouring: -> normal"                       "Smith used Orb of Scouring on \[rare\].* -> \[normal\]"         p5_server.log
check "Scouring on normal rejected"               "craft rejected: Orb of Scouring on .*already Normal"             p5_server.log
check "orbs on uniques rejected"                  "craft rejected: Chaos Orb on .*uniques can't be modified"        p5_server.log
check "non-currency rejected"                     "craft rejected: 'gold' is not crafting currency"                 p5_server.log
check "unknown item rejected"                     "craft rejected: item 123 not found"                              p5_server.log
check "orbs work away from the blacksmith"        "Smith used Orb of Transmutation on \[normal\] \+[0-9]+ Iron Sword" p5_server.log
check "enhancement success (+gold cost)"          "Smith enhance .*: \+[0-9] -> \+[0-9]+ SUCCESS \(chance [0-9]+%, cost [0-9]+ gold"  p5_server.log
check "enhancement failure / downgrade happens"   "Smith enhance .* (FAIL|DOWNGRADE) \(chance"                     p5_server.log
check "enhancement limited by gold or +10 max"    "Smith enhance rejected: (not enough gold|.*max)"                 p5_server.log
check "enhancement only at the blacksmith"        "Smith enhance rejected: you must be at the blacksmith"            p5_server.log
check "enhancement odds + never destroys (offline)" "enhancement rules: destroyed 0, downgrades below \+5 0"           gear_selftest.log
echo; echo "== Equipment, vendor, stash, bag"
checkp "equip changes resistances (Frost Aegis)"  "Smith equipped \[unique\] Frost Aegis .* res metal 0%, wood 0%, water 30%, fire 20%" p5_server.log
checkp "equip rare armour raises defense"         "Smith equipped \[rare\] .*chain_mail.*def (\d+) .*-> .*def (?!\1 )"  p5_server.log
check "resistance reduces live incoming damage"   "took [0-9]+ damage from .*\[Water res [0-9]+%\]"                  p5_server.log
check "resistances measurably cut damage (offline)" "40 water damage taken [0-9]+->[0-9]+"                            gear_selftest.log
check "unequip restores stats (offline)"          "unequip all: max hp ([0-9]+), attack ([0-9]+), water damage taken ([0-9]+) \(back to \1/\2/\3\)" gear_selftest.log
check "crafting an equipped item"                 "Smith used Orb of Transmutation on \[normal\] Copper Ring.*-> \[magic\].*equipped in ring1" p5_server.log
check "sell to the blacksmith"                    "Smith sold \[normal\] Leather Cap .* for [0-9]+ gold"            p5_server.log
check "selling away from the blacksmith rejected" "Smith sell rejected: you must be at the blacksmith"               p5_server.log
check "shared stash"                              "Smith stashed \[unique\] Gold Seeker's Ring"                      p5_server.log
check "drop item on the ground"                   "Smith dropped \[normal\] Sandals .* on the ground"               p5_server.log
check "destroy item"                              "Smith destroyed \[normal\] Cloth Wraps"                          p5_server.log
check "bag full: pickup refused"                  "FullBag can't pick up .*: bag full \(40/40\)"                     p5_server.log
check "bag full: unequip refused"                 "FullBag unequip rejected: your bag is full"                       p5_server.log
check "gear persists across restart (upgrade, rares, stash)" "Login 'Smith'.*restored save.*iron_sword\((normal|magic) \+[1-9][0-9]?\).*stash 1 \[copper_ring\(unique\)\]" p5b_server.log
check "equipment persists across restart"         "Login 'Smith'.*restored save.*equip \{.*offhand=frost_aegis\(unique\).*body=chain_mail\(rare\)" p5b_server.log
python3 - "$SAVE5" > $L/p5_stash.log <<'PY'
import json,sys
a=json.load(open(sys.argv[1]))["accounts"]["smith"]
print("account stash %d items, character stash key %s" % (len(a.get("stash",[])), "stash" in a.get("character",{})))
PY
check "stash is stored account-wide (not per character)" "account stash 1 items, character stash key False" p5_stash.log
echo; echo "== Dungeons (tickets, map device, instances, atlas)"
check "ticket merchant: daily free ticket"        "MapperA took the daily free ticket: \[magic\]"                p6_server.log
check "free ticket only once a day"               "MapperA free ticket rejected: you already took today's free ticket" p6_server.log
check "buy a ticket for gold"                     "MapperA bought \[normal\] Ember Caverns Ticket \(T1\) .* for 60 gold" p6_server.log
check "merchant tiers locked by the atlas"        "MapperA buy ticket rejected: the merchant only sells unlocked atlas nodes up to T5 \(Ember Caverns T9" p6_server.log
check "buying without gold rejected"              "Diver buy ticket rejected: not enough gold"                     p6_server.log
check "chisel adds quality (+IIQ)"                "MapperA used Cartographer's Chisel on .*q0, iiq \+0%.* -> .*q5, iiq \+5%"   p6_server.log
check "orbs add map mods (+IIQ/IIR)"              "MapperA used Orb of Transmutation on \[normal\] Ember Caverns Ticket.* -> \[magic\].*[12] mods" p6_server.log
check "regal makes a rare ticket"                 "MapperA used Regal Orb on \[magic\].* -> \[rare\] .*\(ticket_fire T1, 3 mods" p6_server.log
check "tickets can't be enhanced"                 "MapperA enhance rejected: Dungeon Tickets can't be enhanced"   p6_server.log
check "map device opens a private instance"       "\[dungeon\] MapperA opened Ember Caverns with .* -> instance dun[0-9]+ .*6 portals" p6_server.log
check "second player opens a separate instance"   "\[dungeon\] MapperB opened Forest Den with .* -> instance dun[0-9]+" p6_server.log
check "instance populated (packs, elites, boss)"  "dungeon Ember Caverns T1 .*populated: [0-9]+ packs \([1-9][0-9]* elite\), [0-9]+ monsters, boss Ember Tyrant" p6_server.log
check "themed procedural layouts (wood cave)"     "dungeon Forest Den T1 .*populated: .*boss Den Matriarch"       p6_server.log
check "map mods applied to monsters (unique map)" "dungeon Metal Forge T8 .*boss Forge Golem hp ([0-9]+) .*dmg x1\.30 .*map_mon_hp\": 60"  p6_server.log
check "entering uses a portal"                    "MapperA entered dun[0-9]+ .* - portals left 5"                 p6_server.log
check "solo: other players can't enter"           "Intruder can't enter dun[0-9]+: owned by"                      p6_server.log
check "client builds the instance locally"        "instance dun[0-9]+ built locally: Ember Caverns \(T1\)"      p6_MapperA.log
check "instance isolation: A sees only A"         "zone=dun[0-9]+ players=1 MapperA\("                           p6_MapperA.log
check "instance isolation: B sees only B"         "zone=dun[0-9]+ players=1 MapperB\("                           p6_MapperB.log
if grep -hE "zone=dun" $L/p6_*.log | grep -qE "foreign_entities=[1-9]"; then echo "FAIL  no entities leak between instances"; else echo "PASS  no entities leak between instances"; fi
check "two instances open at once"                "instances: dun[0-9]+\([a-z]+ T[0-9]+ .*\), dun[0-9]+\("     p6_server.log
check "map IIQ/IIR applied to drops"              "\[dun[0-9]+\] .* dropped: .*map/elite iiq \+[1-9][0-9]*% iir \+[0-9]+%" p6_server.log
check "elite bonus applied to drops"              "\[dun[0-9]+\] (Hasted|Armoured|Brutal|Regenerating) .* dropped: .*map/elite iiq \+[4-9][0-9]%" p6_server.log
check "tickets drop inside dungeons"              "\[dun[0-9]+\] .* dropped: .*\(ticket_[a-z]+ T[0-9]+, "           p6_server.log
check "death in a dungeon -> town"                "Diver died in dun[0-9]+ - back to town"                         p6_server.log
check "re-entry after death uses a portal"        "Diver entered dun[0-9]+ .* - portals left 4"                    p6_server.log
check "all 6 portals used up"                     "Diver entered dun[0-9]+ .* - portals left 0"                    p6_server.log
check "instance closes when portals run out"      "closing dun[0-9]+ .*owner Diver\): no portals left"            p6_server.log
check "boss kill completes the run"               "dun[0-9]+ COMPLETED Ember Caverns T1 \(boss Ember Tyrant slain by MapperA\)" p6_server.log
check "boss drops a next-tier ticket"             "COMPLETED .* tickets dropped: \[[a-z]+\] .*\(T2\)"         p6_server.log
check "completion banner on the client"           "banner: Dungeon Complete!"                                     p6_MapperA.log
check "atlas progress + merchant unlock"          "atlas MapperA: \{ \"fire:1\": 1 \} \(bonus \+1% iiq, merchant now sells up to T2\)" p6_server.log
check "completed instance times out + closes"     "closing dun[0-9]+ .*owner MapperA\): completion timeout"      p6_server.log
check "empty instance cleaned up"                 "closing dun[0-9]+ .*owner Idler\): empty for 15s"            p6_server.log
check "instance destroyed on all peers"           "instance dun[0-9]+ removed locally"                            p6_MapperA.log
check "dead instances freed on the server"        "instance dun[0-9]+ destroyed \(open instances: 0, zones: 4\)" p6_server.log
check "atlas persists across restart"             "Login atlas 'MapperA': \{ \"fire:1\": 1 \} \(completed nodes 1, dungeon iiq \+1%" p6b_server.log
check "atlas panel shows the progress"            "atlas panel opened: .*fire:1"                                  p6b_mappera.log
check "log back in town (never inside an instance)" "Login 'MapperA'.*zone meadow"                                p6b_server.log
check "dungeon offline checks"                    "dungeon selftest: all [0-9]+ checks passed"                    gear_selftest.log
echo; echo "== Trade market (Trade Broker)"
check "listing: fee charged, item into escrow"     "Sella listed #[0-9]+ \[rare\] .*chain_mail.* for 300 gold \(fee 6, gold left 2494" p7_server.log
check "currency stack listed with quantity"       "Sella listed #[0-9]+ 5 x orb_chaos for 120 gold \(fee 3"           p7_server.log
check "max active listings enforced"              "Sella list rejected: you already have 4 active listings \(max 4\)" p7_server.log
check "bad price rejected"                        "Sella list rejected: price must be 1-"                              p7_server.log
check "untradeable (bound starter gear) refused"  "Sella list rejected: .* is account-bound \(untradeable\)"          p7_server.log
check "listing fee needs gold"                    "Pauper list rejected: the listing fee is 10 gold \(you have 0\)"  p7_server.log
check "search: category + rarity"                 "Buyer searched \{cat=body rarity=rare\} -> 1 hit\(s\): #[0-9]+ \[rare\] .*chain_mail" p7_server.log
check "search: affix (res:water >= 25)"           "Buyer searched \{stat=res:water stat_min=25\} -> 1 hit\(s\): #[0-9]+ \[unique\] Frost Aegis" p7_server.log
check "search: name text"                         "Buyer searched \{text=ring\} -> 1 hit\(s\): #[0-9]+ \[normal\] Copper Ring" p7_server.log
check "search: currency category"                 "Buyer searched \{cat=currency\} -> 1 hit\(s\): #[0-9]+ 5 x orb_chaos" p7_server.log
check "search: price range + sort"                "Buyer searched \{price_max=100 sort=price_desc\} -> 1 hit\(s\): #[0-9]+ \[normal\] Copper Ring" p7_server.log
check "search: required level"                    "Buyer searched \{cat=ring max_req=5\} -> 1 hit"                  p7_server.log
check "search: ticket theme + tier"               "Buyer searched \{theme=water tier_min=3\} -> 1 hit\(s\): #[0-9]+ \[rare\] .*ticket_water T3" p7_server.log
check "search: usable by class"                   "Buyer searched \{cat=offhand usable=true\} -> 1 hit"             p7_server.log
if python3 -c "import re,sys; m=re.search(r'Buyer searched \{sort=newest\} -> 5 hit\(s\): (.*)', open('$L/p7_server.log').read()); ids=[int(x) for x in re.findall(r'#(\d+) ', m.group(1))] if m else []; sys.exit(0 if len(ids)==5 and ids==sorted(ids, reverse=True) else 1)"; then echo "PASS  search: newest first (all listings)"; else echo "FAIL  search: newest first (all listings)"; fi
check "client receives result pages"              "market page: 1 hit\(s\), page 1/1: #[0-9]+ \[rare\]"           p7_Buyer.log
check "buy: gold moves, 5% tax, seller credited"  "Buyer bought #[0-9]+ \[rare\] .*chain_mail.* from Sella for 300 gold \(tax 15, seller gets 285 into the claim box; buyer gold left 2200; seller online\)" p7_server.log
check "online seller notified"                    "notice: \[Market\] Your .* sold to Buyer for 300 gold \(285 after 5% tax\)" p7_Sella.log
check "self-buy rejected"                         "Sella buy #[0-9]+ rejected: you can't buy your own listing"        p7_server.log
check "not enough gold rejected"                  "Pauper buy #[0-9]+ rejected: not enough gold \(0/900\)"          p7_server.log
check "full bag rejected"                         "FullBag buy #[0-9]+ rejected: your bag is full"                     p7_server.log
if [ "$(grep -cE "Race[AB] bought #[0-9]+ \[normal\] Copper Ring" $L/p7_server.log)" = 1 ] && grep -qE "Race[AB] buy #[0-9]+ rejected: that listing is gone" $L/p7_server.log; then echo "PASS  two buyers race one listing: exactly one wins"; else echo "FAIL  two buyers race one listing: exactly one wins"; fi
check "cancel returns the item"                   "Expo cancelled #[0-9]+ \[normal\] Leather Cap .* -> bag"          p7_server.log
check "expired listing -> claim box"              "listing #[0-9]+ \(.*ticket_water T3.* by Expo\) expired -> returned to the seller's claim box" p7_server.log
check "claim box returns the expired item"        "Expo claimed 0 gold and 1 item\(s\) \[\[rare\] .*ticket_water T3"  p7_server.log
check "offline seller's sale goes to the claim box" "Buyer bought #[0-9]+ 5 x orb_chaos from Sella for 120 gold \(tax 6, seller gets 114 .*seller offline\)" p7_server.log
check "market persists across restart"            "\[market\] loaded accounts_p7_market\.json: 1 active listing\(s\), 1 claim box"         p7b_server.log
check "offline seller told on next login"         "notice: \[Market\] While you were away: 447 gold"                 p7b_Sella.log
check "offline seller collects the gold"          "Sella claimed 447 gold .* \(gold now 2919,"                        p7b_server.log
check "empty claim box rejected"                  "Sella claim rejected: your claim box is empty"                      p7b_server.log
check "bought item kept after restart"            "Login 'Buyer'.*restored save.*gold 2080.*chain_mail\(rare\)"     p7b_server.log
check "unsold listing still listed after restart" "Sella searched \{\} -> 1 hit\(s\): #[0-9]+ \[unique\] Frost Aegis"  p7b_server.log
check "no item duplication (uid audit)"           "duplicates: none"                                                    p7_audit.log
check "gold conserved (fees + tax are the only sink)" "CONSERVED$"                                                   p7_audit.log
check "crash test: trade happened before kill -9" "Snatcher bought #[0-9]+"                                            p7c_server.log
check "crash test: no duplication after restart"  "duplicates: none"                                                    p7c_audit.log
check "crash test: gold conserved after restart"  "CONSERVED$"                                                        p7c_audit.log
check "free daily ticket refused (untradeable)"   "Expo list rejected: .*Ticket.* is account-bound \(untradeable\)"   p7_server.log
if [ -s $L/accounts_p7_market.json ] && ! grep -q '"listings"' $L/accounts_p7.json; then echo "PASS  market saved to its own file (*_market.json, not accounts.json)"; else echo "FAIL  market saved to its own file (*_market.json, not accounts.json)"; fi
check "crash between writes: trade committed to market.json" "CRASH TEST: dying between market.json"           p7e_server.log
check "crash between writes: journal replayed on restart"     "recovered: accounts.json was at tx [0-9]+, market at tx [0-9]+ - replayed the journal for \[.*snatcher" p7f_server.log
if python3 - "$L/p7e_server.log" "$L/p7e_accounts_before_restart.json" "$SAVE7E" <<'PYC'
import json, re, sys
m = re.search(r"Snatcher bought #\d+ .*?\((\w+) ilvl", open(sys.argv[1]).read())
n = lambda f: sum(1 for i in json.load(open(f))["accounts"]["snatcher"]["character"]["bag"] if m and i.get("base") == m.group(1))
sys.exit(0 if m and n(sys.argv[3]) == n(sys.argv[2]) + 1 else 1)
PYC
then echo "PASS  crash between writes: trade missing from accounts.json on disk, buyer has the item after restart"; else echo "FAIL  crash between writes: trade missing from accounts.json on disk, buyer has the item after restart"; fi
check "crash between writes: no duplication"                 "duplicates: none"                                   p7e_audit.log
check "crash between writes: gold conserved"                 "CONSERVED$"                                         p7e_audit.log
check "market offline checks"                     "market selftest: all [0-9]+ checks passed"                           gear_selftest.log
echo; echo "== Atlas (PoE-style map + atlas passive tree)"
check "atlas offline checks (graph, rules, migration, effects)" "atlas selftest: all [0-9]+ checks passed"      atlas_selftest.log
check "effects measured: ticket drops / tier / currency / portals" "ATLAS SELFTEST effects over 20000 kills .*ticket drops ([0-9]+) -> ([0-9]+), higher-tier tickets 0 -> [1-9]" atlas_selftest.log
check "boss tickets favour adjacent nodes (offline)" "boss tickets: 1[1-4][0-9][0-9]/2000 for adjacent" atlas_selftest.log
check "locked node can't be run"                "Atlasa open dungeon rejected: atlas node Smouldering Pit - Ember Caverns T3 is locked"  p8_server.log
check "no atlas points: allocation rejected"     "Atlasa atlas passive a_ring_water rejected: no atlas points left"   p8_server.log
check "T1 node opens (starting node)"            "Atlasa opened Ember Caverns .*atlas node Cinder Throat - Ember Caverns T1"   p8_server.log
check "node has a fixed layout seed"             "Atlasa opened Ember Caverns .*\(seed 136405, "                     p8_server.log
check "first completion grants a point"          "atlas node fire:1 completed by Atlasa: .*first completion \+1"     p8_server.log
check "bonus objective (rare ticket) grants a point" "atlas node fire:1 completed by Atlasa: bonus objective 'rare' MET .*bonus objective \+1.* -> 2 earned" p8_server.log
check "boss ticket for an adjacent node (live)"  "atlas node fire:1 completed .*boss tickets for nodes \[\"fire:2 \(adjacent\)"   p8_server.log
check "passive adjacency enforced"               "Atlasa atlas passive a_metal_5 rejected: .* is not connected"      p8_server.log
check "atlas passive allocated"                  "Atlasa allocated atlas passive Tidal Gate \[a_water_1\] .*2/2 atlas points spent" p8_server.log
check "points cap enforced"                      "Atlasa atlas passive a_fire_1 rejected: no atlas points left"       p8_server.log
check "adjacent node unlocked at the merchant"   "Atlasa bought \[normal\] Ember Caverns Ticket \(T2\)"            p8_server.log
check "merchant refuses locked nodes"            "Atlasa buy ticket rejected: the merchant only sells unlocked atlas nodes .*T3: atlas node locked" p8_server.log
check "extra portal passive applied (7 portals)" "Atlasa opened Ember Caverns .*: 7 portals, .*atlas node Ashen Gallery - Ember Caverns T2, atlas passives \{.*portals 1" p8_server.log
check "atlas respec for gold"                    "Atlasa reset the atlas passive tree: refunded 2 points for 300 gold" p8_server.log
check "respec with nothing allocated rejected"   "Atlasa atlas respec rejected: no atlas passives allocated"          p8_server.log
check "atlas persists across restart (points, bonus, passives)" "Login atlas 'Atlasa': \{ \"fire:1\": 1 \}.*bonus \[\"fire:1\"\], atlas points 2 earned / 1 spent, passives \[\"a_ring_fire\"\]" p8b_server.log
check "old atlas grid migrated to map nodes"     "\[atlas\] Oldmapper: migrated old atlas grid .*\(remapped \[\"water:4->water:3\", \"metal:9->metal:7\"\]\), 5 atlas points" p8b_server.log
check "migrated nodes unlock their neighbours"   "atlas panel opened: .*available \[.*\"water:5\""                 p8b_Oldmapper.log
check "atlas panel lists node states"            "atlas panel opened: .*31 nodes: completed \[\"fire:1\"\], available"   p8b_Atlasa.log
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
echo; echo "== Hideout"
check "Hideout Master in town opens the panel"          "hideout bot: at the Hideout Master, panel open"         p10_bot.log
check "buy decorations with gold"                       "Decor bought 2 x Pine Tree for 240 gold"                p10_server.log
check "buy rejected without gold"                       "buy decoration rejected: not enough gold"               p10_server.log
check "unknown decoration rejected"                     "rejected: unknown decoration 'bogus'"                   p10_server.log
check "editing outside the hideout rejected"            "Decor hideout place rejected: you must be in your hideout" p10_server.log
check "/hideout creates + enters a private instance"    "created ho[0-9]+ for Decor .*Decor enters ho|Decor enters ho[0-9]+ \(from meadow\)" p10_server.log
check "client is in its hideout zone"                   "hideout bot: entered my hideout via /hideout \| zone ho[0-9]+" p10_bot.log
check "place decorations (decoration mode clicks)"      "Decor placed Ancestor Statue at \(28, 14\)"           p10_server.log
check "placement blocking the door rejected"            "place rejected: \(31, 27\) would block the door"      p10_server.log
check "placement outside the room rejected"             "place rejected: \(5, 5\) is outside the hideout"      p10_server.log
check "placement on a station rejected"                 "place rejected: .*too close to the Map Device"          p10_server.log
check "placing unowned decorations rejected"            "you have no unplaced Snow Guardian"                     p10_server.log
check "pick up + move a decoration"                     "moved Ancestor Statue #[0-9]+ \(28, 14\) -> \(27, 13\)" p10_server.log
check "move onto the door rejected"                     "move rejected: \(32, 26\) would block the door"       p10_server.log
check "rotate + flip"                                   "rotated .* to 90 deg"                                   p10_server.log
check "flip"                                            "flipped .*flip true"                                    p10_server.log
check "remove (back to inventory)"                      "removed Pine Tree #[0-9]+ \(back to the decoration inventory\)" p10_server.log
check "move a station"                                  "moved the Trade Broker to \(21, 26\)"                 p10_server.log
check "station on the door rejected"                    "station rejected: \(31, 26\) would block the door"   p10_server.log
check "theme switch keeps decorations"                  "switched the theme to Ember Forge \(kept [0-9]+ decorations" p10_server.log
check "locked theme rejected"                           "Lotus Lake is locked"                                   p10_server.log
check "client rebuilt the themed hideout"               "client zone theme fire, [1-9][0-9]* decoration sprites" p10_bot.log
check "200-decoration limit enforced"                   "placed Frost Boulder at .* 200/200 decorations"         p10_server.log
check "201st decoration rejected"                       "the hideout is full \(200/200 decorations\)"          p10_server.log
check "hideout Ticket Merchant works"                   "\[ho[0-9]+\] Decor took the daily free ticket"         p10_server.log
check "Map Device in the hideout opens a map"           "Decor opened a map from ho[0-9]+"                       p10_server.log
check "dungeon exit portal leads to the hideout"        "inside the dungeon opened from the hideout \(zone dun[0-9]+, exit portal -> ho" p10_bot.log
check "dungeon portal returns to the hideout"           "Zone transfer: Decor dun[0-9]+ -> ho[0-9]+"             p10_server.log
check "logout in the hideout restores there"            "Login 'Decor': restoring into the hideout"              p10b_server.log
check "layout survives a server restart"                "logged back in \(restart\) \| zone ho[0-9]+, theme fire, .*5/200 decorations" p10b_bot.log
check "door back to Sunny Meadow"                       "left the hideout through the door \| zone meadow"      p10b_bot.log
check "/hideout from town after restart"                "back via /hideout \| zone ho[0-9]+, theme fire"        p10b_bot.log
echo; echo "== Errors/warnings (should be none):"
grep -iE "SCRIPT ERROR|^ERROR|^WARNING" $L/*.log | sort | uniq -c | head -40 || true
grep -qiE "SCRIPT ERROR|^ERROR|^WARNING" $L/*.log || echo "none"
