#!/usr/bin/env bash
# Make sure every committed asset has its imported .ctex in .godot/ (a fresh clone has no .godot/,
# an older cache misses newer assets). Godot 4.2 has no --import: a short headless editor run imports.
# Usage: GODOT=... tools/ensure_import.sh   (run from anywhere; exit 1 if assets stay unimported)
set -u
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
missing() {
  git ls-files '*.import' 2>/dev/null | while read -r f; do
    [ -e "${f%.import}" ] || continue   # orphan .import (its asset was removed, e.g. assets/slime.png): nothing to import
    p=$(sed -n 's/^path="res:\/\/\(.*\)"$/\1/p' "$f" | head -1)
    [ -n "$p" ] && [ ! -e "$p" ] && echo "$f"
  done
}
n=$(missing | wc -l)
[ "$n" -eq 0 ] && exit 0
echo "ensure_import: $n asset(s) not imported yet - importing (headless editor)..."
for i in 1 2 3; do
  "$GODOT" --headless --editor --quit-after 400 --path . > /dev/null 2>&1
  n=$(missing | wc -l)
  [ "$n" -eq 0 ] && { echo "ensure_import: done"; exit 0; }
done
echo "ensure_import: still missing:"; missing | head; exit 1
