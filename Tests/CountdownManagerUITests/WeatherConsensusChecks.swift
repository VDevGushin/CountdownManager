import CountdownCore
import CountdownManagerUI
import Foundation

private func weatherBarrierDeadline(_ label: String, file: StaticString = #fileID, line: UInt = #line) -> Task<Void, Never> {
    Task {
        do { try await Task.sleep(for: .seconds(5)) } catch { return }
        preconditionFailure("Weather barrier did not arrive: \(label)", file: file, line: line)
    }
}

private actor ConsensusRequests {
    struct Request: Sendable {
        let source: WeatherSource
        let query: WeatherQuery
        let lastModified: String?
        let etag: String?
    }
    private(set) var requests: [Request] = []
    private(set) var cancelled = Set<Int>()
    private var pending: [Int: CheckedContinuation<WeatherSourceBatch, Error>] = [:]
    private var countWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var logWaiters: [(after: Int, predicate: @Sendable (String) -> Bool, continuation: CheckedContinuation<Void, Never>)] = []
    private(set) var logs: [String] = []

    func fetch(_ source: WeatherSource, query: WeatherQuery, lastModified: String?, etag: String? = nil) async throws -> WeatherSourceBatch {
        let index = requests.count
        requests.append(Request(source: source, query: query, lastModified: lastModified, etag: etag))
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                pending[index] = $0
                let ready = countWaiters.filter { $0.0 <= requests.count }
                countWaiters.removeAll { $0.0 <= requests.count }
                ready.forEach { $0.1.resume() }
            }
        } onCancel: {
            Task { await self.cancel(index) }
        }
    }

    private func cancel(_ index: Int) { cancelled.insert(index) }

    func waitForCount(_ count: Int, file: StaticString = #fileID, line: UInt = #line) async {
        let timeout = weatherBarrierDeadline("requests \(count)", file: file, line: line)
        defer { timeout.cancel() }
        if requests.count < count { await withCheckedContinuation { countWaiters.append((count, $0)) } }
        precondition(requests.count == count, "Unexpected duplicate source requests")
    }

    func record(_ line: String) {
        logs.append(line)
        let ready = logWaiters.filter { logs.count > $0.after && $0.predicate(line) }
        logWaiters.removeAll { logs.count > $0.after && $0.predicate(line) }
        ready.forEach { $0.continuation.resume() }
    }

    func waitForLog(after: Int = 0, file: StaticString = #fileID, line: UInt = #line,
                    _ predicate: @escaping @Sendable (String) -> Bool) async {
        let timeout = weatherBarrierDeadline("diagnostic transition after \(after)", file: file, line: line)
        defer { timeout.cancel() }
        guard !logs.dropFirst(after).contains(where: predicate) else { return }
        await withCheckedContinuation { logWaiters.append((after, predicate, $0)) }
    }

    func finishPending() {
        let values = pending.values
        pending.removeAll()
        for continuation in values { continuation.resume(throwing: CancellationError()) }
    }

    func request(_ source: WeatherSource, occurrence: Int) -> Request {
        requests.filter { $0.source == source }[occurrence]
    }

    func count(_ source: WeatherSource) -> Int { requests.filter { $0.source == source }.count }

    func complete(_ source: WeatherSource, occurrence: Int, result: Result<WeatherSourceBatch, Error>) {
        let index = requests.indices.filter { requests[$0].source == source }[occurrence]
        precondition(pending[index] != nil)
        pending.removeValue(forKey: index)?.resume(with: result)
    }
}

@MainActor
private final class ConsensusClock {
    var date = ISO8601DateFormatter().date(from: "2026-10-14T09:00:00Z")!
    var independentTick: TimeInterval?
    var tick: TimeInterval { independentTick ?? date.timeIntervalSinceReferenceDate }
    func advance(_ seconds: TimeInterval) {
        date = date.addingTimeInterval(seconds)
        if let independentTick { self.independentTick = independentTick + seconds }
    }
}

@MainActor
private final class ConsensusLocation: WeatherLocationProviding {
    func request(allowPrompt: Bool, _ completion: @escaping (Result<WeatherCoordinates, WeatherLocationFailure>) -> Void) {
        preconditionFailure("A manual-city fixture must never request device location")
    }
    func cancel() {}
}

@MainActor
private final class ConsensusSchedule {
    struct Entry {
        let deadline: Date
        let tick: TimeInterval
        let action: @MainActor () -> Void
        var cancelled = false
        var fired = false
    }
    let clock: ConsensusClock
    private(set) var entries: [Entry] = []
    init(clock: ConsensusClock) { self.clock = clock }

    func schedule(_ delay: TimeInterval, action: @escaping @MainActor () -> Void) -> () -> Void {
        precondition(delay.isFinite && delay >= 0)
        let index = entries.count
        entries.append(Entry(deadline: clock.date.addingTimeInterval(delay), tick: clock.tick + delay, action: action))
        return { [weak self] in self?.entries[index].cancelled = true }
    }

    var activeIndex: Int {
        entries.indices.filter { !entries[$0].cancelled && !entries[$0].fired }
            .min { entries[$0].tick < entries[$1].tick }!
    }

    func fireNext(file: StaticString = #fileID, line: UInt = #line) {
        let index = activeIndex
        precondition(entries[index].tick <= clock.tick,
                     "Scheduler is due at \(entries[index].tick), clock is \(clock.tick)", file: file, line: line)
        entries[index].fired = true
        entries[index].action()
    }

    func deliverLate(_ index: Int) { entries[index].action() }
}

@MainActor
private final class ConsensusFixture {
    let requests = ConsensusRequests()
    let clock = ConsensusClock()
    let schedule: ConsensusSchedule
    let controller: WeatherController
    let day: Day
    let event: Countdown
    let defaults: UserDefaults
    let suite = "local.countdownmanager.consensus-checks.\(UUID().uuidString)"

    init(sources: [WeatherSource] = WeatherSource.allCases, computation: WeatherConsensusComputation? = nil,
         http: Bool = false, network: (any WeatherNetworkMonitoring)? = nil, lowPower: @escaping () -> Bool = { false },
         independentClock: Bool = false) {
        if independentClock { clock.independentTick = 100 }
        schedule = ConsensusSchedule(clock: clock)
        defaults = UserDefaults(suiteName: suite)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = WeatherCity.moscow.timeZone
        day = Day(clock.date, calendar: calendar)
        event = Countdown(title: "Consensus fixture", date: day, emoji: "", showsWeather: true)
        let requests = requests
        let clock = clock
        let schedule = schedule
        let legacy: WeatherSourceProvider?
        let fullHTTP: WeatherHTTPProvider?
        if http {
            legacy = nil
            fullHTTP = { try await requests.fetch($0, query: $1, lastModified: $2?.lastModified, etag: $2?.etag) }
        } else {
            legacy = { try await requests.fetch($0, query: $1, lastModified: $2) }
            fullHTTP = nil
        }
        let diagnostics = WeatherDiagnostics { line in Task { await requests.record(line) } }
        controller = WeatherController(
            defaults: defaults,
            sourceProvider: legacy, sources: sources,
            locationProvider: ConsensusLocation(), allowLocationRequests: false, now: { clock.date }, monotonicNow: { clock.tick }, jitter: { 0 },
            scheduler: { schedule.schedule($0, action: $1) }, consensusComputation: computation,
            diagnostics: diagnostics, httpProvider: fullHTTP,
            networkMonitor: network, lowPower: lowPower
        )
        controller.selectLocation(.city(.moscow))
    }

    func start() {
        controller.updateEvents([event])
        controller.setEnabled(true)
    }

    func close() {
        controller.shutdown()
        defaults.removePersistentDomain(forName: suite)
    }

    func complete(
        _ source: WeatherSource, occurrence: Int = 0, temperature: Double,
        category: WeatherCategory = .clear, expiry: Date? = nil, modified: String? = nil,
        partial: Bool = false, headers: [String: String]? = nil
    ) async {
        let request = await requests.request(source, occurrence: occurrence)
        let key = weatherDayKey(day)
        let fullPeriod = request.query.interval(for: key)!
        let period = partial ? DateInterval(start: fullPeriod.start.addingTimeInterval(43_200), end: fullPeriod.end) : fullPeriod
        let sample = WeatherDailySample(dayKey: key, period: period, maximumTemperature: temperature, condition: category)
        await requests.complete(source, occurrence: occurrence, result: .success(WeatherSourceBatch(
            forecasts: [key: sample], expiresAt: expiry, lastModified: modified,
            http: headers.map { WeatherHTTPMetadata(headers: $0, receivedWall: clock.date, receivedTick: clock.tick) }
        )))
    }

