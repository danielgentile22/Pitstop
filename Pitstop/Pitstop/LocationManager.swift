import CoreLocation
import SwiftUI

@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {

    // MARK: - State

    var userLocation: CLLocationCoordinate2D?

    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    var locationError: String?

    // MARK: - Private

    private let manager = CLLocationManager()

    private var isUpdatingLocation = false

    // MARK: - Init

    override init() {
        super.init()
        manager.delegate = self
        // Ten meters is enough to find a bathroom and much cheaper on battery than Best.
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    // MARK: - Permission

    /// Prompts if undetermined, otherwise starts updates when already authorized.
    func requestPermission() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else {
            evaluateAuthorization(manager.authorizationStatus)
        }
    }

    var hasLocationPermission: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

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
            // requestPermission() runs on every ContentView appearance.
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
