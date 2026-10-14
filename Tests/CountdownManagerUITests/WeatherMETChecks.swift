import CountdownCore
import CountdownManagerUI
import Foundation

func testWeatherMETNormalization() throws {
    let query = metFixtureQuery("2026-10-14", zone: "UTC")
    let day = query.interval(for: "2026-10-14")!
    let full = try metFixture(day, hours: 0..<24, sixHourMaximum: true)
    let sample = try METNorwayWeatherProvider.decode(full, query: query).forecasts["2026-10-14"]!
    precondition(sample.period == day)
    precondition(sample.maximumTemperature == 28)
    precondition(sample.rainfallMillimeters == 24, "Overlapping 1/6/12 hour totals must never be added together")
    precondition(sample.condition == .rain)

    let request = try METNorwayWeatherProvider.makeRequest(query)
    precondition(request.url?.scheme == "https" && request.url?.host == "api.met.no")
    precondition(request.url?.path == "/weatherapi/locationforecast/2.0/complete")
    precondition(request.value(forHTTPHeaderField: "User-Agent")?.contains("github.com/VDevGushin/CountdownManager") == true)

    let missingUnits = try metFixture(day, hours: 0..<24, sixHourMaximum: true, units: [:])
    let untyped = try METNorwayWeatherProvider.decode(missingUnits, query: query).forecasts["2026-10-14"]!
    precondition(untyped.maximumTemperature == nil && untyped.rainfallMillimeters == nil && untyped.condition == .rain)
    let wrongUnits = try metFixture(day, hours: 0..<24, sixHourMaximum: true,
                                   units: ["air_temperature_max": "fahrenheit", "precipitation_amount": "inches"])
    let wrong = try METNorwayWeatherProvider.decode(wrongUnits, query: query).forecasts["2026-10-14"]!
    precondition(wrong.maximumTemperature == nil && wrong.rainfallMillimeters == nil)

    let partial = try metFixture(day, hours: 12..<24, sixHourMaximum: true)
    let remaining = try METNorwayWeatherProvider.decode(partial, query: query).forecasts["2026-10-14"]!
    precondition(remaining.period.start == day.start.addingTimeInterval(12 * 3_600))
    precondition(remaining.period.end == day.end && remaining.period != day)
    precondition(remaining.maximumTemperature == 28 && remaining.rainfallMillimeters == 12)

    let sampledOnly = try metFixture(day, hours: 0..<24)
    let sampled = try METNorwayWeatherProvider.decode(sampledOnly, query: query)
    precondition(sampled.forecasts["2026-10-14"]?.maximumTemperature == 60,
                 "A complete Celsius hourly forecast grid supplies a sampled daily maximum")
    try testMETHourlyMaximumFailures(day, query: query)
    let nullRain = try metFixture(day, hours: 0..<24, nullRainHour: 0)
    let missing = try METNorwayWeatherProvider.decode(nullRain, query: query).forecasts["2026-10-14"]!
    precondition(missing.period == day && missing.rainfallMillimeters == nil, "Missing rainfall is never zero")

    for symbol in ["snow", "sleet", "heavysnowandthunder", "mysteryrain"] {
        let data = try metFixture(day, hours: 0..<24, symbol: symbol)
        let decoded = try METNorwayWeatherProvider.decode(data, query: query).forecasts["2026-10-14"]
        precondition(decoded?.rainfallMillimeters == nil, "Mixed or untyped precipitation cannot be called rainfall")
        if symbol == "mysteryrain" { precondition(decoded?.condition == nil) }
    }
    for symbol in ["lightssleetshowersandthunder", "lightssnowshowersandthunder"] {
        let data = try metFixture(day, hours: 0..<24, symbol: symbol)
        let decoded = try METNorwayWeatherProvider.decode(data, query: query).forecasts["2026-10-14"]!
        precondition(decoded.condition == .thunderstorm && decoded.rainfallMillimeters == nil)
    }
    let mixed = try metFixture(day, hours: 0..<24, sixHourMaximum: true, mixedSnowHour: 0)
    let mixedSample = try METNorwayWeatherProvider.decode(mixed, query: query).forecasts["2026-10-14"]!
    precondition(mixedSample.rainfallMillimeters == nil, "A coarse rain symbol cannot override known finer snow")
    let tie = try metFixture(day, hours: 0..<24, dryHours: 12)
    let tied = try METNorwayWeatherProvider.decode(tie, query: query)
    precondition(tied.forecasts["2026-10-14"]?.condition == .rain)
    let mostlyDry = try metFixture(day, hours: 0..<24, dryHours: 18)
    let mostlyDrySample = try METNorwayWeatherProvider.decode(mostlyDry, query: query)
    precondition(mostlyDrySample.forecasts["2026-10-14"]?.condition == .clear)

    for (key, expectedHours) in [("2026-03-29", 23), ("2026-10-25", 25)] {
        let dstQuery = metFixtureQuery(key, zone: "Europe/Berlin")
        let dstDay = dstQuery.interval(for: key)!
        precondition(dstDay.duration == Double(expectedHours) * 3_600)
        let data = try metFixture(dstDay, hours: 0..<expectedHours, sixHourMaximum: true)
        let dst = try METNorwayWeatherProvider.decode(data, query: dstQuery).forecasts[key]!
        precondition(dst.period == dstDay && dst.rainfallMillimeters == Double(expectedHours))
        precondition(dst.maximumTemperature == 60, "Complete hourly DST coverage supplies the fallback without interpolation")
    }
    try testMETCrossingIntervals()
}

