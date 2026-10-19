import CountdownCore
import Foundation

package enum WeatherSource: String, CaseIterable, Hashable, Sendable {
    case openMeteo, metNorway, wttr
}

package struct WeatherQuery: Equatable, Sendable {
    package let coordinates: WeatherCoordinates
    package let timeZone: TimeZone
    package let dayCount: Int
    package let dayKeys: [String]
    private let intervals: [String: DateInterval]
    private let firstDayStart: Date
    private let lastDayStart: Date

    package var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    package var startDay: Day { Day(firstDayStart, calendar: calendar) }
    package var endDay: Day { Day(lastDayStart, calendar: calendar) }

    package init?(coordinates: WeatherCoordinates, timeZone: TimeZone, startDay: Day, dayCount: Int = 16) {
        guard (1...16).contains(dayCount) else { return nil }
        // Keep the requested day boundaries stable during an in-flight request.
        let stableZone = TimeZone(identifier: timeZone.identifier) ?? timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = stableZone
        guard let start = calendar.date(from: DateComponents(
            year: startDay.year, month: startDay.month, day: startDay.day
        )), Day(start, calendar: calendar) == startDay else { return nil }
        var keys: [String] = []
        var periods: [String: DateInterval] = [:]
        var cursor = start
        var finalStart = start
        for _ in 0..<dayCount {
            guard let period = calendar.dateInterval(of: .day, for: cursor), period.duration > 0 else { return nil }
            let key = weatherDayKey(Day(period.start, calendar: calendar))
            guard periods[key] == nil else { return nil }
            keys.append(key)
            periods[key] = period
            finalStart = period.start
            cursor = period.end
        }
        self.coordinates = coordinates
        self.timeZone = stableZone
        self.dayCount = dayCount
        self.dayKeys = keys
        self.intervals = periods
        firstDayStart = start
        lastDayStart = finalStart
    }

    package func interval(for dayKey: String) -> DateInterval? { intervals[dayKey] }
}

package enum WeatherCategory: String, CaseIterable, Hashable, Sendable {
    case clear, partlyCloudy, cloudy, fog, drizzle, rain, sleet, snow, thunderstorm

    package init?(weatherCode: Int) {
        switch weatherCode {
        case 0: self = .clear
        case 1, 2: self = .partlyCloudy
        case 3: self = .cloudy
        case 45, 48: self = .fog
        case 51, 53, 55: self = .drizzle
        case 56, 57, 66, 67: self = .sleet
        case 61, 63, 65, 80, 81, 82: self = .rain
        case 71, 73, 75, 77, 85, 86: self = .snow
        case 95, 96, 97, 99: self = .thunderstorm
        default: return nil
        }
    }

    package var isWet: Bool {
        switch self {
        case .clear, .partlyCloudy, .cloudy, .fog: return false
        case .drizzle, .rain, .sleet, .snow, .thunderstorm: return true
        }
    }

    package var weatherCode: Int {
        switch self {
        case .clear: return 0
        case .partlyCloudy: return 2
        case .cloudy: return 3
        case .fog: return 45
        case .drizzle: return 53
        case .rain: return 63
        case .sleet: return 66
        case .snow: return 73
        case .thunderstorm: return 95
        }
    }

    fileprivate var tiePriority: Int {
        switch self {
        case .clear: return 0
        case .partlyCloudy: return 1
        case .cloudy: return 2
        case .fog: return 3
        case .drizzle: return 4
        case .rain: return 5
        case .sleet: return 6
        case .snow: return 7
        case .thunderstorm: return 8
        }
    }
}

package struct WeatherDailySample: Equatable, Sendable {
    package let dayKey: String
    package let period: DateInterval
    package let maximumTemperature: Double?
    package let rainfallMillimeters: Double?
    package let condition: WeatherCategory?

    package init(
        dayKey: String, period: DateInterval, maximumTemperature: Double? = nil,
        rainfallMillimeters: Double? = nil, condition: WeatherCategory? = nil
    ) {
        self.dayKey = dayKey
        self.period = period
        self.maximumTemperature = maximumTemperature.flatMap {
            $0.isFinite && (-100...70).contains($0) ? $0 : nil
        }
        self.rainfallMillimeters = rainfallMillimeters.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        self.condition = condition
    }
}

