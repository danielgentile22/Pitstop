import CoreLocation
import Testing
@testable import Pitstop

@MainActor
struct BathroomFilterTests {

    // MARK: - Helpers

    private let home = CLLocationCoordinate2D(latitude: 38.8, longitude: -77.0)

    private func candidate(isOpen24Hours: Bool = false, latitude: Double = 38.8) -> Candidate {
        Candidate(
            sourceID: "atp:test:\(isOpen24Hours):\(latitude)",
            brandKey: "target",
            name: "Target",
            latitude: latitude,
            longitude: -77.0,
            isOpen24Hours: isOpen24Hours,
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

    @Test func maxDistanceKeepsEverythingWithoutALocationOrARadius() {
        var filter = BathroomFilter()
        let far = candidate(latitude: 40.0)
        #expect(filter.isWithinMaxDistance(far.coordinate, of: home))
        filter.maxDistance = .halfMile
        #expect(filter.isWithinMaxDistance(far.coordinate, of: nil))
    }

    @Test func maxDistanceAloneDoesNotDropCandidates() {
        var filter = BathroomFilter()
        filter.maxDistance = .halfMile
        #expect(filter.applies(to: candidate()))
    }
}
