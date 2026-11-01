#!/bin/bash
# The one check, run by sessions, by CI and by scripts/testflight.sh before it archives.
# Runs the seed tests, the iOS preflight, then the Swift tests on an iPhone simulator from
# the newest installed iOS runtime. Exits non-zero on the first failure.
#
#   scripts/check.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== seed tests"
uv run --no-project --with pytest pytest -q scripts/seed

echo "== iOS preflight"
scripts/ios-preflight.sh

echo "== iOS tests"
udid=$(xcrun simctl list devices available --json | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
ios = sorted((r for r in devices if ".iOS-" in r), key=lambda r: [int(n) for n in r.split(".iOS-")[1].split("-")], reverse=True)
print(next((d["udid"] for r in ios for d in devices[r] if d["name"].startswith("iPhone")), ""))')
[ -n "$udid" ] || { echo "error: no available iPhone simulator" >&2; exit 1; }
flags=(-project Pitstop/Pitstop.xcodeproj -scheme Pitstop -destination "id=$udid"
       -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO)
log=build/check-build.log
mkdir -p build
# Keep the full logs; on failure show the errors and failed expectations, not just the tail.
xcodebuild build-for-testing "${flags[@]}" > "$log" 2>&1 \
  || { grep -E 'error:' "$log" | sort -u | head -40 || true; tail -20 "$log"; exit 1; }
tests=build/check-test.log
xcodebuild test-without-building "${flags[@]}" > "$tests" 2>&1 \
  || { grep -E 'failed|error:|Expectation' "$tests" | head -40; exit 1; }
grep -E '^Test run with|\*\* TEST' "$tests" | tail -2
