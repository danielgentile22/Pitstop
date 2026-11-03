# Pitstop

An iOS app for logging, rating and finding public bathrooms, with a one-tap route to the fastest one when it can't wait.

**Status:** on-device only, distributed through TestFlight. Your data never leaves the phone: there is no account, server or sync. The only network calls are the Apple Maps lookups listed under [How it works](#how-it-works).

## The problem

Maps apps know where restaurants are. They don't know whether the bathroom inside is free, needs a key, has a changing table or a line out the door. Pitstop is a personal, rated map of the bathrooms you've found, with the details that matter, plus the chain stores nearby that usually have one. It works with no signal and gets you to the best bet in a single tap.

## Features

- **Map and list.** Pins colored by rating, next to Apple's own restroom points of interest. The list is searchable and sorts by distance, rating, date added or name.
- **Unvisited places.** About 6,000 chain locations in Virginia, Maryland and DC (Target, Walmart, Barnes & Noble, grocery chains, gas stations and convenience stores) show as dimmed pins tinted by how reliably that brand has a public restroom. Pins cluster as you zoom out, and a cluster too tight to split opens a list of its places. "I went here" turns a place into a saved bathroom with its name and address filled in. "No public restroom here" dismisses it, and Show dismissed brings it back to undo.
- **Emergency button.** One tap ranks your saved bathrooms and the unvisited places by driving time plus penalties: lower ratings, less reliable brands and, from 10 PM to 6 AM, places known not to be open 24 hours. It then opens Google Maps driving directions to the winner, or Apple Maps if Google Maps is not installed. Places more than 45 effective minutes away are out of range, so the button says nothing is in range instead of sending you on a long drive. Offline, it ranks by straight-line distance at 20 mph.
- **Detailed entries.** Pin placement on a mini map, by dragging or by address search, with automatic reverse geocoding, a 1 to 5 star rating, access type (free, paid, purchase required, key required, private property), stall type, gender designation, wheelchair access, changing table, toilet paper (including a dispenser rating), bidet type, heated seat, soap, hand drying, typical wait, notes, and up to 10 photos from the library or camera.
- **Filters.** Minimum rating, maximum distance, access, stall, gender and wait time, nine must-have toggles, and Show unvisited and Show dismissed. Filters apply live, and the same way, to both the map and the list. Criteria only a visit can answer hide unvisited places.
- **Photos.** A thumbnail carousel on each bathroom and a full-screen viewer with paging, pinch to zoom and swipe to dismiss.
- **Accessibility.** VoiceOver labels on pins and rows, an adjustable star rating control, and animations that respect Reduce Motion.

## How it works

- **SwiftData is the only store.** It holds two models: `Bathroom` for places you visited and `Candidate` for unvisited places from the bundled seed. The store is the only copy of the data, so the schema is versioned and a change needs a migration, never a wipe. If the store will not open, the app copies it to `Documents/StoreBackups/` and explains, instead of crashing.
- **Saves commit before files go.** `BathroomSaver` writes new photos, commits the store, and only then deletes photos you removed, so a failed save keeps the form open and loses nothing.
- **Candidates come from a bundled seed.** On launch, off the main thread, the app imports `CandidateSeed.json` when its version is newer than the last import. The import is idempotent, never changes whether you dismissed a place, and never deletes a dismissed place or one a bathroom was logged from. A bathroom logged from a Candidate keeps its `sourceID`, which hides that Candidate everywhere, so you see the place once.
- **Photos live on disk** as a JPEG up to 1200px and a 200px thumbnail per image under `Documents/BathroomImages/{id}/`, with in-memory caches. The model stores file names only, since the sandbox path can change across updates.
- **Network calls.** Three, all to Apple Maps, and each one degrades offline:
  - Reverse geocoding of the pin in the add form, only once the pin moves off a known address. The save waits at most 2 seconds for it. Offline, the entry keeps the last address it had, or saves without one.
  - Address search in the add form. Offline, it says the search needs a connection.
  - Driving times for the emergency button, for the 8 closest places, within a 3 second deadline that also covers getting a fresh location. Places with no answer use straight-line distance at 20 mph.

## Worth a look

| File | Why |
|---|---|
| [`EmergencyRanker.swift`](Pitstop/Pitstop/EmergencyRanker.swift) | Pure ranking for the emergency button, with every penalty and the range limit in one table. |
| [`DrivingTimeLookup.swift`](Pitstop/Pitstop/DrivingTimeLookup.swift) | Parallel driving-time lookups that give up at a deadline. |
| [`ClusteredMapView.swift`](Pitstop/Pitstop/ClusteredMapView.swift) | An `MKMapView` wrapper that clusters thousands of pins, which SwiftUI's `Map` cannot. |
| [`CandidateImporter.swift`](Pitstop/Pitstop/CandidateImporter.swift) | Version-gated, idempotent seed import that never overrides what you told the app. |
| [`BathroomSaver.swift`](Pitstop/Pitstop/BathroomSaver.swift) | The save order that keeps the store and the photo files in step. |
| [`FlowLayout.swift`](Pitstop/Pitstop/FlowLayout.swift) | A custom SwiftUI `Layout` that wraps filter chips onto rows like text. |
| [`ImageStorage.swift`](Pitstop/Pitstop/ImageStorage.swift) | On-disk photo storage with thumbnails and caches. |

## Requirements

- Xcode 27.2 or later
- iOS 26.2 or later

## Setup

Open `Pitstop/Pitstop.xcodeproj` and run the `Pitstop` scheme. There are no dependencies or config files.

## Tests

Unit tests use Swift Testing and live in `Pitstop/PitstopTests/`. Run them in Xcode with Product > Test, or run everything from the repo root:

```sh
scripts/check.sh    # seed tests, iOS preflight, Swift tests on a simulator
```

CI runs the same script on every push and pull request. `scripts/ios-preflight.sh` alone checks in about 20 seconds that Xcode and the simulators are usable, and prints the command that fixes them when they are not.

## Unvisited places data

The app ships with chain locations in Virginia, Maryland and DC that you have not visited yet, in [`CandidateSeed.json`](Pitstop/Pitstop/CandidateSeed.json). [`scripts/seed/build_seed.py`](scripts/seed/build_seed.py) builds it from [All The Places](https://alltheplaces.xyz/), which scrapes each brand's official store locator every week. Harris Teeter and Weis have no All The Places scraper, so their stores come from [OpenStreetMap](https://www.openstreetmap.org/) through the Overpass API. Exxon, Mobil and Citgo come from the last All The Places run that finished those scrapers (June 2026 for Exxon and Mobil, May 2026 for Citgo), so a station that changed brand since then can be out of date.

**License.** All The Places releases its output data under the [Creative Commons CC-0 waiver](https://creativecommons.org/publicdomain/zero/1.0/) (stated in the License section of its [README](https://github.com/alltheplaces/alltheplaces#license), checked 2026-10-31). CC-0 puts the data in the public domain, so bundling it in this MIT repo is allowed and needs no attribution. This README credits it anyway. The Harris Teeter and Weis locations are © OpenStreetMap contributors, available under the [Open Database License](https://www.openstreetmap.org/copyright).

Because it includes that OpenStreetMap data, [`CandidateSeed.json`](Pitstop/Pitstop/CandidateSeed.json) is licensed under the [Open Database License](https://opendatacommons.org/licenses/odbl/), with credit to OpenStreetMap contributors. The app code stays MIT.

```sh
python3 scripts/seed/build_seed.py                       # download, filter, write the seed
uv run --no-project --with pytest pytest scripts/seed    # tests, offline, on saved fixtures
```

The script prints counts per brand and per state, and bumps the seed version only when the records change. Spiders sometimes stop partway through a weekly run, so for each brand the script uses the newest run that reached a full nationwide count (`min_features` in `SOURCES`) and prints which run that was. Walmart's last full scrape is from 2026-01-31; every run since has returned only part of the chain. The app imports a newer version on the next launch. Brand reliability levels live in [`BrandProfile.swift`](Pitstop/Pitstop/BrandProfile.swift).

## Releasing to TestFlight

```sh
scripts/testflight.sh              # archive, export, upload
scripts/testflight.sh --no-upload  # stop after build/export/Pitstop.ipa
```

The script reads `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH` and `SIGNING_KEYCHAIN_PASSWORD` from a gitignored `.env` at the repo root. It runs `scripts/check.sh` first and stops if the check fails. It signs with the distribution certificate and the "Pitstop App Store" profile named in `Pitstop/ExportOptions.plist`, numbers each build by date and time, and uploads with the App Store Connect API key. Testers in the internal "Me" group get every build automatically.

The bundle ID is `com.danielgentile.GeoPoop`, the app's earlier name, because the App Store Connect record was created under it. The store name is "Pitstop: Bathroom Map"; the home screen shows "Pitstop".

## Screenshots

<!-- SCREENSHOTS: add captures of the map, list, detail sheet, add form and filter sheet here. -->
_Not yet captured._

## Project layout

```
scripts/check.sh                Seed tests, iOS preflight and Swift tests (CI runs it too)
scripts/ios-preflight.sh        Checks Xcode and the simulators before a build
scripts/testflight.sh           Check, archive, sign and upload to TestFlight
scripts/seed/                   Builds the bundled unvisited-places seed, with tests
Pitstop/
├── ExportOptions.plist         App Store export signing
├── Pitstop/
│   ├── PitstopApp.swift        Entry point and SwiftData container
│   ├── ContentView.swift       Map/List switcher, toolbar, emergency flow
│   ├── MapTabView.swift        Map tab: filtering, camera, selection
│   ├── ClusteredMapView.swift  MKMapView wrapper that draws and clusters the pins
│   ├── ListTabView.swift       Searchable, sortable list
│   ├── DetailView.swift        Bathroom detail sheet
│   ├── CandidateDetailView.swift  Unvisited place sheet: I went here, dismiss, undo
│   ├── AddBathroomView.swift   Add and edit form
│   ├── BathroomSaver.swift     Saves and deletes bathrooms and their photos
│   ├── FilterSheetView.swift   Live filters
│   ├── Bathroom.swift          Visited place model
│   ├── Candidate.swift         Unvisited place model
│   ├── Schema.swift            Versioned schema and migration plan
│   ├── CandidateImporter.swift Imports CandidateSeed.json
│   ├── BrandProfile.swift      Brand names and reliability levels
│   ├── EmergencyRanker.swift   Emergency ranking and penalties
│   ├── DrivingTimeLookup.swift Driving times with a deadline
│   ├── ImageStorage.swift      On-disk photo storage and caches
│   └── ...                     Supporting views and helpers
└── PitstopTests/               Swift Testing unit tests
```

## License

[MIT](LICENSE)
