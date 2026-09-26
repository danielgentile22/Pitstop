# Pitstop — Design Document

---

## 1. UX Flow Map

```
┌─────────────────────────────────────────────────────────────┐
│                        APP LAUNCH                           │
│                            │                                │
│                   Location Permission                       │
│                   ┌────────┼────────┐                       │
│                   ▼        ▼        ▼                       │
│               Granted   Denied   Restricted                 │
│                   │        │        │                       │
│                   │     Show Settings    Show Error          │
│                   │     Prompt           Message             │
│                   ▼                                          │
│  ┌──────────────────────────────────────────────────┐       │
│  │              MAIN SCREEN                          │       │
│  │  ┌────────────────────────────────────────────┐  │       │
│  │  │    [Map View]  ◄──Segmented──►  [List View]│  │       │
│  │  └────────────────────────────────────────────┘  │       │
│  │                                                   │       │
│  │  Map View                    List View            │       │
│  │  ├─ Tap Pin ──────┐         ├─ Tap Row ───┐     │       │
│  │  │                ▼         │              ▼     │       │
│  │  │         ┌─────────────┐  │    ┌─────────────┐│       │
│  │  │         │ Detail View │  │    │ Detail View ││       │
│  │  │         │             │  │    │             ││       │
│  │  │         │ ├─ Edit ────┼──┼──► │ Edit Screen ││       │
│  │  │         │ ├─ Delete ──┼──┼──► │ Confirm     ││       │
│  │  │         │ │  (alert)  │  │    │ ├─Yes: Back ││       │
│  │  │         │ │           │  │    │ └─No: Stay  ││       │
│  │  │         └─────────────┘  │    └─────────────┘│       │
│  │                                                   │       │
│  │  Shared Actions (available in both views):        │       │
│  │  ├─ [+] Button ──────────► Add Bathroom Screen   │       │
│  │  ├─ [Filter] Button ─────► Filter Sheet (bottom)  │       │
│  │  └─ [Emergency] Button ──► External Maps App      │       │
│  │                             (directions to nearest)│       │
│  └──────────────────────────────────────────────────┘       │
│                                                              │
│  ┌──────────────────────────────────────────────────┐       │
│  │          ADD BATHROOM SCREEN                      │       │
│  │  ├─ Auto-fills current location                   │       │
│  │  ├─ Adjust pin on mini-map                        │       │
│  │  ├─ Fill in: name, rating, notes, tags, photos    │       │
│  │  ├─ [Save] ──► Back to Main Screen (new pin)      │       │
│  │  └─ [Cancel] ─► Back to Main Screen (no changes)  │       │
│  └──────────────────────────────────────────────────┘       │
│                                                              │
│  ┌──────────────────────────────────────────────────┐       │
│  │          FILTER SHEET                             │       │
│  │  ├─ Rating (minimum stars)                        │       │
│  │  ├─ Tags (multi-select)                           │       │
│  │  ├─ Distance radius                               │       │
│  │  ├─ Date range                                    │       │
│  │  ├─ [Apply] ──► Dismiss, filtered results shown   │       │
│  │  └─ [Reset] ──► Clear all filters                 │       │
│  └──────────────────────────────────────────────────┘       │
└─────────────────────────────────────────────────────────────┘
```

### Navigation Model
- **Main Screen:** `NavigationStack` at root (required for `.searchable` and `.toolbar` to work on List View)
- **Detail View:** Presented as `.sheet` with `presentationDetents([.medium, .large])` — starts at half-height as a preview card, draggable to full
- **Add Bathroom:** Presented as `.fullScreenCover` (full modal, cannot swipe to dismiss — must tap Cancel/Save)
- **Edit Screen:** Reuses `AddBathroomView` in edit mode, presented as `.fullScreenCover` from within Detail View
- **Filter Sheet:** Presented as `.sheet` with `presentationDetents([.medium, .large])` (half-height default, draggable to full)
- **Emergency:** No in-app navigation — opens external Maps app via URL scheme

### Edge Cases in Navigation
- **Location denied:** App still opens to Map View but shows banner "Location access needed" with button to open Settings
- **Location denied + Emergency tap:** Show alert "Enable location in Settings to find the nearest bathroom"
- **Emergency + no saved bathrooms:** Show alert "No bathrooms saved yet. Add your first!"
- **Emergency + no current location:** Show alert with Settings redirect
- **Unsaved changes on Add/Edit:** Show confirmation alert "Discard changes?" before dismissing

