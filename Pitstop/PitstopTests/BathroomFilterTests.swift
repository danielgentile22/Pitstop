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

    /// One filter per rating, access, layout, amenity, and wait-time criterion: everything a Candidate has no data for.
    private static let visitOnlyCriteria: [(String, (inout BathroomFilter) -> Void)] = [
        ("minimum rating",        { $0.minimumRating = 3 }),
        ("access type",           { $0.accessTypes = [.free] }),
        ("stall type",            { $0.stallTypes = [.single] }),
        ("gender",                { $0.genderTypes = [.allGender] }),
        ("indoor",                { $0.requiresIndoor = true }),
        ("wheelchair accessible", { $0.requiresWheelchairAccessible = true }),
        ("changing table",        { $0.requiresChangingTable = true }),
        ("toilet paper",          { $0.requiresToiletPaper = true }),
        ("heated seat",           { $0.requiresHeatedSeat = true }),
        ("bidet",                 { $0.requiresBidet = true }),
        ("soap",                  { $0.requiresSoap = true }),
        ("drying option",         { $0.requiresDryingOption = true }),
        ("wait time",             { $0.waitTimes = [.usuallyEmpty] }),
    ]

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

    @Test(arguments: visitOnlyCriteria.indices)
    func visitOnlyCriterionDropsEveryCandidate(index: Int) {
        let (name, set) = Self.visitOnlyCriteria[index]
        var filter = BathroomFilter()
        set(&filter)
        #expect(!filter.applies(to: candidate()), "\(name)")
        #expect(!filter.applies(to: candidate(isOpen24Hours: true)), "\(name)")
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
