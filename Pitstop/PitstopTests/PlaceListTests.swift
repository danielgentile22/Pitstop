import CoreLocation
import Foundation
import Testing
@testable import Pitstop

@MainActor
struct PlaceListTests {

    // MARK: - Helpers

    private let home = CLLocationCoordinate2D(latitude: 38.8, longitude: -77.0)

    private func bathroom(_ name: String, rating: Int = 0, latitude: Double = 38.8, dateCreated: Date? = nil) -> MapSelection {
        .bathroom(Bathroom(name: name, latitude: latitude, longitude: -77.0, rating: rating, dateCreated: dateCreated))
    }

    private func candidate(_ name: String, latitude: Double = 38.8, isDismissed: Bool = false) -> Candidate {
        Candidate(
            sourceID: "atp:test:\(name):\(latitude)",
            brandKey: "target",
            name: name,
            latitude: latitude,
            longitude: -77.0,
            isOpen24Hours: false,
            isDismissed: isDismissed,
            seedVersion: 1
        )
    }

    private func names(_ places: [MapSelection]) -> [String] {
        places.map {
            switch $0 {
            case .bathroom(let bathroom):   return bathroom.name
            case .candidate(let candidate): return candidate.name
            }
        }
    }

    // MARK: - Distance Sort

    @Test func distanceSortWithoutALocationOrdersByName() {
        let places = [bathroom("Wawa"), .candidate(candidate("target")), bathroom("Sheetz")]
        #expect(names(SortOption.distance.sorted(places, from: nil)) == ["Sheetz", "target", "Wawa"])
    }

    @Test func distanceSortOrdersNearestFirst() {
        let places = [
            bathroom("Far", latitude: 38.85),
            .candidate(candidate("Near", latitude: 38.801)),
            bathroom("Middle", latitude: 38.82),
        ]
        #expect(names(SortOption.distance.sorted(places, from: home)) == ["Near", "Middle", "Far"])
    }

    // MARK: - Name Tiebreak

    /// Every place ties on the sort key, so only the shared tiebreak decides the order.
    @Test(arguments: SortOption.allCases)
    func everySortBreaksTiesByNameIgnoringCase(_ option: SortOption) {
        let created = Date(timeIntervalSince1970: 1_000_000)
        let places = [
            bathroom("wawa", rating: 4, dateCreated: created),
            bathroom("Sheetz", rating: 4, dateCreated: created),
            bathroom("buc-ee's", rating: 4, dateCreated: created),
        ]
        #expect(names(option.sorted(places, from: home)) == ["buc-ee's", "Sheetz", "wawa"])
    }

    @Test func ratingSortPutsHighestFirstAndUnratedLast() {
        let places = [bathroom("Unrated"), bathroom("Three", rating: 3), .candidate(candidate("Unvisited")), bathroom("Five", rating: 5)]
        #expect(names(SortOption.rating.sorted(places, from: nil)) == ["Five", "Three", "Unrated", "Unvisited"])
    }

    // MARK: - Fingerprint

    @Test func fingerprintIsStableForTheSameInput() {
        let bathrooms = [Bathroom(name: "Wawa", latitude: 38.8, longitude: -77.0)]
        let candidates = [candidate("Target")]
        #expect(MapSelection.fingerprint(bathrooms: bathrooms, candidates: candidates)
                == MapSelection.fingerprint(bathrooms: bathrooms, candidates: candidates))
    }

    @Test func fingerprintChangesWhenACandidateIsDismissed() {
        let target = candidate("Target")
        let before = MapSelection.fingerprint(bathrooms: [], candidates: [target])
        target.isDismissed = true
        #expect(MapSelection.fingerprint(bathrooms: [], candidates: [target]) != before)
    }

    @Test func fingerprintChangesWhenABathroomIsEdited() {
        let wawa = Bathroom(name: "Wawa", latitude: 38.8, longitude: -77.0)
        let before = MapSelection.fingerprint(bathrooms: [wawa], candidates: [])
        wawa.rating = 5
        wawa.dateModified = Date(timeIntervalSinceNow: 60)
        #expect(MapSelection.fingerprint(bathrooms: [wawa], candidates: []) != before)
    }

    @Test func fingerprintChangesWhenAPlaceIsAddedOrRemoved() {
        let target = candidate("Target")
        let walmart = candidate("Walmart")
        #expect(MapSelection.fingerprint(bathrooms: [], candidates: [target])
                != MapSelection.fingerprint(bathrooms: [], candidates: [target, walmart]))
    }
}
