import AppKit
import SwiftUI
import ServiceManagement
import CountdownCore

struct ManagerView: View {
    @ObservedObject var store: Store
    @ObservedObject var updates: ApplicationUpdates
    @ObservedObject var editorSession: EventEditorSession
    @ObservedObject var keepAwake: KeepAwakeController
    @ObservedObject var weather: WeatherController
    let diagnosticsContext: () -> DiagnosticExportContext
    var showDesktop: () -> Void = {}
    @State private var editing: Countdown?
    private var showingEditor: Bool { editorSession.isPresented }
    @State private var showingDayChoices = false
    @State private var showingSettings = false
    @State private var attachmentListEventID: UUID?
    @State private var attachmentLibraryIsSource = false
    @StateObject private var attachmentPreview = AttachmentPreviewSession()
    @State private var dayPreset: DayCreationPreset?
    @State private var selectDayDate = false
    @State private var rootIdentity = UUID()
    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @Environment(\.colorScheme) private var colorScheme

    private var attachmentListEvent: Countdown? {
        store.active.first { $0.id == attachmentListEventID && !$0.attachments.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let error = store.error {
                VStack(alignment: .leading, spacing: 6) {
                    Text(error).font(.caption).textSelection(.enabled)
                    Button("Понятно") { store.error = nil }
                }
                .padding(10)
                .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: AuroraInstrument.inputCornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraInstrument.inputCornerRadius)
                        .stroke(Color.red.opacity(0.45), lineWidth: 1)
                )
                .padding([.horizontal, .top], 10)
                .accessibilityIdentifier("application.error")
                .uiSmokeControl(id: "application.error", value: { store.error })
            }
            ZStack {
                listScreen
                    .opacity(showingEditor || showingSettings || attachmentListEvent != nil ? 0 : 1)
                    .disabled(showingEditor || showingSettings || attachmentListEvent != nil)
                    .allowsHitTesting(!showingEditor && !showingSettings && attachmentListEvent == nil)
                    .accessibilityHidden(showingEditor || showingSettings || attachmentListEvent != nil)
                if let item = attachmentListEvent, !showingEditor, !showingSettings {
                    attachmentScreen(item: item)
                    .id(item.id)
                }
                if showingSettings {
                    SettingsView(store: store, updates: updates, keepAwake: keepAwake, weather: weather,
                                 diagnosticsContext: diagnosticsContext) {
                        showingSettings = false
                    }
                }
                if showingEditor {
                    EditorView(
                        store: store,
                        item: editing,
                        dayPreset: dayPreset,
                        selectDayDate: selectDayDate,
                        didSave: { event in
                            if NSApp.isActive {
                                weather.didSaveEvent(event, activeEvents: store.active)
                            } else {
                                weather.updateEvents(store.active)
                            }
                        },
                        done: finishEditor
                    )
                }
            }
        }
        .frame(width: 390, height: 540)
        .background(AuroraPanelCanvas())
        .foregroundStyle(AuroraInstrument.ink(for: colorScheme))
        .tint(plannerAccent)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("root.window")
        .uiSmokeControl(id: "root.window", value: { rootIdentity.uuidString })
        .onChange(of: store.data) { _ in closeUnavailableAttachmentList() }
        .onChange(of: store.today) { _ in closeUnavailableAttachmentList() }
        .onChange(of: attachmentPreview.selection) { selection in
            if selection == nil, !attachmentLibraryIsSource { attachmentListEventID = nil }
        }
    }

    private var listScreen: some View {
        let displayed = store.active
        let primaryID = store.data.primaryID
        return VStack(spacing: 0) {
            if editorSession.desktopIsPresented {
                Text("Редактор открыт в основном окне")
                    .font(.system(size: 11))
                    .padding(8)
                    .accessibilityIdentifier("desktop.editor.active")
            }
            if store.showsEmptyEventList {
                emptyEventList
                    .disabled(editorSession.desktopIsPresented)
            } else {
                header(activeCount: displayed.count)
                    .disabled(editorSession.desktopIsPresented)
                if showingDayChoices && !displayed.isEmpty {
                    dayChoices
                        .disabled(editorSession.desktopIsPresented)
                }
                ScrollView {
                    VStack(spacing: 10) {
                        if store.isLoading {
                            VStack(spacing: 12) {
                                AuroraLoadingPlaceholder()
                                ProgressView("Загружаем события…")
                            }
                        }
                        ForEach(displayed) { item in row(item, primaryID: primaryID) }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                    .animation(
                        accessibilitySettings.prefersReducedMotion ? nil : .easeInOut(duration: 0.2),
                        value: store.data.primaryID
                    )
                }
                .accessibilityIdentifier("event.list")
                .uiSmokeControl(id: "event.list")
                .disabled(editorSession.desktopIsPresented)
            }
            Divider()
            footer
        }
    }

    private var emptyEventList: some View {
        VStack(spacing: 0) {
            PlannerCalendarDateTile(monthControlID: "event.empty.month", day: store.today, isFeatured: false)
                .accessibilityHidden(true)
                .uiSmokeControl(id: "event.empty.date", value: { currentDayHeaderLabel(store.today) })
                .padding(.bottom, 16)
            Text(EventUIStrings.emptyTitle)
                .font(.custom("Georgia", size: 24)).tracking(-0.5)
                .padding(.bottom, 16)
            Text(EventUIStrings.emptyMessage)
                .font(.system(size: 12))
                .lineSpacing(3)
                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                .multilineTextAlignment(.center)
                .padding(.bottom, 20)
            VStack(spacing: 8) {
                Button { createDay(preset: .today(store.today)) } label: {
                    Text("На сегодня").font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity).frame(height: 34)
                        .foregroundStyle(colorScheme == .dark ? AuroraInstrument.canvas(for: colorScheme) : .white)
                        .background(plannerAccent, in: RoundedRectangle(cornerRadius: 6))
                }
                .accessibilityIdentifier("event.empty.today")
                .uiSmokeControl(id: "event.empty.today", action: { createDay(preset: .today(store.today)) })
                HStack(spacing: 8) {
                    emptySecondaryAction("На завтра", id: "event.empty.tomorrow") { createDay(preset: .tomorrow(after: store.today)) }
                    emptySecondaryAction("Выбрать дату", id: "event.empty.chooseDate") {
                        createDay(preset: .tomorrow(after: store.today), selectDate: true)
                    }
                }
            }
            .frame(width: 260)
            .buttonStyle(.plain)
        }
        .uiSmokeControl(id: "event.empty.content")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 36)
        .padding(.vertical, 28)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("event.empty")
        .uiSmokeControl(id: "event.empty")
    }

    private func emptySecondaryAction(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 12))
                .frame(maxWidth: .infinity).frame(height: 32)
                .background(AuroraInstrument.surface(for: colorScheme, elevated: false,
                                                    highContrast: accessibilitySettings.prefersHighContrast),
                            in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(plannerRule, lineWidth: 1))
        }
        .accessibilityIdentifier(id)
        .uiSmokeControl(id: id, action: action)
    }

    private func header(activeCount: Int) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(currentDayHeaderLabel(store.today))
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityIdentifier("header.today")
                    .uiSmokeControl(id: "header.today", value: { currentDayHeaderLabel(store.today) })
                Text(eventCountLabel(activeCount))
                    .font(.system(size: 11))
                    .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                    .uiSmokeControl(id: "header.active-count", value: { eventCountLabel(activeCount) })
            }
            Spacer()
            Button(action: toggleDayChoices) {
                Image(systemName: "calendar.badge.plus")
                    .frame(width: 31, height: 31)
            }
                .buttonStyle(.plain)
                .help(EventUIStrings.createDay).accessibilityLabel(EventUIStrings.createDay)
                .accessibilityIdentifier("day.add")
                .uiSmokeControl(id: "day.add", action: toggleDayChoices)
                .disabled(!store.eventCreationIsAvailable)
            Button(action: add) {
                Image(systemName: "plus")
                    .frame(width: 31, height: 31)
                    .foregroundStyle(colorScheme == .dark ? AuroraInstrument.canvas(for: colorScheme) : .white)
                    .background(plannerAccent, in: RoundedRectangle(cornerRadius: 8))
            }
                .buttonStyle(.plain)
                .help(EventUIStrings.addEvent).accessibilityLabel(EventUIStrings.addEvent)
                .accessibilityIdentifier("event.add")
                .uiSmokeControl(id: "event.add", action: add)
                .disabled(!store.eventCreationIsAvailable)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }

    private var dayChoices: some View {
        HStack {
            Text(EventUIStrings.createDay).font(.caption).foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                .uiSmokeControl(id: "creation.day.label")
            Spacer()
            Button("Сегодня") { createDay(preset: .today(store.today)) }
                .accessibilityIdentifier("creation.day.today")
                .uiSmokeControl(id: "creation.day.today", action: { createDay(preset: .today(store.today)) })
            Button("Завтра") { createDay(preset: .tomorrow(after: store.today)) }
                .accessibilityIdentifier("creation.day.tomorrow")
                .uiSmokeControl(id: "creation.day.tomorrow", action: { createDay(preset: .tomorrow(after: store.today)) })
            Button("Выбрать дату") { createDay(preset: .tomorrow(after: store.today), selectDate: true) }
                .accessibilityIdentifier("creation.day.chooseDate")
                .uiSmokeControl(id: "creation.day.chooseDate", action: {
                    createDay(preset: .tomorrow(after: store.today), selectDate: true)
                })
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .disabled(!store.eventCreationIsAvailable)
    }

    private var plannerAccent: Color {
        AuroraInstrument.accent(for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast)
    }

    private var plannerRule: Color {
        AuroraInstrument.stroke(for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast)
    }

    private func row(_ item: Countdown, primaryID: UUID?) -> some View {
        let presentation = CountdownRowPresentation(
            item: item,
            today: store.today,
            primaryID: primaryID
        )
        return VStack(alignment: .leading, spacing: 0) {
            if presentation.isFeatured {
                featuredEvent(item, presentation: presentation)
            } else {
                secondaryEvent(item, presentation: presentation)
            }
            if presentation.completionLabel != nil {
                SubtaskChecklistView(store: store, item: item, presentation: presentation, editorSession: editorSession)
                    .padding(.top, 8)
            }
            if !item.attachments.isEmpty {
                SavedAttachmentSection(item: item, compact: true, open: { attachment in
                    showAttachmentPreview(attachment, item: item, origin: .summary)
                }, thumbnailURL: { attachment in
                    await store.attachmentThumbnailURL(attachment, eventID: item.id)
                }, showAll: { showAttachmentList(item.id) })
                .padding(.top, 8)
            }
            if !item.links.isEmpty {
                SavedLinkSection(item: item, surface: "panel", open: { store.openLink($0, eventID: item.id) })
                    .padding(.top, 8)
            }
        }
        .padding(12)
        .background(AuroraInstrument.surface(
            for: colorScheme,
            elevated: false,
            highContrast: accessibilitySettings.prefersHighContrast
        ), in: RoundedRectangle(cornerRadius: AuroraInstrument.cardCornerRadius))
        .overlay {
            if accessibilitySettings.prefersHighContrast {
                RoundedRectangle(cornerRadius: AuroraInstrument.cardCornerRadius)
                    .stroke(plannerRule, lineWidth: 1)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("event.card.\(item.id.uuidString)")
        .uiSmokeControl(id: "event.card.\(item.id.uuidString)", value: { item.title })
    }

    private func featuredEvent(_ item: Countdown, presentation: CountdownRowPresentation) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Основное событие")
                    .accessibilityIdentifier("event.featured.label.\(item.id.uuidString)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                Spacer()
                eventActions(item, presentation: presentation)
            }
            HStack(alignment: .center, spacing: 13) {
                VStack(alignment: .leading, spacing: 7) {
                    Text((eventListEmoji(item.emoji).map { $0 + " " } ?? "") + item.title)
                        .font(.custom("Georgia", size: 23))
                        .tracking(-0.6)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .uiSmokeControl(id: "event.title.\(item.id.uuidString)", value: { item.title })
                        .uiSmokeControl(id: "event.featured.title.\(item.id.uuidString)")
                    eventDate(item, label: presentation.dateLabel)
                }
                calendarTile(item, isFeatured: true)
                    .uiSmokeControl(id: "event.featured.calendar.\(item.id.uuidString)")
            }
            Text(presentation.remainingLabel)
                .font(.custom("Georgia", size: 21))
                .foregroundStyle(presentation.isToday
                    ? AuroraInstrument.todayColor(
                        for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast
                    )
                    : AuroraInstrument.accentInk(
                        for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast
                    ))
                .accessibilityIdentifier(presentation.isToday ? "event.today" : "event.remaining")
                .uiSmokeControl(id: "event.relative.\(item.id.uuidString)", value: { presentation.remainingLabel })
                .padding(.top, 1)
            eventNote(presentation, id: item.id)
        }
    }

    private func secondaryEvent(_ item: Countdown, presentation: CountdownRowPresentation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 11) {
                calendarTile(item, isFeatured: false)
                    .uiSmokeControl(id: "event.secondary.calendar.\(item.id.uuidString)")
                GeometryReader { geometry in
                    let title = (eventListEmoji(item.emoji).map { $0 + " " } ?? "") + item.title
                    let textWidth = max(0, geometry.size.width - 59)
                    let wraps = title.contains(where: \.isNewline) || (title as NSString).size(withAttributes: [
                        .font: NSFont.systemFont(ofSize: 14, weight: .semibold)
                    ]).width > textWidth
                    HStack(alignment: .top, spacing: 3) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(title)
                                .font(.system(size: 14, weight: .semibold))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: wraps ? 34 : 17, alignment: .topLeading)
                                .uiSmokeControl(id: "event.title.\(item.id.uuidString)", value: { item.title })
                                .uiSmokeControl(id: "event.secondary.title.\(item.id.uuidString)")
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(compactDateLabel(item.date))
                                    .fixedSize()
                                    .uiSmokeControl(id: "event.date.\(item.id.uuidString)", value: { presentation.dateLabel })
                                Text("·").accessibilityHidden(true)
                                Text(presentation.remainingLabel)
                                    .foregroundStyle(presentation.isToday
                                        ? AuroraInstrument.todayColor(
                                            for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast
                                        )
                                        : AuroraInstrument.secondaryInk(for: colorScheme))
                                    .accessibilityIdentifier(presentation.isToday ? "event.today" : "event.remaining")
                                    .uiSmokeControl(id: "event.relative.\(item.id.uuidString)", value: { presentation.remainingLabel })
                                if wraps, item.showsWeather, weather.forecast(for: item.date) != nil {
                                    Text("·").accessibilityHidden(true)
                                    eventWeather(item).fixedSize()
                                }
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                            .lineLimit(1)
                            .frame(height: 14, alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if !wraps {
                                eventWeather(item)
                                    .frame(height: 14, alignment: .leading)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .frame(width: textWidth, height: 51, alignment: .topLeading)
                        eventActions(item, presentation: presentation)
                    }
                    .uiSmokeControl(id: "event.header.\(item.id.uuidString)", value: { wraps ? "long" : "short" })
                }
                .frame(height: 51)
            }
            eventNote(presentation, id: item.id)
        }
    }

    private func compactDateLabel(_ day: Day) -> String {
        humanDateLabel(day).split(separator: " ").prefix(2).joined(separator: " ")
    }

    private func calendarTile(_ item: Countdown, isFeatured: Bool) -> some View {
        let role = isFeatured ? "featured" : "secondary"
        return PlannerCalendarDateTile(monthControlID: "event.\(role).month.\(item.id.uuidString)", day: item.date, isFeatured: isFeatured)
            .accessibilityHidden(true)
            .uiSmokeControl(id: "event.calendar.\(item.id.uuidString)", value: { humanDateLabel(item.date) })
    }

    private func eventDate(_ item: Countdown, label: String, includesWeather: Bool = true) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .uiSmokeControl(id: "event.date.\(item.id.uuidString)", value: { label })
                .uiSmokeControl(id: "event.featured.date.\(item.id.uuidString)", value: { label })
            if includesWeather, item.showsWeather, weather.forecast(for: item.date) != nil {
                Text("·").accessibilityHidden(true)
                    .uiSmokeControl(id: "event.weather.separator.\(item.id.uuidString)")
                eventWeather(item, role: "featured").fixedSize()
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
        .lineLimit(1)
    }

    @ViewBuilder
    private func eventWeather(_ item: Countdown, role: String = "secondary") -> some View {
        if item.showsWeather, let forecast = weather.forecast(for: item.date) {
            (Text(Image(systemName: forecast.symbolName)) + Text(" " + forecast.temperatureLabel))
            .monospacedDigit()
            .font(.system(size: 11))
            .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(forecast.conditionDescription), \(forecast.temperatureLabel)")
            .accessibilityIdentifier("event.weather.\(item.id.uuidString)")
            .uiSmokeControl(id: "event.weather.\(item.id.uuidString)", value: { forecast.temperatureLabel })
            .uiSmokeControl(id: "event.\(role).weather.\(item.id.uuidString)", value: { forecast.temperatureLabel })
        }
    }

    @ViewBuilder
    private func eventNote(_ presentation: CountdownRowPresentation, id: UUID) -> some View {
        if let note = presentation.note, !note.isEmpty {
            Text(note)
                .font(.system(size: 12))
                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("event.note")
                .uiSmokeControl(id: "event.note.\(id.uuidString)", value: { note })
        }
    }

    private func eventActions(_ item: Countdown, presentation: CountdownRowPresentation) -> some View {
        HStack(spacing: 0) {
            Button { togglePrimary(item.id) } label: {
                Image(systemName: presentation.isPrimary ? "star.fill" : "star")
                    .foregroundStyle(presentation.isPrimary ? plannerAccent : AuroraInstrument.secondaryInk(for: colorScheme))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(presentation.isPrimary ? "Снять основное событие" : "Сделать основным событием")
            .accessibilityIdentifier("event.primary.\(item.id.uuidString)")
            .accessibilityLabel(presentation.isPrimary
                ? "Снять основное событие: \(item.title)" : "Сделать основным событием: \(item.title)")
            .accessibilityValue(presentation.isPrimary ? "Выбрано" : "Не выбрано")
            .uiSmokeControl(
                id: "event.primary.\(item.id.uuidString)",
                action: { togglePrimary(item.id) },
                value: { presentation.isPrimary ? "Выбрано" : "Не выбрано" }
            )
            Button { edit(item.id) } label: {
                Image(systemName: "pencil")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
            .accessibilityLabel("Редактировать событие: \(item.title)")
            .accessibilityIdentifier("event.edit.\(item.id.uuidString)")
            .uiSmokeControl(id: "event.edit.\(item.id.uuidString)", action: { edit(item.id) })
        }
        .fixedSize()
    }

    private func togglePrimary(_ id: UUID) {
        Task {
            guard !editorSession.hasActiveEditor else { return }
            if store.data.primaryID == id {
                await store.clearPrimary()
            } else {
                await store.makePrimary(id)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Label("Хранится на этом Mac", systemImage: "lock")
                .font(.system(size: 10))
                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
            Spacer()
            Button(action: showDesktop) {
                Image(systemName: "macwindow")
                    .font(.system(size: 14))
                    .frame(width: 22, height: 22)
            }
            .help("Открыть основное окно")
            .accessibilityLabel("Открыть основное окно")
            .accessibilityIdentifier("desktop.open")
            .uiSmokeControl(id: "desktop.open", action: showDesktop)
            Button(action: openSettings) {
                Image(systemName: "gearshape")
                    .font(.system(size: 14))
                    .frame(width: 22, height: 22)
                    .overlay(alignment: .topTrailing) {
                        if keepAwake.isEnabled {
                            Circle().fill(plannerAccent).frame(width: 5, height: 5)
                                .padding(2).accessibilityHidden(true)
                        }
                    }
            }
            .help("Настройки")
            .accessibilityLabel("Настройки")
            .accessibilityValue(keepAwake.isEnabled ? "Не спать включено" : "Не спать выключено")
            .accessibilityIdentifier("settings.open")
            .uiSmokeControl(id: "settings.open", action: openSettings)
            Button("Выйти") { updates.quitApplication(nil) }
        }
        .font(.system(size: 11))
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
        .frame(height: 33)
        .background(AuroraPanelCanvas())
    }

    private func openSettings() {
        guard !showingEditor, attachmentListEventID == nil else { return }
        attachmentPreview.close()
        attachmentListEventID = nil
        showingSettings = true
    }

    private func showAttachmentList(_ id: UUID) {
        guard !showingEditor, !showingSettings, !editorSession.hasActiveEditor,
              attachmentListEventID == nil,
              store.active.contains(where: { $0.id == id && !$0.attachments.isEmpty }) else { return }
        attachmentPreview.close()
        attachmentLibraryIsSource = true
        attachmentListEventID = id
    }

    private func closeUnavailableAttachmentList() {
        attachmentPreview.reconcile(event: attachmentListEvent)
        if attachmentListEventID != nil, attachmentListEvent == nil {
            attachmentPreview.close()
            attachmentListEventID = nil
            attachmentLibraryIsSource = false
        }
    }

    private func attachmentScreen(item: Countdown) -> some View {
        ZStack {
            if attachmentLibraryIsSource {
                AttachmentListView(item: item, compact: true, back: closeAttachments,
                                   open: { showAttachmentPreview($0, item: item, origin: .library) },
                                   thumbnailURL: { await store.attachmentThumbnailURL($0, eventID: item.id) })
                    .opacity(attachmentPreview.selection == nil ? 1 : 0)
                    .disabled(attachmentPreview.selection != nil)
                    .allowsHitTesting(attachmentPreview.selection == nil)
                    .accessibilityHidden(attachmentPreview.selection != nil)
            }
            if attachmentPreview.selection != nil {
                AttachmentPreviewView(item: item, compact: true, session: attachmentPreview,
                                      back: closeAttachmentPreview,
                                      resolveURL: { [store] in await store.attachmentThumbnailURL($0, eventID: $1) },
                                      openExternally: { [store] in await store.openAttachment($0, eventID: $1) })
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func showAttachmentPreview(_ attachment: EventAttachment, item: Countdown,
                                       origin: AttachmentPreviewOrigin) {
        guard !showingEditor, !showingSettings, !editorSession.hasActiveEditor,
              let current = store.active.first(where: { $0.id == item.id }),
              current.attachments.contains(where: { $0.id == attachment.id }),
              attachmentPreview.selection == nil,
              origin == .library ? attachmentListEventID == item.id : attachmentListEventID == nil else { return }
        attachmentLibraryIsSource = origin == .library
        attachmentListEventID = item.id
        attachmentPreview.open(event: current, attachmentID: attachment.id, origin: origin,
                               resolveURL: { [store] in await store.attachmentThumbnailURL($0, eventID: $1) })
    }

    private func closeAttachmentPreview() {
        guard attachmentPreview.selection != nil else { return }
        attachmentPreview.close()
        if !attachmentLibraryIsSource { attachmentListEventID = nil }
    }

    private func closeAttachments() {
        attachmentPreview.close()
        attachmentListEventID = nil
        attachmentLibraryIsSource = false
    }

    private func finishEditor() {
        editorSession.endPanelEditor()
        editing = nil
        dayPreset = nil
        selectDayDate = false
    }

    private func add() {
        createEvent()
    }

    private func createEvent() {
        guard !showingSettings, attachmentListEventID == nil,
              !store.hasPendingPersistence, store.eventCreationIsAvailable,
              editorSession.beginPanelEditor() else { return }
        DiagnosticLog.shared.record("editor.open mode=new")
        editing = nil
        dayPreset = nil
        selectDayDate = false
        showingDayChoices = false
    }

    private func toggleDayChoices() {
        guard !editorSession.hasActiveEditor, !showingSettings, attachmentListEventID == nil,
              store.eventCreationIsAvailable else { return }
        showingDayChoices.toggle()
    }

    private func createDay(preset: DayCreationPreset?, selectDate: Bool = false) {
        guard !showingSettings, attachmentListEventID == nil,
              !store.hasPendingPersistence, store.eventCreationIsAvailable, let preset,
              editorSession.beginPanelEditor() else { return }
        DiagnosticLog.shared.record("editor.open mode=day")
        editing = nil
        dayPreset = preset
        selectDayDate = selectDate
        showingDayChoices = false
    }

    private func edit(_ id: UUID) {
        guard !showingSettings, attachmentListEventID == nil, !store.hasPendingPersistence,
              let item = store.active.first(where: { $0.id == id }),
              editorSession.beginPanelEditor() else { return }
        DiagnosticLog.shared.record("editor.open mode=edit id=\(item.id.uuidString)")
        editing = item
        dayPreset = nil
        selectDayDate = false
        showingDayChoices = false
    }
}

struct PlannerCalendarDateTile: View {
    let monthControlID: String
    let day: Day
    let isFeatured: Bool
    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let presentation = CalendarDateTilePresentation(day: day)
        let shape = RoundedRectangle(cornerRadius: isFeatured ? 5 : 4)
        VStack(spacing: 0) {
            Text(presentation.monthLabel)
                .font(.system(size: isFeatured ? 10 : 9, weight: .semibold))
                .tracking(isFeatured ? 0.7 : 0.5)
                .foregroundStyle(colorScheme == .dark ? AuroraInstrument.canvas(for: colorScheme) : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, isFeatured ? 3 : 2)
                .background(AuroraInstrument.accent(
                    for: colorScheme,
                    highContrast: accessibilitySettings.prefersHighContrast
                ))
                .uiSmokeControl(id: monthControlID)
            Text(presentation.dayLabel)
                .font(.custom("Georgia", size: isFeatured ? 32 : 25))
                .tracking(-0.5)
                .foregroundStyle(AuroraInstrument.ink(for: colorScheme))
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
                .padding(.bottom, isFeatured ? 4 : 3)
        }
        .frame(width: isFeatured ? 54 : 42, height: isFeatured ? 65 : 51, alignment: .top)
        .background(AuroraInstrument.surface(
            for: colorScheme,
            elevated: false,
            highContrast: accessibilitySettings.prefersHighContrast
        ))
        .clipShape(shape)
        .overlay(shape.strokeBorder(AuroraInstrument.stroke(
            for: colorScheme,
            highContrast: accessibilitySettings.prefersHighContrast
        ), lineWidth: 1))
        .rotationEffect(.degrees(isFeatured ? 3 : 2))
    }
}

private struct SubtaskChecklistView: View {
    let store: Store
    let item: Countdown
    let presentation: CountdownRowPresentation
    @ObservedObject var editorSession: EventEditorSession

    @ObservedObject private var disclosureState: SubtaskDisclosureState
    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @Environment(\.colorScheme) private var colorScheme

    init(
        store: Store,
        item: Countdown,
        presentation: CountdownRowPresentation,
        editorSession: EventEditorSession
    ) {
        self.store = store
        self.item = item
        self.presentation = presentation
        self.editorSession = editorSession
        _disclosureState = ObservedObject(wrappedValue: store.disclosureState(for: item.id))
    }

    var body: some View {
        let isExpanded = disclosureState.isExpanded
        let completionLabel = presentation.completionLabel ?? "0/0"

        VStack(alignment: .leading, spacing: 5) {
            Button(action: toggleDisclosure) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                    Text("Подзадачи")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AuroraInstrument.ink(for: colorScheme))
                        .uiSmokeControl(id: "panel.subtasks.heading.\(item.id.uuidString)")
                    Spacer()
                    HStack(spacing: 4) {
                        if presentation.allSubtasksCompleted {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .accessibilityHidden(true)
                                .uiSmokeControl(id: "subtasks.complete.\(item.id.uuidString)")
                        }
                        Text(completionLabel.replacingOccurrences(of: "/", with: " из "))
                            .monospacedDigit()
                    }
                    .foregroundStyle(presentation.allSubtasksCompleted
                        ? AuroraInstrument.todayColor(for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast)
                        : AuroraInstrument.secondaryInk(for: colorScheme))
                    .uiSmokeControl(id: "subtasks.progress.\(item.id.uuidString)", value: { completionLabel })
                }
                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                .font(.system(size: 11))
                .frame(minHeight: 22)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Подзадачи: \(completionLabel)\(presentation.allSubtasksCompleted ? ", все выполнены" : ""), \(isExpanded ? "свернуть" : "раскрыть")")
            .accessibilityIdentifier("subtasks.disclosure.\(item.id.uuidString)")
            .uiSmokeControl(
                id: "subtasks.disclosure.\(item.id.uuidString)",
                action: toggleDisclosure,
                value: { disclosureState.isExpanded ? "expanded" : "collapsed" }
            )

            VStack(alignment: .leading, spacing: 0) {
                subtaskRows(presentation.activeSubtasks)
                subtaskRows(presentation.completedSubtasks)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(height: isExpanded ? nil : 0, alignment: .top)
            .opacity(isExpanded ? 1 : 0)
            .clipped()
            .disabled(!isExpanded)
            .allowsHitTesting(isExpanded)
            .accessibilityHidden(!isExpanded)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("subtasks.list")
        }
        .animation(disclosureAnimation, value: isExpanded)
        .animation(
            accessibilitySettings.prefersReducedMotion ? nil : .easeInOut(duration: 0.2),
            value: item.subtasks.map(\.isCompleted)
        )
        .transaction { transaction in
            if accessibilitySettings.prefersReducedMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }

    private var disclosureAnimation: Animation? {
        switch subtaskDisclosureMotion(reduceMotion: accessibilitySettings.prefersReducedMotion) {
        case .immediate:
            nil
        case let .heightAndOpacity(duration):
            .easeInOut(duration: duration)
        }
    }

    @ViewBuilder
    private func subtaskRows(_ subtasks: [Subtask]) -> some View {
        ForEach(subtasks) { subtask in
            HStack(spacing: 0) {
                Toggle(isOn: Binding(
                    get: { subtask.isCompleted },
                    set: { _ in toggleSubtask(subtask.id) }
                )) {
                    Text(subtask.text)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .strikethrough(subtask.isCompleted)
                        .foregroundStyle(subtask.isCompleted
                            ? AuroraInstrument.secondaryInk(for: colorScheme) : AuroraInstrument.ink(for: colorScheme))
                        .help(subtask.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                }
                .toggleStyle(.checkbox)
                .tint(subtask.isCompleted
                    ? AuroraInstrument.completedCheck(for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast)
                    : AuroraInstrument.accent(for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast))
                .accessibilityLabel("\(subtask.isCompleted ? "Отметить невыполненной" : "Отметить выполненной"): \(subtask.text)")
                .accessibilityIdentifier("subtask.toggle.\(subtask.id.uuidString)")
                .uiSmokeControl(
                    id: "subtask.toggle.\(subtask.id.uuidString)",
                    action: { toggleSubtask(subtask.id) },
                    value: {
                        let isCompleted = store.active
                            .first(where: { $0.id == item.id })?
                            .subtasks.first(where: { $0.id == subtask.id })?
                            .isCompleted
                        return isCompleted == true ? "completed" : "active"
                    }
                )

            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(subtask.isCompleted ? "subtask.completed" : "subtask.active")
        }
    }

    private func toggleDisclosure() {
        disclosureState.setExpanded(!disclosureState.isExpanded)
    }

    private func toggleSubtask(_ id: UUID) {
        Task {
            guard !editorSession.hasActiveEditor else { return }
            _ = await store.toggleSubtask(eventID: item.id, subtaskID: id)
        }
    }

}

struct EditorView: View {
    @ObservedObject var store: Store
    let item: Countdown?
    let didSave: (Countdown) -> Void
    let done: () -> Void
    private let isNewDay: Bool
    private let selectDayDate: Bool
    @State private var draft: EventEditorDraft
    @State private var date: Date
    @State private var primary: Bool
    @State private var isSaving = false
    @State private var isImportingAttachments = false
    @StateObject private var attachmentSession = EditorAttachmentSession()
    @State private var confirmingDeletion = false
    @State private var emojiPicker: EditorEmojiPickerState = .closed
    @State private var noteFocusRequest = 0
    @FocusState private var focusedField: EditorFocusTarget?
    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @Environment(\.colorScheme) private var colorScheme

    private static let emojiPageTitles = ["Общие", "Дети", "Работа", "Транспорт", "Праздники"]
    private static let emojiRows = [
        ["☀️", "✈️", "🎉", "🎂", "🎄", "❤️", "🚀", "🏖️", "👶", "🍼", "🧸", "🎈", "🎁", "🎂", "🎉", "🥳", "💼", "💻", "🖥️", "⌨️", "🖱️", "📱", "📞", "📧", "✈️", "🚗", "🚕", "🚌", "🚎", "🏎️", "🚓", "🚑", "🎉", "🎊", "🎈", "🎂", "🎁", "🎄", "🎃", "🎆"],
        ["😀", "😄", "😊", "😍", "🥳", "😎", "🤩", "😂", "🎒", "📚", "✏️", "🖍️", "🎨", "🧩", "🧱", "🎓", "📊", "📈", "📉", "💰", "💳", "🧾", "💵", "🏦", "🚲", "🛴", "🏍️", "🚂", "🚆", "🚇", "🚁", "🚢", "🎇", "🪩", "🥳", "🎶", "🎵", "🎤", "🎸", "🥁"],
        ["💙", "💚", "💜", "🧡", "💛", "🤍", "👍", "🙌", "🐶", "🐱", "🐰", "🐼", "🦄", "🐸", "🐵", "🦋", "📅", "🗓️", "⏰", "⏳", "✅", "☑️", "📌", "📍", "🛳️", "⛵️", "🚤", "🚀", "🛸", "🚠", "🚡", "🚜", "🏆", "🥇", "🥈", "🥉", "⚽️", "🏀", "🎾", "🎯"],
        ["🌈", "❄️", "🌸", "🌻", "🍀", "🌊", "🌙", "🔥", "🎮", "🪁", "🛹", "🚲", "🛴", "🎯", "🎲", "🎳", "📝", "📄", "📁", "📂", "📎", "✂️", "🔗", "🔒", "🗺️", "🧭", "🧳", "🎒", "🛂", "🛃", "🛬", "🛫", "🍰", "🧁", "🍩", "🍪", "🍕", "🍔", "🍿", "🥂"],
        ["🏠", "📅", "⏰", "⭐️", "✨", "🎁", "☕️", "📌", "🍎", "🍓", "🍉", "🍕", "🍔", "🍦", "🍪", "🍰", "🎯", "💡", "🤝", "🏆", "🥇", "🚀", "⚙️", "🧠", "🏨", "🏕️", "🏔️", "🏖️", "🌆", "🌉", "🗼", "🗽", "❤️", "💖", "💕", "💝", "🌹", "🌸", "🌟", "✨"],
        ["⚽️", "🎮", "🎵", "📚", "💡", "🍕", "🐶", "🐱", "🌈", "⭐️", "✨", "☀️", "🌸", "🌻", "🎵", "🎬", "👔", "👩‍💼", "👨‍💼", "🏢", "🏭", "🛠️", "🔧", "📦", "⛽️", "🅿️", "🚦", "🚧", "🛣️", "🛤️", "⚓️", "🚏", "🏖️", "🌴", "☀️", "🌅", "🎬", "🎮", "🎲", "🃏"]
    ]

    private static let emojiColumnsPerPage = 8
    private static let emojiCellWidth: CGFloat = 31
    private static let emojiCellHeight: CGFloat = 32
    private static let emojiSpacing: CGFloat = 5
    private static var emojiPageCount: Int { emojiPageTitles.count }
    private static var emojiPageWidth: CGFloat {
        emojiCellWidth * CGFloat(emojiColumnsPerPage)
            + emojiSpacing * CGFloat(emojiColumnsPerPage - 1)
    }
    private static var emojiExpandedHeight: CGFloat {
        emojiCellHeight * CGFloat(emojiRows.count)
            + emojiSpacing * CGFloat(emojiRows.count - 1)
    }

    init(
        store: Store,
        item: Countdown?,
        dayPreset: DayCreationPreset? = nil,
        selectDayDate: Bool = false,
        didSave: @escaping (Countdown) -> Void,
        done: @escaping () -> Void
    ) {
        self.store = store; self.item = item; self.done = done
        self.didSave = didSave
        isNewDay = item == nil && dayPreset != nil
        self.selectDayDate = item == nil && selectDayDate
        if item == nil, let dayPreset {
            _draft = State(initialValue: EventEditorDraft(day: dayPreset.day))
        } else {
            _draft = State(initialValue: EventEditorDraft(item: item))
        }
        _date = State(initialValue: item?.date.date() ?? dayPreset?.day.date() ?? store.tomorrow)
        _primary = State(initialValue: item.map { store.data.primaryID == $0.id } ?? false)
    }

    private var emojiPage: Int { emojiPicker.pageIndex }
    private var emojiPickerAnimation: Animation? {
        switch editorEmojiPickerMotion(reduceMotion: accessibilitySettings.prefersReducedMotion) {
        case .immediate:
            nil
        case let .heightAndOpacity(duration):
            .easeInOut(duration: duration)
        }
    }

    private var minimumDate: Date { store.today.date() }
    private var validDate: Bool { Day(date) >= store.today }
    private var isUnavailable: Bool {
        guard let item else { return false }
        return item.date < store.today || !store.active.contains(where: { $0.id == item.id })
    }
    private var canSave: Bool {
        !isUnavailable && editorCanSave(
            title: draft.title,
            note: draft.note,
            date: Day(date),
            emoji: draft.emoji,
            subtasks: draft.subtasks,
            links: draft.links,
            today: store.today,
            savedNote: savedNote
        )
    }

    private var savedNote: String? {
        item.flatMap { original in store.active.first(where: { $0.id == original.id })?.note }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(item != nil ? EventUIStrings.editEvent : (isNewDay ? EventUIStrings.newDay : EventUIStrings.newEvent))
                .font(.custom("Georgia", size: 21))
                .tracking(-0.5)
                .frame(maxWidth: .infinity, minHeight: 49, alignment: .leading)
                .padding(.horizontal, 16)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if selectDayDate {
                            Text(isNewDay ? "Выберите дату для нового дня." : "Выберите дату события.")
                                .font(.caption)
                                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                        }
                        titleField
                        noteControls
                        dateControls
                        VStack(alignment: .leading, spacing: 0) {
                            Divider().padding(.bottom, 10)
                            emojiControls
                            eventOptions.padding(.top, 13)
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Divider().padding(.bottom, 13)
                            editorSubtasks(scrollProxy: proxy)
                        }
                        .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 0) {
                            Divider().padding(.bottom, 13)
                            EditorAttachmentSection(attachments: $draft.attachments,
                                                    isImporting: isImportingAttachments, add: addAttachments,
                                                    thumbnailURL: { attachment in
                                await store.editorAttachmentThumbnailURL(attachment, eventID: item?.id,
                                                                         draftID: attachmentSession.id)
                            })
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Divider().padding(.bottom, 13)
                            EditorLinkSection(links: $draft.links)
                        }
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 15)
                    .padding(.leading, 16)
                    .padding(.trailing, 16 + EditorLayout.scrollIndicatorClearance)
                    .padding(.vertical, EditorLayout.focusRingInset)
                }
                .accessibilityIdentifier("editor.scroll")
                .uiSmokeControl(id: "editor.scroll")
            }
            .disabled(isSaving || isImportingAttachments)
            editorActions
        }
        .font(.system(size: 13))
        .foregroundStyle(AuroraInstrument.ink(for: colorScheme))
        .tint(AuroraInstrument.accent(for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(item == nil ? "editor.new" : "editor.edit")
        .uiSmokeControl(id: item == nil ? "editor.new" : "editor.edit")
        .task {
            await Task.yield()
            focusedField = .title
            await Task.yield()
            if UISmokeConfiguration.wasRequested && focusedField == .title {
                UISmokeControlRegistry.shared.markFocused("editor.title")
            }
        }
        .environment(\.locale, Locale(identifier: "ru_RU"))
        .environment(\.calendar, Day.calendar)
        .onChange(of: date) { newDate in
            draft.updateDayTitle(for: Day(newDate))
        }
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Название")
                    .font(.system(size: 11))
                    .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                    .accessibilityIdentifier("editor.title.mode")
                    .accessibilityValue(draft.usesAutomaticTitle ? "Название по дате" : "Своё название")
                    .uiSmokeControl(id: "editor.title.mode", value: { draft.usesAutomaticTitle ? "auto" : "custom" })
                Spacer(minLength: 8)
                if draft.usesAutomaticTitle {
                    Text("По дате")
                        .font(.system(size: 11))
                        .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                } else {
                    Button("Название по дате", action: useAutomaticTitle)
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .font(.system(size: 11))
                        .accessibilityIdentifier("editor.title.automatic")
                        .uiSmokeControl(id: "editor.title.automatic", action: useAutomaticTitle)
                }
            }
            TextField("Например, отпуск", text: Binding(get: { draft.title }, set: { draft.setTitle($0) }))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14))
                .frame(minHeight: 28)
                .focused($focusedField, equals: .title)
                .accessibilityIdentifier("editor.title")
                .uiSmokeControl(id: "editor.title", action: { focus(.title, id: "editor.title") }, value: { draft.title })
        }
    }

    private func useAutomaticTitle() {
        draft.useAutomaticTitle(for: Day(date))
    }

    private var noteControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Заметка · необязательно")
                .font(.caption)
                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
            NoteEditor(text: $draft.note, maximumLength: CountdownNote.allowedLength(savedNote: savedNote),
                       focusRequest: noteFocusRequest)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("editor.note")
                .uiSmokeControl(id: "editor.note", action: { focus(.note, id: "editor.note") }, value: { draft.note })
            HStack(alignment: .top) {
                if (savedNote?.count ?? 0) > CountdownNote.maximumLength {
                    Text("Старая заметка: можно сохранить или сократить.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Text("\(draft.note.count)/150")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("editor.note.count")
                    .uiSmokeControl(id: "editor.note.count", value: { "\(draft.note.count)/150" })
            }
        }
    }

    private var dateControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            DatePicker("Дата", selection: $date, in: minimumDate..., displayedComponents: [.date])
                .datePickerStyle(.field)
                .font(.system(size: 12))
                .frame(minHeight: 28)
                .accessibilityIdentifier("editor.date")
                .uiSmokeControl(id: "editor.date", value: { "\(Day(date).year)-\(Day(date).month)-\(Day(date).day)" })
            if Day(date) == store.today || !validDate {
                Text(dateHelp)
                    .font(.system(size: 10.5))
                    .foregroundStyle(validDate
                        ? AuroraInstrument.warningInk(for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast) : .red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(AuroraInstrument.surface(for: colorScheme, elevated: false,
                                                        highContrast: accessibilitySettings.prefersHighContrast),
                                in: RoundedRectangle(cornerRadius: 5))
                    .accessibilityIdentifier("editor.date.help")
                    .uiSmokeControl(id: "editor.date.help", value: { dateHelp })
            } else {
                Color.clear.frame(height: 0).accessibilityHidden(true)
                    .uiSmokeControl(id: "editor.date.help", value: { dateHelp })
            }
        }
    }

    private var eventOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Показывать погоду для этого дня", isOn: $draft.showsWeather)
                .accessibilityIdentifier("editor.weather")
                .uiSmokeControl(id: "editor.weather", action: { draft.showsWeather.toggle() },
                                value: { draft.showsWeather ? "on" : "off" })
            Toggle("Основное — в строке меню", isOn: $primary)
                .accessibilityIdentifier("editor.primary")
                .uiSmokeControl(id: "editor.primary", action: { primary.toggle() },
                                value: { primary ? "Выбрано" : "Не выбрано" })
        }
        .toggleStyle(.checkbox)
        .font(.system(size: 12))
        .padding(.bottom, 4)
    }

    private var editorActions: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isUnavailable {
                Text("Событие больше недоступно. Черновик сохранён в этом окне; сохранить его как это событие нельзя.")
                    .font(.caption)
                    .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("editor.unavailable")
                    .uiSmokeControl(id: "editor.unavailable")
            }
            if confirmingDeletion && !isUnavailable { deletionControls }
            Divider()
            HStack(spacing: 9) {
                if item != nil && !isUnavailable {
                    Button(role: .destructive) { confirmingDeletion = true } label: {
                        Label("Удалить", systemImage: "trash")
                            .font(.system(size: 11))
                            .frame(minHeight: 28)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                    .accessibilityIdentifier("event.delete")
                    .uiSmokeControl(id: "event.delete", action: { confirmingDeletion = true })
                    .disabled(isSaving || isImportingAttachments || confirmingDeletion)
                }
                Spacer(minLength: 0)
                Button("Отмена", action: cancel)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("editor.cancel")
                    .uiSmokeControl(id: "editor.cancel", action: cancel)
                    .disabled(isSaving)
                Button(action: save) {
                    if isSaving { ProgressView().controlSize(.small) }
                    else { Text("Сохранить") }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(AuroraInstrument.accent(for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast))
                .foregroundStyle(colorScheme == .dark ? AuroraInstrument.canvas(for: colorScheme) : .white)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("editor.save")
                .uiSmokeControl(id: "editor.save", action: save)
                .disabled(!canSave || isSaving || isImportingAttachments || confirmingDeletion)
            }
            .controlSize(.regular)
            .font(.system(size: 12))
            .padding(.horizontal, 16)
            .frame(height: 58)
        }
    }

    private var deletionControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Удалить событие, подзадачи и прикреплённые копии файлов без возможности восстановления? Исходные файлы сохранятся.")
                .font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                Button("Не удалять") { confirmingDeletion = false }
                    .accessibilityIdentifier("event.delete.cancel")
                    .uiSmokeControl(id: "event.delete.cancel", action: { confirmingDeletion = false })
                Button("Удалить событие", role: .destructive, action: delete)
                    .accessibilityIdentifier("event.delete.confirm")
                    .uiSmokeControl(id: "event.delete.confirm", action: delete)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AuroraInstrument.surface(for: colorScheme, elevated: false,
                                            highContrast: accessibilitySettings.prefersHighContrast))
        .disabled(isSaving || isImportingAttachments)
    }

    private func delete() {
        guard let item, !isUnavailable, !isSaving, !isImportingAttachments else { return }
        isSaving = true
        Task {
            if await store.delete(item.id) {
                await attachmentSession.discard(in: store)
                done()
            }
            isSaving = false
        }
    }

    private var dateHelp: String {
        guard validDate else { return "Прошлая дата недоступна. Выберите сегодня или позже." }
        return Day(date) == store.today ? EventUIStrings.todayExpiryNotice : "Можно выбрать сегодня или будущую дату."
    }

    private func editorSubtasks(scrollProxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Подзадачи").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AuroraInstrument.ink(for: colorScheme))
                    .uiSmokeControl(id: "editor.subtasks.heading")
                Spacer()
                Text("\(draft.subtasks.count)/\(Subtask.maximumCount)").font(.caption2).foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
            }
            ForEach(draft.subtasks) { subtask in
                EditorSubtaskRow(
                    draft: $draft,
                    subtask: subtask,
                    focusedField: $focusedField,
                    focusField: focus,
                    deleteRow: removeSubtask
                )
                .id(subtask.id)
                .transition(accessibilitySettings.prefersReducedMotion ? .identity : .opacity)
            }
            Group {
                if draft.subtasks.count < Subtask.maximumCount {
                    Button { addSubtask(scrollProxy: scrollProxy) } label: {
                        Label("Добавить подзадачу", systemImage: "plus")
                            .font(.system(size: 12))
                            .frame(minHeight: 26)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AuroraInstrument.accentInk(
                        for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast
                    ))
                    .accessibilityLabel("Добавить подзадачу")
                    .accessibilityIdentifier("editor.subtask.add")
                    .uiSmokeControl(
                        id: "editor.subtask.add",
                        action: { addSubtask(scrollProxy: scrollProxy) }
                    )
                }
            }
            .disabled(draft.subtasks.count >= Subtask.maximumCount)
            .allowsHitTesting(draft.subtasks.count < Subtask.maximumCount)
            .accessibilityHidden(draft.subtasks.count >= Subtask.maximumCount)
        }
        .animation(editorSubtaskAnimation, value: draft.subtasks.map(\.id))
        .transaction { transaction in
            if accessibilitySettings.prefersReducedMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
        .uiSmokeControl(id: "editor.subtasks", value: { String(draft.subtasks.count) })
    }

    private var emojiControls: some View {
        VStack(alignment: .leading, spacing: 0) {
            emojiSelectionField
            emojiPickerContents
                .padding(.top, emojiPicker.isOpen ? 8 : 0)
        }
        .transaction { transaction in
            if accessibilitySettings.prefersReducedMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
    }

    private var emojiSelectionField: some View {
        ZStack(alignment: .trailing) {
            Button(action: toggleEmojiPicker) {
                HStack {
                    Text("Значок")
                        .font(.system(size: 12))
                    Spacer(minLength: 8)
                    Text(draft.emoji.isEmpty ? "Без значка" : draft.emoji)
                        .font(.system(size: draft.emoji.isEmpty ? 11 : 22))
                        .foregroundStyle(draft.emoji.isEmpty
                            ? AuroraInstrument.secondaryInk(for: colorScheme) : AuroraInstrument.ink(for: colorScheme))
                        .frame(height: 28, alignment: .leading)
                        .id(draft.emoji)
                        .transition(.opacity)
                        .animation(accessibilitySettings.prefersReducedMotion ? nil
                            : .easeInOut(duration: editorEmojiValueTransitionDuration), value: draft.emoji)
                        .accessibilityHidden(true)
                        .uiSmokeControl(id: "editor.emoji", value: { draft.emoji })
                }
                .padding(.leading, 10)
                .padding(.trailing, draft.emoji.isEmpty ? 34 : 60)
                .frame(maxWidth: .infinity, minHeight: 38, maxHeight: 38)
                .contentShape(Rectangle())
                .overlay(alignment: .trailing) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                        .rotationEffect(.degrees(emojiPicker.isOpen ? 180 : 0))
                        .animation(emojiPickerAnimation, value: emojiPicker.isOpen)
                        .padding(.trailing, 10)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .buttonStyle(.plain)
            .focused($focusedField, equals: .emoji)
            .accessibilityLabel(emojiPicker.isOpen
                ? "Скрыть выбор значка, \(draft.emoji.isEmpty ? "без значка" : "текущий значок: " + draft.emoji)"
                : (draft.emoji.isEmpty ? "Выбрать значок" : "Изменить значок: \(draft.emoji)"))
            .accessibilityValue(emojiPicker.isOpen ? "Раскрыто" : "Свёрнуто")
            .accessibilityIdentifier("editor.emoji.toggle")
            .uiSmokeControl(
                id: "editor.emoji.toggle",
                action: toggleEmojiPicker,
                value: { emojiPicker.isOpen ? "expanded" : "collapsed" }
            )

            if !draft.emoji.isEmpty {
                Button(action: clearEmoji) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 34)
                .accessibilityLabel("Убрать значок")
                .help("Убрать значок")
                .accessibilityIdentifier("editor.emoji.none")
                .uiSmokeControl(id: "editor.emoji.none", action: clearEmoji)
            }
        }
        .background(AuroraInstrument.canvas(for: colorScheme),
                    in: RoundedRectangle(cornerRadius: AuroraInstrument.inputCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AuroraInstrument.inputCornerRadius)
                .stroke(
                    focusedField == .emoji
                        ? AuroraInstrument.accent(for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast)
                        : AuroraInstrument.stroke(for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast),
                    lineWidth: focusedField == .emoji ? 2 : 1
                )
                .allowsHitTesting(false)
        }
    }

    private var emojiPickerContents: some View {
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if emojiPicker == .presets {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: Self.emojiSpacing) {
                            ForEach(EventEmojiCatalog.presets, id: \.self) { symbol in
                                emojiButton(symbol, identifier: "editor.emoji.preset.\(emojiIdentifier(symbol))")
                            }
                        }
                        .frame(height: Self.emojiCellHeight, alignment: .top)
                        .uiSmokeControl(id: "editor.emoji.quick", value: { "1x8" })
                        Button(action: showEmojiCatalog) {
                            HStack {
                                Text("Все значки")
                                Image(systemName: "chevron.right").font(.system(size: 10))
                                Spacer()
                            }
                            .font(.system(size: 12))
                            .frame(minHeight: 28)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                        .accessibilityLabel("Все значки")
                        .accessibilityIdentifier("editor.emoji.more")
                        .uiSmokeControl(id: "editor.emoji.more", action: showEmojiCatalog, value: { "collapsed" })
                    }
                    .transition(.opacity)
                }
            }
            .disabled(emojiPicker != .presets)
            .allowsHitTesting(emojiPicker == .presets)
            .accessibilityHidden(emojiPicker != .presets)
            Group {
                if emojiPicker.isCatalog {
                    expandedEmojiPicker.transition(.opacity)
                }
            }
            .disabled(!emojiPicker.isCatalog)
            .allowsHitTesting(emojiPicker.isCatalog)
            .accessibilityHidden(!emojiPicker.isCatalog)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AuroraInstrument.canvas(for: colorScheme),
                    in: RoundedRectangle(cornerRadius: AuroraInstrument.cardCornerRadius))
        .overlay(RoundedRectangle(cornerRadius: AuroraInstrument.cardCornerRadius)
            .stroke(AuroraInstrument.stroke(
                for: colorScheme,
                highContrast: accessibilitySettings.prefersHighContrast
            ), lineWidth: 1)
            .allowsHitTesting(false))
        .fixedSize(horizontal: false, vertical: true)
        .frame(height: emojiPicker.isOpen ? nil : 0, alignment: .top)
        .opacity(emojiPicker.isOpen ? 1 : 0)
        .clipped()
        .disabled(!emojiPicker.isOpen)
        .allowsHitTesting(emojiPicker.isOpen)
        .accessibilityHidden(!emojiPicker.isOpen)
        .animation(emojiPickerAnimation, value: emojiPicker)
        .uiSmokeControl(id: "editor.emoji.picker", value: { emojiPicker.isOpen ? "expanded" : "collapsed" })
    }

    private var expandedEmojiPicker: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(0..<Self.emojiPageCount, id: \.self) { page in
                    Group {
                        if page == emojiPage {
                            emojiPageGrid(page)
                        } else {
                            Color.clear.accessibilityHidden(true)
                        }
                    }
                    .frame(width: Self.emojiPageWidth, height: Self.emojiExpandedHeight, alignment: .topLeading)
                    .disabled(page != emojiPage)
                    .allowsHitTesting(page == emojiPage)
                    .accessibilityHidden(page != emojiPage)
                }
            }
            .offset(x: -CGFloat(emojiPage) * Self.emojiPageWidth)
            .frame(
                width: Self.emojiPageWidth,
                height: Self.emojiExpandedHeight,
                alignment: .topLeading
            )
            .clipped()
            .contentShape(Rectangle())
            .gesture(emojiPageSwipe)
            .uiSmokeControl(
                id: "editor.emoji.expanded",
                value: { "6x8 page \(emojiPage + 1)/\(Self.emojiPageCount)" }
            )

            Text(Self.emojiPageTitles[emojiPage])
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                .frame(width: Self.emojiPageWidth, alignment: .center)
                .accessibilityIdentifier("editor.emoji.category")
                .uiSmokeControl(
                    id: "editor.emoji.category",
                    value: { Self.emojiPageTitles[emojiPage] }
                )

            emojiPagination
        }
    }

    private func emojiPageGrid(_ page: Int) -> some View {
        let startColumn = page * Self.emojiColumnsPerPage
        let endColumn = startColumn + Self.emojiColumnsPerPage

        return HStack(alignment: .top, spacing: Self.emojiSpacing) {
            ForEach(startColumn..<endColumn, id: \.self) { column in
                VStack(spacing: Self.emojiSpacing) {
                    ForEach(0..<Self.emojiRows.count, id: \.self) { row in
                        let symbol = Self.emojiRows[row][column]
                        emojiButton(
                            symbol,
                            identifier: emojiPageIdentifier(
                                page: page,
                                row: row,
                                column: column - startColumn,
                                symbol: symbol
                            )
                        )
                    }
                }
            }
        }
        .frame(height: Self.emojiExpandedHeight, alignment: .top)
    }

    private var emojiPagination: some View {
        HStack(spacing: 8) {
            Button(action: previousEmojiPage) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("Предыдущий набор emoji")
            .accessibilityLabel("Предыдущий набор emoji")
            .accessibilityIdentifier("editor.emoji.page.previous")
            .uiSmokeControl(id: "editor.emoji.page.previous", action: previousEmojiPage)
            .disabled(emojiPage == 0)

            HStack(spacing: 5) {
                ForEach(0..<Self.emojiPageCount, id: \.self) { page in
                    Button {
                        setEmojiPage(page)
                    } label: {
                        Circle()
                            .fill(page == emojiPage ? Color.primary : Color.secondary.opacity(0.35))
                            .frame(width: 6, height: 6)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        page == emojiPage
                            ? "\(Self.emojiPageTitles[page]), страница \(page + 1) из \(Self.emojiPageCount), текущая"
                            : "\(Self.emojiPageTitles[page]), перейти на страницу \(page + 1) из \(Self.emojiPageCount)"
                    )
                    .accessibilityIdentifier("editor.emoji.page.dot.\(page + 1)")
                    .uiSmokeControl(
                        id: "editor.emoji.page.dot.\(page + 1)",
                        action: { setEmojiPage(page) },
                        value: { page == emojiPage ? "selected" : "idle" }
                    )
                }
            }

            Button(action: nextEmojiPage) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .help("Следующий набор emoji")
            .accessibilityLabel("Следующий набор emoji")
            .accessibilityIdentifier("editor.emoji.page.next")
            .uiSmokeControl(id: "editor.emoji.page.next", action: nextEmojiPage)
            .disabled(emojiPage == Self.emojiPageCount - 1)
        }
        .frame(width: Self.emojiPageWidth, alignment: .center)
        .accessibilityElement(children: .contain)
        .uiSmokeControl(
            id: "editor.emoji.page",
            value: { "\(emojiPage + 1)/\(Self.emojiPageCount)" }
        )
    }

    private var emojiPageSwipe: some Gesture {
        DragGesture(minimumDistance: 18)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical), abs(horizontal) > 28 else { return }
                if horizontal < 0 {
                    nextEmojiPage()
                } else {
                    previousEmojiPage()
                }
            }
    }

    private func emojiButton(_ symbol: String, identifier: String) -> some View {
        Button(symbol) {
            chooseEmoji(symbol)
        }
        .buttonStyle(.plain)
        .font(.system(size: 22))
        .frame(width: Self.emojiCellWidth, height: Self.emojiCellHeight)
        .background { emojiSelectionBackground(isSelected: draft.emoji == symbol) }
        .overlay {
            if draft.emoji == symbol {
                RoundedRectangle(cornerRadius: AuroraInstrument.emojiCornerRadius)
                    .stroke(
                        AuroraInstrument.accentBorder(
                            for: colorScheme,
                            highContrast: accessibilitySettings.prefersHighContrast
                        ),
                        lineWidth: 1
                    )
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityLabel("Emoji: \(symbol)")
        .accessibilityValue(draft.emoji == symbol ? "Выбрано" : "Не выбрано")
        .accessibilityIdentifier(identifier)
        .uiSmokeControl(
            id: identifier,
            action: { chooseEmoji(symbol) }
        )
    }

    private func emojiSelectionBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: AuroraInstrument.emojiCornerRadius)
            .fill(isSelected ? AuroraInstrument.accentSurface(
                for: colorScheme,
                highContrast: accessibilitySettings.prefersHighContrast
            ) : AuroraInstrument.stroke(for: colorScheme, highContrast: false).opacity(0.2))
    }

    private func emojiPageIdentifier(page: Int, row: Int, column: Int, symbol: String) -> String {
        let prefix = row == 0 && page == 0 && column < EventEmojiCatalog.presets.count
            ? "editor.emoji.preset"
            : "editor.emoji.option"
        return "\(prefix).page.\(page + 1).row.\(row + 1).column.\(column + 1).\(emojiIdentifier(symbol))"
    }

    private func chooseEmoji(_ symbol: String) {
        guard CountdownData.isEmoji(symbol) else { return }
        withAnimation(emojiPickerAnimation) {
            _ = draft.replaceEmoji(with: symbol)
            emojiPicker.close()
            focusedField = .emoji
        }
    }

    private func clearEmoji() {
        withAnimation(emojiPickerAnimation) {
            draft.clearEmoji()
            emojiPicker.close()
            focusedField = .emoji
        }
    }

    private func toggleEmojiPicker() {
        withAnimation(emojiPickerAnimation) {
            emojiPicker.toggle()
        }
    }

    private func showEmojiCatalog() {
        withAnimation(emojiPickerAnimation) {
            emojiPicker.showCatalog()
        }
    }

    private func setEmojiPage(_ page: Int) {
        guard emojiPicker.isCatalog else { return }
        withAnimation(emojiPickerAnimation) {
            emojiPicker.setPage(page, pageCount: Self.emojiPageCount)
        }
    }

    private func previousEmojiPage() {
        setEmojiPage(emojiPage - 1)
    }

    private func nextEmojiPage() {
        setEmojiPage(emojiPage + 1)
    }

    private var editorSubtaskAnimation: Animation? {
        switch editorSubtaskMotion(reduceMotion: accessibilitySettings.prefersReducedMotion) {
        case .immediate:
            nil
        case let .heightAndOpacity(duration):
            .easeInOut(duration: duration)
        }
    }

    private func removeSubtask(_ id: UUID) {
        guard draft.subtasks.contains(where: { $0.id == id }) else { return }
        if focusedField == .subtask(id) {
            focusedField = nil
        }
        withAnimation(editorSubtaskAnimation) {
            draft.subtasks.removeAll { $0.id == id }
        }
    }

    private func addSubtask(scrollProxy: ScrollViewProxy) {
        let result = withAnimation(editorSubtaskAnimation) { draft.addSubtask() }
        guard let target = result, case let .subtask(id) = target else { return }
        Task { @MainActor in
            await Task.yield()
            guard draft.subtasks.contains(where: { $0.id == id }) else { return }
            scrollProxy.scrollTo(id, anchor: .center)
            focusedField = target
            await Task.yield()
            if UISmokeConfiguration.wasRequested && focusedField == target {
                UISmokeControlRegistry.shared.markFocused("editor.subtask.\(id.uuidString)")
            }
        }
    }

    private func focus(_ target: EditorFocusTarget, id: String) {
        if target == .note {
            focusedField = nil
            Task { @MainActor in
                await Task.yield()
                noteFocusRequest += 1
            }
            return
        }
        focusedField = target
        Task { @MainActor in
            await Task.yield()
            if UISmokeConfiguration.wasRequested && focusedField == target {
                UISmokeControlRegistry.shared.markFocused(id)
            }
        }
    }

    private func cancel() {
        guard !isSaving else { return }
        DiagnosticLog.shared.record("editor.cancel mode=\(item == nil ? "new" : "edit")")
        attachmentSession.cancel()
        done()
    }

    private func addAttachments() {
        guard !isSaving, !isImportingAttachments, !isUnavailable, !confirmingDeletion,
              draft.attachments.count < EventAttachment.maximumCount else { return }
        isImportingAttachments = true
        let draftBinding = $draft
        let importingBinding = $isImportingAttachments
        attachmentSession.importFiles(in: store, currentAttachments: draft.attachments) { imported in
            draftBinding.wrappedValue.attachments.append(contentsOf: imported)
            importingBinding.wrappedValue = false
        }
    }

    private func save() {
        guard canSave, !isSaving, !isImportingAttachments, !confirmingDeletion else { return }
        if let item, item.date < Day(Date()) {
            store.refresh()
            return
        }
        let countdown = draft.countdown(id: item?.id ?? UUID(), date: Day(date))
        isSaving = true
        Task {
            if await store.save(countdown, primary: primary, requireExisting: item != nil) {
                await attachmentSession.discard(in: store)
                didSave(countdown)
                done()
            }
            isSaving = false
        }
    }

    private func emojiIdentifier(_ symbol: String) -> String {
        symbol.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: "-")
    }
}

