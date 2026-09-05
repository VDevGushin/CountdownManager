import AppKit
import SwiftUI
import ServiceManagement
import CountdownCore

struct ManagerView: View {
    @ObservedObject var store: Store
    @State private var editing: Countdown?
    @State private var showingEditor = false
    @State private var pendingDeletion: Countdown?

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
                        Text("Впереди что-то хорошее").font(.headline)
                        Text("Добавьте событие — и дни до него\nпоявятся в строке меню.")
                            .foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Добавить счётчик") { add() }.buttonStyle(.borderedProminent)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(store.active) { item in row(item) }
                        }.padding(12)
                    }
                }
                Divider()
                footer
            }
        }
        .frame(width: 390, height: 460)
        .alert("Countdown Manager", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("Понятно", role: .cancel) { store.error = nil }
        } message: { Text(store.error ?? "") }
        .confirmationDialog(
            "Удалить счётчик?",
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
            Text("«\(pendingDeletion?.title ?? "")» будет удалён без возможности восстановления.")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Countdown Manager").font(.headline)
                Text("\(store.active.count) активных · только будущие даты").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: add) { Image(systemName: "plus") }
                .help("Добавить счётчик").accessibilityLabel("Добавить счётчик")
                .disabled(store.isLoading)
        }.padding(16)
    }

    private func row(_ item: Countdown) -> some View {
        HStack(spacing: 10) {
            Text(item.emoji).font(.system(size: 27)).frame(width: 35)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                Text(item.date.date(), format: .dateTime.day().month(.wide).year())
                    .font(.caption).foregroundStyle(.secondary)
                Text(dayLabel(item.date.days(from: store.today)))
                    .font(.system(size: 16, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            Spacer(minLength: 4)
            Button { Task { await store.makePrimary(item.id) } } label: {
                Image(systemName: store.data.primaryID == item.id ? "star.fill" : "star")
                    .foregroundStyle(store.data.primaryID == item.id ? Color.accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .help(store.data.primaryID == item.id ? "Основной счётчик" : "Сделать основным")
            .accessibilityLabel("Сделать основным: \(item.title)")
            Menu {
                Button("Редактировать") {
                    DiagnosticLog.shared.record("editor.open mode=edit id=\(item.id.uuidString)")
                    editing = item
                    showingEditor = true
                }
                Button("Удалить", role: .destructive) { pendingDeletion = item }
            } label: { Image(systemName: "ellipsis") }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 22)
            .accessibilityLabel("Действия: \(item.title)")
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.045)))
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

struct EditorView: View {
    @ObservedObject var store: Store
    let item: Countdown?
    let done: () -> Void
    @State private var title: String
    @State private var date: Date
    @State private var emoji: String
    @State private var primary: Bool
    @State private var isSaving = false
    @FocusState private var titleFocused: Bool

    init(store: Store, item: Countdown?, done: @escaping () -> Void) {
        self.store = store; self.item = item; self.done = done
        _title = State(initialValue: item?.title ?? "")
        _date = State(initialValue: item?.date.date() ?? store.tomorrow)
        _emoji = State(initialValue: item?.emoji ?? "🎉")
        _primary = State(initialValue: item == nil ? store.active.isEmpty : store.data.primaryID == item?.id)
    }

    private var isCurrentPrimary: Bool { item != nil && store.data.primaryID == item?.id }
    private var validDate: Bool { Day(date) > store.today }
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && validDate
            && CountdownData.isEmoji(emoji.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(item == nil ? "Новый счётчик" : "Редактировать счётчик").font(.headline)
            VStack(alignment: .leading, spacing: 6) {
                Text("Название").font(.caption).foregroundStyle(.secondary)
                TextField("Например, до отпуска", text: $title).textFieldStyle(.roundedBorder).focused($titleFocused)
            }
            VStack(alignment: .leading, spacing: 6) {
                DatePicker("Дата", selection: $date, in: store.tomorrow..., displayedComponents: [.date])
                    .datePickerStyle(.field)
                Text(validDate ? "Можно выбрать начиная с завтрашнего дня." : "Эта дата уже наступила. Выберите будущую.")
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
            VStack(alignment: .leading, spacing: 5) {
                Toggle("Основной — показывать в строке меню", isOn: $primary)
                    .disabled(isCurrentPrimary || store.active.isEmpty)
                if isCurrentPrimary {
                    Text("Чтобы сменить основной, выберите другой счётчик.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            HStack {
                Button("Отмена") {
                    DiagnosticLog.shared.record("editor.cancel mode=\(item == nil ? "new" : "edit")")
                    done()
                }.keyboardShortcut(.cancelAction).disabled(isSaving)
                Spacer()
                Button {
                    let countdown = Countdown(id: item?.id ?? UUID(), title: title, date: Day(date), emoji: emoji)
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
        }
        .padding(20)
        .onAppear { titleFocused = true }
        .environment(\.locale, Locale(identifier: "ru_RU"))
        .environment(\.calendar, Day.calendar)
    }
}
