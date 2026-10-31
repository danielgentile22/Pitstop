import CoreLocation
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

    // MARK: - Unvisited Places

    /// Shows Candidates. On by default, so only turning it off makes the filter active.
    var showUnvisited: Bool = true

    /// Shows Candidates the user marked "No public restroom here", so a dismissal can be undone.
    /// Off by default, so only turning it on makes the filter active.
    var showDismissed: Bool = false

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

    /// Not checked by `applies(to:)`; the views apply it with `isWithinMaxDistance` because it needs the user's location.
    var maxDistance: MaxDistance? = nil

    // MARK: - Derived

    var isActive: Bool {
        !showUnvisited
        || showDismissed
        || requiresVisitDetails
        || requiresOpen24Hours
        || maxDistance != nil
    }

    /// Any criterion only a visit can answer. Candidates have no data for these, so they never match.
    var requiresVisitDetails: Bool {
        !visitChecks.isEmpty
    }

    /// One check per visit-only criterion that is set. The single list behind both `requiresVisitDetails`
    /// and `applies(to: Bathroom)`, so a new criterion cannot be added to one and forgotten in the other.
    private var visitChecks: [(Bathroom) -> Bool] {
        var checks: [(Bathroom) -> Bool] = []
        func check(_ isSet: Bool, _ passes: @escaping (Bathroom) -> Bool) {
            if isSet { checks.append(passes) }
        }
        let filter = self
        check(minimumRating > 0)         { $0.rating >= filter.minimumRating }
        check(!accessTypes.isEmpty)      { filter.accessTypes.contains($0.accessType) }
        check(!stallTypes.isEmpty)       { filter.stallTypes.contains($0.stallType) }
        check(!genderTypes.isEmpty)      { filter.genderTypes.contains($0.genderType) }
        check(requiresIndoor)               { $0.isIndoor }
        check(requiresWheelchairAccessible) { $0.isWheelchairAccessible }
        check(requiresChangingTable)        { $0.hasChangingTable }
        check(requiresToiletPaper)          { $0.hasToiletPaper }
        check(requiresHeatedSeat)           { $0.hasHeatedSeat }
        check(requiresBidet)                { $0.bidetType != .none }
        check(requiresSoap)                 { $0.hasSoap }
        check(requiresDryingOption)         { $0.hasDryingOption }
        check(!waitTimes.isEmpty)        { filter.waitTimes.contains($0.waitTime) }
        return checks
    }

    // MARK: - Application

    /// Every criterion except `maxDistance`.
    func applies(to bathroom: Bathroom) -> Bool {
        if requiresOpen24Hours { guard bathroom.isOpen24Hours else { return false } }
        return visitChecks.allSatisfy { $0(bathroom) }
    }

    /// Every criterion except `maxDistance`. Open 24 hours uses the seed's hours.
    /// `showDismissed` alone decides dismissed Candidates; `showUnvisited` decides the rest.
    func applies(to candidate: Candidate) -> Bool {
        guard candidate.isDismissed ? showDismissed : showUnvisited else { return false }
        guard !requiresVisitDetails else { return false }
        if requiresOpen24Hours { guard candidate.isOpen24Hours else { return false } }
        return true
    }

    /// True when there is no radius or no known location to measure from.
    func isWithinMaxDistance(_ coordinate: CLLocationCoordinate2D, of userLocation: CLLocationCoordinate2D?) -> Bool {
        guard let maxDistance, let userLocation else { return true }
        return Distance.meters(from: userLocation, to: coordinate) <= maxDistance.rawValue
    }

    /// The places the map and the list show: every criterion, `maxDistance` included, on both kinds.
    /// Pass all Bathrooms, not a filtered subset, so a filtered-out visit still hides the Candidate it links to.
    func visiblePlaces(
        bathrooms: [Bathroom],
        candidates: [Candidate],
        userLocation: CLLocationCoordinate2D?
    ) -> (bathrooms: [Bathroom], candidates: [Candidate]) {
        let linkedIDs = bathrooms.linkedSourceIDs
        let visibleBathrooms = isActive
            ? bathrooms.filter { applies(to: $0) && isWithinMaxDistance($0.coordinate, of: userLocation) }
            : bathrooms
        let visibleCandidates = candidates.filter {
            !linkedIDs.contains($0.sourceID)
            && applies(to: $0)
            && isWithinMaxDistance($0.coordinate, of: userLocation)
        }
        return (visibleBathrooms, visibleCandidates)
    }

    // MARK: - Reset

    mutating func reset() {
        self = BathroomFilter()
    }
}
