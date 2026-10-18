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
rm -f $L/*_vendor.json $L/*.tmp
# Ports: everything uses $PORT (default 7920, away from the usual 7777 and other testers' 7790);
# the parallel boss trial uses $PORT+21..+25. Override with PORT=... ./run_local_test.sh
PORT="${PORT:-7920}"
run() { "$GODOT" --headless --path . -- "$@" --port=$PORT; }

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

"$GODOT" --headless --path . -- --bigmap-selftest > $L/bigmap_selftest.log 2>&1
echo "Phase 3 (~130s)..."
run --server --save-file="$SAVE3" --debug-start-level=20 --fast-respawn --allow-warp --quit-after=130 > $L/p3_server.log 2>&1 &
sleep 2
run --join=127.0.0.1 --name=Walker --password=w --class=wood --bot --bot-route=forest,crypt,frost,crypt,forest,meadow --bot-dwell=4 --quit-after=124 > $L/p3_walker.log 2>&1 &
# a crypt camp (crawler + archers + ghost): wiped and respawned as a group, so every overworld crypt type is seen respawning
CCAMP=$(grep -E "BIGMAP SELFTEST crypt +camps at" $L/bigmap_selftest.log | sed -E 's/.*camps at ([0-9]+),([0-9]+).*/\1,\2/' | awk -F, '{print $1 "," $2+3}')
run --join=127.0.0.1 --name=CryptCamper --password=w --class=fire --bot --warp=crypt --warp-cell=$CCAMP --quit-after=124 > $L/p3_crypt_camper.log 2>&1 &
# a frost bat pack: wiped and respawned as a group (the hunters only pass by frost bats, so their respawn was chance-based)
FBAT=$(grep -E "BIGMAP SELFTEST frost +packs " $L/bigmap_selftest.log | grep -oE "frost_bat@[0-9]+,[0-9]+" | head -1 | sed -E 's/frost_bat@//' | awk -F, '{print $1 "," $2+3}')
run --join=127.0.0.1 --name=FrostCamper --password=w --class=fire --bot --warp=frost --warp-cell=$FBAT --quit-after=124 > $L/p3_frost_camper.log 2>&1 &
# a forest Cave Bat pack: overworld cave bats otherwise only respawn if phase-4 bots happen to wipe a bat pack
CBAT=$(grep -E "BIGMAP SELFTEST forest +packs " $L/bigmap_selftest.log | grep -oE " bat@[0-9]+,[0-9]+" | head -1 | sed -E 's/ bat@//' | awk -F, '{print $1 "," $2+3}')
run --join=127.0.0.1 --name=BatCamper --password=w --class=water --bot --warp=forest --warp-cell=$CBAT --quit-after=124 > $L/p3_bat_camper.log 2>&1 &
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
run --server --save-file="$SAVE4" --debug-start-level=20 --debug-level-for=MetalA:22 --debug-loot --fast-respawn --allow-warp --quit-after=76 > $L/p4_server.log 2>&1 &
sleep 2
b4() { n=$1; shift; run --join=127.0.0.1 --name=$n --password=t --bot --bot-no-gear "$@" --quit-after=70 > $L/p4_$n.log 2>&1 & }
b4 MetalA --class=metal --bot-talents=goals:m_bloodthirst,m_bladestorm --bot-target=far --bot-hunt=boss --warp=crypt --warp-cell=26,18
b4 MetalB --class=metal --bot-talents=auto:1 --warp=forest
b4 WoodA  --class=wood  --bot-talents=auto:0 --bot-aim --warp=forest
b4 WoodB  --class=wood  --bot-talents=auto:1 --warp=crypt
b4 WaterA --class=water --bot-talents=goals:a_siphon,a_zero --bot-aim --bot-target=far --bot-hunt=boss --warp=frost --warp-cell=180,28
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

