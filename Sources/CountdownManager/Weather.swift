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
    private let provider: WeatherHTTPProvider
    private let computeConsensus: WeatherConsensusComputation
    private let sources: [WeatherSource]
    private let locationProvider: any WeatherLocationProviding
    private let allowLocationRequests: Bool
    private let now: () -> Date
    private let monotonicNow: () -> TimeInterval
    private let jitter: () -> Double
    private let lowPower: () -> Bool
    private let networkMonitor: (any WeatherNetworkMonitoring)?
    private var networkState = WeatherNetworkState()
    private var networkMonitoring = false
    private var networkGeneration = 0
    private var offlineSince: TimeInterval?
    private var recoveryDeadline: TimeInterval = 0
    private var sourceStates: [WeatherSource: WeatherRequestPolicy.SourceState] = [:]
    private var clockAnchor: (wall: Date, tick: TimeInterval)?
    private let schedule: WeatherRefreshScheduler
    private let diagnostics: WeatherDiagnostics
    private var lastPublication: String?
    private var lastLocationDiagnostic: String?
    private var lastSnapshot: String?
    private var demand: Set<String> = []
    private var coordinates: WeatherCoordinates?
    private var coordinateDate: TimeInterval?
    private var cache: [String: AreaCache] = [:]
    private var fetchTask: Task<Void, Never>?
    private var computationTask: Task<Void, Never>?
    private var computationRevision = 0
    private var computationInput: ComputationInput?
    private var activeKey: String?
    private var activeQuery: WeatherQuery?
    private var locationIsPending = false
    private var locationAttemptDate: TimeInterval?
    private var generation = 0
    private var forecastExpiry: TimeInterval?
    private var refreshCancellation: (() -> Void)?
    private var refreshDate: TimeInterval?
    private var refreshGeneration = 0
    private var stopped = false
    private static let cacheLifetime: TimeInterval = 1_800
    private static let failureBackoff: TimeInterval = 300
    private static let enabledKey = "weather.enabled"
    private static let locationKey = "weather.location"

    private struct SourceCache {
        var batch: WeatherSourceBatch?
        var freshUntil: TimeInterval
        var nextRequest: TimeInterval
        var forceUnconditional = false
        var lastFailure: WeatherRequestPolicy.Outcome?
        var rapidRetry = false
        var lastOutcomeTick: TimeInterval = 0
        var connectionFailure = false
        var failed: Bool
    }

    private struct AreaCache {
        var updatedAt: TimeInterval
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
        let expiry: TimeInterval?
    }

    package init(
        defaults: UserDefaults,
        provider legacyProvider: WeatherForecastProvider? = nil,
        sourceProvider: WeatherSourceProvider? = nil,
        sources: [WeatherSource] = WeatherSource.allCases,
        locationProvider: (any WeatherLocationProviding)? = nil,
        allowLocationRequests: Bool = true,
        now: @escaping () -> Date = Date.init,
        monotonicNow: @escaping () -> TimeInterval = WeatherRequestPolicy.continuousSeconds,
        jitter: @escaping () -> Double = { Double.random(in: 0...1) },
        scheduler: WeatherRefreshScheduler? = nil,
        consensusComputation: WeatherConsensusComputation? = nil,
        diagnostics: WeatherDiagnostics = WeatherDiagnostics(),
        httpProvider: WeatherHTTPProvider? = nil,
        networkMonitor: (any WeatherNetworkMonitoring)? = nil,
        lowPower: @escaping () -> Bool = { ProcessInfo.processInfo.isLowPowerModeEnabled }
    ) {
        self.defaults = defaults
        self.diagnostics = diagnostics
        self.monotonicNow = monotonicNow
        self.jitter = jitter
        self.lowPower = lowPower
        self.networkMonitor = networkMonitor ?? (legacyProvider == nil && sourceProvider == nil && httpProvider == nil
            ? NativeWeatherNetworkMonitor() : nil)
        clockAnchor = (now(), monotonicNow())
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
            if let sourceProvider {
                self.provider = { try await sourceProvider($0, $1, $2?.lastModified) }
            } else {
                self.provider = httpProvider ?? { try await WeatherTransport.fetch($0, query: $1, diagnostics: diagnostics, validators: $2) }
            }
        }
        self.locationProvider = locationProvider ?? NativeWeatherLocationProvider()
        self.allowLocationRequests = allowLocationRequests
        self.now = now
        self.schedule = scheduler ?? { scheduleWeatherRefresh(after: $0, action: $1) }
        enabled = defaults.bool(forKey: Self.enabledKey)
        location = WeatherLocationSelection(storedValue: defaults.string(forKey: Self.locationKey))
        recordState(reason: "init")
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
        recordState(reason: "enabled")
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
        recordState(reason: "location")
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
        let changed = demand != updated
        demand = updated
        if changed { recordState(reason: "demand") }
        recordPublication()
        refresh(allowLocationPrompt: allowLocationPrompt)
    }

    package func forecast(for day: Day) -> DailyWeatherForecast? {
        guard enabled, !stopped, demand.contains(weatherDayKey(day)),
              (0..<16).contains(day.days(from: localToday, calendar: localCalendar)),
              let forecastExpiry, forecastExpiry > monotonicNow(), clockIsConsistent else { return nil }
        return forecasts[weatherDayKey(day)]
    }

    package func refresh() { refresh(allowLocationPrompt: false) }

    /// Reads bounded technical fields without starting work or changing preferences.
    package func diagnosticSnapshotSummary() -> String {
        let timestamp = monotonicNow()
        let eligible = demand.intersection(availableDayKeys())
        let usable = enabled && !stopped && clockIsConsistent && forecastExpiry.map({ $0 > timestamp }) == true
            ? forecasts.keys.filter { eligible.contains($0) }.count : 0
        let entries = activeKey.flatMap { cache[$0]?.entries } ?? [:]
        let freshSources = clockIsConsistent ? entries.values.filter { $0.batch != nil && $0.freshUntil > timestamp }.count : 0
        let failedSources = entries.values.filter(\.failed).count
        let locationIsFresh = coordinates != nil && coordinateDate.map {
            timestamp - $0 < Self.cacheLifetime
        } == true
        let result: String
        if stopped { result = "stopped" }
        else if !enabled { result = "disabled" }
        else if eligible.isEmpty { result = "no_eligible_dates" }
        else if usable > 0 { result = "available" }
        else if locationIsPending { result = "location_pending" }
        else if fetchTask != nil || computationTask != nil { result = "loading" }
        else if location == .automatic && !locationIsFresh { result = "location_unavailable" }
        else { result = "no_usable_data" }
        let mode = location == .automatic ? "auto" : "manual"
        return "result=\(result) enabled=\(enabled) mode=\(mode) demanded=\(eligible.count) usable=\(usable) " +
            "request_pending=\(fetchTask != nil) location_pending=\(locationIsPending) " +
            "computation_pending=\(computationTask != nil) fresh_sources=\(freshSources) failed_sources=\(failedSources) " +
            "clock_consistent=\(clockIsConsistent)"
    }

    package func recordDiagnosticSnapshot(reason: WeatherDiagnosticSnapshotReason) {
        let fields = diagnosticSnapshotSummary()
        guard reason != .settled || lastSnapshot != fields else { return }
        lastSnapshot = fields
        diagnostics.emit("weather.snapshot reason=\(reason.rawValue) \(fields)")
    }

    private func refresh(allowLocationPrompt: Bool) {
        defer { recordDiagnosticSnapshot(reason: .settled) }
        observeClock()
        updateNetworkMonitoring()
        if enabled, !stopped, !demand.isEmpty {
            let previousDemand = demand
            demand.formIntersection(availableDayKeys())
            if previousDemand != demand {
                recordState(reason: "demand")
                recordPublication()
            }
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
            if let coordinates, let coordinateDate, monotonicNow() - coordinateDate < Self.cacheLifetime {
                loadForecasts(at: coordinates)
            } else { requestLocation(allowPrompt: allowLocationPrompt) }
        }
    }

    package func shutdown() {
        stopped = true
        recordState(reason: "shutdown")
        invalidateRequests()
        settingsStatus = nil
        recordDiagnosticSnapshot(reason: .settled)
    }

    private func invalidateRequests() {
        generation += 1
        cancelScheduledRefresh()
        fetchTask?.cancel()
        fetchTask = nil
        cancelComputation()
        activeKey = nil
        activeQuery = nil
        for key in Array(cache.keys) {
            for source in sources where cache[key]?.entries[source]?.lastFailure == .cancelled {
                let deadline = max(monotonicNow(), cache[key]?.entries[source]?.freshUntil ?? 0)
                cache[key]?.entries[source]?.lastFailure = nil
                cache[key]?.entries[source]?.nextRequest = deadline
            }
        }
        locationProvider.cancel()
        if !enabled || stopped || demand.isEmpty { stopNetworkMonitoring() }
        if locationIsPending { recordLocation("result=cancelled") }
        if locationIsPending { locationAttemptDate = nil }
        locationIsPending = false
        forecasts = [:]
        forecastExpiry = nil
        recordPublication()
    }

    private func requestLocation(allowPrompt: Bool) {
        guard allowLocationRequests else {
            recordLocation("result=disabled")
            settingsStatus = "Для прогноза выберите город вручную."
            return
        }
        guard !locationIsPending else { return }
        if let locationAttemptDate, monotonicNow() - locationAttemptDate < Self.failureBackoff {
            scheduleRefresh(at: locationAttemptDate + Self.failureBackoff)
            return
        }
        locationIsPending = true
        recordLocation("result=requested prompt=\(allowPrompt)")
        locationAttemptDate = monotonicNow()
        settingsStatus = "Определяем местоположение…"
        let expectedGeneration = generation
        locationProvider.request(allowPrompt: allowPrompt) { [weak self] result in
            guard let self, self.generation == expectedGeneration, self.enabled, !self.stopped, !self.demand.isEmpty else { return }
            defer { self.recordDiagnosticSnapshot(reason: .settled) }
            self.locationIsPending = false
            switch result {
            case let .success(coordinates):
                self.recordLocation("result=success")
                self.coordinates = coordinates
                self.coordinateDate = self.monotonicNow()
                self.loadForecasts(at: coordinates)
            case .failure(.permissionRequired):
                self.recordLocation("result=permission_required")
                self.settingsStatus = "Для геолокации включите погоду или выберите «Автоматически» в настройках."
            case let .failure(failure):
                switch failure {
                case .denied: self.recordLocation("result=denied")
                case .unavailable: self.recordLocation("result=unavailable")
                case .permissionRequired: break
                }
                self.settingsStatus = "Местоположение недоступно. Выберите город вручную."
                self.scheduleRefresh(at: self.monotonicNow() + Self.failureBackoff)
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
            recordPublication()
            cancelScheduledRefresh()
            activeKey = key
            activeQuery = query
        }
        publishFreshForecasts(key: key, query: query)
        suppressUnneededRapidRetries(key: key)
        guard fetchTask == nil else {
            scheduleNextRefresh(key: key)
            return
        }
        let requestedAt = monotonicNow()
        let dueSources = sources.filter { networkState.status != .offline && sourceDeadline($0, key: key, at: requestedAt) <= requestedAt }
        guard !dueSources.isEmpty else {
            scheduleNextRefresh(key: key)
            return
        }
        if forecasts.isEmpty { settingsStatus = "Получаем прогноз…" }
        let expectedGeneration = generation
        let provider = provider
        var modifications: [WeatherSource: WeatherHTTPMetadata.Validators] = [:]
        for source in dueSources {
            if let entry = cache[key]?.entries[source], !entry.forceUnconditional,
               let validators = entry.batch?.http?.validators, !validators.isEmpty { modifications[source] = validators }
        }
        fetchTask = Task { [weak self] in
            let admitted = self?.startEligibleSources(dueSources, key: key, generation: expectedGeneration) ?? []
            guard !admitted.isEmpty else {
                if let self, self.generation == expectedGeneration, self.activeKey == key {
                    self.fetchTask = nil
                    self.scheduleNextRefresh(key: key)
                    self.recordDiagnosticSnapshot(reason: .settled)
                }
                return
            }
            await withTaskGroup(of: SourceOutcome.self) { group in
                for source in admitted {
                    let modified = modifications[source]
                    group.addTask {
                        do {
                            try Task.checkCancellation()
                            let result = try await provider(source, query, modified)
                            try Task.checkCancellation()
                            return SourceOutcome(source: source, result: .success(result))
                        } catch {
                            await self?.observeServerGate(source: source, error: error)
                            return SourceOutcome(source: source, result: .failure(error))
                        }
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
            defer { self.recordDiagnosticSnapshot(reason: .settled) }
            self.fetchTask = nil
            // A clock/expiry action can run after publication but before the task group drains.
            // Revisit a now-due source rather than losing that coalesced refresh.
            if self.sources.contains(where: { self.networkState.status != .offline && self.sourceDeadline($0, key: key, at: self.monotonicNow()) <= self.monotonicNow() }) {
                self.refresh()
            } else { self.scheduleNextRefresh(key: key) }
        }
        scheduleNextRefresh(key: key)
    }

    private func receive(_ outcome: SourceOutcome, key: String) {
        let tick = monotonicNow()
        var area = cache[key] ?? AreaCache(updatedAt: tick, entries: [:])
        let previous = area.entries[outcome.source]
        var state = sourceStates[outcome.source] ?? WeatherRequestPolicy.SourceState()
        var entry = previous ?? SourceCache(batch: nil, freshUntil: 0, nextRequest: tick, failed: false)
        var policyOutcome: WeatherRequestPolicy.Outcome
        var batch: WeatherSourceBatch?
        var failure = "error=none"
        var connectionFailure = false
        var result = "success"
        switch outcome.result {
        case let .success(value): batch = value; policyOutcome = .success
        case let .failure(error):
            failure = WeatherDiagnostics.errorFields(error)
            result = "failure"
            policyOutcome = WeatherRequestPolicy.classify(error)
            connectionFailure = (error as NSError).domain == NSURLErrorDomain && policyOutcome == .temporary
            let validation: WeatherHTTPMetadata?
            switch error {
            case let WeatherTransportFailure.validated(metadata): validation = metadata
            case let WeatherTransportFailure.notModified(expiry, modified):
                validation = WeatherHTTPMetadata.fromLegacyFields(expires: expiry, lastModified: modified, wall: now(), tick: tick)
            case let WeatherTransportFailure.httpMetadata(_, metadata):
                validation = nil
                if let delay = metadata.retryDelay { state.serverNotBefore = max(state.serverNotBefore, metadata.receivedTick + delay) }
            case let WeatherTransportFailure.http(_, date):
                validation = nil
                if let date = validDate(date) { state.serverNotBefore = max(state.serverNotBefore, tick + max(0, date.timeIntervalSince(now()))) }
            default: validation = nil
            }
            if let validation {
                if var old = previous?.batch, !entry.forceUnconditional, let metadata = old.http,
                   !metadata.validators.isEmpty, metadata.validators.matches(validation.validators) {
                    old.http = metadata.revalidated(by: validation)
                    batch = old
                    result = "not_modified"
                } else { entry.forceUnconditional = true }
            }
        }
        guard policyOutcome != .cancelled else {
            entry.lastFailure = .cancelled
            entry.nextRequest = .infinity
            area.entries[outcome.source] = entry
            cache[key] = area
            return
        }
        var remaining: TimeInterval = 0
        var usable = false
        if var batch {
            let metadata = batch.http ?? legacyMetadata(batch, tick: tick)
            if let delay = metadata.retryDelay { state.serverNotBefore = max(state.serverNotBefore, metadata.receivedTick + delay) }
            batch.http = metadata
            let clockCompatible = abs(now().timeIntervalSince(metadata.receivedWall) - (tick - metadata.receivedTick)) <= 60
            remaining = clockCompatible ? max(0, metadata.remaining - max(0, tick - metadata.receivedTick)) : 0
            if !clockCompatible { diagnostics.emit("weather.clock result=response_discontinuity") }
            usable = activeQuery.map { WeatherDiagnostics.usableDayCount(batch, query: $0) > 0 } ?? false
            entry.batch = metadata.allowsStorage ? batch : nil
            entry.freshUntil = tick + remaining
            entry.forceUnconditional = false
            entry.failed = false
            policyOutcome = remaining > 0 ? .success : .expired
            diagnostics.emit("weather.freshness source=\(outcome.source.rawValue) \(metadata.diagnosticFields)")
        } else { entry.failed = true }
        let fast = fastRetryIsUseful(source: outcome.source, key: key, tick: tick, previous: previous)
            && networkState.status != .offline && !networkState.expensive && !networkState.constrained && !lowPower()
        let previousFastUsed = state.fastUsed
        entry.nextRequest = WeatherRequestPolicy.deadline(outcome: policyOutcome, remaining: remaining,
            usableSuccess: usable, fastAllowed: fast, now: tick, jitter: jitter(), state: &state) ?? tick
        entry.rapidRetry = policyOutcome == .temporary && state.fastUsed > previousFastUsed
        entry.lastOutcomeTick = tick
        entry.lastFailure = batch == nil ? policyOutcome : nil
        entry.connectionFailure = batch == nil && connectionFailure
        sourceStates[outcome.source] = state
        area.entries[outcome.source] = entry
        area.updatedAt = tick
        cache[key] = area
        let cacheState = entry.batch == nil ? "empty" : (entry.freshUntil > tick ? "fresh" : "expired")
        diagnostics.emit("weather.source source=\(outcome.source.rawValue) result=\(result) cache=\(cacheState) " +
                         "fresh_for_s=\(WeatherDiagnostics.seconds(entry.freshUntil - tick)) " +
                         "retry_in_s=\(WeatherDiagnostics.seconds(sourceDeadline(outcome.source, key: key, at: tick) - tick)) " +
                         "retry_reason=\(policyOutcome.rawValue) attempt_index=\(state.attemptIndex) fast_used=\(state.fastUsed) \(failure)")
        if cache.count > 4, let oldest = cache.min(by: { $0.value.updatedAt < $1.value.updatedAt })?.key { cache.removeValue(forKey: oldest) }
    }

    private func legacyMetadata(_ batch: WeatherSourceBatch, tick: TimeInterval) -> WeatherHTTPMetadata {
        WeatherHTTPMetadata.fromLegacyFields(expires: validDate(batch.expiresAt), lastModified: batch.lastModified, wall: now(), tick: tick)
    }

    private func observeServerGate(source: WeatherSource, error: Error) {
        let deadline: TimeInterval?
        let overloaded: Bool
        switch error {
        case let WeatherTransportFailure.httpMetadata(status, metadata):
            deadline = metadata.retryDelay.map { metadata.receivedTick + $0 }
            overloaded = status == 429 || status == 503
        case let WeatherTransportFailure.validated(metadata):
            deadline = metadata.retryDelay.map { metadata.receivedTick + $0 }
            overloaded = false
        case let WeatherTransportFailure.http(status, date):
            deadline = validDate(date).map { monotonicNow() + max(0, $0.timeIntervalSince(now())) }
            overloaded = status == 429 || status == 503
        default: deadline = nil; overloaded = false
        }
        guard deadline != nil || overloaded else { return }
        var state = sourceStates[source] ?? WeatherRequestPolicy.SourceState()
        if let deadline { state.serverNotBefore = max(state.serverNotBefore, deadline) }
        if overloaded { state.providerCooldown = max(state.providerCooldown, monotonicNow() + 300) }
        sourceStates[source] = state
        diagnostics.emit("weather.server_gate source=\(source.rawValue) remaining_s=\(WeatherDiagnostics.seconds(state.admission(at: monotonicNow()) - monotonicNow()))")
    }

    private func fastRetryIsUseful(source: WeatherSource, key: String, tick: TimeInterval, previous: SourceCache?) -> Bool {
        if let previous, previous.batch != nil, previous.freshUntil > tick { return false }
        guard let query = activeQuery else { return false }
        let horizon = source == .wttr ? 3 : (source == .metNorway ? 10 : 16)
        return demand.intersection(Set(query.dayKeys.prefix(horizon))).contains { dayKey in
            if forecastExpiry.map({ $0 > tick }) == true, forecasts[dayKey] != nil { return false }
            return !(cache[key]?.entries.values.contains { entry in
                guard entry.freshUntil > tick, let sample = entry.batch?.forecasts[dayKey] else { return false }
                return sample.period == query.interval(for: dayKey) && sample.maximumTemperature != nil && sample.condition != nil
            } ?? false)
        }
    }

    private func sourceDeadline(_ source: WeatherSource, key: String, at tick: TimeInterval) -> TimeInterval {
        if cache[key]?.entries[source]?.lastFailure == .cancelled { return .infinity }
        return max(cache[key]?.entries[source]?.nextRequest ?? tick,
            sourceStates[source]?.admission(at: tick) ?? tick, recoveryDeadline)
    }

    private func startEligibleSources(_ planned: [WeatherSource], key: String, generation expected: Int) -> [WeatherSource] {
        guard !Task.isCancelled, generation == expected, enabled, !stopped, !demand.isEmpty,
              activeKey == key, networkState.status != .offline else { return [] }
        suppressUnneededRapidRetries(key: key)
        let tick = monotonicNow()
        let admitted = planned.filter { sourceDeadline($0, key: key, at: tick) <= tick }
        for source in admitted {
            var state = sourceStates[source] ?? WeatherRequestPolicy.SourceState()
            state.start(at: tick)
            sourceStates[source] = state
        }
        return admitted
    }

    private func suppressUnneededRapidRetries(key: String) {
        for source in sources {
            guard var entry = cache[key]?.entries[source], entry.rapidRetry else { continue }
            let needed = fastRetryIsUseful(source: source, key: key, tick: monotonicNow(), previous: entry)
            guard !needed || networkState.expensive || networkState.constrained || lowPower() else { continue }
            var state = sourceStates[source] ?? WeatherRequestPolicy.SourceState()
            entry.nextRequest = WeatherRequestPolicy.deadline(outcome: .temporary, now: entry.lastOutcomeTick,
                jitter: jitter(), state: &state) ?? entry.nextRequest
            entry.rapidRetry = false
            sourceStates[source] = state
            cache[key]?.entries[source] = entry
        }
    }

    private func publishFreshForecasts(key: String, query: WeatherQuery) {
        let timestamp = monotonicNow()
        let entries = cache[key]?.entries ?? [:]
        let fresh = entries.filter { $0.value.freshUntil > timestamp && $0.value.batch != nil }
        let input = ComputationInput(key: key, query: query, demand: demand,
                                     batches: fresh.compactMapValues(\.batch), expiry: fresh.values.map(\.freshUntil).min())
        // Withdraw expired/deleted values immediately, before any off-actor computation.
        if let previous = computationInput, !Set(previous.batches.keys).isSubset(of: Set(input.batches.keys)) {
            forecasts = [:]
            forecastExpiry = nil
        }
        if forecastExpiry.map({ $0 <= timestamp }) == true { forecasts = [:]; forecastExpiry = nil }
        forecasts = forecasts.filter { demand.contains($0.key) }
        recordPublication()
        if !forecasts.isEmpty { settingsStatus = nil }
        else if entries.values.contains(where: \.failed) { settingsStatus = "Прогноз недоступен. Попробуем позже." }
        else if !entries.isEmpty { settingsStatus = "Прогноз недоступен для выбранных дат." }
        guard computationInput != input else { return }
        cancelComputation()
        computationInput = input
        guard !input.batches.isEmpty, !input.demand.isEmpty else {
            forecasts = [:]
            forecastExpiry = nil
            recordPublication()
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
                guard let expiry = input.expiry, expiry > self.monotonicNow(), self.clockIsConsistent else {
                    self.publishFreshForecasts(key: key, query: query)
                    return
                }
                self.applyConsensus(consensus, input: input, expiry: expiry)
            } catch {
                guard let self, !Task.isCancelled, self.computationRevision == expectedRevision else { return }
                self.computationTask = nil
                self.settingsStatus = "Прогноз недоступен. Попробуем позже."
                self.diagnostics.emit("weather.computation \(WeatherDiagnostics.errorFields(error))")
                self.recordDiagnosticSnapshot(reason: .settled)
            }
        }
    }

    private func applyConsensus(_ consensus: [String: WeatherConsensus], input: ComputationInput, expiry: TimeInterval) {
        forecasts = consensus.reduce(into: [:]) { result, item in
            // The compact badge promises a daily maximum, so a remaining-hours maximum cannot replace it.
            guard input.demand.contains(item.key), item.value.period == input.query.interval(for: item.key),
                  let forecast = DailyWeatherForecast(weatherCode: item.value.weatherCode, maximumTemperature: item.value.maximumTemperature) else { return }
            result[item.key] = forecast
        }
        forecastExpiry = expiry
        recordPublication()
        if !forecasts.isEmpty { settingsStatus = nil }
        recordDiagnosticSnapshot(reason: .settled)
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
        let tick = monotonicNow()
        var dates: [TimeInterval] = []
        if networkState.status != .offline {
            dates = sources.map { sourceDeadline($0, key: key, at: tick) }.filter { $0.isFinite && $0 > tick }
        }
        dates += cache[key]?.entries.values.compactMap { entry in
            entry.batch != nil && entry.freshUntil > tick ? entry.freshUntil : nil
        } ?? []
        if let date = dates.min() { scheduleRefresh(at: date) }
        else { cancelScheduledRefresh() }
    }

    private func availableDayKeys() -> Set<String> {
        let coordinates = self.coordinates ?? WeatherCity.moscow.coordinates
        return Set(WeatherQuery(coordinates: coordinates, timeZone: location.timeZone, startDay: localToday)?.dayKeys ?? [])
    }

    private func cancelScheduledRefresh() {
        if refreshDate != nil { diagnostics.emit("weather.schedule result=cancelled") }
        refreshGeneration += 1
        refreshCancellation?()
        refreshCancellation = nil
        refreshDate = nil
    }

    private func scheduleRefresh(at date: TimeInterval) {
        guard refreshDate != date else { return }
        cancelScheduledRefresh()
        let expectedGeneration = generation
        let expectedRefresh = refreshGeneration
        refreshDate = date
        let delay = max(0, date - monotonicNow())
        diagnostics.emit("weather.schedule result=scheduled delay_s=\(WeatherDiagnostics.seconds(delay))")
        refreshCancellation = schedule(delay) { [weak self] in
            guard let self, self.generation == expectedGeneration, self.refreshGeneration == expectedRefresh,
                  self.enabled, !self.stopped, !self.demand.isEmpty else { return }
            self.refreshCancellation = nil
            self.refreshDate = nil
            if self.monotonicNow() < date { self.scheduleRefresh(at: date); return }
            self.refresh()
        }
    }

    private var clockIsConsistent: Bool {
        guard let anchor = clockAnchor else { return true }
        return abs(now().timeIntervalSince(anchor.wall) - (monotonicNow() - anchor.tick)) <= 60
    }

    private func observeClock() {
        let wall = now()
        let tick = monotonicNow()
        defer { clockAnchor = (wall, tick) }
        guard !clockIsConsistent else { return }
        cancelComputation()
        forecasts = [:]
        forecastExpiry = nil
        for key in Array(cache.keys) {
            for source in sources {
                if let entry = cache[key]?.entries[source], entry.freshUntil > tick,
                   !entry.failed, entry.lastFailure == nil {
                    // Only doubtful fresh success needs an earlier check; errors keep their monotonic backoff.
                    cache[key]?.entries[source]?.nextRequest = min(entry.nextRequest, tick + 60)
                }
                cache[key]?.entries[source]?.freshUntil = tick
            }
        }
        diagnostics.emit("weather.clock result=discontinuity")
        recordPublication()
    }

    private func updateNetworkMonitoring() {
        guard enabled, !stopped, !demand.isEmpty else { stopNetworkMonitoring(); return }
        guard !networkMonitoring, let networkMonitor else { return }
        networkMonitoring = true
        networkGeneration += 1
        let expected = networkGeneration
        networkMonitor.start { [weak self] state in
            guard let self, self.networkMonitoring, self.networkGeneration == expected,
                  self.enabled, !self.stopped, !self.demand.isEmpty else { return }
            let previous = self.networkState
            self.networkState = state
            guard previous != state else { return }
            let path = state.status == .offline ? "offline" : (state.status == .satisfied ? "satisfied" : "unknown")
            self.diagnostics.emit("weather.path state=\(path) expensive=\(state.expensive) constrained=\(state.constrained)")
            if state.status == .offline && previous.status != .offline { self.offlineSince = self.monotonicNow() }
            if previous.status == .offline && state.status != .offline {
                let prolonged = self.offlineSince.map { self.monotonicNow() - $0 >= 60 } == true
                self.offlineSince = nil
                let value = self.jitter()
                let fraction = value.isFinite ? min(1, max(0, value)) : 0
                self.recoveryDeadline = self.monotonicNow() + 2 + fraction * 3
                for key in Array(self.cache.keys) {
                    for source in self.sources where prolonged && self.cache[key]?.entries[source]?.connectionFailure == true {
                        if let deadline = self.cache[key]?.entries[source]?.nextRequest {
                            self.cache[key]?.entries[source]?.nextRequest = min(deadline, self.recoveryDeadline)
                        }
                    }
                }
                self.scheduleRefresh(at: self.recoveryDeadline)
            } else if let key = self.activeKey { self.scheduleNextRefresh(key: key) }
        }
    }

    private func stopNetworkMonitoring() {
        for source in sources where sourceStates[source] != nil { sourceStates[source]?.quiescent = true }
        if networkMonitoring { networkMonitor?.stop() }
        networkMonitoring = false
        networkGeneration += 1
        offlineSince = nil
        networkState = WeatherNetworkState()
        recoveryDeadline = 0
    }

    private func recordState(reason: String) {
        let mode = location == .automatic ? "auto" : "manual"
        diagnostics.emit("weather.state reason=\(reason) enabled=\(enabled) mode=\(mode) demanded=\(demand.count) sources=\(sources.count)")
    }

    private func recordLocation(_ fields: String) {
        guard lastLocationDiagnostic != fields else { return }
        lastLocationDiagnostic = fields
        diagnostics.emit("weather.location \(fields)")
    }

    private func recordPublication() {
        let fields = "demanded=\(demand.count) usable=\(forecasts.count)"
        guard lastPublication != fields else { return }
        lastPublication = fields
        diagnostics.emit("weather.publication \(fields)")
    }
}
