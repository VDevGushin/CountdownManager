import Foundation
import CountdownCore

package enum EventUIStrings {
    package static let addEvent = "Добавить событие"
    package static let newEvent = "Новое событие"
    package static let editEvent = "Редактировать событие"
    package static let createDay = "Создать день"
    package static let newDay = "Новый день"
    package static let todayExpiryNotice = "После окончания дня событие будет удалено, включая незавершённые подзадачи."
    package static let deleteEvent = "Удалить событие?"
    package static let emptyTitle = "Пока нет событий"
    package static let emptyMessage = "Добавь событие и выбери дату — приложение покажет, сколько дней до него осталось."
}

package enum EventEmojiCatalog {
    package static let presets = ["☀️", "✈️", "🎉", "🎂", "🎄", "❤️", "🚀", "🏖️"]
}

package enum EditorLayout {
    /// Space reserved between focusable controls and the clipping ScrollView viewport.
    package static let focusRingInset: CGFloat = 4
    /// Keeps editor controls clear of the overlay scroll indicator.
    package static let scrollIndicatorClearance: CGFloat = 10
    /// Separates the scrolling form from persistent editor actions.
    package static let actionAreaSpacing: CGFloat = 16
}

package enum SubtaskDisclosureMotion: Equatable {
    case immediate
    case heightAndOpacity(duration: TimeInterval)
}

package func subtaskDisclosureMotion(reduceMotion: Bool) -> SubtaskDisclosureMotion {
    reduceMotion ? .immediate : .heightAndOpacity(duration: 0.2)
}

package func editorSubtaskMotion(reduceMotion: Bool) -> SubtaskDisclosureMotion {
    reduceMotion ? .immediate : .heightAndOpacity(duration: 0.1)
}

package enum EditorEmojiPickerState: Equatable {
    case closed
    case presets
    case catalog(page: Int)

    package var isOpen: Bool { self != .closed }
    package var isCatalog: Bool {
        if case .catalog = self { return true }
        return false
    }
    package var pageIndex: Int {
        if case let .catalog(page) = self { return page }
        return 0
    }

    package mutating func toggle() {
        self = isOpen ? .closed : .presets
    }

    package mutating func showCatalog() {
        guard self == .presets else { return }
        self = .catalog(page: 0)
    }

    package mutating func setPage(_ page: Int, pageCount: Int) {
        guard isCatalog, pageCount > 0 else { return }
        self = .catalog(page: min(max(page, 0), pageCount - 1))
    }

    package mutating func close() {
        self = .closed
    }
}

package enum EditorEmojiPickerMotion: Equatable {
    case immediate
    case heightAndOpacity(duration: TimeInterval)
}

package func editorEmojiPickerMotion(reduceMotion: Bool) -> EditorEmojiPickerMotion {
    reduceMotion ? .immediate : .heightAndOpacity(duration: 0.2)
}

package let editorEmojiValueTransitionDuration: TimeInterval = 0.12

package struct CountdownRowPresentation: Equatable {
    package let note: String?
    package let dateLabel: String
    package let remainingLabel: String
    package let remainingDays: Int
    package let remainingUnit: String?
    package let dateAndRemainingLabel: String
    package let isToday: Bool
    package let isPrimary: Bool
    package let isFeatured: Bool
    package let activeSubtasks: [Subtask]
    package let completedSubtasks: [Subtask]
    package let completionLabel: String?

    package init(item: Countdown, today: Day, primaryID: UUID?, featuredID: UUID? = nil) {
        remainingDays = item.date.days(from: today)
        note = item.note
        dateLabel = humanDateLabel(item.date)
        remainingLabel = countdownLabel(remainingDays)
        remainingUnit = remainingDays == 0 ? nil : remainingLabel.split(separator: " ").dropFirst().joined(separator: " ")
        dateAndRemainingLabel = "\(dateLabel) · \(remainingLabel)"
        isToday = remainingDays == 0
        isPrimary = primaryID == item.id
        isFeatured = (featuredID ?? primaryID) == item.id
        activeSubtasks = item.subtasks.filter { !$0.isCompleted }
        completedSubtasks = item.subtasks.filter(\.isCompleted)
        completionLabel = item.subtasks.isEmpty
            ? nil
            : "\(completedSubtasks.count)/\(item.subtasks.count)"
    }
}

package struct CalendarDateTilePresentation: Equatable {
    package let monthLabel: String
    package let dayLabel: String

    package init(day: Day) {
        let months = [
            "ЯНВ", "ФЕВР", "МАРТ", "АПР", "МАЙ", "ИЮНЬ",
            "ИЮЛЬ", "АВГ", "СЕНТ", "ОКТ", "НОЯБ", "ДЕК"
        ]
        monthLabel = months[day.month - 1]
        dayLabel = String(day.day)
    }
}

package func eventListEmoji(_ emoji: String) -> String? {
    emoji.isEmpty || emoji == "📅" ? nil : emoji
}

package func humanDateLabel(_ day: Day) -> String {
    let months = [
        "января", "февраля", "марта", "апреля", "мая", "июня",
        "июля", "августа", "сентября", "октября", "ноября", "декабря"
    ]
    guard (1...12).contains(day.month) else { return "\(day.day).\(day.month).\(day.year)" }
    return "\(day.day) \(months[day.month - 1]) \(day.year)"
}

package func subtaskDisclosureLabel(isExpanded: Bool, completion: String) -> String {
    "\(isExpanded ? "▾" : "▸") \(completion)"
}

package func statusBarTitle(data: CountdownData, today: Day) -> String {
    guard let primary = activeCountdowns(in: data, today: today).first else { return "◷ Countdown" }
    let emoji = primary.emoji.isEmpty ? "📅" : primary.emoji
    return "\(emoji) \(countdownLabel(primary.date.days(from: today)))"
}

