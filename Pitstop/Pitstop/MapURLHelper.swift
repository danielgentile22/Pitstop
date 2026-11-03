import UIKit

enum MapURLHelper {

    enum TransportMode {
        case walking
        case driving

        /// Mode value shared by the `maps.apple.com` and `comgooglemaps://` links.
        fileprivate var urlValue: String {
            switch self {
            case .walking: return "walking"
            case .driving: return "driving"
            }
        }
    }

    /// Opens directions in Apple Maps. Returns false when the link could not be opened.
    @discardableResult
    static func openDirections(toLatitude lat: Double, longitude lon: Double, mode: TransportMode = .walking) async -> Bool {
        guard let url = URL(string: "https://maps.apple.com/directions?destination=\(coordinate(lat, lon))&mode=\(mode.urlValue)") else {
            return false
        }
        return await UIApplication.shared.open(url)
    }

    /// Opens directions in Google Maps, falling back to Apple Maps when Google Maps is not
    /// installed or refuses the link. Returns false when neither could be opened.
    ///
    /// `open(_:)` returns false for a scheme no installed app claims, so this needs no
    /// `LSApplicationQueriesSchemes` entry the way `canOpenURL(_:)` would.
    @discardableResult
    static func openDirectionsPreferringGoogleMaps(toLatitude lat: Double, longitude lon: Double, mode: TransportMode = .walking) async -> Bool {
        if let url = URL(string: "comgooglemaps://?daddr=\(coordinate(lat, lon))&directionsmode=\(mode.urlValue)"),
           await UIApplication.shared.open(url) {
            return true
        }
        return await openDirections(toLatitude: lat, longitude: lon, mode: mode)
    }

    /// Fixed-point formatting: default Double interpolation can emit scientific notation.
    private static func coordinate(_ lat: Double, _ lon: Double) -> String {
        String(format: "%.6f,%.6f", lat, lon)
    }
}
