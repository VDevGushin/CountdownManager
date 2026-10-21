import CountdownCore
import CountdownManagerUI
import Foundation

private func workflowDeadline(_ label: String, file: StaticString, line: UInt) -> Task<Void, Never> {
    Task {
        do { try await Task.sleep(for: .seconds(5)) } catch { return }
        preconditionFailure("Async workflow barrier did not arrive: \(label)", file: file, line: line)
    }
}

private actor WorkflowWeatherRequests {
    struct Request: Sendable {
        let query: WeatherQuery
        let continuation: CheckedContinuation<WeatherSourceBatch, Error>
    }
    private var requests: [Request] = []
    private var waiting: [(Int, CheckedContinuation<Void, Never>)] = []

    func fetch(_ query: WeatherQuery) async throws -> WeatherSourceBatch {
        // A deliberately non-cooperating provider lets the receiving controller reject late outcomes.
        try await withCheckedThrowingContinuation { continuation in
            requests.append(Request(query: query, continuation: continuation))
            let ready = waiting.filter { $0.0 <= requests.count }
            waiting.removeAll { $0.0 <= requests.count }
            ready.forEach { $0.1.resume() }
        }
    }

    func waitForCount(_ count: Int, file: StaticString = #fileID, line: UInt = #line) async {
        let deadline = workflowDeadline("request \(count)", file: file, line: line)
        defer { deadline.cancel() }
        if requests.count < count { await withCheckedContinuation { waiting.append((count, $0)) } }
        precondition(requests.count == count, "Unexpected duplicate workflow requests", file: file, line: line)
    }

    func query(_ index: Int) -> WeatherQuery { requests[index].query }
    func requestCount() -> Int { requests.count }

    func complete(_ index: Int, temperatures: [String: Double]) {
        let query = requests[index].query
        let forecasts = temperatures.reduce(into: [String: WeatherDailySample]()) { result, entry in
            result[entry.key] = WeatherDailySample(dayKey: entry.key, period: query.interval(for: entry.key)!,
                                                  maximumTemperature: entry.value, condition: .clear)
        }
        requests[index].continuation.resume(returning: WeatherSourceBatch(forecasts: forecasts))
    }

    func fail(_ index: Int, error: Error) { requests[index].continuation.resume(throwing: error) }
}

private final class WorkflowWeatherRecords: @unchecked Sendable {
    private let lock = NSLock()
    private var logs: [String] = []
    private var waiters: [(Int, @Sendable (String) -> Bool, CheckedContinuation<Void, Never>)] = []

    func cursor() -> Int {
        lock.lock()
        defer { lock.unlock() }
        return logs.count
    }

    func record(_ message: String) {
        lock.lock()
        logs.append(message)
        let ready = waiters.filter { logs.count > $0.0 && $0.1(message) }
        waiters.removeAll { logs.count > $0.0 && $0.1(message) }
        lock.unlock()
        ready.forEach { $0.2.resume() }
    }

    func waitForLog(after cursor: Int, file: StaticString = #fileID, line: UInt = #line,
                    matching predicate: @escaping @Sendable (String) -> Bool) async {
        let deadline = workflowDeadline("diagnostic after \(cursor)", file: file, line: line)
        defer { deadline.cancel() }
        await withCheckedContinuation { continuation in
            lock.lock()
            if logs.dropFirst(cursor).contains(where: predicate) {
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append((cursor, predicate, continuation))
                lock.unlock()
            }
        }
    }

    func waitForAvailable(after cursor: Int, usable: Int = 1, file: StaticString = #fileID, line: UInt = #line) async {
        await waitForLog(after: cursor, file: file, line: line) {
            $0.hasPrefix("weather.snapshot reason=settled result=available ") && $0.contains("usable=\(usable) ")
                && $0.contains("request_pending=false ") && $0.contains("computation_pending=false ")
        }
    }
}

@MainActor
private final class WorkflowWeatherLocation: WeatherLocationProviding {
    func request(allowPrompt: Bool, _ completion: @escaping (Result<WeatherCoordinates, WeatherLocationFailure>) -> Void) {
        preconditionFailure("Manual workflow fixtures must not request native location")
    }
    func cancel() {}
}

@MainActor
private final class WorkflowWeatherFixture {
    let requests = WorkflowWeatherRequests()
    let records = WorkflowWeatherRecords()
    let controller: WeatherController
    let first: Countdown
    let second: Countdown
    let defaults: UserDefaults
    let suite = "local.countdownmanager.async-workflow.\(UUID().uuidString)"

    init() {
        let date = ISO8601DateFormatter().date(from: "2026-10-14T09:00:00Z")!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = WeatherCity.moscow.timeZone
        let day = Day(date, calendar: calendar)
        let tomorrow = Day(calendar.date(byAdding: .day, value: 1, to: day.date(calendar: calendar))!, calendar: calendar)
        first = Countdown(title: "First workflow event", date: day, emoji: "", showsWeather: true)
        second = Countdown(title: "Second workflow event", date: tomorrow, emoji: "", showsWeather: true)
        defaults = UserDefaults(suiteName: suite)!
        let requests = requests
        let records = records
        controller = WeatherController(
            defaults: defaults, sourceProvider: { _, query, _ in try await requests.fetch(query) },
            sources: [.openMeteo], locationProvider: WorkflowWeatherLocation(), allowLocationRequests: false,
            now: { date }, monotonicNow: { 100 }, jitter: { 0 }, scheduler: { _, _ in {} },
            diagnostics: WeatherDiagnostics { records.record($0) }
        )
        controller.selectLocation(.city(.moscow))
    }