    func fail(_ source: WeatherSource, occurrence: Int = 0, error: Error = URLError(.timedOut)) async {
        await requests.complete(source, occurrence: occurrence, result: .failure(error))
    }
}

@MainActor
private func waitForConsensus(_ predicate: () async -> Bool, file: StaticString = #fileID, line: UInt = #line) async {
    for _ in 0..<1_000 {
        if await predicate() { return }
        await Task.yield()
    }
    preconditionFailure("Consensus fixture did not reach its expected state", file: file, line: line)
}

@MainActor
private func settleConsensus() async {
    for _ in 0..<32 { await Task.yield() }
}

@MainActor
func testWeatherConsensusLifecycle() async throws {
    testWeatherHTTPDates()
    testWeatherRetryPolicy()
    await testIncrementalConsensus()
    await testConsensusFailureIsolation()
    await testConsensusSourceMetadata()
    await testConsensusShortExpiry()
    await testConsensusExpiryWhileOtherSourcePending(shutdown: false)
    await testConsensusExpiryWhileOtherSourcePending(shutdown: true)
    await testConsensusCancellation()
    await testConsensusAreaCache()
    await testConsensusInvalidMetadata()
    await testDeletedWeatherDemand(sharedDay: false)
    await testDeletedWeatherDemand(sharedDay: true)
    await testSupersededWeatherComputation()
    await testResilientColdTimeouts()
    await testResilientExpiredResponses()
    await testResilient304Representations()
    await testResilientServerGates()
    await testResilientSyntheticEpisode()
    await testResilientNetworkRecovery()
    await testResilientOfflineExpiry()
    await testResilientEnergyLimits()
    await testResilientClockAndMidnight()
    await testResilientClockPreservesFailureBackoff()
    await testResilientCancellationDoesNotRetry()
    testRestoredWeatherPreferences()
    try await testCancelledWeatherProcessing()
}

@MainActor
private func testIncrementalConsensus() async {
    let fixture = ConsensusFixture()
    defer { fixture.close() }
    fixture.start()
    await waitForConsensus { await fixture.requests.requests.count == 3 }
    let initial = await fixture.requests.requests
    precondition(Set(initial.map(\.source)) == Set(WeatherSource.allCases))
    precondition(initial.allSatisfy { $0.query.dayCount == 16 && $0.query.timeZone.identifier == "Europe/Moscow" })
    let query = initial[0].query
    let tomorrow = Day(query.interval(for: query.dayKeys[1])!.start, calendar: query.calendar)
    let anotherDay = Countdown(title: "Second demanded day", date: tomorrow, emoji: "", showsWeather: true)
    fixture.controller.updateEvents([fixture.event, fixture.event, anotherDay])
    await settleConsensus()
    let duplicateCount = await fixture.requests.requests.count
    precondition(duplicateCount == 3, "Events sharing a day must not duplicate source queries")

    await fixture.complete(.openMeteo, temperature: 10)
    await waitForConsensus { fixture.controller.forecast(for: fixture.day)?.maximumTemperature == 10 }
    precondition(fixture.controller.forecast(for: fixture.day)?.weatherCode == 0)
    await fixture.complete(.metNorway, temperature: 30, category: .rain)
    await waitForConsensus { fixture.controller.forecast(for: fixture.day)?.maximumTemperature == 20 }
    precondition(fixture.controller.forecast(for: fixture.day)?.weatherCode == 63, "Wet wins an equal source vote")
    await fixture.complete(.wttr, temperature: 12)
    await waitForConsensus { fixture.controller.forecast(for: fixture.day)?.maximumTemperature == 12
        && fixture.controller.forecast(for: fixture.day)?.weatherCode == 0 }
}

@MainActor
private func testConsensusFailureIsolation() async {
    let fixture = ConsensusFixture()
    defer { fixture.close() }
    fixture.start()
    await waitForConsensus { await fixture.requests.requests.count == 3 }
    await fixture.fail(.metNorway)
    await fixture.complete(.openMeteo, temperature: 18)
    await waitForConsensus { fixture.controller.forecast(for: fixture.day)?.maximumTemperature == 18 }
    await fixture.requests.complete(.wttr, occurrence: 0, result: .success(WeatherSourceBatch(forecasts: [:])))
    await settleConsensus()
    precondition(fixture.controller.forecast(for: fixture.day)?.maximumTemperature == 18)

    let empty = ConsensusFixture()
    defer { empty.close() }
    empty.start()
    await waitForConsensus { await empty.requests.requests.count == 3 }
    for source in WeatherSource.allCases { await empty.fail(source) }
    await settleConsensus()
    precondition(empty.controller.forecast(for: empty.day) == nil)

    let missing = ConsensusFixture()
    defer { missing.close() }
    missing.start()
    await waitForConsensus { await missing.requests.requests.count == 3 }
    for source in WeatherSource.allCases {
        await missing.requests.complete(source, occurrence: 0, result: .success(WeatherSourceBatch(forecasts: [:])))
    }
    await settleConsensus()
    precondition(missing.controller.forecast(for: missing.day) == nil)

    let partial = ConsensusFixture()
    defer { partial.close() }
    partial.start()
    await waitForConsensus { await partial.requests.requests.count == 3 }
    for source in WeatherSource.allCases { await partial.complete(source, temperature: 20, partial: true) }
    await settleConsensus()
    precondition(partial.controller.forecast(for: partial.day) == nil, "Remaining-hours maxima never populate a full-day badge")
}

@MainActor
private func testConsensusSourceMetadata() async {
    let fixture = ConsensusFixture()
    defer { fixture.close() }
    let start = fixture.clock.date
    let modified = "Wed, 14 Oct 2026 08:00:00 GMT"
    fixture.start()
    await waitForConsensus { await fixture.requests.requests.count == 3 }
    await fixture.complete(.openMeteo, temperature: 10, expiry: start.addingTimeInterval(1_800), modified: modified)
    await fixture.complete(.metNorway, temperature: 20, expiry: start.addingTimeInterval(3_600))
    await fixture.fail(.wttr, error: WeatherTransportFailure.http(status: 429, retryAfter: start.addingTimeInterval(7_200)))
    await waitForConsensus { fixture.controller.forecast(for: fixture.day)?.maximumTemperature == 15 }
    await settleConsensus()
    precondition(fixture.controller.forecast(for: fixture.day)?.maximumTemperature == 15)

    fixture.clock.date = start.addingTimeInterval(1_800)
    fixture.schedule.fireNext()
    await waitForConsensus { fixture.controller.forecast(for: fixture.day)?.maximumTemperature == 20 }
    await waitForConsensus { await fixture.requests.requests.count == 4 }
    let conditional = await fixture.requests.request(.openMeteo, occurrence: 1)
    precondition(conditional.lastModified == modified)
    let bCount = await fixture.requests.count(.metNorway)
    let cCount = await fixture.requests.count(.wttr)
    precondition(bCount == 1 && cCount == 1)
    await fixture.fail(.openMeteo, occurrence: 1, error: WeatherTransportFailure.notModified(
        expiresAt: start.addingTimeInterval(3_600), lastModified: nil
    ))
    await waitForConsensus { fixture.controller.forecast(for: fixture.day)?.maximumTemperature == 15 }
    await settleConsensus()

    fixture.clock.date = start.addingTimeInterval(3_600)
    fixture.schedule.fireNext()
    await waitForConsensus { await fixture.requests.requests.count == 6 }
    await fixture.complete(.openMeteo, occurrence: 2, temperature: 12, expiry: start.addingTimeInterval(10_800))
    await fixture.complete(.metNorway, occurrence: 1, temperature: 22, expiry: start.addingTimeInterval(10_800))
    await waitForConsensus { fixture.controller.forecast(for: fixture.day)?.maximumTemperature == 17 }
    await settleConsensus()
    let stillDeferred = await fixture.requests.count(.wttr)
    precondition(stillDeferred == 1 && fixture.controller.forecast(for: fixture.day)?.maximumTemperature == 17)
    fixture.clock.date = start.addingTimeInterval(7_200)
    fixture.schedule.fireNext()
    await waitForConsensus { await fixture.requests.requests.count == 7 }
    await fixture.complete(.wttr, occurrence: 1, temperature: 42)
    await waitForConsensus { fixture.controller.forecast(for: fixture.day)?.maximumTemperature == 22 }
}

