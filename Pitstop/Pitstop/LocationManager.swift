import CoreLocation
import SwiftUI

@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {

    // MARK: - State

    /// The latest fix, with its timestamp and accuracy.
    private(set) var latestFix: CLLocation?

    var userLocation: CLLocationCoordinate2D? { latestFix?.coordinate }

    var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// True when the user allowed only approximate location, which can be kilometers off.
    private(set) var isApproximateOnly = false

    // MARK: - Private

    private let manager = CLLocationManager()

    private var isUpdatingLocation = false

    /// Wakes `freshFix(timeout:)` when a fresh fix arrives.
    private var freshFixWaiter: AsyncStream<Void>.Continuation?

    /// Key in NSLocationTemporaryUsageDescriptionDictionary.
    private static let emergencyPurposeKey = "Emergency"

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

    /// Asks for one-time precise location when only approximate location is allowed.
    func requestTemporaryFullAccuracy() async {
        guard isApproximateOnly else { return }
        _ = try? await manager.requestTemporaryFullAccuracyAuthorization(withPurposeKey: Self.emergencyPurposeKey)
        isApproximateOnly = manager.accuracyAuthorization == .reducedAccuracy
    }

    // MARK: - Fresh Fix

    /// Returns a fix taken in the last minute, waiting up to `timeout` for one.
    /// Falls back to the latest fix, however old, so callers always get an answer if one exists.
    func freshFix(timeout: Duration) async -> CLLocation? {
        if let fix = latestFix, isFresh(fix) { return fix }
        guard isUpdatingLocation else { return latestFix }

        let (arrivals, continuation) = AsyncStream.makeStream(of: Void.self)
        freshFixWaiter?.finish()
        freshFixWaiter = continuation
        // Restarting delivers a new fix even when standing still, where updates otherwise pause.
        manager.stopUpdatingLocation()
        manager.startUpdatingLocation()

        let timer = Task {
            try? await Task.sleep(for: timeout)
            continuation.finish()
        }
        for await _ in arrivals { break }
        timer.cancel()
        continuation.finish()
        return latestFix
    }

    /// Under a minute old and within 100 meters. Approximate location never gets that precise,
    /// so it only has to be recent.
    private func isFresh(_ fix: CLLocation) -> Bool {
        guard -fix.timestamp.timeIntervalSinceNow <= 60 else { return false }
        if isApproximateOnly { return true }
        return fix.horizontalAccuracy >= 0 && fix.horizontalAccuracy <= 100
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        isApproximateOnly = manager.accuracyAuthorization == .reducedAccuracy
        evaluateAuthorization(manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        latestFix = location
        if isFresh(location) {
            freshFixWaiter?.yield()
            freshFixWaiter?.finish()
            freshFixWaiter = nil
        }
    }

    // MARK: - Private Helpers

    private func evaluateAuthorization(_ status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            // requestPermission() runs on every ContentView appearance.
            guard !isUpdatingLocation else { return }
            isUpdatingLocation = true
            manager.startUpdatingLocation()

        case .denied, .restricted:
            isUpdatingLocation = false
            manager.stopUpdatingLocation()

        case .notDetermined:
            break

        @unknown default:
            break
        }
    }
}
