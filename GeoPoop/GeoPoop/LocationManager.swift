//
//  LocationManager.swift
//  GeoPoop
//
//  @Observable wrapper around CLLocationManager that exposes the user's
//  live GPS coordinate and authorization status to the SwiftUI view tree.
//

import CoreLocation
import SwiftUI

/// Manages GPS permissions and streams the user's live coordinate.
///
/// Create one instance and pass it through the view hierarchy.
/// Views access `userLocation`, `hasLocationPermission`, and `isLocationDenied`
/// to react to changes automatically.
@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {

    // MARK: - Published State

    /// The user's most recently received GPS coordinate.
    /// Nil until the first fix arrives (usually within a second of authorization).
    var userLocation: CLLocationCoordinate2D?

    /// The current Core Location authorization status.
    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// A human-readable error string set when location fails.
    var locationError: String?

    // MARK: - Private

    private let manager = CLLocationManager()

    /// Guards against calling startUpdatingLocation() when already active.
    private var isUpdatingLocation = false

    // MARK: - Init

    override init() {
        super.init()
        manager.delegate = self
        // NearestTenMeters is more than precise enough to find a nearby bathroom
        // and significantly better for battery life than kCLLocationAccuracyBest.
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    // MARK: - Public Methods

    /// Call once on app launch. Shows the permission prompt if not yet determined;
    /// otherwise immediately starts location updates if already authorized.
    func requestPermission() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            evaluateAuthorization(manager.authorizationStatus)
        }
    }

    /// True if the user has granted location access (either WhenInUse or Always).
    var hasLocationPermission: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    /// True if the user has explicitly denied location access.
    var isLocationDenied: Bool {
        authorizationStatus == .denied || authorizationStatus == .restricted
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        evaluateAuthorization(manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        userLocation = location.coordinate
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationError = error.localizedDescription
    }

    // MARK: - Private Helpers

    private func evaluateAuthorization(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            locationError = nil
            // Guard prevents redundant startUpdatingLocation() calls on every
            // ContentView.onAppear when permission is already granted.
            guard !isUpdatingLocation else { return }
            isUpdatingLocation = true
            manager.startUpdatingLocation()

        case .denied:
            locationError = "Location access denied. Enable it in Settings to use map features."
            isUpdatingLocation = false
            manager.stopUpdatingLocation()

        case .restricted:
            locationError = "Location access is restricted on this device."
            isUpdatingLocation = false
            manager.stopUpdatingLocation()

        case .notDetermined:
            break

        @unknown default:
            break
        }
    }
}
