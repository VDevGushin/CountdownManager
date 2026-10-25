import CountdownCore
import SwiftUI

struct DesktopEventBrowser: View {
    @ObservedObject var store: Store
    @ObservedObject var weather: WeatherController
    let collection: DesktopEventCollection
    let mode: DesktopEventViewMode
    let selectedID: UUID?
    let isFiltering: Bool
    let select: (UUID) -> Void
    let resetFilters: () -> Void
    let create: () -> Void
    let canCreate: Bool
    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                overview
                if store.isLoading {
                    ProgressView("Загружаем события…").frame(maxWidth: .infinity).padding(.vertical, 48)
                } else if collection.events.isEmpty && !store.eventCreationIsAvailable {
                    unavailableState
                } else if collection.events.isEmpty {
                    emptyState
                } else {
                    if let favorite = collection.favorite {
                        eventButton(favorite, featured: true)
                    }
                    monthSections
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("desktop.browser")
        .uiSmokeControl(id: "desktop.browser")
    }

    private var monthSections: some View {
        DesktopEventFlowLayout(feedProgress: mode == .feed ? 1 : 0) {
            ForEach(collection.monthSections) { section in
                Text(section.title)
                    .font(.custom("Georgia", size: 20))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("desktop.month.\(section.id)")
                    .uiSmokeControl(id: "desktop.month.\(section.id)", value: { section.title })
                    .layoutValue(key: DesktopMonthHeadingKey.self, value: true)
                ForEach(section.items) { item in
                    eventButton(item, featured: false)
                }
            }
        }
        .animation(accessibilitySettings.prefersReducedMotion ? nil : .easeInOut(duration: 0.15), value: mode)
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Впереди").font(.custom("Georgia", size: 32)).tracking(-0.5)
                Spacer()
                Text(eventCountLabel(store.active.count))
                    .font(.system(size: 12))
                    .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
            }
            HStack(alignment: .center, spacing: 10) {
                Text(currentDayHeaderLabel(store.today))
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()
                    .uiSmokeControl(id: "desktop.overview.date", value: { currentDayHeaderLabel(store.today) })
                DesktopForecastSlot(forecast: weather.forecast(for: store.today), role: "overview")
            }
            .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
        }
        .uiSmokeControl(id: "desktop.overview.header")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isFiltering ? "Ничего не нашлось" : EventUIStrings.emptyTitle)
                .font(.custom("Georgia", size: 23))
            Text(isFiltering ? "Попробуйте другое название или покажите все события."
                 : "Добавьте событие — заметка и подготовка будут рядом с датой.")
                .font(.system(size: 13))
                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
            if isFiltering {
                Button("Показать все события", action: resetFilters)
            } else {
                Button("Создать день на сегодня", action: create).disabled(!canCreate)
            }
        }
        .padding(.vertical, 32)
        .accessibilityIdentifier("desktop.empty")
    }

    private var unavailableState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("События пока недоступны").font(.custom("Georgia", size: 23))
            Text("Не удалось получить доступ к списку событий. Сохранённые данные не заменяются пустым списком.")
                .font(.system(size: 13))
                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 32)
        .accessibilityIdentifier("desktop.unavailable")
    }

    private func eventButton(_ item: Countdown, featured: Bool) -> some View {
        Button { select(item.id) } label: {
            DesktopEventCard(item: item, today: store.today, primaryID: store.data.primaryID,
                             weather: weather, featured: featured, feed: !featured && mode == .feed,
                             selected: item.id == selectedID)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.attachments.isEmpty
            ? "Открыть событие: \(item.title)"
            : "Открыть событие: \(item.title). Вложения: \(item.attachments.count)")
        .accessibilityAddTraits(item.id == selectedID ? [.isSelected] : [])
        .accessibilityIdentifier("desktop.event.\(item.id.uuidString)")
        .uiSmokeControl(id: "desktop.event.\(item.id.uuidString)", action: { select(item.id) })
    }
}

private struct DesktopMonthHeadingKey: LayoutValueKey {
    static let defaultValue = false
}

private struct DesktopEventFlowLayout: Layout {
    var feedProgress: CGFloat

