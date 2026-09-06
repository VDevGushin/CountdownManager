import Foundation
import CountdownCore

package enum EventUIStrings {
    package static let addEvent = "Добавить событие"
    package static let newEvent = "Новое событие"
    package static let editEvent = "Редактировать событие"
    package static let deleteEvent = "Удалить событие?"
    package static let emptyTitle = "Пока нет событий"
    package static let emptyMessage = "Добавь событие и выбери дату — приложение покажет, сколько дней до него осталось."
}

package enum EventEmojiCatalog {
    package static let presets = ["☀️", "✈️", "🎉", "🎂", "🎄", "❤️", "🚀", "🏖️"]
    package static let all = [
        "😀", "😎", "🥳", "😍", "🤩", "😊", "🤗", "🫶",
        "☀️", "🌙", "⭐️", "🌈", "❄️", "🌸", "🍂", "🔥",
        "✈️", "🚆", "🚗", "🚢", "🏖️", "🏕️", "🏔️", "🏠",
        "🎉", "🎂", "🎄", "🎁", "🎓", "💍", "👶", "❤️",
        "🚀", "💼", "📚", "🎵", "🎬", "⚽️", "🏆", "🎯",
        "🍕", "☕️", "🍷", "🌍", "📅", "⏳", "💡", "✅"
    ]
}

package enum EditorLayout {
    /// Space reserved between focusable controls and the clipping ScrollView viewport.
    package static let focusRingInset: CGFloat = 4
}

package struct CountdownRowPresentation: Equatable {
    package let note: String?
    package let dateLabel: String
    package let remainingLabel: String
    package let dateAndRemainingLabel: String
    package let isToday: Bool
    package let isPrimary: Bool
    package let activeSubtasks: [Subtask]
    package let completedSubtasks: [Subtask]
    package let completionLabel: String?

    package init(item: Countdown, today: Day, primaryID: UUID?) {
        let remainingDays = item.date.days(from: today)
        note = item.note
        dateLabel = humanDateLabel(item.date)
        remainingLabel = countdownLabel(remainingDays)
        dateAndRemainingLabel = "\(dateLabel) · \(remainingLabel)"
        isToday = remainingDays == 0
        isPrimary = primaryID == item.id
        activeSubtasks = item.subtasks.filter { !$0.isCompleted }
        completedSubtasks = item.subtasks.filter(\.isCompleted)
        completionLabel = item.subtasks.isEmpty
            ? nil
            : "\(completedSubtasks.count)/\(item.subtasks.count)"
    }
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
    return "\(primary.emoji) \(countdownLabel(primary.date.days(from: today)))"
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
    today: Day,
    originalDate: Day? = nil
) -> Bool {
    let dateIsValid = date > today || (originalDate == today && date == today)
    let subtasksAreValid = subtasks.count <= Subtask.maximumCount
        && subtasks.allSatisfy {
            let cleaned = $0.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return !cleaned.isEmpty && cleaned.count <= Subtask.maximumTextLength
        }
    return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && dateIsValid
        && note.trimmingCharacters(in: .whitespacesAndNewlines).count <= 280
        && CountdownData.isEmoji(emoji.trimmingCharacters(in: .whitespacesAndNewlines))
        && subtasksAreValid
}

package enum EditorFocusTarget: Hashable {
    case title
    case note
    case subtask(UUID)
}

package struct EventEditorDraft: Equatable {
    package var title: String
    package var note: String
    package var emoji: String
    package var subtasks: [Subtask]

    package init(item: Countdown?) {
        title = item?.title ?? ""
        note = item?.note ?? ""
        emoji = item?.emoji ?? "🎉"
        subtasks = item?.subtasks ?? []
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
        guard EventEmojiCatalog.all.contains(symbol), CountdownData.isEmoji(symbol) else { return false }
        emoji = symbol
        return true
    }

    package func countdown(id: UUID, date: Day) -> Countdown {
        Countdown(
            id: id,
            title: title,
            note: note,
            date: date,
            emoji: emoji,
            subtasks: subtasks
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
