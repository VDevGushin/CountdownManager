import CountdownCore
import SwiftUI

struct DesktopRootView: View {
    private enum DesktopSheet: Equatable {
        case editor
        case settings
        case attachments(UUID)
    }

    private enum PendingAction {
        case toggleSubtask(eventID: UUID, subtaskID: UUID)
        case toggleFavorite(eventID: UUID)
        case delete(eventID: UUID)
        case edit(itemID: UUID?, preset: DayCreationPreset?, selectDate: Bool)
    }

    @ObservedObject var store: Store
    @ObservedObject var updates: ApplicationUpdates
    @ObservedObject var editorSession: EventEditorSession
    @ObservedObject var keepAwake: KeepAwakeController
    @ObservedObject var weather: WeatherController
    @ObservedObject var accessibilitySettings: AuroraAccessibilitySettings
    @ObservedObject var visualEnvironment: UISmokeVisualEnvironment
    @ObservedObject var appearanceSettings: ApplicationAppearance
    let showPanel: () -> Void
    let switchToPanel: () -> Void
    let diagnosticsContext: () -> DiagnosticExportContext
    var smokeControlScope = ""
    @State private var mode = DesktopEventViewMode.collection
    @State private var query = ""
    @State private var selectedID: UUID?
    @StateObject private var attachmentPreview = AttachmentPreviewSession()
    @State private var attachmentLibraryIsSource = false
    @State private var attachmentPreviewWasPresented = false
    // Retain ownership through native dismissal so background actions cannot enter while the sheet is closing.
    @State private var presentedSheet: DesktopSheet?
    @State private var sheetIsClosing = false
    @State private var editing: Countdown?
    @State private var dayPreset: DayCreationPreset?
    @State private var selectDayDate = false
    @State private var pendingActions: [PendingAction] = []
    @State private var isProcessingActions = false
    @State private var deletingEventID: UUID?
    @FocusState private var searchFocused: Bool
    @Environment(\.colorScheme) private var systemColorScheme

