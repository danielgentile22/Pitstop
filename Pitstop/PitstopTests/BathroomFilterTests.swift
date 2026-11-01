import CoreLocation
import Testing
@testable import Pitstop

@MainActor
struct BathroomFilterTests {

    // MARK: - Helpers

    private let home = CLLocationCoordinate2D(latitude: 38.8, longitude: -77.0)

    private func candidate(isOpen24Hours: Bool = false, latitude: Double = 38.8, isDismissed: Bool = false) -> Candidate {
        Candidate(
            sourceID: "atp:test:\(isOpen24Hours):\(latitude):\(isDismissed)",
            brandKey: "target",
            name: "Target",
            latitude: latitude,
            longitude: -77.0,
            isOpen24Hours: isOpen24Hours,
            isDismissed: isDismissed,
            seedVersion: 1
        )
    }

    /// Every rating, access, layout, amenity, and wait-time criterion: everything a Candidate has no data for.
    nonisolated enum VisitOnlyCriterion: CaseIterable {
        case minimumRating, accessType, stallType, gender, indoor, wheelchairAccessible, changingTable
        case toiletPaper, heatedSeat, bidet, soap, dryingOption, waitTime
    }

    private func filter(setting criterion: VisitOnlyCriterion) -> BathroomFilter {
        var filter = BathroomFilter()
        switch criterion {
        case .minimumRating:        filter.minimumRating = 3
        case .accessType:           filter.accessTypes = [.free]
        case .stallType:            filter.stallTypes = [.single]
        case .gender:               filter.genderTypes = [.allGender]
        case .indoor:               filter.requiresIndoor = true
        case .wheelchairAccessible: filter.requiresWheelchairAccessible = true
        case .changingTable:        filter.requiresChangingTable = true
        case .toiletPaper:          filter.requiresToiletPaper = true
        case .heatedSeat:           filter.requiresHeatedSeat = true
        case .bidet:                filter.requiresBidet = true
        case .soap:                 filter.requiresSoap = true
        case .dryingOption:         filter.requiresDryingOption = true
        case .waitTime:             filter.waitTimes = [.usuallyEmpty]
        }
        return filter
    }

    // MARK: - Show Unvisited

    @Test func defaultFilterKeepsCandidatesAndIsInactive() {
        let filter = BathroomFilter()
        #expect(filter.showUnvisited)
        #expect(!filter.isActive)
        #expect(filter.applies(to: candidate()))
    }

    @Test func hidingUnvisitedDropsEveryCandidateAndCountsAsActive() {
        var filter = BathroomFilter()
        filter.showUnvisited = false
        #expect(filter.isActive)
        #expect(!filter.applies(to: candidate()))
        #expect(!filter.applies(to: candidate(isOpen24Hours: true)))
    }

    @Test func resetShowsUnvisitedAgain() {
        var filter = BathroomFilter()
        filter.showUnvisited = false
        filter.reset()
        #expect(filter.showUnvisited)
    }

    // MARK: - Show Dismissed

    @Test func defaultFilterHidesDismissedCandidates() {
        let filter = BathroomFilter()
        #expect(!filter.showDismissed)
        #expect(!filter.applies(to: candidate(isDismissed: true)))
    }

    @Test func showingDismissedBringsThemBackAndCountsAsActive() {
        var filter = BathroomFilter()
        filter.showDismissed = true
        #expect(filter.isActive)
        #expect(filter.applies(to: candidate(isDismissed: true)))
        #expect(filter.applies(to: candidate()))
    }

    @Test func showDismissedIsIndependentOfShowUnvisited() {
        var filter = BathroomFilter()
        filter.showUnvisited = false
        filter.showDismissed = true
        #expect(filter.applies(to: candidate(isDismissed: true)))
        #expect(!filter.applies(to: candidate()))
    }

    @Test func dismissedCandidatesStillHonorTheOtherCriteria() {
        var filter = BathroomFilter()
        filter.showDismissed = true
        filter.requiresOpen24Hours = true
        #expect(!filter.applies(to: candidate(isDismissed: true)))
        #expect(filter.applies(to: candidate(isOpen24Hours: true, isDismissed: true)))
        filter.requiresOpen24Hours = false
        filter.minimumRating = 3
        #expect(!filter.applies(to: candidate(isDismissed: true)))
    }

    @Test func resetHidesDismissedAgain() {
        var filter = BathroomFilter()
        filter.showDismissed = true
        filter.reset()
        #expect(!filter.showDismissed)
    }

    // MARK: - Open 24 Hours

