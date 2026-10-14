import CountdownCore
import CountdownManagerUI
import Foundation

func testWeatherNormalization() throws {
    testWeatherQueryAndMissingValues()
    testWeatherConsensus()
    testWeatherPeriodSelection()
    try testOpenMeteoDailyNormalization()
    try testOpenMeteoDSTCoverage()
}

private func normalizationQuery(
    zone: TimeZone = TimeZone(secondsFromGMT: 0)!, day: Int = 1, month: Int = 5, dayCount: Int = 3
) -> WeatherQuery {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let date = calendar.date(from: DateComponents(year: 2026, month: month, day: day))!
    return WeatherQuery(
        coordinates: WeatherCoordinates(latitude: 12.34, longitude: 56.78)!, timeZone: zone,
        startDay: Day(date, calendar: calendar), dayCount: dayCount
    )!
}

private func testWeatherQueryAndMissingValues() {
    let query = normalizationQuery()
    precondition(query.dayKeys == ["2026-05-01", "2026-05-02", "2026-05-03"])
    precondition(query.interval(for: "2026-05-04") == nil)
    precondition(WeatherQuery(coordinates: query.coordinates, timeZone: query.timeZone, startDay: query.startDay, dayCount: 0) == nil)
    precondition(WeatherQuery(coordinates: query.coordinates, timeZone: query.timeZone, startDay: query.startDay, dayCount: 17) == nil)
    let longest = normalizationQuery(dayCount: 16)
    precondition(longest.dayKeys.count == 16 && weatherDayKey(longest.endDay) == "2026-05-16")

    let newYork = TimeZone(identifier: "America/New_York")!
    let spring = normalizationQuery(zone: newYork, day: 7, month: 3)
    precondition(spring.interval(for: "2026-03-07")!.duration == 24 * 3_600)
    precondition(spring.interval(for: "2026-03-08")!.duration == 23 * 3_600)
    precondition(spring.interval(for: "2026-03-09")!.duration == 24 * 3_600)
    precondition(spring.interval(for: "2026-03-07")!.end == spring.interval(for: "2026-03-08")!.start)
    let autumn = normalizationQuery(zone: newYork, day: 31, month: 10)
    precondition(autumn.interval(for: "2026-11-01")!.duration == 25 * 3_600)

    let key = query.dayKeys[0]
    let period = query.interval(for: key)!
    for temperature in [Double.nan, .infinity, -.infinity, -101, 71] {
        let sample = WeatherDailySample(dayKey: key, period: period, maximumTemperature: temperature, condition: .clear)
        precondition(sample.maximumTemperature == nil)
        let batches: [WeatherSource: WeatherSourceBatch] = [.openMeteo: WeatherSourceBatch(forecasts: [key: sample])]
        precondition(WeatherNormalizer.aggregate(batches, query: query).isEmpty)
    }
    for rain in [Double.nan, .infinity, -.infinity, -1] {
        precondition(WeatherDailySample(dayKey: key, period: period, rainfallMillimeters: rain).rainfallMillimeters == nil)
    }
    precondition(WeatherDailySample(dayKey: key, period: period, rainfallMillimeters: 0).rainfallMillimeters == 0)
    precondition(WeatherCategory(weatherCode: 97) == .thunderstorm)
    precondition(WeatherCategory(weatherCode: 999) == nil)
}

private func testWeatherConsensus() {
    let query = normalizationQuery()
    let key = query.dayKeys[0]
    let period = query.interval(for: key)!
    func batch(_ temperature: Double?, _ rain: Double?, _ category: WeatherCategory?) -> WeatherSourceBatch {
        WeatherSourceBatch(forecasts: [key: WeatherDailySample(
            dayKey: key, period: period, maximumTemperature: temperature,
            rainfallMillimeters: rain, condition: category
        )])
    }
    let votes: [WeatherSource: WeatherSourceBatch] = [
        .openMeteo: batch(10, 2, .clear), .metNorway: batch(12, 6, .rain), .wttr: batch(60, 100, .rain),
    ]
    let median = WeatherNormalizer.aggregate(votes, query: query)[key]!
    precondition(median.maximumTemperature == 12 && median.rainfallMillimeters == 6)
    precondition(median.condition == .rain && median.weatherCode == 63)
    precondition(median.contributors == Set(WeatherSource.allCases) && median.period == period)

    let tie: [WeatherSource: WeatherSourceBatch] = [.openMeteo: batch(10, nil, .clear), .metNorway: batch(14, nil, .rain)]
    let wetTie = WeatherNormalizer.aggregate(tie, query: query)[key]!
    precondition(wetTie.maximumTemperature == 12 && wetTie.rainfallMillimeters == nil && wetTie.condition == .rain)
    let dryMajority: [WeatherSource: WeatherSourceBatch] = [
        .openMeteo: batch(10, nil, .clear), .metNorway: batch(12, nil, .clear), .wttr: batch(14, nil, .rain),
    ]
    precondition(WeatherNormalizer.aggregate(dryMajority, query: query)[key]?.condition == .clear)
    let wetCategories: [WeatherSource: WeatherSourceBatch] = [.openMeteo: batch(10, nil, .rain), .metNorway: batch(14, nil, .snow)]
    precondition(WeatherNormalizer.aggregate(wetCategories, query: query)[key]?.condition == .snow)

    let incomplete: [WeatherSource: WeatherSourceBatch] = [.openMeteo: batch(10, nil, nil), .metNorway: batch(nil, 4, .rain)]
    let joined = WeatherNormalizer.aggregate(incomplete, query: query)[key]!
    precondition(joined.maximumTemperature == 10 && joined.rainfallMillimeters == 4 && joined.condition == .rain)
    let noCondition: [WeatherSource: WeatherSourceBatch] = [.openMeteo: batch(10, nil, nil), .metNorway: batch(12, 0, nil)]
    precondition(WeatherNormalizer.aggregate(noCondition, query: query).isEmpty)
    let empty: [WeatherSource: WeatherSourceBatch] = [.openMeteo: batch(nil, nil, nil)]
    precondition(WeatherNormalizer.aggregate(empty, query: query).isEmpty)
    let duplicateIdentity = Dictionary([(WeatherSource.openMeteo, batch(10, nil, .clear)), (.openMeteo, batch(14, nil, .rain))], uniquingKeysWith: { _, latest in latest })
    let oneVote = WeatherNormalizer.aggregate(duplicateIdentity, query: query)[key]!
    precondition(oneVote.contributors == [.openMeteo] && oneVote.maximumTemperature == 14 && oneVote.condition == .rain)
}

