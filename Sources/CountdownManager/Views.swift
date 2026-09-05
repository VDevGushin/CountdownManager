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
    @State private var hoveredSubtaskID: UUID?

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
                        Button("+ \(EventUIStrings.addEvent)") { add() }.buttonStyle(.borderedProminent)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(store.active) { item in row(item) }
                        }
                        .padding(12)
                        .animation(.easeInOut(duration: 0.28), value: store.data.primaryID)
                    }
                }
                Divider()
                footer
            }
        }
        .frame(width: 390, height: 540)
        .onChange(of: store.active.map(\.id)) { activeIDs in
            if let editing, !activeIDs.contains(editing.id) {
                showingEditor = false
                self.editing = nil
            }
        }
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
                guard let id = pendingDeletion?.id else { return }
                pendingDeletion = nil
                Task { await store.delete(id) }
            }
            Button("Отмена", role: .cancel) { pendingDeletion = nil }
        } message: {
            Text("«\(pendingDeletion?.title ?? "")» будет удалено без возможности восстановления.")
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
                .disabled(store.isLoading)
        }.padding(16)
    }

    private func row(_ item: Countdown) -> some View {
        let presentation = CountdownRowPresentation(
            item: item,
            today: store.today,
            primaryID: store.data.primaryID
        )
        let isExpanded = store.subtasksAreExpanded(for: item.id)
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
                        quickSubtaskEditor = QuickSubtaskEditorTarget(eventID: item.id, subtask: nil)
                    }
                    .disabled(item.subtasks.count >= Subtask.maximumCount)
                    Divider()
                    Button("Редактировать событие") {
                        DiagnosticLog.shared.record("editor.open mode=edit id=\(item.id.uuidString)")
                        editing = item
                        showingEditor = true
                    }
                    Button("Удалить событие", role: .destructive) { pendingDeletion = item }
                } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22)
                .accessibilityLabel("Действия события: \(item.title)")
            }

            if let completionLabel = presentation.completionLabel {
                Button {
                    store.setSubtasksExpanded(!isExpanded, for: item.id)
                } label: {
                    Text(subtaskDisclosureLabel(isExpanded: isExpanded, completion: completionLabel))
                        .font(.caption)
                        .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Подзадачи: \(completionLabel), \(isExpanded ? "свернуть" : "раскрыть")")
                .accessibilityIdentifier(isExpanded ? "subtasks.expanded" : "subtasks.collapsed")

                if isExpanded {
                    VStack(alignment: .leading, spacing: 5) {
                        subtaskRows(presentation.activeSubtasks, eventID: item.id)
                        if !presentation.activeSubtasks.isEmpty && !presentation.completedSubtasks.isEmpty {
                            Divider().padding(.leading, 24)
                        }
                        subtaskRows(presentation.completedSubtasks, eventID: item.id)
                        if item.subtasks.count < Subtask.maximumCount {
                            Button("+ Добавить") {
                                quickSubtaskEditor = QuickSubtaskEditorTarget(eventID: item.id, subtask: nil)
                            }
                            .buttonStyle(.plain)
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                            .padding(.leading, 24)
                            .accessibilityLabel("Добавить подзадачу")
                        }
                    }
                    .accessibilityIdentifier("subtasks.list")
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(presentation.isPrimary ? Color.accentColor.opacity(0.09) : Color.primary.opacity(0.045))
        )
        .animation(.easeInOut(duration: 0.2), value: presentation.isPrimary)
        .animation(.easeInOut(duration: 0.18), value: isExpanded)
    }

    @ViewBuilder
    private func subtaskRows(_ subtasks: [Subtask], eventID: UUID) -> some View {
        ForEach(subtasks) { subtask in
            HStack(spacing: 6) {
                Toggle("", isOn: Binding(
                    get: { subtask.isCompleted },
                    set: { _ in Task { await store.toggleSubtask(eventID: eventID, subtaskID: subtask.id) } }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .accessibilityLabel("\(subtask.isCompleted ? "Отметить невыполненной" : "Отметить выполненной"): \(subtask.text)")

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
                        quickSubtaskEditor = QuickSubtaskEditorTarget(eventID: eventID, subtask: subtask)
                    }
                    Button("Удалить", role: .destructive) {
                        Task { await store.deleteSubtask(eventID: eventID, subtaskID: subtask.id) }
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
        }
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
            HStack {
                Text("\(text.count)/\(Subtask.maximumTextLength)")
                    .font(.caption)
                    .foregroundStyle(text.count <= Subtask.maximumTextLength ? Color.secondary : Color.red)
                Spacer()
                Button("Отмена", action: done).keyboardShortcut(.cancelAction).disabled(isSaving)
                Button("Сохранить") {
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
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave || isSaving)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear { isFocused = true }
    }
}

struct EditorView: View {
    @ObservedObject var store: Store
    let item: Countdown?
    let done: () -> Void
    @State private var title: String
    @State private var note: String
    @State private var date: Date
    @State private var emoji: String
    @State private var subtasks: [Subtask]
    @State private var primary: Bool
    @State private var isSaving = false
    @FocusState private var titleFocused: Bool

    init(store: Store, item: Countdown?, done: @escaping () -> Void) {
        self.store = store; self.item = item; self.done = done
        _title = State(initialValue: item?.title ?? "")
        _note = State(initialValue: item?.note ?? "")
        _date = State(initialValue: item?.date.date() ?? store.tomorrow)
        _emoji = State(initialValue: item?.emoji ?? "🎉")
        _subtasks = State(initialValue: item?.subtasks ?? [])
        _primary = State(initialValue: item == nil ? store.active.isEmpty : store.data.primaryID == item?.id)
    }

    private var isCurrentPrimary: Bool { item != nil && store.data.primaryID == item?.id }
    private var minimumDate: Date { item?.date == store.today ? store.today.date() : store.tomorrow }
    private var validDate: Bool { Day(date) > store.today || (item?.date == store.today && Day(date) == store.today) }
    private var canSave: Bool {
        editorCanSave(
            title: title,
            note: note,
            date: Day(date),
            emoji: emoji,
            subtasks: subtasks,
            today: store.today,
            originalDate: item?.date
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(item == nil ? EventUIStrings.newEvent : EventUIStrings.editEvent)
                .font(.headline)
                .padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Название").font(.caption).foregroundStyle(.secondary)
                        TextField("Например, отпуск", text: $title).textFieldStyle(.roundedBorder).focused($titleFocused)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Заметка · необязательно").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text("\(note.count)/280").font(.caption2)
                                .foregroundStyle(note.count <= 280 ? Color.secondary : Color.red)
                        }
                        TextField("Пара слов о событии", text: $note, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                            .lineLimit(2...3)
                            .accessibilityIdentifier("editor.note")
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        DatePicker("Дата", selection: $date, in: minimumDate..., displayedComponents: [.date])
                            .datePickerStyle(.field)
                        Text(dateHelp)
                            .font(.caption).foregroundStyle(validDate ? Color.secondary : Color.red)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Emoji")
                            TextField("🎉", text: $emoji).textFieldStyle(.roundedBorder).frame(width: 64)
                            Button { NSApp.orderFrontCharacterPalette(nil) } label: { Image(systemName: "face.smiling") }
                                .help("Открыть панель emoji").accessibilityLabel("Открыть панель emoji")
                        }
                        HStack(spacing: 7) {
                            ForEach(["☀️", "✈️", "🎉", "🎂", "🎄", "❤️", "🚀", "🏖️"], id: \.self) { symbol in
                                Button(symbol) { emoji = symbol }.buttonStyle(.borderless).font(.system(size: 23))
                            }
                        }
                    }
                    editorSubtasks
                    VStack(alignment: .leading, spacing: 5) {
                        Toggle("Основное — показывать в строке меню", isOn: $primary)
                            .disabled(isCurrentPrimary || store.active.isEmpty)
                        if isCurrentPrimary {
                            Text("Чтобы сменить основное событие, выберите другое.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.trailing, 4)
            }
            HStack {
                Button("Отмена") {
                    DiagnosticLog.shared.record("editor.cancel mode=\(item == nil ? "new" : "edit")")
                    done()
                }.keyboardShortcut(.cancelAction).disabled(isSaving)
                Spacer()
                Button {
                    let countdown = Countdown(
                        id: item?.id ?? UUID(),
                        title: title,
                        note: note,
                        date: Day(date),
                        emoji: emoji,
                        subtasks: subtasks
                    )
                    isSaving = true
                    Task {
                        if await store.save(countdown, primary: primary) { done() }
                        isSaving = false
                    }
                } label: {
                    if isSaving { ProgressView().controlSize(.small) }
                    else { Text("Сохранить") }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave || isSaving)
            }
            .padding(.top, 12)
        }
        .padding(20)
        .onAppear { titleFocused = true }
        .environment(\.locale, Locale(identifier: "ru_RU"))
        .environment(\.calendar, Day.calendar)
    }

    private var dateHelp: String {
        if item?.date == store.today {
            return validDate ? "Можно оставить сегодня или перенести событие в будущее." : "Прошлая дата недоступна."
        }
        return validDate ? "Можно выбрать начиная с завтрашнего дня." : "Эта дата уже наступила. Выберите будущую."
    }

    private var editorSubtasks: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Подзадачи · необязательно").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("\(subtasks.count)/\(Subtask.maximumCount)").font(.caption2).foregroundStyle(.secondary)
            }
            ForEach($subtasks) { $subtask in
                HStack(spacing: 7) {
                    Toggle("", isOn: $subtask.isCompleted).labelsHidden().toggleStyle(.checkbox)
                        .accessibilityLabel("Подзадача выполнена")
                    TextField("Подзадача", text: $subtask.text)
                        .textFieldStyle(.roundedBorder)
                    Text("\(subtask.text.count)/\(Subtask.maximumTextLength)")
                        .font(.caption2)
                        .foregroundStyle(subtask.text.count <= Subtask.maximumTextLength ? Color.secondary : Color.red)
                        .frame(width: 34, alignment: .trailing)
                    Button(role: .destructive) {
                        subtasks.removeAll { $0.id == subtask.id }
                    } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help("Удалить подзадачу")
                    .accessibilityLabel("Удалить подзадачу")
                }
            }
            if subtasks.count < Subtask.maximumCount {
                Button("+ Добавить") {
                    var draft = try! Subtask(text: "Новая подзадача")
                    draft.text = ""
                    subtasks.append(draft)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel("Добавить подзадачу")
            }
        }
    }
}
