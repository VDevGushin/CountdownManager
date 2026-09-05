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

public struct Subtask: Identifiable, Codable, Equatable {
    public static let maximumCount = 5
    public static let maximumTextLength = 50

    public let id: UUID
    public var text: String
    public var isCompleted: Bool

    public init(id: UUID = UUID(), text: String, isCompleted: Bool = false) throws {
        self.id = id
        self.text = text
        self.isCompleted = isCompleted
        try normalizeAndValidate()
    }

    private enum CodingKeys: String, CodingKey { case id, text, isCompleted }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        text = try values.decode(String.self, forKey: .text)
        isCompleted = try values.decode(Bool.self, forKey: .isCompleted)
        try validateStoredValue()
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(text, forKey: .text)
        try values.encode(isCompleted, forKey: .isCompleted)
    }

    mutating func normalizeAndValidate() throws {
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        try validateStoredValue()
    }

    func validateStoredValue() throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CountdownError.subtaskText
        }
        guard text.count <= Self.maximumTextLength else {
            throw CountdownError.subtaskLength
        }
    }
}

public struct Countdown: Identifiable, Codable, Equatable {
    public let id: UUID
    public var title: String
    public var note: String?
    public var date: Day
    public var emoji: String
    public var subtasks: [Subtask]

    public init(
        id: UUID = UUID(),
        title: String,
        note: String? = nil,
        date: Day,
        emoji: String,
        subtasks: [Subtask] = []
    ) {
        self.id = id
        self.title = title
        self.note = note
        self.date = date
        self.emoji = emoji
        self.subtasks = subtasks
    }

    private enum CodingKeys: String, CodingKey { case id, title, note, date, emoji, subtasks }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        title = try values.decode(String.self, forKey: .title)
        note = try values.decodeIfPresent(String.self, forKey: .note)
        date = try values.decode(Day.self, forKey: .date)
        emoji = try values.decode(String.self, forKey: .emoji)
        subtasks = try values.decodeIfPresent([Subtask].self, forKey: .subtasks) ?? []
        guard subtasks.count <= Subtask.maximumCount else { throw CountdownError.subtaskCount }
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(title, forKey: .title)
        try values.encodeIfPresent(note, forKey: .note)
        try values.encode(date, forKey: .date)
        try values.encode(emoji, forKey: .emoji)
        try values.encode(subtasks, forKey: .subtasks)
    }
}

public enum CountdownError: LocalizedError {
    case title, note, date, emoji, eventNotFound, subtaskNotFound
    case subtaskText, subtaskLength, subtaskCount

    public var errorDescription: String? {
        switch self {
        case .title: return "Укажите название события."
        case .note: return "Заметка должна быть не длиннее 280 символов."
        case .date: return "Дата события недопустима. Выберите будущую дату."
        case .emoji: return "Укажите один emoji, например ☀️ или 🎉."
        case .eventNotFound: return "Событие больше недоступно."
        case .subtaskNotFound: return "Подзадача больше недоступна."
        case .subtaskText: return "Введите текст подзадачи."
        case .subtaskLength: return "Подзадача должна быть не длиннее 50 символов."
        case .subtaskCount: return "У события может быть не больше пяти подзадач."
        }
    }
}

public struct CountdownData: Codable, Equatable {
    public var items: [Countdown] = []
    public var primaryID: UUID?
    public init() {}

    func validateSubtasksForPersistence() throws {
        for item in items {
            guard item.subtasks.count <= Subtask.maximumCount else { throw CountdownError.subtaskCount }
            for subtask in item.subtasks { try subtask.validateStoredValue() }
        }
    }

    public mutating func normalize(today: Day) {
        items.removeAll { $0.date < today }
        if !items.contains(where: { $0.id == primaryID }) {
            primaryID = items.enumerated().min {
                $0.element.date == $1.element.date
                    ? $0.offset < $1.offset
                    : $0.element.date < $1.element.date
            }?.element.id
        }
    }

    public mutating func save(_ item: Countdown, primary: Bool, today: Day) throws {
        var cleaned = item
        cleaned.title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned.note = item.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.note?.isEmpty == true { cleaned.note = nil }
        cleaned.emoji = item.emoji.trimmingCharacters(in: .whitespacesAndNewlines)
        for index in cleaned.subtasks.indices {
            try cleaned.subtasks[index].normalizeAndValidate()
        }
        guard !cleaned.title.isEmpty else { throw CountdownError.title }
        guard (cleaned.note?.count ?? 0) <= 280 else { throw CountdownError.note }
        let existing = items.first(where: { $0.id == item.id })
        let keepsToday = existing?.date == today && cleaned.date == today
        guard cleaned.date > today || keepsToday else { throw CountdownError.date }
        guard Self.isEmoji(cleaned.emoji) else { throw CountdownError.emoji }
        guard cleaned.subtasks.count <= Subtask.maximumCount else { throw CountdownError.subtaskCount }
        normalize(today: today)
        if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = cleaned }
        else { items.append(cleaned) }
        if primary || primaryID == nil { primaryID = item.id }
        // An existing primary stays primary until another event is selected.
    }

    public mutating func addSubtask(to eventID: UUID, text: String, today: Day) throws -> UUID {
        normalize(today: today)
        guard let eventIndex = items.firstIndex(where: { $0.id == eventID }) else {
            throw CountdownError.eventNotFound
        }
        guard items[eventIndex].subtasks.count < Subtask.maximumCount else {
            throw CountdownError.subtaskCount
        }
        let subtask = try Subtask(text: text)
        items[eventIndex].subtasks.append(subtask)
        return subtask.id
    }

    public mutating func editSubtask(
        eventID: UUID,
        subtaskID: UUID,
        text: String,
        today: Day
    ) throws {
        normalize(today: today)
        guard let eventIndex = items.firstIndex(where: { $0.id == eventID }) else {
            throw CountdownError.eventNotFound
        }
        guard let subtaskIndex = items[eventIndex].subtasks.firstIndex(where: { $0.id == subtaskID }) else {
            throw CountdownError.subtaskNotFound
        }
        var cleaned = items[eventIndex].subtasks[subtaskIndex]
        cleaned.text = text
        try cleaned.normalizeAndValidate()
        items[eventIndex].subtasks[subtaskIndex] = cleaned
    }

    public mutating func deleteSubtask(eventID: UUID, subtaskID: UUID, today: Day) throws {
        normalize(today: today)
        guard let eventIndex = items.firstIndex(where: { $0.id == eventID }) else {
            throw CountdownError.eventNotFound
        }
        guard items[eventIndex].subtasks.contains(where: { $0.id == subtaskID }) else {
            throw CountdownError.subtaskNotFound
        }
        items[eventIndex].subtasks.removeAll { $0.id == subtaskID }
    }

    public mutating func toggleSubtask(eventID: UUID, subtaskID: UUID, today: Day) throws {
        normalize(today: today)
        guard let eventIndex = items.firstIndex(where: { $0.id == eventID }) else {
            throw CountdownError.eventNotFound
        }
        guard let subtaskIndex = items[eventIndex].subtasks.firstIndex(where: { $0.id == subtaskID }) else {
            throw CountdownError.subtaskNotFound
        }
        items[eventIndex].subtasks[subtaskIndex].isCompleted.toggle()
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