private func testWeatherPeriodSelection() {
    let query = normalizationQuery()
    let key = query.dayKeys[0]
    let full = query.interval(for: key)!
    let sixHours = DateInterval(start: full.start, duration: 6 * 3_600)
    let twelveHours = DateInterval(start: full.start, duration: 12 * 3_600)
    func batch(_ period: DateInterval, _ temperature: Double) -> WeatherSourceBatch {
        WeatherSourceBatch(forecasts: [key: WeatherDailySample(
            dayKey: key, period: period, maximumTemperature: temperature, rainfallMillimeters: temperature,
            condition: temperature == 18 ? .rain : .clear
        )])
    }
    let fullPreferred = WeatherNormalizer.aggregate([
        .openMeteo: batch(full, 18), .metNorway: batch(sixHours, 50), .wttr: batch(sixHours, 60),
    ], query: query)[key]!
    precondition(fullPreferred.maximumTemperature == 18 && fullPreferred.rainfallMillimeters == 18)
    precondition(fullPreferred.contributors == [.openMeteo] && fullPreferred.period == full)
    let largestGroup = WeatherNormalizer.aggregate([
        .openMeteo: batch(sixHours, 10), .metNorway: batch(sixHours, 14), .wttr: batch(twelveHours, 60),
    ], query: query)[key]!
    precondition(largestGroup.maximumTemperature == 12 && largestGroup.period == sixHours)
    precondition(largestGroup.contributors == [.openMeteo, .metNorway])
    let longestTie = WeatherNormalizer.aggregate([
        .openMeteo: batch(sixHours, 10), .metNorway: batch(twelveHours, 14),
    ], query: query)[key]!
    precondition(longestTie.period == twelveHours && longestTie.maximumTemperature == 14)
    let laterSixHours = DateInterval(start: full.start.addingTimeInterval(3_600), duration: 6 * 3_600)
    let earliestTie = WeatherNormalizer.aggregate([
        .openMeteo: batch(sixHours, 10), .metNorway: batch(laterSixHours, 14),
    ], query: query)[key]!
    precondition(earliestTie.period == sixHours && earliestTie.contributors == [.openMeteo])
    let outside = DateInterval(start: full.start.addingTimeInterval(-3_600), duration: full.duration)
    precondition(WeatherNormalizer.aggregate([.openMeteo: batch(outside, 10)], query: query).isEmpty)
    let mismatched = WeatherDailySample(dayKey: query.dayKeys[1], period: full, maximumTemperature: 10, condition: .clear)
    precondition(WeatherNormalizer.aggregate([.openMeteo: WeatherSourceBatch(forecasts: [key: mismatched])], query: query).isEmpty)
}

private func openMeteoFixture(_ query: WeatherQuery, offset: Int = 0) -> [String: Any] {
    [
        "timezone": query.timeZone.identifier, "utc_offset_seconds": offset,
        "daily_units": ["time": "iso8601", "weather_code": "wmo code", "temperature_2m_max": "°C", "rain_sum": "mm"],
        "daily": ["time": query.dayKeys, "weather_code": [0, 63, 73], "temperature_2m_max": [10.5, 12, -1], "rain_sum": [0, 4.2, 0]],
    ]
}

private func decodeOpenMeteo(_ fixture: [String: Any], query: WeatherQuery) throws -> WeatherSourceBatch {
    try OpenMeteoWeatherAdapter.decode(JSONSerialization.data(withJSONObject: fixture), query: query)
}