@MainActor
private func testConsensusShortExpiry() async {
    let fixture = ConsensusFixture(sources: [.openMeteo, .metNorway])
    defer { fixture.close() }
    let start = fixture.clock.date
    fixture.start()
    await waitForConsensus { await fixture.requests.requests.count == 2 }
    await fixture.complete(.openMeteo, temperature: 10, expiry: start.addingTimeInterval(20))
    await fixture.complete(.metNorway, temperature: 20, expiry: start.addingTimeInterval(3_600))
    await waitForConsensus { fixture.controller.forecast(for: fixture.day)?.maximumTemperature == 15 }
    await settleConsensus()
    fixture.clock.date = start.addingTimeInterval(20)
    fixture.schedule.fireNext()
    await waitForConsensus { fixture.controller.forecast(for: fixture.day)?.maximumTemperature == 20 }
    await settleConsensus()
    let count = await fixture.requests.requests.count
    precondition(count == 2, "Short TTL hides expired A while retaining B; no request before the60-second floor")
    fixture.clock.date = start.addingTimeInterval(60)
    fixture.schedule.fireNext()
    await waitForConsensus { await fixture.requests.requests.count == 3 }
    await fixture.complete(.openMeteo, occurrence: 1, temperature: 12)
    await waitForConsensus { fixture.controller.forecast(for: fixture.day)?.maximumTemperature == 16 }
}

@MainActor
private func testConsensusExpiryWhileOtherSourcePending(shutdown: Bool) async {
    let fixture = ConsensusFixture()
    defer { fixture.close() }
    let start = fixture.clock.date
    fixture.start()
    await waitForConsensus { await fixture.requests.requests.count == 3 }
    await fixture.complete(.openMeteo, temperature: 10, expiry: start.addingTimeInterval(1_800))
    await fixture.complete(.wttr, temperature: 30, expiry: start.addingTimeInterval(7_200))
    await waitForConsensus { fixture.controller.forecast(for: fixture.day)?.maximumTemperature == 20 }

    // B's first request is still running while A and C are already usable.
    fixture.clock.date = start.addingTimeInterval(1_495)
    await fixture.fail(.metNorway)
    await settleConsensus()
    precondition(fixture.schedule.entries[fixture.schedule.activeIndex].deadline == start.addingTimeInterval(1_795))
    fixture.clock.date = start.addingTimeInterval(1_795)
    fixture.schedule.fireNext()
    await waitForConsensus { await fixture.requests.count(.metNorway) == 2 }
    precondition(fixture.schedule.entries[fixture.schedule.activeIndex].deadline == start.addingTimeInterval(1_800),
                 "Starting B's retry must retain A's earlier expiry task")

    fixture.clock.date = start.addingTimeInterval(1_800)
    fixture.schedule.fireNext()
    await waitForConsensus { fixture.controller.forecast(for: fixture.day)?.maximumTemperature == 30 }
    let pendingCount = await fixture.requests.requests.count
    precondition(pendingCount == 4)

    fixture.clock.date = start.addingTimeInterval(1_805)
    await fixture.complete(.metNorway, occurrence: 1, temperature: 20)
    // No explicit refresh or Store update: draining B's group must pick up the now-due A.
    await waitForConsensus { await fixture.requests.count(.openMeteo) == 2 }
    await waitForConsensus { fixture.controller.forecast(for: fixture.day)?.maximumTemperature == 25 }
    let allRequests = await fixture.requests.requests
    precondition(allRequests.count == 5 && allRequests.last?.source == .openMeteo)

    let scheduled = fixture.schedule.activeIndex
    if shutdown { fixture.controller.shutdown() } else { fixture.controller.setEnabled(false) }
    precondition(fixture.schedule.entries[scheduled].cancelled)
    await waitForConsensus { await fixture.requests.cancelled.count == 1 }
    fixture.clock.date = start.addingTimeInterval(4_000)
    fixture.schedule.deliverLate(scheduled)
    await fixture.complete(.openMeteo, occurrence: 1, temperature: 40)
    await settleConsensus()
    fixture.schedule.deliverLate(scheduled)
    await settleConsensus()
    let finalCount = await fixture.requests.requests.count
    precondition(finalCount == 5 && fixture.controller.forecast(for: fixture.day) == nil,
                 "Late group completion and expiry callbacks cannot resurrect OFF or shutdown weather")
}

@MainActor
private func testConsensusCancellation() async {
    let fixture = ConsensusFixture()
    defer { fixture.close() }
    fixture.start()
    await waitForConsensus { await fixture.requests.requests.count == 3 }
    fixture.controller.setEnabled(false)
    await waitForConsensus { await fixture.requests.cancelled.count == 3 }
    for source in WeatherSource.allCases { await fixture.complete(source, temperature: 50) }
    await settleConsensus()
    precondition(fixture.controller.forecast(for: fixture.day) == nil)

    fixture.controller.setEnabled(true)
    await waitForConsensus { await fixture.requests.requests.count == 6 }
    for source in WeatherSource.allCases { await fixture.complete(source, occurrence: 1, temperature: 20) }
    await settleConsensus()
    let previousSchedule = fixture.schedule.activeIndex
    fixture.controller.setEnabled(false)
    precondition(fixture.schedule.entries[previousSchedule].cancelled)
    fixture.schedule.deliverLate(previousSchedule)
    await settleConsensus()
    let offCount = await fixture.requests.requests.count
    precondition(offCount == 6 && fixture.controller.forecast(for: fixture.day) == nil)

    fixture.controller.setEnabled(true)
    let oldCitySchedule = fixture.schedule.activeIndex
    fixture.controller.selectLocation(.city(.kazan))
    fixture.schedule.deliverLate(oldCitySchedule)
    await waitForConsensus { await fixture.requests.requests.count == 9 }
    fixture.controller.shutdown()
    await waitForConsensus { await fixture.requests.cancelled.count == 6 }
    for source in WeatherSource.allCases { await fixture.complete(source, occurrence: 2, temperature: 60) }
    fixture.schedule.deliverLate(oldCitySchedule)
    await settleConsensus()
    precondition(fixture.controller.forecast(for: fixture.day) == nil)
    let finalCount = await fixture.requests.requests.count
    precondition(finalCount == 9)

    let changed = ConsensusFixture(sources: [.openMeteo])
    defer { changed.close() }
    changed.start()
    await waitForConsensus { await changed.requests.requests.count == 1 }
    changed.controller.selectLocation(.city(.kazan))
    await waitForConsensus {
        let count = await changed.requests.requests.count
        let cancelled = await changed.requests.cancelled.count
        return count == 2 && cancelled == 1
    }
    await changed.complete(.openMeteo, temperature: 50)
    await settleConsensus()
    precondition(changed.controller.forecast(for: changed.day) == nil, "The old city's response must not publish")
    await changed.complete(.openMeteo, occurrence: 1, temperature: 20)
    await waitForConsensus { changed.controller.forecast(for: changed.day)?.maximumTemperature == 20 }
    await settleConsensus()
    let shutdownSchedule = changed.schedule.activeIndex
    changed.controller.shutdown()
    precondition(changed.schedule.entries[shutdownSchedule].cancelled)
    changed.schedule.deliverLate(shutdownSchedule)
    await settleConsensus()
    let changedCount = await changed.requests.requests.count
    precondition(changedCount == 2 && changed.controller.forecast(for: changed.day) == nil)
}

