#!/usr/bin/env bash
# Regenerates docs/market_*.png (needs a display, e.g. DISPLAY=:2 or xvfb-run).
# Usage: GODOT=/path/to/Godot_v4.2.1-stable_linux.x86_64 tools/market_screenshots.sh
set -u
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
T=$(mktemp -d); S="$T/accounts.json"
h() { "$GODOT" --headless --path . -- "$@"; }
w() { "$GODOT" --path . --resolution 1024x576 -- "$@"; }
h --server --save-file="$S" --debug-start-level=20 --debug-gear --allow-warp --quit-after=80 > $T/server.log 2>&1 &
sleep 2
for n in Linh:metal Quan:wood Tran:fire; do
  h --join=127.0.0.1 --name=${n%%:*} --password=s --class=${n##*:} --bot --bot-market=stocker --quit-after=70 > $T/${n%%:*}.log 2>&1 &
done
# Mira (Wood) lists stuff, Khoa buys two of her stacks -> her claim box + history
w --join=127.0.0.1 --name=Mira --password=s --class=wood --bot --bot-market=stocker --open-market=mine --open-market-at=34 \
  --screenshot=docs/market_mine.png --screenshot-delay=38 --quit-after=42 > $T/Mira.log 2>&1 &
h --join=127.0.0.1 --name=Khoa --password=s --class=earth --bot --bot-market=onebuyer --quit-after=40 > $T/Khoa.log 2>&1 &
sleep 14
w --join=127.0.0.1 --name=Browser --password=s --class=water --bot-idle --warp=meadow --warp-cell=20,23 \
  --open-market=browse:max_req=20,usable=1,price_max=1000 --open-market-at=6 --market-tip \
  --screenshot=docs/market_browse.png --screenshot-delay=10 --quit-after=13 > $T/Browser.log 2>&1 &
w --join=127.0.0.1 --name=Seller --password=s --class=metal --bot-idle --warp=meadow --warp-cell=20,23 \
  --open-market=sell --open-market-at=6 --screenshot=docs/market_sell.png --screenshot-delay=10 --quit-after=13 > $T/Seller.log 2>&1 &
wait
grep -h "screenshot\|SCRIPT ERROR" $T/*.log
echo "logs in $T"
