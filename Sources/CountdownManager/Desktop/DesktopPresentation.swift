import Foundation
import CountdownCore

package enum DesktopEventViewMode: String, CaseIterable {
    case collection
    case feed

    package var title: String {
        switch self {
        case .collection: "Коллекция"
        case .feed: "Лента"
        }
    }

    package var systemImage: String {
        switch self {
        case .collection: "square.grid.2x2"
        case .feed: "list.bullet"
        }
    }
}

package struct DesktopEventMonthSection: Equatable, Identifiable {
    package let id: Int
    package let title: String
    package let items: [Countdown]
}

package struct DesktopEventCollection: Equatable {
    package let favorite: Countdown?
    package let ordinary: [Countdown]
    package let monthSections: [DesktopEventMonthSection]

    package var events: [Countdown] {
        (favorite.map { [$0] } ?? []) + ordinary
    }

    package init(items: [Countdown], today: Day, primaryID: UUID?, query: String) {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = items.enumerated().filter { entry in
            let item = entry.element
            return item.date >= today
                && (search.isEmpty || item.title.localizedCaseInsensitiveContains(search)
                    || (item.note?.localizedCaseInsensitiveContains(search) ?? false))
        }.sorted { first, second in
            if first.element.date != second.element.date { return first.element.date < second.element.date }
            return first.offset < second.offset
        }.map(\.element)
        favorite = matching.first { $0.id == primaryID }
        ordinary = matching.filter { $0.id != primaryID }
        monthSections = Self.groupedByMonth(ordinary)
    }

    private static func groupedByMonth(_ items: [Countdown]) -> [DesktopEventMonthSection] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.calendar = Day.calendar
        formatter.timeZone = Day.calendar.timeZone
        formatter.dateFormat = "LLLL yyyy"
        return Dictionary(grouping: items) { $0.date.year * 12 + $0.date.month }
            .sorted { $0.key < $1.key }
            .map { entry in
                let label = formatter.string(from: entry.value[0].date.date())
                return DesktopEventMonthSection(
                    id: entry.key,
                    title: label.prefix(1).uppercased() + label.dropFirst(),
                    items: entry.value
                )
            }
    }
}

package func desktopSelection(current: UUID?, available: [Countdown]) -> UUID? {
    if let current, available.contains(where: { $0.id == current }) { return current }
    return available.first?.id
}

package func desktopMinimumPaneWidth(contentWidth: CGFloat) -> CGFloat {
    max(320, max(0, contentWidth - 1) / 3)
}

package func desktopEventAccessibilityLabel(_ item: Countdown) -> String {
    var label = "Открыть событие: \(item.title)"
    if !item.attachments.isEmpty { label += ". Вложения: \(item.attachments.count)" }
    if !item.links.isEmpty { label += ". Ссылки: \(item.links.count)" }
    return label
}
