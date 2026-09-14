import AppKit
import SwiftUI
import ServiceManagement
import CountdownCore

struct ManagerView: View {
    @ObservedObject var store: Store
    @State private var editing: Countdown?
    @State private var showingEditor = false
    @State private var rootIdentity = UUID()

    var body: some View {
        VStack(spacing: 0) {
            if let error = store.error {
                VStack(alignment: .leading, spacing: 6) {
                    Text(error).font(.caption).textSelection(.enabled)
                    Button("Понятно") { store.error = nil }
                }.padding(10)
                .accessibilityIdentifier("application.error")
                .uiSmokeControl(id: "application.error", value: { store.error })
            }
            ZStack {
                listScreen
                    .opacity(showingEditor ? 0 : 1)
                    .disabled(showingEditor)
                    .allowsHitTesting(!showingEditor)
                    .accessibilityHidden(showingEditor)
                if showingEditor {
                    EditorView(store: store, item: editing, done: finishEditor)
                }
            }
        }
        .frame(width: 390, height: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("root.window")
        .uiSmokeControl(id: "root.window", value: { rootIdentity.uuidString })
    }

    private var listScreen: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 8) {
                    if store.isLoading {
                        ProgressView("Загружаем события…")
                    } else if store.active.isEmpty {
                        Text(EventUIStrings.emptyTitle).font(.headline)
                        Text(EventUIStrings.emptyMessage).foregroundStyle(.secondary)
                    }
                    ForEach(store.active) { item in row(item) }
                }
                .padding(12)
                .animation(.easeInOut(duration: 0.2), value: store.data.primaryID)
            }
            .accessibilityIdentifier("event.list")
            .uiSmokeControl(id: "event.list")
            Divider()
            footer
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
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(presentation.isPrimary ? "Основное событие" : "Сделать основным событием")
                .accessibilityIdentifier("event.primary.\(item.id.uuidString)")
                .accessibilityLabel("Сделать основным событием: \(item.title)")
                Button { edit(item) } label: {
                    Image(systemName: "pencil").frame(width: 28, height: 28)
                }
                .accessibilityLabel("Редактировать событие: \(item.title)")
                .accessibilityIdentifier("event.edit.\(item.id.uuidString)")
                .uiSmokeControl(id: "event.edit.\(item.id.uuidString)", action: { edit(item) })
            }

            if presentation.completionLabel != nil {
                SubtaskChecklistView(
                    store: store,
                    item: item,
                    presentation: presentation
                )
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(presentation.isPrimary ? Color.accentColor.opacity(0.09) : Color.primary.opacity(0.045))
        )
        .accessibilityElement(children: .contain)
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
                Button("Диагностика…") { store.openDiagnostics() }
                Button("Выйти") { NSApp.terminate(nil) }
            }
        }.padding(14)
    }

    private func finishEditor() {
        showingEditor = false
        editing = nil
    }

    private func add() {
        guard !showingEditor else { return }
        DiagnosticLog.shared.record("editor.open mode=new")
        editing = nil
        showingEditor = true
    }

    private func edit(_ item: Countdown) {
        guard !showingEditor else { return }
        DiagnosticLog.shared.record("editor.open mode=edit id=\(item.id.uuidString)")
        editing = item
        showingEditor = true
    }
}

private struct SubtaskChecklistView: View {
    let store: Store
    let item: Countdown
    let presentation: CountdownRowPresentation

    @ObservedObject private var disclosureState: SubtaskDisclosureState

