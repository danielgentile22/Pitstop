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

        /// `dirflg` value for the `maps://` scheme.
        fileprivate var schemeFlag: String {
            switch self {
            case .walking: return "w"
            case .driving: return "d"
            }
        }
    }

    /// Opens directions in Apple Maps, preferring the universal link over `maps://`.
    static func openDirections(toLatitude lat: Double, longitude lon: Double, mode: TransportMode = .walking) {
        // Fixed-point formatting: default Double interpolation can emit scientific notation.
        let latStr = String(format: "%.6f", lat)
        let lonStr = String(format: "%.6f", lon)

        let candidates = [
            "https://maps.apple.com/directions?destination=\(latStr),\(lonStr)&mode=\(mode.universalLinkMode)",
            "maps://?daddr=\(latStr),\(lonStr)&dirflg=\(mode.schemeFlag)"
        ]

        for urlString in candidates {
            if let url = URL(string: urlString), UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                return
            }
        }
    }
}