echo "Phase 5 (~70s): gear, crafting, blacksmith..."
SAVE5="$(pwd)/$L/accounts_p5.json"; rm -f "$SAVE5"
run --server --save-file="$SAVE5" --debug-start-level=13 --debug-gear --debug-full-bag=Full --debug-loot --allow-warp --craft-seed=7 --quit-after=70 > $L/p5_server.log 2>&1 &
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

echo "Phase 6 (~200s): dungeon tickets, map device, instances, atlas..."
SAVE6="$(pwd)/$L/accounts_p6.json"; rm -f "$SAVE6"
run --server --save-file="$SAVE6" --debug-start-level=20 --debug-gear --debug-fresh=Diver --fast-respawn --instance-timeout=15 --complete-timeout=15 --debug-next-tier=1 --ticket-drop-chance=0.12 --quit-after=200 > $L/p6_server.log 2>&1 &
sleep 2
b6() { n=$1; shift; run --join=127.0.0.1 --name=$n --password=d "$@" --quit-after=194 > $L/p6_$n.log 2>&1 & }
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
"$GODOT" --headless --path . -- --port=$PORT --host --name=Solo --password=s --class=fire --bot-idle --menu-test --menu-test-leave=quit --save-file="$SAVE9" --quit-after=40 > $L/p9_host.log 2>&1
# 9b: client of a dedicated server: the game continues online, input stops; then Return to Main Menu
run --server --save-file="$SAVE9" --debug-start-level=5 --quit-after=30 > $L/p9b_server.log 2>&1 &
sleep 2
run --join=127.0.0.1 --name=Online --password=o --class=water --bot --menu-test --menu-test-leave=menu --quit-after=26 > $L/p9b_client.log 2>&1 &
wait
# 9c: a player joins a host whose menu is open -> the host unpauses
"$GODOT" --headless --path . -- --port=$PORT --host --name=Solo --password=s --bot-idle --open-menu=4 --save-file="$SAVE9" --quit-after=22 > $L/p9c_host.log 2>&1 &
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

echo "Phase 11 (~25s): client performance in Whisperwood (entrance + boss lair, 200x128 map)..."
SAVE11="$(pwd)/$L/accounts_p11.json"; rm -f "$SAVE11"
run --server --save-file="$SAVE11" --debug-start-level=20 --allow-warp --fast-respawn --quit-after=24 > $L/p11_server.log 2>&1 &
sleep 2
CAMP=$(grep -E "BIGMAP SELFTEST forest +camps at" $L/bigmap_selftest.log | sed -E 's/.*camps at ([0-9]+),([0-9]+).*/\1,\2/' | awk -F, '{print $1 "," $2+3}')
run --join=127.0.0.1 --name=Camper --password=b --class=fire --bot --warp=forest --warp-cell=$CAMP --quit-after=20 > $L/p11_camper.log 2>&1 &
run --join=127.0.0.1 --name=BenchA --password=b --class=metal --bot-idle --warp=forest --bench=8 --quit-after=20 > $L/p11_bench_entrance.log 2>&1 &
run --join=127.0.0.1 --name=BenchB --password=b --class=earth --bot-idle --warp=forest --warp-cell=178,100 --bench=8 --quit-after=20 > $L/p11_bench_lair.log 2>&1 &
wait

echo "Phase 12 (~130s): Guardian kill unlocks a hideout theme (no unlock-all flag), boss decoration drop, Esc-menu Hideout button, patrols walk their routes..."
SAVE12="$(pwd)/$L/accounts_p12.json"; rm -f "$SAVE12"
run --server --save-file="$SAVE12" --allow-warp --debug-start-level=40 --debug-gear --debug-atlas-kit --decor-drop-chance=1 --instance-timeout=15 --complete-timeout=10 --quit-after=130 > $L/p12_server.log 2>&1 &
sleep 2
run --join=127.0.0.1 --name=Warden --password=g --class=fire --bot --bot-dungeon=full --bot-guardian=fire:10 --quit-after=124 > $L/p12_guardian.log 2>&1 &
run --join=127.0.0.1 --name=Watcher --password=g --class=metal --bot-idle --bot-watch-patrol --quit-after=124 > $L/p12_watcher.log 2>&1 &
run --join=127.0.0.1 --name=MenuHo --password=g --class=water --bot-idle --menu-hideout-test --quit-after=20 > $L/p12_menuho.log 2>&1 &
wait

