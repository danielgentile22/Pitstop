# Pitstop

An iOS app for logging, rating and finding public bathrooms, with a one-tap route to the nearest one when it can't wait.

**Status:** the hosted backend is no longer running, so there is no public build. The code builds and runs against any backend you configure (see [Setup](#setup)).

## The problem

Maps apps know where restaurants are. They don't know whether the bathroom inside is free, needs a key, has a changing table or a line out the door. Pitstop is a shared, rated map of bathrooms with the details that matter, built to work with no signal and to get you to the closest one in a single tap.

## Features

- **Map and list.** Pins colored by rating, next to Apple's own restroom points of interest. The list is searchable and sorts by distance, rating, date added or name.
- **Emergency button.** One tap opens walking directions in Apple Maps to the nearest saved bathroom by straight-line distance, with no network needed. With nothing saved locally, it asks the server for the nearest one within a widening search box.
- **Detailed entries.** Pin placement on a mini map with automatic reverse geocoding, a 1 to 5 star rating, access type (free, paid, purchase required, key required, private property), stall type, gender designation, wheelchair access, changing table, toilet paper (including a dispenser rating), bidet type, heated seat, soap, hand drying, typical wait, notes, and up to 10 photos from the library or camera.
- **Filters.** Minimum rating, maximum distance, access, stall, gender and wait time, plus nine must-have toggles. Filters apply live to both the map and the list.
- **Community signals.** "Still Here? Verify" keeps a verification count and last-verified date. Anyone can report a bathroom (no longer exists, wrong location, incorrect information, inappropriate content, other). Owners can edit, delete, or mark an entry private.
- **Photos.** A thumbnail carousel on each bathroom and a full-screen viewer with paging, pinch to zoom and swipe to dismiss.
- **Accounts.** Email and password sign-up with email confirmation and password reset, or Sign in with Apple. A profile sheet with an editable display name and a count of saved bathrooms. A revoked Apple credential signs the user out on the next launch.
- **Offline first.** Everything is written locally first. Changes queue while offline and replay when the connection returns, with an offline banner and a pending-changes badge in the meantime.
- **Accessibility.** VoiceOver labels on pins and rows, an adjustable star rating control, and animations that respect Reduce Motion.

## How it works

```
 SwiftUI views ──read──> SwiftData store <──sync── SupabaseService <──> hosted Postgres + storage
      │                                                  ▲
      └──write──> SwiftData + SyncQueue ──drain──────────┘
                  (JSON on disk)
```

- **Local store is the source of truth for the UI.** Views read from SwiftData, so the app behaves the same online and offline. Photos are stored on disk as a full-size JPEG and a 200px thumbnail per image, with in-memory caches.
- **Writes go through a queue.** Saving a bathroom writes to SwiftData and enqueues operations (upsert bathroom, delete bathroom, upload photo, delete photos) on `SyncQueue`, which persists them as JSON. The queue drains immediately when online and again whenever `NetworkMonitor` reports the connection is back. Every operation is an upsert or a delete, so replaying one after a crash or partial failure is safe.
- **Reads are delta syncs by location.** On appear, the app pulls bathrooms in a box around the user, and after the first sync only rows whose `updated_at` is newer than the last sync. Conflicts resolve last write wins. A box that crosses the 180th meridian is split into two queries and merged, since one longitude range can't express it.
- **Backend.** A hosted Postgres database with row-level security, object storage for photos, and auth for email and Apple sign-in. Private bathrooms and ownership rules are enforced on the server, not in the app.

## Worth a look

| File | Why |
|---|---|
| [`SyncQueue.swift`](Pitstop/Pitstop/SyncQueue.swift) | The offline queue: persisted operations, de-duplication of repeated operations, and an idempotent drain. |
| [`SupabaseService.swift`](Pitstop/Pitstop/SupabaseService.swift) | Location-based delta sync (`fetchBoundingBox`) with the antimeridian split, plus the widening nearest-bathroom search. |
| [`EmergencyButton.swift`](Pitstop/Pitstop/EmergencyButton.swift), [`MapURLHelper.swift`](Pitstop/Pitstop/MapURLHelper.swift) | The one-tap emergency flow and handoff to Apple Maps walking directions. |
| [`NonceCrypto.swift`](Pitstop/Pitstop/NonceCrypto.swift), [`AppleSignInButtonView.swift`](Pitstop/Pitstop/AppleSignInButtonView.swift) | Sign in with Apple: a cryptographically random nonce, its SHA-256 hash sent to Apple, and the raw value passed to the backend. |
| [`FlowLayout.swift`](Pitstop/Pitstop/FlowLayout.swift) | A custom SwiftUI `Layout` that wraps filter chips onto rows like text. |
| [`PhotoResolver.swift`](Pitstop/Pitstop/PhotoResolver.swift) | Resolves a photo from memory, then disk, then the server, caching what it downloads. |

## Requirements

- Xcode 26.3 or later
- iOS 26.2 or later
- A backend project with Postgres, storage and auth (only needed for sign-in and sync)

## Setup

1. Clone the repo and open `Pitstop/Pitstop.xcodeproj`. Swift Package Manager resolves the pinned dependencies.
2. Copy the config template and fill in your backend URL and publishable key:

   ```sh
   cp Pitstop/Config.xcconfig.example Pitstop/Config.xcconfig
   ```

   `Config.xcconfig` is gitignored. The values reach the app through `Info.plist`. The publishable key is a public identifier; row-level security on the server is what controls access. Without a config the app still builds and launches, but sign-in and sync will fail.
3. To use Sign in with Apple on a device, set your own development team and bundle identifier. The entitlement is already in `Pitstop.entitlements`.
4. Build and run the `Pitstop` scheme.

## Screenshots

<!-- SCREENSHOTS: add captures of the map, list, detail sheet, add form and filter sheet here. -->
_Not yet captured._

## Project layout

```
Pitstop/
├── Base.xcconfig               Shared build settings, includes Config.xcconfig
├── Config.xcconfig.example     Backend config template
├── Info.plist                  Exposes backend config to the app
└── Pitstop/
    ├── PitstopApp.swift        Entry point, auth gate, queue drain on reconnect
    ├── ContentView.swift       Map/List switcher, toolbar, emergency button
    ├── MapTabView.swift        Map with rating-colored pins
    ├── ListTabView.swift       Searchable, sortable list
    ├── DetailView.swift        Bathroom detail sheet
    ├── AddBathroomView.swift   Add and edit form
    ├── FilterSheetView.swift   Live filters
    ├── ReportView.swift        Report an issue
    ├── ProfileView.swift       Profile and sign-out
    ├── LoginView.swift         Email and Apple sign-in
    ├── Bathroom.swift          SwiftData model
    ├── RemoteBathroom.swift    Server row mapping
    ├── SupabaseService.swift   Auth, sync, storage, reports
    ├── SyncQueue.swift         Offline operation queue
    ├── ImageStorage.swift      On-disk photo storage and caches
    ├── PhotoResolver.swift     Local-then-remote photo loading
    └── ...                     Supporting views and helpers
```

## License

[MIT](LICENSE)
