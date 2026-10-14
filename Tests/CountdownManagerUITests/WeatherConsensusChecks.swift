import CountdownCore
import CountdownManagerUI
import Foundation

private actor ConsensusRequests {
    struct Request: Sendable {
        let source: WeatherSource
        let query: WeatherQuery
        let lastModified: String?
    }
    private(set) var requests: [Request] = []
    private(set) var cancelled = Set<Int>()
    private var pending: [Int: CheckedContinuation<WeatherSourceBatch, Error>] = [:]

    func fetch(_ source: WeatherSource, query: WeatherQuery, lastModified: String?) async throws -> WeatherSourceBatch {
        let index = requests.count
        requests.append(Request(source: source, query: query, lastModified: lastModified))
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { pending[index] = $0 }
        } onCancel: {
            Task { await self.cancel(index) }
        }
    }

    private func cancel(_ index: Int) { cancelled.insert(index) }

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
        entries.append(Entry(deadline: clock.date.addingTimeInterval(delay), action: action))
        return { [weak self] in self?.entries[index].cancelled = true }
    }

    var activeIndex: Int {
        entries.indices.filter { !entries[$0].cancelled && !entries[$0].fired }
            .min { entries[$0].deadline < entries[$1].deadline }!
    }

    func fireNext() {
        let index = activeIndex
        precondition(entries[index].deadline <= clock.date)
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

    init(sources: [WeatherSource] = WeatherSource.allCases, computation: WeatherConsensusComputation? = nil) {
        schedule = ConsensusSchedule(clock: clock)
        defaults = UserDefaults(suiteName: suite)!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = WeatherCity.moscow.timeZone
        day = Day(clock.date, calendar: calendar)
        event = Countdown(title: "Consensus fixture", date: day, emoji: "", showsWeather: true)
        let requests = requests
        let clock = clock
        let schedule = schedule
        controller = WeatherController(
            defaults: defaults,
            sourceProvider: { try await requests.fetch($0, query: $1, lastModified: $2) }, sources: sources,
            locationProvider: ConsensusLocation(), allowLocationRequests: false, now: { clock.date },
            scheduler: { schedule.schedule($0, action: $1) }, consensusComputation: computation
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
        partial: Bool = false
    ) async {
        let request = await requests.request(source, occurrence: occurrence)
        let key = weatherDayKey(day)
        let fullPeriod = request.query.interval(for: key)!
        let period = partial ? DateInterval(start: fullPeriod.start.addingTimeInterval(43_200), end: fullPeriod.end) : fullPeriod
        let sample = WeatherDailySample(dayKey: key, period: period, maximumTemperature: temperature, condition: category)
        await requests.complete(source, occurrence: occurrence, result: .success(WeatherSourceBatch(
            forecasts: [key: sample], expiresAt: expiry, lastModified: modified
        )))
    }

    func fail(_ source: WeatherSource, occurrence: Int = 0, error: Error = WeatherProviderFailure.response) async {
        await requests.complete(source, occurrence: occurrence, result: .failure(error))
    }
}

@MainActor
private func waitForConsensus(_ predicate: () async -> Bool) async {
    for _ in 0..<1_000 {
        if await predicate() { return }
        await Task.yield()
    }
    preconditionFailure("Consensus fixture did not reach its expected state")
}

@MainActor
private func settleConsensus() async {
    for _ in 0..<32 { await Task.yield() }
}

@MainActor
func testWeatherConsensusLifecycle() async throws {
    testWeatherHTTPDates()
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
    await fixture.complete(.openMeteo, temperature: 10, expiry: start.addingTimeInterval(60))
    await fixture.complete(.metNorway, temperature: 20, expiry: start.addingTimeInterval(3_600))
    await waitForConsensus { fixture.controller.forecast(for: fixture.day)?.maximumTemperature == 15 }
    await settleConsensus()
    fixture.clock.date = start.addingTimeInterval(60)
    fixture.schedule.fireNext()
    await waitForConsensus { fixture.controller.forecast(for: fixture.day)?.maximumTemperature == 20 }
    await settleConsensus()
    let count = await fixture.requests.requests.count
    precondition(count == 2, "Earlier expiry hides A without violating the 30-minute request floor")
    fixture.clock.date = start.addingTimeInterval(1_800)
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
    private var pending: [Int: CheckedContinuation<[String: WeatherConsensus], Error>] = [:]

    func compute(_ batches: [WeatherSource: WeatherSourceBatch], _ query: WeatherQuery,
                 _ demand: Set<String>) async throws -> [String: WeatherConsensus] {
        let index = inputs.count
        inputs.append(Input(batches: batches, query: query, demand: demand))
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { pending[index] = $0 }
        } onCancel: {
            Task { await self.recordCancellation(index) }
        }
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
            await waitForConsensus { await computations.inputs.count == 1 }
            fixture.controller.updateEvents([second])
            await waitForConsensus { await computations.inputs.count == 2 }
            await computations.complete(0)
            await settleConsensus()
            precondition(fixture.controller.forecast(for: secondDay) == nil && fixture.controller.forecast(for: fixture.day) == nil)
            await computations.complete(1)
            await waitForConsensus { fixture.controller.forecast(for: secondDay)?.maximumTemperature == 10 }
        } else if source == .metNorway {
            await waitForConsensus { await computations.inputs.count == 3 }
        } else {
            await waitForConsensus { await computations.inputs.count == 4 }
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
