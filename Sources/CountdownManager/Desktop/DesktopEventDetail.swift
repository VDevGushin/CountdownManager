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
    @State private var confirmingDeletion = false
    @EnvironmentObject private var accessibilitySettings: AuroraAccessibilitySettings
    @Environment(\.colorScheme) private var colorScheme

    private var presentation: CountdownRowPresentation {
        CountdownRowPresentation(item: item, today: today, primaryID: primaryID)
    }

    private var searchColor: Color {
        AuroraInstrument.accent(for: colorScheme, highContrast: accessibilitySettings.prefersHighContrast)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if confirmingDeletion {
                deletionConfirmation
                Divider()
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    eventIdentity
                    note
                    checklist
                    SavedAttachmentSection(item: item, compact: false,
                                           open: openAttachment, thumbnailURL: attachmentThumbnailURL,
                                           showAll: showAttachments)
                        .id(item.id)
                    SavedLinkSection(item: item, surface: "desktop", open: { openLink($0) })
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AuroraInstrument.surface(for: colorScheme, elevated: false,
                                            highContrast: accessibilitySettings.prefersHighContrast))
        .accessibilityIdentifier("desktop.detail.\(item.id.uuidString)")
        .uiSmokeControl(id: "desktop.detail.\(item.id.uuidString)")
        .uiSmokeControl(id: "desktop.inspector", value: { item.id.uuidString })
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(presentation.isPrimary ? "Избранное событие" : "Выбранное событие")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            AuroraSymbolAction(symbolName: presentation.isPrimary ? "star.fill" : "star",
                surface: .desktop, tone: presentation.isPrimary ? .accent : .ink,
                accessibilityLabel: presentation.isPrimary ? "Убрать из избранного" : "Сделать избранным",
                action: toggleFavorite)
            .help(presentation.isPrimary ? "Убрать из избранного" : "Сделать избранным")
            .accessibilityIdentifier("desktop.favorite.\(item.id.uuidString)")
            .uiSmokeControl(id: "desktop.favorite.\(item.id.uuidString)", action: toggleFavorite,
                            value: { presentation.isPrimary ? "on" : "off" })
            .fixedSize()
            .disabled(!canMutate)
            AuroraSymbolAction(symbolName: "pencil", surface: .desktop, tone: .ink,
                accessibilityLabel: "Редактировать событие", action: edit)
                .fixedSize()
                .help("Изменить событие")
                .accessibilityIdentifier("desktop.detail.edit")
                .uiSmokeControl(id: "desktop.detail.edit", action: edit)
                .disabled(!canMutate)
            AuroraSymbolAction(symbolName: "doc.on.doc", surface: .desktop, tone: .ink,
                accessibilityLabel: "Создать копию события", action: copy)
                .fixedSize()
                .help("Создать копию…")
                .accessibilityIdentifier("desktop.detail.copy")
                .uiSmokeControl(id: "desktop.detail.copy", action: copy)
                .disabled(!canMutate)
            AuroraSymbolAction(symbolName: "trash", surface: .desktop, tone: .ink, role: .destructive,
                accessibilityLabel: "Удалить событие: \(item.title)", action: requestDeletion)
                .fixedSize()
                .help("Удалить событие")
                .accessibilityIdentifier("desktop.detail.delete")
                .uiSmokeControl(id: "desktop.detail.delete", action: requestDeletion)
                .disabled(!canMutate || confirmingDeletion)
        }
        .font(.system(size: 16, weight: .regular))
        .padding(.horizontal, 24)
        .frame(height: 54)
        .uiSmokeControl(id: "desktop.detail.header")
    }

    private var deletionConfirmation: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Удалить «\(item.title)»?")
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Text("Событие, все подзадачи и прикреплённые копии файлов будут удалены. Восстановить их нельзя. Исходные файлы сохранятся.")
                .font(.system(size: 12))
                .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                Button("Отмена") { confirmingDeletion = false }
                    .accessibilityIdentifier("desktop.delete.cancel")
                    .uiSmokeControl(id: "desktop.delete.cancel", action: { confirmingDeletion = false })
                Button("Удалить", role: .destructive, action: confirmDeletion)
                    .accessibilityIdentifier("desktop.delete.confirm")
                    .uiSmokeControl(id: "desktop.delete.confirm", action: confirmDeletion)
                    .disabled(!canMutate)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("desktop.delete.confirmation")
        .uiSmokeControl(id: "desktop.delete.confirmation", value: { item.title })
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

    private var eventIdentity: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Text(desktopSearchAttributedText(item.title, search: search, color: searchColor))
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

    @ViewBuilder
    private var note: some View {
        if let note = presentation.note, !note.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("Заметка")
                Text(desktopSearchAttributedText(note, search: search, color: searchColor))
                    .font(.system(size: 13)).lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    // Discard the native selection across the editor sheet's focus handoff.
                    .id(editorSession.desktopIsPresented)
            }
            .uiSmokeControl(id: "desktop.detail.note")
        }
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionLabel("Подзадачи")
                    .uiSmokeControl(id: "desktop.subtasks.heading.\(item.id.uuidString)")
                Spacer()
                DesktopCompletionLabel(presentation: presentation)
                    .labelStyle(DesktopSummaryLabelStyle(controlID: "desktop.summary.details.tasks.\(item.id)"))
                    .uiSmokeControl(id: "desktop.checklist.progress", value: {
                        presentation.completionLabel ?? "empty"
                    })
            }
            if item.subtasks.isEmpty {
                Text("У этого события пока нет подзадач.")
                    .font(.system(size: 13))
                    .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
            } else {
                SubtaskReorderRows(subtasks: item.subtasks, spacing: 13, isEnabled: canBeginTransfer(),
                                   save: saveSubtaskOrder, row: subtaskRow)
                .animation(accessibilitySettings.prefersReducedMotion ? nil : .easeInOut(duration: 0.15),
                           value: item.subtasks.map(\.isCompleted))
                .transaction { transaction in
                    if accessibilitySettings.prefersReducedMotion {
                        transaction.animation = nil
                        transaction.disablesAnimations = true
                    }
                }
            }
            if presentation.allSubtasksCompleted {
                Label("Всё готово", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AuroraInstrument.todayColor(for: colorScheme,
                                                                highContrast: accessibilitySettings.prefersHighContrast))
                    .accessibilityIdentifier("desktop.checklist.complete")
                    .uiSmokeControl(id: "desktop.checklist.complete")
            }
        }
        .uiSmokeControl(id: "desktop.detail.checklist")
    }

    private func subtaskRow(_ subtask: Subtask, _ interaction: SubtaskReorderInteraction?) -> some View {
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
                        .uiSmokeControl(id: "desktop.subtask.text.\(subtask.id)")
                }
                .toggleStyle(.checkbox)
                .alignmentGuide(.checklistFirstLineCenter) { _ in firstLineCenter }
                .modifier(interaction ?? .disabled)
                .accessibilityIdentifier("desktop.subtask.toggle.\(subtask.id.uuidString)")
                .uiSmokeControl(id: "desktop.subtask.toggle.\(subtask.id.uuidString)",
                                action: { toggleSubtask(subtask.id) },
                                value: { subtask.isCompleted ? "on" : "off" })
                .disabled(!canMutate)
                SubtaskTransferButton(store: store, editorSession: editorSession,
                                      eventID: item.id, subtask: subtask, surface: .desktop,
                                      canBegin: canBeginTransfer)
            }
            SubtaskTransferForm(store: store, editorSession: editorSession, eventID: item.id,
                                subtaskID: subtask.id, surface: .desktop)
        }
    }

    private func saveSubtaskOrder(_ move: SubtaskReorder, _ index: Int) async -> Bool {
        guard canBeginTransfer(), !editorSession.hasActiveEditor else { return false }
        return await store.reorderSubtask(eventID: item.id, move: move, to: index)
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AuroraInstrument.ink(for: colorScheme))
    }
}
