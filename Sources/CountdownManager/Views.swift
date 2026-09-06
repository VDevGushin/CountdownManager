import AppKit
import SwiftUI
import ServiceManagement
import CountdownCore

private struct QuickSubtaskEditorTarget: Identifiable {
    let eventID: UUID
    let subtask: Subtask?
    var id: String { "\(eventID.uuidString)-\(subtask?.id.uuidString ?? "new")" }
}

struct ManagerView: View {
    @ObservedObject var store: Store
    @State private var editing: Countdown?
    @State private var showingEditor = false
    @State private var pendingDeletion: Countdown?
    @State private var quickSubtaskEditor: QuickSubtaskEditorTarget?

    var body: some View {
        VStack(spacing: 0) {
            if showingEditor {
                EditorView(store: store, item: editing) { showingEditor = false; editing = nil }
            } else {
                header
                Divider()
                if store.isLoading {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Загружаем события…").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if store.active.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "calendar.badge.clock").font(.system(size: 38)).foregroundStyle(.secondary)
                        Text(EventUIStrings.emptyTitle).font(.headline)
                        Text(EventUIStrings.emptyMessage)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 310)
                        Button("+ \(EventUIStrings.addEvent)") { add() }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("event.add")
                            .uiSmokeControl(id: "event.add", action: add)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(store.active) { item in row(item) }
                        }
                        .padding(12)
                        .animation(.easeInOut(duration: 0.28), value: store.data.primaryID)
                    }
                    .accessibilityIdentifier("event.list")
                    .uiSmokeControl(id: "event.list")
                }
                Divider()
                footer
            }
        }
        .frame(width: 390, height: 540)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("root.popup")
        .uiSmokeControl(id: "root.popup")
        .onChange(of: store.active.map(\.id)) { activeIDs in
            if let editing, !activeIDs.contains(editing.id) {
                showingEditor = false
                self.editing = nil
            }
        }
        .onAppear { synchronizeSmokeEventActions() }
        .onChange(of: store.data) { _ in synchronizeSmokeEventActions() }
        .sheet(item: $quickSubtaskEditor) { target in
            QuickSubtaskEditorView(store: store, target: target) {
                quickSubtaskEditor = nil
            }
        }
        .alert("Countdown Manager", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("Понятно", role: .cancel) { store.error = nil }
        } message: { Text(store.error ?? "") }
        .confirmationDialog(
            EventUIStrings.deleteEvent,
            isPresented: Binding(
                get: { pendingDeletion != nil },
                set: { if !$0 { pendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Удалить", role: .destructive) {
                confirmDeletion()
            }
            .accessibilityIdentifier("event.delete.confirm")
            Button("Отмена", role: .cancel) { cancelDeletion() }
                .accessibilityIdentifier("event.delete.cancel")
        } message: {
            Text("«\(pendingDeletion?.title ?? "")» будет удалено без возможности восстановления.")
        }
        .onChange(of: pendingDeletion?.id) { eventID in
            guard UISmokeConfiguration.wasRequested else { return }
            if eventID != nil {
                UISmokeControlRegistry.shared.register(
                    id: "event.delete.confirm",
                    action: confirmDeletion,
                    value: nil,
                    isEnabled: true
                )
                UISmokeControlRegistry.shared.register(
                    id: "event.delete.cancel",
                    action: cancelDeletion,
                    value: nil,
                    isEnabled: true
                )
            } else {
                UISmokeControlRegistry.shared.remove(id: "event.delete.confirm")
                UISmokeControlRegistry.shared.remove(id: "event.delete.cancel")
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Countdown Manager").font(.headline)
                Text("\(store.active.count) активных · сегодня и позже").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: add) { Image(systemName: "plus") }
                .help(EventUIStrings.addEvent).accessibilityLabel(EventUIStrings.addEvent)
                .accessibilityIdentifier("event.add")
                .uiSmokeControl(id: "event.add", action: add)
                .disabled(store.isLoading)
        }.padding(16)
    }

    private func row(_ item: Countdown) -> some View {
        let presentation = CountdownRowPresentation(
            item: item,
            today: store.today,
            primaryID: store.data.primaryID
        )
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Text(item.emoji).font(.system(size: 27)).frame(width: 35)
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    if let note = presentation.note, !note.isEmpty {
                        Text(note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            .accessibilityIdentifier("event.note")
                    }
                    Text(presentation.dateAndRemainingLabel)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(presentation.isToday ? Color.accentColor : Color.primary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .accessibilityIdentifier(presentation.isToday ? "event.today" : "event.remaining")
                }
                Spacer(minLength: 4)
                Button { Task { await store.makePrimary(item.id) } } label: {
                    Image(systemName: presentation.isPrimary ? "star.fill" : "star")
                        .foregroundStyle(presentation.isPrimary ? Color.accentColor : .secondary)
                        .scaleEffect(presentation.isPrimary ? 1.12 : 1)
                        .animation(.spring(response: 0.28, dampingFraction: 0.7), value: presentation.isPrimary)
                }
                .buttonStyle(.borderless)
                .help(presentation.isPrimary ? "Основное событие" : "Сделать основным событием")
                .accessibilityLabel("Сделать основным событием: \(item.title)")
                Menu {
                    Button("Добавить подзадачу") {
                        openQuickSubtaskEditor(eventID: item.id, subtask: nil)
                    }
                    .disabled(item.subtasks.count >= Subtask.maximumCount)
                    .accessibilityIdentifier("event.action.add-subtask.\(item.id.uuidString)")
                    Divider()
                    Button("Редактировать событие") { edit(item) }
                    .accessibilityIdentifier("event.action.edit.\(item.id.uuidString)")
                    Button("Удалить событие", role: .destructive) { requestDeletion(item) }
                        .accessibilityIdentifier("event.action.delete.\(item.id.uuidString)")
                } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22)
                .accessibilityLabel("Действия события: \(item.title)")
                .accessibilityIdentifier("event.actions.\(item.id.uuidString)")
            }

            if presentation.completionLabel != nil {
                SubtaskChecklistView(
                    store: store,
                    item: item,
                    presentation: presentation,
                    openQuickSubtaskEditor: openQuickSubtaskEditor
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(presentation.isPrimary ? Color.accentColor.opacity(0.09) : Color.primary.opacity(0.045))
        )
        .animation(.easeInOut(duration: 0.2), value: presentation.isPrimary)
        .accessibilityIdentifier("event.card.\(item.id.uuidString)")
        .uiSmokeControl(id: "event.card.\(item.id.uuidString)", value: { item.title })
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Запускать при входе в macOS", isOn: Binding(
                get: { store.loginStatus == .enabled || store.loginStatus == .requiresApproval },
                set: { store.setLogin($0) }
            )).toggleStyle(.checkbox)
            if store.loginStatus == .requiresApproval {
                Button("Разрешить в настройках macOS…") { SMAppService.openSystemSettingsLoginItems() }
                    .font(.caption)
            }
            HStack {
                Text("Хранится на этом Mac").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu("Приложение") {
                    Button("Открыть папку диагностики…") { store.openDiagnostics() }
                    Divider()
                    Button("Перезапустить") { store.restart() }
                    Divider()
                    Button("Выйти из Countdown Manager") { NSApp.terminate(nil) }
                }.fixedSize()
            }
        }.padding(14)
    }

    private func add() {
        DiagnosticLog.shared.record("editor.open mode=new")
        editing = nil
        showingEditor = true
    }

    private func edit(_ item: Countdown) {
        DiagnosticLog.shared.record("editor.open mode=edit id=\(item.id.uuidString)")
        editing = item
        showingEditor = true
    }

    private func editCurrent(_ eventID: UUID) {
        guard let item = store.active.first(where: { $0.id == eventID }) else { return }
        edit(item)
    }

    private func openQuickSubtaskEditor(eventID: UUID, subtask: Subtask?) {
        quickSubtaskEditor = QuickSubtaskEditorTarget(eventID: eventID, subtask: subtask)
    }

    private func requestDeletion(_ item: Countdown) {
        pendingDeletion = item
    }

    private func requestCurrentDeletion(_ eventID: UUID) {
        guard let item = store.active.first(where: { $0.id == eventID }) else { return }
        requestDeletion(item)
    }

    private func confirmDeletion() {
        guard let id = pendingDeletion?.id else { return }
        pendingDeletion = nil
        Task { await store.delete(id) }
    }

    private func cancelDeletion() {
        pendingDeletion = nil
    }

    private func synchronizeSmokeEventActions() {
        guard UISmokeConfiguration.wasRequested else { return }
        let registry = UISmokeControlRegistry.shared
        let prefixes = ["event.action.add-subtask.", "event.action.edit.", "event.action.delete."]
        let currentIDs = Set(store.active.map(\.id.uuidString))
        for prefix in prefixes {
            for id in registry.ids(withPrefix: prefix) where !currentIDs.contains(String(id.dropFirst(prefix.count))) {
                registry.remove(id: id)
            }
        }
        for item in store.active {
            let eventID = item.id
            registry.register(
                id: "event.action.add-subtask.\(eventID.uuidString)",
                action: { openQuickSubtaskEditor(eventID: eventID, subtask: nil) },
                value: nil,
                isEnabled: item.subtasks.count < Subtask.maximumCount
            )
            registry.register(
                id: "event.action.edit.\(eventID.uuidString)",
                action: { editCurrent(eventID) },
                value: nil,
                isEnabled: true
            )
            registry.register(
                id: "event.action.delete.\(eventID.uuidString)",
                action: { requestCurrentDeletion(eventID) },
                value: nil,
                isEnabled: true
            )
        }
    }
}

