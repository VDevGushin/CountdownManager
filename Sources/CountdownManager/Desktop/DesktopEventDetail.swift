import CountdownCore
import SwiftUI

struct DesktopEventDetail: View {
    let item: Countdown
    let today: Day
    let primaryID: UUID?
    @ObservedObject var weather: WeatherController
    let canMutate: Bool
    let edit: () -> Void
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
                Text(item.title)
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
                Text(note).font(.system(size: 13)).lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
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
                VStack(alignment: .leading, spacing: 13) {
                    ForEach(presentation.activeSubtasks + presentation.completedSubtasks) { subtask in
                        Toggle(isOn: Binding(get: { subtask.isCompleted }, set: { _ in toggleSubtask(subtask.id) })) {
                            Text(subtask.text).font(.system(size: 13))
                                .strikethrough(subtask.isCompleted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .toggleStyle(.checkbox)
                        .accessibilityIdentifier("desktop.subtask.toggle.\(subtask.id.uuidString)")
                        .uiSmokeControl(id: "desktop.subtask.toggle.\(subtask.id.uuidString)",
                                        action: { toggleSubtask(subtask.id) },
                                        value: { subtask.isCompleted ? "on" : "off" })
                        .disabled(!canMutate)
                    }
                }
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

    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AuroraInstrument.ink(for: colorScheme))
    }
}
