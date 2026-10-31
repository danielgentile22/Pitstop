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
        isOpen24Hours: Bool? = true,
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
        isOpen24Hours: Bool? = true,
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

    @Test func lateNightPenaltySkipsCandidatesWithUnknownHours() {
        let ranked = EmergencyRanker.rank(
            from: origin, at: time(hour: 2), calendar: Self.calendar,
            visited: [],
            unvisited: [
                unvisited("unknown", minutesAway: 0, reliability: .likely, isOpen24Hours: nil),
                unvisited("closes", minutesAway: 0, reliability: .likely, isOpen24Hours: false),
            ],
            drivingTimes: [.candidate("unknown"): 7 * 60, .candidate("closes"): 7 * 60]
        )
        // 7 driving + 5 likely brand, plus 20 only for the place known to close at night.
        #expect(ranked.map(\.id) == [.candidate("unknown"), .candidate("closes")])
        #expect(ranked.map(\.effectiveMinutes) == [12, 32])
    }

    @Test func lateNightPenaltySkipsBathroomsWithUnknownHours() {
        let unknown = UUID(), closes = UUID()
        let ranked = EmergencyRanker.rank(
            from: origin, at: time(hour: 2), calendar: Self.calendar,
            visited: [
                visited(unknown, minutesAway: 0, rating: 5, isOpen24Hours: nil),
                visited(closes, minutesAway: 0, rating: 5, isOpen24Hours: false),
            ],
            unvisited: [],
            drivingTimes: [.bathroom(unknown): 7 * 60, .bathroom(closes): 7 * 60]
        )
        // 7 driving + 0 for five stars, plus 20 only for the place known to close at night.
        #expect(ranked.map(\.id) == [.bathroom(unknown), .bathroom(closes)])
        #expect(ranked.map(\.effectiveMinutes) == [7, 27])
    }

    @Test(arguments: [
        (rating: 5, minutes: 0.0),
        (rating: 4, minutes: 0.0),
        (rating: 3, minutes: 2.0),
        (rating: 0, minutes: 2.0),
        (rating: 2, minutes: 5.0),
        (rating: 1, minutes: 5.0),
    ])
    func visitedPenaltyTable(rating: Int, minutes: Double) {
        let id = UUID()
        let ranked = EmergencyRanker.rank(
            from: origin, at: time(hour: 12), calendar: Self.calendar,
            visited: [visited(id, minutesAway: 0, rating: rating)], unvisited: [],
            drivingTimes: [.bathroom(id): 0]
        )
        #expect(ranked.map(\.effectiveMinutes) == [minutes])
    }

    @Test(arguments: [
        (reliability: Reliability.reliable, minutes: 3.0),
        (reliability: Reliability.likely, minutes: 5.0),
        (reliability: Reliability.uncertain, minutes: 10.0),
    ])
    func unvisitedPenaltyTable(reliability: Reliability, minutes: Double) {
        let ranked = EmergencyRanker.rank(
            from: origin, at: time(hour: 12), calendar: Self.calendar,
            visited: [], unvisited: [unvisited("place", minutesAway: 0, reliability: reliability)],
            drivingTimes: [.candidate("place"): 0]
        )
        #expect(ranked.map(\.effectiveMinutes) == [minutes])
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

    // MARK: - Range limit

    @Test func placesBeyondFortyFiveEffectiveMinutesAreLeftOut() {
        let ranked = EmergencyRanker.rank(
            from: origin, at: time(hour: 12), calendar: Self.calendar,
            visited: [],
            unvisited: [
                unvisited("edge", minutesAway: 0, reliability: .reliable),
                unvisited("beyond", minutesAway: 0, reliability: .reliable),
            ],
            // 42 + 3 reliable is exactly 45; 42.5 + 3 is past it.
            drivingTimes: [.candidate("edge"): 42 * 60, .candidate("beyond"): 42.5 * 60]
        )
        #expect(ranked.map(\.id) == [.candidate("edge")])
    }

    @Test func returnsNothingWhenEveryPlaceIsOutOfRange() {
        let far = UUID()
        let ids = rankedIDs(visited: [visited(far, minutesAway: 0, rating: 5)], drivingTimes: [.bathroom(far): 60 * 60])
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

    @Test func nearestPicksClosestEligiblePlacesByStraightLine() {
        let far = UUID()
        let near = UUID()
        let nearest = EmergencyRanker.nearest(
            3,
            from: origin,
            visited: [
                visited(far, minutesAway: 40, rating: 5),
                visited(near, minutesAway: 2, rating: 1, sourceID: "linked"),
            ],
            unvisited: [
                unvisited("dismissed", minutesAway: 1, reliability: .reliable, isDismissed: true),
                unvisited("linked", minutesAway: 1, reliability: .reliable),
                unvisited("middle", minutesAway: 10, reliability: .uncertain),
                unvisited("closest", minutesAway: 1.5, reliability: .uncertain),
            ]
        )
        #expect(nearest.map(\.id) == [.candidate("closest"), .bathroom(near), .candidate("middle")])
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

    @Test func straightLineFallbackDrivesAtTwentyMilesPerHour() {
        // 0.02 degrees due north is about 2,220 meters (a degree of latitude is about 111,000 meters).
        // 20 miles per hour is 20 * 1,609.344 / 60 = 536.448 meters a minute, so about 4.14 minutes.
        let id = UUID()
        let ranked = EmergencyRanker.rank(
            from: origin, at: time(hour: 12), calendar: Self.calendar,
            visited: [.init(id: id, sourceID: nil, latitude: origin.latitude + 0.02, longitude: origin.longitude,
                            rating: 5, isOpen24Hours: true)],
            unvisited: []
        )
        #expect(ranked.count == 1)
        #expect(abs((ranked.first?.effectiveMinutes ?? 0) - 4.14) < 0.05)
    }

    // MARK: - Mapping stored places

    @Test(arguments: [
        (isOpen24Hours: true, isOpen24HoursKnown: Bool?.none, expected: Bool?.some(true)),
        (isOpen24Hours: false, isOpen24HoursKnown: Bool?.none, expected: Bool?.some(false)),
        (isOpen24Hours: false, isOpen24HoursKnown: Bool?.some(true), expected: Bool?.some(false)),
        (isOpen24Hours: false, isOpen24HoursKnown: Bool?.some(false), expected: Bool?.none),
    ])
    func visitedPlaceCopiesBathroom(isOpen24Hours: Bool, isOpen24HoursKnown: Bool?, expected: Bool?) {
        let bathroom = Bathroom(name: "Shop", latitude: 38.9, longitude: -77.1, rating: 4, isOpen24Hours: isOpen24Hours)
        bathroom.sourceID = "node/1"
        bathroom.isOpen24HoursKnown = isOpen24HoursKnown
        let place = EmergencyRanker.VisitedPlace(bathroom)
        #expect(place.id == bathroom.id)
        #expect(place.sourceID == "node/1")
        #expect(place.latitude == 38.9)
        #expect(place.longitude == -77.1)
        #expect(place.rating == 4)
        #expect(place.isOpen24Hours == expected)
    }

    @Test(arguments: [
        (openingHours: String?.none, isOpen24Hours: false, expected: Bool?.none),
        (openingHours: String?.some("24/7"), isOpen24Hours: true, expected: Bool?.some(true)),
        (openingHours: String?.some("Mo-Su 08:00-22:00"), isOpen24Hours: false, expected: Bool?.some(false)),
    ])
    func unvisitedPlaceCopiesCandidate(openingHours: String?, isOpen24Hours: Bool, expected: Bool?) {
        let candidate = Candidate(sourceID: "node/2", brandKey: "wegmans", name: "Wegmans",
                                  latitude: 38.7, longitude: -77.2, isOpen24Hours: isOpen24Hours,
                                  openingHours: openingHours, isDismissed: true, seedVersion: 1)
        let place = EmergencyRanker.UnvisitedPlace(candidate)
        #expect(place.sourceID == "node/2")
        #expect(place.latitude == 38.7)
        #expect(place.longitude == -77.2)
        #expect(place.reliability == .likely)
        #expect(place.isOpen24Hours == expected)
        #expect(place.isDismissed == true)
    }
}
