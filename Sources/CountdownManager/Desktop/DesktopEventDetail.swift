import AppKit
import CountdownCore
import SwiftUI

private extension VerticalAlignment {
    enum ChecklistFirstLineCenter: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat { context[VerticalAlignment.center] }
    }

    static let checklistFirstLineCenter = VerticalAlignment(ChecklistFirstLineCenter.self)
}

struct DesktopEventDetail: View {
    @ObservedObject var store: Store
    @ObservedObject var editorSession: EventEditorSession
    let item: Countdown
    let today: Day
    let primaryID: UUID?
    @ObservedObject var weather: WeatherController
    let search: DesktopEventSearch
    let canMutate: Bool
    let canBeginTransfer: () -> Bool
    let edit: () -> Void
    let copy: () -> Void
    let toggleFavorite: () -> Void
    let delete: () -> Void
    let toggleSubtask: (UUID) -> Void
    let openLink: (EventLink) -> Void
    let openAttachment: (EventAttachment) -> Void
    let attachmentThumbnailURL: @MainActor (EventAttachment) async -> URL?
    let showAttachments: () -> Void
    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @Environment(\.colorScheme) private var colorScheme

    private var presentation: CountdownRowPresentation {
        CountdownRowPresentation(item: item, today: today, primaryID: primaryID)
    }

    private var searchColor: Color {
        AuroraInstrument.accent(for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast)
    }

    var body: some View {
        DesktopSavedDetail(
            owner: SavedMaterialOwner(item), note: presentation.note, search: search,
            heading: presentation.isPrimary ? AppText.string("desktop.detail.favoriteHeading")
                : AppText.string("desktop.detail.selectionHeading"),
            canMutate: canMutate, editorPresented: editorSession.desktopIsPresented,
            delete: delete, openLink: openLink, openAttachment: openAttachment,
            attachmentThumbnailURL: attachmentThumbnailURL, showAttachments: showAttachments,
            actions: eventActions, identity: { eventIdentity }, checklist: { checklist }
        )
    }

    @ViewBuilder
    private func eventActions(confirmingDeletion: Bool, requestDeletion: @escaping () -> Void) -> some View {
        AuroraSymbolAction(symbolName: presentation.isPrimary ? "star.fill" : "star",
            surface: .desktop, tone: presentation.isPrimary ? .accent : .ink,
            accessibilityLabel: presentation.isPrimary ? AppText.string("event.unfavorite") : AppText.string("event.favorite"),
            action: toggleFavorite)
        .help(presentation.isPrimary ? AppText.string("event.unfavorite") : AppText.string("event.favorite"))
        .accessibilityIdentifier("desktop.favorite.\(item.id.uuidString)")
        .uiSmokeControl(id: "desktop.favorite.\(item.id.uuidString)", action: toggleFavorite,
                        value: { presentation.isPrimary ? "on" : "off" })
        .fixedSize()
        .disabled(!canMutate)
        AuroraSymbolAction(symbolName: "pencil", surface: .desktop, tone: .ink,
            accessibilityLabel: AppText.string("event.edit"), action: edit)
            .fixedSize()
            .help(AppText.string("desktop.detail.editHelp"))
            .accessibilityIdentifier("desktop.detail.edit")
            .uiSmokeControl(id: "desktop.detail.edit", action: edit)
            .disabled(!canMutate)
        AuroraSymbolAction(symbolName: "doc.on.doc", surface: .desktop, tone: .ink,
            accessibilityLabel: AppText.string("desktop.detail.copy"), action: copy)
            .fixedSize()
            .help(AppText.string("event.copy"))
            .accessibilityIdentifier("desktop.detail.copy")
            .uiSmokeControl(id: "desktop.detail.copy", action: copy)
            .disabled(!canMutate)
        AuroraSymbolAction(symbolName: "trash", surface: .desktop, tone: .ink, role: .destructive,
            accessibilityLabel: AppText.string("desktop.detail.deleteNamed", item.displayTitle), action: requestDeletion)
            .fixedSize()
            .help(AppText.string("event.delete"))
            .accessibilityIdentifier("desktop.detail.delete")
            .uiSmokeControl(id: "desktop.detail.delete", action: requestDeletion)
            .disabled(!canMutate || confirmingDeletion)
    }

