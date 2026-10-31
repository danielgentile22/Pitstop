# Pitstop

An iOS app for logging, rating and finding public bathrooms, with a one-tap route to the nearest one when it can't wait.

**Status:** on-device only, distributed through TestFlight. Nothing leaves the phone: there is no account, server or sync.

## The problem

Maps apps know where restaurants are. They don't know whether the bathroom inside is free, needs a key, has a changing table or a line out the door. Pitstop is a personal, rated map of the bathrooms you've found, with the details that matter, built to work with no signal and to get you to the closest one in a single tap.

## Features

- **Map and list.** Pins colored by rating, next to Apple's own restroom points of interest. The list is searchable and sorts by distance, rating, date added or name.
- **Emergency button.** One tap opens walking directions in Apple Maps to the nearest saved bathroom by straight-line distance, with no network needed.
- **Detailed entries.** Pin placement on a mini map with automatic reverse geocoding, a 1 to 5 star rating, access type (free, paid, purchase required, key required, private property), stall type, gender designation, wheelchair access, changing table, toilet paper (including a dispenser rating), bidet type, heated seat, soap, hand drying, typical wait, notes, and up to 10 photos from the library or camera.
- **Filters.** Minimum rating, maximum distance, access, stall, gender and wait time, plus nine must-have toggles. Filters apply live to both the map and the list.
- **Photos.** A thumbnail carousel on each bathroom and a full-screen viewer with paging, pinch to zoom and swipe to dismiss.
- **Accessibility.** VoiceOver labels on pins and rows, an adjustable star rating control, and animations that respect Reduce Motion.

## How it works

- **SwiftData is the only store.** Views read and write `Bathroom` records directly. The store is the only copy of the data, so a schema change needs a migration, never a wipe.
- **Photos live on disk** as a full-size JPEG and a 200px thumbnail per image under `Documents/BathroomImages/{id}/`, with in-memory caches. The model stores file names only, since the sandbox path can change across updates.
- **Reverse geocoding** uses MapKit and is the only network call. Without a connection the entry falls back to coordinates.

## Worth a look

| File | Why |
|---|---|
| [`EmergencyButton.swift`](Pitstop/Pitstop/EmergencyButton.swift), [`MapURLHelper.swift`](Pitstop/Pitstop/MapURLHelper.swift) | The one-tap emergency flow and handoff to Apple Maps walking directions. |
| [`FlowLayout.swift`](Pitstop/Pitstop/FlowLayout.swift) | A custom SwiftUI `Layout` that wraps filter chips onto rows like text. |
| [`ImageStorage.swift`](Pitstop/Pitstop/ImageStorage.swift) | On-disk photo storage with thumbnails and caches. |

## Requirements

- Xcode 27.2 or later
- iOS 26.2 or later

## Setup

Open `Pitstop/Pitstop.xcodeproj` and run the `Pitstop` scheme. There are no dependencies or config files.

## Tests

Unit tests use Swift Testing and live in `Pitstop/PitstopTests/`. Run them in Xcode with Product > Test, or from the repo root:

```sh
xcodebuild test -project Pitstop/Pitstop.xcodeproj -scheme Pitstop \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

## Unvisited places data

The app ships with chain locations in Virginia, Maryland and DC that you have not visited yet, in [`CandidateSeed.json`](Pitstop/Pitstop/CandidateSeed.json). [`scripts/seed/build_seed.py`](scripts/seed/build_seed.py) builds it from [All The Places](https://alltheplaces.xyz/), which scrapes each brand's official store locator every week.

**License.** All The Places releases its output data under the [Creative Commons CC-0 waiver](https://creativecommons.org/publicdomain/zero/1.0/) (stated in the License section of its [README](https://github.com/alltheplaces/alltheplaces#license), checked 2026-10-31). CC-0 puts the data in the public domain, so bundling it in this MIT repo is allowed and needs no attribution. This README credits it anyway.

```sh
python3 scripts/seed/build_seed.py                       # download, filter, write the seed
uv run --no-project --with pytest pytest scripts/seed    # tests, offline, on saved fixtures
```

The script prints counts per brand and per state, and bumps the seed version only when the records change. The app imports a newer version on the next launch. Brand reliability levels live in [`BrandProfile.swift`](Pitstop/Pitstop/BrandProfile.swift).

## Releasing to TestFlight

```sh
scripts/testflight.sh              # archive, export, upload
scripts/testflight.sh --no-upload  # stop after build/export/Pitstop.ipa
```

The script reads `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH` and `SIGNING_KEYCHAIN_PASSWORD` from a gitignored `.env` at the repo root. It signs with the distribution certificate and the "Pitstop App Store" profile named in `Pitstop/ExportOptions.plist`, numbers each build by date and time, and uploads with the App Store Connect API key. Testers in the internal "Me" group get every build automatically.

The bundle ID is `com.danielgentile.GeoPoop`, the app's earlier name, because the App Store Connect record was created under it. The store name is "Pitstop: Bathroom Map"; the home screen shows "Pitstop".

## Screenshots

<!-- SCREENSHOTS: add captures of the map, list, detail sheet, add form and filter sheet here. -->
_Not yet captured._

## Project layout

```
scripts/testflight.sh           Archive, sign and upload to TestFlight
scripts/seed/                   Builds the bundled unvisited-places seed, with tests
Pitstop/
├── ExportOptions.plist         App Store export signing
├── Pitstop/
│   ├── PitstopApp.swift        Entry point and SwiftData container
│   ├── ContentView.swift       Map/List switcher, toolbar, emergency button
│   ├── MapTabView.swift        Map with rating-colored pins
│   ├── ListTabView.swift       Searchable, sortable list
│   ├── DetailView.swift        Bathroom detail sheet
│   ├── AddBathroomView.swift   Add and edit form
│   ├── FilterSheetView.swift   Live filters
│   ├── Bathroom.swift          SwiftData model
│   ├── ImageStorage.swift      On-disk photo storage and caches
│   └── ...                     Supporting views and helpers
└── PitstopTests/               Swift Testing unit tests
```

## License

[MIT](LICENSE)
