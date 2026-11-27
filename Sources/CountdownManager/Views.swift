import AppKit
import SwiftUI
import ServiceManagement
import CountdownCore

enum PlannerSection: String {
    case events
    case records

    var title: String {
        switch self {
        case .events: AppText.string("record.section.events")
        case .records: AppText.string("record.section.records")
        }
    }
}

struct PlannerSectionPicker: View {
    @Binding var selection: PlannerSection
    let surface: String
    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Picker(AppText.string("record.section.label"), selection: $selection) {
            Text(PlannerSection.events.title).tag(PlannerSection.events)
            Text(PlannerSection.records.title).tag(PlannerSection.records)
        }
        .pickerStyle(.segmented)
        // AppKit uses a white title on the selected tinted segment in both appearances.
        .tint(AuroraInstrument.accentInk(for: .light, highContrast: colorScheme == .light || accessibilitySettings.prefersHighContrast))
        .labelsHidden()
        .frame(width: 184)
        .accessibilityLabel(AppText.string("record.section.label"))
        .accessibilityIdentifier("\(surface).section")
        .uiSmokeControl(id: "\(surface).section", value: { selection.rawValue })
        .uiSmokeControl(id: "\(surface).section.events", action: { selection = .events })
        .uiSmokeControl(id: "\(surface).section.records", action: { selection = .records })
    }
}

func recordCountLabel(_ count: Int) -> String {
    let noun: String
    switch AppText.pluralCategory(count) {
    case .one: noun = AppText.string("record.count.one")
    case .few: noun = AppText.string("record.count.few")
    case .many: noun = AppText.string("record.count.many")
    }
    return AppText.string("event.count.label", String(count), noun)
}

struct ManagerView: View {
    @ObservedObject var store: Store
    @ObservedObject var updates: ApplicationUpdates
    @ObservedObject var editorSession: EventEditorSession
    @ObservedObject var keepAwake: KeepAwakeController
    @ObservedObject var weather: WeatherController
    let diagnosticsContext: () -> DiagnosticExportContext
    var showDesktop: () -> Void = {}
    var showWhatsNew: () -> Void = {}
    @State private var textAttachmentRequest: TextAttachmentRequest?
    @State private var editing: Countdown?
    @State private var recordEditor: RecordEditorRequest?
    @State private var section: PlannerSection = .events
    @State private var copying: Countdown?
    private var showingEditor: Bool { editorSession.isPresented }
    @State private var showingDayChoices = false
    @State private var showingSettings = false
    @State private var attachmentListOwnerID: SavedMaterialOwnerID?
    @State private var attachmentLibraryIsSource = false
    @StateObject private var attachmentPreview = AttachmentPreviewSession()
    @State private var dayPreset: DayCreationPreset?
    @State private var weekCreation: DayCreationWeek?
    @State private var selectDayDate = false
    @State private var rootIdentity = UUID()
    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme

    private struct RecordEditorRequest {
        let record: UndatedRecord?
    }

    private var attachmentListOwner: SavedMaterialOwner? {
        guard let id = attachmentListOwnerID, let owner = store.savedMaterialOwner(id), !owner.attachments.isEmpty else {
            return nil
        }
        return owner
    }

    private var canSelectSection: Bool { !editorSession.hasActiveEditor && !store.isResolvingMaterials }

