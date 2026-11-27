import CountdownCore
import SwiftUI

struct DesktopEventBrowser: View {
    @ObservedObject var store: Store
    @ObservedObject var weather: WeatherController
    let section: PlannerSection
    let collection: DesktopEventCollection
    let records: [UndatedRecord]
    let mode: DesktopEventViewMode
    let selectedID: UUID?
    let search: DesktopEventSearch
    let select: (UUID) -> Void
    let resetFilters: () -> Void
    let create: () -> Void
    let canCreate: Bool
    @ObservedObject var editorSession: EventEditorSession
    let showTextAttachment: (SavedMaterialOwnerID, String) -> Void
    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                browserOverview
                browserContent
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("desktop.browser")
        .uiSmokeControl(id: "desktop.browser")
    }

    @ViewBuilder private var browserContent: some View {
        let isEvents = section == .events
        let isLoading = isEvents ? store.isLoading : store.isLoadingRecords
        let isEmpty = isEvents ? collection.events.isEmpty : records.isEmpty
        let isAvailable = isEvents ? store.eventCreationIsAvailable : store.recordCreationIsAvailable
        if isLoading {
            ProgressView(isEvents ? AppText.string("app.loadingEvents") : AppText.string("record.loading"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
        } else if isEmpty && !isAvailable {
            if isEvents { unavailableState }
            else {
                Text(AppText.string("record.unavailable"))
                    .font(.custom("Georgia", size: 23))
                    .padding(.vertical, 32)
                    .uiSmokeControl(id: "desktop.record.unavailable")
            }
        } else if isEmpty {
            if isEvents { emptyState }
            else { emptyRecords }
        } else {
            if isEvents, let favorite = collection.favorite { eventButton(favorite, featured: true) }
            DesktopEventFlowLayout(feedProgress: mode == .feed ? 1 : 0) {
                if isEvents { monthSections }
                else { ForEach(records) { recordButton($0) } }
            }
            .animation(accessibilitySettings.prefersReducedMotion ? nil : .easeInOut(duration: 0.15), value: mode)
        }
    }

    @ViewBuilder private var browserOverview: some View {
        if section == .events {
            overview
        } else {
            HStack(alignment: .firstTextBaseline) {
                Text(AppText.string("record.section.records")).font(.custom("Georgia", size: 32)).tracking(-0.5)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if store.recordCreationIsAvailable {
                    Text(recordCountLabel(store.records.count))
                        .font(.system(size: 12))
                        .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                }
            }
        }
    }

    private var emptyRecords: some View {
        let searching = !search.query.isEmpty
        return VStack(alignment: .leading, spacing: 14) {
            Text(searching ? AppText.string("desktop.browser.noSearchResults") : AppText.string("record.empty.title"))
                .font(.custom("Georgia", size: 23))
            Text(searching ? AppText.string("desktop.browser.retryRecordSearch") : AppText.string("record.empty.message"))
                .font(.system(size: 13))
                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
            if searching {
                Button(AppText.string("desktop.browser.showAllRecords"), action: resetFilters)
                    .uiSmokeControl(id: "desktop.record.search.clear", action: resetFilters)
            } else {
                Button(AppText.string("record.create"), action: create)
                    .keyboardShortcut("n", modifiers: .command)
                    .accessibilityIdentifier("desktop.record.empty.create")
                    .uiSmokeControl(id: "desktop.record.empty.create", action: create)
                    .disabled(!canCreate)
            }
        }
        .padding(.vertical, 32)
        .accessibilityIdentifier("desktop.record.empty")
        .uiSmokeControl(id: "desktop.record.empty", value: { searching ? "search" : "empty" })
    }

    private func recordButton(_ record: UndatedRecord) -> some View {
        let match = search.cardMatch(in: record)
        return browserCard(.record(record.id), control: "desktop.record.\(record.id.uuidString)",
                           accessibilityTitle: desktopRecordAccessibilityLabel(record) + (match?.accessibilitySuffix ?? "")) {
            DesktopRecordCard(record: record, feed: mode == .feed, search: search, match: match)
        }
    }

    @ViewBuilder private var monthSections: some View {
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
        if !collection.pastItems.isEmpty {
            Text(AppText.string("event.past"))
                .font(.custom("Georgia", size: 20))
                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("desktop.past")
                .uiSmokeControl(id: "desktop.past", value: { AppText.string("event.past") })
                .layoutValue(key: DesktopMonthHeadingKey.self, value: true)
            ForEach(collection.pastItems) { item in
                eventButton(item, featured: false)
            }
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(AppText.string("desktop.browser.upcoming")).font(.custom("Georgia", size: 32)).tracking(-0.5)
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
            Text(!search.query.isEmpty ? AppText.string("desktop.browser.noSearchResults") : EventUIStrings.emptyTitle)
                .font(.custom("Georgia", size: 23))
            Text(!search.query.isEmpty ? AppText.string("desktop.browser.retrySearch")
                 : AppText.string("desktop.browser.emptyGuidance"))
                .font(.system(size: 13))
                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
            if !search.query.isEmpty {
                Button(AppText.string("desktop.browser.showAll"), action: resetFilters)
            } else {
                Button(AppText.string("desktop.browser.createToday"), action: create).disabled(!canCreate)
            }
        }
        .padding(.vertical, 32)
        .accessibilityIdentifier("desktop.empty")
    }

    private var unavailableState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(AppText.string("desktop.browser.unavailable")).font(.custom("Georgia", size: 23))
            Text(AppText.string("desktop.browser.unavailableExplanation"))
                .font(.system(size: 13))
                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 32)
        .accessibilityIdentifier("desktop.unavailable")
    }

    private func eventButton(_ item: Countdown, featured: Bool) -> some View {
        let match = search.cardMatch(in: item)
        return browserCard(.event(item.id), control: "desktop.event.\(item.id.uuidString)",
                           accessibilityTitle: desktopEventAccessibilityLabel(item) + (match?.accessibilitySuffix ?? ""),
                           featured: featured) {
            DesktopEventCard(item: item, today: store.today, primaryID: store.data.primaryID,
                             weather: weather, featured: featured, feed: !featured && mode == .feed,
                             search: search, match: match)
        }
    }

    private func browserCard<Content: View>(_ ownerID: SavedMaterialOwnerID, control: String,
                                            accessibilityTitle: String, featured: Bool = false,
                                            @ViewBuilder content: () -> Content) -> some View {
        let selected = ownerID.id == selectedID
        let presentationID = ownerID.collection == .events ? "desktop.presentation.\(ownerID.id)"
            : "desktop.record.presentation.\(ownerID.id)"
        return Button { select(ownerID.id) } label: {
            content()
                .modifier(DesktopBrowserCardChrome(selected: selected, padding: featured ? 22 : 16))
                .uiSmokeControl(id: presentationID, value: {
                    featured ? "favorite" : mode.rawValue
                })
        }
        // The opaque card owns its appearance; avoid Plain's additional disabled fade.
        .buttonStyle(.borderless)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .accessibilityIdentifier(control)
        .uiSmokeControl(id: control, action: { select(ownerID.id) })
        .modifier(SavedMaterialTarget(store: store, editorSession: editorSession, ownerID: ownerID,
                                      enabled: canCreate, targetSurface: "desktop.card",
                                      showText: { showTextAttachment(ownerID, $0) }))
    }
}

