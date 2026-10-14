import CountdownCore
import CountdownManagerUI
import Foundation

func testWeatherWttrNormalization() throws {
    let query = wttrFixtureQuery("2026-10-14", zone: "Europe/Moscow")
    let key = "2026-10-14"
    let day = query.interval(for: key)!
    let fixture = wttrFixtureDay(key)
    let full = try wttrSample(fixture, query: query)!
    precondition(full.period == day)
    precondition(full.period.start == ISO8601DateFormatter().date(from: "2026-10-13T21:00:00Z"))
    precondition(full.maximumTemperature == 12.4)
    precondition(full.rainfallMillimeters == 36, "Eight accumulated amounts must be summed once, never multiplied by three")
    precondition(full.condition == .rain)

    let request = try WttrWeatherProvider.makeRequest(query)
    precondition(request.url?.scheme == "https" && request.url?.host == "wttr.is")
    precondition(request.url?.path == "/55.75,37.62")
    let options = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
    precondition(options == [URLQueryItem(name: "format", value: "j1"), URLQueryItem(name: "m", value: nil),
                             URLQueryItem(name: "lang", value: "en")])
    precondition(request.value(forHTTPHeaderField: "Accept") == "application/json")
    precondition(request.timeoutInterval == 12 && !options.contains(where: { $0.name == "key" }))

    var numeric = fixture
    numeric["maxtempC"] = -4.5
    numeric["hourly"] = (0..<8).map { index -> [String: Any] in
        ["time": index * 300, "weatherCode": 113, "precipMM": 0]
    }
    let numbers = try wttrSample(numeric, query: query)!
    precondition(numbers.maximumTemperature == -4.5 && numbers.rainfallMillimeters == 0 && numbers.condition == .clear)

    try testWttrIncompleteSlots(fixture, query: query)
    try testWttrMissingMetrics(fixture, query: query)
    try testWttrConditions(fixture, query: query)
    try testWttrDates(fixture)
}

private func testWttrIncompleteSlots(_ fixture: [String: Any], query: WeatherQuery) throws {
    let original = fixture["hourly"] as? [[String: Any]] ?? []
    var variants = [Array(original.dropFirst())]
    var duplicate = original
    duplicate[7] = duplicate[0]
    variants.append(duplicate)
    for invalidTime: Any in ["1300", "2400", "300.5", NSNull(), true] {
        var changed = original
        changed[0]["time"] = invalidTime
        variants.append(changed)
    }
    for hours in variants {
        var changed = fixture
        changed["hourly"] = hours
        let sample = try wttrSample(changed, query: query)!
        precondition(sample.rainfallMillimeters == nil && sample.condition == nil)
        precondition(sample.maximumTemperature == 12.4, "A provided daily maximum does not require hourly samples")
    }
    for invalidAmount: Any in [NSNull(), "NaN", "Infinity", "-0.1", "1 mm", true, ["value": 2]] {
        var changed = fixture
        var hours = original
        hours[0]["precipMM"] = invalidAmount
        changed["hourly"] = hours
        let sample = try wttrSample(changed, query: query)!
        precondition(sample.rainfallMillimeters == nil && sample.condition == .rain)
    }
    var missing = fixture
    var hours = original
    hours[0].removeValue(forKey: "precipMM")
    missing["hourly"] = hours
    let missingSample = try wttrSample(missing, query: query)
    precondition(missingSample?.rainfallMillimeters == nil)
}

private func testWttrMissingMetrics(_ fixture: [String: Any], query: WeatherQuery) throws {
    for invalidMaximum: Any in [NSNull(), "NaN", "Infinity", "-101", "71", "12 C", true, [12]] {
        var changed = fixture
        changed["maxtempC"] = invalidMaximum
        let sample = try wttrSample(changed, query: query)!
        precondition(sample.maximumTemperature == nil && sample.rainfallMillimeters == 36)
    }
    var fahrenheitOnly = fixture
    fahrenheitOnly.removeValue(forKey: "maxtempC")
    fahrenheitOnly["maxtempF"] = "99"
    let fahrenheitSample = try wttrSample(fahrenheitOnly, query: query)
    precondition(fahrenheitSample?.maximumTemperature == nil)
    var otherUnits = fixture
    otherUnits["hourly"] = (0..<8).map { index -> [String: Any] in
        ["time": String(index * 300), "weatherCode": "296", "precipInches": "1.0", "totalSnow_cm": "20"]
    }
    let otherUnitsSample = try wttrSample(otherUnits, query: query)
    precondition(otherUnitsSample?.rainfallMillimeters == nil)
    var absent = fixture
    absent.removeValue(forKey: "maxtempC")
    absent.removeValue(forKey: "hourly")
    let absentSample = try wttrSample(absent, query: query)
    precondition(absentSample == nil)
}

