//
//  Bathroom.swift
//  Pitstop
//
//  The core data model for a saved bathroom entry.
//  Stored locally with SwiftData — no .xcdatamodeld file needed.
//
//  ── SwiftData @Model Macro ────────────────────────────────────────────────
//
//  The @Model macro synthesises everything Core Data required a
//  .xcdatamodeld file for: it marks the class as a PersistentModel, generates
//  the backing store schema, and wires up observation so @Query-decorated
//  properties in views automatically re-render when a Bathroom changes.
//
//  `final class` (not struct) is required by SwiftData — models must be
//  reference types so the framework can track identity and mutations through
//  its persistence layer.
//
//  ── Property Groups ───────────────────────────────────────────────────────
//
//  Properties are organised into logical groups that map to the sections of
//  the AddBathroomView form, making it easy to see which part of the UI each
//  field serves:
//
//    Identity & Location    — id, name, lat/lon, address
//    Dates                  — dateVisited, dateCreated, dateModified
//    Rating                 — overall 1–5 star quality score
//    Access & Availability  — how you get in, receipt code, 24-hour flag
//    Layout                 — stall type, gender, indoor, wheelchair
//    Toilet Paper           — availability, extras, dispenser quality
//    Fixtures               — heated seat, bidet type, changing table
//    Hygiene                — soap, hand drying, typical wait time
//    Notes & Photos         — free-form text, saved JPEG file names
//    Cloud / Privacy        — isPrivate flag, ownerID
//
//  ── isPrivate / ownerID Cloud Fields ─────────────────────────────────────
//
//  These two properties were added when cloud sync (Supabase) was integrated:
//
//    isPrivate — mirrors the `is_private` column in Supabase. When true,
//      SupabaseService includes a row-level security filter so the record is
//      only returned to the owning user's session. Public bathrooms are visible
//      to all authenticated users. Defaults to false (public) so the most
//      common case requires no extra action from the user.
//
//    ownerID — the Supabase auth UUID (stringified) of the user who created
//      the entry. Used by row-level security policies to enforce that only the
//      owner can edit or delete their own bathroom. Stored as a String rather
//      than UUID because Supabase UUIDs arrive as JSON strings, and converting
//      back and forth on every sync would be unnecessary overhead.
//      An empty string signals a record created before cloud integration
//      (during the SwiftData-only phase of development).
//
//  ── Legacy Tag Stubs ─────────────────────────────────────────────────────
//
//  An earlier version of the model used a free-form [String] tags array
//  (e.g., ["has-soap", "wheelchair-accessible"]) to describe amenities.
//  That approach was replaced by dedicated typed properties (hasSoap,
//  isWheelchairAccessible, etc.) because:
//    • Typed properties are enforceable at compile time.
//    • They integrate cleanly with SwiftData predicates and filter logic.
//    • Enum-backed attributes get display helpers (icon, color, displayName)
//      without ad-hoc string matching.
//
//  The static `predefinedTags` array and `displayName(for:)` helper are kept
//  in the Legacy Tag Support extension so TagChip and TagToggleChip (UI
//  components that predate the refactor) still compile. They are candidates
//  for removal once those components are retired.
//

import Foundation
import CoreLocation
import SwiftData

@Model
final class Bathroom {

    // MARK: - Identity

    /// Stable UUID that uniquely identifies this bathroom across devices.
    ///
    /// @Attribute(.unique) creates a database-level uniqueness constraint so
    /// SwiftData throws if two records with the same id are inserted — this
    /// guards against duplicate rows during cloud sync.
    ///
    /// The id also doubles as the image-storage folder name:
    ///   `Documents/BathroomImages/{id}/photo.jpg`
    /// Using the same UUID avoids a separate lookup table between records
    /// and their on-disk images.
    @Attribute(.unique) var id: UUID

    // MARK: - Location

    /// Human-readable name for the bathroom's location (e.g. "Blue Bottle Coffee").
    var name:      String

    /// WGS-84 latitude in decimal degrees. Stored as Double (64-bit) for
    /// the ~1 cm precision CoreLocation provides — Float would lose ~1 m.
    var latitude:  Double

    /// WGS-84 longitude in decimal degrees.
    var longitude: Double

    /// Human-readable address from reverse geocoding (CLGeocoder).
    /// Nil when geocoding has not been attempted or when it failed (e.g., no
    /// network connection at save time). The app falls back to showing
    /// coordinates in the UI when this is nil.
    var address: String?

