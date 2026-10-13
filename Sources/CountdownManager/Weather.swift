import Combine
import CountdownCore
import Foundation

package func weatherDayKey(_ day: Day) -> String {
    String(format: "%04d-%02d-%02d", day.year, day.month, day.day)
}

package struct DailyWeatherForecast: Equatable, Sendable {
    package let weatherCode: Int
    package let maximumTemperature: Double

    package init?(weatherCode: Int, maximumTemperature: Double) {
        guard Self.knownCodes.contains(weatherCode), maximumTemperature.isFinite,
              (-100...70).contains(maximumTemperature) else { return nil }
        self.weatherCode = weatherCode
        self.maximumTemperature = maximumTemperature
    }

    private static let knownCodes: Set<Int> = [0, 1, 2, 3, 45, 48, 51, 53, 55, 56, 57,
                                              61, 63, 65, 66, 67, 71, 73, 75, 77, 80, 81, 82,
                                              85, 86, 95, 96, 97, 99]

    package var symbolName: String {
        switch weatherCode {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55: return "cloud.drizzle.fill"
        case 56, 57, 66, 67: return "cloud.sleet.fill"
        case 61, 63, 65, 80, 81, 82: return "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        default: return "cloud.bolt.rain.fill"
        }
    }

    package var conditionDescription: String {
        switch weatherCode {
        case 0: return "Ясно"
        case 1, 2: return "Переменная облачность"
        case 3: return "Пасмурно"
        case 45, 48: return "Туман"
        case 51, 53, 55: return "Морось"
        case 56, 57: return "Ледяная морось"
        case 61, 63, 65, 80, 81, 82: return "Дождь"
        case 66, 67: return "Ледяной дождь"
        case 71, 73, 75, 77, 85, 86: return "Снег"
        default: return "Гроза"
        }
    }

    package var temperatureLabel: String {
        let value = Int(maximumTemperature.rounded())
        if value > 0 { return "+\(value)°" }
        if value < 0 { return "−\(abs(value))°" }
        return "0°"
    }

    package var accessibilityDescription: String {
        "\(conditionDescription). Максимальная температура за день: \(temperatureLabel) Цельсия."
    }
}

package typealias WeatherForecastProvider = @Sendable (WeatherCoordinates) async throws -> [String: DailyWeatherForecast]
package typealias WeatherRefreshScheduler = @MainActor (
    TimeInterval, @escaping @MainActor () -> Void
) -> (() -> Void)

@MainActor
private func scheduleWeatherRefresh(after delay: TimeInterval, action: @escaping @MainActor () -> Void) -> () -> Void {
    let task = Task { @MainActor in
        do { try await Task.sleep(for: .seconds(delay)) } catch { return }
        guard !Task.isCancelled else { return }
        action()
    }
    return { task.cancel() }
}

package enum WeatherProviderFailure: Error {
    case response, invalidData
}

package enum OpenMeteoWeatherProvider {
    package static func fetch(_ coordinates: WeatherCoordinates) async throws -> [String: DailyWeatherForecast] {
        let request = try makeRequest(coordinates)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else {
            throw WeatherProviderFailure.response
        }
        return try decode(data)
    }

    package static func makeRequest(_ coordinates: WeatherCoordinates) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.open-meteo.com"
        components.path = "/v1/forecast"
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(coordinates.latitude)),
            URLQueryItem(name: "longitude", value: String(coordinates.longitude)),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max"),
            URLQueryItem(name: "temperature_unit", value: "celsius"),
            URLQueryItem(name: "forecast_days", value: "16"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]
        guard let url = components.url else { throw WeatherProviderFailure.invalidData }
        return URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
    }

    package static func decode(_ data: Data) throws -> [String: DailyWeatherForecast] {
        guard data.count <= 128_000 else { throw WeatherProviderFailure.invalidData }
        let response = try JSONDecoder().decode(Response.self, from: data)
        let daily = response.daily
        guard daily.time.count <= 16, daily.time.count == daily.weatherCode.count,
              daily.time.count == daily.maximumTemperature.count else { throw WeatherProviderFailure.invalidData }
        var forecasts: [String: DailyWeatherForecast] = [:]
        var seen = Set<String>()
        for index in daily.time.indices {
            let key = daily.time[index]
            guard validDayKey(key), seen.insert(key).inserted else { throw WeatherProviderFailure.invalidData }
            guard let code = daily.weatherCode[index], let temperature = daily.maximumTemperature[index],
                  let forecast = DailyWeatherForecast(weatherCode: code, maximumTemperature: temperature) else { continue }
            forecasts[key] = forecast
        }
        return forecasts
    }

    private static func validDayKey(_ key: String) -> Bool {
        guard key.count == 10 else { return false }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: key) else { return false }
        return formatter.string(from: date) == key
    }

    private struct Response: Decodable {
        let daily: Daily
        struct Daily: Decodable {
            let time: [String]
            let weatherCode: [Int?]
            let maximumTemperature: [Double?]
            enum CodingKeys: String, CodingKey {
                case time
                case weatherCode = "weather_code"
                case maximumTemperature = "temperature_2m_max"
            }
        }
    }
}

