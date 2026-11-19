import CountdownCore
import SwiftUI

/// A sibling of the completion toggle, using the existing neutral symbol-action family.
struct SubtaskTransferButton: View {
    @ObservedObject var store: Store
    @ObservedObject var editorSession: EventEditorSession
    let eventID: UUID
    let subtask: Subtask
    let surface: EventEditorSession.Surface
    var canBegin: () -> Bool = { true }

    private var ownsTransfer: Bool {
        editorSession.subtaskTransfer?.surface == surface
    }

    private var isExpanded: Bool {
        guard let draft = editorSession.subtaskTransfer else { return false }
        return draft.surface == surface && draft.eventID == eventID && draft.subtaskID == subtask.id
    }

    var body: some View {
        if subtask.isCompleted {
            // Keep the symbol action's footprint when the row changes completion group.
            Color.clear
                .frame(width: 28, height: 28)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else {
            transferButton
        }
    }

    private var transferButton: some View {
        AuroraSymbolAction(symbolName: "arrowshape.turn.up.right",
            surface: surface == .panel ? .mini : .desktop, tone: .secondary,
            accessibilityLabel: "Перенести подзадачу: \(subtask.text)", action: open)
            .font(.system(size: 12))
            .help("Перенести на другой день")
            .accessibilityValue(isExpanded ? "Выбор даты открыт" : "Выбор даты закрыт")
            .accessibilityIdentifier("subtask.transfer.open.\(subtask.id.uuidString)")
            .uiSmokeControl(id: "subtask.transfer.open.\(subtask.id.uuidString)", action: open,
                            value: { isExpanded ? "expanded" : "collapsed" })
            .disabled(editorSession.subtaskTransferIsSaving || store.hasPendingPersistence || !store.eventCreationIsAvailable
                      || (editorSession.hasActiveEditor && !ownsTransfer) || (!ownsTransfer && !canBegin()))
    }

    private func open() {
        guard !editorSession.subtaskTransferIsSaving, !store.hasPendingPersistence, store.eventCreationIsAvailable,
              !editorSession.hasActiveEditor || ownsTransfer, ownsTransfer || canBegin() else { return }
        if let draft = editorSession.subtaskTransfer {
            editorSession.endSubtaskTransfer()
            if draft.eventID == eventID && draft.subtaskID == subtask.id { return }
        }
        _ = editorSession.beginSubtaskTransfer(eventID: eventID, subtaskID: subtask.id,
                                               surface: surface, date: Day(store.tomorrow))
    }
}

/// Both native surfaces keep the same small inline form beneath the chosen task.
struct SubtaskTransferForm: View {
    @ObservedObject var store: Store
    @ObservedObject var editorSession: EventEditorSession
    let eventID: UUID
    let subtaskID: UUID
    let surface: EventEditorSession.Surface
    @FocusState private var dateIsFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    private var draft: SubtaskTransferDraft? {
        guard let draft = editorSession.subtaskTransfer,
              draft.eventID == eventID, draft.subtaskID == subtaskID, draft.surface == surface else { return nil }
        return draft
    }

    var body: some View {
        if let draft {
            form(draft)
                .id(subtaskID)
                .font(.system(size: 12))
                .padding(.leading, 20)
                .padding(.bottom, 8)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("subtask.transfer.form")
                .uiSmokeControl(id: "subtask.transfer.form")
        }
    }

    private func targets(for draft: SubtaskTransferDraft) -> [Countdown] {
        store.active.filter { $0.date == draft.date && $0.id != draft.eventID }
    }

    private func selectedTarget(in targets: [Countdown], draft: SubtaskTransferDraft) -> UUID? {
        draft.targetEventID ?? (targets.count == 1 ? targets.first?.id : nil)
    }