---

## 2. Wireframes

### Screen 1: Map View (Default Home Screen)

```
┌─────────────────────────────────┐
│   Pitstop            [filter] [+] │  ← Navigation bar (no back button — this is root)
├─────────────────────────────────┤
│  [ Map  |  List ]               │  ← Segmented control
├─────────────────────────────────┤
│                                 │
│         ┌───┐                   │
│         │ 📍│                   │  ← Saved bathroom pin
│         └───┘                   │
│                                 │
│                    ┌───┐        │
│              ┌───┐ │ 📍│        │
│              │ 📍│ └───┘        │
│              └───┘              │
│                                 │  ← Full MapKit map
│                                 │
│           ┌───┐                 │
│           │ 🔵│                 │  ← User location (blue dot)
│           └───┘                 │
│                                 │
│                                 │
│                                 │
│                         ┌─────┐ │
│                         │ 🚨  │ │  ← Emergency FAB
│                         │     │ │     (floating action button)
│                         └─────┘ │     bottom-right
└─────────────────────────────────┘
```

**Interactions:**
- Tap pin → shows callout bubble with name + rating
- Tap callout → opens Detail Sheet
- Tap [+] → opens Add Bathroom screen
- Tap [filter] → opens Filter Sheet
- Tap 🚨 → calculates nearest, opens Maps app with directions
- Swipe segmented control → switches to List View

---

### Screen 2: List View

```
┌─────────────────────────────────┐
│   Pitstop            [filter] [+] │
├─────────────────────────────────┤
│  [ Map  |  List ]               │
├─────────────────────────────────┤
│ 🔍 Search bathrooms...          │  ← Search bar
├─────────────────────────────────┤
│ Sort: Distance ▼                │  ← Sort picker
├─────────────────────────────────┤
│ ┌─────────────────────────────┐ │
│ │ 🖼  Starbucks on Main       │ │
│ │     ★★★★☆  ·  0.3 mi       │ │
│ │     Clean, Free              │ │  ← Tags as chips
│ └─────────────────────────────┘ │
│ ┌─────────────────────────────┐ │
│ │ 🖼  Central Park Restroom   │ │
│ │     ★★★☆☆  ·  0.8 mi       │ │
│ │     Accessible               │ │
│ └─────────────────────────────┘ │
│ ┌─────────────────────────────┐ │
│ │ 🖼  Grand Central Terminal  │ │
│ │     ★★★★★  ·  1.2 mi       │ │
│ │     Clean, Free, Accessible  │ │
│ └─────────────────────────────┘ │
│                                 │
│                                 │
│                         ┌─────┐ │
│                         │ 🚨  │ │
│                         └─────┘ │
└─────────────────────────────────┘
```

**Interactions:**
- Tap row → opens Detail Sheet
- Swipe row left → Delete (with confirmation)
- Pull down → (no refresh needed, local data)
- Sort picker → Distance / Rating / Date Added / Name
- Search bar → filters list in real-time by name

**Empty State (no saved bathrooms):**
```
┌─────────────────────────────────┐
│   Pitstop            [filter] [+] │
├─────────────────────────────────┤
│  [ Map  |  List ]               │
├─────────────────────────────────┤
│                                 │
│                                 │
│           🚽                    │
│                                 │
│    No bathrooms saved yet.      │
│    Tap + to add your first!     │
│                                 │
│                                 │
└─────────────────────────────────┘
```

---

### Screen 3: Detail View (Sheet)

