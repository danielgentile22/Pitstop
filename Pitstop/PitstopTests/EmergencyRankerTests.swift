import Foundation
import CoreLocation
import Testing
@testable import Pitstop

@MainActor
struct EmergencyRankerTests {

    // MARK: - Helpers

    private let origin = CLLocationCoordinate2D(latitude: 38.8, longitude: -77.0)

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    private func time(hour: Int, minute: Int = 0) -> Date {
        Self.calendar.date(from: DateComponents(year: 2026, month: 10, day: 31, hour: hour, minute: minute))!
    }

    /// A point due north of `origin` that takes `minutes` to reach at the fallback speed.
    private func coordinate(minutesAway minutes: Double) -> CLLocationCoordinate2D {
        let meters = minutes * EmergencyRanker.fallbackMetersPerMinute
        return CLLocationCoordinate2D(latitude: origin.latitude + meters / 111_000, longitude: origin.longitude)
    }

    private func visited(
        _ id: UUID = UUID(),
        minutesAway: Double,
        rating: Int,
        isOpen24Hours: Bool = true,
        sourceID: String? = nil
    ) -> EmergencyRanker.VisitedPlace {
        let c = coordinate(minutesAway: minutesAway)
        return .init(id: id, sourceID: sourceID, latitude: c.latitude, longitude: c.longitude,
                     rating: rating, isOpen24Hours: isOpen24Hours)
    }

    private func unvisited(
        _ sourceID: String,
        minutesAway: Double,
        reliability: Reliability,
        isOpen24Hours: Bool = true,
        isDismissed: Bool = false
    ) -> EmergencyRanker.UnvisitedPlace {
        let c = coordinate(minutesAway: minutesAway)
        return .init(sourceID: sourceID, latitude: c.latitude, longitude: c.longitude,
                     reliability: reliability, isOpen24Hours: isOpen24Hours, isDismissed: isDismissed)
    }

    private func rankedIDs(
        at now: Date? = nil,
        visited: [EmergencyRanker.VisitedPlace] = [],
        unvisited: [EmergencyRanker.UnvisitedPlace] = [],
        drivingTimes: [EmergencyRanker.PlaceID: TimeInterval] = [:]
    ) -> [EmergencyRanker.PlaceID] {
        EmergencyRanker.rank(
            from: origin, at: now ?? time(hour: 12), calendar: Self.calendar,
            visited: visited, unvisited: unvisited, drivingTimes: drivingTimes
        ).map(\.id)
    }

    // MARK: - Penalties

    @Test func visitedFiveStarSixMinutesBeatsUncertainFourMinutes() {
        let known = UUID()
        let ids = rankedIDs(
            visited: [visited(known, minutesAway: 6, rating: 5)],
            unvisited: [unvisited("gamble", minutesAway: 4, reliability: .uncertain)]
        )
        #expect(ids == [.bathroom(known), .candidate("gamble")])
    }

    @Test func reliableThreeMinutesBeatsTwoStarFifteenMinutes() {
        let twoStar = UUID()
        let ids = rankedIDs(
            visited: [visited(twoStar, minutesAway: 15, rating: 2)],
            unvisited: [unvisited("bn", minutesAway: 3, reliability: .reliable)]
        )
        #expect(ids == [.candidate("bn"), .bathroom(twoStar)])
    }

    @Test(arguments: [
        (hour: 21, minute: 59, lateNight: false),
        (hour: 22, minute: 0, lateNight: true),
        (hour: 2, minute: 30, lateNight: true),
        (hour: 5, minute: 59, lateNight: true),
        (hour: 6, minute: 0, lateNight: false),
        (hour: 12, minute: 0, lateNight: false),
    ])
    func lateNightPenaltyAppliesOnlyBetweenTenAndSix(hour: Int, minute: Int, lateNight: Bool) {
        // Closes at night, 2 minutes away, versus open 24 hours, 10 minutes away.
        let closes = UUID()
        let allNight = UUID()
        let ids = rankedIDs(
            at: time(hour: hour, minute: minute),
            visited: [
                visited(closes, minutesAway: 2, rating: 5, isOpen24Hours: false),
                visited(allNight, minutesAway: 10, rating: 5, isOpen24Hours: true),
            ]
        )
        #expect(ids.first == (lateNight ? .bathroom(allNight) : .bathroom(closes)))
    }

    // MARK: - Exclusion

    @Test func dismissedAndLinkedCandidatesAreNeverReturned() {
        let logged = UUID()
        let ids = rankedIDs(
            visited: [visited(logged, minutesAway: 20, rating: 1, sourceID: "linked")],
            unvisited: [
                unvisited("dismissed", minutesAway: 1, reliability: .reliable, isDismissed: true),
                unvisited("linked", minutesAway: 1, reliability: .reliable),
                unvisited("open", minutesAway: 30, reliability: .uncertain),
            ]
        )
        #expect(ids == [.bathroom(logged), .candidate("open")])
    }

    @Test func returnsNothingWhenEveryPlaceIsExcluded() {
        let ids = rankedIDs(unvisited: [unvisited("dismissed", minutesAway: 1, reliability: .reliable, isDismissed: true)])
        #expect(ids.isEmpty)
    }

    // MARK: - Driving times

    @Test func drivingTimesOverrideStraightLineEstimate() {
        // Across a river: 1 minute as the crow flies, 30 minutes by car.
        let acrossRiver = UUID()
        let sameSide = UUID()
        let ids = rankedIDs(
            visited: [
                visited(acrossRiver, minutesAway: 1, rating: 5),
                visited(sameSide, minutesAway: 5, rating: 5),
            ],
            drivingTimes: [.bathroom(acrossRiver): 30 * 60]
        )
        #expect(ids == [.bathroom(sameSide), .bathroom(acrossRiver)])
    }

    @Test func effectiveMinutesAddTravelAndPenalties() {
        let ranked = EmergencyRanker.rank(
            from: origin, at: time(hour: 23), calendar: Self.calendar,
            visited: [],
            unvisited: [unvisited("likely", minutesAway: 0, reliability: .likely, isOpen24Hours: false)],
            drivingTimes: [.candidate("likely"): 7 * 60]
        )
        // 7 driving + 5 likely brand + 20 closed at night.
        #expect(ranked.map(\.effectiveMinutes) == [32])
    }
}
