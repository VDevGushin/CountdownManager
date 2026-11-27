import AppKit
import CountdownCore
import SwiftUI

struct DesktopRootView: View {
    private enum DesktopSheet: Equatable {
        case editor
        case recordEditor
        case week
        case textAttachment
        case settings
        case attachments(SavedMaterialOwnerID)
    }

    private enum PendingAction {
        case toggleSubtask(ownerID: SavedMaterialOwnerID, subtaskID: UUID)
        case toggleFavorite(eventID: UUID)
        case delete(eventID: UUID)
        case deleteRecord(recordID: UUID)
        case editRecord(recordID: UUID?)
        case edit(itemID: UUID?, preset: DayCreationPreset?, selectDate: Bool)
        case copy(sourceID: UUID)
        case week(DayCreationWeek)

        var section: PlannerSection {
            switch self {
            case let .toggleSubtask(ownerID, _): ownerID.plannerSection
            case .deleteRecord, .editRecord: .records
            default: .events
            }
        }
    }

    @ObservedObject var store: Store
    @ObservedObject var updates: ApplicationUpdates
    @ObservedObject var editorSession: EventEditorSession
    @ObservedObject var keepAwake: KeepAwakeController
    @ObservedObject var weather: WeatherController
    @ObservedObject var accessibilitySettings: AuroraAccessibilitySettings
    @ObservedObject var visualEnvironment: UISmokeVisualEnvironment
    @ObservedObject var appPreferences: ApplicationPreferences
    let showPanel: () -> Void
    let switchToPanel: () -> Void
    let diagnosticsContext: () -> DiagnosticExportContext
    var showWhatsNew: () -> Void = {}
    var smokeControlScope = ""
    var registerPasteAction: (((() -> Void)?) -> Void)?
    @State private var mode = DesktopEventViewMode.collection
    @State private var section = PlannerSection.events
    @State private var eventQuery = ""
    @State private var recordQuery = ""
    @State private var selectedEventID: UUID?
    @State private var selectedRecordID: UUID?
    @StateObject private var attachmentPreview = AttachmentPreviewSession()
    @State private var attachmentLibraryIsSource = false
    @State private var attachmentPreviewWasPresented = false
    // Retain ownership through native dismissal so background actions cannot enter while the sheet is closing.
    @State private var presentedSheet: DesktopSheet?
    @State private var sheetIsClosing = false
    @State private var showWhatsNewAfterSettings = false
    @State private var textAttachmentRequest: TextAttachmentRequest?
    @State private var editing: Countdown?
    @State private var editingRecord: UndatedRecord?
    @State private var copying: Countdown?
    @State private var dayPreset: DayCreationPreset?
    @State private var weekCreation: DayCreationWeek?
    @State private var selectDayDate = false
    @State private var pendingActions: [PendingAction] = []
    @State private var isProcessingActions = false
    @State private var deletingItem: (section: PlannerSection, id: UUID)?
    @FocusState private var searchFocused: Bool
    @Environment(\.colorScheme) private var systemColorScheme

    private var colorScheme: ColorScheme {
        appPreferences.colorScheme(overriding: visualEnvironment.colorSchemeOverride) ?? systemColorScheme
    }
    private var collection: DesktopEventCollection {
        DesktopEventCollection(items: store.data.items, today: store.today, primaryID: store.data.primaryID,
                               query: eventQuery)
    }
    private var recordCollection: [UndatedRecord] {
        DesktopEventSearch(recordQuery).matchingRecords(in: store.records)
    }
    private var query: Binding<String> { section == .events ? $eventQuery : $recordQuery }
    private var search: DesktopEventSearch { DesktopEventSearch(query.wrappedValue) }
    private var selectedID: UUID? {
        get { section == .events ? selectedEventID : selectedRecordID }
        nonmutating set {
            if section == .events { selectedEventID = newValue }
            else { selectedRecordID = newValue }
        }
    }
    private func creationIsAvailable(in scope: PlannerSection) -> Bool {
        scope == .events ? store.eventCreationIsAvailable : store.recordCreationIsAvailable
    }
    private var canMutate: Bool {
        creationIsAvailable(in: section) && (!store.hasPendingPersistence || isProcessingActions)
            && !editorSession.hasActiveEditor && !showingSettings && !showingEditor && attachmentsOwnerID == nil
            && !hasQueuedEditor
    }
    private var hasQueuedEditor: Bool {
        pendingActions.contains {
            switch $0 {
            case .edit, .copy, .week, .editRecord: return true
            default: return false
            }
        }
    }
    private var canDrainActions: Bool {
        attachmentsOwnerID == nil
            && (!editorSession.hasActiveEditor || (editorSession.desktopIsPresented && hasQueuedEditor))
    }
    private var canPresentSettings: Bool {
        !showingEditor && !showingSettings && !editorSession.hasActiveEditor && attachmentsOwnerID == nil
            && !store.hasPendingPersistence
    }
    private var canSwitchToPanel: Bool {
        !showingEditor && !showingSettings && !editorSession.desktopIsPresented && attachmentsOwnerID == nil
    }
    private var canBrowseSelection: Bool {
        !editorSession.subtaskTransferIsSaving && !store.isResolvingMaterials && !hasQueuedEditor && presentedSheet == nil
    }
    private var attachmentLibraryItem: SavedMaterialOwner? {
        guard case let .attachments(ownerID) = presentedSheet,
              let owner = store.savedMaterialOwner(ownerID), !owner.attachments.isEmpty else { return nil }
        return owner
    }
    private var showingEditor: Bool {
        presentedSheet == .editor || presentedSheet == .recordEditor || presentedSheet == .textAttachment
            || presentedSheet == .week
    }
    private var showingSettings: Bool { presentedSheet == .settings }
    private var attachmentsOwnerID: UUID? {
        if case let .attachments(ownerID) = presentedSheet { return ownerID.id }
        return nil
    }
    private var sheetPresentation: Binding<Bool> {
        Binding(get: { presentedSheet != nil && !sheetIsClosing }, set: { requested in
            if !requested { dismissSheet() }
        })
    }