    func start(_ events: [Countdown]) {
        controller.updateEvents(events)
        controller.setEnabled(true)
    }

    func close() {
        controller.shutdown()
        defaults.removePersistentDomain(forName: suite)
    }
}

@MainActor
func testAsyncWorkflowRegressions() async {
    await testWeatherEditsReuseSharedBatch()
    await testWeatherLocationRoundTripDuringRequest()
    await testWeatherReenableDuringRequest()
    print("Async workflow regression checks passed (3 workflows)")
}

@MainActor
private func testWeatherEditsReuseSharedBatch() async {
    let fixture = WorkflowWeatherFixture()
    defer { fixture.close() }
    let firstKey = weatherDayKey(fixture.first.date)
    let secondKey = weatherDayKey(fixture.second.date)
    fixture.start([fixture.first])
    await fixture.requests.waitForCount(1)

    // Editing the same event's date must retarget the existing batch, without another GET.
    var edited = fixture.first
    edited.date = fixture.second.date
    fixture.controller.updateEvents([edited])
    let cursor = fixture.records.cursor()
    await fixture.requests.complete(0, temperatures: [firstKey: 10, secondKey: 22])
    await fixture.records.waitForAvailable(after: cursor)
    precondition(fixture.controller.forecast(for: fixture.first.date) == nil)
    precondition(fixture.controller.forecast(for: fixture.second.date)?.maximumTemperature == 22)

    // A distinct new event should reveal a cached date without recreating the moved event.
    var additional = fixture.second
    additional.date = fixture.first.date
    precondition(additional.id != edited.id)
    let expanded = fixture.records.cursor()
    fixture.controller.updateEvents([additional, edited])
    await fixture.records.waitForAvailable(after: expanded, usable: 2)
    precondition(fixture.controller.forecast(for: fixture.first.date)?.maximumTemperature == 10)
    precondition(fixture.controller.forecast(for: fixture.second.date)?.maximumTemperature == 22)

    // Turning one event OFF removes only that date; restoring it reuses fresh shared data.
    var disabled = edited
    disabled.showsWeather = false
    fixture.controller.updateEvents([additional, disabled])
    precondition(fixture.controller.forecast(for: fixture.second.date) == nil)
    let restored = fixture.records.cursor()
    fixture.controller.updateEvents([additional, edited])
    await fixture.records.waitForAvailable(after: restored, usable: 2)
    let count = await fixture.requests.requestCount()
    precondition(count == 1, "Date/flag edits and warm-cache demand expansion must not duplicate a batch")
    precondition(fixture.controller.forecast(for: fixture.second.date)?.maximumTemperature == 22)
}

@MainActor
private func testWeatherLocationRoundTripDuringRequest() async {
    let fixture = WorkflowWeatherFixture()
    defer { fixture.close() }
    let key = weatherDayKey(fixture.first.date)
    fixture.start([fixture.first])
    await fixture.requests.waitForCount(1)
    fixture.controller.selectLocation(.city(.kazan))
    await fixture.requests.waitForCount(2)
    fixture.controller.selectLocation(.city(.moscow))
    await fixture.requests.waitForCount(3)
    let queries = await [fixture.requests.query(0), fixture.requests.query(1), fixture.requests.query(2)]
    precondition(queries[0] == queries[2] && queries[0].coordinates != queries[1].coordinates)

    // The old Moscow generation has the same cache key as the replacement but no mutation authority.
    let old = fixture.records.cursor()
    await fixture.requests.fail(0, error: WeatherTransportFailure.http(status: 429, retryAfter: nil))
    await fixture.records.waitForLog(after: old) { $0.hasPrefix("weather.server_gate source=openMeteo ") }
    precondition(fixture.controller.forecast(for: fixture.first.date) == nil)
    precondition(fixture.controller.diagnosticSnapshotSummary().contains("request_pending=true"))
    // Release the cancelled city continuation; it is not a settlement or cache-rejection barrier.
    await fixture.requests.complete(1, temperatures: [key: 60])
    fixture.controller.refresh()
    let current = fixture.records.cursor()
    await fixture.requests.complete(2, temperatures: [key: 12])
    await fixture.records.waitForAvailable(after: current)
    precondition(fixture.controller.forecast(for: fixture.first.date)?.maximumTemperature == 12)
    let count = await fixture.requests.requestCount()
    precondition(count == 3, "An old group must not release the replacement request owner or duplicate its GET")
}

@MainActor
private func testWeatherReenableDuringRequest() async {
    let fixture = WorkflowWeatherFixture()
    defer { fixture.close() }
    let key = weatherDayKey(fixture.first.date)
    fixture.start([fixture.first])
    await fixture.requests.waitForCount(1)
    fixture.controller.setEnabled(false)
    fixture.controller.setEnabled(true)
    await fixture.requests.waitForCount(2)
    let old = fixture.records.cursor()
    await fixture.requests.fail(0, error: WeatherTransportFailure.http(status: 503, retryAfter: nil))
    await fixture.records.waitForLog(after: old) { $0.hasPrefix("weather.server_gate source=openMeteo ") }
    precondition(fixture.controller.enabled && fixture.controller.forecast(for: fixture.first.date) == nil)
    precondition(fixture.controller.diagnosticSnapshotSummary().contains("request_pending=true"))
    fixture.controller.refresh()
    let current = fixture.records.cursor()
    await fixture.requests.complete(1, temperatures: [key: 18])
    await fixture.records.waitForAvailable(after: current)
    precondition(fixture.controller.forecast(for: fixture.first.date)?.maximumTemperature == 18)
    let count = await fixture.requests.requestCount()
    precondition(count == 2, "An OFF generation cannot release or overwrite the new ON request")
}
