import Foundation

package typealias WeatherSourceProvider = @Sendable (
    WeatherSource, WeatherQuery, String?
) async throws -> WeatherSourceBatch
package typealias WeatherHTTPProvider = @Sendable (
    WeatherSource, WeatherQuery, WeatherHTTPMetadata.Validators?
) async throws -> WeatherSourceBatch

package enum WeatherTransportFailure: Error {
    case http(status: Int, retryAfter: Date?)
    case notModified(expiresAt: Date?, lastModified: String?)
    case httpMetadata(status: Int, metadata: WeatherHTTPMetadata)
    case validated(WeatherHTTPMetadata)
}

package enum WeatherTransport {
    package static func fetch(
        _ source: WeatherSource, query: WeatherQuery, lastModified: String? = nil,
        diagnostics: WeatherDiagnostics = WeatherDiagnostics(), session injectedSession: URLSession? = nil,
        validators: WeatherHTTPMetadata.Validators? = nil
    ) async throws -> WeatherSourceBatch {
        var request: URLRequest
        switch source {
        case .openMeteo: request = try OpenMeteoWeatherAdapter.makeRequest(query)
        case .metNorway: request = try METNorwayWeatherProvider.makeRequest(query)
        case .wttr: request = try WttrWeatherProvider.makeRequest(query)
        }
        if let etag = validators?.etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let modified = validators?.lastModified ?? lastModified {
            request.setValue(modified, forHTTPHeaderField: "If-Modified-Since")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        let session = injectedSession ?? URLSession(configuration: configuration)
        defer { if injectedSession == nil { session.finishTasksAndInvalidate() } }
        let requestID = UUID().uuidString
        let startedAt = WeatherRequestPolicy.continuousSeconds()
        let startedWall = Date()
        let context = "source=\(source.rawValue) request=\(requestID)"
        diagnostics.emit("weather.request.start \(context)")
        var status = "none"
        var bytes = "unknown"
        var decode = "skipped"
        var days = 0
        var counts = (full: 0, temperature: 0, condition: 0, usable: 0)
        var failure = "error=none"
        defer {
            let elapsed = (WeatherRequestPolicy.continuousSeconds() - startedAt) * 1_000
            diagnostics.emit("weather.request.end \(context) duration_ms=\(WeatherDiagnostics.seconds(elapsed)) " +
                             "status=\(status) bytes=\(bytes) decode=\(decode) days=\(days) full_days=\(counts.full) " +
                             "temperature_days=\(counts.temperature) condition_days=\(counts.condition) " +
                             "usable_days=\(counts.usable) \(failure)")
        }
        do {
            let (data, response) = try await session.data(for: request)
            bytes = String(data.count)
            status = (response as? HTTPURLResponse).map { String($0.statusCode) } ?? "none"
            guard let response = response as? HTTPURLResponse else { throw WeatherProviderFailure.response }
            let receivedAt = Date()
            let tick = WeatherRequestPolicy.continuousSeconds()
            let fields = response.allHeaderFields.reduce(into: [String: String]()) { result, pair in
                guard let key = pair.key as? String, let value = pair.value as? String else { return }
                result[key] = value
            }
            let metadata = WeatherHTTPMetadata(headers: fields, receivedWall: receivedAt, receivedTick: tick,
                                               duration: tick - startedAt, requestWall: startedWall)
            diagnostics.emit("weather.http source=\(source.rawValue) \(metadata.diagnosticFields)")
            if response.statusCode == 304 {
                throw WeatherTransportFailure.validated(metadata)
            }
            guard response.statusCode == 200 else {
                throw WeatherTransportFailure.httpMetadata(status: response.statusCode, metadata: metadata)
            }
            var batch: WeatherSourceBatch
            try Task.checkCancellation()
            decode = "failed"
            switch source {
            case .openMeteo: batch = try OpenMeteoWeatherAdapter.decode(data, query: query)
            case .metNorway: batch = try METNorwayWeatherProvider.decode(data, query: query)
            case .wttr: batch = try WttrWeatherProvider.decode(data, query: query)
            }
            decode = "ok"
            days = batch.forecasts.count
            counts = WeatherDiagnostics.dayCounts(batch, query: query)
            try Task.checkCancellation()
            batch.http = metadata
            return batch
        } catch {
            failure = WeatherDiagnostics.errorFields(error)
            throw error
        }
    }

    package static func httpDate(_ text: String?) -> Date? {
        text.flatMap { WeatherHTTPMetadata.httpDate($0) }
    }

    package static func retryAfter(_ text: String?, now: Date) -> Date? {
        if let text, let date = WeatherHTTPMetadata.httpDate(text, now: now), date < now { return nil }
        return WeatherHTTPMetadata.retryDelay(text, wall: now, serverDate: nil).map { now.addingTimeInterval($0) }
    }
}
