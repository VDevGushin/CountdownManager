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
package typealias WeatherConsensusComputation = @Sendable (
    [WeatherSource: WeatherSourceBatch], WeatherQuery, Set<String>
) async throws -> [String: WeatherConsensus]
package typealias WeatherRefreshScheduler = @MainActor (
    TimeInterval, @escaping @MainActor () -> Void
) -> (() -> Void)

@MainActor
private func scheduleWeatherRefresh(after delay: TimeInterval, action: @escaping @MainActor () -> Void) -> () -> Void {
    let task = Task { @MainActor in
        do { try await Task.sleep(for: .seconds(min(delay, 86_400))) } catch { return }
        guard !Task.isCancelled else { return }
        action()
    }
    return { task.cancel() }
}

package enum WeatherProviderFailure: Error {
    case response, invalidData
}

/// One source batch per area serves every eligible day; providers fail independently.
@MainActor
package final class WeatherController: ObservableObject {
    @Published package private(set) var enabled: Bool
    @Published package private(set) var location: WeatherLocationSelection
    @Published package private(set) var settingsStatus: String?
    @Published private var forecasts: [String: DailyWeatherForecast] = [:]

    private let defaults: UserDefaults
    private let provider: WeatherSourceProvider
    private let computeConsensus: WeatherConsensusComputation
    private let sources: [WeatherSource]
    private let locationProvider: any WeatherLocationProviding
    private let allowLocationRequests: Bool
    private let now: () -> Date
    private let schedule: WeatherRefreshScheduler
    private var demand: Set<String> = []
    private var coordinates: WeatherCoordinates?
    private var coordinateDate: Date?
    private var cache: [String: AreaCache] = [:]
    private var fetchTask: Task<Void, Never>?
    private var computationTask: Task<Void, Never>?
    private var computationRevision = 0
    private var computationInput: ComputationInput?
    private var activeKey: String?
    private var activeQuery: WeatherQuery?
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

    private struct SourceCache {
        var batch: WeatherSourceBatch?
        var freshUntil: Date
        var nextRequest: Date
        var failed: Bool
    }

    private struct AreaCache {
        var updatedAt: Date
        var entries: [WeatherSource: SourceCache]
    }

    private struct SourceOutcome: Sendable {
        let source: WeatherSource
        let result: Result<WeatherSourceBatch, Error>
    }

    private struct ComputationInput: Equatable, Sendable {
        let key: String
        let query: WeatherQuery
        let demand: Set<String>
        let batches: [WeatherSource: WeatherSourceBatch]
        let expiry: Date?
    }

    package init(
        defaults: UserDefaults,
        provider legacyProvider: WeatherForecastProvider? = nil,
        sourceProvider: WeatherSourceProvider? = nil,
        sources: [WeatherSource] = WeatherSource.allCases,
        locationProvider: (any WeatherLocationProviding)? = nil,
        allowLocationRequests: Bool = true,
        now: @escaping () -> Date = Date.init,
        scheduler: WeatherRefreshScheduler? = nil,
        consensusComputation: WeatherConsensusComputation? = nil
    ) {
        self.defaults = defaults
        computeConsensus = consensusComputation ?? { try await WeatherNormalizer.aggregateDemanded($0, query: $1, demandedDayKeys: $2) }
        if let legacyProvider {
            self.sources = [.openMeteo]
            self.provider = { _, query, _ in
                let raw = try await legacyProvider(query.coordinates)
                var days: [String: WeatherDailySample] = [:]
                for (key, value) in raw {
                    guard let period = query.interval(for: key), let condition = WeatherCategory(weatherCode: value.weatherCode) else { continue }
                    days[key] = WeatherDailySample(dayKey: key, period: period,
                                                  maximumTemperature: value.maximumTemperature, condition: condition)
                }
                return WeatherSourceBatch(forecasts: days)
            }
        } else {
            self.sources = WeatherSource.allCases.filter { sources.contains($0) }
            self.provider = sourceProvider ?? { try await WeatherTransport.fetch($0, query: $1, lastModified: $2) }
        }
        self.locationProvider = locationProvider ?? NativeWeatherLocationProvider()
        self.allowLocationRequests = allowLocationRequests
        self.now = now
        self.schedule = scheduler ?? { scheduleWeatherRefresh(after: $0, action: $1) }
        enabled = defaults.bool(forKey: Self.enabledKey)
        location = WeatherLocationSelection(storedValue: defaults.string(forKey: Self.locationKey))
    }

    package var locationTitle: String { location.title }

    private var localCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = location.timeZone
        return calendar
    }

    private var localToday: Day { Day(now(), calendar: localCalendar) }

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

    package func updateEvents(_ events: [Countdown]) { updateEvents(events, allowLocationPrompt: false) }

    package func didSaveEvent(_ event: Countdown, activeEvents: [Countdown]) {
        let eligible = event.showsWeather && (0..<16).contains(event.date.days(from: localToday, calendar: localCalendar))
        if enabled, location == .automatic, eligible {
            if locationIsPending { invalidateRequests() }
            locationAttemptDate = nil
        }
        updateEvents(activeEvents, allowLocationPrompt: eligible)
    }

    private func updateEvents(_ events: [Countdown], allowLocationPrompt: Bool) {
        let updated = Set(events.filter {
            $0.showsWeather && (0..<16).contains($0.date.days(from: localToday, calendar: localCalendar))
        }.map { weatherDayKey($0.date) })
        if updated.isEmpty, !demand.isEmpty { invalidateRequests() }
        demand = updated
        refresh(allowLocationPrompt: allowLocationPrompt)
    }

    package func forecast(for day: Day) -> DailyWeatherForecast? {
        guard enabled, !stopped, demand.contains(weatherDayKey(day)),
              (0..<16).contains(day.days(from: localToday, calendar: localCalendar)),
              let forecastExpiry, forecastExpiry > now() else { return nil }
        return forecasts[weatherDayKey(day)]
    }

    package func refresh() { refresh(allowLocationPrompt: false) }

    private func refresh(allowLocationPrompt: Bool) {
        if enabled, !stopped, !demand.isEmpty {
            demand.formIntersection(availableDayKeys())
            if demand.isEmpty { invalidateRequests() }
        }
        guard enabled, !stopped, !demand.isEmpty, !sources.isEmpty else {
            settingsStatus = nil
            return
        }
        if let key = activeKey, let query = activeQuery { publishFreshForecasts(key: key, query: query) }
        switch location {
        case let .city(city): loadForecasts(at: city.coordinates)
        case .automatic:
            if let coordinates, let coordinateDate, now().timeIntervalSince(coordinateDate) < Self.cacheLifetime {
                loadForecasts(at: coordinates)
            } else { requestLocation(allowPrompt: allowLocationPrompt) }
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
        cancelComputation()
        activeKey = nil
        activeQuery = nil
        locationProvider.cancel()
        if locationIsPending { locationAttemptDate = nil }
        locationIsPending = false
        forecasts = [:]
        forecastExpiry = nil
    }

    private func requestLocation(allowPrompt: Bool) {
        guard allowLocationRequests else {
            settingsStatus = "Для прогноза выберите город вручную."
            return
        }
        guard !locationIsPending else { return }
        if let locationAttemptDate, now().timeIntervalSince(locationAttemptDate) < Self.failureBackoff {
            scheduleRefresh(at: locationAttemptDate.addingTimeInterval(Self.failureBackoff))
            return
        }
        locationIsPending = true
        locationAttemptDate = now()
        settingsStatus = "Определяем местоположение…"
        let expectedGeneration = generation
        locationProvider.request(allowPrompt: allowPrompt) { [weak self] result in
            guard let self, self.generation == expectedGeneration, self.enabled, !self.stopped, !self.demand.isEmpty else { return }
            self.locationIsPending = false
            switch result {
            case let .success(coordinates):
                self.coordinates = coordinates
                self.coordinateDate = self.now()
                self.loadForecasts(at: coordinates)
            case .failure(.permissionRequired):
                self.settingsStatus = "Для геолокации включите погоду или выберите «Автоматически» в настройках."
            case .failure:
                self.settingsStatus = "Местоположение недоступно. Выберите город вручную."
                self.scheduleRefresh(at: self.now().addingTimeInterval(Self.failureBackoff))
            }
        }
    }

    private func loadForecasts(at coordinates: WeatherCoordinates) {
        guard let query = WeatherQuery(coordinates: coordinates, timeZone: location.timeZone, startDay: localToday) else { return }
        let key = "\(coordinates.cacheIdentity)|\(query.timeZone.identifier)|\(weatherDayKey(query.startDay))"
        if activeKey != key {
            generation += 1
            fetchTask?.cancel()
            fetchTask = nil
            cancelComputation()
            forecasts = [:]
            forecastExpiry = nil
            cancelScheduledRefresh()
            activeKey = key
            activeQuery = query
        }
        publishFreshForecasts(key: key, query: query)
        guard fetchTask == nil else {
            scheduleNextRefresh(key: key)
            return
        }
        let requestedAt = now()
        let dueSources = sources.filter { (cache[key]?.entries[$0]?.nextRequest ?? .distantPast) <= requestedAt }
        guard !dueSources.isEmpty else {
            scheduleNextRefresh(key: key)
            return
        }
        if forecasts.isEmpty { settingsStatus = "Получаем прогноз…" }
        let expectedGeneration = generation
        let provider = provider
        let modifications = cache[key]?.entries.compactMapValues { $0.batch?.lastModified } ?? [:]
        fetchTask = Task { [weak self] in
            await withTaskGroup(of: SourceOutcome.self) { group in
                for source in dueSources {
                    let modified = modifications[source]
                    group.addTask {
                        do {
                            try Task.checkCancellation()
                            let result = try await provider(source, query, modified)
                            try Task.checkCancellation()
                            return SourceOutcome(source: source, result: .success(result))
                        } catch { return SourceOutcome(source: source, result: .failure(error)) }
                    }
                }
                for await outcome in group {
                    guard let self, !Task.isCancelled, self.generation == expectedGeneration,
                          self.enabled, !self.stopped, self.activeKey == key else {
                        group.cancelAll()
                        return
                    }
                    self.receive(outcome, key: key)
                    self.publishFreshForecasts(key: key, query: query)
                    self.scheduleNextRefresh(key: key)
                }
            }
            guard let self, !Task.isCancelled, self.generation == expectedGeneration, self.activeKey == key else { return }
            self.fetchTask = nil
            // A clock/expiry action can run after publication but before the task group drains.
            // Revisit a now-due source rather than losing that coalesced refresh.
            if self.sources.contains(where: { (self.cache[key]?.entries[$0]?.nextRequest ?? .distantPast) <= self.now() }) {
                self.refresh()
            } else { self.scheduleNextRefresh(key: key) }
        }
        scheduleNextRefresh(key: key)
    }

    private func receive(_ outcome: SourceOutcome, key: String) {
        let timestamp = now()
        var area = cache[key] ?? AreaCache(updatedAt: timestamp, entries: [:])
        let previous = area.entries[outcome.source]
        switch outcome.result {
        case let .success(batch):
            let fresh = validDate(batch.expiresAt) ?? timestamp.addingTimeInterval(Self.cacheLifetime)
            area.entries[outcome.source] = SourceCache(batch: batch, freshUntil: fresh,
                                                       nextRequest: max(timestamp.addingTimeInterval(Self.cacheLifetime), fresh), failed: false)
        case let .failure(error):
            if case let WeatherTransportFailure.notModified(expiresAt, lastModified) = error,
               var batch = previous?.batch {
                batch.expiresAt = expiresAt
                batch.lastModified = lastModified ?? batch.lastModified
                let fresh = validDate(expiresAt) ?? timestamp.addingTimeInterval(Self.cacheLifetime)
                area.entries[outcome.source] = SourceCache(batch: batch, freshUntil: fresh,
                                                           nextRequest: max(timestamp.addingTimeInterval(Self.cacheLifetime), fresh), failed: false)
            } else {
                var next = timestamp.addingTimeInterval(Self.failureBackoff)
                if case let WeatherTransportFailure.http(_, retryAfter) = error, let retryAfter = validDate(retryAfter) { next = max(next, retryAfter) }
                area.entries[outcome.source] = SourceCache(batch: previous?.batch,
                                                           freshUntil: previous?.freshUntil ?? .distantPast,
                                                           nextRequest: next, failed: true)
            }
        }
        area.updatedAt = timestamp
        cache[key] = area
        if cache.count > 4, let oldest = cache.min(by: { $0.value.updatedAt < $1.value.updatedAt })?.key { cache.removeValue(forKey: oldest) }
    }

    private func publishFreshForecasts(key: String, query: WeatherQuery) {
        let timestamp = now()
        let entries = cache[key]?.entries ?? [:]
        let fresh = entries.filter { $0.value.freshUntil > timestamp && $0.value.batch != nil }
        let input = ComputationInput(key: key, query: query, demand: demand,
                                     batches: fresh.compactMapValues(\.batch), expiry: fresh.values.map(\.freshUntil).min())
        // Withdraw expired/deleted values immediately, before any off-actor computation.
        if forecastExpiry.map({ $0 <= timestamp }) == true { forecasts = [:]; forecastExpiry = nil }
        forecasts = forecasts.filter { demand.contains($0.key) }
        if !forecasts.isEmpty { settingsStatus = nil }
        else if entries.values.contains(where: \.failed) { settingsStatus = "Прогноз недоступен. Попробуем позже." }
        else if !entries.isEmpty { settingsStatus = "Прогноз недоступен для выбранных дат." }
        guard computationInput != input else { return }
        cancelComputation()
        computationInput = input
        guard !input.batches.isEmpty, !input.demand.isEmpty else {
            forecasts = [:]
            forecastExpiry = nil
            return
        }
        let expectedRevision = computationRevision
        let expectedGeneration = generation
        let compute = computeConsensus
        computationTask = Task { [weak self] in
            do {
                let consensus = try await compute(input.batches, input.query, input.demand)
                guard let self, !Task.isCancelled, self.computationRevision == expectedRevision,
                      self.generation == expectedGeneration, self.computationInput == input,
                      self.activeKey == key, self.demand == input.demand, self.enabled, !self.stopped else { return }
                self.computationTask = nil
                guard let expiry = input.expiry, expiry > self.now() else {
                    self.publishFreshForecasts(key: key, query: query)
                    return
                }
                self.applyConsensus(consensus, input: input, expiry: expiry)
            } catch {
                guard let self, !Task.isCancelled, self.computationRevision == expectedRevision else { return }
                self.computationTask = nil
                self.settingsStatus = "Прогноз недоступен. Попробуем позже."
            }
        }
    }

    private func applyConsensus(_ consensus: [String: WeatherConsensus], input: ComputationInput, expiry: Date) {
        forecasts = consensus.reduce(into: [:]) { result, item in
            // The compact badge promises a daily maximum, so a remaining-hours maximum cannot replace it.
            guard input.demand.contains(item.key), item.value.period == input.query.interval(for: item.key),
                  let forecast = DailyWeatherForecast(weatherCode: item.value.weatherCode, maximumTemperature: item.value.maximumTemperature) else { return }
            result[item.key] = forecast
        }
        forecastExpiry = expiry
        if !forecasts.isEmpty { settingsStatus = nil }
    }

    private func cancelComputation() {
        computationRevision += 1
        computationTask?.cancel()
        computationTask = nil
        computationInput = nil
    }

    private func validDate(_ date: Date?) -> Date? {
        date.flatMap { $0.timeIntervalSince1970.isFinite ? $0 : nil }
    }

    private func scheduleNextRefresh(key: String) {
        let timestamp = now()
        let entries = cache[key]?.entries.values
        let dates = entries?.flatMap { entry -> [Date] in
            var dates = [entry.nextRequest]
            if entry.batch != nil, entry.freshUntil > timestamp { dates.append(entry.freshUntil) }
            return dates
        } ?? []
        guard let date = dates.filter({ $0 > timestamp }).min() else { return }
        scheduleRefresh(at: date)
    }

    private func availableDayKeys() -> Set<String> {
        let coordinates = self.coordinates ?? WeatherCity.moscow.coordinates
        return Set(WeatherQuery(coordinates: coordinates, timeZone: location.timeZone, startDay: localToday)?.dayKeys ?? [])
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
            if self.now() < date { self.scheduleRefresh(at: date); return }
            self.refresh()
        }
    }
}