    private var eventIdentity: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Text(desktopSearchAttributedText(item.displayTitle, search: search, color: searchColor))
                    .font(.custom("Georgia", size: 27)).tracking(-0.5)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                DesktopCalendarLeaf(item: item, featured: false, role: "detail")
                    .fixedSize()
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                DesktopEventDateLabel(item: item, dateLabel: presentation.dateLabel, role: "detail")
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .layoutPriority(1)
                if item.showsWeather, let forecast = weather.forecast(for: item.date) {
                    DesktopForecastLabel(forecast: forecast)
                        .fixedSize()
                        .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                        .uiSmokeControl(id: "desktop.weather.detail.\(item.id)", value: { "available" })
                }
            }
            .frame(height: 18, alignment: .leading)
            .uiSmokeControl(id: "desktop.detail.metadata.\(item.id)")
            Text(presentation.remainingLabel)
                .font(.custom("Georgia", size: 23))
                .foregroundStyle(presentation.isToday
                    ? AuroraInstrument.todayColor(for: colorScheme,
                                                  highContrast: accessibilitySettings.prefersHighContrast)
                    : presentation.isPast ? AuroraInstrument.secondaryInk(for: colorScheme)
                    : AuroraInstrument.accent(for: colorScheme,
                                              highContrast: accessibilitySettings.prefersHighContrast))
        }
        .uiSmokeControl(id: "desktop.detail.identity")
    }

    private var checklist: some View {
        DesktopSavedChecklist(ownerID: .event(item.id), subtasks: item.subtasks, search: search,
                             canMutate: canMutate, canReorder: canBeginTransfer(),
                             toggleSubtask: toggleSubtask, saveSubtaskOrder: saveSubtaskOrder) { subtask in
            SubtaskTransferButton(store: store, editorSession: editorSession,
                                  eventID: item.id, subtask: subtask, surface: .desktop,
                                  canBegin: canBeginTransfer)
        } inline: { subtask in
            SubtaskTransferForm(store: store, editorSession: editorSession, eventID: item.id,
                                subtaskID: subtask.id, surface: .desktop)
        }
    }

    private func saveSubtaskOrder(_ move: SubtaskReorder, _ index: Int) async -> Bool {
        guard canBeginTransfer(), !editorSession.hasActiveEditor else { return false }
        return await store.reorderSubtask(owner: .event(item.id), move: move, to: index)
    }
}