    private var colorScheme: ColorScheme {
        appearanceSettings.colorScheme(overriding: visualEnvironment.colorSchemeOverride) ?? systemColorScheme
    }
    private var collection: DesktopEventCollection {
        DesktopEventCollection(items: store.data.items, today: store.today, primaryID: store.data.primaryID,
                               query: query)
    }
    private var canMutate: Bool {
        store.eventCreationIsAvailable && (!store.hasPendingPersistence || isProcessingActions)
            && !editorSession.hasActiveEditor && !showingSettings && !showingEditor && attachmentsEventID == nil
            && !hasQueuedEditor
    }
    private var hasQueuedEditor: Bool {
        pendingActions.contains { if case .edit = $0 { return true }; return false }
    }
    private var canDrainActions: Bool {
        attachmentsEventID == nil
            && (!editorSession.hasActiveEditor || (editorSession.desktopIsPresented && hasQueuedEditor))
    }
    private var canPresentSettings: Bool {
        !showingEditor && !showingSettings && !editorSession.hasActiveEditor && attachmentsEventID == nil
    }
    private var canSwitchToPanel: Bool {
        !showingEditor && !showingSettings && !editorSession.desktopIsPresented && attachmentsEventID == nil
    }
    private var selection: Countdown? { collection.events.first { $0.id == selectedID } }
    private var attachmentLibraryItem: Countdown? {
        store.active.first { $0.id == attachmentsEventID && !$0.attachments.isEmpty }
    }
    private var showingEditor: Bool { presentedSheet == .editor }
    private var showingSettings: Bool { presentedSheet == .settings }
    private var attachmentsEventID: UUID? {
        if case let .attachments(eventID) = presentedSheet { return eventID }
        return nil
    }
    private var sheetPresentation: Binding<Bool> {
        Binding(get: { presentedSheet != nil && !sheetIsClosing }, set: { requested in
            if !requested { dismissSheet() }
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            desktopCommandBar
            Divider()
            if let error = store.error, !showingEditor, attachmentsEventID == nil { errorBanner(error) }
            if editorSession.isPresented { panelEditorBanner }
            splitContent
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
                .interactiveDismissDisabled()
                .disabled(sheetIsClosing)
                .allowsHitTesting(!sheetIsClosing)
                .accessibilityHidden(sheetIsClosing)
        }
        .environmentObject(accessibilitySettings)
        .environmentObject(appearanceSettings)
        .environment(\.colorScheme, colorScheme)
        .onAppear(perform: reconcileSelection)
        .onChange(of: collection.events.map(\.id)) { _ in reconcileSelection() }
        .onChange(of: editorSession.hasActiveEditor) { _ in processPendingActions() }
        .onChange(of: store.hasPendingPersistence) { _ in processPendingActions() }
        .onChange(of: store.eventCreationIsAvailable) { _ in processPendingActions() }
        .onChange(of: showingSettings) { _ in processPendingActions() }
        .onChange(of: attachmentsEventID) { _ in processPendingActions() }
        .onChange(of: attachmentLibraryItem?.id) { ownerID in
            if ownerID == nil { dismissAttachments() }
        }
        .onChange(of: attachmentLibraryItem) { item in attachmentPreview.reconcile(event: item) }
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
            if selectedID != attachmentsEventID { dismissAttachments() }
        }
        .onChange(of: isProcessingActions) { _ in processPendingActions() }
        .onReceive(store.$data) { _ in
            DispatchQueue.main.async { processPendingActions() }
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
                EditorView(store: store, item: editing, dayPreset: dayPreset, selectDayDate: selectDayDate,
                           didSave: eventSaved, done: dismissSheet)
            }
            .frame(width: 430, height: 600)
        case .settings:
            SettingsView(store: store, updates: updates, keepAwake: keepAwake, weather: weather,
                         diagnosticsContext: diagnosticsContext, back: dismissSettings,
                         backShortcut: .cancelAction, showsCloseButton: true)
                .frame(width: 430, height: 560)
                .background {
                    DesktopSheetBackdropDismissal(isEnabled: !sheetIsClosing && !store.isExportingDiagnostics,
                                                  dismiss: dismissSettings)
                }
                .accessibilityIdentifier("desktop.settings.pane")
                .uiSmokeControl(id: "desktop.settings.pane")
        case .attachments:
            if let item = attachmentLibraryItem {
                attachmentsSheet(item: item)
            } else {
                unavailableAttachmentScreen
                    .frame(width: attachmentPreviewWasPresented ? 640 : 540,
                           height: attachmentPreviewWasPresented ? 560 : 540)
            }
        case nil:
            EmptyView()
        }
    }

    private func attachmentsSheet(item: Countdown) -> some View {
        ZStack {
            if attachmentLibraryIsSource {
                AttachmentListView(item: item, compact: false, back: dismissAttachments,
                                   open: { showAttachmentPreview($0, item: item, origin: .library) },
                                   thumbnailURL: { await store.attachmentThumbnailURL($0, eventID: item.id) },
                                   error: store.error, dismissError: { store.error = nil })
                    .frame(width: 540, height: 540)
                    .opacity(attachmentPreview.selection == nil ? 1 : 0)
                    .disabled(attachmentPreview.selection != nil)
                    .allowsHitTesting(attachmentPreview.selection == nil)
                    .accessibilityHidden(attachmentPreview.selection != nil)
            }
            if attachmentPreview.selection != nil {
                AttachmentPreviewView(item: item, compact: false, session: attachmentPreview,
                                      back: closeAttachmentPreview,
                                      resolveURL: { [store] in await store.attachmentThumbnailURL($0, eventID: $1) },
                                      openExternally: { [store] in await store.openAttachment($0, eventID: $1) },
                                      error: store.error, dismissError: { store.error = nil })
            } else if !attachmentLibraryIsSource {
                unavailableAttachmentScreen
            }
        }
            .frame(width: usesPreviewGeometry ? 640 : 540, height: usesPreviewGeometry ? 560 : 540)
            .id(item.id)
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
            Text("Вложение").font(.custom("Georgia", size: 21))
            Text("Вложение больше недоступно").font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AuroraPanelCanvas())
    }

    private var splitContent: some View {
        GeometryReader { geometry in
            let minimum = desktopMinimumPaneWidth(contentWidth: geometry.size.width)
            HSplitView {
                DesktopEventBrowser(
                    store: store, weather: weather, collection: collection, mode: mode,
                    selectedID: selectedID, isFiltering: !query.isEmpty,
                    select: { selectedID = $0 }, resetFilters: resetFilters,
                    create: { beginEditor(preset: .today(store.today)) }, canCreate: canMutate
                )
                .frame(minWidth: minimum, maxWidth: geometry.size.width - minimum - 1)
                .layoutPriority(1)
                .uiSmokeControl(id: "desktop.overview")
                VStack(spacing: 0) {
                    if let selection {
                        DesktopEventDetail(
                            item: selection, today: store.today, primaryID: store.data.primaryID,
                            weather: weather, canMutate: canMutate && !deletionIsPending(selection.id),
                            edit: { beginEditor(item: selection) }, toggleFavorite: { toggleFavorite(selection) },
                            delete: { deleteEvent(selection.id) },
                            toggleSubtask: { toggleSubtask(selection, subtaskID: $0) },
                            openLink: { store.openLink($0, eventID: selection.id) },
                            openAttachment: { attachment in
                                showAttachmentPreview(attachment, item: selection, origin: .summary)
                            },
                            attachmentThumbnailURL: { attachment in
                                await store.attachmentThumbnailURL(attachment, eventID: selection.id)
                            }, showAttachments: { presentAttachments(eventID: selection.id) }
                        )
                        .id(selection.id)
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

    private var desktopCommandBar: some View {
        HStack(spacing: 12) {
            Picker("Вид событий", selection: $mode) {
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
            .accessibilityLabel("Вид событий")
            .accessibilityIdentifier("desktop.mode")
            .uiSmokeControl(id: "desktop.mode", action: {
                mode = mode == .collection ? .feed : .collection
            }, value: { mode.rawValue })
            Spacer(minLength: 12)
            TextField("Найти событие", text: $query)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .focused($searchFocused)
                .accessibilityLabel("Найти событие")
                .accessibilityIdentifier("desktop.search")
                .uiSmokeControl(id: "desktop.search", action: { searchFocused = true }, value: { query })
            Button { beginEditor() } label: { Label("Событие", systemImage: "plus") }
                .keyboardShortcut("n", modifiers: .command)
                .accessibilityIdentifier("desktop.create")
                .uiSmokeControl(id: "desktop.create", action: { beginEditor() })
                .disabled(!canMutate)
            Menu {
                Button("На сегодня") { beginEditor(preset: .today(store.today)) }
                Button("На завтра") { beginEditor(preset: .tomorrow(after: store.today)) }
                Button("Выбрать дату…") {
                    beginEditor(preset: .tomorrow(after: store.today), selectDate: true)
                }
            } label: {
                Label("Создать день", systemImage: "calendar.badge.plus")
            }
            .fixedSize()
            .disabled(!canMutate)
            .accessibilityIdentifier("desktop.create-day")
        }
        .padding(.horizontal, 20)
        .frame(height: 54)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("desktop.command-bar")
    }

    private var footer: some View {
        HStack(spacing: 16) {
            Label("События хранятся на этом Mac", systemImage: "internaldrive")
                .font(.system(size: 11))
                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
            Spacer(minLength: 0)
            Button(action: switchSurfaceToPanel) { Label("В мини-панель", systemImage: "menubar.rectangle") }
                .accessibilityIdentifier("desktop.panel")
                .uiSmokeControl(id: "desktop.panel", action: switchSurfaceToPanel)
                .disabled(!canSwitchToPanel)
            Button(action: presentSettings) { Label("Настройки", systemImage: "gearshape") }
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
            Label("В мини-панели открыт редактор. Сначала сохраните или отмените изменения.", systemImage: "pencil")
                .font(.system(size: 12))
            Spacer()
            Button("К редактору", action: showPanel)
        }
        .padding(12)
        .background(AuroraInstrument.accentSurface(for: colorScheme,
                                                  highContrast: accessibilitySettings.prefersHighContrast))
        .accessibilityIdentifier("desktop.editor-busy")
        .uiSmokeControl(id: "desktop.editor-busy")
    }

    private var noSelection: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar").font(.system(size: 28)).accessibilityHidden(true)
            Text("Выберите событие").font(.custom("Georgia", size: 23))
            Text("Его заметка и список подготовки появятся здесь.")
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
            Button("Понятно") { store.error = nil }
                .uiSmokeControl(id: "desktop.error.dismiss", action: { store.error = nil })
        }
        .padding(12)
        .background(Color.red.opacity(0.1))
        .accessibilityIdentifier("desktop.error")
        .uiSmokeControl(id: "desktop.error", value: { error })
    }

    private func reconcileSelection() {
        selectedID = desktopSelection(current: selectedID, available: collection.events)
    }

    private func resetFilters() { query = "" }

    private func presentAttachments(eventID: UUID) {
        guard canMutate, !isProcessingActions, pendingActions.isEmpty,
              selection?.id == eventID, selection?.attachments.isEmpty == false else { return }
        attachmentPreview.close()
        attachmentLibraryIsSource = true
        attachmentPreviewWasPresented = false
        presentedSheet = .attachments(eventID)
    }

    private func showAttachmentPreview(_ attachment: EventAttachment, item: Countdown,
                                       origin: AttachmentPreviewOrigin) {
        guard !sheetIsClosing, !isProcessingActions, pendingActions.isEmpty,
              !editorSession.hasActiveEditor,
              let current = store.active.first(where: { $0.id == item.id }),
              current.attachments.contains(where: { $0.id == attachment.id }) else { return }
        if origin == .summary {
            guard presentedSheet == nil, canMutate, selection?.id == item.id else { return }
            attachmentLibraryIsSource = false
            presentedSheet = .attachments(item.id)
        } else {
            guard attachmentsEventID == item.id, attachmentLibraryIsSource,
                  attachmentPreview.selection == nil else { return }
        }
        attachmentPreviewWasPresented = true
        attachmentPreview.open(event: current, attachmentID: attachment.id, origin: origin,
                               resolveURL: { [store] in await store.attachmentThumbnailURL($0, eventID: $1) })
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
        guard attachmentsEventID != nil else { return }
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

    private func dismissSheet() {
        guard presentedSheet != nil, !sheetIsClosing else { return }
        attachmentPreview.cancelPendingEffects()
        sheetIsClosing = true
    }

    private func finishSheetDismissal() {
        let wasEditor = showingEditor
        presentedSheet = nil
        attachmentPreview.close()
        attachmentLibraryIsSource = false
        attachmentPreviewWasPresented = false
        sheetIsClosing = false
        if wasEditor { editorSession.endDesktopEditor() }
    }

    private func switchSurfaceToPanel() {
        guard canSwitchToPanel else { return }
        switchToPanel()
    }

    private func beginEditor(item: Countdown? = nil, preset: DayCreationPreset? = nil, selectDate: Bool = false) {
        guard canMutate, editorSession.beginDesktopEditor() else { return }
        pendingActions.append(.edit(itemID: item?.id, preset: preset, selectDate: selectDate))
        processPendingActions()
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
        dayPreset = preset
        selectDayDate = selectDate
        presentedSheet = .editor
        return true
    }

    private func eventSaved(_ event: Countdown) {
        resetFilters()
        selectedID = event.id
        weather.didSaveEvent(event, activeEvents: store.active)
    }

    private func toggleFavorite(_ event: Countdown) {
        guard canMutate else { return }
        pendingActions.append(.toggleFavorite(eventID: event.id))
        processPendingActions()
    }

    private func toggleSubtask(_ event: Countdown, subtaskID: UUID) {
        guard canMutate else { return }
        pendingActions.append(.toggleSubtask(eventID: event.id, subtaskID: subtaskID))
        processPendingActions()
    }

    private func deletionIsPending(_ eventID: UUID) -> Bool {
        deletingEventID == eventID || pendingActions.contains {
            if case let .delete(queuedID) = $0 { return queuedID == eventID }
            return false
        }
    }

    private func deleteEvent(_ eventID: UUID) {
        guard canMutate, !deletionIsPending(eventID), store.active.contains(where: { $0.id == eventID }) else { return }
        pendingActions.append(.delete(eventID: eventID))
        processPendingActions()
    }

    private func processPendingActions() {
        guard !isProcessingActions, !pendingActions.isEmpty, store.eventCreationIsAvailable,
              !store.hasPendingPersistence, canDrainActions,
              !showingSettings, !showingEditor else { return }
        isProcessingActions = true
        Task { @MainActor in
            defer { isProcessingActions = false }
            while !pendingActions.isEmpty, store.eventCreationIsAvailable,
                  !store.hasPendingPersistence, canDrainActions,
                  !showingSettings, !showingEditor {
                let action = pendingActions.removeFirst()
                let succeeded: Bool
                switch action {
                case let .toggleSubtask(eventID, subtaskID):
                    succeeded = await store.toggleSubtask(eventID: eventID, subtaskID: subtaskID)
                case let .toggleFavorite(eventID):
                    guard store.active.contains(where: { $0.id == eventID }) else {
                        reportPendingActionFailure()
                        return
                    }
                    let expectedID = store.data.primaryID == eventID ? nil : eventID
                    if expectedID == nil { await store.clearPrimary() }
                    else { await store.makePrimary(eventID) }
                    succeeded = store.data.primaryID == expectedID
                case let .delete(eventID):
                    deletingEventID = eventID
                    succeeded = await store.delete(eventID)
                    deletingEventID = nil
                case let .edit(itemID, preset, selectDate):
                    succeeded = presentEditor(itemID: itemID, preset: preset, selectDate: selectDate)
                }
                if !succeeded {
                    reportPendingActionFailure()
                    return
                }
            }
        }
    }

    private func reportPendingActionFailure() {
        let hadRemainingActions = !pendingActions.isEmpty
        pendingActions.removeAll()
        if editorSession.desktopIsPresented && !showingEditor { editorSession.endDesktopEditor() }
        let message = store.error ?? "Событие или подзадача больше недоступны."
        store.error = hadRemainingActions ? message + " Оставшиеся действия не выполнены; повторите их после проверки события." : message
    }
}
