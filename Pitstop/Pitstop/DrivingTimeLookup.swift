import Foundation
import CoreLocation
import MapKit

/// Asks Apple's directions service for driving times, all at once, and gives up at a deadline.
enum DrivingTimeLookup {

    /// Returns travel time in seconds for every destination that answered before `deadline`.
    /// Failures (no signal, no route) and late answers are simply missing, so the ranker falls back
    /// to straight-line distance for them.
    static func drivingTimes(
        from origin: CLLocationCoordinate2D,
        to destinations: [EmergencyRanker.Destination],
        deadline: Duration = .seconds(3)
    ) async -> [EmergencyRanker.PlaceID: TimeInterval] {
        let (answers, continuation) = AsyncStream.makeStream(of: (EmergencyRanker.PlaceID, TimeInterval).self)

        // The stream, not the task group, enforces the deadline: a request that ignores
        // cancellation can delay the group finishing, but never the return.
        let lookups = Task { @MainActor in
            await withTaskGroup(of: Void.self) { group in
                for destination in destinations {
                    group.addTask { @MainActor in
                        if let seconds = await travelTime(from: origin, to: destination) {
                            continuation.yield((destination.id, seconds))
                        }
                    }
                }
            }
            continuation.finish()
        }
        let timer = Task {
            try? await Task.sleep(for: deadline)
            continuation.finish()
        }

        var times: [EmergencyRanker.PlaceID: TimeInterval] = [:]
        for await (id, seconds) in answers {
            times[id] = seconds
        }
        lookups.cancel()
        timer.cancel()
        return times
    }

    private static func travelTime(
        from origin: CLLocationCoordinate2D,
        to destination: EmergencyRanker.Destination
    ) async -> TimeInterval? {
        let request = MKDirections.Request()
        request.source = MKMapItem(location: CLLocation(latitude: origin.latitude, longitude: origin.longitude),
                                   address: nil)
        request.destination = MKMapItem(location: CLLocation(latitude: destination.latitude,
                                                             longitude: destination.longitude),
                                        address: nil)
        request.transportType = .automobile

        let directions = MKDirections(request: request)
        return await withTaskCancellationHandler {
            try? await directions.calculateETA().expectedTravelTime
        } onCancel: {
            Task { @MainActor in directions.cancel() }
        }
    }
}
