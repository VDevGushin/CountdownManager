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
}

package struct DesktopEventCollection: Equatable {
    package let favorite: Countdown?
    package let ordinary: [Countdown]

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
    }
}

package func desktopSelection(current: UUID?, available: [Countdown]) -> UUID? {
    if let current, available.contains(where: { $0.id == current }) { return current }
    return available.first?.id
}

package func desktopMinimumPaneWidth(contentWidth: CGFloat) -> CGFloat {
    max(320, max(0, contentWidth - 1) / 3)
}
