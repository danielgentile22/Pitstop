#!/bin/bash
# iOS preflight: is this Mac's Xcode toolchain fit to build and test? Read-only,
# about 20 seconds at worst. Run it before any iOS build, test or spec fan-out.
#
#   scripts/ios-preflight.sh
#
# Checks Xcode's first-launch status, then lists available simulators, each under a
# watchdog. A hung check counts as a failure. Exits 0 when healthy. On failure it
# exits 1 and its last line is the one command to ask Daniel for (it needs sudo, so
# never run it yourself). After every Xcode update the simulators stay broken until that
# first-launch command runs; a workaround harness only hides it.

set -u
out=$(mktemp) || exit 1
trap 'rm -f "$out"' EXIT

# capped SECONDS CMD...: run CMD in its own process group, output in $out. Kills the
# whole group on timeout (simctl leaves helpers behind) and returns 124.
capped() {
  perl -e '
    my $secs = shift;
    my $pid = fork // die "fork: $!";
    if (!$pid) { setpgrp(0, 0); exec @ARGV or exit 127 }
    $SIG{ALRM} = sub { kill "KILL", -$pid; waitpid $pid, 0; exit 124 };
    alarm $secs;
    waitpid $pid, 0;
    exit($? & 127 ? 128 + ($? & 127) : $? >> 8);
  ' "$@" >"$out" 2>&1 </dev/null
}

ask() {
  echo "iOS preflight FAILED: $1"
  [ -s "$out" ] && tail -n 3 "$out" | sed 's/^/  /'
  echo "Ask Daniel to run: $2"
  exit 1
}

first_launch='sudo xcodebuild -runFirstLaunch'

case $(xcode-select -p 2>/dev/null) in
  (*/CommandLineTools*) ask "xcode-select points at the Command Line Tools, not Xcode" \
    'sudo xcode-select -s /Applications/Xcode.app' ;;
esac

capped 8 xcodebuild -checkFirstLaunchStatus
case $? in
  (0) ;;
  (124) ask "xcodebuild -checkFirstLaunchStatus hung for 8s" "$first_launch" ;;
  (*) ask "Xcode has first-launch tasks pending" "$first_launch" ;;
esac

capped 12 xcrun simctl list devices available
code=$?
grep -q 'CoreSimulator is out of date' "$out" && ask "CoreSimulator is out of date" "$first_launch"
case $code in
  (0) ;;
  (124) ask "xcrun simctl list hung for 12s" "$first_launch" ;;
  (*) ask "xcrun simctl list failed (exit $code)" "$first_launch" ;;
esac

n=$(grep -c -E '\([0-9A-F-]{36}\)' "$out")
[ "$n" -gt 0 ] || ask "no available simulators" "xcodebuild -downloadPlatform iOS"
echo "iOS preflight OK: first launch done, $n simulators available"
