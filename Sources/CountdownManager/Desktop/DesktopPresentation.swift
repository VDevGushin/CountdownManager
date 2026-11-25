import Foundation
import CountdownCore

package enum DesktopEventViewMode: String, CaseIterable {
    case collection
    case feed

    package var title: String {
        switch self {
        case .collection: AppText.string("desktop.mode.collection")
        case .feed: AppText.string("desktop.mode.feed")
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

package struct DesktopSearchMatch {
    enum Kind {
        case subtask, attachment, link

        var label: String {
            switch self {
            case .subtask: AppText.string("subtask.title")
            case .attachment: AppText.string("attachment.title")
            case .link: AppText.string("link.title")
            }
        }
    }

    let kind: Kind
    package let text: String
    let isCompleted: Bool

    package var accessibilitySuffix: String { AppText.string("desktop.browser.matchedItem", kind.label, text) }
}

package struct DesktopEventSearch {
    package let query: String

    package init(_ query: String) {
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    package func ranges(in text: String) -> [Range<String.Index>] {
        guard !query.isEmpty else { return [] }
        var matches: [Range<String.Index>] = []
        var start = text.startIndex
        while start < text.endIndex,
              let match = text.range(of: query, options: .caseInsensitive,
                                     range: start..<text.endIndex, locale: .current), !match.isEmpty {
            matches.append(match)
            start = match.upperBound
        }
        return matches
    }

    package func matches(_ text: String) -> Bool {
        !query.isEmpty && text.localizedCaseInsensitiveContains(query)
    }

    package func firstSubtask(in item: Countdown) -> Subtask? {
        checklistDisplayOrder(item.subtasks).first { matches($0.text) }
    }

    package func cardMatch(in item: Countdown) -> DesktopSearchMatch? {
        guard !query.isEmpty else { return nil }
        if let task = firstSubtask(in: item) {
            return DesktopSearchMatch(kind: .subtask, text: task.text, isCompleted: task.isCompleted)
        }
        return firstMaterialMatch(in: item)
    }

    fileprivate func firstMaterialMatch(in item: Countdown) -> DesktopSearchMatch? {
        if let file = item.attachments.first(where: { matches($0.name) }) {
            return DesktopSearchMatch(kind: .attachment, text: file.name, isCompleted: false)
        }
        for link in item.links {
            if matches(link.name) {
                return DesktopSearchMatch(kind: .link, text: link.name, isCompleted: false)
            }
            if matches(link.address) {
                return DesktopSearchMatch(kind: .link, text: link.address, isCompleted: false)
            }
        }
        return nil
    }

    package func snippet(in text: String) -> (context: String, matchingText: String)? {
        guard !query.isEmpty,
              let match = text.range(of: query, options: .caseInsensitive, locale: .current), !match.isEmpty else { return nil }
        let start = text.distance(from: text.startIndex, to: match.lowerBound) <= 12 ? text.startIndex
            : text.index(match.lowerBound, offsetBy: -8, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(match.upperBound, offsetBy: 24, limitedBy: text.endIndex) ?? text.endIndex
        let context = (start > text.startIndex ? "…" : "") + text[start..<end] + (end < text.endIndex ? "…" : "")
        return (context, String(text[match]))
    }
}

package struct DesktopEventCollection: Equatable {
    package let favorite: Countdown?
    package let ordinary: [Countdown]
    package let monthSections: [DesktopEventMonthSection]
    package let pastItems: [Countdown]

    package var events: [Countdown] {
        (favorite.map { [$0] } ?? []) + ordinary
    }

    package init(items: [Countdown], today: Day, primaryID: UUID?, query: String) {
        let search = DesktopEventSearch(query)
        let matching = items.enumerated().filter { entry in
            let item = entry.element
            return item.isAvailable(on: today)
                && (search.query.isEmpty || search.matches(item.displayTitle)
                    || item.note.map(search.matches) == true
                    || item.subtasks.contains { search.matches($0.text) }
                    || search.firstMaterialMatch(in: item) != nil)
        }.sorted { first, second in
            let firstIsPast = first.element.date < today
            let secondIsPast = second.element.date < today
            if firstIsPast != secondIsPast { return !firstIsPast }
            if first.element.date != second.element.date {
                return firstIsPast ? first.element.date > second.element.date : first.element.date < second.element.date
            }
            return first.offset < second.offset
        }.map(\.element)
        favorite = matching.first { $0.id == primaryID }
        ordinary = matching.filter { $0.id != primaryID }
        monthSections = Self.groupedByMonth(ordinary.filter { $0.date >= today })
        pastItems = ordinary.filter { $0.date < today }
    }

    private static func groupedByMonth(_ items: [Countdown]) -> [DesktopEventMonthSection] {
        let formatter = DateFormatter()
        formatter.locale = AppText.language.locale
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

package func desktopSelection(current: UUID?, available: [UUID]) -> UUID? {
    if let current, available.contains(current) { return current }
    return available.first
}

package func desktopMinimumPaneWidth(contentWidth: CGFloat) -> CGFloat {
    max(320, max(0, contentWidth - 1) / 3)
}

package func desktopEventAccessibilityLabel(_ item: Countdown) -> String {
    var label = AppText.string("desktop.accessibility.openEvent", item.displayTitle)
    if !item.attachments.isEmpty { label += AppText.string("desktop.accessibility.attachmentCount", "\(item.attachments.count)") }
    if !item.links.isEmpty { label += AppText.string("desktop.accessibility.linkCount", "\(item.links.count)") }
    return label
}
