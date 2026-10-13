import Combine
import CountdownCore
import CountdownManagerUI
import Foundation

private actor WeatherRequestRecorder {
    private(set) var requests: [WeatherCoordinates] = []
    private(set) var cancelled = Set<Int>()
    private var pending: [Int: CheckedContinuation<[String: DailyWeatherForecast], Error>] = [:]

    func fetch(_ coordinates: WeatherCoordinates) async throws -> [String: DailyWeatherForecast] {
        let index = requests.count
        requests.append(coordinates)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[index] = continuation
            }
        } onCancel: {
            Task { await self.recordCancellation(index) }
        }
    }

    private func recordCancellation(_ index: Int) { cancelled.insert(index) }

    func complete(_ index: Int, result: Result<[String: DailyWeatherForecast], Error>) {
        precondition(pending[index] != nil)
        pending.removeValue(forKey: index)?.resume(with: result)
    }
}

@MainActor
private final class WeatherLocationRecorder: WeatherLocationProviding {
    private(set) var callbacks: [(Result<WeatherCoordinates, WeatherLocationFailure>) -> Void] = []
    private(set) var cancellationCount = 0
    private(set) var promptPermissions: [Bool] = []

    func request(allowPrompt: Bool, _ completion: @escaping (Result<WeatherCoordinates, WeatherLocationFailure>) -> Void) {
        promptPermissions.append(allowPrompt)
        callbacks.append(completion)
    }

    func cancel() { cancellationCount += 1 }
}

@MainActor
private final class WeatherScheduleRecorder {
    struct Entry {
        let delay: TimeInterval
        let action: @MainActor () -> Void
        var cancelled = false
    }

    private(set) var entries: [Entry] = []

    func schedule(after delay: TimeInterval, action: @escaping @MainActor () -> Void) -> () -> Void {
        let index = entries.count
        entries.append(Entry(delay: delay, action: action))
        return { [weak self] in self?.entries[index].cancelled = true }
    }

    // Deliberately also deliver cancelled callbacks, as a scheduler may already have queued one.
    func fire(_ index: Int) { entries[index].action() }
}

@MainActor
private func waitForWeather(_ condition: () async -> Bool) async {
    for _ in 0..<1_000 {
        if await condition() { return }
        await Task.yield()
    }
    preconditionFailure("Weather fixture did not reach its expected state")
}

private func requireWeatherRequests(_ provider: WeatherRequestRecorder, count: Int) async {
    let actual = await provider.requests.count
    precondition(actual == count)
}

