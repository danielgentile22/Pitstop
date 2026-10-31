import CoreLocation
import MapKit

/// Straight-line distance and how it reads on screen. The filter, the list, the rows, the detail views
/// and the ranker all measure with this, so they never disagree.
enum Distance {

    /// Straight-line distance in meters.
    static func meters(from origin: CLLocationCoordinate2D, to destination: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: destination.latitude, longitude: destination.longitude)
            .distance(from: CLLocation(latitude: origin.latitude, longitude: origin.longitude))
    }

    /// Abbreviated, in the user's units ("0.4 mi"). Nil without a location to measure from.
    static func formatted(from origin: CLLocationCoordinate2D?, to destination: CLLocationCoordinate2D) -> String? {
        guard let origin else { return nil }
        return formatter.string(fromDistance: meters(from: origin, to: destination))
    }

    private static let formatter: MKDistanceFormatter = {
        let formatter = MKDistanceFormatter()
        formatter.unitStyle = .abbreviated
        return formatter
    }()
}