```
┌─────────────────────────────────┐
│ ─────  (drag handle)            │  ← Sheet presentation
├─────────────────────────────────┤
│                                 │
│  Starbucks on Main        [✏️]  │  ← Name + Edit button
│  ★★★★☆                         │  ← Star rating
│                                 │
├─────────────────────────────────┤
│  ┌───────┐ ┌───────┐ ┌───────┐ │
│  │       │ │       │ │       │ │  ← Photo carousel
│  │ Photo │ │ Photo │ │ Photo │ │     (horizontal scroll)
│  │   1   │ │   2   │ │   3   │ │
│  └───────┘ └───────┘ └───────┘ │
├─────────────────────────────────┤
│                                 │
│  📍 123 Main St, New York      │  ← Address
│  📅 Visited: Jan 15, 2026      │  ← Date
│  📏 0.3 miles away             │  ← Distance from user
│                                 │
├─────────────────────────────────┤
│  Tags:                          │
│  ┌───────┐ ┌──────┐ ┌────┐    │
│  │ Clean │ │ Free │ │ ADA│    │  ← Tag chips
│  └───────┘ └──────┘ └────┘    │
│                                 │
├─────────────────────────────────┤
│  Notes:                         │
│  "Second floor, past the        │
│   register. Code is 1234.       │
│   Usually very clean."          │
│                                 │
├─────────────────────────────────┤
│                                 │
│  ┌─────────────────────────┐   │
│  │   🗺  Open in Maps      │   │  ← Opens Maps with directions
│  └─────────────────────────┘   │
│                                 │
│  ┌─────────────────────────┐   │
│  │   🗑  Delete             │   │  ← Red, destructive
│  └─────────────────────────┘   │
│                                 │
└─────────────────────────────────┘
```

---

### Screen 4: Add Bathroom

```
┌─────────────────────────────────┐
│ Cancel    Add Bathroom    Save  │  ← Toolbar (Save disabled
├─────────────────────────────────┤     until name is filled)
│                                 │
│  ┌─────────────────────────┐   │
│  │                         │   │
│  │     Mini Map            │   │  ← Small map with
│  │         📍              │   │     draggable pin
│  │     (drag to adjust)    │   │     auto-centered on
│  │                         │   │     current location
│  └─────────────────────────┘   │
│  📍 123 Main St, New York      │  ← Auto-filled address
│                                 │
├─────────────────────────────────┤
│                                 │
│  Name                           │
│  ┌─────────────────────────┐   │
│  │                         │   │  ← Text field
│  └─────────────────────────┘   │
│                                 │
│  Rating                         │
│  ☆ ☆ ☆ ☆ ☆                     │  ← Tappable stars
│                                 │
│  Tags                           │
│  ┌──────┐┌─────┐┌──────────┐  │
│  │Clean ││Free ││Accessible│  │  ← Toggle chips
│  └──────┘└─────┘└──────────┘  │     (pre-defined set)
│  ┌────────────┐┌────────┐     │
│  │Key Required││Private │     │
│  └────────────┘└────────┘     │
│                                 │
│  Photos                         │
│  ┌──────┐ ┌──────┐            │
│  │  +   │ │  📷  │            │  ← Add from library
│  │ Add  │ │ Take │            │     or take photo
│  └──────┘ └──────┘            │
│                                 │
│  Notes                          │
│  ┌─────────────────────────┐   │
│  │                         │   │  ← Multi-line text
│  │                         │   │
│  └─────────────────────────┘   │
│                                 │
│  Date Visited                   │
│  ┌─────────────────────────┐   │
│  │ March 12, 2026    ▼     │   │  ← Date picker
│  └─────────────────────────┘   │
│                                 │
└─────────────────────────────────┘
```

---

### Screen 5: Filter Sheet

```
┌─────────────────────────────────┐
│ ─────  (drag handle)            │  ← Half-height sheet
├─────────────────────────────────┤     (draggable to full)
│ Reset               Apply       │
├─────────────────────────────────┤
│                                 │
│  Minimum Rating                 │
│  ★ ★ ★ ☆ ☆    (3 and up)      │  ← Tappable stars
│                                 │
├─────────────────────────────────┤
│                                 │
│  Tags (any match)               │
│  ┌──────┐┌─────┐┌──────────┐  │
│  │▪Clean││ Free││▪Accessible│  │  ← Toggle on/off
│  └──────┘└─────┘└──────────┘  │     (▪ = selected)
│  ┌────────────┐┌────────┐     │
│  │Key Required││Private │     │
│  └────────────┘└────────┘     │
│                                 │
├─────────────────────────────────┤
│                                 │
│  Max Distance                   │
│  ○ 0.5 mi  ○ 1 mi  ● 5 mi     │  ← Segmented or slider
│  ○ 10 mi   ○ Any                │
│                                 │
├─────────────────────────────────┤
│                                 │
│  Date Range                     │
│  From: [  Any       ▼ ]        │  ← Optional date pickers
│  To:   [  Any       ▼ ]        │
│                                 │
└─────────────────────────────────┘
```

---

### Screen 6: Emergency Flow (No Screen — External Handoff)