package struct WeatherSourceBatch: Equatable, Sendable {
    package let forecasts: [String: WeatherDailySample]
    package var expiresAt: Date?
    package var lastModified: String?
    package var http: WeatherHTTPMetadata?

    package init(forecasts: [String: WeatherDailySample], expiresAt: Date? = nil, lastModified: String? = nil,
                 http: WeatherHTTPMetadata? = nil) {
        self.forecasts = forecasts
        self.expiresAt = expiresAt
        self.lastModified = lastModified
        self.http = http
    }
}

package struct WeatherConsensus: Equatable, Sendable {
    package let maximumTemperature: Double
    package let rainfallMillimeters: Double?
    package let condition: WeatherCategory
    package let period: DateInterval
    package let contributors: Set<WeatherSource>
    package var weatherCode: Int { condition.weatherCode }
}

package enum WeatherNormalizer {
    package static func aggregate(
        _ batches: [WeatherSource: WeatherSourceBatch], query: WeatherQuery
    ) -> [String: WeatherConsensus] {
        var result: [String: WeatherConsensus] = [:]
        for key in query.dayKeys {
            result[key] = consensus(batches, query: query, dayKey: key)
        }
        return result
    }

    // Nonisolated async work runs on the generic executor in this project's Swift 5 mode.
    // The async boundary is needed for executor isolation, even without an internal suspension.
    // swiftlint:disable async_without_await
    package static func aggregateDemanded(
        _ batches: [WeatherSource: WeatherSourceBatch], query: WeatherQuery, demandedDayKeys: Set<String>
    ) async throws -> [String: WeatherConsensus] {
        try Task.checkCancellation()
        var result: [String: WeatherConsensus] = [:]
        for key in query.dayKeys where demandedDayKeys.contains(key) {
            try Task.checkCancellation()
            result[key] = consensus(batches, query: query, dayKey: key)
        }
        try Task.checkCancellation()
        return result
    }
    // swiftlint:enable async_without_await

    private static func consensus(
        _ batches: [WeatherSource: WeatherSourceBatch], query: WeatherQuery, dayKey key: String
    ) -> WeatherConsensus? {
        guard let day = query.interval(for: key) else { return nil }
        let samples = WeatherSource.allCases.compactMap { source -> Contribution? in
            guard let sample = batches[source]?.forecasts[key], sample.dayKey == key,
                  sample.period.start.timeIntervalSince1970.isFinite,
                  sample.period.end.timeIntervalSince1970.isFinite,
                  sample.period.duration > 0, sample.period.start >= day.start, sample.period.end <= day.end,
                  sample.maximumTemperature != nil || sample.rainfallMillimeters != nil || sample.condition != nil
            else { return nil }
            return Contribution(source: source, sample: sample)
        }
        let fullDay = samples.filter { $0.sample.period == day }
        let selected: [Contribution]
        if !fullDay.isEmpty {
            selected = fullDay
        } else {
            // Metrics describe their actual covered hours, so compare only identical intervals.
            let groups = Dictionary(grouping: samples, by: { $0.sample.period })
            selected = groups.max { lhs, rhs in
                if lhs.value.count != rhs.value.count { return lhs.value.count < rhs.value.count }
                if lhs.key.duration != rhs.key.duration { return lhs.key.duration < rhs.key.duration }
                return lhs.key.start > rhs.key.start
            }?.value ?? []
        }
        guard let maximum = median(selected.compactMap { $0.sample.maximumTemperature }),
              let condition = majority(selected.compactMap { $0.sample.condition }),
              let period = selected.first?.sample.period else { return nil }
        return WeatherConsensus(
            maximumTemperature: maximum,
            rainfallMillimeters: median(selected.compactMap { $0.sample.rainfallMillimeters }),
            condition: condition, period: period, contributors: Set(selected.map(\.source))
        )
    }

    private struct Contribution {
        let source: WeatherSource
        let sample: WeatherDailySample
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? sorted[middle - 1] / 2 + sorted[middle] / 2 : sorted[middle]
    }

    private static func majority(_ values: [WeatherCategory]) -> WeatherCategory? {
        let counts = values.reduce(into: [WeatherCategory: Int]()) { $0[$1, default: 0] += 1 }
        return counts.keys.max { lhs, rhs in
            if counts[lhs] != counts[rhs] { return (counts[lhs] ?? 0) < (counts[rhs] ?? 0) }
            if lhs.isWet != rhs.isWet { return !lhs.isWet }
            return lhs.tiePriority < rhs.tiePriority
        }
    }
}