private func testWttrConditions(_ fixture: [String: Any], query: WeatherQuery) throws {
    let groups: [(WeatherCategory, [Int])] = [
        (.clear, [113]), (.partlyCloudy, [116]), (.cloudy, [119, 122]), (.fog, [143, 248, 260]),
        (.drizzle, [263, 266]), (.rain, [176, 293, 296, 299, 302, 305, 308, 353, 356, 359]),
        (.sleet, [182, 185, 281, 284, 311, 314, 317, 320, 350, 362, 365, 374, 377]),
        (.snow, [179, 227, 230, 323, 326, 329, 332, 335, 338, 368, 371]),
        (.thunderstorm, [200, 386, 389, 392, 395]),
    ]
    for (category, codes) in groups {
        for code in codes {
            var changed = fixture
            changed["hourly"] = wttrFixtureHours(code: code)
            let sample = try wttrSample(changed, query: query)!
            precondition(sample.condition == category)
            if category == .snow || category == .sleet || [200, 392, 395].contains(code) {
                precondition(sample.rainfallMillimeters == nil, "Mixed/frozen amounts cannot be named liquid rainfall")
            }
        }
    }
    var mixed = fixture
    var hours = wttrFixtureHours(code: 296)
    hours[0]["weatherCode"] = "179"
    mixed["hourly"] = hours
    let snowInterval = try wttrSample(mixed, query: query)!
    precondition(snowInterval.condition == .rain && snowInterval.rainfallMillimeters == nil)

    for invalidCode: Any in ["999", "rain", true, NSNull()] {
        hours[0]["weatherCode"] = invalidCode
        mixed["hourly"] = hours
        let sample = try wttrSample(mixed, query: query)!
        precondition(sample.condition == nil && sample.rainfallMillimeters == nil, "Unknown conditions must not become clear")
    }
    var tie = fixture
    tie["hourly"] = (0..<8).map { index -> [String: Any] in
        ["time": String(index * 300), "weatherCode": index < 4 ? "113" : "296", "precipMM": "0"]
    }
    let tied = try wttrSample(tie, query: query)
    precondition(tied?.condition == .rain)
    tie["hourly"] = (0..<8).map { index -> [String: Any] in
        ["time": String(index * 300), "weatherCode": index < 5 ? "113" : "296", "precipMM": "0"]
    }
    let mostlyClear = try wttrSample(tie, query: query)
    precondition(mostlyClear?.condition == .clear)
}

private func testWttrDates(_ fixture: [String: Any]) throws {
    for key in ["2026-03-29", "2026-10-25"] {
        let query = wttrFixtureQuery(key, zone: "Europe/Berlin")
        var changed = fixture
        changed["date"] = key
        precondition(query.interval(for: key)?.duration != 86_400)
        let dstSample = try wttrSample(changed, query: query)
        precondition(dstSample == nil, "Fixed 3-hour slots cannot fabricate DST full-day coverage")
    }
    let query = wttrFixtureQuery("2026-10-14", zone: "Pacific/Kiritimati")
    let sample = try wttrSample(fixture, query: query)!
    precondition(sample.dayKey == "2026-10-14" && sample.period == query.interval(for: sample.dayKey))
    for date in ["2026-02-30", "2026-10-13", "2026-10-15", "20261014", "2026-10-14T00:00:00Z"] {
        var changed = fixture
        changed["date"] = date
        let outOfRange = try wttrSample(changed, query: query)
        precondition(outOfRange == nil)
    }
    let duplicate = try JSONSerialization.data(withJSONObject: ["weather": [fixture, fixture]])
    do {
        _ = try WttrWeatherProvider.decode(duplicate, query: query)
        preconditionFailure("Duplicate civil dates must be rejected")
    } catch {}
    for object: [String: Any] in [["weather": "wrong"], ["weather": [["hourly": []]]], [:]] {
        do {
            _ = try WttrWeatherProvider.decode(JSONSerialization.data(withJSONObject: object), query: query)
            preconditionFailure("Malformed response must be rejected")
        } catch {}
    }
}

private func wttrFixtureQuery(_ key: String, zone: String) -> WeatherQuery {
    let date = ISO8601DateFormatter().date(from: key + "T12:00:00Z")!
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return WeatherQuery(coordinates: WeatherCity.moscow.coordinates, timeZone: TimeZone(identifier: zone)!,
                        startDay: Day(date, calendar: calendar), dayCount: 1)!
}

private func wttrFixtureDay(_ key: String) -> [String: Any] {
    ["date": key, "maxtempC": "12.4", "maxtempF": "99", "totalSnow_cm": "50",
     "hourly": wttrFixtureHours(code: 296)]
}

private func wttrFixtureHours(code: Int) -> [[String: Any]] {
    (0..<8).map { index in
        ["time": String(index * 300), "weatherCode": String(code), "precipMM": String(index + 1), "tempC": "60"]
    }
}

private func wttrSample(_ day: [String: Any], query: WeatherQuery) throws -> WeatherDailySample? {
    let data = try JSONSerialization.data(withJSONObject: ["weather": [day]])
    return try WttrWeatherProvider.decode(data, query: query).forecasts[query.dayKeys[0]]
}
