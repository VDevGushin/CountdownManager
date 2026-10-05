import AppKit
import SwiftUI
import ServiceManagement
import CountdownCore

struct ManagerView: View {
    @ObservedObject var store: Store
    @State private var editing: Countdown?
    @State private var showingEditor = false
    @State private var showingDayChoices = false
    @State private var dayPreset: DayCreationPreset?
    @State private var selectDayDate = false
    @State private var rootIdentity = UUID()
    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @Environment(\.colorScheme) private var colorScheme

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
                    .opacity(showingEditor ? 0 : 1)
                    .disabled(showingEditor)
                    .allowsHitTesting(!showingEditor)
                    .accessibilityHidden(showingEditor)
                if showingEditor {
                    EditorView(
                        store: store,
                        item: editing,
                        dayPreset: dayPreset,
                        selectDayDate: selectDayDate,
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
    }

    private var listScreen: some View {
        let displayed = store.active
        let featuredID = displayed.first?.id
        return VStack(spacing: 0) {
            header(activeCount: displayed.count)
            if showingDayChoices {
                dayChoices
            }
            ScrollView {
                VStack(spacing: 12) {
                    if store.isLoading {
                        VStack(spacing: 12) {
                            AuroraLoadingPlaceholder()
                            ProgressView("Загружаем события…")
                        }
                    } else if displayed.isEmpty {
                        HStack(alignment: .top, spacing: 12) {
                            AuroraEmptyMark()
                            VStack(alignment: .leading, spacing: 4) {
                                Text(EventUIStrings.emptyTitle)
                                    .font(.system(size: 13, weight: .semibold))
                                Text(EventUIStrings.emptyMessage)
                                    .font(.system(size: 12))
                                    .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                            }
                        }
                    }
                    ForEach(displayed) { item in row(item, featuredID: featuredID) }
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
            Divider()
            footer
        }
    }

    private func header(activeCount: Int) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Countdown Manager").font(.custom("Georgia", size: 22))
                    .tracking(-0.8)
                Text("\(activeCount) активных · сегодня и позже")
                    .font(.system(size: 11))
                    .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
            }
            Spacer()
            Button(action: toggleDayChoices) {
                Image(systemName: "calendar.badge.plus")
                    .frame(width: 31, height: 31)
                    .background(AuroraInstrument.stroke(for: colorScheme, highContrast: false).opacity(0.25),
                                in: RoundedRectangle(cornerRadius: 8))
            }
                .buttonStyle(.plain)
                .help(EventUIStrings.createDay).accessibilityLabel(EventUIStrings.createDay)
                .accessibilityIdentifier("day.add")
                .uiSmokeControl(id: "day.add", action: toggleDayChoices)
                .disabled(store.isLoading)
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
                .disabled(store.isLoading)
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var dayChoices: some View {
        HStack {
            Text(EventUIStrings.createDay).font(.caption).foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
            Spacer()
            Button("Завтра") { createDay(selectDate: false) }
                .accessibilityIdentifier("creation.day.tomorrow")
                .uiSmokeControl(id: "creation.day.tomorrow", action: { createDay(selectDate: false) })
            Button("Выбрать дату") { createDay(selectDate: true) }
                .accessibilityIdentifier("creation.day.chooseDate")
                .uiSmokeControl(id: "creation.day.chooseDate", action: { createDay(selectDate: true) })
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .disabled(store.isLoading)
    }

    private var plannerAccent: Color {
        AuroraInstrument.accent(for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast)
    }

    private var plannerRule: Color {
        AuroraInstrument.stroke(for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast)
    }

    private func row(_ item: Countdown, featuredID: UUID?) -> some View {
        let presentation = CountdownRowPresentation(
            item: item,
            today: store.today,
            primaryID: store.data.primaryID,
            featuredID: featuredID
        )
        return VStack(alignment: .leading, spacing: 0) {
            if presentation.isFeatured {
                featuredEvent(item, presentation: presentation)
            } else {
                secondaryEvent(item, presentation: presentation)
            }
            if presentation.completionLabel != nil {
                SubtaskChecklistView(store: store, item: item, presentation: presentation)
                    .padding(.top, 10)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(presentation.isPrimary ? "Основное событие" : "Ближайшее событие")
                    .accessibilityIdentifier("event.featured.label.\(item.id.uuidString)")
                    .font(.system(size: 11))
                    .tracking(0.6)
                    .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                Spacer()
                eventActions(item, presentation: presentation)
            }
            HStack(alignment: .center, spacing: 15) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(item.title)
                        .font(.custom("Georgia", size: 28))
                        .tracking(-0.8)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(presentation.dateLabel)
                        .font(.system(size: 11))
                        .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                }
                calendarTile(item, isFeatured: true)
            }
            if presentation.isToday {
                Text(presentation.remainingLabel)
                    .font(.custom("Georgia", size: 29))
                    .foregroundStyle(AuroraInstrument.todayColor(
                        for: colorScheme,
                        highContrast: accessibilitySettings.prefersHighContrast
                    ))
                    .accessibilityIdentifier("event.today")
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("\(presentation.remainingDays)")
                        .font(.custom("Georgia", size: 29))
                        .foregroundStyle(AuroraInstrument.accentInk(
                            for: colorScheme,
                            highContrast: accessibilitySettings.prefersHighContrast
                        ))
                    Text("\(presentation.remainingUnit ?? "") до события")
                        .font(.system(size: 12))
                        .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(presentation.remainingLabel)
                .accessibilityIdentifier("event.remaining")
            }
            eventNote(presentation)
        }
    }

    private func secondaryEvent(_ item: Countdown, presentation: CountdownRowPresentation) -> some View {
        HStack(alignment: .center, spacing: 13) {
            calendarTile(item, isFeatured: false)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    eventActions(item, presentation: presentation)
                }
                Text(presentation.dateLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                Text(presentation.remainingLabel)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(presentation.isToday
                        ? AuroraInstrument.todayColor(for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast)
                        : AuroraInstrument.accentInk(for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast))
                    .accessibilityIdentifier(presentation.isToday ? "event.today" : "event.remaining")
                eventNote(presentation)
            }
        }
    }

