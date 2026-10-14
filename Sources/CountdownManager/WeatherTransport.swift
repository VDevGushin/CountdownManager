import Foundation

package typealias WeatherSourceProvider = @Sendable (
    WeatherSource, WeatherQuery, String?
) async throws -> WeatherSourceBatch

package enum WeatherTransportFailure: Error {
    case http(status: Int, retryAfter: Date?)
    case notModified(expiresAt: Date?, lastModified: String?)
}

package enum WeatherTransport {
    package static func fetch(
        _ source: WeatherSource, query: WeatherQuery, lastModified: String? = nil
    ) async throws -> WeatherSourceBatch {
        var request: URLRequest
        switch source {
        case .openMeteo: request = try OpenMeteoWeatherAdapter.makeRequest(query)
        case .metNorway: request = try METNorwayWeatherProvider.makeRequest(query)
        case .wttr: request = try WttrWeatherProvider.makeRequest(query)
        }
        if let lastModified { request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since") }
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
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw WeatherProviderFailure.response }
        let receivedAt = Date()
        let expiry = httpDate(response.value(forHTTPHeaderField: "Expires"))
        let modified = response.value(forHTTPHeaderField: "Last-Modified")
        if response.statusCode == 304 {
            throw WeatherTransportFailure.notModified(expiresAt: expiry, lastModified: modified)
        }
        guard response.statusCode == 200 else {
            throw WeatherTransportFailure.http(
                status: response.statusCode,
                retryAfter: retryAfter(response.value(forHTTPHeaderField: "Retry-After"), now: receivedAt)
            )
        }
        var batch: WeatherSourceBatch
        switch source {
        case .openMeteo: batch = try OpenMeteoWeatherAdapter.decode(data, query: query)
        case .metNorway: batch = try METNorwayWeatherProvider.decode(data, query: query)
        case .wttr: batch = try WttrWeatherProvider.decode(data, query: query)
        }
        try Task.checkCancellation()
        batch.expiresAt = expiry
        batch.lastModified = modified
        return batch
    }

    package static func httpDate(_ text: String?) -> Date? {
        guard let text else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        formatter.isLenient = false
        return formatter.date(from: text)
    }

    package static func retryAfter(_ text: String?, now: Date) -> Date? {
        guard let text else { return nil }
        if let seconds = Double(text), seconds.isFinite, seconds >= 0 {
            return now.addingTimeInterval(seconds)
        }
        return httpDate(text).flatMap { $0 >= now ? $0 : nil }
    }
}
