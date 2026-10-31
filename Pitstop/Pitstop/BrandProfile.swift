import Foundation

/// How likely an unvisited location of a brand is to have a usable public bathroom.
nonisolated enum Reliability: String, CaseIterable {
    case reliable
    case likely
    case uncertain

    var displayName: String {
        switch self {
        case .reliable:  return "Reliable"
        case .likely:    return "Likely"
        case .uncertain: return "Uncertain"
        }
    }

    var explanation: String {
        switch self {
        case .reliable:  return "Usually open to the public"
        case .likely:    return "Usually has a restroom, but it varies by store"
        case .uncertain: return "Often needs a code or has no public restroom"
        }
    }
}

/// What the app assumes about every location of one chain. Keys match `brandKey` in the seed script.
nonisolated struct BrandProfile {
    let key: String
    let displayName: String
    let reliability: Reliability
    let expectedAccess: BathroomAccess

    static let table: [String: BrandProfile] = Dictionary(uniqueKeysWithValues: [
        BrandProfile(key: "barnes_and_noble", displayName: "Barnes & Noble", reliability: .reliable, expectedAccess: .free),
        BrandProfile(key: "target",           displayName: "Target",         reliability: .reliable, expectedAccess: .free),
        BrandProfile(key: "walmart",          displayName: "Walmart",        reliability: .reliable, expectedAccess: .free),
        BrandProfile(key: "wegmans",          displayName: "Wegmans",        reliability: .likely,   expectedAccess: .free),
        BrandProfile(key: "harris_teeter",    displayName: "Harris Teeter",  reliability: .likely,   expectedAccess: .free),
        BrandProfile(key: "giant",            displayName: "Giant",          reliability: .likely,   expectedAccess: .free),
        BrandProfile(key: "safeway",          displayName: "Safeway",        reliability: .likely,   expectedAccess: .free),
        BrandProfile(key: "whole_foods",      displayName: "Whole Foods",    reliability: .likely,   expectedAccess: .free),
        BrandProfile(key: "publix",           displayName: "Publix",         reliability: .likely,   expectedAccess: .free),
        BrandProfile(key: "lidl",             displayName: "Lidl",           reliability: .likely,   expectedAccess: .free),
        BrandProfile(key: "food_lion",        displayName: "Food Lion",      reliability: .likely,   expectedAccess: .free),
        BrandProfile(key: "weis",             displayName: "Weis",           reliability: .likely,   expectedAccess: .free),
        // Restrooms are often staff-only; ask at the register.
        BrandProfile(key: "trader_joes",      displayName: "Trader Joe's",   reliability: .uncertain, expectedAccess: .keyRequired),
        BrandProfile(key: "aldi",             displayName: "Aldi",           reliability: .uncertain, expectedAccess: .keyRequired),
        // Company-run gas stations with large stores and public restrooms.
        BrandProfile(key: "wawa",             displayName: "Wawa",           reliability: .reliable, expectedAccess: .free),
        BrandProfile(key: "sheetz",           displayName: "Sheetz",         reliability: .reliable, expectedAccess: .free),
        BrandProfile(key: "royal_farms",      displayName: "Royal Farms",    reliability: .reliable, expectedAccess: .free),
        // Mostly franchised, so it varies by station; the restroom is often locked and the key is at the register.
        BrandProfile(key: "shell",            displayName: "Shell",          reliability: .likely,   expectedAccess: .keyRequired),
        BrandProfile(key: "exxon",            displayName: "Exxon",          reliability: .likely,   expectedAccess: .keyRequired),
        BrandProfile(key: "mobil",            displayName: "Mobil",          reliability: .likely,   expectedAccess: .keyRequired),
        BrandProfile(key: "bp",               displayName: "BP",             reliability: .likely,   expectedAccess: .keyRequired),
        BrandProfile(key: "amoco",            displayName: "Amoco",          reliability: .likely,   expectedAccess: .keyRequired),
        BrandProfile(key: "sunoco",           displayName: "Sunoco",         reliability: .likely,   expectedAccess: .keyRequired),
        BrandProfile(key: "citgo",            displayName: "Citgo",          reliability: .likely,   expectedAccess: .keyRequired),
        BrandProfile(key: "speedway",         displayName: "Speedway",       reliability: .likely,   expectedAccess: .keyRequired),
        BrandProfile(key: "valero",           displayName: "Valero",         reliability: .likely,   expectedAccess: .keyRequired),
        BrandProfile(key: "marathon",         displayName: "Marathon",       reliability: .likely,   expectedAccess: .keyRequired),
        BrandProfile(key: "chevron",          displayName: "Chevron",        reliability: .likely,   expectedAccess: .keyRequired),
        // Many small city stores have no public restroom.
        BrandProfile(key: "seven_eleven",     displayName: "7-Eleven",       reliability: .uncertain, expectedAccess: .keyRequired),
    ].map { ($0.key, $0) })

    /// Unknown keys (a seed newer than the app's table) fall back to uncertain rather than failing.
    static func profile(forKey key: String) -> BrandProfile {
        table[key] ?? BrandProfile(key: key, displayName: key, reliability: .uncertain, expectedAccess: .free)
    }
}