    init(
        store: Store,
        item: Countdown,
        presentation: CountdownRowPresentation
    ) {
        self.store = store
        self.item = item
        self.presentation = presentation
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

                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("subtasks.list")
            }
        }
        .animation(.easeInOut(duration: 0.2), value: item.subtasks.map(\.isCompleted))
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

            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(subtask.isCompleted ? "subtask.completed" : "subtask.active")
        }
    }

    private func toggleDisclosure() {
        disclosureState.setExpanded(!disclosureState.isExpanded)
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
    @State private var confirmingDeletion = false
    @State private var showingMoreEmoji = false
    @State private var emojiPage = 0
    @FocusState private var focusedField: EditorFocusTarget?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let emojiRows = [
        ["☀️", "✈️", "🎉", "🎂", "🎄", "❤️", "🚀", "🏖️", "🌟", "🎁", "🏆", "🎓", "🎈", "🎊", "🎆", "🎇", "🪩", "🎯", "💎", "👑", "💍", "🍼", "🏡", "🗓️"],
        ["😀", "😄", "😁", "😊", "😍", "🥳", "😎", "🤩", "😂", "🥰", "🤗", "😇", "🙂", "😉", "😋", "🤓", "🫠", "🥹", "😴", "🤠", "🥸", "🤯", "😱", "😭"],
        ["💙", "💚", "💜", "🧡", "💛", "🤍", "🩷", "🩵", "🩶", "🖤", "💕", "💞", "💓", "💗", "💖", "💘", "💝", "💟", "👍", "👏", "🙌", "🤝", "✌️", "🤞"],
        ["🌈", "❄️", "🌸", "🌻", "🍀", "🌊", "🌙", "🔥", "✨", "⭐️", "🌺", "🌷", "🌹", "🌼", "🌿", "🌴", "🌵", "🍁", "🍂", "🌧️", "⛈️", "🌤️", "🌅", "🌌"],
        ["⚽️", "🏀", "🏈", "⚾️", "🎾", "🏐", "🏓", "🏸", "🥊", "⛳️", "🎮", "🎵", "🎸", "🎤", "🎬", "📚", "💡", "🚗", "🚲", "🚂", "🚢", "🚁", "🏕️", "🏔️"],
        ["🐶", "🐱", "🦄", "🐼", "🦊", "🐻", "🐨", "🐯", "🦁", "🐸", "🐵", "🦋", "🐝", "🍕", "🍔", "🍣", "🍩", "🍪", "🍓", "🍉", "☕️", "🍷", "🥂", "🍰"]
    ]

    private static let emojiColumnsPerPage = 8
    private static let emojiCellWidth: CGFloat = 34
    private static let emojiCellHeight: CGFloat = 32
    private static let emojiSpacing: CGFloat = 7
    private static var emojiPageCount: Int { emojiRows[0].count / emojiColumnsPerPage }
    private static var emojiPageWidth: CGFloat {
        emojiCellWidth * CGFloat(emojiColumnsPerPage)
            + emojiSpacing * CGFloat(emojiColumnsPerPage - 1)
    }
    private static var emojiExpandedHeight: CGFloat {
        emojiCellHeight * CGFloat(emojiRows.count)
            + emojiSpacing * CGFloat(emojiRows.count - 1)
    }

    init(store: Store, item: Countdown?, done: @escaping () -> Void) {
        self.store = store; self.item = item; self.done = done
        _draft = State(initialValue: EventEditorDraft(item: item))
        _date = State(initialValue: item?.date.date() ?? store.tomorrow)
        _primary = State(initialValue: item == nil ? store.active.isEmpty : store.data.primaryID == item?.id)
    }

    private var isCurrentPrimary: Bool { item != nil && store.data.primaryID == item?.id }
    private var minimumDate: Date { item?.date == store.today ? store.today.date() : store.tomorrow }
    private var validDate: Bool { Day(date) > store.today || (item?.date == store.today && Day(date) == store.today) }
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
                        emojiControls
                        editorSubtasks(scrollProxy: proxy)
                        VStack(alignment: .leading, spacing: 5) {
                            Toggle("Основное — показывать в строке меню", isOn: $primary)
                                .disabled(isCurrentPrimary || store.active.isEmpty)
                            if isCurrentPrimary {
                                Text("Чтобы сменить основное событие, выберите другое.").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding([.top, .bottom, .leading], EditorLayout.focusRingInset)
                    .padding(
                        .trailing,
                        EditorLayout.focusRingInset + EditorLayout.scrollIndicatorClearance
                    )
                }
                .accessibilityIdentifier("editor.scroll")
                .uiSmokeControl(id: "editor.scroll")
            }
            .disabled(isSaving)
            VStack(alignment: .leading, spacing: 12) {
                if isUnavailable {
                    Text("Событие больше недоступно. Черновик сохранён в этом окне; сохранить его как это событие нельзя.")
                        .font(.caption).foregroundStyle(.secondary)
                        .accessibilityIdentifier("editor.unavailable")
                        .uiSmokeControl(id: "editor.unavailable")
                }
                if item != nil && !isUnavailable {
                    deletionControls
                }
                HStack {
                    Button("Отмена", action: cancel)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("editor.cancel")
                    .uiSmokeControl(id: "editor.cancel", action: cancel)
                    .disabled(isSaving)
                    Spacer()
                    Button(action: save) {
                        if isSaving { ProgressView().controlSize(.small) }
                        else { Text("Сохранить") }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("editor.save")
                    .uiSmokeControl(id: "editor.save", action: save)
                    .disabled(!canSave || isSaving || confirmingDeletion)
                }
            }
            .padding(.top, EditorLayout.actionAreaSpacing)
        }
        .padding(20)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(item == nil ? "editor.new" : "editor.edit")
        .uiSmokeControl(id: item == nil ? "editor.new" : "editor.edit")
        .task {
            await Task.yield()
            focusedField = .title
            await Task.yield()
            if UISmokeConfiguration.wasRequested {
                UISmokeControlRegistry.shared.markFocused("editor.title")
            }
        }
        .environment(\.locale, Locale(identifier: "ru_RU"))
        .environment(\.calendar, Day.calendar)
    }

    private var deletionControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            if confirmingDeletion {
                Text("Удалить событие без возможности восстановления?").font(.caption)
                HStack {
                    Button("Не удалять") { confirmingDeletion = false }
                        .accessibilityIdentifier("event.delete.cancel")
                        .uiSmokeControl(id: "event.delete.cancel", action: { confirmingDeletion = false })
                    Button("Удалить", role: .destructive, action: delete)
                        .accessibilityIdentifier("event.delete.confirm")
                        .uiSmokeControl(id: "event.delete.confirm", action: delete)
                }
            } else {
                Button("Удалить событие", role: .destructive) { confirmingDeletion = true }
                    .accessibilityIdentifier("event.delete")
                    .uiSmokeControl(id: "event.delete", action: { confirmingDeletion = true })
            }
        }.disabled(isSaving)
    }

    private func delete() {
        guard let item, !isUnavailable, !isSaving else { return }
        isSaving = true
        Task {
            if await store.delete(item.id) { done() }
            isSaving = false
        }
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
                    } label: {
                        Image(systemName: "trash")
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
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

    private var emojiControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Emoji").font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text(draft.emoji)
                    .font(.system(size: 26))
                    .frame(width: 36, height: 32)
                    .accessibilityLabel("Emoji события")
                    .accessibilityIdentifier("editor.emoji")
                    .uiSmokeControl(id: "editor.emoji", value: { draft.emoji })
                Button(showingMoreEmoji ? "Скрыть" : "Ещё…", action: toggleMoreEmoji)
                    .accessibilityLabel(
                        showingMoreEmoji ? "Скрыть расширенный выбор emoji" : "Показать больше emoji"
                    )
                    .accessibilityIdentifier("editor.emoji.more")
                    .uiSmokeControl(
                        id: "editor.emoji.more",
                        action: toggleMoreEmoji,
                        value: { showingMoreEmoji ? "expanded" : "collapsed" }
                    )
            }

            if showingMoreEmoji {
                expandedEmojiPicker
                    .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                HStack(spacing: Self.emojiSpacing) {
                    ForEach(EventEmojiCatalog.presets, id: \.self) { symbol in
                        emojiButton(symbol, identifierPrefix: "editor.emoji.preset")
                    }
                }
                .frame(height: Self.emojiCellHeight, alignment: .top)
                .accessibilityIdentifier("editor.emoji.quick")
                .uiSmokeControl(id: "editor.emoji.quick", value: { "1x8" })
                .transition(.opacity)
            }
        }
    }

    private var expandedEmojiPicker: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(0..<Self.emojiPageCount, id: \.self) { page in
                    emojiPageGrid(page)
                        .frame(width: Self.emojiPageWidth, alignment: .leading)
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
            .accessibilityIdentifier("editor.emoji.expanded")
            .uiSmokeControl(
                id: "editor.emoji.expanded",
                value: { "6x8 page \(emojiPage + 1)/\(Self.emojiPageCount)" }
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
                            identifierPrefix: row == 0 && column < EventEmojiCatalog.presets.count
                                ? "editor.emoji.preset"
                                : "editor.emoji.option"
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
            .help("Предыдущая страница emoji")
            .accessibilityLabel("Предыдущая страница emoji")
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
                            .frame(width: 14, height: 20)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        page == emojiPage
                            ? "Страница \(page + 1) из \(Self.emojiPageCount), текущая"
                            : "Перейти на страницу \(page + 1) из \(Self.emojiPageCount)"
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
            .help("Следующая страница emoji")
            .accessibilityLabel("Следующая страница emoji")
            .accessibilityIdentifier("editor.emoji.page.next")
            .uiSmokeControl(id: "editor.emoji.page.next", action: nextEmojiPage)
            .disabled(emojiPage == Self.emojiPageCount - 1)
        }
        .frame(width: Self.emojiPageWidth, alignment: .center)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("editor.emoji.pagination")
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

    private func emojiButton(_ symbol: String, identifierPrefix: String) -> some View {
        Button(symbol) {
            chooseEmoji(symbol)
        }
        .buttonStyle(.plain)
        .font(.system(size: 22))
        .frame(width: Self.emojiCellWidth, height: Self.emojiCellHeight)
        .background(draft.emoji == symbol ? Color.accentColor.opacity(0.16) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityLabel("Выбрать \(symbol)")
        .accessibilityIdentifier("\(identifierPrefix).\(emojiIdentifier(symbol))")
        .uiSmokeControl(
            id: "\(identifierPrefix).\(emojiIdentifier(symbol))",
            action: { chooseEmoji(symbol) }
        )
    }

    private func chooseEmoji(_ symbol: String) {
        guard CountdownData.isEmoji(symbol) else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            _ = draft.replaceEmoji(with: symbol)
            emojiPage = 0
            showingMoreEmoji = false
        }
    }

    private func toggleMoreEmoji() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            emojiPage = 0
            showingMoreEmoji.toggle()
        }
    }

    private func setEmojiPage(_ page: Int) {
        guard showingMoreEmoji else { return }
        let boundedPage = min(max(page, 0), Self.emojiPageCount - 1)
        guard boundedPage != emojiPage else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
            emojiPage = boundedPage
        }
    }

    private func previousEmojiPage() {
        setEmojiPage(emojiPage - 1)
    }

    private func nextEmojiPage() {
        setEmojiPage(emojiPage + 1)
    }

    private func addSubtask(scrollProxy: ScrollViewProxy) {
        guard let target = draft.addSubtask(), case let .subtask(id) = target else { return }
        Task { @MainActor in
            await Task.yield()
            scrollProxy.scrollTo(id, anchor: .center)
            focusedField = target
            await Task.yield()
            if UISmokeConfiguration.wasRequested {
                UISmokeControlRegistry.shared.markFocused("editor.subtask.\(id.uuidString)")
            }
        }
    }

    private func focus(_ target: EditorFocusTarget, id: String) {
        focusedField = target
        Task { @MainActor in
            await Task.yield()
            if UISmokeConfiguration.wasRequested {
                UISmokeControlRegistry.shared.markFocused(id)
            }
        }
    }

    private func cancel() {
        guard !isSaving else { return }
        DiagnosticLog.shared.record("editor.cancel mode=\(item == nil ? "new" : "edit")")
        done()
    }

    private func save() {
        guard canSave, !isSaving, !confirmingDeletion else { return }
        if let item, item.date < Day(Date()) {
            store.refresh()
            return
        }
        let countdown = draft.countdown(id: item?.id ?? UUID(), date: Day(date))
        isSaving = true
        Task {
            if await store.save(countdown, primary: primary, requireExisting: item != nil) { done() }
            isSaving = false
        }
    }

    private func emojiIdentifier(_ symbol: String) -> String {
        symbol.unicodeScalars.map { String($0.value, radix: 16) }.joined(separator: "-")
    }
}