    private func notice(for draft: SubtaskTransferDraft, targets: [Countdown], targetID: UUID?) -> String? {
        if draft.date < store.today { return "Выберите сегодня или будущую дату." }
        if targets.isEmpty, store.active.contains(where: { $0.date == draft.date }) {
            return "На этой дате есть только исходное событие. Выберите другую дату."
        }
        if let targetID, let target = targets.first(where: { $0.id == targetID }) {
            if target.subtasks.count >= Subtask.maximumCount {
                return "В событии уже 10 подзадач. Выберите другое событие или дату."
            }
        } else if targetID != nil {
            return "Выбранное событие недоступно. Выберите получателя заново."
        }
        return nil
    }

    private func form(_ draft: SubtaskTransferDraft) -> some View {
        let targets = targets(for: draft)
        let targetID = selectedTarget(in: targets, draft: draft)
        let notice = notice(for: draft, targets: targets, targetID: targetID)
        let canSave = notice == nil && (targets.isEmpty || targetID != nil)
        return VStack(alignment: .leading, spacing: 8) {
            DatePicker("На дату", selection: Binding(
                get: { draft.date.date() },
                set: { editorSession.updateSubtaskTransfer(date: Day($0)) }
            ), in: store.today.date()..., displayedComponents: [.date])
                .datePickerStyle(.field)
                .controlSize(.regular)
                .frame(minHeight: 28)
                .focused($dateIsFocused)
                .accessibilityIdentifier("subtask.transfer.date")
                .uiSmokeControl(id: "subtask.transfer.date", value: { humanDateLabel(draft.date) })
            Picker("В событие", selection: Binding<UUID?>(
                get: { targetID },
                set: { editorSession.selectSubtaskTransferTarget($0) }
            )) {
                if targets.isEmpty {
                    Text("Создать день").tag(nil as UUID?)
                } else {
                    Text("Выберите событие").tag(nil as UUID?)
                    ForEach(targets) { target in
                        Text(target.title).tag(Optional(target.id))
                    }
                }
            }
            .accessibilityIdentifier("subtask.transfer.target")
            .uiSmokeControl(id: "subtask.transfer.target", value: { targetID?.uuidString ?? "none" })
            if targets.isEmpty, notice == nil {
                Text("Будет создан день на выбранную дату.")
                    .font(.system(size: 11))
                    .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
            }
            if let notice {
                Text(notice).font(.system(size: 11)).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("subtask.transfer.notice")
                    .uiSmokeControl(id: "subtask.transfer.notice", value: { notice })
            }
            HStack(spacing: 8) {
                if editorSession.subtaskTransferIsSaving { ProgressView().controlSize(.small) }
                Spacer(minLength: 0)
                Button("Отмена", action: editorSession.endSubtaskTransfer)
                    .auroraSecondaryAction()
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier("subtask.transfer.cancel")
                    .uiSmokeControl(id: "subtask.transfer.cancel", action: editorSession.endSubtaskTransfer)
                Button("Перенести") { transfer(draft, targetID: targetID) }
                    .auroraPrimaryAction()
                    .accessibilityIdentifier("subtask.transfer.confirm")
                    .uiSmokeControl(id: "subtask.transfer.confirm", action: {
                        if canSave { transfer(draft, targetID: targetID) }
                    })
                    .disabled(!canSave)
            }
        }
        .controlSize(.small)
        .disabled(editorSession.subtaskTransferIsSaving || store.hasPendingPersistence || !store.eventCreationIsAvailable)
    }

    private func transfer(_ draft: SubtaskTransferDraft, targetID: UUID?) {
        guard !store.hasPendingPersistence, store.eventCreationIsAvailable,
              editorSession.beginSubtaskTransferSave(draft) else { return }
        Task {
            let saved = await store.transferSubtask(eventID: draft.eventID, subtaskID: draft.subtaskID,
                                                    to: targetID, on: draft.date)
            editorSession.finishSubtaskTransferSave(draft, succeeded: saved != nil)
            editorSession.reconcileSubtaskTransfer(items: store.data.items, today: store.today)
        }
    }
}
