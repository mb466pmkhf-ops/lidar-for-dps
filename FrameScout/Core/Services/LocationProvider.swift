import CoreLocation
import Foundation

/// One-shot GPS fix + optional reverse geocode. GPS works offline; the address lookup
/// needs a connection and is simply skipped when there is none.
@MainActor
final class LocationProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var isLocating = false
    @Published private(set) var lastError: String?

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    struct Fix {
        var coordinate: GeoCoordinate
        var address: String?
        var timeZoneIdentifier: String?
    }

    func currentFix() async -> Fix? {
        lastError = nil
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        isLocating = true
        defer { isLocating = false }

        let location: CLLocation? = await withCheckedContinuation { cont in
            self.continuation?.resume(returning: nil)
            self.continuation = cont
            self.manager.requestLocation()
        }
        guard let location else { return nil }

        var fix = Fix(coordinate: GeoCoordinate(latitude: location.coordinate.latitude,
                                                longitude: location.coordinate.longitude,
                                                altitude: location.altitude))
        if let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first {
            fix.address = [placemark.name, placemark.locality, placemark.administrativeArea, placemark.country]
                .compactMap { $0 }
                .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
                .joined(separator: ", ")
            fix.timeZoneIdentifier = placemark.timeZone?.identifier
        }
        return fix
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let last = locations.last
        Task { @MainActor in
            self.continuation?.resume(returning: last)
            self.continuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            self.lastError = message
            self.continuation?.resume(returning: nil)
            self.continuation = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            if status == .denied || status == .restricted {
                self.lastError = "Location access is off. Enable it in Settings › FrameScout, or enter coordinates manually."
                self.continuation?.resume(returning: nil)
                self.continuation = nil
            }
        }
    }
}
