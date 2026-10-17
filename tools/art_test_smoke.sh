#!/usr/bin/env bash
# ART STYLE TEST smoke run: phases 1, 3 and 11 of run_local_test.sh (zones, portals, big maps, Whisperwood
# client perf) plus their checks, then Phase 11 again with the clients on --art-test (headless; exercises the
# reskin code paths). Slices the commands straight out of run_local_test.sh so it stays in sync.
# Usage: GODOT=/path/to/Godot_v4.2.1-stable_linux.x86_64 tools/art_test_smoke.sh
set -u
cd "$(dirname "$0")/.."
S=run_local_test.sh
T=$(mktemp)
{
  sed -n '15,23p' $S                                   # setup + run()
  sed -n '/^echo "Phase 1 /,/^wait$/p' $S              # phase 1
  sed -n '/^"\$GODOT" --headless --path . -- --bigmap-selftest/p' $S
  sed -n '/^echo "Phase 3 /,/^echo "Phase 4 /p' $S | sed '$d'
  sed -n '/^echo "Phase 11 /,/^echo "Phase 12 /p' $S | sed '$d'
  sed -n '/^check() /p' $S
  grep -E '^check .* (p1_[a-z0-9_]+|p3_[a-z0-9_]+|p11_[a-z0-9_]+|bigmap_selftest)\.log *$' $S
  sed -n '/^for f in p11_bench_entrance p11_bench_lair/,/^done$/p' $S
  echo 'echo; echo "== Phase 11 again, clients with --art-test"'
  sed -n '/^echo "Phase 11 /,/^echo "Phase 12 /p' $S | sed '$d' | sed -e 's/p11_/a11_/g' -e 's/--quit-after=20/--art-test --quit-after=20/g'
  sed -n '/^for f in p11_bench_entrance p11_bench_lair/,/^done$/p' $S | sed 's/p11_/a11_/g'
  echo 'grep -h "ART" $L/a11_*.log | head -3'
  echo 'echo; echo "== Errors/warnings (should be none):"'
  echo 'grep -iE "SCRIPT ERROR|^ERROR|^WARNING" $L/*.log | sort | uniq -c | head -40 || true'
  echo 'grep -qiE "SCRIPT ERROR|^ERROR|^WARNING" $L/*.log || echo "none"'
} > $T
bash $T