    @Test func open24HoursKeepsOnlyCandidatesOpen24Hours() {
        var filter = BathroomFilter()
        filter.requiresOpen24Hours = true
        #expect(filter.applies(to: candidate(isOpen24Hours: true)))
        #expect(!filter.applies(to: candidate(isOpen24Hours: false)))
    }

    // MARK: - Rating and Amenity Criteria

    @Test(arguments: VisitOnlyCriterion.allCases)
    func visitOnlyCriterionDropsEveryCandidate(_ criterion: VisitOnlyCriterion) {
        let filter = filter(setting: criterion)
        #expect(filter.isActive)
        #expect(!filter.applies(to: candidate()))
        #expect(!filter.applies(to: candidate(isOpen24Hours: true)))
    }

    // MARK: - Max Distance

    @Test func maxDistanceKeepsCandidatesInsideTheRadius() {
        var filter = BathroomFilter()
        filter.maxDistance = .oneMile
        let near = candidate(latitude: 38.805)  // about 0.35 mi north
        let far  = candidate(latitude: 38.85)   // about 3.5 mi north
        #expect(filter.isWithinMaxDistance(near.coordinate, of: home))
        #expect(!filter.isWithinMaxDistance(far.coordinate, of: home))
    }

    @Test func maxDistanceCountsAsActiveOnlyWithALocation() {
        var filter = BathroomFilter()
        filter.maxDistance = .oneMile
        #expect(filter.isActive(locationAvailable: true))
        #expect(!filter.isActive(locationAvailable: false))
        filter.requiresOpen24Hours = true
        #expect(filter.isActive(locationAvailable: false))
    }

    @Test func maxDistanceKeepsEverythingWithoutALocationOrARadius() {
        var filter = BathroomFilter()
        let far = candidate(latitude: 40.0)
        #expect(filter.isWithinMaxDistance(far.coordinate, of: home))
        filter.maxDistance = .halfMile
        #expect(filter.isWithinMaxDistance(far.coordinate, of: nil))
    }

    // MARK: - Bathroom Criteria

    /// Every criterion `applies(to: Bathroom)` checks.
    nonisolated enum BathroomCriterion: CaseIterable {
        case minimumRating, accessType, stallType, gender, open24Hours, indoor, wheelchairAccessible
        case changingTable, toiletPaper, heatedSeat, bidet, soap, dryingOption, waitTime
    }

    /// A filter with only `criterion` set, a Bathroom that meets it, and one that does not.
    private func bathroomCase(_ criterion: BathroomCriterion) -> (filter: BathroomFilter, match: Bathroom, miss: Bathroom) {
        var filter = BathroomFilter()
        let match = Bathroom(name: "Match", latitude: 38.8, longitude: -77.0)
        let miss  = Bathroom(name: "Miss",  latitude: 38.8, longitude: -77.0)
        switch criterion {
        case .minimumRating:
            filter.minimumRating = 4
            match.rating = 5; miss.rating = 3
        case .accessType:
            filter.accessTypes = [.free]
            match.accessType = .free; miss.accessType = .purchaseRequired
        case .stallType:
            filter.stallTypes = [.single]
            match.stallType = .single; miss.stallType = .multi
        case .gender:
            filter.genderTypes = [.allGender]
            match.genderType = .allGender; miss.genderType = .menOnly
        case .open24Hours:
            filter.requiresOpen24Hours = true
            match.isOpen24Hours = true; miss.isOpen24Hours = false
        case .indoor:
            filter.requiresIndoor = true
            match.isIndoor = true; miss.isIndoor = false
        case .wheelchairAccessible:
            filter.requiresWheelchairAccessible = true
            match.isWheelchairAccessible = true; miss.isWheelchairAccessible = false
        case .changingTable:
            filter.requiresChangingTable = true
            match.hasChangingTable = true; miss.hasChangingTable = false
        case .toiletPaper:
            filter.requiresToiletPaper = true
            match.hasToiletPaper = true; miss.hasToiletPaper = false
        case .heatedSeat:
            filter.requiresHeatedSeat = true
            match.hasHeatedSeat = true; miss.hasHeatedSeat = false
        case .bidet:
            filter.requiresBidet = true
            match.bidetType = .handheld; miss.bidetType = .none
        case .soap:
            filter.requiresSoap = true
            match.hasSoap = true; miss.hasSoap = false
        case .dryingOption:
            filter.requiresDryingOption = true
            match.hasDryingOption = true; miss.hasDryingOption = false
        case .waitTime:
            filter.waitTimes = [.usuallyEmpty]
            match.waitTime = .usuallyEmpty; miss.waitTime = .unknown
        }
        return (filter, match, miss)
    }

