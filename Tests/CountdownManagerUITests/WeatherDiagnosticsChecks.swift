import CountdownCore
import CountdownManagerUI
import Foundation

private final class WeatherDiagnosticRecords: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [String] = []
    private var waiters: [(@Sendable (String) -> Bool, CheckedContinuation<Void, Never>)] = []

    var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return messages
    }

    func record(_ message: String) {
        lock.lock()
        messages.append(message)
        let ready = waiters.filter { $0.0(message) }
        waiters.removeAll { $0.0(message) }
        lock.unlock()
        ready.forEach { $0.1.resume() }
    }

    func waitFor(_ predicate: @escaping @Sendable (String) -> Bool) async {
        let timeout = Task {
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            preconditionFailure("Missing weather diagnostic transition")
        }
        defer { timeout.cancel() }
        await withCheckedContinuation { continuation in
            lock.lock()
            if messages.contains(where: predicate) {
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append((predicate, continuation))
                lock.unlock()
            }
        }
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
    private var capturedRequest: URLRequest?

    func install(_ value: Value) {
        lock.lock()
        defer { lock.unlock() }
        self.value = value
        capturedRequest = nil
    }

    func capture(_ request: URLRequest) { lock.lock(); capturedRequest = request; lock.unlock() }
    func request() -> URLRequest? { lock.lock(); defer { lock.unlock() }; return capturedRequest }

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
        Self.reply.capture(request)
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
    private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []

    var count: Int { pending.count }

    func fetch(_ source: WeatherSource) async throws -> WeatherSourceBatch {
        totalCount += 1
        return try await withCheckedThrowingContinuation {
            pending[source] = $0
            let ready = waiters.filter { $0.0 <= totalCount }
            waiters.removeAll { $0.0 <= totalCount }
            ready.forEach { $0.1.resume() }
        }
    }

    func waitForTotal(_ expected: Int) async {
        let timeout = Task {
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            preconditionFailure("Missing weather diagnostic source request")
        }
        defer { timeout.cancel() }
        if totalCount < expected { await withCheckedContinuation { waiters.append((expected, $0)) } }
        precondition(totalCount == expected)
    }

    func complete(_ source: WeatherSource, result: Result<WeatherSourceBatch, Error>) {
        guard let continuation = pending.removeValue(forKey: source) else { preconditionFailure("Missing diagnostic source request") }
        continuation.resume(with: result)
    }
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
        locationProvider: WeatherDiagnosticLocation(), allowLocationRequests: false, now: { clock }, monotonicNow: { clock.timeIntervalSinceReferenceDate }, jitter: { 0 },
        scheduler: { _, _ in {} }, diagnostics: records.diagnostics
    )
    defer { controller.shutdown() }
    controller.selectLocation(.city(.moscow))
    controller.updateEvents([event])
    controller.setEnabled(true)
    await requests.waitForTotal(3)
    let query = WeatherQuery(coordinates: WeatherCity.moscow.coordinates, timeZone: WeatherCity.moscow.timeZone,
                             startDay: day)!
    let key = weatherDayKey(day)
    let full = query.interval(for: key)!
    let partial = WeatherDailySample(dayKey: key, period: DateInterval(start: full.start.addingTimeInterval(3_600), end: full.end),
                                    maximumTemperature: 42, condition: .rain)
    await requests.complete(.wttr, result: .success(WeatherSourceBatch(forecasts: [key: partial])))
    await records.waitFor { line in
        matchesWeatherSnapshot(line, expected: ["usable": "0", "fresh_sources": "1",
                                                "request_pending": "true", "computation_pending": "false"])
    }
    precondition(records.lines.contains("weather.publication demanded=1 usable=0"))
    precondition(!records.lines.contains("weather.publication demanded=1 usable=1"))
    precondition(controller.forecast(for: day) == nil, "Successful partial-day data must not produce a daily badge")
    let sample = WeatherDailySample(dayKey: key, period: full, maximumTemperature: 14, condition: .clear)
    await requests.complete(.openMeteo, result: .success(WeatherSourceBatch(forecasts: [key: sample])))
    await records.waitFor { $0 == "weather.publication demanded=1 usable=1" }
    precondition(records.lines.contains("weather.publication demanded=1 usable=1"))
    // Forecast publication does not imply that every provider request has settled.
    // Keep one source pending to prove that distinction before testing cached-refresh deduplication.
    precondition(containsWeatherSnapshot(records, expected: [
        "result": "available", "usable": "1", "request_pending": "true",
    ]))
    await requests.complete(.metNorway, result: .failure(hostileWeatherError(code: NSURLErrorTimedOut)))
    await records.waitFor { $0.hasPrefix("weather.source source=metNorway result=failure ") && $0.contains("url_kind=timeout") }
    await records.waitFor { line in
        matchesWeatherSnapshot(line, expected: [
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
    precondition(records.lines == beforeRefresh, "Unchanged cached refresh must not repeat weather diagnostic transitions")
    requirePrivateWeatherLogs(records)
}

private func matchesWeatherSnapshot(_ line: String, expected: [String: String]) -> Bool {
    guard line.hasPrefix("weather.snapshot ") else { return false }
    let fields = diagnosticFields(line)
    return expected.allSatisfy { fields[$0.key] == $0.value }
}

private func containsWeatherSnapshot(_ records: WeatherDiagnosticRecords, expected: [String: String]) -> Bool {
    records.lines.contains { matchesWeatherSnapshot($0, expected: expected) }
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
        locationProvider: WeatherDiagnosticLocation(), allowLocationRequests: false, now: { clock }, monotonicNow: { clock.timeIntervalSinceReferenceDate }, jitter: { 0 },
        scheduler: { _, _ in {} }, diagnostics: records.diagnostics
    )
    defer { controller.shutdown() }
    precondition(controller.enabled && controller.location == .city(.moscow))
    // The launch path supplies restored events without a toggle or an editor Save.
    controller.updateEvents([event])
    await requests.waitForTotal(3)
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
    await records.waitFor { line in
        matchesWeatherSnapshot(line, expected: [
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

func testWeatherHTTPFreshness() {
    let wall = Date(timeIntervalSince1970: 1_792_000_000)
    func date(_ offset: TimeInterval) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: wall.addingTimeInterval(offset))
    }
    func metadata(_ headers: [String: String], duration: TimeInterval = 0) -> WeatherHTTPMetadata {
        WeatherHTTPMetadata(headers: headers, receivedWall: wall, receivedTick: 100, duration: duration)
    }
    let age = metadata(["Date": date(-30), "Age": "50", "Cache-Control": "max-age=300", "Expires": date(9_000)], duration: 2)
    precondition(age.freshnessReason == .maxAge && age.ageAtReceipt == 52 && age.remaining == 248)
    precondition(metadata(["Date": date(-30), "Age": "50", "Expires": date(70)], duration: 2).remaining == 48)
    precondition(metadata(["Age": "10", "Expires": date(100)], duration: 2).remaining == 88)
    precondition(metadata(["Cache-Control": "max-age=300", "Age": "50"], duration: 2).remaining == 248)
    precondition(metadata(["Age": "50"], duration: 2).remaining == 1_748)
    precondition(metadata([:]).freshnessReason == .heuristic && metadata([:]).remaining == 1_800)
    precondition(metadata(["Expires": date(-10)]).remaining == 0)
    precondition(metadata(["Cache-Control": "max-age=0", "Expires": date(1_800)]).remaining == 0)
    precondition(metadata(["Cache-Control": "max-age=60", "Expires": "invalid"]).remaining == 60,
                 "Explicit max-age overrides Expires, including an invalid obsolete Expires")
    precondition(metadata(["Date": date(0), "date": date(-10)]).remaining == 0)
    for raw in ["max-age=\"60", "max-age=60\"", "max-age=\"\"60\"\""] {
        precondition(metadata(["Cache-Control": raw]).remaining == 0)
    }
    for headers in [["Cache-Control": "max-age=12,max-age=24"], ["Cache-Control": "max-age=no"],
                    ["Cache-Control": "max-age=-1"], ["Date": "bad"], ["Expires": "bad"], ["Age": "-1"],
                    ["Age": "1.5"], ["Age": "NaN"], ["Date": date(120)]] {
        let value = metadata(headers)
        precondition(value.remaining == 0 && value.freshnessReason == .invalid)
    }
    for directive in ["no-cache", "no-store", "no-cache, max-age=1000"] {
        precondition(metadata(["Cache-Control": directive]).remaining == 0)
    }
    precondition(!metadata(["Cache-Control": "no-store"]).allowsStorage)
    precondition(metadata(["Cache-Control": "must-revalidate, max-age=10"]).remaining == 10)
    let old = metadata(["Date": date(0), "Expires": date(60), "ETag": "PRIVATE_BODY", "Last-Modified": date(-3_600)])
    let validation = WeatherHTTPMetadata(headers: ["Date": date(30)], receivedWall: wall.addingTimeInterval(30), receivedTick: 130)
    let merged = old.revalidated(by: validation)
    precondition(merged.remaining == 30 && merged.expires == old.expires && merged.validators == old.validators)
    let absent = WeatherHTTPMetadata(headers: [:], receivedWall: wall.addingTimeInterval(60), receivedTick: 160)
    precondition(old.revalidated(by: absent).remaining == 0, "A header-free304 cannot reset the old lifetime")
    let maxAge = metadata(["Cache-Control": "max-age=60", "Date": date(0), "ETag": "PRIVATE_BODY"])
    precondition(maxAge.revalidated(by: validation).remaining == 60, "A validated Date can renew a preserved max-age")
    precondition(maxAge.revalidated(by: absent).remaining == 0)
    let heuristic = metadata(["Last-Modified": date(-3_600)])
    let lateValidation = WeatherHTTPMetadata(headers: ["Date": date(1_800)],
        receivedWall: wall.addingTimeInterval(1_800), receivedTick: 1_900)
    precondition(heuristic.revalidated(by: lateValidation).remaining == 0,
                 "304 without explicit lifetime cannot manufacture a new heuristic30minutes")
    let forbid = WeatherHTTPMetadata(headers: ["Cache-Control": "no-store"], receivedWall: wall, receivedTick: 100)
    precondition(!maxAge.revalidated(by: forbid).allowsStorage)
    let crossedClock = WeatherHTTPMetadata(headers: ["Cache-Control": "max-age=600"], receivedWall: wall,
                                           receivedTick: 100, duration: 2, requestWall: wall.addingTimeInterval(-7_200))
    precondition(crossedClock.remaining == 0)
    for raw in ["-1", "1.2", "NaN", "infinity", "18446744073709551616"] {
        precondition(WeatherHTTPMetadata.retryDelay(raw, wall: wall, serverDate: nil) == nil)
    }
    precondition(WeatherHTTPMetadata.retryDelay("120", wall: wall, serverDate: nil) == 120)
    precondition(WeatherHTTPMetadata.retryDelay(date(120), wall: wall, serverDate: wall.addingTimeInterval(-60)) == 180)
    precondition(WeatherHTTPMetadata.retryDelay(date(-120), wall: wall, serverDate: nil) == 0)
    precondition(WeatherHTTPMetadata.retryDelay(date(10_000_000), wall: wall, serverDate: nil) == 10_000_000)
    let dates = ["Sun, 06 Nov 1994 08:49:37 GMT", "Sunday, 06-Nov-94 08:49:37 GMT", "Sun Nov  6 08:49:37 1994"]
    let parsed = dates.compactMap { WeatherHTTPMetadata.httpDate($0, now: wall) }
    precondition(parsed.count == 3 && Set(parsed).count == 1)
    for value in [age, old, old.revalidated(by: absent), crossedClock] {
        let fields = value.diagnosticFields
        for sentinel in weatherPrivateSentinels { precondition(!fields.contains(sentinel)) }
    }
    precondition(metadata(["Expires": date(-10)]).diagnosticFields.contains("expires_receipt_s=-10"))
}

func testWeatherHTTPTransportMetadata() async throws {
    let query = diagnosticQuery()
    let records = WeatherDiagnosticRecords()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [WeatherDiagnosticURLProtocol.self]
    configuration.urlCache = nil
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let modified = "Sun, 06 Nov 1994 08:49:37 GMT"
    let tag = "W/\"PRIVATE_BODY\""
    let response = HTTPURLResponse(url: URL(string: "https://private-weather.invalid/PRIVATE_BODY")!, statusCode: 200,
        httpVersion: "HTTP/1.1", headerFields: ["Cache-Control": "max-age=300", "Age": "10", "ETag": tag, "Last-Modified": modified])!
    WeatherDiagnosticURLProtocol.reply.install(.response(response, try diagnosticOpenMeteoData(query)))
    let batch = try await WeatherTransport.fetch(.openMeteo, query: query, diagnostics: records.diagnostics,
                                                 session: session)
    precondition(batch.http?.freshnessReason == .maxAge && batch.http?.validators.etag == tag)
    let validation = HTTPURLResponse(url: response.url!, statusCode: 304, httpVersion: "HTTP/1.1",
                                    headerFields: ["ETag": tag])!
    WeatherDiagnosticURLProtocol.reply.install(.response(validation, Data()))
    do {
        _ = try await WeatherTransport.fetch(.openMeteo, query: query, diagnostics: records.diagnostics,
            session: session, validators: WeatherHTTPMetadata.Validators(etag: tag, lastModified: modified))
        preconditionFailure("304 must carry validation metadata instead of decoding an empty body")
    } catch let WeatherTransportFailure.validated(metadata) {
        precondition(metadata.validators.etag == tag && metadata.expires == nil)
    }
    let sent = WeatherDiagnosticURLProtocol.reply.request()
    precondition(sent?.value(forHTTPHeaderField: "If-None-Match") == tag)
    precondition(sent?.value(forHTTPHeaderField: "If-Modified-Since") == modified)
    precondition(records.lines.contains { $0.hasPrefix("weather.http ") && $0.contains("freshness=maxAge") })
    requirePrivateWeatherLogs(records)
}