@MainActor
private func testConsensusAreaCache() async {
    let fixture = ConsensusFixture(sources: [.openMeteo])
    defer { fixture.close() }
    let started = fixture.clock.date
    fixture.start()
    let cities: [WeatherCity] = [.moscow, .kazan, .grozny, .samara, .krasnodar]
    for (index, city) in cities.enumerated() {
        fixture.controller.selectLocation(.city(city))
        await waitForConsensus { await fixture.requests.requests.count == index + 1 }
        await fixture.complete(.openMeteo, occurrence: index, temperature: 20)
        await waitForConsensus { fixture.controller.forecast(for: fixture.day)?.maximumTemperature == 20 }
        await settleConsensus()
        fixture.clock.date = fixture.clock.date.addingTimeInterval(1)
    }
    fixture.controller.selectLocation(.city(.moscow))
    await waitForConsensus { await fixture.requests.requests.count == 6 }
    await fixture.complete(.openMeteo, occurrence: 5, temperature: 20)
    await settleConsensus()
    fixture.controller.selectLocation(.city(.novosibirsk))
    let beforeBudgetRelease = await fixture.requests.requests.count
    precondition(beforeBudgetRelease == 6, "Changing city cannot bypass the six-start source budget")
    fixture.clock.date = started.addingTimeInterval(600)
    fixture.schedule.fireNext()
    await waitForConsensus { await fixture.requests.requests.count == 7 }
    let request = await fixture.requests.request(.openMeteo, occurrence: 6)
    precondition(request.query.timeZone.identifier == "Asia/Novosibirsk")
    precondition(request.query.startDay == fixture.day && request.query.dayCount == 16)
    let localStart = request.query.interval(for: weatherDayKey(fixture.day))!.start
    precondition(ISO8601DateFormatter().string(from: localStart) == "2026-10-13T17:00:00Z")
    await fixture.complete(.openMeteo, occurrence: 6, temperature: 20)
}

@MainActor
private func testConsensusInvalidMetadata() async {
    let fixture = ConsensusFixture(sources: [.openMeteo, .metNorway])
    defer { fixture.close() }
    fixture.start()
    await waitForConsensus { await fixture.requests.requests.count == 2 }
    await fixture.complete(.openMeteo, temperature: 20, expiry: Date(timeIntervalSince1970: .infinity))
    await fixture.fail(.metNorway, error: WeatherTransportFailure.http(status: 429, retryAfter: Date(timeIntervalSince1970: .nan)))
    await waitForConsensus { fixture.controller.forecast(for: fixture.day)?.maximumTemperature == 20 }
    await settleConsensus()
    precondition(fixture.controller.forecast(for: fixture.day)?.maximumTemperature == 20)
    let retry = fixture.schedule.entries[fixture.schedule.activeIndex].deadline
    precondition(retry == fixture.clock.date.addingTimeInterval(300))
    fixture.clock.date = retry
    fixture.schedule.fireNext()
    await waitForConsensus { await fixture.requests.requests.count == 3 }
    await fixture.complete(.metNorway, occurrence: 1, temperature: 22)
}

private func testWeatherHTTPDates() {
    let now = ISO8601DateFormatter().date(from: "2026-10-14T09:00:00Z")!
    precondition(WeatherTransport.httpDate("Wed, 14 Oct 2026 09:00:00 GMT") == now)
    precondition(WeatherTransport.httpDate(nil) == nil && WeatherTransport.httpDate("invalid") == nil)
    precondition(WeatherTransport.retryAfter("120", now: now) == now.addingTimeInterval(120))
    precondition(WeatherTransport.retryAfter("Wed, 14 Oct 2026 09:05:00 GMT", now: now) == now.addingTimeInterval(300))
    for value in ["-1", "NaN", "infinity", "invalid", "Wed, 14 Oct 2026 08:00:00 GMT"] {
        precondition(WeatherTransport.retryAfter(value, now: now) == nil)
    }
}

@MainActor
private func testDeletedWeatherDemand(sharedDay: Bool) async {
    let fixture = ConsensusFixture()
    defer { fixture.close() }
    let secondDay = sharedDay ? fixture.day : Day(
        Day.calendar.date(byAdding: .day, value: 1, to: fixture.day.date())!
    )
    let second = Countdown(title: "Other eligible event", date: secondDay, emoji: "", showsWeather: true)
    fixture.controller.updateEvents([fixture.event, second])
    fixture.controller.setEnabled(true)
    await waitForConsensus { await fixture.requests.requests.count == 3 }
    fixture.controller.updateEvents([second])
    await settleConsensus()
    let retainedRequests = await fixture.requests.requests.count
    let cancellations = await fixture.requests.cancelled.count
    precondition(retainedRequests == 3 && cancellations == 0, "Deleting one event retains shared useful requests")
    fixture.controller.updateEvents([])
    await waitForConsensus { await fixture.requests.cancelled.count == 3 }
    for source in WeatherSource.allCases { await fixture.complete(source, temperature: 60) }
    await settleConsensus()
    precondition(fixture.controller.forecast(for: fixture.day) == nil && fixture.controller.forecast(for: secondDay) == nil)
    precondition(fixture.schedule.entries.allSatisfy { $0.cancelled || $0.fired })
    fixture.controller.updateEvents([second])
    await waitForConsensus { await fixture.requests.requests.count == 6 }
    precondition(fixture.controller.forecast(for: secondDay) == nil, "Late cancelled replies cannot repopulate cache")
    for source in WeatherSource.allCases { await fixture.fail(source, occurrence: 1) }
}

private actor PausedWeatherComputations {
    struct Input: Sendable {
        let batches: [WeatherSource: WeatherSourceBatch]
        let query: WeatherQuery
        let demand: Set<String>
    }
    private(set) var inputs: [Input] = []
    private(set) var cancelled = Set<Int>()
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var pending: [Int: CheckedContinuation<[String: WeatherConsensus], Error>] = [:]

    func compute(_ batches: [WeatherSource: WeatherSourceBatch], _ query: WeatherQuery,
                 _ demand: Set<String>) async throws -> [String: WeatherConsensus] {
        let index = inputs.count
        inputs.append(Input(batches: batches, query: query, demand: demand))
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                pending[index] = $0
                let ready = waiters.filter { $0.0 <= inputs.count }
                waiters.removeAll { $0.0 <= inputs.count }
                ready.forEach { $0.1.resume() }
            }
        } onCancel: {
            Task { await self.recordCancellation(index) }
        }
    }

    func waitForInputCount(_ expected: Int, file: StaticString = #fileID, line: UInt = #line) async {
        let timeout = weatherBarrierDeadline("computation inputs", file: file, line: line)
        defer { timeout.cancel() }
        if inputs.count < expected { await withCheckedContinuation { waiters.append((expected, $0)) } }
        precondition(inputs.count == expected)
    }

    private func recordCancellation(_ index: Int) { cancelled.insert(index) }

    func complete(_ index: Int) {
        let input = inputs[index]
        // Deliberately ignores cancellation to test publication guards at the receiving boundary.
        let consensus = WeatherNormalizer.aggregate(input.batches, query: input.query).filter { input.demand.contains($0.key) }
        pending.removeValue(forKey: index)!.resume(returning: consensus)
    }
}

@MainActor
private func testSupersededWeatherComputation() async {
    let computations = PausedWeatherComputations()
    let fixture = ConsensusFixture(computation: { try await computations.compute($0, $1, $2) })
    defer { fixture.close() }
    fixture.start()
    await waitForConsensus { await fixture.requests.requests.count == 3 }
    let request = await fixture.requests.request(.openMeteo, occurrence: 0)
    let secondKey = request.query.dayKeys[1]
    let secondDay = Day(request.query.interval(for: secondKey)!.start, calendar: request.query.calendar)
    let second = Countdown(title: "Remaining weather day", date: secondDay, emoji: "", showsWeather: true)
    fixture.controller.updateEvents([fixture.event, second])
    for (source, temperature) in [(WeatherSource.openMeteo, 10.0), (.metNorway, 30.0), (.wttr, 12.0)] {
        let samples = [weatherDayKey(fixture.day), secondKey].reduce(into: [String: WeatherDailySample]()) { result, key in
            result[key] = WeatherDailySample(dayKey: key, period: request.query.interval(for: key)!,
                                             maximumTemperature: temperature, condition: .clear)
        }
        await fixture.requests.complete(source, occurrence: 0, result: .success(WeatherSourceBatch(forecasts: samples)))
        if source == .openMeteo {
            await computations.waitForInputCount(1)
            let progress = Task { @MainActor in fixture.controller.refresh(); return true }
            let responsive = await progress.value
            precondition(responsive && fixture.controller.forecast(for: fixture.day) == nil,
                         "MainActor work must finish before a paused computation is released")
            fixture.controller.updateEvents([second])
            await computations.waitForInputCount(2)
            await computations.complete(0)
            await settleConsensus()
            precondition(fixture.controller.forecast(for: secondDay) == nil && fixture.controller.forecast(for: fixture.day) == nil)
            await computations.complete(1)
            await waitForConsensus { fixture.controller.forecast(for: secondDay)?.maximumTemperature == 10 }
        } else if source == .metNorway {
            await computations.waitForInputCount(3)
        } else {
            await computations.waitForInputCount(4)
        }
    }
    await computations.complete(2)
    await settleConsensus()
    precondition(fixture.controller.forecast(for: secondDay)?.maximumTemperature == 10,
                 "Superseded source computation cannot overwrite the currently published forecast")
    await computations.complete(3)
    await waitForConsensus { fixture.controller.forecast(for: secondDay)?.maximumTemperature == 12 }
    precondition(fixture.controller.forecast(for: fixture.day) == nil)
    let inputs = await computations.inputs
    precondition(inputs[0].demand.count == 2 && inputs.dropFirst().allSatisfy { $0.demand == [secondKey] })
    let cancelled = await computations.cancelled
    precondition(cancelled.isSuperset(of: [0, 2]))
}