    private func calendarTile(_ item: Countdown, isFeatured: Bool) -> some View {
        PlannerCalendarDateTile(day: item.date, isFeatured: isFeatured)
            .accessibilityHidden(true)
            .uiSmokeControl(id: "event.calendar.\(item.id.uuidString)", value: { humanDateLabel(item.date) })
    }

    @ViewBuilder
    private func eventNote(_ presentation: CountdownRowPresentation) -> some View {
        if let note = presentation.note, !note.isEmpty {
            Text(note)
                .font(.system(size: 12))
                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                .lineLimit(2)
                .accessibilityIdentifier("event.note")
        }
    }

    private func eventActions(_ item: Countdown, presentation: CountdownRowPresentation) -> some View {
        HStack(spacing: 0) {
            if let emoji = eventListEmoji(item.emoji) {
                Text(emoji).font(.system(size: 18)).frame(width: 28, height: 28)
                    .accessibilityLabel("Значок события: \(emoji)")
            }
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
                value: { store.data.primaryID == item.id ? "Выбрано" : "Не выбрано" }
            )
            Button { edit(item) } label: {
                Image(systemName: "pencil")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
            .accessibilityLabel("Редактировать событие: \(item.title)")
            .accessibilityIdentifier("event.edit.\(item.id.uuidString)")
            .uiSmokeControl(id: "event.edit.\(item.id.uuidString)", action: { edit(item) })
        }
        .fixedSize()
    }

    private func togglePrimary(_ id: UUID) {
        Task {
            if store.data.primaryID == id {
                await store.clearPrimary()
            } else {
                await store.makePrimary(id)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Запускать при входе в macOS", isOn: Binding(
                get: { store.loginStatus == .enabled || store.loginStatus == .requiresApproval },
                set: { store.setLogin($0) }
            ))
            .toggleStyle(.checkbox)
            .disabled(!store.loginItemManagementIsAvailable)
            if store.loginStatus == .requiresApproval {
                Button("Разрешить в настройках macOS…") { store.openLoginItemSettings() }
                    .font(.caption)
                    .disabled(!store.loginItemManagementIsAvailable)
            }
            HStack {
                Text("Хранится на этом Mac").font(.caption).foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                Spacer()
                Button("Диагностика…") { store.openDiagnostics() }
                Button("Выйти") { NSApp.terminate(nil) }
            }
        }
        .font(.system(size: 11))
        .buttonStyle(.plain)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(AuroraPanelCanvas())
    }

    private func finishEditor() {
        showingEditor = false
        editing = nil
        dayPreset = nil
        selectDayDate = false
    }

    private func add() {
        guard !showingEditor else { return }
        DiagnosticLog.shared.record("editor.open mode=new")
        editing = nil
        dayPreset = nil
        selectDayDate = false
        showingDayChoices = false
        showingEditor = true
    }

    private func toggleDayChoices() {
        guard !showingEditor else { return }
        showingDayChoices.toggle()
    }

    private func createDay(selectDate: Bool) {
        guard !showingEditor,
              let preset = DayCreationPreset.tomorrow(after: store.today) else { return }
        DiagnosticLog.shared.record("editor.open mode=day")
        editing = nil
        dayPreset = preset
        selectDayDate = selectDate
        showingDayChoices = false
        showingEditor = true
    }

    private func edit(_ item: Countdown) {
        guard !showingEditor else { return }
        DiagnosticLog.shared.record("editor.open mode=edit id=\(item.id.uuidString)")
        editing = item
        dayPreset = nil
        selectDayDate = false
        showingDayChoices = false
        showingEditor = true
    }
}