```
User taps 🚨 Emergency button
         │
         ▼
┌─────────────────────────────┐
│ App calculates nearest       │
│ saved bathroom from          │
│ user's current location      │
├─────────────────────────────┤
│         │                    │
│    Has saved     No saved    │
│    bathrooms?    bathrooms   │
│         │              │     │
│         ▼              ▼     │
│   Open Apple Maps   Show     │
│   with directions   alert:   │
│   to nearest        "No      │
│                     saved    │
│                     spots"   │
└─────────────────────────────┘

Apple Maps opens with (try new URL first, fallback for older iOS):
  Primary (iOS 18.4+): https://maps.apple.com/directions?destination=LAT,LONG&mode=walking
  Fallback (iOS 17):   maps://?daddr=LAT,LONG&dirflg=w

Optional Google Maps (if installed):
  comgooglemaps://?daddr=LAT,LONG&directionsmode=walking
  (requires LSApplicationQueriesSchemes entry in Info.plist)
```

---

## 3. Design System

### Philosophy
**100% native Apple.** The app should feel like it ships with iOS. No custom fonts, no custom button styles, no brand colors fighting the system. Let SwiftUI and Human Interface Guidelines do the heavy lifting.

### Colors

| Token                  | SwiftUI Value          | Usage                          |
|------------------------|------------------------|--------------------------------|
| Primary Accent         | `.blue` (system)       | Buttons, links, selected state |
| Emergency              | `.red` (system)        | Emergency button, delete       |
| Star Rating (filled)   | `.yellow` (system)     | Filled star icons              |
| Star Rating (empty)    | `.gray.opacity(0.3)`   | Empty star outlines            |
| Pin Color (high rated) | `.green` (system)      | 4-5 star bathrooms on map      |
| Pin Color (mid rated)  | `.orange` (system)     | 3 star bathrooms on map        |
| Pin Color (low rated)  | `.red` (system)        | 1-2 star bathrooms on map      |
| Background             | (system default)       | Auto light/dark mode           |
| Card Background        | `.secondarySystemGroupedBackground` | List rows, cards  |
| Primary Text           | `.primary`             | Titles, names                  |
| Secondary Text         | `.secondary`           | Subtitles, distances, dates    |
| Tag Chip Background    | `.secondarySystemFill` | Tag pill backgrounds           |
| Tag Chip Text          | `.primary`             | Tag text                       |

**Dark mode:** Fully automatic. All colors above adapt with zero extra work.

### Typography

All system defaults. No custom fonts.

| Style             | SwiftUI Modifier    | Usage                        |
|-------------------|---------------------|------------------------------|
| Large Title       | `.largeTitle`       | (not used — no drill-down)   |
| Title             | `.title2` + `.bold` | Bathroom name in Detail View |
| Headline          | `.headline`         | Bathroom name in List row    |
| Subheadline       | `.subheadline`      | Distance, date, address      |
| Body              | `.body`             | Notes, descriptions          |
| Caption           | `.caption`          | Tag text, metadata           |
| Caption 2         | `.caption2`         | Timestamps, fine print       |

### Icons (SF Symbols)

| Purpose            | SF Symbol Name               | Usage                    |
|--------------------|------------------------------|--------------------------|
| Bathroom pin       | `toilet.fill`                | Map pin marker           |
| Emergency          | `exclamationmark.triangle.fill` | Emergency FAB         |
| Add                | `plus`                       | Add button in nav bar    |
| Filter             | `line.3.horizontal.decrease` | Filter button in nav bar |
| Star (filled)      | `star.fill`                  | Rating filled star       |
| Star (empty)       | `star`                       | Rating empty star        |
| Map tab            | `map.fill`                   | Segmented control        |
| List tab           | `list.bullet`                | Segmented control        |
| Camera             | `camera.fill`                | Take photo button        |
| Photo library      | `photo.on.rectangle.angled`  | Add from library         |
| Location           | `location.fill`              | Address display          |
| Calendar           | `calendar`                   | Date display             |
| Distance           | `figure.walk`                | Distance display         |
| Directions         | `arrow.triangle.turn.up.right.circle.fill` | Open in Maps |
| Edit               | `pencil`                     | Edit button              |
| Delete             | `trash.fill`                 | Delete button            |
| Search             | `magnifyingglass`            | Search bar icon          |
| Empty state        | `toilet`                     | Empty list illustration  |
| Close/Cancel       | `xmark`                      | Dismiss sheets           |
| Checkmark          | `checkmark`                  | Selected filter tags     |

