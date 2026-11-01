# Pitstop

iOS app (SwiftUI, SwiftData, MapKit). README.md covers features, layout and releasing; this file holds what the code cannot tell you.

- **Check:** `scripts/check.sh` runs the seed tests, the iOS preflight and the Swift tests on a simulator. CI (`.github/workflows/ci.yml`) runs the same script on a hosted macOS runner, and `scripts/testflight.sh` refuses to archive unless it passes. Hosted runners lag the local Xcode, so watch CI after an iOS push.
- **Preflight:** `scripts/ios-preflight.sh` checks the toolchain in about 20 seconds. On failure its last line is the one command to ask Daniel for. Never build a workaround for broken simulators.
- **Build only:** `xcodebuild build-for-testing -project Pitstop/Pitstop.xcodeproj -scheme Pitstop -destination 'generic/platform=iOS Simulator' -derivedDataPath build/DerivedData -quiet`. Derived data always goes to `build/DerivedData` (gitignored), one per worktree.
- **Seed:** tests alone are `uv run --no-project --with pytest pytest scripts/seed`. Rebuild with `python3 scripts/seed/build_seed.py`, never by hand-merging JSON. A new brand goes in `SOURCES` and `BrandProfile.table` with `min_features` set from the spider's nationwide count.
- **Config:** release credentials live in the gitignored `.env` at the repo root (names in the README). The app has no config file; worktrees need no symlinks to build.
- **Bundle ID:** `com.danielgentile.GeoPoop` is the app's earlier name, kept because the App Store Connect record was created under it. It is not a typo; never rename it.
- **Specs:** specs and their tickets are GitHub issues in this repo. A spec issue is the parent; tickets are labeled `ready-for-agent`.
- **Tests:** Swift Testing in `Pitstop/PitstopTests/`, a synchronized folder (drop files in, no project edit). The app defaults to MainActor isolation, so mark suites `@MainActor` and mark Hashable key types used off the main actor `nonisolated`.
- **Shared seams:** the Map and List tabs share `PlaceDetailSheet`, and both filter through `BathroomFilter.applies(to:)`. Change behavior there, not in one tab.
