import UIKit

enum MapURLHelper {

    /// Opens walking directions in Apple Maps, preferring the universal link over `maps://`.
    static func openDirections(toLatitude lat: Double, longitude lon: Double) {
        // Fixed-point formatting: default Double interpolation can emit scientific notation.
        let latStr = String(format: "%.6f", lat)
        let lonStr = String(format: "%.6f", lon)

        let candidates = [
            "https://maps.apple.com/directions?destination=\(latStr),\(lonStr)&mode=walking",
            "maps://?daddr=\(latStr),\(lonStr)&dirflg=w"
        ]

        for urlString in candidates {
            if let url = URL(string: urlString), UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
                return
            }
        }
    }
}