@MainActor
private func testRestoredWeatherPreferences() {
    let fixture = ConsensusFixture()
    defer { fixture.close() }
    fixture.controller.selectLocation(.city(.novosibirsk))
    fixture.controller.setEnabled(true)
    fixture.controller.shutdown()
    let replacementDefaults = UserDefaults(suiteName: fixture.suite)!
    let restored = WeatherController(defaults: replacementDefaults, sourceProvider: { _, _, _ in
        preconditionFailure("Restoring preferences without eligible events must not start network work")
    }, locationProvider: ConsensusLocation(), allowLocationRequests: false)
    precondition(restored.enabled && restored.location == .city(.novosibirsk))
    precondition(replacementDefaults.bool(forKey: "weather.enabled"))
    precondition(replacementDefaults.string(forKey: "weather.location") == "novosibirsk")
    restored.setEnabled(false)
    restored.shutdown()
    let next = WeatherController(defaults: UserDefaults(suiteName: fixture.suite)!, allowLocationRequests: false)
    precondition(!next.enabled && next.location == .city(.novosibirsk))
    next.shutdown()
}

private func testCancelledWeatherProcessing() async throws {
    let query = WeatherQuery(coordinates: WeatherCity.moscow.coordinates, timeZone: WeatherCity.moscow.timeZone,
                             startDay: Day(Date()))!
    let decoders: [@Sendable (Data, WeatherQuery) throws -> WeatherSourceBatch] = [
        { try OpenMeteoWeatherAdapter.decode($0, query: $1) },
        { try METNorwayWeatherProvider.decode($0, query: $1) },
        { try WttrWeatherProvider.decode($0, query: $1) },
    ]
    for decode in decoders {
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try decode(Data(), query)
        }
        do { _ = try await task.value; preconditionFailure("Cancelled decoder returned") }
        catch is CancellationError {} // Cancellation wins even before malformed JSON validation.
    }
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await WeatherNormalizer.aggregateDemanded([:], query: query, demandedDayKeys: Set(query.dayKeys))
    }
    do { _ = try await task.value; preconditionFailure("Cancelled consensus returned") }
    catch is CancellationError {}
}

private func testWeatherRetryPolicy() {
    for jitter in [0.0, 1.0] {
        var state = WeatherRequestPolicy.SourceState()
        var tick = 0.0
        let expected = jitter == 0 ? [10.0, 45, 300, 900, 1_800, 1_800] : [20.0, 75, 360, 1_080, 2_160, 2_160]
        for delay in expected {
            state.start(at: tick)
            let deadline = WeatherRequestPolicy.deadline(outcome: .temporary, fastAllowed: true,
                                                         now: tick, jitter: jitter, state: &state)!
            precondition(deadline == tick + delay)
            tick = deadline
        }
        precondition(state.fastUsed == 2)
    }
    var expired = WeatherRequestPolicy.SourceState()
    for delay in [60.0, 300, 900, 1_800] {
        let deadline = WeatherRequestPolicy.deadline(outcome: .expired, now: 100, jitter: 0, state: &expired)
        precondition(deadline == 100 + delay)
    }
    var state = WeatherRequestPolicy.SourceState()
    precondition(WeatherRequestPolicy.deadline(outcome: .success, remaining: 20, now: 0, jitter: 0, state: &state) == 60)
    precondition(WeatherRequestPolicy.deadline(outcome: .success, remaining: 20, now: 0, jitter: 1, state: &state) == 75)
    precondition(WeatherRequestPolicy.deadline(outcome: .success, remaining: 7_200, now: 0, jitter: 1, state: &state) == 7_200)
    precondition(WeatherRequestPolicy.deadline(outcome: .cancelled, now: 0, jitter: 0, state: &state) == nil)
    for start in 0..<6 { state.start(at: Double(start)) }
    precondition(state.admission(at: 5) == 600 && state.admission(at: 600) == 600)
    state.serverNotBefore = 1_000_000_000
    precondition(state.admission(at: 600) == 1_000_000_000)
    precondition(WeatherRequestPolicy.deadline(outcome: .overloaded, now: 600, jitter: 0, state: &state) == 1_000_000_000)
    for error: Error in [URLError(.secureConnectionFailed), URLError(.serverCertificateUntrusted),
                         WeatherProviderFailure.invalidData, WeatherTransportFailure.http(status: 404, retryAfter: nil)] {
        precondition(WeatherRequestPolicy.classify(error) == .permanent)
    }
    for status in [429, 503] {
        precondition(WeatherRequestPolicy.classify(WeatherTransportFailure.http(status: status, retryAfter: nil)) == .overloaded)
    }
    for error: Error in [URLError(.timedOut), URLError(.dnsLookupFailed), URLError(.networkConnectionLost),
                         WeatherTransportFailure.http(status: 502, retryAfter: nil)] {
        precondition(WeatherRequestPolicy.classify(error) == .temporary)
    }
}

@MainActor
private func waitForResilientSettlement(_ fixture: ConsensusFixture, after cursor: Int) async {
    await fixture.requests.waitForLog(after: cursor) {
        $0.hasPrefix("weather.snapshot reason=settled ") && $0.contains("request_pending=false")
            && $0.contains("computation_pending=false") && $0.contains("demanded=1")
    }
}

@MainActor
private func requireNoPendingRequest(_ fixture: ConsensusFixture, total: Int) async {
    precondition(fixture.controller.diagnosticSnapshotSummary().contains("request_pending=false"))
    let count = await fixture.requests.requests.count
    precondition(count == total)
}

@MainActor
private func testResilientColdTimeouts() async {
    let fixture = ConsensusFixture(http: true, independentClock: true)
    defer { fixture.close() }
    fixture.start()
    await fixture.requests.waitForCount(3)
    var progress = false
    let marker = Task { @MainActor in progress = true }
    await marker.value
    precondition(progress && fixture.controller.diagnosticSnapshotSummary().contains("request_pending=true"),
                 "Pending source work must leave MainActor available")
    let delays: [Double] = [10, 45, 300, 900, 1_800]
    for (occurrence, delay) in delays.enumerated() {
        let cursor = await fixture.requests.logs.count
        for source in WeatherSource.allCases { await fixture.fail(source, occurrence: occurrence) }
        await waitForResilientSettlement(fixture, after: cursor)
        let tick = fixture.clock.tick
        precondition(fixture.schedule.entries[fixture.schedule.activeIndex].tick == tick + delay)
        fixture.controller.updateEvents([fixture.event, fixture.event])
        fixture.controller.refresh()
        await requireNoPendingRequest(fixture, total: (occurrence + 1) * 3)
        fixture.clock.advance(delay - 1)
        fixture.controller.refresh()
        await requireNoPendingRequest(fixture, total: (occurrence + 1) * 3)
        fixture.clock.advance(1)
        fixture.schedule.fireNext()
        await fixture.requests.waitForCount((occurrence + 2) * 3)
    }
    fixture.controller.shutdown()
    await fixture.requests.finishPending()
}