@MainActor
func testWeatherLifecycle() async throws {
    try testWeatherDecoding()
    let suite = "local.countdownmanager.weather-checks.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    var clock = Date(timeIntervalSince1970: 1_792_000_000)
    let today = Day(clock)
    let tomorrow = Day(Day.calendar.date(byAdding: .day, value: 1, to: today.date())!)
    let distant = Day(Day.calendar.date(byAdding: .day, value: 16, to: today.date())!)
    let yesterday = Day(Day.calendar.date(byAdding: .day, value: -1, to: today.date())!)
    var first = Countdown(title: "Weather today", date: today, emoji: "")
    first.showsWeather = true
    var second = Countdown(title: "Weather tomorrow", date: tomorrow, emoji: "")
    second.showsWeather = true
    var far = Countdown(title: "Outside forecast range", date: distant, emoji: "")
    far.showsWeather = true
    var expired = Countdown(title: "Expired", date: yesterday, emoji: "")
    expired.showsWeather = true
    let plain = Countdown(title: "No weather", date: today, emoji: "")
    let sunny = DailyWeatherForecast(weatherCode: 0, maximumTemperature: 14.2)!
    let rain = DailyWeatherForecast(weatherCode: 63, maximumTemperature: -4.7)!
    let provider = WeatherRequestRecorder()
    let location = WeatherLocationRecorder()
    let controller = WeatherController(
        defaults: defaults, provider: { try await provider.fetch($0) },
        locationProvider: location, now: { clock }
    )
    defer { controller.shutdown() }
    precondition(!controller.enabled && controller.location == .automatic)
    controller.updateEvents([first, second])
    controller.selectLocation(.city(.moscow))
    precondition(location.callbacks.isEmpty)
    await requireWeatherRequests(provider, count: 0)
    precondition(controller.forecast(for: today) == nil)

    // Cancelling before the task begins must not start a provider while weather is off.
    controller.setEnabled(true)
    controller.setEnabled(false)
    await requireWeatherRequests(provider, count: 0)

    controller.setEnabled(true)
    await waitForWeather { await provider.requests.count == 1 }
    controller.updateEvents([first, first, second, far, expired, plain])
    await requireWeatherRequests(provider, count: 1)
    await provider.complete(0, result: .success([
        weatherDayKey(today): sunny, weatherDayKey(tomorrow): rain, weatherDayKey(distant): sunny,
    ]))
    await waitForWeather { controller.forecast(for: today) == sunny }
    precondition(controller.forecast(for: tomorrow) == rain)
    precondition(controller.forecast(for: distant) == nil && controller.forecast(for: yesterday) == nil)
    precondition(sunny.temperatureLabel == "+14°" && rain.temperatureLabel == "−5°")
    precondition(rain.accessibilityDescription.contains("Максимальная температура за день"))
    controller.updateEvents([second])
    precondition(controller.forecast(for: today) == nil && controller.forecast(for: tomorrow) == rain)
    await requireWeatherRequests(provider, count: 1)

    controller.selectLocation(.city(.kazan))
    precondition(controller.forecast(for: tomorrow) == nil)
    await waitForWeather { await provider.requests.count == 2 }
    await provider.complete(1, result: .success([weatherDayKey(tomorrow): sunny]))
    await waitForWeather { controller.forecast(for: tomorrow) == sunny }
    controller.selectLocation(.city(.moscow))
    precondition(controller.forecast(for: tomorrow) == rain)
    await requireWeatherRequests(provider, count: 2)

    controller.selectLocation(.city(.grozny))
    await waitForWeather { await provider.requests.count == 3 }
    controller.setEnabled(false)
    await waitForWeather { await provider.cancelled.contains(2) }
    await provider.complete(2, result: .success([weatherDayKey(tomorrow): sunny]))
    await Task.yield()
    precondition(controller.forecast(for: tomorrow) == nil && controller.settingsStatus == nil)
    controller.selectLocation(.city(.moscow))
    await requireWeatherRequests(provider, count: 3)
    precondition(location.callbacks.isEmpty)
    controller.setEnabled(true)
    precondition(controller.forecast(for: tomorrow) == rain)

    // A cancelled, non-cooperating provider cannot publish into the replacement location.
    controller.selectLocation(.city(.grozny))
    await waitForWeather { await provider.requests.count == 4 }
    controller.selectLocation(.city(.kazan))
    await waitForWeather { await provider.cancelled.contains(3) }
    await provider.complete(3, result: .success([weatherDayKey(tomorrow): rain]))
    await Task.yield()
    precondition(controller.forecast(for: tomorrow) == sunny)

    controller.selectLocation(.city(.samara))
    await waitForWeather { await provider.requests.count == 5 }
    await provider.complete(4, result: .failure(WeatherProviderFailure.response))
    await waitForWeather { controller.settingsStatus?.contains("Попробуем позже") == true }
    controller.updateEvents([first, second])
    await requireWeatherRequests(provider, count: 5)
    precondition(controller.forecast(for: today) == nil)
    clock = clock.addingTimeInterval(301)
    controller.refresh()
    await waitForWeather { await provider.requests.count == 6 }
    await provider.complete(5, result: .success([weatherDayKey(today): sunny]))
    await waitForWeather { controller.forecast(for: today) == sunny }
    clock = clock.addingTimeInterval(1_801)
    precondition(controller.forecast(for: today) == nil)

    // No eligible events means no location request, including after enabling automatic mode.
    controller.updateEvents([plain, far, expired])
    controller.selectLocation(.automatic)
    precondition(location.callbacks.isEmpty)
    controller.updateEvents([first])
    precondition(location.callbacks.count == 1)
    precondition(location.promptPermissions == [false])
    controller.setEnabled(false)
    location.callbacks[0](.success(WeatherCity.moscow.coordinates))
    precondition(controller.forecast(for: today) == nil)
    await requireWeatherRequests(provider, count: 6)
    controller.setEnabled(true)
    precondition(location.callbacks.count == 2)
    precondition(location.promptPermissions == [false, true])
    controller.selectLocation(.city(.samara))
    location.callbacks[1](.success(WeatherCity.kazan.coordinates))
    await waitForWeather { await provider.requests.count == 7 }
    let lastCoordinates = await provider.requests.last
    precondition(lastCoordinates == WeatherCity.samara.coordinates)
    await provider.complete(6, result: .success([weatherDayKey(today): sunny]))
    await waitForWeather { controller.forecast(for: today) == sunny }

    controller.setEnabled(false)
    let reopened = WeatherController(
        defaults: defaults, provider: { try await provider.fetch($0) },
        locationProvider: location, allowLocationRequests: false, now: { clock }
    )
    precondition(!reopened.enabled && reopened.location == .city(.samara))
    reopened.selectLocation(.automatic)
    reopened.updateEvents([first])
    reopened.setEnabled(true)
    precondition(reopened.settingsStatus != nil && location.callbacks.count == 2)
    await requireWeatherRequests(provider, count: 7)
    reopened.shutdown()
    reopened.updateEvents([first])
    precondition(reopened.forecast(for: today) == nil)
    let restoredLocation = WeatherLocationRecorder()
    let restored = WeatherController(
        defaults: defaults, provider: { try await provider.fetch($0) },
        locationProvider: restoredLocation, now: { clock }
    )
    precondition(restored.enabled && restored.location == .automatic)
    restored.updateEvents([first])
    precondition(restoredLocation.promptPermissions == [false])
    restoredLocation.callbacks[0](.failure(.permissionRequired))
    precondition(restored.settingsStatus?.contains("включите погоду") == true)
    restored.updateEvents([first, second])
    precondition(restoredLocation.callbacks.count == 1)
    restored.selectLocation(.automatic)
    precondition(restoredLocation.promptPermissions == [false, true])
    restoredLocation.callbacks[1](.failure(.denied))
    precondition(restored.settingsStatus?.contains("вручную") == true)
    restored.shutdown()
    testWeatherSavedPermissionAction()
    try await testWeatherCacheBound()
    await testWeatherScheduledLifetime()
}