private func rejectsOpenMeteo(_ fixture: [String: Any], query: WeatherQuery) {
    do {
        _ = try decodeOpenMeteo(fixture, query: query)
        preconditionFailure("Malformed Open-Meteo payload must be rejected")
    } catch {}
}

private func testOpenMeteoDailyNormalization() throws {
    let query = normalizationQuery()
    let request = try OpenMeteoWeatherAdapter.makeRequest(query)
    let url = request.url!
    precondition(url.scheme == "https" && url.host == "api.open-meteo.com")
    let parameters = Dictionary(URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    precondition(parameters["timezone"] == query.timeZone.identifier && parameters["timezone"] != "auto")
    precondition(parameters["daily"] == "weather_code,temperature_2m_max,rain_sum")
    precondition(parameters["start_date"] == query.dayKeys.first && parameters["end_date"] == query.dayKeys.last)
    precondition(parameters["temperature_unit"] == "celsius" && parameters["precipitation_unit"] == "mm")
    let fixture = openMeteoFixture(query)
    let decoded = try decodeOpenMeteo(fixture, query: query)
    precondition(decoded.forecasts.count == 3 && decoded.forecasts[query.dayKeys[1]]?.rainfallMillimeters == 4.2)
    precondition(decoded.forecasts[query.dayKeys[2]]?.condition == .snow)
    precondition(decoded.expiresAt == nil && decoded.lastModified == nil)
    for (field, value) in [("temperature_2m_max", "°F"), ("rain_sum", "inch"), ("weather_code", "unknown"), ("time", "unixtime")] {
        var invalid = fixture
        guard var units = invalid["daily_units"] as? [String: Any] else {
            preconditionFailure("Expected fixture units")
        }
        units[field] = value
        invalid["daily_units"] = units
        rejectsOpenMeteo(invalid, query: query)
    }
    var wrongZone = fixture
    wrongZone["timezone"] = "America/New_York"
    rejectsOpenMeteo(wrongZone, query: query)
    var wrongOffset = fixture
    wrongOffset["utc_offset_seconds"] = Int.min
    rejectsOpenMeteo(wrongOffset, query: query)
    var duplicate = fixture
    guard var daily = duplicate["daily"] as? [String: Any] else {
        preconditionFailure("Expected fixture daily object")
    }
    daily["time"] = [query.dayKeys[0], query.dayKeys[0], query.dayKeys[1]]
    duplicate["daily"] = daily
    rejectsOpenMeteo(duplicate, query: query)
    daily["time"] = query.dayKeys
    daily["temperature_2m_max"] = [10]
    duplicate["daily"] = daily
    rejectsOpenMeteo(duplicate, query: query)

    var missing = fixture
    missing["daily"] = ["time": query.dayKeys, "weather_code": [NSNull(), 999, 0], "temperature_2m_max": [NSNull(), 200, 10], "rain_sum": [NSNull(), -2, 0]]
    let unavailable = try decodeOpenMeteo(missing, query: query)
    precondition(unavailable.forecasts[query.dayKeys[0]]?.maximumTemperature == nil)
    precondition(unavailable.forecasts[query.dayKeys[0]]?.condition == nil && unavailable.forecasts[query.dayKeys[0]]?.rainfallMillimeters == nil)
    precondition(unavailable.forecasts[query.dayKeys[1]]?.maximumTemperature == nil && unavailable.forecasts[query.dayKeys[1]]?.condition == nil)
    let result = WeatherNormalizer.aggregate([.openMeteo: unavailable], query: query)
    precondition(result.keys.sorted() == [query.dayKeys[2]])
    missing["daily"] = ["time": query.dayKeys, "weather_code": [0, 0, 0], "temperature_2m_max": [10, 11, 12], "precipitation_sum": [99, 99, 99]]
    let noLiquidRain = try decodeOpenMeteo(missing, query: query)
    precondition(noLiquidRain.forecasts.values.allSatisfy { $0.rainfallMillimeters == nil })
}

private func testOpenMeteoDSTCoverage() throws {
    let zone = TimeZone(identifier: "America/New_York")!
    let spring = normalizationQuery(zone: zone, day: 7, month: 3)
    let springResult = try decodeOpenMeteo(openMeteoFixture(spring, offset: -5 * 3_600), query: spring)
    precondition(springResult.forecasts.keys.sorted() == ["2026-03-07"])
    let autumn = normalizationQuery(zone: zone, day: 31, month: 10)
    let autumnResult = try decodeOpenMeteo(openMeteoFixture(autumn, offset: -4 * 3_600), query: autumn)
    precondition(autumnResult.forecasts["2026-11-01"]?.period.duration == 24 * 3_600)
    precondition(autumnResult.forecasts["2026-11-01"]?.period != autumn.interval(for: "2026-11-01"))
    precondition(autumnResult.forecasts["2026-11-02"] == nil)
}
