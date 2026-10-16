#!/usr/bin/env python3
"""Market audit for the test run: no item duplication + gold conservation.
usage: market_audit.py SAVE.json SERVER_LOG [SERVER_LOG ...]"""
import json, re, sys
save = json.load(open(sys.argv[1]))
logs = "".join(open(p).read() for p in sys.argv[2:])
uids = {}
def add(inst, where):
    if isinstance(inst, dict) and "uid" in inst:
        uids.setdefault(inst["uid"], []).append(where)
gold = 0
for k, a in save["accounts"].items():
    c = a.get("character", {})
    gold += int(c.get("gold", 0))
    for i in c.get("bag", []): add(i, k + ".bag")
    for s, i in c.get("equipment", {}).items(): add(i, k + ".eq")
    for i in a.get("stash", []): add(i, k + ".stash")
import os
mpath = os.path.splitext(sys.argv[1])[0] + "_market.json"
m = json.load(open(mpath)) if os.path.exists(mpath) else save.get("market", {})
print("market file: %s (tx %s, accounts market_tx %s)" % (mpath, m.get("tx"), save.get("market_tx")))
for l in m.get("listings", []): add(l["item"], "listing#%d" % l["id"])
claims_gold = 0
for k, c in m.get("claims", {}).items():
    claims_gold += int(c.get("gold", 0))
    for i in c.get("items", []): add(i, k + ".claim")
dups = {u: w for u, w in uids.items() if len(w) > 1}
initial = sum(int(g) for g in re.findall(r"Login '[^']+' \(peer \d+\): NEW account .*?, gold (\d+),", logs))
fees = sum(int(x) for x in re.findall(r"listed #\d+ .* \(fee (\d+),", logs))
taxes = sum(int(x) for x in re.findall(r"bought #\d+ .* \(tax (\d+),", logs))
final = gold + claims_gold
print("items: %d unique uids, duplicates: %s" % (len(uids), dups if dups else "none"))
print("gold: initial %d - fees %d - taxes %d = %d ; found %d (characters %d + claim boxes %d) -> %s" % (
    initial, fees, taxes, initial - fees - taxes, final, gold, claims_gold, "CONSERVED" if final == initial - fees - taxes else "MISMATCH"))
