@preconcurrency import CoreLocation
import Foundation

struct BlurbCityLocation: Hashable {
    let city: String
    let region: String?
    let countryCode: String?

    var displayName: String {
        guard let region, !region.isEmpty else { return city }
        return "\(city), \(region)"
    }

    var firestoreData: [String: String] {
        var data = ["city": city]
        if let region, !region.isEmpty { data["region"] = region }
        if let countryCode, !countryCode.isEmpty { data["countryCode"] = countryCode }
        return data
    }

    init?(data: [String: Any]) {
        guard let city = data["city"] as? String,
              !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        self.city = city.trimmingCharacters(in: .whitespacesAndNewlines)
        region = (data["region"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        countryCode = (data["countryCode"] as? String)?.uppercased()
    }

    init(city: String, region: String?, countryCode: String?) {
        self.city = city
        self.region = region
        self.countryCode = countryCode
    }
}

@MainActor
final class CityLocationProvider: NSObject, @preconcurrency CLLocationManagerDelegate {
    static let shared = CityLocationProvider()

    private let manager = CLLocationManager()
    private var waiters: [CheckedContinuation<BlurbCityLocation?, Never>] = []
    private var cachedResult: (location: BlurbCityLocation, date: Date)?
    private var requestInFlight = false

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func currentCity() async -> BlurbCityLocation? {
        if let cachedResult, Date.now.timeIntervalSince(cachedResult.date) < 600 {
            return cachedResult.location
        }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
            guard !requestInFlight else { return }
            requestInFlight = true
            beginRequest()
        }
    }

    private func beginRequest() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            manager.requestLocation()
        case .denied, .restricted:
            finish(with: nil)
        @unknown default:
            finish(with: nil)
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard requestInFlight else { return }
        beginRequest()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            finish(with: nil)
            return
        }
        Task {
            let placemark = try? await CLGeocoder().reverseGeocodeLocation(location).first
            guard let city = placemark?.locality?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !city.isEmpty else {
                finish(with: nil)
                return
            }
            let result = BlurbCityLocation(
                city: city,
                region: placemark?.administrativeArea,
                countryCode: placemark?.isoCountryCode
            )
            cachedResult = (result, .now)
            finish(with: result)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        finish(with: nil)
    }

    private func finish(with result: BlurbCityLocation?) {
        requestInFlight = false
        let continuations = waiters
        waiters.removeAll()
        continuations.forEach { $0.resume(returning: result) }
    }
}