### Components

All native SwiftUI. No custom components unless necessary.

| Component           | SwiftUI Type                          | Where Used               |
|---------------------|---------------------------------------|--------------------------|
| View toggle         | `Picker` (`.segmented` style)         | Map/List switch          |
| Map                 | `Map` (MapKit)                        | Map View, Add Screen     |
| List                | `List`                                | List View                |
| Detail              | `.sheet` with `presentationDetents`   | Detail View              |
| Add screen          | `.fullScreenCover`                    | Add Bathroom             |
| Filter              | `.sheet` with `.medium` detent        | Filter Sheet             |
| Rating input        | Custom (5 tappable SF Symbol stars)   | Add/Edit/Filter          |
| Tag chips           | Custom `FlowLayout` (Layout protocol) of toggle `Button`s | Add/Edit/Filter — HStack won't wrap; need custom flow layout (~50 lines) |
| Text fields         | `TextField`, `TextEditor`             | Name, Notes              |
| Date picker         | `DatePicker`                          | Date visited             |
| Photo picker        | `PhotosPicker` (PhotosUI)             | Image selection          |
| Search              | `.searchable` modifier                | List View                |
| Sort                | `Menu` with `Picker`                  | List View                |
| Alerts              | `.alert`                              | Delete confirmation      |
| Emergency button    | `Button` + `.clipShape(Circle())`     | Floating overlay on map  |
| Map annotations     | `Annotation` (MapKit)                 | Bathroom pins            |

### Spacing & Layout

| Token         | Value  | Usage                              |
|---------------|--------|------------------------------------|
| Screen padding| 16pt   | Standard horizontal padding        |
| Card padding  | 12pt   | Inside list rows                   |
| Section gap   | 24pt   | Between sections in Detail/Add     |
| Element gap   | 8pt    | Between label and input            |
| Tag spacing   | 8pt    | Between tag chips                  |
| Corner radius | 12pt   | Cards, images, tag chips           |
| FAB size      | 56pt   | Emergency button diameter          |
| FAB offset    | 20pt   | From bottom-right corner           |
| Photo thumb   | 80pt   | Photo carousel thumbnail height    |

### Animations

All SwiftUI built-in:

| Action                    | Animation                              |
|---------------------------|----------------------------------------|
| View toggle (map/list)    | `.animation(.easeInOut)` on transition |
| Sheet presentation        | System default (spring)                |
| Pin appear on map         | `.transition(.scale)`                  |
| Filter apply              | `.animation(.default)` on list change  |
| Emergency button          | Subtle pulse `.repeatForever`          |
| Star rating tap           | `.spring(response: 0.3)`              |
| Swipe to delete           | System default                         |

---

## 4. Dependencies

### Apple Frameworks (Built-in — Zero Install)

| Framework      | Import Statement    | Purpose                                    |
|----------------|---------------------|--------------------------------------------|
| SwiftUI        | `import SwiftUI`    | All UI rendering                           |
| MapKit         | `import MapKit`     | Map display, annotations, geocoding        |
| CoreLocation   | `import CoreLocation`| GPS, user location, distance calculations |
| SwiftData      | `import SwiftData`  | Local persistent storage — modern replacement for Core Data, native SwiftUI integration via `@Model` and `@Query` (Phase 2) |
| PhotosUI       | `import PhotosUI`   | Photo picker from library                  |
| UIKit (bridge) | `import UIKit`      | Camera capture (UIImagePickerController)   |

### Third-Party Packages

**None.** Zero. The entire app is built with Apple frameworks.

### System Capabilities Required

These are toggled in Xcode under Signing & Capabilities or set in Info.plist:

| Capability                          | Info.plist Key                          | Value                                            |
|-------------------------------------|-----------------------------------------|--------------------------------------------------|
| Location (when in use)              | `NSLocationWhenInUseUsageDescription`   | "Pitstop uses your location to show nearby bathrooms and provide directions." |
| Camera                              | `NSCameraUsageDescription`              | "Pitstop uses the camera to photograph bathrooms." |
| Photo Library (read)                | `NSPhotoLibraryUsageDescription`        | "Pitstop accesses your photos to add images to bathroom entries." |
| URL Schemes (queried)               | `LSApplicationQueriesSchemes`           | `["comgooglemaps"]` — required to check if Google Maps is installed before opening |