@MainActor
private func testResilientExpiredResponses() async {
    for directive in ["max-age=0", "no-cache", "no-store", "max-age=20"] {
        let fixture = ConsensusFixture(sources: [.openMeteo], http: true, independentClock: true)
        defer { fixture.close() }
        fixture.start()
        await fixture.requests.waitForCount(1)
        let cursor = await fixture.requests.logs.count
        await fixture.complete(.openMeteo, temperature: 14, headers: ["Cache-Control": directive, "ETag": "\"test-v1\""])
        await waitForResilientSettlement(fixture, after: cursor)
        if directive == "max-age=20" {
            precondition(fixture.controller.forecast(for: fixture.day)?.maximumTemperature == 14)
            fixture.clock.advance(20)
            fixture.schedule.fireNext()
            precondition(fixture.controller.forecast(for: fixture.day) == nil)
            await requireNoPendingRequest(fixture, total: 1)
            fixture.clock.advance(40)
        } else {
            precondition(fixture.controller.forecast(for: fixture.day) == nil)
            fixture.clock.advance(59)
            fixture.controller.refresh()
            await requireNoPendingRequest(fixture, total: 1)
            fixture.clock.advance(1)
        }
        fixture.schedule.fireNext()
        await fixture.requests.waitForCount(2)
        let conditional = await fixture.requests.request(.openMeteo, occurrence: 1)
        precondition((conditional.etag == nil) == (directive == "no-store"))
        let nextCursor = await fixture.requests.logs.count
        await fixture.complete(.openMeteo, occurrence: 1, temperature: 15, headers: ["Cache-Control": "max-age=0"])
        await waitForResilientSettlement(fixture, after: nextCursor)
        precondition(fixture.controller.forecast(for: fixture.day) == nil)
        let expected: Double = directive == "max-age=20" ? 60 : 300
        precondition(fixture.schedule.entries[fixture.schedule.activeIndex].tick == fixture.clock.tick + expected)
    }
}

private func consensusHTTPDate(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
    return formatter.string(from: date)
}

@MainActor
private func testResilient304Representations() async {
    let fixture = ConsensusFixture(sources: [.openMeteo], http: true, independentClock: true)
    defer { fixture.close() }
    fixture.start()
    await fixture.requests.waitForCount(1)
    let firstCursor = await fixture.requests.logs.count
    await fixture.complete(.openMeteo, temperature: 14, headers: ["Date": consensusHTTPDate(fixture.clock.date),
        "Cache-Control": "max-age=60", "ETag": "\"test-v1\""])
    await waitForResilientSettlement(fixture, after: firstCursor)
    precondition(fixture.controller.forecast(for: fixture.day)?.maximumTemperature == 14)
    fixture.clock.advance(60)
    fixture.schedule.fireNext()
    await fixture.requests.waitForCount(2)
    let sent = await fixture.requests.request(.openMeteo, occurrence: 1)
    precondition(sent.etag == "\"test-v1\"")
    let cursor = await fixture.requests.logs.count
    let validated = WeatherHTTPMetadata(headers: ["Date": consensusHTTPDate(fixture.clock.date), "ETag": "W/\"test-v1\""],
        receivedWall: fixture.clock.date, receivedTick: fixture.clock.tick)
    await fixture.fail(.openMeteo, occurrence: 1, error: WeatherTransportFailure.validated(validated))
    await waitForResilientSettlement(fixture, after: cursor)
    precondition(fixture.controller.forecast(for: fixture.day)?.maximumTemperature == 14,
                 "304 preserves explicit max-age and exact body")
    fixture.clock.advance(60)
    fixture.schedule.fireNext()
    await fixture.requests.waitForCount(3)
    let badCursor = await fixture.requests.logs.count
    let mismatch = WeatherHTTPMetadata(headers: ["ETag": "\"different\"", "Cache-Control": "max-age=600"],
        receivedWall: fixture.clock.date, receivedTick: fixture.clock.tick)
    await fixture.fail(.openMeteo, occurrence: 2, error: WeatherTransportFailure.validated(mismatch))
    await waitForResilientSettlement(fixture, after: badCursor)
    precondition(fixture.controller.forecast(for: fixture.day) == nil, "304 with a different validator cannot renew stale body")
    fixture.clock.advance(60)
    fixture.schedule.fireNext()
    await fixture.requests.waitForCount(4)
    let unconditional = await fixture.requests.request(.openMeteo, occurrence: 3)
    precondition(unconditional.etag == nil && unconditional.lastModified == nil)
    fixture.controller.shutdown()
    await fixture.requests.finishPending()

    let orphan = ConsensusFixture(sources: [.openMeteo], http: true, independentClock: true)
    defer { orphan.close() }
    orphan.start()
    await orphan.requests.waitForCount(1)
    for occurrence in 0..<2 {
        let cursor = await orphan.requests.logs.count
        let metadata = WeatherHTTPMetadata(headers: ["Cache-Control": "max-age=600", "ETag": "\"orphan\""],
            receivedWall: orphan.clock.date, receivedTick: orphan.clock.tick)
        await orphan.fail(.openMeteo, occurrence: occurrence, error: WeatherTransportFailure.validated(metadata))
        await waitForResilientSettlement(orphan, after: cursor)
        precondition(orphan.controller.forecast(for: orphan.day) == nil)
        let delay: Double = occurrence == 0 ? 60 : 300
        precondition(orphan.schedule.entries[orphan.schedule.activeIndex].tick == orphan.clock.tick + delay)
        orphan.clock.advance(delay)
        orphan.schedule.fireNext()
        await orphan.requests.waitForCount(occurrence + 2)
        let request = await orphan.requests.request(.openMeteo, occurrence: occurrence + 1)
        precondition(request.etag == nil && request.lastModified == nil)
    }
    orphan.controller.shutdown()
    await orphan.requests.finishPending()
}

@MainActor
private func testResilientServerGates() async {
    for status in [429, 503] {
        let fixture = ConsensusFixture(sources: [.openMeteo], http: true, independentClock: true)
        defer { fixture.close() }
        fixture.start()
        await fixture.requests.waitForCount(1)
        let cursor = await fixture.requests.logs.count
        let metadata = WeatherHTTPMetadata(headers: ["Retry-After": "900"], receivedWall: fixture.clock.date,
                                           receivedTick: fixture.clock.tick)
        await fixture.fail(.openMeteo, error: WeatherTransportFailure.httpMetadata(status: status, metadata: metadata))
        await waitForResilientSettlement(fixture, after: cursor)
        fixture.controller.setEnabled(false)
        fixture.clock.date = fixture.clock.date.addingTimeInterval(-7_200)
        fixture.controller.selectLocation(.city(.kazan))
        fixture.controller.setEnabled(true)
        await requireNoPendingRequest(fixture, total: 1)
        fixture.clock.advance(899)
        fixture.controller.refresh()
        await requireNoPendingRequest(fixture, total: 1)
        fixture.clock.advance(1)
        fixture.schedule.fireNext()
        await fixture.requests.waitForCount(2)
        fixture.controller.shutdown()
        await fixture.requests.finishPending()
    }
    // A response observed after cancellation still constrains this provider globally.
    let late = ConsensusFixture(sources: [.openMeteo], http: true, independentClock: true)
    defer { late.close() }
    late.start()
    await late.requests.waitForCount(1)
    late.controller.setEnabled(false)
    let cursor = await late.requests.logs.count
    let metadata = WeatherHTTPMetadata(headers: ["Retry-After": "120"], receivedWall: late.clock.date, receivedTick: late.clock.tick)
    await late.fail(.openMeteo, error: WeatherTransportFailure.httpMetadata(status: 429, metadata: metadata))
    await late.requests.waitForLog(after: cursor) { $0.hasPrefix("weather.server_gate source=openMeteo ") }
    late.controller.selectLocation(.city(.grozny))
    late.controller.setEnabled(true)
    late.clock.advance(299)
    late.controller.refresh()
    await requireNoPendingRequest(late, total: 1)
    late.clock.advance(1)
    late.schedule.fireNext()
    await late.requests.waitForCount(2)
    late.controller.shutdown()
    await late.requests.finishPending()
}