    var animatableData: CGFloat {
        get { feedProgress }
        set { feedProgress = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = max(0, proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 180)
        let frames = frames(width: width, subviews: subviews)
        return CGSize(width: width, height: frames.last?.maxY ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(width: bounds.width, subviews: subviews)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }

    private func frames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        interpolatedDesktopFrames(collection: frames(width: width, mode: .collection, subviews: subviews),
                                  feed: frames(width: width, mode: .feed, subviews: subviews),
                                  progress: feedProgress)
    }

    private func frames(width: CGFloat, mode: DesktopEventViewMode, subviews: Subviews) -> [CGRect] {
        let spacing: CGFloat = mode == .collection ? 12 : 10
        let columns = mode == .collection ? max(1, Int((width + 12) / 192)) : 1
        let cardWidth = max(0, (width - CGFloat(columns - 1) * spacing) / CGFloat(columns))
        var frames: [CGRect] = []
        var position = 0
        var rowTop: CGFloat = 0
        while position < subviews.count {
            if subviews[position][DesktopMonthHeadingKey.self] {
                if position > 0 { rowTop += 24 }
                let height = subviews[position].sizeThatFits(ProposedViewSize(width: width, height: nil)).height
                frames.append(CGRect(x: 0, y: rowTop, width: width, height: height))
                rowTop += height + 12
                position += 1
            } else {
                var end = position + 1
                while end < min(position + columns, subviews.count), !subviews[end][DesktopMonthHeadingKey.self] {
                    end += 1
                }
                let height = subviews[position..<end].map {
                    $0.sizeThatFits(ProposedViewSize(width: cardWidth, height: nil)).height
                }.max() ?? 0
                for column in 0..<(end - position) {
                    frames.append(CGRect(x: CGFloat(column) * (cardWidth + spacing), y: rowTop,
                                         width: cardWidth, height: height))
                }
                rowTop += height
                position = end
                if position < subviews.count, !subviews[position][DesktopMonthHeadingKey.self] { rowTop += spacing }
            }
        }
        return frames
    }
}

private struct DesktopOrdinaryCardLayout: Layout {
    var feedProgress: CGFloat

    var animatableData: CGFloat {
        get { feedProgress }
        set { feedProgress = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = max(0, proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 180)
        let height = max(0, proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? 0)
        let frames = frames(width: width, height: height, subviews: subviews)
        return CGSize(width: width, height: frames.map(\.maxY).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(width: bounds.width, height: bounds.height, subviews: subviews)) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                          anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }

    private func frames(width: CGFloat, height: CGFloat, subviews: Subviews) -> [CGRect] {
        interpolatedDesktopFrames(collection: frames(width: width, height: height, feed: false, subviews: subviews),
                                  feed: frames(width: width, height: height, feed: true, subviews: subviews),
                                  progress: feedProgress)
    }

    private func frames(width: CGFloat, height: CGFloat, feed: Bool, subviews: Subviews) -> [CGRect] {
        guard subviews.count == 5 else { return [] }
        let leaf = subviews[0].sizeThatFits(.unspecified)
        if feed {
            let remainingWidth = min(width * 0.3, subviews[4].sizeThatFits(.unspecified).width)
            let textX = leaf.width + 16
            let textWidth = max(0, width - textX)
            let titleWidth = max(0, textWidth - 12 - remainingWidth)
            let title = subviews[1].sizeThatFits(ProposedViewSize(width: titleWidth, height: nil))
            let metadata = subviews[2].sizeThatFits(ProposedViewSize(width: textWidth, height: nil))
            let completion = subviews[3].sizeThatFits(ProposedViewSize(width: textWidth, height: nil))
            let remaining = subviews[4].sizeThatFits(ProposedViewSize(width: remainingWidth, height: nil))
            let headerHeight = max(title.height, remaining.height)
            return [
                CGRect(origin: .zero, size: leaf),
                CGRect(x: textX, y: 0, width: titleWidth, height: title.height),
                CGRect(x: textX, y: headerHeight + 7, width: textWidth, height: metadata.height),
                CGRect(x: textX, y: headerHeight + 7 + metadata.height + (completion.height > 0 ? 7 : 0),
                       width: textWidth, height: completion.height),
                CGRect(x: width - remainingWidth, y: 0,
                       width: remainingWidth, height: remaining.height)
            ]
        }
        let completion = subviews[3].sizeThatFits(ProposedViewSize(width: max(0, width - leaf.width - 4), height: nil))
        let headerHeight = max(leaf.height, completion.height)
        let title = subviews[1].sizeThatFits(ProposedViewSize(width: width, height: nil))
        let metadata = subviews[2].sizeThatFits(ProposedViewSize(width: width, height: nil))
        let remaining = subviews[4].sizeThatFits(ProposedViewSize(width: width, height: nil))
        let titleTop = headerHeight + 14
        let metadataTop = titleTop + title.height + 14
        let remainingTop = max(height - remaining.height, metadataTop + metadata.height + 14)
        return [
            CGRect(origin: .zero, size: leaf),
            CGRect(x: 0, y: titleTop, width: width, height: title.height),
            CGRect(x: 0, y: metadataTop, width: width, height: metadata.height),
            CGRect(x: width - completion.width, y: 0, width: completion.width, height: completion.height),
            CGRect(x: 0, y: remainingTop, width: width, height: remaining.height)
        ]
    }
}

private func interpolatedDesktopFrames(collection: [CGRect], feed: [CGRect], progress: CGFloat) -> [CGRect] {
    let fraction = min(1, max(0, progress))
    return zip(collection, feed).map { start, end in
        CGRect(x: start.minX + (end.minX - start.minX) * fraction,
               y: start.minY + (end.minY - start.minY) * fraction,
               width: start.width + (end.width - start.width) * fraction,
               height: start.height + (end.height - start.height) * fraction)
    }
}

private struct DesktopEventCard: View {
    let item: Countdown
    let today: Day
    let primaryID: UUID?
    @ObservedObject var weather: WeatherController
    let featured: Bool
    let feed: Bool
    let selected: Bool
    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @Environment(\.colorScheme) private var colorScheme

