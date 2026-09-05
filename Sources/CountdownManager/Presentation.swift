import Foundation
import CountdownCore

package struct CountdownRowPresentation: Equatable {
    package let note: String?
    package let remainingLabel: String
    package let isToday: Bool
    package let isPrimary: Bool

    package init(item: Countdown, today: Day, primaryID: UUID?) {
        let remainingDays = item.date.days(from: today)
        note = item.note
        remainingLabel = countdownLabel(remainingDays)
        isToday = remainingDays == 0
        isPrimary = primaryID == item.id
    }
}

package func activeCountdowns(in data: CountdownData, today: Day) -> [Countdown] {
    data.items.filter { $0.date >= today }.sorted {
        if ($0.id == data.primaryID) != ($1.id == data.primaryID) {
            return $0.id == data.primaryID
        }
        return $0.date == $1.date
            ? $0.title.localizedStandardCompare($1.title) == .orderedAscending
            : $0.date < $1.date
    }
}

package func editorCanSave(
    title: String,
    note: String,
    date: Day,
    emoji: String,
    today: Day
) -> Bool {
    !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        && date > today
        && note.trimmingCharacters(in: .whitespacesAndNewlines).count <= 280
        && CountdownData.isEmoji(emoji.trimmingCharacters(in: .whitespacesAndNewlines))
}