@MainActor
private final class ConsensusNetwork: WeatherNetworkMonitoring {
    var initial: WeatherNetworkState
    private(set) var starts = 0
    private(set) var stops = 0
    private var callbacks: [@MainActor @Sendable (WeatherNetworkState) -> Void] = []
    init(_ initial: WeatherNetworkState) { self.initial = initial }
    func start(_ update: @escaping @MainActor @Sendable (WeatherNetworkState) -> Void) {
        starts += 1
        callbacks.append(update)
        update(initial)
    }
    func stop() { stops += 1 }
    func send(_ state: WeatherNetworkState) { callbacks.last?(state) }
    func late(_ index: Int, _ state: WeatherNetworkState) { callbacks[index](state) }
}

@MainActor
private final class ConsensusEnergy { var low = false }

@MainActor
private func testResilientNetworkRecovery() async {
    let monitor = ConsensusNetwork(WeatherNetworkState(status: .offline))
    let fixture = ConsensusFixture(sources: [.openMeteo], http: true, network: monitor, independentClock: true)
    defer { fixture.close() }
    fixture.start()
    await requireNoPendingRequest(fixture, total: 0)
    precondition(monitor.starts == 1)
    fixture.controller.setEnabled(false)
    fixture.controller.setEnabled(true)
    monitor.late(0, WeatherNetworkState(status: .satisfied))
    await requireNoPendingRequest(fixture, total: 0)
    precondition(monitor.starts == 2 && monitor.stops == 1)
    monitor.send(WeatherNetworkState(status: .satisfied))
    fixture.clock.advance(1)
    fixture.controller.refresh()
    await requireNoPendingRequest(fixture, total: 0)
    fixture.clock.advance(1)
    fixture.schedule.fireNext()
    await fixture.requests.waitForCount(1)
    monitor.send(WeatherNetworkState(status: .offline))
    let cursor = await fixture.requests.logs.count
    await fixture.fail(.openMeteo)
    await waitForResilientSettlement(fixture, after: cursor)
    fixture.clock.advance(120)
    fixture.controller.refresh()
    await requireNoPendingRequest(fixture, total: 1)
    monitor.send(WeatherNetworkState(status: .satisfied))
    monitor.send(WeatherNetworkState(status: .satisfied))
    fixture.clock.advance(2)
    fixture.schedule.fireNext()
    await fixture.requests.waitForCount(2)
    let recoveredCursor = await fixture.requests.logs.count
    // A satisfied path, including a VPN path, does not make the HTTP request succeed.
    await fixture.fail(.openMeteo, occurrence: 1)
    await waitForResilientSettlement(fixture, after: recoveredCursor)
    precondition(fixture.controller.forecast(for: fixture.day) == nil)
    precondition(fixture.schedule.entries[fixture.schedule.activeIndex].tick == fixture.clock.tick + 10)
    monitor.send(WeatherNetworkState(status: .satisfied, expensive: true))
    fixture.clock.advance(10)
    fixture.schedule.fireNext()
    await requireNoPendingRequest(fixture, total: 2)
    monitor.send(WeatherNetworkState(status: .satisfied))
    fixture.controller.refresh()
    await requireNoPendingRequest(fixture, total: 2)
    precondition(fixture.schedule.entries[fixture.schedule.activeIndex].tick == fixture.clock.tick + 890,
                 "Cost transitions retain the next900-second ordinary backoff step")
    fixture.clock.advance(890)
    fixture.schedule.fireNext()
    await fixture.requests.waitForCount(3)
    let thirdCursor = await fixture.requests.logs.count
    await fixture.fail(.openMeteo, occurrence: 2)
    await waitForResilientSettlement(fixture, after: thirdCursor)
    precondition(fixture.schedule.entries[fixture.schedule.activeIndex].tick == fixture.clock.tick + 45,
                 "Network/cost transitions cannot reset the used fast-retry budget")
    fixture.controller.shutdown()
    precondition(monitor.stops == 2)
    monitor.late(1, WeatherNetworkState(status: .satisfied))
    await requireNoPendingRequest(fixture, total: 3)
}

@MainActor
private func testResilientEnergyLimits() async {
    for mode in 0..<3 {
        let energy = ConsensusEnergy()
        energy.low = mode == 2
        let monitor = ConsensusNetwork(WeatherNetworkState(status: .satisfied, expensive: mode == 0, constrained: mode == 1))
        let fixture = ConsensusFixture(sources: [.openMeteo], http: true, network: monitor,
                                       lowPower: { energy.low }, independentClock: true)
        defer { fixture.close() }
        fixture.start()
        await fixture.requests.waitForCount(1)
        let cursor = await fixture.requests.logs.count
        await fixture.fail(.openMeteo)
        await waitForResilientSettlement(fixture, after: cursor)
        precondition(fixture.schedule.entries[fixture.schedule.activeIndex].tick == fixture.clock.tick + 300)
        energy.low = false
        monitor.send(WeatherNetworkState(status: .satisfied))
        fixture.clock.advance(299)
        fixture.controller.refresh()
        await requireNoPendingRequest(fixture, total: 1)
        fixture.clock.advance(1)
        fixture.schedule.fireNext()
        await fixture.requests.waitForCount(2)
        fixture.controller.shutdown()
        await fixture.requests.finishPending()
    }
}

@MainActor
private func testResilientClockPreservesFailureBackoff() async {
    for status in [404, 500] {
        for partial in [nil, false, true] as [Bool?] {
            let fixture = ConsensusFixture(sources: [.openMeteo], http: true, lowPower: { true }, independentClock: true)
            defer { fixture.close() }
            fixture.start()
            await fixture.requests.waitForCount(1)
            let occurrence: Int
            if let partial {
                let cursor = await fixture.requests.logs.count
                await fixture.complete(.openMeteo, temperature: 14, partial: partial, headers: ["Cache-Control": "max-age=600"])
                await waitForResilientSettlement(fixture, after: cursor)
                fixture.clock.advance(600)
                fixture.schedule.fireNext()
                await fixture.requests.waitForCount(2)
                occurrence = 1
            } else { occurrence = 0 }
            let cursor = await fixture.requests.logs.count
            await fixture.fail(.openMeteo, occurrence: occurrence, error: WeatherTransportFailure.http(status: status, retryAfter: nil))
            await waitForResilientSettlement(fixture, after: cursor)
            let delay: TimeInterval = status == 404 ? 1_800 : 300
            let deadline = fixture.clock.tick + delay
            precondition(fixture.schedule.entries[fixture.schedule.activeIndex].tick == deadline)
            fixture.clock.date = fixture.clock.date.addingTimeInterval(-7_200)
            fixture.controller.refresh()
            precondition(fixture.controller.forecast(for: fixture.day) == nil)
            precondition(fixture.schedule.entries[fixture.schedule.activeIndex].tick == deadline,
                         "Clock rollback must preserve failure backoff, including retained full/partial bodies")
            fixture.clock.advance(delay - 1)
            fixture.controller.refresh()
            await requireNoPendingRequest(fixture, total: occurrence + 1)
            fixture.clock.advance(1)
            fixture.schedule.fireNext()
            await fixture.requests.waitForCount(occurrence + 2)
            fixture.controller.shutdown()
            await fixture.requests.finishPending()
        }
    }
}

