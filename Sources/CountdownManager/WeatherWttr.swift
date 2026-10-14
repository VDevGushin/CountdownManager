import CoreFoundation
import Foundation

package enum WttrWeatherProvider {
    package static func makeRequest(_ query: WeatherQuery) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "wttr.is"
        components.path = "/\(query.coordinates.latitude),\(query.coordinates.longitude)"
        components.queryItems = [
            URLQueryItem(name: "format", value: "j1"),
            URLQueryItem(name: "m", value: nil),
            URLQueryItem(name: "lang", value: "en"),
        ]
        guard let url = components.url else { throw WeatherProviderFailure.invalidData }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    package static func decode(_ data: Data, query: WeatherQuery) throws -> WeatherSourceBatch {
        try Task.checkCancellation()
        guard data.count <= 2_000_000,
              let response = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let days = response["weather"] as? [[String: Any]], days.count <= 16 else {
            throw WeatherProviderFailure.invalidData
        }
        var forecasts: [String: WeatherDailySample] = [:]
        try Task.checkCancellation()
        var seen = Set<String>()
        for day in days {
            try Task.checkCancellation()
            guard let key = day["date"] as? String else { throw WeatherProviderFailure.invalidData }
            guard seen.insert(key).inserted else { throw WeatherProviderFailure.invalidData }
            guard let period = query.interval(for: key) else { continue }
            // j1 dates are location civil dates, not device UTC timestamps. Eight fixed 3-hour
            // slots cannot establish a 23/25-hour DST day; do not invent coverage for that day.
            guard period.duration == 86_400 else { continue }
            let maximum = number(day["maxtempC"]).flatMap { (-100...70).contains($0) ? $0 : nil }
            let slots = completeSlots(day["hourly"])
            let condition = slots.flatMap(predominantCondition)
            let rainfall = slots.flatMap(liquidRainfall)
            guard maximum != nil || condition != nil || rainfall != nil else { continue }
            forecasts[key] = WeatherDailySample(
                dayKey: key, period: period, maximumTemperature: maximum,
                rainfallMillimeters: rainfall, condition: condition
            )
        }
        return WeatherSourceBatch(forecasts: forecasts)
    }

    private struct Slot {
        let code: Int?
        let amount: Double?
    }

    private static let liquidCodes: Set<Int> = [176, 263, 266, 293, 296, 299, 302, 305, 308, 353, 356, 359, 386, 389]

    private static func completeSlots(_ value: Any?) -> [Slot]? {
        guard let hours = value as? [[String: Any]], hours.count == 8 else { return nil }
        var slots: [Int: Slot] = [:]
        let expected = Set(stride(from: 0, through: 2_100, by: 300))
        for hour in hours {
            guard let time = integer(hour["time"]), expected.contains(time), slots[time] == nil else { return nil }
            slots[time] = Slot(code: integer(hour["weatherCode"]), amount: number(hour["precipMM"]))
        }
        guard Set(slots.keys) == expected else { return nil }
        return slots.keys.sorted().compactMap { slots[$0] }
    }

    private static func liquidRainfall(_ slots: [Slot]) -> Double? {
        var total = 0.0
        for slot in slots {
            guard let amount = slot.amount, amount >= 0,
                  let code = slot.code, let condition = category(code) else { return nil }
            // WWO precipMM is a 3-hour accumulated amount, not mm/hour or snow depth.
            // It may contain frozen/mixed precipitation; require a known liquid phase.
            let knownDryZero = amount == 0 && !condition.isWet
            guard liquidCodes.contains(code) || knownDryZero else { return nil }
            total += amount
        }
        return total.isFinite ? total : nil
    }

    private static func predominantCondition(_ slots: [Slot]) -> WeatherCategory? {
        var counts: [WeatherCategory: Int] = [:]
        for slot in slots {
            guard let code = slot.code, let condition = category(code) else { return nil }
            counts[condition, default: 0] += 1
        }
        let priority: [WeatherCategory] = [.clear, .partlyCloudy, .cloudy, .fog, .drizzle,
                                          .rain, .sleet, .snow, .thunderstorm]
        return priority.max { lhs, rhs in
            let left = counts[lhs, default: 0]
            let right = counts[rhs, default: 0]
            if left != right { return left < right }
            if lhs.isWet != rhs.isWet { return !lhs.isWet }
            return (priority.firstIndex(of: lhs) ?? 0) < (priority.firstIndex(of: rhs) ?? 0)
        }
    }

    // Official WWO condition codes: worldweatheronline.com/weather-api/api/docs/weather-icons.aspx
    private static func category(_ code: Int) -> WeatherCategory? {
        switch code {
        case 113: return .clear
        case 116: return .partlyCloudy
        case 119, 122: return .cloudy
        case 143, 248, 260: return .fog
        case 263, 266: return .drizzle
        case 176, 293, 296, 299, 302, 305, 308, 353, 356, 359: return .rain
        case 182, 185, 281, 284, 311, 314, 317, 320, 350, 362, 365, 374, 377: return .sleet
        case 179, 227, 230, 323, 326, 329, 332, 335, 338, 368, 371: return .snow
        case 200, 386, 389, 392, 395: return .thunderstorm
        default: return nil
        }
    }

    private static func number(_ value: Any?) -> Double? {
        let parsed: Double?
        if let string = value as? String {
            parsed = Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        } else if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            parsed = number.doubleValue
        } else {
            parsed = nil
        }
        return parsed.flatMap { $0.isFinite ? $0 : nil }
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = number(value), number.rounded() == number, (0...10_000).contains(number) else { return nil }
        return Int(number)
    }
}
