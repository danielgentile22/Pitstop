//
//  BathroomAttributes.swift
//  Pitstop
//
//  All structured attribute enums for the Bathroom model.
//
//  ── Why Codable + CaseIterable on Every Enum ──────────────────────────────
//
//  Codable
//    SwiftData persists enum properties by encoding their `rawValue`. For
//    that to work, the enum must be Codable (which String-backed enums get
//    automatically via the `RawRepresentable` + `Codable` combination).
//    Codable is also required for Supabase JSON serialisation/deserialisation
//    so the same enum type can round-trip through the network layer without
//    any manual mapping code.
//
//  CaseIterable
//    Provides `allCases`, which drives ForEach loops in Picker and filter UI
//    components. Without it, every picker would need a hand-written array
//    of cases — a maintenance burden whenever a case is added or removed.
//    CaseIterable is essentially free for enums with no associated values.
//
//  ── Raw Value Choices ─────────────────────────────────────────────────────
//
//  Raw values use lowercase snake_case strings (e.g. "paid_entry",
//  "all_gender") rather than the Swift identifier names. This matters because:
//    1. The raw value IS the database column value in Supabase. Snake_case
//       is the conventional column value format in PostgreSQL and matches
//       what the iOS team agreed with the backend schema.
//    2. It insulates the app from Swift identifier renaming: if
//       `paidEntry` is renamed to `directFee` in Swift, the persisted string
//       "paid_entry" is unchanged, so existing rows in SwiftData and Supabase
//       continue to decode correctly without a migration.
//    3. "unknown" / "none" sentinel values are explicit strings rather than
//       the Swift default rawValue of 0, making database rows human-readable
//       without an enum lookup table.
//
//  ── Display Helpers (color, icon, displayName) ────────────────────────────
//
//  Each enum carries display metadata as computed properties rather than
//  requiring views to switch over the enum themselves. The benefits:
//
//    • Single source of truth — the mapping lives in one file. Adding a new
//      case (e.g., BathroomAccess.membershipRequired) means adding one case
//      block here; every view that uses `.color`, `.icon`, or `.displayName`
//      gets the new mapping automatically.
//
//    • Eliminates switch statements in views — views call
//      `bathroom.accessType.color` instead of duplicating a switch block in
//      every list row, detail section, and filter chip that renders the value.
//
//    • Testability — the mapping logic can be unit-tested in isolation
//      without rendering a view.
//
//    • SF Symbol and Color choices are co-located with the case they
//      describe, making it easy to audit icon/colour semantics at a glance.
//

import SwiftUI

// MARK: - Access Type

/// How the bathroom is accessed and whether payment or purchase is involved.
///
/// Raw values are snake_case strings stored verbatim in both the local
/// SwiftData store and the Supabase `access_type` column.
enum BathroomAccess: String, Codable, CaseIterable, Identifiable {
    case free             = "free"
    case paidEntry        = "paid_entry"     // Fee to use the bathroom directly
    case paidVenue        = "paid_venue"     // Paid admission to the venue it's in
    case purchaseRequired = "purchase"       // Must buy something first
    case keyRequired      = "key_required"   // Must ask staff for a key
    case privateProperty  = "private"        // Private home or property

    /// Required by `Identifiable`; delegates to the stable rawValue string
    /// so SwiftUI can use BathroomAccess values directly as ForEach IDs.
    var id: String { rawValue }

    /// Full human-readable label for detail views and form pickers
    /// where space allows the complete description.
    var displayName: String {
        switch self {
        case .free:             return "Free"
        case .paidEntry:        return "Paid (bathroom fee)"
        case .paidVenue:        return "Paid (venue admission)"
        case .purchaseRequired: return "Purchase required"
        case .keyRequired:      return "Key required"
        case .privateProperty:  return "Private property"
        }
    }

    /// Abbreviated label for compact contexts like list rows and map callouts
    /// where the full `displayName` would be truncated.
    var shortName: String {
        switch self {
        case .free:             return "Free"
        case .paidEntry:        return "Paid"
        case .paidVenue:        return "Paid venue"
        case .purchaseRequired: return "Buy something"
        case .keyRequired:      return "Key required"
        case .privateProperty:  return "Private"
        }
    }