private struct PlannerCalendarDateTile: View {
    let day: Day
    let isFeatured: Bool
    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let presentation = CalendarDateTilePresentation(day: day)
        let shape = RoundedRectangle(cornerRadius: isFeatured ? 5 : 4)
        VStack(spacing: 0) {
            Text(presentation.monthLabel)
                .font(.system(size: 11, weight: .semibold))
                .tracking(isFeatured ? 1 : 0.5)
                .foregroundStyle(colorScheme == .dark ? AuroraInstrument.canvas(for: colorScheme) : .white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, isFeatured ? 5 : 3)
                .background(AuroraInstrument.accent(
                    for: colorScheme,
                    highContrast: accessibilitySettings.prefersHighContrast
                ))
            Text(presentation.dayLabel)
                .font(.custom("Georgia", size: isFeatured ? 34 : 23))
                .tracking(-0.5)
                .foregroundStyle(AuroraInstrument.ink(for: colorScheme))
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
                .padding(.bottom, 8)
        }
        .frame(width: isFeatured ? 65 : 46)
        .background(AuroraInstrument.surface(
            for: colorScheme,
            elevated: false,
            highContrast: accessibilitySettings.prefersHighContrast
        ))
        .clipShape(shape)
        .overlay(shape.stroke(AuroraInstrument.stroke(
            for: colorScheme,
            highContrast: accessibilitySettings.prefersHighContrast
        ), lineWidth: 1))
        .rotationEffect(.degrees(isFeatured ? 3 : 2))
        .shadow(color: AuroraInstrument.stroke(for: colorScheme, highContrast: false).opacity(0.3), radius: 0, x: 2, y: 3)
    }
}

private struct SubtaskChecklistView: View {
    let store: Store
    let item: Countdown
    let presentation: CountdownRowPresentation