### Deployment Target

| Setting            | Value    |
|--------------------|----------|
| iOS minimum        | 17.0     |
| Xcode minimum      | 15.0     |
| Swift version      | 5.9+     |

> iOS 17 chosen because it gives us the latest MapKit SwiftUI APIs
> (`Map` content builder with `Annotation`/`Marker`, `MapCameraPosition`, `UserAnnotation`),
> SwiftData, PhotosPicker improvements, and `ContentUnavailableView` for empty states.
> This covers iPhone XS/XR (2018) and newer — all devices with A12 Bionic or later.

---

## 5. File Structure (Planned)

```
Pitstop/
├── PitstopApp.swift                  # App entry point
├── Models/
│   └── Bathroom.swift                # Core Data entity + helpers
├── ViewModels/
│   ├── BathroomListViewModel.swift   # List data, filtering, sorting
│   └── LocationManager.swift         # CLLocationManager wrapper
├── Views/
│   ├── ContentView.swift             # Main container (segmented toggle)
│   ├── Map/
│   │   ├── MapTabView.swift          # Full map with pins
│   │   └── BathroomAnnotation.swift  # Custom map pin view
│   ├── List/
│   │   ├── ListTabView.swift         # Scrollable bathroom list
│   │   ├── BathroomRow.swift         # Single list row
│   │   └── EmptyStateView.swift      # "No bathrooms" placeholder
│   ├── Detail/
│   │   ├── DetailView.swift          # Full bathroom detail sheet
│   │   ├── PhotoCarousel.swift       # Horizontal scrolling photos
│   │   └── StarRatingView.swift      # Reusable star display
│   ├── Add/
│   │   ├── AddBathroomView.swift     # Full-screen add form
│   │   ├── MiniMapPicker.swift       # Draggable pin on small map
│   │   └── TagPickerView.swift       # Tag selection chips
│   ├── Filter/
│   │   └── FilterSheetView.swift     # Filter options sheet
│   └── Shared/
│       ├── StarRatingInput.swift     # Tappable star input
│       ├── TagChip.swift             # Single tag pill
│       └── EmergencyButton.swift     # Floating emergency FAB
├── Utilities/
│   ├── MapURLHelper.swift            # Build Apple/Google Maps URLs
│   └── DistanceFormatter.swift       # "0.3 mi" formatting
├── Layouts/
│   └── FlowLayout.swift              # Custom wrapping layout for tag chips
├── Persistence/
│   └── ImageStorage.swift            # Save/load photos to app documents
└── Assets.xcassets/                  # App icon, colors
```

Note: With SwiftData, there is no `.xcdatamodeld` file or `PersistenceController`.
The `@Model` macro on `Bathroom.swift` replaces all of that. The `ModelContainer`
is configured in `PitstopApp.swift` with a single line.

---

## 6. Data Model

This section was missing from the original document. **Critical for development.**

### Bathroom (SwiftData `@Model`)

```swift
@Model
class Bathroom {
    // Identity
    var id: UUID

    // Core fields
    var name: String                    // Required — user-given name
    var latitude: Double                // From pin placement
    var longitude: Double               // From pin placement
    var address: String?                // Reverse geocoded, may fail

    // Metadata
    var rating: Int                     // 1-5 (0 = unrated)
    var notes: String                   // Free text, can be empty
    var tags: [String]                  // e.g. ["clean", "free", "accessible"]
    var dateVisited: Date               // User-selected date
    var dateCreated: Date               // Auto-set on creation
    var dateModified: Date              // Auto-updated on edit

    // Photos
    var imageFileNames: [String]        // File names referencing app documents directory

    // Computed (not stored)
    // distance from user — calculated at runtime from LocationManager
}
```

### Predefined Tags

```
clean, free, accessible, key-required, private,
single-stall, family, outdoor, indoor, 24-hour,
customer-only, gender-neutral
```

Users select from predefined tags only (v1). Custom tags can be added in a future version.

### SwiftData Container Setup

```swift
// In PitstopApp.swift
@main
struct PitstopApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: Bathroom.self)
    }
}
```

Views query data with:
```swift
@Query(sort: \Bathroom.dateCreated, order: .reverse) var bathrooms: [Bathroom]
```