@MainActor
private func testResilientClockAndMidnight() async {
    let fixture = ConsensusFixture(sources: [.openMeteo], http: true, independentClock: true)
    defer { fixture.close() }
    fixture.start()
    await fixture.requests.waitForCount(1)
    let cursor = await fixture.requests.logs.count
    await fixture.complete(.openMeteo, temperature: 14, headers: ["Cache-Control": "max-age=600", "ETag": "\"clock-v1\""])
    await waitForResilientSettlement(fixture, after: cursor)
    fixture.clock.date = fixture.clock.date.addingTimeInterval(7_200)
    precondition(fixture.controller.forecast(for: fixture.day) == nil, "Clock discontinuity makes freshness doubtful immediately")
    let doubtful = fixture.controller.diagnosticSnapshotSummary()
    precondition(doubtful.contains("usable=0") && doubtful.contains("fresh_sources=0") && doubtful.contains("clock_consistent=false"),
                 "A read-only snapshot must agree with the getter before refresh observes a wall-clock discontinuity")
    fixture.controller.refresh()
    await requireNoPendingRequest(fixture, total: 1)
    precondition(fixture.schedule.entries[fixture.schedule.activeIndex].tick == fixture.clock.tick + 60)
    fixture.clock.advance(60)
    fixture.schedule.fireNext()
    await fixture.requests.waitForCount(2)
    let oldWall = fixture.clock.date
    let oldTick = fixture.clock.tick
    fixture.clock.date = fixture.clock.date.addingTimeInterval(-14_400)
    fixture.controller.refresh()
    let nextCursor = await fixture.requests.logs.count
    let query = await fixture.requests.request(.openMeteo, occurrence: 1).query
    let key = weatherDayKey(fixture.day)
    let sample = WeatherDailySample(dayKey: key, period: query.interval(for: key)!, maximumTemperature: 50, condition: .rain)
    let queuedBeforeJump = WeatherHTTPMetadata(headers: ["Cache-Control": "max-age=600"], receivedWall: oldWall, receivedTick: oldTick)
    await fixture.requests.complete(.openMeteo, occurrence: 1,
        result: .success(WeatherSourceBatch(forecasts: [key: sample], http: queuedBeforeJump)))
    await waitForResilientSettlement(fixture, after: nextCursor)
    precondition(fixture.controller.forecast(for: fixture.day) == nil, "A queued pre-jump response cannot restore doubtful freshness")
    fixture.clock.advance(60)
    fixture.schedule.fireNext()
    await fixture.requests.waitForCount(3)
    let freshCursor = await fixture.requests.logs.count
    await fixture.complete(.openMeteo, occurrence: 2, temperature: 15, headers: ["Cache-Control": "max-age=600"])
    await waitForResilientSettlement(fixture, after: freshCursor)
    precondition(fixture.controller.forecast(for: fixture.day)?.maximumTemperature == 15)
    fixture.clock.advance(3_600)
    for _ in 0..<10 { fixture.controller.refresh() }
    await fixture.requests.waitForCount(4)
    let total = await fixture.requests.requests.count
    precondition(total == 4 && fixture.controller.forecast(for: fixture.day) == nil, "Wake refresh coalesces missed deadlines without catch-up")
    fixture.controller.shutdown()
    await fixture.requests.finishPending()

    let midnight = ConsensusFixture(sources: [.openMeteo], http: true, independentClock: true)
    defer { midnight.close() }
    let nextDay = Day(Day.calendar.date(byAdding: .day, value: 1, to: midnight.day.date())!)
    let event = Countdown(title: "Future midnight demand", date: nextDay, emoji: "", showsWeather: true)
    midnight.controller.updateEvents([event])
    midnight.controller.setEnabled(true)
    await midnight.requests.waitForCount(1)
    let firstCursor = await midnight.requests.logs.count
    await midnight.complete(.openMeteo, temperature: 10, headers: ["Cache-Control": "max-age=600", "ETag": "\"old-range\""])
    await waitForResilientSettlement(midnight, after: firstCursor)
    midnight.clock.advance(43_200)
    midnight.controller.updateEvents([event])
    await midnight.requests.waitForCount(2)
    let newRequest = await midnight.requests.request(.openMeteo, occurrence: 1)
    precondition(newRequest.query.startDay == nextDay && newRequest.etag == nil,
                 "Midnight uses a new exact range rather than validating another representation")
    midnight.controller.shutdown()
    await midnight.requests.finishPending()
}

@MainActor
private func testResilientSyntheticEpisode() async {
    let fixture = ConsensusFixture(http: true, independentClock: true)
    defer { fixture.close() }
    fixture.start()
    await fixture.requests.waitForCount(3)
    let cursor = await fixture.requests.logs.count
    await fixture.complete(.metNorway, temperature: 42, headers: [
        "Date": consensusHTTPDate(fixture.clock.date),
        "Expires": consensusHTTPDate(fixture.clock.date.addingTimeInterval(-10)),
    ])
    await fixture.fail(.openMeteo)
    await fixture.fail(.wttr)
    await waitForResilientSettlement(fixture, after: cursor)
    precondition(fixture.controller.forecast(for: fixture.day) == nil)
    precondition(fixture.schedule.entries[fixture.schedule.activeIndex].tick == fixture.clock.tick + 10)
    fixture.clock.advance(10)
    fixture.schedule.fireNext()
    await fixture.requests.waitForCount(5)
    let earlyCursor = await fixture.requests.logs.count
    await fixture.complete(.wttr, occurrence: 1, temperature: 9, headers: ["Cache-Control": "max-age=1800"])
    await fixture.requests.waitForLog(after: earlyCursor) { $0 == "weather.publication demanded=1 usable=1" }
    precondition(fixture.controller.forecast(for: fixture.day)?.maximumTemperature == 9)
    precondition(fixture.controller.diagnosticSnapshotSummary().contains("request_pending=true"),
                 "Early useful success must publish while another source is still pending")
    let lateCursor = await fixture.requests.logs.count
    await fixture.complete(.openMeteo, occurrence: 1, temperature: 15, headers: ["Cache-Control": "max-age=1800"])
    await waitForResilientSettlement(fixture, after: lateCursor)
    precondition(fixture.controller.forecast(for: fixture.day)?.maximumTemperature == 12)
    fixture.clock.advance(50)
    fixture.schedule.fireNext()
    await fixture.requests.waitForCount(6)
    let metCount = await fixture.requests.count(.metNorway)
    precondition(metCount == 2, "Already-expired200 rechecks at60s without refreshing useful sources")
    let secondCursor = await fixture.requests.logs.count
    await fixture.complete(.metNorway, occurrence: 1, temperature: 50, headers: ["Cache-Control": "max-age=0"])
    await waitForResilientSettlement(fixture, after: secondCursor)
    precondition(fixture.controller.forecast(for: fixture.day)?.maximumTemperature == 12)
    precondition(fixture.schedule.entries[fixture.schedule.activeIndex].tick == fixture.clock.tick + 300)
}

@MainActor
private func testResilientCancellationDoesNotRetry() async {
    let fixture = ConsensusFixture(sources: [.openMeteo], http: true, independentClock: true)
    defer { fixture.close() }
    fixture.start()
    await fixture.requests.waitForCount(1)
    let cursor = await fixture.requests.logs.count
    await fixture.fail(.openMeteo, error: CancellationError())
    await waitForResilientSettlement(fixture, after: cursor)
    fixture.clock.advance(300)
    fixture.controller.refresh()
    await requireNoPendingRequest(fixture, total: 1)
    precondition(fixture.schedule.entries.allSatisfy { $0.cancelled || $0.fired })
    precondition(fixture.controller.diagnosticSnapshotSummary().contains("failed_sources=0"))
    fixture.controller.setEnabled(false)
    fixture.controller.setEnabled(true)
    await fixture.requests.waitForCount(2)
    fixture.controller.shutdown()
    await fixture.requests.finishPending()
}

@MainActor
private func testResilientOfflineExpiry() async {
    let monitor = ConsensusNetwork(WeatherNetworkState(status: .satisfied))
    let fixture = ConsensusFixture(sources: [.openMeteo], http: true, network: monitor, independentClock: true)
    defer { fixture.close() }
    fixture.start()
    await fixture.requests.waitForCount(1)
    let cursor = await fixture.requests.logs.count
    await fixture.complete(.openMeteo, temperature: 14, headers: ["Cache-Control": "max-age=20"])
    await waitForResilientSettlement(fixture, after: cursor)
    precondition(fixture.controller.forecast(for: fixture.day) != nil)
    monitor.send(WeatherNetworkState(status: .offline))
    fixture.clock.advance(20)
    fixture.schedule.fireNext()
    precondition(fixture.controller.forecast(for: fixture.day) == nil, "Offline must retain the freshness-expiry action")
    await requireNoPendingRequest(fixture, total: 1)
    monitor.send(WeatherNetworkState(status: .satisfied))
    fixture.clock.advance(2)
    fixture.schedule.fireNext()
    await requireNoPendingRequest(fixture, total: 1)
    fixture.clock.advance(38)
    fixture.schedule.fireNext()
    await fixture.requests.waitForCount(2)
    fixture.controller.shutdown()
    await fixture.requests.finishPending()
}
