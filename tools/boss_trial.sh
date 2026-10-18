#!/usr/bin/env bash
# Balance trial: each of the 5 classes fights the first zone's boss (Whisperwood Forest,
# Broodmother Lv8) SOLO at the intended level, on its own server (parallel, ports $PORT+21..+25, PORT defaults to 7920).
# The bot starts next to the lair with only its class starting kit (no found gear), spends
# its passive points automatically and cycles its 4 skills + basic attack + potions.
# The server's "BOSS FIGHT" line (first hit -> kill) gives time-to-kill, damage taken,
# deaths. Writes $OUT (a table) and returns 0 if every class killed the boss.
# Usage: GODOT=... tools/boss_trial.sh [LEVEL] [SECONDS] [OUT] [LOGPREFIX]
set -u
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
LV=${1:-7}; SECS=${2:-150}; OUT=${3:-test-logs/boss_trial.txt}; P=${4:-test-logs/bt}
i=0
for c in metal wood water fire earth; do
  port=$((${PORT:-7920} + 21 + i)); i=$((i+1)); S="$(pwd)/${P}_${c}_save.json"; rm -f "$S"
  ( "$GODOT" --headless --path . -- --server --port=$port --save-file="$S" --debug-start-level=$LV --allow-warp --no-xp --quit-after=$((SECS+6)) > ${P}_${c}_server.log 2>&1 ) &
  ( sleep 2; "$GODOT" --headless --path . -- --join=127.0.0.1 --port=$port --name=Trial${c^} --password=t --class=$c --bot --bot-no-gear \
      --bot-talents=auto:0 --bot-smart --bot-hunt=boss --warp=forest --warp-cell=176,104 --quit-after=$SECS > ${P}_${c}_bot.log 2>&1 ) &
done
wait
python3 - "$P" "$LV" "$OUT" <<'PY'
import re, sys
p, lv, out = sys.argv[1], sys.argv[2], sys.argv[3]
rows, ok = [], True
for c in ["metal", "wood", "water", "fire", "earth"]:
    log = open("%s_%s_server.log" % (p, c)).read()
    m = re.search(r"BOSS FIGHT Broodmother\(Lv\d+, (\d+) hp\) killed in ([\d.]+)s \| \S+ Lv(\d+) \w+: dealt (\d+), damage taken (\d+), deaths (\d+), hp (\d+)/(\d+)", log)
    if m:
        rows.append("%-6s | Lv%-3s | killed | %6.1f s | %5s | %3s | %s/%s" % (c, m.group(3), float(m.group(2)), m.group(5), m.group(6), m.group(7), m.group(8)))
    else:
        ok = False
        hp = re.findall(r"Broodmother\(Lv\d+\) for \d+.* -> hp (\d+)/(\d+)", log)
        rows.append("%-6s | Lv%-3s | NOT KILLED (boss hp %s) | - | - | - | -" % (c, lv, "/".join(hp[-1]) if hp else "untouched"))
txt = "Boss trial: Broodmother (Whisperwood Forest boss) solo, intended level %s, class starting kit\nclass  | level | result | time-to-kill | dmg taken | deaths | hp left\n" % lv + "\n".join(rows)
times = [float(x) for x in re.findall(r"\| +([\d.]+) s \|", txt)]
if times and len(times) == 5:
    txt += "\nspread: fastest %.1f s, slowest %.1f s, ratio %.2f" % (min(times), max(times), max(times) / min(times))
print(txt); open(out, "w").write(txt + "\n")
sys.exit(0 if ok else 1)
PY
