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
                VStack(alignment: .leading, spacing: 26) {
                    eventIdentity
                    note
                    checklist
                }
                .padding(26)
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
            Button(action: toggleFavorite) {
                Image(systemName: presentation.isPrimary ? "star.fill" : "star")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .foregroundStyle(AuroraInstrument.accent(for: colorScheme,
                                                     highContrast: accessibilitySettings.prefersHighContrast))
            .accessibilityLabel(presentation.isPrimary ? "Убрать из избранного" : "Сделать избранным")
            .help(presentation.isPrimary ? "Убрать из избранного" : "Сделать избранным")
            .accessibilityIdentifier("desktop.favorite.\(item.id.uuidString)")
            .uiSmokeControl(id: "desktop.favorite.\(item.id.uuidString)", action: toggleFavorite,
                            value: { presentation.isPrimary ? "on" : "off" })
            .fixedSize()
            .disabled(!canMutate)
            Button(action: edit) {
                Image(systemName: "pencil")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
                .fixedSize()
                .help("Изменить событие")
                .accessibilityLabel("Редактировать событие")
                .accessibilityIdentifier("desktop.detail.edit")
                .uiSmokeControl(id: "desktop.detail.edit", action: edit)
                .disabled(!canMutate)
            Button(role: .destructive, action: requestDeletion) {
                Image(systemName: "trash")
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
                .fixedSize()
                .help("Удалить событие")
                .accessibilityLabel("Удалить событие: \(item.title)")
                .accessibilityIdentifier("desktop.detail.delete")
                .uiSmokeControl(id: "desktop.detail.delete", action: requestDeletion)
                .disabled(!canMutate || confirmingDeletion)
        }
        .buttonStyle(.borderless)
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
            Text("Событие и все подзадачи будут удалены. Восстановить их нельзя.")
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
        VStack(alignment: .leading, spacing: 22) {
            Text(item.title)
                .font(.custom("Georgia", size: 29)).tracking(-0.5)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            HStack(alignment: .center, spacing: 20) {
                DesktopCalendarLeaf(item: item, featured: true, role: "detail")
                VStack(alignment: .leading, spacing: 8) {
                    DesktopEventDateLabel(item: item, dateLabel: presentation.dateLabel, role: "detail")
                        .font(.system(size: 13))
                    Text(presentation.remainingLabel)
                        .font(.custom("Georgia", size: 23))
                        .foregroundStyle(presentation.isToday
                            ? AuroraInstrument.todayColor(for: colorScheme,
                                                          highContrast: accessibilitySettings.prefersHighContrast)
                            : AuroraInstrument.accent(for: colorScheme,
                                                      highContrast: accessibilitySettings.prefersHighContrast))
                    if item.showsWeather, let forecast = weather.forecast(for: item.date) {
                        DesktopForecastLabel(forecast: forecast)
                            .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                    }
                }
            }
        }
    }

    private var note: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("Заметка")
            if let note = presentation.note, !note.isEmpty {
                Text(note).font(.system(size: 13)).lineSpacing(5)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            } else {
                Text("Можно добавить пару слов о событии.")
                    .font(.system(size: 13))
                    .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
                Button("Добавить заметку", action: edit).disabled(!canMutate)
            }
        }
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                sectionLabel("Подготовиться")
                Spacer()
                DesktopCompletionLabel(presentation: presentation)
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
            }
            Button(item.subtasks.isEmpty ? "Добавить подзадачи…" : "Изменить список…", action: edit)
                .accessibilityIdentifier("desktop.checklist.edit")
                .uiSmokeControl(id: "desktop.checklist.edit", action: edit)
                .disabled(!canMutate)
            if presentation.allSubtasksCompleted {
                Label("Всё готово", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AuroraInstrument.todayColor(for: colorScheme,
                                                                highContrast: accessibilitySettings.prefersHighContrast))
                    .accessibilityIdentifier("desktop.checklist.complete")
                    .uiSmokeControl(id: "desktop.checklist.complete")
            }
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title).font(.system(size: 12, weight: .semibold))
            .foregroundStyle(AuroraInstrument.secondaryInk(for: colorScheme))
    }
}