echo "Phase 13 (~40s): Play Solo (one click, in-process local server, no login, profile slot saved)..."
SAVE13="$(pwd)/$L/solo_profile.json"; rm -f "$SAVE13"
# 13a: click the menu's Play Solo button once (headless): a new hero in profile slot 2
"$GODOT" --headless --path . -- --port=$PORT --click-solo --solo-slot=2 --name=Soloist --class=wood --bot --save-file="$SAVE13" --quit-after=16 > $L/p13_solo.log 2>&1 &
sleep 8
# nobody can join a solo game (bound to 127.0.0.1, peers refused)
run --join=127.0.0.1 --name=Crasher --password=x --bot-idle --quit-after=5 > $L/p13_joiner.log 2>&1
wait
# 13b: Play Solo again: the same slot is restored (level, class), no password asked
"$GODOT" --headless --path . -- --port=$PORT --click-solo --solo-slot=2 --bot-idle --save-file="$SAVE13" --quit-after=8 > $L/p13_solo_again.log 2>&1

echo "Phase 14 (~120s): online co-op party: invite/accept, both enter the leader's dungeon and clear it together..."
SAVE14="$(pwd)/$L/accounts_p14.json"; rm -f "$SAVE14"
run --server --save-file="$SAVE14" --debug-start-level=20 --debug-gear --instance-timeout=15 --complete-timeout=12 --quit-after=120 > $L/p14_server.log 2>&1 &
sleep 2
b14() { n=$1; shift; run --join=127.0.0.1 --name=$n --password=p --bot --bot-no-gear "$@" --quit-after=114 > $L/p14_$n.log 2>&1 & }
b14 Leader --class=fire --bot-dungeon=full --bot-dungeon-theme=fire --bot-party=invite:Member
b14 Member --class=water --bot-dungeon=party --bot-party=accept
sleep 20
b14 Outsider --class=metal --bot-dungeon=intrude
# version handshake: a client of another build is refused with a clear message; a peer that skips it is ignored + dropped
run --join=127.0.0.1 --name=OldBuild --password=p --bot --fake-version=volam-old --quit-after=10 > $L/p14_oldbuild.log 2>&1
run --join=127.0.0.1 --name=NoHello --password=p --bot --skip-handshake --quit-after=10 > $L/p14_nohello.log 2>&1
wait

echo "Phase 15 (~75s): NPC vendor (sell loot, buy from the rotating stock, persistence, rotation timer)..."
SAVE15="$(pwd)/$L/accounts_p15.json"; rm -f "$SAVE15"
run --server --save-file="$SAVE15" --debug-start-level=10 --debug-gear --debug-fresh=Pauper --debug-full-bag=Full --debug-loot --quit-after=30 > $L/p15_server.log 2>&1 &
sleep 2
b15() { n=$1; shift; run --join=127.0.0.1 --name=$n --password=v "$@" --quit-after=26 > $L/p15_$n.log 2>&1 & }
b15 Shopper --class=metal --bot --bot-no-gear --bot-vendor=1
b15 Pauper --class=fire --bot --bot-no-gear --bot-vendor=1 --bot-vendor-role=probe
b15 FullBag --class=earth --bot --bot-no-gear --bot-vendor=1 --bot-vendor-role=probe
wait
cp $L/accounts_p15_vendor.json $L/p15_vendor_before_restart.json
run --server --save-file="$SAVE15" --quit-after=14 > $L/p15b_server.log 2>&1 &
sleep 2
run --join=127.0.0.1 --name=Shopper --password=v --bot --bot-no-gear --bot-vendor=2 --quit-after=10 > $L/p15b_Shopper.log 2>&1 &
wait
# a short rotation period: the stock rotates on the timer while the server runs
run --server --save-file="$SAVE15" --vendor-rotate=6 --quit-after=16 > $L/p15c_server.log 2>&1

