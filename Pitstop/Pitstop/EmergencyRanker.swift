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

        func ranked(_ id: PlaceID, _ latitude: Double, _ longitude: Double,
                    penalty: Double, isOpen24Hours: Bool) -> RankedPlace {
            let travelMinutes = drivingTimes[id].map { $0 / 60 }
                ?? CLLocation(latitude: latitude, longitude: longitude).distance(from: originLocation)
                    / fallbackMetersPerMinute
            let lateNight = isLateNight && !isOpen24Hours ? Penalty.closedLateNight : 0
            return RankedPlace(id: id, latitude: latitude, longitude: longitude,
                               effectiveMinutes: travelMinutes + penalty + lateNight)
        }

        let linkedIDs = Set(visited.compactMap(\.sourceID))

        let visitedRanked = visited.map {
            ranked(.bathroom($0.id), $0.latitude, $0.longitude,
                   penalty: Penalty.visited(rating: $0.rating), isOpen24Hours: $0.isOpen24Hours)
        }
        let unvisitedRanked = unvisited
            .filter { !$0.isDismissed && !linkedIDs.contains($0.sourceID) }
            .map {
                ranked(.candidate($0.sourceID), $0.latitude, $0.longitude,
                       penalty: Penalty.unvisited($0.reliability), isOpen24Hours: $0.isOpen24Hours)
            }

        return (visitedRanked + unvisitedRanked).sorted { $0.effectiveMinutes < $1.effectiveMinutes }
    }
}