    var body: some View {
        let collection = collection
        let records = section == .records ? recordCollection : []
        let visibleIDs = section == .events ? collection.events.map(\.id) : records.map(\.id)
        VStack(spacing: 0) {
            desktopCommandBar
            Divider()
            if let error = store.error, !showingEditor, attachmentsOwnerID == nil { errorBanner(error) }
            if editorSession.isPresented || editorSession.subtaskTransfer?.surface == .panel { panelEditorBanner }
            splitContent(collection, records: records)
            Divider()
            footer
        }
        .background(AuroraInstrument.canvas(for: colorScheme))
        .foregroundStyle(AuroraInstrument.ink(for: colorScheme))
        .tint(AuroraInstrument.accent(for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast))
        .disabled(presentedSheet != nil)
        .allowsHitTesting(presentedSheet == nil)
        .accessibilityHidden(presentedSheet != nil)
        .sheet(isPresented: sheetPresentation, onDismiss: finishSheetDismissal) {
            sheetContent
                .foregroundStyle(AuroraInstrument.ink(for: colorScheme))
                .tint(AuroraInstrument.accent(for: colorScheme,
                                             highContrast: accessibilitySettings.prefersHighContrast))
                .background(AuroraPanelCanvas())
                .background(DesktopSheetTerminationPolicy(preventsTermination: showingEditor))
                .interactiveDismissDisabled()
                .disabled(sheetIsClosing)
                .allowsHitTesting(!sheetIsClosing)
                .accessibilityHidden(sheetIsClosing)
        }
        .environmentObject(accessibilitySettings)
        .environmentObject(appPreferences)
        .environment(\.locale, appPreferences.language.locale)
        .environment(\.colorScheme, colorScheme)
        .onAppear {
            reconcileSelection(visibleIDs)
            registerPasteAction?(pasteTextAttachment)
        }
        .onDisappear { registerPasteAction?(nil) }
        .onChange(of: visibleIDs) { reconcileSelection($0) }
        .onChange(of: section) { value in
            if value == .records, editorSession.subtaskTransfer?.surface == .desktop {
                editorSession.endSubtaskTransfer()
            }
        }
        .onChange(of: editorSession.hasActiveEditor) { _ in processPendingActions() }
        .onChange(of: store.hasPendingPersistence) { _ in processPendingActions() }
        .onChange(of: store.eventCreationIsAvailable) { _ in processPendingActions() }
        .onChange(of: store.recordCreationIsAvailable) { _ in processPendingActions() }
        .onChange(of: showingSettings) { _ in processPendingActions() }
        .onChange(of: attachmentsOwnerID) { _ in processPendingActions() }
        .onChange(of: attachmentLibraryItem?.id) { ownerID in
            if ownerID == nil { dismissAttachments() }
        }
        .onChange(of: attachmentLibraryItem) { owner in attachmentPreview.reconcile(owner: owner) }
        .onChange(of: attachmentPreview.selection) { preview in
            if preview == nil {
                if !attachmentLibraryIsSource {
                    dismissAttachments()
                } else if attachmentLibraryItem != nil {
                    attachmentPreviewWasPresented = false
                }
            }
        }
        .onChange(of: selectedID) { selectedID in
            if let transfer = editorSession.subtaskTransfer, transfer.surface == .desktop,
               transfer.eventID != selectedID {
                editorSession.endSubtaskTransfer()
            }
            if selectedID != attachmentsOwnerID { dismissAttachments() }
        }
        .onChange(of: isProcessingActions) { _ in processPendingActions() }
        .onReceive(store.$data) { _ in
            DispatchQueue.main.async {
                if !store.hasPendingPersistence {
                    editorSession.reconcileSubtaskTransfer(items: store.data.items, today: store.today)
                }
                processPendingActions()
            }
        }
        .onChange(of: store.today) { _ in
            editorSession.reconcileSubtaskTransfer(items: store.data.items, today: store.today)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("desktop.root")
        .uiSmokeControl(id: "desktop.root")
        .uiSmokeControlScope(smokeControlScope)
    }

    @ViewBuilder private var sheetContent: some View {
        switch presentedSheet {
        case .editor:
            VStack(spacing: 0) {
                if let error = store.error { errorBanner(error) }
                EditorView(store: store, item: editing, copying: copying, dayPreset: dayPreset, selectDayDate: selectDayDate,
                           didSave: eventSaved, done: dismissSheet)
            }
            .frame(width: 430, height: 600)
        case .recordEditor:
            VStack(spacing: 0) {
                if let error = store.error { errorBanner(error) }
                EditorView(store: store, record: editingRecord, didSave: recordSaved, done: dismissSheet)
            }
            .frame(width: 430, height: 600)
        case .week:
            if let weekCreation {
                VStack(spacing: 0) {
                    if let error = store.error { errorBanner(error) }
                    WeekDayCreationView(store: store, week: weekCreation,
                                        didCreate: weekCreated, cancel: dismissSheet)
                }
                .frame(width: 430, height: 560)
            }
        case .textAttachment:
            if let request = textAttachmentRequest {
                VStack(spacing: 0) {
                    if let error = store.error { errorBanner(error) }
                    TextAttachmentComposer(text: request.text,
                        eventTitle: store.savedMaterialOwner(request.ownerID)?.displayTitle ?? request.ownerID.unavailableTitle,
                        submit: { text in
                            let saved = await store.appendMaterials(EventMaterials(textFile: text), to: request.ownerID)
                            if saved { dismissSheet() }
                            return saved
                        }, cancel: dismissSheet)
                }
                .frame(width: 430, height: 600)
            }
        case .settings:
            SettingsView(store: store, updates: updates, keepAwake: keepAwake, weather: weather,
                         diagnosticsContext: diagnosticsContext, showWhatsNew: presentWhatsNewFromSettings,
                         back: dismissSettings,
                         backShortcut: .cancelAction, showsCloseButton: true)
                .frame(width: 430, height: 560)
                .background {
                    DesktopSheetBackdropDismissal(isEnabled: !sheetIsClosing && !store.isExportingDiagnostics,
                                                  dismiss: dismissSettings)
                }
                .accessibilityIdentifier("desktop.settings.pane")
                .uiSmokeControl(id: "desktop.settings.pane")
        case let .attachments(ownerID):
            if let item = attachmentLibraryItem {
                attachmentsSheet(owner: item, ownerID: ownerID)
            } else {
                unavailableAttachmentScreen
                    .frame(width: attachmentPreviewWasPresented ? 640 : 540,
                           height: attachmentPreviewWasPresented ? 560 : 540)
            }
        case nil:
            EmptyView()
        }
    }

    private func attachmentsSheet(owner: SavedMaterialOwner, ownerID: SavedMaterialOwnerID) -> some View {
        ZStack {
            if attachmentLibraryIsSource {
                AttachmentListView(owner: owner, compact: false, back: dismissAttachments,
                                   open: { showAttachmentPreview($0, ownerID: ownerID, origin: .library) },
                                   thumbnailURL: { [store] in
                                       await store.attachmentThumbnailURL($0, owner: ownerID)
                                   },
                                   error: store.error, dismissError: { store.error = nil })
                    .frame(width: 540, height: 540)
                    .opacity(attachmentPreview.selection == nil ? 1 : 0)
                    .disabled(attachmentPreview.selection != nil)
                    .allowsHitTesting(attachmentPreview.selection == nil)
                    .accessibilityHidden(attachmentPreview.selection != nil)
            }
            if attachmentPreview.selection != nil {
                AttachmentPreviewView(owner: owner, compact: false, session: attachmentPreview,
                                      back: closeAttachmentPreview,
                                      resolveURL: { [store] attachment, _ in await store.attachmentThumbnailURL(attachment, owner: ownerID) },
                                      openExternally: { [store] attachment, _ in await store.openSavedAttachment(attachment, owner: ownerID) },
                                      error: store.error, dismissError: { store.error = nil })
            } else if !attachmentLibraryIsSource {
                unavailableAttachmentScreen
            }
        }
            .frame(width: usesPreviewGeometry ? 640 : 540, height: usesPreviewGeometry ? 560 : 540)
            .id(owner.id)
            .background {
                DesktopSheetBackdropDismissal(isEnabled: !sheetIsClosing, dismiss: closeTopAttachmentScreen)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("desktop.attachments.pane")
            .uiSmokeControl(id: "desktop.attachments.pane")
    }

    private var usesPreviewGeometry: Bool {
        attachmentPreview.selection != nil || (!attachmentLibraryIsSource && attachmentPreviewWasPresented)
    }

    private var unavailableAttachmentScreen: some View {
        VStack(spacing: 12) {
            Text(AppText.string("attachment.title")).font(.custom("Georgia", size: 21))
            Text(AppText.string("attachment.unavailable")).font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AuroraPanelCanvas())
    }

    private func splitContent(_ collection: DesktopEventCollection, records: [UndatedRecord]) -> some View {
        let visibleSection = section
        return GeometryReader { geometry in
            let minimum = desktopMinimumPaneWidth(contentWidth: geometry.size.width)
            HSplitView {
                DesktopEventBrowser(
                    store: store, weather: weather, section: section, collection: collection, records: records, mode: mode,
                    selectedID: selectedID, search: search,
                    select: { id in
                        guard canBrowseSelection, section == visibleSection else { return }
                        selectedID = id
                    }, resetFilters: {
                        guard canBrowseSelection, section == visibleSection else { return }
                        resetFilters()
                    },
                    create: {
                        guard section == visibleSection else { return }
                        if section == .records { beginRecordEditor() }
                        else { beginEditor(preset: .today(store.today)) }
                    }, canCreate: canMutate,
                    editorSession: editorSession, showTextAttachment: presentTextAttachment
                )
                .frame(minWidth: minimum, maxWidth: geometry.size.width - minimum - 1)
                .layoutPriority(1)
                .uiSmokeControl(id: "desktop.overview")
                VStack(spacing: 0) {
                    if section == .records, let selection = records.first(where: { $0.id == selectedID }) {
                        recordDetail(selection)
                            .id(selection.id)
                            .modifier(detailMaterialTarget(.record(selection.id)))
                    } else if section == .events, let selection = collection.events.first(where: { $0.id == selectedID }) {
                        DesktopEventDetail(
                            store: store, editorSession: editorSession, item: selection, today: store.today, primaryID: store.data.primaryID,
                            weather: weather, search: search,
                            canMutate: canMutate && !deletionIsPending(selection.id, in: .events),
                            canBeginTransfer: { canMutate && !isProcessingActions && pendingActions.isEmpty },
                            edit: { beginEditor(item: selection) }, copy: { beginCopy(sourceID: selection.id) },
                            toggleFavorite: { toggleFavorite(selection) },
                            delete: { deleteEvent(selection.id) },
                            toggleSubtask: { toggleSubtask(ownerID: .event(selection.id), subtaskID: $0) },
                            openLink: { store.openSavedLink($0, owner: .event(selection.id)) },
                            openAttachment: { showAttachmentPreview($0, ownerID: .event(selection.id), origin: .summary) },
                            attachmentThumbnailURL: { await store.attachmentThumbnailURL($0, owner: .event(selection.id)) },
                            showAttachments: { presentAttachments(ownerID: .event(selection.id)) }
                        )
                        .id(selection.id)
                        .modifier(detailMaterialTarget(.event(selection.id)))
                    } else {
                        noSelection
                            .uiSmokeControl(id: "desktop.inspector")
                    }
                }
                .frame(minWidth: minimum, maxWidth: geometry.size.width - minimum - 1)
            }
            .overlay { DesktopDividerGrip() }
            .uiSmokeControl(id: "desktop.split")
        }
    }

    private func detailMaterialTarget(_ ownerID: SavedMaterialOwnerID) -> SavedMaterialTarget {
        SavedMaterialTarget(store: store, editorSession: editorSession, ownerID: ownerID, enabled: canMutate,
                            targetSurface: "desktop.detail",
                            showText: { presentTextAttachment(ownerID: ownerID, text: $0) })
    }

    private func recordDetail(_ record: UndatedRecord) -> some View {
        let available = canMutate && !deletionIsPending(record.id, in: .records)
        return DesktopRecordDetail(
            record: record, search: search, canMutate: available,
            canReorder: available && !isProcessingActions && pendingActions.isEmpty,
            editorPresented: editorSession.desktopIsPresented,
            edit: { beginRecordEditor(recordID: record.id) }, delete: { deleteRecord(record.id) },
            toggleSubtask: { toggleSubtask(ownerID: .record(record.id), subtaskID: $0) },
            saveSubtaskOrder: { move, index in
                guard section == .records, selectedRecordID == record.id, canMutate,
                      !isProcessingActions, pendingActions.isEmpty else { return false }
                return await store.reorderSubtask(owner: .record(record.id), move: move, to: index)
            },
            openLink: { store.openSavedLink($0, owner: .record(record.id)) },
            openAttachment: { showAttachmentPreview($0, ownerID: .record(record.id), origin: .summary) },
            attachmentThumbnailURL: { await store.attachmentThumbnailURL($0, owner: .record(record.id)) },
            showAttachments: { presentAttachments(ownerID: .record(record.id)) }
        )
    }

    private var desktopCommandBar: some View {
        HStack(spacing: 12) {
            PlannerSectionPicker(selection: Binding(get: { section }, set: selectSection), surface: "desktop")
                .disabled(!canBrowseSelection)
            Picker(AppText.string("desktop.modeLabel"), selection: $mode) {
                ForEach(DesktopEventViewMode.allCases, id: \.self) { mode in
                    Label(mode.title, systemImage: mode.systemImage)
                        .labelStyle(.iconOnly)
                        .help(mode.title)
                        .accessibilityLabel(mode.title)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 80)
            .accessibilityLabel(AppText.string("desktop.modeLabel"))
            .accessibilityIdentifier("desktop.mode")
            .uiSmokeControl(id: "desktop.mode", action: {
                mode = mode == .collection ? .feed : .collection
            }, value: { mode.rawValue })
            Spacer(minLength: 12)
            let searchTitle = section == .events ? AppText.string("desktop.search") : AppText.string("desktop.searchRecords")
            let searchHint = section == .events ? AppText.string("desktop.searchHint") : AppText.string("desktop.searchRecordsHint")
            TextField(searchTitle, text: query)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .focused($searchFocused)
                .accessibilityLabel(searchTitle)
                .accessibilityHint(searchHint)
                .accessibilityIdentifier("desktop.search")
                .uiSmokeControl(id: "desktop.search", action: { searchFocused = true }, value: { query.wrappedValue })
                .disabled(hasQueuedEditor || store.isResolvingMaterials)
            if section == .events {
                eventCreationControls
            } else if !store.showsEmptyRecordList || !search.query.isEmpty {
                Button { beginRecordEditor() } label: {
                    AuroraToolbarLabel(title: AppText.string("record.title"), systemImage: "plus", showsMenuIndicator: false)
                }
                .auroraToolbarAction()
                .keyboardShortcut("n", modifiers: .command)
                .accessibilityIdentifier("desktop.record.create")
                .uiSmokeControl(id: "desktop.record.create", action: { beginRecordEditor() })
                .disabled(!canMutate)
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 54)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("desktop.command-bar")
    }

    @ViewBuilder private var eventCreationControls: some View {
        Button { beginEditor() } label: {
            AuroraToolbarLabel(title: AppText.string("event.title"), systemImage: "plus", showsMenuIndicator: false)
        }
        .auroraToolbarAction()
        .keyboardShortcut("n", modifiers: .command)
        .accessibilityIdentifier("desktop.create")
        .uiSmokeControl(id: "desktop.create", action: { beginEditor() })
        .disabled(!canMutate)
        Menu {
            Button(AppText.string("event.createToday")) { beginEditor(preset: .today(store.today)) }
            Button(AppText.string("event.createTomorrow")) { beginEditor(preset: .tomorrow(after: store.today)) }
            Button(AppText.string("event.chooseDateMenu")) {
                beginEditor(preset: .tomorrow(after: store.today), selectDate: true)
            }
            Divider()
            Button(weekCreationTitle(for: store.today) + "…", action: beginWeekDays)
                .accessibilityIdentifier("desktop.create-week")
        } label: {
            AuroraToolbarLabel(title: AppText.string("event.createDay"), systemImage: "calendar.badge.plus", showsMenuIndicator: true)
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .auroraToolbarAction()
        .fixedSize()
        .accessibilityIdentifier("desktop.create-day")
        .uiSmokeControl(id: "desktop.create-week", action: beginWeekDays,
                        value: { weekCreationTitle(for: store.today) })
        .disabled(!canMutate)
    }

    private var footer: some View {
        let storage = section == .events ? AppText.string("desktop.localStorage") : AppText.string("panel.localStorage")
        return HStack(spacing: 16) {
            Label(storage, systemImage: "internaldrive")
                .font(.system(size: 11))
                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
            Spacer(minLength: 0)
            Button(action: switchSurfaceToPanel) { Label(AppText.string("desktop.miniPanel"), systemImage: "menubar.rectangle") }
                .accessibilityIdentifier("desktop.panel")
                .uiSmokeControl(id: "desktop.panel", action: switchSurfaceToPanel)
                .disabled(!canSwitchToPanel)
            Button(action: presentSettings) { Label(AppText.string("settings.title"), systemImage: "gearshape") }
                .accessibilityIdentifier("desktop.settings")
                .keyboardShortcut(",", modifiers: .command)
                .uiSmokeControl(id: "desktop.settings", action: presentSettings)
                .disabled(!canPresentSettings)
        }
        .padding(.horizontal, 18)
        .frame(height: 44)
        .background(AuroraInstrument.timerSurface(for: colorScheme))
    }

    private var panelEditorBanner: some View {
        HStack {
            Label(editorSession.subtaskTransfer?.surface == .panel
                  ? AppText.string("desktop.pendingTransfer")
                  : AppText.string("desktop.pendingEditor"),
                  systemImage: editorSession.subtaskTransfer?.surface == .panel ? "arrowshape.turn.up.right" : "pencil")
                .font(.system(size: 12))
            Spacer()
            Button(editorSession.subtaskTransfer?.surface == .panel ? AppText.string("desktop.returnToTransfer") : AppText.string("desktop.returnToEditor"), action: showPanel)
        }
        .padding(12)
        .background(AuroraInstrument.accentSurface(for: colorScheme,
                                                  highContrast: accessibilitySettings.prefersHighContrast))
        .accessibilityIdentifier("desktop.editor-busy")
        .uiSmokeControl(id: "desktop.editor-busy")
    }

    private var noSelection: some View {
        VStack(spacing: 12) {
            if section == .events {
                Image(systemName: "calendar").font(.system(size: 28)).accessibilityHidden(true)
                Text(AppText.string("desktop.chooseEvent"))
                    .font(.custom("Georgia", size: 23))
            }
            Text(section == .events ? AppText.string("desktop.noSelection") : AppText.string("desktop.record.noSelection"))
                .font(.system(size: 13)).multilineTextAlignment(.center)
                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AuroraInstrument.surface(for: colorScheme, elevated: false,
                                            highContrast: accessibilitySettings.prefersHighContrast))
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(alignment: .top) {
            Text(error).font(.system(size: 12)).textSelection(.enabled)
            Spacer()
            Button(AppText.string("common.ok")) { store.error = nil }
                .uiSmokeControl(id: "desktop.error.dismiss", action: { store.error = nil })
        }
        .padding(12)
        .background(Color.red.opacity(0.1))
        .accessibilityIdentifier("desktop.error")
        .uiSmokeControl(id: "desktop.error", value: { error })
    }

    private func reconcileSelection(_ visibleIDs: [UUID]) {
        selectedID = desktopSelection(current: selectedID, available: visibleIDs)
    }

    private func selectSection(_ nextSection: PlannerSection) {
        guard canBrowseSelection, section != nextSection else { return }
        searchFocused = false
        switch nextSection {
        case .events:
            selectedEventID = desktopSelection(current: selectedEventID, available: collection.events.map(\.id))
        case .records:
            selectedRecordID = desktopSelection(current: selectedRecordID, available: recordCollection.map(\.id))
        }
        section = nextSection
    }

    private func resetFilters() { query.wrappedValue = "" }

    private func presentAttachments(ownerID: SavedMaterialOwnerID) {
        guard canMutate, !isProcessingActions, pendingActions.isEmpty, section == ownerID.plannerSection,
              selectedID == ownerID.id, store.savedMaterialOwner(ownerID)?.attachments.isEmpty == false else { return }
        attachmentPreview.close()
        attachmentLibraryIsSource = true
        attachmentPreviewWasPresented = false
        presentedSheet = .attachments(ownerID)
    }

    private func showAttachmentPreview(_ attachment: EventAttachment, ownerID: SavedMaterialOwnerID,
                                       origin: AttachmentPreviewOrigin) {
        guard !sheetIsClosing, !isProcessingActions, pendingActions.isEmpty,
              !editorSession.hasActiveEditor, let current = store.savedMaterialOwner(ownerID),
              current.attachments.contains(where: { $0.id == attachment.id }) else { return }
        let sheet = DesktopSheet.attachments(ownerID)
        if origin == .summary {
            guard presentedSheet == nil, canMutate, section == ownerID.plannerSection, selectedID == ownerID.id else { return }
            attachmentLibraryIsSource = false
            presentedSheet = sheet
        } else {
            guard presentedSheet == sheet, attachmentLibraryIsSource,
                  attachmentPreview.selection == nil else { return }
        }
        attachmentPreviewWasPresented = true
        attachmentPreview.open(owner: current, attachmentID: attachment.id, origin: origin,
                               resolveURL: { [store] attachment, _ in await store.attachmentThumbnailURL(attachment, owner: ownerID) })
    }

    private func closeAttachmentPreview() {
        guard !sheetIsClosing, attachmentPreview.selection != nil else { return }
        if attachmentLibraryIsSource {
            attachmentPreview.close()
            attachmentPreviewWasPresented = false
        } else {
            dismissAttachments()
        }
    }

    private func closeTopAttachmentScreen() {
        if attachmentPreview.selection != nil { closeAttachmentPreview() } else { dismissAttachments() }
    }

    private func dismissAttachments() {
        guard attachmentsOwnerID != nil else { return }
        dismissSheet()
    }

    private func presentSettings() {
        guard canPresentSettings else { return }
        presentedSheet = .settings
    }

    private func dismissSettings() {
        guard showingSettings, !store.isExportingDiagnostics else { return }
        dismissSheet()
    }

    private func presentWhatsNewFromSettings() {
        guard showingSettings, !sheetIsClosing, !store.isExportingDiagnostics,
              !store.hasPendingPersistence else { return }
        showWhatsNewAfterSettings = true
        DiagnosticLog.shared.record("whats-new.settings-request")
        dismissSheet()
    }

    private func dismissSheet() {
        guard presentedSheet != nil, !sheetIsClosing else { return }
        attachmentPreview.cancelPendingEffects()
        sheetIsClosing = true
    }

    private func finishSheetDismissal() {
        let wasEditor = showingEditor
        let presentWhatsNew = showWhatsNewAfterSettings
        DiagnosticLog.shared.record("whats-new.settings-dismissed requested=\(presentWhatsNew)")
        showWhatsNewAfterSettings = false
        presentedSheet = nil
        textAttachmentRequest = nil
        weekCreation = nil
        editing = nil
        editingRecord = nil
        copying = nil
        attachmentPreview.close()
        attachmentLibraryIsSource = false
        attachmentPreviewWasPresented = false
        sheetIsClosing = false
        if wasEditor { editorSession.endDesktopEditor() }
        if presentWhatsNew {
            // SwiftUI calls onDismiss before AppKit detaches the parent's sheet.
            // Unwind that callback; the shared action still rechecks current admission.
            DispatchQueue.main.async { showWhatsNew() }
        }
    }

    private func switchSurfaceToPanel() {
        guard canSwitchToPanel else { return }
        switchToPanel()
    }

    private func pasteTextAttachment() {
        guard !(NSApp.keyWindow?.firstResponder is NSTextView), let selectedID,
              let text = NSPasteboard.general.string(forType: .string) else { return }
        presentTextAttachment(ownerID: section == .events ? .event(selectedID) : .record(selectedID), text: text)
    }

    private func presentTextAttachment(ownerID: SavedMaterialOwnerID, text: String) {
        guard canMutate, !isProcessingActions,
              ownerID.plannerSection == section,
              let owner = store.savedMaterialOwner(ownerID),
              editorSession.beginDesktopEditor() else { return }
        selectedID = owner.id
        textAttachmentRequest = TextAttachmentRequest(ownerID: ownerID, text: text)
        presentedSheet = .textAttachment
    }

    private func beginEditor(item: Countdown? = nil, preset: DayCreationPreset? = nil, selectDate: Bool = false) {
        guard section == .events, canMutate, editorSession.beginDesktopEditor() else { return }
        pendingActions.append(.edit(itemID: item?.id, preset: preset, selectDate: selectDate))
        processPendingActions()
    }

    private func beginCopy(sourceID: UUID) {
        guard section == .events, canMutate, editorSession.beginDesktopEditor() else { return }
        pendingActions.append(.copy(sourceID: sourceID))
        processPendingActions()
    }

    private func beginWeekDays() {
        guard section == .events, canMutate, let week = DayCreationWeek(today: store.today),
              editorSession.beginDesktopEditor() else { return }
        pendingActions.append(.week(week))
        processPendingActions()
    }

    private func presentWeekDays(_ week: DayCreationWeek) -> Bool {
        guard store.eventCreationIsAvailable, !store.hasPendingPersistence,
              editorSession.desktopIsPresented, !showingSettings, !showingEditor else { return false }
        weekCreation = week
        presentedSheet = .week
        return true
    }

    private func weekCreated(_ events: [Countdown]) {
        eventQuery = ""
        if let event = events.first {
            selectedEventID = event.id
            weather.didSaveEvent(event, activeEvents: store.active)
        }
    }

    private func presentEditor(itemID: UUID?, preset: DayCreationPreset?, selectDate: Bool) -> Bool {
        guard store.eventCreationIsAvailable, !store.hasPendingPersistence,
              editorSession.desktopIsPresented, !showingSettings, !showingEditor else { return false }
        let latestItem: Countdown?
        if let itemID {
            guard let current = store.active.first(where: { $0.id == itemID }) else { return false }
            latestItem = current
        } else {
            latestItem = nil
        }
        editing = latestItem
        copying = nil
        dayPreset = preset
        selectDayDate = selectDate
        presentedSheet = .editor
        return true
    }

    private func presentCopy(sourceID: UUID) -> Bool {
        guard store.eventCreationIsAvailable, !store.hasPendingPersistence,
              editorSession.desktopIsPresented, !showingSettings, !showingEditor,
              let source = store.active.first(where: { $0.id == sourceID }) else { return false }
        editing = nil
        copying = source
        dayPreset = nil
        selectDayDate = false
        presentedSheet = .editor
        return true
    }

    private func eventSaved(_ event: Countdown) {
        eventQuery = ""
        selectedEventID = event.id
        weather.didSaveEvent(event, activeEvents: store.active)
    }

    private func beginRecordEditor(recordID: UUID? = nil) {
        guard section == .records, canMutate else { return }
        if let recordID {
            guard selectedRecordID == recordID, !deletionIsPending(recordID, in: .records) else { return }
        }
        guard editorSession.beginDesktopEditor() else { return }
        pendingActions.append(.editRecord(recordID: recordID))
        processPendingActions()
    }

    private func presentRecordEditor(recordID: UUID?) -> Bool {
        guard section == .records, store.recordCreationIsAvailable, !store.hasPendingPersistence,
              editorSession.desktopIsPresented, !showingSettings, !showingEditor else { return false }
        if let recordID {
            guard let record = store.records.first(where: { $0.id == recordID }) else { return false }
            editingRecord = record
        } else {
            editingRecord = nil
        }
        presentedSheet = .recordEditor
        return true
    }

    private func recordSaved(_ record: UndatedRecord) {
        recordQuery = ""
        selectedRecordID = record.id
    }

    private func toggleFavorite(_ event: Countdown) {
        guard section == .events, canMutate else { return }
        pendingActions.append(.toggleFavorite(eventID: event.id))
        processPendingActions()
    }

    private func toggleSubtask(ownerID: SavedMaterialOwnerID, subtaskID: UUID) {
        guard section == ownerID.plannerSection, selectedID == ownerID.id, canMutate,
              !deletionIsPending(ownerID.id, in: section) else { return }
        pendingActions.append(.toggleSubtask(ownerID: ownerID, subtaskID: subtaskID))
        processPendingActions()
    }

    private func deletionIsPending(_ id: UUID, in scope: PlannerSection) -> Bool {
        if deletingItem?.section == scope, deletingItem?.id == id { return true }
        return pendingActions.contains { action in
            switch action {
            case let .delete(queuedID): scope == .events && queuedID == id
            case let .deleteRecord(queuedID): scope == .records && queuedID == id
            default: false
            }
        }
    }

    private func deleteEvent(_ eventID: UUID) {
        guard section == .events, canMutate, !deletionIsPending(eventID, in: .events),
              store.active.contains(where: { $0.id == eventID }) else { return }
        pendingActions.append(.delete(eventID: eventID))
        processPendingActions()
    }

    private func deleteRecord(_ recordID: UUID) {
        guard section == .records, selectedRecordID == recordID, canMutate, !deletionIsPending(recordID, in: .records),
              store.records.contains(where: { $0.id == recordID }) else { return }
        pendingActions.append(.deleteRecord(recordID: recordID))
        processPendingActions()
    }

    private func processPendingActions() {
        guard !isProcessingActions, !pendingActions.isEmpty,
              !store.hasPendingPersistence, canDrainActions,
              !showingSettings, !showingEditor else { return }
        isProcessingActions = true
        Task { @MainActor in
            defer { isProcessingActions = false }
            while !pendingActions.isEmpty,
                  !store.hasPendingPersistence, canDrainActions,
                  !showingSettings, !showingEditor {
                let action = pendingActions.removeFirst()
                guard creationIsAvailable(in: action.section) else {
                    reportPendingActionFailure(in: action.section)
                    return
                }
                let succeeded: Bool
                switch action {
                case let .toggleSubtask(ownerID, subtaskID):
                    succeeded = await store.toggleSubtask(owner: ownerID, subtaskID: subtaskID)
                case let .toggleFavorite(eventID):
                    guard store.active.contains(where: { $0.id == eventID }) else {
                        reportPendingActionFailure(in: .events)
                        return
                    }
                    let expectedID = store.data.primaryID == eventID ? nil : eventID
                    if expectedID == nil { await store.clearPrimary() }
                    else { await store.makePrimary(eventID) }
                    succeeded = store.data.primaryID == expectedID
                case let .delete(eventID):
                    deletingItem = (.events, eventID)
                    succeeded = await store.delete(eventID)
                    deletingItem = nil
                case let .deleteRecord(recordID):
                    deletingItem = (.records, recordID)
                    succeeded = await store.deleteRecord(recordID)
                    deletingItem = nil
                case let .edit(itemID, preset, selectDate):
                    succeeded = presentEditor(itemID: itemID, preset: preset, selectDate: selectDate)
                case let .editRecord(recordID):
                    succeeded = presentRecordEditor(recordID: recordID)
                case let .copy(sourceID):
                    succeeded = presentCopy(sourceID: sourceID)
                case let .week(week):
                    succeeded = presentWeekDays(week)
                }
                if !succeeded {
                    reportPendingActionFailure(in: action.section)
                    return
                }
            }
        }
    }

    private func reportPendingActionFailure(in scope: PlannerSection) {
        let hadRemainingActions = !pendingActions.isEmpty
        pendingActions.removeAll()
        if editorSession.desktopIsPresented && !showingEditor { editorSession.endDesktopEditor() }
        let unavailable = scope == .events ? AppText.string("desktop.queuedTargetMissing") : AppText.string("record.error.unavailable")
        store.reportQueuedActionFailure(fallback: unavailable, hadRemainingActions: hadRemainingActions)
    }
}

private extension SavedMaterialOwnerID {
    var plannerSection: PlannerSection {
        collection == .events ? .events : .records
    }
}
