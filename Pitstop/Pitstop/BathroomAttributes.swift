import SwiftUI

// Raw values are persisted verbatim, locally and in the backend's columns.
// Don't change them when renaming cases; existing rows would stop decoding.

// MARK: - Access Type

enum BathroomAccess: String, Codable, CaseIterable, Identifiable {
    case free             = "free"
    case paidEntry        = "paid_entry"     // fee for the bathroom itself
    case paidVenue        = "paid_venue"     // admission to the venue it's in
    case purchaseRequired = "purchase"
    case keyRequired      = "key_required"
    case privateProperty  = "private"

    var id: String { rawValue }

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

    /// For list rows and map callouts.
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

enum StallType: String, Codable, CaseIterable {
    case single  = "single"
    case multi   = "multi"
    case unknown = "unknown"

    var displayName: String {
        switch self {
        case .single:  return "Single occupancy"
        case .multi:   return "Multiple stalls"
        case .unknown: return "Unknown"
        }
    }

    var icon: String {
        switch self {
        case .single:  return "person.fill"
        case .multi:   return "person.2.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

// MARK: - Gender Type

enum GenderType: String, Codable, CaseIterable {
    case allGender  = "all_gender"
    case menOnly    = "men"
    case womenOnly  = "women"
    case familyRoom = "family"

    var displayName: String {
        switch self {
        case .allGender:  return "All-gender"
        case .menOnly:    return "Men's"
        case .womenOnly:  return "Women's"
        case .familyRoom: return "Family room"
        }
    }

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

enum BidetType: String, Codable, CaseIterable {
    case none       = "none"
    case handheld   = "handheld"    // spray attachment
    case electronic = "electronic"  // washlet seat

    var displayName: String {
        switch self {
        case .none:       return "None"
        case .handheld:   return "Handheld spray"
        case .electronic: return "Electronic seat"
        }
    }

    var icon: String {
        switch self {
        case .none:       return "xmark.circle"
        case .handheld:   return "drop"
        case .electronic: return "sparkles"
        }
    }
}

// MARK: - Wait Time

/// Declaration order is least to most busy; `allCases` relies on it.
enum WaitTime: String, Codable, CaseIterable {
    case unknown       = "unknown"
    case usuallyEmpty  = "empty"
    case sometimesBusy = "sometimes_busy"
    case usuallyBusy   = "usually_busy"

    var displayName: String {
        switch self {
        case .unknown:       return "Unknown"
        case .usuallyEmpty:  return "Usually empty"
        case .sometimesBusy: return "Sometimes busy"
        case .usuallyBusy:   return "Often a line"
        }
    }

    var icon: String {
        switch self {
        case .unknown:       return "questionmark.circle"
        case .usuallyEmpty:  return "checkmark.circle"
        case .sometimesBusy: return "clock"
        case .usuallyBusy:   return "exclamationmark.circle"
        }
    }

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

/// Stored in the backend `reports` table. Ordered most-likely first for the picker.
enum ReportReason: String, Codable, CaseIterable, Identifiable {
    case noLongerExists = "no_longer_exists"
    case wrongLocation  = "wrong_location"
    case incorrectInfo  = "incorrect_info"
    case inappropriate  = "inappropriate"      // notes or photos
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
