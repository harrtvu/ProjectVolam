#!/usr/bin/env bash
# Regression check: a clone whose .godot/ cache was built by an OLDER commit must still start
# after `git pull` without opening the editor (no class-cache rescan). New global classes
# (class_name) are not in that cache, so new scripts must be preloaded, not used by class_name.
# Usage: GODOT=/path/to/godot tools/stale_cache_check.sh [old_commit (default 86382b3)]
set -u
GODOT="${GODOT:-godot}"; OLD="${1:-86382b3}"
cd "$(dirname "$0")/.."
T=$(mktemp -d)
git worktree add -q --detach "$T/wt" "$OLD" || exit 2
( cd "$T/wt" && "$GODOT" --headless --editor --quit-after 200 > "$T/old_import.log" 2>&1 )
# bring the current working tree (tracked + new files, no .godot) over the old checkout
git ls-files -co --exclude-standard | grep -v "^\.godot/" | tar -cf - -T - | tar -xf - -C "$T/wt"
( cd "$T/wt" && git ls-files | while read -r f; do [ -e "$OLDPWD/$f" ] || rm -f "$f"; done )
( cd "$T/wt" && timeout 60 "$GODOT" --headless --path . -- --quit-after=3 > "$T/run.log" 2>&1 )
git worktree remove --force "$T/wt"
if grep -qE "SCRIPT ERROR|Parse Error|Failed to load script" "$T/run.log"; then
  echo "FAIL  stale .godot cache: game fails to start without the editor"; grep -E "SCRIPT ERROR|Parse Error|Failed to load" "$T/run.log" | head -5; exit 1
fi
echo "PASS  starts with a stale .godot class cache from $OLD (no editor rescan)"
