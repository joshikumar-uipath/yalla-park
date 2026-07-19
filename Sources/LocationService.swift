import Foundation
import CoreLocation

/// One-shot location per spec §3 — no background tracking, "when in use" only.
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    var coordinate: CLLocationCoordinate2D?
    var areaName: String?
    var denied = false
    /// Incremented on every fix — CLLocationCoordinate2D isn't Equatable, so views observe this.
    var fixID = 0

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters // fast fix is fine (§8)
    }

    func requestOneShot() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            denied = true
        default:
            manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            denied = false
            manager.requestLocation()
        case .denied, .restricted:
            denied = true
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.first else { return }
        coordinate = location.coordinate
        fixID += 1
        geocoder.reverseGeocodeLocation(location) { [weak self] placemarks, _ in
            guard let p = placemarks?.first else { return }
            // Prefer the street — it's what you'd read off the parking sign area.
            self?.areaName = p.thoroughfare ?? p.subLocality ?? p.locality ?? p.name
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Never block the UI on a fix (§8) — the screen already rendered.
    }
}
