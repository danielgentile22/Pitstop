import Foundation

/// How likely an unvisited location of a brand is to have a usable public bathroom.
enum Reliability: String, CaseIterable {
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
struct BrandProfile {
    let key: String
    let displayName: String
    let reliability: Reliability
    let expectedAccess: BathroomAccess

    static let table: [String: BrandProfile] = Dictionary(uniqueKeysWithValues: [
        BrandProfile(key: "barnes_and_noble", displayName: "Barnes & Noble", reliability: .reliable, expectedAccess: .free),
        BrandProfile(key: "target",           displayName: "Target",         reliability: .reliable, expectedAccess: .free),
        BrandProfile(key: "walmart",          displayName: "Walmart",        reliability: .reliable, expectedAccess: .free),
    ].map { ($0.key, $0) })

    /// Unknown keys (a seed newer than the app's table) fall back to uncertain rather than failing.
    static func profile(forKey key: String) -> BrandProfile {
        table[key] ?? BrandProfile(key: key, displayName: key, reliability: .uncertain, expectedAccess: .free)
    }
}