@MainActor
private func testWeatherScheduledLifetime() async {
    let suite = "local.countdownmanager.weather-schedule-checks.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    var clock = Date(timeIntervalSince1970: 1_792_000_000)
    let event = Countdown(title: "Stationary weather", date: Day(clock), emoji: "", showsWeather: true)
    let sunny = DailyWeatherForecast(weatherCode: 0, maximumTemperature: 14)!
    let rain = DailyWeatherForecast(weatherCode: 63, maximumTemperature: 10)!
    let provider = WeatherRequestRecorder()
    let scheduler = WeatherScheduleRecorder()
    let controller = WeatherController(
        defaults: defaults, provider: { try await provider.fetch($0) },
        locationProvider: WeatherLocationRecorder(), now: { clock },
        scheduler: { scheduler.schedule(after: $0, action: $1) }
    )
    defer { controller.shutdown() }
    var publications = 0
    let observation = controller.objectWillChange.sink { publications += 1 }
    defer { observation.cancel() }
    controller.selectLocation(.city(.moscow))
    controller.updateEvents([event])
    controller.setEnabled(true)
    await waitForWeather { await provider.requests.count == 1 }
    await provider.complete(0, result: .success([weatherDayKey(event.date): sunny]))
    await waitForWeather { controller.forecast(for: event.date) == sunny }
    precondition(scheduler.entries.count == 1 && scheduler.entries[0].delay == 1_800)

    // No Store publication or user action occurs: the one-shot expiry invalidates the badge itself.
    let beforeExpiry = publications
    clock = clock.addingTimeInterval(1_800)
    scheduler.fire(0)
    precondition(controller.forecast(for: event.date) == nil && publications > beforeExpiry)
    await waitForWeather { await provider.requests.count == 2 }
    await provider.complete(1, result: .success([weatherDayKey(event.date): rain]))
    await waitForWeather { controller.forecast(for: event.date) == rain }
    precondition(scheduler.entries.count == 2 && scheduler.entries[1].delay == 1_800)
    controller.refresh()
    precondition(scheduler.entries.count == 2, "A cache hit must reuse its existing one-shot")

    clock = clock.addingTimeInterval(1_800)
    scheduler.fire(1)
    await waitForWeather { await provider.requests.count == 3 }
    await provider.complete(2, result: .failure(WeatherProviderFailure.response))
    await waitForWeather { scheduler.entries.count == 3 }
    precondition(controller.forecast(for: event.date) == nil && scheduler.entries[2].delay == 300)
    controller.updateEvents([event])
    precondition(scheduler.entries.count == 3)
    clock = clock.addingTimeInterval(300)
    scheduler.fire(2)
    await waitForWeather { await provider.requests.count == 4 }
    await provider.complete(3, result: .success([weatherDayKey(event.date): sunny]))
    await waitForWeather { controller.forecast(for: event.date) == sunny }

    controller.setEnabled(false)
    precondition(scheduler.entries[3].cancelled)
    clock = clock.addingTimeInterval(1_800)
    let afterOff = publications
    scheduler.fire(3)
    scheduler.fire(2)
    await requireWeatherRequests(provider, count: 4)
    precondition(controller.forecast(for: event.date) == nil && publications == afterOff)

    controller.setEnabled(true)
    await waitForWeather { await provider.requests.count == 5 }
    await provider.complete(4, result: .success([weatherDayKey(event.date): rain]))
    await waitForWeather { controller.forecast(for: event.date) == rain }
    controller.selectLocation(.city(.kazan))
    precondition(scheduler.entries[4].cancelled)
    scheduler.fire(4)
    await waitForWeather { await provider.requests.count == 6 }
    await provider.complete(5, result: .success([weatherDayKey(event.date): sunny]))
    await waitForWeather { controller.forecast(for: event.date) == sunny }
    controller.shutdown()
    precondition(scheduler.entries[5].cancelled)
    scheduler.fire(5)
    await requireWeatherRequests(provider, count: 6)
    precondition(controller.forecast(for: event.date) == nil)
}