    private var sectionSelection: Binding<PlannerSection> {
        Binding(get: { section }, set: { next in
            guard canSelectSection else { return }
            section = next
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            if let error = store.error {
                VStack(alignment: .leading, spacing: 6) {
                    Text(error).font(.caption).textSelection(.enabled)
                    Button(AppText.string("common.ok")) { store.error = nil }
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
                    .opacity(showingEditor || showingSettings || attachmentListOwner != nil ? 0 : 1)
                    .disabled(showingEditor || showingSettings || attachmentListOwner != nil)
                    .allowsHitTesting(!showingEditor && !showingSettings && attachmentListOwner == nil)
                    .accessibilityHidden(showingEditor || showingSettings || attachmentListOwner != nil)
                if let ownerID = attachmentListOwnerID, let item = attachmentListOwner, !showingEditor, !showingSettings {
                    attachmentScreen(item: item, ownerID: ownerID)
                    .id(item.id)
                }
                if showingSettings {
                    SettingsView(store: store, updates: updates, keepAwake: keepAwake, weather: weather,
                                 diagnosticsContext: diagnosticsContext, showWhatsNew: showWhatsNew) {
                        showingSettings = false
                    }
                }
                if let request = textAttachmentRequest {
                    let unavailable = request.ownerID.panelSection == .events
                        ? AppText.string("event.unavailable") : AppText.string("record.unavailable")
                    TextAttachmentComposer(text: request.text,
                        eventTitle: store.savedMaterialOwner(request.ownerID)?.displayTitle ?? unavailable,
                        submit: { text in
                            let saved = await store.appendMaterials(EventMaterials(textFile: text), to: request.ownerID)
                            if saved { finishEditor() }
                            return saved
                        }, cancel: finishEditor)
                }
                if showingEditor, let weekCreation {
                    WeekDayCreationView(store: store, week: weekCreation, didCreate: { events in
                        if NSApp.isActive, let event = events.first {
                            weather.didSaveEvent(event, activeEvents: store.active)
                        } else {
                            weather.updateEvents(store.active)
                        }
                    }, cancel: finishEditor)
                }
                if showingEditor, let recordEditor {
                    EditorView(store: store, record: recordEditor.record, didSave: { _ in }, done: finishEditor)
                }
                if showingEditor, textAttachmentRequest == nil, weekCreation == nil, recordEditor == nil {
                    EditorView(
                        store: store,
                        item: editing,
                        copying: copying,
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
        .onChange(of: store.data) { _ in
            closeUnavailableAttachmentList()
            if !store.hasPendingPersistence {
                editorSession.reconcileSubtaskTransfer(items: store.data.items, today: store.today)
            }
        }
        .onChange(of: store.records) { _ in closeUnavailableAttachmentList() }
        .onChange(of: section) { _ in showingDayChoices = false }
        .onChange(of: store.today) { _ in
            closeUnavailableAttachmentList()
            editorSession.reconcileSubtaskTransfer(items: store.data.items, today: store.today)
        }
        .onChange(of: attachmentPreview.selection) { selection in
            if selection == nil, !attachmentLibraryIsSource { attachmentListOwnerID = nil }
        }
    }

    private var listScreen: some View {
        VStack(spacing: 0) {
            if editorSession.desktopIsPresented || editorSession.subtaskTransfer?.surface == .desktop {
                Text(editorSession.subtaskTransfer?.surface == .desktop
                     ? AppText.string("panel.pendingTransfer") : AppText.string("panel.pendingEditor"))
                    .font(.system(size: 11))
                    .padding(8)
                    .accessibilityIdentifier("desktop.editor.active")
            }
            HStack {
                PlannerSectionPicker(selection: sectionSelection, surface: "panel")
                    .disabled(!canSelectSection)
                Spacer()
            }
            .padding(.horizontal, 16)
            .frame(height: 43)
            Divider()
            ZStack {
                eventList
                    .opacity(section == .events ? 1 : 0)
                    .disabled(section != .events)
                    .allowsHitTesting(section == .events)
                    .accessibilityElement(children: section == .events ? .contain : .ignore)
                    .accessibilityHidden(section != .events)
                recordList
                    .opacity(section == .records ? 1 : 0)
                    .disabled(section != .records)
                    .allowsHitTesting(section == .records)
                    .accessibilityElement(children: section == .records ? .contain : .ignore)
                    .accessibilityHidden(section != .records)
            }
            Divider()
            footer
        }
    }

    private var eventList: some View {
        let displayed = store.active
        let primaryID = store.data.primaryID
        return VStack(spacing: 0) {
            if store.showsEmptyEventList {
                emptyEventList
                    .disabled(editorSession.desktopIsPresented)
            } else {
                eventListHeader(activeCount: displayed.count)
                    .disabled(editorSession.desktopIsPresented)
                if showingDayChoices && !displayed.isEmpty {
                    dayChoices
                        .disabled(editorSession.desktopIsPresented)
                }
                savedCardList(for: .events) {
                    if store.isLoading {
                        VStack(spacing: 12) {
                            AuroraLoadingPlaceholder()
                            ProgressView(AppText.string("app.loadingEvents"))
                        }
                    }
                    ForEach(displayed) { item in row(item, primaryID: primaryID) }
                }
                .accessibilityIdentifier("event.list")
                .uiSmokeControl(id: "event.list")
                .disabled(editorSession.desktopIsPresented)
            }
        }
    }

    @ViewBuilder
    private var recordList: some View {
        if store.isLoadingRecords {
            VStack(spacing: 12) {
                AuroraLoadingPlaceholder()
                ProgressView(AppText.string("record.loading"))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.showsEmptyRecordList {
            emptyRecordList
        } else if store.records.isEmpty {
            Text(AppText.string("record.unavailable"))
                .font(.system(size: 12))
                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 0) {
                listHeader {
                    listHeading(recordCountLabel(store.records.count), id: "panel.records.count")
                } actions: {
                    creationButton(AppText.string("record.create"), id: "panel.record.create", action: createRecord)
                        .disabled(!canEditRecord)
                }
                savedCardList(for: .records) {
                    ForEach(store.records) { recordCard($0) }
                }
                .accessibilityIdentifier("panel.records")
                .uiSmokeControl(id: "panel.records", value: { String(store.records.count) })
            }
        }
    }

    private func savedCardList<Cards: View>(for section: PlannerSection, @ViewBuilder cards: () -> Cards) -> some View {
        ScrollView {
            VStack(spacing: 10, content: cards)
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .animation(
                    accessibilitySettings.prefersReducedMotion ? nil : .easeInOut(duration: 0.2),
                    value: section == .events ? store.data.primaryID : nil
                )
        }
    }

    private var emptyRecordList: some View {
        VStack(spacing: 16) {
            Text(AppText.string("record.empty.title"))
                .font(.custom("Georgia", size: 24))
                .tracking(-0.5)
            Text(AppText.string("record.empty.message"))
                .font(.system(size: 12))
                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            emptyPrimaryAction(AppText.string("record.create"), id: "panel.record.create", symbol: "plus", action: createRecord)
                .frame(width: 260)
                .disabled(!canEditRecord)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 36)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("panel.records.empty")
        .uiSmokeControl(id: "panel.records.empty")
    }

    private func creationButton(_ label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "plus")
                .frame(width: 31, height: 31)
                .foregroundStyle(colorScheme == .dark ? AuroraInstrument.canvas(for: colorScheme) : .white)
                .background(plannerAccent, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
        .uiSmokeControl(id: id, action: action)
    }

    private var canEditRecord: Bool {
        store.recordCreationIsAvailable && !store.hasPendingPersistence && !editorSession.hasActiveEditor
    }

    private func recordCard(_ item: UndatedRecord) -> some View {
        let id = item.id.uuidString
        return savedCard(.record(item), note: item.note, noteSpacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(item.title)
                AuroraSymbolAction(symbolName: "pencil", surface: .mini, tone: .secondary,
                                   accessibilityLabel: AppText.string("record.editNamed", item.title)) {
                    openRecordEditor(item.id)
                }
                .help(AppText.string("record.edit"))
                .accessibilityIdentifier("panel.record.edit.\(id)")
                .uiSmokeControl(id: "panel.record.edit.\(id)", action: { openRecordEditor(item.id) })
                .disabled(!canEditRecord)
            }
        }
    }

    private var emptyEventList: some View {
        VStack(spacing: 0) {
            PlannerCalendarDateTile(monthControlID: "event.empty.month", day: store.today, isFeatured: false)
                .accessibilityHidden(true)
                .uiSmokeControl(id: "event.empty.date", value: { currentDayHeaderLabel(store.today, locale: locale) })
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
                emptyPrimaryAction(AppText.string("event.createToday"), id: "event.empty.today") {
                    createDay(preset: .today(store.today))
                }
                HStack(spacing: 8) {
                    emptySecondaryAction(AppText.string("event.createTomorrow"), id: "event.empty.tomorrow") { createDay(preset: .tomorrow(after: store.today)) }
                    emptySecondaryAction(AppText.string("event.chooseDate"), id: "event.empty.chooseDate") {
                        createDay(preset: .tomorrow(after: store.today), selectDate: true)
                    }
                }
                emptySecondaryAction(weekCreationTitle(for: store.today) + "…", id: "event.empty.week",
                                     action: createWeekDays)
                    .foregroundStyle(plannerAccent)
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

    private func emptyPrimaryAction(_ title: String, id: String, symbol: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                if let symbol { Label(title, systemImage: symbol) }
                else { Text(title) }
            }
            .font(.system(size: 13, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .foregroundStyle(colorScheme == .dark ? AuroraInstrument.canvas(for: colorScheme) : .white)
            .background(plannerAccent, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .uiSmokeControl(id: id, action: action)
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

    private func eventListHeader(activeCount: Int) -> some View {
        listHeader {
            VStack(alignment: .leading, spacing: 3) {
                listHeading(currentDayHeaderLabel(store.today, locale: locale), id: "header.today")
                Text(eventCountLabel(activeCount))
                    .font(.system(size: 11))
                    .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                    .uiSmokeControl(id: "header.active-count", value: { eventCountLabel(activeCount) })
            }
        } actions: {
            Button(action: toggleDayChoices) {
                Image(systemName: "calendar.badge.plus")
                    .frame(width: 31, height: 31)
            }
                .buttonStyle(.plain)
                .help(EventUIStrings.createDay).accessibilityLabel(EventUIStrings.createDay)
                .accessibilityIdentifier("day.add")
                .uiSmokeControl(id: "day.add", action: toggleDayChoices)
                .disabled(!store.eventCreationIsAvailable || editorSession.hasActiveEditor)
            creationButton(EventUIStrings.addEvent, id: "event.add", action: add)
                .disabled(!store.eventCreationIsAvailable || editorSession.hasActiveEditor)
        }
    }

    private func listHeading(_ title: String, id: String) -> some View {
        Text(title)
            .font(.system(size: 15, weight: .semibold))
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier(id)
            .uiSmokeControl(id: id, value: { title })
    }

    private func listHeader<Heading: View, Actions: View>(
        @ViewBuilder heading: () -> Heading, @ViewBuilder actions: () -> Actions
    ) -> some View {
        HStack {
            heading()
            Spacer()
            actions()
        }
        .frame(height: 36)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var dayChoices: some View {
        VStack(spacing: 8) {
            HStack {
                Text(EventUIStrings.createDay).font(.caption).foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                    .uiSmokeControl(id: "creation.day.label")
                Spacer()
                Button(AppText.string("calendar.today")) { createDay(preset: .today(store.today)) }
                    .accessibilityIdentifier("creation.day.today")
                    .uiSmokeControl(id: "creation.day.today", action: { createDay(preset: .today(store.today)) })
                Button(AppText.string("calendar.tomorrow")) { createDay(preset: .tomorrow(after: store.today)) }
                    .accessibilityIdentifier("creation.day.tomorrow")
                    .uiSmokeControl(id: "creation.day.tomorrow", action: { createDay(preset: .tomorrow(after: store.today)) })
                Button(AppText.string("event.chooseDate")) { createDay(preset: .tomorrow(after: store.today), selectDate: true) }
                    .accessibilityIdentifier("creation.day.chooseDate")
                    .uiSmokeControl(id: "creation.day.chooseDate", action: {
                        createDay(preset: .tomorrow(after: store.today), selectDate: true)
                    })
            }
            Button(action: createWeekDays) {
                Text(weekCreationTitle(for: store.today) + "…")
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(plannerAccent)
            }
                .accessibilityIdentifier("creation.day.week")
                .uiSmokeControl(id: "creation.day.week", action: createWeekDays)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .disabled(!store.eventCreationIsAvailable || editorSession.hasActiveEditor)
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
        return savedCard(.event(item), note: presentation.note, noteSpacing: presentation.isFeatured ? 7 : 8) {
            if presentation.isFeatured {
                featuredEvent(item, presentation: presentation)
            } else {
                secondaryEvent(item, presentation: presentation)
            }
        }
    }

    private func savedCard<Header: View>(_ owner: SubtaskChecklistView.Owner, note: String?, noteSpacing: CGFloat,
                                         @ViewBuilder header: () -> Header) -> some View {
        let ownerID = owner.materialID
        let material = owner.materials
        let record = ownerID.panelSection == .records
        let identifier = "\(record ? "panel.record.card" : "event.card").\(owner.id.uuidString)"
        return VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: noteSpacing) {
                header()
                itemNote(note, controlPrefix: record ? "record.note" : "event.note", id: owner.id)
            }
            if !owner.subtasks.isEmpty {
                SubtaskChecklistView(store: store, owner: owner, editorSession: editorSession, section: $section)
                    .padding(.top, 8)
            }
            savedMaterialSections(material, ownerID: ownerID)
        }
        .modifier(PlannerCardSurface())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(identifier)
        .uiSmokeControl(id: identifier, value: { material.displayTitle })
        .modifier(SavedMaterialTarget(store: store, editorSession: editorSession, ownerID: ownerID,
            enabled: section == ownerID.panelSection && !showingSettings && attachmentListOwnerID == nil,
            targetSurface: "panel.card", showText: { presentTextAttachment(ownerID: ownerID, text: $0) }))
    }

    private func featuredEvent(_ item: Countdown, presentation: CountdownRowPresentation) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(AppText.string("panel.mainEvent"))
                    .accessibilityIdentifier("event.featured.label.\(item.id.uuidString)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                Spacer()
                eventActions(item, presentation: presentation)
            }
            HStack(alignment: .center, spacing: 13) {
                VStack(alignment: .leading, spacing: 7) {
                    Text((eventListEmoji(item.emoji).map { $0 + " " } ?? "") + item.displayTitle)
                        .font(.custom("Georgia", size: 23))
                        .tracking(-0.6)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .uiSmokeControl(id: "event.title.\(item.id.uuidString)", value: { item.displayTitle })
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
                    : presentation.isPast ? AuroraInstrument.secondaryInk(for: colorScheme)
                    : AuroraInstrument.accentInk(
                        for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast
                    ))
                .accessibilityIdentifier(presentation.isToday ? "event.today" : "event.remaining")
                .uiSmokeControl(id: "event.relative.\(item.id.uuidString)", value: { presentation.remainingLabel })
                .padding(.top, 1)
        }
    }

    private func secondaryEvent(_ item: Countdown, presentation: CountdownRowPresentation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 11) {
                calendarTile(item, isFeatured: false)
                    .uiSmokeControl(id: "event.secondary.calendar.\(item.id.uuidString)")
                GeometryReader { geometry in
                    let title = (eventListEmoji(item.emoji).map { $0 + " " } ?? "") + item.displayTitle
                    let textWidth = max(0, geometry.size.width - 87)
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
                                .uiSmokeControl(id: "event.title.\(item.id.uuidString)", value: { item.displayTitle })
                                .uiSmokeControl(id: "event.secondary.title.\(item.id.uuidString)")
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(humanDateLabel(item.date, includesYear: false))
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
        }
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
            .accessibilityLabel(forecast.accessibilityDescription)
            .accessibilityIdentifier("event.weather.\(item.id.uuidString)")
            .uiSmokeControl(id: "event.weather.\(item.id.uuidString)", value: { forecast.temperatureLabel })
            .uiSmokeControl(id: "event.\(role).weather.\(item.id.uuidString)", value: { forecast.temperatureLabel })
        }
    }

    @ViewBuilder
    private func itemNote(_ itemNote: String?, controlPrefix: String, id: UUID) -> some View {
        if let itemNote, !itemNote.isEmpty {
            Text(itemNote)
                .font(.system(size: 12))
                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(controlPrefix)
                .uiSmokeControl(id: "\(controlPrefix).\(id.uuidString)", value: { itemNote })
        }
    }

    @ViewBuilder
    private func savedMaterialSections(_ owner: SavedMaterialOwner, ownerID: SavedMaterialOwnerID) -> some View {
        if !owner.attachments.isEmpty {
            SavedAttachmentSection(owner: owner, compact: true, open: { attachment in
                showAttachmentPreview(attachment, ownerID: ownerID, origin: .summary)
            }, thumbnailURL: { attachment in
                await store.attachmentThumbnailURL(attachment, owner: ownerID)
            }, showAll: { showAttachmentList(ownerID) })
            .padding(.top, 8)
        }
        if !owner.links.isEmpty {
            SavedLinkSection(owner: owner, surface: "panel", open: { store.openSavedLink($0, owner: ownerID) })
                .padding(.top, 8)
        }
    }

    private func eventActions(_ item: Countdown, presentation: CountdownRowPresentation) -> some View {
        HStack(spacing: 0) {
            AuroraSymbolAction(symbolName: presentation.isPrimary ? "star.fill" : "star",
                surface: .mini, tone: presentation.isPrimary ? .accent : .secondary,
                accessibilityLabel: presentation.isPrimary
                    ? AppText.string("panel.removeFavoriteNamed", item.displayTitle) : AppText.string("panel.favoriteNamed", item.displayTitle),
                action: { togglePrimary(item.id) })
            .help(presentation.isPrimary ? AppText.string("panel.removeFavorite") : AppText.string("panel.favorite"))
            .accessibilityIdentifier("event.primary.\(item.id.uuidString)")
            .accessibilityValue(presentation.isPrimary ? AppText.string("common.selected") : AppText.string("common.unselected"))
            .uiSmokeControl(
                id: "event.primary.\(item.id.uuidString)",
                action: { togglePrimary(item.id) },
                value: { presentation.isPrimary ? AppText.string("common.selected") : AppText.string("common.unselected") }
            )
            .disabled(store.isHandlingMaterials)
            AuroraSymbolAction(symbolName: "pencil", surface: .mini, tone: .secondary,
                accessibilityLabel: AppText.string("panel.editNamed", item.displayTitle), action: { edit(item.id) })
            .accessibilityIdentifier("event.edit.\(item.id.uuidString)")
            .uiSmokeControl(id: "event.edit.\(item.id.uuidString)", action: { edit(item.id) })
            AuroraSymbolAction(symbolName: "doc.on.doc", surface: .mini, tone: .secondary,
                accessibilityLabel: AppText.string("panel.copyNamed", item.displayTitle), action: { copyEvent(item.id) })
            .help(AppText.string("event.copy"))
            .accessibilityIdentifier("event.copy.\(item.id.uuidString)")
            .uiSmokeControl(id: "event.copy.\(item.id.uuidString)", action: { copyEvent(item.id) })
        }
        .fixedSize()
    }

    private func togglePrimary(_ id: UUID) {
        Task {
            guard !editorSession.hasActiveEditor, !store.isHandlingMaterials else { return }
            if store.data.primaryID == id {
                await store.clearPrimary()
            } else {
                await store.makePrimary(id)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Label(AppText.string("panel.localStorage"), systemImage: "lock")
                .font(.system(size: 10))
                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
            Spacer()
            Button(action: showDesktop) {
                Image(systemName: "macwindow")
                    .font(.system(size: 14))
                    .frame(width: 22, height: 22)
            }
            .help(AppText.string("app.menu.openMainWindow"))
            .accessibilityLabel(AppText.string("app.menu.openMainWindow"))
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
            .help(AppText.string("settings.title"))
            .accessibilityLabel(AppText.string("settings.title"))
            .accessibilityValue(keepAwake.isEnabled ? AppText.string("panel.keepAwakeOn") : AppText.string("panel.keepAwakeOff"))
            .accessibilityIdentifier("settings.open")
            .uiSmokeControl(id: "settings.open", action: openSettings)
            Button(AppText.string("panel.quit")) { updates.quitApplication(nil) }
        }
        .font(.system(size: 11))
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
        .frame(height: 33)
        .background(AuroraPanelCanvas())
    }

    private func openSettings() {
        guard !editorSession.hasActiveEditor, attachmentListOwnerID == nil, !store.hasPendingPersistence else { return }
        attachmentPreview.close()
        attachmentListOwnerID = nil
        showingSettings = true
    }

    private func showAttachmentList(_ ownerID: SavedMaterialOwnerID) {
        guard section == ownerID.panelSection, !showingEditor, !showingSettings, !editorSession.hasActiveEditor,
              !store.isResolvingMaterials,
              attachmentListOwnerID == nil, let owner = store.savedMaterialOwner(ownerID),
              !owner.attachments.isEmpty else { return }
        attachmentPreview.close()
        attachmentLibraryIsSource = true
        attachmentListOwnerID = ownerID
    }

    private func closeUnavailableAttachmentList() {
        attachmentPreview.reconcile(owner: attachmentListOwner)
        if attachmentListOwnerID != nil, attachmentListOwner == nil {
            attachmentPreview.close()
            attachmentListOwnerID = nil
            attachmentLibraryIsSource = false
        }
    }

    private func attachmentScreen(item: SavedMaterialOwner, ownerID: SavedMaterialOwnerID) -> some View {
        ZStack {
            if attachmentLibraryIsSource {
                AttachmentListView(owner: item, compact: true, back: closeAttachments,
                                   open: { showAttachmentPreview($0, ownerID: ownerID, origin: .library) },
                                   thumbnailURL: { await store.attachmentThumbnailURL($0, owner: ownerID) })
                    .opacity(attachmentPreview.selection == nil ? 1 : 0)
                    .disabled(attachmentPreview.selection != nil)
                    .allowsHitTesting(attachmentPreview.selection == nil)
                    .accessibilityHidden(attachmentPreview.selection != nil)
            }
            if attachmentPreview.selection != nil {
                AttachmentPreviewView(owner: item, compact: true, session: attachmentPreview,
                                      back: closeAttachmentPreview,
                                      resolveURL: { attachment, expectedID in
                                          guard expectedID == item.id else { return nil }
                                          return await store.attachmentThumbnailURL(attachment, owner: ownerID)
                                      }, openExternally: { attachment, expectedID in
                                          guard expectedID == item.id else { return }
                                          await store.openSavedAttachment(attachment, owner: ownerID)
                                      })
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func showAttachmentPreview(_ attachment: EventAttachment, ownerID: SavedMaterialOwnerID,
                                       origin: AttachmentPreviewOrigin) {
        guard section == ownerID.panelSection, !showingEditor, !showingSettings, !editorSession.hasActiveEditor,
              !store.isResolvingMaterials,
              let current = store.savedMaterialOwner(ownerID),
              current.attachments.contains(where: { $0.id == attachment.id }),
              attachmentPreview.selection == nil,
              origin == .library ? attachmentListOwnerID == ownerID : attachmentListOwnerID == nil else { return }
        attachmentLibraryIsSource = origin == .library
        attachmentListOwnerID = ownerID
        attachmentPreview.open(owner: current, attachmentID: attachment.id, origin: origin, resolveURL: { attachment, expectedID in
            guard expectedID == current.id else { return nil }
            return await store.attachmentThumbnailURL(attachment, owner: ownerID)
        })
    }

    private func closeAttachmentPreview() {
        guard attachmentPreview.selection != nil else { return }
        attachmentPreview.close()
        if !attachmentLibraryIsSource { attachmentListOwnerID = nil }
    }

    private func closeAttachments() {
        attachmentPreview.close()
        attachmentListOwnerID = nil
        attachmentLibraryIsSource = false
    }

    private func presentTextAttachment(ownerID: SavedMaterialOwnerID, text: String) {
        guard section == ownerID.panelSection, !showingSettings, attachmentListOwnerID == nil, !store.hasPendingPersistence,
              store.savedMaterialOwner(ownerID) != nil, editorSession.beginPanelEditor() else { return }
        textAttachmentRequest = TextAttachmentRequest(ownerID: ownerID, text: text)
        showingDayChoices = false
    }

    private func finishEditor() {
        textAttachmentRequest = nil
        weekCreation = nil
        recordEditor = nil
        editorSession.endPanelEditor()
        editing = nil
        copying = nil
        dayPreset = nil
        selectDayDate = false
    }

    private func createRecord() {
        openRecordEditor(nil)
    }

    private func openRecordEditor(_ recordID: UUID?) {
        guard section == .records, canEditRecord, !showingSettings, attachmentListOwnerID == nil else { return }
        let record: UndatedRecord?
        if let recordID {
            guard let current = store.records.first(where: { $0.id == recordID }) else { return }
            record = current
        } else {
            record = nil
        }
        guard editorSession.beginPanelEditor() else { return }
        recordEditor = RecordEditorRequest(record: record)
    }

    private func add() {
        createEvent()
    }

    private func createEvent() {
        guard !showingSettings, attachmentListOwnerID == nil,
              !store.hasPendingPersistence, store.eventCreationIsAvailable,
              editorSession.beginPanelEditor() else { return }
        DiagnosticLog.shared.record("editor.open mode=new")
        editing = nil
        copying = nil
        dayPreset = nil
        selectDayDate = false
        showingDayChoices = false
    }

    private func toggleDayChoices() {
        guard !editorSession.hasActiveEditor, !showingSettings, attachmentListOwnerID == nil,
              store.eventCreationIsAvailable else { return }
        showingDayChoices.toggle()
    }

    private func createDay(preset: DayCreationPreset?, selectDate: Bool = false) {
        guard !showingSettings, attachmentListOwnerID == nil,
              !store.hasPendingPersistence, store.eventCreationIsAvailable, let preset,
              editorSession.beginPanelEditor() else { return }
        DiagnosticLog.shared.record("editor.open mode=day")
        editing = nil
        copying = nil
        dayPreset = preset
        selectDayDate = selectDate
        showingDayChoices = false
    }

    private func createWeekDays() {
        guard !showingSettings, attachmentListOwnerID == nil,
              !store.hasPendingPersistence, store.eventCreationIsAvailable,
              let week = DayCreationWeek(today: store.today), editorSession.beginPanelEditor() else { return }
        editing = nil
        copying = nil
        dayPreset = nil
        selectDayDate = false
        weekCreation = week
        showingDayChoices = false
    }

    private func copyEvent(_ id: UUID) {
        guard !showingSettings, attachmentListOwnerID == nil, !store.hasPendingPersistence,
              store.eventCreationIsAvailable,
              let item = store.active.first(where: { $0.id == id }),
              editorSession.beginPanelEditor() else { return }
        DiagnosticLog.shared.record("editor.open mode=copy id=\(item.id.uuidString)")
        editing = nil
        copying = item
        dayPreset = nil
        selectDayDate = false
        showingDayChoices = false
    }

    private func edit(_ id: UUID) {
        guard !showingSettings, attachmentListOwnerID == nil, !store.hasPendingPersistence,
              let item = store.active.first(where: { $0.id == id }),
              editorSession.beginPanelEditor() else { return }
        DiagnosticLog.shared.record("editor.open mode=edit id=\(item.id.uuidString)")
        editing = item
        copying = nil
        dayPreset = nil
        selectDayDate = false
        showingDayChoices = false
    }
}

private extension SavedMaterialOwnerID {
    var panelSection: PlannerSection {
        switch self {
        case .event: .events
        case .record: .records
        }
    }
}

private struct PlannerCardSurface: ViewModifier {
    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        let highContrast = accessibilitySettings.prefersHighContrast
        let shape = RoundedRectangle(cornerRadius: AuroraInstrument.cardCornerRadius)
        content
            .padding(12)
            .background(AuroraInstrument.surface(for: colorScheme, elevated: false, highContrast: highContrast), in: shape)
            .overlay {
                if highContrast {
                    shape.stroke(AuroraInstrument.stroke(for: colorScheme, highContrast: true), lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
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
    enum Owner {
        case event(Countdown)
        case record(UndatedRecord)

        var id: UUID { materialID.id }

        var subtasks: [Subtask] {
            switch self {
            case let .event(item): return item.subtasks
            case let .record(item): return item.subtasks
            }
        }

        var materialID: SavedMaterialOwnerID {
            switch self {
            case let .event(item): .event(item.id)
            case let .record(item): .record(item.id)
            }
        }

        var materials: SavedMaterialOwner {
            switch self {
            case let .event(item): SavedMaterialOwner(item)
            case let .record(item): SavedMaterialOwner(item)
            }
        }
    }

    @ObservedObject var store: Store
    let owner: Owner
    @ObservedObject var editorSession: EventEditorSession
    private let section: Binding<PlannerSection>

    @ObservedObject private var disclosureState: SubtaskDisclosureState
    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @Environment(\.colorScheme) private var colorScheme

    init(
        store: Store,
        owner: Owner,
        editorSession: EventEditorSession,
        section: Binding<PlannerSection>
    ) {
        self.store = store
        self.owner = owner
        self.editorSession = editorSession
        self.section = section
        _disclosureState = ObservedObject(wrappedValue: store.disclosureState(for: owner.materialID))
    }

    var body: some View {
        let isExpanded = disclosureState.isExpanded
        let completedCount = owner.subtasks.filter(\.isCompleted).count
        let allCompleted = completedCount > 0 && completedCount == owner.subtasks.count
        let completionLabel = "\(completedCount)/\(owner.subtasks.count)"

        VStack(alignment: .leading, spacing: 5) {
            Button(action: toggleDisclosure) {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .accessibilityHidden(true)
                    Text(AppText.string("subtask.heading"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AuroraInstrument.ink(for: colorScheme))
                        .uiSmokeControl(id: "panel.subtasks.heading.\(owner.id.uuidString)")
                    Spacer()
                    HStack(spacing: 4) {
                        if allCompleted {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .semibold))
                                .accessibilityHidden(true)
                                .uiSmokeControl(id: "subtasks.complete.\(owner.id.uuidString)")
                        }
                        Text(completionLabel.replacingOccurrences(of: "/", with: AppText.string("subtask.progressSeparator")))
                            .monospacedDigit()
                    }
                    .foregroundStyle(allCompleted
                        ? AuroraInstrument.todayColor(for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast)
                        : AuroraInstrument.secondaryInk(for: colorScheme))
                    .uiSmokeControl(id: "subtasks.progress.\(owner.id.uuidString)", value: { completionLabel })
                }
                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                .font(.system(size: 11))
                .frame(minHeight: 22)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppText.string("subtask.disclosure", completionLabel, "\(allCompleted ? AppText.string("subtask.completionSuffix") : "")", "\(isExpanded ? AppText.string("common.collapse") : AppText.string("common.expand"))"))
            .accessibilityIdentifier("subtasks.disclosure.\(owner.id.uuidString)")
            .uiSmokeControl(
                id: "subtasks.disclosure.\(owner.id.uuidString)",
                action: toggleDisclosure,
                value: { disclosureState.isExpanded ? "expanded" : "collapsed" }
            )

            SubtaskReorderRows(subtasks: owner.subtasks, spacing: 0,
                               isEnabled: isExpanded && canMutateChecklist, save: saveSubtaskOrder, row: subtaskRow)
            .fixedSize(horizontal: false, vertical: true)
            // Disclosure clips the list's height while leaving room for the drag highlight on either side.
            .padding(.horizontal, subtaskLiftOutset)
            .frame(height: isExpanded ? nil : 0, alignment: .top)
            .opacity(isExpanded ? 1 : 0)
            .clipped()
            .padding(.horizontal, -subtaskLiftOutset)
            .disabled(!isExpanded)
            .allowsHitTesting(isExpanded)
            .accessibilityHidden(!isExpanded)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("subtasks.list")
        }
        .animation(disclosureAnimation, value: isExpanded)
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

    private var isActive: Bool { section.wrappedValue == owner.materialID.panelSection }

    private var canMutateChecklist: Bool {
        guard isActive, !editorSession.hasActiveEditor, !store.hasPendingPersistence else { return false }
        switch owner {
        case .event: return store.eventCreationIsAvailable
        case .record: return store.recordCreationIsAvailable
        }
    }

    private var canToggleSubtask: Bool {
        guard isActive, !editorSession.hasActiveEditor, !store.isHandlingMaterials else { return false }
        if case .record = owner { return store.canEnqueuePanelRecordSubtaskToggle }
        return true
    }

    private func saveSubtaskOrder(_ move: SubtaskReorder, _ index: Int) async -> Bool {
        guard disclosureState.isExpanded, canMutateChecklist else { return false }
        return await store.reorderSubtask(owner: owner.materialID, move: move, to: index)
    }

    private func subtaskRow(_ subtask: Subtask, _ interaction: SubtaskReorderInteraction?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
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
                .modifier(interaction ?? .disabled)
                .disabled(!canToggleSubtask)
                .tint(subtask.isCompleted
                    ? AuroraInstrument.completedCheck(for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast)
                    : AuroraInstrument.accent(for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast))
                .accessibilityLabel("\(subtask.isCompleted ? AppText.string("subtask.markIncomplete") : AppText.string("subtask.markComplete")): \(subtask.text)")
                .accessibilityIdentifier("subtask.toggle.\(subtask.id.uuidString)")
                .uiSmokeControl(
                    id: "subtask.toggle.\(subtask.id.uuidString)",
                    action: { toggleSubtask(subtask.id) },
                    value: {
                        let isCompleted = currentSubtasks.first { $0.id == subtask.id }?.isCompleted
                        return isCompleted == true ? "completed" : "active"
                    }
                )

                if case .event = owner {
                    SubtaskTransferButton(store: store, editorSession: editorSession, eventID: owner.id,
                                          subtask: subtask, surface: .panel)
                }
            }
            if case .event = owner {
                SubtaskTransferForm(store: store, editorSession: editorSession, eventID: owner.id,
                                    subtaskID: subtask.id, surface: .panel)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(subtask.isCompleted ? "subtask.completed" : "subtask.active")
    }

    private var currentSubtasks: [Subtask] {
        switch owner {
        case .event: return store.active.first { $0.id == owner.id }?.subtasks ?? []
        case .record: return store.records.first { $0.id == owner.id }?.subtasks ?? []
        }
    }

    private func toggleDisclosure() {
        guard isActive else { return }
        disclosureState.setExpanded(!disclosureState.isExpanded)
    }

    private func toggleSubtask(_ id: UUID) {
        guard disclosureState.isExpanded, canToggleSubtask else { return }
        switch owner {
        case .record:
            store.enqueuePanelRecordSubtaskToggle(recordID: owner.id, subtaskID: id)
        case .event:
            Task {
                guard canToggleSubtask else { return }
                _ = await store.toggleSubtask(eventID: owner.id, subtaskID: id)
            }
        }
    }

}

struct EditorView: View {
    @ObservedObject var store: Store
    private enum Mode {
        case event(didSave: (Countdown) -> Void)
        case record(item: UndatedRecord?, didSave: (UndatedRecord) -> Void)
    }

    let item: Countdown?
    private let copySource: Countdown?
    private let mode: Mode
    let done: () -> Void
    private let isNewDay: Bool
    private let selectDayDate: Bool
    @State private var composingText: String?
    @State private var draft: EventEditorDraft
    @State private var date: Date?
    @State private var primary: Bool
    @State private var isSaving = false
    @State private var isImportingAttachments = false
    @StateObject private var attachmentSession: EditorAttachmentSession
    @State private var confirmingDeletion = false
    @State private var removingPastRetention = false
    @State private var emojiPicker: EditorEmojiPickerState = .closed
    @State private var noteFocusRequest = 0
    @FocusState private var focusedField: EditorFocusTarget?
    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @EnvironmentObject private var appPreferences: ApplicationPreferences
    @Environment(\.colorScheme) private var colorScheme

    private static var emojiPageTitles: [String] { [
        AppText.string("icon.page.general"), AppText.string("icon.page.children"), AppText.string("icon.page.work"),
        AppText.string("icon.page.transport"), AppText.string("icon.page.celebrations")
    ] }
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
        copying source: Countdown? = nil,
        dayPreset: DayCreationPreset? = nil,
        selectDayDate: Bool = false,
        didSave: @escaping (Countdown) -> Void,
        done: @escaping () -> Void
    ) {
        self.store = store; self.item = item; self.done = done
        copySource = source
        mode = .event(didSave: didSave)
        _attachmentSession = StateObject(wrappedValue: EditorAttachmentSession())
        isNewDay = item == nil && source == nil && dayPreset != nil
        self.selectDayDate = source != nil || (item == nil && selectDayDate)
        if let source {
            _draft = State(initialValue: EventEditorDraft(copying: source, date: max(source.date, store.today)))
        } else if item == nil, let dayPreset {
            _draft = State(initialValue: EventEditorDraft(day: dayPreset.day))
        } else {
            _draft = State(initialValue: EventEditorDraft(item: item))
        }
        _date = State(initialValue: source.map { max($0.date, store.today).date() }
            ?? item?.date.date() ?? dayPreset?.day.date() ?? store.tomorrow)
        _primary = State(initialValue: source == nil && (item.map { store.data.primaryID == $0.id } ?? false))
    }

    init(store: Store, record: UndatedRecord?, didSave: @escaping (UndatedRecord) -> Void, done: @escaping () -> Void) {
        self.store = store
        self.done = done
        item = nil
        copySource = nil
        isNewDay = false
        selectDayDate = false
        mode = .record(item: record, didSave: didSave)
        _draft = State(initialValue: EventEditorDraft(record: record))
        _date = State(initialValue: nil)
        _primary = State(initialValue: false)
        _attachmentSession = StateObject(wrappedValue: EditorAttachmentSession(section: .records))
    }

    private var isRecord: Bool {
        if case .record = mode { return true }
        return false
    }

    private var originalRecord: UndatedRecord? {
        if case let .record(record, _) = mode { return record }
        return nil
    }

    private var heading: String {
        if isRecord {
            return originalRecord == nil ? AppText.string("record.editor.new") : AppText.string("record.editor.edit")
        }
        if copySource != nil { return AppText.string("editor.copyTitle") }
        if item != nil { return EventUIStrings.editEvent }
        return isNewDay ? EventUIStrings.newDay : EventUIStrings.newEvent
    }

    private var editorID: String {
        if isRecord { return originalRecord == nil ? "record.editor.new" : "record.editor.edit" }
        return copySource != nil ? "editor.copy" : item == nil ? "editor.new" : "editor.edit"
    }

    private var deletionID: String { isRecord ? "record.delete" : "event.delete" }

    private var emojiPage: Int { emojiPicker.pageIndex }
    private var emojiPickerAnimation: Animation? {
        switch editorEmojiPickerMotion(reduceMotion: accessibilitySettings.prefersReducedMotion) {
        case .immediate:
            nil
        case let .heightAndOpacity(duration):
            .easeInOut(duration: duration)
        }
    }

    private var savedEvent: Countdown? {
        item.flatMap { original in store.active.first { $0.id == original.id } }
    }
    private var retainedDate: Day? {
        savedEvent.flatMap { $0.keepsAfterDate ? $0.date : nil }
    }
    private var minimumDate: Date { min(retainedDate ?? store.today, store.today).date() }
    private var selectedDay: Day { date.map { Day($0) } ?? store.today }
    private var validDate: Bool { selectedDay >= store.today || selectedDay == retainedDate }
    private var isUnavailable: Bool {
        if let originalRecord { return !store.records.contains { $0.id == originalRecord.id } }
        guard let original = copySource ?? item else { return false }
        return !store.active.contains(where: { $0.id == original.id })
    }
    private var canSave: Bool {
        guard !isUnavailable else { return false }
        if isRecord {
            return editorContentCanSave(title: draft.title, note: draft.note, subtasks: draft.subtasks, links: draft.links)
        }
        return editorCanSave(
            title: draft.title,
            note: draft.note,
            date: selectedDay,
            emoji: draft.emoji,
            subtasks: draft.subtasks,
            links: draft.links,
            today: store.today,
            savedNote: savedNote,
            savedDate: retainedDate
        )
    }

    private var savedNote: String? {
        (copySource ?? item).flatMap { original in store.active.first(where: { $0.id == original.id })?.note }
    }

    var body: some View {
        ZStack {
            editorContent
                .opacity(composingText == nil ? 1 : 0)
                .disabled(composingText != nil)
                .allowsHitTesting(composingText == nil)
                .accessibilityHidden(composingText != nil)
            if let text = composingText {
                TextAttachmentComposer(text: text, eventTitle: draft.title, submit: { text in
                    await addTextToDraft(text)
                }, cancel: { composingText = nil })
            }
        }
    }

    private var editorContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(heading)
                .font(.custom("Georgia", size: 21))
                .tracking(-0.5)
                .frame(maxWidth: .infinity, minHeight: 49, alignment: .leading)
                .padding(.horizontal, 16)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if selectDayDate {
                            Text(copySource != nil ? AppText.string("editor.copyDatePrompt")
                                 : isNewDay ? AppText.string("editor.newDayDatePrompt") : AppText.string("editor.eventDatePrompt"))
                                .font(.caption)
                                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                        }
                        titleField
                        noteControls
                        if !isRecord {
                            dateControls
                            VStack(alignment: .leading, spacing: 0) {
                                Divider().padding(.bottom, 10)
                                emojiControls
                                eventOptions.padding(.top, 13)
                            }
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            Divider().padding(.bottom, 13)
                            editorSubtasks(scrollProxy: proxy)
                        }
                        .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 0) {
                            Divider().padding(.bottom, 13)
                            EditorAttachmentSection(attachments: $draft.attachments,
                                                    keepsAfterDate: draft.keepsAfterDate,
                                                    isImporting: isImportingAttachments, add: addAttachments,
                                                    thumbnailURL: editorAttachmentURL,
                                                    showsExpiryNotice: !isRecord)
                            Button(AppText.string("material.pasteText")) { beginTextComposition() }
                                .buttonStyle(.borderless)
                                .padding(.top, 10)
                                .disabled(draft.attachments.count >= EventAttachment.maximumCount)
                                .accessibilityIdentifier("editor.materials.paste")
                                .uiSmokeControl(id: "editor.materials.paste", action: beginTextComposition)
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
        .accessibilityIdentifier(editorID)
        .uiSmokeControl(id: editorID)
        .task {
            await Task.yield()
            let initialFocus: EditorFocusTarget = copySource == nil ? .title : .date
            focusedField = initialFocus
            await Task.yield()
            if UISmokeConfiguration.wasRequested && focusedField == initialFocus {
                UISmokeControlRegistry.shared.markFocused(copySource == nil ? "editor.title" : "editor.date")
            }
        }
        .modifier(MaterialDropZone(enabled: !isSaving && !isImportingAttachments && !isUnavailable
                                    && !confirmingDeletion && composingText == nil,
                                  beginReceiving: {
                                      guard !isSaving, !isImportingAttachments, !isUnavailable else { return false }
                                      isImportingAttachments = true
                                      return true
                                  }, finishReceiving: { isImportingAttachments = false },
                                  receive: receiveMaterials, reportError: { store.error = $0 }))
        .environment(\.locale, appPreferences.language.locale)
        .environment(\.calendar, Day.calendar)
        .onChange(of: appPreferences.language) { _ in
            if let date { draft.updateDayTitle(for: Day(date)) }
        }
        .onChange(of: date) { newDate in
            if let newDate { draft.updateDayTitle(for: Day(newDate)) }
        }
    }

    private func editorAttachmentURL(_ attachment: EventAttachment) async -> URL? {
        if isRecord {
            return await store.editorAttachmentThumbnailURL(attachment, recordID: originalRecord?.id,
                                                             draftID: attachmentSession.id)
        }
        return await store.editorAttachmentThumbnailURL(attachment, eventID: copySource?.id ?? item?.id,
                                                         draftID: attachmentSession.id)
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 6) {
            if isRecord {
                Text(AppText.string("editor.name"))
                    .font(.system(size: 11))
                    .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
            } else {
                eventTitleMode
            }
            TextField(isRecord ? AppText.string("record.editor.titlePrompt") : AppText.string("editor.namePrompt"),
                      text: Binding(get: { draft.title }, set: { draft.setTitle($0) }))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14))
                .frame(minHeight: 28)
                .focused($focusedField, equals: .title)
                .accessibilityLabel(AppText.string("editor.name"))
                .accessibilityIdentifier("editor.title")
                .uiSmokeControl(id: "editor.title", action: { focus(.title, id: "editor.title") }, value: { draft.title })
        }
    }

    private var eventTitleMode: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(AppText.string("editor.name"))
                .font(.system(size: 11))
                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                .accessibilityIdentifier("editor.title.mode")
                .accessibilityValue(draft.usesAutomaticTitle ? AppText.string("editor.autoTitle") : AppText.string("editor.customTitle"))
                .uiSmokeControl(id: "editor.title.mode", value: { draft.usesAutomaticTitle ? "auto" : "custom" })
            Spacer(minLength: 8)
            if draft.usesAutomaticTitle {
                Text(AppText.string("editor.byDate"))
                    .font(.system(size: 11))
                    .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
            } else {
                Button(AppText.string("editor.autoTitle"), action: useAutomaticTitle)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .font(.system(size: 11))
                    .accessibilityIdentifier("editor.title.automatic")
                    .uiSmokeControl(id: "editor.title.automatic", action: useAutomaticTitle)
            }
        }
    }

    private func useAutomaticTitle() {
        draft.useAutomaticTitle(for: selectedDay)
    }

    private var noteControls: some View {
        let label = isRecord ? AppText.string("record.editor.noteLabel") : AppText.string("note.optional")
        let placeholder = isRecord ? AppText.string("record.editor.notePrompt") : AppText.string("note.prompt")
        return VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
            NoteEditor(text: $draft.note, focusRequest: noteFocusRequest,
                       placeholder: placeholder, label: label)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("editor.note")
                .uiSmokeControl(id: "editor.note", action: { focus(.note, id: "editor.note") }, value: { draft.note })
            HStack(alignment: .top) {
                if (savedNote?.count ?? 0) > CountdownNote.maximumLength {
                    Text(AppText.string("editor.legacyNote"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Text("\(draft.note.count)/150")
                    .font(.caption2)
                    .foregroundStyle(draft.note.count <= CountdownNote.allowedLength(savedNote: savedNote)
                        ? AuroraInstrument.secondaryInk(for: colorScheme) : .red)
                    .accessibilityIdentifier("editor.note.count")
                    .uiSmokeControl(id: "editor.note.count", value: { "\(draft.note.count)/150" })
            }
        }
    }

    private var dateControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let copySource, copySource.date < store.today {
                Text(AppText.string("editor.copyPastDate"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                    .accessibilityIdentifier("editor.copy.past-source")
                    .uiSmokeControl(id: "editor.copy.past-source")
            }
            DatePicker(AppText.string("editor.date"), selection: Binding(get: { date ?? store.tomorrow }, set: { date = $0 }),
                       in: minimumDate..., displayedComponents: [.date])
                .datePickerStyle(.field)
                .font(.system(size: 12))
                .frame(minHeight: 28)
                .focused($focusedField, equals: .date)
                .accessibilityIdentifier("editor.date")
                .uiSmokeControl(id: "editor.date", action: { focus(.date, id: "editor.date") }, value: { "\(selectedDay.year)-\(selectedDay.month)-\(selectedDay.day)" })
            if (selectedDay == store.today && !draft.keepsAfterDate) || !validDate {
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
            Toggle(AppText.string("editor.eventWeather"), isOn: $draft.showsWeather)
                .accessibilityIdentifier("editor.weather")
                .uiSmokeControl(id: "editor.weather", action: { draft.showsWeather.toggle() },
                                value: { draft.showsWeather ? "on" : "off" })
            Toggle(AppText.string("editor.primaryInMenu"), isOn: $primary)
                .accessibilityIdentifier("editor.primary")
                .uiSmokeControl(id: "editor.primary", action: { primary.toggle() },
                                value: { primary ? AppText.string("common.selected") : AppText.string("common.unselected") })
            VStack(alignment: .leading, spacing: 5) {
                Toggle(AppText.string("editor.retainAfterDate"), isOn: $draft.keepsAfterDate)
                    .accessibilityIdentifier("editor.keep")
                    .uiSmokeControl(id: "editor.keep", action: { draft.keepsAfterDate.toggle() },
                                    value: { draft.keepsAfterDate ? "on" : "off" })
                Text(draft.keepsAfterDate
                     ? AppText.string("editor.retainedNotice")
                     : AppText.string("editor.expiryNotice"))
                    .font(.system(size: 10.5))
                    .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 18)
            }
        }
        .toggleStyle(.checkbox)
        .font(.system(size: 12))
        .padding(.bottom, 4)
    }

    private var editorActions: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isUnavailable {
                Text(unavailableMessage)
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
                if (item != nil || originalRecord != nil) && !isUnavailable {
                    Button(role: .destructive, action: requestDeletion) {
                        Label(AppText.string("editor.delete"), systemImage: "trash")
                            .font(.system(size: 11))
                            .frame(minHeight: 28)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                    .accessibilityIdentifier(deletionID)
                    .uiSmokeControl(id: deletionID, action: requestDeletion)
                    .disabled(isSaving || isImportingAttachments || confirmingDeletion)
                }
                Spacer(minLength: 0)
                Button(AppText.string("common.cancel"), action: cancel)
                    .auroraSecondaryAction()
                    .keyboardShortcut(confirmingDeletion && !isUnavailable ? nil : .cancelAction)
                    .accessibilityIdentifier("editor.cancel")
                    .uiSmokeControl(id: "editor.cancel", action: cancel)
                    .disabled(isSaving)
                Button(action: save) {
                    if isSaving { ProgressView().controlSize(.small) }
                    else { Text(AppText.string("editor.save")) }
                }
                .auroraPrimaryAction()
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

    private var unavailableMessage: String {
        if isRecord { return AppText.string("record.unavailable") }
        return copySource != nil ? AppText.string("editor.copySourceUnavailable") : AppText.string("editor.unavailable")
    }

    private var deleteWarning: String {
        if isRecord { return AppText.string("record.deleteWarning") }
        return removingPastRetention ? AppText.string("editor.clearRetentionWarning") : AppText.string("editor.deleteWarning")
    }

    private var deletionControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(deleteWarning)
                .font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("\(deletionID).explanation")
                .uiSmokeControl(id: "\(deletionID).explanation", value: { removingPastRetention ? "past-retention" : "manual" })
            HStack(spacing: 16) {
                Button(isRecord ? AppText.string("record.cancelDeletion") : AppText.string("editor.cancelDeletion"),
                       action: cancelDeletion)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("\(deletionID).cancel")
                    .uiSmokeControl(id: "\(deletionID).cancel", action: cancelDeletion)
                Button(isRecord ? AppText.string("record.delete") : AppText.string("event.delete"),
                       role: .destructive, action: delete)
                    .accessibilityIdentifier("\(deletionID).confirm")
                    .uiSmokeControl(id: "\(deletionID).confirm", action: delete)
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
        guard !isUnavailable, !isSaving, !isImportingAttachments, let id = originalRecord?.id ?? item?.id else { return }
        isSaving = true
        Task {
            let deleted = if isRecord { await store.deleteRecord(id) } else { await store.delete(id) }
            if deleted {
                await attachmentSession.discard(in: store)
                done()
            }
            isSaving = false
        }
    }

    private func requestDeletion() {
        removingPastRetention = false
        confirmingDeletion = true
    }

    private func cancelDeletion() {
        if removingPastRetention { draft.keepsAfterDate = true }
        removingPastRetention = false
        confirmingDeletion = false
    }

    private var dateHelp: String {
        guard validDate else { return AppText.string("editor.pastDateWarning") }
        if draft.keepsAfterDate { return AppText.string("editor.retainedNotice") }
        return selectedDay == store.today ? EventUIStrings.todayExpiryNotice : AppText.string("editor.allowedDate")
    }

    private func editorSubtasks(scrollProxy: ScrollViewProxy) -> some View {
        let displayedSubtasks = checklistDisplayOrder(draft.subtasks)
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(AppText.string("subtask.heading")).font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AuroraInstrument.ink(for: colorScheme))
                    .uiSmokeControl(id: "editor.subtasks.heading")
                Spacer()
                Text("\(draft.subtasks.count)/\(Subtask.maximumCount)").font(.caption2).foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
            }
            ForEach(displayedSubtasks) { subtask in
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
                        Label(AppText.string("subtask.add"), systemImage: "plus")
                            .font(.system(size: 12))
                            .frame(minHeight: 26)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AuroraInstrument.accentInk(
                        for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast
                    ))
                    .accessibilityLabel(AppText.string("subtask.add"))
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
        .animation(editorSubtaskAnimation, value: displayedSubtasks.map(\.id))
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
                    Text(AppText.string("icon.label"))
                        .font(.system(size: 12))
                    Spacer(minLength: 8)
                    Text(draft.emoji.isEmpty ? AppText.string("icon.none") : draft.emoji)
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
                ? AppText.string("icon.hidePicker", "\(draft.emoji.isEmpty ? AppText.string("icon.noneInDescription") : AppText.string("icon.currentPrefix") + draft.emoji)")
                : (draft.emoji.isEmpty ? AppText.string("icon.choose") : AppText.string("icon.edit", draft.emoji)))
            .accessibilityValue(emojiPicker.isOpen ? AppText.string("icon.expanded") : AppText.string("icon.collapsed"))
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
                .accessibilityLabel(AppText.string("icon.remove"))
                .help(AppText.string("icon.remove"))
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
                                Text(AppText.string("icon.all"))
                                Image(systemName: "chevron.right").font(.system(size: 10))
                                Spacer()
                            }
                            .font(.system(size: 12))
                            .frame(minHeight: 28)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                        .accessibilityLabel(AppText.string("icon.all"))
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
            .help(AppText.string("icon.previousPage"))
            .accessibilityLabel(AppText.string("icon.previousPage"))
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
                            ? AppText.string("icon.currentPage", Self.emojiPageTitles[page], "\(page + 1)", "\(Self.emojiPageCount)")
                            : AppText.string("icon.openPage", Self.emojiPageTitles[page], "\(page + 1)", "\(Self.emojiPageCount)")
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
            .help(AppText.string("icon.nextPage"))
            .accessibilityLabel(AppText.string("icon.nextPage"))
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
        .accessibilityLabel(AppText.string("icon.emojiAccessibility", symbol))
        .accessibilityValue(draft.emoji == symbol ? AppText.string("common.selected") : AppText.string("common.unselected"))
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
        guard !isSaving, composingText == nil else { return }
        let logMode = isRecord ? (originalRecord == nil ? "record-new" : "record-edit")
            : (copySource != nil ? "copy" : item == nil ? "new" : "edit")
        DiagnosticLog.shared.record("editor.cancel mode=\(logMode)")
        attachmentSession.cancel()
        done()
    }

    private func beginTextComposition() {
        guard !isSaving, !isImportingAttachments, !isUnavailable, composingText == nil,
              draft.attachments.count < EventAttachment.maximumCount else { return }
        composingText = NSPasteboard.general.string(forType: .string) ?? ""
    }

    private func addTextToDraft(_ text: TextAttachment) async -> Bool {
        guard !isSaving, !isImportingAttachments, !isUnavailable,
              draft.attachments.count < EventAttachment.maximumCount else { return false }
        isImportingAttachments = true
        defer { isImportingAttachments = false }
        guard await attachmentSession.prepare(in: store),
              let attachment = await store.createTextAttachment(text, draftID: attachmentSession.id),
              !isUnavailable else { return false }
        draft.attachments.append(attachment)
        composingText = nil
        return true
    }

    private func receiveMaterials(_ materials: EventMaterials) {
        guard !isSaving, !isImportingAttachments, !isUnavailable, !confirmingDeletion, composingText == nil else { return }
        if let text = materials.text { composingText = text; return }
        do { try materials.validateCapacity(attachments: draft.attachments, existingLinks: draft.links) }
        catch { store.error = error.localizedDescription; return }
        if materials.files.isEmpty { draft.links += materials.links; return }
        isImportingAttachments = true
        attachmentSession.importFiles(in: store, currentAttachments: draft.attachments, sources: materials.files,
                                      retaining: materials.stagedFiles) { imported in
            draft.attachments += imported
            if imported.count == materials.files.count { draft.links += materials.links }
            isImportingAttachments = false
        }
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
        guard canSave, !isSaving, !isImportingAttachments, !confirmingDeletion, composingText == nil else { return }
        if case let .record(record, didSave) = mode {
            saveRecord(original: record, didSave: didSave)
            return
        }
        guard case let .event(didSave) = mode else { return }
        store.refresh()
        guard canSave else { return }
        if selectedDay < store.today, !draft.keepsAfterDate {
            removingPastRetention = true
            confirmingDeletion = true
            return
        }
        let countdown = draft.countdown(id: item?.id ?? UUID(), date: selectedDay)
        isSaving = true
        Task {
            let saved: Countdown?
            if let copySource {
                if await attachmentSession.prepare(in: store) {
                    saved = await store.saveCopy(countdown, sourceID: copySource.id,
                                                 draftID: attachmentSession.id, primary: primary)
                } else {
                    saved = nil
                }
            } else {
                saved = await store.save(countdown, primary: primary, requireExisting: item != nil) ? countdown : nil
            }
            if let saved {
                await attachmentSession.discard(in: store)
                didSave(saved)
                done()
            }
            isSaving = false
        }
    }

    private func saveRecord(original: UndatedRecord?, didSave: @escaping (UndatedRecord) -> Void) {
        let record = UndatedRecord(id: original?.id ?? UUID(), title: draft.title, note: draft.note,
                                  subtasks: draft.subtasks, attachments: draft.attachments, links: draft.links)
        isSaving = true
        Task {
            if await store.saveRecord(record, requireExisting: original != nil) {
                await attachmentSession.discard(in: store)
                didSave(store.records.first { $0.id == record.id } ?? record)
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
                    .accessibilityLabel(AppText.string("subtask.completed"))
            }
            TextField(AppText.string("subtask.title"), text: text)
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
            .help(AppText.string("subtask.delete"))
            .accessibilityLabel(AppText.string("subtask.delete"))
            .accessibilityIdentifier("editor.subtask.delete.\(subtask.id.uuidString)")
            .uiSmokeControl(id: "editor.subtask.delete.\(subtask.id.uuidString)", action: { deleteRow(subtask.id) })
        }
        .disabled(!isAvailable)
        .allowsHitTesting(isAvailable)
        .accessibilityHidden(!isAvailable)
    }
}