    private var presentation: CountdownRowPresentation {
        CountdownRowPresentation(item: item, today: today, primaryID: primaryID)
    }
    private var accent: Color {
        AuroraInstrument.accent(for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast)
    }

    var body: some View {
        Group {
            if featured { featuredContent }
            else { ordinaryContent }
        }
        .transition(.identity)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(featured ? 22 : 16)
        .background(AuroraInstrument.surface(for: colorScheme, elevated: selected,
                                            highContrast: accessibilitySettings.prefersHighContrast))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(selected ? accent : AuroraInstrument.stroke(
                    for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast
                ), lineWidth: selected ? 2 : 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .uiSmokeControl(id: "desktop.presentation.\(item.id.uuidString)", value: {
            featured ? "favorite" : (feed ? "feed" : "collection")
        })
    }

    private var featuredContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Избранное", systemImage: "star.fill")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(accent)
                    Text(item.title).font(.custom("Georgia", size: 27)).tracking(-0.5)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                DesktopCalendarLeaf(item: item, featured: true, role: "browser").padding(.top, 9)
            }
            .uiSmokeControl(id: "desktop.favorite.identity.\(item.id)")
            dateAndWeather
                .uiSmokeControl(id: "desktop.favorite.metadata.\(item.id)")
            Text(presentation.remainingLabel).font(.custom("Georgia", size: 25))
                .foregroundStyle(timeColor)
            if presentation.completionLabel != nil || !item.attachments.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    DesktopCompletionLabel(presentation: presentation)
                    attachmentIndicator
                }
            }
        }
    }

    private var ordinaryContent: some View {
        DesktopOrdinaryCardLayout(feedProgress: feed ? 1 : 0) {
            DesktopCalendarLeaf(item: item, featured: false, role: "browser")
                .uiSmokeControl(id: "desktop.card.leaf.\(item.id)")
            VStack(alignment: .leading, spacing: 0) {
                Text(item.title).font(.system(size: 15, weight: .semibold))
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    .transaction { $0.animation = nil }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .uiSmokeControl(id: "desktop.card.title.\(item.id)")
            VStack(alignment: .leading, spacing: 0) {
                dateAndWeather.transaction { $0.animation = nil }
            }
                .clipped()
                .uiSmokeControl(id: "desktop.card.metadata.\(item.id)")
            completionLayout {
                DesktopCompletionLabel(presentation: presentation).transaction { $0.animation = nil }
                attachmentIndicator.transaction { $0.animation = nil }
            }
                .clipped()
                .uiSmokeControl(id: "desktop.card.completion.\(item.id)")
            VStack(alignment: feed ? .trailing : .leading, spacing: 0) {
                Text(presentation.remainingLabel).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(timeColor)
                    .multilineTextAlignment(feed ? .trailing : .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .transaction { $0.animation = nil }
            }
                .clipped()
                .uiSmokeControl(id: "desktop.collection.remaining.\(item.id.uuidString)", value: { presentation.remainingLabel })
        }
    }

    private var dateAndWeather: some View {
        metadataLayout {
            eventDate
                .fixedSize(horizontal: feed || featured, vertical: false)
            DesktopForecastSlot(forecast: item.showsWeather ? weather.forecast(for: item.date) : nil,
                                role: "browser.\(item.id)")
                .frame(width: feed || featured ? 52 : nil, alignment: .leading)
        }
        .font(.system(size: 11))
        .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
    }

    private var metadataLayout: AnyLayout {
        feed || featured ? AnyLayout(HStackLayout(alignment: .center, spacing: 8))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
    }

    private var completionLayout: AnyLayout {
        feed ? AnyLayout(HStackLayout(alignment: .center, spacing: 12))
            : AnyLayout(VStackLayout(alignment: .trailing, spacing: 6))
    }

    private var eventDate: some View {
        DesktopEventDateLabel(item: item, dateLabel: presentation.dateLabel, role: "browser")
    }

    @ViewBuilder
    private var attachmentIndicator: some View {
        if !item.attachments.isEmpty {
            Label(String(item.attachments.count), systemImage: "paperclip")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                .lineLimit(1)
                .fixedSize()
                .accessibilityLabel("Вложения: \(item.attachments.count)")
                .help("Вложения: \(item.attachments.count)")
                .accessibilityIdentifier("desktop.attachments.indicator.\(item.id.uuidString)")
                .uiSmokeControl(id: "desktop.attachments.indicator.\(item.id.uuidString)",
                                value: { String(item.attachments.count) })
        }
    }

    private var timeColor: Color {
        presentation.isToday ? AuroraInstrument.todayColor(
            for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast
        ) : accent
    }
}

struct DesktopCalendarLeaf: View {
    let item: Countdown
    let featured: Bool
    let role: String
    var body: some View {
        PlannerCalendarDateTile(monthControlID: "desktop.calendar.\(role).\(item.id.uuidString)",
                                day: item.date, isFeatured: featured)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(humanDateLabel(item.date))
            .padding(.trailing, 6)
            .padding(.bottom, 6)
    }
}

struct DesktopEventDateLabel: View {
    let item: Countdown
    let dateLabel: String
    let role: String

    private var metadataLabel: String {
        if let emoji = eventListEmoji(item.emoji) { return "\(emoji) \(dateLabel)" }
        return dateLabel
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let emoji = eventListEmoji(item.emoji) {
                Text(emoji).font(.system(size: 14))
            }
            Text(dateLabel)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metadataLabel)
        .accessibilityIdentifier("desktop.date.\(role).\(item.id.uuidString)")
        .uiSmokeControl(id: "desktop.date.\(role).\(item.id.uuidString)", value: { metadataLabel })
    }
}