echo "Phase 16 (~50s): first-time tutorial (movement, skills, loot, equip, passive web; skip; shown once)..."
SAVE16="$(pwd)/$L/accounts_p16.json"; rm -f "$SAVE16"
run --server --save-file="$SAVE16" --debug-level-for=UiTest:10 --quit-after=36 > $L/p16_server.log 2>&1 &
sleep 2
run --join=127.0.0.1 --name=Newbie --password=t --class=earth --bot --bot-no-gear --bot-tutorial=full --quit-after=32 > $L/p16_Newbie.log 2>&1 &
run --join=127.0.0.1 --name=UiTest --password=t --class=earth --bot --bot-idle --ui-selftest --quit-after=16 > $L/p16_UiTest.log 2>&1 &
run --join=127.0.0.1 --name=Skipper --password=t --class=water --bot --bot-tutorial=skip --quit-after=32 > $L/p16_Skipper.log 2>&1 &
wait
run --server --save-file="$SAVE16" --quit-after=14 > $L/p16b_server.log 2>&1 &
sleep 2
run --join=127.0.0.1 --name=Newbie --password=t --bot --bot-tutorial=full --quit-after=10 > $L/p16b_Newbie.log 2>&1 &
run --join=127.0.0.1 --name=Skipper --password=t --bot --bot-tutorial=skip --quit-after=10 > $L/p16b_Skipper.log 2>&1 &
wait