    // MARK: - Dates

    /// When the user physically visited this bathroom. User-settable so they
    /// can log a visit that happened earlier in the day. Defaults to Date().
    var dateVisited:  Date

    /// When the record was first created in the local store. Set once in
    /// init() and never updated — used for "recently added" sort ordering.
    var dateCreated:  Date

    /// Timestamp of the last local or cloud-sync modification. Updated by
    /// SupabaseService on each sync so the list can show "last updated" info
    /// and resolve conflicts (last-write-wins on the cloud).
    var dateModified: Date

    // MARK: - Overall Rating

    /// Overall quality score on a 1–5 star scale.
    ///
    /// 0 = not yet rated. The UI treats 0 differently from 1 (renders as
    /// "unrated" rather than "1 star") so the default zero is meaningful.
    var rating: Int

    // MARK: - Access & Availability

    /// How the bathroom is accessed (free, paid, key required, etc.).
    /// BathroomAccess is Codable so SwiftData stores the raw String value
    /// and reconstructs the enum on read.
    var accessType: BathroomAccess

    /// True when a receipt code is required to unlock the door (typically
    /// for `purchaseRequired` bathrooms). Shown as an extra warning in the
    /// detail view so the user knows to keep their receipt.
    var requiresReceiptCode: Bool

    /// True when the bathroom is accessible around the clock (e.g. a 24-hour
    /// gas station). False means hours are unknown or limited.
    var isOpen24Hours: Bool

    // MARK: - Layout

    /// Single private room vs. multi-stall facility.
    /// Single-occupancy bathrooms are generally preferred in an emergency
    /// because they have a lockable door and no queue.
    var stallType: StallType

    /// Gender designation for this bathroom (all-gender, men, women, family).
    var genderType: GenderType

    /// True = indoors (mall, café, office); false = outdoor or portable unit.
    /// Outdoor bathrooms are flagged in the list so users can prepare
    /// appropriately in bad weather.
    var isIndoor: Bool

    /// True when the bathroom meets wheelchair / ADA accessibility standards
    /// (wide stall, grab bars, lowered fixtures). False if unknown or
    /// not accessible.
    var isWheelchairAccessible: Bool

    // MARK: - Toilet Paper

    /// Whether toilet paper was present at the time of the last visit.
    var hasToiletPaper: Bool

    /// True when spare/extra rolls are stocked beyond the active roll.
    /// Differentiates "one nearly-empty roll" from "well stocked".
    var hasExtraToiletPaper: Bool

    /// Quality rating of the toilet paper dispenser on a 0–5 scale.
    /// 0 = no dedicated dispenser (paper left on the tank, etc.) or unknown.
    /// 1–5 = present and rated (5 = premium multi-roll dispenser).
    var dispenserRating: Int

    // MARK: - Fixtures

    /// Whether the toilet seat is heated. A luxury worth calling out.
    var hasHeatedSeat: Bool

    /// Type of bidet feature: none, handheld spray attachment, or full
    /// electronic washlet seat.
    var bidetType: BidetType

    /// Whether a baby/child changing table is available. Particularly
    /// important for users travelling with infants.
    var hasChangingTable: Bool

    // MARK: - Hygiene

    /// Whether soap is available at the sink. False includes "dispenser
    /// present but empty", which is an unfortunately common scenario.
    var hasSoap: Bool

    /// Whether paper towels or a hand dryer are available. False means
    /// air-dry or bring your own.
    var hasDryingOption: Bool

    /// Typical busyness / expected wait time at this bathroom.
    var waitTime: WaitTime

    // MARK: - Notes & Photos

    /// Free-form text for anything the structured fields don't cover —
    /// tips, caveats, access instructions, or general commentary.
    var notes: String

    /// File names of JPEG images stored under:
    ///   `<Documents>/BathroomImages/<id>/<filename>`
    ///
    /// File names (not full paths) are stored so the array remains valid
    /// if the app's sandbox Documents directory path changes across iOS
    /// upgrades — the root path is reconstructed at read time.
    var imageFileNames: [String]

    // MARK: - Community Verification

    /// Number of distinct users who have tapped "Still Here?" to confirm
    /// this bathroom still exists. Incremented server-side on each verification.
    /// Higher counts indicate more reliable data.
    var verificationCount: Int