@MainActor
private func testWeatherSavedPermissionAction() {
    let suite = "local.countdownmanager.weather-save-checks.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let clock = Date(timeIntervalSince1970: 1_792_000_000)
    let event = Countdown(title: "Saved weather day", date: Day(clock), emoji: "", showsWeather: true)
    let location = WeatherLocationRecorder()
    let controller = WeatherController(
        defaults: defaults, provider: { _ in preconditionFailure("Permission-only fixture must not fetch") },
        locationProvider: location, now: { clock }
    )
    defer { controller.shutdown() }
    controller.setEnabled(true)
    precondition(location.promptPermissions.isEmpty, "Empty demand must not request location")
    controller.updateEvents([event])
    precondition(location.promptPermissions == [false])
    location.callbacks[0](.failure(.permissionRequired))
    controller.didSaveEvent(event, activeEvents: [event])
    precondition(location.promptPermissions == [false, true], "Save bypasses passive permission backoff")
    location.callbacks[1](.failure(.permissionRequired))

    let restoredLocation = WeatherLocationRecorder()
    let restored = WeatherController(
        defaults: defaults, provider: { _ in preconditionFailure("Permission-only fixture must not fetch") },
        locationProvider: restoredLocation, now: { clock }
    )
    defer { restored.shutdown() }
    restored.updateEvents([event])
    precondition(restoredLocation.promptPermissions == [false], "Restored enabled weather never prompts")
    restored.didSaveEvent(event, activeEvents: [event])
    precondition(restoredLocation.promptPermissions == [false, true], "Save replaces a pending passive check")
    restoredLocation.callbacks[0](.success(WeatherCity.moscow.coordinates))
    precondition(restored.forecast(for: event.date) == nil, "Superseded location must be ignored")
    restoredLocation.callbacks[1](.failure(.denied))
    restored.setEnabled(false)
    restored.didSaveEvent(event, activeEvents: [event])
    precondition(restoredLocation.promptPermissions == [false, true], "Saving cannot enable global weather")
}

