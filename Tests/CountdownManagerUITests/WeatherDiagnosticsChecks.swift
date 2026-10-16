import CountdownCore
import CountdownManagerUI
import Foundation

private final class WeatherDiagnosticRecords: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [String] = []

    var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return messages
    }

    func record(_ message: String) {
        lock.lock()
        defer { lock.unlock() }
        messages.append(message)
    }

    var diagnostics: WeatherDiagnostics { WeatherDiagnostics { self.record($0) } }
}

private final class WeatherDiagnosticReply: @unchecked Sendable {
    enum Value {
        case response(URLResponse, Data)
        case failure(NSError)
        case partialFailure(URLResponse, Data, NSError)
    }

    private let lock = NSLock()
    private var value: Value?

    func install(_ value: Value) {
        lock.lock()
        defer { lock.unlock() }
        self.value = value
    }

    func read() -> Value {
        lock.lock()
        defer { lock.unlock() }
        guard let value else { preconditionFailure("Missing isolated weather reply") }
        return value
    }
}

private final class WeatherDiagnosticURLProtocol: URLProtocol {
    static let reply = WeatherDiagnosticReply()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        switch Self.reply.read() {
        case let .response(response, data):
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        case let .failure(error):
            client?.urlProtocol(self, didFailWithError: error)
        case let .partialFailure(response, data, error):
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private let weatherPrivateSentinels = [
    "private-weather.invalid", "latitude=12.34", "longitude=56.78", "12.34", "56.78",
    String(WeatherCity.moscow.coordinates.latitude), String(WeatherCity.moscow.coordinates.longitude),
    "moscow", "Москва", "Europe/Moscow",
    "PRIVATE_CITY", "PRIVATE_EVENT_TITLE", "PRIVATE_BODY", "PRIVATE_ERROR_DOMAIN",
]

private func hostileWeatherError(code: Int, domain: String = NSURLErrorDomain) -> NSError {
    let text = weatherPrivateSentinels.joined(separator: " ")
    let url = URL(string: "https://private-weather.invalid/PRIVATE_BODY?latitude=12.34&longitude=56.78")!
    return NSError(domain: domain, code: code, userInfo: [
        NSLocalizedDescriptionKey: text,
        NSLocalizedFailureReasonErrorKey: text,
        NSLocalizedRecoverySuggestionErrorKey: text,
        NSURLErrorFailingURLErrorKey: url,
        NSURLErrorFailingURLStringErrorKey: url.absoluteString,
        NSUnderlyingErrorKey: NSError(domain: "PRIVATE_ERROR_DOMAIN", code: 99, userInfo: [NSLocalizedDescriptionKey: text]),
        "body": text,
        "event_title": "PRIVATE_EVENT_TITLE",
    ])
}

private func requirePrivateWeatherLogs(_ records: WeatherDiagnosticRecords) {
    let text = records.lines.joined(separator: "\n")
    precondition(!text.isEmpty, "Privacy assertions require actual emitted diagnostic records")
    for sentinel in weatherPrivateSentinels {
        precondition(!text.contains(sentinel), "Weather diagnostics leaked a private sentinel")
    }
    precondition(!text.contains("https://") && !text.contains("http://"))
}

private func diagnosticFields(_ line: String) -> [String: String] {
    Dictionary(line.split(separator: " ").dropFirst().compactMap { item in
        let pair = item.split(separator: "=", maxSplits: 1)
        return pair.count == 2 ? (String(pair[0]), String(pair[1])) : nil
    }, uniquingKeysWith: { _, last in last })
}

private func diagnosticQuery() -> WeatherQuery {
    let calendar = Calendar(identifier: .gregorian)
    let day = Day(DateComponents(calendar: calendar, year: 2026, month: 10, day: 14).date!, calendar: calendar)
    return WeatherQuery(coordinates: WeatherCoordinates(latitude: 12.34, longitude: 56.78)!,
                        timeZone: TimeZone(secondsFromGMT: 0)!, startDay: day, dayCount: 1)!
}

private func diagnosticOpenMeteoData(
    _ query: WeatherQuery, unit: String = "°C", temperature: Bool = true, condition: Bool = true
) throws -> Data {
    var daily: [String: Any] = ["time": query.dayKeys]
    if temperature { daily["temperature_2m_max"] = [14] }
    if condition { daily["weather_code"] = [0] }
    return try JSONSerialization.data(withJSONObject: [
        "timezone": query.timeZone.identifier, "utc_offset_seconds": 0,
        "daily_units": ["time": "iso8601", "weather_code": "wmo code", "temperature_2m_max": unit],
        "daily": daily,
        "private_body": weatherPrivateSentinels.joined(separator: " "),
    ])
}

private func diagnosticHTTP(_ status: Int) -> HTTPURLResponse {
    HTTPURLResponse(url: URL(string: "https://private-weather.invalid/PRIVATE_BODY")!,
                    statusCode: status, httpVersion: "HTTP/1.1",
                    headerFields: ["Last-Modified": "PRIVATE_BODY", "X-Private": "PRIVATE_EVENT_TITLE"])!
}

private func checkDiagnosticFetch(
    source: WeatherSource = .openMeteo, query: WeatherQuery,
    reply: WeatherDiagnosticReply.Value, expected: [String: String], succeeds: Bool
) async {
    let records = WeatherDiagnosticRecords()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [WeatherDiagnosticURLProtocol.self]
    configuration.urlCache = nil
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    WeatherDiagnosticURLProtocol.reply.install(reply)
    do {
        _ = try await WeatherTransport.fetch(source, query: query, diagnostics: records.diagnostics, session: session)
        precondition(succeeds, "Expected transport failure")
    } catch {
        precondition(!succeeds, "Expected transport success")
    }
    let starts = records.lines.filter { $0.hasPrefix("weather.request.start ") }
    let ends = records.lines.filter { $0.hasPrefix("weather.request.end ") }
    precondition(starts.count == 1 && ends.count == 1, "Every request must emit one paired completion")
    let start = diagnosticFields(starts[0])
    let end = diagnosticFields(ends[0])
    precondition(start["source"] == source.rawValue && end["source"] == source.rawValue)
    precondition(start["request"] == end["request"] && UUID(uuidString: end["request"] ?? "") != nil)
    precondition(Int(end["duration_ms"] ?? "") ?? -1 >= 0)
    for (key, value) in expected { precondition(end[key] == value, "Unexpected diagnostic field \(key): \(end)") }
    requirePrivateWeatherLogs(records)
}

func testWeatherTransportDiagnostics() async throws {
    let query = diagnosticQuery()
    let valid = try diagnosticOpenMeteoData(query)
    await checkDiagnosticFetch(query: query, reply: .response(diagnosticHTTP(200), valid),
                              expected: ["status": "200", "bytes": String(valid.count), "decode": "ok",
                                         "days": "1", "full_days": "1", "temperature_days": "1",
                                         "condition_days": "1", "usable_days": "1", "error": "none"], succeeds: true)
    for hasTemperature in [true, false] {
        let missing = try diagnosticOpenMeteoData(query, temperature: hasTemperature, condition: !hasTemperature)
        await checkDiagnosticFetch(query: query, reply: .response(diagnosticHTTP(200), missing),
                                  expected: ["status": "200", "decode": "ok", "error": "none", "days": "1",
                                             "full_days": "1", "temperature_days": hasTemperature ? "1" : "0",
                                             "condition_days": hasTemperature ? "0" : "1", "usable_days": "0"], succeeds: true)
    }
    for source in WeatherSource.allCases {
        let body = Data("PRIVATE_BODY PRIVATE_EVENT_TITLE".utf8)
        await checkDiagnosticFetch(source: source, query: query, reply: .response(diagnosticHTTP(503), body),
                                  expected: ["status": "503", "bytes": String(body.count), "decode": "skipped",
                                             "error": "http", "days": "0", "usable_days": "0"], succeeds: false)
    }
    let malformed = Data("PRIVATE_BODY invalid JSON".utf8)
    await checkDiagnosticFetch(query: query, reply: .response(diagnosticHTTP(200), malformed),
                              expected: ["status": "200", "decode": "failed", "error": "decode"], succeeds: false)
    await checkDiagnosticFetch(query: query, reply: .response(diagnosticHTTP(200), try diagnosticOpenMeteoData(query, unit: "°F")),
                              expected: ["status": "200", "decode": "failed", "error": "invalid_data"], succeeds: false)
    await checkDiagnosticFetch(source: .wttr, query: query,
                              reply: .response(diagnosticHTTP(200), Data("{\"weather\":[],\"body\":\"PRIVATE_BODY\"}".utf8)),
                              expected: ["status": "200", "decode": "ok", "error": "none",
                                         "days": "0", "full_days": "0", "temperature_days": "0",
                                         "condition_days": "0", "usable_days": "0"], succeeds: true)
    // A 200 header and some bytes do not constitute a completed URLSession data response.
    await checkDiagnosticFetch(source: .wttr, query: query,
                              reply: .partialFailure(diagnosticHTTP(200), Data("PRIVATE_BODY {\"weather\":".utf8),
                                                     hostileWeatherError(code: NSURLErrorTimedOut)),
                              expected: ["status": "none", "bytes": "unknown", "decode": "skipped", "error": "url",
                                         "url_code": String(NSURLErrorTimedOut), "url_kind": "timeout",
                                         "days": "0", "full_days": "0", "temperature_days": "0",
                                         "condition_days": "0", "usable_days": "0"], succeeds: false)
    let failures: [(Int, String)] = [
        (NSURLErrorTimedOut, "timeout"), (NSURLErrorNotConnectedToInternet, "offline"),
        (NSURLErrorCannotConnectToHost, "connection"), (NSURLErrorCancelled, "cancelled"),
    ]
    for (code, kind) in failures {
        await checkDiagnosticFetch(query: query, reply: .failure(hostileWeatherError(code: code)),
                                  expected: ["status": "none", "decode": "skipped", "error": "url",
                                             "url_code": String(code), "url_kind": kind], succeeds: false)
    }
    await checkDiagnosticFetch(query: query, reply: .failure(hostileWeatherError(code: 42, domain: "PRIVATE_ERROR_DOMAIN")),
                              expected: ["status": "none", "decode": "skipped", "error": "other"], succeeds: false)
}

@MainActor
private final class WeatherDiagnosticLocation: WeatherLocationProviding {
    func request(allowPrompt: Bool, _ completion: @escaping (Result<WeatherCoordinates, WeatherLocationFailure>) -> Void) {
        preconditionFailure("Diagnostic fixture must use its manual city")
    }
    func cancel() {}
}

private actor WeatherDiagnosticSources {
    private var pending: [WeatherSource: CheckedContinuation<WeatherSourceBatch, Error>] = [:]
    private(set) var totalCount = 0

    var count: Int { pending.count }

    func fetch(_ source: WeatherSource) async throws -> WeatherSourceBatch {
        totalCount += 1
        return try await withCheckedThrowingContinuation { pending[source] = $0 }
    }

    func complete(_ source: WeatherSource, result: Result<WeatherSourceBatch, Error>) {
        guard let continuation = pending.removeValue(forKey: source) else { preconditionFailure("Missing diagnostic source request") }
        continuation.resume(with: result)
    }
}

@MainActor
private func waitForDiagnostic(_ predicate: () async -> Bool) async {
    for _ in 0..<1_000 {
        if await predicate() { return }
        await Task.yield()
    }
    preconditionFailure("Weather diagnostic fixture did not reach its expected state")
}

@MainActor
func testWeatherControllerDiagnostics() async {
    let suite = "local.countdownmanager.weather-diagnostics.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let records = WeatherDiagnosticRecords()
    let requests = WeatherDiagnosticSources()
    let clock = ISO8601DateFormatter().date(from: "2026-10-14T09:00:00Z")!
    let day = Day(clock)
    let event = Countdown(title: "PRIVATE_EVENT_TITLE", note: "PRIVATE_BODY", date: day, emoji: "", showsWeather: true)
    let controller = WeatherController(
        defaults: defaults, sourceProvider: { source, _, _ in try await requests.fetch(source) },
        locationProvider: WeatherDiagnosticLocation(), allowLocationRequests: false, now: { clock },
        scheduler: { _, _ in {} }, diagnostics: records.diagnostics
    )
    defer { controller.shutdown() }
    controller.selectLocation(.city(.moscow))
    controller.updateEvents([event])
    controller.setEnabled(true)
    await waitForDiagnostic { await requests.count == 3 }
    let query = WeatherQuery(coordinates: WeatherCity.moscow.coordinates, timeZone: WeatherCity.moscow.timeZone,
                             startDay: day)!
    let key = weatherDayKey(day)
    let full = query.interval(for: key)!
    let partial = WeatherDailySample(dayKey: key, period: DateInterval(start: full.start.addingTimeInterval(3_600), end: full.end),
                                    maximumTemperature: 42, condition: .rain)
    await requests.complete(.wttr, result: .success(WeatherSourceBatch(forecasts: [key: partial])))
    await waitForDiagnostic {
        records.lines.contains { $0.hasPrefix("weather.source source=wttr result=success ") }
    }
    for _ in 0..<32 { await Task.yield() }
    precondition(records.lines.contains("weather.publication demanded=1 usable=0"))
    precondition(!records.lines.contains("weather.publication demanded=1 usable=1"))
    precondition(controller.forecast(for: day) == nil, "Successful partial-day data must not produce a daily badge")
    let sample = WeatherDailySample(dayKey: key, period: full, maximumTemperature: 14, condition: .clear)
    await requests.complete(.openMeteo, result: .success(WeatherSourceBatch(forecasts: [key: sample])))
    await waitForDiagnostic { controller.forecast(for: day)?.maximumTemperature == 14 }
    precondition(records.lines.contains("weather.publication demanded=1 usable=1"))
    // Forecast publication does not imply that every provider request has settled.
    // Keep one source pending to prove that distinction before testing cached-refresh deduplication.
    precondition(containsWeatherSnapshot(records, expected: [
        "result": "available", "usable": "1", "request_pending": "true",
    ]))
    await requests.complete(.metNorway, result: .failure(hostileWeatherError(code: NSURLErrorTimedOut)))
    await waitForDiagnostic {
        records.lines.contains { $0.hasPrefix("weather.source source=metNorway result=failure ") && $0.contains("url_kind=timeout") }
    }
    await waitForDiagnostic {
        containsWeatherSnapshot(records, expected: [
            "reason": "settled", "result": "available", "usable": "1", "failed_sources": "1",
            "request_pending": "false", "computation_pending": "false",
        ])
    }
    precondition(controller.forecast(for: day)?.maximumTemperature == 14, "A failed source must retain the other provider's usable forecast")
    for source in [WeatherSource.openMeteo, .wttr] {
        precondition(records.lines.contains { $0.hasPrefix("weather.source source=\(source.rawValue) result=success ") })
    }
    let beforeRefresh = records.lines
    controller.refresh()
    for _ in 0..<32 { await Task.yield() }
    precondition(records.lines == beforeRefresh, "Unchanged cached refresh must not repeat weather diagnostic transitions")
    requirePrivateWeatherLogs(records)
}

private func containsWeatherSnapshot(_ records: WeatherDiagnosticRecords, expected: [String: String]) -> Bool {
    records.lines.contains { line in
        guard line.hasPrefix("weather.snapshot ") else { return false }
        let fields = diagnosticFields(line)
        return expected.allSatisfy { fields[$0.key] == $0.value }
    }
}

@MainActor
func testWeatherRestoredDiagnostics() async {
    let suite = "local.countdownmanager.weather-restored-diagnostics.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(true, forKey: "weather.enabled")
    defaults.set("moscow", forKey: "weather.location")
    let savedPreferences = defaults.persistentDomain(forName: suite)!
    let records = WeatherDiagnosticRecords()
    let requests = WeatherDiagnosticSources()
    let clock = ISO8601DateFormatter().date(from: "2026-10-14T09:00:00Z")!
    let event = Countdown(title: "PRIVATE_EVENT_TITLE", note: "PRIVATE_BODY", date: Day(clock), emoji: "", showsWeather: true)
    let controller = WeatherController(
        defaults: defaults, sourceProvider: { source, _, _ in try await requests.fetch(source) },
        locationProvider: WeatherDiagnosticLocation(), allowLocationRequests: false, now: { clock },
        scheduler: { _, _ in {} }, diagnostics: records.diagnostics
    )
    defer { controller.shutdown() }
    precondition(controller.enabled && controller.location == .city(.moscow))
    // The launch path supplies restored events without a toggle or an editor Save.
    controller.updateEvents([event])
    await waitForDiagnostic { await requests.totalCount == 3 }
    precondition(containsWeatherSnapshot(records, expected: [
        "enabled": "true", "mode": "manual", "demanded": "1", "result": "loading", "request_pending": "true",
    ]), "Restored weather must automatically describe its in-flight launch state")
    controller.recordDiagnosticSnapshot(reason: .diagnostics)
    precondition(containsWeatherSnapshot(records, expected: [
        "reason": "diagnostics", "result": "loading", "request_pending": "true", "usable": "0",
    ]), "An outstanding request must remain distinguishable from no usable data")
    for source in WeatherSource.allCases {
        await requests.complete(source, result: .failure(hostileWeatherError(code: NSURLErrorTimedOut)))
    }
    await waitForDiagnostic {
        containsWeatherSnapshot(records, expected: [
            "reason": "settled", "result": "no_usable_data", "request_pending": "false",
            "computation_pending": "false", "demanded": "1", "usable": "0", "failed_sources": "3", "fresh_sources": "0",
        ])
    }
    precondition(controller.forecast(for: event.date) == nil)
    let completedRequestCount = await requests.totalCount
    for _ in 0..<2 { controller.recordDiagnosticSnapshot(reason: .diagnostics) }
    let explicit = records.lines.filter {
        $0.hasPrefix("weather.snapshot reason=diagnostics ") && diagnosticFields($0)["result"] == "no_usable_data"
    }
    precondition(explicit.count == 2, "Every explicit diagnostic action must record its current snapshot")
    for _ in 0..<32 { await Task.yield() }
    let afterSnapshots = await requests.totalCount
    precondition(afterSnapshots == completedRequestCount && afterSnapshots == 3,
                 "Reading diagnostics must not fetch weather or bypass source backoff")
    precondition(NSDictionary(dictionary: savedPreferences).isEqual(to: defaults.persistentDomain(forName: suite)!),
                 "Reading snapshots must not mutate persisted weather settings")

    controller.updateEvents([])
    controller.recordDiagnosticSnapshot(reason: .diagnostics)
    precondition(containsWeatherSnapshot(records, expected: [
        "reason": "diagnostics", "result": "no_eligible_dates", "demanded": "0", "request_pending": "false",
    ]))
    controller.setEnabled(false)
    let disabledPreferences = defaults.persistentDomain(forName: suite)!
    controller.recordDiagnosticSnapshot(reason: .diagnostics)
    precondition(containsWeatherSnapshot(records, expected: [
        "reason": "diagnostics", "result": "disabled", "enabled": "false", "request_pending": "false",
    ]))
    precondition(NSDictionary(dictionary: disabledPreferences).isEqual(to: defaults.persistentDomain(forName: suite)!))
    let finalCount = await requests.totalCount
    precondition(finalCount == 3)
    requirePrivateWeatherLogs(records)
}