private struct SubtaskChecklistView: View {
    let store: Store
    let item: Countdown
    let presentation: CountdownRowPresentation
    let openQuickSubtaskEditor: (UUID, Subtask?) -> Void

    @ObservedObject private var disclosureState: SubtaskDisclosureState
    @State private var hoveredSubtaskID: UUID?

    init(
        store: Store,
        item: Countdown,
        presentation: CountdownRowPresentation,
        openQuickSubtaskEditor: @escaping (UUID, Subtask?) -> Void
    ) {
        self.store = store
        self.item = item
        self.presentation = presentation
        self.openQuickSubtaskEditor = openQuickSubtaskEditor
        _disclosureState = ObservedObject(wrappedValue: store.disclosureState(for: item.id))
    }

    var body: some View {
        let isExpanded = disclosureState.isExpanded
        let completionLabel = presentation.completionLabel ?? "0/0"

        VStack(alignment: .leading, spacing: 5) {
            Button(action: toggleDisclosure) {
                Text(subtaskDisclosureLabel(isExpanded: isExpanded, completion: completionLabel))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Подзадачи: \(completionLabel), \(isExpanded ? "свернуть" : "раскрыть")")
            .accessibilityIdentifier("subtasks.disclosure.\(item.id.uuidString)")
            .uiSmokeControl(
                id: "subtasks.disclosure.\(item.id.uuidString)",
                action: toggleDisclosure,
                value: { disclosureState.isExpanded ? "expanded" : "collapsed" }
            )

            if isExpanded {
                VStack(alignment: .leading, spacing: 5) {
                    subtaskRows(presentation.activeSubtasks)
                    if !presentation.activeSubtasks.isEmpty && !presentation.completedSubtasks.isEmpty {
                        Divider().padding(.leading, 24)
                    }
                    subtaskRows(presentation.completedSubtasks)
                    if item.subtasks.count < Subtask.maximumCount {
                        Button("+ Добавить") {
                            openQuickSubtaskEditor(item.id, nil)
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                        .padding(.leading, 24)
                        .accessibilityLabel("Добавить подзадачу")
                        .accessibilityIdentifier("event.quick-subtask.add.\(item.id.uuidString)")
                        .uiSmokeControl(
                            id: "event.quick-subtask.add.\(item.id.uuidString)",
                            action: { openQuickSubtaskEditor(item.id, nil) }
                        )
                    }
                }
                .accessibilityIdentifier("subtasks.list")
            }
        }
        .animation(.easeInOut(duration: 0.18), value: isExpanded)
    }

    @ViewBuilder
    private func subtaskRows(_ subtasks: [Subtask]) -> some View {
        ForEach(subtasks) { subtask in
            HStack(spacing: 6) {
                Toggle("", isOn: Binding(
                    get: { subtask.isCompleted },
                    set: { _ in Task { await store.toggleSubtask(eventID: item.id, subtaskID: subtask.id) } }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .accessibilityLabel("\(subtask.isCompleted ? "Отметить невыполненной" : "Отметить выполненной"): \(subtask.text)")
                .accessibilityIdentifier("subtask.toggle.\(subtask.id.uuidString)")
                .uiSmokeControl(
                    id: "subtask.toggle.\(subtask.id.uuidString)",
                    action: { Task { await store.toggleSubtask(eventID: item.id, subtaskID: subtask.id) } },
                    value: {
                        let isCompleted = store.active
                            .first(where: { $0.id == item.id })?
                            .subtasks.first(where: { $0.id == subtask.id })?
                            .isCompleted
                        return isCompleted == true ? "completed" : "active"
                    }
                )

                Text(subtask.text)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .strikethrough(subtask.isCompleted)
                    .foregroundStyle(subtask.isCompleted ? Color.secondary : Color.primary)
                    .help(subtask.text)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Menu {
                    Button("Редактировать") {
                        openQuickSubtaskEditor(item.id, subtask)
                    }
                    .accessibilityIdentifier("subtask.action.edit.\(subtask.id.uuidString)")
                    Button("Удалить", role: .destructive) {
                        Task { await store.deleteSubtask(eventID: item.id, subtaskID: subtask.id) }
                    }
                } label: {
                    Image(systemName: "ellipsis").font(.caption)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 20)
                .opacity(hoveredSubtaskID == subtask.id ? 1 : 0.25)
                .accessibilityLabel("Действия подзадачи: \(subtask.text)")
            }
            .onHover { hovering in hoveredSubtaskID = hovering ? subtask.id : nil }
            .accessibilityIdentifier(subtask.isCompleted ? "subtask.completed" : "subtask.active")
            .uiSmokeControl(
                id: "subtask.action.edit.\(subtask.id.uuidString)",
                action: { openCurrentSubtaskEditor(subtask.id) }
            )
        }
    }

    private func toggleDisclosure() {
        disclosureState.setExpanded(!disclosureState.isExpanded)
    }

    private func openCurrentSubtaskEditor(_ subtaskID: UUID) {
        guard let subtask = store.active
            .first(where: { $0.id == item.id })?
            .subtasks.first(where: { $0.id == subtaskID }) else { return }
        openQuickSubtaskEditor(item.id, subtask)
    }
}

private struct QuickSubtaskEditorView: View {
    @ObservedObject var store: Store
    let target: QuickSubtaskEditorTarget
    let done: () -> Void
    @State private var text: String
    @State private var isSaving = false
    @FocusState private var isFocused: Bool

    init(store: Store, target: QuickSubtaskEditorTarget, done: @escaping () -> Void) {
        self.store = store
        self.target = target
        self.done = done
        _text = State(initialValue: target.subtask?.text ?? "")
    }

    private var canSave: Bool {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !cleaned.isEmpty && cleaned.count <= Subtask.maximumTextLength
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(target.subtask == nil ? "Новая подзадача" : "Редактировать подзадачу").font(.headline)
            TextField("Что нужно сделать", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .accessibilityIdentifier("quick-subtask.field")
                .uiSmokeControl(
                    id: "quick-subtask.field",
                    action: focus,
                    value: { text }
                )
            HStack {
                Text("\(text.count)/\(Subtask.maximumTextLength)")
                    .font(.caption)
                    .foregroundStyle(text.count <= Subtask.maximumTextLength ? Color.secondary : Color.red)
                Spacer()
                Button("Отмена", action: done)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSaving)
                    .accessibilityIdentifier("quick-subtask.cancel")
                    .uiSmokeControl(id: "quick-subtask.cancel", action: done)
                Button("Сохранить", action: save)
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave || isSaving)
                .accessibilityIdentifier("quick-subtask.save")
                .uiSmokeControl(id: "quick-subtask.save", action: save)
            }
        }
        .padding(20)
        .frame(width: 340)
        .accessibilityIdentifier("quick-subtask.editor")
        .uiSmokeControl(id: "quick-subtask.editor")
        .onAppear { focus() }
    }

    private func focus() {
        Task { @MainActor in
            await Task.yield()
            isFocused = true
            await Task.yield()
            if UISmokeConfiguration.wasRequested {
                UISmokeControlRegistry.shared.markFocused("quick-subtask.field")
            }
        }
    }

    private func save() {
        guard canSave, !isSaving else { return }
        isSaving = true
        Task {
            let didSave: Bool
            if let subtask = target.subtask {
                didSave = await store.editSubtask(
                    eventID: target.eventID,
                    subtaskID: subtask.id,
                    text: text
                )
            } else {
                didSave = await store.addSubtask(to: target.eventID, text: text)
            }
            if didSave { done() }
            isSaving = false
        }
    }
}

struct EditorView: View {
    @ObservedObject var store: Store
    let item: Countdown?
    let done: () -> Void
    @State private var draft: EventEditorDraft
    @State private var date: Date
    @State private var primary: Bool
    @State private var isSaving = false
    @State private var isEmojiPickerPresented = false
    @FocusState private var focusedField: EditorFocusTarget?

    init(store: Store, item: Countdown?, done: @escaping () -> Void) {
        self.store = store; self.item = item; self.done = done
        _draft = State(initialValue: EventEditorDraft(item: item))
        _date = State(initialValue: item?.date.date() ?? store.tomorrow)
        _primary = State(initialValue: item == nil ? store.active.isEmpty : store.data.primaryID == item?.id)
    }

    private var isCurrentPrimary: Bool { item != nil && store.data.primaryID == item?.id }
    private var minimumDate: Date { item?.date == store.today ? store.today.date() : store.tomorrow }
    private var validDate: Bool { Day(date) > store.today || (item?.date == store.today && Day(date) == store.today) }
    private var canSave: Bool {
        editorCanSave(
            title: draft.title,
            note: draft.note,
            date: Day(date),
            emoji: draft.emoji,
            subtasks: draft.subtasks,
            today: store.today,
            originalDate: item?.date
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(item == nil ? EventUIStrings.newEvent : EventUIStrings.editEvent)
                .font(.headline)
                .padding(.bottom, 12)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Название").font(.caption).foregroundStyle(.secondary)
                            TextField("Например, отпуск", text: $draft.title)
                                .textFieldStyle(.roundedBorder)
                                .focused($focusedField, equals: .title)
                                .accessibilityIdentifier("editor.title")
                                .onTapGesture { isEmojiPickerPresented = false }
                                .uiSmokeControl(
                                    id: "editor.title",
                                    action: { focus(.title, id: "editor.title") },
                                    value: { draft.title }
                                )
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Заметка · необязательно").font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Text("\(draft.note.count)/280").font(.caption2)
                                    .foregroundStyle(draft.note.count <= 280 ? Color.secondary : Color.red)
                            }
                            TextField("Пара слов о событии", text: $draft.note, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .lineLimit(2...3)
                                .accessibilityIdentifier("editor.note")
                                .onTapGesture { isEmojiPickerPresented = false }
                                .focused($focusedField, equals: .note)
                                .uiSmokeControl(
                                    id: "editor.note",
                                    action: { focus(.note, id: "editor.note") },
                                    value: { draft.note }
                                )
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            DatePicker("Дата", selection: $date, in: minimumDate..., displayedComponents: [.date])
                                .datePickerStyle(.field)
                                .accessibilityIdentifier("editor.date")
                                .uiSmokeControl(id: "editor.date", value: { "\(Day(date).year)-\(Day(date).month)-\(Day(date).day)" })
                            Text(dateHelp)
                                .font(.caption).foregroundStyle(validDate ? Color.secondary : Color.red)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Emoji")
                                Button(action: toggleEmojiPicker) {
                                    HStack(spacing: 6) {
                                        Text(draft.emoji).font(.system(size: 23))
                                        Image(systemName: "chevron.down").font(.caption2).foregroundStyle(.secondary)
                                    }
                                    .frame(minWidth: 58)
                                }
                                .buttonStyle(.bordered)
                                .help("Выбрать emoji")
                                .accessibilityLabel("Выбрать emoji, сейчас \(draft.emoji)")
                                .accessibilityIdentifier("editor.emoji.control")
                                .uiSmokeControl(
                                    id: "editor.emoji.control",
                                    action: toggleEmojiPicker,
                                    value: { draft.emoji }
                                )
                                .popover(isPresented: $isEmojiPickerPresented, arrowEdge: .bottom) {
                                    emojiPicker
                                }
                            }
                            HStack(spacing: 7) {
                                ForEach(EventEmojiCatalog.presets, id: \.self) { symbol in
                                    Button(symbol) {
                                        chooseEmoji(symbol)
                                    }
                                    .buttonStyle(.borderless)
                                    .font(.system(size: 23))
                                    .accessibilityLabel("Выбрать \(symbol)")
                                    .accessibilityIdentifier("editor.emoji.preset.\(emojiIdentifier(symbol))")
                                    .uiSmokeControl(
                                        id: "editor.emoji.preset.\(emojiIdentifier(symbol))",
                                        action: { chooseEmoji(symbol) }
                                    )
                                }
                            }
                        }
                        editorSubtasks(scrollProxy: proxy)
                        VStack(alignment: .leading, spacing: 5) {
                            Toggle("Основное — показывать в строке меню", isOn: $primary)
                                .disabled(isCurrentPrimary || store.active.isEmpty)
                            if isCurrentPrimary {
                                Text("Чтобы сменить основное событие, выберите другое.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(EditorLayout.focusRingInset)
                }
                .accessibilityIdentifier("editor.scroll")
                .uiSmokeControl(id: "editor.scroll")
            }
            HStack {
                Button("Отмена", action: cancel)
                .keyboardShortcut(.cancelAction)
                .disabled(isSaving)
                .accessibilityIdentifier("editor.cancel")
                .uiSmokeControl(id: "editor.cancel", action: cancel)
                Spacer()
                Button(action: save) {
                    if isSaving { ProgressView().controlSize(.small) }
                    else { Text("Сохранить") }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave || isSaving)
                .accessibilityIdentifier("editor.save")
                .uiSmokeControl(id: "editor.save", action: save)
            }
            .padding(.top, 12)
        }
        .padding(20)
        .accessibilityIdentifier(item == nil ? "editor.new" : "editor.edit")
        .uiSmokeControl(id: item == nil ? "editor.new" : "editor.edit")
        .onAppear {
            Task { @MainActor in
                await Task.yield()
                focusedField = .title
                await Task.yield()
                if UISmokeConfiguration.wasRequested {
                    UISmokeControlRegistry.shared.markFocused("editor.title")
                }
            }
        }
        .onChange(of: isEmojiPickerPresented) { isPresented in
            guard UISmokeConfiguration.wasRequested else { return }
            if isPresented {
                UISmokeControlRegistry.shared.register(
                    id: "editor.emoji.picker",
                    action: nil,
                    value: { "visible" },
                    isEnabled: true
                )
            } else {
                UISmokeControlRegistry.shared.remove(id: "editor.emoji.picker")
            }
        }
        .environment(\.locale, Locale(identifier: "ru_RU"))
        .environment(\.calendar, Day.calendar)
    }

    private var dateHelp: String {
        if item?.date == store.today {
            return validDate ? "Можно оставить сегодня или перенести событие в будущее." : "Прошлая дата недоступна."
        }
        return validDate ? "Можно выбрать начиная с завтрашнего дня." : "Эта дата уже наступила. Выберите будущую."
    }

    private func editorSubtasks(scrollProxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Подзадачи · необязательно").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(draft.subtasks.count)/\(Subtask.maximumCount)").font(.caption2).foregroundStyle(.secondary)
            }
            ForEach($draft.subtasks) { $subtask in
                HStack(spacing: 7) {
                    if subtask.isCompleted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Выполнена")
                    }
                    TextField("Подзадача", text: $subtask.text)
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: .subtask(subtask.id))
                        .accessibilityIdentifier("editor.subtask.\(subtask.id.uuidString)")
                        .onTapGesture { isEmojiPickerPresented = false }
                        .uiSmokeControl(
                            id: "editor.subtask.\(subtask.id.uuidString)",
                            action: {
                                focus(.subtask(subtask.id), id: "editor.subtask.\(subtask.id.uuidString)")
                            },
                            value: { subtask.text }
                        )
                    Text("\(subtask.text.count)/\(Subtask.maximumTextLength)")
                        .font(.caption2)
                        .foregroundStyle(subtask.text.count <= Subtask.maximumTextLength ? Color.secondary : Color.red)
                        .frame(width: 34, alignment: .trailing)
                    Button(role: .destructive) {
                        draft.subtasks.removeAll { $0.id == subtask.id }
                    } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("Удалить подзадачу")
                    .accessibilityLabel("Удалить подзадачу")
                }
                .id(subtask.id)
            }
            if draft.subtasks.count < Subtask.maximumCount {
                Button("+ Добавить") { addSubtask(scrollProxy: scrollProxy) }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel("Добавить подзадачу")
                .accessibilityIdentifier("editor.subtask.add")
                .uiSmokeControl(
                    id: "editor.subtask.add",
                    action: { addSubtask(scrollProxy: scrollProxy) }
                )
            }
        }
    }

    private var emojiPicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 4), count: 8), spacing: 4) {
            ForEach(EventEmojiCatalog.all, id: \.self) { symbol in
                Button(symbol) {
                    chooseEmoji(symbol)
                }
                .buttonStyle(.plain)
                .font(.system(size: 22))
                .frame(width: 34, height: 32)
                .background(draft.emoji == symbol ? Color.accentColor.opacity(0.16) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityLabel("Выбрать \(symbol)")
                .accessibilityIdentifier("editor.emoji.option.\(emojiIdentifier(symbol))")
                .uiSmokeControl(
                    id: "editor.emoji.option.\(emojiIdentifier(symbol))",
                    action: { chooseEmoji(symbol) }
                )
            }
        }
        .padding(10)
        .accessibilityIdentifier("editor.emoji.picker")
    }

    private func toggleEmojiPicker() {
        isEmojiPickerPresented.toggle()
    }

    private func chooseEmoji(_ symbol: String) {
        _ = draft.replaceEmoji(with: symbol)
        isEmojiPickerPresented = false
    }

    private func addSubtask(scrollProxy: ScrollViewProxy) {
        guard let target = draft.addSubtask(), case let .subtask(id) = target else { return }
        Task { @MainActor in
            await Task.yield()
            withAnimation { scrollProxy.scrollTo(id, anchor: .center) }
            focusedField = target
            await Task.yield()
            if UISmokeConfiguration.wasRequested {
                UISmokeControlRegistry.shared.markFocused("editor.subtask.\(id.uuidString)")
            }
        }
    }

    private func focus(_ target: EditorFocusTarget, id: String) {
        isEmojiPickerPresented = false
        focusedField = target
        Task { @MainActor in
            await Task.yield()
            if UISmokeConfiguration.wasRequested {
                UISmokeControlRegistry.shared.markFocused(id)
            }
        }
    }

    private func cancel() {
        DiagnosticLog.shared.record("editor.cancel mode=\(item == nil ? "new" : "edit")")
        done()
    }

    private func save() {
        guard canSave, !isSaving else { return }
        let countdown = draft.countdown(id: item?.id ?? UUID(), date: Day(date))
        isSaving = true
        Task {
            if await store.save(countdown, primary: primary) { done() }
            isSaving = false
        }
    }

    private func emojiIdentifier(_ symbol: String) -> String {
        symbol.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: "-")
    }
}