echo "Phase 17 (~50s): party XP share (a member next to the kill gets the XP, one far away does not)..."
SAVE17="$(pwd)/$L/accounts_p17.json"; rm -f "$SAVE17"
run --server --save-file="$SAVE17" --allow-warp --quit-after=50 > $L/p17_server.log 2>&1 &
sleep 2
run --join=127.0.0.1 --name=XpLead --password=p --class=fire --bot --bot-no-gear --bot-party=invite:XpNear,XpFar --quit-after=46 > $L/p17_XpLead.log 2>&1 &
run --join=127.0.0.1 --name=XpNear --password=p --class=water --bot --bot-follow=XpLead --bot-party=accept --quit-after=46 > $L/p17_XpNear.log 2>&1 &
run --join=127.0.0.1 --name=XpFar --password=p --class=earth --bot --bot-idle --bot-party=accept --warp=meadow --warp-cell=20,64 --quit-after=46 > $L/p17_XpFar.log 2>&1 &
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
if grep -qhE "foreign_entities=[1-9]" $(ls $L/*.log | grep -vE "_host.log|p13_solo"); then echo "FAIL  visibility isolation (client received other-zone entities)"; else echo "PASS  visibility isolation (no client ever received another zone's entities)"; fi
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
for f in p11_bench_entrance p11_bench_lair; do
  l=$(grep -h "^BENCH zone=forest" $L/$f.log | head -1)
  if [ -n "$l" ] && echo "$l" | awk '{for(i=1;i<=NF;i++){split($i,kv,"="); v[kv[1]]=kv[2]} exit !(v["frame_ms"]<16.7 && v["physics_ms"]<4 && v["nodes"]<1500 && v["monsters_here"]<40)}'; then
    echo "PASS  Whisperwood client perf ${f#p11_bench_}: $(echo "$l" | grep -oE " (frame_ms|physics_ms|nodes|monsters_here)=[0-9.]+" | paste -sd' ')"
  else echo "FAIL  Whisperwood client perf ${f#p11_bench_} (frame_ms<16.7 physics_ms<4 nodes<1500 monsters_here<40): $l"; fi
done
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
            "FireA:Meteor.*cd 10.0s" "FireB:Fireball.*cd 2.1s, x2.61" "EarthA:Mountain's Challenge.*cd 8.4s" "EarthB:Ground Slam.*cd 2.5s, x2.18"; do
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
check "selling away from the blacksmith rejected" "Smith sell rejected: you must be at the vendor or the blacksmith"               p5_server.log
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
check "elite bonus applied to drops"              "\[dun[0-9]+\] (Hasted|Armoured|Brutal|Regenerating) .* dropped: .*map/elite iiq \+([4-9][0-9]|[1-9][0-9]{2,})%" p6_server.log
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
check "move a station"                                  "moved the Vendor to \(21, 26\)"                 p10_server.log
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
check "hideout door works with E"                       "Decor used the hideout door \(E\)"                     p10b_server.log
check "logout in the hideout restores there"            "Login 'Decor': restoring into the hideout"              p10b_server.log
check "layout survives a server restart"                "logged back in \(restart\) \| zone ho[0-9]+, theme fire, .*5/200 decorations" p10b_bot.log
check "door back to Sunny Meadow"                       "left the hideout through the door \| zone meadow"      p10b_bot.log
check "/hideout from town after restart"                "back via /hideout \| zone ho[0-9]+, theme fire"        p10b_bot.log
check "Guardian test starts without the theme"         "dungeon bot: asking for a debug fire:10 ticket, hideout themes \[\"meadow\"\]" p12_guardian.log
check "Guardian ticket opened (fire:10)"                "Warden opened Ember Caverns .*Ember Caverns T10"                 p12_server.log
check "killing the Fire Guardian unlocks Ember Forge"   "Warden unlocked the hideout theme Ember Forge \(slew the Guardian" p12_server.log
check "boss decoration drop (forced chance 1.0)"        "Warden found a decoration: .* \(dungeon boss drop\) - owned [1-9]" p12_server.log
if python3 - "$SAVE12" "$L/p12_server.log" <<'PY'
import json, re, sys
ho = json.load(open(sys.argv[1]))["accounts"]["warden"]["character"]["hideout"]
m = re.search(r"Warden found a decoration: (.+?) \(dungeon boss drop\) - owned (\d+)", open(sys.argv[2]).read())
names = {n: k for k, n in re.findall(r'"([a-z_]+)":\s*\{"name":\s*"([^"]+)"', open("scripts/hideout.gd").read())}
did = names.get(m.group(1)) if m else None
print("      saved hideout: unlocked %s, owned %s (boss drop %s)" % (ho["unlocked"], ho["owned"], did))
sys.exit(0 if m and did and int(ho["owned"].get(did, 0)) == int(m.group(2)) and "fire" in ho["unlocked"] else 1)
PY
then echo "PASS  drop lands in owned decorations + theme saved"; else echo "FAIL  drop lands in owned decorations + theme saved"; fi
check "Esc menu Hideout button clicked (UI)"            "menu hideout test: clicking the Esc menu's Hideout button"       p12_menuho.log
check "the click fired the menu's Hideout action"       "\[menu\] Hideout pressed"                                      p12_menuho.log
check "server took the button press"                    "MenuHo enters ho[0-9]+ \(from meadow\)"                          p12_server.log
check "client entered its hideout via the button"       "menu hideout test: ENTERED the hideout - zone ho[0-9]+, Esc menu closed" p12_menuho.log
echo; echo "== Overworld patrols"
check "watcher stands by a patrol route"                "patrol watch: standing at cell"                                  p12_watcher.log
if awk '/patrol #[0-9]+ patrol of .* reached site [12]\/3/ { match($0, /#[0-9]+/); id = substr($0, RSTART, RLENGTH);
      match($0, /reached site [12]/); s = substr($0, RSTART + 13, 1);
      match($0, /leader [0-9]+ px/); d = substr($0, RSTART + 7, RLENGTH - 10) + 0;
      match($0, /nearest player [0-9]+ px/); p = substr($0, RSTART + 15, RLENGTH - 18) + 0;
      if (p < 1500 && d > 300) seen[id "," s] = 1 }
    END { for (k in seen) { split(k, a, ","); if (seen[a[1] ",1"] && seen[a[1] ",2"]) ok = 1 } exit !ok }' $L/p12_server.log; then
  echo "PASS  a patrol walks between its sites ($(grep -cE "patrol #[0-9]+ .* reached site [12]/3" $L/p12_server.log) waypoints reached with a player in range)"
else echo "FAIL  a patrol walks between its sites"; fi
echo; echo "== Play Solo (M2)"
check "Play Solo clicked once on the main menu"        "menu test: clicking Play Solo \(Slot 2 - empty"                 p13_solo.log
check "in-process local server, no login step"         "Solo \(local, in-process\) server listening on port [0-9]+"      p13_solo.log
check "new local profile slot created (no password)"   "Created local profile slot 2 for 'Soloist'"                       p13_solo.log
check "solo hero spawned in the world"                 "Login 'Soloist' \(peer 1\): NEW account - class wood"           p13_solo.log
check "solo game saved to the local profile"           "Saved .*solo_profile.json \(shutdown\)"                         p13_solo.log
check "other players can't join a solo game"           "Solo game: refusing peer [0-9]+"                                  p13_solo.log
check "solo slot restored on the next Play Solo"       "menu test: clicking Play Solo \(Slot 2 - Soloist, Venom Druid Lv[0-9]+\)" p13_solo_again.log
check "solo progress restored (class, level)"          "Login 'Soloist' \(peer 1\): restored save - class wood"         p13_solo_again.log
echo; echo "== Party co-op dungeons (M2)"
check "party invite sent"                              "\[party\] Leader invited Member"                                  p14_server.log
check "invite to an offline name rejected"             "\[party\] Leader invite rejected: 'Nobody' is not online"        p14_server.log
check "accept without an invite rejected"              "\[party\] Leader accept rejected: you have no pending party invite" p14_server.log
check "party formed"                                   "\[party\] Member joined Leader's party #[0-9]+: Leader \(leader\), Member" p14_server.log
check "party panel follows members into the dungeon"     "party state: 2 member.* zones: Leader@dun[0-9]+ Member@dun[0-9]+"   p14_Member.log
check "member's HUD gets the party"                    "party state: 2 member\(s\) \[Leader, Member\], leader Leader"   p14_Member.log
check "leader opens the dungeon"                       "\[dungeon\] Leader opened Ember Caverns"                          p14_server.log
check "party member enters the leader's instance"      "\[dungeon\] Member entered (dun[0-9]+)"                           p14_server.log
check "non-member still refused"                       "Outsider can't enter dun[0-9]+: owned by Leader \(not in their party\)" p14_server.log
check "both players in the same instance"              "zone=dun[0-9]+ players=2 .*(Leader|Member)\(.*(Leader|Member)\("  p14_Member.log
if grep -qE "\[dun[0-9]+\] .* was slain by Member" $L/p14_server.log && grep -qE "\[dun[0-9]+\] .* was slain by Leader" $L/p14_server.log; then echo "PASS  both party members kill monsters in the instance ($(grep -cE "\[dun[0-9]+\] .* was slain by Member" $L/p14_server.log) by Member, $(grep -cE "\[dun[0-9]+\] .* was slain by Leader" $L/p14_server.log) by Leader)"; else echo "FAIL  both party members kill monsters in the instance"; fi
check "dungeon cleared by the party"                   "dun[0-9]+ cleared by a party of 2: "                                 p14_server.log
check "boss kill completes the party run"              "dun[0-9]+ COMPLETED Ember Caverns T1"                               p14_server.log
check "version handshake accepted (same build)"        "Version volam-m2\.[0-9]+ accepted by the server, logging in"  p14_Member.log
check "other build refused with a clear message"       "Login rejected: Version mismatch: server volam-m2\.[0-9]+, you volam-old"  p14_oldbuild.log
check "server logged the refused version"              "Peer [0-9]+ refused: Version mismatch"                         p14_server.log
check "login without a handshake ignored"              "Ignored login from peer [0-9]+: no accepted version handshake" p14_server.log
check "peer without a handshake disconnected"          "Peer [0-9]+ sent no version handshake in 4s .* disconnected"   p14_server.log
if grep -q "checksum failed" $L/p14_*.log; then echo "FAIL  no rpc checksum errors from the version test"; else echo "PASS  no rpc checksum errors from the version test"; fi
check "member sees the completion banner"              "banner: Dungeon Complete!"                                          p14_Member.log
echo; echo "== NPC vendor (M2, replaces the player market)"
check "vendor stock rolled and saved"                 "\[vendor\] stock rotated \(first stock\): rotation [0-9]+, day [0-9-]+, 12 entries"   p15_server.log
check "vendor panel opened at the Vendor (E)"         "vendor panel opened"                                                p15_Shopper.log
check "client receives the stock"                     "vendor stock: 12 entries, next rotation in [0-9]+s"                p15_Shopper.log
check "buy potions (gold -> stack)"                   "\[vendor\] Shopper bought 3 x health_potion for 30 gold"         p15_server.log
check "buy gear from the stock"                       "\[vendor\] Shopper bought \[(normal|magic|rare)\] .* for [0-9]+ gold .*0 left in stock" p15_server.log
check "sold-out entry rejected"                       "\[vendor\] Shopper buy rejected: .* is sold out"                  p15_server.log
check "unknown stock id rejected"                     "\[vendor\] Shopper buy rejected: that item is not in stock"      p15_server.log
check "sell loot to the vendor for gold"              "Shopper sold \[[a-z]+\] .* for [0-9]+ gold"                       p15_server.log
check "selling away from the vendor rejected"         "Shopper sell rejected: you must be at the vendor"                   p15_server.log
check "buying without gold rejected"                  "\[vendor\] Pauper buy rejected: not enough gold"                  p15_server.log
check "unaffordable buy explained in the panel"       "vendor panel: Not enough gold for #[0-9]+"                        p15_Pauper.log
checkp "selling never drops the item on the ground"   "ground items near me before/after selling: (\d+) -> \1$"           p15_Shopper.log
check "health potions sell for a little gold"         "Shopper sold [0-9]+ x health_potion for [0-9]+ gold"              p15_server.log
check "buying with a full bag rejected"               "\[vendor\] FullBag buy rejected: your bag is full"                p15_server.log
check "stock persists across restart (same rotation)" "\[vendor\] loaded accounts_p15_vendor.json: rotation [0-9]+ .*12 entries"  p15b_server.log
if ! grep -q "stock rotated" $L/p15b_server.log && python3 tools/vendor_compare.py "$L/p15_vendor_before_restart.json" "$L/p15b_Shopper.log"; then echo "PASS  stock, prices and sold-out entries identical after restart"; else echo "FAIL  stock, prices and sold-out entries identical after restart"; fi
check "bought item kept after restart"                "Login 'Shopper'.*restored save"                                     p15b_server.log
check "stock rotates on the timer"                    "\[vendor\] stock rotated \(timer\)"                               p15c_server.log
check "vendor offline checks"                         "vendor selftest: all [0-9]+ checks passed"                          gear_selftest.log
if grep -rqE "market_server|market_ui|request_market" scripts/; then echo "FAIL  player market code removed"; else echo "PASS  player market code removed (no market scripts or requests left)"; fi
echo; echo "== First-time tutorial (M2)"
check "big windows exclusive incl. N map (I/N x40, C/T/atlas)" "UI SELFTEST exclusive windows .*: PASS"                    p16_UiTest.log
check "N zone map draws above chat/skill bar/help/stats"   "UI SELFTEST N map above the HUD: PASS"                     p16_UiTest.log
check "fast typing after Enter goes into chat (no hotkeys)" "UI SELFTEST fast typing after Enter goes to chat: PASS"    p16_UiTest.log
check "skills back to back run out of mana (UiTest)"    "UiTest skill 4 rejected: not enough mana"                  p16_server.log
check "tutorial box never covers the inventory (step 4)"   "UI SELFTEST tutorial box clear of the inventory: PASS"     p16_UiTest.log
check "tutorial starts for a new character"            "\[tutorial\] Newbie: starting the tutorial \(new character\)"   p16_server.log
check "step 1: movement"                               "tutorial step 1 done: Move"                                   p16_Newbie.log
check "step 2: skills (keys 1-4)"                      "tutorial step 2 done: Skills"                                 p16_Newbie.log
check "practice loot dropped"                          "\[tutorial\] Newbie: practice loot dropped"                   p16_server.log
check "step 3: loot pickup"                            "tutorial step 3 done: Loot"                                   p16_Newbie.log
check "step 4: equipping gear"                         "tutorial step 4 done: Equip gear"                             p16_Newbie.log
check "step 5: passive web"                            "tutorial step 5 done: Passive web"                            p16_Newbie.log
check "finished flag saved"                            "\[tutorial\] Newbie finished the tutorial - flag saved \(done\)" p16_server.log
check "tutorial can be skipped"                        "tutorial skipped at step 1/5"                                 p16_Skipper.log
check "skipped flag saved"                             "\[tutorial\] Skipper skipped the tutorial - flag saved \(skipped\)" p16_server.log
if grep -qE "\[tutorial\] (Newbie|Skipper): starting" $L/p16b_server.log || grep -q "tutorial started" $L/p16b_Newbie.log $L/p16b_Skipper.log; then echo "FAIL  shown once (not again after a restart + re-login)"; else echo "PASS  shown once (not again after a restart + re-login)"; fi
if python3 -c "import json,sys; a=json.load(open('$SAVE16'))['accounts']; sys.exit(0 if a['newbie']['character']['tutorial']=='done' and a['skipper']['character']['tutorial']=='skipped' else 1)"; then echo "PASS  tutorial flag stored per character"; else echo "FAIL  tutorial flag stored per character"; fi
if grep -qE "\[tutorial\] (Oldie|Oldtown|Lost): starting" $L/p2_server.log; then echo "FAIL  old characters don't get the tutorial"; else echo "PASS  old characters don't get the tutorial"; fi
echo; echo "== Fresh pull onto an old .godot cache"
GODOT="$GODOT" tools/stale_cache_check.sh 86382b3 | grep -E "^(PASS|FAIL)"
echo; echo "== Party XP share (range 1000 px, same zone, alive)"
check "near member joined"                             "\[party\] XpNear joined XpLead's party"                     p17_server.log
check "far member joined"                              "\[party\] XpFar joined XpLead's party"                      p17_server.log
check "leader kills and gains XP"                      "XpLead gained [0-9]+ XP"                                    p17_server.log
check "kill shared with the member next to it"         "was slain by XpLead \(\+[0-9]+ XP each, party share: XpNear\)" p17_server.log
check "member near the kill gains XP without hitting"  "XpNear gained [0-9]+ XP"                                    p17_server.log
check "member's own client sees its XP rise"           "follow bot: [0-9]+ px from XpLead, xp [1-9][0-9]*/"        p17_XpNear.log
check "far member logged as out of range"              "party share: XpFar too far from XpLead's kill \([0-9]+ > 1000 px\), no XP" p17_server.log
if grep -q "XpFar gained" $L/p17_server.log; then echo "FAIL  far member gets no XP"; else echo "PASS  far member gets no XP"; fi
if grep -q "was slain by XpNear" $L/p17_server.log; then echo "FAIL  near member never attacked (XP came from the share)"; else echo "PASS  near member never attacked (XP came from the share)"; fi
echo; echo "== Errors/warnings (should be none):"
grep -iE "SCRIPT ERROR|^ERROR|^WARNING" $L/*.log | sort | uniq -c | head -40 || true
grep -qiE "SCRIPT ERROR|^ERROR|^WARNING" $L/*.log || echo "none"
if grep -qiE "SCRIPT ERROR|^ERROR|^WARNING" $L/*.log; then echo "FAIL  no engine/script errors or warnings in any log (see above)"; else echo "PASS  no engine/script errors or warnings in any log"; fi