---

## 7. Image Storage Strategy

Photos are NOT stored in SwiftData (blobs bloat the database and degrade performance).

### Storage Location
```
App Documents Directory/
└── BathroomImages/
    ├── {bathroom-id}/
    │   ├── img_001.jpg
    │   ├── img_002.jpg
    │   └── img_003.jpg
    └── {another-bathroom-id}/
        └── img_001.jpg
```

### Rules
- **Format:** JPEG, compressed to 80% quality
- **Max dimension:** Resize to max 1200px on longest edge before saving (saves storage, still sharp on iPhone screens)
- **Thumbnail:** Generate a 200px thumbnail on save for list rows and carousel previews
- **Max photos per bathroom:** 10 (prevent storage abuse)
- **Deletion:** When a bathroom is deleted, delete its entire image folder
- **File names stored in model:** `imageFileNames: [String]` array stores just the file names, app constructs full path at runtime

### Helper Class
```
ImageStorage.swift
├── saveImage(bathroomId: UUID, image: UIImage) -> String?   // returns fileName
├── loadImage(bathroomId: UUID, fileName: String) -> UIImage?
├── loadThumbnail(bathroomId: UUID, fileName: String) -> UIImage?
├── deleteImage(bathroomId: UUID, fileName: String)
└── deleteAllImages(bathroomId: UUID)
```

---

## 8. Map Behavior

### Initial Region on Launch
- **If saved bathrooms exist:** Zoom to fit all saved pins with padding
- **If no saved bathrooms:** Center on user's current location at ~5km radius
- **If no location permission:** Center on a default location (e.g., center of US) at country zoom level

### User Location
```swift
@State private var position: MapCameraPosition = .userLocation(
    followsHeading: false,
    fallback: .automatic
)

Map(position: $position) {
    UserAnnotation()           // Blue dot
    ForEach(bathrooms) { b in
        Annotation(b.name, coordinate: b.coordinate) {
            BathroomAnnotation(rating: b.rating)
        }
    }
}
.mapControls {
    MapUserLocationButton()    // Re-center button
    MapCompass()
}
```

### Pin Clustering
- For v1: No clustering. Pins overlap if close together.
- For v2: Use `MKClusterAnnotation` via UIKit bridge if users accumulate 50+ bathrooms.

### Draggable Pin (Add Bathroom Screen)
SwiftUI MapKit has **no built-in draggable annotation**. Two approaches:

**Option A (Recommended — simpler):** Fixed crosshair in center of mini-map. User pans the map to position the pin. This is how Apple Maps "Drop Pin" works.

**Option B (Complex):** Use `MapReader` + `MapProxy` + tap gesture to convert screen coordinates to map coordinates. User taps to place/move pin.

We will use **Option A** — center crosshair pattern.

---

## 9. Accessibility

### VoiceOver
- All map pins: `accessibilityLabel("Bathroom: \(name), \(rating) stars, \(distance)")"`
- Emergency button: `accessibilityLabel("Emergency: find nearest bathroom")`
- Star ratings: `accessibilityValue("\(rating) out of 5 stars")`
- Tag chips: `accessibilityLabel("\(tag), \(isSelected ? "selected" : "not selected")")`
- Photo carousel: `accessibilityLabel("Photo \(index) of \(total)")`

### Dynamic Type
- All text uses system font styles (`.headline`, `.body`, etc.) — automatically scales
- Tag chips: Use `.minimumScaleFactor(0.8)` to prevent overflow
- List rows: Allow height to grow with text size

### Reduce Motion
- Check `UIAccessibility.isReduceMotionEnabled` — disable emergency button pulse animation
- Use `.animation(reduceMotion ? .none : .easeInOut)` pattern

### Color Accessibility
- Pin colors (green/orange/red) also show rating number for color-blind users
- Don't rely on color alone for any information

---

## 10. Technical Notes & Gotchas

### `.searchable` Requires NavigationStack
The `.searchable` modifier only renders a search bar when inside a `NavigationStack` or `NavigationSplitView`. The main `ContentView` MUST be wrapped in a `NavigationStack` — this contradicts the original "No NavigationStack" note and has been corrected in Section 1.

### Camera Access Requires UIKit Bridge
As of iOS 18, there is NO pure SwiftUI camera view. We must use `UIImagePickerController` wrapped in `UIViewControllerRepresentable`. `PhotosPicker` handles gallery selection only.

