# GeoPoop

An iOS app for logging and finding public bathrooms. Built purely to learn iOS development — SwiftUI, MapKit, SwiftData, and Supabase.

> **This is a personal learning project, not a production app.** Code quality, architecture, and features reflect what I was exploring at the time, not a polished product.

---

## What it does

- **Map view** — see all your logged bathrooms as pins on a MapKit map
- **List view** — sortable and searchable list with distance, rating, and tags
- **Add bathrooms** — name, star rating, tags (clean, free, accessible, etc.), photos, and notes
- **Filter** — narrow results by rating, tags, distance, and date
- **Emergency button** — one tap to get directions to the nearest saved bathroom via Apple Maps
- **Cloud sync** — bathrooms sync to Supabase so data survives reinstalls
- **Offline support** — changes queue locally and sync when back online
- **Auth** — email/password login via Supabase Auth

## Tech stack

| | |
|---|---|
| UI | SwiftUI |
| Local persistence | SwiftData |
| Maps | MapKit |
| Backend + auth | [Supabase](https://supabase.com) |
| Image storage | Supabase Storage |

**Requirements:** Xcode 15+, iOS 17+

---

## Running it

You need your own Supabase project. Update `GeoPoop/SupabaseConfig.swift` with your credentials:

```swift
static let projectURL    = URL(string: "https://your-project.supabase.co")!
static let publishableKey = "your-anon-key"
```

Then open `GeoPoop/GeoPoop.xcodeproj` in Xcode and run.

> The anon/publishable key is safe to commit — it's a project identifier, not a secret. Row Level Security in Supabase is the actual security layer.

---

## Project structure

```
GeoPoop/
├── GeoPoopApp.swift           # App entry, singletons, auth gate
├── ContentView.swift           # Root Map ↔ List segmented view
│
├── MapTabView.swift            # MapKit map with bathroom pins
├── ListTabView.swift           # Sortable, searchable list
├── DetailView.swift            # Bathroom detail sheet
├── AddBathroomView.swift       # Add/edit form (full-screen modal)
├── FilterSheetView.swift       # Filter panel
├── LoginView.swift             # Sign in / sign up / forgot password
│
├── Bathroom.swift              # SwiftData local model
├── RemoteBathroom.swift        # Supabase response shape
├── BathroomAttributes.swift    # Tags, attributes, enums
├── BathroomFilter.swift        # Filter state model
│
├── SupabaseService.swift       # All Supabase API calls
├── SupabaseConfig.swift        # Project URL + anon key
├── SyncQueue.swift             # Offline operation queue
├── NetworkMonitor.swift        # Connectivity state
├── LocationManager.swift       # CoreLocation wrapper
├── ImageStorage.swift          # Photo upload/download
└── PhotoResolver.swift         # Local vs. remote photo routing
```

---

## Why "GeoPoop"?

Because sometimes you urgently need a bathroom, and that turned out to be a perfectly reasonable iOS learning project.
