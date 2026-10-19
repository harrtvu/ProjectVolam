#!/usr/bin/env bash
# Regression check (PlayTester e2051c6): a clone without a matching .godot/ import cache must run
# with no engine errors. Two cases, both from a `git clone` of COMMIT:
#   A) stale cache: .godot/ built by OLD (before the portal art), then COMMIT checked out, no editor
#      (the portal PNGs have .import files but no .ctex) -> must not print 'Failed loading resource';
#   B) no cache at all: the suite's own import step (tools/ensure_import.sh, if the commit has it),
#      then the game -> no errors.
# Each case runs a server + a bot that opens a T1 portal and enters it (~30 s).
# Usage: GODOT=... tools/fresh_clone_check.sh [COMMIT=HEAD] [OLD=20bf932] [PORT=8990]
set -u
GODOT="${GODOT:-godot}"; COMMIT="${1:-HEAD}"; OLD="${2:-20bf932}"; PORT="${3:-8990}"
cd "$(dirname "$0")/.."
REPO=$(pwd); C=$(git rev-parse "$COMMIT"); T=$(mktemp -d -p "${TMPROOT:-/workspace/scratch}" fresh.XXXX)
play() {   # dir tag
  ( cd "$1" || exit 1
    "$GODOT" --headless --path . -- --server --port=$PORT --save-file="$T/$2_acc.json" --debug-start-level=6 --quit-after=34 > "$T/$2_server.log" 2>&1 &
    sleep 2
    "$GODOT" --headless --path . -- --join=127.0.0.1 --port=$PORT --name=Fresh --password=f --class=fire --bot --bot-no-gear \
      --bot-dungeon=enter --bot-dungeon-theme=wood --bot-dungeon-tier=1 --quit-after=30 > "$T/$2_client.log" 2>&1 &
    sleep 40; kill %1 %2 2>/dev/null; wait )
}
scan() {   # tag what
  if grep -qiE "SCRIPT ERROR|^ERROR|^WARNING" "$T/$1_server.log" "$T/$1_client.log"; then
    echo "FAIL  $2: engine errors"; grep -hiE "SCRIPT ERROR|^ERROR|^WARNING" "$T/$1_server.log" "$T/$1_client.log" | sort | uniq -c | head -6; RC=1
  elif ! grep -q "entered dun" "$T/$1_server.log"; then
    echo "FAIL  $2: the bot never entered its dungeon (see $T)"; RC=1
  else echo "PASS  $2: no engine errors, portal opened and entered"; fi
}
RC=0
git clone -q --no-local "$REPO" "$T/a" && git -C "$T/a" checkout -q "$OLD"
( cd "$T/a" && "$GODOT" --headless --editor --quit-after 400 --path . > "$T/a_import.log" 2>&1 )
git -C "$T/a" checkout -q "$C"
play "$T/a" a; scan a "stale .godot cache from $OLD, $COMMIT checked out, no editor"
git clone -q --no-local "$REPO" "$T/b" && git -C "$T/b" checkout -q "$C"
if [ -x "$T/b/tools/ensure_import.sh" ]; then GODOT="$GODOT" "$T/b/tools/ensure_import.sh" > "$T/b_import.log" 2>&1; fi
play "$T/b" b; scan b "fresh clone (no .godot), the suite's import step, then the game"
[ $RC -eq 0 ] && rm -rf "$T"
exit $RC
