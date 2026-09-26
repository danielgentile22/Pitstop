import Foundation

// MARK: - MaxDistance

enum MaxDistance: Double, CaseIterable, Equatable {
    case halfMile  =  804.67   // meters
    case oneMile   = 1609.34
    case fiveMiles = 8046.72
    case tenMiles  = 16093.44

    var displayName: String {
        switch self {
        case .halfMile:  return "½ mi"
        case .oneMile:   return "1 mi"
        case .fiveMiles: return "5 mi"
        case .tenMiles:  return "10 mi"
        }
    }
}

// MARK: - BathroomFilter

struct BathroomFilter: Equatable {

    // Empty sets and 0 mean "any".

    // MARK: - Rating

    var minimumRating: Int = 0

    // MARK: - Access

    var accessTypes: Set<BathroomAccess> = []

    // MARK: - Layout

    var stallTypes: Set<StallType> = []

    var genderTypes: Set<GenderType> = []

    // MARK: - Boolean Must-Haves

    var requiresOpen24Hours:          Bool = false
    var requiresIndoor:               Bool = false
    var requiresWheelchairAccessible: Bool = false
    var requiresChangingTable:        Bool = false
    var requiresToiletPaper:          Bool = false
    var requiresHeatedSeat:           Bool = false
    var requiresBidet:                Bool = false
    var requiresSoap:                 Bool = false
    var requiresDryingOption:         Bool = false

    // MARK: - Wait Time

    var waitTimes: Set<WaitTime> = []

    // MARK: - Distance

    /// Not checked by `applies(to:)`; ListTabView applies it because it needs the user's location.
    var maxDistance: MaxDistance? = nil

    // MARK: - Derived

    var isActive: Bool {
        minimumRating > 0
        || !accessTypes.isEmpty
        || !stallTypes.isEmpty
        || !genderTypes.isEmpty
        || requiresOpen24Hours
        || requiresIndoor
        || requiresWheelchairAccessible
        || requiresChangingTable
        || requiresToiletPaper
        || requiresHeatedSeat
        || requiresBidet
        || requiresSoap
        || requiresDryingOption
        || !waitTimes.isEmpty
        || maxDistance != nil
    }

    // MARK: - Application

    /// Every criterion except `maxDistance`.
    func applies(to bathroom: Bathroom) -> Bool {

        if minimumRating > 0 {
            guard bathroom.rating >= minimumRating else { return false }
        }
        if !accessTypes.isEmpty {
            guard accessTypes.contains(bathroom.accessType) else { return false }
        }
        if !stallTypes.isEmpty {
            guard stallTypes.contains(bathroom.stallType) else { return false }
        }
        if !genderTypes.isEmpty {
            guard genderTypes.contains(bathroom.genderType) else { return false }
        }
        if requiresOpen24Hours          { guard bathroom.isOpen24Hours          else { return false } }
        if requiresIndoor               { guard bathroom.isIndoor               else { return false } }
        if requiresWheelchairAccessible { guard bathroom.isWheelchairAccessible else { return false } }
        if requiresChangingTable        { guard bathroom.hasChangingTable        else { return false } }
        if requiresToiletPaper          { guard bathroom.hasToiletPaper          else { return false } }
        if requiresHeatedSeat           { guard bathroom.hasHeatedSeat           else { return false } }
        if requiresBidet                { guard bathroom.bidetType != .none      else { return false } }
        if requiresSoap                 { guard bathroom.hasSoap                 else { return false } }
        if requiresDryingOption         { guard bathroom.hasDryingOption         else { return false } }
        if !waitTimes.isEmpty           { guard waitTimes.contains(bathroom.waitTime) else { return false } }

        return true
    }

    // MARK: - Reset

    mutating func reset() {
        self = BathroomFilter()
    }
}
