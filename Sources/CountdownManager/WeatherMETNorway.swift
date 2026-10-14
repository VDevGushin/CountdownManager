import Foundation

package enum METNorwayWeatherProvider {
    package static func makeRequest(_ query: WeatherQuery) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.met.no"
        components.path = "/weatherapi/locationforecast/2.0/complete"
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(query.coordinates.latitude)),
            URLQueryItem(name: "lon", value: String(query.coordinates.longitude)),
        ]
        guard let url = components.url else { throw METFailure.invalidData }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development"
        request.setValue("CountdownManager/\(version) https://github.com/VDevGushin/CountdownManager", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    package static func decode(_ data: Data, query: WeatherQuery) throws -> WeatherSourceBatch {
        try Task.checkCancellation()
        guard data.count <= 2_000_000 else { throw METFailure.invalidData }
        let response = try JSONDecoder().decode(Response.self, from: data)
        try Task.checkCancellation()
        guard response.properties.timeseries.count <= 512 else { throw METFailure.invalidData }
        let units = response.properties.meta?.units ?? [:]
        let temperatureIsCelsius = units["air_temperature_max"] == "celsius"
        let hourlyTemperatureIsCelsius = units["air_temperature"] == "celsius"
        let precipitationIsMillimeters = units["precipitation_amount"] == "mm"
        let formatter = ISO8601DateFormatter()
        var segments: [Segment] = []
        var hourlyTemperatures: [Date: Double] = [:]
        var previousTime: Date?
        for timestep in response.properties.timeseries {
            try Task.checkCancellation()
            guard timestep.time.hasSuffix("Z"), let start = formatter.date(from: timestep.time),
                  previousTime.map({ start > $0 }) ?? true else { throw METFailure.invalidData }
            previousTime = start
            if hourlyTemperatureIsCelsius, let temperature = timestep.data.instant?.details?.airTemperature,
               temperature.isFinite, (-100...70).contains(temperature) {
                hourlyTemperatures[start] = temperature
            }
            for (hours, payload) in timestep.data.periods {
                guard let payload else { continue }
                let symbol = payload.summary?.symbolCode?.split(separator: "_").first.map(String.init)
                let condition = symbol.flatMap(category)
                let temperature = temperatureIsCelsius ? payload.details?.maximumTemperature : nil
                let amount = precipitationIsMillimeters ? payload.details?.precipitationAmount : nil
                let validTemperature = temperature.flatMap { $0.isFinite && (-100...70).contains($0) ? $0 : nil }
                let validAmount = amount.flatMap { $0.isFinite && (0...3_000).contains($0) ? $0 : nil }
                // MET precipitation includes melted snow: only an identified liquid phase is rainfall.
                let isLiquid = condition != nil && symbol.map { $0.contains("rain") || $0.contains("drizzle") } == true
                    && symbol.map { !$0.contains("snow") && !$0.contains("sleet") } == true
                let knownDryZero = validAmount == 0 && condition.map { !$0.isWet } == true
                let rainfall = isLiquid || knownDryZero ? validAmount : nil
                let mixedOrUnknownPhase = symbol.map { $0.contains("snow") || $0.contains("sleet") } == true
                    || (condition == nil && (validAmount ?? 0) > 0)
                guard condition != nil || validTemperature != nil || validAmount != nil else { continue }
                segments.append(Segment(
                    period: DateInterval(start: start, duration: Double(hours) * 3_600),
                    maximumTemperature: validTemperature, rainfall: rainfall,
                    excludesLiquidTotal: mixedOrUnknownPhase, condition: condition
                ))
            }
        }
        var forecasts: [String: WeatherDailySample] = [:]
        for key in query.dayKeys {
            try Task.checkCancellation()
            guard let day = query.interval(for: key), let coverage = try bestCoverage(segments, within: day) else { continue }
            let period = DateInterval(start: coverage.segments[0].period.start, end: coverage.end)
            let temperatureCoverage = try bestCoverage(segments.filter { $0.maximumTemperature != nil }, within: period)
            let rainfallCoverage = try bestCoverage(segments.filter { $0.rainfall != nil }, within: period)
            let intervalMaximum = fullCoverage(temperatureCoverage, of: period)
                ? temperatureCoverage?.segments.compactMap(\.maximumTemperature).max() : nil
            let maximum = intervalMaximum ?? (period == day ? hourlyMaximum(hourlyTemperatures, for: day) : nil)
            let rainfall = fullCoverage(rainfallCoverage, of: period) && !coverage.segments.contains(where: \.excludesLiquidTotal)
                ? rainfallCoverage?.segments.compactMap(\.rainfall).reduce(0, +) : nil
            let condition = predominantCategory(coverage.segments)
            guard maximum != nil || rainfall != nil || condition != nil else { continue }
            forecasts[key] = WeatherDailySample(
                dayKey: key, period: period, maximumTemperature: maximum,
                rainfallMillimeters: rainfall, condition: condition
            )
        }
        return WeatherSourceBatch(forecasts: forecasts)
    }

    private enum METFailure: Error { case invalidData }

    private struct Segment {
        let period: DateInterval
        let maximumTemperature: Double?
        let rainfall: Double?
        let excludesLiquidTotal: Bool
        let condition: WeatherCategory?
    }

    private struct Coverage {
        let segments: [Segment]
        let end: Date
        let resolutionCost: TimeInterval
    }

    // Choose a contiguous path, never overlapping sums or fractions of a crossing interval.
    // Among paths with the same coverage, finer periods win without sacrificing complete coverage.
    private static func bestCoverage(_ segments: [Segment], within period: DateInterval) throws -> Coverage? {
        try Task.checkCancellation()
        let contained = segments.filter { $0.period.start >= period.start && $0.period.end <= period.end }
        let byStart = Dictionary(grouping: contained, by: { $0.period.start })
        var memo: [Date: Coverage] = [:]
        func path(from start: Date) throws -> Coverage {
            try Task.checkCancellation()
            if let cached = memo[start] { return cached }
            var best = Coverage(segments: [], end: start, resolutionCost: 0)
            for segment in byStart[start] ?? [] {
                let tail = try path(from: segment.period.end)
                let candidate = Coverage(
                    segments: [segment] + tail.segments, end: tail.end,
                    resolutionCost: segment.period.duration * segment.period.duration + tail.resolutionCost
                )
                if candidate.end > best.end || (candidate.end == best.end && candidate.resolutionCost < best.resolutionCost) {
                    best = candidate
                }
            }
            memo[start] = best
            return best
        }
        var result: Coverage?
        for start in byStart.keys.sorted() {
            let candidate = try path(from: start)
            guard !candidate.segments.isEmpty else { continue }
            if let previous = result {
                let duration = candidate.end.timeIntervalSince(start)
                let previousStart = previous.segments[0].period.start
                let previousDuration = previous.end.timeIntervalSince(previousStart)
                if duration > previousDuration || (duration == previousDuration && start < previousStart) {
                    result = candidate
                }
            } else {
                result = candidate
            }
        }
        return result
    }

    private static func fullCoverage(_ coverage: Coverage?, of period: DateInterval) -> Bool {
        coverage?.segments.first?.period.start == period.start && coverage?.end == period.end
    }

    // Fallback derives the maximum of a complete hourly forecast grid, not current observations.
    // Every local-day hourly slot must exist; never interpolate sparse steps or a missing hour.
    private static func hourlyMaximum(_ temperatures: [Date: Double], for day: DateInterval) -> Double? {
        let hours = Int(day.duration / 3_600)
        guard (23...25).contains(hours), day.duration == Double(hours) * 3_600 else { return nil }
        var values: [Double] = []
        for hour in 0..<hours {
            guard let temperature = temperatures[day.start.addingTimeInterval(Double(hour) * 3_600)] else { return nil }
            values.append(temperature)
        }
        return values.max()
    }

    private static let categories: [WeatherCategory] = [
        .clear, .partlyCloudy, .cloudy, .fog, .drizzle, .rain, .sleet, .snow, .thunderstorm,
    ]

    private static func predominantCategory(_ segments: [Segment]) -> WeatherCategory? {
        var weights = Array(repeating: TimeInterval(0), count: categories.count)
        for segment in segments {
            guard let condition = segment.condition, let index = categories.firstIndex(of: condition) else { return nil }
            weights[index] += segment.period.duration
        }
        guard let maximum = weights.max(), maximum > 0 else { return nil }
        // Equal-duration wet and dry periods choose wet; ties within a group use a stable severity order.
        let index = weights.indices.filter { weights[$0] == maximum }.max()
        return index.map { categories[$0] }
    }

    private static func category(_ symbol: String) -> WeatherCategory? {
        let wetRoots = ["lightrain", "rain", "heavyrain", "lightsleet", "sleet", "heavysleet",
                        "lightsnow", "snow", "heavysnow"]
        let wetSuffixes = ["", "showers", "andthunder", "showersandthunder"]
        let officialTypo = ["lightssleetshowersandthunder", "lightssnowshowersandthunder"].contains(symbol)
        let knownWetSymbol = officialTypo || wetRoots.contains { root in wetSuffixes.contains { symbol == root + $0 } }
        guard knownWetSymbol || ["clearsky", "fair", "partlycloudy", "cloudy", "fog"].contains(symbol) else { return nil }
        if symbol.contains("thunder") { return .thunderstorm }
        if symbol.contains("sleet") { return .sleet }
        if symbol.contains("snow") { return .snow }
        if symbol.contains("rain") { return .rain }
        switch symbol {
        case "clearsky": return .clear
        case "fair", "partlycloudy": return .partlyCloudy
        case "cloudy": return .cloudy
        case "fog": return .fog
        default: return nil
        }
    }

    private struct Response: Decodable {
        let properties: Properties
        struct Properties: Decodable {
            let meta: Metadata?
            let timeseries: [Timestep]
        }
        struct Metadata: Decodable { let units: [String: String]? }
        struct Timestep: Decodable {
            let time: String
            let data: Periods
        }
        struct Periods: Decodable {
            let instant: Payload?
            let oneHour: Payload?
            let sixHours: Payload?
            let twelveHours: Payload?
            enum CodingKeys: String, CodingKey {
                case instant
                case oneHour = "next_1_hours"
                case sixHours = "next_6_hours"
                case twelveHours = "next_12_hours"
            }
            var periods: [(Int, Payload?)] { [(1, oneHour), (6, sixHours), (12, twelveHours)] }
        }
        struct Payload: Decodable {
            let summary: Summary?
            let details: Details?
        }
        struct Summary: Decodable {
            let symbolCode: String?
            enum CodingKeys: String, CodingKey { case symbolCode = "symbol_code" }
        }
        struct Details: Decodable {
            let airTemperature: Double?
            let maximumTemperature: Double?
            let precipitationAmount: Double?
            enum CodingKeys: String, CodingKey {
                case airTemperature = "air_temperature"
                case maximumTemperature = "air_temperature_max"
                case precipitationAmount = "precipitation_amount"
            }
        }
    }
}
