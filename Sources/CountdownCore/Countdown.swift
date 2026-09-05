import Foundation

/// A civil date, independent of the time zone in which it was created.
public struct Day: Codable, Equatable, Comparable {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(_ date: Date, calendar: Calendar = Self.calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        year = parts.year!; month = parts.month!; day = parts.day!
    }

    private enum CodingKeys: String, CodingKey { case year, month, day }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let year = try values.decode(Int.self, forKey: .year)
        let month = try values.decode(Int.self, forKey: .month)
        let day = try values.decode(Int.self, forKey: .day)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: year, month: month, day: day)
        guard (1...9999).contains(year),
              let date = calendar.date(from: components) else {
            throw DecodingError.dataCorruptedError(
                forKey: .day,
                in: values,
                debugDescription: "Invalid Gregorian date"
            )
        }
        let roundTrip = calendar.dateComponents([.year, .month, .day], from: date)
        guard roundTrip.year == year, roundTrip.month == month, roundTrip.day == day else {
            throw DecodingError.dataCorruptedError(
                forKey: .day,
                in: values,
                debugDescription: "Invalid Gregorian date"
            )
        }

        self.year = year
        self.month = month
        self.day = day
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(year, forKey: .year)
        try values.encode(month, forKey: .month)
        try values.encode(day, forKey: .day)
    }

    public static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }

    public func date(calendar: Calendar = Self.calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    public func days(from today: Day, calendar: Calendar = Self.calendar) -> Int {
        calendar.dateComponents([.day], from: today.date(calendar: calendar), to: date(calendar: calendar)).day ?? 0
    }

    public static func < (lhs: Day, rhs: Day) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

public struct Countdown: Identifiable, Codable, Equatable {
    public let id: UUID
    public var title: String
    public var note: String?
    public var date: Day
    public var emoji: String

    public init(id: UUID = UUID(), title: String, note: String? = nil, date: Day, emoji: String) {
        self.id = id; self.title = title; self.note = note; self.date = date; self.emoji = emoji
    }
}

public enum CountdownError: LocalizedError {
    case title, note, date, emoji
    public var errorDescription: String? {
        switch self {
        case .title: return "Укажите название."
        case .note: return "Заметка должна быть не длиннее 280 символов."
        case .date: return "Дата должна быть позже сегодняшней."
        case .emoji: return "Укажите один emoji, например ☀️ или 🎉."
        }
    }
}

public struct CountdownData: Codable, Equatable {
    public var items: [Countdown] = []
    public var primaryID: UUID?
    public init() {}

    public mutating func normalize(today: Day) {
        items.removeAll { $0.date < today }
        if !items.contains(where: { $0.id == primaryID }) {
            primaryID = items.sorted {
                $0.date == $1.date ? $0.id.uuidString < $1.id.uuidString : $0.date < $1.date
            }.first?.id
        }
    }

    public mutating func save(_ item: Countdown, primary: Bool, today: Day) throws {
        var cleaned = item
        cleaned.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.note = item.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.note?.isEmpty == true { cleaned.note = nil }
        cleaned.emoji = item.emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.title.isEmpty else { throw CountdownError.title }
        guard (cleaned.note?.count ?? 0) <= 280 else { throw CountdownError.note }
        guard cleaned.date > today else { throw CountdownError.date }
        guard Self.isEmoji(cleaned.emoji) else { throw CountdownError.emoji }
        normalize(today: today)
        if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = cleaned }
        else { items.append(cleaned) }
        if primary || primaryID == nil { primaryID = item.id }
        // An existing primary stays primary until another countdown is selected.
    }

    public mutating func delete(_ id: UUID, today: Day) {
        items.removeAll { $0.id == id }
        normalize(today: today)
    }

    public static func isEmoji(_ value: String) -> Bool {
        guard value.count == 1 else { return false }
        return value.unicodeScalars.contains { $0.properties.isEmojiPresentation }
            || (value.unicodeScalars.contains { $0.properties.isEmoji }
                && value.unicodeScalars.contains { $0.value == 0xFE0F || $0.value == 0x20E3 })
    }
}

public func dayLabel(_ count: Int) -> String {
    let tail = abs(count) % 100
    let unit = abs(count) % 10
    let word = (11...14).contains(tail) ? "дней" : (unit == 1 ? "день" : ((2...4).contains(unit) ? "дня" : "дней"))
    return "\(count) \(word)"
}

public func countdownLabel(_ count: Int) -> String {
    count == 0 ? "Сегодня" : dayLabel(count)
}
