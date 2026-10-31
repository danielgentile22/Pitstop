import UIKit

enum MapURLHelper {

    enum TransportMode {
        case walking
        case driving

        /// `mode` value for the `maps.apple.com` universal link.
        fileprivate var universalLinkMode: String {
            switch self {
            case .walking: return "walking"
            case .driving: return "driving"
            }
        }
    }

    /// Opens directions in Apple Maps. Returns false when the link could not be opened.
    @discardableResult
    static func openDirections(toLatitude lat: Double, longitude lon: Double, mode: TransportMode = .walking) async -> Bool {
        // Fixed-point formatting: default Double interpolation can emit scientific notation.
        let latStr = String(format: "%.6f", lat)
        let lonStr = String(format: "%.6f", lon)

        guard let url = URL(string: "https://maps.apple.com/directions?destination=\(latStr),\(lonStr)&mode=\(mode.universalLinkMode)") else {
            return false
        }
        return await UIApplication.shared.open(url)
    }
}