package func activeCountdowns(in data: CountdownData, today: Day) -> [Countdown] {
    data.items.enumerated()
        .filter { $0.element.date >= today }
        .sorted {
            let lhsPrimary = $0.element.id == data.primaryID
            let rhsPrimary = $1.element.id == data.primaryID
            if lhsPrimary != rhsPrimary { return lhsPrimary }
            if $0.element.date != $1.element.date { return $0.element.date < $1.element.date }
            return $0.offset < $1.offset
        }
        .map(\.element)
}

package func editorCanSave(
    title: String,
    note: String,
    date: Day,
    emoji: String,
    subtasks: [Subtask] = [],
    today: Day
) -> Bool {
    let cleanedEmoji = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
    let dateIsValid = date >= today
    let subtasksAreValid = subtasks.count <= Subtask.maximumCount
        && subtasks.allSatisfy {
            let cleaned = $0.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return !cleaned.isEmpty && cleaned.count <= Subtask.maximumTextLength
        }
    return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && dateIsValid
        && note.trimmingCharacters(in: .whitespacesAndNewlines).count <= 280
        && (cleanedEmoji.isEmpty || CountdownData.isEmoji(cleanedEmoji))
        && subtasksAreValid
}

package enum EditorFocusTarget: Hashable {
    case title
    case note
    case emoji
    case subtask(UUID)
}

package func russianWeekdayTitle(_ day: Day) -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let titles = ["Воскресенье", "Понедельник", "Вторник", "Среда", "Четверг", "Пятница", "Суббота"]
    return titles[calendar.component(.weekday, from: day.date(calendar: calendar)) - 1]
}

package struct DayCreationPreset: Equatable {
    package let day: Day

    package init(day: Day) {
        self.day = day
    }

    package static func today(_ today: Day) -> DayCreationPreset {
        DayCreationPreset(day: today)
    }

    package static func tomorrow(after today: Day, calendar: Calendar = Day.calendar) -> DayCreationPreset? {
        guard let date = calendar.date(byAdding: .day, value: 1, to: today.date(calendar: calendar)) else {
            return nil
        }
        return DayCreationPreset(day: Day(date, calendar: calendar))
    }
}

package func eventCountLabel(_ count: Int) -> String {
    let noun: String
    if (11...14).contains(count % 100) {
        noun = "событий"
    } else {
        switch count % 10 {
        case 1: noun = "событие"
        case 2...4: noun = "события"
        default: noun = "событий"
        }
    }
    return "\(count) \(noun)"
}

package func currentDayHeaderLabel(_ day: Day) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ru_RU")
    formatter.calendar = Day.calendar
    formatter.timeZone = Day.calendar.timeZone
    formatter.dateFormat = "EEE, d MMMM"
    let label = formatter.string(from: day.date())
    return label.prefix(1).uppercased() + label.dropFirst()
}

package func applicationVersionLabel(bundle: Bundle = .main) -> String? {
    guard let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
          !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return "Версия \(version)"
}

package struct EventEditorDraft: Equatable {
    package var title: String
    package var note: String
    package var emoji: String
    package var subtasks: [Subtask]
    package var showsWeather: Bool
    private var followsDayDate = false

    package init(item: Countdown?) {
        title = item?.title ?? ""
        note = item?.note ?? ""
        emoji = item?.emoji ?? ""
        subtasks = item?.subtasks ?? []
        showsWeather = item?.showsWeather ?? false
    }

    package init(day: Day) {
        title = russianWeekdayTitle(day)
        note = ""
        emoji = ""
        subtasks = []
        showsWeather = true
        followsDayDate = true
    }

    package mutating func setTitle(_ title: String) {
        guard title != self.title else { return }
        self.title = title
        followsDayDate = false
    }

    package mutating func updateDayTitle(for day: Day) {
        guard followsDayDate else { return }
        title = russianWeekdayTitle(day)
    }

    @discardableResult
    package mutating func addSubtask() -> EditorFocusTarget? {
        guard subtasks.count < Subtask.maximumCount,
              var subtask = try? Subtask(text: "Новая подзадача") else { return nil }
        subtask.text = ""
        subtasks.append(subtask)
        return .subtask(subtask.id)
    }

    @discardableResult
    package mutating func replaceEmoji(with symbol: String) -> Bool {
        guard CountdownData.isEmoji(symbol) else { return false }
        emoji = symbol
        return true
    }

    package mutating func clearEmoji() {
        emoji = ""
    }

    package func countdown(id: UUID, date: Day) -> Countdown {
        Countdown(
            id: id,
            title: title,
            note: note,
            date: date,
            emoji: emoji,
            subtasks: subtasks,
            showsWeather: showsWeather
        )
    }
}

package struct SubtaskDisclosurePersistence {
    private let defaults: UserDefaults
    private let key: String

    package init(defaults: UserDefaults = .standard, key: String = "expandedSubtasksByEvent") {
        self.defaults = defaults
        self.key = key
    }

    package func isExpanded(eventID: UUID) -> Bool {
        let values = defaults.dictionary(forKey: key) as? [String: Bool] ?? [:]
        return values[eventID.uuidString] ?? true
    }

    package func setExpanded(_ isExpanded: Bool, eventID: UUID) {
        var values = defaults.dictionary(forKey: key) as? [String: Bool] ?? [:]
        values[eventID.uuidString] = isExpanded
        defaults.set(values, forKey: key)
    }

    package func remove(eventID: UUID) {
        var values = defaults.dictionary(forKey: key) as? [String: Bool] ?? [:]
        values.removeValue(forKey: eventID.uuidString)
        defaults.set(values, forKey: key)
    }
}