private struct DesktopBrowserCardChrome: ViewModifier {
    let selected: Bool
    let padding: CGFloat
    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let highContrast = accessibilitySettings.prefersHighContrast
        let shape = RoundedRectangle(cornerRadius: 8)
        let outline = selected ? AuroraInstrument.accent(for: colorScheme, highContrast: highContrast)
            : AuroraInstrument.stroke(for: colorScheme, highContrast: highContrast)
        content
            .transition(.identity)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(AuroraInstrument.surface(for: colorScheme, elevated: selected, highContrast: highContrast))
            .clipShape(shape)
            .overlay { shape.strokeBorder(outline, lineWidth: selected ? 2 : 1) }
            .contentShape(shape)
    }
}

private struct DesktopMonthHeadingKey: LayoutValueKey {
    static let defaultValue = false
}

private struct DesktopEventFlowLayout: Layout {
    private static let collectionCardWidth: CGFloat = 180
    var feedProgress: CGFloat

    var animatableData: CGFloat {
        get { feedProgress }
        set { feedProgress = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = max(0, proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? Self.collectionCardWidth)
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
        let cardWidth = mode == .collection ? min(Self.collectionCardWidth, width) : width
        let columns = mode == .collection ? max(1, Int((width + spacing) / (cardWidth + spacing))) : 1
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
    let search: DesktopEventSearch
    let match: DesktopSearchMatch?
    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @Environment(\.colorScheme) private var colorScheme

    private var presentation: CountdownRowPresentation {
        CountdownRowPresentation(item: item, today: today, primaryID: primaryID)
    }
    private var accent: Color {
        AuroraInstrument.accent(for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast)
    }

    var body: some View {
        if featured { featuredContent }
        else { ordinaryContent }
    }

    private var featuredContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Label(AppText.string("event.favoriteHeading"), systemImage: "star.fill")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(accent)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(desktopSearchAttributedText(item.displayTitle, search: search, color: accent))
                            .font(.custom("Georgia", size: 27)).tracking(-0.5)
                            .fixedSize(horizontal: false, vertical: true)
                        searchMatch
                    }
                }
                Spacer(minLength: 0)
                DesktopCalendarLeaf(item: item, featured: true, role: "browser").padding(.top, 9)
            }
            .uiSmokeControl(id: "desktop.favorite.identity.\(item.id)")
            dateAndWeather
                .uiSmokeControl(id: "desktop.favorite.metadata.\(item.id)")
            Text(presentation.remainingLabel).font(.custom("Georgia", size: 25))
                .foregroundStyle(timeColor)
            if presentation.completionLabel != nil || !item.attachments.isEmpty || !item.links.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    DesktopCompletionLabel(presentation: presentation)
                        .labelStyle(DesktopSummaryLabelStyle(controlID: "desktop.summary.tasks.\(item.id)"))
                    attachmentIndicator
                    linkIndicator
                }
            }
        }
    }

    private var ordinaryContent: some View {
        DesktopOrdinaryCardLayout(feedProgress: feed ? 1 : 0) {
            DesktopCalendarLeaf(item: item, featured: false, role: "browser")
                .uiSmokeControl(id: "desktop.card.leaf.\(item.id)")
            VStack(alignment: .leading, spacing: 6) {
                Text(desktopSearchAttributedText(item.displayTitle, search: search, color: accent))
                    .font(.system(size: 15, weight: .semibold))
                    .multilineTextAlignment(.leading)
                    .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    .transaction { $0.animation = nil }
                searchMatch
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
                DesktopCompletionLabel(presentation: presentation)
                    .labelStyle(DesktopSummaryLabelStyle(controlID: "desktop.summary.tasks.\(item.id)"))
                    .transaction { $0.animation = nil }
                attachmentIndicator.transaction { $0.animation = nil }
                linkIndicator.transaction { $0.animation = nil }
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

    private var searchMatch: some View {
        DesktopCardSearchSnippet(match: match, search: search, accent: accent,
                                 controlID: "desktop.search.snippet.\(item.id)")
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
                .labelStyle(DesktopSummaryLabelStyle(controlID: "desktop.summary.attachments.\(item.id)"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                .lineLimit(1)
                .fixedSize()
                .accessibilityLabel(AppText.string("attachment.count", "\(item.attachments.count)"))
                .help(AppText.string("attachment.count", "\(item.attachments.count)"))
                .accessibilityIdentifier("desktop.attachments.indicator.\(item.id.uuidString)")
                .uiSmokeControl(id: "desktop.attachments.indicator.\(item.id.uuidString)",
                                value: { String(item.attachments.count) })
        }
    }

    @ViewBuilder
    private var linkIndicator: some View {
        if !item.links.isEmpty {
            Label(String(item.links.count), systemImage: "link")
                .labelStyle(DesktopSummaryLabelStyle(controlID: "desktop.summary.links.\(item.id)"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                .lineLimit(1)
                .fixedSize()
                .accessibilityLabel(AppText.string("link.count", "\(item.links.count)"))
                .help(AppText.string("link.count", "\(item.links.count)"))
                .accessibilityIdentifier("desktop.links.indicator.\(item.id)")
                .uiSmokeControl(id: "desktop.links.indicator.\(item.id)", value: { String(item.links.count) })
        }
    }

    private var timeColor: Color {
        if presentation.isPast { return AuroraInstrument.secondaryInk(for: colorScheme) }
        return presentation.isToday ? AuroraInstrument.todayColor(
            for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast
        ) : accent
    }
}

private struct DesktopRecordCard: View {
    let record: UndatedRecord
    let feed: Bool
    let search: DesktopEventSearch
    let match: DesktopSearchMatch?
    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color {
        AuroraInstrument.accent(for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(desktopSearchAttributedText(record.title, search: search, color: accent))
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(2)
                .help(record.title)
            if match != nil {
                DesktopCardSearchSnippet(match: match, search: search, accent: accent,
                                         controlID: "desktop.record.search.snippet.\(record.id)")
            } else if let note = record.note, !note.isEmpty {
                Text(desktopSearchAttributedText(note, search: search, color: accent, singleLine: true))
                    .font(.system(size: 12))
                    .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                    .lineLimit(feed ? 1 : 2)
            }
            if !record.subtasks.isEmpty || !record.attachments.isEmpty || !record.links.isEmpty {
                HStack(spacing: 8) {
                    DesktopCompletionLabel(tasks: record.subtasks)
                        .labelStyle(DesktopSummaryLabelStyle(controlID: "desktop.record.summary.tasks.\(record.id)"))
                    materialCount(record.attachments.count, symbol: "paperclip")
                    materialCount(record.links.count, symbol: "link")
                }
                .padding(.top, 2)
            }
        }
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private func materialCount(_ count: Int, symbol: String) -> some View {
        if count > 0 {
            Label(String(count), systemImage: symbol)
                .labelStyle(DesktopSummaryLabelStyle(controlID: "desktop.record.summary.\(symbol).\(record.id)"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                .fixedSize()
        }
    }
}

private struct DesktopCardSearchSnippet: View {
    let match: DesktopSearchMatch?
    let search: DesktopEventSearch
    let accent: Color
    let controlID: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let match, let snippet = search.snippet(in: match.text) {
            let highlighted = desktopSearchAttributedText(snippet.context, search: search, color: accent, singleLine: true)
            ViewThatFits(in: .horizontal) {
                Text(highlighted)
                    .strikethrough(match.isCompleted)
                Text(String(snippet.matchingText.map { $0.isNewline ? " " : $0 }))
                    .foregroundColor(accent)
                    .strikethrough(match.isCompleted)
            }
            .font(.system(size: 12))
            .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transaction { $0.animation = nil }
            .uiSmokeControl(id: controlID, value: { String(highlighted.characters) })
        }
    }
}

package func desktopSearchAttributedText(_ value: String, search: DesktopEventSearch,
                                         color: Color, singleLine: Bool = false) -> AttributedString {
    var text = AttributedString(value)
    for match in search.ranges(in: value) {
        if let range = Range(match, in: text) {
            text[range].foregroundColor = color
        }
    }
    guard singleLine, value.contains(where: \.isNewline) else { return text }
    // Keep the original match ranges when line breaks become display spaces.
    var flattened = AttributedString()
    for run in text.runs {
        let line = String(text[run.range].characters.map { $0.isNewline ? " " : $0 })
        flattened.append(AttributedString(line, attributes: run.attributes))
    }
    return flattened
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

struct DesktopSummaryLabelStyle: LabelStyle {
    let controlID: String

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            configuration.title.monospacedDigit()
                .uiSmokeControl(id: "\(controlID).value")
            configuration.icon.frame(width: 18)
                .accessibilityHidden(true)
                .uiSmokeControl(id: "\(controlID).icon")
        }
    }
}

struct DesktopCompletionLabel: View {
    let completed: Int
    let total: Int
    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @Environment(\.colorScheme) private var colorScheme

    init(presentation: CountdownRowPresentation) {
        completed = presentation.completedSubtasks.count
        total = completed + presentation.activeSubtasks.count
    }

    init(tasks: [Subtask]) {
        completed = tasks.filter(\.isCompleted).count
        total = tasks.count
    }

    var body: some View {
        if total > 0 {
            Label("\(completed)/\(total)", systemImage: completed == total ? "checkmark.circle.fill" : "checklist")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(completed == total
                    ? AuroraInstrument.todayColor(for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast)
                    : AuroraInstrument.secondaryInk(for: colorScheme))
                .accessibilityLabel(AppText.string("desktop.browser.checklistProgress", "\(completed)", "\(total)"))
        }
    }
}