    @Test(arguments: BathroomCriterion.allCases)
    func bathroomCriterionKeepsOnlyMatchingBathrooms(_ criterion: BathroomCriterion) {
        let (filter, match, miss) = bathroomCase(criterion)
        #expect(filter.isActive)
        #expect(filter.applies(to: match))
        #expect(!filter.applies(to: miss))
    }

    @Test func minimumRatingKeepsTheBoundaryRating() {
        var filter = BathroomFilter()
        filter.minimumRating = 3
        #expect(filter.applies(to: Bathroom(name: "Three", latitude: 38.8, longitude: -77.0, rating: 3)))
        #expect(!filter.applies(to: Bathroom(name: "Two", latitude: 38.8, longitude: -77.0, rating: 2)))
    }

    @Test func defaultFilterKeepsEveryBathroom() {
        let bathroom = Bathroom(name: "Plain", latitude: 38.8, longitude: -77.0, hasToiletPaper: false, hasSoap: false)
        #expect(BathroomFilter().applies(to: bathroom))
    }

    // MARK: - Visible Places

    private func bathroom(latitude: Double = 38.8, sourceID: String? = nil) -> Bathroom {
        let bathroom = Bathroom(name: "Visit \(latitude)", latitude: latitude, longitude: -77.0)
        bathroom.sourceID = sourceID
        return bathroom
    }

    @Test func maxDistanceHidesFarPlacesOfBothKinds() {
        var filter = BathroomFilter()
        filter.maxDistance = .oneMile
        let nearVisit = bathroom(latitude: 38.805)   // about 0.35 mi north
        let farVisit  = bathroom(latitude: 38.85)    // about 3.5 mi north
        let nearPlace = candidate(latitude: 38.805)
        let farPlace  = candidate(latitude: 38.85)

        let visible = filter.visiblePlaces(bathrooms: [nearVisit, farVisit], candidates: [nearPlace, farPlace], userLocation: home)

        #expect(visible.bathrooms.map(\.id) == [nearVisit.id])
        #expect(visible.candidates.map(\.sourceID) == [nearPlace.sourceID])
    }

    @Test func maxDistanceKeepsEveryPlaceWithoutALocation() {
        var filter = BathroomFilter()
        filter.maxDistance = .halfMile
        let visible = filter.visiblePlaces(bathrooms: [bathroom(latitude: 40)], candidates: [candidate(latitude: 40)], userLocation: nil)
        #expect(visible.bathrooms.count == 1)
        #expect(visible.candidates.count == 1)
    }

    @Test func linkedCandidatesAreHiddenEvenWhenTheirBathroomIsFilteredOut() {
        var filter = BathroomFilter()
        filter.requiresOpen24Hours = true
        let linked   = candidate(isOpen24Hours: true)
        let unlinked = candidate(isOpen24Hours: true, latitude: 38.81)
        let closedVisit = bathroom(sourceID: linked.sourceID)   // not open 24 hours, so filtered out

        let visible = filter.visiblePlaces(bathrooms: [closedVisit], candidates: [linked, unlinked], userLocation: home)

        #expect(visible.bathrooms.isEmpty)
        #expect(visible.candidates.map(\.sourceID) == [unlinked.sourceID])
    }

    @Test func dismissedCandidatesFollowShowDismissed() {
        var filter = BathroomFilter()
        let dismissed = candidate(isDismissed: true)
        let open      = candidate()

        #expect(filter.visiblePlaces(bathrooms: [], candidates: [dismissed, open], userLocation: home)
            .candidates.map(\.sourceID) == [open.sourceID])

        filter.showDismissed = true
        #expect(filter.visiblePlaces(bathrooms: [], candidates: [dismissed, open], userLocation: home)
            .candidates.map(\.sourceID) == [dismissed.sourceID, open.sourceID])
    }

    // MARK: - Linked Source IDs

    @Test func linkedSourceIDsAreEveryBathroomsSource() {
        let ids = [bathroom(sourceID: "atp:a"), bathroom(), bathroom(sourceID: "atp:b")].linkedSourceIDs
        #expect(ids == ["atp:a", "atp:b"])
    }

    @Test func maxDistanceAloneDoesNotDropCandidates() {
        var filter = BathroomFilter()
        filter.maxDistance = .halfMile
        #expect(filter.applies(to: candidate()))
    }
}