### Keyboard Handling for Add/Edit Form
- Use `.scrollDismissesKeyboard(.interactively)` on the Form/ScrollView
- Use `@FocusState` with a keyboard toolbar "Done" button
- Both are needed — scroll dismissal alone fails if the form doesn't scroll

### FlowLayout for Tag Chips
SwiftUI has no built-in wrapping HStack. We need a custom `FlowLayout` using the `Layout` protocol (iOS 16+, ~50 lines of code). This replaces the incorrect `HStack` reference in the components table.

### Reverse Geocoding Rate Limits
`CLGeocoder` has rate limits. Don't call it on every map pan — only call once when the user confirms pin placement (on save).

### SwiftData vs Core Data Decision
SwiftData chosen over Core Data because:
- iOS 17+ only = no backward compatibility needed
- `@Model` macro eliminates boilerplate (no managed object subclasses, no xcdatamodel files)
- `@Query` integrates natively with SwiftUI views (auto-updating)
- Same SQLite engine underneath — same performance
- Simpler migration path for schema changes

---

## 11. What's Deferred to Future Versions

| Feature | Version | Notes |
|---------|---------|-------|
| Custom user-created tags | v2 | v1 uses predefined tags only |
| Map pin clustering | v2 | Needed if 50+ bathrooms |
| iCloud sync / backup | v2 | All data is local-only in v1 — phone loss = data loss |
| Data export (JSON/CSV) | v2 | Safety net for data preservation |
| Sharing a bathroom entry | v2 | Send location to a friend |
| Widget (nearest bathroom) | v2 | iOS widget showing closest saved spot |
| Apple Watch companion | v3 | Emergency button on wrist |
| Siri Shortcuts | v3 | "Hey Siri, nearest bathroom" |

---

## 12. Senior Review Changelog

Issues found and resolved during review:

| # | Severity | Issue | Resolution |
|---|----------|-------|------------|
| 1 | **CRITICAL** | Data model section completely missing | Added Section 6 with full SwiftData model |
| 2 | **CRITICAL** | Core Data specified, but SwiftData is correct for iOS 17+ | Changed to SwiftData throughout |
| 3 | **CRITICAL** | `.searchable` requires `NavigationStack` but doc said "No NavigationStack" | Corrected Navigation Model — root view IS in NavigationStack |
| 4 | **HIGH** | No image storage strategy defined | Added Section 7 with full storage plan |
| 5 | **HIGH** | "iPhone 8S" doesn't exist; wrong device compatibility | Fixed to "iPhone XS/XR (2018) and newer" |
| 6 | **HIGH** | Draggable pin has no SwiftUI API — not acknowledged | Added Section 8 with center-crosshair solution |
| 7 | **HIGH** | Edit Screen referenced in UX flow but no wireframe | Clarified: reuses AddBathroomView in edit mode |
| 8 | **HIGH** | Apple Maps URL scheme being deprecated | Added dual URL strategy (new unified + legacy fallback) |
| 9 | **MEDIUM** | `photo.on.rectangle` SF Symbol deprecated | Changed to `photo.on.rectangle.angled` |
| 10 | **MEDIUM** | `HStack` for tag chips won't wrap | Changed to custom `FlowLayout` using Layout protocol |
| 11 | **MEDIUM** | `LSApplicationQueriesSchemes` missing for Google Maps | Added to Info.plist capabilities table |
| 12 | **MEDIUM** | Back button "◄" shown on root view wireframes | Removed — root view has no back button |
| 13 | **MEDIUM** | Emergency button: location denied case not handled | Added edge cases to Navigation Model |
| 14 | **MEDIUM** | No accessibility plan | Added Section 9 |
| 15 | **MEDIUM** | Map initial region behavior undefined | Added Section 8 |
| 16 | **LOW** | Detail View sheet detents not specified | Added `[.medium, .large]` to navigation model |
| 17 | **LOW** | Camera requires UIKit bridge — not noted | Added to Technical Notes |
| 18 | **LOW** | Keyboard handling for forms not planned | Added to Technical Notes |
| 19 | **LOW** | No mention of future features / scope boundaries | Added Section 11 |
| 20 | **LOW** | File structure still referenced Core Data files | Updated to reflect SwiftData (no xcdatamodeld) |