    @ObservedObject private var disclosureState: SubtaskDisclosureState
    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @Environment(\.colorScheme) private var colorScheme

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
                HStack {
                    Text("Подзадачи").foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                    Spacer()
                    Text(subtaskDisclosureLabel(isExpanded: isExpanded, completion: completionLabel))
                        .monospacedDigit()
                        .foregroundStyle(AuroraInstrument.accentInk(
                            for: colorScheme,
                            highContrast: accessibilitySettings.prefersHighContrast
                        ))
                }
                .font(.system(size: 11))
                .frame(minHeight: 22)
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
            HStack(spacing: 6) {
                Toggle("", isOn: Binding(
                    get: { subtask.isCompleted },
                    set: { _ in Task { await store.toggleSubtask(eventID: item.id, subtaskID: subtask.id) } }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
                .tint(subtask.isCompleted
                    ? AuroraInstrument.completedCheck(for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast)
                    : AuroraInstrument.accent(for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast))
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
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .strikethrough(subtask.isCompleted)
                    .foregroundStyle(subtask.isCompleted
                        ? AuroraInstrument.secondaryInk(for: colorScheme) : AuroraInstrument.ink(for: colorScheme))
                    .help(subtask.text)
                    .frame(maxWidth: .infinity, alignment: .leading)

            }
            .padding(.vertical, 7)
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
    private let isNewDay: Bool
    private let selectDayDate: Bool
    @State private var draft: EventEditorDraft
    @State private var date: Date
    @State private var primary: Bool
    @State private var isSaving = false
    @State private var confirmingDeletion = false
    @State private var emojiPicker: EditorEmojiPickerState = .closed
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
        done: @escaping () -> Void
    ) {
        self.store = store; self.item = item; self.done = done
        isNewDay = item == nil && dayPreset != nil
        self.selectDayDate = isNewDay && selectDayDate
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
            Text(item != nil ? EventUIStrings.editEvent : (isNewDay ? EventUIStrings.newDay : EventUIStrings.newEvent))
                .font(.custom("Georgia", size: 28))
                .tracking(-0.8)
                .padding(.bottom, 12)
            if selectDayDate {
                Text("Выберите дату для нового дня.")
                    .font(.caption).foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                    .padding(.bottom, 8)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        editorBlock {
                            VStack(alignment: .leading, spacing: 12) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Название").font(.caption).foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                                    TextField("Например, отпуск", text: Binding(
                                        get: { draft.title },
                                        set: { draft.setTitle($0) }
                                    ))
                                        .textFieldStyle(.roundedBorder)
                                        .focused($focusedField, equals: .title)
                                        .auroraInputChrome(isFocused: focusedField == .title)
                                        .accessibilityIdentifier("editor.title")
                                        .uiSmokeControl(
                                            id: "editor.title",
                                            action: { focus(.title, id: "editor.title") },
                                            value: { draft.title }
                                        )
                                }
                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text("Заметка · необязательно").font(.caption).foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                                        Spacer()
                                        Text("\(draft.note.count)/280").font(.caption2)
                                            .foregroundStyle(draft.note.count <= 280 ? Color.secondary : Color.red)
                                    }
                                    TextField("Пара слов о событии", text: $draft.note, axis: .vertical)
                                        .textFieldStyle(.roundedBorder)
                                        .lineLimit(2...3)
                                        .accessibilityIdentifier("editor.note")
                                        .focused($focusedField, equals: .note)
                                        .auroraInputChrome(isFocused: focusedField == .note)
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
                            }
                        }
                        editorBlock { emojiControls }
                        editorBlock { editorSubtasks(scrollProxy: proxy) }
                        VStack(alignment: .leading, spacing: 12) {
                            Rectangle()
                                .fill(AuroraInstrument.stroke(
                                    for: colorScheme,
                                    highContrast: accessibilitySettings.prefersHighContrast
                                ))
                                .frame(height: 1)
                                .accessibilityHidden(true)
                            Toggle("Основное — показывать в строке меню", isOn: $primary)
                                .accessibilityIdentifier("editor.primary")
                                .uiSmokeControl(
                                    id: "editor.primary",
                                    action: { primary.toggle() },
                                    value: { primary ? "Выбрано" : "Не выбрано" }
                                )
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
                        .font(.caption).foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
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
                    .tint(AuroraInstrument.accent(
                        for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast
                    ))
                    .foregroundStyle(colorScheme == .dark ? AuroraInstrument.canvas(for: colorScheme) : .white)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("editor.save")
                    .uiSmokeControl(id: "editor.save", action: save)
                    .disabled(!canSave || isSaving || confirmingDeletion)
                }
            }
            .padding(.top, EditorLayout.actionAreaSpacing)
        }
        .padding(19)
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
                Text("Подзадачи · необязательно").font(.caption).foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
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
                    Button("+ Добавить") { addSubtask(scrollProxy: scrollProxy) }
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

    private func editorBlock<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(AuroraInstrument.surface(
                for: colorScheme,
                elevated: false,
                highContrast: accessibilitySettings.prefersHighContrast
            ), in: RoundedRectangle(cornerRadius: AuroraInstrument.cardCornerRadius))
            .overlay {
                if accessibilitySettings.prefersHighContrast {
                    RoundedRectangle(cornerRadius: AuroraInstrument.cardCornerRadius)
                        .stroke(AuroraInstrument.stroke(for: colorScheme, highContrast: true), lineWidth: 1)
                        .allowsHitTesting(false)
                }
            }
    }

    private var emojiControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Значок · необязательно")
                .font(.caption)
                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
            emojiSelectionField
            emojiPickerContents
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
                    Text(draft.emoji.isEmpty ? "Без значка" : draft.emoji)
                        .font(.system(size: draft.emoji.isEmpty ? 13 : 26))
                        .foregroundStyle(draft.emoji.isEmpty
                            ? AuroraInstrument.secondaryInk(for: colorScheme) : AuroraInstrument.ink(for: colorScheme))
                        .frame(height: 28, alignment: .leading)
                        .id(draft.emoji)
                        .transition(.opacity)
                        .animation(accessibilitySettings.prefersReducedMotion ? nil
                            : .easeInOut(duration: editorEmojiValueTransitionDuration), value: draft.emoji)
                        .accessibilityHidden(true)
                        .uiSmokeControl(id: "editor.emoji", value: { draft.emoji })
                    Spacer(minLength: 0)
                }
                .padding(.leading, 10)
                .padding(.trailing, draft.emoji.isEmpty ? 34 : 70)
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
        .auroraInputChrome(isFocused: focusedField == .emoji)
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
                .focused($focusedField, equals: .subtask(subtask.id))
                .auroraInputChrome(isFocused: focusedField == .subtask(subtask.id))
                .accessibilityIdentifier("editor.subtask.\(subtask.id.uuidString)")
                .uiSmokeControl(
                    id: "editor.subtask.\(subtask.id.uuidString)",
                    action: {
                        guard isAvailable else { return }
                        focusField(.subtask(subtask.id), "editor.subtask.\(subtask.id.uuidString)")
                    },
                    value: { currentSubtask.text }
                )
            Text("\(currentSubtask.text.count)/\(Subtask.maximumTextLength)")
                .font(.caption2)
                .foregroundStyle(currentSubtask.text.count <= Subtask.maximumTextLength ? Color.secondary : Color.red)
                .frame(width: 34, alignment: .trailing)
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
