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
                    if !collection.ordinary.isEmpty {
                        HStack {
                            Text(collection.favorite == nil ? "Все события" : "И ещё впереди")
                                .font(.custom("Georgia", size: 20))
                            Spacer()
                            Text("По дате").font(.system(size: 11))
                                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                        }
                        if mode == .collection {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                                ForEach(collection.ordinary) { item in eventButton(item, featured: false) }
                            }
                        } else {
                            LazyVStack(spacing: 10) {
                                ForEach(collection.ordinary) { item in eventButton(item, featured: false) }
                            }
                        }
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("desktop.browser")
        .uiSmokeControl(id: "desktop.browser")
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
            HStack(spacing: 8) {
                Text(currentDayHeaderLabel(store.today))
                    .font(.system(size: 13, weight: .medium))
                if let forecast = weather.forecast(for: store.today) {
                    Text("·").accessibilityHidden(true)
                    DesktopForecastLabel(forecast: forecast)
                }
            }
            .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
        }
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
        .accessibilityLabel("Открыть событие: \(item.title)")
        .accessibilityAddTraits(item.id == selectedID ? [.isSelected] : [])
        .accessibilityIdentifier("desktop.event.\(item.id.uuidString)")
        .uiSmokeControl(id: "desktop.event.\(item.id.uuidString)", action: { select(item.id) })
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
            else if feed { feedContent }
            else { collectionContent }
        }
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
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Label("Избранное", systemImage: "star.fill")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(accent)
                Text(item.title).font(.custom("Georgia", size: 27)).tracking(-0.5)
                    .fixedSize(horizontal: false, vertical: true)
                dateAndWeather
                Text(presentation.remainingLabel).font(.custom("Georgia", size: 25))
                    .foregroundStyle(timeColor)
                DesktopCompletionLabel(presentation: presentation)
            }
            Spacer(minLength: 0)
            DesktopCalendarLeaf(item: item, featured: true, role: "browser").padding(.top, 9)
        }
    }

    private var collectionContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                DesktopCalendarLeaf(item: item, featured: false, role: "browser")
                Spacer(minLength: 4)
                DesktopCompletionLabel(presentation: presentation)
            }
            Text(item.title).font(.system(size: 15, weight: .semibold))
                .lineLimit(3).frame(maxWidth: .infinity, alignment: .leading)
            dateAndWeather
            Spacer(minLength: 0)
            Text(presentation.remainingLabel).font(.system(size: 13, weight: .medium))
                .foregroundStyle(timeColor)
                .uiSmokeControl(id: "desktop.collection.remaining.\(item.id.uuidString)", value: { presentation.remainingLabel })
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var feedContent: some View {
        HStack(alignment: .center, spacing: 16) {
            DesktopCalendarLeaf(item: item, featured: false, role: "browser")
            VStack(alignment: .leading, spacing: 7) {
                Text(item.title).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                dateAndWeather
                DesktopCompletionLabel(presentation: presentation)
            }
            Spacer(minLength: 0)
            Text(presentation.remainingLabel)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(timeColor)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var dateAndWeather: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { eventDate; eventForecast }
            VStack(alignment: .leading, spacing: 6) { eventDate; eventForecast }
        }
        .font(.system(size: 11))
        .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
    }

    private var eventDate: some View {
        DesktopEventDateLabel(item: item, dateLabel: presentation.dateLabel, role: "browser")
    }

    @ViewBuilder private var eventForecast: some View {
        if item.showsWeather, let forecast = weather.forecast(for: item.date) {
            DesktopForecastLabel(forecast: forecast)
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