    /// The last time any user confirmed this bathroom was still accessible.
    /// Nil for newly added bathrooms that haven't been verified yet.
    /// Used to surface a "may be outdated" warning after 180+ days.
    var lastVerifiedAt: Date?

    // MARK: - Cloud / Privacy

    /// When true, this bathroom is only visible to its owner in the cloud.
    ///
    /// Supabase row-level security enforces this on the server side, so
    /// even a direct API call from another user's session cannot read a
    /// private record. Defaults to false (public) so new bathrooms are
    /// shared with the community unless the user opts out.
    var isPrivate: Bool

    /// Supabase auth UUID (as a String) of the user who created this entry.
    ///
    /// Stored as a String because:
    ///   1. Supabase returns UUIDs as JSON strings — no conversion needed.
    ///   2. UUID(uuidString:) is failable; storing as String avoids
    ///      unwrapping on every sync.
    ///
    /// Empty string for records created before cloud integration was added.
    /// SupabaseService populates this field automatically on upload using
    /// the currently authenticated user's session ID.
    var ownerID: String

    // MARK: - Init

    init(
        id:                     UUID           = UUID(),
        name:                   String,
        latitude:               Double,
        longitude:              Double,
        address:                String?        = nil,
        rating:                 Int            = 0,
        accessType:             BathroomAccess = .free,
        requiresReceiptCode:    Bool           = false,
        isOpen24Hours:          Bool           = false,
        stallType:              StallType      = .single,
        genderType:             GenderType     = .allGender,
        isIndoor:               Bool           = true,
        isWheelchairAccessible: Bool           = false,
        hasToiletPaper:         Bool           = true,
        hasExtraToiletPaper:    Bool           = false,
        dispenserRating:        Int            = 0,
        hasHeatedSeat:          Bool           = false,
        bidetType:              BidetType      = .none,
        hasChangingTable:       Bool           = false,
        hasSoap:                Bool           = true,
        hasDryingOption:        Bool           = true,
        waitTime:               WaitTime       = .unknown,
        notes:                  String         = "",
        dateVisited:            Date           = Date(),
        dateCreated:            Date?          = nil,
        imageFileNames:         [String]       = [],
        isPrivate:              Bool           = false,
        ownerID:                String         = "",
        verificationCount:      Int            = 0,
        lastVerifiedAt:         Date?          = nil
    ) {
        self.id                     = id
        self.name                   = name
        self.latitude               = latitude
        self.longitude              = longitude
        self.address                = address
        self.rating                 = rating
        self.accessType             = accessType
        self.requiresReceiptCode    = requiresReceiptCode
        self.isOpen24Hours          = isOpen24Hours
        self.stallType              = stallType
        self.genderType             = genderType
        self.isIndoor               = isIndoor
        self.isWheelchairAccessible = isWheelchairAccessible
        self.hasToiletPaper         = hasToiletPaper
        self.hasExtraToiletPaper    = hasExtraToiletPaper
        self.dispenserRating        = dispenserRating
        self.hasHeatedSeat          = hasHeatedSeat
        self.bidetType              = bidetType
        self.hasChangingTable       = hasChangingTable
        self.hasSoap                = hasSoap
        self.hasDryingOption        = hasDryingOption
        self.waitTime               = waitTime
        self.notes                  = notes
        self.dateVisited            = dateVisited
        // dateCreated: use caller-supplied value (for cloud sync restoring original
        // creation time) or Date() for brand-new local records.
        self.dateCreated            = dateCreated ?? Date()
        self.dateModified           = Date()
        self.imageFileNames         = imageFileNames
        self.isPrivate              = isPrivate
        self.ownerID                = ownerID
        self.verificationCount      = verificationCount
        self.lastVerifiedAt         = lastVerifiedAt
    }

    // MARK: - Computed Properties

    /// Convenience accessor that bundles latitude + longitude into the struct
    /// expected by MapKit and CoreLocation APIs.
    ///
    /// Not stored as a CLLocationCoordinate2D directly because SwiftData
    /// cannot persist that struct natively — it must be decomposed into
    /// two Doubles.
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Straight-line distance in metres from a given CLLocation to this bathroom.
    ///
    /// Used by ContentView's emergency handler to find the nearest bathroom.
    /// CLLocation.distance(from:) uses the WGS-84 ellipsoid model, giving
    /// accurate results globally with no network dependency.
    func distance(from location: CLLocation) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude).distance(from: location)
    }
}