struct DesktopRecordDetail: View {
    let record: UndatedRecord
    let search: DesktopEventSearch
    let canMutate: Bool
    let canReorder: Bool
    let editorPresented: Bool
    let edit: () -> Void
    let delete: () -> Void
    let toggleSubtask: (UUID) -> Void
    let saveSubtaskOrder: (SubtaskReorder, Int) async -> Bool
    let openLink: (EventLink) -> Void
    let openAttachment: (EventAttachment) -> Void
    let attachmentThumbnailURL: @MainActor (EventAttachment) async -> URL?
    let showAttachments: () -> Void
    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        DesktopSavedDetail(
            owner: SavedMaterialOwner(record), note: record.note, search: search, heading: AppText.string("record.title"),
            canMutate: canMutate, editorPresented: editorPresented, delete: delete, openLink: openLink,
            openAttachment: openAttachment, attachmentThumbnailURL: attachmentThumbnailURL,
            showAttachments: showAttachments, actions: recordActions, identity: { recordIdentity }
        ) {
            if !record.subtasks.isEmpty {
                DesktopSavedChecklist(ownerID: .record(record.id), subtasks: record.subtasks, search: search,
                                     canMutate: canMutate, canReorder: canReorder,
                                     toggleSubtask: toggleSubtask, saveSubtaskOrder: saveSubtaskOrder) { _ in
                    EmptyView()
                } inline: { _ in
                    EmptyView()
                }
            }
        }
    }

    @ViewBuilder
    private func recordActions(confirmingDeletion: Bool, requestDeletion: @escaping () -> Void) -> some View {
        let editLabel = AppText.string("desktop.record.edit")
        AuroraSymbolAction(symbolName: "pencil", surface: .desktop, tone: .ink,
                           accessibilityLabel: editLabel, action: edit)
            .fixedSize()
            .help(editLabel)
            .accessibilityIdentifier("desktop.record.detail.edit")
            .uiSmokeControl(id: "desktop.record.detail.edit", action: edit)
            .disabled(!canMutate)
        AuroraSymbolAction(symbolName: "trash", surface: .desktop, tone: .ink, role: .destructive,
                           accessibilityLabel: AppText.string("desktop.record.deleteNamed", record.title),
                           action: requestDeletion)
            .fixedSize()
            .help(AppText.string("record.delete"))
            .accessibilityIdentifier("desktop.record.detail.delete")
            .uiSmokeControl(id: "desktop.record.detail.delete", action: requestDeletion)
            .disabled(!canMutate || confirmingDeletion)
    }

    private var recordIdentity: some View {
        let color = AuroraInstrument.accent(for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast)
        return Text(desktopSearchAttributedText(record.title, search: search, color: color))
            .font(.custom("Georgia", size: 27)).tracking(-0.5)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct DesktopSavedDetail<Actions: View, Identity: View, Checklist: View>: View {
    let owner: SavedMaterialOwner
    let note: String?
    let search: DesktopEventSearch
    let heading: String
    let canMutate: Bool
    let editorPresented: Bool
    let delete: () -> Void
    let openLink: (EventLink) -> Void
    let openAttachment: (EventAttachment) -> Void
    let attachmentThumbnailURL: @MainActor (EventAttachment) async -> URL?
    let showAttachments: () -> Void
    @ViewBuilder let actions: (Bool, @escaping () -> Void) -> Actions
    @ViewBuilder let identity: () -> Identity
    @ViewBuilder let checklist: () -> Checklist
    @State private var confirmingDeletion = false
    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @Environment(\.colorScheme) private var colorScheme

    private var isEvent: Bool { owner.collection == .events }

    var body: some View {
        let detailID = isEvent ? "desktop.detail.\(owner.id)" : "desktop.record.detail.\(owner.id)"
        VStack(spacing: 0) {
            header
            Divider()
            if confirmingDeletion {
                deletionConfirmation
                Divider()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    identity()
                    description
                    checklist()
                    SavedAttachmentSection(owner: owner, compact: false,
                                           open: openAttachment, thumbnailURL: attachmentThumbnailURL,
                                           showAll: showAttachments)
                        .id(owner.id)
                    SavedLinkSection(owner: owner, surface: "desktop", open: openLink)
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AuroraInstrument.surface(for: colorScheme, elevated: false,
                                            highContrast: accessibilitySettings.prefersHighContrast))
        .accessibilityIdentifier(detailID)
        .uiSmokeControl(id: detailID)
        .uiSmokeControl(id: "desktop.inspector", value: { owner.id.uuidString })
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(heading)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            actions(confirmingDeletion, requestDeletion)
        }
        .font(.system(size: 16, weight: .regular))
        .padding(.horizontal, 24)
        .frame(height: 54)
        .uiSmokeControl(id: isEvent ? "desktop.detail.header" : "desktop.record.detail.header")
    }

    @ViewBuilder private var description: some View {
        if let note, !note.isEmpty {
            let color = AuroraInstrument.accent(for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast)
            VStack(alignment: .leading, spacing: 8) {
                Text(isEvent ? AppText.string("event.note") : AppText.string("record.note"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AuroraInstrument.ink(for: colorScheme))
                Text(desktopSearchAttributedText(note, search: search, color: color))
                    .font(.system(size: 13)).lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    // Discard the native selection across the editor sheet's focus handoff.
                    .id(editorPresented)
            }
            .uiSmokeControl(id: isEvent ? "desktop.detail.note" : "desktop.record.detail.note")
        }
    }

    private var deletionConfirmation: some View {
        let controlPrefix = isEvent ? "desktop.delete" : "desktop.record.delete"
        return VStack(alignment: .leading, spacing: 10) {
            Text(isEvent ? AppText.string("desktop.detail.confirmDelete", owner.displayTitle)
                : AppText.string("desktop.record.confirmDelete", owner.displayTitle))
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Text(isEvent ? AppText.string("desktop.detail.deleteWarning") : AppText.string("record.deleteWarning"))
                .font(.system(size: 12))
                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button(AppText.string("common.cancel")) { confirmingDeletion = false }
                    .accessibilityIdentifier("\(controlPrefix).cancel")
                    .uiSmokeControl(id: "\(controlPrefix).cancel", action: { confirmingDeletion = false })
                Button(AppText.string("common.delete"), role: .destructive, action: confirmDeletion)
                    .accessibilityIdentifier("\(controlPrefix).confirm")
                    .uiSmokeControl(id: "\(controlPrefix).confirm", action: confirmDeletion)
                    .disabled(!canMutate)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("\(controlPrefix).confirmation")
        .uiSmokeControl(id: "\(controlPrefix).confirmation", value: { owner.displayTitle })
    }

    private func requestDeletion() {
        guard canMutate, !confirmingDeletion else { return }
        confirmingDeletion = true
    }

    private func confirmDeletion() {
        guard canMutate, confirmingDeletion else { return }
        confirmingDeletion = false
        delete()
    }
}

private struct DesktopSavedChecklist<Trailing: View, Inline: View>: View {
    let ownerID: SavedMaterialOwnerID
    let subtasks: [Subtask]
    let search: DesktopEventSearch
    let canMutate: Bool
    let canReorder: Bool
    let toggleSubtask: (UUID) -> Void
    let saveSubtaskOrder: (SubtaskReorder, Int) async -> Bool
    @ViewBuilder let trailing: (Subtask) -> Trailing
    @ViewBuilder let inline: (Subtask) -> Inline
    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @Environment(\.colorScheme) private var colorScheme

    private var controlPrefix: String { ownerID.collection == .events ? "desktop" : "desktop.record" }
    private var searchColor: Color {
        AuroraInstrument.accent(for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast)
    }

    var body: some View {
        let completed = subtasks.filter(\.isCompleted).count
        let progress = subtasks.isEmpty ? "empty" : "\(completed)/\(subtasks.count)"
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(AppText.string("subtask.heading"))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AuroraInstrument.ink(for: colorScheme))
                    .uiSmokeControl(id: "\(controlPrefix).subtasks.heading.\(ownerID.id)")
                Spacer()
                DesktopCompletionLabel(tasks: subtasks)
                    .labelStyle(DesktopSummaryLabelStyle(controlID: "\(controlPrefix).summary.details.tasks.\(ownerID.id)"))
                    .uiSmokeControl(id: "\(controlPrefix).checklist.progress", value: { progress })
            }
            if subtasks.isEmpty {
                Text(AppText.string("desktop.detail.noSubtasks"))
                    .font(.system(size: 13))
                    .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
            } else {
                SubtaskReorderRows(subtasks: subtasks, spacing: 13, isEnabled: canReorder,
                                   save: saveSubtaskOrder, row: subtaskRow)
                    .animation(accessibilitySettings.prefersReducedMotion ? nil : .easeInOut(duration: 0.15),
                               value: subtasks.map(\.isCompleted))
                    .transaction { transaction in
                        if accessibilitySettings.prefersReducedMotion {
                            transaction.animation = nil
                            transaction.disablesAnimations = true
                        }
                    }
            }
            if completed > 0 && completed == subtasks.count {
                Label(AppText.string("subtask.finished"), systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AuroraInstrument.todayColor(for: colorScheme,
                                                                highContrast: accessibilitySettings.prefersHighContrast))
                    .accessibilityIdentifier("\(controlPrefix).checklist.complete")
                    .uiSmokeControl(id: "\(controlPrefix).checklist.complete")
            }
        }
        .uiSmokeControl(id: "\(controlPrefix).detail.checklist")
    }

    private func subtaskRow(_ subtask: Subtask, _ interaction: SubtaskReorderInteraction?) -> some View {
        let control = "\(controlPrefix).subtask.toggle.\(subtask.id)"
        let fontSize: CGFloat = 13
        let rowFont = NSFont.systemFont(ofSize: fontSize)
        let firstLineCenter = ceil(rowFont.ascender - rowFont.descender + rowFont.leading) / 2
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .checklistFirstLineCenter, spacing: 0) {
                Toggle(isOn: Binding(get: { subtask.isCompleted }, set: { _ in toggleSubtask(subtask.id) })) {
                    Text(desktopSearchAttributedText(subtask.text, search: search, color: searchColor))
                        .font(.system(size: fontSize))
                        .strikethrough(subtask.isCompleted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .uiSmokeControl(id: "\(controlPrefix).subtask.text.\(subtask.id)")
                }
                .toggleStyle(.checkbox)
                .alignmentGuide(.checklistFirstLineCenter) { _ in firstLineCenter }
                .modifier(interaction ?? .disabled)
                .accessibilityIdentifier(control)
                .uiSmokeControl(id: control, action: { toggleSubtask(subtask.id) },
                                value: { subtask.isCompleted ? "on" : "off" })
                .disabled(!canMutate)
                trailing(subtask)
            }
            inline(subtask)
        }
    }
}
