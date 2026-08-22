#!/usr/bin/env bash
# Run `swift test` N times, killing any run that hangs. Usage: soak.sh [runs] [seconds-per-run]
set -uo pipefail
cd "$(dirname "$0")/.."
runs=${1:-20}
limit=${2:-120}
pass=0; fail=0; hang=0
for i in $(seq 1 "$runs"); do
    log=$(mktemp)
    swift test >"$log" 2>&1 &
    pid=$!
    ( sleep "$limit"; kill -9 $pid 2>/dev/null ) & watchdog=$!
    if wait $pid; then pass=$((pass+1)); else
        if kill -0 $watchdog 2>/dev/null; then fail=$((fail+1)); echo "FAIL run $i ($log)";
        else hang=$((hang+1)); echo "HANG run $i ($log)"; fi
    fi
    kill $watchdog 2>/dev/null
    [ $pass -gt 0 ] && rm -f "$log"
done
echo "runs=$runs pass=$pass fail=$fail hang=$hang"
[ "$pass" -eq "$runs" ]
