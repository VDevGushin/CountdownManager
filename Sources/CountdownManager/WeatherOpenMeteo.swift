import CountdownCore
import Foundation

package enum OpenMeteoWeatherAdapter {
    package static func makeRequest(_ query: WeatherQuery) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "api.open-meteo.com"
        components.path = "/v1/forecast"
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(query.coordinates.latitude)),
            URLQueryItem(name: "longitude", value: String(query.coordinates.longitude)),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,rain_sum"),
            URLQueryItem(name: "temperature_unit", value: "celsius"),
            URLQueryItem(name: "precipitation_unit", value: "mm"),
            URLQueryItem(name: "timeformat", value: "iso8601"),
            URLQueryItem(name: "timezone", value: query.timeZone.identifier),
            URLQueryItem(name: "start_date", value: weatherDayKey(query.startDay)),
            URLQueryItem(name: "end_date", value: weatherDayKey(query.endDay)),
        ]
        guard let url = components.url else { throw WeatherProviderFailure.invalidData }
        return URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
    }

    package static func decode(_ data: Data, query: WeatherQuery) throws -> WeatherSourceBatch {
        try Task.checkCancellation()
        guard data.count <= 128_000 else { throw WeatherProviderFailure.invalidData }
        let response = try JSONDecoder().decode(Response.self, from: data)
        try Task.checkCancellation()
        guard let responseZone = TimeZone(identifier: response.timezone), responseZone == query.timeZone,
              (-14 * 3_600...14 * 3_600).contains(response.utcOffsetSeconds),
              let fixedZone = TimeZone(secondsFromGMT: response.utcOffsetSeconds),
              response.dailyUnits.time == "iso8601", response.daily.time.count <= query.dayCount else {
            throw WeatherProviderFailure.invalidData
        }
        let daily = response.daily
        try validate(daily.maximumTemperature, unit: response.dailyUnits.maximumTemperature, expectedUnit: "°C", count: daily.time.count)
        try validate(daily.rainfall, unit: response.dailyUnits.rainfall, expectedUnit: "mm", count: daily.time.count)
        try validate(daily.weatherCode, unit: response.dailyUnits.weatherCode?.lowercased(), expectedUnit: "wmo code", count: daily.time.count)
        var fixedCalendar = Calendar(identifier: .gregorian)
        fixedCalendar.timeZone = fixedZone
        var forecasts: [String: WeatherDailySample] = [:]
        var seen = Set<String>()
        for index in daily.time.indices {
            try Task.checkCancellation()
            let key = daily.time[index]
            guard let localDay = query.interval(for: key), seen.insert(key).inserted else {
                throw WeatherProviderFailure.invalidData
            }
            let day = Day(localDay.start, calendar: query.calendar)
            guard let fixedStart = fixedCalendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day)) else {
                throw WeatherProviderFailure.invalidData
            }
            let actualPeriod = DateInterval(start: fixedStart, duration: 86_400)
            // Open-Meteo daily sums use a fixed 24-hour offset, even across DST changes.
            // Never clip a sum/max to different hours and describe it as local-day data.
            guard actualPeriod.start >= localDay.start, actualPeriod.end <= localDay.end else { continue }
            forecasts[key] = WeatherDailySample(
                dayKey: key, period: actualPeriod,
                maximumTemperature: daily.maximumTemperature?[index],
                rainfallMillimeters: daily.rainfall?[index],
                condition: daily.weatherCode?[index].flatMap { WeatherCategory(weatherCode: $0) }
            )
        }
        return WeatherSourceBatch(forecasts: forecasts)
    }

    private static func validate<T>(_ values: [T?]?, unit: String?, expectedUnit: String, count: Int) throws {
        guard let values else { return }
        guard values.count == count, unit == expectedUnit else { throw WeatherProviderFailure.invalidData }
    }

    private struct Response: Decodable {
        let timezone: String
        let utcOffsetSeconds: Int
        let dailyUnits: Units
        let daily: Daily

        enum CodingKeys: String, CodingKey {
            case timezone, daily
            case utcOffsetSeconds = "utc_offset_seconds"
            case dailyUnits = "daily_units"
        }

        struct Units: Decodable {
            let time: String
            let weatherCode: String?
            let maximumTemperature: String?
            let rainfall: String?

            enum CodingKeys: String, CodingKey {
                case time
                case weatherCode = "weather_code"
                case maximumTemperature = "temperature_2m_max"
                case rainfall = "rain_sum"
            }
        }

        struct Daily: Decodable {
            let time: [String]
            let weatherCode: [Int?]?
            let maximumTemperature: [Double?]?
            let rainfall: [Double?]?

            enum CodingKeys: String, CodingKey {
                case time
                case weatherCode = "weather_code"
                case maximumTemperature = "temperature_2m_max"
                case rainfall = "rain_sum"
            }
        }
    }
}
