import CountdownCore
import SwiftUI

struct DesktopRootView: View {
    private enum PendingAction {
        case toggleSubtask(eventID: UUID, subtaskID: UUID)
        case toggleFavorite(eventID: UUID)
        case delete(eventID: UUID)
        case edit(itemID: UUID?, preset: DayCreationPreset?, selectDate: Bool)
    }

    @ObservedObject var store: Store
    @ObservedObject var timer: CountdownTimer
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
    @State private var mode = DesktopEventViewMode.collection
    @State private var query = ""
    @State private var selectedID: UUID?
    @State private var showingEditor = false
    @State private var showingSettings = false
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
            && !editorSession.hasActiveEditor && !showingSettings && !showingEditor
            && !hasQueuedEditor
    }
    private var hasQueuedEditor: Bool {
        pendingActions.contains { if case .edit = $0 { return true }; return false }
    }
    private var canDrainActions: Bool {
        !editorSession.hasActiveEditor || (editorSession.desktopIsPresented && hasQueuedEditor)
    }
    private var canPresentSettings: Bool {
        !showingEditor && !showingSettings && !editorSession.hasActiveEditor
    }
    private var canSwitchToPanel: Bool {
        !showingEditor && !showingSettings && !editorSession.desktopIsPresented
    }
    private var selection: Countdown? { collection.events.first { $0.id == selectedID } }

    var body: some View {
        VStack(spacing: 0) {
            desktopCommandBar
            Divider()
            if let error = store.error { errorBanner(error) }
            if editorSession.isPresented { panelEditorBanner }
            splitContent
            Divider()
            footer
        }
        .background(AuroraInstrument.canvas(for: colorScheme))
        .foregroundStyle(AuroraInstrument.ink(for: colorScheme))
        .tint(AuroraInstrument.accent(for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast))
        .sheet(isPresented: $showingEditor, onDismiss: editorSession.endDesktopEditor) {
            EditorView(store: store, item: editing, dayPreset: dayPreset, selectDayDate: selectDayDate,
                       didSave: eventSaved, done: { showingEditor = false })
                .frame(width: 430, height: 600)
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(store: store, updates: updates, keepAwake: keepAwake, weather: weather,
                         diagnosticsContext: diagnosticsContext, back: { showingSettings = false })
                .frame(width: 430, height: 560)
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
        .onChange(of: isProcessingActions) { _ in processPendingActions() }
        .onReceive(store.$data) { _ in
            DispatchQueue.main.async { processPendingActions() }
        }
        .accessibilityIdentifier("desktop.root")
        .uiSmokeControl(id: "desktop.root")
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
                            toggleSubtask: { toggleSubtask(selection, subtaskID: $0) }
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
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 190)
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
        .accessibilityIdentifier("desktop.command-bar")
    }

    private var footer: some View {
        HStack(spacing: 16) {
            CountdownTimerStrip(timer: timer, layout: .desktop).frame(width: 390)
            Spacer(minLength: 0)
            Label("События хранятся на этом Mac", systemImage: "internaldrive")
                .font(.system(size: 11))
                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
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
        .padding(.trailing, 18)
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

    private func presentSettings() {
        guard canPresentSettings else { return }
        showingSettings = true
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
        showingEditor = true
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
