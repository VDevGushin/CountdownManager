import CoreLocation
import Foundation

package struct WeatherCoordinates: Equatable, Sendable {
    package let latitude: Double
    package let longitude: Double

    package init?(latitude: Double, longitude: Double) {
        guard latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        // Daily forecasts need an area, not a precise device position.
        self.latitude = (latitude * 100).rounded() / 100
        self.longitude = (longitude * 100).rounded() / 100
    }

    package var cacheIdentity: String {
        String(format: "%.2f,%.2f", locale: Locale(identifier: "en_US_POSIX"), latitude, longitude)
    }
}

package enum WeatherCity: String, CaseIterable, Identifiable, Sendable {
    case moscow, saintPetersburg, kazan, grozny, nizhnyNovgorod
    case yekaterinburg, novosibirsk, samara, rostovOnDon, krasnodar

    package var id: String { rawValue }

    package var title: String {
        switch self {
        case .moscow: return "Москва"
        case .saintPetersburg: return "Санкт-Петербург"
        case .kazan: return "Казань"
        case .grozny: return "Грозный"
        case .nizhnyNovgorod: return "Нижний Новгород"
        case .yekaterinburg: return "Екатеринбург"
        case .novosibirsk: return "Новосибирск"
        case .samara: return "Самара"
        case .rostovOnDon: return "Ростов-на-Дону"
        case .krasnodar: return "Краснодар"
        }
    }

    package var coordinates: WeatherCoordinates {
        let point: (Double, Double)
        switch self {
        case .moscow: point = (55.75, 37.62)
        case .saintPetersburg: point = (59.94, 30.31)
        case .kazan: point = (55.79, 49.12)
        case .grozny: point = (43.32, 45.69)
        case .nizhnyNovgorod: point = (56.33, 44.01)
        case .yekaterinburg: point = (56.84, 60.61)
        case .novosibirsk: point = (55.03, 82.92)
        case .samara: point = (53.20, 50.15)
        case .rostovOnDon: point = (47.22, 39.72)
        case .krasnodar: point = (45.04, 38.98)
        }
        return WeatherCoordinates(latitude: point.0, longitude: point.1)!
    }
}

package enum WeatherLocationSelection: Equatable, Hashable, Sendable {
    case automatic
    case city(WeatherCity)

    package var title: String {
        switch self {
        case .automatic: return "Автоматически"
        case let .city(city): return city.title
        }
    }

    var storedValue: String {
        switch self {
        case .automatic: return "automatic"
        case let .city(city): return city.rawValue
        }
    }

    init(storedValue: String?) {
        if let storedValue, let city = WeatherCity(rawValue: storedValue) {
            self = .city(city)
        } else {
            self = .automatic
        }
    }
}

package enum WeatherLocationFailure: Error, Sendable {
    case unavailable, denied, permissionRequired
}

@MainActor
package protocol WeatherLocationProviding: AnyObject {
    func request(allowPrompt: Bool, _ completion: @escaping (Result<WeatherCoordinates, WeatherLocationFailure>) -> Void)
    func cancel()
}

/// The manager is created only when enabled weather has an eligible automatic-location demand.
@MainActor
package final class NativeWeatherLocationProvider: NSObject, WeatherLocationProviding, CLLocationManagerDelegate {
    private var manager: CLLocationManager?
    private var completion: ((Result<WeatherCoordinates, WeatherLocationFailure>) -> Void)?
    private var requestedLocation = false
    private var requestedAuthorization = false
    private var allowPrompt = false
    private var fixTimeout: Task<Void, Never>?

    package func request(
        allowPrompt: Bool, _ completion: @escaping (Result<WeatherCoordinates, WeatherLocationFailure>) -> Void
    ) {
        cancel()
        self.allowPrompt = allowPrompt
        self.completion = completion
        let manager = CLLocationManager()
        self.manager = manager
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        manager.delegate = self
        handleAuthorization()
    }

    package func cancel() {
        completion = nil
        fixTimeout?.cancel()
        fixTimeout = nil
        manager?.stopUpdatingLocation()
        manager?.delegate = nil
        manager = nil
        requestedLocation = false
        requestedAuthorization = false
        allowPrompt = false
    }

    private func handleAuthorization() {
        guard completion != nil, let manager else { return }
        switch manager.authorizationStatus {
        case .notDetermined:
            guard allowPrompt else {
                finish(.failure(.permissionRequired))
                return
            }
            guard !requestedAuthorization else { return }
            requestedAuthorization = true
            manager.requestWhenInUseAuthorization()
        case .restricted, .denied: finish(.failure(.denied))
        case .authorizedAlways, .authorizedWhenInUse:
            guard !requestedLocation else { return }
            requestedLocation = true
            manager.requestLocation()
            let identity = ObjectIdentifier(manager)
            fixTimeout = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 20_000_000_000) } catch { return }
                guard let self, let current = self.manager, ObjectIdentifier(current) == identity else { return }
                self.finish(.failure(.unavailable))
            }
        @unknown default: finish(.failure(.unavailable))
        }
    }

    private func finish(_ result: Result<WeatherCoordinates, WeatherLocationFailure>) {
        let callback = completion
        cancel()
        callback?(result)
    }

    nonisolated package func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let identity = ObjectIdentifier(manager)
        Task { @MainActor [weak self] in
            guard let self, let current = self.manager, ObjectIdentifier(current) == identity else { return }
            self.handleAuthorization()
        }
    }

    nonisolated package func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let identity = ObjectIdentifier(manager)
        let point = locations.last.flatMap { location -> WeatherCoordinates? in
            guard location.horizontalAccuracy >= 0,
                  abs(location.timestamp.timeIntervalSinceNow) <= 600 else { return nil }
            return WeatherCoordinates(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        }
        Task { @MainActor [weak self] in
            guard let self, let current = self.manager, ObjectIdentifier(current) == identity else { return }
            if let point { self.finish(.success(point)) } else { self.finish(.failure(.unavailable)) }
        }
    }

    nonisolated package func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let identity = ObjectIdentifier(manager)
        let denied = (error as NSError).code == CLError.denied.rawValue
        Task { @MainActor [weak self] in
            guard let self, let current = self.manager, ObjectIdentifier(current) == identity else { return }
            self.finish(.failure(denied ? .denied : .unavailable))
        }
    }
}