    /// SF Symbol name that visually communicates the access type.
    ///
    /// Icon rationale:
    ///   free             → unfilled dollar circle (cost exists but is zero)
    ///   paidEntry        → filled dollar circle (direct monetary cost)
    ///   paidVenue        → ticket (venue-level cost, not bathroom-specific)
    ///   purchaseRequired → shopping bag (buy something to earn access)
    ///   keyRequired      → key (literal physical key needed)
    ///   privateProperty  → house (private home / restricted property)
    var icon: String {
        switch self {
        case .free:             return "dollarsign.circle"
        case .paidEntry:        return "dollarsign.circle.fill"
        case .paidVenue:        return "ticket"
        case .purchaseRequired: return "bag"
        case .keyRequired:      return "key"
        case .privateProperty:  return "house"
        }
    }

    /// Tint color used for chips, badges, and map annotations.
    ///
    /// Color semantics follow a traffic-light convention:
    ///   green  = no barrier (free access)
    ///   orange = conditional access (costs money or requires a venue purchase)
    ///   yellow = requires active staff interaction (key request)
    ///   red    = generally inaccessible to the public
    ///   blue   = purchase-based — distinct from venue admission
    var color: Color {
        switch self {
        case .free:             return .green
        case .paidEntry:        return .orange
        case .paidVenue:        return .orange
        case .purchaseRequired: return .blue
        case .keyRequired:      return .yellow
        case .privateProperty:  return .red
        }
    }
}

// MARK: - Stall Type

/// Whether the bathroom is a single private room or a multi-stall facility.
///
/// Single-occupancy bathrooms have a lockable door and offer more privacy;
/// multi-stall facilities have open entry and individual lockable stalls.
/// `unknown` is provided as an explicit sentinel rather than using an
/// Optional so the property can remain non-optional in the model.
enum StallType: String, Codable, CaseIterable {
    case single  = "single"   // One lockable room for one person
    case multi   = "multi"    // Multiple stalls, open entry
    case unknown = "unknown"

    /// Full human-readable label. Used in the detail view and add form.
    var displayName: String {
        switch self {
        case .single:  return "Single occupancy"
        case .multi:   return "Multiple stalls"
        case .unknown: return "Unknown"
        }
    }

