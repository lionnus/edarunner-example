#!/usr/bin/env bash
# wait.sh <cap_s>: run `edr watch --once` until no run is live, then fail unless every
# run of the board ended done. The last cycle after the end collects the last stage.
set -euo pipefail
end=$((SECONDS + $1))
while :; do
  edr status --narrow | grep -q "nothing live" && over=1 || over=0
  edr watch --once
  [ "$over" = 1 ] && break
  [ "$SECONDS" -lt "$end" ] || { echo "a run is still live after $1 s"; edr status; exit 1; }
  sleep 30
done
edr status
edr --json status | python3 -c 'import json, sys
runs = json.load(sys.stdin)["data"]["runs"]
bad = [(r["label"], r["phase"]) for r in runs if r["phase"] != "done"]
assert runs and not bad, bad'
