import Foundation
import CoreLocation
import Observation

/// Thin observable wrapper around `CLLocationManager`.
///
/// The manager is created on the main thread, so Core Location delivers delegate callbacks
/// on the main thread; `MainActor.assumeIsolated` documents and checks that assumption.
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    private(set) var lastLocation: CLLocation?
    private(set) var isUpdating = false
    private(set) var lastError: String?

    @ObservationIgnored var onLocation: (@MainActor (CLLocation) -> Void)?
    @ObservationIgnored var onError: (@MainActor (String) -> Void)?

    private let manager = CLLocationManager()

    override init() {
        super.init()
        authorizationStatus = manager.authorizationStatus
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .otherNavigation
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    var statusTitle: String {
        switch authorizationStatus {
        case .notDetermined: "Не запрошено"
        case .restricted: "Ограничено"
        case .denied: "Запрещено"
        case .authorizedAlways: "Разрешено всегда"
        case .authorizedWhenInUse: "При использовании"
        @unknown default: "Неизвестно"
        }
    }

    func requestAuthorization() {
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func startUpdating() {
        requestAuthorization()
        lastError = nil
        manager.startUpdatingLocation()
        isUpdating = true
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
        isUpdating = false
    }

    // MARK: CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard !locations.isEmpty else { return }
        lastLocation = locations.last
        let batch = locations
        MainActor.assumeIsolated {
            for location in batch {
                onLocation?(location)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // kCLErrorLocationUnknown is transient: Core Location keeps trying.
        if let clError = error as? CLError, clError.code == .locationUnknown { return }
        let message = error.localizedDescription
        lastError = message
        MainActor.assumeIsolated {
            onError?(message)
        }
    }
}