@MainActor
private func testWeatherCacheBound() async throws {
    let suite = "local.countdownmanager.weather-cache-checks.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    var clock = Date(timeIntervalSince1970: 1_792_000_000)
    var event = Countdown(title: "Cache fixture", date: Day(clock), emoji: "")
    event.showsWeather = true
    let provider = WeatherRequestRecorder()
    let location = WeatherLocationRecorder()
    let controller = WeatherController(
        defaults: defaults, provider: { try await provider.fetch($0) },
        locationProvider: location, now: { clock }
    )
    defer { controller.shutdown() }
    controller.updateEvents([event])
    controller.selectLocation(.city(.moscow))
    controller.setEnabled(true)
    let cities: [WeatherCity] = [.moscow, .kazan, .grozny, .samara, .krasnodar]
    for (index, city) in cities.enumerated() {
        controller.selectLocation(.city(city))
        await waitForWeather { await provider.requests.count == index + 1 }
        await provider.complete(index, result: .success([
            weatherDayKey(event.date): DailyWeatherForecast(weatherCode: 0, maximumTemperature: Double(index))!,
        ]))
        await waitForWeather { controller.forecast(for: event.date)?.maximumTemperature == Double(index) }
        clock = clock.addingTimeInterval(1)
    }
    controller.selectLocation(.city(.moscow))
    await waitForWeather { await provider.requests.count == 6 }
    await provider.complete(5, result: .success([:]))
    await waitForWeather { controller.settingsStatus?.contains("выбранных дат") == true }
    precondition(controller.forecast(for: event.date) == nil)
}

private func testWeatherDecoding() throws {
    precondition(WeatherCity.allCases.count == 10)
    precondition(WeatherCoordinates(latitude: .nan, longitude: 0) == nil)
    precondition(WeatherCoordinates(latitude: 91, longitude: 0) == nil)
    let coordinates = WeatherCoordinates(latitude: 55.7558, longitude: 37.6173)!
    precondition(coordinates.latitude == 55.76 && coordinates.longitude == 37.62)
    let request = try OpenMeteoWeatherProvider.makeRequest(coordinates)
    let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
    precondition(query.contains { $0.name == "forecast_days" && $0.value == "16" })
    precondition(query.contains { $0.name == "timezone" && $0.value == "auto" })
    precondition(query.contains { $0.name == "daily" && $0.value == "weather_code,temperature_2m_max" })
    precondition(request.url?.scheme == "https")
    let data = Data("""
        {"daily":{"time":["2026-10-13","2026-10-14","2026-10-15"],
        "weather_code":[0,999,63],"temperature_2m_max":[14.4,20,null]}}
        """.utf8)
    let decoded = try OpenMeteoWeatherProvider.decode(data)
    precondition(decoded.count == 1 && decoded["2026-10-13"]?.temperatureLabel == "+14°")
    precondition(DailyWeatherForecast(weatherCode: 0, maximumTemperature: .infinity) == nil)
    precondition(DailyWeatherForecast(weatherCode: 0, maximumTemperature: 1_000) == nil)
    precondition(DailyWeatherForecast(weatherCode: 999, maximumTemperature: 10) == nil)
    precondition(DailyWeatherForecast(weatherCode: 97, maximumTemperature: 10)?.conditionDescription == "Гроза")
    for code in [56, 57, 66, 67] {
        precondition(DailyWeatherForecast(weatherCode: code, maximumTemperature: 1)?.symbolName == "cloud.sleet.fill")
    }
    precondition(DailyWeatherForecast(weatherCode: 3, maximumTemperature: -0.2)?.temperatureLabel == "0°")
    for json in [
        "{\"daily\":{\"time\":[\"2026-02-30\"],\"weather_code\":[0],\"temperature_2m_max\":[10]}}",
        "{\"daily\":{\"time\":[\"2026-10-13\"],\"weather_code\":[],\"temperature_2m_max\":[10]}}",
        "{\"daily\":{\"time\":[\"2026-10-13\",\"2026-10-13\"],\"weather_code\":[0,0],\"temperature_2m_max\":[10,10]}}",
    ] {
        do {
            _ = try OpenMeteoWeatherProvider.decode(Data(json.utf8))
            preconditionFailure("Invalid weather payload was accepted")
        } catch { precondition(!(error is CancellationError)) }
    }
    let excessive = try JSONSerialization.data(withJSONObject: ["daily": [
        "time": Array(repeating: "2026-10-13", count: 17),
        "weather_code": Array(repeating: 0, count: 17),
        "temperature_2m_max": Array(repeating: 10, count: 17),
    ]])
    for invalid in [excessive, Data(repeating: 32, count: 128_001)] {
        do {
            _ = try OpenMeteoWeatherProvider.decode(invalid)
            preconditionFailure("Unbounded weather payload was accepted")
        } catch { precondition(!(error is CancellationError)) }
    }
}
