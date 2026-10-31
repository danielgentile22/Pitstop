import Foundation
import CoreLocation

/// Ranks every place the emergency button could send the user to by effective minutes:
/// travel minutes plus penalties for uncertainty. Pure: plain values in, ordered values out.
enum EmergencyRanker {

    // MARK: - Penalties

    /// Every penalty, in minutes. Starting guesses; tune here.
    enum Penalty {
        static func visited(rating: Int) -> Double {
            switch rating {
            case 4...5: return 0
            case 1...2: return 5
            default:    return 2   // 3 stars or unrated (0)
            }
        }

        static func unvisited(_ reliability: Reliability) -> Double {
            switch reliability {
            case .reliable:  return 3
            case .likely:    return 5
            case .uncertain: return 10
            }
        }

        /// Added to places not open 24 hours from `lateNightStartHour` until `lateNightEndHour`, local time.
        static let closedLateNight: Double = 20
        static let lateNightStartHour = 22
        static let lateNightEndHour   = 6

        // Dismissed Candidates are never chosen: `rank` drops them instead of penalizing them.
    }

    /// Speed assumed for places without a driving time.
    static let fallbackMilesPerHour: Double = 20
    static let fallbackMetersPerMinute = fallbackMilesPerHour * 1609.344 / 60

    // MARK: - Inputs

    nonisolated enum PlaceID: Hashable {
        case bathroom(UUID)
        case candidate(String)   // Candidate.sourceID
    }

    struct VisitedPlace {
        let id: UUID
        /// The Candidate this bathroom was logged from, if any. That Candidate is never returned.
        let sourceID: String?
        let latitude: Double
        let longitude: Double
        let rating: Int
        let isOpen24Hours: Bool
    }

    struct UnvisitedPlace {
        let sourceID: String
        let latitude: Double
        let longitude: Double
        let reliability: Reliability
        let isOpen24Hours: Bool
        let isDismissed: Bool
    }

    // MARK: - Output

    struct RankedPlace {
        let id: PlaceID
        let latitude: Double
        let longitude: Double
        let effectiveMinutes: Double
    }

    /// A place the user could be sent to, before any travel time is known.
    struct Destination {
        let id: PlaceID
        let latitude: Double
        let longitude: Double
    }

    // MARK: - Ranking

    /// - Parameters:
    ///   - calendar: Supplies the local time zone for the late-night rule.
    ///   - drivingTimes: Travel time in seconds per place. Places missing from it use straight-line
    ///     distance at `fallbackMilesPerHour`.
    static func rank(
        from origin: CLLocationCoordinate2D,
        at now: Date,
        calendar: Calendar = .current,
        visited: [VisitedPlace],
        unvisited: [UnvisitedPlace],
        drivingTimes: [PlaceID: TimeInterval] = [:]
    ) -> [RankedPlace] {
        let originLocation = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        let hour = calendar.component(.hour, from: now)
        let isLateNight = hour >= Penalty.lateNightStartHour || hour < Penalty.lateNightEndHour

        return eligible(visited: visited, unvisited: unvisited)
            .map { place in
                let travelMinutes = drivingTimes[place.destination.id].map { $0 / 60 }
                    ?? distance(from: originLocation, to: place.destination) / fallbackMetersPerMinute
                let lateNight = isLateNight && !place.isOpen24Hours ? Penalty.closedLateNight : 0
                return RankedPlace(id: place.destination.id,
                                   latitude: place.destination.latitude,
                                   longitude: place.destination.longitude,
                                   effectiveMinutes: travelMinutes + place.penalty + lateNight)
            }
            .sorted { $0.effectiveMinutes < $1.effectiveMinutes }
    }

    /// The `limit` places `rank` could return that are closest in a straight line: the ones worth
    /// asking a directions service about.
    static func nearest(
        _ limit: Int,
        from origin: CLLocationCoordinate2D,
        visited: [VisitedPlace],
        unvisited: [UnvisitedPlace]
    ) -> [Destination] {
        let originLocation = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        return eligible(visited: visited, unvisited: unvisited)
            .map { ($0.destination, distance(from: originLocation, to: $0.destination)) }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map(\.0)
    }

    // MARK: - Eligibility

    private struct EligiblePlace {
        let destination: Destination
        let penalty: Double
        let isOpen24Hours: Bool
    }

    /// Every Bathroom, plus every Candidate that is neither dismissed nor already logged as a Bathroom.
    private static func eligible(visited: [VisitedPlace], unvisited: [UnvisitedPlace]) -> [EligiblePlace] {
        let linkedIDs = Set(visited.compactMap(\.sourceID))

        let visitedPlaces = visited.map {
            EligiblePlace(destination: .init(id: .bathroom($0.id), latitude: $0.latitude, longitude: $0.longitude),
                          penalty: Penalty.visited(rating: $0.rating), isOpen24Hours: $0.isOpen24Hours)
        }
        let unvisitedPlaces = unvisited
            .filter { !$0.isDismissed && !linkedIDs.contains($0.sourceID) }
            .map {
                EligiblePlace(destination: .init(id: .candidate($0.sourceID), latitude: $0.latitude, longitude: $0.longitude),
                              penalty: Penalty.unvisited($0.reliability), isOpen24Hours: $0.isOpen24Hours)
            }
        return visitedPlaces + unvisitedPlaces
    }

    private static func distance(from origin: CLLocation, to destination: Destination) -> CLLocationDistance {
        CLLocation(latitude: destination.latitude, longitude: destination.longitude).distance(from: origin)
    }
}
