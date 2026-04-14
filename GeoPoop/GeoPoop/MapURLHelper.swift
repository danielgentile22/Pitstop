//
//  MapURLHelper.swift
//  GeoPoop
//
//  Shared helper for building and opening Apple Maps URLs.
//  Previously duplicated in ContentView (emergency) and DetailView (Open in Maps).
//
//  Coordinate format:
//    Uses String(format: "%.6f") to guarantee a plain decimal representation —
//    Double's default interpolation can produce scientific notation for extreme
//    coordinate values, which would silently break the URL.
//

import UIKit

enum MapURLHelper {

    /// Opens Apple Maps with walking directions to the given coordinate.
    ///
    /// Tries the unified scheme (iOS 18+) first, then falls back to the classic
    /// `maps://` scheme which works on all supported iOS versions.
    static func openDirections(toLatitude lat: Double, longitude lon: Double) {
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