private struct EditorSubtaskRow: View {
    @Binding var draft: EventEditorDraft
    let subtask: Subtask
    @FocusState.Binding var focusedField: EditorFocusTarget?
    let focusField: (EditorFocusTarget, String) -> Void
    let deleteRow: (UUID) -> Void
    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @Environment(\.colorScheme) private var colorScheme

    private var currentSubtask: Subtask {
        draft.subtasks.first { $0.id == subtask.id } ?? subtask
    }

    private var isAvailable: Bool {
        draft.subtasks.contains { $0.id == subtask.id }
    }

    private var text: Binding<String> {
        Binding(
            get: { currentSubtask.text },
            set: { value in
                guard let index = draft.subtasks.firstIndex(where: { $0.id == subtask.id }) else { return }
                draft.subtasks[index].text = value
            }
        )
    }

    var body: some View {
        HStack(spacing: 7) {
            if currentSubtask.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                    .accessibilityLabel("Выполнена")
            }
            TextField("Подзадача", text: text)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .frame(minHeight: 28)
                .focused($focusedField, equals: .subtask(subtask.id))
                .accessibilityIdentifier("editor.subtask.\(subtask.id.uuidString)")
                .uiSmokeControl(
                    id: "editor.subtask.\(subtask.id.uuidString)",
                    action: {
                        guard isAvailable else { return }
                        focusField(.subtask(subtask.id), "editor.subtask.\(subtask.id.uuidString)")
                    },
                    value: { currentSubtask.text }
                )
            if focusedField == .subtask(subtask.id) || currentSubtask.text.count > Subtask.maximumTextLength {
                Text("\(currentSubtask.text.count)/\(Subtask.maximumTextLength)")
                    .font(.system(size: 10))
                    .foregroundStyle(currentSubtask.text.count <= Subtask.maximumTextLength
                        ? AuroraInstrument.secondaryInk(for: colorScheme) : .red)
                    .frame(width: 34, alignment: .trailing)
            }
            Button(role: .destructive) { deleteRow(subtask.id) } label: {
                Image(systemName: "trash")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Удалить подзадачу")
            .accessibilityLabel("Удалить подзадачу")
            .accessibilityIdentifier("editor.subtask.delete.\(subtask.id.uuidString)")
            .uiSmokeControl(id: "editor.subtask.delete.\(subtask.id.uuidString)", action: { deleteRow(subtask.id) })
        }
        .disabled(!isAvailable)
        .allowsHitTesting(isAvailable)
        .accessibilityHidden(!isAvailable)
    }
}