/// One bounded daily batch serves all weather-enabled events in the selected area.
@MainActor
package final class WeatherController: ObservableObject {
    @Published package private(set) var enabled: Bool
    @Published package private(set) var location: WeatherLocationSelection
    @Published package private(set) var settingsStatus: String?
    @Published package private(set) var locationHelp: String?
    @Published private var forecasts: [String: DailyWeatherForecast] = [:]

    private let defaults: UserDefaults
    private let provider: WeatherForecastProvider
    private let locationProvider: any WeatherLocationProviding
    private let allowLocationRequests: Bool
    private let now: () -> Date
    private let schedule: WeatherRefreshScheduler
    private var demand: Set<String> = []
    private var coordinates: WeatherCoordinates?
    private var coordinateDate: Date?
    private var cache: [String: CacheEntry] = [:]
    private var fetchTask: Task<Void, Never>?
    private var locationIsPending = false
    private var locationAttemptDate: Date?
    private var generation = 0
    private var forecastExpiry: Date?
    private var refreshCancellation: (() -> Void)?
    private var refreshDate: Date?
    private var refreshGeneration = 0
    private var stopped = false
    private static let cacheLifetime: TimeInterval = 1_800
    private static let failureBackoff: TimeInterval = 300
    private static let enabledKey = "weather.enabled"
    private static let locationKey = "weather.location"

    private struct CacheEntry {
        let date: Date
        let forecasts: [String: DailyWeatherForecast]
        let failed: Bool
    }

    package init(
        defaults: UserDefaults,
        provider: @escaping WeatherForecastProvider = { try await OpenMeteoWeatherProvider.fetch($0) },
        locationProvider: (any WeatherLocationProviding)? = nil,
        allowLocationRequests: Bool = true,
        now: @escaping () -> Date = Date.init,
        scheduler: WeatherRefreshScheduler? = nil
    ) {
        self.defaults = defaults
        self.provider = provider
        self.locationProvider = locationProvider ?? NativeWeatherLocationProvider()
        self.allowLocationRequests = allowLocationRequests
        self.now = now
        self.schedule = scheduler ?? { scheduleWeatherRefresh(after: $0, action: $1) }
        enabled = defaults.bool(forKey: Self.enabledKey)
        location = WeatherLocationSelection(storedValue: defaults.string(forKey: Self.locationKey))
    }

    package var locationTitle: String { location.title }

    package func setEnabled(_ enabled: Bool) {
        guard !stopped, self.enabled != enabled else { return }
        self.enabled = enabled
        defaults.set(enabled, forKey: Self.enabledKey)
        if enabled { locationAttemptDate = nil }
        invalidateRequests()
        refresh(allowLocationPrompt: enabled)
    }

    package func selectLocation(_ location: WeatherLocationSelection) {
        guard !stopped else { return }
        if self.location == location {
            if location == .automatic {
                locationAttemptDate = nil
                refresh(allowLocationPrompt: true)
            }
            return
        }
        self.location = location
        defaults.set(location.storedValue, forKey: Self.locationKey)
        coordinates = nil
        coordinateDate = nil
        locationAttemptDate = nil
        invalidateRequests()
        refresh(allowLocationPrompt: location == .automatic)
    }

    package func updateEvents(_ events: [Countdown]) {
        updateEvents(events, allowLocationPrompt: false)
    }

    package func didSaveEvent(_ event: Countdown, activeEvents: [Countdown]) {
        let eligible = event.showsWeather && (0..<16).contains(event.date.days(from: Day(now())))
        if enabled, location == .automatic, eligible {
            // A passive permission check must not block an explicit saved weather choice.
            if locationIsPending { invalidateRequests() }
            locationAttemptDate = nil
        }
        updateEvents(activeEvents, allowLocationPrompt: eligible)
    }

    private func updateEvents(_ events: [Countdown], allowLocationPrompt: Bool) {
        let today = Day(now())
        let updated = Set(events.filter { $0.showsWeather && (0..<16).contains($0.date.days(from: today)) }
            .map { weatherDayKey($0.date) })
        if updated.isEmpty, !demand.isEmpty { invalidateRequests() }
        demand = updated
        refresh(allowLocationPrompt: allowLocationPrompt)
    }

    package func forecast(for day: Day) -> DailyWeatherForecast? {
        guard enabled, !stopped, demand.contains(weatherDayKey(day)),
              (0..<16).contains(day.days(from: Day(now()))),
              let forecastExpiry, forecastExpiry > now() else { return nil }
        return forecasts[weatherDayKey(day)]
    }

    package func refresh() {
        refresh(allowLocationPrompt: false)
    }

    private func refresh(allowLocationPrompt: Bool) {
        if enabled, !stopped, !demand.isEmpty {
            demand.formIntersection(availableDayKeys())
            if demand.isEmpty { invalidateRequests() }
        }
        guard enabled, !stopped, !demand.isEmpty else {
            settingsStatus = nil
            locationHelp = nil
            return
        }
        switch location {
        case let .city(city): loadForecasts(at: city.coordinates)
        case .automatic:
            if let coordinates, let coordinateDate, now().timeIntervalSince(coordinateDate) < Self.cacheLifetime {
                loadForecasts(at: coordinates)
            } else {
                requestLocation(allowPrompt: allowLocationPrompt)
            }
        }
    }

    package func shutdown() {
        stopped = true
        invalidateRequests()
        settingsStatus = nil
    }

    private func invalidateRequests() {
        generation += 1
        cancelScheduledRefresh()
        fetchTask?.cancel()
        fetchTask = nil
        locationProvider.cancel()
        if locationIsPending { locationAttemptDate = nil }
        locationIsPending = false
        forecasts = [:]
        forecastExpiry = nil
        locationHelp = nil
    }

    private func requestLocation(allowPrompt: Bool) {
        guard allowLocationRequests else {
            settingsStatus = "Для прогноза выберите город вручную."
            locationHelp = settingsStatus
            return
        }
        guard !locationIsPending else { return }
        if let locationAttemptDate, now().timeIntervalSince(locationAttemptDate) < Self.failureBackoff { return }
        locationIsPending = true
        locationAttemptDate = now()
        settingsStatus = "Определяем местоположение…"
        let expectedGeneration = generation
        locationProvider.request(allowPrompt: allowPrompt) { [weak self] result in
            guard let self, self.generation == expectedGeneration, self.enabled,
                  !self.stopped, !self.demand.isEmpty else { return }
            self.locationIsPending = false
            switch result {
            case let .success(coordinates):
                self.locationHelp = nil
                self.coordinates = coordinates
                self.coordinateDate = self.now()
                self.loadForecasts(at: coordinates)
            case .failure(.permissionRequired):
                self.settingsStatus = "Для геолокации включите погоду или выберите «Автоматически» в настройках."
                self.locationHelp = self.settingsStatus
            case .failure:
                self.settingsStatus = "Местоположение недоступно. Выберите город вручную."
                self.locationHelp = self.settingsStatus
            }
        }
    }

    private func loadForecasts(at coordinates: WeatherCoordinates) {
        guard fetchTask == nil else { return }
        let identity = coordinates.cacheIdentity
        if let entry = cache[identity] {
            let lifetime = entry.failed ? Self.failureBackoff : Self.cacheLifetime
            if now().timeIntervalSince(entry.date) < lifetime {
                forecasts = entry.forecasts
                forecastExpiry = entry.failed ? nil : entry.date.addingTimeInterval(lifetime)
                if entry.failed {
                    settingsStatus = "Прогноз недоступен. Попробуем позже."
                } else {
                    settingsStatus = entry.forecasts.isEmpty ? "Прогноз недоступен для выбранных дат." : nil
                }
                scheduleRefresh(at: entry.date.addingTimeInterval(lifetime))
                return
            }
        }
        cancelScheduledRefresh()
        settingsStatus = "Получаем прогноз…"
        let expectedGeneration = generation
        let provider = provider
        fetchTask = Task { [weak self] in
            guard !Task.isCancelled else { return }
            do {
                let result = try await provider(coordinates)
                guard let self, !Task.isCancelled, self.generation == expectedGeneration,
                      self.enabled, !self.stopped, !self.demand.isEmpty else { return }
                let allowedKeys = self.availableDayKeys()
                let bounded = result.filter { allowedKeys.contains($0.key) }
                let receivedAt = self.now()
                self.storeCache(CacheEntry(date: receivedAt, forecasts: bounded, failed: false), identity: identity)
                self.forecasts = bounded
                self.forecastExpiry = receivedAt.addingTimeInterval(Self.cacheLifetime)
                self.settingsStatus = bounded.isEmpty ? "Прогноз недоступен для выбранных дат." : nil
                self.fetchTask = nil
                self.scheduleRefresh(at: receivedAt.addingTimeInterval(Self.cacheLifetime))
            } catch {
                guard let self, !Task.isCancelled, self.generation == expectedGeneration,
                      self.enabled, !self.stopped else { return }
                let failedAt = self.now()
                self.storeCache(CacheEntry(date: failedAt, forecasts: [:], failed: true), identity: identity)
                self.forecasts = [:]
                self.forecastExpiry = nil
                self.settingsStatus = "Прогноз недоступен. Попробуем позже."
                self.fetchTask = nil
                self.scheduleRefresh(at: failedAt.addingTimeInterval(Self.failureBackoff))
            }
        }
    }

    private func availableDayKeys() -> Set<String> {
        let today = Day(now())
        return Set((0..<16).compactMap { offset in
            Day.calendar.date(byAdding: .day, value: offset, to: today.date()).map { weatherDayKey(Day($0)) }
        })
    }

    private func cancelScheduledRefresh() {
        refreshGeneration += 1
        refreshCancellation?()
        refreshCancellation = nil
        refreshDate = nil
    }

    private func scheduleRefresh(at date: Date) {
        guard refreshDate != date else { return }
        cancelScheduledRefresh()
        let expectedGeneration = generation
        let expectedRefresh = refreshGeneration
        refreshDate = date
        refreshCancellation = schedule(max(0, date.timeIntervalSince(now()))) { [weak self] in
            guard let self, self.generation == expectedGeneration, self.refreshGeneration == expectedRefresh,
                  self.enabled, !self.stopped, !self.demand.isEmpty else { return }
            self.refreshCancellation = nil
            self.refreshDate = nil
            if self.now() < date {
                self.scheduleRefresh(at: date)
                return
            }
            self.forecasts = [:]
            self.forecastExpiry = nil
            self.refresh()
        }
    }

    private func storeCache(_ entry: CacheEntry, identity: String) {
        cache[identity] = entry
        if cache.count > 4, let oldest = cache.min(by: { $0.value.date < $1.value.date })?.key {
            cache.removeValue(forKey: oldest)
        }
    }
}