private func metFixtureQuery(_ key: String, zone: String) -> WeatherQuery {
    let date = ISO8601DateFormatter().date(from: key + "T12:00:00Z")!
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return WeatherQuery(coordinates: WeatherCity.moscow.coordinates, timeZone: TimeZone(identifier: zone)!,
                        startDay: Day(date, calendar: calendar), dayCount: 1)!
}

private func metFixture(
    _ day: DateInterval, hours: Range<Int>, sixHourMaximum: Bool = false,
    units: [String: String] = ["air_temperature": "celsius", "air_temperature_max": "celsius", "precipitation_amount": "mm"],
    symbol: String = "rain", nullRainHour: Int? = nil, dryHours: Int = 0, mixedSnowHour: Int? = nil
) throws -> Data {
    let formatter = ISO8601DateFormatter()
    var timesteps: [[String: Any]] = []
    for hour in hours {
        let condition = hour == mixedSnowHour ? "snow" : (hour < dryHours ? "clearsky" : symbol)
        let precipitation: Any = hour == nullRainHour ? NSNull() : (hour < dryHours ? 0.0 : 1.0)
        var periods: [String: Any] = [
            "instant": ["details": ["air_temperature": 60.0]],
            "next_1_hours": ["summary": ["symbol_code": condition + "_day"],
                             "details": ["precipitation_amount": precipitation]],
        ]
        if sixHourMaximum, hour.isMultiple(of: 6) {
            periods["next_6_hours"] = ["summary": ["symbol_code": symbol],
                                       "details": ["air_temperature_max": Double(hour + 10), "precipitation_amount": 60.0]]
            if hour.isMultiple(of: 12) {
                periods["next_12_hours"] = ["summary": ["symbol_code": symbol],
                                            "details": ["precipitation_amount": 120.0]]
            }
        }
        timesteps.append(["time": formatter.string(from: day.start.addingTimeInterval(Double(hour) * 3_600)), "data": periods])
    }
    timesteps.append(["time": formatter.string(from: day.start.addingTimeInterval(Double(hours.upperBound) * 3_600)),
                      "data": ["instant": ["details": ["air_temperature": 65.0]]]])
    return try JSONSerialization.data(withJSONObject: ["properties": ["meta": ["units": units], "timeseries": timesteps]])
}

private func testMETHourlyMaximumFailures(_ day: DateInterval, query: WeatherQuery) throws {
    let complete = try metFixture(day, hours: 0..<24)
    let timesteps = try metFixtureRows(complete)
    func modified(_ rows: [[String: Any]], units: [String: String] = ["air_temperature": "celsius"]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["properties": ["meta": ["units": units], "timeseries": rows]])
    }
    var missing = timesteps
    missing.remove(at: 7)
    var null = timesteps
    guard var nullData = null[7]["data"] as? [String: Any] else { preconditionFailure("Invalid fixture") }
    nullData["instant"] = ["details": ["air_temperature": NSNull()]]
    null[7]["data"] = nullData
    var invalid = timesteps
    guard var invalidData = invalid[7]["data"] as? [String: Any] else { preconditionFailure("Invalid fixture") }
    invalidData["instant"] = ["details": ["air_temperature": 999.0]]
    invalid[7]["data"] = invalidData
    var nonfinite = timesteps
    invalidData["instant"] = ["details": ["air_temperature": "NaN"]]
    nonfinite[7]["data"] = invalidData
    let sixHourPeriods = try metFixture(day, hours: 0..<24, sixHourMaximum: true)
    let sparse = try metFixtureRows(sixHourPeriods).enumerated().filter { $0.offset.isMultiple(of: 6) }.map(\.element)
    let cases = try [
        modified(missing), modified(null), modified(invalid), modified(nonfinite), modified(sparse),
        modified(timesteps, units: [:]), modified(timesteps, units: ["air_temperature": "fahrenheit"]),
        metFixture(day, hours: 12..<24),
    ]
    for data in cases {
        do {
            let decoded = try METNorwayWeatherProvider.decode(data, query: query)
            precondition(decoded.forecasts["2026-10-14"]?.maximumTemperature == nil,
                         "Incomplete, invalid, untyped and sparse hourly grids cannot claim a daily maximum")
        } catch { precondition(!(error is CancellationError)) }
    }
}

private func metFixtureRows(_ data: Data) throws -> [[String: Any]] {
    guard let raw = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let properties = raw["properties"] as? [String: Any],
          let rows = properties["timeseries"] as? [[String: Any]] else { preconditionFailure("Invalid fixture") }
    return rows
}

private func testMETCrossingIntervals() throws {
    let query = metFixtureQuery("2026-10-14", zone: "Europe/Moscow")
    let formatter = ISO8601DateFormatter()
    let utcMidnight = formatter.date(from: "2026-10-14T00:00:00Z")!
    let timesteps = (0..<4).map { index -> [String: Any] in
        ["time": formatter.string(from: utcMidnight.addingTimeInterval(Double(index * 6) * 3_600)),
         "data": ["next_6_hours": ["summary": ["symbol_code": "rain"],
                                   "details": ["air_temperature_max": Double(10 + index), "precipitation_amount": 2.0]]]]
    }
    let data = try JSONSerialization.data(withJSONObject: ["properties": [
        "meta": ["units": ["air_temperature_max": "celsius", "precipitation_amount": "mm"]], "timeseries": timesteps,
    ]])
    let sample = try METNorwayWeatherProvider.decode(data, query: query).forecasts["2026-10-14"]!
    precondition(sample.period == DateInterval(start: utcMidnight, duration: 18 * 3_600))
    precondition(sample.rainfallMillimeters == 6 && sample.maximumTemperature == 12)
    precondition(sample.period != query.interval(for: "2026-10-14"), "UTC intervals crossing local midnight must not be prorated")
}
