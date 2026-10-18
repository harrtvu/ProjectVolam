#!/usr/bin/env python3
"""Test helper: the vendor stock a client saw after a restart equals the saved vendor.json
(same ids, quantities incl. sold-out entries, and prices)."""
import json, re, sys
v = json.load(open(sys.argv[1]))
want = sorted("#%d x%d @%d" % (e["id"], e["qty"], e["price"]) for e in v["stock"])
m = re.search(r"vendor stock: \d+ entries[^:]*: (.*)", open(sys.argv[2]).read())
got = sorted(re.sub(r"^#(\d+) .* (x\d+ @\d+)$", r"#\1 \2", x) for x in m.group(1).split(" | ")) if m else []
print("saved:", want); print("seen: ", got)
sys.exit(0 if want == got and any(" x0 " in w + " " for w in want) else 1)