    /// SF Symbol name communicating the number of occupants.
    ///
    ///   single  → person.fill  (one person silhouette)
    ///   multi   → person.2.fill (two-person silhouette)
    ///   unknown → questionmark.circle
    var icon: String {
        switch self {
        case .single:  return "person.fill"
        case .multi:   return "person.2.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

// MARK: - Gender Type

/// Who the bathroom is designated for.
///
/// `allGender` covers both gender-neutral signage and bathrooms explicitly
/// labelled "all-gender". `familyRoom` is separate because it typically
/// indicates additional features (changing table, larger space) beyond
/// just gender-neutral access.
enum GenderType: String, Codable, CaseIterable {
    case allGender  = "all_gender"  // Gender-neutral / all-gender
    case menOnly    = "men"
    case womenOnly  = "women"
    case familyRoom = "family"      // Family / parent restroom

    /// Human-readable label. "All-gender" is preferred over "Unisex" which
    /// can be ambiguous.
    var displayName: String {
        switch self {
        case .allGender:  return "All-gender"
        case .menOnly:    return "Men's"
        case .womenOnly:  return "Women's"
        case .familyRoom: return "Family room"
        }
    }

    /// SF Symbol name chosen to represent gender designation.
    ///
    ///   allGender  → figure.dress.line.vertical.figure (two-figure inclusive icon)
    ///   menOnly    → figure.stand (standing male silhouette)
    ///   womenOnly  → figure.dress (dress silhouette)
    ///   familyRoom → figure.and.child.holdinghands (adult + child)
    var icon: String {
        switch self {
        case .allGender:  return "figure.dress.line.vertical.figure"
        case .menOnly:    return "figure.stand"
        case .womenOnly:  return "figure.dress"
        case .familyRoom: return "figure.and.child.holdinghands"
        }
    }
}

// MARK: - Bidet Type

/// The type of bidet feature present, if any.
///
/// `none` is the explicit zero-value rather than an Optional so the
/// Bathroom model property stays non-optional and SwiftData can store it
/// without wrapping in a container type.
enum BidetType: String, Codable, CaseIterable {
    case none       = "none"
    case handheld   = "handheld"    // Handheld spray attachment (shattaf)
    case electronic = "electronic"  // Electronic bidet seat / washlet (e.g. TOTO)

    /// Human-readable label used in detail view and filter sheet.
    var displayName: String {
        switch self {
        case .none:       return "None"
        case .handheld:   return "Handheld spray"
        case .electronic: return "Electronic seat"
        }
    }

    /// SF Symbol name.
    ///
    ///   none       → xmark.circle (explicitly absent)
    ///   handheld   → drop (water droplet — the spray)
    ///   electronic → sparkles (luxury / high-tech connotation)
    var icon: String {
        switch self {
        case .none:       return "xmark.circle"
        case .handheld:   return "drop"
        case .electronic: return "sparkles"
        }
    }
}

// MARK: - Wait Time

/// How busy this bathroom typically is, expressed as expected wait time.
///
/// Ordinal severity: unknown < usuallyEmpty < sometimesBusy < usuallyBusy.
/// The ordering is intentional — if sorting by congestion in the future,
/// the rawValue strings are not ordered, but the CaseIterable allCases
/// array is ordered by declaration order.
enum WaitTime: String, Codable, CaseIterable {
    case unknown       = "unknown"
    case usuallyEmpty  = "empty"
    case sometimesBusy = "sometimes_busy"
    case usuallyBusy   = "usually_busy"

    /// Human-readable label. "Often a line" is more viscerally meaningful
    /// than "Usually busy" in an emergency context.
    var displayName: String {
        switch self {
        case .unknown:       return "Unknown"
        case .usuallyEmpty:  return "Usually empty"
        case .sometimesBusy: return "Sometimes busy"
        case .usuallyBusy:   return "Often a line"
        }
    }

    /// SF Symbol name using urgency cues.
    ///
    ///   unknown       → questionmark.circle
    ///   usuallyEmpty  → checkmark.circle (all clear)
    ///   sometimesBusy → clock (time / wait implied)
    ///   usuallyBusy   → exclamationmark.circle (warning)
    var icon: String {
        switch self {
        case .unknown:       return "questionmark.circle"
        case .usuallyEmpty:  return "checkmark.circle"
        case .sometimesBusy: return "clock"
        case .usuallyBusy:   return "exclamationmark.circle"
        }
    }

    /// Tint color following a traffic-light convention.
    ///
    /// Gray for unknown keeps it visually neutral (no implied good/bad).
    /// Green → orange → red maps to increasing urgency, consistent with the
    /// convention used throughout the app for status indicators.
    var color: Color {
        switch self {
        case .unknown:       return Color(.systemGray3)
        case .usuallyEmpty:  return .green
        case .sometimesBusy: return .orange
        case .usuallyBusy:   return .red
        }
    }
}

// MARK: - Report Reason

/// Why a user is reporting a bathroom entry to the moderation queue.
///
/// Raw values are snake_case strings stored in the `reports` table in Supabase.
/// The ordering is intentional: most-likely reasons first.
enum ReportReason: String, Codable, CaseIterable, Identifiable {
    case noLongerExists = "no_longer_exists"   // Bathroom has been removed / demolished
    case wrongLocation  = "wrong_location"      // Pin is in the wrong place
    case incorrectInfo  = "incorrect_info"      // Attributes are wrong (hours, access type, etc.)
    case inappropriate  = "inappropriate"       // Inappropriate content in notes or photos
    case other          = "other"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .noLongerExists: return "No longer exists"
        case .wrongLocation:  return "Wrong location"
        case .incorrectInfo:  return "Incorrect information"
        case .inappropriate:  return "Inappropriate content"
        case .other:          return "Other"
        }
    }

    var icon: String {
        switch self {
        case .noLongerExists: return "building.2.slash"
        case .wrongLocation:  return "location.slash"
        case .incorrectInfo:  return "exclamationmark.circle"
        case .inappropriate:  return "hand.raised"
        case .other:          return "ellipsis.circle"
        }
    }
}
