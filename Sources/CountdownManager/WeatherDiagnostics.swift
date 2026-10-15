import Foundation

package enum WeatherDiagnosticSnapshotReason: String, Sendable {
    case launch, diagnostics, settled
}

/// Weather logs accept only bounded technical values, never provider or user strings.
package struct WeatherDiagnostics: Sendable {
    private let record: @Sendable (String) -> Void

    package static let journal = WeatherDiagnostics { DiagnosticLog.shared.record($0) }

    package init(record: @escaping @Sendable (String) -> Void = { _ in }) {
        self.record = record
    }

    func emit(_ message: String) { record(message) }

    package static func errorFields(_ error: Error) -> String {
        if error is CancellationError { return "error=cancelled" }
        if let transport = error as? WeatherTransportFailure {
            switch transport {
            case let .http(status, _): return "error=http http_status=\(status)"
            case .notModified: return "error=not_modified"
            }
        }
        if error is DecodingError { return "error=decode" }
        if let failure = error as? WeatherProviderFailure {
            switch failure {
            case .response: return "error=invalid_response"
            case .invalidData: return "error=invalid_data"
            }
        }
        let native = error as NSError
        guard native.domain == NSURLErrorDomain else { return "error=other" }
        let kind: String
        switch native.code {
        case NSURLErrorTimedOut: kind = "timeout"
        case NSURLErrorNotConnectedToInternet: kind = "offline"
        case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost, NSURLErrorNetworkConnectionLost:
            kind = "connection"
        case NSURLErrorCancelled: kind = "cancelled"
        default: kind = "other"
        }
        return "error=url url_code=\(native.code) url_kind=\(kind)"
    }

    package static func usableDayCount(_ batch: WeatherSourceBatch, query: WeatherQuery) -> Int {
        dayCounts(batch, query: query).usable
    }

    static func dayCounts(
        _ batch: WeatherSourceBatch, query: WeatherQuery
    ) -> (full: Int, temperature: Int, condition: Int, usable: Int) {
        batch.forecasts.reduce(into: (full: 0, temperature: 0, condition: 0, usable: 0)) { counts, entry in
            let sample = entry.value
            guard entry.key == sample.dayKey, sample.period == query.interval(for: entry.key) else { return }
            counts.full += 1
            if sample.maximumTemperature != nil { counts.temperature += 1 }
            if sample.condition != nil { counts.condition += 1 }
            if sample.maximumTemperature != nil, sample.condition != nil { counts.usable += 1 }
        }
    }

    static func seconds(_ interval: TimeInterval) -> Int {
        guard interval.isFinite else { return 0 }
        return Int(min(max(0, interval.rounded(.up)), Double(Int.max / 2)))
    }
}