struct DesktopForecastLabel: View {
    let forecast: DailyWeatherForecast

    var body: some View {
        Label(forecast.temperatureLabel, systemImage: forecast.symbolName)
            .font(.system(size: 11))
            .accessibilityLabel(forecast.accessibilityDescription)
    }
}

struct DesktopForecastSlot: View {
    let forecast: DailyWeatherForecast?
    let role: String

    var body: some View {
        HStack(spacing: 0) {
            if let forecast { DesktopForecastLabel(forecast: forecast).fixedSize() }
            Spacer(minLength: 0)
        }
        .frame(height: 16, alignment: .leading)
        .accessibilityHidden(forecast == nil)
        .uiSmokeControl(id: "desktop.weather.\(role)", value: { forecast == nil ? "absent" : "available" })
    }
}

struct DesktopCompletionLabel: View {
    let presentation: CountdownRowPresentation
    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let completion = presentation.completionLabel {
            Label(completion, systemImage: presentation.allSubtasksCompleted ? "checkmark.circle.fill" : "checklist")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(presentation.allSubtasksCompleted
                    ? AuroraInstrument.todayColor(for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast)
                    : AuroraInstrument.secondaryInk(for: colorScheme))
                .accessibilityLabel("Подготовка: \(presentation.completedSubtasks.count) из \(presentation.completedSubtasks.count + presentation.activeSubtasks.count)")
        }
    }
}
